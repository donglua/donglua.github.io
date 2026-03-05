---
layout: post
title: "macOS dd 命令提速：理解 rdisk 与 disk 的区别"
date: 2026-03-05 09:15:00 +0800
categories: [技术, macOS]
tags: [dd, macOS, NAS, 效率, 命令行]
description: "在 macOS 上使用 dd 写盘时，将 /dev/diskN 替换为 /dev/rdiskN 可显著提升写入速度。本文从 BSD 设备模型的角度解析 disk 与 rdisk 的区别，并给出完整的操作流程。"
---

## 背景

最近在用 `dd` 给 NAS 写系统盘，发现写入速度很慢。排查后发现，macOS 下 `dd` 的目标设备选择对写入性能有很大影响——使用 `/dev/rdiskN` 替代 `/dev/diskN`，速度可以提升一个数量级。

这其实是 BSD 系统中 **buffered device** 与 **raw device** 的经典区别，值得单独写一篇记录。

---

## disk 与 rdisk 的区别

macOS 的 `/dev` 目录下，每块磁盘对应两个设备节点：

| 设备路径 | 类型 | 说明 |
|:---|:---|:---|
| `/dev/disk4` | Buffered device | 经过内核 buffer cache |
| `/dev/rdisk4` | Raw device | 绕过 buffer cache，直接操作设备 |

`r` 即 **raw**。

### 底层原理

使用 buffered device 时，I/O 路径如下：

```
用户空间 → 内核 buffer cache → 磁盘驱动 → 物理设备
```

buffer cache 适合随机读写和小 I/O 场景，但对 `dd` 这类大块顺序写入反而是额外开销：

- **多一次内存拷贝**：数据先拷贝到 buffer cache，再从 cache 写入设备
- **缓冲管理开销**：内核需维护缓冲区元数据、执行 LRU 淘汰
- **内存压力**：大量写入数据涌入 cache，可能触发页面回收

使用 raw device 时，I/O 路径简化为：

```
用户空间 → 磁盘驱动 → 物理设备
```

跳过 buffer cache，减少一次拷贝和相关管理开销，写入速度自然更快。

### 平台差异

这是 **BSD 设备模型**的特性，macOS 底层基于 Darwin（XNU 内核），继承了这一设计。Linux 的块设备架构不同，没有 `rdisk` 的概念，但可以通过 `oflag=direct` 达到类似效果。

---

## 操作流程

以写入 NAS 系统镜像到 U 盘为例。

### 1. 确认目标磁盘

```bash
diskutil list
```

找到目标设备，例如 `/dev/disk4`。**务必确认设备编号，避免误写其他磁盘。**

### 2. 卸载磁盘

```bash
diskutil unmountDisk /dev/disk4
```

> 注意是 `unmountDisk`（卸载），不是 `eject`（推出）。推出后设备节点会消失。

### 3. 写入镜像

```bash
# ❌ 使用 buffered device，较慢
sudo dd if=TrueNAS-13.3.iso of=/dev/disk4 bs=1m

# ✅ 使用 raw device，显著提速
sudo dd if=TrueNAS-13.3.iso of=/dev/rdisk4 bs=1m
```

### 4. 推出设备

```bash
diskutil eject /dev/disk4
```

---

## 进阶用法

### 查看写入进度

macOS 的 `dd` 支持 `SIGINFO` 信号，写入过程中按 **`Ctrl + T`** 可输出当前进度：

```
4194304+0 records in
4194304+0 records out
4294967296 bytes transferred in 58.12 secs (73903245 bytes/sec)
```

### 使用 pv 显示实时进度条

```bash
brew install pv
sudo sh -c 'pv TrueNAS-13.3.iso | dd of=/dev/rdisk4 bs=1m'
```

输出示例：

```
2.10GiB 0:01:05 [67.8MiB/s] [===================>        ] 52% ETA 0:00:58
```

### bs 参数注意事项

macOS（BSD）和 Linux（GNU）的 `dd` 在 `bs` 单位标记上有差异：

| 平台 | 写法 | 含义 |
|:---|:---|:---|
| macOS (BSD) | `bs=1m` | 1 MiB（小写 m） |
| Linux (GNU) | `bs=1M` | 1 MiB（大写 M） |

一般设置在 `1m` ~ `4m` 之间即可，过大可能因对齐问题反而降低效率。

---

## 性能对比

以 4GB 系统镜像写入 USB 3.0 U 盘为参考：

| 方式 | 命令 | 耗时 | 速度 |
|:---|:---|:---|:---|
| Buffered | `dd of=/dev/disk4 bs=1m` | ~15 min | ~4.5 MB/s |
| **Raw** | `dd of=/dev/rdisk4 bs=1m` | **~1.5 min** | **~45 MB/s** |

实际速度取决于硬件，但量级差距稳定存在。

---

## 小结

| 项目 | 内容 |
|:---|:---|
| 核心操作 | `/dev/diskN` → `/dev/rdiskN` |
| 原理 | 绕过内核 buffer cache，减少内存拷贝 |
| 来源 | BSD raw device 特性 |
| 适用场景 | dd 写盘、制作启动盘、刷固件 |
| 注意 | macOS 用 `bs=1m`（小写），Linux 用 `bs=1M`（大写） |
