# D099: evalExpr Phase A 首批 1a 合并 Plan — BINARY / UNARY / TERNARY / SHORT_CIRCUIT / COMPTIME_EXPR

**Status:** Planned(纯 Plan,本 D 文档不改代码,不跑 bootstrap,授权后方开 Execute 轮)
**Depends on:** D093(evalExpr 单函数 dispatch 骨架)/ D094 §决策 §规则 2(pure subset 白名单)/ D098 §决策 1(MaybeVal 编码 + 构造器/访问器接口)
**Date:** 2026-04-18
**Last Updated:** 2026-04-18

---

## 第一性需求

D093 §决策 要求把 comptime/runtime 双轨合并为 evalExpr 单函数 dispatch 返回 `?Value`(SS 化为 `MaybeVal`)。D098 §决策 1 已敲定 `MaybeVal{known,val}` 接口 + 构造器(mvKnown/mvRuntime/mvError)+ 访问器(mvKnownOf/mvValOf)。**缺失:骨架迁移的第一批着陆点**。

本 Plan 选 5 个**表达式纯形态** kind 作首批 1a:

| kind | 为什么作首批 |
|---|---|
| **BINARY** | D094 §规则 2 pure subset 白名单首项;最高频、operand-driven 折叠天然适用;无诊断副作用 |
| **UNARY** | pure subset 白名单;单操作数,逻辑最简单 |
| **TERNARY** | pure subset 扩展;三操作数但仍无副作用;操作数分支已现成 |
| **SHORT_CIRCUIT**(BINARY `&&` / `\|\|`)| 已被 BINARY L699 派出到 `genValShortCircuit` 独立函数,合并时需一并拉回 evalExpr 统一 |
| **COMPTIME_EXPR** | `comptime{...}` 块入口本身;evalExpr 路径里 COMPTIME_EXPR 必须返回 known=true 否则 comptimeError,与 D094 §规则 2 "块内全部编译期" 对齐 |

5 kind 全是**无副作用纯求值**,是 D094 §规则 2 定义的 pure subset 核心子集,合并时不触及 IO/赋值/调用/诊断路径。CALL/METHOD_CALL/NEW_EXPR 首批**不动**(有 println/exit 诊断副作用,触 D094 §规则 2 "不自动折叠"条款,推到 Phase A 中批 1b)。

## 当前事实(2026-04-18 `bootstrap/gen_exprs.ss` snapshot)

| kind | 当前分派位置 | 独立函数 / 内联 |
|---|---|---|
| BINARY | `genVal` L132 → `genValBinary(id)` | L697 独立函数 |
| UNARY | `genVal` L133 → `genValUnary(id)` | L759 独立函数 |
| TERNARY | `genVal` L135 → `genValTernary(id)` | L804 独立函数 |
| SHORT_CIRCUIT(BINARY And/Or)| `genValBinary` L699 `if op=="And"\|\|"Or" → genValShortCircuit` | L837 独立函数 |
| COMPTIME_EXPR | `genVal` L212 内联(约 4 行)| 无独立函数 |

`bootstrap/gen_exprs.ss` 中 `comptimeDepth` 出现 **33 处**(2026-04-18 grep 实测,D093 §差距清单 40+ snapshot 是历史值,已 drift)。5 kind 贡献的 comptimeDepth 分支待分步骤表记录。

## 决策(分 6 步,每步独立可 bootstrap + linter GATE PASS)

### §步骤 0 — 建 evalExpr 骨架 + MaybeVal class 落地

**目标**:在 `bootstrap/gen_exprs.ss` 或新文件 `bootstrap/eval_expr.ss` 中建 evalExpr 骨架,**不改任何现有 genVal/genValBinary/... 调用路径**。evalExpr 先走**旁路**(没有调用者),由步骤 1-5 逐步接入。

**落地**:
```ss
class MaybeVal {
    known: bool;
    val: int;
}
function mvKnown(valId: int): MaybeVal { return new MaybeVal(true, valId); }
function mvRuntime(regId: int): MaybeVal { return new MaybeVal(false, regId); }
function mvError(): MaybeVal { return new MaybeVal(false, -1); }
function mvKnownOf(mv: MaybeVal): bool { return mv.known; }
function mvValOf(mv: MaybeVal): int { return mv.val; }

function evalExpr(astId: int): MaybeVal {
    // 首批 1a 只覆盖 5 kind,其余 kind 返回 mvError() 占位
    const kind = nGetKind(astId);
    // kind 分支由步骤 1-5 依次填入
    return mvError();
}
```

**验证**:
- `./build.sh bootstrap` 固定点 PASS(新增 class + 函数,无调用点,不影响现有语义)
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS(M2 节点数、M7b 函数数会上升 — **这是步骤 0 唯一允许的上升**,因为骨架本身就是新增结构。步骤 1-5 必须用"合并削减"抵消到不低于 baseline)

**Linter 指标预期(步骤 0 单步)**:M2 +~15(class + 6 函数 AST 节点)/ M7b +7 / 其他 M/N 持平。**累计到步骤 5 结束必须全部 ≤ baseline**,中途不 record baseline。

### §步骤 1 — BINARY 迁移(不含 And/Or,留给步骤 4)

**改 `evalExpr`**:
```ss
if (kind == "BINARY") {
    const op = nGetS1(astId);
    if (op == "And" || op == "Or") { /* 由步骤 4 接管 */ return mvError(); }
    const lhs = evalExpr(nGetI1(astId));
    const rhs = evalExpr(nGetI2(astId));
    if (mvKnownOf(lhs) && mvKnownOf(rhs)) {
        // 调 interp* 常量计算(复用现有 interpBinop 路径)
        return mvKnown(interpBinop(op, mvValOf(lhs), mvValOf(rhs)));
    }
    // operand-driven pure subset(D094 §规则 2):
    //   块外 BINARY 且 allOperandsCt 为 false → 发射 runtime 指令
    //   块内(comptimeDepth > 0)则调用方应检查 mvKnownOf 失败即 error
    return mvRuntime(emitBinaryRuntime(astId, lhs, rhs));
}
```

**改 `genVal` L132**:
```ss
if (kind == "BINARY") {
    const op = nGetS1(id);
    if (op == "And" || op == "Or") { return genValBinary(id); } // 步骤 4 前 And/Or 仍走老路
    const mv = evalExpr(id);
    if (mvKnownOf(mv)) { return ctVal(mvValOf(mv)); }
    if (comptimeDepth > 0) { return comptimeError("BINARY needs known operands in comptime block", id); }
    return constVal(regTable[mvValOf(mv)]);
}
```

**删 `genValBinary`** 中 And/Or 以外的主路径(保留 And/Or shim 直到步骤 4)。

**验证**:
- bootstrap 固定点 PASS
- 现有 BINARY 测试全绿(算术/比较/字符串拼接)
- linter:M1 CC 削 ~3-5 / M4 dispatch 削 ~2 / M3a 调用边削 ~5(genValBinary 主体删除)

### §步骤 2 — UNARY 迁移

**改 `evalExpr`**:
```ss
if (kind == "UNARY") {
    const op = nGetS1(astId);
    const arg = evalExpr(nGetI1(astId));
    if (mvKnownOf(arg)) { return mvKnown(interpUnop(op, mvValOf(arg))); }
    return mvRuntime(emitUnaryRuntime(astId, arg));
}
```

**改 `genVal` L133**:同步骤 1 pattern。

**删 `genValUnary`** 主体。

**验证**:同步骤 1;linter M1/M4/M3a 继续削减。

### §步骤 3 — TERNARY 迁移

**改 `evalExpr`**:
```ss
if (kind == "TERNARY") {
    const cond = evalExpr(nGetI1(astId));
    if (mvKnownOf(cond)) {
        // 编译期折叠:选中分支,另一分支不 emit(D094 §规则 2 pure subset)
        const picked = interpAsBool(mvValOf(cond)) ? nGetI2(astId) : nGetI3(astId);
        return evalExpr(picked);
    }
    // runtime:两分支都要 emit + phi
    const t = evalExpr(nGetI2(astId));
    const f = evalExpr(nGetI3(astId));
    return mvRuntime(emitTernaryRuntime(astId, cond, t, f));
}
```

**改 `genVal` L135 + 删 `genValTernary`**。

**验证**:覆盖 comptime-folded + runtime phi 两条路径测试(若无现成测试,补 `tests/phase5/evalexpr_ternary.ss`)。

### §步骤 4 — SHORT_CIRCUIT(BINARY And/Or)迁移

**改 `evalExpr`**(在步骤 1 BINARY 分支内):
```ss
if (kind == "BINARY") {
    const op = nGetS1(astId);
    if (op == "And" || op == "Or") {
        const lhs = evalExpr(nGetI1(astId));
        if (mvKnownOf(lhs)) {
            const lhsBool = interpAsBool(mvValOf(lhs));
            // 短路:And + false → false,Or + true → true
            if ((op == "And" && !lhsBool) || (op == "Or" && lhsBool)) {
                return mvKnown(interpNewBool(lhsBool));
            }
            return evalExpr(nGetI2(astId));
        }
        return mvRuntime(emitShortCircuitRuntime(astId, op, lhs));
    }
    // ... 步骤 1 非 And/Or 主路径
}
```

**删 `genValShortCircuit`** 独立函数;`genValBinary` 完全删除。

**验证**:短路语义专项测试(`a() || b()` b 不求值);linter M1/M4 继续削,M3b 最大入度可能下降(genValBinary/genValShortCircuit 被移除)。

### §步骤 5 — COMPTIME_EXPR 迁移

**改 `evalExpr`**:
```ss
if (kind == "COMPTIME_EXPR") {
    if (comptimeDepth > 0) { return mvError(); }  // 调用方转 comptimeError("nested comptime expression")
    inferType(astId);
    const litStr = comptimeExprLiteral.getString(`${astId}`);
    return mvKnown(interpNewString(litStr));  // 或按字面量类型走 interpNewInt/Bool/...
}
```

**改 `genVal` L212-216**:
```ss
if (kind == "COMPTIME_EXPR") {
    const mv = evalExpr(id);
    if (!mvKnownOf(mv)) { return comptimeError("nested comptime expression", id); }
    return constVal(emitConstFromVal(mvValOf(mv)));
}
```

**注意**:COMPTIME_EXPR 的字面量类型判定(当前用 `comptimeExprLiteral` Map)**保留**,不在本 Plan 范围。合并只动 dispatch 入口。

**验证**:comptime 块内嵌 comptime 测试 + 块外 comptime 表达式测试全绿。

### §步骤 6 — 收尾量化 + 清理

**目标**:所有 5 kind 已走 evalExpr 单路径,`genValBinary/genValUnary/genValTernary/genValShortCircuit` 全部删除,`genVal` L132/L133/L135/L212 成为 `evalExpr + mvKnownOf 分派` 薄包装。

**删除清单**(必须在本步骤或更早删,禁止遗留):
- `function genValBinary(id)` L697(步骤 1 + 4 覆盖后)
- `function genValUnary(id)` L759(步骤 2 覆盖后)
- `function genValTernary(id)` L804(步骤 3 覆盖后)
- `function genValShortCircuit(op, id)` L837(步骤 4 覆盖后)

**Linter 指标预期(累计 步骤 0→6,含步骤 0 新增骨架成本)**:

| 指标 | 预期 delta(累计) | 依据 |
|---|---|---|
| M1 CC | -12 ~ -18 | 4 个 genValCt* 独立函数内 if/else 分支删除 |
| M2 节点数 | -80 ~ -120 | 4 函数 body 删除(总约 100-150 行 → ~100 AST 节点净削减,抵消步骤 0 +15) |
| M3a 调用边 | -10 ~ -15 | genVal → genValBinary/Unary/Ternary/ShortCircuit 4 条调用边消失 |
| M3b 最大入度 | 0 或 -1 | genValBinary 1880 入度不变(其他函数入度最大,genVal* 函数入度低) |
| M4 dispatch 深度 | -6 ~ -10 | 4 个 genValCt* 内 `if kind == ...` 链消失 |
| M7b 函数数 | -4 ~ +2 | -4(删 4 genValCt*) +6-7(新增 evalExpr + 3 构造器 + 2 访问器 + MaybeVal class 隐式 ctor)≈ +2 ~ +3 |
| 其他 N1-N5 | 持平 | 不引入新 kind、无 Halstead 体积上升、无深嵌套、无 MEMBER_ASSIGN |

**收尾 gate**:所有指标 **≤ baseline**(M7b 净 +2~3 被 M1-M4 的削减抵消,linter 是**任一**超标阻断,故 M7b 上升允许但需其余指标大幅下降),`bin/ss run tools/reflection_health_linter.ss record` **不执行**(baseline 只在整体削减稳定后由单独 commit record)。

## Rejected Alternatives

- **A:首批选 IDENT / CALL / MEMBER_ACCESS** — IDENT 涉及 ctInvalidated + ctScopeStack + genericTypeSubs + resolveCtTypeAlias 5 条路径(L136-175),单一 kind 超 40 行状态;CALL 含 genericFuncNodes + callPreRegs + NAMED_ARG 三轨(L217-);MEMBER_ACCESS 含反射 Meta 对象 L2ζ-L2κ 累积路径。首批必须选**纯形态**,这 3 个属中批 1b / 后批 2 范围
- **B:不建独立 evalExpr 函数,直接改 genVal 返回 MaybeVal** — 破坏 genVal 现有返回 int 契约,全部调用点(100+)一次性迁移,LOC 估 300+ 且无分步 bootstrap 验证,违反 D098 §决策 2 Phase A "先跑通骨架再扩展"原则
- **C:把 SHORT_CIRCUIT 留到 Phase A 后批** — BINARY 与 SHORT_CIRCUIT 共享 `genValBinary` 调用入口(L699 派生),步骤 1 BINARY 迁移必须留 shim 到 And/Or 继续走老路,延长"双轨并存"窗口。步骤 4 紧随步骤 1 减少 shim 生命周期是更小代价
- **D:COMPTIME_EXPR 不进首批(留给"comptime 专项"轮)** — COMPTIME_EXPR 只有 4 行逻辑 + 明确"块内必 known"语义,正好示范 D094 §规则 2 "块内全部编译期"条款接入 evalExpr 的最小形态,延后无收益

## 新张力(D099 引出)

1. **`emitBinaryRuntime / emitUnaryRuntime / emitTernaryRuntime / emitShortCircuitRuntime` 新函数需建** — 步骤 1-4 每步需要一个"已知 MaybeVal 列表 → emit LLVM IR + push regTable → 返回 regId"的桥接函数。当前 `genValBinary` 主体内联做这事,抽出后是新函数。**风险**:新建函数会让 M7b +4,但合并主体删除抵消。
   **解决**:步骤 1-4 逐步建,名字与 kind 对齐不留模糊;如最后发现 4 函数 body 高度同构,步骤 6 收尾合并为 `emitRuntimeInst(kind, astId, subMvs)` 单函数(M7b 再 -3)

2. **`regTable` 尚未存在** — D098 §决策 1 引用 `regTable: Array<string>` 存 LLVM 寄存器字符串供 `mvRuntime(regId)` 索引,但 bootstrap 当前无此结构(现状 `genValBinary` 直接返回字符串)。**解决**:步骤 0 建 `let regTable: Array<string> = []` 全局 + `regTablePush(s: string): int` helper,`emitBinaryRuntime` 等 emit 后 push 拿索引。`regTable` 生命周期 per-函数(函数体结束清空),避免跨函数累积

3. **`interpBinop / interpUnop` 是否已存在** — 步骤 1-2 引用 interp* 做常量计算,若无则步骤 0 需补建(从现有 `genValBinary` 折叠分支逻辑提取)。本 Plan 假设存在,Execute 轮第一步先 grep 确认,缺则补到步骤 0

4. **COMPTIME_EXPR 字面量返回类型不是单一 "string"** — `comptimeExprLiteral` 存的是已 serialize 的字面量字符串,实际 MaybeVal 应携带原值类型(int/string/bool)而非 serialize 后的字符串。**解决**:步骤 5 细化,按 `inferType(astId)` 返回类型走对应 `interpNewInt/String/Bool`,本 Plan 骨架用 `interpNewString` 占位,Execute 轮按 infer 类型分派

5. **步骤 0 骨架的 `evalExpr` 返回 mvError() 占位是否被调用** — 骨架建立但无调用者时 `evalExpr` dead code,linter M3b(最大入度)维持 1880(不触及),但 `evalExpr` 函数入度=0 是**预期的临时状态**,步骤 1 起接入调用。若步骤 0 结束后 linter 因 evalExpr M2 上升超过累计预算,暂**不 record baseline**,继续步骤 1 合并抵消即可

## 下一步(Plan 下的 Execute 顺序)

**本 D 文档不触发任何 bootstrap 改动**。用户批准本 Plan 后,Execute 轮按以下顺序(每步一个 commit,每个 commit linter GATE PASS):

1. **Execute 0**:步骤 0 骨架(MaybeVal class + 构造器 + 访问器 + evalExpr 空壳 + regTable)
2. **Execute 1**:步骤 1 BINARY 非 And/Or 迁移
3. **Execute 2**:步骤 2 UNARY 迁移
4. **Execute 3**:步骤 3 TERNARY 迁移
5. **Execute 4**:步骤 4 SHORT_CIRCUIT(BINARY And/Or)迁移
6. **Execute 5**:步骤 5 COMPTIME_EXPR 迁移
7. **Execute 6**:步骤 6 清理 + 收尾量化 + linter record baseline(独立 commit)

每 Execute 开始前必须先填 PSM 十问(PFV 流程),完成后过 VCM 五验。单步 bootstrap 失败 → 定位根因不越步;单步 linter 任一指标 regression → 先削减再推进,不改 baseline 让 gate 过(CLAUDE.md §反射根因 gate 强制条款)。

Plan 完成后评估推进中批 1b(IDENT / MEMBER_ACCESS / INDEX_ACCESS / TEMPLATE_LIT / ARRAY_LIT — D094 §规则 2 pure subset 余项)或推后批 2(CALL / METHOD_CALL / NEW_EXPR — pure subset 外需 D094 §规则 2 "不自动折叠"条款处理)。

## 参考

- D093 §决策 §Zig 原理 / §SS 本质一样骨架 行 52-77(evalExpr 骨架直译来源)
- D094 §决策 §规则 2 两级折叠表 / §Pure subset 白名单(L92-113)
- D098 §决策 1 MaybeVal 编码 / §构造入口 / §访问器 mvKnownOf/mvValOf / §SS 语言约束(2026-04-18 probe 结论)
- `bootstrap/gen_exprs.ss` L125-216(`genVal` dispatcher + 5 kind 当前分派入口)
- `bootstrap/gen_exprs.ss` L697-870(`genValBinary` / `genValUnary` / `genValTernary` / `genValShortCircuit` 4 独立函数主体)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt`(M1-M7 + N1-N5 基线 @ commit 9e20f26)
