# D105: evalExpr Phase A 中批 1b 第 5 kind Plan — MEMBER_ACCESS(反射 gate 专章)

**Status:** 首轮 Plan,Execute 0 未开工
**Depends on:** D104 §步骤 1 evalIdent 实测(M7b -7 / N3 -1316 / M2 -51 / N2 -255 / F1 -148)/ D104 §步骤 2 指向 D105 MEMBER_ACCESS 反射 gate 专章 / D103 §步骤 1 evalArrayLit(对称三段式)/ D101 §新张力 1 mv 编码 / D100 §坑 Q 银行余量不 record / D102 §规则 1.1-1.4 分层 GATE + ±0.5% DRIFT / D102 §规则 2.1-2.3 F1 文件行数 GATE / D098 §决策 1 mv 编码 / D097 反射根因指标 / D095 FieldMeta 字段 `name`/`type`/`annotations` / D088 §第一性需求 结构化字段访问 / D094 §规则 2 pure subset 白名单(`MEMBER_ACCESS` 在列)/ CLAUDE.md §反射根因 gate(强制) / `memory/feedback_reflection_root_cause_gate.md`
**Date:** 2026-04-19

---

## 第一性需求

D104 Execute 1 已合并 IDENT(1b 第 4 kind),eval_expr.ss 新建 evalIdent + evalExpr 头部分派 + L132 shim 扩 8 kind + 删 gen_exprs.ss L134-174 整块 41 行。**实测全线反向通过**(baseline = commit 9343330):

```
M7b 676→669 Δ=-7(预估 669 / bank -7~-8 命中)
N3  518111→516795 Δ=-1316(预估 -1167~-1317 命中下限)
N2  380630→380375 Δ=-255(累计组 tol ±1903 远内)
M2  76126→76075 Δ=-51(累计组 tol ±380 远内)
F1:gen_exprs.ss 1721→1573 Δ=-148(相对 Execute 1 前 -41,行数精确 = body 行数)
```

D102 ±0.5% DRIFT 窗口**三次生产验证连续反向通过**(D101 TEMPLATE_LIT / D103 ARRAY_LIT / D104 IDENT 全 PROGRESS),窗口设计有效性得证。**本 Plan 接 D104 §步骤 2 位置预言**,选 MEMBER_ACCESS 作 1b-5 最后一 kind,**承载反射 gate 专章**(对称 CLAUDE.md §反射根因 gate 强制条款)。

baseline(D101 Execute 0 commit 9343330 record,D103/D104 均未 record,**银行余量继续累积**):

```
M1=5134  M2=76126  M3a=12122  M3b=1879  M4=3037
M5=1750  M6=32     M7a=27     M7b=676   N1=34
N2=380630  N3=518111  N4=321  N5=0
F1:bootstrap/gen_exprs.ss=1721  (+ 13 条其他)
```

cur(D104 Execute 1 后):`M7b=669(bank +7)/ N3=516795(bank -1316)/ M2=76075(bank -51)/ N2=380375(bank -255)/ F1:gen_exprs.ss=1573(bank -148)`。**4 项余量深度富裕**,M7b +7 余量 ≥ 新函数 +1 需求 7 倍,N3 / N2 / M2 结构组累计组深窖。

**MEMBER_ACCESS 是 1b 最后一 kind**,完成后 1b 全收(INDEX_ACCESS / TEMPLATE_LIT / ARRAY_LIT / IDENT / MEMBER_ACCESS 全归 eval_expr.ss),Phase A 可递进后批 2(POSTFIX_INC / ASSIGN / METHOD_CALL 等写语义 kind)或记录 baseline 释放银行余量。

## 为什么 1b-5 选 MEMBER_ACCESS(无对照候选,反射专章必过)

1b 其余 4 kind 已落(D100/D101/D103/D104),MEMBER_ACCESS 是**唯一剩余 pure subset 白名单 kind**。D094 §规则 2 L104 明言 `MEMBER_ACCESS` 在白名单。**不选 = 1b 不闭环**。

| 要素 | MEMBER_ACCESS | 来源依据 |
|---|---|---|
| body 行 | L299-421,**123 行** | `bootstrap/gen_exprs.ss` Read |
| 节点估 | ~400 | D104 §DRIFT 预估表对照 |
| subsystem 耦合 | **5 反射触点** | D095 / D097 / enum / class static / CT object field |
| 反射 gate | **必过 reflection_health_linter**(前后对照)| CLAUDE.md §反射根因 gate + D097 |
| Step 0 压力 | 低(M7b bank +7 充裕)| D104 Execute 1 后 cur |

**反射 gate 是本 Plan 核心约束**:MEMBER_ACCESS 是 D088 §第一性需求「结构化字段访问」的**读侧主承载**,body 内 5 反射触点全在 D097 防规避指标保护范围。改动前后各跑一次 `bin/ss run tools/reflection_health_linter.ss`,结构组 8 项严格 ≤ baseline(M3b/M4/M6/M7a/M7b/N3/N4/N5),任一升则 commit 阻断。

## 当前事实(2026-04-19 snapshot,commit e68b555 @ D104 Execute 1 后)

| 项 | 值 / 位置 |
|---|---|
| MEMBER_ACCESS 分派 | `bootstrap/gen_exprs.ss:299-421`(**123 行 inline**,header `if (kind == "MEMBER_ACCESS")` 在 L299) |
| L132 shim | `kind == "IDENT"`(D104 扩至 8 kind) |
| eval_expr.ss | ~294 行(D104 Execute 1 后),7 函数(evalExpr + evalTernary + evalShortCircuit + evalIndexAccess + evalTemplateLit + evalArrayLit + evalIdent) |
| genMemberAccess / genOptionalMemberAccess(runtime 侧,不迁)| gen_exprs.ss 内,保留;MEMBER_ACCESS 迁入 evalMemberAccess 后 runtime 回退改走 evalMemberAccess 内的 `0 - constVal(...) - 1` mv 编码 |

**MEMBER_ACCESS body 5 反射触点**(L299-421 逐层):

- **L299**:header `if (kind == "MEMBER_ACCESS") {`
- **L300-301**:`member = nGetS1(id)` / `objNode = nGetI1(id)`
- **触点 A — D095 FieldMeta**(L302-344,43 行):
  - L302-308:`f.name` 返回字段常量 name
  - L309-321:`f.type` 返回 `classFieldTypes[cls.fld]`
  - L322-343:`f.annotations` 返回 `classFieldAnnotations[cls.fld]` 的 comptime string array(comptimeDepth > 0 限定)
  - **依赖**:`comptimeConsts` / `classFieldTypes` / `classFieldAnnotations`
- **触点 B — enum 值访问**(L345-359,15 行):
  - L348-353:`interpEnumValues` + `interpEnumTypes`(comptime-scoped)
  - L354-359:`enumReady` + `enumValues` + `enumTypes`(runtime-scoped)
  - **依赖**:`interpEnumValues` / `interpEnumTypes` / `enumValues` / `enumTypes` / `enumReady`
- **触点 C — class 静态字段回退**(L360-362,3 行):
  - `comptimeDepth == 0 && getVarType(eName) == "" && classFields.has(eName)` → `genMemberAccess(id)`
  - **依赖**:`classFields` / `getVarType`
- **触点 D — CT object / string / array / TypeValue**(L364-389,26 行):
  - L364-369:`interpGetField(objPayload, member)`(object field 读)
  - L370-377:string / array `.length`
  - L378-389:TypeValue `.name` / `.fields`(走 `interpCtFieldsArray`)
- **触点 E — D097 AnnotationMeta**(L390-414,25 行):
  - `cls.annotations` 构造 comptime `Array<AnnotationMeta>`
  - 通过 `classNodeIds` + `nGetI4` 读 AST annotation list + `interpNewVal("object", "AnnotationMeta")` + `interpSetField` 填 name/args
  - **依赖**:`classNodeIds` / `nGetI4` / `nGetS1` / `nGetList` / `nGetKind` / `interpNewVal` / `interpSetField` / `interpArrayPush` / `interpNewArray` / `interpNewString`
- **L416-418**:`comptimeError` 错误路径(comptime 非 CT 值访问)
- **L419-420**:runtime 回退 `genOptionalMemberAccess(id, reg(obj))` / `genMemberAccess(id, reg(obj))`(**raw constVal,迁入 evalMemberAccess 后必包 mv 编码**,对称 D101 §新张力 1 / D103 §新张力 1 / D104 §新张力 2)

## 对照 D102 §规则 1.1-1.4 分层 GATE 的 DRIFT 预估

baseline = commit 9343330(D101 Execute 0),cur = D104 Execute 1 后。D105 Execute 1 预估相对 baseline:

| 指标 | 组 | baseline | D104 cur | D105 step 1 后(估)| Δ 相对 baseline | tol | 判定 | 依据 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5125 | 5135-5145 | +1~+11 | ±25 | OK | body 5 触点 CC 节点搬家(for 循环 3 处 +3 / if 链 +8),近似守恒 |
| M2 | 累计 | 76126 | 76075 | 76090-76120 | -6~-36 | ±380 | PROGRESS | 新函数签名 +12 + L132 shim 扩 kind +3 + 删 outer `if kind == MEMBER_ACCESS` -2 = 净 +13~+17 相对 Execute 1 后 |
| M3a | 累计 | 12122 | 12125 | 12130-12140 | +8~+18 | ±60 | OK | genVal → evalMemberAccess 新边 +1;helper 调用数守恒 |
| M3b | 结构 | 1879 | 1879 | 1879 | 0 | 0(严格)| OK | 不触最大入度函数 |
| M4 | 结构 | 3037 | 3035 | 3033-3035 | -2~-4 | 0(严格)| OK/PROGRESS | `if kind == MEMBER_ACCESS` 删除 -1 + evalExpr 头部加 1 分派 +1 = 净 0 |
| M5 | 累计 | 1750 | 1750 | 1750 | 0 | ±8 | OK | 不新增可变变量(迁移变量守恒) |
| M6 | 结构 | 32 | 32 | 32 | 0 | 0(严格)| OK | 不新增递归 |
| M7a | 结构 | 27 | 27 | 27 | 0 | 0(严格)| OK | body depth 5(D097 最深 for-in 2 层 + if 3 层)搬入独立函数 depth 4-5,不升最大;M7a 记录在其他函数不变 |
| M7b | 结构 | 676 | 669 | **670**(+1 evalMemberAccess)| **-6** | 0(严格)| **OK**(bank +6 充裕)| bank +7 → +6,余量 ≥ 0 |
| N1 | 累计 | 34 | 34 | 34 | 0 | ±1 | OK | 不引入新 kind |
| N2 | 累计 | 380630 | 380375 | 380400-380500 | -130~-230 | ±1903 | PROGRESS | M2 派生;body 5 触点搬家 Halstead 项波动 +25~+125 相对 Execute 1 后 |
| N3 | 结构 | 518111 | 516795 | **516400-516700** | **-1411~-1711** | 0(严格)| **PROGRESS** | body depth 5 (D097 最深 for-in-annotation) 搬入独立函数 depth 2-3,压缩 -100~-400 相对 Execute 1 后;IDENT 实测 -199 证 scope 迁移压缩率模型,MEMBER_ACCESS body 深度更深(D097 最深 for-in 2 层 + if 3 层 嵌套)压缩量更大 |
| N4 | 结构 | 321 | 321 | 321 | 0 | 0(严格)| OK | 不触最大节点出度函数 |
| N5 | 结构 | 0 | 0 | 0 | 0 | 0(严格)| OK | 不新增 MEMBER_ASSIGN |
| **F1:gen_exprs.ss** | - | 1721 | 1573 | **~1450** | **-271** | 单调下降 | **PROGRESS** | 删 L299-421 整块 123 行 inline body;+L132 shim 扩 kind 字面量替代不增行;净 -123 相对 Execute 1 后 |

**累计组 6 项**全 OK/PROGRESS(M2 +13~+17 / N2 +25~+125 均在 DRIFT 窗口内 15-50× 充裕),**结构组 8 项**全 OK/PROGRESS(核心 M7b +1 bank 吸收 / N3 继续大削 -100~-400),**F1** gen_exprs.ss PROGRESS(1573→~1450 相对 baseline 累计 -271 行)。

## 反射 gate 专章(本 Plan 核心约束)

CLAUDE.md §反射根因 gate 强制条款:「触碰反射路径前后必须跑 `bin/ss run tools/reflection_health_linter.ss`;任一物理指标(M1-M7 + N1-N5)高于 baseline 阻断 commit」。

### R1 — 改动前对照(Execute 1 首次工具调用前)

```
bin/ss run tools/reflection_health_linter.ss
# 期望输出:全部指标 ≤ baseline(M7b=669 / N3=516795 / F1=1573 / 等)
# 若 cur > baseline → 说明 D104 Execute 1 引入退化,D105 Plan 拒绝启动,退回排查
```

### R2 — Execute 1 body 迁移中(每触点单测)

迁入 evalMemberAccess 后,必须单测覆盖 5 触点:

- **触点 A** D095 FieldMeta:`@derive(ToString) class Foo { x: int }` comptime 展开中 `f.name` / `f.type` / `f.annotations`
- **触点 B** enum 值访问:`enum Color { Red, Green }` 运行时 `Color.Red` + comptime `Color.Red`
- **触点 C** class 静态字段回退:`class Foo { static X = 1 } ... Foo.X`(comptime 不处理,走 runtime)
- **触点 D** CT object / string / array / TypeValue:`const o = { a: 1 }; o.a` / `"abc".length` / `[1,2,3].length` / `const t = Foo.__type__; t.name` / `t.fields`
- **触点 E** D097 AnnotationMeta:`@Inject("db") class Bar {} ... Bar.annotations[0].name == "Inject"`

### R3 — 改动后对照(Execute 1 commit 前)

```
bin/ss run tools/reflection_health_linter.ss
# 期望输出:
#   结构组 8 项 全 OK/PROGRESS(M7b ≤ 676 / N3 PROGRESS / M4/M7a/M6/M3b/N4/N5 ≤ baseline)
#   累计组 6 项 全 OK/PROGRESS(M2/N2/M1/M3a/M5/N1 DRIFT 窗口内)
#   F1:gen_exprs.ss 1573→~1450 单调下降 PASS
#
# 任一结构组 > baseline → commit 阻断,Step 0 补削减或 Plan 退回
```

### R4 — commit 前行为闭环

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- `bin/ss test tests/` 全绿(尤其 @derive / @Inject / enum / reflection 测试)
- `bin/ss run tools/reflection_health_linter.ss` R3 通过 + record 仍不触发(银行策略延续)

**反射 gate 失败的回退策略**:

1. **结构组任一升**(如 M7b +2 或 M7a +1 或 N3 升):Step 0 启动,grep 孤儿 helper / inline 单调用点 / 合并 ct* helper,回退到 R3 通过
2. **行为测试红**(@derive 展开错误 / annotation 丢失 / enum 值错类型):Plan 退回,MEMBER_ACCESS 推 Phase A 后批 2,先独立 Plan 修根因后再 1b-5
3. **bootstrap 固定点红**:定位根因,不越步(对称 feedback_no_workaround)

## 决策(分 3 步,每步独立 bootstrap + 分层 GATE PASS + 反射 gate 对照)

### §步骤 0 — 可选预削减 commit(M7b bank +7 充裕,默认跳过)

**决策**:D105 Step 0 **默认跳过**,直接 Execute 1 MEMBER_ACCESS 迁移。依据:

- 当前 M7b=669,baseline 676,bank +7 ≥ 新函数 +1,D102 §规则 1.1 结构组严格 ≤ baseline,670 ≤ 676 **通过**
- 跳过 Step 0 节省 1 轮 Execute,银行策略精神(延续 D100 §坑 Q / D104 §步骤 0)= 累积余量直到 1b 全完再 record,本轮无需再腾
- 对照 D104 Step 0 默认跳过实测通过,D105 重复该模式

**例外触发条件**(若 Step 1 R3 反射 gate 失败则回退此步):

- Step 1 实测 M7b 净 +2 或更多(意外拆 evalMemberAccess 子函数)→ 触发 Step 0 补削减
- Step 1 实测 N3 反向不降(估 -100~-400 未达)→ 触发 Step 0 补削减
- Step 1 实测 M4 升(分发深度意外膨胀)→ 触发 Step 0 补削减

**若触发 Step 0**:按 D103 §步骤 0 / D104 §步骤 0 候选清单(bootstrap 孤儿 helper grep / 单调用 helper inline / ct* helper 合并)操作,单 commit 落地,bootstrap 固定点 PASS + 反射 gate R3 PASS。

### §步骤 1 — MEMBER_ACCESS 迁移(独立函数 evalMemberAccess,对称 evalIdent pattern)

**新建 `bootstrap/eval_expr.ss` 末尾 `evalMemberAccess(astId: int): int`**(对称 evalIdent / evalArrayLit / evalTemplateLit 模板):

函数 body 结构(对照 gen_exprs.ss L299-421 迁入):

```ss
function evalMemberAccess(astId: int): int {
    const member = nGetS1(astId)
    const objNode = nGetI1(astId)
    // 触点 A: D095 FieldMeta
    if (nGetKind(objNode) == "IDENT" && comptimeConsts.has(nGetS1(objNode)) == 1) {
        // ... L302-344 整块搬入(43 行)
    }
    // 触点 B: enum 值访问
    if (nGetKind(objNode) == "IDENT") {
        const eName = nGetS1(objNode)
        // ... L346-362 整块搬入(enum + class static 回退)
    }
    // 触点 D + E: CT object / string / array / TypeValue / AnnotationMeta
    const obj = genVal(objNode)
    if (isCt(obj) == 1) {
        // ... L365-414 整块搬入(50 行)
    }
    // 错误路径 + runtime 回退(必包 mv 编码)
    if (comptimeDepth > 0) {
        return comptimeError(`cannot access field '${member}' on ${isCt(obj) == 1 ? interpType(payload(obj)) : "runtime"} value`, astId)
    }
    if (nGetI3(astId) > 0) { return 0 - constVal(genOptionalMemberAccess(astId, reg(obj))) - 1 }
    return 0 - constVal(genMemberAccess(astId, reg(obj))) - 1
}
```

**关键点**:

- **坑 mv 编码延续**:原 L361 / L419 / L420 raw constVal 3 处,迁入 evalMemberAccess 后**必须全部包** `0 - constVal(...) - 1`(对称 D101/D103/D104 处理)。L361 是 `classFields` 回退路径(触点 C class static),L419/L420 是通用 runtime 回退。**3 处全改不漏**
- **ct 分支** `return ctVal(...)` 不变(已是 mv 编码 known 分支),触点 A/B/D/E 的 ctVal 路径保持
- **helper 不迁** — `isKnownClass` / `interpNewString` / `interpNewInt` / `interpCtFieldsArray` / `interpNewVal` / `interpSetField` / `interpArrayPush` / `interpNewArray` / `comptimeError` / `genOptionalMemberAccess` / `genMemberAccess` 全部保留在原位,对称 TEMPLATE_LIT genTemplateLit / ARRAY_LIT genArrayLit / IDENT genIdent 不迁模式
- **全局 Map 跨文件访问** — `comptimeConsts` / `classFieldTypes` / `classFieldAnnotations` / `interpEnumValues` / `interpEnumTypes` / `enumValues` / `enumTypes` / `enumReady` / `classFields` / `classNodeIds` 迁入 eval_expr.ss 后跨文件引用。对照 D104 Execute 1 evalIdent 跨文件读 `ctScopeStack` / `ctVars` / `ctInvalidated` / `interpVars` / `genericTypeSubs` 已 PASS,此处风险低但需 bootstrap 固定点验证

**改 `bootstrap/gen_exprs.ss` L132 shim**:

```ss
// BEFORE(8 kind,D104 Execute 1 落地)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
// AFTER(9 kind)
if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT" || kind == "MEMBER_ACCESS") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
```

**改 `bootstrap/eval_expr.ss` evalExpr 头部**(加 MEMBER_ACCESS 分派):

```ss
if (k == "MEMBER_ACCESS") { return evalMemberAccess(astId) }
```

**删 `bootstrap/gen_exprs.ss` L299-421 整块**(123 行 MEMBER_ACCESS inline body,含 outer `if kind == "MEMBER_ACCESS"` header)

**独立验证链**(tokenize → parse → checker → eval):

1. **Tokenizer**:MEMBER_ACCESS 由 `.` token 驱动,parse_exprs.ss MEMBER_ACCESS parse 不改 —— parse 层零影响
2. **check_stmts.ss** MEMBER_ACCESS checkExpr 不改(checker 类型推断路径不走 eval)
3. **eval 路径**:`genVal(MEMBER_ACCESS) → L132 shim → evalExpr → evalMemberAccess`,对称 IDENT/TEMPLATE_LIT/ARRAY_LIT 链
4. **runtime IR emit**:`genMemberAccess(id, reg)` / `genOptionalMemberAccess(id, reg)` 不迁,gen_exprs.ss 内保留 —— IR 输出字节级不变

**验证**(R1/R3 前后对照 + 行为测试 + bootstrap):

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- `bin/ss test tests/` 全绿,尤其:
  - @derive(ToString/Equals/HashCode) 展开(D095 FieldMeta 路径)
  - @Inject / @Route 等 annotation handler(D097 AnnotationMeta 路径)
  - enum values/names/valueOf(触点 B)
  - CT object field 读(触点 D)
  - class static 字段(触点 C)
- `bin/ss run tools/reflection_health_linter.ss` R3 PASS:
  - 结构组 8 项 OK/PROGRESS(核心 M7b 670 ≤ 676 bank +6 / N3 PROGRESS -100~-400)
  - 累计组 6 项 OK/PROGRESS(M2 +13~+17 / N2 +25~+125 均 DRIFT 窗口内)
  - F1:gen_exprs.ss PROGRESS(1573→~1450,累计 -271)

### §步骤 2 — 收尾评估 + 1b 全收决策(record vs Phase A 后批 2)

**目标**:Step 1 完成后决策是 record baseline(释放 1b 累积银行余量)还是继续 Phase A 后批 2(POSTFIX_INC / ASSIGN / METHOD_CALL 等写语义 kind)。

**决策矩阵**:

| 条件 | 决策 |
|---|---|
| Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ +5,N3 bank < -1500 | 不 record,起 D106 Plan 直接 POSTFIX_INC(轻量写 kind,Step 0 轻量) |
| Step 1 实测 M7b 余量 < +3 或 N3 bank > -500 | record baseline 释放余量,再起 D106 |
| Step 1 实测任一结构组超 baseline(反射 gate 阻断)| Plan 退回,Step 0 补削减后 Execute 2 再试 |
| 1b 全收(5 kind 齐落)银行余量仍深窖 | 默认**不 record**,延续 D100 §坑 Q 策略,Phase A 后批继续累积 |

**1b 全收后的 F1 状态**(相对 baseline):

- `bootstrap/gen_exprs.ss` 1721→~1450,累计 -271,距 F1 目标 ≤ 600 仍 ~850 行余量,Phase A 后批 2 继续削减 METHOD_CALL(body 估 100+ 行)/ POSTFIX_INC / ASSIGN 等
- D094 §规则 2 pure subset 白名单剩余:POSTFIX_INC / POSTFIX_DEC / ASSIGN / METHOD_CALL / CALL / NEW_EXPR / THIS / SUPER / GROUPING / NULL_LIT / INT_LIT / STRING_LIT / TRUE_LIT / FALSE_LIT / DOUBLE_LIT(后 6 个字面量已在 L126-131 evalExpr 分派)

**Execute 2 不涉及代码改动**,仅评估 + 起 D106 Plan / 或 record commit,单独 commit。

## Rejected Alternatives

### §A — 1b-5 bundle MEMBER_ACCESS 全 5 触点一次迁 + 反射测试并行

**拒绝理由**:

- Plan 粒度守则:一 Plan 一 kind,每 commit bootstrap + GATE 独立 PASS(D100/D101/D103/D104 建立)
- 反射 gate 专章要求**改动前后各跑一次** reflection_health_linter,单独 commit 便于定位退化源
- 触点 A-E 虽逻辑独立但共享 comptimeDepth / objNode 结构判定,拆分 5 commit 破坏迁移原子性,反而增加 bootstrap 固定点失败风险
- **正确路径:MEMBER_ACCESS 整块迁移单 commit,5 触点行为测试在同一 Execute 内联完成**

### §B — 不做 MEMBER_ACCESS,1b-5 跳过直接起 Phase A 后批 2(METHOD_CALL)

**拒绝理由**:

- 1b pure subset 白名单强制 MEMBER_ACCESS 归属,跳过 = 1b 不闭环,后批 2 依赖 MEMBER_ACCESS 已迁(METHOD_CALL body 内调 MEMBER_ACCESS 子路径)
- 反射 gate 专章在 MEMBER_ACCESS 最密集,跳过不降 D088 §第一性需求「结构化字段访问」风险,反推后批工作量
- 银行余量富裕,无跳过动机
- **正确路径:1b-5 MEMBER_ACCESS 必做,本 Plan 承担**

### §C — 反射 gate 改动前不跑 R1 对照(只跑 R3)

**拒绝理由**:

- CLAUDE.md §反射根因 gate 明言「触碰反射路径**前后**必须跑」,R1 缺失 = 规则违反
- 若 D104 Execute 1 已引入未发现的退化(虽 D104 声明 PASS 但 cur 未做 baseline 对照),R1 缺失会把退化归咎于 D105 Execute 1,排错难度指数上升
- R1 耗时 10s,无节省价值
- **正确路径:R1 强制跑,作为 Execute 1 首个工具调用**

### §D — Step 0 强制预削减(M7b 充裕也跑)

**拒绝理由**:

- D103/D104 Step 0 跳过实测全通,M7b bank +7 是 D100 Step 0 启动时(+2)的 3.5 倍
- 强制 Step 0 多消耗 1 轮 Execute 无价值,银行策略精神是累积余量,不是强制消耗
- D103 §步骤 0 已证 @derive 孤儿清除是"一次性红利",后续 Step 0 候选递减
- **正确路径:Step 0 默认跳过,例外触发条件见 §步骤 0**

### §E — Step 1 commit 同时 record baseline(一次 commit 搞定)

**拒绝理由**:

- 银行策略(D100 §坑 Q / D101-D104 §步骤 2)核心是 1b 全完再 record,Step 1 仅是 1b-5 完成,**不等于 Phase A 全完**
- record 和 evalMemberAccess 迁移是两个职责:迁移改代码结构,record 锁定对照点,合并 commit 违背原子性
- 若 Step 1 实测超预估需回退,record 已写入 baseline 不可撤销(D097 L102「累积方向严禁更新 baseline」)
- **正确路径:Step 2 独立评估 + 独立 commit(若 record)**

## 新张力(D105 引出)

1. **5 反射触点交叉干扰隐藏假设** — 本 Plan 首选依据断言「触点 A-E 逻辑独立,共享 comptimeDepth / objNode 判定」。**隐藏假设**:`comptimeConsts.has(nGetS1(objNode))` 在触点 A 判真时,触点 B/D/E 的 `interpEnumValues.has(eName)` / `interpGetField` 走向是否一致?D095 FieldMeta 设计中 for-in-unroll 绑定常量可能与 enum 常量同名。**验证点**:Execute 1 必须单测(a) 字段名 == enum 名冲突 / (b) 字段名 == class 名冲突 / (c) TypeValue `.fields` 内部字段名 == 外层 @derive 展开字段名。若实测冲突 → **Plan 退回**,1b-5 改推后批独立修根因
2. **L361 + L419 + L420 三处 raw constVal 同步改 mv 编码** — D101 TEMPLATE_LIT 1 处 / D103 ARRAY_LIT 2 处 / D104 IDENT 1 处 / D105 MEMBER_ACCESS **3 处**,漏改任一 → caller 拿到 reg str 当 known val → comptime 折叠误判。**验证点**:Execute 1 必须单测 3 条 runtime 路径字节级 IR:(a) `obj.field` 普通 runtime(L420)/ (b) `obj?.field` optional chain(L419)/ (c) `ClassName.staticField` class static 回退(L361)
3. **eval_expr.ss 8 函数(1b 全收后)** — D100 §新张力 2 / D101 §新张力 3 / D103 §新张力 3 / D104 §新张力 3 连续四次提:「Phase B 类化期需评估是否压回单 evalExpr body」。1b 全收后 eval_expr.ss 结构 = evalExpr + evalTernary + evalShortCircuit + evalIndexAccess + evalTemplateLit + evalArrayLit + evalIdent + evalMemberAccess(8 函数),函数数增长是 Phase A 分 kind 迁移必然副作用。**Phase B MaybeVal 类化后**(D098 §决策 2),evalMemberAccess 等 body 可能 inline 回 evalExpr 单函数(MaybeVal class 方法携带 state,depth 压缩)。D105 延续风险记录,不在本轮解决
4. **反射 gate R1/R3 baseline 同一 commit** — reflection_health_linter baseline = commit 9343330(D101 Execute 0),**D102/D103/D104 Execute 未更新 baseline**(银行策略)。R1/R3 对照的 baseline 是 9343330 的快照,跨越 4 轮 Execute 未 record。**风险**:若 D104 Execute 1 实测数值链与 baseline 脱节超 ±0.5% DRIFT 累积窗口,R3 判定可能误差。**对策**:Execute 1 开工前额外跑一次 `git log --oneline tools/linter_baseline.txt` 确认 baseline commit = 9343330,不一致 → 更新 Plan §第一性需求 段落 baseline 引用
5. **D088 §第一性需求 距离验证** — 本 Plan 落 MEMBER_ACCESS 是 D088 §第一性需求「`obj.fields()` + `obj[name]`」的**读侧主承载**(`obj[name]` 等价 INDEX_ACCESS 已在 D100 落,`obj.fields()` 走 METHOD_CALL 后批)。Phase 距离 = 1(Phase A 收尾),对照 VCM ⑤ 路线验证「距离 ≥2 phase 警告可能绕道」,**本轮 = 1 Phase 距离,合规**
6. **@derive ToString/Equals/HashCode 行为回归风险** — 触点 A D095 FieldMeta 是 @derive 展开的核心依赖,迁入 evalMemberAccess 后若 `f.name` / `f.type` / `f.annotations` 任一返回路径破坏(mv 编码漏 / ctVal 拼错 / comptimeConsts 读错),**全部 @derive 测试连锁红**。**对策**:Execute 1 首个非对照命令 = `bin/ss test tests/phase5/d095_*.ss`(grep 现有 D095 test),PASS 才继续;不 PASS → 定位根因不越步

## 下一步(Plan 下的 Execute 顺序)

1. [ ] Planned — **Execute 0**(默认跳过):M7b bank +7 充裕,若 Execute 1 R3 反射 gate 失败触发,补削减 M7b -1 / N3 / M4 —— **本 Plan 未触发,默认跳过生效**
2. [ ] Planned — **Execute 1**:MEMBER_ACCESS 迁移 evalMemberAccess(对称 evalIdent 三段式),eval_expr.ss 末尾新建 evalMemberAccess + evalExpr 头部加分派 + L132 shim 扩 9 kind + 删 gen_exprs.ss L299-421 整块 123 行 inline + L361/L419/L420 三处 runtime 回退改 mv 编码
   - **R1 前对照**:`bin/ss run tools/reflection_health_linter.ss` 全部指标 ≤ baseline 后启动
   - **D095 行为回归首测**:`bin/ss test tests/phase5/d095_*.ss` PASS 后继续
   - **5 触点单测覆盖**:触点 A D095 / B enum / C class static / D CT object / E D097 AnnotationMeta
   - **R3 后对照**:结构组 8 项全 OK/PROGRESS / 累计组 6 项全 OK/PROGRESS / F1 PROGRESS
   - **bootstrap 固定点 + test tests/ 全绿**
3. [ ] Planned — **Execute 2**:收尾评估(1b 全收后 record vs 继续 Phase A 后批 2;默认不 record 延续银行策略)+ 起 D106 Plan(Phase A 后批 2 首 kind,候选 POSTFIX_INC 轻量写 kind 或 METHOD_CALL 中量调用 kind)

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进;**反射 gate 专章 R1/R3 任一失败 → Plan 退回,不强推**。

## 参考

- D104 §步骤 1 evalIdent / §步骤 2 指向 D105 / Execute 1 实测(M7b -7 / N3 -1316 / M2 -51 / N2 -255 / F1 -148)
- D103 §步骤 1 evalArrayLit(对称三段式模板)
- D101 §步骤 1 evalTemplateLit / §新张力 1 mv 编码
- D100 §坑 Q(银行余量不 record)/ §坑 P(M2/N2 迁移成本模型)
- D102 §规则 1.1-1.4(分层 GATE + DRIFT 窗口)/ §规则 2.1-2.3(F1 文件行数 GATE)
- D099 §坑 G-O(N3/M7b 成本模型)
- D098 §决策 1 MaybeVal Phase A mv 编码 / §决策 2 Phase B 类化
- D097 反射根因指标(M1-M7 + N1-N5 + D102 分层策略)
- D095 FieldMeta(`f.name` / `f.type` / `f.annotations` 三字段)
- D094 §规则 2 pure subset 白名单(MEMBER_ACCESS 归属)
- D088 §第一性需求(`obj.fields()` + `obj[name]` 结构化字段访问)
- CLAUDE.md §反射根因 gate / §交互式单文档(含 ultrathink gate) / §PFV 流程
- `memory/feedback_reflection_root_cause_gate.md` / `memory/feedback_ultrathink_gate.md` / `memory/feedback_pfv_process.md`
- `bootstrap/gen_exprs.ss:299-421`(MEMBER_ACCESS 当前 inline 123 行)
- `bootstrap/gen_exprs.ss:132`(L132 shim,D104 Execute 1 后 8 kind)
- `bootstrap/gen_exprs.ss` genMemberAccess / genOptionalMemberAccess runtime 侧(不迁)
- `bootstrap/eval_expr.ss`(~294 行,7 函数,D104 Execute 1 结果)
- `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt` @ D101 Execute 0 commit 9343330(F1 1721 / M7b 676 / N3 518111)
- `tools/next_prompt_ultrathink_linter.ss`(D105 轮引入,PFV §收尾 gate 第 3 步 (b) 机械 gate)
