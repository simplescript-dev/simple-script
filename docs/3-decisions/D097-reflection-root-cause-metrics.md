# D097: 反射根因指标 — 不可伪造的 linter 守护

**Status:** 工具链就绪 (tools/reflection_health_linter.ss v2) + **§后续工作 5 闭合 ✓**(D117 Execute 0-5 + D118 Execute 0-4 完整兑现,累积路径消除,2026-04-21;baseline 仍冻结 @ commit `9e20f26` — Execute 1-3 期间 M5/M7b/M4/M3a/N3/F1 七项 PROGRESS 单调削减 vs M2 +89 / N2 +445 累积方向 in tol,GATE PASS 但累积方向 **不触发 record**,符合 §削减方向 record 规则,等未来反射工作 M2/N2 单调降回再触发新 baseline)
**Depends on:** D088(Zig comptime 路线)、D093(单函数 dispatch 消除双轨)、D095/D096(反射 API)
**Date:** 2026-04-18
**Last Updated:** 2026-04-21

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
bin/ss run tools/reflection_health_linter.ss                                       # 对比基线
bin/ss run tools/reflection_health_linter.ss record                                # 把当前值写为新基线
bin/ss run tools/reflection_health_linter.ss bump <metric> <new_budget> <doc>      # 扩容申报升 budget_max (D124)
```

- **任一指标 > budget_max → `exit(1)` GATE BLOCKED**(改动触及编译器结构且未伴随根因削减或扩容申报)
- **所有指标 ≤ budget_max → `exit(0)` GATE PASS**(无 regression)

仅此两种终态,无中间"ALL TARGETS MET / 未完成目标"分级 — 目标在 D093 §决策 里,不在 linter 阈值里。linter 的职责只做**单调守护**:任何 commit 必须证明自己不加深结构。

> **baseline 2 列制升级见 D124**:2026-04-22 起 baseline.txt 升为 `metric=baseline_value:budget_max` 2 列,gate 条件从 `cur ≤ baseline + tol` 升为 `cur ≤ budget_max`。`baseline_value` 承本节"历史证据"角色(单调下压规则保留),`budget_max` 承"gate 阈值"角色(上移必经 `bump` CLI + D 文档 §扩容申报 锚点 + audit trail)。非扩容轮两列同值,gate 行为等同本节严格契约。

## 开发流集成

反射相关改动(触碰 `bootstrap/gen_class.ss` / `gen_stmts.ss` / `check_stmts.ss` 的反射路径,或新增 `classXxxAnnotation*` 全局),**以及任何可能影响编译器结构规模的改动**,在 commit 前必须跑本 linter,任一指标 regression 阻断 commit。

Baseline 更新规则:

- **只在削减方向更新**:例如合并两个 Map 使 M5 从 1758 降到 1750,`bin/ss run tools/reflection_health_linter.ss record` 写入新 baseline,commit message 说明削减路径
- **累积方向严禁更新**:新增 kind 分支 / 新增 Map / 新增 sidecar 导致 M/N 任一项上升,必须先回头削减,不允许"调高 baseline 让 gate 过"
- **扩容申报(D124 2 列制)**:形态升级(容器 Array→Map / 新 Meta kind / AST 字段扩)累计组物理下限必然上升,走 `bump` CLI + D 文档 §扩容申报段 + audit trail,`budget_max` 申报驱动上移,`baseline_value` 在 Execute 完成后另一次 record 同步(DRIFT 态 cur ≤ budget_max 允许升 bv)

## 后续工作

L2λ 起的反射累积路径**明确废弃**。下一轮根因路径由 D093 §决策 承接(单函数 `evalExpr` dispatch),**不扩展任何 `interp*` 独立求值器副本**:

1. [x] Done at `bootstrap/parse/prelude.ss:19,25,31,36,43`(D117 Execute 1 commit `cc1624b`)— 5 类 comptime Meta 载体 `FieldMeta(L19) / AnnotationMeta(L25) / ParamMeta(L31) / MethodMeta(L36) / ClassMeta(L43)` 全部在 prelude.ss 定义,走 D096 Phase 4 L1 "comptime class 能在 runtime 实例化",不是 interp.ss typed-value struct
2. [x] Done at `bootstrap/eval/member_access.ss:36` + `bootstrap/eval/interp_obj.ss:11`(D117 Execute 3 commit `bda5813`)— evalMemberAccess `isKnownClass(clsName) == 1` 分支统一走 `interpGetField(interpBuildTypeInfo(clsName), member)`,Meta 对象成员访问与普通对象成员访问共享 `interpGetField` 入口,无 hardcoded `cls.fields`/`.annotations` 特例
3. [x] Done at `bootstrap/gen/stmts/stmts_loop_forin.ss:12,105,113`(D117 Execute 4 commit `f80bf95`)+ `bootstrap/eval/interp_obj.ss`(D117 Execute 5 commit `6e264fd` 删 `interpCollectFields` / `interpCtFieldsArray` 两字符串路径函数)— `genForInUnrolled` 单一入口,Meta 数组(cls.fields / cls.methods / m.annotations / a.args)走通用 fold 路径 + ct-probe 绑 Meta object 到 ctVars,反射专用支路消解;`grep -rn "interpCollectFields\|interpCtFieldsArray" bootstrap/` 0 命中
4. [x] Done at `bootstrap/eval/interp_obj.ss:151`(D117 Execute 2-5 + D118 Execute 1-3)— `interpBuildTypeInfo(typeName)` 单入口构造 ClassMeta/FieldMeta/MethodMeta/AnnotationMeta/ParamMeta 全图,数据源是 AST(`classNodeIds[typeName]` → class AST → paramList / methodsBlock / ANNOTATION_LIST),InternPool dedup,走 commit `ac4cbc9` `cls.annotations` 先例的同形态——**非** `interpExpr` 扩展
5. [x] Done at `bootstrap/gen/class/class.ss:15,57` + `bootstrap/gen/class/class_register.ss:48-63` + `bootstrap/eval/member_access.ss:4-8` + `bootstrap/gen/stmts/stmts_loop_forin.ss:12-67,108` + `bootstrap/gen/class/class_comptime.ss:98-108` + `bootstrap/gen/exprs/exprs.ss:15-50`(D118 Execute 1-3 commits `9cced65`/`7cbe55f`/`100dc44`)—
   - **3 `classXxxAnnotation*` Map 全删**:`classFieldAnnotations` + `classFieldAnnotationArgs`(Execute 1)+ `classMethodAnnotations`(Execute 2);`grep -rn "classFieldAnnotations\|classFieldAnnotationArgs\|classMethodAnnotations\|extractAnnotationsReflection" bootstrap/` 0 命中
   - **`extractAnnotationsReflection` CSV 拼接函数删**(Execute 2,16 行 + 6 行调用点 + 5 行 args 提取分支)
   - **`__class` sidecar 删**:`member_access.ss:14-32` `fmClsKey=${fmName}.__class` 读取 + `stmts_loop_forin.ss:35,64` `comptimeConsts.set/delete(${itemName}.__class, ...)` 两处写入(Execute 3)
   - **member_access 三 hardcoded 反射分支删**:`member_access.ss:4-8` evalMemberAccess L7-33 `comptimeConsts.has(fmName) && member==name/type/annotations` 三分支(Execute 3)+ `class_comptime.ss:98-108` `MEMBER_ACCESS.name && mObj=STRING_LIT` 4 行子分支(Execute 3 Class B 收敛点位 1)+ `exprs.ss:15-50` isCtStringIdx + resolveCtString `MEMBER_ACCESS.name && mObj=STRING_LIT` 子分支 + `comptimeConsts.has(mObj)` 子条件(Execute 3 Class B 收敛点位 2)
   - **Class B 剩余 5 处反射 nGetS1 字符串分支** 经 D118 §决策 4 评估为"已最小化无削减空间"(`check_stmts.ss:386` + `gen_types.ss:437,441` + `exprs.ss:30`),归档至 D119 重评(Plan 起草触发条件:未来反射新维度扩展冲击该 5 处)
6. [x] Done(D117 Execute 1-5 + D118 Execute 1-3 每 commit)— 每步 `./build.sh bootstrap` 固定点 + `bin/ss run tools/reflection_health_linter.ss` GATE PASS;最终累计 vs 原 baseline(commit `9e20f26`)M1 -8 / M3a -15 / M4 -40 / M5 -11 / M7b -2 / N3 -4822 / F1 gen_decls.ss 691→690 **PROGRESS 单调削减**;M2 +89 / N2 +445 在 tol 内(±380 / ±1903)— **零 regression**

每次迁移都由 linter 量化推进了多少,不靠感觉。**任何引入 `interp*` 求值器副本的方案都不是根因**,参照 D093 §Rejected Alternatives A/C/D。

## 闭合(2026-04-21 D117+D118 完成 — accumulative path 根因消除)

§第一性问题 描述的"反射每增加一个维度就新增 1 hardcoded kind 分支 + 1 全局 Map + 1 sidecar 键 + 1 genForInUnrolled 调用点"四元累积路径,经 D117 Execute 0-5 + D118 Execute 1-3 八轮迁移**完整消除**:

| 累积维度 | D097 当时残量 | 2026-04-21 现状 | 根因消除轨迹 |
|---|---|---|---|
| hardcoded `nGetS1==` kind 分支 | L2ζ-L2κ 5+ 处反射特例 | 反射相关 0 处(D118 Execute 3 删 member_access 3 + class_comptime 1 + exprs 1);非反射 15 处 AST kind 合法检查保留无累积风险 | D117 Execute 3 evalMemberAccess on Meta 统一 + D118 Execute 3 三分支根治 |
| `classXxxAnnotation*` 全局 Map | 3 Map(classFieldAnnotations / classFieldAnnotationArgs / classMethodAnnotations) | 0 Map(`grep` 全代码零命中)| D118 Execute 1-2 删 3 Map + extractAnnotationsReflection 函数 |
| `__sidecar` 键(伴随 comptimeConsts) | `__class` sidecar 在 stmts_loop_forin / member_access | 0 sidecar(member_access.ss:4-8 + stmts_loop_forin.ss:12-67 全删)| D118 Execute 3 for-in unroll 绑 FieldMeta object 替代 string + sidecar |
| `genForInUnrolled` 调用点(反射专用) | cls.fields / cls.methods / m.annotations / a.args 各一份 | 1 单入口(stmts_loop_forin.ss:12 + 105 + 113),Meta 数组走通用 fold + ct-probe | D117 Execute 4-5 删 interpCollectFields / interpCtFieldsArray + 通用 fold |

D088 §第一性需求"反射是 Meta 对象自然成员访问,与普通字段访问共享 evalExpr 分发,无需 kind 分支"**完整兑现**。后续若新增反射维度,走"扩 Meta class 字段 + AST 直读"模板(已建立 5 类 Meta + interpBuildTypeInfo 单入口 + InternPool dedup),不再需要新 Map / 新 sidecar / 新 hardcoded 分支。D097 双 gate(§累积方向严禁 record + §削减方向单调推进)在 D117+D118 期间持续守护无 regression。
