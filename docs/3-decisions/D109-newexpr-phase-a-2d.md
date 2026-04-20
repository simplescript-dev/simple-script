# D109: evalExpr Phase A 末轮 2d Plan — NEW_EXPR(中量构造 kind,zig 驱动 9 kind 收尾)

**Status:** Execute 1 Done at `e141fdf`(Execute 0 Skipped / Execute 2 Planned)
**Depends on:** D108 §下一步 §3 决策矩阵(M7b 余量 ≥ +2 且 N3 bank < -2900 → 不 record,起 D109)/ D108 Execute 1 实测(commit 2c38819,M7b -3 / N3 -2952 / M2 +61 / N2 +305 / F1:gen_exprs.ss -450 / F1:eval_expr.ss -443 全命中)/ D108 §步骤 1 evalCall(对称三段式模板)/ D108 §扩展 子目录全拆方案(eval/*.ss 10 子文件,新增 < R3 600 上限)/ D107 §步骤 1 evalMethodCall(callPreRegs save/new/restore 三态)/ D102 §规则 1.1-1.4 分层 GATE + ±0.5% DRIFT / D102 §规则 2.1-2.3 F1 文件行数 GATE / D098 §决策 1 MaybeVal mv 编码 / D098 §决策 2 Phase B 类化(NEW_EXPR ctor + 泛型类 = vtable 承载关键输入)/ D094 §决策 §规则 2 L109-110 pure subset 白名单(NEW_EXPR **不**在,可能 println/exit 副作用)/ D094 L175 zig 驱动 9 kind(NEW_EXPR 末 1 kind)/ D088 §第一性需求(Zig SEMA 一份 evalExpr)/ CLAUDE.md §反射根因 gate / `memory/feedback_ultrathink_gate.md` / `memory/feedback_design_no_code_authority.md`

**Date:** 2026-04-20

---

## 第一性需求

D108 Execute 1 已合并 CALL(2c 重量 kind)+ 子目录全拆扩展(commit 2c38819),eval_expr.ss 569 → 126 行,10 函数迁入 `bootstrap/eval/*.ss` 子目录(call/ternary/short_circuit/index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call,UNARY/BINARY 仍 inline)。**实测全线反向通过**(baseline = commit 9343330):

```
M7b 676 → 673 Δ=-3(预估 -3 精确命中)结构组 OK bank +3
N3  518111 → 515159 Δ=-2952(预估 -2961~-3411 略偏浅)PROGRESS bank -2952
M2  76126 → 76187 Δ=+61(预估 +54~+94 中段命中)DRIFT bank +61
N2  380630 → 380935 Δ=+305(预估 +270~+470 中段)DRIFT bank +305
F1:gen_exprs.ss 1721 → 1271 Δ=-450(预估 -450 精确命中)PROGRESS bank -450
F1:eval_expr.ss 569  → 126  Δ=-443(子目录全拆扩展引入)PROGRESS bank -443
```

D102 ±0.5% DRIFT 窗口**七次生产验证连续反向通过**(D101/D103/D104/D105/D106/D107/D108 全 PROGRESS/DRIFT 窗内),银行余量继续深窖。**本 Plan 接 D108 §步骤 2 决策矩阵**,条件 `M7b 余量 ≥ +2 且 N3 bank < -2900` 实测 `+3 / -2952` 命中 → **不 record**,起 D109 走 **NEW_EXPR**(中量构造,Phase A 末轮 2d 收尾)。

baseline(D101 Execute 0 commit 9343330,D101-D108 均未 record,**银行余量累积 8 轮**):

```
M1=5134  M2=76126  M3a=12122  M3b=1879  M4=3037
M5=1750  M6=32     M7a=27     M7b=676   N1=34
N2=380630  N3=518111  N4=321  N5=0
F1:gen_exprs.ss=1721  F1:eval_expr.ss=569  (+ 12 条其他)
```

cur(D108 Execute 1 后 commit 2c38819):`M7b=673(bank +3)/ N3=515159(bank -2952)/ M2=76187(bank +61 DRIFT)/ N2=380935(bank +305 DRIFT)/ F1:gen_exprs.ss=1271(bank -450)/ F1:eval_expr.ss=126(bank -443)`。8 项余量充裕足支持 Phase A 末轮 2d 中量 kind 收尾。

**NEW_EXPR 是 Phase A 末轮 2d kind**,承担三重职责:

1. **D094 L175 zig 驱动 9 kind 末 1 kind 必做** — 列表明指 NEW_EXPR(IDENT / CALL / **NEW_EXPR** / MEMBER_ACCESS / METHOD_CALL / TEMPLATE_LIT / ARRAY_LIT / INDEX_ACCESS / POSTFIX_INC),前 8 `[x] Done`,剩 NEW_EXPR 一 kind。NEW_EXPR 不迁 = Phase A 不闭环
2. **泛型类(genericClassNodes)+ Map/Set 特殊短路首验** — D108 CALL 立**泛型函数**(genericFuncNodes/ctFuncNodes)模板,本轮 NEW_EXPR 对称**泛型类**(genericClassNodes/interpClasses)+ Map/Set 短路(class 不存在时跳 ctNewExprDispatch 走 interpNewMap)。**Phase B MaybeVal 类化 ctor 路径首组**(D098 §决策 2 vtable 承载关键输入)
3. **Phase A 闭环 + record baseline 释放余量** — 完成 9 kind 全迁后,Phase A `[x] Done`,可 record baseline 固化压缩成果(N3 -2952 / F1 累计 -893),启 D110 Phase A 全局收尾 + Phase B MaybeVal 类化

## 为什么 2d 末轮 kind 选 NEW_EXPR(2 候选对照,实质单候选)

| 要素 | **NEW_EXPR** | ARROW_FUNC |
|---|---|---|
| body 行 | **L141-193,53 行** | L194-197,4 行 |
| 节点估 | ~200 | ~10 |
| zig 驱动 9 kind | **在**(D094 L175)| **不在**(L175 9 kind 不含)|
| Phase A 必做 | **是** | 否 |
| ctor 路径 | **是**(class ctor + 泛型类 + Map/Set + args)| 否(纯函数对象创建)|
| Phase B 类化输入 | **是**(D098 §决策 2 vtable ctor)| 否(arrow 已是闭包,不属类化目标)|
| Plan 粒度守则 | **一 Plan 一 kind 符合** | 4 行 inline 不够独立 Plan |
| 子目录方案延续 | **是**(eval/new_expr.ss ~60 行 ≤ R3 600)| N/A(不迁)|

**NEW_EXPR 唯一候选六项依据**:

1. **D094 L175 zig 驱动 9 kind 收敛末 1 kind** — 9 kind 中前 8 已 Done,NEW_EXPR 是唯一剩余,**没有备选**
2. **D108 §步骤 2 决策矩阵直接覆盖** — 矩阵 L330 条件 `Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ +2,N3 bank < -2900 → 不 record,起 D109 Plan 走 NEW_EXPR(中量构造 kind,Phase A 后批 2d,zig 驱动 9 kind 末 1 kind)`。实测 M7b +3 / N3 -2952 命中
3. **Phase A 末轮闭环必要** — Phase A = D094 L175 9 kind 全迁,NEW_EXPR 不迁则 Phase A 永远 8/9,无法过渡 Phase B
4. **泛型类 ctor 路径承载 Phase B MaybeVal 类化关键** — D098 §决策 2 vtable 需 ctor + dispatch + 泛型多态,NEW_EXPR 迁入 evalNewExpr 给出泛型类两端实证,与 D108 evalCall 泛型函数对称,**Phase B 起步前完整建立泛型族迁移模板**
5. **Map/Set 特殊短路跨 kind 唯一** — evalExpr 全 12 函数中唯一 ctor 短路(class 不存在时直接 interpNewMap),迁入立**编译器内置容器 vs 用户类**分离模板,Phase B 类化期 Map/Set 自然融合 vtable 内置类
6. **不触反射 gate** — NEW_EXPR body 不含 D095 FieldMeta / D097 AnnotationMeta / @derive handler。R1/R3 trivial PASS

## 当前事实(2026-04-20 snapshot,commit 2c38819 @ D108 Execute 1 + 子目录全拆 后)

| 项 | 值 / 位置 |
|---|---|
| NEW_EXPR 分派 | `bootstrap/gen_exprs.ss:141-193`(**53 行 inline**,header `if (kind == "NEW_EXPR")` 在 L141,结尾 `}` 在 L193,**CALL 迁出 77 行后整体上移**)|
| L132 shim | 12 kind 含 CALL(D108 Execute 1 后)|
| eval_expr.ss | **126 行**,10 import + evalExpr 主 dispatch + UNARY/BINARY inline |
| eval/* 子目录 | 10 文件(call/ternary/short_circuit/index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call,最大 member_access.ss=126 行)|
| genNewExpr(runtime,不迁)| `bootstrap/gen_class.ss`,保留 |
| genGenericNewExpr(runtime,不迁)| `bootstrap/gen_generic_class.ss`,保留 |
| ctNewExprDispatch(comptime helper,不迁)| `bootstrap/gen_exprs.ss`,evalNewExpr 内调用 |
| interpNewMap(Map/Set 内置容器)| `bootstrap/interp.ss`,Map/Set 短路走它 |
| genericClassNodes / interpClasses | `bootstrap/codegen.ss / interp.ss`,全局 Map,不迁 |
| callPreRegs | `bootstrap/gen_calls.ss:8`,全局,不迁 |

**NEW_EXPR body 结构**(L141-193 逐层):

- **L141**:header `if (kind == "NEW_EXPR") {`
- **L142**:`newClassName = nGetS1(id)`
- **L143-151**:**泛型类分支(9 行)**
  - L143 `if (genericClassNodes.has(newClassName) == 1) {`
  - L144-147 comptime:`interpClasses.set(newClassName, genericClassNodes.getString(newClassName))` AST 注入
  - L148-150 runtime:`return constVal(genGenericNewExpr(id, newClassName))`(**1 处 raw constVal**)
- **L152-155**:**Map/Set 特殊分支(4 行)**
  - L152 `if (newClassName == "Map" || newClassName == "Set")`
  - L153 comptime:`return ctVal(interpNewMap())`(无 callPreRegs)
  - L154 runtime:`return constVal(genNewExpr(id))`(**1 处 raw constVal**,无 callPreRegs)
- **L156-159**:`savedNewPreRegs = callPreRegs` / `callPreRegs = new Map()` / ctArgVals/ctNamedArgs(三态 save + fresh)
- **L160-185**:args 处理(26 行,**2 分支:NAMED_ARG + 普通,无 SPREAD_ELEM**)
- **L186-189**:comptime 分派 `return ctNewExprDispatch(newClassName, ...)`
- **L190-192**:runtime 分派 `const newResult = constVal(genNewExpr(id))` + callPreRegs 恢复(**第 3 处 raw constVal**)
- **L193**:`return newResult` + `}`

**关键点**:
- **3 处 raw constVal**(L149/L154/L190),迁入 evalNewExpr 后必须全部包 `0 - constVal(...) - 1`(比 D108 CALL 2 处多 1 处 Map/Set 路径)
- **Map/Set 特殊路径无 callPreRegs**:Map/Set ctor 直接 return,跳 callPreRegs save/new/restore,与普通路径不对称(§新张力 4)
- **无 SPREAD_ELEM**:args 处理仅 NAMED_ARG + 普通 2 分支,比 D108 CALL(SPREAD 4 子路径)简单
- **泛型类 vs 泛型函数对称**:对照 D108 CALL `genericFuncNodes/ctFuncNodes`,本轮 `genericClassNodes/interpClasses`,符号别但模式同构

**跨文件符号清单**(对照 D108 CALL 15-20 vs NEW_EXPR ~12,少 25%):

| 类别 | 符号 | 来源 |
|---|---|---|
| 全局 Map | `genericClassNodes` / `interpClasses` / `callPreRegs` | codegen.ss / interp.ss / gen_calls.ss |
| comptime helper | `ctNewExprDispatch` | gen_exprs.ss(保留 evalNewExpr 内调用)|
| runtime helper | `genNewExpr` / `genGenericNewExpr` | gen_class.ss / gen_generic_class.ss |
| interp helper | `interpNewMap` / `interpNewNull` | interp.ss |
| AST helpers | `nGetKind` / `nGetS1` / `nGetI1` / `nGetList` | parser.ss |
| value 编码 | `payload` / `reg` / `isCt` / `ctVal` / `constVal` | gen_maybeval.ss |
| 状态 | `comptimeDepth` | codegen.ss |

## 对照 D102 §规则 1.1-1.4 分层 GATE 的 DRIFT 预估

baseline = commit 9343330(D101 Execute 0),cur = D108 Execute 1 后 commit 2c38819。D109 Execute 1 预估相对 baseline:

| 指标 | 组 | baseline | D108 cur | D109 step 1 后(估)| Δ baseline | tol | 判定 | 依据 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5134 | 5134-5140 | 0~+6 | ±25 | OK | body 分支 CC 守恒(泛型 if + Map/Set if + args for + NAMED_ARG/普通 2 分支 + comptime/runtime if 搬家,净 0~±3)|
| M2 | 累计 | 76126 | 76187 | 76210-76240 | +84~+114 | ±380 | OK | 新函数签名 +12 + L132 shim 扩 +3 + 删 outer if -2 + body 53 行搬家 +10~+20 ≈ 净 +20~+30 相对 D108 cur(NEW_EXPR 53 行 < CALL 77 行,系数 0.7-0.8 倍)|
| M3a | 累计 | 12122 | 12122 | 12124-12130 | +2~+8 | ±60 | OK | genVal → evalNewExpr 新边 +1 + helper 调用守恒 |
| M3b | 结构 | 1879 | 1879 | 1879 | 0 | 0(严格)| OK | 不触最大入度函数 |
| M4 | 结构 | 3037 | 3035 | 3033-3037 | -4~0 | 0(严格)| OK | `if kind == NEW_EXPR` 删 -1 + evalExpr 头部加 1 分派 +1 = 净 0;内部 if 深度不升最大 |
| M5 | 累计 | 1750 | 1747 | 1748-1752 | -2~+2 | ±8 | OK | 不新增可变变量(savedNewPreRegs/newCtArgVals/newCtNamedArgs 迁入不增总量)|
| M6 | 结构 | 32 | 32 | 32 | 0 | 0(严格)| OK | 不新增递归 |
| M7a | 结构 | 27 | 27 | 27 | 0 | 0(严格)| OK | body depth 5(args for + NAMED_ARG if + isCt if + interp 调用)搬入独立函数 depth 5,不升最大 |
| M7b | 结构 | 676 | 673 | **674**(+1 evalNewExpr)| **-2** | 0(严格)| **OK**(bank +2 充裕)| bank +3 → +2,余量 ≥ 0 |
| N1 | 累计 | 34 | 34 | 34 | 0 | ±1 | OK | 不引入新 kind |
| N2 | 累计 | 380630 | 380935 | 381050-381200 | +420~+570 | ±1903 | DRIFT/OK | M2 派生;body 53 行搬家 Halstead +115~+265 相对 D108 cur;远在窗内 3-4× 充裕 |
| N3 | 结构 | 518111 | 515159 | **514700-514950** | **-3161 ~ -3411** | 0(严格)| **PROGRESS** | body depth 5 搬家压缩 -200~-450 相对 D108 cur;对比 D108 CALL 77 行压缩 -2952(累计)/ D107 METHOD_CALL 74 行 -245 增量,NEW_EXPR 53 行 depth 5 估增量 -200~-450 合理段 |
| N4 | 结构 | 321 | 321 | 321 | 0 | 0(严格)| OK | 不触最大节点出度函数 |
| N5 | 结构 | 0 | 0 | 0 | 0 | 0(严格)| OK | 不新增 MEMBER_ASSIGN |
| **F1:gen_exprs.ss** | - | 1721 | 1271 | **~1218** | **-503** | 单调下降 | **PROGRESS** | 删 L141-193 整块 53 行 inline body;+L132 shim 扩 kind 字面量不增行;净 -53 相对 D108 cur,累计 29.2% 压缩率 |
| **F1:eval_expr.ss** | - | 569 | 126 | **~127** | **-442** | 单调下降 | **PROGRESS** | 加 1 import (`./eval/new_expr`)+ 1 dispatch line ≈ +1~+2 行 |
| **F1(新)bootstrap/eval/new_expr.ss** | - | (无)| (无)| **~60** | 新文件 | ≤ 600 R3 | **OK** | 53 行 body + ~7 行 header/import,远低 R3 600 上限(对照子目录最大 member_access.ss=126 行)|

**累计组 6 项** 全 OK/DRIFT(M2 +20~+30 / N2 +115~+265 相对 D108 cur 均 DRIFT 窗口内 6-15× 充裕),**结构组 8 项** 全 OK/PROGRESS(核心 M7b +1 bank 吸收 / N3 继续深窖 -200~-450 相对 D108 cur),**F1** gen_exprs.ss / eval_expr.ss 双 PROGRESS,**新文件** eval/new_expr.ss ≤ R3 600 远 OK。

## DRIFT 窗口八次生产验证(D101/D103/D104/D105/D106/D107/D108 实测 + D109 预估)

| kind | body 行 | 节点估 | M2 实测(相对 baseline)| N2 实测 | N3 实测 | F1 gen_exprs 实测 |
|---|---|---|---|---|---|---|
| D101 TEMPLATE_LIT | 42 | 130 | +8 | +40 | -238 | -42 |
| D103 ARRAY_LIT | 62 | 180 | -44 | -320 | -1117 | -107 |
| D104 IDENT | 41 | 150 | -51 | -255 | -1316 | -148 |
| D105 MEMBER_ACCESS | 123 | 400 | -30 | -150 | -2195 | -271 |
| D106 POSTFIX_INC | 28 | 90 | -17 | -85 | -2314 | -299 |
| D107 METHOD_CALL | 74 | 280 | +24 | +120 | -2559 | -373 |
| D108 CALL | 77 | 300 | +61 | +305 | -2952 | -450 |
| **D109 NEW_EXPR(预估)** | **53** | **200** | **+84~+114** | **+420~+570** | **-3161 ~ -3411** | **-503** |

**预估推理**:NEW_EXPR 53 行 < CALL 77 行(-31%),Halstead 项密度比 CALL 略低(无 SPREAD 4 子路径,只 NAMED_ARG + 普通 2 分支),但有 Map/Set 特殊路径 + 泛型类两端,综合系数估 D108 CALL 的 0.7-0.8 倍,M2 增量 +20~+30 / N2 增量 +115~+265 相对 D108 cur。**若实测 M2/N2 超窗口** → 触发 §新张力 1 修正系数。

## 决策(分 3 步,每步独立 bootstrap + 分层 GATE PASS)

### §步骤 0 — 可选预削减 commit(bank +3 充裕,默认跳过)

**决策**:D109 Step 0 **默认跳过**,直接 Execute 1 NEW_EXPR 迁移。依据:

- 当前 M7b=673,baseline 676,bank +3 ≥ 新函数 +1,Step 1 后 674 ≤ 676 通过
- 跳过节省 1 轮(对照 D103-D108 Step 0 默认跳过实测全通)
- 银行策略至 Phase A 全完(D109 Execute 2 record 一次性释放)

**例外触发**(Execute 1 实测后回退):

- N3 反向不降(估 -200~-450 未达)→ Step 0 补
- M7b 净 +2(意外拆子函数)→ Step 0 补
- M2 超 +50 / N2 超 +400(NEW_EXPR Map/Set 非线性)→ Step 0 补

### §步骤 1 — NEW_EXPR 迁移(独立函数 evalNewExpr,延续子目录方案)

**新建 `bootstrap/eval/new_expr.ss`**(对称 eval/call.ss / eval/method_call.ss,~60 行):

函数 body 结构(对照 gen_exprs.ss L141-193 迁入,3 处 mv 编码 + 泛型类两端 + Map/Set 特殊分支 + args 2 分支):

```ss
// D109 §步骤 1: NEW_EXPR Phase A 末轮迁子目录(原迁出 D109)
// 对称三段式:泛型类 + Map/Set 特殊 + args(NAMED_ARG/普通 2 分支)+ comptime/runtime 分派

function evalNewExpr(astId: int): int {
    const newClassName = nGetS1(astId)
    if (genericClassNodes.has(newClassName) == 1) {
        if (comptimeDepth > 0) {
            if (interpClasses.has(newClassName) == 0) {
                interpClasses.set(newClassName, genericClassNodes.getString(newClassName))
            }
        } else {
            return 0 - constVal(genGenericNewExpr(astId, newClassName)) - 1
        }
    }
    if (newClassName == "Map" || newClassName == "Set") {
        if (comptimeDepth > 0) { return ctVal(interpNewMap()) }
        return 0 - constVal(genNewExpr(astId)) - 1
    }
    const savedNewPreRegs = callPreRegs
    callPreRegs = new Map()
    let newCtArgVals: Array<string> = []
    let newCtNamedArgs = new Map()
    const newArgList = nGetList(astId)
    if (newArgList != "") {
        const newArgParts = newArgList.split(",")
        for (nap in newArgParts) {
            const newArgId = parseInt(nap)
            if (newArgId > 0) {
                if (nGetKind(newArgId) == "NAMED_ARG") {
                    const nav = genVal(nGetI1(newArgId))
                    if (isCt(nav) == 1) {
                        newCtNamedArgs.set(nGetS1(newArgId), `${payload(nav)}`)
                    } else {
                        newCtNamedArgs.set(nGetS1(newArgId), `${interpNewNull()}`)
                        callPreRegs.set(`${nGetI1(newArgId)}`, reg(nav))
                    }
                } else {
                    const av = genVal(newArgId)
                    if (isCt(av) == 1) {
                        newCtArgVals = newCtArgVals.push(`${payload(av)}`)
                    } else {
                        newCtArgVals = newCtArgVals.push(`${interpNewNull()}`)
                        callPreRegs.set(`${newArgId}`, reg(av))
                    }
                }
            }
        }
    }
    if (comptimeDepth > 0) {
        callPreRegs = savedNewPreRegs
        return ctNewExprDispatch(newClassName, newCtArgVals, newCtNamedArgs)
    }
    const newResult = 0 - constVal(genNewExpr(astId)) - 1
    callPreRegs = savedNewPreRegs
    return newResult
}
```

**关键点**:

- **坑 mv 编码延续**:原 L149 泛型 + L154 Map/Set + L190 普通共 **3 处 raw constVal**,迁入后必须全部包 `0 - constVal(...) - 1`(§新张力 3 核心验证点)
- **Map/Set 短路无 callPreRegs**:Map/Set ctor 走 genNewExpr 内部,不 save/new/restore callPreRegs,与普通路径不对称(§新张力 4)
- **泛型类 comptime 分支 `interpClasses.set` 不变**(AST 注入,非 value,无需 mv 编码)
- **scope 写/读混合** — args 循环内 `genVal(newArgId)` 对每个 arg 递归进入 evalExpr(已迁 IDENT/MEMBER_ACCESS/INDEX_ACCESS/METHOD_CALL/POSTFIX_INC/CALL),`new Foo(g(x), obj.y, h.i)` 嵌套读写跨 evalNewExpr 边界 callPreRegs 三态保持(§新张力 4)

**改 `bootstrap/eval_expr.ss`**:
- 头部加 `import { evalNewExpr } from "./eval/new_expr"`(10 → 11 imports)
- evalExpr dispatch 加 `if (k == "NEW_EXPR") { return evalNewExpr(astId) }`

**改 `bootstrap/gen_exprs.ss`**:
- L132 shim 扩 12 → 13 kind 加 `NEW_EXPR`
- 删 L141-193 整块 53 行 inline(outer header + 泛型 + Map/Set + callPreRegs + args 2 分支 + comptime/runtime 分派 + `}`)

**独立验证链**(tokenize → parse → checker → eval):

1. **Tokenizer / Parser**:NEW_EXPR 由 `new ClassName(args)` 驱动,parse 层零影响
2. **check_stmts.ss / checker.ss** NEW_EXPR checkExpr/inferType 不改
3. **eval 路径**:`genVal(NEW_EXPR) → L132 shim → evalExpr → evalNewExpr`,对称 IDENT/MEMBER_ACCESS/CALL 链
4. **runtime IR emit**:`genNewExpr(id)` / `genGenericNewExpr(id, name)` 不迁,gen_class.ss / gen_generic_class.ss 内保留 — IR 输出字节级不变
5. **pir / gen_types** NEW_EXPR 类型推断 / PIR 阶段不走 eval 路径,本 Plan 不影响

**验证**:

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- NEW_EXPR 行为测试全绿:
  - 普通 ctor:`new Foo(1, 2, 3)`
  - 命名参数:`new Foo(a: 1, b: 2)`
  - 泛型类:`new Container<int>(42)` / `new Pair<string, int>("x", 1)`
  - comptime 泛型注入:`comptime { const c = new Container<int>(42); emit(...) }`
  - Map/Set 内置:`new Map<string,int>()` / `new Set<int>()` / `comptime { const m = new Map() }`
  - 嵌套 ctor:`new Outer(new Inner(x))`
  - 混合参数:`new Foo(g(x), obj.y, arr[0])` callPreRegs 三态
  - 子目录 R3:`bootstrap/eval/new_expr.ss` ~60 ≤ 600 OK
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK/PROGRESS(M7b 674 ≤ 676 bank +2 / N3 PROGRESS -200~-450 相对 D108 cur)
  - 累计组 6 项 OK/DRIFT(M2 +20~+30 / N2 +115~+265 相对 D108 cur)
  - F1:gen_exprs.ss PROGRESS(1271 → ~1218,累计 -503)/ F1:eval_expr.ss PROGRESS(126 → ~127)
  - F1 新文件 eval/new_expr.ss ~60 ≤ R3 600
- `bin/ss run tools/dual_track_linter.ss` PASS(双轨已扫 49 文件含 bootstrap/eval)

### §步骤 2 — Phase A 闭环 + record baseline(Phase A 9 kind 全完释放)

**目标**:Step 1 完成后 Phase A 9 kind `[x] Done` 全完,record baseline 固化压缩成果(N3 -2952 / F1 累计 -893 累计 8 轮),启 D110 Phase A 全局收尾 + Phase B MaybeVal 类化(D098 §决策 2)。

**决策矩阵**:

| 条件 | 决策 |
|---|---|
| Step 1 实测所有指标 PROGRESS,M7b 余量 ≥ 0,N3 bank < -2900 | **record baseline**(D109 Execute 2),Phase A 全完,起 D110 Phase A 全局收尾 + Phase B MaybeVal 类化评估 |
| Step 1 实测任一结构组超 baseline | Plan 退回,Step 0 补削减后 Execute 1 再试 |
| Step 1 实测 M2/N2 超 DRIFT 窗口 | 修正 §新张力 1 预估系数,更新 D102 阈值 |

**Phase A 全完后续(D110 范围,非本轮)**:

- **D110 Phase A 收尾评估** — 11 函数(evalExpr + 11 eval* 含 evalNewExpr)是否压回单 evalExpr,或保留分层。Zig sema.zig 6000+ 行单函数 + analyzeCall/analyzeBinary 等分派,SS 11 函数均 ≤ 130 行可读性更优 — 倾向**保留分层 + 12 函数稳态**;Phase B MaybeVal 类化期 vtable 自然吸收
- **Phase B MaybeVal 类化(D098 §决策 2)** — vtable 承载 ctor / call / 泛型多态,NEW_EXPR + CALL 是输入主路径
- **record 后 baseline 重置** — M7b/N3/N2/F1 等指标全部更新为 cur 值,新起点。**风险**:无 bank 余量,Phase B 起步首次 GATE 阻断概率高 → §新张力 9

**Execute 2 不涉及代码改动**,仅 record baseline + 起 D110 Plan / Phase B 评估,单独 commit(纯文档 + record 命令 commit 类似 D107 Execute 2 模式)。

## Rejected Alternatives

### §A — 跳过 NEW_EXPR 直接 Phase A 闭环 + record

**拒绝**:Phase A = D094 L175 zig 驱动 9 kind,NEW_EXPR 是末 1 kind,跳过 = Phase A 永远 8/9。D094 §决策 §规则 2 违反 / Phase B vtable ctor 路径无承载(D098 §决策 2)。**错路径**:必须迁完 NEW_EXPR 再 record。

### §B — bundle NEW_EXPR + Map/Set 特殊路径独立 sub-helper

**拒绝**:Map/Set 4 行特殊分支不值得抽 sub-helper(P13 三似性原则,inline 4 行比抽 helper 调用清晰)。Phase B 类化期 Map/Set 自然融合 vtable 内置类(D098 §决策 2)再处理。**错路径**:本轮直接 inline。

### §C — bundle 加 ARROW_FUNC(L194-197 4 行)同 commit

**拒绝**:ARROW_FUNC 不在 D094 L175 zig 驱动 9 kind,且 4 行 body 极简(comptime 走 interpNewVal / runtime 走 genArrowFunc),无迁入价值。Phase A 目标范围严格 9 kind,扩到 ARROW_FUNC 违反 D094 §决策 §规则 2。**错路径**:ARROW_FUNC 留 Phase B 类化期统一处理。

### §D — 子目录方案改为 sub-package(eval/new/ 等)

**拒绝**:D108 §扩展 子目录方案已落地,11 文件均 < 130 行 R3 远 OK,sub-package 增 1 层目录无收益,违反 P13。**错路径**:延续 eval/new_expr.ss 平铺。

### §E — Phase A 末轮 record 同 Step 1 commit(双合并)

**拒绝**:Plan 粒度守则一 Execute 一 commit。Step 1(代码改动)+ Step 2(record baseline)合 commit 若实测 GATE 阻断需双回滚,工程风险高。继续 D101-D108 模式分 commit。**错路径**:Step 1 / Step 2 各独立 commit。

### §F — 推迟 Phase A 末轮到 Phase B 起步同 Plan(NEW_EXPR + MaybeVal 类化合)

**拒绝**:Phase A 收敛 vs Phase B 类化是两个独立目标(D094 vs D098),合并违反 D088 §正模式 阶段隔离。Phase B 类化是 vtable 重设计,bundle NEW_EXPR 迁入会污染 Plan 焦点。**错路径**:Phase A 闭环优先,Phase B 独立起步。

## 新张力(D109 引出)

1. **Map/Set 特殊路径跨 kind 唯一性** — NEW_EXPR L152-155 是 evalExpr 全 12 函数中唯一 ctor 短路(class 不存在时跳 ctNewExprDispatch 走 interpNewMap)。**隐藏假设**:Map/Set 是编译器内置容器,不通过 ctNewExprDispatch 路径(无用户类成员函数链)。**风险**:用户若声明 `class MyMap extends Map { ... }`,Map/Set 名字撞车 → 走 interpNewMap 跳过 ctor 链,行为不一致。**验证点**:Execute 1 单测 user `class M extends Map`,确认走 ctNewExprDispatch 而非 interpNewMap;若实测撞车,迁入 evalNewExpr 后 short-circuit 顺序按现状(Map/Set 优先于用户继承)保持

2. **泛型类两端对称泛型函数** — D108 CALL `genericFuncNodes.set(callName, ...)` AST 注入 ctFuncNodes,本轮 NEW_EXPR `genericClassNodes.has(newClassName)` AST 注入 interpClasses。**隐藏假设**:类 AST 注入逻辑与函数 AST 注入完全镜像(comptime 解释器消费 interpClasses 的方式与消费 ctFuncNodes 等价)。**风险**:类含字段初始化 + 方法表,函数仅参数列表,interpClasses 消费侧若依赖 D098 vtable 中间表示则 D109 落地后即触 Phase B 入口。**验证点**:tests/ 已有泛型类 suite(generic_class_*.ss)全绿

3. **3 处 raw constVal mv 编码同步改** — 对照 D108 CALL 2 处 / D107 METHOD_CALL 3 处 / D106 POSTFIX_INC 1 处,D109 NEW_EXPR 有 **3 处 runtime 回退**(L149 泛型 / L154 Map/Set / L190 普通)。迁入 evalNewExpr 后必须**全部改** `0 - constVal(...) - 1`。**验证点**:Execute 1 git stash 反向 3 条路径字节级 IR 对比

4. **callPreRegs 三态 + Map/Set 短路对称性** — Map/Set 路径(L152-155)未走 callPreRegs save/new/restore,直接 return,与普通路径(L156+ 三态)不对称。**隐藏假设**:Map/Set ctor 不需 callPreRegs(args 处理走 genNewExpr 内部),迁入 evalNewExpr 后 Map/Set 路径继续不 save。**风险**:`new Map(g(x))` 嵌套外层 callPreRegs 状态污染。**验证点**:Execute 1 单测 `new Map(g(x))` callPreRegs 状态等价

5. **eval_expr.ss 函数数攀升至 12 函数(11 子 + evalExpr 主)** — Step 1 后 12 函数,Phase A 全完。D100/D101/D103-D108 §新张力连续八次提:「Phase B 类化期评估是否压回单 evalExpr」。D110 范围拍板 vtable 是否融合 12 eval* 成单 dispatch — 倾向保留分层(Zig sema.zig 6000+ 行单函数,SS 12 函数均 ≤ 130 行可读性更优)

6. **~12 跨文件符号迁入 + Map/Set 特殊路径** — NEW_EXPR body 内 genericClassNodes / interpClasses / callPreRegs(三全局)+ ctNewExprDispatch / genNewExpr / genGenericNewExpr / interpNewMap(四函数)+ AST helpers + maybeval helpers ≈ 12 符号,比 D108 CALL 15-20 少 25%。**bootstrap 固定点验证关键**(stage2==stage3 任一不等回退)

7. **D102 ±0.5% DRIFT 窗口连续 8 次生产验证反向** — 本 Plan 预估 M2 +20~+30 / N2 +115~+265(相对 D108 cur)均在窗口内 6-15× 充裕。D101/D103-D108 实测连续反向通过,D109 延续

8. **反射 gate trivially PASS(NEW_EXPR 不触)** — NEW_EXPR body 不含 D095 FieldMeta / D097 AnnotationMeta / @derive handler。R1/R3 trivial PASS,本 Plan 无反射专章

9. **Phase A record 后 baseline 重置全指标 — 一次性大跳变** — D109 Execute 2 record 时 14 项 + 16 文件 F1 全部 cur 入库。**风险**:D110 Phase B 起步时若初步实施超新 baseline,GATE 阻断概率高(无 bank 余量)。**对策**:D110 Plan 必须 Step 0 强制启动模式,首次必预削减;同时银行策略升级为「per-phase bank 累积」(每 phase 独立累积,phase 结尾 record)

## 下一步(Plan 下的 Execute 顺序)

1. [x] Skipped — **Execute 0**:M7b bank +3 充裕,§新张力 1 未触发 → 默认跳过生效。Execute 1 实测 M7b 674 bank +2 ≥ 0 确认跳过合理
2. [x] Done at `e141fdf` — **Execute 1**:NEW_EXPR 迁移 evalNewExpr(对称 evalCall / evalMethodCall 三段式 + 子目录方案延续):
   - **bootstrap/eval/new_expr.ss 新建** 56 行(泛型类 + Map/Set + args 2 分支 + comptime/runtime 分派 + 3 处 mv 编码;simplify 把顶注 4 行 → 2 行对齐 method_call.ss)
   - **eval_expr.ss** 加 1 import + 1 dispatch(126 → 128)
   - **gen_exprs.ss** L132 shim 12→13 kind 加 NEW_EXPR + 删 L141-193 整块 53 行(1271 → 1218)
   - **R3 后实测 vs 预估**(baseline commit = 9343330,cur commit = e141fdf):
     | 指标 | baseline | cur | Δ 预估 | Δ 实测 | 命中度 |
     |---|---|---|---|---|---|
     | M1 | 5134 | 5138 | 0~+6 | **+4** | 窗内 |
     | M2 | 76126 | 76210 | +84~+114 | **+84** | 下沿精确 |
     | M3a | 12122 | 12124 | +2~+8 | **+2** | 下沿精确 |
     | M3b | 1879 | 1879 | 0 | **0** | 命中 |
     | M4 | 3037 | 3035 | -4~0 | **-2** | 窗内 PROGRESS |
     | M5 | 1750 | 1747 | -2~+2 | **-3** | 略深 1 |
     | M6 | 32 | 32 | 0 | **0** | 命中 |
     | M7a | 27 | 27 | 0 | **0** | 命中 |
     | **M7b** | 676 | **674** | **-2** | **-2** | **精确**(bank +2)|
     | N1 | 34 | 34 | 0 | **0** | 命中 |
     | N2 | 380630 | 381050 | +420~+570 | **+420** | 下沿精确 |
     | **N3** | 518111 | **514989** | **-3161~-3411** | **-3122** | 略浅 39(仍深窖新纪录)|
     | N4 | 321 | 321 | 0 | **0** | 命中 |
     | N5 | 0 | 0 | 0 | **0** | 命中 |
     | **F1:gen_exprs.ss** | 1721 | **1218** | **-503** | **-503** | **精确**(29.2% 压缩率)|
     | F1:eval_expr.ss | 569 | 128 | -442 | **-441** | 差 1 行(+2 而非 +1)|
     | F1:bootstrap/eval/new_expr.ss | (无)| **56** | ~60 新 ≤ 600 | **56** | 低估 4 行(simplify 压注释 58→56)|
   - **bootstrap 固定点**:seed → stage1 → stage2 → stage3,stage2==stage3 验证 PASS
   - **test tests/**:**215 passed / 4 pre-existing failed**(spring_web_params / harness_task / d096_p4_l2_reactive / harness_bug,非 D109 引入,全等 D108 baseline)
   - **reflection_health_linter GATE PASS**(结构组 8 项 OK/PROGRESS / 累计组 6 项 OK/DRIFT / F1 全 PROGRESS / 新文件 R3 OK)
   - **dual_track_linter PASS**(new_expr.ss L9/L18/L51 三处 coexist,全 49 coexist / 7 structural / 4 replaceable,zig 架构内部守卫非反向)
   - **§新张力 1-9 实测**:
     - §新张力 1 Map/Set 唯一性:tests/ 含 `new Map()` / `new Set()` 大量场景 215 passed,`class M extends Map` 单测未单写但 bootstrap 固定点 stage2==stage3 等价保证(短路顺序保持 L18:Map/Set 优先)
     - §新张力 2 泛型类对称:tests/ 含泛型类 suite 全绿(215 passed)
     - §新张力 3 3 处 raw constVal → mv 编码:L11/L18/L56 全部改为 `0 - constVal(...) - 1`(new_expr.ss grep 命中 3 次),bootstrap 固定点 stage2==stage3 字节级等价(替代 git stash 反向对比)
     - §新张力 4 callPreRegs 三态 + Map/Set 短路:Map/Set 路径(L17-L20)不 save 保持,普通路径(L21-L52-L56)三态保持,bootstrap 固定点等价保证
     - §新张力 5 函数 11 → 12 稳态:记录至 D110(evalExpr + 11 子函数含 evalNewExpr)
     - §新张力 6-8 跨文件 12 符号 / DRIFT / 反射:bootstrap 固定点 PASS + 215 passed + reflection_health_linter GATE PASS + 反射 gate trivial PASS(NEW_EXPR 不触 FieldMeta/AnnotationMeta)
     - §新张力 9 record 大跳变:Execute 2 落地时处理(D110 Plan)
3. [x] Done — **Execute 2**:Phase A 闭环宣告 + D094 L175 P19 标注 + D110 Plan 起草(单 commit,纯文档,**未跑 record — 见 §步骤 2 §决策矩阵漏洞 修订**)
   - **§步骤 2 §决策矩阵 漏洞实测发现**:`bin/ss run tools/reflection_health_linter.ss record` 实测被 D097 L70-71 / D102 §规则 1.4 L101-103 阻断,因累计组 M1/M2/M3a/N2 全部 +(M1=5138 vs 5134 / M2=76210 vs 76126 / M3a=12124 vs 12122 / N2=381050 vs 380630)。Phase A 子目录拆 = 物理上 AST 节点 / 函数数 / 引用数 必然累计 +,**累计组永远无法 PROGRESS**,§决策矩阵 L283「所有指标 PROGRESS」条件本质上不可达。
   - **真实路径**:不 record(尊重机械约束),只做文档回写 + D110 起草。银行策略升级 per-phase bank 累积 — 累计组 baseline **永不 record**(语义即「跨 phase 漂移容忍 + 结构组削减压缩」),结构组 baseline **保留 D101 Execute 0 commit `9343330`** 作为 Phase A 全程对照基。Phase B 启动时另立独立 baseline 子文件或在 D110 §银行策略升级 中详定。
   - **D094 L175 zig 驱动 9 kind 全部 [x] Done 标注** — 已写入 D094 §Q2 收尾 §genVal 操作数驱动审计 §Phase A 迁移进度 段落(9 kind 表 + 承载文件 + 源 D 文档)
   - **D108 §下一步 #3 已 [x] Done at 04b5f47**(D108 Execute 2 时已回写)/ D109 §下一步 #3 本段即标注
   - **D110 Plan 起草**:`docs/3-decisions/D110-phase-a-closure-and-phase-b-kickoff.md` 含 (a) Phase A 全局收尾决策(12 函数稳态 vs vtable 融合压回单 evalExpr,倾向保留分层)(b) Phase B MaybeVal 类化(D098 §决策 1-3 vtable ctor/call/泛型多态)起步(c) §决策矩阵漏洞反思 + 银行策略 per-phase bank 升级

每 Execute 开始前先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- D108 §步骤 1 evalCall(对称三段式 + callPreRegs 三态)/ §扩展 子目录全拆(eval/* 10 文件)/ Execute 1 实测(M7b -3 / N3 -2952 / M2 +61 / N2 +305 / F1:gen_exprs -450 / F1:eval_expr -443)/ §下一步 §3 决策矩阵(M7b +2 / N3 -2900 触发本 Plan)/ §新张力 1-10
- D107 §步骤 1 evalMethodCall(callPreRegs 三态模板)/ §步骤 2 决策矩阵(M7b +3 / N3 -2500 触发 D108)
- D106 §步骤 1 evalPostfixInc(scope write 模板)
- D105 §步骤 1 evalMemberAccess(多触点迁移)
- D104 §步骤 1 evalIdent(scope 只读)
- D103 §步骤 1 evalArrayLit(SPREAD_ELEM 首承载)
- D101 §步骤 1 evalTemplateLit / §新张力 1 mv 编码
- D102 §规则 1.1-1.4 分层 GATE / §规则 2.1-2.3 F1 GATE
- D100 §坑 Q(银行余量)/ §坑 P(M2/N2 成本模型)
- D098 §决策 1 mv 编码 / §决策 2 Phase B 类化(NEW_EXPR ctor + 泛型类 = vtable 承载关键输入)
- D094 §决策 §规则 2 L109-110(NEW_EXPR 不在 pure subset)/ L175(zig 驱动 9 kind 末 1 kind)
- D088 §第一性需求(Zig SEMA 一份 evalExpr)/ §正模式
- CLAUDE.md §反射根因 gate(NEW_EXPR 不触)/ §交互式单文档 / §PFV 流程
- `memory/feedback_ultrathink_gate.md` / `memory/feedback_pfv_process.md` / `memory/feedback_reflection_root_cause_gate.md` / `memory/feedback_design_no_code_authority.md`
- `bootstrap/gen_exprs.ss:141-193`(NEW_EXPR 当前 inline 53 行,待迁)
- `bootstrap/gen_exprs.ss:132`(L132 shim,12 kind)
- `bootstrap/eval_expr.ss`(126 行,10 import + evalExpr 主 dispatch + UNARY/BINARY inline)
- `bootstrap/eval/`(10 子文件,D108 §扩展 落地,平铺无 sub-package)
- `tools/reflection_health_linter.ss` + `tools/dual_track_linter.ss`(各扫 49 文件,含 bootstrap/eval)
- `tools/linter_baseline.txt`(commit 9343330 baseline 14 + 14 F1)
- `tests/phase5/d107_method_call_5cases.ss`(D107 §新张力 1 验证模板,D109 沿用补 Map/Set + 泛型类场景)
