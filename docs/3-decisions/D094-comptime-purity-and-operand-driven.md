# D094: Comptime Purity + Operand-Driven Folding

**Status:** P2 Done — 剩余 3 dual (POSTFIX_INC/COMPTIME_EXPR/ARROW_FUNC) 等待架构演进
**Depends on:** D093(SEMA 单函数 dispatch), Q1 成果(配对=0, zig=7)
**Date:** 2026-04-16

## 第一性原则

Zig comptime 是**纯计算环境**。不允许 IO、extern 调用、指针转换。这个约束不是限制，是使能条件 — 正因为 comptime 没有副作用，编译器才能**安全地自动折叠**任何操作数全部已知的表达式，无需判断该表达式是否"意图在运行时执行"。

SS 的 comptime 解释器已经隐性满足此约束（无 file/network API），但从未显式声明。本决策将其升格为设计规则，并利用它完成 D093 §差距 1（消灭 comptimeDepth 分岔）。

## Q1 成果（本决策的前置条件）

| 指标 | Q1 前 | Q1 后 |
|---|---|---|
| genValCt* 配对函数 | 4 | **0** |
| dual kinds | 11 | 4 |
| zig kinds | 0 | 7 |
| comptimeDepth 命中 | ~40 | 53（计数方式不同） |

Q1 完成了**结构合并**：genVal 先求值操作数再分叉，isCt + reg 机制就位。但分叉守卫仍是 `comptimeDepth > 0`（模式标志），不是 operand known-ness（操作数驱动）。

## 决策

### 规则 1: Comptime = 纯计算

| 允许 | 禁止 |
|---|---|
| 算术、比较、逻辑运算 | IO（文件、网络、系统调用） |
| 字符串操作（拼接、split、indexOf 等） | extern/FFI 调用 |
| Array/Map 创建与操作 | 运行时内存操作 |
| 对象创建、字段读写 | — |
| println（= Zig @compileLog，编译期诊断） | — |
| exit（= Zig @compileError，编译期终止） | — |

SS 解释器已天然满足，无需加代码限制。本规则是设计承诺，未来扩展 comptime 能力时必须遵守。

### 规则 2: 两级折叠

| 场景 | 折叠范围 | 机制 |
|---|---|---|
| `comptime { }` 块内 | **全部**表达式必须编译期可求值 | comptimeDepth > 0 → evalExpr 返回 unknown 即 error |
| `comptime { }` 块外 | 仅 **pure subset** 自动折叠 | operand-driven: allOperandsCt → fold |

**Pure subset**（块外自动折叠白名单）：
- 字面量（INT_LIT, STRING_LIT, DOUBLE_LIT, TRUE/FALSE/NULL）
- 算术/比较/逻辑 BINARY
- UNARY
- TEMPLATE_LIT（模板拼接）
- ARRAY_LIT（数组字面量）
- MEMBER_ACCESS（字段读取）
- INDEX_ACCESS（下标访问）

**不自动折叠**（仅在 comptime 块内折叠）：
- CALL / METHOD_CALL / NEW_EXPR — 用户函数可能有 println/exit 等诊断副作用
- POSTFIX_INC — 变量副作用
- 赋值语句

这与 Zig 的行为一致：普通函数不因参数已知就自动 comptime 化，需要 `comptime` 关键字或 comptime 块显式触发。

### 规则 3: IDENT ct validity tracking

变量在 comptime 块中被赋值后，其 ctVal 在后续 runtime 代码中可能被覆盖。需要 invalidation 机制：

- `ctInvalidated` Map：runtime 赋值时标记 `ctInvalidated.set("func:varName", "1")`
- IDENT 查 ctVars 前先检查 `ctInvalidated` — 已 invalidated 则走 genIdent
- 仅影响 `comptimeDepth == 0` 时的 IDENT 查找（comptime 块内不检查 invalidated）

## 实施步骤

### P2-a: IDENT ct validity tracking

**改动范围**：gen_exprs.ss（IDENT 分支）+ gen_assigns.ss（赋值时标记）

1. 新增全局 `let ctInvalidated = new Map()`
2. gen_assigns.ss 中所有 runtime 赋值路径：`ctInvalidated.set("${currentFunc}:${varName}", "1")`
3. genVal IDENT 分支：移除 `comptimeDepth > 0` 守卫，改为先查 ctInvalidated，未 invalidated 且 ctVars 有值则返回 ctVal

**验证**：bootstrap 固定点 + 全量测试 + linter dual 4→3

### P2-b: Pure subset 操作数驱动折叠

**改动范围**：gen_exprs.ss 中 7 个 zig kind 的分叉守卫

对 pure subset 中的 kind（TEMPLATE_LIT, ARRAY_LIT, MEMBER_ACCESS, INDEX_ACCESS）：
- 替换 `if (comptimeDepth > 0)` 为 `if (allOperandsCt)`
- allOperandsCt 通过检查已求值操作数的 isCt 判定

对 CALL/METHOD_CALL/NEW_EXPR：
- 保留 `comptimeDepth > 0` 守卫（函数调用不自动折叠）
- 或引入 `@comptime` 函数注解允许自动折叠（future work）

**验证**：bootstrap 固定点 + linter comptimeDepth 命中下降

### P2-c: 边界情况

- ARROW_FUNC: 扩展 materialize 支持 fn 类型（调用 genArrowFunc）
- POSTFIX_INC / COMPTIME_EXPR: 保持现状（错误桩 / 模式切换语义）
- genArrowFunc regTable 问题：考虑 save/restore regTable

## 度量

| 指标 | Q1 后 | P2-a 后 | P2-b 后 |
|---|---|---|---|
| dual kinds | 4 | **3** | **3** |
| comptimeDepth 命中 | 53 | 53 | **52** |
| 自动折叠覆盖 | 0 kind | 0 kind | **1 kind** (TEMPLATE_LIT) |

P2-b 实际影响比预期小：MEMBER_ACCESS/INDEX_ACCESS 主折叠路径 Q1 已是 isCt 驱动，
ARRAY_LIT 因 materialize 不支持数组类型无法在 runtime 自动折叠。
仅 TEMPLATE_LIT 有实质改动（comptimeDepth→allCt 守卫替换）。

## Rejected Alternatives

- **全部 kind 自动折叠**（含 CALL/METHOD_CALL）— 用户函数可能有 println/exit 诊断输出，自动折叠导致"写了 println 但编译时就打印"的惊讶。Zig 也不自动折叠普通函数调用。
- **不做 ct validity tracking，保留 IDENT 的 comptimeDepth 守卫** — IDENT 是所有 kind 的操作数来源，不解决 IDENT 则 P2-b 的操作数驱动折叠无法生效（operand 永远是 constVal）。
- **全局 const 追踪替代 invalidation** — const 变量不可 invalidated，但 let 变量可以。需要区分 const/let，比简单 invalidation Map 更复杂，收益有限。
