# D087: Comptime — 编译期执行用户代码

**Status:** Planned
**Depends on:** self-bootstrapping compiler (done), SimpleScript interpreter (to build)
**Principle:** spec/13 — 语言只内置机制，不内置策略

## Background

### 起因：D086 注解处理的局限

D086 实现了注解分发机制：`annotationMapping(name, handler)` 让 lib 注册注解→handler 映射，编译器生成工厂/包装函数后调 handler。达到约 95% 的框架知识外部化。

编译器中仍残留 3 个框架耦合点（gen_annotations.ss:172-185）：
- `HttpServletRequest` / `HttpServletResponse` 类型名硬编码在包装函数参数桥接中
- `HttpServletRequest_getPathVariable` 方法名硬编码在参数提取中

根本原因：**只有编译器能生成 LLVM IR，但编译器不应含框架知识**。没有编译期代码执行能力时，这个矛盾无法完全解决。

### 问题的本质

注解处理只是表象。真正的问题是：**当 lib 需要在编译期做决策和生成代码时，谁来执行这段逻辑？**

目前是"编译器硬编码"——工厂函数生成、包装函数参数桥接都写死在编译器里。每种新的编译期需求都要改编译器代码。

## Research

### 方案一：插件系统（Rust proc-macro 模型）

**机制：** 编译器加载外部动态库（插件），传入 token 流，插件返回变换后的 token 流。

**Rust 社区实际反馈：**
- 框架作者需要学特殊的插件 API（syn/quote/proc-macro2），与普通 Rust 写法不同
- 调试是公认最大痛点：错误指向宏调用处，不指向插件内部出错位置
- IDE 支持差：编辑器不理解插件生成的代码，自动补全和跳转失灵
- 编译慢：每个插件是独立程序，编译器要先编译插件再加载运行

**实现要求：** 动态库加载（dlopen）、稳定 ABI、安全沙箱、TokenStream API 设计

**评估：** 工程量大，用户体验差（两种语言），与 SimpleScript 自举架构不契合。

### 方案二：编译期执行（Zig comptime 模型）

**机制：** 编译器内置解释器，在编译时直接运行用户代码。不需要外部插件，不需要特殊语法。

**Zig 实际体验：**
- 框架作者用普通 Zig 写编译期逻辑——同一种语言，同一种思维
- 调试和普通代码一样：加 print 就能调试，错误信息精确
- IDE 完整支持：都是普通代码
- Zig 编译器用 Zig 自举，comptime 让自举更自然

**Zig comptime 限制（设计选择）：**
- 编译期不能做 I/O（不能读文件、网络）——保证编译跨平台可重现
- 不能做运行时反射——所有反射在编译期完成

**同类语言：** D 语言 CTFE、Nim 内置 VM。2025 年语言设计圈趋势倾向 comptime。

### 对比

| | 插件系统 (Rust) | 编译期执行 (Zig) |
|---|---|---|
| 框架作者学习成本 | 高——需学插件 API | 低——普通 SimpleScript |
| 调试体验 | 差——Rust 社区公认痛点 | 好——和普通代码一样 |
| IDE 支持 | 差 | 好 |
| 编译器实现 | 动态库加载 + ABI + 沙箱 | 内置解释器 |
| 与自举的契合 | 低 | 高——SimpleScript 和 Zig 都是自举 |
| 解决问题范围 | 仅注解处理 | 注解 + 泛型 + 条件编译 + 代码生成 |
| 错误信息 | 差 | 好 |

## Decision

**选择方案二：comptime（编译期执行）。**

### 核心理由

1. **SimpleScript 是自举编译器**——编译器用 SimpleScript 写的。加一个 SimpleScript 解释器，编译器就能在编译时运行任意 SimpleScript 代码。与 Zig 自举架构完全一致。

2. **一种语言统治一切**——框架作者用 SimpleScript 写框架逻辑、编译期处理、运行时代码。不需要学"插件 API"这种第二语言。符合"简单易用"的设计理念。

3. **解决的不只是注解**——comptime 实现后，泛型单态化、条件编译、代码生成、类型反射全部可用。一个机制解决一类问题。插件系统只解决注解处理。

4. **用户体验碾压**——调试像普通代码、错误信息精确、IDE 完整支持。

### 实现路径

**Phase 1：SimpleScript 解释器**（拆为 6 个子步骤，每步一轮对话）

| 步骤 | 内容 | 完成标准 |
|------|------|---------|
| 1a | 解释器骨架：值表示（int/string/double/bool/null）、环境/作用域栈、表达式求值（算术/比较/逻辑/字符串拼接/模板字符串） | `comptime { const x = 1 + 2 }` 能执行并产出值 |
| 1b | 语句：let/const 声明、if/else、while、for、for-in、break/continue、return | comptime 块中能跑完整控制流 |
| 1c | 函数：声明、调用、递归、默认参数、闭包 | comptime 中能定义函数并调用，支持递归 |
| 1d | 类：new、字段读写、方法调用、this、继承 | comptime 中能 `new MyClass()` 并调用方法 |
| 1e | 内置类型方法：string（split/indexOf/substring 等）、Array（push/length/map 等）、Map（set/get/has/keys 等） | comptime 中能做字符串拼接、数组操作、Map 查询 |
| 1f | 与编译器集成：comptime 执行结果注入后续编译阶段（如生成声明、注册类型） | comptime 生成的函数/类型在运行时可用 |

**Phase 2：comptime 语法与标记**

| 步骤 | 内容 | 完成标准 |
|------|------|---------|
| 2a | Parser：识别 `comptime` 关键字，解析 `comptime { ... }` 块为新 AST 节点 COMPTIME_BLOCK | `comptime { println("hello") }` 能解析为 AST |
| 2b | Checker：验证 comptime 块（禁止 I/O 调用、禁止运行时专用特性） | comptime 块中调 readFile 报编译错误 |
| 2c | Codegen 集成：遇到 COMPTIME_BLOCK 时调用 Phase 1 的解释器执行，跳过 IR 生成 | `comptime { const x = 1 + 2; println(x) }` 编译时输出 3，运行时无代码 |
| 2d | comptime 函数参数：`function foo(comptime n: int)` 要求调用时 n 必须是编译期已知值 | `foo(3)` 通过，`foo(runtimeVar)` 报错 |

**Phase 3：编译期反射与代码生成**

| 步骤 | 内容 | 完成标准 |
|------|------|---------|
| 3a | `@typeInfo(T)`：返回 ClassInfo 对象，含 fields（名称+类型）、methods（名称+参数+返回类型）、annotations | `comptime { const info = @typeInfo(MyClass); println(info.fields.length()) }` 输出字段数 |
| 3b | comptime 代码生成：comptime 块可调用编译器 API 注入声明（函数、全局变量） | comptime 生成的函数在运行时可调用 |
| 3c | comptime 字符串→代码：类似 D 语言 mixin，`@comptimeEmit(irString)` 将字符串作为代码注入 | comptime 可根据反射结果动态生成任意代码 |

**Phase 4：用 comptime 重写注解处理**

| 步骤 | 内容 | 完成标准 |
|------|------|---------|
| 4a | lib/spring/boot.ss 用 comptime + @typeInfo 实现工厂函数生成 | @Component 类的单例工厂由 lib comptime 代码生成，非编译器硬编码 |
| 4b | lib/spring/boot.ss 用 comptime 实现方法包装生成，参数桥接逻辑完全在 lib 中 | HttpServletRequest/HttpServletResponse/getPathVariable 从编译器中消失 |
| 4c | 删除 bootstrap/gen_annotations.ss，删除 codegen.ss/gen_stmts.ss/prelude.ss 中的 annotationMapping 相关代码 | 编译器零注解处理代码，bootstrap 通过 |
| 4d | spring_di.ss 测试通过，验证 comptime 注解处理与原实现行为一致 | 180+ 测试全部通过 |

## 设计细节

### 解释器文件结构

解释器作为编译器的新模块，放在 bootstrap/ 下：

| 文件 | 职责 |
|------|------|
| `bootstrap/interp.ss` | 解释器核心：值表示、环境、表达式/语句求值 |
| `bootstrap/interp_builtins.ss` | 内置类型方法（string/array/map），拆分避免单文件过大 |

解释器复用现有 AST 节点系统（nGetKind/nGetS1/nGetI1/nGetList 等），不另建 AST。Parser 产出的 AST 直接传给解释器执行。

### 值表示

解释器内部用 Map 表示值，key 为属性名：

```
// int: { __type: "int", __val: "42" }
// string: { __type: "string", __val: "hello" }
// object: { __type: "object", __class: "MyService", field1: value1, ... }
// array: { __type: "array", __items: "id1,id2,id3" }
// fn: { __type: "fn", __funcId: "123" }  // AST node ID of FUNC_DECL
// null: { __type: "null" }
```

这种方式和编译器现有架构一致（全局 Map 存储），无需新的数据结构。

### 环境/作用域

用栈模拟作用域。每个作用域是一个 Map（变量名→值 ID）。函数调用时 push 新作用域，返回时 pop。

### 与现有 AST 的交互

- 解释器接收 AST node ID，递归求值
- 遇到 `BINARY` 节点：求值左右子节点，执行运算
- 遇到 `CALL` 节点：查找函数的 FUNC_DECL node ID，解释执行函数体
- 遇到 `NEW_EXPR` 节点：创建对象值，调用构造函数

### 自举安全性

**问题：** seed 编译器（bin/ss）没有解释器代码。bootstrap 编译器新增了 interp.ss。seed 能编译 interp.ss 吗？

**安全：** interp.ss 是普通 SimpleScript 代码（函数、Map 操作、字符串处理）。seed 编译器完全能编译它。解释器不使用 comptime 自身——它是 comptime 的实现，不是 comptime 的用户。

**验证流程：** seed → stage1（含解释器）→ stage2 → stage3，验证 stage2==stage3。与现有 bootstrap 流程一致。

### comptime 不支持的操作

编译期禁止以下操作（checker 报错）：
- I/O：readFile、writeFile、println（调试用 println 可选择允许）
- 网络：httpGet 等
- 进程：exec、exit
- 并发：Thread.start、Channel

这保证编译结果不依赖编译环境，跨平台可重现。

## Rejected

- **插件系统（Rust proc-macro）**——用户体验差（两种语言、调试难、IDE 差），与自举不契合，只解决注解问题
- **外部工具（Go generate）**——破坏单文件编译体验

## Files

暂无代码变更。本文档记录选型决策，实现在后续 round 中进行。
