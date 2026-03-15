---
layout: post
title: "Android WebView 拦截请求导致的会话不一致问题及解决方案"
date: 2025-12-23 21:00:00 +0000
categories: android webview
tags: android webview okhttp cookie
---

---
layout: post
title: "Android WebView 拦截请求导致的会话不一致问题及解决方案"
date: 2025-12-23 21:00:00 +0000
categories: android webview
tags: android webview okhttp cookie
---

## 问题现象

在 Android 开发中，常通过重写 WebView 的 `shouldInterceptRequest` 方法，使用自定义网络栈（如 OkHttp）来接管部分资源请求（例如仅拦截 GET 请求以使用 HTTPDNS 或统一缓存）。

这种**部分拦截**的策略极易引发一个严重问题：**会话（Session）不一致**。
用户在登录后（原生网络栈 POST 请求），后续页面依然处于未登录状态；或图形验证码校验始终不过。

## 根本原因

会话不一致的根本原因是：**原生 WebView 的 `CookieManager` 与第三方网络库（OkHttp）的 Cookie 存储相互隔离且未同步。**

```
用户登录流程的时序割裂：
1. [GET] 加载登录页面 → 被拦截，走 OkHttp 请求
2. [POST] 提交登录表单 → 未被拦截，走 WebView 原生请求，服务端返回 Set-Cookie
3. [GET] 获取用户信息 → 被拦截，走 OkHttp 请求
```

- WebView 原生请求收到的 `Set-Cookie` 会保存在 `CookieManager` 中。
- 后续拦截走 OkHttp 的请求，如果没有提取并携带 `CookieManager` 中的 Cookie，或者 OkHttp 响应的 `Set-Cookie` 没有反向同步给 `CookieManager`，两套网络栈使用的就是不同的 Session 标识。

## 解决方案

核心思路：**在拦截逻辑中，充当 Cookie 的双向同步桥梁。**

> 注：`WebResourceRequest.requestHeaders` 在调用 `shouldInterceptRequest` 时，系统已经自动从 `CookieManager` 注水了最新的 Cookie，因此只需要关注**响应后**的 Cookie 回写。

在拦截实现中增加响应后的 Cookie 同步逻辑：

```kotlin
private fun getResponseByOkHttp(request: WebResourceRequest?): WebResourceResponse? {
    request ?: return null
    val url = request.url.toString()
    val requestBuilder = okhttp3.Request.Builder()
        .url(url)
        .method(request.method, null)
    
    // 1. 携带 WebView 已有的 Cookie (系统已注入到 requestHeaders)
    request.requestHeaders?.forEach { (key, value) ->
        requestBuilder.addHeader(key, value)
    }
    
    val response = okhttpClient.newCall(requestBuilder.build()).execute()
    
    // 2. 关键：同步响应头中的 Set-Cookie 到 WebView的 CookieManager
    // 必须在判断状态码之前同步，以防 302 重定向丢失 Cookie
    syncCookiesToManager(url, response)
    
    if (response.code != 200) {
        response.close()
        return null
    }
    
    val body = response.body ?: return null
    // 构建并返回 WebResourceResponse...
}

/**
 * 将 OkHttp 响应中的 Set-Cookie 写入 CookieManager
 */
private fun syncCookiesToManager(url: String, response: okhttp3.Response) {
    val cookies = response.headers("Set-Cookie")
    if (cookies.isNotEmpty()) {
        val cookieManager = android.webkit.CookieManager.getInstance()
        cookies.forEach { 
            cookieManager.setCookie(url, it) 
        }
        cookieManager.flush()  // 确保立即持久化到本地，防止进程被杀导致丢失
    }
}
```

## 扩展建议

**1. 过滤第三方域名**
并非所有请求都适合拦截。涉及第三方支付、授权的网页，建议通过白名单/黑名单机制过滤，让原生 WebView 自行处理，避免引发未知的安全或跨域 Cookie 异常。

**2. HTTPDNS 附带效应**
使用 HTTPDNS 替换域名为 IP 后发起请求，其真实的 `Host` 头需要手动补全，否则可能触发 CDN 阻断或服务端 Host 校验严格环境下的 400 错误。

## 小结

WebView 请求拦截是优化利器，但**拦截了请求，就必须完整接管并维护 HTTP 的状态机（Cookie/Session）**。构建稳定的双向 Cookie 同步机制，是此类架构落地的必修课。
