# D097: 反射根因指标 — 不可伪造的 linter 守护

**Status:** 工具链就绪 (tools/reflection_health_linter.ss v2),baseline 冻结 @ commit 9e20f26
**Depends on:** D088(Zig comptime 路线)、D093(单函数 dispatch 消除双轨)、D095/D096(反射 API)
**Date:** 2026-04-18
**Last Updated:** 2026-04-18

---

## 第一性问题

D096 Phase 4 L2ζ-L2κ 为反射每增加一个维度(FieldMeta.annotations、a.args、cls.annotations、cls.methods、m.annotations)就新增:

- 一条 `nGetS1(iterableId) == "成员名"` 的 hardcoded kind 分支
- 一个 `classXxxAnnotations` / `classXxxAnnotationArgs` 全局 Map
- 一个 `__sidecar` sidecar 键伴随 comptimeConsts
- 一个 `genForInUnrolled` 调用点

这是**累积式扩展**,不是**根因解决**。每增加一种反射字段,分支数/Map 数/sidecar 数/调用点都 +1。Zig SEMA 路线(D088/D093)的根因方案是 D093 §决策 定义的**单函数 `evalExpr` dispatch** — 任一 AST 节点走同一求值入口返回 `MaybeVal`,反射是 Meta 对象的自然成员访问,与普通字段访问共享 `evalExpr` 分发,无需 kind 分支。

> **路径澄清(2026-04-18 回写)**:本文档**不**鼓励扩展 `interpExpr*` / `interpStmt*` 或任何 `interp*` 独立求值器副本来承载反射语义。那是 D092 装修双轨路径,已被 D093 §Rejected Alternatives(A/C/D)明确否决。**唯一合规根因路径** = D093 §决策「evalExpr 单函数 dispatch」。

**但 Claude 可以改名、分拆到 helper、挪到深层嵌套,让 grep 误判"根因已解决"**。因此需要**不可伪造的物理指标**:AST 结构性计数,与名字/位置/文件无关。

## 指标定义 (不可伪造 — v2 纯图论)

linter 位于 `tools/reflection_health_linter.ss`,通过 `@/bootstrap/lexer/lexer` + `@/bootstrap/parse/parser` 复用编译器前端,对 `bootstrap/**/*.ss` 做 AST 遍历计数(`collectSSFiles` 递归扫)。

v1 的 G1-G5(字符串匹配 `nGetS1=="fields"`、变量名前缀 `classXxxAnnotation`、宏入口 `genForInUnrolled`、NEW_EXPR 名匹配)被证明**可伪造** — 改名、拆 helper、藏深嵌套即可规避。2026-04-18 commit `072690f` + `9e20f26` 整体替换为下列 **14 项纯图论物理指标**(称 M1-M7 物理形态 + N1-N5 防规避扩展)。baseline 位于 `tools/linter_baseline.txt`,由 linter `record` 子命令写入,不手工编辑。

| # | 指标 | AST / 调用图模式 | 物理含义 | 当前 baseline |
|---|---|---|---|---|
| M1 | CC 总和 | 每函数 (IF/WHILE/DO_WHILE/FOR/FOR_IN/FOR_OF/TERNARY/SWITCH_CASE/CATCH_CLAUSE/`&&`/`\|\|`/NullCoalesce 各 +1) 之和 | 圈复杂度上界 | 5144 |
| M2 | 节点总数 | AST 节点访问总数 | 代码体积物理下界 | 76244 |
| M3a | 调用边数 | CALL + METHOD_CALL + NEW_EXPR callsite 数 | 调用图密度 | 12156 |
| M3b | 最大入度 | 最"热"目标函数被引用次数 | God-function 指标 | 1880 |
| M4 | Dispatch 深度和 | 所有 IF 的 else-chain 长度 + SWITCH case 总数 | 单函数分派负担 | 3051 |
| M5 | 可变 state 点数 | 顶层 VAR_DECL + ASSIGN/INDEX_ASSIGN/MEMBER_ASSIGN/COMPOUND_ASSIGN/POSTFIX_INC/POSTFIX_DEC 节点数 | 可变状态散射度 | 1758 |
| M6 | 递归函数数 | 函数 body 内直接调自身的函数数(SCC proxy) | 递归入口数 | 32 |
| M7a | 最大 IF 嵌套深 | 单函数内最大 IF 嵌套深度 | 抗"藏深嵌套"规避 | 27 |
| M7b | 函数总数 | FUNC_DECL + ARROW_FUNC 总数 | 抗"拆 helper"规避 | 679 |
| N1 | kind 基数 | 出现过的不同 AST kind 数量 | 引入新节点类型必 +1 | 34 |
| N2 | Halstead 体积 | `M2 × floor(log2(N1))` | 信息论总体积下界 | 381220 |
| N3 | AST 深度总和 | 所有节点从根的深度累加 | 抗"藏深嵌套"规避 | 518479 |
| N4 | 最大节点出度 | 任一节点的 list 长度上限 | 抗"压长序列"规避 | 321 |
| N5 | 成员写入数 | MEMBER_ASSIGN 节点数 | 抗"把 Map 搬到 class 字段"规避 | 0 |

## 不可伪造性论证

14 项全部是 AST 结构节点或调用图边的计数,与标识符命名、文件归属、嵌套深度、语言表面形态无关。改名 / 换文件 / 拆 helper / 深嵌套 / 压长序列 / 把 Map 搬到 class 字段 中的任何一种规避手法,都会在至少一项上留下正向增量。**唯一能让全部指标不上升的路径 = 真的削减结构** — 删分支 / 删 Map / 删可变 state / 减 kind 数 / 合并函数 — 这正是 D093 §决策 消除双轨要鼓励的方向。

## Gate 行为

```
bin/ss run tools/reflection_health_linter.ss           # 对比基线
bin/ss run tools/reflection_health_linter.ss record    # 把当前值写为新基线
```

- **任一指标 > baseline → `exit(1)` GATE BLOCKED**(改动触及编译器结构且未伴随根因削减)
- **所有指标 ≤ baseline → `exit(0)` GATE PASS**(无 regression)

仅此两种终态,无中间"ALL TARGETS MET / 未完成目标"分级 — 目标在 D093 §决策 里,不在 linter 阈值里。linter 的职责只做**单调守护**:任何 commit 必须证明自己不加深结构。

## 开发流集成

反射相关改动(触碰 `bootstrap/gen_class.ss` / `gen_stmts.ss` / `check_stmts.ss` 的反射路径,或新增 `classXxxAnnotation*` 全局),**以及任何可能影响编译器结构规模的改动**,在 commit 前必须跑本 linter,任一指标 regression 阻断 commit。

Baseline 更新规则:

- **只在削减方向更新**:例如合并两个 Map 使 M5 从 1758 降到 1750,`bin/ss run tools/reflection_health_linter.ss record` 写入新 baseline,commit message 说明削减路径
- **累积方向严禁更新**:新增 kind 分支 / 新增 Map / 新增 sidecar 导致 M/N 任一项上升,必须先回头削减,不允许"调高 baseline 让 gate 过"

## 后续工作

L2λ 起的反射累积路径**明确废弃**。下一轮根因路径由 D093 §决策 承接(单函数 `evalExpr` dispatch),**不扩展任何 `interp*` 独立求值器副本**:

1. 定义 `ClassMeta / FieldMeta / MethodMeta / AnnotationMeta / ParamMeta` 五类 comptime class(走 D096 Phase 4 L1 "comptime class 能在 runtime 实例化",不是 interp.ss 里的 typed-value struct)
2. `evalExpr` 扩展 MEMBER_ACCESS on Meta 对象 → 返回 `MaybeVal{known:true, val:字段值}`(D093 §SS 本质一样骨架 行 52-59)
3. `evalExpr` / `genForIn` 对 Meta 数组走通用 iteration:迭代目标是编译期常量数组时共享同一 fold 路径,不分"反射专用"支路,`genForInUnrolled` 调用点自然消解
4. 把 L2ζ-L2κ 的 Map 数据 migrate 到 Meta 对象构造(commit `ac4cbc9` `cls.annotations` 走 AST+Meta 删 CSV sidecar 是先例,**非** `interpExpr` 扩展)
5. 逐步删除 `classXxxAnnotation*` Map、`__*` sidecar、`nGetS1(x)==` 字符串分支
6. 每步 `./build.sh bootstrap` 固定点 + linter GATE PASS,M/N 指标在削减方向单调推进(允许部分项保持,**任何一项上升即 regression**)

每次迁移都由 linter 量化推进了多少,不靠感觉。**任何引入 `interp*` 求值器副本的方案都不是根因**,参照 D093 §Rejected Alternatives A/C/D。
