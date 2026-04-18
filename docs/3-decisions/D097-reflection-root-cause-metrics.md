# D097: 反射根因指标 — 不可伪造的 linter 守护

**Status:** 工具链就绪(tools/reflection_health_linter.ss),baseline 冻结 @ commit 0750511
**Depends on:** D088(Zig comptime 路线)、D093(dual-track 消除)、D095/D096(反射 API)
**Date:** 2026-04-18
**Last Updated:** 2026-04-18

---

## 第一性问题

D096 Phase 4 L2ζ-L2κ 为反射每增加一个维度(FieldMeta.annotations、a.args、cls.annotations、cls.methods、m.annotations)就新增:

- 一条 `nGetS1(iterableId) == "成员名"` 的 hardcoded kind 分支
- 一个 `classXxxAnnotations` / `classXxxAnnotationArgs` 全局 Map
- 一个 `__sidecar` sidecar 键伴随 comptimeConsts
- 一个 `genForInUnrolled` 调用点

这是**累积式扩展**,不是**根因解决**。每增加一种反射字段,分支数/Map 数/sidecar 数/调用点都 +1。Zig SEMA 路线(D088/D093)的根因方案是统一的 `ClassMeta/FieldMeta/MethodMeta/AnnotationMeta/ParamMeta` 对象模型 + `interpExpr/interpStmt` 走解释器,反射是 Meta 对象的自然成员访问,无需 kind 分支。

**但 Claude 可以改名、分拆到 helper、挪到深层嵌套,让 grep 误判"根因已解决"**。因此需要**不可伪造的物理指标**:AST 结构性计数,与名字/位置/文件无关。

## 指标定义(不可伪造)

linter 位于 `tools/reflection_health_linter.ss`,通过 `@/bootstrap/lexer` + `@/bootstrap/parser` 复用编译器前端,对 `bootstrap/*.ss` 做 AST 遍历计数。

### G1 — Hardcoded 反射 kind 分支

AST 模式: `BINARY Eq` 节点,其中:
- 左子树为 `CALL` 且 `nGetS1 == "nGetS1"`
- 右子树为 `STRING_LIT` 且 S1 ∈ {`fields`, `methods`, `annotations`, `args`}

物理含义: 编译器对反射成员做字符串等值比较,每个等值比较 = 一条 hardcoded 分支。

**Baseline:** 6 (gen_stmts.ss 5 + check_stmts.ss 1)
**Target:** 0

根因解决后,Meta 对象承载所有反射语义,无需字符串分支。

### G2 — 反射 Annotation 全局 Map

AST 模式: top-level `VAR_DECL`,S1 以 `class` 开头且包含子串 `Annotation`。

物理含义: 反射数据的全局状态散射点。

**Baseline:** 6 (classFieldAnnotations / classFieldAnnotationArgs / classAnnotations / classAnnotationArgs / classMethodAnnotations / classMethodAnnotationArgs)
**Target:** ≤ 1 (允许一个迁移期过渡桥;最终归零)

根因解决后,反射数据存在 Meta 对象里,不需要全局 Map 按字符串键查表。

### G3 — Distinct sidecar 后缀

AST 模式: `TMPL_FRAG_LIT` 节点,S1 包含 `.__<identifier>`,排除 `{__comptime, __ct_, __ct, __FILE__, __LINE__}`(这些是解释器/文件基础设施,非反射 sidecar)。

物理含义: comptimeConsts 上"临时搭车"的状态种类数。

**Baseline:** 4 (`__class`, `__methodCls`, `__annCls`, `__annFld`)
**Target:** 0

根因解决后,for-in 变量直接绑定 Meta 对象,不需要 sidecar 补充上下文。

### G4 — genForInUnrolled 调用点

AST 模式: `CALL` 节点,S1 == `"genForInUnrolled"`。

物理含义: comptime for-in 的宏展开入口数(反模式: 应走解释器统一求值)。

**Baseline:** 8 (全在 gen_stmts.ss)
**Target:** ≤ 2 (保留极少数特殊 literal 展开;主路径归 interpStmt)

根因解决后,`for (x in coll)` 在 comptime 中走 interpStmt + interpExpr,是通用解释器行为,不再是反射专用 macro。

### G5 — Comptime Meta 构造(distinct 类型)

AST 模式: `NEW_EXPR` 节点,S1 ∈ {`ClassMeta`, `FieldMeta`, `MethodMeta`, `AnnotationMeta`, `ParamMeta`}。

物理含义: Meta 对象在 comptime 中被实例化的类型数(≤ 5,因为只有 5 种 Meta)。

**Baseline:** 0 (Meta 只是 D095 概念,还没实体)
**Target:** ≥ 4 (至少 4 种 Meta 在 comptime 中被用到)

根因解决的正向信号: 反射改走 Meta 对象,Meta 的 NEW_EXPR 数量应从 0 爬到 4-5。

## 不可伪造性论证

五个指标都计 AST 结构节点,与标识符命名、文件归属、嵌套深度无关。改名/换文件/拆 helper/深嵌套均不改变计数。唯一合法的降指标路径是真的删除分支/Map/sidecar/调用点,或真的实例化 Meta 对象 —— 这正是根因解决要鼓励的方向。

## Gate 行为

```
bin/ss run tools/reflection_health_linter.ss
```

- G1/G2/G3/G4 任一高于 baseline,或 G5 低于 baseline → `exit(1)` GATE BLOCKED
- 所有指标达标 (G1=0 G2≤1 G3=0 G4≤2 G5≥4) → `exit(0)` ALL TARGETS MET
- 其余 → `exit(0)` GATE PASS (no regressions; 未完成 Zig SEMA 目标)

## 开发流集成

反射相关改动(触碰 `bootstrap/gen_class.ss` / `gen_stmts.ss` / `check_stmts.ss` 的反射路径,或新增 `classXxxAnnotation*` 全局)在 commit 前必须跑本 linter,任何 regression(G1-G4 升、G5 降)阻断 commit。

Baseline 的更新: 仅当是**削减方向的合法变动**(例如合并两个 Map → G2 从 6 降到 5)才允许人工更新 baseline,且必须在 commit message 中说明削减路径。累积方向严禁更新 baseline。

## 后续工作

L2λ 起的反射累积路径**明确废弃**。下一轮工作是根因解决:

1. 定义 `ClassMeta/FieldMeta/MethodMeta/AnnotationMeta/ParamMeta` 五类 comptime class
2. interpExpr 扩展 MEMBER_ACCESS on Meta 对象 → 直接返回字段值
3. interpStmt 扩展 FOR_IN on Meta 数组 → 标准 iteration,不走 genForInUnrolled
4. 把 L2ζ-L2κ 的 Map 数据 migrate 到 Meta 对象构造
5. 逐步删除 `classXxxAnnotation*` Map、`__*` sidecar、`nGetS1(x)==` 分支
6. 每步 bootstrap + linter 验证: G1-G4 递减,G5 递增

每次迁移都由 linter 量化推进了多少,不靠感觉。
