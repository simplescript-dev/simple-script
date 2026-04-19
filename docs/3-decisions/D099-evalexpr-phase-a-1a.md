# D099: evalExpr Phase A 首批 1a 合并 Plan — BINARY / UNARY / TERNARY / SHORT_CIRCUIT / COMPTIME_EXPR

**Status:** Executing(Execute 0-4 已落地,Execute 5-6 待推进)
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

### §步骤 0 — 建 evalExpr 骨架(D098 §决策 1 Phase A 物理编码:纯 int)

**目标**:在新文件 `bootstrap/eval_expr.ss` 中建 **evalExpr 单函数空壳**,**不**同步建 mv* 系列 helper。helpers(mvKnown/mvRuntime/mvError/mvKnownOf/mvValOf)挪到步骤 1 BINARY 合并期随首次使用时建,那时可用 genValBinary 删除抵消 M7b。

**为什么只 1 函数**:2026-04-18 实测:6 函数骨架触 M7b +5 / M1 +4 regression(无法用"不改现有调用路径"的骨架单独抵消)。linter 机械阻断任一指标 > baseline 的 commit,step 0 独立提交必须 ≤ baseline。最小骨架 = 1 函数 evalExpr 返回 `0 - 1` 哨兵,M7b +1(baseline 余量 -1 抵消净 +0),M1 +0,M2 +8 左右,N1 +0。

**编码**(D098 §决策 1 Phase A):`mv >= 0` known / `mv <= -2` runtime regId 索引(1-based) / `mv == -1` error。纯 int,无 class,无 bool 字面量,无 field access。**规避 linter N1 regression 已验证**(bootstrap 其他文件从不用裸 `true`/`false` 字面量、从不直读 class field)。

**落地(step 0 单 commit)**:
```ss
// bootstrap/eval_expr.ss
function evalExpr(astId: int): int {
    // 步骤 1-5 依次填入 BINARY / UNARY / TERNARY / SHORT_CIRCUIT / COMPTIME_EXPR
    // helpers mvKnown/mvKnownOf/mvValOf 在步骤 1 随第一次使用时建
    return 0 - 1
}
```

**main.ss import 增补(step 0 单 commit)**:
```ss
import { evalExpr } from "./eval_expr"
```

**注**:`regTable` / `constVal` / `reg` 已在 `codegen.ss:16, 143, 148` 存在,步骤 0 **不新建**,步骤 1-5 接入时从 codegen 调用即可。

**验证**:
- `./build.sh bootstrap` 固定点 PASS
- `bin/ss run tools/reflection_health_linter.ss` **GATE PASS**(M7b cur 可达 679 = baseline 679,delta=0;其他 M/N 持平或 PROGRESS)

**Linter 指标预期(步骤 0 单步)**:M7b +1(抵消 baseline 余量 -1 净 0)/ M2 +~8 / M1 / M4 / N1 持平。**所有指标 ≤ baseline**。

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

**Execute 1 落地实录(2026-04-18)**:
- `bootstrap/eval_expr.ss`:evalExpr 吸收 BINARY(非 And/Or)主体,复用 codegen `ctVal/constVal/reg/isCt/payload/interpIntOp/interpDoubleOp/interpNewString/interpNewBool` + gen_exprs `genVal/inferType/comptimeError/genBinary/genIntBinary/genValStringCompare`。**不建 Phase A helpers**(mvKnown/mvKnownOf/mvValOf 恒等/1-ternary 抽象,Phase A 纯 int 编码下无语义增益,按 §踩过的坑 G 延迟到 Phase B MaybeVal 类化期)。字符串比较 comptime 路径直接委托 `genValStringCompare`(其内部已折叠 ct-both,省 6 分支 ~100 N3 AST 节点)。**operand 评估仍走 genVal 而非递归 evalExpr** — 步骤 1 evalExpr 仅识别 BINARY,递归 evalExpr 对 IDENT/LIT 等会返回 -1 错误,recursive evalExpr pattern 推迟到批 1b IDENT/LIT 着陆后
- `bootstrap/gen_exprs.ss` L697:`genValBinary` 主体从 57 行骨架缩为 5 行 shim — `op==And/Or → genValShortCircuit` / 否则 `evalExpr` 解 mv(`mv>=0? mv : 0-mv-1`)。L132 分派不动(`return genValBinary(id)`),inline 解码会使 AST 深度叠进 `genVal` if chain 造成 N3 反弹
- `bootstrap/main.ss` L17:`import { evalExpr } from "./eval_expr"` 不变(无 helper 新增)
- Linter GATE PASS:M1=5130(baseline 5144,Δ-14)/ M2=76105(Δ-139)/ M3a=12135(Δ-21)/ M4=3041(Δ-10)/ M5=1750(Δ-8)/ M7b=679(=baseline)/ N2=380525(Δ-695)/ N3=517590(Δ-889);其余指标持平。所有方向削减,合 D097 §L102 单调 gate
- Bootstrap 固定点 PASS:stage2 == stage3
- 测试:phase2/3/4 100%(53/53),phase5 tracked 全绿(未追踪 spring_web_params / d096_reactive / harness_bug 失败为 step 1 前的 pre-existing,与 BINARY 迁移无关)
- **§步骤 1 与 Plan 的 3 处偏差**(Execute 1 实录):① mv helpers 不建(§踩过的坑 G)② operand 评估保留 genVal(§踩过的坑 H)③ 字符串比较 comptime 复用 genValStringCompare(§踩过的坑 I)。均为 Phase A 阶段合理收敛,不污染 Phase B 类化路径

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

**Execute 2 落地实录(2026-04-19)**:
- `bootstrap/eval_expr.ss`:evalExpr 顶部加 `if (nGetKind(astId) == "UNARY") { ... }` 吸收 UNARY 主体(comptime + 运行时两路径)。**方案选型** — 按坑 I 延伸候选过两选:X1 `evalUnary` 独立函数(M7b +1 撞 baseline=679 余量 0 阻断)vs X4 inline 到 evalExpr body(N3 +~80 余量 889 充裕)。选 X4。**承坑 G/H/J**:不建 mv helpers,operand 走 `genVal(nGetI1(astId))` 不递归 evalExpr,非 int/bool fallback 委托现有 `genUnary`。runtime 返回编码 `0 - constVal(uR) - 1`(mv runtime 编码)
- `bootstrap/gen_exprs.ss` L704:`genValUnary` 主体 44 行 → 3 行 shim(`const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1`)。L133 分派不动
- Linter GATE PASS:M1=5132(baseline 5144,Δ-12)/ M2=76138(Δ-106)/ M3a=12136(Δ-20)/ M4=3042(Δ-9)/ M5=1750(Δ-8)/ M7b=679(=baseline)/ N2=380690(Δ-530)/ N3=518249(Δ-230);其余指标持平。**相对 step 1**:M1 +2(外层 `if kind==UNARY` +1 + shim 三元 +1)/ M2 +33 / M3a +1 / M4 +1 / N3 +659(UNARY body 进 if 块 depth +1 ~659 节点深度累加)— 全部仍在 baseline 内
- Bootstrap 固定点 PASS:stage2 == stage3
- 测试:214 passed / 3 failed(spring_web_params / d096_p4_l2_reactive / harness_bug,均为 step 1 前 pre-existing,与 UNARY 迁移无关)
- **§步骤 2 与 Plan 的偏差**(Execute 2 实录):① mv helpers 不建(坑 G 延续)② operand 仍走 `genVal` 而非递归 evalExpr(坑 H 延续,evalExpr 当前仅识别 BINARY+UNARY)③ 方案从 X1 per-kind 函数 → X4 inline(§坑 K)。均为 Phase A 收敛策略,不污染 Phase B 类化路径

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

**Execute 3 落地实录(2026-04-19)**:
- `bootstrap/eval_expr.ss`:evalExpr 顶部 UNARY 之后加 1 行分派 `if (nGetKind(astId) == "TERNARY") { return evalTernary(astId) }`;文件末尾新增 `evalTernary(astId: int): int` 独立函数 27 行承载 TERNARY 全部 body(comptime-folded + comptime-block-null + runtime phi),mv 编码返回(runtime 路径 `0 - constVal(r) - 1`);comptime-folded 用 ternary compression `genVal(interpTruthy(...) == 1 ? nGetI2(astId) : nGetI3(astId))` 压缩原 if-else 两分支
- `bootstrap/gen_exprs.ss` L135:`return genValTernary(id)` → `const mvT = evalExpr(id); return mvT >= 0 ? mvT : 0 - mvT - 1` inline 分派(genValTernary 已删,shim 路径不可行,直接 inline mv decode)
- `bootstrap/gen_exprs.ss` L709-L740:`genValTernary` 整体删除(步骤 6 L225 清理项前置到步骤 3,触坑 L 的「同步删+新建」)
- Linter GATE PASS:M1=5135(Δ-9)/ M2=76169(Δ-75)/ M3a=12138(Δ-18)/ M3b=1880(=)/ M4=3042(Δ-9)/ M5=1750(Δ-8)/ M6=32(=)/ M7a=27(=)/ M7b=679(=baseline)/ N1=34(=)/ N2=380845(Δ-375)/ N3=518477(Δ-2)/ N4=321(=)/ N5=0(=);所有指标 ≤ baseline
- Bootstrap 固定点 PASS:stage2 == stage3;测试 214 passed / 3 failed(spring_web_params / d096_p4_l2_reactive / harness_bug 均 pre-existing,与 TERNARY 无关)
- **§步骤 3 与 Plan 的偏差**(Execute 3 实录):① mv helpers 不建(坑 G 延续)② operand 走 genVal 非递归 evalExpr(坑 H 延续)③ 方案从「inline + 3 行 shim」→「删 genValTernary + 新建 evalTernary + genVal L135 inline mv decode」(§坑 L)④ 步骤 6 L225 `genValTernary` 清理项前置到步骤 3

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

**Execute 4 落地实录(2026-04-19)**:
- `bootstrap/eval_expr.ss`:evalExpr L52 `const op = nGetS1(astId)` 后新增 1 行分派 `if (op == "And" || op == "Or") { return evalShortCircuit(op, astId) }`(在 comptimeDepth 检查之前,避免 And/Or 走通用 comptime 双 operand 折叠路径);文件末尾新增 `evalShortCircuit(op, astId): int` 独立函数 28 行承载完整 SHORT_CIRCUIT body(comptime lhs-known short-cut + comptime runtime-lhs null + runtime alloca/store/load phi)。mv 编码:comptime 短路命中 `ctVal(interpNewBool(0))` / `lv`;comptime rhs fallthrough 统一编码 `isCt(rv) == 1 ? rv : 0 - rv - 1`;runtime `0 - constVal(scRes) - 1`。runtime branch direction 从原 `if (op == "And") emitIR(...) else emitIR(...)` 5 行压缩为 2 行 ternary + 1 emitIR(§坑 M.1 Linter 削减专用)
- `bootstrap/gen_exprs.ss` L697-702:`genValBinary` 从 5 行 shim 瘦身为 3 行(删除 `op == "And" \|\| "Or"` 分派 fork);L709-743 `genValShortCircuit` 35 行整体删除;L133 `if (kind == "UNARY") { return genValUnary(id) }` 合并到 L132 `if (kind == "BINARY" \|\| kind == "UNARY") { return genValBinary(id) }`(§坑 M.2:genValUnary 前置步骤 6 清理,shim body 与 genValBinary 完全同构可合并);`function genValUnary` 3 行 shim 整体删除
- 方案选型(§坑 L 延伸):M7b=679=baseline 余量 0 + N3=518479 实测余量 2,极紧。genValShortCircuit runtime body 17 行(alloca + 2 label + template literal 密集)与 TERNARY 22 行密度类似,第一次尝试 inline 到 evalExpr `if op==And\|\|Or` 分支会触 N3 regression。实测:inline 方案 N3 +216 BLOCKED;改"删 genValShortCircuit + 新建 evalShortCircuit 独立函数"(与 evalTernary 对称 body depth 1)N3 +82 仍 BLOCKED;再合并 branch ternary N3 +8 BLOCKED;最后前置 genValUnary 清理(M7b -1 余量释放 + N3 -约 20)N3 -82 **PASS**
- Linter GATE PASS:M1=5136(baseline 5144,Δ-8)/ M2=76157(Δ-87)/ M3a=12133(Δ-23)/ M3b=1879(Δ-1)/ M4=3039(Δ-12)/ M5=1750(Δ-8)/ M7b=**678**(Δ-1,baseline 余量释放 1)/ N1=34(=)/ N2=380785(Δ-435)/ N3=**518397**(Δ-82)/ N4=321(=)/ N5=0(=);所有指标 PROGRESS(M3b 首次低于 baseline,genValShortCircuit 入度消失)
- Bootstrap 固定点 PASS:stage2 == stage3;测试 213 passed / 4 failed(spring_web_params / d096_p4_l2_reactive / harness_bug / harness_task 均 pre-existing,git stash 回退到 commit f54fd9f 验证 harness_task 已失败,与 SHORT_CIRCUIT 迁移无关)
- **§步骤 4 与 Plan 的偏差**(Execute 4 实录):① mv helpers 不建(坑 G 延续)② operand 走 genVal 非递归 evalExpr(坑 H 延续)③ 方案从 "inline 到 evalExpr BINARY 分支" → "删 genValShortCircuit + 新建 evalShortCircuit 独立函数"(§坑 L 延伸到 SHORT_CIRCUIT,runtime phi 密度确如步骤 3 预告)④ 步骤 6 `genValUnary` 清理前置到步骤 4(§坑 M:linter GATE 约束下的合理前置,与步骤 3 前置 `genValTernary` 清理同构)⑤ comptime And 短路 `return ctVal(interpNewBool(0))` 语义沿用原 genValShortCircuit(与 runtime `store i32 leftStr` 返回原 lhs 值存在语义分歧,本轮**不修**,属 D099 范围外 bug;需要独立 D 文档追踪)

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
- `function genValBinary(id)` L697 — **未删**,保留为 3 行 mv decode shim(坑 I:inline 到 genVal L132 会炸 N3 +192),步骤 6 收尾评估能否 rename 或删
- ~~`function genValUnary(id)` L759~~ — 已删于步骤 4(Execute 4 落地,触坑 M「前置步骤 6 清理以释放 M7b 余量」,genVal L133 合并到 L132 `BINARY \|\| UNARY` 分派)
- ~~`function genValTernary(id)` L804~~ — 已删于步骤 3(Execute 3 落地,触坑 L「同步删+新建」)
- ~~`function genValShortCircuit(op, id)` L837~~ — 已删于步骤 4(Execute 4 落地,evalShortCircuit 独立函数承接)

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

## 踩过的坑(Execute 实录)

### 坑 G:Phase A helpers mvKnown/mvKnownOf/mvValOf 建了会回滚

**现象(Execute 1 第一次尝试)**:按 Plan §步骤 1 原文建 3 helpers + evalExpr 外层 `if (kind == "BINARY")` dispatch,触 linter M1+4 / M2+3 / M3a+9 / M7b+2 / N2+15 / N3+1379 六指标 regression,GATE BLOCKED。

**根因**:Phase A 编码为纯 int(mv>=0 known / mv<=-2 runtime / mv==-1 error),3 helpers 物理形态:
- `mvKnown(v: int): int { return v }` — 恒等,CC 1
- `mvKnownOf(mv: int): int { return mv >= 0 ? 1 : 0 }` — 单 TERNARY,CC 2
- `mvValOf(mv: int): int { return mv }` — 恒等,CC 1

3 helpers 总 CC 4 + M7b +3 + M2 +~30(body 节点)+ M3a +~13(调用点 wrap 边)。Phase A 是纯 int 编码,helpers 无语义增益(只是 Phase B 类化时的接口形状占位)。

**解决**:Phase A 不建 helpers,mv 编解码直接 inline(`mv >= 0` / `mv` / `0 - mv - 1`)。Phase B MaybeVal 类化时再建真接口(helpers 此时携带 class field 访问语义)。

### 坑 H:recursive evalExpr 对非 BINARY 操作数会返回 -1

**现象**:Plan §步骤 1 原文写 `const lhs = evalExpr(nGetI1(astId))` 递归评估,但 evalExpr 步骤 1 仅识别 BINARY,其他 kind(IDENT / INT_LIT / MEMBER_ACCESS)全部走 fallthrough `return 0 - 1`(error 哨兵),破坏语义。

**根因**:Plan 假设 evalExpr 已完整 dispatch 所有 kind。实际 step 1 只吸收 BINARY 一个 kind,operand 评估必须走现有 genVal 分派(覆盖所有 kind 的旧路径)。

**解决**:step 1 evalExpr BINARY 分支内**保留 genVal(nGetI1/I2(astId))** 作 operand 评估;recursive evalExpr pattern 推迟到批 1b(IDENT/LIT/MEMBER_ACCESS 等 pure subset 余项)着陆后,那时 evalExpr dispatch 表才足以承接递归调用。

### 坑 I:外层 `if (kind == "BINARY")` dispatch 引发 N3 +1379 AST 深度反弹

**现象**:Plan §步骤 1 代码形态 `function evalExpr(astId) { ... if (kind == "BINARY") { body ... } return -1 }` 把 genValBinary body 整体下沉到 IF 块内,所有 ~1400 AST 节点深度 +1,累计 N3 +1379。

**根因**:N3 = 全部 AST 节点深度累加。`if (kind == "BINARY") { ... }` 外层包裹使内部每个节点 depth+1,节点数 × 1 = N3 delta。

**解决**:改扁平 guard pattern `if (nGetKind(astId) != "BINARY") { return 0 - 1 }` 提前返回,body 留在函数体 depth 1 与 genValBinary 同层;step 2+ 若扩 kind dispatch,改为 `if (kind == X) return evalX(astId)` per-kind 分发函数,保持 body 不进 IF 深度。但实际 Execute 1 进一步删去 guard(caller shim 已过滤 BINARY 且 filter And/Or),M1 再 -1。

**延伸**:gen_exprs.ss L132 原计划展开 5 行 inline mv 解码会把代码叠进 `genVal` if chain(depth ~5),观测 N3 +192。**解决**:保留 `genValBinary` 为 5 行 shim(`op 检查 And/Or → genValShortCircuit` / 否则 `evalExpr + mv decode`),shim body 在函数体 depth 1 比 inline depth 5 节省 ~200 N3。shim 是"便宜的函数包装"不违 §决策 2 Phase A(class 留 Phase B)。

### 坑 K:step 2 UNARY 分派 per-kind 函数 vs inline 二选

**现象(Execute 2 方案选型)**:D099 原文坑 I 延伸建议 "step 2+ 若扩 kind dispatch,改为 `if (kind == X) return evalX(astId)` per-kind 分发函数,保持 body 不进 IF 深度"(X1)。但 X1 必须新建 `evalUnary` 独立函数,M7b +1。step 1 结束时 M7b=679 = baseline,余量 0 → X1 立即 GATE BLOCKED。

**根因**:linter GATE 是单调(任一指标 > baseline 阻断),不看综合削减。M7b 余量 0 时任何新函数都触 blocked,除非同步删除等量函数(shim 保留策略下无法删)。N3 余量 889 则宽松。

**解决**:改方案 X4 — UNARY body 直接 inline 到 evalExpr 函数体 `if (kind == "UNARY") { ... }` 内。代价 N3 +~80(body 裹进 if 深度 +1),在 N3 余量内。trade-off 选型依据:**看 baseline 余量最紧的指标**(M7b)决定,不看"理论最扁平"。step 3+(TERNARY/SHORT_CIRCUIT/COMPTIME_EXPR)继续 inline 直到 step 6 收尾统一清理。

**延伸**:当 body 很大(genVal 主体 ~200 行)或嵌套很深(depth > 3)时,inline 会炸 N3。届时需要"同步删 + 新建"双操作维持 M7b。step 2 UNARY body 仅 40 行深度 ≤3,inline 可行。step 3 TERNARY runtime phi 行数小但 AST 密度高,触发坑 L「同步删+新建」实操。

### 坑 L:TERNARY runtime phi AST 密度高,inline 到 `if kind==TERNARY` 块 depth 2 炸 N3

**现象(Execute 3 两次尝试)**:① 按 Plan §步骤 3 原文把 genValTernary 全部 body(29 行 runtime phi + comptime-folded)inline 到 evalExpr `if kind==TERNARY` 块,N3=518965 / baseline 518479,Δ+486 REGRESSION,GATE BLOCKED。② partial inline(只 comptime-folded 进 evalExpr ~11 行,runtime phi 留在 genValTernary 混合 shim),N3=518710 Δ+231 仍 REGRESSION。

**根因**:TERNARY runtime phi 22 行里含 alloca + store/store/load + 3 个 label br + 多个 template literal,每个 `${var}` 产生 multiple AST 节点。整块 inline 到 depth 2 后所有节点 depth +1 累加 N3 +486。相比 UNARY 40 行 body inline +659(Execute 2 实测)显得"每行更费 N3",因 UNARY 无 template literal 密集区。坑 K 末段已经预告该情况:"当 body 很大或嵌套很深时,inline 会炸 N3。届时需要'同步删+新建'双操作维持 M7b。"TERNARY runtime phi 是首次触发该条件的 kind。

**解决**:方案 AO——
- 删除 `genValTernary`(M7b -1)
- 新建 `evalTernary(astId: int): int` 独立函数(M7b +1,净 0)承载完整 TERNARY body(comptime-folded + comptime-block-null + runtime phi),depth 1 不受 `if kind` 块包裹
- evalExpr 里 TERNARY 分派只 1 行 `if (nGetKind(astId) == "TERNARY") { return evalTernary(astId) }`
- gen_exprs.ss L135 分派改 inline mv decode(`const mvT = evalExpr(id); return mvT >= 0 ? mvT : 0 - mvT - 1`),不再走 shim(genValTernary 删除后 shim 路径不可行)

Linter 结果:N3 cur=518477 / baseline 518479,Δ-2 PROGRESS;M7b 净 0 持平;其他指标全 PROGRESS。方案 AO 等价于 **步骤 3 + 部分步骤 6 清理**(步骤 6 L225 本来就要删 genValTernary),提前到步骤 3 只是 linter 约束下的合理前置,不影响 D099 整体 pipeline 收敛。

**延伸**:步骤 4 SHORT_CIRCUIT 如果 runtime phi 模式类似(label + br 密集),可能复刻方案 AO(删 genValShortCircuit + 新建 evalShortCircuit)。步骤 5 COMPTIME_EXPR body 短(< 5 行)应可直接 inline,无需重复。

### 坑 M:step 4 SHORT_CIRCUIT comptime 分支 mv 编码成本 + genValUnary 前置清理

**现象(Execute 4 三次尝试)**:① inline genValShortCircuit body 到 evalExpr `if op==And\|\|Or` 分支,N3 +216 REGRESSION GATE BLOCKED;② 改"删 genValShortCircuit + 新建 evalShortCircuit 独立函数"(与 evalTernary 对称 body depth 1),加两处 `const rv = genVal(nGetI2(astId)); return isCt(rv) == 1 ? rv : 0 - rv - 1` comptime rhs mv 编码,N3 +82 REGRESSION;③ 合并两处编码为一处(短路条件提前 return,fallthrough 统一 encode),再把 runtime `if (op == "And") emitIR(...) else emitIR(...)` 5 行压缩为 `scT/scF ternary + 1 emitIR` 2 行,N3 +8 REGRESSION。

**根因 1**:mv 编码成本。原 `genValShortCircuit` comptime rhs fallthrough 直接 `return genVal(nGetI2(id))`(1 节点 call),新 evalShortCircuit 必须返回 mv 编码 → `const rv = genVal(...); return isCt(rv) == 1 ? rv : 0 - rv - 1`(ternary + eq + bin sub + un neg ~15 节点 × depth 2-3)。这是 mv 编码强加的 N3 成本,且难以完全抵消。

**根因 2**:linter GATE 单调阻断。N3 +8 仍然 BLOCKED,即使 M1/M2/M3a/M4 等全 PROGRESS。必须找出 ≥8 N3 的削减源。

**解决**:前置步骤 6 `genValUnary` 清理 — `genValBinary` 和 `genValUnary` body 完全同构(3 行 mv decode shim),`genVal` L132/L133 两行分派可以合并为 `if (kind == "BINARY" \|\| kind == "UNARY") { return genValBinary(id) }`。删 `genValUnary` 函数(M7b -1) + 合并 dispatch 一行(M2 -数个 + N3 -约 20)。净效果 N3 -82 PASS(其中 genValUnary body 删除贡献 ~20,dispatch 合并 ~5,总和本轮 changed 文件 comparable)。

**延伸**:`genValBinary` shim 保留(坑 I:inline 到 genVal L132 炸 N3),步骤 6 收尾评估能否 rename 为通用 `genValMvDecode` 并让 TERNARY 分派也走同一 shim(L135 当前 inline mv decode 可共享)。

**evalShortCircuit vs evalTernary 对称模式确立**:两者皆为"删 genVal* 独立函数 + 新建 eval* 独立函数 + dispatch 单行 + body depth 1"pattern。后续步骤 5 COMPTIME_EXPR body 短(< 5 行)可 inline,不触发此模式;若将来吸收 pure subset 余项(IDENT/MEMBER_ACCESS 等 body > 10 行 + runtime IR 密集的 kind),对称 pattern 是首选。

**延伸 — evalShortCircuit runtime 块 vs genShortCircuit 跨路径重复(步骤 6 待清理)**:`bootstrap/eval_expr.ss` `evalShortCircuit` L144-163 的 runtime 路径 IR 发射块与 `bootstrap/gen_exprs.ss` `genShortCircuit` L1521-1539 约 15 行完全同构(alloca + store + icmp + br + store + br + load 模板)。**本轮不合并**的原因:`genShortCircuit` 签名为 `(op, leftId, rightId)` 在 L1524 `genExpr(leftId)` 会 emit lhs IR;`evalShortCircuit` runtime 路径进入时 lhs 已由 `genVal(nGetI1)` emit → 委托 `genShortCircuit(op, nGetI1, nGetI2)` 会造成 **lhs double-emit bug**。步骤 6 收尾评估 `genShortCircuit` 签名改造(`leftId` → `leftStr` 或 overload)消除此重复,属跨路径重构,不适合在 §步骤 4 原子任务内做。

### 坑 J:comptime 字符串比较 6 分支 inline 造成 N3 累积

**现象**:evalExpr 吸收 genValBinary 的 comptime string-compare 块(6 个 op 分支,每个 ctVal(interpNewBool(...))),即使扁平 guard 后 N3 仍 +27 residue。

**解决**:委托现有 `genValStringCompare(op, astId)` — 其内部 `genVal(lhs/rhs)` + ct-both 折叠 + runtime IR 发射三路径已完备,直接 delegate 省 6 分支 ~100 N3。委托是**无语义变化的代码复用**,不新建 function(genValStringCompare 原已存在,M7b 不动)。副作用:comptime ct-both 路径重复 genVal 评估(ctBlp/ctBrp payload 不复用),但 genVal 在 comptime 是纯函数,性能损耗可忽略,Phase B InternPool 会消除重复。

## 下一步(Plan 下的 Execute 顺序)

**本 D 文档不触发任何 bootstrap 改动**。用户批准本 Plan 后,Execute 轮按以下顺序(每步一个 commit,每个 commit linter GATE PASS):

1. ~~**Execute 0**:步骤 0 骨架~~ — 落地于 commit 53066f0(evalExpr 空壳 `return 0 - 1`,Phase A 纯 int 编码,MaybeVal class 延后 Phase B)
2. ~~**Execute 1**:步骤 1 BINARY 非 And/Or 迁移~~ — 落地于 commit 5f2198e(§步骤 1 Execute 1 落地实录 + §坑 G/H/I/J)
3. ~~**Execute 2**:步骤 2 UNARY 迁移~~ — 落地于 commit ae7a0c2(§步骤 2 Execute 2 落地实录 + §坑 K)
4. ~~**Execute 3**:步骤 3 TERNARY 迁移~~ — 落地于 commit f54fd9f(§步骤 3 Execute 3 落地实录 + §坑 L;步骤 6 `genValTernary` 清理前置到本步)
5. ~~**Execute 4**:步骤 4 SHORT_CIRCUIT(BINARY And/Or)迁移~~ — 落地(§步骤 4 Execute 4 落地实录 + §坑 M;步骤 6 `genValUnary` 清理前置到本步)
6. **Execute 5**:步骤 5 COMPTIME_EXPR 迁移(下一步)
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
