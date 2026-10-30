---
layout: post
title: "Flutter 中文加粗不生效：用像素检测按需补偿字重"
date: 2026-09-14
categories: [flutter, android]
tags: [flutter, android, typography, skia, font]
description: "在部分 Android 手机上，通过离屏渲染比较 w400、w500 和 w700 的像素，再用同色、零模糊的阴影补偿未生效的字重。"
---

之前在一台 Android 10 手机上遇到过中文字重不生效的问题：标题设置了 `FontWeight.w500` 或 `w700`，看起来却和普通字重接近。业务代码里的字重设置没有丢，但页面上标题和正文的层次没了。

我采用的方案是：**先离屏绘制同一段文字，检测字重有没有改变渲染结果；对没有变化的字重，再用同色、零模糊的阴影做少量加粗。** 业务层仍然使用 `FontWeight`，检测和补偿集中放在公共文本组件中。

这套方案适合继续使用 Android 系统默认字体的应用，不需要随包加入中文字库，也不需要维护一份机型名单。

## 通过渲染结果决定是否补偿

单纯按品牌或型号开启补偿，粒度太粗。同一品牌的不同系统版本可能使用不同字体，用户也可能更换系统字体。直接比较当前环境下的渲染结果，更贴近要解决的问题。

检测时，选取一段中文样本，分别用 `w400`、`w500` 和 `w700` 绘制。除了字重，字体、字号、颜色、绘制位置和画布尺寸都保持一致，然后逐字节比较图片的 RGBA 数据。

将离屏绘制封装为 `renderSample` 后，核心判断如下。示例使用 `flutter/foundation.dart` 中的 `listEquals` 比较像素：

```dart
final normal = await renderSample(FontWeight.w400);
final medium = await renderSample(FontWeight.w500);
final bold = await renderSample(FontWeight.w700);

final needsMedium =
    normal != null && medium != null && listEquals(normal, medium);
final needsBold =
    normal != null && bold != null && listEquals(normal, bold);
```

`renderSample` 内部用 `ParagraphBuilder` 创建段落，在 `PictureRecorder` 的画布上绘制，再通过 `toImage` 和 `toByteData(format: ImageByteFormat.rawRgba)` 取得像素。画布需要留出足够空间，避免截断字形；返回前确认图片里有文字，采样失败或空图返回 `null`。用完后释放 `Paragraph`、`Picture` 和 `Image`。

两个标志独立保存：`w500` 与 `w400` 相同，就开启 Medium 补偿；`w700` 与 `w400` 相同，就开启 Bold 补偿。这样可以处理「Medium 没有变化，但 Bold 已经正常加粗」的情况。

像素完全相同，说明这段样本在当前条件下没有呈现字重差异。样本应覆盖目标页面常用的字符，字号也应贴近实际使用；中文标题的检测结果用于中文标题，不直接推广到所有字体和字符。

## 用零模糊阴影增加笔画覆盖

Flutter 的 [`TextStyle.shadows`](https://api.flutter.dev/flutter/painting/TextStyle/shadows.html) 会在文字下面绘制阴影。将阴影设为与文字相同的颜色，并把 `blurRadius` 设为 `0`，就会得到一个略微偏移的字形副本。它与原来的文字叠加后，笔画会变厚，同时保留文字本体的填充。

补偿强度可以用偏移量控制。下面的示例给 Medium 增加一个向右偏移的副本，给 Bold 增加左、右、下三个方向的副本：

| 字重 | 阴影偏移 |
| --- | --- |
| `w500` | `(0.35, 0)` |
| `w700` | `(0.4, 0)`、`(-0.4, 0)`、`(0, 0.3)` |

这些数值用于演示两档补偿强度，单位是逻辑像素，可以按实际字号调整。偏移应保持小幅度，避免把汉字内部的留白挤在一起。这种做法属于伪加粗，不会生成字体设计中的真实 Medium 或 Bold 字形。

## 把补偿收口到样式函数

下面的函数接收最终文字样式和两项检测结果，只对命中的字重添加阴影。代码使用 `flutter/foundation.dart` 和 `flutter/material.dart`。

```dart
TextStyle applyFauxWeight(
  TextStyle style, {
  required bool needsMedium,
  required bool needsBold,
}) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android ||
      style.fontFamily != null ||
      (style.fontFamilyFallback?.isNotEmpty ?? false) ||
      (style.fontVariations?.isNotEmpty ?? false) ||
      style.foreground != null ||
      (style.shadows?.isNotEmpty ?? false) || style.color == null) {
    return style;
  }
  final offsets = switch (style.fontWeight) {
    FontWeight.w700 when needsBold =>
      const [Offset(0.4, 0), Offset(-0.4, 0), Offset(0, 0.3)],
    FontWeight.w500 when needsMedium => const [Offset(0.35, 0)],
    _ => const <Offset>[],
  };
  if (offsets.isEmpty) return style;
  return style.copyWith(shadows: [
    for (final offset in offsets)
      Shadow(color: style.color!, offset: offset, blurRadius: 0),
  ]);
}
```

入口处保留了几个过滤条件：仅处理 Android 默认字体，显式指定字体、字体轴、前景画笔或阴影的样式沿用原有处理。这让系统字体的检测结果只作用于对应的文本，也避免覆盖业务本来就有的绘制效果。

函数保留原来的 `fontWeight`，只追加视觉补偿。因此，业务侧仍然可以用 `w500` 表示中等字重、用 `w700` 表示粗体，不必知道当前设备是否触发了兼容处理。

## 在公共文本组件中接入

应用初始化时完成检测，将结果保存在内存中。文本组件构建时读取这两个标志，不重复进行离屏绘制。系统字体发生变化后，再重新检测。

样式处理放在公共文本组件的 `build` 阶段：先按 `Text` 的规则合并 `DefaultTextStyle` 和局部样式，并处理系统的粗体文字设置，再把最终样式传给 `applyFauxWeight`。这样，继承而来的颜色和字重也能参与补偿。

这里有一个接入细节：**先确定颜色，再生成阴影。** `Shadow` 有自己的颜色，后续只调用 `copyWith(color: ...)`，已有阴影不会跟着变色。主题切换或业务改色时，从未补偿的最终样式重新调用这个函数即可。

接入后，页面继续声明所需的字重，公共组件根据检测结果决定是否补偿。像素已有差异的字重直接保留原样；没有差异的那一档，才增加对应的同色阴影。
