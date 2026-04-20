# D108: evalExpr Phase A 后批 2c Plan — CALL(重量调用 kind,纯迁移路径)

**Status:** Execute 1 Done(commit 2c38819,含子目录全拆扩展,见 §扩展)
**Depends on:** D107 §步骤 2 决策矩阵(M7b 余量 ≥ +3 且 N3 bank < -2500 → 起 D108)/ D107 Execute 1 实测命中 / D107 §步骤 1 evalMethodCall(对称三段式模板,含 callPreRegs save/new/restore 三态)/ D106 §步骤 1 evalPostfixInc / D105 §步骤 1 evalMemberAccess(多触点迁移模板)/ D104 §步骤 1 evalIdent / D103 §步骤 1 evalArrayLit(SPREAD_ELEM 在 Array 字面量已承载)/ D101 §新张力 1 mv 编码 / D100 §坑 Q 银行余量不 record / D102 §规则 1.1-1.4 分层 GATE + ±0.5% DRIFT / D102 §规则 2.1-2.3 F1 文件行数 GATE / D098 §决策 1 MaybeVal mv 编码 / D094 §决策 §规则 2 L109-110 pure subset 白名单(CALL **不**在,不自动折叠)/ D094 L175 zig 驱动 9 kind(CALL 在列)/ D088 §第一性需求(Zig SEMA 一份 evalExpr)/ CLAUDE.md §反射根因 gate / `memory/feedback_ultrathink_gate.md` / `memory/feedback_design_no_code_authority.md`

**Date:** 2026-04-20

---

## 第一性需求

D107 Execute 1 已合并 METHOD_CALL(2b 首 kind,中量调用迁移),eval_expr.ss 新建 evalMethodCall + evalExpr 头部分派 + L132 shim 扩 11 kind + 删 gen_exprs.ss L271-344 整块 74 行 inline。**实测全线反向通过**(baseline = commit 9343330):

```
M7b 676→672 Δ=-4(预估 672 精确命中)
N3  518111→515552 Δ=-2559(预估 -2611~-3011 轻微偏浅,但仍深窖新纪录)
M2  76126→76150 Δ=+24 DRIFT(预估 +9~+34 中段命中)
N2  380630→380750 Δ=+120 DRIFT(预估 -30~+90 略偏高 30)
F1:gen_exprs.ss 1721→1348 Δ=-373(预估 ~1348 精确命中,21.7% 压缩率)
```

D102 ±0.5% DRIFT 窗口**六次生产验证连续反向通过**(D101 TEMPLATE_LIT / D103 ARRAY_LIT / D104 IDENT / D105 MEMBER_ACCESS / D106 POSTFIX_INC / D107 METHOD_CALL 全 PROGRESS/DRIFT 窗内),银行余量继续深窖。**本 Plan 接 D107 §步骤 2 决策矩阵**,条件 `M7b 余量 ≥ +3 且 N3 bank < -2500` 实测 `+4 / -2559` 命中 → **不 record**,起 D108 走 **CALL**(重量调用,Phase A 后批 2c 首选)。

baseline(D101 Execute 0 commit 9343330,D103/D104/D105/D106/D107 均未 record,**银行余量累积**):

```
M1=5134  M2=76126  M3a=12122  M3b=1879  M4=3037
M5=1750  M6=32     M7a=27     M7b=676   N1=34
N2=380630  N3=518111  N4=321  N5=0
F1:bootstrap/gen_exprs.ss=1721  (+ 13 条其他)
```

cur(D107 Execute 1 后 commit 6a30bda):`M7b=672(bank +4)/ N3=515552(bank -2559)/ M2=76150(bank +24 DRIFT)/ N2=380750(bank +120 DRIFT)/ F1:gen_exprs.ss=1348(bank -373)`。**5 项余量深度富裕**,M7b +4 ≥ 新函数 +1 余量 4 倍,N3 结构组深窖再破纪录,F1 累计 21.7% 压缩,足支持 Phase A 后批 2c 重量 kind 起步。

**CALL 是 Phase A 后批 2c 首 kind**(非 NEW_EXPR 2d 先落),承担三重职责:

1. **D094 L175 zig 驱动 9 kind 必做** —— 列表明指 CALL 归属(IDENT / **CALL** / NEW_EXPR / MEMBER_ACCESS / METHOD_CALL / TEMPLATE_LIT / ARRAY_LIT / INDEX_ACCESS / POSTFIX_INC 共 9 kind,前 7 `[x] Done`,剩 **CALL + NEW_EXPR**)。CALL 不迁 = Phase A 不闭环
2. **user function inline + 泛型实例化 + SPREAD_ELEM 首次进 evalExpr args 分支** —— 2b METHOD_CALL 已证参数迭代 + callPreRegs 三态 + 2 分支(NAMED_ARG / 普通),CALL 扩展 **SPREAD_ELEM 3 分支 + 泛型 genericFuncNodes/ctFuncNodes 两端** 场景,对 Phase B MaybeVal 类化(D098 §决策 2)输入 args 调用面再扩一维
3. **Phase A 末期重量 kind 必过** —— CALL 77 行 body 是 9 kind 剩余最大体量(仅略大于 METHOD_CALL 74 行),过则 Phase A 后批剩 NEW_EXPR 一 kind,不过则 Phase A 全完链断

## 为什么 2c 首 kind 选 CALL(3 候选对照)

| 要素 | **CALL** | NEW_EXPR | POSTFIX_DEC expr |
|---|---|---|---|
| body 行 | **L141-217,77 行** | L218-270,53 行 | gen_exprs.ss 无独立 expr inline(grep 0 匹配,D107 §Rejected A 已证)|
| 节点估 | ~300 | ~200 | 0(不存在)|
| expr 形式支持 | **已有**(gen_exprs.ss:141 inline) | **已有**(gen_exprs.ss:218 inline) | **从未有**(genPostfixExpr L110 硬编码 add,只处理 INC)|
| subsystem 耦合 | **~15-20 跨文件依赖** — genericFuncNodes / ctFuncNodes / genGenericCall / callPreRegs / genCall / ctCallDispatch / interpNewNull / interpType / interpArrayLen / interpArrayGet / comptimeDepth / SPREAD_ELEM / NAMED_ARG / nGet* helpers / payload / reg / isCt / ctVal / constVal | ~10 跨文件依赖 — genericClassNodes / interpClasses / genGenericNewExpr / genNewExpr / ctNewExprDispatch / callPreRegs 等(比 CALL 少 SPREAD_ELEM + 用户函数 inline / 泛型函数 AST 注入) | N/A |
| pure subset | **不在**(D094 L109-110 可能有 println/exit 副作用)| **不在** | **不在** |
| zig 驱动 9 kind | **在**(D094 L175)| **在**(D094 L175)| **不在** D094 L175 |
| Step 0 压力 | 无(bank +4 充裕)| 无(bank +4 充裕)| N/A |
| 反射 gate | **不触**(CALL body 不含 FieldMeta/AnnotationMeta;@derive handler 走独立 gen_derive 路径,非 CALL/METHOD_CALL inline)| 不触 | N/A |
| Phase A 纯迁移 | **是**(inline body 现存 → 迁入 evalCall 不改行为)| **是** | **否 — 新增 expr 形式 feature + 首次迁移**(D107 §Rejected A 实证)|
| Plan 粒度 | **一 Plan 一 kind 守则符合** | 一 Plan 一 kind 守则符合 | 需 bundle 才能承载 feature + 迁移,违反守则 |
| D107 §步骤 2 §2c 地位 | **首选**(重量候选,~20+ 依赖)| 次选(中量候选)| 推 Phase B 或独立小 Plan |

**CALL 首选六项依据**:

1. **D094 L175 zig 驱动 9 kind 收敛序列决定** — Phase A 剩 CALL + NEW_EXPR 两 kind,两 kind 均必做。本 Plan 选 **CALL 先于 NEW_EXPR** 依据体量 + 复杂度递减:CALL 77 行(泛型 + SPREAD_ELEM + ~15-20 跨文件)> NEW_EXPR 53 行(构造 + ~10 跨文件,无 SPREAD_ELEM / 无泛型函数注入)。**重量先上,轻量收尾**,Phase A 末轮 NEW_EXPR 53 行迁移同 METHOD_CALL 模板,风险面小;若反过来 NEW_EXPR 先 + CALL 后,Phase A 末轮重量起 → 银行余量若临界(经连续迁后)反弹压力更大

2. **D107 §步骤 2 决策矩阵直接覆盖** — 矩阵 L299 条件 `Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ +3,N3 bank < -2500 → 不 record,起 D108 Plan 走 CALL(重量调用 kind,Phase A 后批 2c)`。实测 M7b +4 / N3 -2559 / 全 PROGRESS(DRIFT 窗内)命中

3. **CALL 是 9 kind 剩余最大体量** — gen_exprs.ss 剩 zig 驱动 kind:CALL(77 行 L141-217)/ NEW_EXPR(53 行 L218-270)/ ARROW_FUNC(4 行 L271-274,dual kind 非 zig 驱动,不迁)。按 D102 §规则 1.1 结构组严格 ≤ baseline + ±0.5% DRIFT 窗口,**重量先上再补中量**,定位难度可控;若后批末轮再起 CALL,若银行消耗完临界则需先 Step 0 削减再 Execute,增 1 轮

4. **SPREAD_ELEM 首次进 evalExpr args 分支 — 跨 kind 对称价值** — evalArrayLit(D103 Execute 1)已承载 SPREAD_ELEM 于 Array 字面量展开(eval_expr.ss:252/263/289 三处处理);evalCall 是**第二处**进 SPREAD,对 args 侧 ct/runtime + array/非array 组合建立模板,Phase A 后批 2d NEW_EXPR 无 SPREAD(gen_exprs.ss L237-262 NAMED_ARG + 普通 2 分支,无 SPREAD 逻辑),跨 kind 对称验证落在 D108

5. **泛型 user function inline 首验** — CALL body 首行分支 `genericFuncNodes.has(callName) == 1`(L144-152):
   - comptime:`ctFuncNodes.set(callName, genericFuncNodes.getString(callName))`(AST 注入 comptime 解释器)
   - runtime:`return constVal(genGenericCall(id, callName, callArgList))`(直接调用泛型实例化器)
   
   **对 Phase B MaybeVal 类化输入**:MaybeVal 需承载 call dispatch 的 vtable + 类型参数多态(D098 §决策 2),CALL 迁入 evalCall 给出泛型路径两端状态实证,NEW_EXPR 迁 evalNewExpr 同结构承载(genericClassNodes/interpClasses 两端),建立泛型调用族迁移模板

6. **不触反射 gate** — CALL body 不含 D095 FieldMeta / D097 AnnotationMeta / @derive handler 路径。@derive 的 ts-gen 字符串拼接走 `gen_derive.ss` 独立路径,CALL inline 只处理普通函数 + 泛型函数 + println/print/intrinsic。R1/R3 对照 trivial PASS,本 Plan 无反射专章开销(对比 D105 MEMBER_ACCESS 需反射 gate 专章)

## 当前事实(2026-04-20 snapshot,commit 6a30bda @ D107 Execute 1 后)

| 项 | 值 / 位置 |
|---|---|
| CALL 分派 | `bootstrap/gen_exprs.ss:141-217`(**77 行 inline**,header `if (kind == "CALL")` 在 L141,结尾 `}` 在 L217)|
| L132 shim | 11 kind 含 METHOD_CALL(D107 Execute 1 后)|
| eval_expr.ss | **567 行**,10 函数(evalExpr + evalTernary + evalShortCircuit + evalIndexAccess + evalTemplateLit + evalArrayLit + evalIdent + evalMemberAccess + evalPostfixInc + evalMethodCall)|
| genCall(runtime,不迁)| `bootstrap/gen_calls.ss:464`,保留 |
| genGenericCall(runtime,不迁)| `bootstrap/gen_calls.ss:323`,保留 |
| ctCallDispatch(comptime helper,不迁)| `bootstrap/gen_exprs.ss:333`,保留,evalCall 内调用 |
| genericFuncNodes / ctFuncNodes | `bootstrap/codegen.ss:95 / :19`,全局,不迁 |
| callPreRegs | `bootstrap/gen_calls.ss:8`,全局,不迁 |

**CALL body 结构**(L141-217 逐层):

- **L141**:header `if (kind == "CALL") {`
- **L142-143**:`callName = nGetS1(id)` / `callArgList = nGetList(id)`
- **L144-152**:泛型分支(9 行)
  - L144 `if (genericFuncNodes.has(callName) == 1) {`
  - L145-148 comptime:`ctFuncNodes.set` AST 注入
  - L149-151 runtime:`return constVal(genGenericCall(id, callName, callArgList))`
- **L153-154**:`savedCallPreRegs = callPreRegs` / `callPreRegs = new Map()`(**三态 save + fresh**)
- **L155-157**:`callCtArgVals = []` / `callCtNamedArgs = new Map()` / `callCtHasNamed = 0`
- **L158-209**:args 处理(52 行,3 分支)
  - L159 `callArgParts = callArgList.split(",")`
  - L160 `for (cap in callArgParts)`
  - L163-171 NAMED_ARG 分支(9 行)
  - L172-197 **SPREAD_ELEM 分支(26 行)** — isCt+array / isCt+非array / runtime,四条子路径
  - L198-205 普通 arg 分支(8 行)
- **L210-213**:comptime 分派 `return ctCallDispatch(id, callName, ...)`
- **L214-216**:runtime 分派 `const callResult = constVal(genCall(id))` + callPreRegs 恢复(**第 2 处 raw constVal,迁入后必包 mv 编码**)
- **L217**:`return callResult` + `}`

**关键点**:CALL 的 **runtime 回退 1 处 raw constVal**(L214),**SPREAD_ELEM 分支无 raw constVal**(srcVal 来自 genVal,callPreRegs.set 只搬 reg str 不重新 constVal),共 **1 处** runtime 回退需改 mv 编码;**泛型 runtime 分支 1 处**(L150 `return constVal(genGenericCall(...))`),共 **2 处 raw constVal**,比 METHOD_CALL 3 处少。

**跨文件符号清单**(对照 D107 §METHOD_CALL 16 依赖 vs CALL ~15-20):

| 类别 | 符号 | 来源 |
|---|---|---|
| 全局 Map | `genericFuncNodes` / `ctFuncNodes` / `callPreRegs` | codegen.ss / gen_calls.ss |
| comptime helper | `ctCallDispatch` | gen_exprs.ss(保留 evalCall 内调用)|
| runtime helper | `genCall` / `genGenericCall` | gen_calls.ss |
| interp helper | `interpNewNull` / `interpType` / `interpArrayLen` / `interpArrayGet` | interp.ss |
| AST helpers | `nGetKind` / `nGetS1` / `nGetI1` / `nGetList` / `nGetLine` / `nGetCol` | parser.ss / ast_maps.ss |
| value 编码 | `payload` / `reg` / `isCt` / `ctVal` / `constVal` | gen_maybeval.ss |
| 状态 | `comptimeDepth` | codegen.ss |

## 对照 D102 §规则 1.1-1.4 分层 GATE 的 DRIFT 预估

baseline = commit 9343330(D101 Execute 0),cur = D107 Execute 1 后 commit 6a30bda。D108 Execute 1 预估相对 baseline:

| 指标 | 组 | baseline | D107 cur | D108 step 1 后(估) | Δ 相对 baseline | tol | 判定 | 依据 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5134 | 5134-5142 | 0~+8 | ±25 | OK | body 分支 CC 守恒(泛型 2 分支 + args for + NAMED_ARG/SPREAD/普通 3 分支 + comptime/runtime if 搬家,净 0~±4)|
| M2 | 累计 | 76126 | 76150 | 76180-76220 | +54~+94 | ±380 | OK | 新函数签名 +12 + L132 shim 扩 kind +3 + 删 outer `if kind == CALL` -2 + body 77 行搬家内部 Halstead 项波动 +20~+30 ≈ 净 +30~+40 相对 D107 cur(略大于 METHOD_CALL 净 +24 因 body 3 行多 + SPREAD_ELEM 4 子路径)|
| M3a | 累计 | 12122 | 12122 | 12124-12132 | +2~+10 | ±60 | OK | genVal → evalCall 新边 +1 + helper 调用数守恒 |
| M3b | 结构 | 1879 | 1879 | 1879 | 0 | 0(严格)| OK | 不触最大入度函数(genVal/emitIR 边数不升)|
| M4 | 结构 | 3037 | 3035 | 3033-3037 | -4~0 | 0(严格)| OK | `if kind == CALL` 删除 -1 + evalExpr 头部加 1 分派 +1 = 净 0;内部 for 循环深度不升最大 |
| M5 | 累计 | 1750 | 1747 | 1748-1754 | -2~+4 | ±8 | OK | 不新增可变变量(savedCallPreRegs/callCtHasNamed/callCtArgVals 迁入不增总量)|
| M6 | 结构 | 32 | 32 | 32 | 0 | 0(严格)| OK | 不新增递归 |
| M7a | 结构 | 27 | 27 | 27 | 0 | 0(严格)| OK | body depth 5(args for + SPREAD if + isCt if + interpType if + interpArrayLen while)搬入独立函数 depth 5,不升最大 |
| M7b | 结构 | 676 | 672 | **673**(+1 evalCall)| **-3** | 0(严格)| **OK**(bank +3 充裕)| bank +4 → +3,余量 ≥ 0 |
| N1 | 累计 | 34 | 34 | 34 | 0 | ±1 | OK | 不引入新 kind |
| N2 | 累计 | 380630 | 380750 | 380900-381100 | +270~+470 | ±1903 | DRIFT/OK | M2 派生;body 77 行搬家 Halstead 项波动 +150~+350 相对 D107 cur;远在窗内 4× 充裕 |
| N3 | 结构 | 518111 | 515552 | **514700-515150** | **-2961 ~ -3411** | 0(严格)| **PROGRESS** | body depth 5 搬家压缩 -400~-850 相对 D107 cur;对比 METHOD_CALL 74 行 depth 4 压缩 -245 / MEMBER_ACCESS 123 行 depth 5 压缩 -879 / ARRAY_LIT 62 行 depth 4 压缩 -858(D105 相对 D104),CALL 77 行 depth 5(SPREAD_ELEM 嵌套 while)估 -400~-850 合理偏高段 |
| N4 | 结构 | 321 | 321 | 321 | 0 | 0(严格)| OK | 不触最大节点出度函数 |
| N5 | 结构 | 0 | 0 | 0 | 0 | 0(严格)| OK | 不新增 MEMBER_ASSIGN |
| **F1:gen_exprs.ss** | - | 1721 | 1348 | **~1271** | **-450** | 单调下降 | **PROGRESS** | 删 L141-217 整块 77 行 inline body;+L132 shim 扩 kind 字面量不增行;净 -77 相对 D107 cur |

**累计组 6 项** 全 OK/DRIFT(M2 +30~+40 / N2 +150~+350 相对 D107 cur 均 DRIFT 窗口内 10-50× 充裕),**结构组 8 项** 全 OK/PROGRESS(核心 M7b +1 bank 吸收 / N3 继续深窖 -400~-850 相对 D107 cur),**F1** gen_exprs.ss PROGRESS(1348→~1271 相对 baseline 累计 -450 行)。

## DRIFT 窗口七次生产验证(D101/D103/D104/D105/D106/D107 实测 + D108 预估)

| kind | body 行 | 节点估 | M2 实测 vs 预估(相对 baseline)| N2 实测 vs 预估 | N3 实测 vs 预估 | F1 实测 vs 预估 |
|---|---|---|---|---|---|---|
| D101 TEMPLATE_LIT | 42 | 130 | +8 vs N/A | +40 vs N/A | -238 vs N/A | -42 vs N/A |
| D103 ARRAY_LIT | 62 | 180 | -44 vs N/A | -320 vs N/A | -1117 vs N/A | -107 vs N/A |
| D104 IDENT | 41 | 150 | -51 vs N/A | -255 vs N/A | -1316 vs -1167~-1317 | -148 vs -148 |
| D105 MEMBER_ACCESS | 123 | 400 | -30 vs -6~-36 | -150 vs -130~-230 | -2195 vs -1411~-1711(**超下限 484**)| -271 vs -271 |
| D106 POSTFIX_INC | 28 | 90 | -17 vs -26~-46(**偏浅 9**)| -85 vs -110~-170(**偏浅 25**)| -2314 vs -2241~-2311(**超下限 3**)| -299 vs -299 |
| D107 METHOD_CALL | 74 | 280 | +24 vs +9~+34(中段命中)| +120 vs -30~+90(**偏高 30**)| -2559 vs -2611~-3011(**偏浅 52**)| -373 vs -373 |
| **D108 CALL(预估)** | **77** | **300** | **+54~+94** | **+270~+470** | **-2961 ~ -3411** | **-450** |

**预估偏差推理**:CALL 77 行体量略大于 METHOD_CALL 74 行(+4%),但 SPREAD_ELEM 4 子路径 + interpType/interpArrayLen/interpArrayGet 3 额外 interp 调用 + 泛型 genericFuncNodes/ctFuncNodes 两端处理,**Halstead 项密度比 METHOD_CALL 高 15-20%**,M2/N2 膨胀系数预估 +30~+40 / +150~+350 相对 D107 cur,即相对 baseline +30~+40 + +24 = +54~+64,+120 + +150~+350 = +270~+470。**若实测 M2/N2 超窗口(+380 / +1903)** → 触发 §新张力 1 "M2/N2 膨胀非线性" 风险,Plan 需修正或退回 Step 0 补削减。

## 决策(分 3 步,每步独立 bootstrap + 分层 GATE PASS)

### §步骤 0 — 可选预削减 commit(bank +4 充裕,默认跳过)

**决策**:D108 Step 0 **默认跳过**,直接 Execute 1 CALL 迁移。依据:

- 当前 M7b=672,baseline 676,bank +4 ≥ 新函数 +1,D102 §规则 1.1 结构组严格 ≤ baseline,673 ≤ 676 **通过**
- 跳过 Step 0 节省 1 轮 Execute,银行策略精神(延续 D100 §坑 Q / D103-D107 §步骤 0 默认跳过)= 累积余量
- 对照 D103/D104/D105/D106/D107 Step 0 默认跳过实测全通,D108 重复该模式

**例外触发条件**(若 Step 1 预估超预期则回退此步):

- Execute 1 实测 N3 反向不降(估 -400~-850 未达相对 D107 cur)→ 触发 Step 0 补削减
- Execute 1 实测 M7b 净 +2 或更多(evalCall 意外拆子函数)→ 触发 Step 0 补削减
- Execute 1 实测 M2 超 +60(SPREAD_ELEM/泛型非线性膨胀)→ 触发 Step 0 补削减
- Execute 1 实测 N2 超 +500(SPREAD while 嵌套节点密度意外)→ 触发 Step 0 补削减

**若触发 Step 0**:按 D103/D104/D105/D106/D107 §步骤 0 候选清单(bootstrap 孤儿 helper grep / 单调用 helper inline / ct* helper 合并)操作,单 commit 落地,bootstrap 固定点 PASS + 分层 GATE PASS。

### §步骤 1 — CALL 迁移(独立函数 evalCall,对称 evalMethodCall pattern)

**新建 `bootstrap/eval_expr.ss` 末尾 `evalCall(astId: int): int`**(对称 evalMethodCall / evalMemberAccess / evalIdent / evalPostfixInc 模板):

函数 body 结构(对照 gen_exprs.ss L141-217 迁入):

```ss
function evalCall(astId: int): int {
    const callName = nGetS1(astId)
    const callArgList = nGetList(astId)
    // 泛型分支
    if (genericFuncNodes.has(callName) == 1) {
        if (comptimeDepth > 0) {
            if (ctFuncNodes.has(callName) == 0) {
                ctFuncNodes.set(callName, genericFuncNodes.getString(callName))
            }
        } else {
            return 0 - constVal(genGenericCall(astId, callName, callArgList)) - 1
        }
    }
    const savedCallPreRegs = callPreRegs
    callPreRegs = new Map()
    let callCtArgVals: Array<string> = []
    let callCtNamedArgs = new Map()
    let callCtHasNamed = 0
    if (callArgList != "") {
        const callArgParts = callArgList.split(",")
        for (cap in callArgParts) {
            const callArgId = parseInt(cap)
            if (callArgId > 0) {
                if (nGetKind(callArgId) == "NAMED_ARG") {
                    callCtHasNamed = 1
                    const nav = genVal(nGetI1(callArgId))
                    if (isCt(nav) == 1) {
                        callCtNamedArgs.set(nGetS1(callArgId), `${payload(nav)}`)
                    } else {
                        callCtNamedArgs.set(nGetS1(callArgId), `${interpNewNull()}`)
                        callPreRegs.set(`${callArgId}`, reg(nav))
                    }
                } else if (nGetKind(callArgId) == "SPREAD_ELEM") {
                    const srcVal = genVal(nGetI1(callArgId))
                    if (isCt(srcVal) == 1) {
                        const srcPayload = payload(srcVal)
                        if (interpType(srcPayload) != "array") {
                            if (comptimeDepth > 0) {
                                println(`error: [comptime] cannot spread non-array value at line ${nGetLine(callArgId)}:${nGetCol(callArgId)}`)
                                exit(1)
                            }
                            callPreRegs.set(`${nGetI1(callArgId)}`, reg(srcVal))
                        } else {
                            const srcLen = interpArrayLen(srcPayload)
                            let srcI = 0
                            while (srcI < srcLen) {
                                const srcElemId = interpArrayGet(srcPayload, srcI)
                                if (srcElemId > 0) { callCtArgVals = callCtArgVals.push(`${srcElemId}`) }
                                srcI = srcI + 1
                            }
                        }
                    } else {
                        if (comptimeDepth > 0) {
                            println(`error: [comptime] cannot spread runtime value at line ${nGetLine(callArgId)}:${nGetCol(callArgId)}`)
                            exit(1)
                        }
                        callPreRegs.set(`${nGetI1(callArgId)}`, reg(srcVal))
                    }
                } else {
                    const av = genVal(callArgId)
                    if (isCt(av) == 1) {
                        callCtArgVals = callCtArgVals.push(`${payload(av)}`)
                    } else {
                        callCtArgVals = callCtArgVals.push(`${interpNewNull()}`)
                        callPreRegs.set(`${callArgId}`, reg(av))
                    }
                }
            }
        }
    }
    if (comptimeDepth > 0) {
        callPreRegs = savedCallPreRegs
        return ctCallDispatch(astId, callName, callCtArgVals, callCtNamedArgs, callCtHasNamed)
    }
    const callResult = 0 - constVal(genCall(astId)) - 1
    callPreRegs = savedCallPreRegs
    return callResult
}
```

**关键点**:

- **坑 mv 编码延续**:原 L150 泛型 runtime 分支 `return constVal(genGenericCall(...))` + L214 普通 runtime 分支 `constVal(genCall(id))` 共 **2 处 raw constVal**,迁入 evalCall 后必须全部包 `0 - constVal(...) - 1`。**§新张力 3 核心验证点**(继 D101/D103-D107 §新张力 2 继承的 mv 编码坑)

- **泛型 comptime 分支 `ctFuncNodes.set` 不变**(AST 注入,非 value,无需 mv 编码)

- **SPREAD_ELEM 无 raw constVal**:srcVal 已是 genVal 结果,`callPreRegs.set(reg(srcVal))` 只搬 reg 字符串,不重新产生 constVal

- **scope 写/读混合** — args 循环内 `genVal(callArgId)` 对每个 arg 递归进入 evalExpr(已迁 IDENT/MEMBER_ACCESS/INDEX_ACCESS/METHOD_CALL/POSTFIX_INC),**§新张力 4 核心验证点**:`f(g(x++), obj.m(y), h.i)` 嵌套读写跨 evalCall 边界 callPreRegs 三态保持

- **helper 不迁** — 除 evalCall body 内 `genVal(callArgId)` / `isCt` / `payload` / `reg` 外,其他 ~15-20 跨文件符号全部保留在原位,对称 evalMethodCall 跨文件读 pendingSuperParent/classFields 模式

**改 `bootstrap/gen_exprs.ss` L132 shim**:

```ss
// BEFORE(11 kind,D107 Execute 1 落地)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT" || kind == "MEMBER_ACCESS" || kind == "POSTFIX_INC" || kind == "METHOD_CALL") { ... }
// AFTER(12 kind)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT" || kind == "MEMBER_ACCESS" || kind == "POSTFIX_INC" || kind == "METHOD_CALL" || kind == "CALL") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
```

**改 `bootstrap/eval_expr.ss` evalExpr 头部**(加 CALL 分派):

```ss
if (k == "CALL") { return evalCall(astId) }
```

**删 `bootstrap/gen_exprs.ss` L141-217 整块**(77 行 CALL inline body,含 outer `if kind == "CALL"` header)

**独立验证链**(tokenize → parse → checker → eval):

1. **Tokenizer**:CALL 由 `f(args)` / `obj.m(args)` 驱动,parse_exprs.ss CALL parse 不改 —— parse 层零影响
2. **check_stmts.ss / checker.ss** CALL checkExpr/inferType 不改(checker 类型推断路径不走 eval)
3. **eval 路径**:`genVal(CALL) → L132 shim → evalExpr → evalCall`,对称 IDENT/MEMBER_ACCESS/METHOD_CALL/POSTFIX_INC 链
4. **runtime IR emit**:`genCall(id)` / `genGenericCall(id, callName, callArgList)` 不迁,gen_calls.ss 内保留 —— IR 输出字节级不变
5. **pir_lower.ss / gen_pir.ss** CALL 初始化 kind 引用 —— PIR 阶段不涉 eval 路径,本 Plan 不影响
6. **gen_types.ss** CALL 类型推断 `inferType` 路径 —— 静态类型推断不走 eval,本 Plan 不影响

**验证**:

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- CALL 行为测试全绿:
  - 普通 call:`f(1, 2, 3)` 编译 + 运行
  - 泛型 call:`identity<int>(42)` / `map<string>(arr, fn)`
  - comptime 泛型注入:`comptime { const r = genericFn<int>(x); emit(...) }`
  - spread call:`f(...arr)` array 展开 + 非 array 退 runtime
  - comptime spread array:`comptime { const r = f(...[1, 2, 3]) }`
  - named args:`f(name: "x", age: 18)`
  - 嵌套调用:`f(g(h(x)))` + 混合 `f(g(x), obj.y, arr[0])`
  - intrinsic:`println(...)` / `print(...)` / `parseInt(...)` / `emit(...)`
  - comptime call dispatch:`comptime { const r = intrinsic(...) }`
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK/PROGRESS(核心 M7b 673 ≤ 676 bank +3 / N3 PROGRESS -400~-850 相对 D107 cur)
  - 累计组 6 项 OK/DRIFT(M2 +30~+40 / N2 +150~+350 相对 D107 cur 均 DRIFT 窗口内)
  - F1:gen_exprs.ss PROGRESS(1348 → ~1271,累计 -450)

### §步骤 2 — 收尾评估 + 指向 2d(NEW_EXPR 中量候选)

**目标**:Step 1 完成后决策 Phase A 后批 2d 起 NEW_EXPR 或 Phase A 末轮 record。**不 record**(延续银行策略至 Phase A 全完)。

**决策矩阵**:

| 条件 | 决策 |
|---|---|
| Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ +2,N3 bank < -2900 | 不 record,起 D109 Plan 走 NEW_EXPR(中量构造 kind,Phase A 后批 2d,zig 驱动 9 kind 末 1 kind) |
| Step 1 实测 M7b 余量 < +2 或 N3 bank > -2400 | record baseline 释放余量,再起 D109 |
| Step 1 实测任一结构组超 baseline(分层 GATE 阻断)| Plan 退回,Step 0 补削减后 Execute 2 再试 |
| Step 1 实测 M2/N2 超 DRIFT 窗口 | 修正 §新张力 1 预估系数,更新 D102 DRIFT 窗口阈值或 §规则 1.1-1.4 |

**2d 候选选型提示(D109 Plan 范围,非本轮)**:

- **NEW_EXPR 2d 首选**:body 53 行 L218-270 + 构造函数路径(genericClassNodes / interpClasses / genGenericNewExpr / genNewExpr / ctNewExprDispatch / Map/Set 特殊分支)+ class 字段初始化;D094 L175 zig 驱动 9 kind 必做;Phase A 末轮
- **Phase A 全完后 record baseline**:D109 Execute 2 Step 1 完成后,全 9 kind `[x] Done`,全部银行余量累计释放 → record baseline 固化为新起点,Phase B MaybeVal 类化开工
- **POSTFIX_DEC expr 形式新增**:非 Phase A 目标(D094 L175 不含),推迟 Phase B 类化期或用户需求驱动时独立小 Plan(继 D107 §Rejected A 决定)

**Execute 2 不涉及代码改动**,仅评估 + 起 D109 Plan(NEW_EXPR)/ 或 record commit,单独 commit。

## Rejected Alternatives

### §A — 首 kind 选 NEW_EXPR 对称中量候选

**拒绝理由**(体量 + 策略对照):

- NEW_EXPR 53 行 L218-270 < CALL 77 行 L141-217,若 2c NEW_EXPR 先,则 2d CALL 77 行成末轮重量 kind;此时银行若累计消耗压缩余量到临界(连续六轮每轮消 M7b -1),末轮重量 kind 回退风险 > 本轮 2c 走 CALL
- **Phase A 末轮优先轻量原则**:D103 ARRAY_LIT 62 行 → D104 IDENT 41 行 → D105 MEMBER_ACCESS 123 行(逆势重量)→ D106 POSTFIX_INC 28 行(回轻)→ D107 METHOD_CALL 74 行 → 本轮 CALL 77 行(重量)→ 下轮 NEW_EXPR 53 行(轻量收尾)。**重-轻交替模式**保银行余量波动对称
- SPREAD_ELEM 4 子路径 + 泛型两端处理是 CALL 独有特性,迁 evalCall 立模板供 NEW_EXPR 2d 参考(NEW_EXPR 无 SPREAD,但泛型 genericClassNodes 模式对称)
- **正确路径:D108 CALL 先,D109 NEW_EXPR 收尾**

### §B — bundle CALL + NEW_EXPR 单 Plan 迁(构造族合并)

**拒绝理由**:

- Plan 粒度守则:一 Plan 一 kind,每 commit bootstrap + GATE 独立 PASS(D100/D101/D103/D104/D105/D106/D107 连续七轮建立)
- CALL 77 行 + NEW_EXPR 53 行 = 130 行合并 body,超出 D105 MEMBER_ACCESS 123 行体量(当时 Phase A 单轮最大),M2/N2 DRIFT 风险合计 +380 / +1900 临近累计组窗口硬上限,非线性膨胀不可控
- CALL 泛型函数 inline(genericFuncNodes/ctFuncNodes 函数 AST 注入)vs NEW_EXPR 泛型类(genericClassNodes/interpClasses 类 AST 注入)逻辑同构但 subsystem 不同,合并 bundle 若实测异常无法区分是函数路径还是类路径问题
- D107 §Rejected C 已 reject METHOD_CALL+CALL bundle 基于类似理由,对称延续
- **正确路径:D108 单 CALL,D109 独立评估 NEW_EXPR**

### §C — bundle METHOD_CALL + CALL + NEW_EXPR 三 kind(调用族全合并)

**拒绝理由**:

- METHOD_CALL 已 D107 Execute 1 commit 6a30bda 合并,不可回退重合
- 即使回退重合(76+77+53)+shim 处理 = 206 行超 D105 MEMBER_ACCESS 123 行 68%,M2/N2 DRIFT 双炸(估 M2 +90~+120 / N2 +550~+900,虽仍在 ±380 / ±1903 窗口内,但非线性接近窗口上限,Plan 弹性清零)
- Plan 粒度守则 + D107 §Rejected C 对称延续
- **正确路径:D108 单 CALL,METHOD_CALL 已独立,NEW_EXPR 独立 D109**

### §D — 跳过 Phase A 后批 2c 直接 record baseline(2b 全完释放余量)

**拒绝理由**:

- 银行策略(D100 §坑 Q / D101-D107 §步骤 2)核心是**Phase A 全完再 record**,2b 批单 kind METHOD_CALL ≠ Phase A 全完(9 kind 剩 CALL + NEW_EXPR 2 kind 未迁)
- Phase A 目标是 D088 §正模式「一份 evalExpr 函数」,CALL / NEW_EXPR 均在 D094 L175 zig 驱动 9 kind 内,后批 2c/2d 必做
- record 本身也是一次 commit,Plan 粒度守则不允许"仅 record 无功能改动"单独成 kind(对称 D103/D104/D105/D106/D107 §Rejected C/D)
- 此处 record 会冲掉 M2 +24 / N2 +120 的 DRIFT 余量,下轮 CALL 迁移启动时累计组从 0 起线,膨胀空间缩 15.8×,风险反弹
- **正确路径:继续 Phase A 后批 2c CALL 迁移,银行余量继续累积直到 Phase A 全完**

### §E — Step 0 强制预削减(不跳过)

**拒绝理由**:

- 当前 M7b bank +4 充裕,对照 D100 Step 0 启动 M7b +2 / D101 M7b 0 / D103 M7b 0 / D104 M7b +8 / D105 M7b +7 / D106 M7b +6 / D107 M7b +5,+4 属充裕区间
- 强制 Step 0 多消耗 1 轮 Execute 无价值,银行策略是累积余量,不强制消耗
- D103/D104/D105/D106/D107 Step 0 跳过实测全通,D108 重复模式可靠
- **正确路径:Step 0 默认跳过,例外触发条件见 §步骤 0**

### §F — 将 POSTFIX_DEC expr 纳入 Phase A 目标并单独 Plan

**拒绝理由**(继 D107 §Rejected F 延续):

- **D094 L175 zig 驱动 9 kind 明确不含 POSTFIX_DEC**,Phase A 收敛目标是 9 kind,POSTFIX_DEC 非目标
- POSTFIX_DEC expr 形式是**编译器 gap**(stmt 已通 / expr 未支持),修 gap 是独立小 feature 而非 Phase A 收敛;拆到 Phase A 等于扩大 Phase A 目标范围,违反 D088 收敛路径
- 用户需求未驱动(`let y = x--` 场景少;for 循环递减通常走 `i = i - 1` 或 `i--` stmt 形式),gap 无紧迫性
- **正确路径:POSTFIX_DEC expr 推至 Phase B 类化期(MaybeVal 重设计承载)或独立小 Plan(用户触发时再启)**

## 新张力(D108 引出)

1. **M2/N2 膨胀非线性(SPREAD + 泛型 + interp helpers 三重叠加)** — 本 Plan DRIFT 预估 M2 +30~+40 / N2 +150~+350 相对 D107 cur 基于 METHOD_CALL 74 行实测 +24 / +120 线性外推。**隐藏假设**:CALL 77 行 Halstead 项密度与 METHOD_CALL 等价。**实测风险**:CALL SPREAD_ELEM 26 行含 `while (srcI < srcLen) { ... }` 嵌套 while + isCt + interpType + interpArrayLen + interpArrayGet 三 interp 调用,Halstead 项密度估比 METHOD_CALL 高 15-20%,M2/N2 可能超线性膨胀至 +60~+80 / +400~+600。**验证点**:Execute 1 必须实测对照 D107 METHOD_CALL 系数,偏差 > 30% → 修正 D102 DRIFT 窗口阈值或 §规则 1.1 公式(当前 `tol = baseline / 200` ±0.5%,Phase A 连续迁移后累计膨胀接近上限,可能需升级至 ±0.75% 或引入「每 kind 迁移成本模型」per-kind 预算)

2. **泛型 callerId 跨边界** — L144 `genericFuncNodes.has(callName)` 决定 AST 注入或 genGenericCall。**隐藏假设**:comptime 分支 `ctFuncNodes.set(callName, genericFuncNodes.getString(callName))` 迁入 evalCall 后 ctFuncNodes/genericFuncNodes 跨文件状态字节级等价,泛型 call 嵌套(`identity<int>(map<string>(arr, fn))`)在 evalCall 递归中 comptime/runtime 分支切换行为不变。**验证点**:Execute 1 单测 comptime 泛型 + runtime 泛型 + 嵌套泛型三场景,偏移则 Plan 退回

3. **原 gen_exprs.ss 2 处 raw constVal 同步改 mv 编码** — 对照 D107 METHOD_CALL 3 处 / D106 POSTFIX_INC 1 处,D108 CALL 有 **2 处 runtime 回退**(L150 泛型 genGenericCall / L214 普通 genCall)。迁入 evalCall 后必须**全部改** `0 - constVal(...) - 1`。**验证点**:若漏改 → caller 拿到 reg str 被当 known val 处理 → comptime 折叠误判。Execute 1 必须 git stash 反向单测 2 条路径 IR 字节级对比(继 D101/D103-D107 §新张力 2 模式)

4. **callPreRegs 三态保持(save/new/restore)跨 evalCall 边界** — CALL body L153 `savedCallPreRegs = callPreRegs` + L154 `callPreRegs = new Map()` + L211/L215 `callPreRegs = savedCallPreRegs`(双 return 点)三态,迁入 evalCall 后跨函数边界状态必须字节级等价。**隐藏假设**:嵌套 `f(g(x))` 外层 evalCall 保存 callPreRegs 到 savedCallPreRegs,内层 evalCall 递归自己 new Map + args 循环 + restore → 外层 restore 回 outermost 初值。**风险**:异常路径(comptime `println exit(1)` SPREAD 非 array)未 restore callPreRegs 即 process 退,但无下文(exit 立即结束),非长期污染。**验证点**:Execute 1 跑 `f(g(h(x)))` 三层嵌套 + `f(...arr, g(x), h.i)` SPREAD + 嵌套混合,callPreRegs 状态跨边界等价

5. **user function inline 策略(genericFuncNodes/ctFuncNodes 两端)** — L144-152 泛型函数路径分 comptime/runtime 两端:comptime 走 AST 注入 ctFuncNodes(供 interp.ss 解释器消费),runtime 走 genGenericCall(直接泛型实例化 + 调用)。**隐藏假设**:迁入 evalCall 后两端语义仍正交,comptime 解释器消费 ctFuncNodes.getString(callName) 返回的是 AST 字符串(非 interp value),行为必须跟原 inline 字节级等价。**边界**:用户泛型函数 `function identity<T>(x: T): T` 被 comptime 调 `identity<int>(42)` vs runtime 调,两端走不同路径必须产出相同结果。**验证点**:tests/ 已有泛型 suite(generic_*.ss)必须全绿

6. **SPREAD_ELEM 首验(CALL args 侧)** — evalArrayLit(D103 Execute 1)已承载 SPREAD_ELEM 于 Array 字面量(eval_expr.ss:252/263/289),evalCall 是 **Phase A 第二处**承载 SPREAD_ELEM 的迁移。args 侧 SPREAD 分 4 子路径:(a) isCt + array(while 展开到 callCtArgVals)/(b) isCt + 非 array + comptime(exit 报错)/(c) isCt + 非 array + runtime(callPreRegs.set 退 runtime)/(d) 非 isCt + comptime(exit 报错)/(e) 非 isCt + runtime(callPreRegs.set 退 runtime)。**隐藏假设**:迁入 evalCall 后 4-5 子路径 + interpType/interpArrayLen/interpArrayGet 三 interp 调用与 eval_expr.ss L252/263/289 evalArrayLit 的 SPREAD 处理字节级等价(虽语义不同一个展开 element 一个展开 arg,但调用序列共用)。**验证点**:Execute 1 单测 `f(...arr)` / `comptime { const r = f(...[1,2,3]) }` / `f(...obj.arr)` / `f(x, ...rest, y)` 四场景

7. **eval_expr.ss 函数数持续攀升(11 函数)** — Step 1 后 11 函数(evalExpr + 10 eval*),Phase A 后批 2c/2d 每 kind +1,全完 12 函数。D100/D101/D103/D104/D105/D106/D107 §新张力连续七次提:「Phase B 类化期需评估是否压回单 evalExpr body」。D108 延续风险记录,不在本轮解决。**对策**:D109 Plan(NEW_EXPR)落地后 Phase A 全完,D110 Phase A 全局收尾评估时拍板 MaybeVal 类化 vtable 是否自然融合 12 eval* 成单 dispatch(Zig sema.zig 是 6000+ 行单函数 + analyzeCall/analyzeBinary 等分派,SS 可借鉴或保留分层)

8. **~15-20 跨文件符号迁入隐性依赖风险** — CALL body 内 genericFuncNodes / ctFuncNodes / callPreRegs(三全局 Map)+ ctCallDispatch / genCall / genGenericCall(三函数)+ interpNewNull / interpType / interpArrayLen / interpArrayGet(四 interp)+ AST helpers + maybeval helpers ≈ 15-20 符号迁入 eval_expr.ss 后跨文件引用。对照 D107 METHOD_CALL 跨文件 16 已 PASS,CALL +25% 符号规模,**bootstrap 固定点验证关键**(stage2==stage3 任一不等即回退)。**风险**:comptime 解释器消费 ctFuncNodes 时若跨 evalCall 迁移前后差一字节(Map.getString() 返回 "" vs non-empty 的判定逻辑),stage2 IR 偏移累加 → stage3 不等 stage2

9. **D102 ±0.5% DRIFT 窗口连续 7 次生产验证反向** — 本 Plan 预估 M2 +30~+40 / N2 +150~+350(相对 D107 cur),均在 ±380 / ±1903 窗口内 10-50× 充裕。D101/D103/D104/D105/D106/D107 实测连续反向通过(全 PROGRESS/DRIFT 窗内),D108 预期延续趋势。**若实测超 DRIFT** → §新张力 1 触发(M2/N2 非线性膨胀),修正系数记录进 D109 Plan + 可能升级 D102 §规则 1.2 阈值

10. **反射 gate trivially PASS(CALL 不触)** — CALL body 不含 D095 FieldMeta / D097 AnnotationMeta / @derive handler 路径。@derive 的 ts-gen 字符串拼接走 `gen_derive.ss` 独立路径(CALL 只处理 println / print / parseInt / emit / 泛型 / 用户函数);反射 metadata 访问走 MEMBER_ACCESS(已 D105 迁 `.fields()` / `.annotations()`)。R1/R3 对照 trivial PASS,本 Plan 无反射专章开销,对称 D107 继承

## 下一步(Plan 下的 Execute 顺序)

1. [x] Done — **Execute 0**(默认跳过):M7b bank +4 充裕,§新张力 1 未触发 → 跳过生效
2. [x] Done(commit 2c38819) — **Execute 1**:CALL 迁移 evalCall(对称 evalMethodCall / evalMemberAccess / evalPostfixInc 三段式) **+ 用户追加子目录全拆扩展(见 §扩展)**
   - **实测对照预估**(baseline = 9343330):
     - M7b 676 → 673 Δ=-3 实测命中(预估 -3)结构组 OK
     - N3 518111 → 515159 Δ=-2952 实测命中(预估 -2961~-3411 略偏浅)PROGRESS
     - M2 76126 → 76187 Δ=+61 实测命中(预估 +54~+94 中段)DRIFT
     - N2 380630 → 380935 Δ=+305 实测命中(预估 +270~+470)DRIFT
     - F1:gen_exprs.ss 1721 → 1271 Δ=-450 实测精确命中(预估 -450)PROGRESS
     - F1:eval_expr.ss 569 → 126 Δ=-443(子目录全拆扩展引入)
     - 14 项 + F1 全 OK/PROGRESS/DRIFT 窗内,GATE PASS
   - bootstrap stage2==stage3 PASS
   - 4 测试 pre-existing failed(spring_web_params / harness_task / d096_p4_l2_reactive / harness_bug),非 D108 引入(stash baseline 同样失败已验证)
   - **eval_expr.ss 末尾** 新建 `evalCall(astId: int): int`(~85 行,含 泛型 2 分支 + callPreRegs 三态 + args 循环 NAMED_ARG/SPREAD_ELEM/普通 3 分支 + comptime/runtime 分派 + 2 处 mv 编码 runtime 回退)
   - **eval_expr.ss evalExpr 头部** 新增 `if (k == "CALL") { return evalCall(astId) }` 分派
   - **gen_exprs.ss L132 shim** 扩 11 → 12 kind 加 `CALL`
   - **gen_exprs.ss** 删除原 L141-217 整块 77 行 inline(outer header + 泛型 + callPreRegs + args 3 分支 + comptime/runtime 分派 + `}`)
   - **R1 前对照**(baseline = commit 9343330):M7b=672 / N3=515552 / M2=76150 / N2=380750 / F1:gen_exprs.ss=1348,14 项 + F1 全 OK/PROGRESS/DRIFT 窗内
   - **R3 后对照预估**(相对 baseline):
     - M7b 676 → 673 Δ=-3(bank +4 → +3)结构组严格 OK
     - N3 515552 → 514700-515150 Δ=-2961~-3411(bank -2559 → -2961~-3411)结构组严格 PROGRESS(深窖新纪录)
     - M2 76126 → 76180-76220 Δ=+54~+94(累计组 DRIFT ±380 远内 4-7×)OK
     - N2 380630 → 380900-381100 Δ=+270~+470(累计组 DRIFT ±1903 远内 4-7×)OK/DRIFT
     - F1:gen_exprs.ss 1721 → ~1271 Δ=-450(单调下降累计 26.1% 压缩率)PROGRESS
     - 结构组 8 项 OK/PROGRESS / 累计组 6 项 OK/DRIFT / F1 PROGRESS
   - **bootstrap 固定点**:seed → stage1 → stage2 → stage3,stage2==stage3 验证
   - **test tests/**:期望与 D107 Execute 1 baseline 一致(213 passed / 4 pre-existing failed),非 D108 引入
   - **§新张力 1-10 验证**:
     - §新张力 1 M2/N2 膨胀非线性:Execute 1 实测与预估偏差 < 30% → 解除;否则修正系数入 D109
     - §新张力 2 泛型 callerId 跨边界:comptime 泛型 + runtime 泛型 + 嵌套泛型 3 场景单测
     - §新张力 3 2 处 raw constVal → mv 编码:git stash 反向 2 条路径字节级 IR 对比
     - §新张力 4 callPreRegs 三态保持:`f(g(h(x)))` + `f(...arr, g(x), h.i)` + 嵌套混合 3 场景单测
     - §新张力 5 user function inline:tests/ 泛型 suite 全绿
     - §新张力 6 SPREAD_ELEM 首验:`f(...arr)` / `comptime { f(...[1,2,3]) }` / `f(...obj.arr)` / `f(x, ...rest, y)` 4 场景单测
     - §新张力 7-10 函数攀升 / 跨文件 / DRIFT / 反射:bootstrap 固定点 + 全量测试 + reflection_health_linter GATE PASS
3. [ ] Planned — **Execute 2**:收尾评估(§步骤 2 决策矩阵条件「M7b 余量 ≥ +2 且 N3 bank < -2900」实测判断:M7b bank +3 ✓ / N3 bank -2952 ✓ → 默认**不 record**,延续银行策略至 Phase A 全完;支持 Phase A 末轮 2d NEW_EXPR)+ 下轮起 D109 Plan(2d NEW_EXPR 中量构造候选,zig 驱动 9 kind 末 1 kind)

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 扩展 — 子目录全拆(用户追加,Execute 1 同 commit 落地)

**触发**:Execute 1 首尝(单文件方案 evalCall 写到 `eval_expr.ss` 末尾)实测 `F1 bootstrap/eval_expr.ss cur=646 baseline=-1 → REGRESSION`(D102 §规则 2.1 R3 新文件 > 600 硬阻断)。Plan 设计漏估 evalCall 80 行加到 567 行 eval_expr.ss 后突破 R3 600 上限。

**用户追加方向**(message verbatim):
- "我认为应该改将eval_expr 里的每个大函数都独立为子目录的小文件 你觉得呢ultrathink"
- "子目录 / 一次全拆"

**实施**(同 commit 2c38819):

1. 新建 `bootstrap/eval/` 子目录,10 子函数各一文件:
   - `call.ss`(82 行,evalCall)/ `ternary.ss`(33)/ `short_circuit.ss`(32)/ `index_access.ss`(20)/ `template_lit.ss`(46)/ `array_lit.ss`(61)/ `ident.ss`(44)/ `member_access.ss`(126)/ `postfix_inc.ss`(32)/ `method_call.ss`(78)
   - 最大子文件 = 126,远低 R3 600 上限
2. `eval_expr.ss` 仅留 evalExpr 主 dispatch + UNARY/BINARY inline + 10 条 import,569 → 126 行
3. import 由 `eval_expr.ss`(non-baseline)承载,**不动 main.ss F1=630 baseline**(R1 守门规避)
4. `tools/dual_track_linter.ss` + `tools/reflection_health_linter.ss` 各 +1 行 `collectSSFiles("bootstrap/eval")` 扫子目录(`collectSSFiles` 用 `listDir` 平铺过滤 `.endsWith(".ss")`,子目录条目不含 `.ss` 被自动跳过,需显式追加调用)

**收益对照**:

| 项 | 单文件方案 | 子目录全拆方案 |
|---|---|---|
| eval_expr.ss F1 | 646(R3 阻断)| **126**(继续 ≤ 600 不入 baseline)|
| 子文件数 | 0 | 10 |
| 单文件最大 F1 | 646 | 126(member_access)|
| 后续单 kind 迁移空间 | 600 - 646 = 阻断 | 600 - 126 = **474 行余量**|
| Phase A 末轮 NEW_EXPR(53 行)落点 | 阻断 | 子目录新建 `eval/new_expr.ss` 一行不挤主文件 |
| 阅读熟悉度 | 1 文件 1271 行 | 11 文件均 < 130 行 |

**遗留(留 D109 或后续)**:

- `runtimeMv(s)` helper 抽取(Agent 2 #6,21 处 `0 - constVal(...) - 1` 散落,不在本次范围)
- `findCtVarKey(name)` helper 抽取(Agent 1 #1,4-5 处 ctScopeStack lookup 重复,预存在债务)
- `evalCallArgs` 抽取(Agent 1 #2,call.ss / method_call.ss 镜像 args 处理 ~30 行,留 D109)
- `collectSSFiles` 改递归(Agent 1 #4,需 `isDir` runtime API 或安全 `.ss` 后缀策略,留独立小 Plan)

## 参考

- D107 §步骤 1 evalMethodCall(对称三段式模板,callPreRegs 三态 + args NAMED_ARG/普通 2 分支)/ §步骤 2 决策矩阵(M7b +3 / N3 -2500 阈值,本 Plan 触发)/ Execute 1 实测(M7b -4 / N3 -2559 / M2 +24 / N2 +120 / F1 -373)/ §新张力 1-8(args 跨边界 / mv 编码 / 函数攀升 / 16 跨文件 / enum 触点 / DRIFT 生产验证 / POSTFIX_DEC 长期滞留 / super 状态泄漏)
- D106 §步骤 1 evalPostfixInc(对称三段式,首 scope write)/ §步骤 2 决策矩阵(POSTFIX_DEC bundle grep 推翻延续)
- D105 §步骤 1 evalMemberAccess(对称三段式,多触点迁移模板)/ §新张力 1(反射触点交叉干扰)
- D104 §步骤 1 evalIdent(scope 只读迁移模板)
- D103 §步骤 1 evalArrayLit(**SPREAD_ELEM 首次承载,Array 字面量展开**)/ D101 §步骤 1 evalTemplateLit / §新张力 1 mv 编码
- D100 §坑 Q(银行余量不 record)/ §坑 P(M2/N2 迁移成本模型)
- D102 §规则 1.1-1.4(分层 GATE + DRIFT 窗口 ±0.5%)/ §规则 2.1-2.3(F1 文件行数 GATE)
- D099 §坑 G-O(N3/M7b 成本模型)
- D098 §决策 1 MaybeVal Phase A mv 编码 / §决策 2 Phase B 类化(CALL dispatch + 泛型多态是 vtable 承载关键输入)
- D094 §决策 §规则 2 L109-110(CALL 不在 pure subset 白名单 — 可能 println/exit 副作用)/ L175(zig 驱动 9 kind CALL 在列,Phase A 目标)
- D088 §第一性需求(Zig 路线 SEMA 收敛一份 evalExpr)/ §正模式「一份 evalExpr 函数」/ §反模式(维持双轨制)
- CLAUDE.md §反射根因 gate(CALL 不触)/ §交互式单文档(含 ultrathink gate)/ §PFV 流程
- `memory/feedback_ultrathink_gate.md` / `memory/feedback_pfv_process.md` / `memory/feedback_reflection_root_cause_gate.md` / `memory/feedback_design_no_code_authority.md`(D107 §2b grep 推翻延续:CALL body 77 行实测 L141-217 非 D107 Plan 估 100 行 L141-214,以本 Plan grep 为准)/ `memory/feedback_no_workaround.md`(POSTFIX_DEC expr gap 不绕过延续)
- `bootstrap/gen_exprs.ss:141-217`(CALL 当前 inline 77 行,待迁)
- `bootstrap/gen_exprs.ss:218-270`(NEW_EXPR 53 行,D109 Plan 范围)
- `bootstrap/gen_exprs.ss:132`(L132 shim,D107 Execute 1 后 11 kind)
- `bootstrap/gen_exprs.ss:333`(ctCallDispatch comptime helper,保留,evalCall 内调用)
- `bootstrap/gen_calls.ss:8`(callPreRegs 全局声明)
- `bootstrap/gen_calls.ss:323`(genGenericCall runtime,保留)
- `bootstrap/gen_calls.ss:464`(genCall runtime,保留)
- `bootstrap/codegen.ss:19`(ctFuncNodes 全局声明)
- `bootstrap/codegen.ss:95`(genericFuncNodes 全局声明)
- `bootstrap/eval_expr.ss`(567 行,10 函数,D107 Execute 1 结果)
- `bootstrap/eval_expr.ss:252 / :263 / :289`(SPREAD_ELEM 首处承载于 evalArrayLit,D103 Execute 1)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt` @ D101 Execute 0 commit 9343330(F1 1721 / M7b 676 / N3 518111)
- `tools/next_prompt_ultrathink_linter.ss`(PFV §收尾 gate 第 3 步 (b) 机械 gate)
- `tests/phase5/d107_method_call_5cases.ss`(D107 §新张力 1 5 场景验证模板,D108 Execute 1 沿用补 SPREAD + 泛型场景)
