---
layout: post
title:  "Rust 入门到可用：从所有权到工程实践"
date:   2026-06-23 09:30:00 +0800
categories: [技术, Rust]
tags: [rust, programming, tutorial]
permalink: /rust-from-zero-to-practical/
---

Rust 的学习难点不在语法数量，而在默认规则发生了变化。

多数语言把内存管理交给运行时或开发者经验，Rust 则把内存安全、线程安全和资源释放规则放进编译期。代码只有通过这些规则，才允许生成可执行文件。

这篇文章按「能写出可维护 Rust 程序」的目标组织内容。它不会覆盖标准库每个 API，也不会把 Rust 写成语法速查表。重点是建立一条主线：类型如何表达数据，所有权如何管理资源，错误如何向上传递，工程如何组织和验证。

示例会围绕一个小型日志分析器展开：读取日志文本，解析日志级别，统计各类日志数量，最后输出结果。这个例子足够小，但能覆盖 Rust 日常开发的大部分基础能力。

---

## 1. Rust 适合解决什么问题

Rust 是一门系统级编程语言，目标是同时获得三件事：

- **内存安全**：避免悬垂指针、重复释放、越界访问等问题。
- **并发安全**：在编译期尽量阻止数据竞争。
- **低运行时开销**：没有强制垃圾回收，抽象通常会被编译器优化掉。

这决定了 Rust 的典型使用场景：

- 命令行工具。
- 高性能服务端组件。
- 跨平台核心库。
- 嵌入式、操作系统、数据库、浏览器引擎等底层系统。
- 需要从动态语言或 JVM 语言下沉到 Native 层的性能热点。

Rust 不适合所有场景。如果业务主要依赖成熟框架、快速迭代 UI 和大量现成生态，Rust 未必是最短路径。它的价值通常出现在资源管理、性能边界、并发正确性和跨平台复用这些位置。

## 2. 安装与第一个项目

Rust 官方工具链通过 `rustup` 管理。安装后常用工具包括：

- `rustc`：编译器。
- `cargo`：构建、测试、依赖管理和发布工具。
- `rustfmt`：代码格式化工具。
- `clippy`：静态检查工具。

创建项目：

```bash
cargo new log-analyzer
cd log-analyzer
cargo run
```

生成的目录结构如下：

```text
log-analyzer
├── Cargo.toml
└── src
    └── main.rs
```

`Cargo.toml` 是项目配置文件，类似构建脚本和依赖清单的组合：

```toml
[package]
name = "log-analyzer"
version = "0.1.0"
edition = "2024"

[dependencies]
```

`src/main.rs` 是二进制程序入口：

```rust
fn main() {
    println!("Hello, world!");
}
```

运行命令：

```bash
cargo run
```

常用 Cargo 命令如下：

| 命令 | 作用 |
|------|------|
| `cargo new app` | 创建项目 |
| `cargo run` | 编译并运行 |
| `cargo build` | 编译项目 |
| `cargo build --release` | 以发布模式编译 |
| `cargo test` | 运行测试 |
| `cargo fmt` | 格式化代码 |
| `cargo clippy` | 运行静态检查 |

Rust 工程通常不直接调用 `rustc`，而是通过 `cargo` 完成日常操作。

## 3. 变量、可变性和表达式

Rust 变量默认不可变：

```rust
fn main() {
    let count = 10;
    println!("{count}");
}
```

如果需要修改，必须显式加 `mut`：

```rust
fn main() {
    let mut count = 10;
    count += 1;
    println!("{count}");
}
```

这个设计不是语法洁癖，而是减少状态变化。默认不可变后，函数内部哪些值会变得更清楚。

Rust 支持变量遮蔽：

```rust
fn main() {
    let raw = "42";
    let raw = raw.parse::<i32>().unwrap();
    println!("{raw}");
}
```

第二个 `raw` 是新变量，不是修改旧变量。遮蔽常用于把一个值从原始形态转换成更精确的形态。

Rust 中很多结构是表达式。表达式会产生值：

```rust
fn main() {
    let score = 82;

    let level = if score >= 60 {
        "pass"
    } else {
        "fail"
    };

    println!("{level}");
}
```

注意 `if` 两个分支必须返回同一类型。Rust 不会把类型差异留到运行时再处理。

## 4. 函数和返回值

Rust 函数使用 `fn` 定义：

```rust
fn add(left: i32, right: i32) -> i32 {
    left + right
}

fn main() {
    println!("{}", add(1, 2));
}
```

函数体最后一行没有分号时，会作为返回值：

```rust
fn is_error(level: &str) -> bool {
    level == "ERROR"
}
```

加上分号后就变成语句，语句不返回业务值：

```rust
fn broken() -> i32 {
    1;
}
```

这段代码无法编译，因为函数声明返回 `i32`，实际返回的是空值 `()`。

Rust 的空值类型叫 `()`，类似「没有有意义的返回值」。

## 5. 基础类型

常见标量类型如下：

| 类型 | 示例 | 说明 |
|------|------|------|
| `bool` | `true` | 布尔值 |
| `i32` | `-1` | 32 位有符号整数 |
| `u64` | `42` | 64 位无符号整数 |
| `f64` | `3.14` | 64 位浮点数 |
| `char` | `'中'` | Unicode 标量值 |
| `()` | `()` | 空值 |

复合类型包括元组和数组：

```rust
fn main() {
    let point: (i32, i32) = (10, 20);
    let first = point.0;

    let numbers: [i32; 3] = [1, 2, 3];
    let second = numbers[1];

    println!("{first}, {second}");
}
```

数组长度是类型的一部分，`[i32; 3]` 和 `[i32; 4]` 是不同类型。动态长度集合通常使用 `Vec<T>`。

## 6. 所有权：Rust 最核心的规则

Rust 没有强制垃圾回收。每个值都有一个所有者，所有者离开作用域时，值会被释放。

```rust
fn main() {
    let message = String::from("hello");
    println!("{message}");
}
```

`message` 离开 `main` 作用域后，它持有的堆内存会自动释放。

所有权有三条核心规则：

- 每个值在同一时间只有一个所有者。
- 所有者离开作用域，值被释放。
- 赋值、传参和返回值可能发生所有权转移。

看一段容易踩坑的代码：

```rust
fn main() {
    let a = String::from("hello");
    let b = a;

    println!("{a}");
    println!("{b}");
}
```

这段代码不能编译。`String` 持有堆内存，`let b = a` 会把所有权从 `a` 移动到 `b`。移动之后，`a` 不能继续使用。

如果确实需要复制堆数据，可以显式调用 `clone`：

```rust
fn main() {
    let a = String::from("hello");
    let b = a.clone();

    println!("{a}");
    println!("{b}");
}
```

`clone` 可能产生真实开销。Rust 要求把这种开销写出来，避免隐式深拷贝。

对于整数、布尔值这类简单类型，赋值通常是复制：

```rust
fn main() {
    let a = 1;
    let b = a;

    println!("{a}");
    println!("{b}");
}
```

这类类型实现了 `Copy` trait。复制成本低，不需要转移所有权。

## 7. 借用和引用

如果函数只是读取一个值，不应该拿走所有权。此时使用引用：

```rust
fn length(value: &String) -> usize {
    value.len()
}

fn main() {
    let message = String::from("hello");
    let size = length(&message);

    println!("{message}, {size}");
}
```

`&message` 表示借用，函数参数 `&String` 表示只读引用。调用后，`message` 仍然可用。

更常见的写法是使用 `&str`：

```rust
fn length(value: &str) -> usize {
    value.len()
}

fn main() {
    let owned = String::from("hello");
    let literal = "world";

    println!("{}", length(&owned));
    println!("{}", length(literal));
}
```

`String` 是可增长的堆字符串，拥有数据所有权。`&str` 是字符串切片，只是指向一段 UTF-8 文本的引用。

函数参数优先使用 `&str`，可以同时接收 `String` 和字符串字面量，接口更灵活。

## 8. 可变引用

读取用不可变引用，修改用可变引用：

```rust
fn append_error(line: &mut String) {
    line.push_str(" ERROR");
}

fn main() {
    let mut line = String::from("2026-06-23");
    append_error(&mut line);
    println!("{line}");
}
```

可变引用有严格限制：

- 同一时间只能有一个可变引用。
- 可变引用存在时，不能同时存在普通引用。

下面的代码不能编译：

```rust
fn main() {
    let mut line = String::from("hello");
    let first = &line;
    let second = &mut line;

    println!("{first}");
    println!("{second}");
}
```

原因是 `first` 还在使用期间，`second` 试图修改同一份数据。Rust 在编译期阻止这种不确定行为。

这条规则是并发安全的基础：要么多人只读，要么一人修改。

## 9. 生命周期先按使用规则理解

生命周期是 Rust 中容易被夸大的概念。入门阶段先记住一句话：引用不能比它指向的数据活得更久。

下面的代码不能编译：

```rust
fn broken() -> &str {
    let value = String::from("temporary");
    &value
}
```

`value` 在函数结束时释放，返回的引用会指向已释放的内存。Rust 直接拒绝编译。

正确做法是返回拥有所有权的值：

```rust
fn build_message() -> String {
    String::from("temporary")
}
```

多数业务代码不需要手写生命周期标注。编译器可以根据规则推导：

```rust
fn first_word(value: &str) -> &str {
    value.split_whitespace().next().unwrap_or("")
}
```

当一个函数接收多个引用，又返回引用时，编译器可能需要显式生命周期帮助判断返回值来自哪里：

```rust
fn longer<'a>(left: &'a str, right: &'a str) -> &'a str {
    if left.len() >= right.len() {
        left
    } else {
        right
    }
}
```

`'a` 不是延长生命周期的工具，只是在描述输入引用和输出引用之间的关系。

## 10. 用 struct 表达数据

日志分析器需要表达一行日志：

```rust
#[derive(Debug)]
struct LogEntry {
    level: String,
    message: String,
}

fn main() {
    let entry = LogEntry {
        level: String::from("ERROR"),
        message: String::from("database timeout"),
    };

    println!("{entry:?}");
}
```

`struct` 类似具名字段的数据结构。`#[derive(Debug)]` 让结构体可以用 `{:?}` 打印。

可以为结构体实现方法：

```rust
#[derive(Debug)]
struct LogEntry {
    level: String,
    message: String,
}

impl LogEntry {
    fn is_error(&self) -> bool {
        self.level == "ERROR"
    }
}

fn main() {
    let entry = LogEntry {
        level: String::from("ERROR"),
        message: String::from("database timeout"),
    };

    println!("{}", entry.is_error());
}
```

`&self` 是 `self: &Self` 的简写，表示方法只读取当前对象。

如果方法需要修改字段，使用 `&mut self`：

```rust
impl LogEntry {
    fn normalize_level(&mut self) {
        self.level = self.level.to_uppercase();
    }
}
```

如果方法要消费整个对象，使用 `self`：

```rust
impl LogEntry {
    fn into_message(self) -> String {
        self.message
    }
}
```

## 11. enum、Option 和 Result

Rust 的 `enum` 比很多语言中的枚举更强。它可以携带数据：

```rust
#[derive(Debug, Eq, Hash, PartialEq)]
enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Unknown(String),
}
```

解析日志级别：

```rust
fn parse_level(raw: &str) -> LogLevel {
    match raw {
        "TRACE" => LogLevel::Trace,
        "DEBUG" => LogLevel::Debug,
        "INFO" => LogLevel::Info,
        "WARN" => LogLevel::Warn,
        "ERROR" => LogLevel::Error,
        other => LogLevel::Unknown(other.to_string()),
    }
}
```

`match` 必须覆盖所有情况。这个要求让新增分支时更容易发现遗漏。

Rust 没有空引用作为普通返回方式，而是使用 `Option<T>`：

```rust
fn first_token(line: &str) -> Option<&str> {
    line.split_whitespace().next()
}

fn main() {
    match first_token("ERROR database timeout") {
        Some(token) => println!("{token}"),
        None => println!("empty line"),
    }
}
```

`Option<T>` 只有两个可能：

```rust
enum Option<T> {
    Some(T),
    None,
}
```

可能失败的操作使用 `Result<T, E>`：

```rust
enum Result<T, E> {
    Ok(T),
    Err(E),
}
```

例如解析数字：

```rust
fn parse_count(raw: &str) -> Result<u32, std::num::ParseIntError> {
    raw.parse::<u32>()
}
```

`Option` 表示「可能没有值」，`Result` 表示「可能失败，并且需要错误原因」。

## 12. 错误处理和问号运算符

Rust 不使用异常作为常规错误传递机制。函数签名会直接说明是否可能失败。

读取文件内容：

```rust
use std::fs;
use std::io;

fn read_log(path: &str) -> Result<String, io::Error> {
    fs::read_to_string(path)
}
```

如果函数内部有多个可能失败的步骤，可以用 `?` 向上传递错误：

```rust
use std::fs;
use std::io;

fn read_first_line(path: &str) -> Result<String, io::Error> {
    let content = fs::read_to_string(path)?;
    let first = content.lines().next().unwrap_or("").to_string();
    Ok(first)
}
```

`?` 的含义是：

- 如果是 `Ok(value)`，取出 `value` 继续执行。
- 如果是 `Err(error)`，直接从当前函数返回 `Err(error)`。

`main` 函数也可以返回 `Result`：

```rust
use std::error::Error;
use std::fs;

fn main() -> Result<(), Box<dyn Error>> {
    let content = fs::read_to_string("app.log")?;
    println!("{content}");
    Ok(())
}
```

`Box<dyn Error>` 可以承载多种错误类型，适合小工具和示例程序。大型项目通常会定义更精确的错误类型，或使用 `thiserror`、`anyhow` 等库。

## 13. 完成第一个日志解析器

先准备一段日志文本：

```text
INFO server started
WARN cache miss
ERROR database timeout
INFO request completed
ERROR payment failed
```

实现解析和统计：

```rust
use std::collections::HashMap;

#[derive(Debug, Eq, Hash, PartialEq)]
enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Unknown(String),
}

#[derive(Debug)]
struct LogEntry {
    level: LogLevel,
    message: String,
}

fn parse_level(raw: &str) -> LogLevel {
    match raw {
        "TRACE" => LogLevel::Trace,
        "DEBUG" => LogLevel::Debug,
        "INFO" => LogLevel::Info,
        "WARN" => LogLevel::Warn,
        "ERROR" => LogLevel::Error,
        other => LogLevel::Unknown(other.to_string()),
    }
}

fn parse_line(line: &str) -> Option<LogEntry> {
    let mut parts = line.splitn(2, ' ');
    let level = parts.next()?;
    let message = parts.next().unwrap_or("").trim();

    Some(LogEntry {
        level: parse_level(level),
        message: message.to_string(),
    })
}

fn analyze(content: &str) -> HashMap<LogLevel, usize> {
    let mut result = HashMap::new();

    for line in content.lines() {
        if let Some(entry) = parse_line(line) {
            *result.entry(entry.level).or_insert(0) += 1;
        }
    }

    result
}

fn main() {
    let content = "\
INFO server started
WARN cache miss
ERROR database timeout
INFO request completed
ERROR payment failed";

    let result = analyze(content);
    println!("{result:?}");
}
```

这段代码已经覆盖多个关键点：

- `LogLevel` 用 `enum` 表达有限集合。
- `LogEntry` 用 `struct` 表达一行结构化日志。
- `parse_line` 用 `Option` 表达空行或非法行。
- `HashMap` 负责统计。
- `entry` API 负责处理「不存在则插入」的计数场景。

`*result.entry(entry.level).or_insert(0) += 1;` 是这一节最密集的一行。拆开理解：

```rust
let counter = result.entry(entry.level).or_insert(0);
*counter += 1;
```

`or_insert(0)` 返回的是可变引用 `&mut usize`，所以需要用 `*counter` 解引用后修改计数。

## 14. Vec、HashMap 和常用集合

`Vec<T>` 是动态数组：

```rust
fn main() {
    let mut numbers = Vec::new();
    numbers.push(1);
    numbers.push(2);
    numbers.push(3);

    println!("{numbers:?}");
}
```

也可以用宏创建：

```rust
fn main() {
    let numbers = vec![1, 2, 3];
    println!("{numbers:?}");
}
```

读取元素时，索引访问可能 panic：

```rust
fn main() {
    let numbers = vec![1, 2, 3];
    println!("{}", numbers[10]);
}
```

更稳妥的方式是 `get`：

```rust
fn main() {
    let numbers = vec![1, 2, 3];

    match numbers.get(10) {
        Some(value) => println!("{value}"),
        None => println!("not found"),
    }
}
```

`HashMap<K, V>` 是哈希表：

```rust
use std::collections::HashMap;

fn main() {
    let mut counts = HashMap::new();
    counts.insert("ERROR", 2);
    counts.insert("WARN", 1);

    println!("{counts:?}");
}
```

更新计数的惯用写法：

```rust
use std::collections::HashMap;

fn main() {
    let mut counts = HashMap::new();

    for level in ["INFO", "ERROR", "INFO"] {
        *counts.entry(level).or_insert(0) += 1;
    }

    println!("{counts:?}");
}
```

集合会涉及所有权。把 `String` 放进 `Vec<String>` 后，集合拥有这些字符串：

```rust
fn main() {
    let item = String::from("ERROR");
    let values = vec![item];

    println!("{values:?}");
}
```

`item` 已经移动进 `values`，后续不能再直接使用 `item`。

## 15. 迭代器

Rust 的迭代器是惰性的。调用 `map`、`filter` 不会立即执行，直到 `collect`、`for`、`count` 等消费操作出现。

把日志行解析成结构化数据：

```rust
#[derive(Debug)]
struct LogEntry {
    level: String,
    message: String,
}

fn parse_line(line: &str) -> Option<LogEntry> {
    let mut parts = line.splitn(2, ' ');
    let level = parts.next()?;
    let message = parts.next().unwrap_or("");

    Some(LogEntry {
        level: level.to_string(),
        message: message.to_string(),
    })
}

fn main() {
    let content = "INFO ok\nERROR failed\nWARN slow";

    let errors: Vec<LogEntry> = content
        .lines()
        .filter_map(parse_line)
        .filter(|entry| entry.level == "ERROR")
        .collect();

    println!("{errors:?}");
}
```

几个常见方法：

| 方法 | 作用 |
|------|------|
| `iter()` | 借用迭代 |
| `iter_mut()` | 可变借用迭代 |
| `into_iter()` | 消费集合并取得所有权 |
| `map()` | 转换每个元素 |
| `filter()` | 保留符合条件的元素 |
| `filter_map()` | 过滤并转换 `Option` |
| `collect()` | 收集为集合 |

三种迭代方式的所有权差异非常重要：

```rust
fn main() {
    let values = vec![String::from("a"), String::from("b")];

    for value in values.iter() {
        println!("{value}");
    }

    println!("{}", values.len());
}
```

`iter()` 只借用，循环结束后 `values` 仍然可用。

```rust
fn main() {
    let values = vec![String::from("a"), String::from("b")];

    for value in values.into_iter() {
        println!("{value}");
    }
}
```

`into_iter()` 消费集合。循环后不能再使用 `values`。

## 16. trait：Rust 的抽象方式

`trait` 定义一组行为，类似「某个类型具备什么能力」。

```rust
trait Summary {
    fn summary(&self) -> String;
}

struct LogEntry {
    level: String,
    message: String,
}

impl Summary for LogEntry {
    fn summary(&self) -> String {
        format!("[{}] {}", self.level, self.message)
    }
}

fn print_summary(item: &impl Summary) {
    println!("{}", item.summary());
}
```

`impl Summary` 表示参数可以是任何实现了 `Summary` 的类型。

泛型写法等价但更明确：

```rust
fn print_summary<T: Summary>(item: &T) {
    println!("{}", item.summary());
}
```

trait 也可以提供默认实现：

```rust
trait Named {
    fn name(&self) -> &str;

    fn display_name(&self) -> String {
        format!("name={}", self.name())
    }
}
```

Rust 的很多能力都通过 trait 表达，例如：

- `Debug`：支持 `{:?}` 打印。
- `Clone`：支持显式克隆。
- `Copy`：支持按位复制。
- `Default`：支持默认值。
- `From`/`Into`：支持类型转换。
- `Iterator`：支持迭代。

`derive` 可以让编译器为简单类型自动生成 trait 实现：

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
struct User {
    id: u64,
    name: String,
}
```

## 17. 泛型

泛型让函数或类型不绑定具体类型：

```rust
fn first<T>(values: &[T]) -> Option<&T> {
    values.first()
}
```

`T` 是类型参数。`&[T]` 是切片，表示一段连续的 `T`。

如果泛型函数需要调用某些方法，就要加 trait 约束：

```rust
use std::fmt::Debug;

fn print_first<T: Debug>(values: &[T]) {
    if let Some(value) = values.first() {
        println!("{value:?}");
    }
}
```

多个约束可以使用 `+`：

```rust
use std::fmt::Debug;

fn duplicate<T: Clone + Debug>(value: T) -> T {
    println!("{value:?}");
    value.clone()
}
```

约束复杂时可以使用 `where`：

```rust
use std::fmt::Debug;

fn print_pair<T, U>(left: T, right: U)
where
    T: Debug,
    U: Debug,
{
    println!("{left:?}, {right:?}");
}
```

泛型不是运行时动态分发的默认方案。Rust 通常会为具体类型生成专门代码，这也是它能保持性能的重要原因。

## 18. 模块和工程组织

当代码变多后，应拆分模块。

推荐结构：

```text
src
├── analyzer.rs
├── log_entry.rs
└── main.rs
```

`src/log_entry.rs`：

```rust
#[derive(Debug, Eq, Hash, PartialEq)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Unknown(String),
}

#[derive(Debug)]
pub struct LogEntry {
    pub level: LogLevel,
    pub message: String,
}

pub fn parse_level(raw: &str) -> LogLevel {
    match raw {
        "TRACE" => LogLevel::Trace,
        "DEBUG" => LogLevel::Debug,
        "INFO" => LogLevel::Info,
        "WARN" => LogLevel::Warn,
        "ERROR" => LogLevel::Error,
        other => LogLevel::Unknown(other.to_string()),
    }
}

pub fn parse_line(line: &str) -> Option<LogEntry> {
    let mut parts = line.splitn(2, ' ');
    let level = parts.next()?;
    let message = parts.next().unwrap_or("").trim();

    Some(LogEntry {
        level: parse_level(level),
        message: message.to_string(),
    })
}
```

`src/analyzer.rs`：

```rust
use std::collections::HashMap;

use crate::log_entry::{parse_line, LogLevel};

pub fn analyze(content: &str) -> HashMap<LogLevel, usize> {
    let mut result = HashMap::new();

    for line in content.lines() {
        if let Some(entry) = parse_line(line) {
            *result.entry(entry.level).or_insert(0) += 1;
        }
    }

    result
}
```

`src/main.rs`：

```rust
mod analyzer;
mod log_entry;

use analyzer::analyze;

fn main() {
    let content = "\
INFO server started
WARN cache miss
ERROR database timeout";

    let result = analyze(content);
    println!("{result:?}");
}
```

关键规则：

- `mod log_entry;` 声明模块。
- `pub` 暴露给模块外部。
- `crate::log_entry` 从当前 crate 根模块开始查找。
- 默认私有，只有显式 `pub` 才能从外部访问。

Rust 的包管理概念：

| 概念 | 说明 |
|------|------|
| package | 一个 `Cargo.toml` 描述的包 |
| crate | 一个编译单元，可以是库或二进制 |
| module | crate 内部的代码组织单元 |
| workspace | 多个 package 的工作区 |

入门阶段先掌握 package、crate、module 三个概念即可。

## 19. 测试

Rust 内置测试框架，不需要额外依赖。

可以在同一个文件里写单元测试：

```rust
#[derive(Debug, Eq, PartialEq)]
enum LogLevel {
    Info,
    Error,
    Unknown(String),
}

fn parse_level(raw: &str) -> LogLevel {
    match raw {
        "INFO" => LogLevel::Info,
        "ERROR" => LogLevel::Error,
        other => LogLevel::Unknown(other.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_known_level() {
        assert_eq!(parse_level("ERROR"), LogLevel::Error);
    }

    #[test]
    fn keeps_unknown_level() {
        assert_eq!(
            parse_level("FATAL"),
            LogLevel::Unknown(String::from("FATAL"))
        );
    }
}
```

运行测试：

```bash
cargo test
```

测试模块常用 `#[cfg(test)]` 标记，只在测试编译时启用。

集成测试放在 `tests/` 目录：

```text
tests
└── analyzer_test.rs
```

集成测试会从外部使用库 crate，因此适合验证公开 API。要写集成测试，通常需要把核心逻辑放进 `src/lib.rs`，再由 `src/main.rs` 调用。

## 20. 调试和常用宏

常用输出宏：

```rust
fn main() {
    let value = 42;

    println!("value={value}");
    eprintln!("error={value}");
    dbg!(value);
}
```

差异如下：

| 宏 | 作用 |
|----|------|
| `println!` | 输出到标准输出 |
| `eprintln!` | 输出到标准错误 |
| `dbg!` | 打印表达式、文件和行号，并返回表达式所有权 |

格式化输出：

```rust
fn main() {
    let name = "rust";
    let count = 3;

    println!("{name}");
    println!("{count:?}");
    println!("{count:#?}");
}
```

`{:?}` 依赖 `Debug`，`{}` 依赖 `Display`。业务结构体通常先 `derive(Debug)`，需要面向用户的格式化结果时再实现 `Display`。

## 21. 并发：所有权进入线程

Rust 标准库可以直接创建线程：

```rust
use std::thread;

fn main() {
    let handle = thread::spawn(|| {
        println!("run in thread");
    });

    handle.join().unwrap();
}
```

线程闭包如果要使用外部变量，通常需要 `move`：

```rust
use std::thread;

fn main() {
    let message = String::from("hello");

    let handle = thread::spawn(move || {
        println!("{message}");
    });

    handle.join().unwrap();
}
```

`move` 把 `message` 的所有权移动到新线程，避免主线程提前释放数据。

多个线程之间传递消息可以使用 channel：

```rust
use std::sync::mpsc;
use std::thread;

fn main() {
    let (sender, receiver) = mpsc::channel();

    thread::spawn(move || {
        sender.send(String::from("done")).unwrap();
    });

    let message = receiver.recv().unwrap();
    println!("{message}");
}
```

共享状态通常使用 `Arc<Mutex<T>>`：

```rust
use std::sync::{Arc, Mutex};
use std::thread;

fn main() {
    let counter = Arc::new(Mutex::new(0));
    let mut handles = Vec::new();

    for _ in 0..4 {
        let counter = Arc::clone(&counter);
        let handle = thread::spawn(move || {
            let mut value = counter.lock().unwrap();
            *value += 1;
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap();
    }

    println!("{}", *counter.lock().unwrap());
}
```

含义如下：

- `Arc<T>` 是线程安全的引用计数指针，用于多个线程共享所有权。
- `Mutex<T>` 保证同一时间只有一个线程能修改内部数据。
- `lock()` 返回锁保护的数据引用。

Rust 不是让并发变得无需思考，而是把很多错误提前到编译期和类型层面。

## 22. async 入门边界

Rust 支持 `async`/`await`，但标准库不自带完整异步运行时。实际项目通常选择 `tokio` 或 `async-std`。

异步函数写法：

```rust
async fn fetch() -> String {
    String::from("result")
}
```

`async fn` 返回的是 Future。Future 需要运行时轮询，才会真正执行。

使用 `tokio` 的最小示例：

```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
```

```rust
#[tokio::main]
async fn main() {
    let value = fetch().await;
    println!("{value}");
}

async fn fetch() -> String {
    String::from("result")
}
```

入门阶段不建议同时深挖所有权、生命周期和 async。优先掌握同步 Rust，再进入 async，会少很多干扰。

## 23. 宏和派生

Rust 宏以 `!` 结尾：

```rust
fn main() {
    println!("hello");
    vec![1, 2, 3];
}
```

常见宏：

| 宏 | 作用 |
|----|------|
| `println!` | 格式化输出 |
| `format!` | 生成 `String` |
| `vec!` | 创建 `Vec` |
| `dbg!` | 调试输出 |
| `assert_eq!` | 测试断言 |

派生宏使用 `derive` 属性：

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
struct Config {
    host: String,
    port: u16,
}
```

宏可以生成代码，但入门阶段只需要会读常见宏。自定义宏不是学习 Rust 的第一优先级。

## 24. 常见错误和排查方式

### 24.1 value borrowed here after move

典型代码：

```rust
fn main() {
    let value = String::from("hello");
    let other = value;
    println!("{value}");
    println!("{other}");
}
```

含义：`value` 的所有权已经移动到 `other`，不能再使用 `value`。

常见修复方式：

- 如果后续不需要原变量，删除后续使用。
- 如果只需要读取，改成引用。
- 如果确实需要两份数据，显式 `clone`。

### 24.2 cannot borrow as mutable

典型代码：

```rust
fn main() {
    let value = String::from("hello");
    value.push_str(" world");
}
```

含义：变量默认不可变。

修复：

```rust
fn main() {
    let mut value = String::from("hello");
    value.push_str(" world");
}
```

### 24.3 cannot borrow as mutable because it is also borrowed as immutable

典型代码：

```rust
fn main() {
    let mut value = String::from("hello");
    let read = &value;
    let write = &mut value;

    println!("{read}");
    println!("{write}");
}
```

含义：同一时间不能既有人读，又有人写。

修复方式是缩短不可变引用的使用范围：

```rust
fn main() {
    let mut value = String::from("hello");

    {
        let read = &value;
        println!("{read}");
    }

    let write = &mut value;
    write.push_str(" world");
}
```

### 24.4 mismatched types

Rust 类型检查很严格。常见问题是 `String` 和 `&str` 混用：

```rust
fn print(value: String) {
    println!("{value}");
}

fn main() {
    print("hello");
}
```

修复方式之一是让函数接收 `&str`：

```rust
fn print(value: &str) {
    println!("{value}");
}

fn main() {
    print("hello");
}
```

如果函数确实需要拥有字符串，调用处转换：

```rust
fn print(value: String) {
    println!("{value}");
}

fn main() {
    print(String::from("hello"));
}
```

## 25. 项目实践建议

Rust 入门最容易误入两个方向：一是只背所有权规则，迟迟不写完整程序；二是直接进入 async、宏、unsafe，导致错误信息密度过高。

更稳妥的学习路径如下：

1. 先写命令行工具，熟悉 `cargo`、`Result`、文件 IO、集合和测试。
2. 再写一个小型库，练习模块、公开 API、错误类型和文档注释。
3. 再引入第三方库，例如 `serde`、`clap`、`reqwest`。
4. 最后学习 async、FFI、宏和 unsafe。

工程中可以遵循几条规则：

- 函数参数优先使用借用，例如 `&str`、`&[T]`。
- 返回值需要离开函数时，返回拥有所有权的类型，例如 `String`、`Vec<T>`。
- 不要为了通过编译到处 `clone`，先判断所有权是否真的需要复制。
- 能用 `Option` 和 `Result` 表达的情况，不要用特殊值表示失败。
- 公共 API 要暴露清晰类型，不要让调用方猜测字符串格式。
- 每次遇到编译错误，先读第一条错误信息和对应代码位置。

## 26. 什么时候使用 unsafe

`unsafe` 不是关闭 Rust 安全系统，而是告诉编译器：这段代码的某些安全条件由开发者保证。

常见使用场景：

- 调用 C API。
- 操作裸指针。
- 实现底层数据结构。
- 编写性能敏感且编译器无法证明安全性的代码。

入门阶段不需要写 `unsafe`。能够用安全 Rust 表达的逻辑，应优先使用安全 Rust。

安全 Rust 已经能覆盖大部分业务代码、命令行工具、网络服务和库开发。`unsafe` 应被限制在很小范围内，并通过安全 API 包装起来。

## 27. FFI 的基本概念

Rust 可以通过 FFI 与 C ABI 交互。最小示例：

```rust
#[unsafe(no_mangle)]
pub extern "C" fn add(left: i32, right: i32) -> i32 {
    left + right
}
```

含义如下：

- `extern "C"` 使用 C ABI。
- `no_mangle` 保留函数名，便于外部链接。
- FFI 边界尽量使用 C 兼容类型，例如整数、指针、长度。

复杂数据结构不应直接穿过 FFI 边界。常见做法是：

- 外部传入指针和长度。
- Rust 内部转换成安全类型。
- Rust 对外暴露少量稳定函数。
- 字符串和内存释放规则必须明确。

FFI 是 Rust 进入既有 Native 体系的重要方式，但它也会带来内存所有权边界问题。入门阶段先理解概念，实际项目中再结合目标平台细化。

## 28. 一份完整可运行版本

下面是一份单文件版本，可直接放入 `src/main.rs` 运行：

```rust
use std::collections::HashMap;
use std::error::Error;
use std::fs;

#[derive(Debug, Eq, Hash, PartialEq)]
enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Unknown(String),
}

#[derive(Debug)]
struct LogEntry {
    level: LogLevel,
    message: String,
}

fn parse_level(raw: &str) -> LogLevel {
    match raw {
        "TRACE" => LogLevel::Trace,
        "DEBUG" => LogLevel::Debug,
        "INFO" => LogLevel::Info,
        "WARN" => LogLevel::Warn,
        "ERROR" => LogLevel::Error,
        other => LogLevel::Unknown(other.to_string()),
    }
}

fn parse_line(line: &str) -> Option<LogEntry> {
    let mut parts = line.splitn(2, ' ');
    let level = parts.next()?;
    let message = parts.next().unwrap_or("").trim();

    Some(LogEntry {
        level: parse_level(level),
        message: message.to_string(),
    })
}

fn analyze(content: &str) -> HashMap<LogLevel, usize> {
    let mut result = HashMap::new();

    for line in content.lines() {
        if let Some(entry) = parse_line(line) {
            *result.entry(entry.level).or_insert(0) += 1;
        }
    }

    result
}

fn main() -> Result<(), Box<dyn Error>> {
    let path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| String::from("app.log"));

    let content = fs::read_to_string(path)?;
    let result = analyze(&content);

    for (level, count) in result {
        println!("{level:?}: {count}");
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_known_level() {
        assert_eq!(parse_level("ERROR"), LogLevel::Error);
    }

    #[test]
    fn parses_unknown_level() {
        assert_eq!(
            parse_level("FATAL"),
            LogLevel::Unknown(String::from("FATAL"))
        );
    }

    #[test]
    fn parses_log_line() {
        let entry = parse_line("WARN cache miss").unwrap();

        assert_eq!(entry.level, LogLevel::Warn);
        assert_eq!(entry.message, "cache miss");
    }

    #[test]
    fn analyzes_content() {
        let content = "\
INFO started
ERROR timeout
ERROR failed";

        let result = analyze(content);

        assert_eq!(result.get(&LogLevel::Info), Some(&1));
        assert_eq!(result.get(&LogLevel::Error), Some(&2));
    }
}
```

准备 `app.log`：

```text
INFO server started
WARN cache miss
ERROR database timeout
INFO request completed
ERROR payment failed
```

运行：

```bash
cargo run -- app.log
```

测试：

```bash
cargo test
```

这份代码不是 Rust 的全部，但已经包含日常开发最常用的骨架：类型建模、解析、错误处理、集合统计、命令行参数、文件读取和测试。

## 29. 总结

Rust 的核心不是「语法复杂」，而是把资源管理规则前移到编译期。

入门时应优先掌握五件事：

- **所有权**：谁负责释放数据。
- **借用**：如何在不转移所有权的情况下读取或修改数据。
- **类型建模**：用 `struct`、`enum`、`Option`、`Result` 表达业务状态。
- **错误处理**：用 `Result` 和 `?` 让失败路径显式存在。
- **工程实践**：用 Cargo、测试、模块和 trait 组织代码。

Rust 的学习曲线前段较陡，但它的回报也很直接：一旦代码通过编译，很多内存和并发问题已经被排除在运行时之外。真正掌握 Rust，不是记住所有规则，而是形成一个稳定判断：什么时候该拥有数据，什么时候该借用数据，什么时候该把失败写进类型。
