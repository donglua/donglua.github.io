---
layout: post
title: "把蓝湖验收写成 Prompt：一套可复用的 UI 审核提示词"
date: 2026-05-15 14:00:00 +0800
categories: [技术, AI]
tags: [Lanhu, UI, Design Token, Android, Flutter, HarmonyOS, AI Agent]
description: "蓝湖稿还原不应停留在截图比对。更可靠的做法，是先固定设计版本和坐标空间，再用台账约束边界、间距、背景、颜色、资产与运行态验证，让 AI 的 UI 审核结论可追溯。"
---

蓝湖稿还原交给 AI 时，常见失败点不是模型不会看图，而是 Prompt 太像一句口头需求：检查一下还原是否正确、哪里不一样、帮忙改成和设计稿一致。

这类 Prompt 缺少两个关键约束。第一，设计节点、版本和坐标空间没有固定，后续的数字就无法复查；第二，验收只看截图或单个 `margin`，没有追踪背景、模块共边、列表空态、运行态图片和分割线的真正 owner。

这篇文章的主张是：蓝湖验收要交给 AI 稳定执行，重点不是把 Prompt 写得更长，而是把它变成一条有证据门槛的流程。先固定设计规格，再建立页面级和组件级台账；补丁只改台账确认的 owner；最后把构建产物带回真实路由和目标状态验证。缺少运行态截图时，最多只能报告 `IMPLEMENTED`，不能写成「已与蓝湖一致」。

下面的 Prompt 按这个顺序组织：请求范围与证据等级、设计身份与坐标、页面盒模型、横向边界、绝对纵向坐标、模块间距、列表和文字契约、颜色与资源、补丁前后审查。

---

## 先确定请求模式

同一套 Prompt 可能用于只读审查、实际修复或提交前收尾，三种模式的权限不同：

| 请求模式 | 常见说法 | 本轮允许的动作 |
|---|---|---|
| `review` | 看下、核对、审查、有没有问题 | 只读审查和列出问题，不改代码、不提交 |
| `implement` | 改、修复、按设计稿还原 | 审查、修改目标范围并验证，不自动提交 |
| `commit` | commit、提交此次改动 | 完成修改和验证后，只提交明确范围的文件 |

先写清模式，能避免「先改了再补证据」或把源码检查误报成运行态完成。

## 使用方式

先准备四类输入：

| 输入 | 说明 |
|---|---|
| 设计来源 | 蓝湖设计节点名、稳定 `id`、版本或 `updateTime`、页面状态、主题、Tab、结构化 `HTML/CSS/tokens/layout/layers` |
| 代码范围 | 页面入口、布局文件、组件文件、列表模型、图片加载代码 |
| 目标平台 | Android View、Flutter、HarmonyOS ArkUI 或其他 UI 框架 |
| 当前问题 | 例如边距偏大、底色不对、标签不居中、图片边框异常 |

然后按顺序投喂 Prompt。不要一次要求 AI 同时修所有问题。先让 AI 固定设计身份并产出台账，再根据台账做窄范围补丁。

对蓝湖工具，入口顺序固定为：

```text
lanhu_design(mode="list", url={蓝湖设计 URL})
lanhu_design(
  mode="analyze",
  design_names={已固定的设计名称或 id},
  include=["html", "tokens", "layout", "layers", "image"],
  url={蓝湖设计 URL}
)
```

`list` 的结果只用于发现设计名称，不能把可变的列表索引当作最终身份。`analyze` 返回 `status=success` 也不代表所有数据齐全，需要分别标记身份、几何、层级、字体颜色、资产和视觉参考是 `complete`、`partial` 还是 `missing`。缺失的证据域只能降低结论范围，不能用附近页面或截图猜补。

如果某个证据域为空，先用固定的 design id 或名称重试一次；仍缺失时，再用专门的 `tokens`/`slices` 模式、旧版 Lanhu 工具或当前本地导出补齐。所有补齐来源和仍缺失的部分都要写进报告，不能把传输成功当成规格完整。

## 证据等级

把结论分级，能让源码、产物和设备截图各自承担清晰的责任：

| 结论 | 最低证据 |
|---|---|
| `ANALYZED` | 已固定设计 `id`/版本，并比较了实际代码入口 |
| `IMPLEMENTED` | 目标 diff 和相关源码、构建或测试检查通过 |
| `ARTIFACT_VERIFIED` | 最终 APK、AAB、HAP 或 Web bundle 已确认包含目标资源或代码 |
| `RUNTIME_VERIFIED` | 在匹配的设备或浏览器上进入真实路由，覆盖目标状态并留存截图 |
| `MATCHES_LANHU` | 运行态截图与固定版本设计做了同坐标空间的测量比较，所有适用审查门槛通过 |

`MATCHES_LANHU` 是验收结论，不是源码构建的同义词。设备、浏览器或设计数据不可用时，文章中的最终 Prompt 必须报告缺失证据和实际停留等级。

---

## Prompt 0：固定设计身份和坐标空间

所有几何台账都依赖同一个坐标系。这个 Prompt 放在其他 Prompt 之前，先把设计版本、返回数据和测量单位锁定。

```text
任务：固定本次 UI 审查的设计身份、证据完整性和坐标空间。

输入：
- 蓝湖 URL：{URL}
- 设计名称或节点：{名称 / 节点}
- 页面状态：{主题 / Tab / 数据态 / 空态 / 加载态}
- 当前代码入口：{Activity、Fragment、页面组件、布局或 provider}
- 目标平台：{Android View / Flutter / HarmonyOS ArkUI}

执行：
1. 先调用 lanhu_design(mode="list", url=...)，记录精确 design name、稳定 id、latest_version、updateTime。
2. 再调用 lanhu_design(mode="analyze", design_names=..., include=["html", "tokens", "layout", "layers", "image"], url=...)。
3. 分别标记 identity、geometry、hierarchy、typography/color、assets、visual reference 六个证据域为 complete、partial 或 missing。
4. 记录 analyze 根节点的逻辑宽高。常规 375 宽设计若明确对应 375dp，才记录「1 design unit = 1dp」。
5. 分开记录四类坐标：项目列表缩略图、analyze HTML/layout、切图像素、运行截图像素。禁止用缩略图或切图宽度直接换算 Android dp。
6. 记录运行截图的 viewport、density、font scale、状态栏/导航栏 inset，以及与设计图比较时的裁剪和缩放方式。

输出：
- 设计身份表。
- 六个证据域的完整性表。
- 坐标空间记录和换算依据。
- 仍缺失的证据，以及因此不能做出的结论。
```

这一步的结果是可复查的输入合同。若没有稳定 `id` 和版本，或 analyze 根宽度无法解释，后续只能做定性审查，不能给出精确间距结论。

---

## Prompt 1：限定规格来源

这段 Prompt 用来防止 AI 用截图观感覆盖结构化规格。

```text
角色：UI 还原审核代理。

任务：基于蓝湖结构化数据审查当前页面实现，不以截图观感覆盖结构化规格。

输入：
- 设计节点：{设计节点名称}
- 页面状态：{主题 / Tab / 空态 / 加载态 / 数据态}
- 设计规格：{HTML/CSS/tokens/layout/layers}
- 当前代码范围：{文件路径或组件入口}
- 平台：{Android View / Flutter / HarmonyOS ArkUI}

规则：
1. 以 HTML、CSS、tokens、layout、layers 作为规格。
2. 截图只用于复核，不用于推翻结构化数据。
3. 每个结论都要写出设计值、当前代码来源、当前渲染结果、差异归属。
4. 不允许只回答「看起来差不多」。

输出：
- 先列出本次审查范围。
- 再列出需要建立的台账。
- 最后说明暂不修改代码，先完成证据表。
```

适用场景：首次接入设计稿、换 Tab、换主题、设计节点不明确、截图和结构化数据看起来不一致。

---

## Prompt 2：页面盒模型和背景归属

这段 Prompt 用来审查页面根、滚动容器、列表容器和空白区域。

```text
任务：建立页面级盒模型和背景归属表。

必须检查：
1. 页面根容器宽度、高度、背景。
2. 从窗口根到模块根的背景归属：
   Activity/window root
   -> Fragment/page root
   -> Tab/page container
   -> refresh/layout parent
   -> RecyclerView/ListView/ScrollView
   -> item/module root
3. 短内容、空列表、加载态、模块隐藏、底部 padding、overscroll 暴露出的颜色。
4. 滚动容器是否应保持透明，页面底色是否应由父容器承担。

输出表格：
| 层级 | 蓝湖要求 | 当前代码 | 暴露状态 | 差异 | 处理建议 |
|---|---|---|---|---|---|

限制：
- 不允许只检查长列表满屏状态。
- 不允许通过给列表控件直接上背景来掩盖父容器背景问题，除非设计明确要求列表本身拥有底色。
```

适用场景：页面底色、空白区域、加载态、短列表、底部露色问题。

---

## Prompt 3：横向边界台账

这段 Prompt 用来解决模块左右边界不一致的问题。

```text
任务：建立同列模块的横向边界台账。

检查对象：
- 同一页面内上下相邻的模块、卡片、列表组、Banner、模块组。
- 任何被指出「宽度不一致」「左右边界不一致」「应该共边」的模块。

每行必须记录：
- 蓝湖横向几何：page width、left、width、right、推导出的左右边距。
- 当前代码来源：root width、margin、padding、父容器 padding、列表模型 margin、ItemDecoration。
- 当前几何结果。
- 模块之间是否应该共边。
- 哪一层负责横向边界。

输出表格：
| 模块 | 蓝湖横向几何 | 当前代码来源 | 当前几何 | 边界关系 | owner | 处理 |
|---|---|---|---|---|---|---|

限制：
- 不允许把内部 padding 当成模块外边界，除非设计背景显示同一视觉面跨过该 padding。
- 不允许只说单个模块 margin 正确，必须比较同列模块之间的关系。
```

适用场景：卡片左右边距、同列模块共边、列表组宽度、模块组和下方模块不一致。

---

## Prompt 4：绝对纵向坐标台账

这段 Prompt 用来处理自定义状态栏、顶部工具栏、重叠模块和负向偏移。

```text
任务：建立页面级绝对纵向坐标台账。

检查对象：
- 顶部状态区、导航区、工具栏、Header、首个内容模块。
- 使用 position:absolute、负向 top、嵌套 top、paddingTop 或重叠视觉层的节点。
- 固定底部操作区和内容区域之间的可见距离。

每个纵向锚点必须记录：
- 蓝湖节点路径：从页面根到目标节点的完整层级。
- 蓝湖 y 计算：祖先 top、子节点 top、paddingTop、负向偏移累加后的页面级 y。
- 当前代码 y 计算：root top、系统 inset、toolbar top、parent padding、constraint、margin、translationY。
- 派生关系：前一个模块 bottom 到后一个模块 top 的距离，允许出现负值。
- owner：状态栏策略、工具栏高度、Header 高度、模块 top margin、父容器 padding、子节点 padding 或固定底部容器。

输出表格：
| 锚点或模块 | 蓝湖 absolute y | 当前代码 absolute y | 派生关系 | owner | 处理 |
|---|---:|---:|---|---|---|

限制：
- 不允许把子节点 padding 或 margin 直接当成页面级 y。
- 不允许只看最近一层 XML margin。
- 如果存在重叠层，必须用 bottom -> top 计算重叠距离。
```

适用场景：状态栏透明、自定义工具栏、重叠卡片、吸顶 Header、固定底部按钮、负向偏移。

---

## Prompt 5：模块间距台账

这段 Prompt 用来避免把一个蓝湖间距值机械改成某个 XML margin。

```text
任务：建立模块间距台账，计算最终可见距离。

检查对象：
- Tab/Header -> 首个模块。
- 模块 -> 模块。
- 卡片 -> 卡片。
- 列表组 -> 底部导航或页面底部。
- 模块隐藏、加载态、空态后的相邻关系。

每行必须记录：
- 蓝湖 gap：从结构化 layout 推导，不用目测。
- 当前 gap 来源：上一个模块 bottom padding、下一个模块 top margin、列表 padding、item root margin、分割线、ItemDecoration、父容器 padding。
- 可见距离公式，例如：12 child bottom + 12 list padding + 8 module margin = 32dp。
- gap owner：最终应该由哪一层负责。

输出表格：
| 视觉关系 | 蓝湖 gap | 当前来源 | 当前可见距离 | owner | 处理 |
|---|---:|---|---:|---|---|

限制：
- 不允许只检查一个非零 margin。
- 不允许把多个 gap 平均成一个值。
- 不允许在台账仍有未知值时报告「整体间距正确」。
```

适用场景：模块间距偏大、Header 到首项距离不对、多个 padding 叠加、列表底部留白异常。

---

## Prompt 6：列表完整契约

这段 Prompt 用于列表页，重点是不要只修用户指出的局部症状。

```text
任务：在首次修改同一列表面之前，建立完整列表契约。

必须审查：
1. 顶部区域：每个 Tab 的高度、选中/未选中态、对应容器、Header 文字槽位、Header 到首项距离；不能用一个 Tab 的结果代替其他 Tab。
2. 列表容器：root padding、首项间距、overscroll、底部 padding、空态背景。
3. 重复项：首项、普通项、末项的高度、宽度、背景、圆角、分割线。
4. Item 内容：标题、摘要、元信息、标签、图片、引用块的字体、行高、字重、槽位。
5. 分割线：左右缩进、高度、颜色、归属层级。
6. 横向列表：viewport 起点、首项位置、项间距、尾部 padding 和是否允许设计上的溢出。

特别规则：
- 设计视觉模块和代码 item 不一定一一对应。
- 若设计把多个区域放在同一个视觉 block 中，而代码拆成多个 item，先重新划分 gap owner。
- 若设计上是两个模块，代码由同一个列表模型连续生成，也要按设计模块审查。

输出表格：
| 检查面 | 蓝湖规格 | 当前代码 | owner | 风险 | 后续补丁范围 |
|---|---|---|---|---|---|

限制：
- 不要求一次提交修完全部问题。
- 允许按视觉维度窄提交，但第一轮必须暴露完整列表契约。
```

适用场景：RecyclerView、ListView、Flutter ListView、瀑布流、搜索结果、消息列表、资讯列表。

---

## Prompt 7：文字槽位台账

这段 Prompt 用来处理固定高度卡片中的文字垂直位置、行高和截断。

```text
任务：建立固定高度卡片的文字槽位台账。

检查对象：
- 标题、副标题、数值、摘要、元信息、底部名称、标签文字。

每行必须记录：
- 蓝湖文字盒：font-size、line-height、font-weight、x/y、width/height、上下锚点。
- 当前代码：textSize、lineHeight、includeFontPadding、font weight、top/bottom constraint、gravity、maxLines、ellipsize。
- 槽位计算：slot height、line box height、top residual、bottom residual。
- 截断风险：最长运行态文案是否会被兄弟控件挤压。
- 有界行规则：若 Android `TextView` 位于固定高度行内，旁边有 icon、checkbox、switch 或按钮，先检查文本自身 `layout_height`、`lineHeight`、`includeFontPadding`、`android:gravity="center_vertical"`，不要移动相邻图标补偿文本未居中。
- 宽度规则：协议、富文本或正文 `TextView` 不应为了凑总宽度从 `wrap_content` 改成固定宽，除非设计或代码契约明确要求固定文本槽位。

输出表格：
| 文本角色 | 蓝湖文字盒 | 当前代码 | 槽位计算 | 截断风险 | 处理 |
|---|---|---|---|---|---|

限制：
- 不允许只看 layout_marginTop。
- 不允许通过缩小字体解决宽度分配问题，除非设计规格本身要求字体变小。
```

适用场景：文字上下不居中、固定高度卡片、标签文字偏下、标题提前省略、数值和名称互相挤压、行内图标和文本垂直位置不一致。

---

## Prompt 8：颜色和 Token 映射

这段 Prompt 用来避免只按十六进制颜色做替换。

```text
任务：建立颜色语义角色表，并映射到项目资源。

检查对象：
- 页面背景、卡片背景、模块标题、正文、元信息、禁用态、右侧操作文字、右侧箭头、分割线。

规则：
1. 若蓝湖提供命名 Token，优先按 Token 语义映射资源。
2. 当前十六进制值相同，不代表语义一致。
3. 同一行中的标题、正文、右侧操作文字、箭头、分割线必须分开记录。
4. 检查日夜模式或皮肤资源，不只看当前主题。

输出表格：
| 视图身份 | 语义角色 | 蓝湖 Token 或颜色 | 当前代码资源 | 主题变体 | 处理 |
|---|---|---|---|---|---|

限制：
- 不允许在共享布局里做宽泛颜色替换。
- 修右侧操作颜色时，不得顺带修改标题或正文。
```

适用场景：颜色接近但语义不对、深色模式异常、右侧文字和箭头颜色不一致。

---

## Prompt 9：结构元素和运行态图片

这段 Prompt 用来检查容易被当成装饰的小元素。

```text
任务：审查结构元素和运行态图片，不只检查静态布局。

必须检查：
1. 标题左图标、右侧操作文字、右侧箭头、清除按钮、徽标、分割线是否存在。
2. 卡片内排名角标、NEW 标识、状态标签、业务标签、覆盖标签是否存在。
3. 服务端图片或图标的 ImageView 尺寸、scaleType、placeholder、圆角变换、裁剪策略，并沿着布局 ID 追到 adapter、model 和图片加载调用；确认图标是 image/vector/slice 资源，而不是未经设计许可的文字 glyph。
4. 父容器圆角是否真的裁剪了 bitmap；若没有，检查项目现有的圆角 loader 或 transform，以及 placeholder 是否使用同样的圆角。
5. 头像或图片边框的绘制顺序：兄弟节点顺序、foreground、elevation、translationZ、父容器裁剪、自定义容器测量锚点。

输出表格：
| 元素 | 蓝湖是否存在 | 当前代码 | 运行态来源 | 绘制或加载风险 | 处理 |
|---|---|---|---|---|---|

限制：
- 不允许把服务端图片只当成 XML 背景检查。
- 父容器有圆角，不代表图片本体已裁剪。
- 边框宽度正确，不代表绘制顺序正确。
```

适用场景：旧图标残留、角标缺失、服务端图片圆角无效、头像边框压住图片。

---

## Prompt 10：重复组件和图标 alpha bounds

重复图标最容易被错误放大或缩小。蓝湖的外层 group 可能是 `54x54`，但里面的可见图形只占 `34x34`；代码的 `ImageView`、bitmap 画布、透明留白和 `scaleType` 也可能分别由不同层控制。先建立 peer contract，再决定是否真的存在尺寸变体。

```text
任务：审查重复组件的共性契约和每个图标的实际可见边界。

检查对象：
- 目标组件及其左、右或上下 sibling。
- 所有已选中/未选中、日/夜、登录/未登录、占位图/服务端图状态。
- 每个已打包 density bucket 的图标或图片资源。

每个条目必须记录：
- peer contract：共同的布局 carrier、资源密度模式、排列方式、scaleType/content mode 和状态变体。
- 蓝湖层级：外层 wrapper/group 尺寸，以及嵌套可见内容层的 bounds。
- 代码 carrier：ImageView 或组件的宽高、padding、约束和内容模式。
- bitmap canvas：资源像素宽高。
- alpha trim：去除透明像素后的可见范围，写成 `WxH+X+Y`。
- effective bounds：密度缩放和内容模式作用后的可见高度、视觉中心和底边位置。

规则：
1. 使用 ImageMagick 或等价结构化工具检查每个密度桶，例如：
   magick identify -format '%f %wx%h trim=%@\n' {资源文件}
2. 外层 wrapper 不能直接决定 carrier；只有结构化层级明确证明是有意变体时，才允许独立尺寸。
3. 确认多个 peer 共享某个值后，只把这个值提取到现有 dimension、style、token、theme value 或组件 primitive；图片内容和点击行为仍保持各自独立。
4. 为所有 peer 和状态写一个聚焦测试，既检查共享引用和解析后的值，也检查每个条目的资源、路由、绑定和点击行为没有被替换。

输出表格：
| 条目 | carrier | bitmap canvas | alpha trim | scale/content mode | peer 结果 | 处理 |
|---|---|---|---|---|---|---|
```

这张表解决的是「布局矩形一样但视觉大小不同」的问题。只有源码、所有密度资源和同屏运行截图都检查过，才可以把重复图标的结果提升到 `RUNTIME_VERIFIED`；不能只凭一个 PNG 或一个 `ImageView` 矩形下结论。

---

## 平台映射和运行态边界

台账中的数字要落到目标平台的真实属性上，不能只在 Prompt 里停留为「设计稿有一个 8」。常用映射如下：

| 平台 | 几何和间距 | 文字 | 还需要追踪的运行态来源 |
|---|---|---|---|
| Android View/XML | `dp`、`layout_margin`、`padding`、约束、`minHeight`、`gravity` | `sp`、`lineHeight`、`includeFontPadding`、`textStyle`/typeface | adapter、data binding、图片 loader、RecyclerView padding/ItemDecoration、日夜资源 |
| Flutter | logical pixel、`EdgeInsets`、`SizedBox`、constraints | `TextStyle(fontSize, height, fontWeight, color)` | builder/model、图片 `fit`、placeholder、滚动容器和空态 |
| HarmonyOS ArkUI | `vp`、`.margin`、`.padding`、`.width`、`.height` | `fp`、`FontWeight` | 状态变量、异步图片、组件显隐和页面容器背景 |

Android 的有界文字行要先检查 `TextView` 自己的 line box、`layout_height`、`lineHeight`、`includeFontPadding` 和 `gravity`，不要移动旁边的图标来补偿文字未居中。协议或富文本正文也不要为了凑总宽度把 `wrap_content` 改成固定宽度，除非设计明确要求固定文字槽位。

如果后续追问「margin、padding、边距、间距、背景、底色、整体是否正确」，应把前一次审查视为未完成，重新建立页面盒模型、背景归属、横向边界和模块间距台账。前一次只检查了局部控件，不能直接复用为整页结论。

---

## Prompt 11：补丁前目标清单

这段 Prompt 用来控制 AI 修改范围。

```text
任务：在修改代码前，生成补丁目标清单。

每个目标必须包含：
- 文件路径。
- 视图 ID、组件名或绑定名。
- 属性名。
- 当前值。
- 目标值。
- 语义角色。
- 来自哪张台账。

输出表格：
| 文件 | 视图或组件 | 属性 | 当前值 | 目标值 | 语义角色 | 证据来源 |
|---|---|---|---|---|---|---|

限制：
- 不允许先改代码再补证据。
- 不允许跨语义角色做批量替换。
- 不允许把无关重构混入视觉修复。
```

适用场景：准备让 AI 自动改代码、需要控制补丁范围、同一资源名被多个角色复用。

---

## Prompt 12：补丁后审查

这段 Prompt 用来在构建前先读 diff。

```text
任务：审查本次 diff 是否只修改目标层级。

必须检查：
1. diff 是否只包含补丁目标清单中的文件、视图、属性。
2. 是否误改同一行中的标题、正文、元信息、右侧操作、箭头或分割线。
3. 间距修复是否只调整台账中确认的 owner。
4. 成对元素是否一起处理，例如右侧操作文字和右侧箭头。
5. 是否混入无关重构、格式化或未请求的依赖变更。
6. 如果本轮是在修正上一轮被指出的问题，必须先验证渲染症状；未验证前不要提交，只保留未提交补丁或继续补验证证据。

输出：
- 通过项。
- 风险项。
- 必须回退的误改。
- 可继续运行的验证命令。
```

适用场景：AI 已经改完代码、准备构建或截图复核之前。

---

## 一段完整总 Prompt

实际使用时，也可以把上面的要求合并成一段总 Prompt。适合第一次审查某个页面。

```text
角色：UI 还原审核代理。

目标：基于蓝湖结构化规格审查当前页面实现，先产出台账，再做窄范围修复建议。

输入：
- 设计节点：{设计节点}
- 页面状态：{主题 / Tab / 数据态 / 空态 / 加载态}
- 设计规格：{HTML/CSS/tokens/layout/layers}
- 当前代码范围：{页面入口、布局、组件、列表模型、图片加载代码}
- 平台：{Android View / Flutter / HarmonyOS ArkUI}
- 当前问题：{问题描述}
- 设计身份：{design id / version / updateTime}

执行顺序：
1. 先用 `list` 固定 design id、版本和 `updateTime`，再用 `analyze` 获取 `html`、`tokens`、`layout`、`layers`、`image`。
2. 分别标记身份、几何、层级、字体颜色、资产和视觉参考证据域的完整性；缺失域不得猜补。
3. 记录 analyze 根宽高、设计到平台的换算和运行截图的 viewport/density/font scale/inset。
4. 建立页面盒模型和背景归属表，覆盖短内容、空列表、加载、隐藏和底部露色。
5. 建立同列模块横向边界台账；若有绝对定位、负向偏移、重叠或固定底部区，再建立绝对纵向坐标台账。
6. 建立模块间距台账，按视觉锚点相加所有 child、list、provider、item 和 decoration 间距。
7. 如果目标是列表页，建立完整列表契约；如果有固定高度卡片或有界文本行，建立文字槽位台账。
8. 建立颜色语义角色表和 Token 映射，检查日夜或皮肤变体。
9. 审查标题附件、卡片角标、分割线、运行态图片、圆角裁剪和图片边框绘制顺序。
10. 若存在重复组件，建立 peer contract 和 alpha-bounds 台账，检查每个密度桶。
11. 生成补丁目标清单；只有 `implement` 或 `commit` 模式才进入修改。
12. 修改后先审 diff，再构建、检查最终产物，并在真实路由复现指定状态。
13. 把设计与运行截图归一到同一坐标空间，输出最高证据等级和未满足的门槛。

输出格式：
- 审查范围。
- 固定的设计身份、坐标空间和证据域完整性。
- 台账列表。
- 发现的问题，按风险排序。
- 补丁目标清单。
- 需要验证的状态、命令和截图。
- 最高证据等级：`ANALYZED` / `IMPLEMENTED` / `ARTIFACT_VERIFIED` / `RUNTIME_VERIFIED` / `MATCHES_LANHU`。
- 不能达到更高等级的具体原因。
```

---

## 收尾检查 Prompt

收尾前可以用下面这段做最后一轮检查。只有 `commit` 模式才允许提交。

```text
任务：判断本次蓝湖还原修复是否可以收尾。

必须确认：
- 设计 `id`、版本或 `updateTime` 已固定，六个证据域已标记完整、部分或缺失。
- 设计 analyze 根尺寸、运行 viewport、density、font scale、系统 inset 和比较裁剪方式已经记录。
- 页面级左右边界已经检查。
- 同列模块横向边界台账已经完成。
- 自定义状态栏、工具栏、重叠层或固定底部区域涉及的绝对纵向坐标已经检查。
- 相邻模块间距台账已经完成，且每个可见模块对都有 owner。
- 列表页已经审查完整列表契约。
- 分割线、ItemDecoration、列表模型 spacer 已经检查。
- 固定高度卡片已经检查文字槽位。
- 有界行内 `TextView` 已经先检查自身 line box 和垂直居中策略，没有用移动相邻图标补偿文本问题。
- 标题左图标、右侧操作、箭头、角标、标签、分割线已经检查。
- 运行态图片、圆角、placeholder、边框绘制顺序已经检查。
- 重复图标已比较 wrapper、carrier、bitmap canvas、alpha trim、密度和 content mode；确认的共性已由共享资源或样式表达，并有 peer/state 测试。
- 颜色改动按语义角色分开，未做宽泛替换。
- diff 已经审查，没有误改相邻角色。
- 目标构建产物已经检查，确认包含本次资源或代码。
- 已通过真实路由进入指定页面，覆盖指定 Tab、主题、数据/空/加载状态，并留存运行截图。
- 设计图和运行截图已归一到同一坐标空间，并记录稳定几何、文字槽位、颜色、资源和模块间距的差值。
- 若本轮修正上一轮被指出的问题，渲染症状已经验证；未验证则不提交。

输出：
- 可以收尾 / 不能收尾。
- 最高证据等级。
- 不能收尾时列出缺失证据和被阻塞的更高等级。
- 可以收尾时列出构建命令、产物路径、真实路由和截图状态。
```

---

## 报告必须分开写

最终报告不要把不同证据混成一句「已完成」。至少分成四行：

| 层级 | 应报告的事实 |
|---|---|
| 设计规格 | 固定的 `id`、版本、根尺寸、证据域完整性、采用的 Token 和测量来源 |
| 源码和构建 | 修改的文件、目标属性、测试或构建结果、未改动的相邻语义角色 |
| 产物 | APK/AAB/HAP/Web bundle 路径、版本或 hash、资源是否实际被打包和解析 |
| 运行态 | 真实路由、状态/主题/Tab、viewport/density/font scale、截图比较结果和仍存在的差值 |

运行态不可用时，直接写明「`IMPLEMENTED`；设备或浏览器验证缺失」，不要把源码证据转述成 `MATCHES_LANHU`。

---

## 总结

蓝湖验收 Prompt 的核心，不是让 AI「看图更细」，而是让 AI 按固定证据格式工作，并且知道证据何时还不够。

一套可复用的 Prompt 至少要规定四件事：

- 规格来源：结构化设计数据优先，截图只做复核。
- 坐标和台账：固定设计身份，分开 analyze 坐标、切图像素和运行截图，边界、绝对坐标、间距、列表契约、文字槽位、颜色角色、peer 和运行态图片分别成表。
- 修改边界：先生成补丁目标清单，再改代码，改完先审 diff；共享属性用共享资源或样式表达，并用测试防止 peer 漂移。
- 验收等级：源码、产物、真实路由和截图各自报告，缺一项就停在相应等级。

只要 Prompt 能持续产出这些证据，AI 给出的就不只是视觉判断，而是一套可复查、可停止、可继续验证的 UI 审核流程。
