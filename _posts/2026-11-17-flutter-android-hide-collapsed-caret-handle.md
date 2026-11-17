---
layout: post
title: "Flutter Android 隐藏输入框「光标水滴」手柄：只屏蔽 collapsed，不丢长按选区与菜单"
date: 2026-11-17 14:29:00 +0800
categories: [flutter, android]
tags: [flutter, android, text-field, selection-controls]
description: "在 Android 上，Flutter TextField 在文本非空时点击或切回可编辑态会弹出光标水滴手柄。本文通过自定义 MaterialTextSelectionControls 只隐藏 collapsed 手柄，并说明混入 TextSelectionHandleControls、限定 Android 平台及 48x48 隐形热区的边界。"
---

在做一个带自定义表情面板的聊天输入栏时，Android 端出现了一个很碍眼的交互细节：只要输入框里有字，点一下输入框、重新获焦，或者在表情面板和系统键盘之间切换，光标正下方就会挂出一个 Material 风格的「水滴」手柄（`collapsed` selection handle）。底部输入栏贴近屏幕边缘或表情面板顶部，这个水滴经常直接盖在按钮或输入区边框上。

排查完 Flutter 的选区控制链路后，结论很直接：**不要去改 `EditableText` 内部状态，也不要直接传 `EmptyTextSelectionControls()`；继承 `MaterialTextSelectionControls` 并混入 `TextSelectionHandleControls`，仅在 `buildHandle` 里把 `TextSelectionHandleType.collapsed` 渲染成 `SizedBox.shrink()`，且严格只在 Android 平台启用。**

这样做能同时满足三件事：单光标水滴消失、长按选区手柄和复制粘贴菜单完整保留、iOS 端不受影响。

## 一、为什么水滴总会弹出来

很多人遇到「切到表情面板或点表情后弹出水滴」时，第一反应是检查自己的文本写入方式。比如常见表情面板写法是直接拼接 `.text`：

```dart
controller.text += emojiTag;
```

在 Flutter 的 `TextEditingController.text=` 实现中，直接赋值 `.text` 会把 `selection` 重置为非法的 `TextSelection.collapsed(offset: -1)`。当输入框处于聚焦态时，`EditableTextState._didChangeTextEditingValue` 会把无效选区修正到文本末尾。

但真正导致水滴出现的原因不在这里——`EditableText` 修正无效选区时特意绕开了 `_handleSelectionChanged`，注释里明确写了就是为了避免在 Android 上把选区手柄点亮。水滴之所以弹出来，是因为 `TextField`（包括 `extended_text_field` 等同类封装）在 `_TextFieldState._shouldShowSelectionHandles` 里硬编码了这条规则：

```dart
if (cause == SelectionChangedCause.keyboard) {
  return false;
}
if (widget.readOnly && _effectiveController.selection.isCollapsed) {
  return false;
}
if (!_isEnabled) {
  return false;
}
if (cause == SelectionChangedCause.longPress || ...) {
  return true;
}
if (_effectiveController.text.isNotEmpty) {
  return true;
}
```

只要满足「非键盘输入引起、非只读、文本非空」，框架就会把 `showSelectionHandles` 置为 `true`。于是哪怕把表情插入改成维护合法 `selection` 的 `controller.value = ...`，只要用户在文字非空时点击输入框、重新聚焦，或者从自定义键盘的 `readOnly: true` 切回系统键盘的 `readOnly: false`（`didUpdateWidget` 中 `readOnly` 变化同样会打开手柄），光标水滴依然会弹出来。

## 二、常见误区：直接上 `EmptyTextSelectionControls`

`TextField` 暴露了 `selectionControls` 参数，于是最容易想到的做法是传入 Flutter 自带的 `EmptyTextSelectionControls()`。

问题在于，`EmptyTextSelectionControls` 把三种手柄全部清空了。换上它之后，单光标水滴确实没了，但用户长按选中文字时左右两端的拖动范围手柄（`left` / `right`）也会一起消失，相当于把文本精确选择能力废掉了。我们需要的是**只隐藏单光标态的水滴，保留选区态的双端手柄**。

## 三、最小实现与两个必踩的坑

Flutter 把选择手柄分成三种枚举：

- `TextSelectionHandleType.left`：范围选区的左端手柄
- `TextSelectionHandleType.right`：范围选区的右端手柄
- `TextSelectionHandleType.collapsed`：单光标态的水滴手柄

因此只要重写 `TextSelectionControls.buildHandle`，在 `type == TextSelectionHandleType.collapsed` 时返回零尺寸占位组件，其余分支交给父类 `MaterialTextSelectionControls` 即可：

```dart
import 'package:flutter/material.dart';

/// 仅隐藏 Android 单光标水滴（collapsed），保留范围选区手柄与上下文菜单。
class CaretHandleHiddenSelectionControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    if (type == TextSelectionHandleType.collapsed) {
      return const SizedBox.shrink();
    }
    return super.buildHandle(context, type, textLineHeight, onTap);
  }
}

final TextSelectionControls caretHandleHiddenSelectionControls =
    CaretHandleHiddenSelectionControls();
```

这段代码很短，但有两个容易遗漏的约束，少一个就会出问题。

### 坑 1：必须混入 `TextSelectionHandleControls`

从 Flutter 3.3 引入 `contextMenuBuilder` 开始，`EditableText` 和各类第三方输入库（如 `extended_text_field`）都会做这层判断：

```dart
if (selectionControls is! TextSelectionHandleControls) {
  // 退回已废弃的 selectionControls.buildToolbar(...)
}
```

如果只继承 `MaterialTextSelectionControls` 而不写 `with TextSelectionHandleControls`，长按菜单就会退回旧版 `buildToolbar` 通路，自定义 `contextMenuBuilder`、桌面/移动端平台适配菜单都会失效。框架内部的默认控件 `materialTextSelectionHandleControls` 也是用同样的方式混入该 mixin 的。

### 坑 2：必须限定只在 Android 平台传入

千万不要在组件里无条件写死：

```dart
// 错误示范：会把 iOS 的选区手柄也变成 Android 水滴
selectionControls: caretHandleHiddenSelectionControls,
```

当 `selectionControls` 为 `null` 时，`TextField` 会按 `Theme.of(context).platform` 自动选择平台控件：Android 走 `materialTextSelectionHandleControls`，iOS 走 `cupertinoTextSelectionHandleControls`。

如果在 iOS 上也传入继承自 `MaterialTextSelectionControls` 的实例，长按选区时的左右手柄会瞬间变成 Android Material 的水滴样式，颜色也改走 `Theme.colorScheme.primary` 而非 `CupertinoTheme`。更关键的是，Flutter 的 `CupertinoTextSelectionControls.buildHandle` 对 `collapsed` 本来就只返回一个透明占位的 `SizedBox`，iOS 原生并不会画出水滴。

正确接入方式是检查 `Theme.of(context).platform`：

```dart
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    required this.controller,
    this.hideCaretHandle = true,
    super.key,
  });

  final TextEditingController controller;
  final bool hideCaretHandle;

  @override
  Widget build(BuildContext context) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    return TextField(
      controller: controller,
      selectionControls:
          hideCaretHandle && isAndroid ? caretHandleHiddenSelectionControls : null,
    );
  }
}
```

这里用 `Theme.of(context).platform` 而不是 `dart:io` 的 `Platform.isAndroid`，是因为 `TextField` 内部正是根据 `Theme.of(context).platform` 分发选区控件，同时也能直接在 Widget 测试中通过 `ThemeData(platform: ...)` 覆盖验证。

## 四、实测行为与已知边界

接入后，各场景下的表现如下：

| 场景 | Android 行为 | iOS 行为 |
| --- | --- | --- |
| 单击非空输入框 / 获焦 / 切换键盘 | 竖线光标正常闪烁，下方无水滴手柄 | 与改前一致，无水滴 |
| 长按 / 双击选中文字 | `left` / `right` 选区手柄和复制粘贴菜单正常 | 保持原生 Cupertino 手柄与菜单 |
| 点击光标正下方 | 不会再弹出水滴上的粘贴条，点击穿透到下层控件 | 与改前一致 |

这里有一个必须提前知悉的边界：**该改动只清除了视觉绘制，没有移除 Overlay 的 `48×48` 透明拖拽热区。**

查看 `TextSelectionOverlay` 的 `_SelectionHandleOverlay` 实现可以发现，框架会根据 `getHandleSize` 和 `getHandleAnchor` 算出手柄矩形，再按 `kMinInteractiveDimension`（`48.0`）外扩成一个 `RawGestureDetector(behavior: HitTestBehavior.translucent)`。因为我们返回了 `SizedBox.shrink()`，里面原本用来点击弹出粘贴条的 `GestureDetector(onTap: onTap)` 不再构建，所以**普通点击会直接穿透**到底下的按钮或列表。

但外层的 `PanGestureRecognizer` 依然挂在 Overlay 上。如果输入栏下方紧挨着一个可垂直滚动的面板（比如表情网格），当光标刚好落在输入框末尾附近时，手指从光标正下方这一小块区域起手滑动，仍可能被判定为「拖动光标」而不是滚动下方面板。真机上如果发现这个区域紧贴频繁滑动的交互元素，建议实际滑动确认手感是否可接受。

## 五、收口检查清单

如果要在自己的项目里复用这套做法，落地时核对这四项即可：

1. 自定义控件继承 `MaterialTextSelectionControls` 并**混入 `TextSelectionHandleControls`**，不要漏掉 mixin。
2. `buildHandle` 仅拦截 `TextSelectionHandleType.collapsed` 返回 `const SizedBox.shrink()`，其他类型调用 `super.buildHandle`。
3. 接入处通过 `Theme.of(context).platform == TargetPlatform.android` 做平台隔离，iOS 及其他平台保持传 `null`。
4. 如果输入栏搭配了自定义表情面板，建议把原本 `controller.text += tag` 的拼接方式一并改成维护 `controller.value` 的光标位置插入——二者解决的问题不同（一个隐藏水滴、一个防止光标跳回末尾），互补但不互相替代。
