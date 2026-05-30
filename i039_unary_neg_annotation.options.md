# I039 — annotation arg 负数字面量(UNARY)未支持 — 方案对比

**bug:** `@M(neg = -2.5)` / `@M(min = -10)` → `[comptime] annotation arg kind 'UNARY' not yet supported`(`interp_obj.ss:211`)
**根因层定位:** `evalAnnotationArg`(`bootstrap/eval/interp_obj.ss:170`)kind 分派表覆盖 STRING_LIT / INT_LIT / DOUBLE_LIT / TRUE_LIT / FALSE_LIT / MEMBER_ACCESS / ARRAY_LIT / IDENT,**独缺 UNARY** → 负字面量(SS 无裸负字面量,`-x` 统一解析成 UNARY)fall through 到 loud comptimeError。

## §实证(MNK §字段 12)

**事实断言核对(grep + read,当场贴):**
- UNARY op 槽 = `nGetS1`、operand 槽 = `nGetI1` —— `eval_expr.ss:52-53` `const uOp = nGetS1(astId); const childId = nGetI1(astId)` 实证
- 一元负 op 字符串 = `"Neg"` —— `eval_expr.ss:65` `if (uOp == "Neg") { return ctVal(interpNewInt(0 - interpAsInt(subP))) }` 实证
- evalAnnotationArg 缺 UNARY —— `interp_obj.ss:170-211` read 实证(8 kind 分支无 UNARY,fall through `comptimeError` @:211)
- **关键约束发现**:`eval_expr.ss:54-60` UNARY **只 fold int/bool**,double 走 runtime punt(`uType != "int" && uType != "bool"` → `genUnary(astId)`),line 50-51 注释"double fold 留 1.5c"是 finding C 前 stale 理由 —— 即 eval_expr **没有** comptime double-negate 可供复用(影响候选 C 判定)

**最危险假设:** `-2.5` 在 parser 是 `UNARY(op="Neg", operand=DOUBLE_LIT)`,而非折成 `DOUBLE_LIT(-2.5)` 或别的 op 名。
**证伪/坐实:** 错误信息字面 `kind 'UNARY'` 坐实是 UNARY 节点;op 名 `"Neg"` 由 `eval_expr.ss:65` 坐实;operand 在 `nGetI1`。
**最小 spike:** 在 evalAnnotationArg 加 1 处 UNARY-Neg 分支 → 跑 `/tmp/i039_red.ss` → 期望 `d=-2.5 i=-10` GREEN,再 bootstrap 三阶段定点 + 全测。

## 候选方案(候选 ≥ 3 + 层次标 + 决策行)

| 候选 | 层次 | 做法 | 根因解决度 | 假设破裂闭合 |
|---|---|---|---|---|
| **A** | 接口层 | `evalAnnotationArg` 补 UNARY 分支:`uOp=="Neg"` + operand 是 INT_LIT/DOUBLE_LIT → 直接读 operand literal string 解析+取负(`interpNewInt(0 - parseInt(...))` / `interpNewDouble(0.0 - parseDouble(...))`),镜像既有 INT_LIT/DOUBLE_LIT 分支加负号;非数值 operand / 非 Neg unary 维持 fall-through loud | **高** — I039 根因精确就是该分派表缺 UNARY,在边界补 Neg+numeric-literal 分支即根治 | "Neg"+nGetS1/nGetI1 假设由 spike 实切坐实 |
| **B** | 接口层 | UNARY 分支递归 `evalAnnotationArg(operand)` 拿 tv,再按 `interpType` 取负(int 直减 / double 走 `bitsToDouble(interpAsStr)` 重建后 `0.0 - d`) | 中 — 复用 operand eval 但引双重 readback(bitsToDouble),而 annotation operand 必为 literal,无额外覆盖收益,徒增复杂度 | 同 A |
| **C** | 架构层 | 抽 `interpNegateValue(valId)` shared helper(int/double dispatch),`eval_expr.ss` UNARY + evalAnnotationArg 共用;**附带**补 eval_expr double-unary-fold(line 55 punt) | 看似最深,但把"eval_expr comptime double unary fold"(独立 deferred 项,line 50-51 注释)拉进 I039 = scope creep + 触碰中央 evalExpr dispatch 风险,违 §字段 8 scope | — |

**决策行:** **选 A,因** I039 根因精确落在 `evalAnnotationArg` 分派表缺 UNARY 这一接口边界,补 Neg+numeric-literal 分支是该边界的根因解决;不退化为数据层 call-site patch(buildAnnotationMetaArray 预取负 = 绕过真分派表),不升到架构层 C(把独立 deferred 的 eval_expr double-fold 拉进来 = scope creep 触中央 dispatch);不选 B 因双重 readback 复杂度无覆盖收益(operand 必为 literal,直接读源更清晰)。

**§字段 11 ladder:** A 对 I039 scope 是最根 —— 更"深"的 C 是另一条 deferred 主线(eval_expr double unary fold,证据 `eval_expr.ss:50-51` 注释),非 I039 更根,强拉入是 scope creep。
**假设破裂入口:** "`-2.5` = UNARY(op=Neg, operand=DOUBLE_LIT)";spike 实切坐实后方全量 Execute。
