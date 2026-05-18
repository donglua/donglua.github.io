---
layout: post
title: "为什么 TextView 在小尺寸角标里永远居不了中"
date: 2026-05-18 13:00:00 +0800
categories: [技术, Android]
tags: [Android, Custom View, Typography, Font Metrics]
description: "TextView 的 gravity=center 基于 font metrics 定位文字，而 font metrics 包含了大量不可见的预留空间。当容器足够小时，这种偏移肉眼可见。解法是用 Paint.getTextBounds() 拿到实际墨水区域，自己做居中。"
---

设计稿给了一个 14×12dp 的排名角标，背景圆角矩形，里面一个数字居中。用 `TextView` + `gravity="center"` 实现，结果数字总是偏上。调 padding、调 `includeFontPadding="false"`、换 `lineSpacingExtra`，怎么都差那么一两个像素。

## Font Metrics ≠ 你看到的字

Android 的 `TextView` 用 **font metrics** 定位文字。Font metrics 描述的是字体的"设计空间"，而不是某个具体字符的实际像素范围：

```
┌─────────────────────────────┐
│          leading             │  ← 行间距预留
├─────────────────────────────┤
│          ascent              │  ← 包含音调符号空间 (Ä, É)
│                             │
│      ┌───────────┐          │
│      │  visible  │          │  ← 实际墨水区域 (glyph bounds)
│      │   glyph   │          │
│      └───────────┘          │
│                             │
├─────────────────────────────┤
│          descent             │  ← 包含下挂字母空间 (g, y, p)
└─────────────────────────────┘
```

`TextView` 的"居中"是把 ascent 到 descent 这段区间居中在容器里。但对于数字 "1"~"9"：

- 实际墨水区域只占 ascent 的一部分（数字不需要音调符号的空间）
- descent 几乎为零（数字没有下挂部分）

结果就是：font metrics 的几何中心和字形的视觉中心不重合，文字看起来偏上。

容器越大，这个偏移占比越小，越不明显。但当容器只有 12dp 高时，1~2px 的偏移肉眼可见。

## 用 getTextBounds() 验证

用 `Paint.getTextBounds()` 可以拿到字符实际墨水区域的 `Rect`，和 `FontMetrics` 对比一下就能看出差距：

```kotlin
val paint = Paint().apply { textSize = 30f }

val metrics = paint.fontMetrics
// metrics.ascent = -28.0  (baseline 以上 28px)
// metrics.descent = 7.0   (baseline 以下 7px)
// 总高度 = 35px，中心在 baseline 上方 10.5px

val bounds = Rect()
paint.getTextBounds("3", 0, 1, bounds)
// bounds.top = -21  (baseline 以上 21px)
// bounds.bottom = 0 (刚好到 baseline)
// 总高度 = 21px，中心在 baseline 上方 10.5px
```

font metrics 认为文字占 35px，实际 "3" 只占 21px。两者的"中心"差了 `(35 - 21) / 2 = 7px`。在 12dp（约 36px @3x）的容器里，7px 的偏移非常明显。

## 解法：基于 glyph bounds 做测量和绘制

放弃 `TextView`，继承 `View`，自己用 `getTextBounds()` 做居中：

```kotlin
class RankBadgeTextView(context: Context, attrs: AttributeSet?) : View(context, attrs) {

    private val textBounds = Rect()
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var textString = ""

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        if (textString.isNotEmpty()) {
            textPaint.getTextBounds(textString, 0, textString.length, textBounds)
        } else {
            textBounds.setEmpty()
        }
        val desiredWidth = paddingLeft + textBounds.width() + paddingRight
        val desiredHeight = paddingTop + textBounds.height() + paddingBottom
        setMeasuredDimension(
            resolveSize(desiredWidth, widthMeasureSpec),
            resolveSize(desiredHeight, heightMeasureSpec),
        )
    }

    override fun onDraw(canvas: Canvas) {
        if (textString.isEmpty()) return

        val contentLeft = paddingLeft
        val contentRight = width - paddingRight
        val contentTop = paddingTop
        val contentBottom = height - paddingBottom

        val x = contentLeft +
            (contentRight - contentLeft - textBounds.width()) / 2F -
            textBounds.left
        val baseline = contentTop +
            (contentBottom - contentTop - textBounds.height()) / 2F -
            textBounds.top

        canvas.drawText(textString, x, baseline, textPaint)
    }
}
```

几个关键点：

**为什么要减 `textBounds.left`？**

`getTextBounds()` 返回的 `left` 不一定是 0。斜体字或某些字形的左侧会有 bearing（留白或溢出）。减去 `left` 才能让字形的视觉左边缘对齐到我们计算的 x 位置。

**为什么 `-textBounds.top` 就是 baseline 偏移？**

`getTextBounds()` 的坐标系以 baseline 为原点，baseline 以上为负。所以 `top` 是负数（比如 -21），`-top` 就是"从字形顶部到 baseline 的距离"。我们先算出字形顶部应该在哪（居中后的位置），再加上这个距离，就得到了 baseline 的 y 坐标。

**为什么 `onMeasure` 用 glyph bounds 而不是 font metrics？**

如果用 font metrics 测量高度（ascent + descent = 35px），然后在 `onDraw` 里用 glyph bounds 居中（实际只有 21px），wrap_content 时容器会比内容大很多。对于角标这种紧凑场景，测量和绘制必须基于同一套数据。

## 什么时候该用这个方案

这不是一个通用方案。它适合的场景有明确的特征：

- 容器很小（≤ 16dp 高），像素级偏移肉眼可见
- 只显示数字或单个字符，不需要处理多行、省略号、Span
- 需要文字在背景图形中精确视觉居中（角标、徽章、头像上的数字）

正常的文本展示仍然应该用 `TextView`。font metrics 的"偏移"在常规尺寸下是正确的排版行为——它保证了多行文本的行间距一致，保证了不同字符（大写、小写、带音调）在同一行内对齐。只有当你把文字塞进一个极小的容器、且只关心单个字符的视觉中心时，font metrics 才会成为问题。
