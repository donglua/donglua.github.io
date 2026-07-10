---
layout: post
title: Android 多渠道打包终极方案：直接原位修改 AXML 二进制
date: 2026-07-10 13:30:00 +0800
categories: [Android, 逆向工程, 自动化打包]
tags: [Android, Python, AXML, 自动化, 多渠道打包]
---

在 Android 的自动化多渠道打包流程中，最核心的一步往往是修改 `AndroidManifest.xml` 中特定的 `meta-data` 值（即渠道 ID）。

市面上常见的做法有两种：
1. **Apktool 反编译**：全量反编译出纯文本的 XML，修改后再回编译。缺点是极其耗时，不适合 CI 环境里动辄打几十上百个渠道包的场景。
2. **轻量级解析工具（如 xml2axml）**：将 Android 二进制 XML（AXML）解码为普通 XML，用正则修改后再重新编码。这种做法虽然快，但依赖第三方工具，且容易踩坑（例如笔者曾遇到 `xml2axml` 在解析第三方 SDK 注入的超长纯数字 ID 时，抛出 `Integer.parseInt` 溢出崩溃的 Bug）。

为了彻底摆脱上述痛点，本文介绍一种**极速、零依赖、高容错**的多渠道打包方案：**通过 Python 脚本，直接读取并原位修改（In-place Patching）APK 的二进制 AXML 流**。

## 方案原理：为什么可以原位修改？

Android 编译后的 `AndroidManifest.xml` 是 AXML 二进制格式。渠道 ID 通常存放在类似下面这样的 `meta-data` 标签里：

```xml
<meta-data
    android:name="MY_APP_CHANNEL_ID"
    android:value="1" />
```

在二进制结构中，这个 `<meta-data>` 标签会被转换为一个 `START_TAG` 数据块。其中，`android:value="1"` 这个属性的值，在编译期如果被识别为整数，就会以 `TYPE_INT_DEC`（`0x10`）的类型存储，其真正的值（`1`）直接保存在一个 4 字节的 `typed_data` 字段中。

**核心思路：**
既然只是要修改这个数字，我们完全不需要解压整个字符串池（String Pool），也不需要改变文件大小和任何二进制偏移量。我们只需要：
1. 解析 AXML 头部，跳过字符串池。
2. 找到名为 `MY_APP_CHANNEL_ID` 的属性所属的数据块。
3. **直接覆盖那 4 个字节的 `typed_data`，将新渠道号写入进去**。

这种方案不仅绕过了复杂的解包和打包流程，而且只需 Python 标准库即可完成，执行时间在毫秒级别。

## Python 核心代码实现

下面是实现原位修改 AXML 的完整 Python 核心代码（已做脱敏处理）。你可以将其无缝集成到你的多渠道打包 Shell 脚本或 CI 流程中：

```python
#!/usr/bin/env python3
import struct
import sys
import os

TYPE_STRING = 0x03
TYPE_INT_DEC = 0x10
TYPE_INT_HEX = 0x11
CHUNK_START_TAG = 0x0102

def read_string_from_pool(data, strings_data_start, rel_offset, is_utf8):
    """从字符串池读取一个字符串"""
    abs_offset = strings_data_start + rel_offset
    if is_utf8:
        b = data[abs_offset]
        abs_offset += 2 if b & 0x80 else 1
        b = data[abs_offset]
        if b & 0x80:
            byte_count = ((b & 0x7F) << 8) | data[abs_offset + 1]
            abs_offset += 2
        else:
            byte_count = b
            abs_offset += 1
        return data[abs_offset:abs_offset + byte_count].decode('utf-8')
    else:
        char_count = struct.unpack_from('<H', data, abs_offset)[0]
        abs_offset += 2
        return data[abs_offset:abs_offset + char_count * 2].decode('utf-16-le')

def parse_string_pool(data, sp_offset):
    sp_type, sp_header_size, sp_chunk_size = struct.unpack_from('<HHI', data, sp_offset)
    sp_string_count, sp_style_count = struct.unpack_from('<II', data, sp_offset + 8)
    sp_flags = struct.unpack_from('<I', data, sp_offset + 16)[0]
    sp_strings_start = struct.unpack_from('<I', data, sp_offset + 20)[0]

    is_utf8 = bool(sp_flags & (1 << 8))
    offsets_start = sp_offset + sp_header_size
    strings_data_start = sp_offset + sp_strings_start

    strings = []
    for i in range(sp_string_count):
        rel_offset = struct.unpack_from('<I', data, offsets_start + i * 4)[0]
        s = read_string_from_pool(data, strings_data_start, rel_offset, is_utf8)
        strings.append(s)
    return strings, sp_chunk_size

def get_attr_string_value(strings, attr_raw_value, typed_type, typed_data):
    if attr_raw_value >= 0 and attr_raw_value < len(strings):
        return strings[attr_raw_value]
    if typed_type == TYPE_STRING and typed_data >= 0 and typed_data < len(strings):
        return strings[typed_data]
    return None

def patch_channel(manifest_path, target_channel_key, new_channel_id):
    with open(manifest_path, 'rb') as f:
        data = bytearray(f.read())

    xml_type, xml_header_size = struct.unpack_from('<HH', data, 0)
    sp_offset = xml_header_size
    strings, sp_chunk_size = parse_string_pool(data, sp_offset)

    # 1. 在字符串池中寻找目标属性
    channel_name_str_idx = None
    name_attr_str_idx = None
    value_attr_str_idx = None

    for i, s in enumerate(strings):
        if s == target_channel_key:
            channel_name_str_idx = i
        elif s == "name":
            name_attr_str_idx = i
        elif s == "value":
            value_attr_str_idx = i

    if channel_name_str_idx is None:
        print("未在文件中找到目标渠道键值")
        sys.exit(1)

    # 2. 遍历标签，定位属性值并直接修改二进制
    pos = sp_offset + sp_chunk_size
    while pos < len(data):
        chunk_type = struct.unpack_from('<H', data, pos)[0]
        chunk_size = struct.unpack_from('<I', data, pos + 4)[0]

        if chunk_type == CHUNK_START_TAG:
            attr_size = struct.unpack_from('<H', data, pos + 26)[0]
            attr_count = struct.unpack_from('<H', data, pos + 28)[0]
            attrs_base = pos + 36

            has_channel_name = False
            value_attr_pos = None

            for a in range(attr_count):
                attr_pos = attrs_base + a * attr_size
                attr_name_idx = struct.unpack_from('<i', data, attr_pos + 4)[0]
                attr_raw_value = struct.unpack_from('<i', data, attr_pos + 8)[0]
                typed_type = data[attr_pos + 15]
                typed_data = struct.unpack_from('<I', data, attr_pos + 16)[0]

                if attr_name_idx == name_attr_str_idx:
                    str_val = get_attr_string_value(strings, attr_raw_value, typed_type, typed_data)
                    if str_val == target_channel_key:
                        has_channel_name = True

                if attr_name_idx == value_attr_str_idx:
                    value_attr_pos = attr_pos

            # 如果找到了我们的渠道标签，进行 4字节 原位覆盖
            if has_channel_name and value_attr_pos is not None:
                new_value_int = int(new_channel_id)
                # 强行将类型设置为 Int(0x10)，并覆盖 4 字节的 Data
                data[value_attr_pos + 15] = TYPE_INT_DEC
                struct.pack_into('<I', data, value_attr_pos + 16, new_value_int)

                # 将原始字符串引用置为 -1，避免和字符串池产生冲突
                attr_raw_value = struct.unpack_from('<i', data, value_attr_pos + 8)[0]
                if attr_raw_value >= 0:
                    struct.pack_into('<i', data, value_attr_pos + 8, -1)

                with open(manifest_path, 'wb') as f:
                    f.write(data)
                print(f"✅ 成功将渠道号修改为: {new_channel_id}")
                return

        pos += chunk_size

if __name__ == '__main__':
    # 命令行使用示例：python patch.py AndroidManifest.xml 84
    if len(sys.argv) == 3:
        patch_channel(sys.argv[1], "MY_APP_CHANNEL_ID", sys.argv[2])
```

## 融入自动化脚本

有了这个核心脚本后，我们的多渠道打包流程可以精简为极速的四个步骤：
1. **解包**: `unzip` 解压出待修改的 `AndroidManifest.xml`。
2. **改码**: 用上文的 Python 脚本一秒修改完毕。
3. **重包**: 使用 `zip` 直接替换回原 APK 内（速度飞快）。
4. **对齐&签名**: 调用 Android 原生的 `zipalign` 和 `apksigner`（或 `uber-apk-signer`）完成最后的加工。

## 结语

在处理多渠道打包这种强需求时，很多时候我们容易陷入使用繁重三方工具的怪圈。但回到问题本质，我们发现所需的只是一次对 4 字节内存的简单赋值。通过直接与底层 AXML 结构对话，我们不仅获得了极致的速度，还成功绕开了各种不靠谱的第三方工具 Bug，实现了自动化流程的最优解。
