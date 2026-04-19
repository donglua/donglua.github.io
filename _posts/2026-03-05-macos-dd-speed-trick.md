---
layout: post
title: 'macOS dd 命令提速：理解 rdisk 与 disk 的区别'
date: 2026-03-05 09:15:00 +0800
categories: [技术, macOS]
tags: [dd, macOS, NAS, 效率, 命令行]
description: '在 macOS 上使用 dd 写盘时，将 /dev/diskN 替换为 /dev/rdiskN 可显著提升写入速度。本文从 BSD 设备模型的角度解析 disk 与 rdisk 的区别，并给出完整的操作流程。'
---

## 问题现象

在 macOS 上使用 `dd` 制作系统盘或写入大镜像时，默认使用 `/dev/diskN` 作为目标设备，写入速度往往极慢（例如 4GB 镜像需耗时 15 分钟以上）。

## 根本原因

macOS 基于 Darwin 内核（继承自 BSD），其 `/dev` 目录下每块物理磁盘通常暴露两个设备节点：`diskN` 和 `rdiskN`。

- **`/dev/diskN` (Buffered Device)**：走内核 Buffer Cache。数据从用户空间先拷贝到内核缓存，再由内核调度写入物理设备。带来额外的内存拷贝和管理开销。
- **`/dev/rdiskN` (Raw Device)**：绕过内核缓存，直接进行块级物理 I/O。

对于 `dd` 这种大块连续顺序写入的工具，内核缓存毫无益处，只会成为性能瓶颈。

## 解决方案

将目标设备路径从 `diskN` 替换为带 `r` 前缀的原始设备 `rdiskN`（如 `/dev/rdisk4`）。速度提升可达 10 倍以上。

### 最佳实践流程

1. **确认目标磁盘**
   ```bash
   diskutil list
   ```
   > 注意：务必反复确认目标设备编号（如 `disk4`），避免覆盖重要数据。

2. **卸载磁盘（非推出）**
   必须先卸载卷才能使用 `dd` 进行底层覆盖：
   ```bash
   diskutil unmountDisk /dev/disk4
   ```

3. **执行高速写入**
   使用 `rdisk` 结合合理的 `bs`（Block Size）写入。macOS（BSD）下 `bs` 单位标志为小写 `m`。
   ```bash
   sudo dd if=TrueNAS-13.3.iso of=/dev/rdisk4 bs=1m
   ```

4. **查看进度**
   写入过程中按 <kbd>Ctrl</kbd> + <kbd>T</kbd> 发送 `SIGINFO` 信号，可查看当前写入进度与速率。

5. **推出设备**
   完成写入后安全弹出：
   ```bash
   diskutil eject /dev/disk4
   ```

## 拓展说明

### Linux 环境差异

Linux 的块设备架构与 BSD 不同，没有 `rdisk` 的概念。在 Linux 环境下要实现绕过缓存的 Direct I/O 提速，需通过 `oflag=direct` 参数实现：
```bash
sudo dd if=image.iso of=/dev/sdX bs=1M oflag=direct
```

### 结合 pv 实现可视化进度条

如果希望拥有直观的动态进度条，可结合 `pv` 工具使用：
```bash
brew install pv
# pv 负责读取并显示进度，通过管道交给 dd 裸写
sudo sh -c 'pv TrueNAS-13.3.iso | dd of=/dev/rdisk4 bs=1m'
```
