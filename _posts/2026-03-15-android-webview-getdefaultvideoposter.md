---
layout: post
title: "Android WebView 视频起播前闪现灰色遮罩（播放按钮）的解决方案"
date: 2026-03-15
---

在 Android WebView 中加载使用前端播放器 SDK 的课程类 H5 页面时，视频自动起播、首帧渲染前，播放区域会闪现一个灰色的系统内置播放按钮遮罩。不同机型或 Android 版本表现略有差异，且**前端无法通过 CSS/JS 手段隐藏**，需由 Android 端处理。

## 根本原因

WebView 内部的 `<video>` 元素有一个系统内置的 poster（视频封面占位），由 `WebChromeClient.getDefaultVideoPoster()` 控制。该方法默认返回 `null`，触发系统用内置灰色播放图标填充视频区域。

> 相关讨论：[HTML5 video: Remove overlay play icon](https://stackoverflow.com/questions/18271991/html5-video-remove-overlay-play-icon)

## 解决方案

在自定义 `WebChromeClient` 中重写 `getDefaultVideoPoster()`，返回一张 1×1 透明 Bitmap：

```kotlin
webChromeClient = object : WebChromeClient() {

    /**
     * 返回透明占位图，消除视频起播前闪现的系统默认灰色遮罩
     */
    override fun getDefaultVideoPoster(): Bitmap? {
        return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    }
}
```

- `ARGB_8888` 支持 Alpha 通道，新建 Bitmap 像素默认全透明（`0x00000000`）
- 1×1 像素，内存开销可忽略不计
- 无需手动回收

## 小结

任何在 WebView 中嵌入 `<video>` 的 H5 页面都可能触发此问题，建议将此重写作为 `WebChromeClient` 的标准配置项。
