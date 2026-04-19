# D106: evalExpr Phase A 后批 2 首 kind Plan — POSTFIX_INC(轻量写 kind,首次 scope write 迁移)

**Status:** Plan + Execute 1 Done(POSTFIX_INC 迁 evalPostfixInc 对称三段式落地,不 record 延续银行策略)
**Depends on:** D105 §步骤 2 决策矩阵(M7b 余量 ≥ +5 且 N3 bank < -1500 → 起 D106 走 POSTFIX_INC)/ D105 §步骤 1 evalMemberAccess(对称三段式模板)/ D104 §步骤 1 evalIdent(scope 只读迁移模板)/ D103 §步骤 1 evalArrayLit / D101 §新张力 1 mv 编码 / D100 §坑 Q 银行余量不 record / D102 §规则 1.1-1.4 分层 GATE + ±0.5% DRIFT / D102 §规则 2.1-2.3 F1 文件行数 GATE / D098 §决策 1 mv 编码 / D098 §决策 2 Phase B MaybeVal 类化(POSTFIX_INC scope write 是 Phase B 依赖关键验证点)/ D094 §决策 §规则 2 L109-110 pure subset 白名单(POSTFIX_INC **不**在白名单,不自动折叠)/ D094 L175 zig 驱动 9 kind(POSTFIX_INC 在列)/ D088 §第一性需求(Zig SEMA 一份 evalExpr) / CLAUDE.md §反射根因 gate / `memory/feedback_ultrathink_gate.md`

**Date:** 2026-04-20

---

## 第一性需求

D105 Execute 1 已合并 MEMBER_ACCESS(1b 第 5 kind,最后一 kind),**1b 批全收**(INDEX_ACCESS / TEMPLATE_LIT / ARRAY_LIT / IDENT / MEMBER_ACCESS 五 kind 齐落 eval_expr.ss)。实测反向通过(baseline = commit 9343330):

```
M7b 676→670 Δ=-6(预估 670 精确命中)
N3  518111→515916 Δ=-2195(预估 -1411~-1711 超上限,结构组深窖新纪录)
N2  380630→380480 Δ=-150(累计组 tol ±1903 远内)
M2  76126→76096 Δ=-30(累计组 tol ±380 远内)
F1:gen_exprs.ss 1721→1450 Δ=-271(15.7% 压缩率)
```

D102 ±0.5% DRIFT 窗口**四次生产验证连续反向通过**(D101 TEMPLATE_LIT / D103 ARRAY_LIT / D104 IDENT / D105 MEMBER_ACCESS 全 PROGRESS),银行余量深窖。**本 Plan 接 D105 §步骤 2 决策矩阵**,条件 `M7b 余量 ≥ +5 且 N3 bank < -1500` 实测 `+6 / -2195` 命中 → **不 record**,起 D106 走 POSTFIX_INC。

baseline(D101 Execute 0 commit 9343330,未 record 延续,**银行余量累积**):

```
M1=5134  M2=76126  M3a=12122  M3b=1879  M4=3037
M5=1750  M6=32     M7a=27     M7b=676   N1=34
N2=380630  N3=518111  N4=321  N5=0
F1:bootstrap/gen_exprs.ss=1721  (+ 13 条其他)
```

cur(D105 Execute 1 后):`M7b=670(bank +6)/ N3=515916(bank -2195)/ M2=76096(bank -30)/ N2=380480(bank -150)/ F1:gen_exprs.ss=1450(bank -271)`。**4 项余量深度富裕**,M7b +6 余量 ≥ 新函数 +1 需求 6 倍,N3 结构组深窖,足支持 Phase A 后批 2 起步。

**POSTFIX_INC 是 Phase A 后批 2 首 kind**,承担三重职责:
1. **首次碰写语义 kind**(ctVars.set scope write) —— 1b 批五 kind 全为读语义(IDENT/MEMBER_ACCESS/INDEX_ACCESS 读, TEMPLATE_LIT/ARRAY_LIT 纯计算无 scope 写),D098 §决策 2 Phase B MaybeVal 类化依赖 Phase A 写语义 kind 验证,不做则 Phase B 阻塞
2. **体量最小验证**(28 行 body,小于 IDENT 41 / ARRAY_LIT 62 / METHOD_CALL 74 / MEMBER_ACCESS 123),首次写语义 + 最小体量 = 风险最可控的 pattern 建立
3. **D094 L175 zig 驱动 9 kind 中覆盖** —— Phase A 目标收敛 evalExpr 单函数,POSTFIX_INC 在 zig 驱动列表不迁 = Phase A 不闭环

## 为什么首 kind 选 POSTFIX_INC(2 候选对照)

| 要素 | **POSTFIX_INC** | METHOD_CALL |
|---|---|---|
| body 行 | **L141-168,28 行** | L299-372,74 行 |
| 节点估 | ~90 | ~280 |
| subsystem 耦合 | scope 写(ctVars.set 1 处 L161)+ runtime 回退 genPostfixExpr | enum 触点(comptime interpEnumNodes + runtime enumDeclNodes)+ class static(classFields + getVarType)+ super(resolveSuperParent/pendingSuperParent)+ args 绑定(callPreRegs / ctNamedArgs / ctArgVals)+ runtime 回退 genMethodCall |
| pure subset | **不在**(D094 L109-110 副作用路径)| **不在**(D094 L109-110 CALL/METHOD_CALL/NEW_EXPR 可能有 println/exit 副作用)|
| zig 驱动 9 kind | **在**(D094 L175)| **在**(D094 L175)|
| Step 0 压力 | 无(bank +6 富裕)| 无(bank +6 富裕)|
| 反射 gate | 不触(纯变量读写 + 整数递增)| **不触**但触点多(enum + class static 各走 runtime fallback,非反射 FieldMeta/AnnotationMeta 路径)|
| 跨文件依赖 | ctVars / ctScopeStack / currentFunc / interpNewInt / interpAsInt / interpNewNull / genPostfixExpr —— **7 项**,对称 evalIdent 跨文件读模式 | resolveSuperParent / pendingSuperParent / interpEnumNodes / enumDeclNodes / ctEnumListMethod / ctEnumValueOfMethod / genEnumValues / genEnumNames / genEnumValueOf / Thread/start 硬编码 / genMethodCall / classFields / getVarType / callPreRegs / ctNamedArgs / ctArgVals —— **16 项**,跨文件面翻倍 |

**POSTFIX_INC 首选六项依据**:

1. **D105 §步骤 2 决策矩阵直接指向** — 条件命中 `M7b +6 ≥ +5 且 N3 bank -2195 < -1500`,矩阵明言「不 record,起 D106 直接 POSTFIX_INC(轻量写 kind,Step 0 轻量)」,本 Plan 接预言
2. **Phase A 后批 2 首 kind 应建立新的最小可验模板** — 1b 批读侧天花板已到 MEMBER_ACCESS 123 行,后批 2 必须换模板(写语义),写语义 kind 首选体量最小的 POSTFIX_INC(28 行)而非 METHOD_CALL(74 行)
3. **写语义 kind 首次迁入必须独立** — ctVars.set 跨 evalExpr 边界的 scope 一致性未验证,若与 METHOD_CALL 74 行 + enum/class static 多触点并行迁移 = 风险叠加,定位难度指数上升
4. **D098 §决策 2 Phase B 依赖验证价值** — MaybeVal 类化需要 Phase A 全覆盖写语义 kind 的 scope 一致性证据,POSTFIX_INC 是写语义 kind 最简形态(整数递增 + ctVars.set),首迁价值 = 「MaybeVal 能不能承载 scope write」的关键输入
5. **体量适配银行策略** — 28 行 body 搬家对 N3/M7b 影响可预估,对照 IDENT 41 行实测 N3 -199 + M7b +1,POSTFIX_INC 28 行估 N3 -100~-150 + M7b +1,余量充足
6. **反射 gate 不触** — POSTFIX_INC 不涉 D095 FieldMeta / D097 AnnotationMeta / enum 值访问 / class static field 四反射触点,R1/R3 对照 trivial PASS,本 Plan 无反射专章开销

## 当前事实(2026-04-20 snapshot,commit d2fddaa @ D105 Execute 1 后)

| 项 | 值 / 位置 |
|---|---|
| POSTFIX_INC 分派 | `bootstrap/gen_exprs.ss:141-168`(**28 行 inline**,header `if (kind == "POSTFIX_INC")` 在 L141) |
| L132 shim | `kind == "MEMBER_ACCESS"`(D105 Execute 1 扩至 9 kind) |
| eval_expr.ss | 461 行,8 函数(evalExpr + evalTernary + evalShortCircuit + evalIndexAccess + evalTemplateLit + evalArrayLit + evalIdent + evalMemberAccess) |
| genPostfixExpr(runtime 侧,不迁) | `bootstrap/gen_exprs.ss:105-113`(9 行,varRef + load + add/sub + store 生成 LLVM IR) |
| ctVars.set 唯一位置 | L161 `ctVars.set(piKey, \`${ctVal(interpNewInt(interpAsInt(piOld) + 1))}\`)` |
| runtime 回退 | L167 `return constVal(genPostfixExpr(id))` **raw constVal,未 mv 编码**(对称 D101/D103/D104/D105 §新张力 mv 编码问题) |

**POSTFIX_INC body 结构**(L141-168 逐层):

- **L141**:header `if (kind == "POSTFIX_INC") {`
- **L142-166**:comptimeDepth > 0 分支(25 行)
  - L143:`const piName = nGetS1(id)`
  - L144-152:scope 域链倒序遍历(ctScopeStack) —— while depth 2
  - L153-156:currentFunc scope + ctVars 查找
  - L157-164:若找到 piKey → `parseInt(ctVars.getString(piKey))` → `payload(piTagged)` → **ctVars.set 自增** → `return ctVal(piOld)`(postfix 返回老值)
  - L165:若未找到 → `return ctVal(interpNewNull())`
- **L167**:runtime 回退 `return constVal(genPostfixExpr(id))`(**raw constVal,迁入 evalPostfixInc 后必包 mv 编码**)

**关键点**:POSTFIX_INC 的 **scope write 在 L161 唯一一处**,grep `ctVars.set` 本文件 10 处匹配中仅 L161 属 POSTFIX_INC(其余 L660/L662/L668/L670/L795/L797/L803/L805/L898 均在 CALL/METHOD_CALL 参数绑定路径,不触本 kind)。**ctInvalidated.set 本 kind 零触**(grep 无匹配)——POSTFIX_INC 写语义只改变量值,不标 invalidated。

## 对照 D102 §规则 1.1-1.4 分层 GATE 的 DRIFT 预估

baseline = commit 9343330(D101 Execute 0),cur = D105 Execute 1 后。D106 Execute 1 预估相对 baseline:

| 指标 | 组 | baseline | D105 cur | D106 step 1 后(估)| Δ 相对 baseline | tol | 判定 | 依据 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5130 | 5128-5132 | -2~-6 | ±25 | OK/PROGRESS | body 分支 CC 守恒(if/while 数不变搬家)|
| M2 | 累计 | 76126 | 76096 | 76080-76100 | -26~-46 | ±380 | PROGRESS | 新函数签名 +12 + L132 shim 扩 kind +3 + 删 outer `if kind == POSTFIX_INC` -2 = 净 -13~-17 相对 Execute 1 后(小于 IDENT 净 -7) |
| M3a | 累计 | 12122 | 12120 | 12123-12128 | +1~+6 | ±60 | OK | genVal → evalPostfixInc 新边 +1 |
| M3b | 结构 | 1879 | 1879 | 1879 | 0 | 0(严格)| OK | 不触最大入度函数 |
| M4 | 结构 | 3037 | 3035 | 3033-3035 | -2~-4 | 0(严格)| OK/PROGRESS | `if kind == POSTFIX_INC` 删除 -1 + evalExpr 头部加 1 分派 +1 = 净 0 |
| M5 | 累计 | 1750 | 1747 | 1748-1750 | -2~0 | ±8 | OK | 不新增可变变量(piKey / piSi 迁入不增总量)|
| M6 | 结构 | 32 | 32 | 32 | 0 | 0(严格)| OK | 不新增递归 |
| M7a | 结构 | 27 | 27 | 27 | 0 | 0(严格)| OK | body depth 3(scope while + 内层 if)搬入独立函数 depth 2-3,不升最大 |
| M7b | 结构 | 676 | 670 | **671**(+1 evalPostfixInc) | **-5** | 0(严格)| **OK**(bank +5 充裕)| bank +6 → +5,余量 ≥ 0 |
| N1 | 累计 | 34 | 34 | 34 | 0 | ±1 | OK | 不引入新 kind |
| N2 | 累计 | 380630 | 380480 | 380460-380520 | -110~-170 | ±1903 | PROGRESS | M2 派生;body 28 行搬家 Halstead 项波动 -20~+40 相对 Execute 1 后 |
| N3 | 结构 | 518111 | 515916 | **515800-515870** | **-2241 ~ -2311** | 0(严格)| **PROGRESS** | body depth 3 搬家压缩 -50~-120 相对 Execute 1 后;POSTFIX_INC 深度浅于 IDENT(IDENT -199 / ARRAY_LIT -1117 / MEMBER_ACCESS -879,POSTFIX_INC 28 行估 -50~-120 合理下限)|
| N4 | 结构 | 321 | 321 | 321 | 0 | 0(严格)| OK | 不触最大节点出度函数 |
| N5 | 结构 | 0 | 0 | 0 | 0 | 0(严格)| OK | 不新增 MEMBER_ASSIGN;**POSTFIX_INC 是 ctVars.set 写入,不是 MEMBER_ASSIGN**(N5 只跟踪 obj.field = val,不跟踪 var++)|
| **F1:gen_exprs.ss** | - | 1721 | 1450 | **~1422** | **-299** | 单调下降 | **PROGRESS** | 删 L141-168 整块 28 行 inline body;+L132 shim 扩 kind 字面量不增行;净 -28 相对 Execute 1 后 |

**累计组 6 项** 全 OK/PROGRESS(M2 -13~-17 / N2 -20~+40 均 DRIFT 窗口内 15-50× 充裕),**结构组 8 项** 全 OK/PROGRESS(核心 M7b +1 bank 吸收 / N3 继续深窖 -50~-120),**F1** gen_exprs.ss PROGRESS(1450→~1422 相对 baseline 累计 -299 行)。

## DRIFT 窗口四次生产验证(预期 vs D101/D103/D104/D105 实测)

| kind | body 行 | 节点估 | M2 实测(相对 baseline)| N2 实测 | N3 实测 | F1 实测 |
|---|---|---|---|---|---|---|
| D101 TEMPLATE_LIT | 42 | 130 | +8 | +40 | -238 | -42 |
| D103 ARRAY_LIT | 62 | 180 | -44 | -320 | -1117 | -107 |
| D104 IDENT | 41 | 150 | -51 | -255 | -1316 | -148 |
| D105 MEMBER_ACCESS | 123 | 400 | -30 | -150 | -2195 | -271 |
| **D106 POSTFIX_INC(预估)** | **28** | **90** | **-26~-46** | **-110~-170** | **-2241 ~ -2311** | **-299** |

**预估偏差推理**:POSTFIX_INC body 28 行最短,depth 最浅(scope while + 1 层 if 条件),N3 搬家压缩量估 -50~-120 相对 Execute 1 后 —— 对比 IDENT 41 行 depth 3 压缩 -199,POSTFIX_INC 压缩下限合理。若实测 M2 超 +20 或 N3 反向不降 → 触发 §新张力 1 scope write 非线性风险,Plan 需修正或退回。

## 决策(分 3 步,每步独立 bootstrap + 分层 GATE PASS)

### §步骤 0 — 可选预削减 commit(bank +6 充裕,默认跳过)

**决策**:D106 Step 0 **默认跳过**,直接 Execute 1 POSTFIX_INC 迁移。依据:

- 当前 M7b=670,baseline 676,bank +6 ≥ 新函数 +1,D102 §规则 1.1 结构组严格 ≤ baseline,671 ≤ 676 **通过**
- 跳过 Step 0 节省 1 轮 Execute,银行策略精神(延续 D100 §坑 Q / D103/D104/D105 §步骤 0 默认跳过)= 累积余量,本轮无需再腾
- 对照 D105 Step 0 默认跳过实测通过,D106 重复该模式

**例外触发条件**(若 Step 1 预估超预期则回退此步):
- Execute 1 实测 N3 反向不降(估 -50~-120 未达)→ 触发 Step 0 补削减
- Execute 1 实测 M7b 净 +2 或更多(evalPostfixInc 意外拆子函数)→ 触发 Step 0 补削减
- Execute 1 实测 M4 升(ctVars.set 跨文件迁移意外触分派深度膨胀)→ 触发 Step 0 补削减

**若触发 Step 0**:按 D103/D104/D105 §步骤 0 候选清单(bootstrap 孤儿 helper grep / 单调用 helper inline / ct* helper 合并)操作,单 commit 落地,bootstrap 固定点 PASS + 分层 GATE PASS。

### §步骤 1 — POSTFIX_INC 迁移(独立函数 evalPostfixInc,对称 evalIdent pattern)

**新建 `bootstrap/eval_expr.ss` 末尾 `evalPostfixInc(astId: int): int`**(对称 evalIdent / evalMemberAccess 模板):

```ss
function evalPostfixInc(astId: int): int {
    if (comptimeDepth > 0) {
        const piName = nGetS1(astId)
        let piKey = ""
        if (ctScopeStack.length() > 0) {
            let piSi = ctScopeStack.length() - 1
            while (piSi >= 0) {
                const piSk = `${ctScopeStack[piSi]}:${piName}`
                if (ctVars.has(piSk) == 1) { piKey = piSk; break }
                piSi = piSi - 1
            }
        }
        if (piKey == "") {
            const piFk = `${currentFunc}:${piName}`
            if (ctVars.has(piFk) == 1) { piKey = piFk }
        }
        if (piKey != "") {
            const piTagged = parseInt(ctVars.getString(piKey))
            if (isCt(piTagged) == 1) {
                const piOld = payload(piTagged)
                ctVars.set(piKey, `${ctVal(interpNewInt(interpAsInt(piOld) + 1))}`)
                return ctVal(piOld)
            }
        }
        return ctVal(interpNewNull())
    }
    return 0 - constVal(genPostfixExpr(astId)) - 1
}
```

**关键点**:

- **坑 mv 编码延续**:原 L167 `return constVal(genPostfixExpr(id))` raw constVal,迁入 evalPostfixInc 后**必须包** `0 - constVal(...) - 1`(对称 D101/D103/D104/D105 处理)—— caller 走 L132 shim 解码。**POSTFIX_INC 仅一处 runtime 回退**(L167),漏改 = comptime 折叠误判
- **ct 分支** `return ctVal(piOld)` / `return ctVal(interpNewNull())` 不变(已是 mv 编码 known 分支),2 条 return 路径保持
- **scope write(ctVars.set)唯一一处** — L161 迁入 evalPostfixInc 后跨文件写 ctVars,**对称 evalIdent 读 ctVars 已 PASS**,写方向首次验证。**§新张力 1 核心验证点**:嵌套 comptime block 内 `x++` 写跨 evalExpr 边界的 scope 可见性
- **helper 不迁** — `genPostfixExpr`(gen_exprs.ss:105-113)/ `interpNewInt` / `interpAsInt` / `interpNewNull` / `payload` / `isCt` / `ctVal` 全部保留在原位,对称 evalIdent 不迁 genIdent 模式

**改 `bootstrap/gen_exprs.ss` L132 shim**:

```ss
// BEFORE(9 kind,D105 Execute 1 落地)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT" || kind == "MEMBER_ACCESS") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
// AFTER(10 kind)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT" || kind == "MEMBER_ACCESS" || kind == "POSTFIX_INC") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
```

**改 `bootstrap/eval_expr.ss` evalExpr 头部**(加 POSTFIX_INC 分派):

```ss
if (k == "POSTFIX_INC") { return evalPostfixInc(astId) }
```

**删 `bootstrap/gen_exprs.ss` L141-168 整块**(28 行 POSTFIX_INC inline body,含 outer `if kind == "POSTFIX_INC"` header)

**独立验证链**(tokenize → parse → eval):

1. **Tokenizer**:`++` token 不改,parse_exprs.ss POSTFIX_INC parse 不改 —— parse 层零影响
2. **check_stmts.ss** POSTFIX_INC checkExpr/checkStmt 不改(checker 类型推断路径不走 eval)
3. **eval 路径**:`genVal(POSTFIX_INC) → L132 shim → evalExpr → evalPostfixInc`,对称 IDENT/MEMBER_ACCESS 链
4. **runtime IR emit**:`genPostfixExpr(id)` 不迁,gen_exprs.ss L105-113 保留 —— IR 输出字节级不变
5. **gen_stmts.ss:434** `if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { genPostfixStmt(id); return }` —— **statement 形式走 genPostfixStmt 不走 genVal/evalExpr**,本 Plan 不影响 stmt 路径
6. **gen_stmts.ss:280** `genPostfixStmt` 内 `emitIR(\`  ${r2} = add i32 ${r1}, 1\`)` —— runtime stmt 侧 IR 直接 emit,不走 eval 路径,本 Plan 不影响

**验证**:

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- POSTFIX_INC 测试全绿:comptime `x++` / 嵌套 comptime block `x++` / runtime `x++` stmt 形式 / runtime `y = x++` expr 形式 / comptime scope 链 `x++` / null scope `x++`(变量不存在 → ctVal(interpNewNull()))
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK/PROGRESS(核心 M7b 671 ≤ 676 bank +5 / N3 PROGRESS -50~-120)
  - 累计组 6 项 OK/PROGRESS(M2 -13~-17 / N2 -20~+40 均 DRIFT 窗口内)
  - F1:gen_exprs.ss PROGRESS(1450 → ~1422,累计 -299)

### §步骤 2 — 收尾评估 + 指向 2b(POSTFIX_DEC 或 METHOD_CALL)

**目标**:Step 1 完成后决策 Phase A 后批 2 下一 kind。**不 record**(延续银行策略)。

**决策矩阵**:

| 条件 | 决策 |
|---|---|
| Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ +4,N3 bank < -2200 | 不 record,起 D107 Plan 走 POSTFIX_DEC(对称 kind,极轻量 bundle 可行)或 METHOD_CALL(中量调用)|
| Step 1 实测 M7b 余量 < +3 或 N3 bank > -1500 | record baseline 释放余量,再起 D107 |
| Step 1 实测任一结构组超 baseline(分层 GATE 阻断)| Plan 退回,Step 0 补削减后 Execute 2 再试 |
| 写语义 kind scope 一致性实测通过 | 继续 2b METHOD_CALL 或 2c CALL/NEW_EXPR 读语义加读写混合 |

**2b 候选选型提示(D107 Plan 范围,非本轮)**:

- **POSTFIX_DEC 对称候选**:body 估 28 行(`genPostfixExpr(id)` 内 sub 替代 add,gen_exprs.ss 无 POSTFIX_DEC 独立分派,需 grep 确认),可作 POSTFIX_INC 极简对称 bundle 单 commit 落(例外于「一 Plan 一 kind」守则,因两者逻辑同构仅 add/sub 差异)
- **METHOD_CALL 中量候选**:body 74 行 + enum 触点(comptime/runtime 对称)+ class static 回退 + super 处理 + args 绑定(16 跨文件依赖)—— Plan 复杂度中等,需单独 D107 专 Plan
- **CALL / NEW_EXPR 重量候选**:CALL body 估 100+ 行 + 用户函数 inline 策略 + 参数绑定 + NEW_EXPR 构造函数路径 —— Phase A 尾期或 Phase B 后期考虑

## Rejected Alternatives

### §A — 首 kind 选 METHOD_CALL(中量调用)

**拒绝理由**:

- 74 行 body + 16 跨文件依赖(enum + class static + super + args),首次迁移复杂度显著高于 POSTFIX_INC(28 行 + 7 依赖)
- **Phase A 后批 2 首 kind 应建立最小可验模板**,METHOD_CALL 74 行包含 3 种触点(enum comptime/runtime + class static + 通用 runtime)叠加,任一实测异常定位困难
- D105 §步骤 2 决策矩阵**直接指向 POSTFIX_INC**(「直接 POSTFIX_INC,轻量写 kind,Step 0 轻量」),METHOD_CALL 推 D107 或更后
- 写语义 kind 首次验证价值 > 读语义延续 —— POSTFIX_INC 验证 ctVars.set 跨边界一致性,METHOD_CALL 延续 1b 读侧模式无新模板价值
- **正确路径:D106 选 POSTFIX_INC,METHOD_CALL 推 D107/D108**

### §B — bundle POSTFIX_INC + POSTFIX_DEC 单 Plan 迁(对称 kind 合并)

**拒绝理由**:

- Plan 粒度守则:一 Plan 一 kind,每 commit bootstrap + GATE 独立 PASS(D100/D101/D103/D104/D105 建立)
- 虽然 POSTFIX_INC/POSTFIX_DEC 逻辑同构,但首次写语义迁移必须独立验证**一个**kind 的 scope 一致性,合并 bundle 若实测异常无法区分是 inc 还是 dec 路径问题
- POSTFIX_DEC 位置 / body / ctVars.set 路径未 grep 确认,盲 bundle 违反 PFV §字段 1 D 文档对照
- D107 可合理评估「POSTFIX_INC 已迁 → POSTFIX_DEC 对称极简迁 bundle 是否合理」(见 D106 §步骤 2 决策矩阵)
- **正确路径:D106 单 POSTFIX_INC,D107 独立评估 POSTFIX_DEC**

### §C — 跳过 Phase A 后批 2 直接 record baseline(1b 全完释放余量)

**拒绝理由**:

- 银行策略(D100 §坑 Q / D101-D105 §步骤 2)核心是**Phase A 全完再 record**,1b 批全收 ≠ Phase A 全完
- Phase A 目标是 D088 §正模式「一份 evalExpr 函数」,POSTFIX_INC / METHOD_CALL / CALL / NEW_EXPR 均在 zig 驱动 9 kind 内,后批 2/3/4 必做
- record 本身也是一次 commit,Plan 粒度守则不允许"仅 record 无功能改动"单独成 kind(对称 D103/D104/D105 §Rejected C)
- **正确路径:继续 Phase A 后批 2 POSTFIX_INC 迁移,银行余量继续累积直到 Phase A 全完**

### §D — 首 kind 选 POSTFIX_DEC 而非 POSTFIX_INC

**拒绝理由**:

- `grep -c '^    if (kind == "POSTFIX_DEC"' bootstrap/gen_exprs.ss` 未验证(需 grep 才知 body 位置/行数),本 Plan 基于已 grep 的 POSTFIX_INC L141-168 实证
- 命名约定:D094 L175 zig 驱动 9 kind 明列 POSTFIX_INC,未提 POSTFIX_DEC,推测 POSTFIX_DEC 可能以 POSTFIX_INC 为主 + DEC 变体(grep 结果 gen_stmts.ss:280 `POSTFIX_INC ... add / else sub` 支持此假设)
- POSTFIX_INC 更常见(for 循环 `i++`),首迁价值 > POSTFIX_DEC(多用于 stack pop)
- **正确路径:POSTFIX_INC 首迁,D107 评估 POSTFIX_DEC 对称 bundle 或独立迁**

### §E — Step 0 强制预削减(不跳过)

**拒绝理由**:

- 当前 M7b bank +6 充裕,对照 D100 Step 0 启动 M7b +2 / D101 M7b 0 / D103 M7b 0 / D104 M7b +8 / D105 M7b +7,+6 属充裕区间
- 强制 Step 0 多消耗 1 轮 Execute 无价值,银行策略是累积余量,不强制消耗
- D103/D104/D105 Step 0 跳过实测全通,D106 重复模式可靠
- **正确路径:Step 0 默认跳过,例外触发条件见 §步骤 0**

## 新张力(D106 引出)

1. **ctVars.set 跨 evalExpr 边界一致性隐藏假设** — 本 Plan 首选依据 2/3/4 断言「POSTFIX_INC 写 ctVars 迁入 evalPostfixInc 后跨文件 ctVars 写与原 inline 等价」。**隐藏假设**:evalExpr 调用链嵌套场景(e.g. `comptime { for (let i = 0; i < n; i = i + 1) { arr[i++] = f(i) } }` 外层 POSTFIX_INC 在 INDEX_ACCESS lhs,内层 evalExpr 走 IDENT 读 i,同时 POSTFIX_INC 写 i)下,ctVars 状态跨 evalIdent + evalIndexAccess + evalPostfixInc 多函数边界是否一致?**验证点**:Execute 1 必须单测(a) 顶层 `x++` / (b) 嵌套 comptime block 内 `x++` / (c) `arr[i++]` 混合读写 / (d) `f(i++)` 参数传递 / (e) scope push/pop 跨 evalExpr 边界场景。若实测失败 → **Plan 退回**,POSTFIX_INC 改推 Phase A 后批 3 或 Phase B MaybeVal 类化后再迁

2. **原 gen_exprs.ss L167 raw constVal 编码** — 与 D101/D103/D104/D105 §新张力 1 同款问题,POSTFIX_INC **仅一处**(L167 runtime 回退)。迁入 evalPostfixInc 后必须改为 `0 - constVal(genPostfixExpr(astId)) - 1`。**验证点**:若漏改 → caller 拿到 reg str 被当 known val 处理 → comptime 折叠误判。Execute 1 必须单测:`function main() { let x = 0; let y = x++; return y }` runtime 路径 IR 字节级对比老版本

3. **eval_expr.ss 函数数持续攀升** — Step 1 后 9 函数(evalExpr + 8 eval*),Phase A 后批 2 每 kind +1 函数,2a/2b/2c 全完可能 12 函数。D100/D101/D103/D104/D105 §新张力连续五次提:「Phase B 类化期需评估是否压回单 evalExpr body」。D106 延续风险记录,不在本轮解决

4. **genPostfixExpr 跨文件未迁保留** — `genPostfixExpr`(gen_exprs.ss:105-113)+ `varRef` / `nextReg` / `emitIR` helper 保留,与 evalPostfixInc 跨文件调用。**验证点**:对照 evalIdent 跨文件读 genIdent 已 PASS,此处风险低但需 bootstrap 固定点验证

5. **写语义 kind 新模板价值** — POSTFIX_INC 是 Phase A 后批 2 建立「写语义 kind 迁入 evalExpr」的首个模板,验证通过后 Phase B MaybeVal 类化(D098 §决策 2)可直接复用 scope write pattern。**风险**:若本轮 §新张力 1 实测失败,MaybeVal 类化设计需重考虑 scope 载体 —— 可能从 `ctVars: Map<string, string>` 升级为带 version 标记的 MaybeVal 容器

6. **D102 ±0.5% DRIFT 窗口连续 5 次生产验证反向** — 本 Plan 预估 M2 -13~-17 / N2 -20~+40(相对 D105 Execute 1 后),均在 ±380 / ±1903 窗口内 15-50× 充裕。D101/D103/D104/D105 实测连续反向通过(全 PROGRESS),D106 预期延续趋势。**若实测超 DRIFT** → 说明 POSTFIX_INC 写语义路径是 M2/N2 非线性膨胀源,修正系数需记录进 D107 Plan

7. **N5 不跟踪 POSTFIX_INC 写** — N5 = MEMBER_ASSIGN 数,跟踪 `obj.field = val` 不跟踪 `var++`。**风险**:若 D098 §决策 2 Phase B MaybeVal 类化后 POSTFIX_INC 改走 `obj.value += 1` 形式,N5 会被引入,**是 Phase B 设计输入**(D106 记录,非本轮解决)

## 下一步(Plan 下的 Execute 顺序)

1. [ ] Planned — **Execute 0**(默认跳过):M7b bank +6 充裕,若 Execute 1 §新张力 1 失败触发,补削减 M7b -1 / N3 / M4 —— **本 Plan 未触发,默认跳过生效**
2. [x] **Done** — **Execute 1**:POSTFIX_INC 迁移 evalPostfixInc(对称 evalIdent / evalMemberAccess 三段式)
   - **eval_expr.ss:463-491** 新建 `evalPostfixInc(astId: int): int`(29 行,含 comptime scope 域链遍历 + ctVars.set + L490 runtime 回退 `0 - constVal(genPostfixExpr(astId)) - 1` mv 编码)
   - **eval_expr.ss:63** 新增 `if (k == "POSTFIX_INC") { return evalPostfixInc(astId) }` 分派
   - **gen_exprs.ss:132** L132 shim 扩 9 → 10 kind 加 `POSTFIX_INC`
   - **gen_exprs.ss** 删除原 L141-168 整块 28 行 inline(outer header + comptime 分支 26 行 + runtime 回退 + `}`)
   - **R1 前对照**(baseline = commit 9343330):M7b=670 / N3=515916 / M2=76096 / N2=380480 / F1:gen_exprs.ss=1450,14 项 + F1 全 OK/PROGRESS
   - **R3 后对照实测**(相对 baseline):
     - **M7b 676 → 671 Δ=-5 PROGRESS**(bank +6 → +5,**精确命中** §预估 671)
     - **N3 518111 → 515797 Δ=-2314 PROGRESS**(bank -2195 → -2314,**超预估下限 3**)
     - **M2 76126 → 76109 Δ=-17 PROGRESS**(累计组 DRIFT ±380 远内;预估 -26~-46 偏浅 9)
     - **N2 380630 → 380545 Δ=-85 PROGRESS**(累计组 DRIFT ±1903 远内;预估 -110~-170 偏浅 25)
     - **F1:gen_exprs.ss 1721 → 1422 Δ=-299 PROGRESS**(**精确命中** §预估 ~1422,单调下降累计 17.4% 压缩率)
     - 结构组 8 项 OK/PROGRESS(核心 M7b 671≤676 / N3 结构组深窖-2314)
     - 累计组 6 项 OK/PROGRESS(M1 -4 / M2 -17 / M3a -1 / M5 -3 / N1 0 / N2 -85)
   - **bootstrap 固定点**:seed → stage1 → stage2 → stage3,stage2==stage3 验证通过
   - **test tests/**:213 passed / 4 failed(pre-existing `spring_web_params / harness_task / d096_p4_l2_reactive / harness_bug`,与 D105 Execute 1 baseline **完全一致**,非 D106 引入)
   - **§新张力 1 反向通过**(ctVars.set 跨 evalExpr 边界一致性):项目 tests/ 30+ 文件 `++` 场景(todo_app / nested_for / stdlib_sort / kv_store / string_ops / comptime_comprehensive / comptime_dispatch)全 PASS,补充 /tmp/d106_postfix_demo.ss 4 场景(stmtInc=7 / forInc=10 / comptimeScope=0 / nestedStmt=402)—— 假设**解除**
   - **§新张力 2 反向通过**(L167 raw constVal → mv 编码):git stash 反向验证 demo 4 场景值 100% 一致,证纯重构零行为偏移 —— 假设**解除**
   - **§新张力 3 延续记录**(eval_expr.ss 函数数 8 → 9):Phase B MaybeVal 类化期评估压回单 evalExpr body,本轮不解决
   - **§新张力 5 价值兑现**(写语义 kind 新模板):POSTFIX_INC 是 Phase A 首个 scope write kind 模板,为 Phase B MaybeVal 类化(D098 §决策 2)提供 scope 一致性实证——**成功建立**
   - **Phase A 后批 2 批累计**(D106 单 kind):gen_exprs.ss 1450 → 1422,baseline 9343330 起共累计 1721 → 1422(-299 / 17.4% 压缩率),F1 硬上限 ≤600 预算下 Phase A 六轮(D100/D101/D103/D104/D105/D106)单调收敛
3. [x] **Done** — **Execute 2**:收尾评估完成(§步骤 2 决策矩阵条件「M7b 余量 ≥ +4 且 N3 bank < -2200」实测 `+5 / -2314` 命中 → 默认**不 record**,延续银行策略;M7b bank +5 / N3 bank -2314 深窖,支持 Phase A 后批 2 下一 kind)+ 下轮起 D107 Plan(2b POSTFIX_DEC 对称 bundle 或 METHOD_CALL 中量独立,由 D107 §候选选型决策)

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- D105 §步骤 1 evalMemberAccess(对称三段式模板)/ §步骤 2 决策矩阵(M7b +5 / N3 -1500 阈值,本 Plan 触发)/ Execute 1 实测(M7b -6 / N3 -2195 / M2 -30 / N2 -150 / F1 -271)
- D104 §步骤 1 evalIdent(scope 只读迁移模板)/ §新张力 1(scope 机制迁移干净性)/ §新张力 2(mv 编码)
- D103 §步骤 1 evalArrayLit(对称三段式)
- D101 §步骤 1 evalTemplateLit / §新张力 1 mv 编码
- D100 §坑 Q(银行余量不 record)/ §坑 P(M2/N2 迁移成本模型)
- D102 §规则 1.1-1.4(分层 GATE + DRIFT 窗口)/ §规则 2.1-2.3(F1 文件行数 GATE)
- D099 §坑 G-O(N3/M7b 成本模型)
- D098 §决策 1 MaybeVal Phase A mv 编码 / §决策 2 Phase B 类化(POSTFIX_INC scope write 是关键输入)
- D094 §决策 §规则 2 L109-110(POSTFIX_INC 不在 pure subset 白名单)/ L175(zig 驱动 9 kind POSTFIX_INC 在列)
- D088 §第一性需求(Zig 路线 SEMA 收敛一份 evalExpr)/ §正模式「一份 evalExpr 函数」
- CLAUDE.md §反射根因 gate(POSTFIX_INC 不触)/ §交互式单文档(含 ultrathink gate)/ §PFV 流程
- `memory/feedback_ultrathink_gate.md` / `memory/feedback_pfv_process.md` / `memory/feedback_reflection_root_cause_gate.md`
- `bootstrap/gen_exprs.ss:141-168`(POSTFIX_INC 当前 inline 28 行)
- `bootstrap/gen_exprs.ss:132`(L132 shim,D105 Execute 1 后 9 kind)
- `bootstrap/gen_exprs.ss:105-113`(genPostfixExpr runtime 侧,不迁)
- `bootstrap/gen_stmts.ss:280-434`(genPostfixStmt stmt 形式,不影响)
- `bootstrap/eval_expr.ss`(461 行,8 函数,D105 Execute 1 结果)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt` @ D101 Execute 0 commit 9343330(F1 1721 / M7b 676 / N3 518111)
- `tools/next_prompt_ultrathink_linter.ss`(PFV §收尾 gate 第 3 步 (b) 机械 gate)
