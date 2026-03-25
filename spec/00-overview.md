# SimpleScript Language Specification

## Overview

SimpleScript 是一门面向现代软件开发的编译型语言。语法以 Java 为基础，博采众长，
编译到 LLVM IR 并静态链接 musl libc，产出高性能、小体积的原生二进制。

## Design Philosophy

> 六边形战士：吸取各语言优点，规避它们的缺点。

### 语法设计原则

```
1. 语法只参考 Java 和 TypeScript — 全球使用人数最多、心智负担最低的两门语言
2. 绝不引入 Go/Rust/Kotlin 的奇怪语法 — 不要 :=、不要生命周期标注、
   不要 if-let/when/val/fun、不要 0..10 范围语法、不要 a to b
3. 人能读懂 — 任何 Java/TS 开发者看到 SimpleScript 代码应该立刻能理解
4. 最少关键字 — 能用现有语法表达的不发明新语法
5. 零心智负担 — 不需要学新概念，只需要用熟悉的方式写代码
```

### 吸取的优点（仅限设计思想，不引入语法）

| 来源语言 | 吸取的设计思想 | 绝不引入的语法 |
|---------|--------------|--------------|
| Java | OOP 语法、泛型、接口、JDK 25 switch | — |
| TypeScript | const/let、箭头函数、模板字符串、类型后置、import/export | — |
| Rust | Result 错误处理、枚举关联值、单态化泛型 | 生命周期 `'a`、`if let`、`match`、`impl`、`&`/`&mut` |
| Go | 虚拟线程并发思想、channel 通信 | `:=`、`func`、`if err != nil`、大写导出 |
| Kotlin | 空安全思想 | `val`/`var`/`fun`、`when`、`data class`、`sealed class`、scope functions |
| Swift | ARC 内存管理思想 | `guard`、`defer`、`protocol` |
| C | 原生性能、musl 静态链接 | 指针、手动 malloc/free |

## Core Decisions

| 决策项 | 选择 | 理由 |
|-------|------|------|
| 编译路径 | Source → LLVM IR → musl 静态链接 | 原生性能 + 极小体积 + 跨平台 |
| 内存管理 | 自动引用计数 (ARC) | 无 GC 停顿、确定性释放、零心智负担 |
| OOP | class + interface | Java 开发者零迁移成本 |
| 泛型 | 单态化 (monomorphization) | 零运行时开销 |
| 反射 | 不支持 | 保持二进制小、编译期确定一切 |
| 空安全 | 类型系统级别 (`T` vs `T?`) | 编译期消除 NPE |
| 错误处理 | Result<T, E> + `?` 操作符 | 无异常开销、显式错误流 |
| 并发 | 虚拟线程 (M:N 调度) | 同步写法、无 async 传染、百万级并发 |
| 目标平台 | Linux (首要) → macOS → Windows | musl 优先、逐步扩展 |

## Target Metrics

| 指标 | 目标 |
|------|------|
| Hello World 二进制 | < 100KB (静态链接) |
| 编译速度 | > 10万行/秒 |
| 运行时性能 | 对标 C/Rust (±10%) |
| 内存开销 | 引用计数 ≈ 每对象 8 字节 |

## Roadmap

- **Phase 1**: 核心语言 + CLI 工具链
- **Phase 2**: 标准库 + 包管理器
- **Phase 3**: 虚拟线程 + 网络库
- **Phase 4**: FFI (C interop) + 生态扩展
