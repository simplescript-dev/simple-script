# D101: evalExpr Phase A 中批 1b 第 2 kind Plan — TEMPLATE_LIT

**Status:** Execute 0 Done at commit 9343330,Execute 1 Done at commit 3f0da11,Execute 2 未开工(Step 2 决策点由 D103 1b-3 选型 ARRAY_LIT 吸收)
**Depends on:** D100 §Rejected A(TEMPLATE_LIT 作 1b 第 2 轮铺垫)/ D100 §步骤 1 evalIndexAccess 对称 pattern / D102 §规则 1.1-1.4(分层 GATE)/ D102 §规则 2.1-2.3(F1 文件行数 GATE)/ D098 §决策 1 mv 编码 / D094 §规则 2 pure subset
**Date:** 2026-04-19

---

## 第一性需求

D100 Execute 1 已合并 INDEX_ACCESS(1b 首个 kind),shim 链扩 5 kind,eval_expr.ss 新增 evalIndexAccess 独立函数并对称 evalTernary / evalShortCircuit / evalComptimeExpr 模板。D102 Phase 2 已落地 linter 分层化 + F1 GATE,累计组 DRIFT 窗口 ±0.5% 替代 D100 §坑 P 的"凑余量八股文"失败。baseline 当前刷到:

```
M1=5135  M2=76150  M3a=12128  M3b=1879  M4=3037
M5=1750  M6=32     M7a=27     M7b=677   N1=34
N2=380750  N3=518205  N4=321  N5=0
F1:bootstrap/gen_exprs.ss=1721  (+ 13 条其他)
```

**本 Plan 选 TEMPLATE_LIT 作 1b 第 2 kind**,承接 D094 §规则 2 pure subset 4 项余项(TEMPLATE_LIT / ARRAY_LIT / IDENT / MEMBER_ACCESS)。D100 §Rejected A L150 已明确:「TEMPLATE_LIT 作 1b 第 2 个 kind 更合理」—— 对称 pattern 在 INDEX_ACCESS 走通后,TEMPLATE_LIT 直接套用 `删 genVal 内联 + 新建 eval* 独立函数 + L132 || 链扩一 kind` 三段式,同时验证 D102 §规则 1.3 DRIFT 终态在「body ~130 节点 × 两 for 循环」搬家下不误报 REGRESSION。

## 为什么 1b-2 选 TEMPLATE_LIT(4 候选对照)

| kind | 体量(行)| 节点密度(估)| subsystem 耦合 | Step 0 预削减压力 |
|---|---|---|---|---|
| **TEMPLATE_LIT** | L537-578,**42 行** | ~130 | tmplPreRegs(runtime 迁移挂钩) / genTemplateLit(不迁) | 中(M7b +1 需抵消) |
| ARRAY_LIT | L580-643,63 行 | ~180 | SPREAD_ELEM 展开 while 循环 + 3 种 elem 类型 | 高(body 大 + 深嵌套) |
| IDENT | L134-174,40 行 | ~150 | **5 路径**(ctInvalidated / ctScopeStack / genericTypeSubs / resolveCtTypeAlias / ctVars)| 极高(多 state 耦合) |
| MEMBER_ACCESS | L340-462,123 行 | ~400 | **反射根因 gate**(D095 FieldMeta / D097 AnnotationMeta / enum / class field)| 极高(必过 reflection_health_linter G1-G5) |

**TEMPLATE_LIT 首选依据**:
1. **D100 铺垫已成** — §Rejected A 明言作 1b 第 2 个 kind,对称 pattern 已验证通路
2. **零反射 gate 触发** — TEMPLATE_LIT 纯字符串模板组合,不触 D095 / D097 反射路径
3. **subsystem 耦合最浅** — 仅 `tmplPreRegs` 全局 Map(存 fragId → reg str)和 `genTemplateLit`(runtime IR emit,不迁)两项,对称 INDEX_ACCESS 的"零耦合"略重但远低于 IDENT/MEMBER_ACCESS
4. **D102 DRIFT 窗口首验** — body 42 行 × 深嵌套 2 个 for 循环,是验证「搬家物理成本 M2 +5~25 / N2 +20~70 不误报」的最佳样本;若此轮 DRIFT 不误报,1b-3/4/5 的 ARRAY_LIT/IDENT/MEMBER_ACCESS 可安心推进
5. **N3 大削潜力** — body depth 4(两层 for × 内层 if)搬到独立函数 depth 1-2,预估 N3 -200~-400(vs INDEX_ACCESS 实测 -182),结构组严格 GATE 下 PROGRESS 明确

## 当前事实(2026-04-19 snapshot)

| 项 | 值 / 位置 |
|---|---|
| TEMPLATE_LIT 分派 | `bootstrap/gen_exprs.ss:537-579`(42 行 inline) |
| genTemplateLit(runtime 侧,不迁)| `bootstrap/gen_calls.ss:557+` |
| L132 shim | `|| kind == "INDEX_ACCESS"`(D100 扩至 5 kind) |
| eval_expr.ss | 190 行,5 函数(evalExpr + evalTernary + evalShortCircuit + evalComptimeExpr + evalIndexAccess) |
| TMPL_FRAG_LIT / TMPL_FRAG_EXPR | fragment 两 kind,nGetS1 取字面量串 / nGetI1 取表达式 id(TEMPLATE_LIT body 内迭代) |
| tmplPreRegs 全局 Map | `bootstrap/gen_calls.ss:6`,TEMPLATE_LIT runtime 分支 pre-populate,genTemplateLit 读 |

**TEMPLATE_LIT body 结构**(L537-579 逐层):
- 空串快速路径(fragList == "")
- for loop #1(L543-550):遍历 parts 算 fragVals + allCt
- comptime 折叠分支(L551-568):for loop #2 拼字符串,内含 if/elseif 两分支
- runtime 回退(L569-578):comptime 错 / tmplPreRegs pre-populate for loop #3 / call genTemplateLit

## 对照 D102 §规则 1.1-1.4 分层 GATE 的 DRIFT 预估

**关键**:D102 落地后累计组允许 ±0.5% 窗口,不再强迫 M2/N2 净削减;但 N3 / M7b / M3b / M4 / M6 / M7a / N4 / N5 八结构组严格不升。

| 指标 | 组 | baseline | D101 step 1 后 cur(估) | Δ | tol | 判定 | 依据 |
|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5135 | 5130-5140 | ±5 | ±25 | OK/DRIFT | body 分支数近似,新函数签名 CC=1 |
| M2 | 累计 | 76150 | **76170-76200** | **+20~+50** | ±380 | **DRIFT**(190× 充裕) | 新函数签名节点 + 新 dispatch 行 + L132 扩一 kind + 删 outer `if kind == TEMPLATE_LIT` wrapper 节点。body 两层 for 循环搬家节点数近似 |
| M3a | 累计 | 12128 | 12125-12132 | ±5 | ±60 | OK/DRIFT | genVal → evalTemplateLit 新边 +1;L132 扁平化少 1 调用 |
| M3b | 结构 | 1879 | 1879 | 0 | 0(严格) | OK | 不触最大入度函数(interpNewX 等热函数入度不变) |
| M4 | 结构 | 3037 | 3036-3037 | 0 ~ -1 | 0(严格) | OK | genVal 内 `if kind == "TEMPLATE_LIT"` 删除,dispatch 链 -1 |
| M5 | 累计 | 1750 | 1750 | 0 | ±8 | OK | 不新增可变变量 |
| M6 | 结构 | 32 | 32 | 0 | 0(严格) | OK | 不新增递归 |
| M7a | 结构 | 27 | 27 | 0 | 0(严格) | OK | 独立函数后 body depth 缩短,不升最大嵌套 |
| M7b | 结构 | 677 | **677**(+1 evalTemplateLit,-1 Step 0 抵消)| **0** | 0(严格) | OK | **Step 0 必须预削减 1 函数,否则 GATE BLOCKED** |
| N1 | 累计 | 34 | 34 | 0 | ±1(保底)| OK | 不引入新 kind |
| N2 | 累计 | 380750 | **380780-380830** | **+30~+80** | ±1903 | **DRIFT**(23× 充裕) | M2 派生,body 两层 for 搬家 Halstead 波动 |
| N3 | 结构 | 518205 | **517800-518050** | **-155 ~ -405** | 0(严格) | **PROGRESS** | body 两 for + 内 if 从 depth 4-5 搬到独立函数 depth 1-2 |
| N4 | 结构 | 321 | 321 | 0 | 0(严格) | OK | 不触最大节点出度函数 |
| N5 | 结构 | 0 | 0 | 0 | 0(严格) | OK | 不新增成员写入 |
| **F1:gen_exprs.ss** | - | 1721 | **~1679** | **-42** | 单调下降 | **PROGRESS** | 删除 L537-579 整块 42 行 inline body;+L132 shim 扩一 kind ~0 行净增;净 -42 |

**累计组 6 项** 全落 DRIFT 窗口内,**结构组 8 项** 全 OK / PROGRESS,**F1** gen_exprs.ss PROGRESS。核心验证点:D102 §规则 1.3 DRIFT 终态在 M2 +20~50 / N2 +30~80 下触发 PASS(不 BLOCKED),同时 N3 结构组严格守护不破。

## DRIFT 窗口对 D100 §坑 P 的正面回放

D100 §坑 P 记录:INDEX_ACCESS 迁移实测 M2 +2 / N2 +10,依据「body 节点总数近似,深度贡献走 N3」。D102 Phase 2 已把 M2 / N2 归累计组并引入 ±0.5% DRIFT,TEMPLATE_LIT body 更大(130 节点 vs 80 节点)M2/N2 增量按比例扩展到 +20~50 / +30~80,**预期首次验证累计组 DRIFT 在生产迁移里产生正向价值**:

- 若 DRIFT PASS 正常运作 → 1b-3/4/5 可继续对称 pattern 推进,不被累计组阻挡
- 若实测 M2/N2 增量超 DRIFT 窗口 → 暴露 D102 §规则 1.2 ±0.5% 阈值偏紧,触发 D103(Plan 内 §风险 已列)
- 若结构组 N3 未如预期 PROGRESS → 暴露「body depth 搬家削减 N3」模型偏差,触发 D102 §风险 复检

## 决策(分 3 步,每步独立 bootstrap + 分层 GATE PASS)

### §步骤 0 — 预削减 commit(拿 M7b ≥ -1 余量,抵消 step 1 新 evalTemplateLit)

**目标**:结构组 M7b 严格不升,Step 1 新增 evalTemplateLit +1 必须同 commit 内 -1 抵消或 Step 0 预先削减腾余量。**不钦定源**,Execute 0 按 PFV 流程 grep 实测选净削减最大项。

**候选削减源**(Execute 0 轮 grep 验证可行性):

1. **eval_expr.ss evalComptimeExpr(L168-172,4 行)inline 回 evalExpr dispatch** — 当前仅 2 行 body(`if comptimeDepth > 0 return comptimeError` / `inferType + constVal`),L53 单调用,inline 到 `if (k == "COMPTIME_EXPR")` 分支节省 1 函数。**风险**:N3 可能微增(inline 处加深 depth 1),需同步验证 N3 不 REGRESSION
2. **bootstrap 内孤儿 helper grep** — 迁移轮可能产生调用点被吸收后的孤儿函数(如老 `inferBinaryType` / `genValBinary` 内部 helper 若已全 inline 至 evalExpr)
3. **gen_exprs.ss 或 gen_calls.ss 内 dead helper** — D099 1a 5 kind 合并后某些 runtime helper 可能已无调用点,需 grep 确认
4. **tools/reflection_health_linter.ss 内小函数 inline** — D102 Phase 2 已 inline 了 mapSetInt;`popFunc` / `funcTop` 仍是候选,但 linter 只扫 bootstrap/ 不影响 M7b baseline,**不作候选**

**Execute 0 操作顺序**:
1. `grep -n "^function " bootstrap/eval_expr.ss` + 统计每函数调用点
2. `grep -rn "^function " bootstrap/ | awk` 找单调用点(孤儿)
3. 候选 1-3 逐一估 inline 后 N3 / M2 影响,选「M7b -1 且 N3 不升 且 M2 增量最小」
4. 单 commit 落地,bootstrap 固定点 PASS + linter GATE PASS

**验证**:
- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS,M7b 至少 -1

**若无单项可达 M7b -1**:step 0 拆 0a/0b 累积,但每 commit 独立 bootstrap + GATE PASS。

### §步骤 1 — TEMPLATE_LIT 迁移(独立函数 evalTemplateLit,对称 pattern)

**新建 `bootstrap/eval_expr.ss` 末尾 `evalTemplateLit(astId: int): int`**:

```ss
function evalTemplateLit(astId: int): int {
    const fragList = nGetList(astId)
    if (fragList == "") { return ctVal(interpNewString("")) }
    let allCt = 1
    const tmplParts = fragList.split(",")
    let fragVals = new Map()
    for (tp in tmplParts) {
        const fragId = parseInt(tp)
        if (fragId > 0 && nGetKind(fragId) == "TMPL_FRAG_EXPR") {
            const fv = genVal(nGetI1(fragId))
            fragVals.set(`${fragId}`, `${fv}`)
            if (isCt(fv) != 1) { allCt = 0 }
        }
    }
    if (allCt == 1) {
        let ctResult = ""
        for (tp in tmplParts) {
            const fragId = parseInt(tp)
            if (fragId > 0) {
                const fk = nGetKind(fragId)
                if (fk == "TMPL_FRAG_LIT") { ctResult = `${ctResult}${nGetS1(fragId)}` }
                else if (fk == "TMPL_FRAG_EXPR" && fragVals.has(`${fragId}`) == 1) {
                    const fv = parseInt(fragVals.getString(`${fragId}`))
                    if (isCt(fv) == 1) { ctResult = `${ctResult}${interpToStr(payload(fv))}` }
                }
            }
        }
        return ctVal(interpNewString(ctResult))
    }
    if (comptimeDepth > 0) { return comptimeError("template literal contains runtime expression", astId) }
    tmplPreRegs = new Map()
    for (tp in tmplParts) {
        const fragId = parseInt(tp)
        if (fragId > 0 && nGetKind(fragId) == "TMPL_FRAG_EXPR") {
            const fv = parseInt(fragVals.getString(`${fragId}`))
            tmplPreRegs.set(`${fragId}`, reg(fv))
        }
    }
    return 0 - constVal(genTemplateLit(astId)) - 1
}
```

**关键点**:
- 坑 H 延续:operand `genVal(nGetI1(fragId))` 保留,**不递归 evalExpr**(fragment expr 可为任意 kind,evalExpr dispatch 仅 6 kind)
- 对称 evalIndexAccess L189:`return 0 - constVal(genTemplateLit(astId)) - 1`(runtime mv 编码)—— **与原 gen_exprs.ss L578 `return constVal(genTemplateLit(id))` 编码不同**,必须加 `0 - ... - 1`,caller 走 L132 shim `mv >= 0 ? mv : 0 - mv - 1` 解码后还原
- ct 分支 `return ctVal(interpNewString(...))` 不变(已是 mv 编码 known 分支)

**改 `bootstrap/gen_exprs.ss` L132 shim**:
```ss
// BEFORE
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
// AFTER
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
```

**改 `bootstrap/eval_expr.ss` evalExpr 头部**(L54 INDEX_ACCESS 分派后加):
```ss
if (k == "TEMPLATE_LIT") { return evalTemplateLit(astId) }
```

**删 `bootstrap/gen_exprs.ss` L537-579 整块**(42 行 TEMPLATE_LIT inline body)

**独立验证链**(tokenize → parse → eval):
1. Tokenizer:`TEMPLATE_START` / `TEMPLATE_MIDDLE` / `TEMPLATE_END` 三 token 不改,parse_exprs.ss TEMPLATE_LIT parse 不改 —— **parse 层零影响**
2. check_stmts.ss TEMPLATE_LIT checkExpr 不改(checker 只做类型推断,不走 eval 路径)
3. eval 路径:`genVal(TEMPLATE_LIT) → L132 shim → evalExpr → evalTemplateLit`,对称 INDEX_ACCESS 走通链
4. runtime IR emit:`genTemplateLit(id)` 不迁,gen_calls.ss L557+ 保留 —— **IR 输出字节级不变**

**验证**:
- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- TEMPLATE_LIT 测试全绿:纯字面量模板 / 含 expr 模板 / comptime 折叠 / runtime emit / 嵌套 template
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK / PROGRESS(核心 M7b 0 / N3 PROGRESS)
  - 累计组 6 项 OK / DRIFT / PROGRESS(M2 +20~50 / N2 +30~80 均在 DRIFT 窗口内)
  - F1:gen_exprs.ss PROGRESS(1721 → ~1679)

### §步骤 2 — 收尾评估 + 指向 1b-3(ARRAY_LIT 或 IDENT)

**目标**:step 1 完成后决策是继续 1b 下一 kind 还是 record baseline。默认**不 record**(对照 D100 §步骤 2 / §坑 Q),等 1b 全 5 kind 落地后单 commit record。

**决策点**:
- step 1 后 M7b 余量 / N3 余量 充足 → 另起 D103 选 ARRAY_LIT(体量大但 SPREAD_ELEM 分支是典型 N 元迭代,可继续验证 DRIFT 窗口)
- 余量紧张 → 独立 commit record 释放余量给下 kind
- F1:gen_exprs.ss 目标 ≤ 600,当前 1721 → 1679 后仍 > 600,需 1b-3/4/5 继续削减;估 ARRAY_LIT -63 / IDENT -40 / MEMBER_ACCESS -123,1b 全完 ~1480,仍 > 600,Phase A 后批 2 继续

## Rejected Alternatives

### §A — 1b-2 选 ARRAY_LIT

**拒绝理由**:
- body 63 行 + SPREAD_ELEM 分支 while 循环 depth 再 +1,Step 0 预削减压力更大(M7b +1 抵消 + N3 余量需 -80 级别准备,且 M2/N2 DRIFT 增量估 +30~80 / +50~150 更激进)
- D100 §Rejected B L151 已明言:「与 TEMPLATE_LIT 类似是多 operand 迭代结构,比 TEMPLATE_LIT 多一层(SPREAD_ELEM 分支内 while srcI<srcLen 数组展开),Step 0 预削减压力最大,推到 1b 末轮」
- **正确位置:1b-3 或更后**

### §B — 1b-2 选 IDENT

**拒绝理由**:
- 40 行但 **5 路径耦合**(ctInvalidated / ctScopeStack / genericTypeSubs / resolveCtTypeAlias / ctVars),scope 机制需 Phase B MaybeVal 类化期吸收(D098 §决策 2)
- D099 §Rejected A / D100 §Rejected C 两次否决作早期 kind
- **正确位置:1b 末轮或推 Phase A 后批 2**

### §C — 1b-2 选 MEMBER_ACCESS

**拒绝理由**:
- 123 行 + 触 **反射根因 gate**(CLAUDE.md §反射根因 gate 强制条款 + D097),必过 reflection_health_linter G1-G5
- D100 §Rejected D 已明言:「含 D095 FieldMeta / D097 AnnotationMeta 累积路径,本轮不应承担」
- **正确位置:1b 末轮,独立 Plan + 反射 gate 专章**

### §D — 跳过 Step 0,直接 Step 1 inline TEMPLATE_LIT body 到 evalExpr(不建独立函数)

**拒绝理由**:
- body 130 节点 × 两 for 循环 inline 到 evalExpr 头部 `if k == TEMPLATE_LIT` 块,evalExpr body 继续膨胀(当前 ~100 行)
- N3 严格不升,body inline depth +4~5 会炸 N3 远超余量
- D099 §坑 L 已确认:runtime phi / N 元迭代结构必走独立函数
- **正确路径:独立函数 evalTemplateLit,对称 evalIndexAccess pattern**

### §E — Step 1 一次 bundle INDEX_ACCESS + TEMPLATE_LIT 两 kind(无 Step 0)

**拒绝理由**:
- D100 Execute 1 已独立 commit INDEX_ACCESS,bundle 违反单步独立可回滚原则
- Plan 粒度守则:一 commit 一 kind,每 commit bootstrap + GATE 独立 PASS
- **正确路径:D101 独立轮,Step 0 + Step 1 + Step 2 三 commit**

## 新张力(D101 引出)

1. **原 gen_exprs.ss L578 `return constVal(genTemplateLit(id))` 编码** — 老 genVal 路径直接返回 reg str 的 constVal 编码,**无 `0 - ... - 1` 包裹**。迁入 evalTemplateLit 必须改为 mv 编码 `0 - constVal(...) - 1`,caller L132 shim `mv >= 0 ? mv : 0 - mv - 1` 解码还原。**验证点**:若错传 raw constVal 不 mv 编码 → caller 拿到 reg str 被当 known val 处理 → comptime 折叠误判。Execute 1 必须单测 runtime emit 路径 IR 字节级对比老版本
2. **tmplPreRegs 全局 Map 迁移语义** — 当前 gen_exprs.ss L570 `tmplPreRegs = new Map()` 重置,L575 `tmplPreRegs.set(...)` 填充,L578 `genTemplateLit(id)` 读。迁入 evalTemplateLit 后三处操作同函数内保留,**但 evalTemplateLit 在 runtime 分支才触发该 Map 操作**,comptime 分支早 return 不污染 Map。**验证点**:嵌套 template 场景(外层 TEMPLATE_LIT runtime,内层 TEMPLATE_LIT comptime)Map 状态是否正确 —— 当前 inline body 已有该问题,迁移**不改变语义**,但需确认测试覆盖
3. **eval_expr.ss 函数数攀升** — step 1 后 6 函数(evalExpr + 5 eval*),1b 全完 10 函数。D100 §新张力 2 已提:「Phase B 类化期需评估是否压回单 evalExpr body(MaybeVal class 携带 state 后可能 inline 回无深度代价)」。D101 延续该风险,不在本轮解决
4. **Step 0 候选 1(inline evalComptimeExpr)的 N3 副作用** — evalComptimeExpr 2 行 body,inline 到 evalExpr L53 `if k == COMPTIME_EXPR` 块,depth +1 × 2 行 节点 = N3 +4~6。结构组严格,若此 +4 无法被 step 1 N3 -155 大削抵消则 BLOCKED。**对策**:Execute 0 实测并观察 step 1 实际 N3 削减量,若不达 -155+ 则切候选 2(孤儿 helper)
5. **D102 ±0.5% DRIFT 窗口首次生产验证** — 本 Plan 预估 M2 +20~50 / N2 +30~80,均在 ±380 / ±1903 窗口内 20-60× 充裕。若实测超 DRIFT → 说明 D102 ±0.5% 阈值偏紧,触发 D103(Plan 内新决策)按每 kind 迁移预算细化窗口

## 下一步(Plan 下的 Execute 顺序)

1. [x] Done at commit 9343330 — **Execute 0**:删 codegen.ss generate 死函数腾 M7b 余量(677→676 / baseline record)
2. [x] Done at bootstrap/eval_expr.ss:55,193 + bootstrap/gen_exprs.ss:132 — **Execute 1**:TEMPLATE_LIT 迁移 evalTemplateLit(对称 evalIndexAccess);同 commit inline evalComptimeExpr 回 evalExpr L53 dispatch 块抵消 M7b +1。GATE PASS:M7b 676 delta=0 / N3 -238 / M2 +8 / N2 +40 / F1:gen_exprs.ss 1721→1678 PROGRESS。D102 ±0.5% DRIFT 窗口首次生产验证 PASS
3. [ ] Planned — **Execute 2**:Step 2 收尾评估(record vs 继续 1b-3;默认继续)

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- D100 §Rejected A(TEMPLATE_LIT 作 1b 第 2 铺垫)/ §步骤 1(evalIndexAccess 对称模板)/ §坑 P(M2/N2 迁移成本)/ §坑 Q(银行余量不 record)
- D102 §规则 1.1-1.4(分层 GATE + DRIFT 窗口)/ §规则 2.1-2.3(F1 文件行数 GATE)
- D099 §坑 G-O(N3/M7b 成本模型)/ §步骤 5(evalComptimeExpr 建立)
- D098 §决策 1 MaybeVal Phase A mv 编码
- D094 §规则 2 pure subset 白名单(TEMPLATE_LIT 归属)
- CLAUDE.md §反射根因 gate(1b-2 TEMPLATE_LIT 不触,但 1b-5 MEMBER_ACCESS 必触)
- `bootstrap/gen_exprs.ss:537-579`(TEMPLATE_LIT 当前 inline)
- `bootstrap/gen_calls.ss:6`(tmplPreRegs)/ `:557+`(genTemplateLit runtime 侧,不迁)
- `bootstrap/eval_expr.ss:174-190`(evalIndexAccess 对称模板,D100 Execute 1)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt` @ D102 Phase 2 Execute(当前 baseline 含 F1)
