# Spec Implementation Status

Status: ✅ Done | 🔶 Partial | ❌ Not started | 📄 Doc only | 🚫 Rejected

## Language Core

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 00 | Language Overview | ✅ | 设计理念已实现，语言可自举 |
| 01 | Syntax & Type System | 🔶 | int/double/string/bool done。缺: byte/short/long/float/char/uint/ulong/any |
| 31 | Type Inference | ✅ | checkerInferType 8 check sites (D053-D065)。inferType 迁移已分析关闭 (D066) |
| 40 | Numeric Types | 🔶 | 只有 int (i32) + double (f64)。缺: byte/short/long/float/unsigned |
| 41 | Grammar Summary | 📄 | 参考文档 |
| 42 | Access Modifiers | ❌ | 无 export/protected/internal，无可见性控制 |
| 43 | Null Safety | 🔶 | D067 Phase 1 done：T? 类型、checker null 检查、ptr 比较、?? null 合并。Phase 2 (smart narrowing) 待实现 |
| 34 | String Advanced | 🔶 | 模板字符串 + 基本方法 done。缺: UTF-8 proper (当前 null-terminated) |
| 37 | Range & Tuple | 🔶 | Tuple done (D034), for-in done。Range 语法不做（TS 无对应语法） |

## Memory & Error Handling

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 03 | Memory (ARC) | ✅ | Perceus RC Phase 1 complete, mimalloc 集成 |
| 71 | Perceus RC | ✅ | TypeInfo + drop/clone gen + PIR liveness + REUSE |
| 02 | Error Handling | ❌ | 当前 try/catch (setjmp/longjmp)。需: Result<T,E> + ? 操作符 |
| 29 | Error Codes | 🔶 | checker 错误有源码位置 + 建议。缺: 完整错误编号体系 |
| 38 | Exception Interop | ❌ | 无 panic/recover 区分 |

## Concurrency

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 04 | Virtual Threads | ❌ | 无并发支持 |
| 28 | Async I/O | ❌ | 所有 I/O 同步阻塞 |
| 68 | Async Tasks | ❌ | 无后台任务 |

## OOP & Type Features

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 32 | Inheritance | 🔶 | class/extends/interface done。缺: open/abstract 修饰符 |
| 23 | Generics Advanced | 🔶 | 泛型函数/类/约束/多约束 done。缺: 协变/逆变 |
| 44 | Generic Constraints | ✅ | D031 type constraints + multi-constraints |
| 27 | Pattern Matching | 🔶 | switch enum/bool done (D029)。类型模式 + guard 不做（TS 无对应语法） |
| 36 | Destructuring | ✅ | array + object destructuring done |
| 16 | Operator Overloading | ❌ | 无运算符重载 |
| 35 | Scope Functions | 🚫 | 明确拒绝 Kotlin 风格 scope functions |

## Module System & Build

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 11 | Module System | 🔶 | import 工作。缺: export 可见性控制 |
| 07 | Package Manager | ❌ | ss.json 有雏形，无依赖管理/registry |
| 09 | Toolchain | 🔶 | build/run/test/check/fmt/repl/new/clean done。缺: lint/publish/bench |
| 12 | Compiler | 🔶 | SS 自举 (非 Rust)，LLVM IR pipeline 完整 |
| 30 | Prelude | ✅ | prelude.ss 自动注入 |
| 33 | Cross Compilation | ❌ | 仅 Linux x86_64 |
| 50 | File Extension | ✅ | .ss / ss.json 约定 |
| 45 | Coding Conventions | 🔶 | formatter 存在，命名约定非强制 |

## Standard Library

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 06 | Stdlib Overview | 🔶 | 21 模块 ~5217 LOC。缺: 大量 spec 规划的模块 |
| 26 | Collections Advanced | 🔶 | Array/Map/Set done。缺: Queue/Deque/Stack, immutable variants |
| 54 | Date & Time | 🔶 | datetime.ss 基础版。缺: java.time 级别 API |
| 53 | Environment | 🔶 | getenv/system/args done |
| 24 | Interop & Ecosystem | ❌ | 无生态互操作 |

### Stdlib 当前模块 (21 modules)

json, csv, url, uuid, assert, color, template, crypto, regex, sort, log, ini, path, fs, datetime, math, string_utils, base64, sha256, http, argparse

### Stdlib spec 规划但未实现

random, toml, xml, gzip/zlib, aes, rsa, tls, dns, websocket, db, concurrent utils

## Annotations & Metaprogramming

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 08 | Annotations | ❌ | 无注解系统 |
| 13 | Annotation Layers | ❌ | 无 |
| 39 | Compile-Time Meta | ❌ | 无编译期元编程 |

## FFI & Interop

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 05 | C FFI | ❌ | 仅 vendor mimalloc, 无通用 FFI |
| 62 | WebAssembly | ❌ | 无 WASM target |

## Testing & DX

| Spec | Topic | Status | Notes |
|------|-------|--------|-------|
| 17 | Testing Framework | ❌ | 测试是独立程序，无 test/expect API |
| 14 | CLI Framework | ❌ | 无 @Command 注解框架 |
| 25 | Language Comparison | 📄 | 参考文档 |
| 15 | Example Project | 📄 | 参考文档 |
| 20 | Security | 🔶 | 类型检查有帮助，无系统性安全防护 |

## Web Framework (spec 21-22, 51-52, 57-67)

| Spec | Topic | Status |
|------|-------|--------|
| 21 | Middleware | ❌ |
| 22 | WebSocket | ❌ |
| 51 | Template Engine | ❌ |
| 52 | File Upload | ❌ |
| 57 | Middleware Advanced | ❌ |
| 59 | Session & Cookie | ❌ |
| 60 | Validation | ❌ |
| 61 | Swagger/OpenAPI | ❌ |
| 66 | Error Pages | ❌ |
| 67 | Pagination | ❌ |

## Database & Persistence (spec 10, 55-56)

| Spec | Topic | Status |
|------|-------|--------|
| 10 | ORM | ❌ |
| 55 | DB Migration | ❌ |
| 56 | Connection Pool | ❌ |

## Infrastructure (spec 46-49, 63-65)

| Spec | Topic | Status |
|------|-------|--------|
| 46 | gRPC | ❌ |
| 47 | Event System | ❌ |
| 48 | Microservice | ❌ |
| 49 | Task Scheduling | ❌ |
| 63 | Cache | ❌ |
| 64 | Message Queue | ❌ |
| 65 | Metrics | ❌ |

## Additional Services (spec 18-19, 58, 69)

| Spec | Topic | Status |
|------|-------|--------|
| 18 | Config Management | ❌ |
| 19 | Logging | 🔶 | log.ss 基础版 |
| 58 | i18n | ❌ |
| 69 | Email | ❌ |

---

## Summary

| Status | Count |
|--------|-------|
| ✅ Done | 10 |
| 🔶 Partial | 16 |
| ❌ Not started | 40 |
| 📄 Doc only | 4 |
| 🚫 Rejected | 1 |

## Critical Path (写完整项目的最短路径)

核心语言层 (不依赖框架即可写项目):
1. **null safety (T?)** — spec/43
2. **Result<T,E> + ?** — spec/02
3. **access modifiers** — spec/42
4. **package manager** — spec/07
5. **testing framework** — spec/17

框架层 (写 web 服务):
6. **annotations** — spec/08
7. **virtual threads** — spec/04
8. **FFI** — spec/05
