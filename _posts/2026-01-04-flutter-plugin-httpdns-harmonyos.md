---
layout: post
title: "Flutter 插件适配鸿蒙：阿里云 HTTPDNS SDK 集成实践"
date: 2026-01-04 11:00:00 +0800
categories: flutter harmonyos
tags: flutter harmonyos httpdns aliyun plugin
---

随着 HarmonyOS NEXT 的发展，越来越多的 Flutter 应用需要适配鸿蒙平台。本文记录了将阿里云 HTTPDNS Flutter 插件 (`aliyun_httpdns`) 适配到 HarmonyOS 的完整过程，包括遇到的问题和解决方案。

## 背景

阿里云 HTTPDNS 是一款基于 HTTP 协议的域名解析服务，能够有效防止 DNS 劫持、提升解析速度。官方已提供 Android、iOS 和 HarmonyOS 原生 SDK，但 Flutter 插件尚未支持 HarmonyOS 平台。

## 技术架构

```
┌─────────────────────────────────────────────────────┐
│                    Flutter App                       │
├─────────────────────────────────────────────────────┤
│              aliyun_httpdns (Dart)                  │
│                 MethodChannel                        │
├──────────┬──────────────┬───────────────────────────┤
│ Android  │     iOS      │        HarmonyOS          │
│ Kotlin   │    Swift     │         ArkTS             │
├──────────┼──────────────┼───────────────────────────┤
│ 阿里云   │   阿里云     │        阿里云             │
│ SDK      │    SDK       │    @aliyun/httpdns       │
└──────────┴──────────────┴───────────────────────────┘
```

## 实现步骤

### 1. 配置 pubspec.yaml

在插件的 `pubspec.yaml` 中添加 HarmonyOS 平台支持：

```yaml
flutter:
  plugin:
    platforms:
      android:
        package: com.aliyun.ams.httpdns
        pluginClass: AliyunHttpDnsPlugin
      ios:
        pluginClass: AliyunHttpDnsPlugin
      ohos:
        package: com.aliyun.ams.httpdns
        pluginClass: AliyunHttpDnsPlugin
```

### 2. 创建 ohos 目录结构

```
ohos/
├── src/main/
│   ├── ets/components/plugin/
│   │   └── AliyunHttpDnsPlugin.ets
│   └── module.json5
├── oh-package.json5
├── build-profile.json5
├── hvigorfile.ts
└── index.ets
```

### 3. 配置依赖 (oh-package.json5)

```json5
{
  "name": "aliyun_httpdns",
  "version": "1.0.0",
  "description": "Aliyun HTTPDNS Flutter plugin for HarmonyOS",
  "main": "index.ets",
  "author": "",
  "license": "Apache-2.0",
  "dependencies": {
    "@aliyun/httpdns": "^1.2.2"
  }
}
```

### 4. 实现插件核心代码

```typescript
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/...';
import { httpdns, HttpDnsConfig, IHttpDnsService, IpType } from '@aliyun/httpdns';

export default class AliyunHttpDnsPlugin implements FlutterPlugin, MethodCallHandler {
  private httpDnsService: IHttpDnsService | null = null;

  private async initialize(args: ESObject, result: MethodResult): Promise<void> {
    // 解析参数
    let accountId: string | undefined;
    if (args instanceof Map) {
        if (args.has('accountId')) accountId = args.get('accountId') as string;
    } else {
        if (args['accountId']) accountId = args['accountId'] as string;
    }

    // 配置服务
    const config: HttpDnsConfig = { useHttps: true };
    httpdns.configService(accountId, config);
    
    // 获取服务实例
    const service = await httpdns.getService(accountId);
    this.httpDnsService = service;
    result.success(true);
  }

  private async resolveHost(args: ESObject, result: MethodResult): Promise<void> {
    const hostname = args['hostname'] as string;
    const dnsResult = await this.httpDnsService.getHttpDnsResultAsync(hostname, IpType.Both);
    result.success({
      "ipv4": dnsResult?.ipv4s || [],
      "ipv6": dnsResult?.ipv6s || []
    });
  }
}
```

## 遇到的问题与解决方案

### 问题 1：MissingPluginException

**现象**：调用插件方法时抛出 `MissingPluginException`

**原因**：HarmonyOS Flutter 插件未自动注册

**解决方案**：在 Example 应用的 `GeneratedPluginRegistrant.ets` 中手动注册：

```typescript
import AliyunHttpDnsPlugin from 'aliyun_httpdns';

export default class GeneratedPluginRegistrant {
  static registerWith(bindingBase: FlutterPluginBinding) {
    bindingBase.getFlutterEngine().getPlugins().add(new AliyunHttpDnsPlugin());
  }
}
```

### 问题 2：ArkTS 类型检查错误

**现象**：`Record<string, any>` 类型报错

**原因**：ArkTS 严格模式不允许 `any` 类型

**解决方案**：使用 `ESObject` 替代 `any`，并使用 `instanceof Map` 检测参数类型：

```typescript
private async initialize(args: ESObject, result: MethodResult): Promise<void> {
  if (args instanceof Map) {
      // Map 类型处理
  } else {
      // Object 类型处理
  }
}
```

### 问题 3：字节码 HAR 兼容性问题

**现象**：编译报错 `Specification Limit Violation`

**原因**：阿里云 SDK 的 `.har` 文件需要特定编译配置

**解决方案**：在 `build-profile.json5` 中启用：

```json5
{
  "app": {
    "products": [{
      "buildOption": {
        "strictMode": {
          "useNormalizedOHMUrl": true
        }
      }
    }]
  }
}
```

### 问题 4：参数解析为 undefined

**现象**：`hostname` 和 `ipType` 参数为 `undefined`

**原因**：Flutter 传递的参数可能是 `Map` 对象，而非普通 `Object`

**解决方案**：同时处理两种情况：

```typescript
if (args instanceof Map) {
    if (args.has('hostname')) hostname = args.get('hostname') as string;
} else {
    if (args['hostname']) hostname = args['hostname'] as string;
}
```

### 问题 5：同步解析返回空结果

**现象**：`getHttpDnsResultSyncNonBlocking` 首次调用返回空

**原因**：非阻塞方法在缓存未命中时立即返回空结果

**解决方案**：改用异步方法 `getHttpDnsResultAsync`：

```typescript
const dnsResult = await this.httpDnsService.getHttpDnsResultAsync(hostname, ipType);
```

## 平台差异处理

| 功能 | Android | iOS | HarmonyOS |
|------|---------|-----|-----------|
| accountId 类型 | int/String | Int | String |
| useHttps 配置 | setHttpsRequestEnabled | setHTTPSRequestEnabled | configService.useHttps |
| 日志开关 | HttpDnsLog.enable() | setLogEnabled() | httpdns.enableHiLog() |

## 总结

本次适配工作涉及：
- Flutter 插件 HarmonyOS 平台配置
- ArkTS 类型系统适配
- 阿里云 HTTPDNS SDK 集成
- 跨平台 API 差异处理

HarmonyOS Flutter 插件开发与 Android/iOS 有一些差异，主要体现在：
- 类型系统更严格（ArkTS）
- 参数传递方式不同（Map vs Object）
- SDK API 略有差异

通过本文的实践，相信读者可以更顺利地适配其他 Flutter 插件到 HarmonyOS 平台。
