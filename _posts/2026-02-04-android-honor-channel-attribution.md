---
layout: post
title:  "Android 接入荣耀应用市场广告归因指南"
date:   2026-02-04 17:35:00 +0800
categories: [技术, Android]
tags: [荣耀, 广告归因, Honor, Android]
---

随着荣耀（Honor）品牌独立，其应用市场的广告归因逻辑也与华为（Huawei）发生了分离。对于开发者而言，在适配荣耀设备时，不能简单复用原有的华为归因代码（如 `InstallReferrer` 或 `ContentProvider`），需要接入荣耀专属的归因查询接口。

本文将介绍如何在 Android 应用中接入荣耀应用市场的广告归因功能，帮助开发者准确获取推广渠道和转化数据。

## 背景

在进行荣耀渠道推广时，App 需要通过荣耀应用市场提供的 `ContentProvider` 接口查询下载归因信息（如广告计划 ID、创意 ID 等）。这些数据对于后续的效果评估和转化回传（Conversion Tracking）至关重要。

## 接入步骤

荣耀归因的核心是通过 `ContentResolver` 查询特定的 `Uri`，并解析返回的 `Cursor` 数据。

### 1. 核心常量定义

荣耀归因的 Uri 固定为：`content://com.hihonor.appmarket.commondata/item/wisepackage`。
我们需要关注的关键数据是 `wise_params`，它通常位于 Cursor 的第 4 列（索引为 3）。

```kotlin
private const val PROVIDER_URI = "content://com.hihonor.appmarket.commondata/item/wisepackage"
private const val INDEX_WISE_PARAMS = 3 // 归因参数在 Cursor 中的索引
```

### 2. 归因检测器实现

我们可以封装一个单例对象 `HonorChannelDetector`，专门负责查询和解析荣耀的归因数据。

返回的 `wise_params` 是一个 JSON 格式的字符串，包含以下关键字段：
*   **`itgSctChannel`**: 智能分包渠道号（我们在荣耀广告后台绑定的渠道标识）。
*   **`trackId`**: 点击事件追踪 ID，用于回传转化。
*   **`callback`**: 归因回传地址。

**代码示例**：

```kotlin
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.text.TextUtils
import android.util.Log // 或使用你的日志工具
import org.json.JSONException
import org.json.JSONObject

object HonorChannelDetector {
    private const val TAG = "HonorChannelDetector"
    private const val PROVIDER_URI = "content://com.hihonor.appmarket.commondata/item/wisepackage"
    private const val INDEX_WISE_PARAMS = 3

    /**
     * 查询荣耀归因数据
     * @return Triple(channelCode, taskId, callback)
     */
    fun getTrackId(context: Context): Triple<String, String, String> {
        val packageName = arrayOf(context.packageName)
        
        var channelCode = ""
        var taskId = ""
        var callback = ""

        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(
                Uri.parse(PROVIDER_URI),
                null, null, packageName, null
            )
            
            if (cursor != null && cursor.moveToFirst()) {
                // 读取 wise_params 字段
                val wiseParams = cursor.getString(INDEX_WISE_PARAMS)
                Log.i(TAG, "Honor wiseParams: $wiseParams")
                
                if (!TextUtils.isEmpty(wiseParams)) {
                    try {
                        val json = JSONObject(wiseParams)
                        // 解析关键字段
                        // itgSctChannel: 智能分包渠道号
                        if (json.has("itgSctChannel")) {
                            channelCode = json.getString("itgSctChannel")
                        }
                        
                        // trackId: 点击事件 trackId
                        if (json.has("trackId")) {
                            taskId = json.getString("trackId")
                        }
                        
                        // callback: 广告主回传转化地址
                        if (json.has("callback")) {
                            callback = json.getString("callback")
                        }
                        
                    } catch (e: JSONException) {
                        Log.e(TAG, "Honor wiseParams json parse error", e)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Honor getTrackId failed", e)
        } finally {
            cursor?.close()
        }

        return Triple(channelCode, taskId, callback)
    }
}
```

## 常见问题与注意事项

1.  **Cursor 判空与包含性检查**:
    查询返回的 Cursor 可能为 `null`，或者行数为空，务必进行 `cursor != null && cursor.moveToFirst()` 检查。
    
2.  **数据时效性**:
    荣耀端侧存储的归因信息有有效期（通常为 90 天，付费推广 trackId 可能更短）。如果用户安装很久后才打开 App，或者清除了应用市场缓存，可能无法查询到数据。

3.  **调试建议**:
    *   在荣耀开发者后台创建测试用的“智能分包”和“广告计划”。
    *   通过广告链接下载并安装测试包。
    *   观察 Logcat 输出，确保 `wise_params` 能被正确解析。

## 参考文档

*   [荣耀开发者服务平台 - 归因回传对接](https://developer.hihonor.com/) (请参考官方最新文档)

---
*本文代码仅供参考，请根据实际项目需求进行调整。*
