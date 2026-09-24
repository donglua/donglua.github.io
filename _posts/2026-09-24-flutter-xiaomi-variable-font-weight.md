---
layout: post
title: "Flutter 升级后小米字体变粗：追到 MiSans 的 wght 轴"
date: 2026-09-24 10:30:00 +0800
categories: [flutter, android]
tags: [flutter, android, typography, skia, font]
description: "一次 Flutter 3.47.5 小米字体变粗问题的排查：区分 FontWeight 与可变字体轴，读取实际系统映射，以独立诊断应用验证最小兼容方案。"
---

升级到 Flutter 3.47.5 后，一台小米手机上的文字明显变粗了，标题尤其突出。业务代码里的 `FontWeight.w400`、`w500`、`w700` 没有跟着修改，问题却出现在多个使用公共文本组件的页面。

最初很容易怀疑系统开启了粗体，或者渲染后端发生变化。最终找到的关键是：**Flutter 传入的字重数值，与这台设备为 MiSans 配置的可变字体轴值，并不相同。** 引擎自动写入 `wght` 后，原来由系统配置指定的轴值被覆盖了。

本文记录这条证据链，以及一个限定在已识别字体配置上的应用侧兼容方案。排查与设备验证使用 Flutter 3.47.5；没有遍历历史版本，因此不把它写成问题首次出现的版本。

## 先确认到底是哪一层在加粗

我先检查了系统设置和应用文本配置。第一台设备上，字体缩放为 `1.0`，系统字重调整项未设置，应用的 `MediaQuery.boldText` 已关闭。这些结果不足以说明系统字体没有定制，但没有支持「用户开启了额外加粗」的判断。

渲染后端也需要现场确认。这次检查到的应用已经关闭 Impeller，不能仅凭「升级后出现」就将问题归因于 Impeller。

## 系统配置给出了第一条直接证据

可变字体可以用一份字体文件生成不同粗细的字形。`wght` 是其中控制字重的轴，数值决定选用这个字体设计空间里的哪个位置。Flutter 的 [`fontVariations` 文档](https://api.flutter.dev/flutter/painting/TextStyle/fontVariations.html)提供了设置这类轴的接口。

Android 字体配置还可以给字体实例声明一个用于匹配的 `weight`。这个匹配值与实例内部的 `wght` 轴值，未必相等。

第一台设备的 `/system/etc/fonts.xml` 中，默认 `sans-serif` 家族使用 `MiSansVF_Overlay.ttf`。其中一个字体实例的相关配置如下，省略了其他条目：

```xml
<font weight="700" style="normal">MiSansVF_Overlay.ttf
    <axis tag="wght" stylevalue="450" />
</font>
```

它表示：匹配字重 `700` 时，这个实例配置的 `wght` 是 `450`。直接把轴设置为 `700`，会得到另一种更粗的字形。

后来换了第二台小米，我又读取了它的实际配置。两台设备都使用这个字体文件，但映射并不一致：

| 请求字重 | 设备 A：Android 16 | 设备 B：Android 13 |
| --- | ---: | ---: |
| `w400` 对应的 `wght` | 330 | 330 |
| `w500` 对应的 `wght` | 380 | 430 |
| `w700` 对应的 `wght` | 450 | 500 |

这张表也否定了一个看似省事的修复：给所有小米写死 `330 / 380 / 450`。它能匹配第一台设备，却会在第二台设备上选错中等和粗体的轴值。品牌和字体文件名，都不足以确定具体映射。

## Flutter 为什么没有沿用这些轴值

接下来检查实际 SDK 对应的引擎源码。在 [Flutter 3.47.5 的 `paragraph_builder_skia.cc`](https://github.com/flutter/flutter/blob/3.47.5/engine/src/flutter/txt/src/skia/paragraph_builder_skia.cc#L189-L211) 中，文本样式转成 Skia 样式时，会先收集显式传入的字体轴。

如果这些轴里没有 `wght`，引擎就补上一个，把 `font_weight` 转成浮点数作为轴值。随后，这组坐标被放进字体参数。

因此，在这次的默认字体路径上，请求 `FontWeight.w700` 最终会得到显式的 `wght=700`，而设备 A 的系统实例原本配置的是 `wght=450`。业务样式没有改，实际参与生成字形的参数却变了。

我随后保持字体、文本和画布条件相同，只切换是否显式传入系统配置中的轴值。笔画随之变细，支持了这条源码路径对现场现象的解释。Flutter 仓库中的 [issue #186443](https://github.com/flutter/flutter/issues/186443) 也记录了升级后小米字体变粗的类似现象，但它只能作为外部线索；本次结论依赖实际源码、设备配置和对照实验。

## 最小修复：保留字重，补回已确认的轴

修复放在公共文本样式的最终出口：保留业务的 `FontWeight`，只为符合条件的默认系统字体补上 `wght`。这样，引擎检测到显式轴后，就不会再用请求字重覆盖它；原有的字体匹配信息也仍然保留。

下面是实际修复中负责合并样式的核心部分，函数名已泛化。`systemAxes` 来自当前设备经过校验的字体配置；配置读取和平台判断不在这个函数中：

```dart
TextStyle restoreSystemWeight(
  TextStyle style,
  Map<FontWeight, double> systemAxes,
) {
  final family = style.fontFamily;
  final axis = systemAxes[style.fontWeight];
  if (axis == null ||
      (family != null && family.isNotEmpty && family != 'sans-serif') ||
      (style.fontFamilyFallback?.isNotEmpty ?? false) ||
      (style.fontVariations?.any((v) => v.axis == 'wght') ?? false)) {
    return style;
  }
  return style.copyWith(fontVariations: [
    ...?style.fontVariations,
    FontVariation('wght', axis),
  ]);
}
```

这里有几个不能省掉的条件。显式字体、显式回退列表和调用方自己指定的 `wght` 都优先保留；其他字体轴也不能被清空。如果当前样式没有声明字重，就不猜它继承的是 `w400`。应用原有的自定义字重设置，则在调用这个函数之前优先处理。

读取配置的范围同样需要收紧：这次只接受默认 `sans-serif` 家族中，已识别的 `MiSansVF_Overlay.ttf` 正常样式及有效轴值。文件不可读、字体不匹配、条目缺失或数值无效时，保留原有行为，不根据品牌名称猜一个数值。

配置放入已有的 Android 字体初始化流程，独立诊断应用在首屏绘制前等待初始化完成。

## 用独立应用验证，而不是只看一张截图

为了隔离业务主题、页面布局和运行时配置，我制作了一个独立包名的诊断应用，直接引用修复后的公共组件。它不覆盖业务应用，分别展示三个字重，每个字重都有三组结果：Android 原生绘制、Flutter 默认绘制、公共组件修复后绘制。

对照使用「字体示例 Aa12」作为样本文字，字号为 40 像素，画布固定、基线对齐，均为黑字白底。这样比较时，字号与图片缩放不会混进字重变化里。

下面是设备 A 的诊断截图。每组从上到下依次是原生 Android、Flutter 默认和修复后的结果。点击图片可查看原尺寸。

<figure>
  <a href="{{ '/assets/images/flutter-xiaomi-font-weight/device-a.png' | relative_url }}"><img src="{{ '/assets/images/flutter-xiaomi-font-weight/device-a.png' | relative_url }}" alt="设备 A 的字重对照：400、500、700 各包含原生、Flutter 默认与修复后三行" width="420" loading="lazy"></a>
  <figcaption>设备 A，Android 16。修复后的 wght 分别为 330、380、450。</figcaption>
</figure>

除了观察完整对照页，我还统计了图像的墨迹总量：对黑白图像的每个像素累加 `255 - R`，其中 `R` 是红色通道值。数字越大，表示固定画布内的黑色覆盖越多。以下是设备 A 使用上述样本文字时，`w700` 的结果：

| 设备 | Flutter 默认墨迹总量 | 恢复系统轴后 | 相对默认值变化 |
| --- | ---: | ---: | ---: |
| A | 1,164,617 | 830,878 | −28.7% |

这些数字用于佐证笔画覆盖减少，不能解读为「视觉字重准确降低了多少」，也不代表修复后与 Android 原生逐像素一致。原生和 Flutter 的字体选择、栅格化细节仍可能不同；原生结果在这里是参照，而不是像素相等的验收目标。

验证还包括 5 项针对解析与样式合并的单元测试，以及每台设备各 16 项诊断应用断言。检查范围覆盖了系统轴映射、显式轴优先级、自定义字体和回退列表，以及重复应用修复时不继续追加轴。

第二台设备的意义尤其大：它使用不同映射，仍能从自身配置获得对应结果。因此，诊断断言也必须依据当前设备读取到的有效映射，并与设备配置核对，不能把第一台设备的数值当成所有设备的标准答案。

这次验证到的是公共组件及独立诊断 APK。完整业务 APK 的依赖更新、最终打包和业务页面回归仍是后续验收环节，不能用诊断应用通过来替代。

## 兼容方案的停止条件

读取 `/system/etc/fonts.xml` 是这次针对已识别配置采取的兼容措施。所检查文件的头部也明确提示：这不是供第三方应用长期依赖的稳定接口，格式和位置可能变化。因此，不能把这段读取逻辑包装成通用的 Android 字体 API。

以下变化都需要重新验证：系统升级后配置不可读或结构变化、用户切换系统字体或主题、Flutter 修改轴处理逻辑，以及页面改用自带字体。这次初始化只读取一次配置，没有实现运行期间切换系统字体后的自动刷新。

目前，修复只覆盖经过公共样式出口的文本。未经过这个出口的 `Text`、`RichText` 和 Canvas 文本，需要单独接入并验证。
