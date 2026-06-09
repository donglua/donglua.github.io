---
layout: post
title: "Guava EventBus 注册 Activity 在低版本 Android 上引发 NoClassDefFoundError"
date: 2026-04-21 14:00:00 +0800
categories: android
tags: [Android, EventBus, Guava, ART, PictureInPicture, 崩溃分析]
description: "分析 AndroidX 升级后，Guava EventBus 直接注册 Activity 在低版本 Android 上触发 PictureInPictureUiState 解析失败的原因与修复方式。"
---

## 背景

一次 AndroidX 依赖升级后，低版本设备开始在兼容测试中稳定崩溃。崩溃只出现在 Android 11 及以下系统，高版本设备没有异常。

表面入口是 Guava EventBus 的 `register()`：

```text
com.google.common.util.concurrent.ExecutionError:
  java.lang.NoClassDefFoundError: Failed resolution of: Landroid/app/PictureInPictureUiState;
    at com.google.common.eventbus.EventBus.register(EventBus.java)
    at cn.example.utils.EventBusCenter.register(EventBusCenter.kt:7)
    at cn.example.ui.SomeActivity.onCreate(SomeActivity.kt)
```

业务代码没有直接使用 `PictureInPictureUiState`，也没有主动调用画中画相关 API。问题出在三个条件叠加：

- AndroidX Activity 的父类方法签名里出现了 Android 12 才存在的 framework 类型。
- Guava EventBus 注册订阅者时会反射扫描订阅者的完整继承链。
- 业务代码把 `Activity` 本身注册成了 EventBus subscriber。

结论先放前面：不要把 `Activity`、`Fragment`、`View` 这类 framework 组件对象直接传给 Guava EventBus 做 subscriber。把订阅方法移到一个独立 subscriber 对象里，让 EventBus 扫描的类继承链停在业务小对象上。

---

## 现场代码

`EventBusCenter` 本身只是一个薄封装：

```kotlin
object EventBusCenter {
    val instance = EventBus()

    fun register(obj: Any?) {
        instance.register(obj)
    }

    fun unregister(obj: Any?) {
        instance.unregister(obj)
    }
}
```

原始写法是把 `@Subscribe` 方法直接放在 `Activity` 上，然后注册 `this`：

```kotlin
class SomeActivity : AppCompatActivity() {

    @Subscribe
    fun onMessageEvent(event: String) {
        // 处理事件
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        EventBusCenter.register(this)
    }

    override fun onDestroy() {
        EventBusCenter.unregister(this)
        super.onDestroy()
    }
}
```

这段代码看起来没有引用 Android 12 的 API，但它把一个复杂的 framework 组件暴露给了 Guava EventBus 的反射扫描逻辑。

---

## 触发条件

### 1. 缺失类来自 Android 12

`android.app.PictureInPictureUiState` 是 Android 12（API 31）新增类。低版本系统镜像里没有这个类。

只要运行时尝试解析这个类型，就可能抛出：

```text
java.lang.NoClassDefFoundError: Failed resolution of: Landroid/app/PictureInPictureUiState;
```

这类错误不要求业务代码显式调用相关方法。方法签名、字段签名、注解、泛型桥接方法、反射枚举方法列表，都可能让运行时去解析一个当前系统不存在的类型。

### 2. 依赖升级把新方法带进了父类

依赖升级后，AndroidX Activity / ComponentActivity 的类定义里可能包含类似方法：

```java
public void onPictureInPictureUiStateChanged(PictureInPictureUiState pipState) {
}
```

这段代码在高版本设备上没有问题，因为系统存在 `PictureInPictureUiState`。

在 Android 11 及以下设备上，单纯安装 APK 通常也不会立刻崩溃。风险来自运行时是否触发该方法签名的解析。只要某段代码反射枚举到这个方法，ART 就可能尝试解析参数类型，然后发现 framework 类不存在。

### 3. EventBus 注册会扫描父类链

Guava EventBus 不是只看当前类上有没有 `@Subscribe`。它会通过 `SubscriberRegistry` 找出订阅者类型及其父类型，然后反射读取方法：

```java
Set<Class<?>> supertypes = TypeToken.of(clazz).getTypes().rawTypes();
for (Class<?> supertype : supertypes) {
    for (Method method : supertype.getDeclaredMethods()) {
        // 查找 @Subscribe 方法
    }
}
```

当注册对象是 `SomeActivity` 时，扫描范围不是：

```text
SomeActivity
```

而是接近：

```text
SomeActivity
  -> AppCompatActivity
  -> FragmentActivity
  -> ComponentActivity
  -> Activity
  -> ...
```

`@Subscribe` 只写在 `SomeActivity` 上，但 EventBus 为了支持继承场景，仍然会遍历父类链。问题就出在 `ComponentActivity.getDeclaredMethods()`。

---

## 崩溃调用路径

完整调用路径可以压缩成下面几步：

```text
SomeActivity.onCreate()
  -> EventBusCenter.register(this)
    -> EventBus.register(SomeActivity)
      -> SubscriberRegistry 扫描 SomeActivity 的所有父类型
        -> ComponentActivity.getDeclaredMethods()
          -> 解析方法签名 PictureInPictureUiState
            -> Android 11 及以下系统不存在该 framework 类
              -> NoClassDefFoundError
```

这里有一个容易误判的点：崩溃不是因为调用了 `onPictureInPictureUiStateChanged()`，而是因为反射枚举方法时触发了方法签名解析。

因此，加上版本判断也不一定能解决问题：

```kotlin
if (Build.VERSION.SDK_INT >= 31) {
    // ...
}
```

如果 `EventBus.register(this)` 仍然发生在低版本设备上，反射扫描仍然可能先于业务分支执行，崩溃仍然存在。

---

## 为什么高版本正常，低版本崩溃

高版本设备存在 `android.app.PictureInPictureUiState`，所以 `ComponentActivity` 方法签名可以被解析。

低版本设备不存在这个 framework 类。AndroidX 可以在编译期引用它，是因为应用使用了高版本 `compileSdk`；但运行期类是否存在，取决于设备系统版本。

这也是 Android 兼容性问题里很常见的一类分裂：

| 阶段 | 是否通过 | 原因 |
|---|---|---|
| 编译期 | 通过 | `compileSdk` 提供了 API 31 类定义 |
| 安装期 | 通常通过 | 未必立即解析所有方法签名 |
| 运行期反射扫描 | 失败 | 低版本 framework 不存在目标类 |

换句话说，`compileSdk` 能让代码编译通过，但不能把新系统类带到旧设备上。

---

## 修复目标

修复不是「避开 `PictureInPictureUiState`」这么简单。业务代码本来就没有直接引用它。

真正要做的是缩小 EventBus 的反射扫描边界：

```text
不要让 EventBus 扫描 Activity 继承链。
```

把 subscriber 从 `Activity` 本身移出去，让注册对象变成一个小而独立的对象：

```text
EventBus.register(Activity)              // 风险：扫描 Activity 父类链
EventBus.register(EventBusSubscriber)    // 安全：只扫描 subscriber 自身及 Object
```

---

## 推荐修复：独立 subscriber 对象

可以把订阅方法提取到一个顶层类、普通 Kotlin 嵌套类，或者 `companion object` 内的嵌套类中。关键点不是必须放在 `companion object`，而是这个类不能是 `Activity` 的子类，也不能把 `Activity` 放进 EventBus 的扫描继承链里。

示例写法：

```kotlin
class SomeActivity : AppCompatActivity() {

    private val eventBusSubscriber = EventBusSubscriber(
        onMessage = { event ->
            handleEvent(event)
        }
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        EventBusCenter.register(eventBusSubscriber)
    }

    override fun onDestroy() {
        EventBusCenter.unregister(eventBusSubscriber)
        super.onDestroy()
    }

    private fun handleEvent(event: String) {
        // 处理事件
    }

    private class EventBusSubscriber(
        private val onMessage: (String) -> Unit
    ) {
        @Subscribe
        fun onMessageEvent(event: String) {
            onMessage(event)
        }
    }
}
```

Kotlin 的嵌套类默认不持有外部类引用，只有显式标记为 `inner` 的类才会持有外部类实例。

因此，下面这个类是可以作为独立 subscriber 的：

```kotlin
private class EventBusSubscriber(...)
```

下面这个则不建议作为默认方案：

```kotlin
private inner class EventBusSubscriber(...)
```

`inner` 会引入外部 `Activity` 引用。虽然 EventBus 主要扫描的是 subscriber 的继承链，不是字段类型，但这种写法会增加生命周期引用风险，也让问题边界变得不清晰。

---

## 匿名对象是否可以

如果只是为了切断 EventBus 对 `Activity` 父类链的扫描，注册一个匿名对象通常也能做到：

```kotlin
private val eventBusSubscriber = object {
    @Subscribe
    fun onMessageEvent(event: String) {
        handleEvent(event)
    }
}
```

此时 EventBus 扫描的是匿名对象的类，而不是 `SomeActivity`。

但匿名对象会自然捕获外部 `Activity` 的方法或字段，代码审查时也不如命名类清楚。对于生命周期长、事件来源复杂、容易遗漏 `unregister()` 的项目，命名的独立 subscriber 更容易维护。

所以这里推荐的规则是：

- 只看崩溃规避：不要注册 `Activity` 本身。
- 看长期维护：优先使用命名的独立 subscriber。
- 如果 subscriber 会持有 `Activity` 行为，必须保证和 `Activity` 生命周期成对注册与注销。

---

## 修复前后对比

| 维度 | 原始写法 | 修复后 |
|---|---|---|
| 注册对象 | `this`，即 `Activity` 本身 | 独立 subscriber 对象 |
| EventBus 扫描范围 | `Activity` 完整父类链 | subscriber 类及其父类 |
| 是否触及 `ComponentActivity` | 是 | 否 |
| 低版本兼容风险 | 高 | 低 |
| 生命周期风险 | `Activity` 直接被 EventBus 持有 | 仍需注销，但边界更清楚 |

---

## 为什么不建议直接注册 framework 组件

这次问题由 `PictureInPictureUiState` 引发，但根因不是这个类本身。

`Activity`、`Fragment`、`View` 这类对象的继承链很长，父类来自 Android framework 和 AndroidX。它们的方法签名会随着依赖升级、`compileSdk` 提升、AndroidX 实现变化而变化。

把它们直接交给反射框架，相当于把整个父类链暴露给框架扫描。只要父类链上出现一个低版本设备无法解析的类型，就可能在业务代码之外崩溃。

高风险写法包括：

```kotlin
EventBusCenter.register(this)        // this 是 Activity
EventBusCenter.register(fragment)    // fragment 是 Fragment
```

更稳的写法是：

```kotlin
EventBusCenter.register(subscriber)
```

其中 `subscriber` 是专门为事件订阅准备的小对象，只暴露必要的 `@Subscribe` 方法。

---

## 类似风险场景

只要框架会反射枚举类方法，就可能遇到类似问题：

- Guava EventBus 的 `EventBus.register()`
- Otto EventBus 的 `Bus.register()`
- 自定义注解扫描逻辑里的 `getDeclaredMethods()` / `getMethods()`
- 运行期路由、插件、埋点框架中对宿主类的反射扫描

排查时可以按下面顺序收敛：

1. 找到 `NoClassDefFoundError` 里真正缺失的类。
2. 确认该类从哪个 API 级别开始存在。
3. 查找崩溃栈里第一个反射入口。
4. 看传入反射框架的对象是否是 `Activity`、`Fragment`、`View` 或其他复杂 framework 类型。
5. 把反射扫描对象替换成独立小对象，再在低版本设备上验证。

---

## 总结

这个崩溃的本质不是「画中画 API 不能在低版本用」，而是「反射框架扫描了不该扫描的类继承链」。

`PictureInPictureUiState` 只是第一个暴露问题的缺失类型。真正脆弱的写法是把 `Activity` 本身注册到 Guava EventBus，让 EventBus 在低版本设备上扫描 `ComponentActivity` 的方法列表。

修复原则很简单：

- EventBus subscriber 应该是小对象，不应该是 `Activity` 本身。
- 低版本兼容问题不能只看业务代码是否显式调用新 API，还要看反射、注解扫描、方法枚举是否会解析新 API 类型。
- AndroidX 升级后，如果出现旧系统才有的 `NoClassDefFoundError`，需要重点检查父类方法签名和反射扫描入口。

这一类问题的排查重点不在「哪里调用了缺失类」，而在「谁触发了缺失类的解析」。
