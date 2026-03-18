---
layout: post
title: "用向量数据库给 OpenClaw 装上长期记忆"
date: 2026-03-18 15:30:00 +0800
categories: [技术, AI]
tags: [OpenClaw, 向量数据库, BGE-M3, Zilliz, RAG]
description: "OpenClaw 的默认记忆是一个 MEMORY.md 文件，随着信息积累，全文塞进 Prompt 越来越不实际。本文记录如何用 BGE-M3 + Zilliz Cloud 把它改造成语义向量搜索，只把相关记忆注入上下文。"
---

OpenClaw 默认的记忆方案很直接：把所有记忆写进 `MEMORY.md`，每次对话把整个文件塞进 Prompt。简单，透明，但有个硬伤——**随着记忆增长，Token 消耗线性膨胀，而且大模型对长文本里的细节本来就容易"遗忘"**。

解法是向量数据库：不再全量注入，而是根据当前对话内容做语义检索，只取 Top-K 条相关记忆。

---

## 方案选型

**Embedding 模型**：[BAAI/bge-m3](https://huggingface.co/BAAI/bge-m3)

选它的原因：
- 单模型同时输出 **Dense**（语义）+ **Sparse**（词频权重）两种向量，天然支持混合搜索
- 中文支持好，个人记忆场景多为中文
- 本地运行，无 API 费用，离线可用

**向量数据库**：[Zilliz Cloud](https://cloud.zilliz.com)（托管 Milvus）

- 免费层够个人使用（1 Cluster，1GB 存储）
- 原生支持 BGE-M3 的 Dense + Sparse 混合搜索（`hybrid_search` + `RRFRanker`）
- 零运维

---

## 原理

```
记忆写入：文本 → BGE-M3 → dense+sparse 向量 → Zilliz
记忆读取：用户输入 → BGE-M3 → 混合检索 → Top-K 相关记忆 → 注入 Prompt
```

混合搜索（Hybrid Search）= Dense ANN 语义召回 + Sparse BM25 关键词召回，两路结果经 **RRF（Reciprocal Rank Fusion）** 融合排序。核心优势：语义相近但用词不同的记忆，和精确包含关键词的记忆，都能被召回。

---

## 实现

项目地址：[openclaw-vector-memory](https://github.com/donglua/openclaw-vector-memory)

结构也很简单：

```
.
├── requirements.txt
├── .env.example
├── main.py              # CLI 入口
└── memory/
    ├── embedder.py      # Embedding 后端（local / remote）
    ├── store.py         # Zilliz Cloud 读写核心
    └── migrate.py       # 从 MEMORY.md 迁移
```

### 一键集成到 OpenClaw

本项目提供了一键安装脚本，能直接把代码、依赖和配置自动注入到你的 OpenClaw 项目中：

```bash
# 假设你的 OpenClaw 项目路径是 ~/workspace/openclaw
./install.sh ~/workspace/openclaw
```

执行后，脚本会自动在目标项目的 `AGENTS.md` 中追加下面这段系统提示词，引导主 Agent 自动使用：

```markdown
# 🧠 长期向量记忆库 (自动注入)
**核心指令**：不要直接读取或写入传统的 `MEMORY.md` 文件。对于用户的偏好、长期记忆、以及背景上下文，请使用以下向量搜索工具：
1. **检索记忆**：当你需要回忆关于用户的信息时，使用终端执行：
   `python3 vector_memory.py --search "你要检索的关键语义"`
2. **保存记忆**：当用户告知你全新的偏好或长期有效的事实，使用终端执行：
   `python3 vector_memory.py --save "清晰且完整的记忆内容"`
```

未来你的 Agent 将会自动通过执行 CLI 命令来调取或保存精准记忆，而不再是死板地把全篇记忆塞进上下文窗口！

### CLI 用法

除了集成到代码，项目也提供了方便的命令行工具。首先安装依赖：

```bash
pip3 install -r requirements.txt
cp .env.example .env
```

然后可以执行：

```bash
# 写入一条记忆
python3 main.py --save "用户喜欢用 Python，讨厌 Java"

# 语义搜索
python3 main.py --search "这个用户有什么编程习惯"

# 从 MEMORY.md 迁移已有记忆
python3 main.py --migrate /path/to/MEMORY.md

# 查看记忆总条数
python3 main.py --count
```

`--migrate` 会按段落分块（`\n\n` 切割）已有记忆，批量写入向量库。

---

## 没有本地 GPU 怎么办

`embedder.py` 支持多种后端，通过 `.env` 灵活切换。

**用本地模型（体验最佳，默认使用 BGE-M3）：**

```bash
EMBEDDING_PROVIDER=local
```
首次运行会自动下载模型（约 2GB），之后离线可用，原生支持 Dense + Sparse 双路召回。

**用远程 API（无需本地算力）：**

可以配置使用市面上任意提供 Embedding 接口的服务（硅基流动、OpenAI，甚至你的本地 Ollama 服务）：

```bash
# 远程 Embedding API（以硅基流动为例）
EMBEDDING_PROVIDER=remote
EMBEDDING_API_BASE=https://api.siliconflow.cn/v1
EMBEDDING_API_KEY=sk-xxx
EMBEDDING_MODEL=BAAI/bge-m3
EMBEDDING_DIM=1024
```

常见服务配置对照：

| 服务 | `EMBEDDING_API_BASE` | `EMBEDDING_MODEL` | `EMBEDDING_DIM` |
|------|---------------------|------------------|----------------|
| 硅基流动 | `https://api.siliconflow.cn/v1` | `BAAI/bge-m3` | `1024` |
| OpenAI | `https://api.openai.com/v1` | `text-embedding-3-small` | `1536` |
| Ollama | `http://localhost:11434/v1` | `nomic-embed-text` | `768` |

需要注意的是，通常远程 API 只返回 Dense 向量，此时 `store.py` 会检测到空 Sparse 自动降级为纯语义搜索，无需手动修改代码。对个人记忆场景影响不大。

---

## 效果

从"全量 MEMORY.md 塞 Prompt"改为"语义 Top-5 检索"之后：

- Token 消耗大幅下降（记忆越多效果越明显）
- 相关性更高——不相关的历史记忆不再干扰当前对话
- 可以无限堆积记忆，不用担心 Context 溢出

代价：首次运行需要下载 BGE-M3 模型（约 2GB），以及一个 Zilliz Cloud 账号。
