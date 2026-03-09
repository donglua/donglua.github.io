---
layout: post
title: "为 Jekyll 博客接入 Giscus 评论系统"
date: 2026-03-09
---

静态博客天然不具备评论功能，常见的解决方案是引入第三方评论系统。本文记录为 Jekyll 博客接入 [Giscus](https://giscus.app/) 的完整过程。

## 为什么选择 Giscus

评论系统主要有以下几类选择：

- **Disqus**：老牌产品，但免费版有广告，数据在第三方服务器上。
- **Utterances**：基于 GitHub Issues，轻量，但接口功能有限。
- **Giscus**：基于 GitHub Discussions，功能更完整，支持回复和表情，无广告，数据完全在自己的仓库。

对于技术博客而言，Giscus 是目前最合适的选择：读者本来就有 GitHub 账号，数据自己掌控，界面简洁无广告。

## Giscus 工作原理

Giscus 的核心思路是**把博客评论托管在 GitHub Discussions 中**，整个链路如下：

1. 在博客页面嵌入一个跨域 `<iframe>`，iframe 内运行 Giscus 的前端程序。
2. 读者点击"登录"后，通过 GitHub OAuth 授权 Giscus 代替其发表评论。
3. Giscus 通过 GitHub GraphQL API 读写仓库的 Discussions 内容。
4. 每篇文章根据 URL `pathname` 匹配对应的 Discussion 帖子；第一次有人评论时，Giscus Bot 会自动在仓库创建该帖子。

没有独立数据库，GitHub 仓库就是数据库。

## 接入步骤

### 1. 准备 GitHub 仓库

确保博客所在的 GitHub 仓库满足以下条件：

- **可见性**：Public（公开仓库）
- **开启 Discussions**：进入仓库 `Settings` → `Features` → 勾选 `Discussions`

### 2. 安装 Giscus App

访问 [github.com/apps/giscus](https://github.com/apps/giscus)，点击 `Install`，授权到博客仓库。

### 3. 获取配置参数

访问 [giscus.app](https://giscus.app/zh-CN)，填写仓库信息（如 `username/repo`），选择 Discussion 分类（推荐 `Announcements`），页面底部会生成完整的 `<script>` 代码，其中包含以下关键参数：

- `data-repo-id`：仓库的 GraphQL Node ID
- `data-category-id`：Discussion 分类的 Node ID

### 4. 创建 include 文件

新建 `_includes/giscus.html`，将生成的脚本粘贴进去：

```html
<script src="https://giscus.app/client.js"
        data-repo="username/repo"
        data-repo-id="YOUR_REPO_ID"
        data-category="Announcements"
        data-category-id="YOUR_CATEGORY_ID"
        data-mapping="pathname"
        data-strict="0"
        data-reactions-enabled="1"
        data-emit-metadata="0"
        data-input-position="top"
        data-theme="preferred_color_scheme"
        data-lang="zh-CN"
        crossorigin="anonymous"
        async>
</script>
```

`data-theme="preferred_color_scheme"` 会自动跟随系统深色/浅色模式切换，无需额外处理。

### 5. 在文章布局中引入

编辑 `_layouts/post.html`，在文章内容后面加入：

{% raw %}
```html
{%- if site.giscus.repo -%}
{%- include giscus.html -%}
{%- endif -%}
```
{% endraw %}

用 `site.giscus.repo` 作为开关，方便在 `_config.yml` 中统一控制。

### 6. 添加配置项

在 `_config.yml` 中新增：

```yaml
giscus:
  repo: username/repo
```

只需此一行即可启用。若要临时关闭评论，删除这两行即可，无需改动模板文件。

## 效果

部署后，每篇文章底部会出现 Giscus 评论框。第一条评论发布后，即可在 GitHub 仓库的 Discussions 页面看到对应帖子，评论完全可以在 GitHub 侧管理。
