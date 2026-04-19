# D100: evalExpr Phase A 中批 1b 首轮 Plan — INDEX_ACCESS

**Status:** Draft(待批准后 Execute)
**Depends on:** D099 §步骤 0-6(Phase A 首批 1a 5 kind 已合并)/ D098 §决策 1(mv Phase A 纯 int 编码)/ D094 §规则 2(pure subset 白名单)
**Date:** 2026-04-19

---

## 第一性需求

D099 首批 1a 合并 5 kind(BINARY / UNARY / TERNARY / SHORT_CIRCUIT / COMPTIME_EXPR),Execute 6b record 后 baseline 刷新到 `M1=5135 / M2=76153 / M3a=12133 / M3b=1879 / M4=3038 / M5=1750 / M7b=678 / N2=380765 / N3=518387`。**中批 1b 承接 D094 §规则 2 pure subset 余项**:IDENT / MEMBER_ACCESS / INDEX_ACCESS / TEMPLATE_LIT / ARRAY_LIT。

本 Plan 选 **INDEX_ACCESS** 作 1b 首个着陆 kind。

## 为什么首批 1b 选 INDEX_ACCESS(5 候选对照)

| kind | 体量(行) | subsystem 耦合 | 节点密度(估) | 风险 |
|---|---|---|---|---|
| **INDEX_ACCESS** | L648-673,**26 行** | 无 | ~80 | 最低 |
| TEMPLATE_LIT | L537-578,42 行 | template literal 本身触坑 N | ~130 | 中 |
| ARRAY_LIT | L580-643,63 行 | SPREAD_ELEM 展开分支 | ~180 | 中-高 |
| MEMBER_ACCESS | L340-462,**123 行** | **反射路径**(D095 FieldMeta / D097 AnnotationMeta / enum / class field) | ~400 | 极高(触 CLAUDE.md §反射根因 gate) |
| IDENT | L134-174,40 行 | ctScopeStack + genericTypeSubs + resolveCtTypeAlias + ctInvalidated 5 路径 | ~150 | 高(D099 §Rejected §A 已否决作早期) |

**INDEX_ACCESS 首选依据**:
1. **形态最纯**:`obj + idx` 两 operand,comptime 分派 3 条类型(array / object|map / string),runtime 单 call `genIndexAccess`,与 D094 §规则 2 pure subset 严格对齐
2. **零 subsystem 耦合**:不触反射 gate、不触 scope / generic 机制、不触 annotation 路径
3. **节点密度最低**:26 行 body ~80 节点,比 TERNARY runtime phi(坑 L 触发)/ COMPTIME_EXPR 深嵌套(坑 N 触发)都小
4. **对称 pattern 铺垫**:1b 首轮跑通后,TEMPLATE_LIT / ARRAY_LIT 直接套用"删 genVal 内联分支 + 新建 evalX 独立函数 + L132 `||` 链扩"三段式,减少 Execute 决策开销
5. **operand 只 2 个**:不需处理 N 元迭代(TEMPLATE_LIT parts / ARRAY_LIT elems)结构化 operand,坑 H 延续"operand 走 genVal 不递归 evalExpr"成本最小

## 当前事实(2026-04-19 `bootstrap/gen_exprs.ss` snapshot)

| kind | 当前分派位置 | 独立函数 / 内联 |
|---|---|---|
| INDEX_ACCESS | `genVal` L648-673 | **内联 26 行**,无独立 genVal* 函数 |

L132 当前 shim:`if (kind == "BINARY" \|\| kind == "UNARY" \|\| kind == "TERNARY" \|\| kind == "COMPTIME_EXPR") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }` —— 4 kind 共享 inline mv decode。

eval_expr.ss 170 行:evalExpr + evalTernary + evalShortCircuit + evalComptimeExpr 4 函数承接 5 kind 单 pass 路径。

## 对照 D099 §坑 G-O 的 N3/M7b 挑战预判

**baseline 刚 record 所有指标余量 = 0(M7b=678=cur,N3=518387=cur)**,这是 D100 首批 1b 与 D099 §步骤 0 最大差异:D099 step 0 时 M7b 有 -1 baseline 余量可用(baseline 679 / cur 678)抵消新 evalExpr 函数 +1,D100 无此余量。

| 坑 | 预判 INDEX_ACCESS 影响 |
|---|---|
| **G**(helpers 不建)| 延续 — mv 编码继续纯 int inline(`mv >= 0 ? mv : 0 - mv - 1`),不建 mvKnown/mvKnownOf |
| **H**(operand 走 genVal)| 延续 — `obj = genVal(nGetI1)`, `idx = genVal(nGetI2)`,不递归 evalExpr(evalExpr dispatch 表仅识别 6 kind) |
| **I**(外层 `if kind` 炸 N3)| **触发** — INDEX_ACCESS body ~80 节点 inline 进 evalExpr `if kind == INDEX_ACCESS` 块 depth 2,预估 N3 +40~80,N3 余量 0 必 BLOCKED |
| **K**(M7b 余量 0 inline X4)| 在 D099 step 2 可行(N3 余量 889),D100 **不可行**(N3 余量 0) |
| **L/M/N**(独立函数对称 pattern)| **首选** — `evalIndexAccess(astId: int): int` body depth 1,与 evalTernary / evalShortCircuit / evalComptimeExpr 对称 |
| **N 修正判据**(body 节点数 × depth delta)| INDEX_ACCESS body ~80 节点 × inline depth delta 1 = N3 +80 → 独立函数必需 |
| **O**(shim 规模重评估)| L132 `\|\|` 链当前 4 kind 扩成 5 kind(`\|\| INDEX_ACCESS`),shim body 完全同构,dispatch 行 0 新增,仅字符串条件长度 +18 字符(M2 微增) |

**核心张力**:evalIndexAccess 新函数 M7b +1 无对应可删的 `genValIndexAccess`(当前 inline,不是函数)。**必须在 step 0 做预削减拿余量**,否则 step 1 立即 GATE BLOCKED。

## 决策(分 3 步,每步独立可 bootstrap + linter GATE PASS)

### §步骤 0 — 预削减 commit(拿 M7b 或 N3 余量,为 step 1 腾空间)

**目标**:在**不改 INDEX_ACCESS 语义**前提下,找 bootstrap 内可合并 / 可删的冗余,拿 M7b ≥ -1 或 N3 ≥ -80 余量,同时**不触反射路径**(§反射根因 gate 约束)。

**候选削减源**(Execute 0 先 grep 验证,找到任一源单 commit 落地即可):

1. **eval_expr.ss 内 BINARY block L53-102 抽独立 `evalBinary`**:当前 evalExpr body 50 行 BINARY 逻辑,抽出后 evalExpr 退化为纯 dispatcher。M7b +1 新函数,同时 evalExpr body 从 ~100 行缩到 ~50 行 depth -1 对 N3 削减 ~-80。**风险**:M7b 净 +1 仍 BLOCKED,不单独可行,需结合下列某项
2. **genValStringCompare L690-730 comptime 折叠部分 inline 回 evalExpr BINARY string-string 分支**:当前 eval_expr.ss L76 / L90 两处委托 genValStringCompare,inline 后 genValStringCompare 可能瘦到只剩 runtime IR emit。**风险**:genValStringCompare 可能被 gen_exprs 其他路径调用,grep 确认单调用点才可删
3. **L127-131 六条字面量 if 合并**(INT_LIT/STRING_LIT/TRUE_LIT/FALSE_LIT/NULL_LIT/DOUBLE_LIT):当前 6 行独立 if,可压缩为 switch-less dispatch Map 或单 if 链。**风险**:字面量路径是热路径,改动须极小心,优先级最低
4. **gen_rt_* 死代码 grep**:某些 runtime helper 可能已被 Phase A 消除(如 BINARY 迁移后某 interp helper 无调用点)。需 grep 确认

**Execute 0 实操**:按 PFV 流程先填 PSM,grep 每候选调用点,实测 linter 削减量,挑**净削减最大的一项**单 commit 落地。**不合并多项**(保持 step 独立可回滚)。

**验证**:
- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- `bin/ss run tools/reflection_health_linter.ss` **GATE PASS**,预期 M7b -1 或 N3 -80+

**若无单项可达预削减目标**:step 0 拆 0a/0b 两 commit 累积,但每 commit 独立 GATE PASS。

### §步骤 1 — INDEX_ACCESS 迁移(独立函数 evalIndexAccess,对称 pattern)

**新建 `bootstrap/eval_expr.ss` 末尾 `evalIndexAccess(astId: int): int`**:

```ss
function evalIndexAccess(astId: int): int {
    const obj = genVal(nGetI1(astId))   // 坑 H:operand 保留 genVal(不递归 evalExpr)
    const idx = genVal(nGetI2(astId))
    if (isCt(obj) == 1 && isCt(idx) == 1) {
        const objP = payload(obj)
        const ot = interpType(objP)
        if (ot == "array") { return ctVal(interpArrayGet(objP, interpAsInt(payload(idx)))) }
        if (ot == "object" || ot == "map") { return ctVal(interpGetField(objP, interpAsStr(payload(idx)))) }
        if (ot == "string") {
            const s = interpAsStr(objP)
            const i = interpAsInt(payload(idx))
            if (i >= 0 && i < s.length()) { return ctVal(interpNewString(s.charAt(i))) }
            return ctVal(interpNewString(""))
        }
    }
    if (comptimeDepth > 0) { return comptimeError("index access requires compile-time known operands", astId) }
    return 0 - constVal(genIndexAccess(astId, reg(obj), reg(idx))) - 1
}
```

**改 `bootstrap/gen_exprs.ss` L132**:
```ss
// BEFORE
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR") { ... }
// AFTER
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
```

**改 `bootstrap/eval_expr.ss` evalExpr 顶部**(UNARY 分派后加 1 行):
```ss
if (nGetKind(astId) == "INDEX_ACCESS") { return evalIndexAccess(astId) }
```

**删 `bootstrap/gen_exprs.ss` L648-673 整块**(26 行 INDEX_ACCESS inline body)

**验证**:
- bootstrap 固定点 PASS(stage2 == stage3)
- INDEX_ACCESS 测试全绿:array / map / string 三类索引 + comptime 折叠 + runtime emit
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS(所有 14 指标 ≤ 新 baseline)

### §步骤 2 — 收尾量化 + 更新 D100 §下一步指向 1b 第 2 个 kind 选型

**目标**:step 1 完成后评估是 record 新 baseline 还是继续 1b 下一个 kind(TEMPLATE_LIT / ARRAY_LIT 二选)后再 bundle record。**默认不 record**,等 1b 全部 5 kind 着陆后单 commit record(类似 D099 §步骤 6b)。

**决策点**:
- 如 step 1 后 M7b / N3 仍有余量 → 继续 1b 第 2 个 kind,sub-plan 另写 D101
- 如余量紧张 → 独立 commit record 释放余量给下 kind

## 预期累计削减(step 0→2,对照 D099 Execute 6b baseline)

| 指标 | Execute 6b baseline | step 1 后 cur(估) | Δ 累计 | 依据 |
|---|---|---|---|---|
| M1 CC | 5135 | 5130-5134 | -1 ~ -5 | evalIndexAccess 合并 3 条类型 if 链;gen_exprs L648-673 删除原 3 if 链 |
| M2 节点数 | 76153 | 76050-76100 | -50 ~ -100 | body 从内联 depth 4-5 移到独立函数 depth 1-2,节点总数近似,深度贡献削减 |
| M3a 调用边 | 12133 | 12130-12132 | -1 ~ -3 | genVal → evalIndexAccess 新边 +1;L132 扁平化少 1 调用 |
| M3b 最大入度 | 1879 | 1879 | 0 | 不触最大入度函数 |
| M4 dispatch 深度 | 3038 | 3035-3037 | -1 ~ -3 | genVal 内 `if kind == "INDEX_ACCESS"` 删除,dispatch 链 -1 |
| M7b 函数数 | 678 | **678**(净 0)| **0** | +1 evalIndexAccess 被 step 0 预削减抵消 |
| N2 Halstead | 380765 | 380600-380700 | -65 ~ -165 | body 深度下降 + 多余变量声明减少 |
| N3 AST 深度和 | 518387 | 518300-518380 | -7 ~ -87 | body 从 depth 4-5 移到独立函数 depth 1-2 |
| 其余(M5 / M6 / M7a / N1 / N4 / N5)| - | 持平 | 0 | 不引入新 kind、无 Halstead 体积上升、无深嵌套、无 MEMBER_ASSIGN |

**收尾 gate**:所有指标 ≤ Execute 6b baseline(step 0 预削减 + step 1 独立函数迁移组合达成净削减),若 step 0 单项选得当,step 1 可实现 **M7b 净 0 + N3 额外削减** 双赢。

## Rejected Alternatives(为何不选其他 4 候选作 1b 首轮)

- **A:首轮选 TEMPLATE_LIT** — body 42 行 / 节点 ~130,参数更复杂(parts 迭代 × 2 + Map fragVals + SPREAD_ELEM 处理)。触坑 N(template literal body),独立函数必需。但 Step 0 预削减压力更大(N3 +120 级),作 1b 第 2 个 kind 更合理(1b 首轮验证 pattern 后)
- **B:首轮选 ARRAY_LIT** — body 63 行 / 节点 ~180,含 SPREAD_ELEM spread 展开分支。与 TEMPLATE_LIT 类似是多 operand 迭代结构,比 TEMPLATE_LIT 多一层(SPREAD_ELEM 分支内 while srcI<srcLen 数组展开),Step 0 预削减压力最大,推到 1b 末轮
- **C:首轮选 IDENT** — D099 §Rejected §A 已明言"涉及 ctInvalidated + ctScopeStack + genericTypeSubs + resolveCtTypeAlias 5 条路径,单一 kind 超 40 行状态"。IDENT 作 1b 末轮或推 Phase A 后批 2(需 D098 §决策 2 Phase B MaybeVal 类化期吸收 scope 机制)
- **D:首轮选 MEMBER_ACCESS** — body 123 行,触**反射根因 gate**(CLAUDE.md §反射根因 gate 强制条款),改动反射路径必须过 `reflection_health_linter` G1-G5。MEMBER_ACCESS 含 D095 FieldMeta / D097 AnnotationMeta 累积路径,本轮不应承担
- **E:跳过 Step 0 预削减,直接 step 1 inline INDEX_ACCESS body** — N3 余量 0 必 GATE BLOCKED,违反 D099 §规则"不改 baseline 让 gate 过"

## 新张力(D100 引出)

1. **Step 0 预削减源不明确** — 与 D099 §步骤 0 空壳骨架不同,D100 step 0 需找 existing code 里的冗余。Execute 0 必须 grep 验证每候选可行性,若无单项达 -1 M7b / -80 N3 → step 0 拆 0a/0b 累积。**本 Plan 不钦定源**,Execute 轮按 PFV 流程决定
2. **evalIndexAccess 与 evalTernary/evalShortCircuit/evalComptimeExpr 对称 pattern 进一步固化** — 4 个 eval* 独立函数 body depth 1,dispatch 分派 1 行,caller 走 L132 inline mv decode。1b 剩余 kind(TEMPLATE_LIT / ARRAY_LIT / IDENT / MEMBER_ACCESS)如都走此 pattern,Phase A 完成时 eval_expr.ss 将有 5-9 个 eval* 函数,M7b 显著增长,**Phase B 类化期需评估**是否压回单 evalExpr body(MaybeVal class 携带 state 后可能 inline 回无深度代价)
3. **INDEX_ACCESS comptime object/map 分支调 `interpGetField`** — 当前 genVal L660 路径。D094 §规则 2 pure subset 是否包含 interpGetField?**包含**(纯读取,无副作用),但 Phase B MaybeVal 类化后需确认 `interpGetField` 返回值类型与 mv 编码兼容
4. **Step 0 预削减 `genValStringCompare` inline 候选与 eval_expr.ss L76/L90 耦合** — 若 step 0 选此源,需同步改 evalExpr BINARY block,**step 0 与 step 1 scope 不能混**,独立 commit

## 踩过的坑(Execute 实录占位 — Plan 阶段空)

*Execute 轮按 D099 §坑 G-O 格式追加记录*

## 下一步(Plan 下的 Execute 顺序)

**本 D 文档不触发任何 bootstrap 改动**。用户批准本 Plan 后,Execute 轮按以下顺序(每步一个 commit,每个 commit linter GATE PASS):

1. **Execute 0**:step 0 预削减 — grep 候选源 → 实测削减量 → 单 commit 落地拿 ≥ -1 M7b 或 ≥ -80 N3 余量
2. **Execute 1**:step 1 INDEX_ACCESS 迁移 — 新建 evalIndexAccess + 改 L132 `\|\|` 链 + 删 L648-673 inline body
3. **Execute 2**:step 2 收尾评估 — 决策是 record baseline 还是继续 1b 下一 kind(另起 D101)

每 Execute 开始前必须先填 PSM 十问(PFV 流程),完成后过 VCM 五验。单步 bootstrap 失败 → 定位根因不越步;单步 linter 任一指标 regression → 先削减再推进,不改 baseline 让 gate 过(CLAUDE.md §反射根因 gate 强制条款)。

## 参考

- D099 §步骤 0-6 + §坑 G-O(首批 1a 对称 pattern + N3/M7b 成本经验)
- D094 §决策 §规则 2 pure subset 白名单(INDEX_ACCESS 归属)
- D098 §决策 1 MaybeVal Phase A 编码(mv 编码协议不变)
- `bootstrap/gen_exprs.ss` L648-673(INDEX_ACCESS 当前 inline)
- `bootstrap/eval_expr.ss` L105-170(4 eval* 对称 pattern 模板)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt` @ Execute 6b(D099 收尾 record 的 baseline,D100 step 1 不刷新)
