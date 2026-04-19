# D104: evalExpr Phase A 中批 1b 第 4 kind Plan — IDENT

**Status:** 首轮 Plan,Execute 0 未开工
**Depends on:** D103 §步骤 2(指向 D104 选 IDENT 或 MEMBER_ACCESS) / D101 §步骤 1 evalTemplateLit 对称 pattern / D103 §步骤 1 evalArrayLit 对称 pattern / D100 §坑 Q(银行余量不 record)/ D102 §规则 1.1-1.4(分层 GATE + ±0.5% DRIFT)/ D102 §规则 2.1-2.3(F1 文件行数 GATE)/ D098 §决策 1 mv 编码 / D098 §决策 2 Phase B MaybeVal 类化 / D094 §规则 2 pure subset 白名单(L104 `IDENT` 在列)/ D088 §第一性需求(Zig SEMA 一份 evalExpr 函数)/ CLAUDE.md §反射根因 gate
**Date:** 2026-04-19

---

## 第一性需求

D103 Execute 1 已合并 ARRAY_LIT(1b 第 3 kind),eval_expr.ss 新增 evalArrayLit 独立函数 + evalExpr L60 dispatch + L132 shim 扩 7 kind,**实测超预估**:`M7b 676→668 Δ=-8 PROGRESS(Execute 0 -9 + Execute 1 +1) / N3 518111→516994 Δ=-1117 PROGRESS(预估 -300~-500 超 2×+)/ N2 380630→380310 Δ=-320 PROGRESS(反向优于 DRIFT 窗口)/ M2 76126→76082 Δ=-44 PROGRESS / F1:gen_exprs.ss 1721→1614 Δ=-107`。结构组 8 项全 OK/PROGRESS,累计组 6 项全 PROGRESS。D102 ±0.5% DRIFT 窗口二次生产验证**反向通过**(实测全部 PROGRESS,连 DRIFT 都没触发)。baseline 当前(仍 D101 Execute 0 commit 9343330 record,Execute 1/D103 0-1 均未 record,**银行余量累积**):

```
M1=5134  M2=76126  M3a=12122  M3b=1879  M4=3037
M5=1750  M6=32     M7a=27     M7b=676   N1=34
N2=380630  N3=518111  N4=321  N5=0
F1:bootstrap/gen_exprs.ss=1721  (+ 13 条其他)
```

cur 实际值(D103 Execute 1 后):`M7b=668(bank +8)/ N3=516994(bank -1117)/ M2=76082(bank -44)/ N2=380310(bank -320)/ F1:gen_exprs.ss=1614(bank -107)`,**4 项余量显著富裕**(M7b 最紧 +8 / N3 结构组深窖 -1117 / F1 累计 -107)。

**本 Plan 选 IDENT 作 1b-4 kind**,承接 D094 §规则 2 pure subset 余项(D100/D101/D103 完成 INDEX_ACCESS/TEMPLATE_LIT/ARRAY_LIT,余 2 项 IDENT / MEMBER_ACCESS)。D103:L246 §步骤 2 明言「1b-4 候选选型提示:IDENT(body 40 行,5 路径耦合)—— 适合在反射 gate 专章前作过渡 kind,验证 scope 机制迁移是否可行;若 ctScopeStack / ctInvalidated / genericTypeSubs 机制可干净迁入 evalIdent 则 1b-4 选此,否则推 Phase A 后批 2」。**本轮接位置预言**,MEMBER_ACCESS 推 1b-5 独立 Plan(D105 反射 gate 专章)。

## 为什么 1b-4 选 IDENT(2 候选对照,3 候选扣除已落)

| kind | 体量(行) | 节点密度(估) | subsystem 耦合 | Step 0 预削减压力 | 反射 gate |
|---|---|---|---|---|---|
| **IDENT** | L134-174,**41 行** | ~150 | **5 路径 scope 机制**(ctScopeStack / ctVars / ctInvalidated / comptimeDepth+interpFindScopeKey / genericTypeSubs+resolveCtTypeAlias)| 中(scope 耦合深但体量小) | **不触** |
| MEMBER_ACCESS | L340-462,123 行 | ~400 | **反射根因 gate**(D095 FieldMeta / D097 AnnotationMeta / enum / class static field)| 极高(必过 reflection_health_linter G1-G5) | **触 §反射根因 gate** |

**IDENT 首选依据**:

1. **D103:L246 §步骤 2 已明言位置预言** — 「IDENT 适合在反射 gate 专章前作过渡 kind」,本轮接该预言,MEMBER_ACCESS 推独立 D105 反射专章
2. **零反射 gate 触发** — IDENT 纯 scope 查找 + ctVars 读 + genericTypeSubs 读 + class 名作 TypeValue,不触 D095 FieldMeta / D097 AnnotationMeta / 反射路径,相比 MEMBER_ACCESS 风险显著更低
3. **体量适中** — 41 行 body(L134-174),比 TEMPLATE_LIT 42 行略小,比 ARRAY_LIT 62 行显著小,迁移工程量可控
4. **scope 机制迁移验证价值** — 5 路径 ctScopeStack / ctVars / ctInvalidated / interpFindScopeKey / genericTypeSubs 全部为**只读**(IDENT 不写 scope,POSTFIX_INC 才写),干净迁入 evalIdent 可行性高;若实测污染 evalExpr 调用链(嵌套 comptime 场景)则触发 D104 §新张力 1,Plan 退回 Phase A 后批 2
5. **银行余量富裕** — 当前 M7b +8 / N3 -1117 / F1 -107,Step 0 预削减压力**远低于** D100/D101/D103(分别 M7b +2/+0/+0 余量启动);可走「Step 0 轻量 -1 M7b」或「Step 0-1 合并(Execute 1 bundle 腾 + 迁)」
6. **F1 单削 41 行** — `bootstrap/gen_exprs.ss` 当前 1614 行,删 41 行后 ~1573,距 F1 目标 ≤ 600 仍远,但 1b-4 + 1b-5 全完 ~1450,Phase A 后批 2 继续削减

## 当前事实(2026-04-19 snapshot)

| 项 | 值 / 位置 |
|---|---|
| IDENT 分派 | `bootstrap/gen_exprs.ss:134-174`(**41 行 inline**,header `if (kind == "IDENT")` 在 L134) |
| genIdent(runtime 侧,不迁)| `bootstrap/gen_exprs.ss:17-27`(11 行,已独立函数) |
| L132 shim | `|| kind == "ARRAY_LIT"`(D103 扩至 7 kind) |
| eval_expr.ss | 293 行,6 函数(evalExpr + evalTernary + evalShortCircuit + evalIndexAccess + evalTemplateLit + evalArrayLit) |
| IDENT scope 路径 5 项 | (1) ctScopeStack 域链 L136-145 / (2) ctVars+ctInvalidated L146-150 / (3) interpFindScopeKey+interpVars L151-155 / (4) isKnownClass+interpNewType L156-159 / (5) genericTypeSubs+resolveCtTypeAlias+interpNewType L160-171 |
| runtime 回退 | L173 `return constVal(genIdent(id))` **raw constVal,未 mv 编码**(对称 D103 §新张力 1 ARRAY_LIT L541/L599 问题) |

**IDENT body 结构**(L134-174 逐层):

- **L134**:header `if (kind == "IDENT") {`
- **L135**:`const ctIdName = nGetS1(id)`
- **L136-145**:scope 域链倒序遍历(comptimeDepth > 0 且 ctScopeStack.length > 0)—— while depth 2,**body 最深 depth 3**
- **L146-150**:currentFunc scope + ctVars 查找 + ctInvalidated 过滤
- **L151-171**:comptimeDepth > 0 分支(4 子路径)
  - L151-155:interpFindScopeKey + interpVars 解释器 scope
  - L156-159:class 名作 TypeValue(isKnownClass)
  - L160-167:genericTypeSubs + isKnownClass(泛型实参)
  - L168-171:resolveCtTypeAlias(类型别名)
- **L173**:runtime 回退 `return constVal(genIdent(id))`(**raw constVal,迁入 evalIdent 后必包 mv 编码**)

## 对照 D102 §规则 1.1-1.4 分层 GATE 的 DRIFT 预估

D102 落地后累计组允许 ±0.5% 窗口(M1/M2/M3a/M5/N1/N2),结构组严格不升(M3b/M4/M6/M7a/M7b/N3/N4/N5)。cur 以 D103 Execute 1 后未 record 状态计,baseline 仍是 commit 9343330 值。

| 指标 | 组 | baseline | D103 Execute 1 后 cur | D104 step 1 后 cur(估)| Δ 相对 baseline | tol | 判定 | 依据 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5125 | 5125-5130 | -4~-9 | ±25 | OK/PROGRESS | Step 0 若删孤儿 helper 继续 -1~-3,body 分支数近似 |
| M2 | 累计 | 76126 | 76082 | 76095-76115 | -11~-31 | ±380 | PROGRESS | 新函数签名节点 +12 + 新 dispatch 行 +4 + L132 扩一 kind +3 + 删 outer `if kind == IDENT` wrapper -2。净 +13~+17 相对 Execute 1 后 |
| M3a | 累计 | 12122 | 12125 | 12130-12135 | +8~+13 | ±60 | OK | genVal → evalIdent 新边 +1;L132 扁平化少 1 调用 |
| M3b | 结构 | 1879 | 1879 | 1879 | 0 | 0(严格)| OK | 不触最大入度函数 |
| M4 | 结构 | 3037 | 3035 | 3033-3035 | -2~-4 | 0(严格)| OK/PROGRESS | genVal 内 `if kind == "IDENT"` 删除 -1;evalExpr 头部加 1 分派 +1 = 净 -1~0 |
| M5 | 累计 | 1750 | 1750 | 1750 | 0 | ±8 | OK | 不新增可变变量(while ctSi / let ctSi 迁入不增总量) |
| M6 | 结构 | 32 | 32 | 32 | 0 | 0(严格)| OK | 不新增递归 |
| M7a | 结构 | 27 | 27 | 27 | 0 | 0(严格)| OK | 独立函数后 body depth 3 → 1-2,不升最大嵌套;evalIdent 函数内 depth 2-3 < 现有 M7a=27 |
| M7b | 结构 | 676 | 668 | **669**(+1 evalIdent,可选 Step 0 -1 抵消至 668)| **-7 ~ -8** | 0(严格)| **OK**(bank +7~+8 充裕)| **Step 0 可选,余量充裕允许 +1 不预削减** |
| N1 | 累计 | 34 | 34 | 34 | 0 | ±1(保底)| OK | 不引入新 kind |
| N2 | 累计 | 380630 | 380310 | 380330-380360 | -270~-300 | ±1903 | PROGRESS | M2 派生;相对 Execute 1 后 +20~+50,body 5 路径搬家 Halstead 波动 |
| N3 | 结构 | 518111 | 516994 | **516794-516944**(估)| **-1167 ~ -1317**(相对 baseline)| 0(严格)| **PROGRESS** | body scope 路径 while depth 3 + 4 子路径 if 链搬到独立函数 depth 1-2;相对 Execute 1 后 -50~-200(比 ARRAY_LIT -1117 小,IDENT body depth 更浅) |
| N4 | 结构 | 321 | 321 | 321 | 0 | 0(严格)| OK | 不触最大节点出度函数 |
| N5 | 结构 | 0 | 0 | 0 | 0 | 0(严格)| OK | 不新增成员写入 |
| **F1:gen_exprs.ss** | - | 1721 | 1614 | **~1573** | **-148**(相对 baseline)/ **-41**(相对 Execute 1 后)| 单调下降 | **PROGRESS** | 删 L134-174 整块 41 行 inline body;+L132 shim 扩一 kind(字面扩展 `|| kind == "IDENT"` ~15 字符 = 1 token,行数不增);净 -41 |

**累计组 6 项** 全落 PROGRESS / OK(反向富裕,无 DRIFT 风险),**结构组 8 项** 全 OK / PROGRESS(核心 M7b +1 bank 吸收 / N3 继续大削 -50~-200),**F1** gen_exprs.ss PROGRESS(1721→1573 相对 baseline 累计 -148 行)。

## DRIFT 窗口三次生产验证(预期 vs D101/D103 实测)

| kind | body 行 | 节点估 | M2 实测 | N2 实测 | N3 实测 | F1 实测 |
|---|---|---|---|---|---|---|
| D101 TEMPLATE_LIT | 42 | 130 | +8 | +40 | -238 | -42 |
| D103 ARRAY_LIT | 62 | 180 | -44 | -320 | -1117 | -107(累计) |
| **D104 IDENT(预估)** | **41** | **150** | **+13~+17** | **+20~+50** | **-50~-200** | **-41** |

**预估偏差来源**:
- M2/N2 比 TEMPLATE_LIT 略高 —— IDENT 有 5 路径 scope 分支(TEMPLATE_LIT 仅 2 分支 comptime/runtime),分支条件数多
- N3 比 TEMPLATE_LIT/ARRAY_LIT 显著小 —— IDENT body 最深 depth 3(ARRAY_LIT depth 5,TEMPLATE_LIT depth 4),搬家后深度差小
- F1 精确 = body 行数

若实测 M2 超 +20 或 N3 低于 -50 → 触发 D104 §新张力 1 scope 机制非线性风险,Plan 需修正或退回。

## 决策(分 3 步,每步独立 bootstrap + 分层 GATE PASS)

### §步骤 0 — 可选预削减 commit(银行余量富裕,默认跳过)

**决策**:D104 Step 0 **默认跳过**,直接 Execute 1 IDENT 迁移。依据:

- 当前 M7b=668,baseline 676,bank +8 余量 **远大于** +1(evalIdent 新函数)
- D102 §规则 1.1 结构组严格 ≤ baseline,668+1=669 ≤ 676 **通过**
- 跳过 Step 0 节省 1 轮 Execute,银行策略精神(延续 D100 §坑 Q)= 累积余量直到 1b 全完再 record,本轮无需再腾

**例外触发条件**(若 Step 1 预估超预期则回退此步):
- Execute 1 实测 N3 反向不降(估 -50~-200 未达下限)→ 触发 Step 0 补削减(grep 孤儿 helper / inline 单调用点,对称 D103 Execute 0 模式)
- Execute 1 实测 M7b 净 +2 或更多(evalIdent 意外拆子函数)→ 触发 Step 0 补削减

**若触发 Step 0**:按 D103 §步骤 0 候选清单(bootstrap 孤儿 helper grep / 单调用 helper inline / ct* helper 合并)操作,单 commit 落地,bootstrap 固定点 PASS + linter 分层 GATE PASS。

### §步骤 1 — IDENT 迁移(独立函数 evalIdent,对称 pattern)

**新建 `bootstrap/eval_expr.ss` 末尾 `evalIdent(astId: int): int`**(对称 evalTemplateLit / evalArrayLit 模板):

```ss
function evalIdent(astId: int): int {
    const ctIdName = nGetS1(astId)
    if (comptimeDepth > 0 && ctScopeStack.length() > 0) {
        let ctSi = ctScopeStack.length() - 1
        while (ctSi >= 0) {
            const ctScopeKey = `${ctScopeStack[ctSi]}:${ctIdName}`
            if (ctVars.has(ctScopeKey) == 1) {
                return parseInt(ctVars.getString(ctScopeKey))
            }
            ctSi = ctSi - 1
        }
    }
    const ctKey = `${currentFunc}:${ctIdName}`
    if (ctVars.has(ctKey) == 1 && ctInvalidated.has(ctKey) == 0) {
        const ctIdVal = parseInt(ctVars.getString(ctKey))
        if (isCt(ctIdVal) == 1) { return ctIdVal }
    }
    if (comptimeDepth > 0) {
        const ctInterpKey = interpFindScopeKey(ctIdName)
        if (ctInterpKey != "") {
            return ctVal(parseInt(interpVars.getString(ctInterpKey)))
        }
        if (isKnownClass(ctIdName) == 1) {
            return ctVal(interpNewType(ctIdName))
        }
        if (genericTypeSubs.has(ctIdName) == 1) {
            const ctSubName = genericTypeSubs.getString(ctIdName)
            if (isKnownClass(ctSubName) == 1) {
                return ctVal(interpNewType(ctSubName))
            }
        }
        const ctAliased = resolveCtTypeAlias(ctIdName)
        if (ctAliased != ctIdName) {
            return ctVal(interpNewType(ctAliased))
        }
    }
    return 0 - constVal(genIdent(astId)) - 1
}
```

**关键点**:

- **坑 mv 编码延续**:原 L173 `return constVal(genIdent(id))` raw constVal,迁入 evalIdent 后**必须包** `0 - constVal(...) - 1`(对称 D101 TEMPLATE_LIT / D103 ARRAY_LIT 处理)—— caller 走 L132 shim `mv >= 0 ? mv : 0 - mv - 1` 解码还原。**这是 IDENT 迁移字节级 IR 验证必过点**
- **ct 分支** `return ctVal(...)` / `return parseInt(ctVars.getString(...))` 不变(已是 mv 编码 known 分支),5 条 return 路径保持
- **scope 机制只读** — IDENT 不写 scope(ctScopeStack.push / ctVars.set / ctInvalidated.set 都在 let/const/POSTFIX_INC 等其他 kind),迁入 evalIdent **零副作用扩散风险**
- **helper 不迁** — `interpFindScopeKey` / `isKnownClass` / `resolveCtTypeAlias` 三个 helper 保留在原位,对称 TEMPLATE_LIT `genTemplateLit` / ARRAY_LIT `genArrayLit` 不迁模式

**改 `bootstrap/gen_exprs.ss` L132 shim**:

```ss
// BEFORE(7 kind)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
// AFTER(8 kind)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
```

**改 `bootstrap/eval_expr.ss` evalExpr 头部**(加 IDENT 分派):

```ss
if (k == "IDENT") { return evalIdent(astId) }
```

**删 `bootstrap/gen_exprs.ss` L134-174 整块**(41 行 IDENT inline body,含 outer `if kind == "IDENT"` header)

**独立验证链**(tokenize → parse → eval):

1. **Tokenizer**:IDENT token 不改,parse_exprs.ss IDENT parse 不改 —— **parse 层零影响**
2. **check_stmts.ss** IDENT checkExpr 不改(checker 只做类型推断,不走 eval 路径)
3. **eval 路径**:`genVal(IDENT) → L132 shim → evalExpr → evalIdent`,对称 TEMPLATE_LIT/ARRAY_LIT 走通链
4. **runtime IR emit**:`genIdent(id)` 不迁,gen_exprs.ss L17-27 保留 —— **IR 输出字节级不变**

**验证**:

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- IDENT 测试全绿:简单变量读 / scope 链 / ctInvalidated / comptime class 名 / 泛型实参 T / 类型别名 / 嵌套 comptime block
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK / PROGRESS(核心 M7b 669 ≤ 676 bank / N3 PROGRESS -50~-200)
  - 累计组 6 项 OK / PROGRESS(M2 +13~+17 / N2 +20~+50 均在 DRIFT 窗口内)
  - F1:gen_exprs.ss PROGRESS(1614 → ~1573,累计 -148)

### §步骤 2 — 收尾评估 + 指向 1b-5(必起 D105 反射 gate 专章)

**目标**:step 1 完成后决策是继续 1b-5 MEMBER_ACCESS 还是 record baseline。默认**不 record**(延续 D100 §坑 Q / D101 §步骤 2 / D103 §步骤 2 银行策略),1b 全完 5 kind 后单 commit record。

**决策点**:

- step 1 后 M7b 余量 / N3 余量 充足 → 另起 **D105 Plan**,MEMBER_ACCESS body 123 行 + 反射 gate 专章
- 余量紧张 → 独立 commit record 释放余量给 MEMBER_ACCESS
- F1:gen_exprs.ss 目标 ≤ 600,当前 1614 → 1573 后仍 > 600,MEMBER_ACCESS 删 123 行 → ~1450,仍 > 600,Phase A 后批 2 继续削减

**1b-5 候选选型提示(D105 Plan 范围,非本轮)**:

- **MEMBER_ACCESS 独立 Plan 必须**:
  - **反射 gate 专章**:D095 FieldMeta(f.name / f.type / f.annotations)/ D097 AnnotationMeta / enum 值访问 / class static field 四个反射触点分章节
  - **改动前后各跑 `bin/ss run tools/reflection_health_linter.ss`**,G1-G4 不升 / G5 不降阻断 commit(CLAUDE.md §反射根因 gate 强制)
  - **interpGetField / interpSetField / classNodeIds 语义迁移验证**(对称 TEMPLATE_LIT `tmplPreRegs` / ARRAY_LIT `arrPreRegs` 全局 Map 迁移语义)
  - **comptimeError 错误路径保留**(L457-459)
  - **genOptionalMemberAccess / genMemberAccess 双 runtime 回退**(L460-461)不迁

## Rejected Alternatives

### §A — 1b-4 选 MEMBER_ACCESS

**拒绝理由**:

- 123 行 body(L340-462)+ 触 **反射根因 gate**(CLAUDE.md §反射根因 gate 强制条款 + D097),必过 reflection_health_linter G1-G5
- D100 §Rejected D / D101 §Rejected C / D103 §Rejected B 三次明言:「含 D095 FieldMeta / D097 AnnotationMeta 累积路径,本轮不应承担」
- 若 1b-4 选此,**1b-5 无对称 kind 可选**(IDENT 被推后),造成 1b 序列"反射专章在前、scope 过渡 kind 在后"的倒置,破坏 Plan 粒度递增原则
- **正确位置:1b-5 独立 D105 Plan + 反射 gate 专章**

### §B — 1b-4 bundle IDENT + MEMBER_ACCESS 两 kind(单轮 Plan)

**拒绝理由**:

- Plan 粒度守则:一 Plan 一 kind,每 commit bootstrap + GATE 独立 PASS(D100/D101/D103 建立)
- IDENT 与 MEMBER_ACCESS subsystem 耦合差异极大(IDENT 5 scope 路径无反射 / MEMBER_ACCESS 反射 gate 4 触点),合并 Plan 无共用模板
- 反射 gate 专章要求独立 Plan(CLAUDE.md §反射根因 gate 隐含)
- **正确路径:D104 单 IDENT,D105 单 MEMBER_ACCESS**

### §C — 跳过 1b-4 直接 record baseline(提前 release 余量)

**拒绝理由**:

- 银行策略(D100 §坑 Q / D101 §步骤 2 / D103 §步骤 2)核心是**累积余量到 1b 全完再 record**,提前 record 损失后续 kind 迁移的余量累积效应
- 当前余量 M7b +8 / N3 -1117 / F1 -107 **显著富裕**,无 record 动机
- record 本身也是一次 commit,Plan 粒度守则不允许"仅 record 无功能改动"单独成 kind
- **正确路径:继续 1b-4 IDENT 迁移,银行余量继续累积**

### §D — 1b-4 推 Phase A 后批 2(不在本轮做 IDENT)

**拒绝理由**:

- D103:L246 §步骤 2 位置预言:「若 scope 机制可干净迁入 evalIdent 则 1b-4 选此,否则推 Phase A 后批 2」
- IDENT scope 机制**全部只读**(见 §步骤 1 关键点),干净迁入可行性高,无需等 D098 §决策 2 Phase B MaybeVal 类化
- 余量富裕(+8 M7b / -1117 N3)支持本轮迁移,推后无收益
- 若 Execute 1 实测 scope 污染(嵌套 comptime 场景)→ 触发 §新张力 1,**本 Plan 退回**,此时再推 Phase A 后批 2
- **正确路径:本轮尝试 IDENT,保留退回选项,不预先推后**

### §E — Step 0 强制预削减(不跳过)

**拒绝理由**:

- 当前 M7b bank +8 充裕,对照 D100 Step 0 启动时 M7b +2 / D101 启动时 M7b 0 / D103 启动时 M7b 0,余量呈 **指数级富裕**
- 强制 Step 0 多消耗 1 轮 Execute 无价值,银行策略精神是累积余量,不是强制消耗
- D103 §步骤 0 已证 @derive 孤儿清除是"一次性红利",后续 Step 0 候选递减(ct* helper 合并 / 单调用 inline 等效应小)
- **正确路径:Step 0 默认跳过,例外触发条件见 §步骤 0**

## 新张力(D104 引出)

1. **scope 机制迁移干净性隐藏假设** — 本 Plan 首选依据 4 断言「5 路径 scope 全部只读,干净迁入 evalIdent 无污染」。**隐藏假设**:evalExpr 调用链嵌套场景(e.g. `comptime { let x = interpret(ctArr[0]) }` 外层 IDENT 读 ctArr,内层 evalExpr 走 INDEX_ACCESS → evalIndexAccess → 内部 genVal 再遇 IDENT)下,ctScopeStack 状态是否一致?**验证点**:Execute 1 必须单测(a) 顶层 IDENT 读 scope 变量 / (b) 嵌套 comptime block 内 IDENT / (c) scope push/pop 跨 evalExpr 边界场景。若实测失败 → **Plan 退回**,1b-4 改推 Phase A 后批 2
2. **原 gen_exprs.ss L173 raw constVal 编码** — 与 D101 §新张力 1(TEMPLATE_LIT)/ D103 §新张力 1(ARRAY_LIT 两处)同款问题,**IDENT 仅一处**(L173 runtime 回退)。迁入 evalIdent 后必须改为 `0 - constVal(genIdent(astId)) - 1`。**验证点**:若漏改 → caller 拿到 reg str 被当 known val 处理 → comptime 折叠误判。Execute 1 必须单测:`let x = someRuntimeVar; println(x)` runtime 路径 IR 字节级对比老版本
3. **eval_expr.ss 函数数攀升持续** — step 1 后 7 函数(evalExpr + 6 eval*),1b 全完 8 函数(+ evalMemberAccess)。D100 §新张力 2 / D101 §新张力 3 / D103 §新张力 3 已三次提:「Phase B 类化期需评估是否压回单 evalExpr body(MaybeVal class 携带 state 后可能 inline 回无深度代价)」。D104 延续该风险,不在本轮解决
4. **helper 未迁保留在 gen_exprs.ss** — `interpFindScopeKey`(声明位置待 grep)/ `isKnownClass` / `resolveCtTypeAlias` 三个 helper 保留,与 evalIdent 跨文件调用。**验证点**:Execute 1 bootstrap 编译器必须能 link 这些跨文件引用(对称 TEMPLATE_LIT genTemplateLit / ARRAY_LIT genArrayLit 跨文件引用已 PASS,此处风险低)
5. **D102 ±0.5% DRIFT 窗口三次生产验证反向** — 本 Plan 预估 M2 +13~+17 / N2 +20~+50(相对 D103 Execute 1 后),均在 ±380 / ±1903 窗口内 20-60× 充裕。D101 实测反向通过(全 PROGRESS),D103 实测反向通过(全 PROGRESS),D104 预期延续反向通过趋势。**若实测超 DRIFT** → 说明 IDENT 5 路径分支数是 M2/N2 非线性膨胀源,修正系数需记录进 D105 Plan
6. **1b-5 反射 gate 专章 Plan 复杂度** — D105 MEMBER_ACCESS 必须专章反射 gate,Plan 复杂度显著高于 D100/D101/D103/D104。**对策**:本轮 D104 §步骤 2 已明言 D105 Plan 必含 G1-G5 对照 + 4 反射触点分章节 + comptimeError 路径保留,为 D105 Plan 起草提供骨架

## 下一步(Plan 下的 Execute 顺序)

1. [ ] Planned — **Execute 0**(默认跳过):M7b bank +8 充裕,若 Execute 1 预估偏差超预期触发,补削减 M7b -1;grep 孤儿 helper / inline 单调用点
2. [ ] Planned — **Execute 1**:IDENT 迁移 evalIdent(对称 evalTemplateLit / evalArrayLit 三段式),eval_expr.ss 末尾新建 evalIdent + evalExpr 头部加分派 + L132 shim 扩 8 kind + 删 gen_exprs.ss L134-174 整块 41 行 inline + L173 runtime 回退改 mv 编码
3. [ ] Planned — **Execute 2**:收尾评估(record vs 继续 1b-5;默认继续)+ 起 D105 Plan(MEMBER_ACCESS 反射 gate 专章)

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- D103 §步骤 1 evalArrayLit(对称三段式模板)/ §步骤 2 指向 D104 / Execute 1 实测(M7b -8 / N3 -1117 / N2 -320 / M2 -44 / F1 -107)
- D101 §步骤 1 evalTemplateLit / §新张力 1 mv 编码 / §新张力 2 全局 Map 迁移语义
- D100 §坑 Q(银行余量不 record)/ §坑 P(M2/N2 迁移成本模型)
- D102 §规则 1.1-1.4(分层 GATE + DRIFT 窗口)/ §规则 2.1-2.3(F1 文件行数 GATE)
- D099 §坑 G-O(N3/M7b 成本模型)
- D098 §决策 1 MaybeVal Phase A mv 编码 / §决策 2 Phase B 类化
- D094 §规则 2 pure subset 白名单(IDENT 归属 L104)
- D088 §第一性需求(Zig 路线 SEMA 收敛)/ §正模式「一份 evalExpr 函数」
- CLAUDE.md §反射根因 gate(1b-4 IDENT 不触,1b-5 MEMBER_ACCESS 必触)
- `bootstrap/gen_exprs.ss:134-174`(IDENT 当前 inline 41 行)
- `bootstrap/gen_exprs.ss:132`(L132 shim,当前 7 kind)
- `bootstrap/gen_exprs.ss:17-27`(genIdent runtime 侧,不迁)
- `bootstrap/eval_expr.ss`(293 行,6 函数,D103 Execute 1 结果)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt` @ D101 Execute 0 commit 9343330(F1 1721 / M7b 676)
