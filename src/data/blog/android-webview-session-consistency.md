---
author: DongLua
pubDatetime: 2025-12-23T21:00:00Z
title: Android WebView 拦截请求导致的会话不一致问题及解决方案
featured: false
draft: false
tags:
  - android
  - webview
  - okhttp
  - cookie
description: 解决 Android WebView 使用 shouldInterceptRequest 拦截请求时，因 OkHttp 和 WebView 的 Cookie 不同步导致的会话不一致问题。
---

## 背景

在 Android 开发中，为了优化网络请求，我们经常会在 WebView 中使用 `shouldInterceptRequest` 方法拦截请求，并替换为 OkHttp 来执行。这样做的好处是可以使用 HTTPDNS、统一的网络配置、请求日志等。

然而，如果只拦截部分请求（比如只拦截 GET 请求），就可能导致**会话（Session）不一致**的问题。

## 问题描述

典型的场景如下：

```
用户登录流程：
1. [GET] 加载登录页面 → 拦截走 OkHttp
2. [POST] 提交登录表单 → 走 WebView 原生
3. [GET] 获取用户信息 → 拦截走 OkHttp
```

问题出现在：
- OkHttp 收到的 `Set-Cookie` 响应头没有同步到 WebView 的 `CookieManager`
- WebView 设置的 Cookie 也可能没有同步到 OkHttp 的请求里

这就导致 GET 请求和 POST 请求使用的是不同的 Session，服务端自然就认不出你了。

## 问题代码

```kotlin
override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
    // 只拦截 GET 请求
    if ("GET".equals(request?.method, true)) {
        return getResponseByOkHttp(request)
    }
    return super.shouldInterceptRequest(view, request)
}

private fun getResponseByOkHttp(request: WebResourceRequest?): WebResourceResponse? {
    request ?: return null
    val url = request.url.toString()
    val requestBuilder = okhttp3.Request.Builder()
        .url(url)
        .method(request.method, null)
    
    // ❌ 问题1：直接使用 requestHeaders，未确认 Cookie 来源
    request.requestHeaders?.forEach { (key, value) ->
        requestBuilder.addHeader(key, value)
    }
    
    val response = okhttpClient.newCall(requestBuilder.build()).execute()
    
    // ❌ 问题2：响应中的 Set-Cookie 被直接丢弃了！
    
    val body = response.body ?: return null
    return WebResourceResponse(...)
}
```

## 解决方案

核心思路：**将 OkHttp 响应中的 `Set-Cookie` 同步到 WebView 的 `CookieManager`**。

### 修复后的代码

```kotlin
/**
 * 将响应中的 Set-Cookie 同步到 CookieManager
 */
private fun syncCookiesToManager(url: String, response: okhttp3.Response) {
    val cookies = response.headers("Set-Cookie")
    if (cookies.isNotEmpty()) {
        val cookieManager = android.webkit.CookieManager.getInstance()
        cookies.forEach { 
            Timber.d("syncCookiesToManager: $url -> $it")
            cookieManager.setCookie(url, it) 
        }
        cookieManager.flush()  // 确保立即持久化
    }
}

private fun getResponseByOkHttp(request: WebResourceRequest?): WebResourceResponse? {
    request ?: return null
    val url = request.url.toString()
    val requestBuilder = okhttp3.Request.Builder()
        .url(url)
        .method(request.method, null)
    
    // ✅ 直接使用 requestHeaders
    // WebView 在调用 shouldInterceptRequest 时已经从 CookieManager 获取了 Cookie
    request.requestHeaders?.forEach { (key, value) ->
        requestBuilder.addHeader(key, value)
    }
    
    val response = okhttpClient.newCall(requestBuilder.build()).execute()
    
    // ✅ 关键：同步响应中的 Cookie 到 CookieManager
    // 注意：要在判断状态码之前同步，因为 302 重定向也可能带 Set-Cookie
    syncCookiesToManager(url, response)
    
    if (response.code != 200) {
        response.close()
        return null
    }
    
    val body = response.body ?: return null
    // ... 构建 WebResourceResponse
}
```

### 关键点解释

1. **为什么只需要处理响应的 Cookie？**
   
   因为 `WebResourceRequest.requestHeaders` 已经包含了 WebView 从 `CookieManager` 获取的 Cookie。WebView 在调用 `shouldInterceptRequest` 之前，会自动把当前 URL 对应的 Cookie 放进 `requestHeaders` 里。

2. **为什么要在判断状态码之前同步 Cookie？**
   
   HTTP 302 重定向响应也可能携带 `Set-Cookie`。如果先判断状态码再同步，就会丢失这些 Cookie。

3. **`flush()` 的作用**
   
   `CookieManager.setCookie()` 是异步的，调用 `flush()` 可以确保 Cookie 立即持久化到磁盘，避免因为进程被杀而丢失。

## 验证方法

1. 在 `syncCookiesToManager` 添加日志，确认 Cookie 被正确同步
2. 测试登录流程：登录 → 刷新页面 → 确认用户状态保持
3. 测试验证码场景：获取验证码图片 → 提交验证码 → 确认校验通过

## 其他注意事项

### 不适合拦截的域名

某些第三方域名（如支付页面）可能有额外的安全校验，建议排除：

```kotlin
val FILTER_HOSTS = listOf(
    "qq.com",       // 腾讯
    "alipay.com",   // 支付宝
    // ...
)

private fun shouldInterceptToOkhttp(request: WebResourceRequest?): Boolean {
    val url = request?.url ?: return false
    if ("GET".equals(request.method, true)) {
        // 过滤掉不需要拦截的域名
        return FILTER_HOSTS.none { url.toString().contains(it) }
    }
    return false
}
```

### HTTPDNS 可能带来的问题

使用 HTTPDNS 会让请求直连 IP，但 HTTP 请求的 `Host` 头仍然是域名。某些服务端可能对 IP 和 Host 做额外校验，需要注意。

## 总结

WebView 请求拦截是把双刃剑。用得好可以优化网络性能，用不好就会导致各种诡异的会话问题。关键是要记住：

> **拦截了请求，就要接管 Cookie 同步的责任。**

希望这篇文章能帮助你少踩一个坑。
