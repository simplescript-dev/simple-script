# D094: Comptime Purity + Operand-Driven Folding

**Status:** Partial (2026-04-18 回写) — §决策 §规则 1-3 + §P2 实施步骤 Done at gen_exprs.ss / gen_assigns.ss;§Q2 收尾 §天花板分析 §终态判定 "comptimeDepth 不可消除 = 正确架构" 与 D093 §决策 §Zig 原理 第 2 条冲突,**不作未来架构权威依据**,见 §Supersession
**Depends on:** D093(SEMA 单函数 dispatch), Q1 成果(配对=0, zig=7)
**Date:** 2026-04-16
**Last Updated:** 2026-04-18

## Supersession(2026-04-18 回写,D094 §终态判定 vs D093 §决策 边界澄清)

**D094 §Q2 收尾 §天花板分析 §终态判定 与 D093 §决策 互斥。该终态不作未来 evalExpr 工程的架构权威依据。** D094 §决策 §规则 1-3 本身有效并已落地,超出部分(§Q2 §终态判定 / §coexist 守卫分析)是对"当前 kind 级审计"的事实陈述,**不是对 D093 §决策 的达成宣告**。

### 证据 — 判定互斥对照

| D094 断言(§Q2 收尾) | D093 断言(§决策) | 状态 |
|---|---|---|
| §天花板分析:"comptimeDepth 作为 comptime 上下文标记**不可消除,是正确架构**" | §Zig 原理 第 2 条:"`?Value` 二元返回...**没有任何 `if comptime then A else B` 分岔**" | 互斥 |
| §coexist 守卫分析:"44 个 coexist 引用中的 comptimeDepth...**operand ct-ness 无法替代**" | §SS 本质一样骨架 行 73-76:"块内任何 `evalExpr` 返回 known=false 即 error,**不存在 'comptime 专用' 走法**" | 互斥 |
| §度量 终态:"dual kinds 4→3, comptimeDepth 命中 53→52,自动折叠覆盖 0→1 kind(TEMPLATE_LIT)" | §差距清单 第 5 条:"现状 comptime 块内触发一整套独立求值器...**本质是 code + state 两份独立系统**。目标:块内走同一个 `evalExpr`,只在块边界把 flag 置位/复位" | D094 是局部改进;D093 目标未承载 |

### 机制原因

D094 §Q2 §天花板分析 基于**当前 `genVal` / `genStmt` dispatcher 架构不变**的前提做 kind 级审计——在该前提下,"coexist 44 点"确实是局部正确守卫(避免 fall-through 到错误路径)。但 D093 §决策 要求的是**把 dispatcher 本身换成 `evalExpr` 单函数**,在新架构下 comptime 块降为边界 flag,44 处 coexist 分派入口 → 分派表合并进 `evalExpr` kind 分支,两种 state(ctVars/interp* 独立求值器 vs `MaybeVal` 共享 Value)合并到一份。

D094 终态判定属于 **D093 §Rejected Alternatives §D** 的具体形态:

> **D**: 把 `genValCt*` 合入 `genExpr` 但保留 `if comptimeDepth > 0` 分岔 — **表面合并底层仍双轨,消除不到根**

D094 把 `genValCt*` 配对函数吸收进 `genVal`(Q1 成果配对 4→0),再做 operand-driven pure subset 白名单,但 44 处 coexist 守卫保留 —— 这正是 §D 所述"表面合并底层仍双轨"。

### D094 适用范围(保留,继续有效)

- §决策 §规则 1: Comptime = 纯计算(禁 IO/FFI,`println`=`@compileLog`,`exit`=`@compileError`)
- §决策 §规则 2: 两级折叠(块内全部编译期,块外 pure subset 自动折叠白名单)
- §决策 §规则 3: IDENT ct validity tracking(`ctInvalidated` Map)
- §实施步骤 §P2-a / §P2-b / §P2-c: 已落地,bootstrap 固定点通过

以上作为 D093 路径上的**局部优化**保留——evalExpr 合并完成后 pure subset 白名单仍有意义(自动折叠策略),`ctInvalidated` 语义在 MaybeVal scope 模型中仍需(变量 runtime 赋值后 comptime 值失效)。

### D094 不适用范围(不作权威依据)

- §Q2 收尾 §kind 级转换到顶:"9 zig + 2 dual + 11 simple,81% 转化率,replaceable ≈ 0" 作为**当前架构的审计事实**保留,但**不代表 D093 §决策 已达成**
- §Q2 §天花板分析 §coexist 守卫分析:"不可消除,是正确架构" **只对 D094 dispatcher 不变的前提成立**,D093 换 `evalExpr` 后失效
- §Q2 §终态判定:"D094 kind 级转换到顶,comptimeDepth 不可消除" **不作为 evalExpr 工程的起点或约束**

### Supersession 关系

- **D094 §决策 §规则 1-3 + §P2 实施步骤**: 保留有效,D093 evalExpr 合并期可并用(pure subset 白名单 / ctInvalidated 语义继承)
- **D094 §Q2 §终态判定 + §天花板分析**: 作为 2026-04-16 当时架构审计的历史快照保留,**不作未来 evalExpr 工程的架构权威依据**
- **D093 §决策 §Zig 原理 / §SS 本质一样骨架**: D088 §第一性需求 → 根因路径的**唯一权威主干**
- **D093 §张力 1-3**(MaybeVal 编码 / InternPool / Type-as-Value): 由 D098 承接(本文档不承载,2026-04-18 巡检确证)

### 禁止行为

1. **禁止**引用 D094 §Q2 §终态判定 反对 D093 §决策 要求的 "comptime 块降为 flag" 或 "evalExpr 单 dispatch"
2. **禁止**把"D094 Status = Done"当作 D093 §下一步 第 1 条(产出 MaybeVal/InternPool/Type-as-Value 详设)的委托已完成(D094 全文 0 次 MaybeVal/InternPool,见本段 §证据)
3. **禁止**在未过 D093 §决策 + 未决 D093 §张力 1-3 的情况下,以"D094 already Done"理由跳过 evalExpr 首批合并的架构设计工作

---

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

### Q2 收尾：kind 级转换到顶

**Status:** kind 级 + 引用级转换收敛，replaceable ≈ 0

#### genVal 操作数驱动审计

| 分类 | 数量 | kind |
|---|---|---|
| zig (isCt 驱动) | 9 | IDENT, CALL, NEW_EXPR, MEMBER_ACCESS, METHOD_CALL, TEMPLATE_LIT, ARRAY_LIT, INDEX_ACCESS, POSTFIX_INC |
| dual (结构性) | 2 | COMPTIME_EXPR (模式入口), ARROW_FUNC (类型级) |
| simple | 11 | 字面量等无 ct 处理 |
| **转化率** | **81%** (9/11) | |

##### Phase A 迁移进度(2026-04-20 D109 Execute 1 末轮回写,P19 标注)

zig 驱动 9 kind 全部 [x] Done,evalExpr 子目录方案落地 `bootstrap/eval/*.ss`(11 子文件 + evalExpr 主 dispatch),Phase A `[x] Done`。

| kind | 状态 | 承载文件 | 来源 D 文档 |
|---|---|---|---|
| TEMPLATE_LIT | [x] Done | `bootstrap/eval/template_lit.ss` | D101 Execute 1 |
| ARRAY_LIT | [x] Done | `bootstrap/eval/array_lit.ss` | D103 Execute 1 |
| IDENT | [x] Done | `bootstrap/eval/ident.ss` | D104 Execute 1 |
| MEMBER_ACCESS | [x] Done | `bootstrap/eval/member_access.ss` | D105 Execute 1 |
| INDEX_ACCESS | [x] Done | `bootstrap/eval/index_access.ss` | D105 Execute 1 |
| POSTFIX_INC | [x] Done | `bootstrap/eval/postfix_inc.ss` | D106 Execute 1 |
| METHOD_CALL | [x] Done | `bootstrap/eval/method_call.ss` | D107 Execute 1 |
| CALL | [x] Done | `bootstrap/eval/call.ss` | D108 Execute 1 commit `2c38819` |
| NEW_EXPR | [x] Done | `bootstrap/eval/new_expr.ss` | D109 Execute 1 commit `e141fdf` |

Phase A 闭环 = 9 kind 全迁。下一阶段 D110 Phase A 全局收尾(12 函数稳态 / vtable 融合评估)+ Phase B MaybeVal 类化(D098 §决策 2)。

#### genStmt 语句处理审计

| 分类 | 数量 |
|---|---|
| zig (isCt 驱动) | 17 |
| dual (结构性) | 8 — FUNC_DECL/CLASS_DECL/ENUM_DECL(声明)、BREAK/CONTINUE(控制流)、EXPR_STMT(桥接)、TRY、COMPTIME_BLOCK(入口) |
| missing | **0** |
| simple | 1 |

#### comptimeDepth 55 条引用分类

| 分类 | 数量 | 说明 |
|---|---|---|
| coexist | 44 | 函数内已有 isCt 共存，comptimeDepth 是辅助守卫 |
| structural | 7 | 赋值方(runComptimeBlockBody)、循环控制(genBlock)、无操作数声明(registerEnum/genBreak/genContinueStmt/resolveSuperParent) |
| boundary | 4 | genFuncDeclStmt/genClassDecl/genStmt(EXPR_STMT)/genTryCatch — 形式上可替换但无操作数可 isCt，实为声明级模式守卫 |

#### 天花板分析

kind 级转换已穷尽。剩余 10 个 dual kind（genVal 2 + genStmt 8）全部是结构性的：要么是模式切换入口（COMPTIME_BLOCK/COMPTIME_EXPR），要么是声明注册（FUNC_DECL/CLASS_DECL/ENUM_DECL），要么是无操作数控制流（BREAK/CONTINUE），要么是纯桥接（EXPR_STMT/TRY/ARROW_FUNC）。

**coexist 守卫分析：不可消除，是正确架构。** 44 个 coexist 引用中的 comptimeDepth 承担两个不可分离的职责：(1) 分派选择 — CALL/METHOD_CALL/NEW_EXPR 即使参数全 ct，comptime 块外也不走解释器（D094 规则 2）；(2) 安全网 — comptime 块内 isCt 失败时阻止 fall through 到 emitIR。这两个职责都需要"当前是否在 comptime 块内"的信息，operand ct-ness 无法替代。

#### 实证验证（tests/phase5/comptime_dispatch.ss）

10 个边界测试验证 comptimeDepth 语义。与 Zig Sema 对比：

| 行为 | SS | Zig | 评估 |
|------|-----|-----|------|
| 纯表达式块外自动折叠 | ✅ | ✅ | 一致 |
| comptime 块内本地函数调用 | ✅ | ✅ | 一致 |
| comptime 块内调用**外部函数** | ✅ (registerFuncDeclNode 修复后) | ✅ 可调任意纯函数 | 一致 |
| comptime class new + BINARY | ✅ (interpCollectFields 修复后) | ✅ | 一致 |
| comptime Map index assign/read | ✅ | ✅ | 一致 |
| comptime throw 条件跳过 | ✅ | ✅ | 一致 |
| comptime postfix++ | ✅ | ✅ | 一致 |
| comptime enum | ✅ | ✅ | 一致 |

Zig Sema 用 `comptime_reason`（optional tagged union，含错误来源信息）标记 comptime 上下文。SS 用 `comptimeDepth`（int 计数器）。功能等价（判断是否在 comptime 块内）。外部函数可达性已修复（registerFuncDeclNode 阶段注册所有顶层 FUNC_DECL 到 ctFuncNodes）。剩余可改进点：comptime 错误溯源（Zig 的 ComptimeReason 含来源位置信息）。

**终态判定：** D094 kind 级转换到顶。comptimeDepth 作为 comptime 上下文标记不可消除，是正确架构。8/8 Zig Sema 语义验证通过，无剩余差距。

## Rejected Alternatives

- **全部 kind 自动折叠**（含 CALL/METHOD_CALL）— 用户函数可能有 println/exit 诊断输出，自动折叠导致"写了 println 但编译时就打印"的惊讶。Zig 也不自动折叠普通函数调用。
- **不做 ct validity tracking，保留 IDENT 的 comptimeDepth 守卫** — IDENT 是所有 kind 的操作数来源，不解决 IDENT 则 P2-b 的操作数驱动折叠无法生效（operand 永远是 constVal）。
- **全局 const 追踪替代 invalidation** — const 变量不可 invalidated，但 let 变量可以。需要区分 const/let，比简单 invalidation Map 更复杂，收益有限。
