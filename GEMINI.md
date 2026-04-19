# Jekyll Blog Project Context

## 1. 项目概览 (Project Overview)
这是 Donglu (DL) 的个人技术博客。基于 [Jekyll](https://jekyllrb.com/) (Ruby 静态网站生成器) 构建，使用默认的 `minima` 主题，通过 Markdown 文件生成静态页面。

- **主要语言:** Ruby, Markdown, HTML, YAML
- **框架版本:** Jekyll ~> 4.4.1
- **使用主题:** minima
- **使用插件:** jekyll-feed, nokogiri, mermaid_processor.rb (自定义插件)

## 2. 核心行为准则 (Core Directives)

### 2.1 写作风格
- **硬核技术风**：行文简洁客观。避免夸张营销用语和过多 emoji，保持清晰干练的技术叙述。
- **逻辑严密**：文章结构必须具备强逻辑性。通常遵循「问题现象 → 根本原因 → 解决方案 → 原理扩展/总结」的金字塔结构，层层递进。
- **精炼准确**：结论要一针见血，避免啰嗦和无关紧要的发散。如果问题出在特定场景/特定前置条件，必须在开篇明确指出，不泛泛而谈。
- **写作目标优先级**：准确先于修辞，清晰先于热闹，可扫读先于堆砌解释。

### 2.2 语气规范
- 使用克制、直接、可执行的中文；以说明、界定、引导为主，不用夸张宣传语。
- 不使用第二人称（`你`、`您`、`同学`），如无必要不直接点名读者，用无主句或说明句即可。
- 避免问候式开场（`Hello`、`Hi`）和口号式抽象表达。
- **禁用黑话词**（除非该词在当前语境中有严格业务定义）：`赋能`、`抓手`、`闭环`、`沉淀`、`对齐`、`对标`、`拉通`、`打通`、`协同`、`联动`、`洞察`、`赛道`、`心智`、`调性`、`战役`、`链路`、`势能`、`兜底`。
  - 优先替换为更具体表达：`赋能` → `提供`，`抓手` → `关键措施`，`闭环` → `完整流程`，`对齐` → `统一`，`兜底` → `保障机制`。

### 2.3 标点规范
- 中文引号统一使用直角引号：`「」`，不使用中文双引号 `""`。
- 正文中避免连续使用多个感叹号、省略号、宣传口号式断句；避免使用感叹号。

### 2.4 中英文留白
在可见正文中，中文与半角英文单词、英文缩写、独立数字和版本号之间保留空格，提高可读性。

- 正确：`获取批量 ID`、`HTTP 请求`、`版本 2.0`、`AI 服务`
- **不要**对以下内容机械加空格：行内代码块、JSON 键名、URL、API 路径、数据库字段名。
  - 例：`user_id`、`/api/example`、`statusCode` 保持原样。

### 2.5 术语大小写归一
仅对可见正文中的自然语言短语做归一，不作用于代码、路径、字段和配置项字面量。

| 错写 | 推荐 |
|------|------|
| `id` / `Id` | `ID` |
| `http` / `Http` | `HTTP` |
| `url` / `Url` | `URL` |
| `json` / `Json` | `JSON` |
| `api` / `Api` | `API` |
| `yaml` / `Yaml` | `YAML` |
| `java` | `Java` |
| `kotlin` | `Kotlin` |
| `python` | `Python` |
| `ruby` | `Ruby` |
| `swift` | `Swift` |
| `dart` | `Dart` |
| `javascript` / `JS` | `JavaScript` |
| `typescript` | `TypeScript` |
| `go`（语言名） | `Go` |
| `sql` | `SQL` |
| `bash` | `Bash` |
| `github` | `GitHub` |
| `docker` | `Docker` |
| `redis` | `Redis` |
| `mysql` | `MySQL` |
| `grpc` | `gRPC` |
| `graphql` | `GraphQL` |
| `websocket` | `WebSocket` |
| `H5`（移动 Web 页面） | `移动 Web 页面` |

### 2.6 中文易错词表
| 错误写法 | 正确写法 |
|----------|----------|
| `阀值` | `阈值` |
| `登陆系统` | `登录系统` |
| `布署` | `部署` |
| `配制参数` | `配置参数` |
| `回朔` | `回溯` |
| `标示字段` | `标识字段` |
| `帐户`（金融语境） | `账户` |
| `帐号`（平台用户语境） | `账号` |
| `做为` | `作为` |
| `截止 X 日` | `截至 XXXX 年 X 月 X 日` |
| `缩小了 3 倍` | `缩小到原来的 1/3` |
| `翻了 1 倍` | `变为原来的 2 倍` |
| `不超过 100 以上` | `不超过 100` |

### 2.7 内容规范
- 除非有特殊要求，文章内容及代码注释请优先使用简体中文。

### 2.8 文章创建规范
- 新文章必须存放在 `_posts/` 目录下，文件命名格式必须为 `YYYY-MM-DD-title.md`。
- 必须在文件顶部使用 YAML Front Matter 指定 `layout`、`title` 等元数据。

### 2.9 排版与结构规则
- 一个段落只承载一个主要信息点。
- 长句可以保留，但避免连续堆叠两个以上长句。
- 列表项要平行，不要有的写定义、有的写宣传、有的写结论。
- 标题要能反映用途，不要只写抽象名词。

### 2.10 最终检查清单
交付文章前检查：

- [ ] 是否出现 `你`、`您`、`同学`
- [ ] 是否出现中文双引号 `""`（应改为直角引号 `「」`）
- [ ] 中文与英文、数字之间是否需要留白
- [ ] 是否存在禁用黑话词
- [ ] 是否存在过强的宣传口吻或感叹号
- [ ] 文案是否便于扫读
- [ ] 术语大小写是否归一

## 3. 构建与运行 (Building and Running)
本项目使用 Bundler 管理 Ruby gem 依赖。每次执行 Jekyll 相关命令前，必须使用 `bundle exec` 以确保使用正确的 gem 版本。

- **安装依赖:**
  ```bash
  bundle install
  ```
- **本地开发服务器运行:**
  ```bash
  bundle exec jekyll serve --livereload
  ```
  *(注：开启 livereload 会自动刷新，但修改 `_config.yml` 后需要重启服务器)*
- **构建静态站点:**
  ```bash
  bundle exec jekyll build
  ```
  *(生成的静态文件会存放在 `_site/` 目录下)*

## 4. 项目结构 (Project Structure)
- `_config.yml`: 站点全局配置 (title, url, theme, plugins 等)。
- `Gemfile` / `Gemfile.lock`: Ruby 依赖管理文件。
- `_posts/`: Markdown 格式的博客文章存放目录。
- `_layouts/`: 自定义 HTML 布局模板 (如 `post.html`)。
- `_includes/`: 可复用的 HTML 代码片段 (如 `google-analytics.html`, `mermaid.html`)。
- `_plugins/`: 自定义 Ruby 插件 (如用于渲染 Mermaid 图表的 `mermaid_processor.rb`)。
- `_site/`: 生成的静态站点目录 (已被 Git 忽略)。
- `.github/workflows/jekyll.yml`: 用于自动化构建和部署的 GitHub Actions 工作流。

## 5. 特定功能 (Specific Features)
- **Mermaid 支持:** 站点内置了对 Mermaid 的支持。通过 `_plugins/mermaid_processor.rb` 和 `_includes/mermaid.html` 渲染图表，在编写 Markdown 时可直接使用 mermaid 语法块。