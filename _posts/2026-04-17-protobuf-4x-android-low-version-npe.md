---
layout: post
title: "Protobuf 4.x 在 Android 低版本设备的 NullPointerException 分析与修复"
date: 2026-04-17 18:30:00 +0800
categories: android
tags: [Android, Protobuf, 编译器, Unsafe, R8, D8, AGP, SDK]
---

## 背景

我们维护了一套面向第三方提供的 Android SDK。在一次构建链升级中，工程的 Android Gradle Plugin（AGP）升级到了 **7.1.3**，协议运行库同步升级至 **Protobuf 4.x Lite Runtime**。

SDK 交付给第三方合作方后，对方反馈：**在 Android 10 及以下设备上会产生稳定崩溃，而在 Android 11 及以上设备上运行正常。** 本地编译通过，高版本设备无异常，问题只在第三方真实接入的低版本设备上复现。

---

## 现象

崩溃日志如下：

```java
java.lang.NullPointerException: Attempt to invoke virtual method 'void com.google.protobuf.ProtobufArrayList.ensureIsMutable()' on a null object reference
    at com.google.protobuf.ProtobufArrayList.add(ProtobufArrayList.java:80)
    at com.google.protobuf.MessageSchema.reflectField(MessageSchema.java:599)
    at com.google.protobuf.MessageSchema.newSchemaForRawMessageInfo(MessageSchema.java:506)
    at com.google.protobuf.MessageSchema.newSchema(MessageSchema.java:225)
    at com.google.protobuf.ManifestSchemaFactory.createSchema(ManifestSchemaFactory.java:48)
    at com.google.protobuf.Protobuf.schemaFor(Protobuf.java:54)
    at com.google.protobuf.GeneratedMessageLite.makeImmutable(GeneratedMessageLite.java:209)
    at com.google.protobuf.GeneratedMessageLite$Builder.build(GeneratedMessageLite.java:488)
```

触发路径是普通的消息构建：

```java
SomeMessage.newBuilder()
    .addItems(...)
    .build();
```

崩溃并不发生在业务赋值阶段，而是发生在 `build()` 调用触发的 `makeImmutable()` 内部 —— 即 Protobuf Lite Runtime 根据消息类的内部元数据重建 Schema、冻结 repeated/list 字段的阶段。

---

## 原因分析

### 1. Protobuf 4.x 的元数据编码方式

Protobuf Lite 为了压缩包体，不保留完整的 Java 反射描述，而是将消息的结构信息（字段类型、字段偏移量等）高度压缩，编码为一个 `String` 常量写入生成类中：

```java
return newMessageInfo(DEFAULT_INSTANCE, info, objects);
```

`info` 字符串并非普通文本，而是包含了大量二进制位，其中充斥着非标准的 UTF-16 字节流、不可见控制符以及残缺的代理对（Surrogate pairs）。运行时依赖解析这段字符串来重建消息的内部 Schema。

### 2. 旧版 D8 的字符串转码缺陷

本工程使用的 AGP 7.1.3 内置的旧版 D8 编译器，在执行 `.class → .dex` 转换过程中，对字符串常量存在一套转码优化流程。当遭遇 Protobuf 这段包含非标准 UTF-16 字节流的特殊字符串时，D8 会误触编码规则，将其中部分字节截断或转义（String Corruption）。

这一步发生在编译期，产物外观上一切正常，但 Dex 文件中实际携带的元数据字符串已经被破坏，偏移量信息出现偏差。

### 3. Unsafe 快路径放大了问题

Protobuf 4.x Lite Runtime 大量使用 `sun.misc.Unsafe` 进行字段读写，典型模式如下：

```java
Object value = UnsafeUtil.getObject(message, fieldOffset);
```

运行时先根据 Schema 中的元数据算出字段在对象内存中的偏移量 `fieldOffset`，再通过 `Unsafe` 直接按偏移量读取内容，跳过了 `Field.get()` 的类型检查开销。

这种方式性能极高，但对元数据的正确性有绝对依赖。一旦偏移量因第 2 步中 D8 的转码缺陷而出现偏差，`Unsafe` 会按错误地址读取内存，得到 `null` 或无效对象，最终在 `ProtobufArrayList.ensureIsMutable()` 处抛出 NPE。

### 4. 为什么只在 Android 10 及以下复现

同一份损坏的 Dex 文件被安装到不同系统版本的设备上，行为却截然不同，原因在于 Protobuf 内部 `UnsafeUtil` 的初始化策略与 Android Hidden API 限制的交互：

**Android 11 及以上：** 系统对 Hidden API 的管控趋于严格，`UnsafeUtil` 在通过反射尝试获取 `sun.misc.Unsafe` 实例时会被拦截并抛出异常。Protobuf 捕获异常后触发内部的**安全降级（Fallback）机制**，将 Unsafe 快路径标志置为不可用，转而使用基于字段名称的标准反射路径（`Field.get`）。标准反射不依赖偏移量，因此规避了损坏元数据带来的问题。

**Android 10 及以下：** 系统对私有 API 尚未完全封禁，`UnsafeUtil` 顺利获取到了 `Unsafe` 实例并启用快路径。随后运行时按照被 D8 损坏的偏移量读取内存，触发崩溃。

这也解释了为什么高版本系统正常、低版本系统崩溃：**高版本系统是因为被系统限制而"被动"走了安全路径，并非 Protobuf 4.x 在高版本上没有这个 bug。**

---

## 验证

为确认问题根源在构建链而非业务代码，我们做了一个对照实验：不改任何业务代码、协议定义和调用方式，仅在 AGP 7.1.3 工程中覆盖升级 R8 版本。

结果：Android 10 上的崩溃消失，Android 11+ 继续正常。

---

## 修复方案

对于暂时不能整体升级 AGP 大版本的工程，可以在维持 AGP 7.1.3 不变的前提下，单独覆盖其内置的 R8/D8 内核版本。

在根目录 `build.gradle` 中添加：

```gradle
buildscript {
    repositories {
        maven { url 'https://storage.googleapis.com/r8-releases/raw' }
        maven { url 'https://mirrors.huaweicloud.com/repository/maven/' }
        mavenCentral()
        google()
    }
    dependencies {
        classpath "com.android.tools.build:gradle:7.1.3"

        // 覆盖旧版 AGP 内置的 R8 / D8，3.3.75+ 已修复该字符串转码问题
        classpath "com.android.tools:r8:3.3.75"
    }
}
```

添加后重新编译，Protobuf 元数据字符串将被正确保留，Android 10 及以下设备的崩溃问题消除。

---

## 总结

| 环节 | 问题 |
|---|---|
| Protobuf 4.x 生成类 | 将 Schema 编码为含非标准 UTF-16 字节的字符串常量 |
| AGP 7.1.3 内置 D8 | 转换 `.class → .dex` 时对该字符串进行了错误的转码处理 |
| Unsafe 快路径 | 依赖被损坏的偏移量读取内存，得到 `null` |
| Android 10 及以下 | Unsafe 可正常获取，直接走快路径触发崩溃 |
| Android 11+ | Unsafe 被 Hidden API 限制拦截，Fallback 到标准反射，规避了问题 |

这个问题的特殊之处在于：**代码本身没有逻辑错误，也能正常编译，错误发生在构建链处理产物的阶段，且只在特定系统版本下暴露。** 对于 SDK 对外发布场景，构建工具链的版本兼容性同样属于需要纳入质量保障的环节。
