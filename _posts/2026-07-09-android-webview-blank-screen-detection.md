---
layout: post
title: "Android WebView 白屏检测：基于 View 层网格采样的可靠方案"
date: 2026-07-09
categories: android webview
tags: android webview blank-screen detection
---

WebView 白屏是移动端最难排查的故障之一。页面加载后用户看到的是一片空白，但 WebView 内部可能已经「完成加载」——`onPageFinished` 正常回调、`progress` 达到 100，日志层面一切正常。

本文介绍一种**不依赖 WebView 内部状态**的白屏检测方案，核心思路是从 Android 视图系统侧对 WebView 做像素级采样判定。

## 白屏检测为什么难

常见的检测思路及其局限：

| 方案 | 原理 | 失效场景 |
|------|------|----------|
| 监听 `onPageFinished` | 页面加载完成时检查内容 | 渲染进程崩溃后回调不触发；JS 卡死时页面「加载完成」但内容为空 |
| `evaluateJavascript` 检查 DOM | 注入 JS 判断 DOM 节点数 | 渲染进程崩溃后 JS 通道不可用 |
| JSBridge 心跳 | 前端定时向 Native 报活 | 依赖前端配合；内核异常时 Bridge 同样失效 |

这些方案的共同问题：**都依赖 WebView 内部状态**。当 WebView 渲染进程崩溃、JS 卡死、内核异常时，所有基于 WebView 内部通道的检测手段都可能失效。

## 核心思路：走 View 层，不走 WebView 内部

Android 的 `View.draw(Canvas)` 由视图系统控制，不依赖 WebView 渲染进程。即使渲染进程已经崩溃，`View.draw()` 仍然能执行——画出的就是当前显示的内容（崩溃时通常是纯背景色）。

利用这一点，可以在 View 层对 WebView 的显示内容做像素采样，判断是否为白屏。

## 触发时机

检测需要明确的触发条件，避免无意义的频繁采样。采用两路信号，任一触发即执行白屏判定：

### 1. 加载超时采样

从 `loadUrl()` 开始计时，**8 秒后无条件采样一次**。

关键设计决策：

- **不用 `onPageFinished` 做提前取消**。理由同上——渲染进程崩溃时该回调不可靠。8 秒定时器只和宿主生命周期绑定，宿主销毁时取消。
- 8 秒是初始经验值。可以通过同时记录「超时但非白屏」的情况来评估阈值是否合理——如果该情况大量出现，说明 8 秒偏短。

### 2. 渲染进程崩溃回调

- 系统 WebView：`WebViewClient.onRenderProcessGone()` 触发时直接判定为白屏。
- 部分第三方内核（如 X5）提供类似的白屏回调，触发时同样直接判定。
- 崩溃路径不需要走像素采样，直接进入上报流程。

## 采样算法：10×10 网格判定

### 流程

```
1. 获取 WebView 对应的 View
2. 调用 view.draw(canvas) 将当前显示内容绘制到 Bitmap
3. 在 Bitmap 上按 10×10 网格取 100 个采样点
4. 统计命中「背景色」的点数
5. 命中率 ≥ 95% → 判定为白屏
```

### 采样细节

**Bitmap 绘制**：

```kotlin
val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.RGB_565)
val canvas = Canvas(bitmap)
view.draw(canvas)
```

- 使用 `RGB_565` 而非 `ARGB_8888`，内存减半（一个像素 2 字节 vs 4 字节）
- 尺寸为 View 的可见宽高，不涉及整页快照，避免大 Bitmap 开销

**网格采样**：

```kotlin
object BlankScreenSampler {

    fun sample(
        view: View,
        expectedBgColor: Int,
        gridSize: Int = 10,
        colorTolerance: Int = 10,
        matchThreshold: Int = 95,
    ): Boolean {
        val bitmap = Bitmap.createBitmap(
            view.width, view.height, Bitmap.Config.RGB_565
        )
        val canvas = Canvas(bitmap)
        view.draw(canvas)

        val cellWidth = bitmap.width / gridSize
        val cellHeight = bitmap.height / gridSize
        var matchCount = 0

        for (row in 0 until gridSize) {
            for (col in 0 until gridSize) {
                val x = col * cellWidth + cellWidth / 2
                val y = row * cellHeight + cellHeight / 2
                val pixel = bitmap.getPixel(x, y)
                if (isColorMatch(pixel, expectedBgColor, colorTolerance)) {
                    matchCount++
                }
            }
        }

        bitmap.recycle()
        return matchCount >= matchThreshold
    }

    private fun isColorMatch(pixel: Int, target: Int, tolerance: Int): Boolean {
        return abs(Color.red(pixel) - Color.red(target)) <= tolerance
            && abs(Color.green(pixel) - Color.green(target)) <= tolerance
            && abs(Color.blue(pixel) - Color.blue(target)) <= tolerance
    }
}
```

**背景色判定**：

- 日间模式和夜间模式使用各自的背景色值
- 每通道允许 ±10 容差，消除抗锯齿边缘等噪声影响
- 100 个采样点中 ≥ 95 个命中背景色，即判定为白屏

### 性能开销

| 操作 | 耗时量级 | 内存开销 |
|------|----------|----------|
| `View.draw(Canvas)` | 毫秒级 | RGB_565 Bitmap，几百 KB ~ 1 MB |
| 100 次 `getPixel` | 微秒级 | 可忽略 |
| 采样后 `recycle()` | 即时释放 | — |

不会引入可感知的卡顿。

## 检测器设计

将检测逻辑封装为一个独立组件，宿主页面通过组合方式接入：

```kotlin
class BlankScreenDetector(
    private val hostTag: String,
    private val webViewProvider: () -> View?,
    private val urlProvider: () -> String,
    private val isNightMode: () -> Boolean,
    private val dayBgColor: Int,
    private val nightBgColor: Int,
    private val timeoutMs: Long = 8_000L,
) {
    /** loadUrl 时调用，重置计时器 */
    fun onLoadStart(url: String)

    /** 系统 WebView 渲染进程崩溃回调 */
    fun onRenderProcessGone()

    /** 第三方内核白屏回调 */
    fun onDetectedBlankScreen()

    /** 宿主销毁时调用，取消计时器、清除引用 */
    fun release()
}
```

### 内部行为

- **`onLoadStart`**：取消之前的计时器，记录起始时间戳，post 一个延迟 Runnable（8 秒）到主线程。
- **Delayed Runnable 执行时**：`webViewProvider()` 拿不到 View 或 View 已 detached → 跳过；否则调用采样器判定。命中白屏上报 `TIMEOUT`，未命中上报 `TIMEOUT_NOT_BLANK`（用于评估阈值合理性）。
- **`onRenderProcessGone` / `onDetectedBlankScreen`**：直接以对应原因上报，同时取消未执行的计时器。
- **`release`**：`removeCallbacks`，回调置空，防止内存泄漏。

### 上报格式

命中白屏时输出一条结构化日志，格式示例：

```
[BlankScreen] host=WebViewFragment url=https://... reason=TIMEOUT night=false elapsedMs=8012
```

| 字段 | 说明 |
|------|------|
| `host` | 宿主类型标识 |
| `url` | 当前加载的 URL |
| `reason` | 触发原因：`TIMEOUT` / `TIMEOUT_NOT_BLANK` / `RENDER_CRASH` / `BLANK_SCREEN_CB` |
| `night` | 是否夜间模式 |
| `elapsedMs` | 从 `loadUrl` 到检测触发的耗时 |

本阶段仅做日志上报，不展示错误页，不做自动重试。先通过日志收集数据，观察白屏发生的频率和分布，再决定后续的恢复策略。

## 生命周期处理

几个容易踩坑的点：

1. **宿主销毁时必须 `release()`**。否则 Delayed Runnable 持有 View 引用导致内存泄漏。
2. **后台切换不主动取消**。`onPause` / `onStop` 时计时器继续走，但采样前通过 `View.isAttachedToWindow` 和 `View.width > 0` 前置检查，不可见时跳过上报。
3. **计时器 post 到 MainLooper**。避免跨线程访问 View。

## 宿主接入示例

以 Fragment 为例：

```kotlin
class WebViewFragment : Fragment() {

    private lateinit var detector: BlankScreenDetector

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        detector = BlankScreenDetector(
            hostTag = "WebViewFragment",
            webViewProvider = { binding.webView },
            urlProvider = { binding.webView.url.orEmpty() },
            isNightMode = { NightModeHelper.isNight() },
            dayBgColor = ContextCompat.getColor(requireContext(), R.color.bg_day),
            nightBgColor = ContextCompat.getColor(requireContext(), R.color.bg_night),
        )
    }

    fun loadUrl(url: String) {
        binding.webView.loadUrl(url)
        detector.onLoadStart(url)
    }

    override fun onDestroyView() {
        detector.release()
        super.onDestroyView()
    }
}
```

Activity 的接入方式类似，生命周期挂载点换为 `onCreate` / `onDestroy`。

## 单元测试

`BlankScreenSampler` 是纯函数，可以构造 Bitmap 覆盖各种边界条件：

| 用例 | 预期 |
|------|------|
| 全部填充背景色 | 判定白屏 |
| 背景色占比 95% | 判定白屏（阈值边界） |
| 背景色占比 94% | 不判定白屏 |
| 每通道差异 ±10 以内 | 判定白屏（容差边界） |
| 每通道差异 ±11 | 不判定白屏 |
| 夜间背景色 + 夜间参数 | 判定白屏 |

`BlankScreenDetector` 的测试重点：

- 8 秒后触发采样并上报
- 渲染崩溃回调触发时上报对应原因并取消计时器
- `release()` 后即使定时到期也不会回调

## 方案边界

明确不做的事情：

- **不做内容级检测**（识别文字/图片区域）——超出白屏范畴，且开销大
- **不上报截图**——日志只走结构化字段
- **不做自动重试/错误页**——本次范围仅上报，积累数据后再决定恢复策略
- **不做全量覆盖**——先覆盖核心 WebView 页面，检测器独立于宿主，后续扩展只需在新页面接入即可

## 小结

WebView 白屏检测的核心难点在于：白屏发生时 WebView 内部通道往往已经不可用。本方案绕开这个限制，从 Android 视图系统侧切入——`View.draw()` 不受渲染进程状态影响，配合网格采样做像素级判定，在可控的性能开销下实现了可靠的白屏检测。

先上报、后治理，用数据驱动后续的恢复策略设计。
