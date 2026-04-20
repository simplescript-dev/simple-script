# D110: Phase A 全局收尾 + Phase B MaybeVal 类化起步(evalExpr 阶段过渡)

**Status:** Proposed(D109 Execute 2 起草,2026-04-20)
**Depends on:** D109 Execute 2 §步骤 2 §决策矩阵漏洞修订(累计组永不 record 的机械约束) / D094 §Q2 收尾 §Phase A 迁移进度(9 kind 全 `[x] Done at e141fdf`) / D098 §决策 1-3(MaybeVal 编码 / InternPool / Type-as-Value Phase A → Phase B 过渡) / D097 L70-71 累积方向严禁 record / D102 §规则 1.1-1.4 分层 GATE + §规则 2.1-2.3 F1 GATE / D101-D109 八轮 §步骤 1 evalExpr 子函数迁移实测 / D088 §第一性需求(Zig SEMA 一份 evalExpr)/ §正模式(一份 evalExpr 函数) / D093 §决策 §Zig 原理(MaybeVal `?Value` 单语义)/ §SS 本质一样骨架 / CLAUDE.md §反射根因 gate / `memory/feedback_ultrathink_gate.md` / `memory/feedback_design_no_code_authority.md` / `memory/feedback_no_dramatic_reset.md`

**Date:** 2026-04-20

---

## 第一性需求

D109 Execute 1 commit `e141fdf` 已合并 NEW_EXPR,D094 L175 zig 驱动 9 kind 全部 `[x] Done`,Phase A 闭环。`bootstrap/eval_expr.ss` 128 行(10 子 import + evalExpr 主 dispatch + UNARY/BINARY inline)+ `bootstrap/eval/*.ss` 11 子文件(call/ternary/short_circuit/index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call/new_expr,最大 member_access=126 行)= 12 函数稳态。

**D109 Execute 2 机械阻断实测**(2026-04-20,commit cur):`bin/ss run tools/reflection_health_linter.ss record` 输出:

```
record 拒绝: M1 5134 → 5138 累积方向
record 拒绝: M2 76126 → 76210 累积方向
record 拒绝: M3a 12122 → 12124 累积方向
record 拒绝: N2 380630 → 381050 累积方向
D097 L102 + D102 §规则 2.1 R4: 累积方向 / F1 行数升严禁更新 baseline。
```

D109 §步骤 2 §决策矩阵 L283-289 写的「Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ 0,N3 bank < -2900 → record baseline」与 D097 L70-71 / D102 §规则 1.4 L101-103 机械冲突 — Phase A 子目录拆出 11 新文件 = 物理上 AST 节点数 / 函数数 / 调用边数 / Halstead 项必然累计升,**累计组(M1/M2/M3a/M5/N2)永远不可能全 PROGRESS**,record 永不可达。

本 Plan 三重职责:

1. **Phase A 全局收尾决策** — 12 函数稳态 vs vtable 融合压回单 evalExpr。D100-D109 §新张力 5/7 连续八次警示「Phase B 类化期拍板」,本 Plan 范围拍板
2. **Phase B MaybeVal 类化起步** — D098 §决策 1-3 Phase A → Phase B 过渡,引入 `valOf` / `valType` 访问器作为接口边界(Phase B 启动前必做,免 Phase B 大改散点)
3. **银行策略升级 + D109 §决策矩阵漏洞修订** — 累计组 baseline 永不 record 的语义澄清(对照 D097 L70-71 / D102 §规则 1.4)+ 结构组 baseline 保留 D101 Execute 0 commit `9343330` 作为 Phase A 全程对照基 + Phase B 启动时 per-phase bank 独立累积

## 当前事实(2026-04-20 snapshot,commit cur)

| 项 | 值 / 位置 |
|---|---|
| evalExpr 主 dispatch | `bootstrap/eval_expr.ss:20-128`,128 行(10 import + evalExpr body)|
| inline kind | **UNARY**(L22-62,41 行)/ **COMPTIME_EXPR**(L64-68,4 行)/ **BINARY**(L80-127,47 行)|
| 分派子函数 | TERNARY/INDEX_ACCESS/TEMPLATE_LIT/ARRAY_LIT/IDENT/MEMBER_ACCESS/POSTFIX_INC/METHOD_CALL/CALL/NEW_EXPR + SHORT_CIRCUIT(BINARY op "And"/"Or")= 11 子函数 |
| eval/*.ss | 11 文件 20-126 行,总 736 行(含 eval_expr.ss 主)|
| linter 结构组 cur vs D101 baseline | M3b=1879=0 / M4=3035 -2 / M5=1747 -3 / M6=32=0 / M7a=27=0 / **M7b=674 -2** / N1=34=0 / **N3=514989 -3122** / N4=321=0 / N5=0=0 |
| linter 累计组 cur vs D101 baseline | M1=5138 +4 DRIFT / **M2=76210 +84 DRIFT** / M3a=12124 +2 DRIFT / M5=1747 -3 PROGRESS / **N2=381050 +420 DRIFT** |
| F1 文件行数(≤ 600 graduate 不入 baseline)| gen_exprs.ss 1218(D101=1721 Δ=-503)/ eval_expr.ss 128(D101=569 已 graduate)/ eval/*.ss 11 新文件全 ≤ 126 R3 trivial PASS |
| D098 §决策 1 MaybeVal Phase A mv 编码 | 已在 `bootstrap/eval_expr.ss:1-4` 契约固化,11 子函数全部遵守(grep `0 - constVal(.*) - 1` eval/ 累计 21 处)|
| D098 §决策 2 InternPool | **未启动**(Phase A 沿用 `ctVal(id) = id \| 1073741824` tagged int)|
| D098 §决策 3 Type-as-Value | **未启动**(`comptimeTypeAliases` 独立通道仍存 `bootstrap/codegen.ss:83`)|
| D098 valOf / valType 访问器 | **未引入**,`interp*` 家族直读 tagged int payload(bootstrap/codegen.ss L277-500 约 30 函数)|

**Phase A 收敛成果**(baseline = D101 Execute 0 commit `9343330`,cur = D109 Execute 1 commit `e141fdf`):

- 结构组 8 项全 OK/PROGRESS(M7b -2 / N3 -3122 深窖 / 其余 OK)
- 累计组 6 项全 DRIFT 窗内(M1/M2/M3a/N2 正方向漂移 / M5 PROGRESS)
- F1:gen_exprs.ss -503 单文件压缩 29.2% / eval_expr.ss 569→128 graduate 出 R1 / 11 eval/* 新文件全 R3 OK

## 决策(分 3 部分,每部分独立可推进)

### §决策 1 — Phase A 全局收尾:保留 12 函数稳态,不压回单 evalExpr

**决策**:保留当前 12 函数分层结构(evalExpr 主 + 11 eval/*.ss 子 + UNARY/BINARY/COMPTIME_EXPR inline)。**不**压回单 evalExpr,**不**追加 UNARY/BINARY/COMPTIME_EXPR 迁移子目录。

**依据**:

1. **Zig sema.zig 参照**:Zig Sema 主 `analyze*` 函数 6000+ 行单函数,内部调 `analyzeCall` / `analyzeBinary` / `analyzeAs` 等分派子函数 — **单函数分派不是 Zig 的唯一形态,Zig 本身就是「主 dispatch + 子分析器」分层**。SS 12 函数平均 ≤ 80 行远比 Zig 单函数可读
2. **F1 限制驱动**:D102 §规则 2.1 R3 新文件 ≤ 600 + R1 单调下降 → 压回单 evalExpr 即 eval_expr.ss 128 + ~600(11 子函数总 ~608 行)= 736 行 > 600 立即 R3 阻断。物理不可行
3. **D088 §正模式 不要求字面单函数**:原文「一份 evalExpr 函数」指**入口统一**(同一 `evalExpr(astId)` 调用返回 `MaybeVal`),不指「物理上所有 kind 逻辑挤一个函数 body」。Zig 对齐的语义在入口 + 返回值 + 分派统一,不在物理单函数
4. **D093 §SS 本质一样骨架** L73-76:「块内任何 `evalExpr` 返回 known=false 即 error」要求的是**语义统一**(同一求值骨架),SS 当前 evalExpr 主 dispatch + 11 子函数在**每 kind 分支返回 MaybeVal 统一接口**,与 Zig 骨架同构
5. **UNARY/BINARY inline 不迁合理**:41 + 47 行 inline 即 main 函数 body 的核心,迁出后 evalExpr 主 dispatch 退化为 11-13 行 pure switch 反而失去 inline 处理 int/bool/double/string 四路径的紧凑性。**P13 三似性原则**:UNARY 三 op 分支(Neg/Not/BitNot)+ BINARY 多 op 分支(NullCoalesce/Instanceof/As/Pow/普通)各自独立逻辑不符合抽取条件
6. **COMPTIME_EXPR 4 行 inline 不迁**:与 D109 §Rejected C「ARROW_FUNC 4 行不迁」对称延续

**Phase A 闭环标识**:`docs/3-decisions/D094-comptime-purity-and-operand-driven.md §Q2 收尾 §genVal 操作数驱动审计 §Phase A 迁移进度` 9 kind 全 `[x] Done` 表已写入(D109 Execute 2 同步回写)。D110 §决策 1 落地后 Phase A 工程闭环。

**不涉及代码改动**(本决策是评估 + 宣告,不产生 commit)。

### §决策 2 — Phase B MaybeVal 类化起步:引入 `valOf` / `valType` 访问器作为接口边界

**目标**:为 Phase B InternPool 引入做准备(D098 §决策 2 §Phase B + §新张力 2「Phase A 就应引入访问器作为接口边界,免 Phase B 大改」)。**Phase A 不做 InternPool**(D098 §决策 2 已明定),仅引入访问器屏蔽 tagged int vs pool index 的内部差异。

**引入形态**:

```ss
// bootstrap/gen_maybeval.ss(或 bootstrap/codegen.ss 段)新增:
function valOf(valId: int): int {
    // Phase A: payload(valId) 直接解码 ctVal tagged int
    // Phase B: pool.load(valId).payload 走 InternPool
    return payload(valId)
}

function valType(valId: int): string {
    // Phase A: interpType(valId) 走 bit 30 + interp*
    // Phase B: pool.load(valId).tag 走 InternPool
    return interpType(valId)
}
```

**改造范围**(Phase A 末期 Execute 1 落地):

- `bootstrap/codegen.ss` L277-500 约 30 `interp*` 函数**调用侧**:凡 `payload(mv)` / `interpType(id)` 改调 `valOf(mv)` / `valType(id)` 进入访问器边界
- **不动** `interp*` 函数内部实现(继续沿用 tagged int 解码)
- **不动** `ctVal(id)` 构造(Phase B 改 `internPoolGetOrInsert`)

**预估指标影响**(相对当前 cur 即 D109 Execute 1 末):

| 指标 | 组 | cur | 预估 | Δ | 判定 |
|---|---|---|---|---|---|
| M1 | 累计 | 5138 | 5140~5145 | +2~+7 | OK(DRIFT 窗远内)|
| M2 | 累计 | 76210 | 76230~76280 | +20~+70 | OK(±380 充裕)|
| M3a | 累计 | 12124 | 12150~12180 | +26~+56 | OK(±60 压临界,视访问器调用次数)|
| M3b | 结构 | 1879 | 1879 | 0 | OK |
| M4 | 结构 | 3035 | 3035~3037 | 0~+2 | **DRIFT 风险**(严格 0 不升,访问器若进入 dispatch 路径可能 +1)|
| M5 | 累计 | 1747 | 1747 | 0 | OK |
| M6 | 结构 | 32 | 32 | 0 | OK |
| M7a | 结构 | 27 | 27 | 0 | OK |
| M7b | 结构 | 674 | 676 | +2 | **DRIFT 风险**(严格 0 不升,引入 2 新函数 valOf/valType)|
| N1 | 累计 | 34 | 34 | 0 | OK |
| N2 | 累计 | 381050 | 381100~381200 | +50~+150 | OK(±1903 充裕)|
| N3 | 结构 | 514989 | 515000~515050 | +11~+61 | **DRIFT 风险**(严格 0 不升,访问器调用边深度可能微升)|
| F1 | - | 不变 | 不变 | 0 | OK |

**核心风险点**:M7b / M4 / N3 三结构组 STRICT 指标。M7b 必 +2(新函数),M4 视访问器是否进入 dispatch 路径(改 inline 调用不升),N3 视访问器 body 复杂度(若 body = 1 行 return 则不升)。

**对策**:Execute 1 先跑 Step 0 预削减释放 M7b bank +2,**或者**动用 per-phase bank 升级(§决策 3)先把 Phase B 启动时 M7b/N3 baseline 重置到 cur(674/514989),允许 Phase B 内部增量。

**验证**:

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS(结构组不升 + 累计组 DRIFT 内)
- 所有 tests/ 行为不变(访问器是 pass-through,Phase A 语义等价)
- `bin/ss run tools/dual_track_linter.ss` PASS(访问器不新增 kind,不触 D088 双轨)

### §决策 3 — 银行策略升级:累计组永不 record / 结构组 baseline 持续累积

**触发**:D109 Execute 2 实测 record 被机械阻断,D109 §步骤 2 §决策矩阵 L283-289「所有指标 PROGRESS → record」语义不可达。

**新语义**(对照 D097 L70-71 / D102 §规则 1.4 澄清,不创造新机制,澄清现有机制边界):

1. **累计组(M1/M2/M3a/N2)baseline 永不 record** —— 新功能新语法新 kind 引入必然累计 +,累计组 baseline 设计意义是「相对 D097 L1 首次 baseline 的漂移上限 tol = baseline/200」,随时间推移**只降不升**。D102 §规则 1.4 L102「累计组:任一 cur > baseline → record 拒绝」即此语义机械化
2. **结构组(M3b/M4/M6/M7a/M7b/N1/N3/N4/N5)baseline 仅在削减后 record** —— 结构组反映编译器**结构复杂度**(函数数 / 递归数 / dispatch 深度 / AST 深度),削减即重构收敛,baseline 单调下降。当前 cur 结构组 8 项 OK/PROGRESS 但因累计组 +,整体 record 阻断
3. **D109 §决策矩阵修订** —— 改条件为:

| 条件 | 决策(原 D109 L283-289)| 决策(D110 §决策 3 修订)|
|---|---|---|
| Step 1 实测结构组全 OK/PROGRESS + 累计组 DRIFT 窗内 | 「所有指标 PROGRESS → record」(**不可达**)| **不 record,状态回写 D 文档标注 phase 闭环即可**,Phase 延续 D101 baseline 作跨 phase 对照基 |
| 任一结构组 cur > baseline | Plan 退回削减 | **同原决策**,结构组严格不升(D097 L102)|
| 累计组任一 cur > baseline + tol | DRIFT 窗外阻断 | **同原决策**,DRIFT 机制不变 |

4. **Phase B 启动时的 per-phase bank 处理** —— 两方案对比:

| 方案 | 描述 | 评估 |
|---|---|---|
| **A. 独立 baseline 文件 per phase** | `tools/linter_baseline_phase_a.txt` / `_phase_b.txt`,phase 启动时 fork baseline,phase 内削减 record 独立文件 | **拒绝**:双 baseline 文件漂移 + `tools/reflection_health_linter.ss` 需改双源,违反 D102 §规则 §单数据源 |
| **B. 单 baseline + phase 标记注释** | `tools/linter_baseline.txt` 顶部加 `# phase: <current>` 注释,phase 切换时人工 + linter 提示,不自动分 baseline | **选定**:最小改动,兼容现有机制,phase 切换作为 D 文档级事件不依赖 linter 自动化 |
| **C. 跨 phase 单 baseline 不分** | 保留 D101 baseline 一贯到底,Phase B 内部不 record,直到最终 all-phase 闭环 | **备选**:D102 §规则 1.4 当前默认语义,若 Phase B 工程规模 < Phase A 可直接延续 |

**本 Plan 选 C 作为 Phase B 起步默认**(D097 / D102 机械规则不变),Phase B 推进过程中若 M7b/N3 bank 累积余量 < 5 时升级到 B。

**不涉及代码改动**(本决策是策略澄清 + D 文档回写,不改 linter 实现)。

## Rejected Alternatives

### §A — Phase A 收尾压回单 evalExpr(vtable 融合统一入口)

**拒绝理由**:

- F1 R3 硬阻断:单函数合并后 eval_expr.ss 736 行 > 600,R3 REGRESSION(见 §决策 1 依据 2)
- Zig sema.zig 本身就是「主 + 子分析器」分层,不强制物理单函数(见 §决策 1 依据 1 / 4)
- 违反 `memory/feedback_design_no_code_authority.md`:把「11 子函数分层」当架构假设否定而不是当前形态的简化描述

### §B — UNARY / BINARY / COMPTIME_EXPR 追加迁移 `bootstrap/eval/*.ss`

**拒绝理由**:

- D094 L175 zig 驱动 9 kind 审计表明确 UNARY/BINARY 是 "simple"(11 kind 字面量等无 ct 处理),COMPTIME_EXPR 是 "dual"(模式入口),**不在 9 kind 迁移目标内**
- UNARY 41 行 inline + BINARY 47 行 inline = evalExpr 主 dispatch 的核心逻辑,迁出后主 dispatch 退化 pure switch 失去紧凑性
- COMPTIME_EXPR 4 行与 D109 §Rejected C ARROW_FUNC 4 行对称理由延续

### §C — Phase A / Phase B 合并推进(访问器引入 + InternPool 同轮)

**拒绝理由**:

- D098 §决策 2 Phase A / Phase B / Phase C 明确分步「不一次全做」,一轮合并违反 D098 §决策 2 L116「evalExpr 骨架先跑通,InternPool 后引入」
- Phase B InternPool 涉及 key 设计 + hash 策略(D098 §新张力 4)+ Map hash/equal 定制风险,与访问器引入规模差 5-10×,合推非线性风险
- `memory/feedback_no_dramatic_reset.md`:Phase 切换作为分段诊断,不允许整体推倒重来

### §D — 修改 linter 接受累计组分组 record(改 writeBaseline 允许累计组升)

**拒绝理由**:

- 违反 D097 L70-71 的机械约束(「累积方向严禁更新 baseline」),设计意图是防 baseline 被漂移蚕食
- 累计组 baseline 的语义本就是**漂移上限参照**,允许 record = 把 baseline 变成 cur 的跟随值,失去 anti-drift 功能
- 本决策源自对 D097 L70-71 的**误读**(以为是可调整的策略,实为不变量)

### §E — 把 D109 §决策矩阵漏洞记作「路线偏移警告」而非「设计漏洞」

**拒绝理由**:

- 漏洞源自 D109 Plan 设计阶段对 D097 L70-71 / D102 §规则 1.4 的**覆盖盲区** — `memory/feedback_design_no_code_authority.md` 的典型教训:D 文档设计时把既有代码当架构权威忽略了机械规则
- 不修订 = 漏洞残留下轮 Phase B 起步时复现(「为什么 Phase B 也 record 不了?」循环)

### §F — 重新设计 baseline 分组文件(结构 / 累计 双 baseline 文件)

**拒绝理由**:

- 违反 D102 §规则 §单数据源(`tools/linter_baseline.txt` 一份合并,避免双文件漂移)
- 工程收益 vs 成本负面:双文件 + 双 record 路径 + 双 compareAndReport 逻辑 + phase 切换同步,复杂度 10× 于单文件加 phase 注释
- 现行单文件 + D097 + D102 机械规则已充分,改造 = 过度工程

### §G — 不起草 D110,直接 D111 Phase B 启动

**拒绝理由**:

- D109 §决策矩阵漏洞未记录 → 下轮 Phase B 起步时无参照,同漏洞可能在 Phase B 内部 record 尝试时复现
- Phase A 闭环宣告缺独立 D 文档承载(D109 只承载 NEW_EXPR 迁移,不承载全局收尾)
- D098 §决策 2 Phase B 启动前访问器引入要求(§新张力 2)无 Plan 承载

## 新张力(D110 引出)

1. **累计组 baseline 漂移失锚风险**(长期)— 当前 D101 baseline M1=5134 / M2=76126 / M3a=12122 / N2=380630,Phase A 已累积 +4 / +84 / +2 / +420,若 Phase B 再累积 +20~+200 每项(访问器 + InternPool),tol 窗口(M1 ±25 / M2 ±380 / M3a ±60 / N2 ±1903)几轮内占满。**对策**:本 Plan 未解决,留 Phase B 中后期评估是否引入「delta baseline」即「相对上次 phase 闭环 cur」的子对照基,当前 D101 baseline 保留作「绝对 baseline」
2. **per-phase bank 的语义边界未完全明确** — §决策 3 方案 C 选定跨 phase 单 baseline,但「Phase A 闭环 cur = Phase B 起步 baseline」的 implicit 语义未形式化。**风险**:Phase B 中期削减时 record 的 baseline 是 D101 的 M7b=676 而非 Phase A 闭环 cur=674,削减压力计算基准混淆
3. **访问器引入点跨文件散布** — D098 §新张力 2 明确 Phase A 末期引入,但 `interp*` 调用点在 30 函数 × 平均 5-10 调用点 = 150-300 处散布,一次性全改 LOC 估 300+,影响累计组 M2/M3a 大幅 DRIFT。**对策**:D110 Execute 1 范围限定「新增 valOf/valType 函数 + 选取 5-10 个高频 interp* 调用点改造」,其余 Phase B 中期渐进
4. **InternPool key 设计未定延续 D098 §新张力 4** — `STR|<huge_string>` 序列化成本 / `ARR|[...]` 数组 key / hash 冲突率,D098 明确「Phase B 启动时评估,不预判」。**D110 范围不触**,留 D111 或 D112 独立 Plan
5. **Phase B 启动首次 GATE 阻断概率** — §决策 2 预估 M7b +2 / N3 +11~+61 都是结构组 STRICT 指标 → GATE 阻断概率高。**对策**:Execute 1 先跑 Step 0 预削减(释放 M7b bank ≥ +2)**或**沿用 D101 baseline 继续(cur 674 ≤ 676 bank +2 仍充裕,N3 -3122 深窖远不动)— 后者实施成本 0,优先
6. **UNARY/BINARY inline 不迁的长期可读性** — §决策 1 保留 inline 88 行 + 4 行 COMPTIME_EXPR = 92 行 inline 比 11 子函数平均 70 行略长。**隐藏假设**:inline 逻辑紧凑 > 迁出后 dispatch 退化。**风险**:Phase B 中期若 BINARY op 分支激增(NullCoalesce/Instanceof/As/Pow/Add/string compare/int/double 6+ 分支)body 可能升至 80+ 行,届时评估是否迁 `bootstrap/eval/binary.ss`
7. **`valOf` / `valType` 命名与 D098 §新张力 6 函数重载冲突风险** — D098 §决策 1 用 `mvKnownOf` / `mvValOf` 错名避重载 dispatch 失效,D110 valOf/valType 作为 Value 层访问器与 MaybeVal 层 mvValOf 区分。**风险**:未来若 MaybeVal / Value 合并(Phase C)命名空间冲突。**对策**:Phase B 不合并,保持两层独立命名
8. **D109 §决策矩阵漏洞影响 D108 / D107 / ... 历史 Plan** — D109 §决策矩阵继承 D108 §步骤 2 §决策矩阵(完全同构),D108 同样有「所有指标 PROGRESS → record」条件。**回查 D107/D106/D105/D104/D103/D101 §步骤 2** 是否有类似条件 — 若有则历史 Plan 均含此漏洞,但因均选「不 record 延续银行策略」路径实际未触。**结论**:漏洞是**潜在**而非**历史触发**,本 Plan 修订足够,无需回写历史 D 文档
9. **反射 gate trivially PASS** — D110 不触反射路径(不改 D095 FieldMeta / D097 AnnotationMeta / @derive handler),R1/R3 trivial PASS。反射健康度由 `bin/ss run tools/reflection_health_linter.ss` GATE 提供,本 Plan 无反射专章

## 下一步(Plan 下的 Execute 顺序)

1. [x] Done at `aa57864` — **Plan 起草 + §决策 1/2/3 拍板**:本文档写入,D109 §步骤 2 §决策矩阵漏洞修订归 §决策 3,D094 §Q2 收尾 §Phase A 迁移进度 P19 标注 9 kind 全完(D109 Execute 2 同 commit)
2. [ ] Planned — **Execute 1**(Phase B 访问器引入):
   - 新增 `valOf(valId: int): int` / `valType(valId: int): string` 于 `bootstrap/gen_maybeval.ss`(或新建 `bootstrap/gen_value.ss`)
   - 选取 5-10 个高频 `interp*` 调用点改调访问器(建议:`bootstrap/codegen.ss` L277-500 内 evalExpr 驱动路径调用的 `interpAsInt` / `interpAsStr` / `interpType` 前 5-10 处)
   - 单独 commit + bootstrap 固定点 + 全测 + GATE PASS
   - 预估:M7b +2 / N3 +11~+61 / M2 +20~+70 / N2 +50~+150(Phase B 首轮结构组 +,D101 baseline 仍 bank +2 充裕)
3. [ ] Planned — **Execute 2 及后续**(Phase B InternPool 引入 / Type-as-Value 合并 / 反射 metadata InternPool 承载等):独立 D 文档 D111+(D098 §决策 2 §Phase B / §决策 3 Phase B 对应 Plan)

每 Execute 开始前先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- D109 §步骤 2 §决策矩阵 L283-289(漏洞源)/ §下一步 #3(本 Plan 起草触发)/ Execute 1 实测(N3 -3122 / F1 gen_exprs -503 / F1 eval_expr -441)
- D108 §步骤 1 evalCall / §扩展 子目录全拆(eval/* 11 文件 R3 方案)
- D107 §步骤 1 evalMethodCall / §步骤 2 决策矩阵同构原型
- D101-D106 §步骤 1 8 kind 迁移模板(TEMPLATE_LIT/ARRAY_LIT/IDENT/MEMBER_ACCESS/INDEX_ACCESS/POSTFIX_INC 各 Plan)
- D102 §规则 1.1-1.4 分层 GATE / §规则 1.4 record 行为 L99-103(累计组永不 record 机械规则)/ §规则 2.1-2.3 F1 GATE / §规则 2.1 R3 新文件 ≤ 600 / R4 graduate
- D100 §坑 Q 银行余量 / §坑 P M2/N2 成本
- D099 §坑 G-O N3/M7b 成本
- D098 §决策 1 MaybeVal 编码 Phase A mv int / §决策 2 InternPool Phase A → Phase B 过渡 / §决策 3 Type-as-Value / §新张力 2 Phase A 访问器引入 / §新张力 4 InternPool key 设计
- D097 L70-71 累积方向严禁 record(机械规则源)/ L102(D102 §规则 1.4 继承)
- D094 §Q2 收尾 §genVal 操作数驱动审计 §Phase A 迁移进度(9 kind 全 [x] Done 表,D109 Execute 2 同步写入)
- D093 §决策 §Zig 原理(MaybeVal `?Value` / Value 无类型 / Type as Value / InternPool)/ §SS 本质一样骨架 / §张力 1-3
- D088 §第一性需求(Zig SEMA 一份 evalExpr)/ §正模式(一份 evalExpr 函数,非物理单函数)/ §反模式(维持双轨制)
- CLAUDE.md §反射根因 gate(D110 不触)/ §交互式单文档 / §PFV 流程
- `memory/feedback_ultrathink_gate.md` / `memory/feedback_pfv_process.md` / `memory/feedback_reflection_root_cause_gate.md` / `memory/feedback_design_no_code_authority.md`(本 Plan 核心教训:设计矩阵忽略机械规则是架构权威误用)/ `memory/feedback_no_dramatic_reset.md`(Phase 切换分段诊断不推倒重来)
- `bootstrap/eval_expr.ss`(128 行主 dispatch,D109 Execute 1 后形态)
- `bootstrap/eval/`(11 子文件,D108 §扩展 落地)
- `bootstrap/codegen.ss:83`(`comptimeTypeAliases` 独立通道,Phase B §决策 3 收尾目标)
- `bootstrap/codegen.ss:277-500`(约 30 `interp*` 函数,Phase B §决策 2 访问器改造范围)
- `tools/reflection_health_linter.ss`(writeBaseline L330-371 / compareAndReport L373+)
- `tools/linter_baseline.txt`(D101 Execute 0 commit `9343330` baseline,D110 §决策 3 方案 C 保留延续)
- `tools/next_prompt_ultrathink_linter.ss`(PFV §收尾 gate 第 3 步 (b) 机械 gate)
