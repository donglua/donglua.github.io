---
layout: post
title: "JZOfficeAndroid：一个轻量级 Android Office 文档预览库"
date: 2026-09-22 10:00:00 +0800
categories: [技术, Android]
tags: [Android, Rust, Office, 开源]
description: "JZOfficeAndroid 支持在 Android 应用内离线预览 DOCX、PPTX 和 XLSX，0.3.0 本地 Release 构建的核心 AAR 约 782 KiB。项目以减少加载等待、控制接入包体积为目标，本文介绍其功能、预览效果、接入方式及适用范围。"
---

以前在 Android 项目中遇到 Office 文档预览需求，我通常会接入微软的在线预览方案。但实际使用下来，最影响体验的问题是加载慢：点开一份文档后，需要等待内容显示。改成本地预览时，我也希望控制接入成本，尤其是给应用增加的包体积。因此，JZOfficeAndroid 从一开始就有两个目标：减少文档加载等待，同时尽量降低接入带来的包体积增量。

[JZOfficeAndroid](https://github.com/donglua/JZOfficeAndroid) 就是围绕这两个目标做的一个开源库。它支持 **DOCX、PPTX 和 XLSX 的基础预览**，通过 Android `Uri` 打开文件，在应用内完成解析和显示，不依赖服务器转换、WebView 或已安装的 Office 应用。0.3.0 本地 Release 构建的核心 AAR 约 782 KiB，适合希望控制接入体积、又需要在应用内查看 Office 附件的 Android 项目。

它的定位是轻量、离线、只读的内容预览。对于需要精确打印版式、复杂公式计算或编辑能力的产品，还需要选择具备相应能力的方案。

## 减少打开文档时的等待

JZOfficeAndroid 采用本地解析和渲染。对于已经保存在设备上、或通过 URI 可以直接读取的文档，应用能够直接打开，不需要再等待在线预览服务返回内容。网络附件则先下载到本地，再交给同一个预览组件显示。

这让预览的加载过程由应用自己管理：文件读取、解析和图片解码在工作线程执行，图片按可见区域加载，页面可以展示加载状态并处理错误。项目希望改善的是从「点开附件」到「看到内容」的体验。

0.3.0 进一步为 PPTX 引入按需排版，只为可见页和前后相邻页准备文字与绘图布局；图片缓存会保留最近使用的图片，返回时可以复用，减少重复解码。文档仍一次解析成完整的有界模型，按需处理的是页面布局和图片。

具体打开速度仍取决于文件大小、内容复杂度和设备性能。项目目前没有提供与微软在线预览的统一耗时对照，因此这里介绍的是实现方式和目标；是否达到业务要求，需要用相同文档实测。

## 控制接入包体积，核心 AAR 不到 1 MB

包体积是项目设计时的一项约束。JZOfficeAndroid 聚焦只读的基础预览，不打包字体，将在线下载拆成可选模块；只需要本地预览的应用，可以只引入核心库。这样可以按实际需求选择接入内容，控制新增的包体积。

截至 2026 年 9 月 22 日，项目当前版本为 **0.3.0**。以下为该版本本地 Release 构建的实际文件大小，CI 发布附件以 [v0.3.0 Release](https://github.com/donglua/JZOfficeAndroid/releases/tag/v0.3.0) 为准：

| 模块 | AAR 大小 | 用途 |
| --- | --- | --- |
| `viewer` | 约 **782 KiB**（800,593 字节） | DOCX、PPTX、XLSX 本地预览 |
| `viewer-online` | 约 **18.9 KiB**（19,313 字节） | 可选的在线下载与缓存管理 |
| 两者合计 | 约 **801 KiB**（819,906 字节） | 下载在线文件后在本地预览 |

核心 AAR 已包含 `arm64-v8a` 和 `armeabi-v7a` 两种架构的原生库，不打包字体和 Demo 样例。通过 Maven 依赖接入时，应用项目不需要安装 Rust 或 NDK。

这里统计的是 AAR 压缩文件大小。接入后的 APK 增量还会受到 ABI 选择、R8 优化和原生库打包方式影响，应以实际应用的构建结果为准。

## 三种格式，各自保留常用的浏览能力

Word、PPT 和 Excel 的阅读方式不同，项目也为它们保留了不同的显示方式。

**DOCX 以连续内容流展示。** 可以查看段落、字号和颜色、粗斜体、下划线、行距与缩进，以及图片和基础表格。内容纵向滚动，适合阅读说明文档和文字附件；它不复现 Word 的精确分页，接口返回的页数为 1。

**PPTX 按幻灯片顺序展示。** 保留页面尺寸和元素位置，支持文字、图片、基础图形、组合变换、简单表格，以及读取文件内缓存数据的基础折线图。可以滚动浏览、缩放和跳转页面；动画、SmartArt 和复杂图表不在当前支持范围内。

**XLSX 以工作表网格展示。** 支持多工作表切换、行列标题、双向滚动、合并单元格、基础样式，以及常见数字、百分比和日期格式。公式显示文件保存时写入的缓存结果，不在设备上重新计算；没有缓存结果时，会显示公式文本并给出提示。

下面是撰文时项目仓库提供的 Android Demo 样例截图。截图来自当前源码 Demo，展示三种格式的预览形式；具体版本和文档的显示效果以实际运行结果为准。点击可查看大图。

<table>
  <thead>
    <tr><th>DOCX</th><th>PPTX</th><th>XLSX</th></tr>
  </thead>
  <tbody>
    <tr>
      <td><a href="https://raw.githubusercontent.com/donglua/JZOfficeAndroid/06dd459a74caeb70da4d477fd5ec7af0a888ac3c/docs/images/preview-docx.png"><img src="https://raw.githubusercontent.com/donglua/JZOfficeAndroid/06dd459a74caeb70da4d477fd5ec7af0a888ac3c/docs/images/preview-docx.png" alt="JZOfficeAndroid DOCX 预览：文字、图片与表格" width="220" loading="lazy"></a></td>
      <td><a href="https://raw.githubusercontent.com/donglua/JZOfficeAndroid/06dd459a74caeb70da4d477fd5ec7af0a888ac3c/docs/images/preview-pptx.png"><img src="https://raw.githubusercontent.com/donglua/JZOfficeAndroid/06dd459a74caeb70da4d477fd5ec7af0a888ac3c/docs/images/preview-pptx.png" alt="JZOfficeAndroid PPTX 预览：组合图形与折线图" width="220" loading="lazy"></a></td>
      <td><a href="https://raw.githubusercontent.com/donglua/JZOfficeAndroid/06dd459a74caeb70da4d477fd5ec7af0a888ac3c/docs/images/preview-xlsx.png"><img src="https://raw.githubusercontent.com/donglua/JZOfficeAndroid/06dd459a74caeb70da4d477fd5ec7af0a888ac3c/docs/images/preview-xlsx.png" alt="JZOfficeAndroid XLSX 预览：单元格样式与工作表标签" width="220" loading="lazy"></a></td>
    </tr>
  </tbody>
</table>

三种格式共用 `OfficePreviewView` 入口，支持拖动滚动、双指缩放、双击缩放和重置缩放。应用可以监听页码变化，给 PPTX 添加上一页、下一页按钮，也可以通过工作表名称和切表接口给 XLSX 添加标签栏。页码和工作表序号均从 1 开始。

## 本地预览与在线下载按需选择

只需要打开本地附件时，使用 `viewer` 即可。它接受应用有权读取的 `content://` 和 `file://` URI，适合接入系统文件选择器或其他应用交过来的文件。宿主负责取得读取权限，不需要把 `content://` 强行转换为文件系统中的真实路径。

如果文件来自网络，可以增加 `viewer-online`。它支持文件直链、签名 URL、自定义请求头、下载进度、取消和缓存清理，也允许替换下载器，接入应用已有的网络能力。默认实现使用 `HttpURLConnection`，不额外引入网络库。

在线预览的过程是「下载完成 → 本地解析 → 显示文档」。文档渲染仍在设备上完成，不需要额外的云端 Office 转换服务；当前不支持边下载边看、断点续传或持久离线缓存。

## 接入一个预览页面

最低支持 Android 6.0（API 23）。0.3.0 使用新的 Maven groupId `io.github.donglua.office`。以下为该版本的依赖坐标，Maven Central 对应产物可获取后，在项目仓库配置中启用 `mavenCentral()` 即可接入。本地预览使用：

```kotlin
dependencies {
    implementation("io.github.donglua.office:viewer:0.3.0")
}
```

需要在线预览时，改为依赖在线模块即可。它会传递依赖同版本的 `viewer`，本地预览接口也可以直接使用：

```kotlin
dependencies {
    implementation("io.github.donglua.office:viewer-online:0.3.0")
}
```

下面是依据项目 README 整理的接入片段，省略文件选择器和页面容器的创建。`container` 是已有的 `ViewGroup`，`uri` 是已取得读取权限的文档 URI；在主线程执行：

```kotlin
import android.util.Log
import android.widget.Toast
import cn.jingzhuan.lib.office.OfficePreviewView

val preview = OfficePreviewView(container.context)
container.addView(preview)

preview.open(uri, object : OfficePreviewView.Listener {
    override fun onLoaded(info: OfficePreviewView.Info) {
        Log.d("OfficePreview", "${info.format}: ${info.pageCount}")
        // info.warnings 为预览提示，info.sheetNames 为 XLSX 表名。
    }

    override fun onError(error: Exception) {
        Toast.makeText(
            preview.context,
            error.message ?: "文档预览出现错误",
            Toast.LENGTH_SHORT
        ).show()
    }
})
```

`onLoaded` 表示文档模型已经可用，图片会按可见区域继续加载。后续某张图片解码失败时，仍可能收到 `onError`，其他内容可以继续浏览。`Info.warnings` 可用于提示已识别的简化内容，但不表示做过完整的 Office 兼容性检查。

页面销毁时，在 Activity 的 `onDestroy()` 或 Fragment 的 `onDestroyView()` 中调用 `preview.clear()`，释放文档和图片引用。`open()`、`clear()`、跳页和缩放设置都在主线程调用，回调也回到主线程。

从 0.2.0 升级时，需要同时更新 groupId 和版本号，artifactId 与 Java 包名保持不变。发布状态、源码模块及本地 AAR 接入方式见 [README](https://github.com/donglua/JZOfficeAndroid#android-接入)。

## Rust 负责解析，Android 负责显示

项目的实现分成两部分：Rust 核心解析 Office 文件，Android 层使用原生 Canvas 绘制内容。

DOCX、PPTX 和 XLSX 属于 OOXML 格式，文档的文字、样式、图片和部件关系组织在 ZIP 容器中。`jz-office-core` 读取这些内容，转换为平台无关的文档模型；`viewer` 接收模型，完成文字排版、图片解码、绘制和手势交互。

每次打开文档，通过一次 JNI 解析调用传递整份有界模型，图片只传包内路径，不放进 JSON。后续滚动和缩放在 Android 层处理，不需要反复跨 JNI 请求。这种分工保留了原生 View 的接入方式，也让解析核心可以独立测试。

源码中，`core/` 是解析核心，`viewer/` 是 Android 预览库，`viewer-online/` 是可选下载模块，`demo/` 则提供内置样例、文件选择器和在线预览入口。只使用发布的 AAR 时，不需要了解这些内部细节。

## 使用前确认支持范围

项目适合应用内附件阅读、简单报告展示，以及离线浏览常见 Office 内容。接入前需要确认几个边界：

- **仅支持新格式。** 当前不支持旧版 `.doc`、`.ppt`、`.xls`，也不支持加密文档和编辑。旧文件需要先转换格式，仅修改扩展名无效。
- **以内容可读为目标。** 使用系统字体，换行和版式可能与 Microsoft Office 不同；DOCX 精确分页、PPT 动画、Excel 公式计算等能力不在范围内。
- **有文件与资源限制。** 输入文件上限为 128 MiB，XML、页数、单元格和图片另有各自预算。文件大小低于上限，并不保证一定能够打开。

评估时，可以先运行 Demo 查看三种内置样例，再换成实际业务中常见的文档，检查正文、表格、图片、翻页和缩放是否满足阅读要求。同时记录从打开到首屏可读的耗时，并在相同构建配置下比较接入前后的 APK 大小，确认加载体验和包体积都符合项目要求。对合同精确版式、复杂报表或大型演示文稿，应直接用相应文件验证，不能只根据扩展名判断兼容性。

JZOfficeAndroid 采用 **Apache License 2.0** 开源。项目源码、Demo 和完整能力说明见 [GitHub 仓库](https://github.com/donglua/JZOfficeAndroid)，版本说明与附件发布状态见 [Releases](https://github.com/donglua/JZOfficeAndroid/releases)。
