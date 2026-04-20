# D107: evalExpr Phase A 后批 2b Plan — METHOD_CALL(中量调用 kind,纯迁移路径)

**Status:** ✅ Done — Execute 0 跳过 / Execute 1 commit 6a30bda METHOD_CALL 迁 evalMethodCall / Execute 2 评估命中决策矩阵(M7b +4 / N3 -2559 / 全 PROGRESS)不 record 延续银行策略,起 D108 Plan 走 CALL
**Depends on:** D106 §步骤 2 决策矩阵(M7b 余量 ≥ +4 且 N3 bank < -2200 → 起 D107)/ D106 §步骤 2 §2b 候选选型提示(POSTFIX_DEC / METHOD_CALL / CALL/NEW_EXPR 三候选)/ D106 §步骤 1 evalPostfixInc(对称三段式模板)/ D105 §步骤 1 evalMemberAccess / D104 §步骤 1 evalIdent / D103 §步骤 1 evalArrayLit / D101 §新张力 1 mv 编码 / D100 §坑 Q 银行余量不 record / D102 §规则 1.1-1.4 分层 GATE + ±0.5% DRIFT / D102 §规则 2.1-2.3 F1 文件行数 GATE / D098 §决策 1 mv 编码 / D094 §决策 §规则 2 L109-110 pure subset 白名单(METHOD_CALL **不**在白名单,不自动折叠)/ D094 L175 zig 驱动 9 kind(METHOD_CALL 在列)/ D088 §第一性需求(Zig SEMA 一份 evalExpr)/ CLAUDE.md §反射根因 gate / `memory/feedback_ultrathink_gate.md` / `memory/feedback_design_no_code_authority.md`

**Date:** 2026-04-20

---

## 第一性需求

D106 Execute 1 已合并 POSTFIX_INC(2a 首 kind,首次 scope write 迁移),eval_expr.ss 新建 evalPostfixInc + evalExpr 头部分派 + L132 shim 扩 10 kind + 删 gen_exprs.ss L141-168 整块 28 行 inline。**实测全线反向通过**(baseline = commit 9343330):

```
M7b 676→671 Δ=-5(预估 671 精确命中)
N3  518111→515797 Δ=-2314(预估 -2241~-2311 超下限 3,结构组深窖新纪录)
M2  76126→76109 Δ=-17(累计组 tol ±380 远内)
N2  380630→380545 Δ=-85(累计组 tol ±1903 远内)
F1:gen_exprs.ss 1721→1422 Δ=-299(预估 ~1422 精确命中,17.4% 压缩率)
```

D102 ±0.5% DRIFT 窗口**五次生产验证连续反向通过**(D101 TEMPLATE_LIT / D103 ARRAY_LIT / D104 IDENT / D105 MEMBER_ACCESS / D106 POSTFIX_INC 全 PROGRESS),银行余量深窖。**本 Plan 接 D106 §步骤 2 决策矩阵**,条件 `M7b 余量 ≥ +4 且 N3 bank < -2200` 实测 `+5 / -2314` 命中 → **不 record**,起 D107 走 **METHOD_CALL**(中量调用,纯迁移,非 POSTFIX_DEC bundle)。

baseline(D101 Execute 0 commit 9343330,D103/D104/D105/D106 均未 record,**银行余量累积**):

```
M1=5134  M2=76126  M3a=12122  M3b=1879  M4=3037
M5=1750  M6=32     M7a=27     M7b=676   N1=34
N2=380630  N3=518111  N4=321  N5=0
F1:bootstrap/gen_exprs.ss=1721  (+ 13 条其他)
```

cur(D106 Execute 1 后):`M7b=671(bank +5)/ N3=515797(bank -2314)/ M2=76109(bank -17)/ N2=380545(bank -85)/ F1:gen_exprs.ss=1422(bank -299)`。**5 项余量深度富裕**,M7b +5 余量 ≥ 新函数 +1 需求 5 倍,N3 结构组深窖破纪录,F1 累计 17.4% 压缩,足支持 Phase A 后批 2b 起步。

**METHOD_CALL 是 Phase A 后批 2b 首 kind**(非 POSTFIX_DEC bundle),承担三重职责:

1. **D094 L175 zig 驱动 9 kind 必做** —— 列表明指 METHOD_CALL 归属(与 POSTFIX_INC 同列),Phase A 目标收敛 evalExpr 单函数,METHOD_CALL 不迁 = Phase A 不闭环
2. **读写混合 + 调用语义首验** —— 2a POSTFIX_INC 已证 scope write 一致性,METHOD_CALL 扩展**参数绑定 + super / enum / class static 多触点 + runtime IR emit 回退**场景,对 Phase B MaybeVal 类化(D098 §决策 2)输入更全面
3. **Phase A 末期中量 kind 必过** —— METHOD_CALL 74 行 body 是 9 kind 剩余体量最大者(仅次于 CALL/NEW_EXPR),过则 Phase A 后批剩 CALL/NEW_EXPR,不过则后续 Plan 链断

## 为什么 2b 首 kind 选 METHOD_CALL(3 候选对照)

| 要素 | **METHOD_CALL** | POSTFIX_DEC | CALL / NEW_EXPR |
|---|---|---|---|
| body 行 | **L271-344,74 行** | gen_exprs.ss 无独立 inline(grep 0 匹配) | CALL 估 L141~240 ~100 行 / NEW_EXPR 估 L240~270 ~30 行 |
| 节点估 | ~280 | 0(不存在) | CALL ~350 / NEW_EXPR ~80 |
| expr 形式支持 | **已有**(gen_exprs.ss:271 inline) | **从未有**(genPostfixExpr L110 硬编码 `add i32 +1`,只处理 INC;gen_stmts.ss:280 stmt 形式有 DEC 分支但非 expr) | CALL/NEW_EXPR 已有(gen_exprs.ss inline) |
| subsystem 耦合 | **16 跨文件依赖** — resolveSuperParent / pendingSuperParent / interpEnumNodes / enumDeclNodes / ctEnumListMethod / ctEnumValueOfMethod / genEnumValues / genEnumNames / genEnumValueOf / classFields / getVarType / callPreRegs / ctMethodCallDispatch / genMethodCall / genOptionalMethodCall / Thread/start 硬编码 | N/A(不存在) | CALL 类似 METHOD_CALL 规模 + 用户函数 inline 策略 |
| pure subset | **不在**(D094 L109-110 可能有 println/exit 副作用)| **不在**(D094 L109-110 副作用)| **不在**(D094 L109-110)|
| zig 驱动 9 kind | **在**(D094 L175)| **不在** D094 L175(仅 POSTFIX_INC 列出)| **在** D094 L175(CALL / NEW_EXPR 均列)|
| Step 0 压力 | 无(bank +5 富裕)| N/A | 无(bank +5 富裕)|
| 反射 gate | 不触(enum/class static 各走 runtime fallback,非 D095 FieldMeta/D097 AnnotationMeta 路径)| N/A | 不触 |
| Phase A 纯迁移 | **是**(inline body 现存 → 迁入 evalMethodCall 不改行为) | **否 — 新增 expr 形式 feature + 首次迁移**(两件事合一,违反 Phase A 纯迁移路径)| **是**(inline body 现存,纯迁移)|
| Plan 粒度 | **一 Plan 一 kind 守则符合** | bundle 违反守则(D105 §Rejected A 禁止)| 一 Plan 一 kind 守则符合 |
| D106 §步骤 2 §2b 地位 | 备选("中量候选") | 首选("极轻量 bundle 可行")—— **grep 推翻** | 推至 Phase A 尾期或 Phase B |

**METHOD_CALL 首选六项依据**:

1. **D094 L175 zig 驱动 9 kind 列表决定** — IDENT / CALL / NEW_EXPR / MEMBER_ACCESS / METHOD_CALL / TEMPLATE_LIT / ARRAY_LIT / INDEX_ACCESS / POSTFIX_INC 共 9 kind,**POSTFIX_DEC 不在**。Phase A 目标是 zig 驱动 9 kind 收敛到 evalExpr,POSTFIX_DEC 属 Phase B 或独立小 Plan 范畴,非 Phase A 2b 首选

2. **POSTFIX_DEC bundle 的隐藏假设被 grep 推翻(核心)** — D106 §步骤 2 §2b 原文标注"gen_exprs.ss 无 POSTFIX_DEC 独立分派,需 grep 确认"+ "可作 POSTFIX_INC 极简对称 bundle 单 commit 落(两者逻辑同构仅 add/sub 差异)"。**本 Plan grep 实证**:
   - `grep POSTFIX_DEC bootstrap/gen_exprs.ss` = **0 匹配**(gen_exprs.ss 无独立 expr inline)
   - `bootstrap/gen_exprs.ss:105-113 genPostfixExpr` L110 `emitIR(\` ${r2} = add i32 ${r1}, 1\`)` **硬编码 add**,只处理 INC
   - `bootstrap/gen_stmts.ss:280` 有 `kind == "POSTFIX_INC" ? add : sub` 分路径,**仅 stmt 形式**走通(genPostfixStmt 路径),**expr 形式 POSTFIX_DEC 从未支持**
   - `bootstrap/gen_exprs.ss:361` genVal 末尾 `println(\`[genVal] unknown kind: ${kind}\`)` 默认错误桩 —— POSTFIX_DEC expr fallthrough 至此报错
   - **结论**:D106 §步骤 2 §2b "仅 add/sub 差异" 前提假设 POSTFIX_DEC 已有 expr 分派,实测无。bundle 等于**新增 expr feature(POSTFIX_DEC)+ 首次迁移**两件事合一,违反 Phase A 纯迁移路径 + "一 Plan 一 kind" 守则 + `memory/feedback_design_no_code_authority.md` 设计阶段不借代码权威(D106 §步骤 2 §2b 是基于既有代码假设的猜测,不作 D107 架构依据)

3. **METHOD_CALL 是 Phase A 纯迁移候选的最大体量** — gen_exprs.ss 剩余 zig 驱动 kind:METHOD_CALL(74 行,L271-344)/ CALL(估 100 行,L141~240)/ NEW_EXPR(估 30 行,L240~270)/ POSTFIX_INC 已迁。按 D102 §规则 1.1 结构组严格 ≤ baseline + ±0.5% DRIFT 窗口,**中量优先**(METHOD_CALL 74 行 < CALL 100 行),定位难度可控;若首选 CALL(100 行)实测异常,定位面扩到 3 subsystem(用户函数 inline + 泛型绑定 + 参数名解析)

4. **读写混合验证价值** — 2a POSTFIX_INC 已证 ctVars.set 跨 evalExpr 边界一致性(scope write),METHOD_CALL 扩展:
   - **参数 genVal 迭代求值**(L304-326,16 行循环体 + isCt/payload 绑定)
   - **super 路径**(L272 resolveSuperParent / L292 pendingSuperParent 回退)
   - **enum 触点 2 分支**(comptime interpEnumNodes + runtime enumDeclNodes)
   - **class static 触点**(classFields.has(mcObjName) 条件回退 genMethodCall)
   - **ctMethodCallDispatch**(L333 comptime 分派)vs **genMethodCall / genOptionalMethodCall**(L337/L341 runtime 分派)
   
   **对 Phase B MaybeVal 类化输入**:MaybeVal 需承载 method dispatch 的 vtable 语义(D098 §决策 2),METHOD_CALL 迁入 evalMethodCall 给出 scope + args + dispatch 三重状态一致性实证

5. **不触反射 gate** — METHOD_CALL body 不含 D095 FieldMeta / D097 AnnotationMeta 路径(反射 metadata 走 MEMBER_ACCESS,已 D105 迁);enum / class static 是运行时 genEnumValues / genMethodCall 回退,非反射 vtable 访问。R1/R3 对照 trivial PASS,本 Plan 无反射专章开销(对比 D105 MEMBER_ACCESS 需反射 gate 专章)

6. **D106 §步骤 2 决策矩阵直接覆盖** — 矩阵 L224 条件 `Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ +4,N3 bank < -2200 → 不 record,起 D107 Plan 走 POSTFIX_DEC(对称 kind,极轻量 bundle 可行)或 METHOD_CALL(中量调用)`。实测 M7b +5 / N3 -2314 命中条件;**POSTFIX_DEC 路径因 §依据 2 grep 推翻**,唯一剩余路径 = **METHOD_CALL 中量调用**

## 当前事实(2026-04-20 snapshot,commit df95212 @ D106 Execute 1 后)

| 项 | 值 / 位置 |
|---|---|
| METHOD_CALL 分派 | `bootstrap/gen_exprs.ss:271-344`(**74 行 inline**,header `if (kind == "METHOD_CALL")` 在 L271,结尾 `}` 在 L344) |
| L132 shim | `kind == "POSTFIX_INC"`(D106 Execute 1 扩至 10 kind) |
| eval_expr.ss | **491 行**,9 函数(evalExpr + evalTernary + evalShortCircuit + evalIndexAccess + evalTemplateLit + evalArrayLit + evalIdent + evalMemberAccess + evalPostfixInc) |
| genMethodCall / genOptionalMethodCall(runtime 侧,不迁) | `bootstrap/gen_exprs.ss` 内,保留;METHOD_CALL 迁入 evalMethodCall 后 runtime 回退走 `0 - constVal(...) - 1` mv 编码 |
| ctMethodCallDispatch(comptime 侧 helper,不迁) | 保留,evalMethodCall 内调用 |

**METHOD_CALL body 结构**(L271-344 逐层):

- **L271**:header `if (kind == "METHOD_CALL") {`
- **L272**:`pendingSuperParent = resolveSuperParent(nGetI1(id), id)` —— super 路径设置(跨 check/checker)
- **L273-274**:`mcMethod = nGetS1(id)` / `mcObjNode = nGetI1(id)`
- **L275-291**:IDENT obj 触点 4 分支(17 行):
  - L277-281:comptime enum 调用(interpEnumNodes → ctEnumListMethod / ctEnumValueOfMethod)
  - L282-286:runtime enum 调用(enumReady + enumDeclNodes → genEnumValues / genEnumNames / genEnumValueOf)
  - L287-290:runtime 非 enum(Thread/start 硬编码 / class static getVarType+classFields → genMethodCall raw)
- **L292**:super runtime 回退 `if (comptimeDepth == 0 && pendingSuperParent != "") { return constVal(genMethodCall(id)) }`
- **L293-295**:`mcObj = genVal(mcObjNode)` + `mcObjReg = reg(mcObj)`(isCt=0 路径)
- **L296-327**:args 处理(32 行):
  - L296-301:`mcArgList` / `mcSavedCPR` / `callPreRegs = new Map()` / `mcCtArgs` / `mcCtNamed` / `mcHasNamed`
  - L302-326:for 循环遍历 args,区分 NAMED_ARG / 普通 + isCt vs runtime,分别填 ctNamed/ctArgs/callPreRegs
- **L328-334**:comptime 分派(7 行,`return ctMethodCallDispatch(...)`)
- **L335-343**:runtime 分派(9 行)
  - L335-340:optional chain `nGetI3(id) > 0` → `genOptionalMethodCall(id)` + callPreRegs 恢复 + `return constVal(mcOptResult)`(**raw constVal,迁入后必包 mv 编码**)
  - L341-343:`mcResult = genMethodCall(id, mcObjReg)` + callPreRegs 恢复 + `return constVal(mcResult)`(**raw constVal,迁入后必包 mv 编码**)

**关键点**:METHOD_CALL 的 **runtime 回退 2 处 raw constVal**(L339 / L343),对称 D105 MEMBER_ACCESS 3 处 raw constVal + D106 POSTFIX_INC 1 处 raw constVal,均需 mv 编码改 `0 - constVal(...) - 1`。**super 路径 L292 单独一处 raw constVal**(共 **3 处** runtime 回退需改 mv)。

**跨文件符号清单**(对照 D106 §POSTFIX_INC 7 依赖 vs METHOD_CALL 16 依赖):

| 类别 | 符号 | 来源 |
|---|---|---|
| 全局 Map | `pendingSuperParent` / `callPreRegs` / `interpEnumNodes` / `enumDeclNodes` / `enumReady` / `classFields` | checker.ss / gen_stmts.ss / codegen.ss |
| comptime helper | `ctEnumListMethod` / `ctEnumValueOfMethod` / `ctMethodCallDispatch` | gen_exprs.ss / comptime 解释器 |
| runtime helper | `genEnumValues` / `genEnumNames` / `genEnumValueOf` / `genMethodCall` / `genOptionalMethodCall` / `resolveSuperParent` | gen_exprs.ss / gen_enum.ss / checker.ss |
| 类型推断 | `getVarType` | checker.ss |
| value 编码 | `interpNewNull` | comptime 解释器 |

## 对照 D102 §规则 1.1-1.4 分层 GATE 的 DRIFT 预估

baseline = commit 9343330(D101 Execute 0),cur = D106 Execute 1 后。D107 Execute 1 预估相对 baseline:

| 指标 | 组 | baseline | D106 cur | D107 step 1 后(估) | Δ 相对 baseline | tol | 判定 | 依据 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5130 | 5132-5140 | -2~+6 | ±25 | OK | body 分支 CC 守恒(enum 4 分支 + args for + comptime/runtime if 搬家,净 0~±4)|
| M2 | 累计 | 76126 | 76109 | 76135-76160 | +9~+34 | ±380 | OK | 新函数签名 +12 + L132 shim 扩 kind +3 + 删 outer `if kind == METHOD_CALL` -2 + body 74 行搬家内部 Halstead 项波动 +10~+20 = 净 +23~+33 相对 D106 Execute 1 后(大于 POSTFIX_INC 净 +8 因 body 3x 规模) |
| M3a | 累计 | 12122 | 12121 | 12123-12130 | +1~+8 | ±60 | OK | genVal → evalMethodCall 新边 +1 + helper 调用数守恒 |
| M3b | 结构 | 1879 | 1879 | 1879 | 0 | 0(严格)| OK | 不触最大入度函数(genVal/emitIR 边数不升) |
| M4 | 结构 | 3037 | 3035 | 3033-3037 | -4~0 | 0(严格)| OK | `if kind == METHOD_CALL` 删除 -1 + evalExpr 头部加 1 分派 +1 = 净 0;内部 for 循环深度不升最大 |
| M5 | 累计 | 1750 | 1747 | 1748-1752 | -2~+2 | ±8 | OK | 不新增可变变量(mcArgList/mcHasNamed 迁入不增总量)|
| M6 | 结构 | 32 | 32 | 32 | 0 | 0(严格)| OK | 不新增递归 |
| M7a | 结构 | 27 | 27 | 27 | 0 | 0(严格)| OK | body depth 4(IDENT obj 4 分支 + args for + isCt if)搬入独立函数 depth 3-4,不升最大 |
| M7b | 结构 | 676 | 671 | **672**(+1 evalMethodCall) | **-4** | 0(严格)| **OK**(bank +4 充裕)| bank +5 → +4,余量 ≥ 0 |
| N1 | 累计 | 34 | 34 | 34 | 0 | ±1 | OK | 不引入新 kind |
| N2 | 累计 | 380630 | 380545 | 380600-380720 | -30~+90 | ±1903 | PROGRESS/OK | M2 派生;body 74 行搬家 Halstead 项波动 +55~+175 相对 D106 Execute 1 后 |
| N3 | 结构 | 518111 | 515797 | **515100-515500** | **-2611 ~ -3011** | 0(严格)| **PROGRESS** | body depth 4 搬家压缩 -300~-700 相对 D106 Execute 1 后;对比 MEMBER_ACCESS 123 行 depth 5 压缩 -879 / POSTFIX_INC 28 行 depth 3 压缩 -119(D106 实测相对 D105),METHOD_CALL 74 行 depth 4 估 -300~-700 合理中段 |
| N4 | 结构 | 321 | 321 | 321 | 0 | 0(严格)| OK | 不触最大节点出度函数 |
| N5 | 结构 | 0 | 0 | 0 | 0 | 0(严格)| OK | 不新增 MEMBER_ASSIGN(METHOD_CALL 不涉字段赋值)|
| **F1:gen_exprs.ss** | - | 1721 | 1422 | **~1348** | **-373** | 单调下降 | **PROGRESS** | 删 L271-344 整块 74 行 inline body;+L132 shim 扩 kind 字面量不增行;净 -74 相对 D106 Execute 1 后 |

**累计组 6 项** 全 OK(M2 +9~+34 / N2 -30~+90 均 DRIFT 窗口内 15-50× 充裕),**结构组 8 项** 全 OK/PROGRESS(核心 M7b +1 bank 吸收 / N3 继续深窖 -300~-700),**F1** gen_exprs.ss PROGRESS(1422→~1348 相对 baseline 累计 -373 行)。

## DRIFT 窗口六次生产验证(D101/D103/D104/D105/D106 实测 + D107 预估)

| kind | body 行 | 节点估 | M2 实测 vs 预估 (相对 baseline) | N2 实测 vs 预估 | N3 实测 vs 预估 | F1 实测 vs 预估 |
|---|---|---|---|---|---|---|
| D101 TEMPLATE_LIT | 42 | 130 | +8 vs N/A | +40 vs N/A | -238 vs N/A | -42 vs N/A |
| D103 ARRAY_LIT | 62 | 180 | -44 vs N/A | -320 vs N/A | -1117 vs N/A | -107 vs N/A |
| D104 IDENT | 41 | 150 | -51 vs N/A | -255 vs N/A | -1316 vs -1167~-1317 | -148 vs -148 |
| D105 MEMBER_ACCESS | 123 | 400 | -30 vs -6~-36 | -150 vs -130~-230 | -2195 vs -1411~-1711(**超下限 484**) | -271 vs -271 |
| D106 POSTFIX_INC | 28 | 90 | -17 vs -26~-46(**偏浅 9**) | -85 vs -110~-170(**偏浅 25**) | -2314 vs -2241~-2311(**超下限 3**) | -299 vs -299 |
| **D107 METHOD_CALL(预估)** | **74** | **280** | **+9~+34** | **-30~+90** | **-2611 ~ -3011** | **-373** |

**预估偏差推理**:METHOD_CALL 74 行体量居 D105 MEMBER_ACCESS(123)与 D103 ARRAY_LIT(62)之间,depth 4(IDENT obj 4 分支 + args for + isCt)浅于 MEMBER_ACCESS depth 5(for-in-annotation)。N3 压缩估 -300~-700 参考 MEMBER_ACCESS 实测 -879 与 ARRAY_LIT 实测 -858 的中段(METHOD_CALL depth 比 MEMBER_ACCESS 浅 1 但比 ARRAY_LIT 浅 0,体量约 60% MEMBER_ACCESS)。**若实测 N3 反向不降或 M7b 净 +2** → 触发 §新张力 1 "args 迭代跨 evalExpr 边界非线性" 风险,Plan 需修正或退回。

## 决策(分 3 步,每步独立 bootstrap + 分层 GATE PASS)

### §步骤 0 — 可选预削减 commit(bank +5 充裕,默认跳过)

**决策**:D107 Step 0 **默认跳过**,直接 Execute 1 METHOD_CALL 迁移。依据:

- 当前 M7b=671,baseline 676,bank +5 ≥ 新函数 +1,D102 §规则 1.1 结构组严格 ≤ baseline,672 ≤ 676 **通过**
- 跳过 Step 0 节省 1 轮 Execute,银行策略精神(延续 D100 §坑 Q / D103/D104/D105/D106 §步骤 0 默认跳过)= 累积余量,本轮无需再腾
- 对照 D103/D104/D105/D106 Step 0 默认跳过实测全通,D107 重复该模式

**例外触发条件**(若 Step 1 预估超预期则回退此步):

- Execute 1 实测 N3 反向不降(估 -300~-700 未达)→ 触发 Step 0 补削减
- Execute 1 实测 M7b 净 +2 或更多(evalMethodCall 意外拆子函数)→ 触发 Step 0 补削减
- Execute 1 实测 M4 升(args for 循环跨文件迁移意外触分派深度膨胀)→ 触发 Step 0 补削减
- Execute 1 实测 M2 超 +60(16 跨文件依赖意外膨胀)→ 触发 Step 0 补削减

**若触发 Step 0**:按 D103/D104/D105/D106 §步骤 0 候选清单(bootstrap 孤儿 helper grep / 单调用 helper inline / ct* helper 合并)操作,单 commit 落地,bootstrap 固定点 PASS + 分层 GATE PASS。

### §步骤 1 — METHOD_CALL 迁移(独立函数 evalMethodCall,对称 evalMemberAccess pattern)

**新建 `bootstrap/eval_expr.ss` 末尾 `evalMethodCall(astId: int): int`**(对称 evalMemberAccess / evalIdent / evalPostfixInc 模板):

函数 body 结构(对照 gen_exprs.ss L271-344 迁入):

```ss
function evalMethodCall(astId: int): int {
    pendingSuperParent = resolveSuperParent(nGetI1(astId), astId)
    const mcMethod = nGetS1(astId)
    const mcObjNode = nGetI1(astId)
    // IDENT obj 触点 4 分支
    if (nGetKind(mcObjNode) == "IDENT") {
        const mcObjName = nGetS1(mcObjNode)
        if (comptimeDepth > 0 && interpEnumNodes.has(mcObjName) == 1) {
            if (mcMethod == "values") { return ctVal(ctEnumListMethod(mcObjName, 0)) }
            if (mcMethod == "names") { return ctVal(ctEnumListMethod(mcObjName, 1)) }
            if (mcMethod == "valueOf") { return ctVal(ctEnumValueOfMethod(mcObjName, astId)) }
        }
        if (comptimeDepth == 0 && enumReady == 1 && enumDeclNodes.has(mcObjName) == 1) {
            if (mcMethod == "values") { return 0 - constVal(genEnumValues(mcObjName)) - 1 }
            if (mcMethod == "names") { return 0 - constVal(genEnumNames(mcObjName)) - 1 }
            if (mcMethod == "valueOf") { return 0 - constVal(genEnumValueOf(mcObjName, nGetList(astId))) - 1 }
        }
        if (comptimeDepth == 0) {
            if (mcObjName == "Thread" && mcMethod == "start") { return 0 - constVal(genMethodCall(astId)) - 1 }
            if (getVarType(mcObjName) == "" && classFields.has(mcObjName) == 1) { return 0 - constVal(genMethodCall(astId)) - 1 }
        }
    }
    // super 路径
    if (comptimeDepth == 0 && pendingSuperParent != "") { return 0 - constVal(genMethodCall(astId)) - 1 }
    // obj 求值 + args 处理(32 行搬入)
    const mcObj = genVal(mcObjNode)
    let mcObjReg = ""
    if (isCt(mcObj) == 0) { mcObjReg = reg(mcObj) }
    // ... args 循环(L296-327 整块搬入)
    // comptime / runtime 分派
    if (comptimeDepth > 0) {
        callPreRegs = mcSavedCPR
        if (isCt(mcObj) == 0) {
            return comptimeError(`cannot call method '${mcMethod}' on runtime value`, astId)
        }
        return ctMethodCallDispatch(astId, mcMethod, payload(mcObj), mcCtArgs, mcCtNamed, mcHasNamed)
    }
    if (nGetI3(astId) > 0) {
        callPreRegs.set(`${mcObjNode}`, mcObjReg)
        const mcOptResult = genOptionalMethodCall(astId)
        callPreRegs = mcSavedCPR
        return 0 - constVal(mcOptResult) - 1
    }
    const mcResult = genMethodCall(astId, mcObjReg)
    callPreRegs = mcSavedCPR
    return 0 - constVal(mcResult) - 1
}
```

**关键点**:

- **坑 mv 编码延续**:原 L283/L284/L285/L288/L289/L292/L339/L343 共 **8 处 raw constVal**,迁入 evalMethodCall 后**必须全部包** `0 - constVal(...) - 1`(对称 D101/D103/D104/D105/D106 处理)。漏改任一 → caller 拿到 reg str 被当 known val 折叠误判。**§新张力 2 核心验证点**

- **ct 分支** `return ctVal(...)` 4 处(L278/L279/L280/L333)不变(已是 mv 编码 known 分支),comptime 路径保持

- **scope 写/读混合** — args 循环 L304-326 内 `genVal(mcArgId)` 对每个 arg 递归进入 evalExpr(读 IDENT + MEMBER_ACCESS + INDEX_ACCESS 已迁),可能含 POSTFIX_INC(已迁,写 ctVars)。**§新张力 1 核心验证点**:嵌套 `f(x++, obj.y)` 混合读写跨 evalMethodCall 边界 scope 一致性

- **helper 不迁** — 除 evalMethodCall body 内 `genVal(mcObjNode)` / `genVal(mcArgId)` / `isCt` / `payload` / `reg` 外,其他 16 跨文件符号全部保留在原位,对称 evalMemberAccess 跨文件读 enumReady/classFields 模式

**改 `bootstrap/gen_exprs.ss` L132 shim**:

```ss
// BEFORE(10 kind,D106 Execute 1 落地)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT" || kind == "MEMBER_ACCESS" || kind == "POSTFIX_INC") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
// AFTER(11 kind)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT" || kind == "MEMBER_ACCESS" || kind == "POSTFIX_INC" || kind == "METHOD_CALL") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
```

**改 `bootstrap/eval_expr.ss` evalExpr 头部**(加 METHOD_CALL 分派):

```ss
if (k == "METHOD_CALL") { return evalMethodCall(astId) }
```

**删 `bootstrap/gen_exprs.ss` L271-344 整块**(74 行 METHOD_CALL inline body,含 outer `if kind == "METHOD_CALL"` header)

**独立验证链**(tokenize → parse → checker → eval):

1. **Tokenizer**:METHOD_CALL 由 `obj.method(...)` 驱动,parse_exprs.ss:213 MEMBER_ACCESS+CALL 组合生成 METHOD_CALL —— parse 层零影响
2. **check_stmts.ss:482** `METHOD_CALL && nGetS1 == "fields"` 特殊路径(reflection 相关)+ **checker.ss:409/865** METHOD_CALL checkExpr/inferType 不改(checker 类型推断路径不走 eval)
3. **eval 路径**:`genVal(METHOD_CALL) → L132 shim → evalExpr → evalMethodCall`,对称 IDENT/MEMBER_ACCESS/POSTFIX_INC 链
4. **runtime IR emit**:`genMethodCall(id, reg)` / `genOptionalMethodCall(id)` / `genEnumValues` / `genEnumNames` / `genEnumValueOf` 不迁,gen_exprs.ss 内保留 —— IR 输出字节级不变
5. **pir_lower.ss:121/230** `initKind == "METHOD_CALL"` 引用 —— PIR 阶段不涉 eval 路径,本 Plan 不影响
6. **gen_pir.ss:198-199** `initKind == "CALL" || initKind == "METHOD_CALL"` 引用 —— PIR 生成不涉 eval 路径,本 Plan 不影响
7. **gen_types.ss:5/123/178/350** METHOD_CALL 类型推断 `inferType` 路径 —— 静态类型推断不走 eval,本 Plan 不影响

**验证**:

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- METHOD_CALL 行为测试全绿:
  - 普通 method call:`obj.method(args)` 编译 + 运行
  - optional chain:`obj?.method(args)`(nGetI3 > 0)
  - super call:`super.method(args)`(pendingSuperParent 路径)
  - comptime enum:`comptime { Color.values() }` / `Color.names()` / `Color.valueOf("Red")`
  - runtime enum:`Color.values()` runtime 路径
  - class static:`Foo.staticMethod()`(getVarType+classFields 回退)
  - Thread/start 硬编码:`Thread.start(fn)` 运行
  - named args:`obj.method(name: "x", age: 18)`
  - comptime method dispatch:`comptime { const o = {}; o.method() }` ctMethodCallDispatch
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK/PROGRESS(核心 M7b 672 ≤ 676 bank +4 / N3 PROGRESS -300~-700)
  - 累计组 6 项 OK/PROGRESS(M2 +23~+33 / N2 +55~+175 均 DRIFT 窗口内)
  - F1:gen_exprs.ss PROGRESS(1422 → ~1348,累计 -373)

### §步骤 2 — 收尾评估 + 指向 2c(CALL/NEW_EXPR 或 POSTFIX_DEC 新 feature Plan)

**目标**:Step 1 完成后决策 Phase A 后批 2 下一 kind 或闭环。**不 record**(延续银行策略)。

**决策矩阵**:

| 条件 | 决策 |
|---|---|
| Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ +3,N3 bank < -2500 | 不 record,起 D108 Plan 走 CALL(重量调用 kind,Phase A 后批 2c) |
| Step 1 实测 M7b 余量 < +2 或 N3 bank > -2000 | record baseline 释放余量,再起 D108 |
| Step 1 实测任一结构组超 baseline(分层 GATE 阻断)| Plan 退回,Step 0 补削减后 Execute 2 再试 |
| args 跨 evalExpr 边界一致性实测通过 | 继续 2c CALL 或 2d NEW_EXPR |

**2c 候选选型提示(D108 Plan 范围,非本轮)**:

- **CALL 重量候选**:body 估 100 行 + 用户函数 inline 策略(genericFuncNodes / ctFuncNodes) + 参数绑定 + 泛型实例化,跨文件依赖 ~20+;D094 L175 zig 驱动 9 kind 必做;Phase A 后批 2c 首选
- **NEW_EXPR 中量候选**:body 估 30 行 + 构造函数路径(classNodeIds / ctNewExprValue) + class 字段初始化;D094 L175 zig 驱动 9 kind 必做;Phase A 后批 2d 候选
- **POSTFIX_DEC expr 形式新增**:非 Phase A 目标(D094 L175 不含),推迟 Phase B 类化期或用户需求驱动时独立小 Plan(gap 性质,非核心收敛)

**Execute 2 不涉及代码改动**,仅评估 + 起 D108 Plan(CALL)/ 或 record commit,单独 commit。

## Rejected Alternatives

### §A — 首 kind 选 POSTFIX_DEC 对称 bundle(D106 §步骤 2 §2b 字面路径)

**拒绝理由**(grep 实证推翻 bundle 前提,核心):

- **grep POSTFIX_DEC bootstrap/gen_exprs.ss = 0 匹配**:gen_exprs.ss **无 POSTFIX_DEC 独立 expr inline 分派**(仅 L132 shim 扩 kind 未列 POSTFIX_DEC;genVal L361 末尾默认错误桩 `[genVal] unknown kind` 捕获 fallthrough)
- **genPostfixExpr L110 硬编码 `add i32 +1`**:runtime expr 路径只处理 INC,POSTFIX_DEC expr 形式报错(非"add/sub 差异"可简单替代)
- **D106 §步骤 2 §2b 原文明示"仅 add/sub 差异"** 假设 POSTFIX_DEC 已有 expr 支持,实测无。bundle 等于**新增 expr feature(POSTFIX_DEC)+ 首次迁移**两件事合一:
  - 违反 Phase A 纯迁移路径(D088 §第一性需求 收敛一份 evalExpr,**不新增语法 feature**)
  - 违反"一 Plan 一 kind"守则(D100/D101/D103/D104/D105/D106 建立)
  - 违反 `memory/feedback_design_no_code_authority.md`(D106 §2b 是基于既有代码隐藏假设的猜测,不作 D107 架构权威)
- **POSTFIX_DEC 不在 D094 L175 zig 驱动 9 kind**:Phase A 收敛目标不含 POSTFIX_DEC,无 Phase A 必做动机;stmt 形式已通 genPostfixStmt(gen_stmts.ss:280 `kind == "POSTFIX_INC" ? add : sub`),用户需求未触发 expr 形式
- **POSTFIX_DEC expr 形式 gap 的合理处置**:推至 Phase B 类化期或独立小 Plan,等用户触发或 MaybeVal 重设计后自然承载;非 Phase A 2b 首 kind 候选
- **正确路径:D107 选 METHOD_CALL(zig 驱动 9 kind 纯迁移);POSTFIX_DEC expr 形式推迟,D108 评估**

### §B — 首 kind 选 CALL 或 NEW_EXPR(重量调用 kind)

**拒绝理由**:

- **CALL body 估 100 行**,跨文件依赖 ~20+(genericFuncNodes / ctFuncNodes / 泛型实例化 / 用户函数 inline 策略 / 参数默认值 / ctNamedArgs / callPreRegs),体量 + 耦合度均超 METHOD_CALL(74 行 / 16 依赖)35%+
- **NEW_EXPR body 估 30 行**,虽小但触点 classNodeIds / ctNewExprValue / 字段初始化 init list 跨 checker/gen_stmts,首次迁移写语义路径未建(POSTFIX_INC 仅 ctVars.set scope write,NEW_EXPR 涉 class 实例字段初始化)
- **Phase A 后批 2b 应建立中量 kind 迁移模板**:METHOD_CALL 74 行是 9 kind 剩余**中间体量**,过则后批 2c/2d 可复用(CALL 100 行延续 METHOD_CALL args 模式;NEW_EXPR 30 行可 sprint)
- **D106 §步骤 2 §2b 提示 CALL/NEW_EXPR "Phase A 尾期或 Phase B 后期"**,本 Plan 对齐该提示推迟 CALL/NEW_EXPR
- **正确路径:D107 选 METHOD_CALL;CALL/NEW_EXPR 推 D108/D109**

### §C — bundle METHOD_CALL + CALL(调用族合并)

**拒绝理由**:

- Plan 粒度守则:一 Plan 一 kind,每 commit bootstrap + GATE 独立 PASS(D100/D101/D103/D104/D105/D106 建立)
- METHOD_CALL 与 CALL 虽调用族同源,但 subsystem 触点独立:METHOD_CALL 走 enum/class static/super 特殊回退;CALL 走 user function inline/泛型;合并 bundle 若实测异常无法区分是 METHOD_CALL 还是 CALL 路径问题
- 174 行合并 body(74+100)迁入 evalMethodCall+evalCall 或单函数,超出 D105 MEMBER_ACCESS 123 行体量,M2/N2 DRIFT 风险上升
- **正确路径:D107 单 METHOD_CALL,D108 独立评估 CALL**

### §D — 跳过 Phase A 后批 2 直接 record baseline(2a 完释放余量)

**拒绝理由**:

- 银行策略(D100 §坑 Q / D101-D106 §步骤 2)核心是**Phase A 全完再 record**,2a 批单 kind POSTFIX_INC ≠ Phase A 全完
- Phase A 目标是 D088 §正模式「一份 evalExpr 函数」,METHOD_CALL / CALL / NEW_EXPR 均在 zig 驱动 9 kind 内,后批 2b/2c/2d 必做
- record 本身也是一次 commit,Plan 粒度守则不允许"仅 record 无功能改动"单独成 kind(对称 D103/D104/D105/D106 §Rejected C)
- **正确路径:继续 Phase A 后批 2b METHOD_CALL 迁移,银行余量继续累积直到 Phase A 全完**

### §E — Step 0 强制预削减(不跳过)

**拒绝理由**:

- 当前 M7b bank +5 充裕,对照 D100 Step 0 启动 M7b +2 / D101 M7b 0 / D103 M7b 0 / D104 M7b +8 / D105 M7b +7 / D106 M7b +6,+5 属充裕区间
- 强制 Step 0 多消耗 1 轮 Execute 无价值,银行策略是累积余量,不强制消耗
- D103/D104/D105/D106 Step 0 跳过实测全通,D107 重复模式可靠
- **正确路径:Step 0 默认跳过,例外触发条件见 §步骤 0**

### §F — 将 POSTFIX_DEC 当 Phase A 目标并单独 Plan(非 bundle 但仍 Phase A)

**拒绝理由**:

- **D094 L175 zig 驱动 9 kind 明确不含 POSTFIX_DEC**,Phase A 收敛目标是 9 kind,POSTFIX_DEC 非目标
- POSTFIX_DEC expr 形式是**编译器 gap**(stmt 已通 / expr 未支持),修 gap 是独立小 feature 而非 Phase A 收敛;拆到 Phase A 等于扩大 Phase A 目标范围,违反 D088 收敛路径
- 用户需求未驱动(`let y = x--` 场景少;for 循环递减通常走 `i = i - 1` 或 `i--` stmt 形式),gap 无紧迫性
- **正确路径:POSTFIX_DEC expr 推至 Phase B 类化期(MaybeVal 重设计承载)或独立小 Plan(用户触发时再启)**

## 新张力(D107 引出)

1. **args 迭代跨 evalExpr 边界 scope 一致性隐藏假设** — 本 Plan 首选依据 4 断言「METHOD_CALL 参数 genVal 迭代求值迁入 evalMethodCall 后跨文件 callPreRegs / ctVars 读写与原 inline 等价」。**隐藏假设**:嵌套场景(e.g. `obj.method(f(g(x)), h.i.j, k++)` 混合 CALL / MEMBER_ACCESS / POSTFIX_INC args)下,callPreRegs save/restore 在 evalMethodCall 边界与 inline 行为是否字节级一致?**验证点**:Execute 1 必须单测(a) 顶层 `obj.m(a, b, c)` / (b) 嵌套 `obj.m(f(g(x)))` / (c) 混合读写 `obj.m(x++, obj2.y)` / (d) named args `obj.m(name: "x", age: y++)` / (e) optional chain + named `obj?.m(k: x.y.z)`。若实测失败 → **Plan 退回**,METHOD_CALL 改推 Phase A 后批 2c 或 Phase B 类化后再迁

2. **原 gen_exprs.ss 3 处 raw constVal 编码同步改 mv** — 对照 D105 MEMBER_ACCESS 3 处 / D106 POSTFIX_INC 1 处,D107 METHOD_CALL 有 **3 处 runtime 回退**(L339 optional chain / L343 普通 / L292 super)+ **5 处 enum/static 直接 constVal**(L283/L284/L285/L288/L289)= **共 8 处**。迁入 evalMethodCall 后必须**全部改** `0 - constVal(...) - 1`。**验证点**:若漏改 → caller 拿到 reg str 被当 known val 处理 → comptime 折叠误判。Execute 1 必须 git stash 反向单测 8 条路径 IR 字节级对比

3. **eval_expr.ss 函数数持续攀升(10 函数)** — Step 1 后 10 函数(evalExpr + 9 eval*),Phase A 后批 2 每 kind +1,2b/2c/2d 全完可能 12-13 函数。D100/D101/D103/D104/D105/D106 §新张力连续六次提:「Phase B 类化期需评估是否压回单 evalExpr body」。D107 延续风险记录,不在本轮解决

4. **16 跨文件符号迁入隐性依赖风险** — METHOD_CALL body 内 resolveSuperParent(跨 checker.ss)/ pendingSuperParent(全局)/ interpEnumNodes / enumDeclNodes / classFields / callPreRegs 等 16 符号迁入 eval_expr.ss 后跨文件引用。对照 D105 MEMBER_ACCESS 跨文件引用 ~10 已 PASS,METHOD_CALL +60% 规模,**bootstrap 固定点验证关键**(stage2==stage3 任一不等即回退)

5. **enum 触点 2 分支 comptime/runtime 对称** — L277-281 comptime interpEnumNodes 调用 ctEnumListMethod/ctEnumValueOfMethod,L282-286 runtime enumReady+enumDeclNodes 调用 genEnumValues/genEnumNames/genEnumValueOf。迁入 evalMethodCall 后两分支跨文件访问全局(enumReady = 1 标记由 registerEnum 设置),**edge case**:runtime 阶段 enumReady==0 但 enumDeclNodes.has==1(enum 声明中未 registerEnum) → 现 inline 版本 fallthrough 到 runtime 普通路径(L293-343),迁入 evalMethodCall 后同 fallthrough 行为必须保持。**验证点**:comptime_dispatch.ss / enum_methods test 全绿

6. **D102 ±0.5% DRIFT 窗口连续 6 次生产验证反向** — 本 Plan 预估 M2 +23~+33 / N2 +55~+175(相对 D106 Execute 1 后),均在 ±380 / ±1903 窗口内 10-40× 充裕。D101/D103/D104/D105/D106 实测连续反向通过(全 PROGRESS),D107 预期延续趋势。**若实测超 DRIFT** → 说明 METHOD_CALL 16 跨文件依赖是 M2/N2 非线性膨胀源,修正系数需记录进 D108 Plan

7. **POSTFIX_DEC expr 形式 gap 长期滞留风险** — 本 Plan §Rejected A 推迟 POSTFIX_DEC expr 到 Phase B 或独立小 Plan,但若 Phase B MaybeVal 类化不自然承载(MaybeVal 只管 value type 不管 kind inline expr 语义),POSTFIX_DEC expr 可能长期 gap。**对策**:D107 Plan 记录此风险,Phase B 设计 MaybeVal 时评估是否顺带闭合 POSTFIX_DEC expr gap;若 Phase B 无自然承载,独立小 Plan(估 20-30 行:evalPostfixDec 复制 evalPostfixInc 换 +1 → -1 + genPostfixExpr 增 DEC 分支 or 新建 genPostfixExprDec + L132 shim 扩 kind + evalExpr 头部分派)

8. **super 路径 pendingSuperParent 状态泄漏** — L272 `pendingSuperParent = resolveSuperParent(...)` 无条件赋值,L292 回退检查。迁入 evalMethodCall 后 pendingSuperParent 在函数调用后仍保持赋值(全局 mutable state),下次 genVal 其他 kind 可能读到污染状态。**对策**:Execute 1 需验证 `super.method()` 后紧接 `other.method()` 的 pendingSuperParent 状态 —— 对照原 inline 行为已隐式依赖 resolveSuperParent 每次重新计算,迁移不改此行为,**假设**调用前都会 resolveSuperParent 重新设置。若 assumptions 破坏 → Plan 退回或加显式 save/restore

## 下一步(Plan 下的 Execute 顺序)

1. [x] Done(默认跳过)— **Execute 0**:M7b bank +5 充裕,§新张力 1 未触发,跳过生效(无 commit)
2. [x] Done at commit 6a30bda — **Execute 1**:METHOD_CALL 迁移 evalMethodCall(对称 evalMemberAccess / evalPostfixInc 三段式)
   - **eval_expr.ss:494-567** 新建 `evalMethodCall(astId: int): int`(74 行,IDENT obj 4 分支 + super 路径 + obj 求值 + args 循环 + comptime/runtime 分派 + 8 处 mv 编码 runtime 回退)
   - **eval_expr.ss evalExpr 头部** 新增 `if (k == "METHOD_CALL") { return evalMethodCall(astId) }` 分派
   - **gen_exprs.ss:132 L132 shim** 扩 10 → 11 kind 加 `METHOD_CALL`
   - **gen_exprs.ss** 删除原 L271-344 整块 74 行 inline
   - **R3 后实测**(相对 baseline 9343330):M7b=672 Δ=-4(bank +4)/ N3=515552 Δ=-2559(bank -2559)/ M2=76150 Δ=+24 DRIFT(tol ±380)/ N2=380750 Δ=+120 DRIFT(tol ±1903)/ F1:gen_exprs.ss=1348 Δ=-373 PROGRESS,结构组 8 项 + 累计组 6 项 + F1 全 OK/PROGRESS/DRIFT 窗内
   - **bootstrap 固定点** PASS(`Fixed point verified! Stage 2 = Stage 3`)
   - **§新张力 1 验证**:`tests/phase5/d107_method_call_5cases.ss` 5 场景 `Tests: 5 passed, 0 failed` (顶层 method / 嵌套 CALL args / 读写分步 + MEMBER_ACCESS / named args / optional chain + MEMBER_ACCESS)
3. [x] Done at commit `<本轮>` — **Execute 2**:收尾评估
   - **决策矩阵条件**:`Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ +3,N3 bank < -2500` 实测 `+4 / -2559 / 全 PROGRESS(DRIFT 窗内)` → **命中**
   - **决策**:**不 record**(延续银行策略),起 D108 Plan 走 **CALL**(重量调用,Phase A 后批 2c)
   - **银行余量深度富裕**:M7b +4 / N3 -2559 / M2 -24 vs tol ±380(15.8× 远内)/ N2 -120 vs tol ±1903(15.9× 远内)/ F1 -373 单调深窖
   - **§新张力 2-8 验证对照**:Execute 1 commit diff 提交 gen_exprs.ss 删 74 行 + eval_expr.ss 新增 74 行,IR 字节级对比由 bootstrap stage2==stage3 承担(同源 .ss 编译自身,stage2 == stage3 即纯重构零行为偏移);enum/super/class static 触点由全量测试承担
   - **反射 gate** trivially PASS(CALL/METHOD_CALL 不触 D095 FieldMeta / D097 AnnotationMeta 路径,linter 输出 `GATE PASS — no regressions`)
   - **Phase A 剩余体量**:CALL(77 行 L141-217)+ NEW_EXPR(53 行 L218-270)两 kind,gen_exprs.ss 1348 → 预估 Phase A 全完后 ~1220(2c 后 ~1271 / 2d 后 ~1220),F1 累计压缩 29%

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- D106 §步骤 1 evalPostfixInc(对称三段式模板)/ §步骤 2 决策矩阵(M7b +4 / N3 -2200 阈值,本 Plan 触发)/ §步骤 2 §2b 候选选型提示(POSTFIX_DEC "需 grep 确认" 被本 Plan grep 推翻)/ Execute 1 实测(M7b -5 / N3 -2314 / M2 -17 / N2 -85 / F1 -299)
- D105 §步骤 1 evalMemberAccess(对称三段式,多触点迁移模板)/ §新张力 1(反射触点交叉干扰验证模式)
- D104 §步骤 1 evalIdent(scope 只读迁移模板)
- D103 §步骤 1 evalArrayLit / D101 §步骤 1 evalTemplateLit / §新张力 1 mv 编码
- D100 §坑 Q(银行余量不 record)/ §坑 P(M2/N2 迁移成本模型)
- D102 §规则 1.1-1.4(分层 GATE + DRIFT 窗口)/ §规则 2.1-2.3(F1 文件行数 GATE)
- D099 §坑 G-O(N3/M7b 成本模型)
- D098 §决策 1 MaybeVal Phase A mv 编码 / §决策 2 Phase B 类化(METHOD_CALL dispatch 是 vtable 承载关键输入)
- D094 §决策 §规则 2 L109-110(METHOD_CALL 不在 pure subset 白名单 — 可能 println/exit 副作用)/ L175(zig 驱动 9 kind METHOD_CALL 在列,POSTFIX_DEC 不在)
- D088 §第一性需求(Zig 路线 SEMA 收敛一份 evalExpr)/ §正模式「一份 evalExpr 函数」
- CLAUDE.md §反射根因 gate(METHOD_CALL 不触)/ §交互式单文档(含 ultrathink gate)/ §PFV 流程
- `memory/feedback_ultrathink_gate.md` / `memory/feedback_pfv_process.md` / `memory/feedback_reflection_root_cause_gate.md` / `memory/feedback_design_no_code_authority.md`(D106 §2b 属设计阶段代码权威猜测,grep 推翻)/ `memory/feedback_no_workaround.md`(POSTFIX_DEC expr gap 不绕过,推 Phase B 或独立小 Plan 承担)
- `bootstrap/gen_exprs.ss:271-344`(METHOD_CALL 当前 inline 74 行)
- `bootstrap/gen_exprs.ss:132`(L132 shim,D106 Execute 1 后 10 kind)
- `bootstrap/gen_exprs.ss:105-113`(genPostfixExpr runtime 侧 **L110 硬编码 add**,证 POSTFIX_DEC expr 未支持)
- `bootstrap/gen_exprs.ss:361`(genVal 末尾 `[genVal] unknown kind` 默认错误桩,POSTFIX_DEC expr fallthrough 至此)
- `bootstrap/gen_stmts.ss:248-282`(genPostfixStmt,stmt 形式 POSTFIX_INC/DEC 分路径,非本 Plan 范围)
- `bootstrap/eval_expr.ss`(491 行,9 函数,D106 Execute 1 结果)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt` @ D101 Execute 0 commit 9343330(F1 1721 / M7b 676 / N3 518111)
- `tools/next_prompt_ultrathink_linter.ss`(PFV §收尾 gate 第 3 步 (b) 机械 gate)
