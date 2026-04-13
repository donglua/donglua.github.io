---
layout: post
title: "Android 接入 vivo 应用商店智能分包（Install Referrer）实战指南"
date: 2026-04-13 09:30:00 +0800
categories: android
tags: [Android, vivo, Install Referrer, 广告归因, Kotlin]
---

> 本文基于 **智能分包开发文档 V3.0**，记录在 Android 项目中接入 vivo 智能分包的完整流程。

## 什么是智能分包

vivo 应用商店的「智能分包」功能，本质上是 Install Referrer 机制——当用户通过 vivo 广告投放渠道下载安装应用后，应用可以读取到这次安装对应的广告归因参数（渠道号、广告任务 ID、创意 ID 等），用于广告效果归因和 oCPX 回传。

**核心特性：** 智能分包参数在安装后不会变化，读取一次缓存即可。

## 接入方案选择

vivo 提供了两种读取方式：

| 方案 | 实现方式 | 推荐度 |
|:---|:---|:---|
| AIDL | 绑定 `com.bbk.appstore.CHANNEL_SERVICE` 服务 | 一般 |
| **ContentProvider** | 调用 `content://com.bbk.appstore.provider.appstatus` | **推荐** ✅ |

ContentProvider 方案代码更简洁，无需管理 ServiceConnection 生命周期，本文采用此方案。

## 数据流转全景

```
vivo 应用商店
    │
    ▼ ContentProvider.call("read_channel")
    │
channelValue = {"code": 0, "value": "{...}"}
    │
    ▼ code == 0 → 取 "value" 字段
    │
value = {
    "referrer_click_timestamp_seconds": "1658541060088",
    "install_referrer": "task_id%3Dxxx%26channel_id%3Dxxx%26...",
    "package_name": "com.example.app",
    "vivo_ext_referrer": "BdAwWkj..."
}
    │
    ▼ 直接回传完整 JSON 给服务端（无需额外处理）
```

## 核心实现（Kotlin）

```kotlin
object VivoChannelDetector {

    private const val PROVIDER_URI = "content://com.bbk.appstore.provider.appstatus"

    /**
     * 读取 vivo 智能分包参数
     * @return 智能分包 value JSON 字符串，失败返回 null
     */
    fun readChannel(context: Context, packageName: String): String? {
        // 优先从本地缓存读取（智能分包安装后不会变化）
        val cached = readFromCache(context)
        if (!cached.isNullOrEmpty()) return cached

        try {
            val inputBundle = Bundle().apply {
                putString("package_name", packageName)
            }
            val bundle = context.contentResolver.call(
                Uri.parse(PROVIDER_URI),
                "read_channel",
                null,
                inputBundle
            )
            if (bundle != null) {
                val channelValue = bundle.getString("channelValue")
                if (!channelValue.isNullOrEmpty()) {
                    val json = JSONObject(channelValue)
                    val code = json.optInt("code")
                    if (code == 0) {
                        val value = json.optString("value")
                        // 读取成功，存入本地缓存
                        saveToCache(context, value)
                        return value
                    } else {
                        Log.w(TAG, "code=$code, message=${json.optString("message")}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "readChannel failed", e)
        }
        return null
    }
}
```

### 调用示例

获取到的 `value` 是完整的智能分包参数 JSON，**可以直接回传给服务端，不需要额外处理**：

```kotlin
val value = VivoChannelDetector.readChannel(context, context.packageName)
if (value != null) {
    // 直接回传完整 JSON 给服务端
    api.uploadReferrer(value)
}
```

如果客户端需要提取特定字段（如渠道号），可以进一步解析 `install_referrer`——它是 URL 编码的 query string：

```kotlin
val json = JSONObject(value)
val referrer = URLDecoder.decode(json.optString("install_referrer"), "UTF-8")
// 解码后: task_id=xxx&channel_id=appstore_001&request_id=xxx&ad_id=xxx&ext_info=xxx

val params = referrer.split("&")
    .mapNotNull { it.split("=", limit = 2).takeIf { kv -> kv.size == 2 } }
    .associate { it[0] to it[1] }

val channelId = params["channel_id"]  // 渠道号
val taskId = params["task_id"]        // 任务 ID
val extInfo = params["ext_info"]      // oCPX 回传参数
```

## 返回字段说明

`readChannel` 返回的 `value` 是一个 JSON 字符串，包含以下字段：

| 字段 | 含义 | 示例 |
|:---|:---|:---|
| `referrer_click_timestamp_seconds` | 广告点击时间戳（毫秒） | `"1658541060088"` |
| `install_referrer` | 智能分包参数（URL 编码） | `"task_id%3Dxxx%26channel_id%3Dxxx%26..."` |
| `package_name` | 应用包名 | `"com.example.app"` |
| `vivo_ext_referrer` | vivo 广告补充参数 | `"BdAwWkj..."` |

`install_referrer` URL 解码后包含以下子字段：

| 子字段 | 含义 | 用途 |
|:---|:---|:---|
| `channel_id` | 广告任务绑定的智能分包渠道号 | 渠道归因 |
| `task_id` | 广告任务 ID | 任务追踪 |
| `request_id` | 广告请求 ID | 请求追踪 |
| `ad_id` | 广告创意 ID | 创意分析 |
| `ext_info` | 回传参数 | oCPX 对接 |

## 参考资料

- [vivo 营销平台 - 帮助中心](https://ad.vivo.com.cn/help?id=497)
- [智能分包开发文档 V3.0（PDF）](https://ads-marketing-vivofs.vivo.com.cn/NtBrJ9dueygDLoz8/admin/af4ab17d-cdf2-4a1c-9260-2a58551b85a0.pdf)
