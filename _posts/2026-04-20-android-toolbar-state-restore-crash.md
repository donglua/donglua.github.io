---
layout: post
title: "一次由重复 Toolbar ID 引发的 Android 状态恢复崩溃"
date: 2026-04-20 09:00:00 +0800
categories: android
tags: [Android, Toolbar, SavedState, View, DataBinding, include]
---

## 背景

某个 Android 模块在少量场景下出现崩溃，日志核心信息如下：

```java
java.lang.IllegalArgumentException

Wrong state class, expecting View State but received class androidx.appcompat.widget.Toolbar$SavedState instead.
This usually happens when two views of different type have the same id in the same hierarchy.
This view's id is id/toolbar.
```

崩溃并不发生在页面首次打开时，而是集中出现在以下时机：

- 页面重建
- 配置变更后恢复界面状态
- 进程被系统回收后重新进入页面

这类问题的特点是：普通功能验证往往正常，但一旦触发状态恢复，系统会在 `onRestoreInstanceState` 阶段直接抛异常。

---

## 现象

从异常文本可以直接得到两个关键信息：

1. 系统正在恢复一个 `id=toolbar` 的视图状态。
2. 当前接收方期望的是普通 `View` 的状态对象，但实际收到的是 `Toolbar$SavedState`。

这意味着同一个 `ID` 对应到了两种不同类型的视图。更具体一点说，状态是在一个 `Toolbar` 上保存的，却被恢复到了一个非 `Toolbar` 的视图上。

这类崩溃常见于布局复用场景，尤其是 `include`、`merge`、Data Binding 和多层容器叠加后的最终视图树。

---

## 根因分析

问题布局可以抽象成下面这种形式。

页面布局：

```xml
<androidx.constraintlayout.widget.ConstraintLayout
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <include
        android:id="@+id/toolbar"
        layout="@layout/include_toolbar" />

</androidx.constraintlayout.widget.ConstraintLayout>
```

被复用的 toolbar 布局：

```xml
<layout>
    <androidx.constraintlayout.widget.ConstraintLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content">

        <androidx.appcompat.widget.Toolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="wrap_content" />

    </androidx.constraintlayout.widget.ConstraintLayout>
</layout>
```

这里的问题不在于 `include` 本身，而在于 **外层 include 节点和内层真正的 `Toolbar` 使用了同一个 `ID`**。

最终运行时，视图树里会同时出现两个概念上都叫 `toolbar` 的节点：

- 一个是 `include` 落地后的外层容器，例如 `ConstraintLayout`
- 一个是容器内部真正可保存 `Toolbar$SavedState` 的 `Toolbar`

当系统保存状态时，`Toolbar` 会以 `id=toolbar` 存入自己的 `SavedState`。等到恢复状态时，系统按照 `ID` 回填，结果外层容器也占用了同一个 `ID`。这时恢复逻辑命中了错误的目标视图：

- 保存阶段：状态来自 `Toolbar`
- 恢复阶段：状态被分发给 `ConstraintLayout`

于是系统发现：

- 目标视图只接受普通 `View.BaseSavedState`
- 实际收到的是 `Toolbar$SavedState`

最终抛出 `IllegalArgumentException`。

---

## 为什么不是所有页面都会崩溃

这个问题虽然是布局层面的，但并不是所有使用了公共 toolbar 的页面都会稳定触发，原因通常有三个：

### 1. 只有触发状态恢复时才会暴露

如果页面只经历「打开 -> 使用 -> 退出」，可能完全看不到问题。只有系统真正走到视图状态保存与恢复流程时，冲突才会变成异常。

### 2. 只有重复 ID 对应的视图类型不同才会出错

如果两个同名节点碰巧都是普通容器，未必会立刻崩。真正危险的是像这次这样，一个是 `Toolbar`，另一个是普通 `ViewGroup`。

### 3. 复用布局会放大影响范围

一旦问题存在于公共 toolbar 布局中，所有通过 `include` 复用它、并且外层继续命名为 `toolbar` 的页面，都可能在相同条件下中招。

---

## 修复方案

最小修复方式很简单：**保证外层 include 节点与内层真正的 `Toolbar` 不使用同一个 `ID`。**

例如，将内层 `Toolbar` 的 `ID` 改成 `toolbar_view`：

```xml
<layout>
    <androidx.constraintlayout.widget.ConstraintLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content">

        <androidx.appcompat.widget.Toolbar
            android:id="@+id/toolbar_view"
            android:layout_width="match_parent"
            android:layout_height="wrap_content" />

    </androidx.constraintlayout.widget.ConstraintLayout>
</layout>
```

对应代码侧也改为引用新的字段：

```kotlin
setSupportActionBar(binding.toolbar.toolbarView)
```

这样处理有两个好处：

- 页面层不需要重做整体布局结构
- 公共布局只改一处，受影响页面统一切换引用即可

如果页面本身并不需要对 `include` 节点使用 `android:id="@+id/toolbar"`，另一种做法是直接移除外层这个 `ID`。本质都是同一个原则：**一个状态型控件在最终视图树中只能占用一个确定的 ID。**

---

## 排查这类问题的有效方法

如果后续再遇到类似的 `Wrong state class` 崩溃，排查顺序可以直接固定为下面几步：

### 1. 先读异常文案

异常里通常已经给出了最关键的信息：

- 期望的状态类型
- 实际收到的状态类型
- 对应视图的 `ID`

这一步往往比先看业务代码更快。

### 2. 全局搜索对应 `ID`

例如直接搜索：

```bash
rg -n '@\+id/toolbar|@id/toolbar' .
```

重点看以下几类位置：

- `include`
- 公共布局
- Data Binding 布局根节点
- 自定义 View 容器

### 3. 看最终层级，而不是只看单个 XML

单独看某一个布局文件，可能只看到一个 `toolbar`。但一旦 `include` 展开、Data Binding 包裹、容器合并后，最终视图树里可能已经出现两个同名节点。

### 4. 优先修公共布局

如果重复 `ID` 来自公共组件，优先在公共层修正，再统一替换调用侧引用。这样比逐页修改更稳。

---

## 总结

这次问题可以压缩成一句话：

**状态恢复阶段的崩溃，很多时候不是业务逻辑问题，而是最终视图树中存在重复 `ID`，并且重复节点的视图类型不同。**

对于 `Toolbar`、`RecyclerView`、`FragmentContainerView` 这类自带状态恢复逻辑的控件，这个问题尤其容易放大。

一条简单但很有效的约束是：

- 公共布局内部的状态型控件，`ID` 要保持唯一
- 外层 `include` 如果只是为了拿 binding root，不要继续复用同名 `ID`
- 只要异常里出现 `Wrong state class`，优先检查最终视图树中的重复 `ID`

这类问题的修复代码通常不多，但前提是先把「状态是谁保存的，恢复时又落到了谁身上」这件事看清楚。
