# D103: evalExpr Phase A 中批 1b 第 3 kind Plan — ARRAY_LIT

**Status:** Execute 0 Done at commit 6197667,Execute 1/2 未开工
**Depends on:** D101 §步骤 1 evalTemplateLit 对称 pattern / D101 §Rejected A(ARRAY_LIT 推到 1b-3 或更后)/ D100 §Rejected B(ARRAY_LIT body 大推 1b 末轮)/ D100 §步骤 1 evalIndexAccess 三段式模板 / D102 §规则 1.1-1.4(分层 GATE + ±0.5% DRIFT)/ D102 §规则 2.1-2.3(F1 文件行数 GATE)/ D098 §决策 1 mv 编码 / D094 §规则 2 pure subset 白名单(L104 `ARRAY_LIT` 在列)
**Date:** 2026-04-19

---

## 第一性需求

D101 Execute 1 已合并 TEMPLATE_LIT(1b 第 2 kind),shim 链扩 6 kind,eval_expr.ss 新增 evalTemplateLit 独立函数 + inline evalComptimeExpr 回 evalExpr L53 dispatch 抵消 M7b +1,GATE PASS 实测 `M7b=676 delta=0 / N3 -238 / M2 +8 / N2 +40 / F1:gen_exprs.ss 1721→1678`。D102 ±0.5% DRIFT 窗口**首次生产验证 PASS**(累计组 6 项 DRIFT 充裕,结构组 N3 大削不破)。baseline 当前(D101 Execute 0 commit 9343330 record,Execute 1 未 record,留余量给 1b-3):

```
M1=5134  M2=76126  M3a=12122  M3b=1879  M4=3037
M5=1750  M6=32     M7a=27     M7b=676   N1=34
N2=380630  N3=518111  N4=321  N5=0
F1:bootstrap/gen_exprs.ss=1721  (+ 13 条其他)
```

cur 实际值(D101 Execute 1 后,未刷新 baseline):`M7b=676 / N3=517873(估 518111-238) / F1:gen_exprs.ss=1678`,F1 余量 **43 行**(1721-1678),M7b 余量 0(净 0),N3 余量 ~238(若 Execute 1 实测 -238 全额保留)。

**本 Plan 选 ARRAY_LIT 作 1b 第 3 kind**,承接 D094 §规则 2 pure subset 余项(D100/D101 完成 INDEX_ACCESS/TEMPLATE_LIT,余 3 项 IDENT / MEMBER_ACCESS / ARRAY_LIT;后两位置由 D101 §Rejected B/C 明确推 1b 末轮)。D100:L151 §Rejected B 已明言「ARRAY_LIT 与 TEMPLATE_LIT 类似是多 operand 迭代结构,比 TEMPLATE_LIT 多一层(SPREAD_ELEM 分支内 while 数组展开),Step 0 预削减压力最大,推到 1b 末轮」;D101:L200 §Rejected A 亦明言「ARRAY_LIT 正确位置:1b-3 或更后」。**当前轮次即 1b-3,接位置预言**。

## 为什么 1b-3 选 ARRAY_LIT(3 候选对照,5 候选扣除已落)

| kind | 体量(行) | 节点密度(估) | subsystem 耦合 | Step 0 预削减压力 | 反射 gate |
|---|---|---|---|---|---|
| **ARRAY_LIT** | L538-599,**62 行** | ~180 | arrPreRegs(runtime 迁移挂钩)/ genArrayLit(不迁)/ SPREAD_ELEM 分支 | 中-高(body 大 + SPREAD while 展开深度)| 不触 |
| IDENT | L134-174,40 行 | ~150 | **5 路径**(ctInvalidated / ctScopeStack / genericTypeSubs / resolveCtTypeAlias / ctVars) | 极高(多 state 耦合) | 不触 |
| MEMBER_ACCESS | L340-462,123 行 | ~400 | **反射根因 gate**(D095 FieldMeta / D097 AnnotationMeta / enum / class field)| 极高(必过 reflection_health_linter G1-G5)| **触 §反射根因 gate** |

**ARRAY_LIT 首选依据**:

1. **D100/D101 铺垫已成** — D100:L151 / D101:L200 两次明言 ARRAY_LIT 推到 1b-3,本轮接位置预言,对称 evalTemplateLit 三段式验证成熟(D101 Execute 1 实测 GATE PASS)
2. **零反射 gate 触发** — ARRAY_LIT 纯数组字面量组合,不触 D095 / D097 反射路径,相比 MEMBER_ACCESS(123 行 + 必过 G1-G5)风险显著更低
3. **subsystem 耦合受限** — 仅 `arrPreRegs` 全局 Map(gen_calls.ss:7,存 elemId → reg str)和 `genArrayLit`(runtime IR emit,不迁)两项,对称 TEMPLATE_LIT 的 `tmplPreRegs`/`genTemplateLit` 模板,迁移语义一一对应
4. **D102 DRIFT 窗口二次生产验证** — body 62 行 × ~180 节点(比 TEMPLATE_LIT 42 行 × ~130 节点大 ~40%),M2 +12~20 / N2 +55~80 估算仍远落 ±380 / ±1903 窗口内,可验证「更大 body 迁移下累计组 DRIFT 不误报」
5. **N3 削减潜力** — body depth 4-5(comptime 分支内 `while srcI < srcLen` SPREAD 展开 +1)搬到独立函数 depth 1-2,预估 N3 -300~-500(vs TEMPLATE_LIT 实测 -238,按深度 +1 + body 节点 +40% 线性缩放)
6. **F1 双大削** — `bootstrap/gen_exprs.ss` 当前 1678 行,删 62 行后 ~1616,距 F1 目标 ≤ 600 仍远,但 1b-3 单轮削减居所有 1b kind 之首(TEMPLATE_LIT -42 / INDEX_ACCESS -26 / ARRAY_LIT -62 / IDENT -40 / MEMBER_ACCESS -123)

## 当前事实(2026-04-19 snapshot)

| 项 | 值 / 位置 |
|---|---|
| ARRAY_LIT 分派 | `bootstrap/gen_exprs.ss:537-599`(**62 行 inline**,header `if (kind == "ARRAY_LIT")` 在 L537) |
| genArrayLit(runtime 侧,不迁)| `bootstrap/gen_calls.ss:607+` |
| L132 shim | `|| kind == "TEMPLATE_LIT"`(D101 扩至 6 kind) |
| eval_expr.ss | 233 行,5 函数(evalExpr + evalTernary + evalShortCircuit + evalIndexAccess + evalTemplateLit) |
| SPREAD_ELEM 子 kind | elem 两类:普通 elem 直接 `genVal(elemId)` / SPREAD_ELEM 调 `genVal(nGetI1(elemId))`;comptime 分支 SPREAD 展开有 `while srcI < srcLen` 循环 |
| arrPreRegs 全局 Map | `bootstrap/gen_calls.ss:7`,ARRAY_LIT runtime 分支 pre-populate,genArrayLit 读(L645/L653/L687 三处)|
| arrPreRegs caller / reader 分离 | pre-populate 在 `gen_exprs.ss:587-597`,read 在 `gen_calls.ss:645/653/687`,迁移后 pre-populate 在 evalArrayLit 内,read 在 gen_calls.ss 不变 |

**ARRAY_LIT body 结构**(L537-599 逐层):

- **L537**:header `if (kind == "ARRAY_LIT") {`
- **L538-542**:空数组快速路径(elemList == "")+ 3 分支 return(空 comptime / 空 runtime)
- **L543-559**:for loop #1 — 遍历 parts 算 elemVals + allCt,内含 SPREAD_ELEM 分支(L549-552)vs 普通 elem(L553-557)
- **L560-586**:comptime 折叠分支 — for loop #2(L562-584)内含 SPREAD_ELEM spread 展开 `while srcI < srcLen` 循环 (L571-575)**body 最深 depth 5**,以及非 SPREAD 直接 `interpArrayPush` 回退(L580-582)
- **L587-599**:runtime 回退 — `arrPreRegs = new Map()` 重置 + for loop #3(L588-598)pre-populate + `return constVal(genArrayLit(id))`(**L599 raw constVal,未 mv 编码**)

## 对照 D102 §规则 1.1-1.4 分层 GATE 的 DRIFT 预估

D102 落地后累计组允许 ±0.5% 窗口(M1/M2/M3a/M5/N1/N2),结构组严格不升(M3b/M4/M6/M7a/M7b/N3/N4/N5)。cur 以 D101 Execute 1 后未 record 状态计,baseline 仍是 commit 9343330 值。

| 指标 | 组 | baseline | Execute 1 后 cur(估)| D103 step 1 后 cur(估)| Δ 相对 baseline | tol | 判定 | 依据 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5135 | 5135-5140 | +1~+6 | ±25 | OK/DRIFT | body 分支数近似,新函数签名 CC=1 |
| M2 | 累计 | 76126 | 76150 | **76165-76195** | **+39~+69** | ±380 | **DRIFT**(~5.5× 充裕)| 新函数签名节点 + 新 dispatch 行 + L132 扩一 kind + 删 outer `if kind == ARRAY_LIT` wrapper 节点。ARRAY_LIT body ~180 节点(TEMPLATE_LIT ~130 × 180/130 系数 → M2 增量 +8 × 1.4 = +12~+20 相对 Execute 1 后)|
| M3a | 累计 | 12122 | 12128 | 12133-12138 | +11~+16 | ±60 | OK/DRIFT | genVal → evalArrayLit 新边 +1;L132 扁平化少 1 调用;comptime 路径 interp* 边数守恒 |
| M3b | 结构 | 1879 | 1879 | 1879 | 0 | 0(严格)| OK | 不触最大入度函数(interpNewX 等热函数入度不变)|
| M4 | 结构 | 3037 | 3037 | 3035-3037 | -2 ~ 0 | 0(严格)| OK | genVal 内 `if kind == "ARRAY_LIT"` 删除,dispatch 链 -1;evalExpr 头部加 1 分派 +1 = 净 -1~0 |
| M5 | 累计 | 1750 | 1750 | 1750 | 0 | ±8 | OK | 不新增可变变量(SPREAD let srcI / allCt / fragVals 迁入不增总量) |
| M6 | 结构 | 32 | 32 | 32 | 0 | 0(严格)| OK | 不新增递归 |
| M7a | 结构 | 27 | 27 | 27 | 0 | 0(严格)| OK | 独立函数后 body depth 5 → 1-2,**不升**最大嵌套;evalArrayLit 函数内 depth 3-4(for 内 if 内 while 内 if) < 现有 M7a=27 |
| M7b | 结构 | 676 | 676 | **676**(+1 evalArrayLit,-1 Step 0 孤儿抵消)| **0** | 0(严格)| OK | **Step 0 必须预削减 1 函数,否则 GATE BLOCKED** |
| N1 | 累计 | 34 | 34 | 34 | 0 | ±1(保底)| OK | 不引入新 kind |
| N2 | 累计 | 380630 | 380750 | **380805-380890** | **+175~+260** | ±1903 | **DRIFT**(~7× 充裕)| M2 派生,body 三 for + 内层 while SPREAD 展开搬家 Halstead 波动。相对 Execute 1 后 +55~+140,按 180/130 线性缩放 TEMPLATE_LIT 实测 +40 → +55~+80 |
| N3 | 结构 | 518111 | 517873(估 -238)| **517473-517673**(估)| **-438 ~ -638**(相对 baseline) | 0(严格)| **PROGRESS** | body 三 for × 内 while(comptime SPREAD 展开)从 depth 4-5 搬到独立函数 depth 1-2;相对 Execute 1 后 -300~-500(比 TEMPLATE_LIT -238 大 1.5~2×,因 SPREAD 有 while 额外深度 +1)|
| N4 | 结构 | 321 | 321 | 321 | 0 | 0(严格)| OK | 不触最大节点出度函数 |
| N5 | 结构 | 0 | 0 | 0 | 0 | 0(严格)| OK | 不新增成员写入 |
| **F1:gen_exprs.ss** | - | 1721 | 1678(43 行余量)| **~1616** | **-105**(相对 baseline)/ **-62**(相对 Execute 1 后)| 单调下降 | **PROGRESS** | 删 L538-599 整块 62 行 inline body;+L132 shim 扩一 kind(字面扩展 `|| kind == "ARRAY_LIT"` ~20 字符 = 1 token,行数不增);净 -62 |

**累计组 6 项** 全落 DRIFT 窗口内(M2/N2 最大增量仍 5.5-7× 充裕),**结构组 8 项** 全 OK / PROGRESS(核心 M7b 0 / N3 大削),**F1** gen_exprs.ss PROGRESS(1721→1616 相对 baseline 累计 -105 行)。

## DRIFT 窗口二次生产验证(预期 vs D101 实测)

D101 Execute 1 TEMPLATE_LIT 迁移实测 `M2 +8 / N2 +40 / N3 -238 / F1 -42`,落在 Plan 预估 `M2 +20~50 / N2 +30~80 / N3 -155~-405 / F1 -42` 的窄区间内(M2 偏低、N2 中位、N3 中位、F1 精确)。D103 ARRAY_LIT body 比 TEMPLATE_LIT 大 ~40%(62 行 vs 42 行 / 180 节点 vs 130 节点)+ SPREAD_ELEM 分支有 while 循环额外深度 +1,按 D101 实测线性缩放:

- M2 预估 **+12~+20**(D101 实测 +8 × 1.5~2.5)—— 上限略高因 SPREAD 分支条件数多
- N2 预估 **+55~+80**(D101 实测 +40 × 1.4~2)—— 线性缩放
- N3 预估 **-300~-500**(D101 实测 -238 × 1.25~2)—— SPREAD while 额外 depth +1 贡献显著
- F1 预估 **-62**(精确 = body 行数)

若实测超预估上限 → 触发 D103 §新张力 1 "非线性膨胀"(SPREAD while 循环结构可能打破线性模型),Plan 内已列风险;若低于下限 → 说明 ARRAY_LIT body 节点冗余度比 TEMPLATE_LIT 高(更多字面量 `new Map()` / `interpNewArray("")` 分支),为 1b-4/5 迁移的 M2/N2 预估提供修正系数。

## 决策(分 3 步,每步独立 bootstrap + 分层 GATE PASS)

### §步骤 0 — 预削减 commit(拿 M7b ≥ -1 余量,抵消 step 1 新 evalArrayLit)

**目标**:结构组 M7b 严格不升,Step 1 新增 evalArrayLit +1 必须同 commit 内 -1 抵消或 Step 0 预先削减腾余量。**不钦定源**,Execute 0 按 PFV 流程 grep 实测选净削减最大项。

**候选削减源**(Execute 0 轮 grep 验证可行性):

1. **bootstrap 内孤儿 helper grep** — 迁移轮积累的调用点被吸收后的孤儿函数:
   - `grep -rn "^function " bootstrap/ | awk '{print $NF}' | sed 's/(.*$//' | sort | uniq -c`列出函数名
   - 对每函数名 `grep -rn "<name>(" bootstrap/` 统计调用点,零调用 = 孤儿可删
   - 可能候选:D101 Execute 1 后 `genValTemplateLit` 若存在已无调用(迁入 evalTemplateLit 后),但该函数 D101 Execute 1 已删除,不作候选
2. **gen_exprs.ss 内 dead helper** — D099/D100/D101 1a/1b-1/1b-2 合并后某些 runtime helper 可能无调用点:
   - `ctMapMethod` / `ctArrayMethod` / `ctStringMethod` 等 ct* helper(L1154-1336)若某分支已被 evalExpr 收拢,外部入口可能已无人调
   - 需 grep 实测
3. **eval_expr.ss 内 evalTernary / evalShortCircuit inline 回 evalExpr** — 两函数各 ~30 行,body depth 2-3,inline 回 evalExpr 的 `if k == "TERNARY"` / 字符串 op And/Or 分支,**风险**:evalExpr body 膨胀 ~60 行 + N3 微增,net 需实测,可能不划算
4. **单调用点 helper inline** — 找 `grep -rn "<helperName>(" bootstrap/` 仅 1-2 调用点的小 helper,inline 后删函数:
   - 候选如 `isCtStringIdx`(gen_exprs.ss:55,12 行)/ `resolveCtString`(gen_exprs.ss:68,12 行)若调用点少可评估
5. **tools/reflection_health_linter.ss 内小函数 inline** — 不作候选(linter 不扫自身)

**Execute 0 操作顺序**:
1. `grep -rn "^function " bootstrap/ | sort -t: -k3` + 统计每函数调用点
2. 找单调用 / 零调用候选 5-10 项
3. 估每候选 inline / 删除 后 N3 / M2 / F1 副作用
4. 选「M7b -1 且 N3 不升 且 M2 增量最小 且 F1 不升」
5. 单 commit 落地,bootstrap 固定点 PASS + linter 分层 GATE PASS

**验证**:
- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS,M7b 至少 -1

**若无单项可达 M7b -1**:step 0 拆 0a/0b 累积,但每 commit 独立 bootstrap + GATE PASS。

### §步骤 1 — ARRAY_LIT 迁移(独立函数 evalArrayLit,对称 pattern)

**新建 `bootstrap/eval_expr.ss` 末尾 `evalArrayLit(astId: int): int`**(对称 evalTemplateLit 模板):

```ss
function evalArrayLit(astId: int): int {
    const elemList = nGetList(astId)
    if (elemList == "") {
        if (comptimeDepth > 0) { return ctVal(interpNewArray("")) }
        return 0 - constVal(genArrayLit(astId)) - 1
    }
    let allCt = 1
    const arrParts = elemList.split(",")
    let elemVals = new Map()
    for (ap in arrParts) {
        const elemId = parseInt(ap)
        if (elemId > 0) {
            const isSpread = nGetKind(elemId) == "SPREAD_ELEM"
            const ev = isSpread == 1 ? genVal(nGetI1(elemId)) : genVal(elemId)
            elemVals.set(`${elemId}`, `${ev}`)
            if (isCt(ev) != 1) { allCt = 0 }
        }
    }
    if (comptimeDepth > 0) {
        const arr = interpNewArray("")
        for (ap in arrParts) {
            const elemId = parseInt(ap)
            if (elemId > 0) {
                const ev = parseInt(elemVals.getString(`${elemId}`))
                if (nGetKind(elemId) == "SPREAD_ELEM") {
                    if (isCt(ev) == 1 && interpType(payload(ev)) == "array") {
                        const srcArrId = payload(ev)
                        const srcLen = interpArrayLen(srcArrId)
                        let srcI = 0
                        while (srcI < srcLen) {
                            const srcElemId = interpArrayGet(srcArrId, srcI)
                            if (srcElemId > 0) { interpArrayPush(arr, srcElemId) }
                            srcI = srcI + 1
                        }
                    } else {
                        println(`error: [comptime] cannot spread non-array value at line ${nGetLine(elemId)}:${nGetCol(elemId)}`)
                        exit(1)
                    }
                } else {
                    interpArrayPush(arr, isCt(ev) == 1 ? payload(ev) : interpNewNull())
                }
            }
        }
        return ctVal(arr)
    }
    arrPreRegs = new Map()
    for (ap in arrParts) {
        const elemId = parseInt(ap)
        if (elemId > 0) {
            const ev = parseInt(elemVals.getString(`${elemId}`))
            if (nGetKind(elemId) == "SPREAD_ELEM") {
                arrPreRegs.set(`${nGetI1(elemId)}`, reg(ev))
            } else {
                arrPreRegs.set(`${elemId}`, reg(ev))
            }
        }
    }
    return 0 - constVal(genArrayLit(astId)) - 1
}
```

**关键点**:

- **坑 H 延续**:operand `genVal(nGetI1(elemId))` / `genVal(elemId)` 保留,**不递归 evalExpr**(elem 可为任意 kind,evalExpr dispatch 仅 7 kind)
- **坑 D101 §新张力 1 mv 编码延续**:原 L541 `return constVal(genArrayLit(id))` 和 L599 同款 raw constVal,迁入 evalArrayLit 后**必须包** `0 - constVal(...) - 1`(两处 runtime 返回都改)—— caller 走 L132 shim `mv >= 0 ? mv : 0 - mv - 1` 解码还原。**这是 ARRAY_LIT 迁移最大语义切点,字节级 IR 验证必过**
- **ct 分支** `return ctVal(...)` 不变(已是 mv 编码 known 分支),两处(空数组 L540 / comptime 分支 L585 原 `return ctVal(arr)`)
- **SPREAD 展开优化**:原 L549-557 两分支(SPREAD_ELEM / 普通 elem)合并为三元 `isSpread == 1 ? ... : ...`,M2 -3 / N2 -5(细节优化,节省余量以抵消新函数签名节点)

**改 `bootstrap/gen_exprs.ss` L132 shim**:

```ss
// BEFORE(6 kind)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
// AFTER(7 kind)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
```

**改 `bootstrap/eval_expr.ss` evalExpr 头部**(L59 TEMPLATE_LIT 分派后加):

```ss
if (k == "ARRAY_LIT") { return evalArrayLit(astId) }
```

**删 `bootstrap/gen_exprs.ss` L537-599 整块**(62 行 ARRAY_LIT inline body,含 outer `if kind == "ARRAY_LIT"` header)

**独立验证链**(tokenize → parse → eval):

1. **Tokenizer**:`[` / `]` / `,` 不改,parse_exprs.ss ARRAY_LIT parse 不改 —— **parse 层零影响**
2. **check_stmts.ss** ARRAY_LIT checkExpr 不改(checker 只做类型推断,不走 eval 路径)
3. **eval 路径**:`genVal(ARRAY_LIT) → L132 shim → evalExpr → evalArrayLit`,对称 TEMPLATE_LIT 走通链
4. **runtime IR emit**:`genArrayLit(id)` 不迁,gen_calls.ss L607+ 保留 —— **IR 输出字节级不变**(除 caller 从 L132 shim 走 mv 解码,但解码后 reg str 与原 raw constVal 返回同值)

**验证**:

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- ARRAY_LIT 测试全绿:空数组 / 元素均 comptime / 含 runtime elem / SPREAD_ELEM comptime 展开 / SPREAD_ELEM runtime / 嵌套数组 / 混合 string+int 字面量
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK / PROGRESS(核心 M7b 0 / N3 PROGRESS -300~-500)
  - 累计组 6 项 OK / DRIFT / PROGRESS(M2 +12~20 / N2 +55~80 均在 DRIFT 窗口内)
  - F1:gen_exprs.ss PROGRESS(1721 → ~1616,累计 -105)

### §步骤 2 — 收尾评估 + 指向 1b-4

**目标**:step 1 完成后决策是继续 1b 下一 kind 还是 record baseline。默认**不 record**(延续 D100 §步骤 2 / §坑 Q / D101 §步骤 2 策略),等 1b 全部 5 kind 落地后单 commit record。

**决策点**:

- step 1 后 M7b 余量 / N3 余量 充足 → 另起 D104 选 IDENT(5 路径耦合虽重但 body 仅 40 行)或 MEMBER_ACCESS(123 行但需触反射 gate 专章)
- 余量紧张 → 独立 commit record 释放余量给下 kind
- F1:gen_exprs.ss 目标 ≤ 600,当前 1678 → 1616 后仍 > 600,需 1b-4/5 继续削减;估 IDENT -40 / MEMBER_ACCESS -123,1b 全完 ~1453,仍 > 600,Phase A 后批 2 继续

**1b-4 候选选型提示(D104 Plan 范围,非本轮)**:

- **IDENT(body 40 行,5 路径耦合)**:适合在反射 gate 专章前作过渡 kind,验证 scope 机制迁移是否可行;若 ctScopeStack / ctInvalidated / genericTypeSubs 机制可干净迁入 evalIdent 则 1b-4 选此,否则推 Phase A 后批 2
- **MEMBER_ACCESS(body 123 行,反射 gate)**:必须独立 Plan + 反射 gate 专章,G1-G5 全部打勾,Plan 复杂度显著高于其他 1b kind

## Rejected Alternatives

### §A — 1b-3 选 IDENT

**拒绝理由**:

- 40 行但 **5 路径耦合**(ctInvalidated / ctScopeStack / genericTypeSubs / resolveCtTypeAlias / ctVars),scope 机制需 Phase B MaybeVal 类化期吸收(D098 §决策 2)
- D099 §Rejected A / D100 §Rejected C / D101 §Rejected B 三次否决作早期 kind
- ARRAY_LIT 有 D100:L151 / D101:L200 两次明确位置预言(1b-3),路线承诺已下
- **正确位置:1b-4 或推 Phase A 后批 2**

### §B — 1b-3 选 MEMBER_ACCESS

**拒绝理由**:

- 123 行 + 触 **反射根因 gate**(CLAUDE.md §反射根因 gate 强制条款 + D097),必过 reflection_health_linter G1-G5
- D100 §Rejected D / D101 §Rejected C 已明言:「含 D095 FieldMeta / D097 AnnotationMeta 累积路径,本轮不应承担」
- **正确位置:1b 末轮,独立 Plan + 反射 gate 专章**

### §C — 跳过 Step 0,直接 Step 1 inline ARRAY_LIT body 到 evalExpr(不建独立函数)

**拒绝理由**:

- body 180 节点 × 三 for 循环 × 内层 while SPREAD 展开 inline 到 evalExpr 头部 `if k == ARRAY_LIT` 块,evalExpr body 继续膨胀(当前 ~100 行 + 62 行 = ~162 行)
- N3 严格不升,body inline depth +5~+6(最深处 for→if→while→if)会炸 N3 +400~600 远超余量
- D099 §坑 L / D101 §新张力 2 已确认:runtime phi / N 元迭代 / SPREAD 展开结构必走独立函数
- **正确路径:独立函数 evalArrayLit,对称 evalTemplateLit pattern**

### §D — Step 1 一次 bundle TEMPLATE_LIT + ARRAY_LIT 两 kind(无 Step 0)

**拒绝理由**:

- D101 Execute 1 已独立 commit TEMPLATE_LIT,bundle 违反单步独立可回滚原则
- Plan 粒度守则:一 commit 一 kind,每 commit bootstrap + GATE 独立 PASS
- **正确路径:D103 独立轮,Step 0 + Step 1 + Step 2 三 commit**

### §E — 把 ARRAY_LIT 与 IDENT 合并到单 D104 Plan(1b 末批两 kind 一起)

**拒绝理由**:

- ARRAY_LIT 和 IDENT subsystem 耦合差异极大(ARRAY_LIT 零 scope / IDENT 5 scope 路径),合并 Plan 无共用模板
- D100/D101 建立的「一 Plan 一 kind」精准粒度,合并破坏可追溯
- **正确路径:D103 单 ARRAY_LIT,D104 单 IDENT(或 MEMBER_ACCESS)**

## 新张力(D103 引出)

1. **原 gen_exprs.ss L541 / L599 两处 raw constVal 编码** — 与 D101 §新张力 1(TEMPLATE_LIT L578 raw constVal)同款问题,**但 ARRAY_LIT 有两处**(空数组 runtime path L541 + 非空 runtime path L599),迁入 evalArrayLit 后两处都必须改为 `0 - constVal(...) - 1`。**验证点**:若漏改任一处 → caller 拿到 reg str 被当 known val 处理 → comptime 折叠误判或字节级 IR 差异。Execute 1 必须**单测两条路径**:(a) `[]` 空数组 runtime(`function f() { return [] }`)/ (b) `[expr1, expr2]` runtime mixed(`function f(x: int) { return [x, x+1] }`)
2. **arrPreRegs 全局 Map 迁移语义** — 当前 `gen_exprs.ss:587` `arrPreRegs = new Map()` 重置,L593/L595 `arrPreRegs.set(...)` 填充,`gen_calls.ss:645/653/687` 三处 read。迁入 evalArrayLit 后三处操作同函数内保留 write,**但 evalArrayLit 在 runtime 非空分支才触发该 Map 操作**,comptime 分支早 return 不污染 Map;runtime 空分支(elemList == "")亦无 Map 操作。**验证点**:嵌套 array 场景(外层 ARRAY_LIT runtime,内层 ARRAY_LIT comptime)Map 状态是否正确 —— 当前 inline body 已有该问题,迁移**不改变语义**,但需确认测试覆盖
3. **eval_expr.ss 函数数攀升** — step 1 后 6 函数(evalExpr + 5 eval*),1b 全完 8 函数(+evalIdent + evalMemberAccess)。D100 §新张力 2 / D101 §新张力 3 已提:「Phase B 类化期需评估是否压回单 evalExpr body(MaybeVal class 携带 state 后可能 inline 回无深度代价)」。D103 延续该风险,不在本轮解决
4. **Step 0 候选非线性风险** — Execute 0 grep 孤儿 helper 若未找到单项达标,需 inline 单调用 helper,但 inline 可能触发 N3 副作用(depth 局部 +1)。**对策**:Execute 0 对每候选实测 inline 后 N3 / M2 / F1 三指标,若 M7b -1 但 N3 +5 反赌 step 1 N3 大削抵消;若 M7b -1 + N3 不变则最优
5. **D102 ±0.5% DRIFT 窗口二次生产验证** — 本 Plan 预估 M2 +39~69 / N2 +175~260(相对 baseline),均在 ±380 / ±1903 窗口内 5.5-7× 充裕(比 D101 的 20-60× 略紧,因 ARRAY_LIT body 更大)。若实测超 DRIFT → 说明 D102 ±0.5% 阈值对大 body 迁移偏紧,触发 D104(Plan 内新决策)按每 kind body 大小细化窗口系数
6. **SPREAD_ELEM 分支 depth 4-5 非线性膨胀风险** — ARRAY_LIT body 最深处 `comptime 分支内 for elemId → if SPREAD_ELEM → if isCt+type==array → while srcI < srcLen → if srcElemId > 0 → interpArrayPush`,共 5 层。**相比 TEMPLATE_LIT 最深 depth 4**(for tp → if TMPL_FRAG_EXPR → if fragVals.has → if isCt → 赋值),depth +1 是线性缩放模型的**风险变量**。若实测 N3 削减低于预估下限(< -300)→ 说明 depth +1 不贡献额外削减,模型偏差需修正

## 下一步(Plan 下的 Execute 顺序)

1. [x] Done at commit 6197667 — **Execute 0**:删 bootstrap/prelude.ss L208-252 的 9 个 @derive 死 helpers(`_ss_hashContrib`/`_ss_jsonValue`/`_ss_zero` × int/string/double 三重载,45 行)。grep bootstrap/ lib/ tests/ 全域零调用,@derive 无活跃 ctDeriveX handler。GATE PASS 实测:M7b 676→667 **delta=-9 PROGRESS**(超额目标 ≥-1,腾余量 9 足供 1b-3~5 迁移)/ N3 -513 / M1 -9 / M2 -61 / M3a -3 / M5 -2 / N2 -305 全 PROGRESS / 严格组 OK / F1 gen_exprs.ss 1678(D101 Execute 1 效应保留)/ bootstrap 固定点 PASS / 4 pre-existing tests fail 与改动无关(stash+rebuild 反向验证)
2. [ ] Planned — **Execute 1**:ARRAY_LIT 迁移 evalArrayLit(对称 evalTemplateLit);同 commit 改 L132 shim 扩 7 kind + evalExpr 头部加 1 分派 + 删 L537-599。单 commit bootstrap PASS + 分层 GATE PASS(M7b 0 / N3 PROGRESS -300~-500 / M2 DRIFT +12~20 / N2 DRIFT +55~80 / F1:gen_exprs.ss -62)
3. [ ] Planned — **Execute 2**:收尾评估(record vs 继续 1b-4;默认继续)+ 起 D104 选 IDENT 或 MEMBER_ACCESS

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- D101 §步骤 1 evalTemplateLit(对称三段式模板)/ §新张力 1 mv 编码强制 / §新张力 2 全局 Map 迁移语义 / Execute 1 实测(M2 +8 / N2 +40 / N3 -238 / F1 -42)
- D100 §Rejected B(ARRAY_LIT 推 1b 末轮)/ §坑 P(M2/N2 迁移成本模型)/ §坑 Q(银行余量不 record)
- D102 §规则 1.1-1.4(分层 GATE + DRIFT 窗口)/ §规则 2.1-2.3(F1 文件行数 GATE)
- D099 §坑 G-O(N3/M7b 成本模型)
- D098 §决策 1 MaybeVal Phase A mv 编码
- D094 §规则 2 pure subset 白名单(ARRAY_LIT 归属 L104)
- D088 §第一性需求(Zig 路线 SEMA 收敛)
- CLAUDE.md §反射根因 gate(1b-3 ARRAY_LIT 不触,但 1b-5 MEMBER_ACCESS 必触)
- `bootstrap/gen_exprs.ss:537-599`(ARRAY_LIT 当前 inline 62 行)
- `bootstrap/gen_exprs.ss:132`(L132 shim,当前 6 kind)
- `bootstrap/gen_calls.ss:7`(arrPreRegs 全局 Map)/ `:607+`(genArrayLit runtime 侧,不迁)/ `:645/653/687`(arrPreRegs 三处 read)
- `bootstrap/eval_expr.ss:191-233`(evalTemplateLit 对称模板,D101 Execute 1)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt` @ D101 Execute 0 commit 9343330(F1 1721 / M7b 676)
