# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SimpleScript 是一门编译型语言，语法基于 Java/TypeScript，编译到 LLVM IR 并静态链接 musl libc，产出原生二进制。

## 构建与测试

```bash
# 构建编译器
cargo build -p ss-cli

# 编译 .ss 文件
cargo run -p ss-cli --bin ss -- build file.ss -o output
cargo run -p ss-cli --bin ss -- build --release file.ss    # 优化构建 (-O2 -s)
cargo run -p ss-cli --bin ss -- build --emit-ir file.ss    # 输出 LLVM IR

# 编译并运行
cargo run -p ss-cli --bin ss -- run file.ss
cargo run -p ss-cli --bin ss -- run --watch file.ss        # 文件变更自动重编译

# 其他命令
cargo run -p ss-cli --bin ss -- check file.ss   # 仅类型检查
cargo run -p ss-cli --bin ss -- test tests/      # 运行 .ss 测试套件
cargo run -p ss-cli --bin ss -- fmt file.ss      # 格式化
cargo run -p ss-cli --bin ss -- repl             # 交互式 REPL
cargo run -p ss-cli --bin ss -- new myapp        # 创建新项目 (ss.json + src/main.ss)
cargo run -p ss-cli --bin ss -- clean            # 清理缓存 (/tmp/ss_*.o)

# Rust 单元测试
cargo test -p ss-lexer     # 词法分析测试
cargo test -p ss-parser    # 语法分析测试
cargo test                 # 全部 crate 测试
```

`ss test` 会递归查找目录下所有 `.ss` 文件，编译运行，以退出码判定通过/失败。测试按 `tests/{mvp,phase2,phase3,phase4}/` 分阶段组织。

## 编译器架构

四阶段流水线，每阶段一个 crate：

```
.ss 源码 → Lexer (Vec<Token>) → Parser (Program/AST) → Checker (TypedProgram) → Codegen (LLVM IR) → musl-gcc 链接 → 静态二进制
```

### 核心数据流

| 阶段 | crate | 入口函数 | 输入 → 输出 |
|------|-------|---------|------------|
| 词法 | `ss-lexer` | `tokenize()` | `&str` → `Vec<Token>` |
| 语法 | `ss-parser` | `parse()` | `Vec<Token>` → `Program { stmts: Vec<Stmt> }` |
| 类型 | `ss-checker` | `Checker::check()` | `&Program` → `TypedProgram { program, global_vars, functions }` |
| 代码生成 | `ss-codegen` | `Codegen::compile()` | `&TypedProgram` → LLVM object file |

### 关键类型

- **Lexer**: `Token { kind: TokenKind, span: Span }`，`TemplateFragment::Literal | Expr` 处理模板字符串
- **Parser**: `Stmt { kind: StmtKind, span }` / `Expr { kind: ExprKind, span }`，`TypeAnnotation` 枚举 (Int/Double/String/Bool/Void/Named)
- **Checker**: `Type` 枚举用于类型推断，`FuncInfo { params, return_type }`，Levenshtein 距离提示拼写错误
- **Codegen**: `Codegen<'ctx>` 持有 LLVM module/builder，`VarType` 枚举 (Int/Double/String/Bool/Object)，`ClassInfo` 存储类结构体元数据

### Codegen 三趟编译 (codegen.rs)

1. **前向声明**：注册所有函数签名和类定义，保存默认参数值
2. **全局变量**：顶层 `const`/`let` 编译为 LLVM 全局变量 (`add_global()`)
3. **函数/类体**：编译函数体和类方法，构造函数生成为 `ClassName_new()`

codegen 拆分为模块：`codegen.rs`（主逻辑+语句）、`exprs.rs`（表达式编译）、`runtime_decl.rs`（运行时函数声明）、`helpers.rs`（值转换+变量加载）。

### 运行时 (runtime/runtime.c)

C 语言运行时，通过 `musl-gcc` 编译（缓存在 `/tmp/ss_runtime.o`），提供：
- I/O：`ym_println`/`ym_print`/`ym_readLine`/`ym_readFile`/`ym_writeFile`
- 字符串：19 个方法 (`ym_string_concat`/`ym_trim`/`ym_replace`/`ym_split`/`ym_join` 等)
- 数组：堆分配 `long long*`（slot 0 = length），`ym_newArray`/`ym_arrayPush`/`ym_arraySort` 等
- HashMap：`ym_mapNew`/`ym_mapSet`/`ym_mapGet` (string→i64)
- 数学：`ym_sqrt`/`ym_abs`/`ym_pow`/`ym_random` 等
- 类型转换：`ym_int_to_string`/`ym_parseInt`/`ym_parseDouble`

运行时函数在 `runtime_decl.rs` 中前向声明为 LLVM 函数类型。

### 类系统

- 类编译为 LLVM struct，继承通过字段拼接（父类字段在前）
- 构造函数 `ClassName_new()` 通过 `build_malloc()` 分配
- 方法编译为全局函数 `ClassName_methodName(this, args...)`
- 静态分派，无 vtable

### 链接过程 (ss-cli/main.rs `compile()`)

1. 解析 imports（递归，有环检测）
2. 四阶段流水线生成 object file
3. `musl-gcc` 编译 runtime.c（有缓存）
4. `musl-gcc` 静态链接：object + runtime → 二进制
5. Release 模式加 `-O2 -s`

依赖：Inkwell 0.5 (LLVM 18)，Clap 4，thiserror 2。

## 语法设计原则

- 语法只参考 Java 和 TypeScript，不引入 Go/Rust/Kotlin 的语法
- const/let (TypeScript 风格)，类型后置 (name: Type)
- 顶层 const 编译为 LLVM 全局变量（不是 hack 到 main 里）
- function 关键字，class/new/this/extends
- 模板字符串 `${}`，JDK 25 风格 switch

## 开发原则

### 问题解决

- **Root Cause 优先**：永远从根源修复问题（修改工具/框架代码），不逐个修补项目文件。不用临时方案绕过问题，不要表层最快方案假装解决
- **三思而后行**：方案选择时要搜索、对比，选择最优最佳实践，不要第一个能跑的方案就用
- **技术结论必须验证**：说"X 方案有 Y 缺点"之前，先确认 Y 是否真实存在。不确定就说不确定，不要编一个听起来合理的理由。用模糊的"复杂度"当借口回避工作 = 偷懒
- **用 log 调试难题**：遇到难以定位的问题，添加调试日志输出定位根因，不要靠猜测反复尝试
- **逐步确认不想当然**：每一步修复后都要验证结果，不要假设已经修好就继续下一步

### 代码质量

- **单文件不要过大**：单个源文件超过 500 行时应考虑拆分。过大的文件难以理解、难以 review、增量编译效率低
- **最小改动**：只做直接请求的改动，不加无关的重构、注释、docstring
- **不过度工程**：不加 feature flag、不设计假想需求、不为一次性操作创建抽象
- **降低心智负担**：API/配置/命令设计要让用户零思考即可使用，合理默认值、自动推断、约定大于配置
- **删除即删除**：废弃代码直接删掉，不留 `// removed` 注释或 `_unused` 变量
- **先读后改**：修改代码前必须先读懂现有代码，不凭印象写代码
- **全面深度阅读**：读文档/代码时要完整深入，不要只看开头几行就下结论，避免遗漏关键细节
- **融入项目风格**：成熟项目中做迭代时，先观察项目现有的代码风格、命名惯例、架构模式，保持一致

### 安全与规范

- **不引入安全漏洞**：注意命令注入、XSS、SQL 注入等 OWASP Top 10
- **不跳过检查**：不用 `--no-verify`、`--force` 等跳过安全检查的参数
- **只验证边界**：只在系统边界（用户输入、外部 API）做验证，内部代码信任框架保证

### 工作方式

- **先搜索最佳实践**：动手前先搜索业界最佳实践和成熟方案，不闭门造车
- **方案对比决策**：有多个方案时，列表对比各方案优缺点，选出最佳方案再动手
- **先搜索再造轮子**：GitHub、npm/PyPI/crates.io 搜索现有实现，优先采用成熟方案
- **Spec 先行**：新功能必须先写 spec，讨论充分后再实现
- **逐条实现**：对照 spec 实现时，列出 checklist 逐条完成，不凭印象跳步
- **问题分类逐个击破**：处理多个问题时，先将问题归类列表，然后逐个解决并确认，不混在一起处理
- **优先使用项目 skill**：操作其他项目时，先检查该项目下是否有可用的 slash command / skill，优先使用而非手动操作
- **主动发现反模式并提案新原则**：发现自己或代码中违反应成为原则的模式时，主动指出问题、提炼为一句原则、提醒用户确认后加入 init-principle 持久化
- **memory 写入时询问持久化**：写入 memory 时，如果内容有普适价值，询问用户是否同时写入 init-principle。memory 会丢，principle 存 GitHub 永不丢
