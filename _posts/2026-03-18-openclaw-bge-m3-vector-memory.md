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

项目地址：[openclaw-bge-memory](https://github.com/donglua/openclaw-bge-memory)

结构很简单：

```
memory/
├── embedder.py   # BGE-M3 封装，支持本地或远程 OpenAI 兼容 API
├── store.py      # Zilliz Cloud 读写，自动适配 dense-only / 混合搜索
└── migrate.py    # 从 MEMORY.md 批量迁移
main.py           # CLI 入口
```

### 存入一条记忆

```python
from memory import MemoryStore
store = MemoryStore()
store.save("用户喜欢用 Python，偏好简洁代码风格")
```

`MemoryStore` 内部自动调用 BGE-M3 生成向量并写入 Zilliz，无需关心 Embedding 细节。

### 检索并注入 Prompt

```python
# 替换原来的 open("MEMORY.md").read()
context = store.build_prompt_context(user_input)
prompt = f"{context}\n\n用户：{user_input}"
```

`build_prompt_context` 内部做混合搜索，返回格式化好的 Markdown 片段，直接拼 Prompt 就行。

### 迁移已有的 MEMORY.md

```bash
python main.py --migrate /path/to/MEMORY.md
```

按段落分块（`\n\n` 切割），批量写入向量库。

---

## 没有本地 GPU 怎么办

`embedder.py` 支持两种后端，`.env` 切换：

```bash
# 本地 BGE-M3（默认，完整混合搜索）
EMBEDDING_PROVIDER=local

# 远程 OpenAI 兼容 API（仅 Dense 搜索，无需本地模型）
EMBEDDING_PROVIDER=remote
EMBEDDING_API_BASE=https://api.siliconflow.cn/v1
EMBEDDING_API_KEY=sk-xxx
EMBEDDING_MODEL=BAAI/bge-m3
EMBEDDING_DIM=1024
```

远程 API 不返回 Sparse 向量，`store.py` 检测到空 Sparse 后自动降级为纯 Dense 搜索，无需手动配置。

对于个人记忆这类自然语言场景，Dense 搜索的召回质量已经足够，Sparse 补充的是专有名词和精确关键词的命中率。

---

## 效果

从"全量 MEMORY.md 塞 Prompt"改为"语义 Top-5 检索"之后：

- Token 消耗大幅下降（记忆越多效果越明显）
- 相关性更高——不相关的历史记忆不再干扰当前对话
- 可以无限堆积记忆，不用担心 Context 溢出

代价：首次运行需要下载 BGE-M3 模型（约 2GB），以及一个 Zilliz Cloud 账号。
