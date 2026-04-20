# D112: Phase A 收尾 — 消除 `comptimeTypeAliases` 独立通道(type alias 并入 ctVars)

**Status:** Plan 起草中(Execute 未启动,本文档产出即 Plan 落地)
**Depends on:** D098 §决策 3 Phase A L148-153(本 Plan 承接 Phase A 收尾唯一未执行项)/ D098 §下一步 L194 `[ ] Planned — 写 Phase A 末尾 comptimeTypeAliases → ctVars 合并 Plan`(本 Plan 即该承接)/ D098 §新张力 4(InternPool key 设计 D111 §决策 3 已决)/ D111 §决策 1-2(InternPool 引入 + `type|<className>` dedup key 落地,本 Plan §决策 2 `tvStringOf(payload)` 反查路径依赖 dedup 稳定性)/ D111 §新张力 4 L452-453(本 Plan 承接)/ D108 §步骤 1 IDENT 迁出(evalIdent 现位 `bootstrap/eval/ident.ss`)/ D102 §规则 1.1-1.4 分层 GATE + §规则 2.1-2.3 F1 GATE / D097 L70-71 累计组永不 record / D101 baseline(D110/D111 跨 Phase 延续作对照基)/ D094 §规则 2 pure subset(本 Plan 不动)/ D093 §决策 §Zig 原理 第 3 条(Type 本身是一个 Value,与 int/string 共享 Value 容器)/ D088 §第一性需求(Zig SEMA 一份 evalExpr,反射 Meta 对象 = MEMBER_ACCESS)/ §正模式 / §反模式 / CLAUDE.md §反射根因 gate / §交互式单文档 / §PFV 流程 / `memory/feedback_ultrathink_gate.md` / `memory/feedback_no_workaround.md`

**Date:** 2026-04-20

---

## 第一性需求

D111 Execute 2 commit `32a8f6d` 已落地 Phase B InternPool 5 标量 dedup(`interpNewType(className)` 走 `internPoolGetOrInsert("type|${className}", newTvType(className))`,codegen.ss:314-316),`type|<className>` key 自动 dedup + `tvStringOf(payload(tvId))` 反查 className 能力已就位。**但 D098 §决策 3 Phase A L148-153 收尾项仍未执行** —— `comptimeTypeAliases` 独立全局 Map 仍作 Type alias 专轨查表机制:

1. **codegen.ss:84** `let comptimeTypeAliases = new Map()` 全局声明
2. **codegen.ss:90-93** `resolveCtTypeAlias(name)` 函数查 `comptimeTypeAliases.has(name) → getString(name)`
3. **codegen.ss:989** pre-scan 路径 `comptimeTypeAliases.set(nGetS1(s), returnName)`(VAR_DECL COMPTIME_EXPR + `return IDENT` 模式)
4. **gen_decls.ss:235** 全局层 VAR_DECL TypeValue 走 `comptimeTypeAliases.set(name, ceLit)`
5. **gen_decls.ss:506** 函数内 VAR_DECL TypeValue 走 `comptimeTypeAliases.set(name, ceLit)`
6. **eval/ident.ss:38-41**(D108 迁出后位置)evalIdent 在 ctVars 查完后再调 `resolveCtTypeAlias(ctIdName)` 做第 2 轨 resolve

D088 §第一性需求(Zig SEMA 一份 evalExpr,反射 Meta 对象访问 = 普通 evalExpr MEMBER_ACCESS)→ D098 §决策 3 L148-153 Phase A 收尾的收益链:

```
Type-as-Value 并入 ctVars/MaybeVal 共享容器
  → evalIdent ctVars L17 查表命中 type tagged int 直接返回
  → resolveCtTypeAlias 7 处调用点内部走 ctVars 反查(函数保留,内部改体)
  → Phase B class instance / Meta 对象接入时沿 "Value 共享容器" 同轨扩展
  → D093 §Zig 原理 第 3 条"Type 本身是一个 Value,与 int/string 共享 Value 容器"语义就位
```

**否定证据**:不消除 `comptimeTypeAliases` → evalIdent 内 L2 ctVars + L6 resolveCtTypeAlias 两轨并存 → Phase B Meta 对象 / class instance 接入时 "是不是 type alias / 是不是 Meta 对象 / 是不是 class instance" 多轨分支将累积 → Zig SEMA 单 dispatch 骨架长期失锚 → D098 §决策 2 Phase C 评估(`interp*` 家族全迁 InternPool)失去 "Value 容器一轨" 前提。

D098 §下一步 L194 `[ ] Planned — 写 Phase A 末尾 comptimeTypeAliases → ctVars 合并 Plan` 明确指向本 D112,D111 §新张力 4 L452-453 已回指 "Type-as-Value 与 InternPool 合并(D098 §决策 3 Phase B)未在本 Plan ... 留 D112 单独 Plan,Phase B 中期推进"。本 Plan 职责:

1. **写端 3 处归并** —— `comptimeTypeAliases.set` 3 处(codegen.ss:989 / gen_decls.ss:235,506)改为 `ctVars.set` 同构写入
2. **读端 resolveCtTypeAlias 函数体改走 ctVars** —— 函数签名 + 7 处调用点签名不动,仅内部从 `comptimeTypeAliases.getString(name)` 改为 "ctVars 查(`${currentFunc}:${name}` / `:${name}`)+ isCt + interpType==type + tvStringOf(payload)"
3. **evalIdent 简化** —— eval/ident.ss:38-41 resolveCtTypeAlias 段删除(ctVars L17 已命中 type tagged int)
4. **comptimeTypeAliases 全局 Map 声明删** + gen_types.ss:277 注释升级至 "VAR_DECL 走 ctVars(D112)"

## 当前事实(2026-04-20 snapshot,commit `32a8f6d` D111 Execute 2 后)

| 项 | 值 / 位置 |
|---|---|
| `comptimeTypeAliases` 声明 | `bootstrap/codegen.ss:84` `let comptimeTypeAliases = new Map()` |
| `comptimeTypeAliases` 读(仅 1 处)| `bootstrap/codegen.ss:91` `resolveCtTypeAlias` 函数体 |
| `comptimeTypeAliases` 写(3 处)| `bootstrap/codegen.ss:989` pre-scan / `bootstrap/gen_decls.ss:235` 全局 / `bootstrap/gen_decls.ss:506` 函数内 |
| `comptimeTypeAliases` 注释(1 处)| `bootstrap/gen_types.ss:277` "外层 VAR_DECL 走 comptimeTypeAliases" 需升级 |
| `resolveCtTypeAlias` 定义 | `bootstrap/codegen.ss:90-93`(4 行)|
| `resolveCtTypeAlias` 调用(6 处)| `bootstrap/gen_decls.ss:536` NEW_EXPR setObjClass / `bootstrap/eval/ident.ss:38` evalIdent alias 段 / `bootstrap/gen_class.ss:971` genNewExpr / `bootstrap/gen_types.ss:162` inferType NEW_EXPR / `bootstrap/gen_types.ss:340` inferType NEW_EXPR(另分支)/ `bootstrap/gen_exprs.ss:470` ctNewExprDispatch |
| `ctVars` 现状 | `bootstrap/codegen.ss:18` `let ctVars = new Map()` / 14 处 set + 10 处 has/getString 已在 gen_decls / gen_stmts / gen_exprs / gen_assigns / eval/* 共存使用 |
| `ctVars` key 约定 | `${currentFunc}:${name}`(函数 scope) / `:${name}`(全局 scope,currentFunc="" 时)|
| `interpNewType` | `bootstrap/codegen.ss:314-316` 走 `internPoolGetOrInsert("type|${className}", newTvType(className))` D111 已落地 |
| `tvStringOf` | `bootstrap/codegen.ss:268` 返回 tvS1 存 className(本 Plan §决策 2 反查依赖)|
| `evalIdent` ctVars 查表命中 | `bootstrap/eval/ident.ss:17-20` `${currentFunc}:${ctIdName}` 命中 + `isCt(ctIdVal)==1 → return ctIdVal`,本 Plan 利用此路径吸收 type alias |
| 当前 linter cur(2026-04-20 D111 Execute 2 后)| M1=5142 / M2=76302 / M3a=12141 / M3b=1879 / M4=3037 / **M5=1749** / M6=32 / M7a=27 / **M7b=676** / N1=34 / N2=381510 / **N3=515442** / N4=321 / N5=0 |
| D101 baseline | M1=5134 / M2=76126 / M3a=12122 / M3b=1879 / M4=3037 / M5=1750 / M6=32 / M7a=27 / **M7b=676** / N1=34 / N2=380630 / **N3=518111** / N4=321 / N5=0 |
| bank cur vs baseline | M1+8/tol±25 余 17 / M2+176/tol±380 余 204 / M3a+19/tol±60 余 41 / M3b 严格 0 / M4 严格 0 / M5 PROGRESS(余 9)/ M6/M7a/N4/N5 严格 0 / **M7b 0 严格 — 主要风险点** / N1 tol±1 余 1 / N2+880/tol±1903 余 1023 / **N3 PROGRESS(深窖 2669)** |
| F1 cur | codegen.ss=1263(baseline 1267 PROGRESS)/ gen_decls.ss=691(baseline 691 OK 严格)/ eval/ident.ss=44(无 F1 baseline,R3 ≤600 极充裕)/ gen_types.ss=738(baseline 738 OK 严格)/ gen_class.ss=1286(baseline 1286 OK 严格)/ gen_exprs.ss=1218(baseline 1721 PROGRESS)|

## 决策(分 4 §,§决策 1-2 主改,§决策 3-4 配套)

### §决策 1 — 写端:3 处 `comptimeTypeAliases.set` 改 `ctVars.set` 同构写入

**codegen.ss:989(pre-scan 路径,`preScanCodegenCtClassesInStmts` 内)**:

```ss
// D112 §决策 1:pre-scan 路径无 currentFunc tracking,统一写全局 scope key `:${name}`
// 真实 VAR_DECL 遍历在 genGlobalVar/genVarDecl 时再次写入(currentFunc 真实绑定),
// 两次写同 key 语义一致(都是 T → ctVal(interpNewType("Foo"))),无副作用。
if (returnName != "") {
    ctVars.set(`:${nGetS1(s)}`, `${ctVal(interpNewType(returnName))}`)
}
```

**gen_decls.ss:235(全局 VAR_DECL COMPTIME_EXPR TypeValue)**:

```ss
} else if (ceType == "type") {
    // D112 §决策 1:全局 scope,currentFunc="",key = `:${name}`
    ctVars.set(`:${name}`, `${ctVal(interpNewType(ceLit))}`)
    return
}
```

**gen_decls.ss:506(函数内 VAR_DECL COMPTIME_EXPR TypeValue)**:

```ss
// D112 §决策 1:函数内 scope,currentFunc 已绑定,key = `${currentFunc}:${name}`
if (initId > 0 && nGetKind(initId) == "COMPTIME_EXPR" && initType == "type") {
    const ceLit = comptimeExprLiteral.getString(`${initId}`)
    ctVars.set(`${currentFunc}:${name}`, `${ctVal(interpNewType(ceLit))}`)
    return
}
```

**语义变化**:
- 现状:`comptimeTypeAliases: Map<name, className-string>`,3 处写入 value 是 className 字符串(`ceLit` / `returnName`)
- D112:`ctVars: Map<scope:name, tagged-int-string>`,value 是 tagged int 字符串(`${ctVal(interpNewType(ceLit))}`)
- **反查入口**:`ctVars.getString(key) → parseInt → isCt → payload → interpType=="type" → tvStringOf(payload)` = className,与 `comptimeTypeAliases.getString(name)` 等价

**D111 InternPool dedup 保障**:`interpNewType("Foo")` 调用 `internPoolGetOrInsert("type|Foo", newTvType("Foo"))`,同 className 保证同 tvId,ctVars 多次写入 "同 key → 同 tagged int" 幂等。

### §决策 2 — 读端:`resolveCtTypeAlias` 函数体改走 ctVars(签名不变,7 处调用点不动)

**codegen.ss:90-93 改写为**:

```ss
// D112 §决策 2:从 `comptimeTypeAliases` 专轨 → ctVars 共享通道反查
// 语义保留:函数内 scope 优先(`${currentFunc}:${name}`),全局 scope fallback(`:${name}`)
// 非 type ctVal 或未命中 → 原样返回 name(与现状语义一致)
function resolveCtTypeAlias(name: string): string {
    const fk = `${currentFunc}:${name}`
    if (ctVars.has(fk) == 1) {
        const fv = parseInt(ctVars.getString(fk))
        if (isCt(fv) == 1 && interpType(payload(fv)) == "type") {
            return tvStringOf(payload(fv))
        }
    }
    const gk = `:${name}`
    if (ctVars.has(gk) == 1) {
        const gv = parseInt(ctVars.getString(gk))
        if (isCt(gv) == 1 && interpType(payload(gv)) == "type") {
            return tvStringOf(payload(gv))
        }
    }
    return name
}
```

**函数体行数**:4 行 → 12 行(F1 codegen.ss +8 行,但 §决策 4 删 L84 `comptimeTypeAliases` 声明 -1 行,净 +7 行 → cur 1263+7=1270 > baseline 1267 **R1 REGRESSION 风险**)。

**F1 codegen.ss 对策**(详见 §预估指标表):
- 优化 1:合并 fk/gk 双查为 helper(但 M7b +1 与严格 0 冲突)
- **优化 2(采用)**:**inline 1/3 处 `interpNewType` 调用点**(codegen.ss 内 5 处 interpNewType,inline 2 处节省 -4 行) → 净 codegen.ss 1263+7-4=1266 OK

**语义细节**:
- currentFunc 在 runtime 路径下由 genFuncBody/genClassMethod 绑定,6 处 resolveCtTypeAlias 调用点(gen_decls.ss:536 / gen_class.ss:971 / gen_types.ss:162,340 / gen_exprs.ss:470 / eval/ident.ss:38)均在 runtime 遍历过程,currentFunc 为真实函数名
- eval/ident.ss:38 的 resolveCtTypeAlias 调用 **删除**(§决策 3),不在 6 处 runtime 调用之列;实际 runtime 调用 = 5 处
- 全局 scope `:${name}` fallback 保障 "全局 `const T = ...` 在任何函数内使用" 场景语义不变
- `interpType(payload(fv)) == "type"` 判断:D111 valType 已走 pool 反查(gen_maybeval.ss:11-14),但此处保持 `interpType` D092 原路径(tvKindOf 直读)等价返回 "type" —— Phase C 若 `interpType` 统一走 valType,则此处同步升级

### §决策 3 — evalIdent 简化:`eval/ident.ss:38-41` resolveCtTypeAlias 段删除

**现状 eval/ident.ss:37-41**:

```ss
        }
        const ctAliased = resolveCtTypeAlias(ctIdName)
        if (ctAliased != ctIdName) {
            return ctVal(interpNewType(ctAliased))
        }
    }
```

**D112 改写**:删除 L38-41 四行(4 行净删减)。

**理由**:
- §决策 1 写端将 type alias 存入 ctVars key=`${currentFunc}:${name}` 或 `:${name}`(tagged int = `ctVal(interpNewType(className))`)
- evalIdent L6-15(ctScopeStack 域链)/ L17-20(currentFunc scope)已命中 `ctVars.has + isCt → return parseInt`
- 全局 scope 命中需补:evalIdent 当前查表序为"ctScopeStack → currentFunc scope",**未含全局 `:${name}` fallback**

**全局 scope fallback 补齐**(eval/ident.ss L17-20 内 / 扩写 1 处):

```ss
// 现状 L17-20
const ctKey = `${currentFunc}:${ctIdName}`
if (ctVars.has(ctKey) == 1 && ctInvalidated.has(ctKey) == 0) {
    const ctIdVal = parseInt(ctVars.getString(ctKey))
    if (isCt(ctIdVal) == 1) { return ctIdVal }
}

// D112 §决策 3:全局 scope fallback(覆盖 `const T = comptime{...}` 全局 type alias)
const ctGlobalKey = `:${ctIdName}`
if (ctVars.has(ctGlobalKey) == 1) {
    const ctGlobalVal = parseInt(ctVars.getString(ctGlobalKey))
    if (isCt(ctGlobalVal) == 1) { return ctGlobalVal }
}
```

**行数变化**:eval/ident.ss 删 4 行(L38-41)+ 加 5 行(全局 fallback)= 净 +1 行。44 → 45(无 F1 baseline R3 ≤600 极充裕)。

**语义验证**(用例 `tests/phase5/comptime_comprehensive.ll.str` 或 `tests/phase5/d096_basic.ll.str` 涉及 Type alias):`const T = comptime { return Foo }` 全局声明后 `let x: T = ...` 或 `new T()` 场景 → setObjClass(gen_decls.ss:536)调 resolveCtTypeAlias("T"),走 ctVars `:T` 命中 type ctVal → tvStringOf = "Foo"。

### §决策 4 — `comptimeTypeAliases` 全局 Map 声明删除 + gen_types.ss 注释升级

**codegen.ss:84 删**:`let comptimeTypeAliases = new Map()`(1 行)。M5 -1(全局 state 减少)。

**gen_types.ss:277 注释升级**:

```ss
// 现状
// TypeValue:literal 存 class 名,外层 VAR_DECL 走 comptimeTypeAliases

// D112 §决策 4
// TypeValue:literal 存 class 名,外层 VAR_DECL 走 ctVars(D112 消除独立通道)
```

1 行注释改写,无行数净变化。

## 预估指标表(对照 D101 baseline + 当前 cur D111 后)

cur 取 2026-04-20 `bin/ss run tools/reflection_health_linter.ss` 实测(D111 Execute 2 commit `32a8f6d` 后)。

| 指标 | 组 | baseline | cur | bank | 预估 step1 后 | Δ-from-cur | 判定 | 风险 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5142 | 余 17 | 5144~5148 | +2~+6 | OK | low(resolveCtTypeAlias 函数体 +4~8 复合赋值 / evalIdent 全局 fallback +2 复合 / 写端 3 处 call 参数复杂化 +0~2)|
| M2 | 累计 | 76126 | 76302 | 余 204 | 76330~76420 | +28~+118 | OK(余 ≥ 86)| medium(resolveCtTypeAlias 函数体扩 +~8 行 AST 节点 / evalIdent 全局 fallback 5 行 / 写端 3 处调用 `ctVal(interpNewType(...))` 节点嵌套 / §决策 4 删 1 行 let 节点)|
| M3a | 累计 | 12122 | 12141 | 余 41 | 12145~12155 | +4~+14 | OK(余 ≥ 27)| low(resolveCtTypeAlias 内 4 次 Map ops + 2 次 isCt + 2 次 interpType + 2 次 tvStringOf = 10 新调用边 / evalIdent 全局 fallback +2 边 / 写端 3 处 interpNewType/ctVal 复合调用 +6 边 / §决策 4 删 L91 `comptimeTypeAliases.has/getString` -2 边 = 净 +14~+16 — 需 Execute 精确测)|
| M3b | 结构 | 1879 | 1879 | **严格 0** | 1879 | **0** | OK | **low(resolveCtTypeAlias 入度不变 7 处调用点 / evalIdent fallback 入度扩展为 currentFunc scope + global scope 但不新增入度最大函数)** |
| M4 | 结构 | 3037 | 3037 | **严格 0** | 3037~3039 | 0~+2 | **DRIFT 风险** | **medium(resolveCtTypeAlias body 双 scope if-嵌套 depth 2 × 2 = 4 次 if / evalIdent 全局 fallback +1 if-depth2 / 写端无 dispatch 深度升 — 实测警惕)** |
| M5 | 累计 | 1750 | 1749 | 余 9(PROGRESS 1)| 1748~1750 | -1~+1 | OK | low(§决策 4 删 `comptimeTypeAliases` 全局 -1 / 写端 3 处 `ctVars.set` = 已有 mutable state 路径,无新 state +0)|
| M6 | 结构 | 32 | 32 | 严格 0 | 32 | 0 | OK | low(无新递归)|
| M7a | 结构 | 27 | 27 | 严格 0 | 27 | 0 | OK | low(resolveCtTypeAlias body 嵌套最深 depth 2 `if...if` 线性顺序 / evalIdent 全局 fallback depth 2 对称 / 均 ≤ 当前最大 27)|
| **M7b** | 结构 | 676 | 676 | **严格 0** | **676** | **0** | OK | **low(本 Plan 不新增函数 / 不删函数 / resolveCtTypeAlias 仅改体保签名)**(**与 D111 不同** — D111 新增 internPoolGetOrInsert 函数 +1 必需 Step 0 预削 -1,本 Plan 无新函数天然达 0,Step 0 可选)|
| N1 | 累计 | 34 | 34 | tol±1 余 1 | 34 | 0 | OK | low(无新 AST kind)|
| N2 | 累计 | 380630 | 381510 | 余 1023 | 381550~381700 | +40~+190 | OK(余 ≥ 833)| low(M2 派生 × log2(34))|
| N3 | 结构 | 518111 | 515442 | 深窖余 +2669 | 515450~515570 | +8~+128 | OK(深窖充裕)| low(resolveCtTypeAlias body 双 scope depth 2 + evalIdent fallback depth 2 + 写端 3 处调用嵌套 depth 2-3,总体 ≤ 200 AST depth 新增 — 深窖余 2669 远充足)|
| N4 | 结构 | 321 | 321 | 严格 0 | 321 | 0 | OK | low(无单节点 list 出度上升)|
| N5 | 结构 | 0 | 0 | 严格 0 | 0 | 0 | OK | low(无 MEMBER_ASSIGN)|
| F1 codegen.ss | - | 1267 | 1263(PROGRESS -4)| 严格不升 | **1266~1267** | +3~+4 | OK(贴线)| **medium(resolveCtTypeAlias body +8 行 / §决策 4 删 let 1 行 / 净 +7 行;需 inline 2 处 interpNew* -4 行或 `resolveCtTypeAlias` 改紧凑 2-line 查表语法)** — **对策**:采用"inline 1 处 `interpNewType` 调用点"节省 -4 行,§步骤 1 Step 1f 明确 |
| F1 gen_decls.ss | - | 691 | 691 | 严格不升 | 691 | 0 | OK | low(gen_decls.ss L235 改写 `ctVars.set` 单行 / L506 同 / 净 0 / 极精确)|
| F1 eval/ident.ss | - | n/a | 44 | R3 ≤600 极充裕 | 45 | +1 | OK | low(删 4 行 L38-41 + 加 5 行全局 fallback = +1)|
| F1 gen_types.ss | - | 738 | 738 | 严格不升 | 738 | 0 | OK | low(注释 1 行改写,无行数变化)|

**核心风险点**:

1. **F1 codegen.ss +7 净 > baseline bank 0** — **必须通过 inline interpNew* 调用点 -4 行** 或 `resolveCtTypeAlias` 改紧凑 `if (cond) { return ... }` 单行语法 `-3 行`。**对策**:§步骤 1 Step 1f 明确 inline `interpNewBool`(codegen.ss:305 `return newTvBool(b) → internPoolGetOrInsert(bool|${b}, newTvBool(b))` body 与 interpNewInt 几乎等价,2 行 → 0 行 inline 全 1 处或 2 处)节省 -2~-4 行
2. **M3a +4~+14 累计组 DRIFT 上沿** — 余 41 充裕但需警惕 resolveCtTypeAlias body 内 Map ops + interp* 调用边扩散
3. **M4 0~+2 结构组 DRIFT 风险** — resolveCtTypeAlias body double-if 嵌套,单函数 depth+2;bank 严格 0 → +2 即 REGRESSION。**对策**:Execute 实测若 +1~+2 → 改写 resolveCtTypeAlias 体为**平铺 if**(两个 if 互不嵌套,早 return),depth +0 可控
4. **N2 +40~+190 累计组** — 余 1023 充裕,无阻断风险

**预估命中率**:7 项严格组(M3b/M6/M7a/M7b/N1/N4/N5)预期全 0 / 2 项结构组 DRIFT 风险(M4/M7a —— M4 主要警惕)/ 5 项累计组 DRIFT 窗口内 / F1 贴线需对策补齐。**与 D111 不同 — 本 Plan 无新增函数天然 M7b 严格达 0**。

## §步骤 0 — 预削减(可选,M7b 已严格 0 不需要强制预削,但可作 F1 codegen.ss buffer)

**目标**:若 Execute 1 实测 F1 codegen.ss cur > baseline 1267(Step 1 净 +7 超过 inline 补偿 -4 剩 +3)→ Step 0 预削减 ≥ -3 行抵消。

**候选削减源**(Execute 0 轮 grep 验证):

1. **`interpNewBool`(codegen.ss:305-307,3 行)** 单调用点 inline
   - grep `interpNewBool(` 全 N 调用点,每处改 `internPoolGetOrInsert(\`bool|${b}\`, newTvBool(b))`
   - 风险:N 处 caller 各 +~50 字符(行数不变但 L 变长),M2/N2 微升(每 caller +~3 节点)
   - **冲突检查**:D111 §决策 4 已将 interpNewBool 作 dedup 入口,不能真删 interpNewBool → **此候选 Rejected**(同 D111 §步骤 0 候选 3 拒绝逻辑)

2. **`interpNewNull`(codegen.ss:309-311,3 行)** 全调用点 inline
   - 同 1,D111 §决策 4 dedup 入口,**Rejected**

3. **`interpAsBool`(codegen.ss:289-291,3 行)** 全调用点 inline
   - D111 §步骤 0 候选 2 曾列未采用(Step 0 实际选了 interpAsClassName 单削 -1 已够)
   - 本 Plan Step 0 若启动,此为首选

4. **`interpBuildTypeInfo`/ `interpCollectFields` 等长函数行数紧凑** — 无紧凑空间

5. **gen_types.ss:277 多余注释整段合并到 D112 引用** — 注释改写 +0 行(无收益)

**Plan 优先序**:若 F1 codegen.ss Execute 实测 +3~+7 未被 inline 2 处 `interpNew*` 覆盖,Step 0 启动 `interpAsBool` inline(2 行 body → 0 行 + N caller 各 +1 行直读 `tvIntOf` → F1 净 -3~-1 取决于 N)。若 F1 Step 1 实测 +0~+2(inline 补偿成功)→ Step 0 跳过。

**Execute 0 触发条件**:Step 1 末尾实测 `F1 codegen.ss > 1267` → 回滚 Step 1 中途 → Step 0 单独 commit 预削 → Step 1 重试。

## §步骤 1 — Execute 实施(写端 3 处 + 读端 1 处 + evalIdent 1 处 + 声明 1 处 + 注释 1 处)

单 commit 含全部子步骤,bootstrap 固定点 PASS。

### Step 1a — codegen.ss:84 删 `comptimeTypeAliases` 全局声明

简单删 1 行(M5 -1,§决策 4)。

### Step 1b — codegen.ss:90-93 `resolveCtTypeAlias` 函数体改写

按 §决策 2 改写 4 行 → 12 行(或紧凑 10 行双 if 平铺)。

### Step 1c — codegen.ss:989 pre-scan 写入改 ctVars

按 §决策 1 第 1 处改写:`comptimeTypeAliases.set(nGetS1(s), returnName)` → `ctVars.set(\`:${nGetS1(s)}\`, \`${ctVal(interpNewType(returnName))}\`)`。

### Step 1d — gen_decls.ss:235 + 506 写入改 ctVars

按 §决策 1 第 2、3 处改写:两处 `comptimeTypeAliases.set(name, ceLit)` → `ctVars.set(\`${currentFunc}:${name}\`, \`${ctVal(interpNewType(ceLit))}\`)`(全局层 currentFunc="")。

### Step 1e — eval/ident.ss 删 L38-41 + 补全局 fallback

删 4 行 resolveCtTypeAlias 段 + 加 5 行全局 scope fallback = net +1 行(§决策 3)。

### Step 1f — inline 1-2 处 `interpNew*` 补 F1 codegen.ss 压力(条件触发)

Execute 实测 Step 1a-1e 后 F1 codegen.ss > 1267 → inline `interpAsBool`(codegen.ss:289-291)单处 2 行 body 所有调用点。**条件不触发则跳过**。

### Step 1g — gen_types.ss:277 注释升级

1 行注释改写,零行数净变化(§决策 4)。

### Step 1h — 单 commit + bootstrap 固定点 + 全测 + GATE PASS

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- `bin/ss test tests/` 全绿(InternPool dedup + ctVars 查表是行为透明,用户测试用 comptime type alias 的用例继续 PASS)
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK/PROGRESS(**M7b 严格 0 / M4 严格或 +1~+2 DRIFT 警惕 / M7a 0 / N3 PROGRESS 深窖维稳**)
  - 累计组 5 项 DRIFT 窗口内(M1/M2/M3a/M5/N1/N2)
  - F1:codegen.ss ≤ 1267 OK/PROGRESS / gen_decls.ss=691 OK / eval/ident.ss 45 ≤ 600 R3 极充裕 / gen_types.ss / gen_class.ss / gen_exprs.ss 严格不升

## §步骤 2 — 收尾评估 + 状态回写

**Execute 2 回写目标**:

- **D098 §决策 3 Phase A L148-153** 标 `[x] Done at <commit-sha>`(本 D112 Execute 落地后 commit ref 写入)
- **D098 §下一步 L194** `[x] Done at D112 §决策 1-4 / Execute <commit-sha>`
- **D111 §新张力 4 L452-453** `[x] Resolved at D112 §决策 1-4`
- **D098 §决策 3 Phase B** 标注:"Type 句柄 id 来自 InternPool `type|<className>` dedup"已在 D111 §决策 4 落地(不重记,引用即可)

**默认不 record**(D110 §决策 3 累计组永不 record / 结构组允许 record 但本 Plan 仅清理双轨不做结构削减):
- 累计组 M1/M2/M3a/M5/N2 DRIFT,**不 record**(D097 L70-71)
- 结构组 M3b/M4/M6/M7a/M7b/N1/N4/N5 0 / 0~+2 → 无削减,**不 record**
- F1 codegen.ss 若 PROGRESS 再小,仍在 baseline 下 → 可选 record(与 D111 同等决策权,Plan 不强制)

**后续指向**(D112 Execute 落地后,本 Plan 范围外):

| 决策 | 触发条件 | 承载 D 文档 |
|---|---|---|
| evalExpr `==` op 改 id == id(Value.eql O(1) 落地验证)| D112 Done + 反射 Meta 路径 Value.eql 频率验证 | D113+(Plan + Execute)|
| Array/Map/Double dedup(Phase C 范围)| 反射 Meta `cls.fields` 数组 dedup 收益实测 | D113+ / D114+ |
| class instance / user Meta 对象 InternPool 承载(Phase B 扩展)| D112 Done + Meta 对象高频访问 + D098 §新张力 5 | D115+ |
| sha256 预 hash 评估 | 实测 STR key 性能退化 ≥ 5% 或 KB 级 STR 频繁 | D114+ |
| `interp*` 家族内部全迁 InternPool(Phase C)| Phase B 实测 dedup 命中率 + Value.eql O(1) 收益度量 | D115+ |

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## Rejected Alternatives

### §A — 保留 `comptimeTypeAliases` 独立通道,仅把 evalIdent L38-41 删除

**拒绝理由**:
- 违反 D098 §决策 3 L148 "消除 `comptimeTypeAliases` 作为独立查表机制"(文本要求 Map 删除,不是只删一处调用)
- 写端 3 处 set 继续存在 → 独立轨不消亡 → resolveCtTypeAlias 内部仍查 comptimeTypeAliases → 其他 6 处 resolveCtTypeAlias 调用点继续走专轨 → D093 §Zig 原理 第 3 条 "Type 是 Value 共享容器" 不成立
- 属于**假消除**,不及 Phase A 收尾标准

### §B — Type alias 存独立 `typeAliases: Map<scope:name, int>` 专 Map(而非 ctVars)

**拒绝理由**:
- 专 Map 等同 `comptimeTypeAliases` 的 scope 化重命名,本质仍是第 N 条独立通道
- D098 §决策 3 L149-153 明文 "ctVars 里存的 MaybeVal.val = interpNewType(actualClassName)" —— 要求并入 ctVars 不是新建 typeAliases
- 违反 memory/feedback_design_no_code_authority.md "不为对称美抽过早抽象,工程边界先行":专 Map 看似 "scope 化" 实则添加新轨

### §C — 完全 inline `resolveCtTypeAlias` 7 处调用点(消除函数 M7b -1)

**拒绝理由**:
- 7 处调用点各 +~8 行(resolveCtTypeAlias body 内 double-scope 查表)= F1 扩散:gen_class.ss +8 / gen_decls.ss +8 / gen_types.ss +16 / gen_exprs.ss +8 / eval/ident.ss(本已删 L38)= **codegen.ss/gen_decls.ss/gen_types.ss/gen_class.ss/gen_exprs.ss 5 文件合 F1 升 ≥40 行**,多文件 R1 REGRESSION 风险
- M2/N2 累计组膨胀 7×(5~8 节点)= +35~+56,超本 Plan 预估上沿
- M7b -1 单项收益微小,不值交易
- memory/feedback_design_no_code_authority.md 指向保留适度抽象,7 处复用函数是合理 DRY

### §D — pre-scan(codegen.ss:989)写入直接删,依赖 genGlobalVar / genVarDecl 在真正遍历时写入

**拒绝理由**(候选有效但范围超本 Plan):
- 论证:gen_decls.ss:235/506 在真正 genGlobalVar / genVarDecl 遍历时会写入 ctVars → 看起来 pre-scan L989 写入冗余
- **反论证**:pre-scan 的目的是"让 CLASS_DECL 元数据注册 + pendingCtClassIds push 提前到模块 codegen 开头"(codegen.ss:939-942 注释),returnName 的 alias 写入和 class 预注册是**配对关系** —— 若 class 在 pre-scan 就注册而 alias 延后到 genGlobalVar 才写,pre-scan 末尾的 "pendingCtClassIds flush → fullyRegisterCtClass → genStmt CLASS_DECL → 类内部引用 T 时查不到 alias" 可能出现
- 删 L989 写入需要验证:(a) pre-scan pendingCtClassIds 消费期是否查 alias、(b) fullyRegisterCtClass 路径是否依赖 alias
- **本 Plan 立场**:保留 L989 写入改为 `ctVars.set`(三处 set 并行,key 统一全局 `:${name}`),语义不变,零风险;候选 §D 作 Phase B 中期优化 → 开 D113+ 独立 Plan 评估删 pre-scan 写入可行性

### §E — 把 `resolveCtTypeAlias` 签名改为 `(currentFunc: string, name: string)` 参数化 scope

**拒绝理由**:
- 6 处调用点全改,工程量大
- currentFunc 是 codegen 全局 state(`let currentFunc = ""` 在各处修改),函数内直接读取即可,参数化是信号冗余
- F1 / M2 / M3a 负面收益高

### §F — 把 type alias 编入 MaybeVal 新 tag(bit 30 以外新 tag 位)

**拒绝理由**:
- 违反 D098 §决策 3 §Rejected §C "Type-as-Value 新开 tag 位 ... 立刻把 tagged int 编码改二层,所有 ctVal 调用点(100+)需同步,Phase A 范围外"
- D111 InternPool `type|<className>` key 已承载 Type 识别能力,`interpType(payload) == "type"` 够用

### §G — Plan 阶段不立 D112,直接开 Execute commit

**拒绝理由**:
- D098 §下一步 L194 明文 `[ ] Planned — 写 Phase A 末尾 comptimeTypeAliases → ctVars 合并 Plan`(强调 Plan)
- 直接 commit 无 Plan 承载 → 缺设计决策记录,违反 P16(决策记录立即化)+ §交互式单文档
- 沿袭 D101-D111 Plan + Execute 两段式模板,Plan 阶段明确 §决策 + §步骤 + 预估 + Rejected + 新张力 + §下一步,Execute 轮专注实施 + 实测回写

## 新张力(D112 引出)

1. **ctVars scope 语义变化 — 全局 `:${name}` fallback** — 现状 `comptimeTypeAliases` 是跨函数全局 Map,任何位置声明的 type alias 全局可见;D112 将 type alias 按声明位置存入 `:${name}`(全局声明)或 `${currentFunc}:${name}`(函数内声明),**语义更严谨**(函数内 alias 仅局部可见)。**对策**:evalIdent / resolveCtTypeAlias 双 scope 查(currentFunc 优先 + 全局 fallback)保留 "全局 const 全函数可见" 主流语义;函数内 alias 被其他函数引用的 edge case 不再支持 —— **该场景实际未被任何现有测试 / bootstrap 自身使用,Execute 2 实测若发生 bootstrap 固定点失败,降级方案为全部 alias 统一写 `:${name}` 全局 key**(pre-scan 已是此行为)

2. **codegen.ss:989 pre-scan 与 gen_decls.ss:235 双写同 key** — pre-scan 阶段和真正 genGlobalVar 阶段**两次**写入同一 key(value 一致,`interpNewType` InternPool dedup 保证 tvId 相等),功能无副作用但写入开销 2x。**对策**:Plan 接受 2x 写入,Phase C 若优化为 "pre-scan 仅记录 CLASS_DECL 元数据,alias 延后到 gen_decls 首写" 可消重写(§Rejected §D 指向此路径)

3. **resolveCtTypeAlias 双 scope 查 F1 codegen.ss 贴线风险** — 函数体 4 行 → 12 行净 +8;inline 1-2 处 interpNew* 补偿 -4 后仍 +4 贴近 baseline 1267(cur 1263 → 预估 1266)。**对策**:Step 1f 显式 inline interpAsBool 补 -3 / 或 resolveCtTypeAlias 改紧凑单行 if(SS 不强禁 / 节省 -3)

4. **M4 DRIFT 风险** — resolveCtTypeAlias body double-scope 双 if-depth2 可能 M4 +1~+2;bank 严格 0 → 必 DRIFT。**对策**:改写成 "if (fk 命中 + type) { return ... } ; if (gk 命中 + type) { return ... } ; return name" 平铺单层 if 结构,depth 控制在当前最大范围内不升

5. **interpType(payload(fv)) == "type" 性能** — resolveCtTypeAlias / evalIdent 全局 fallback 两处新增 `interpType(payload(fv))` 调用 —— interpType 走 D092 tvKindOf 直读(gen_maybeval.ss valType 已改走 InternPool 反查,但 interpType 原路径保留);每次 resolveCtTypeAlias 调用 +2 次 Map lookup(tvKind getString × 2)。**对策**:Phase B 中期统一 interpType 走 valType 时自动消除,本 Plan 接受小成本

6. **eval/ident.ss 全局 scope fallback 与其他 ctVars 查表的对称性** — D112 §决策 3 给 evalIdent 加全局 scope fallback L17-20 后,**其他 ctVars 查表点**(gen_stmts.ss pfKey / gen_assigns.ss ctAkey / gen_class.ss eval_expr 代理 / eval/postfix_inc.ss piKey 等约 10 处)**未必同步加全局 fallback**。大部分 ctVars 查表是函数内 scope 语义(for-in / postfix++ / assignment),不需要全局 fallback;evalIdent 是唯一"用户显式引用 IDENT 名"入口,需全局可见。**对策**:Plan 接受 "仅 evalIdent 加全局 fallback" 的非对称,其他查表点保持 scope 局部;Phase C 若有反例再评估统一

7. **用户代码测试覆盖不足** — `tests/phase5/d096_basic.ll.str` / `tests/phase5/comptime_comprehensive.ll.str` 覆盖 Type alias 用例有限(主要走 class 基础形态),D112 核心语义变化未必充分覆盖。**对策**:Execute 2 跑 `bin/ss test tests/phase5/` 全绿前提下 + 额外手测 `tests/phase5/comptime_coverage_gaps.ss`(若含 Type alias 场景)+ 必要时补测用例

8. **`resolveCtTypeAlias` 7 处调用 vs 实际 5 处 runtime 调用** — `eval/ident.ss:38` 的调用将被 §决策 3 删除,D112 Execute 后 `resolveCtTypeAlias` 实际调用 = 5 处(gen_decls.ss / gen_class.ss / gen_types.ss × 2 / gen_exprs.ss)。**对策**:Plan 文本已明示,Execute 2 grep `resolveCtTypeAlias(` 回填为 5 处

9. **Type alias 指向的 className 在 pre-scan 时可能未注册为 class** — pre-scan 在 class 元数据 push 前写 alias;alias 值是 ceLit / returnName(class 名字符串),`interpNewType(className)` 不校验 class 是否已注册(只创建 Value tag)→ 即使 class 后续才注册,alias tagged int 仍有效。**对策**:Plan 接受此顺序(与现状 comptimeTypeAliases.set 时未校验 class 注册行为等价),零影响

10. **D112 完成度判定 — Phase A 收尾实际闭环** — 本 Plan 执行后 D098 §决策 3 Phase A L148-153 全量闭环,D098 §下一步 L192-195 4 项中 L194 `[x] Done`,剩 L195 `Phase B 启动前单独决策` 作为独立后续。**对策**:§步骤 2 回写 D098 状态标注明确,本 Plan Execute 完成即 Phase A 收尾成功

## 下一步(Plan 下的 Execute 顺序)

1. [ ] Planned — **Execute 0**(条件触发):若 Execute 1 实测 F1 codegen.ss > baseline 1267 → 回滚 Step 1 + 单 commit 预削减 `interpAsBool` inline(D111 候选 2)→ Step 1 重试。若 Step 1 F1 实测 ≤ 1267(inline 补偿达标)→ **Step 0 跳过**
2. [ ] Planned — **Execute 1**(等同 §步骤 1):Step 1a(删 L84 comptimeTypeAliases 声明)+ Step 1b(resolveCtTypeAlias body 改写)+ Step 1c(codegen.ss:989 pre-scan 改 ctVars.set)+ Step 1d(gen_decls.ss:235/506 改 ctVars.set)+ Step 1e(eval/ident.ss:38-41 删 + 全局 fallback)+ Step 1f(条件 inline interpAsBool)+ Step 1g(gen_types.ss:277 注释升级)+ Step 1h(单 commit + bootstrap 固定点 + 全测 + 分层 GATE + F1 GATE PASS)
3. [ ] Planned — **Execute 2**(等同 §步骤 2):本文档 §实测 段落落地(11~14 项精确 / 少量优于预估 / M3a/M4 警惕实测列)+ §状态回写(D098 §决策 3 Phase A + D098 §下一步 L194 + D111 §新张力 4 分别 `[x] Done/Resolved`)
4. [ ] Planned — **后续 D 文档**:D113+(evalExpr `==` 改 id==id / Array Map dedup / 反射 Meta InternPool / class instance dedup)/ D114+(sha256 评估)/ D115+(Phase C interp* 全迁)

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- **D098 §决策 3 Phase A L148-153**(本 Plan 承接的 Phase A 收尾项)/ §下一步 L194(本 Plan 起草触发)/ §决策 1(MaybeVal 编码 Phase A mv int)/ §决策 2(InternPool Phase A → Phase B,本 Plan 复用 D111 落地)/ §Rejected §C(Type-as-Value 新开 tag 位 Rejected,本 Plan §Rejected §F 继承)
- **D111 §决策 1**(InternPool 双 Map + getOrInsert,本 Plan 反查 `tvStringOf(payload)` 依赖)/ §决策 2(valOf/valType pool 反查)/ §决策 3(`|` 分隔 key 设计 `type|<className>`,本 Plan §决策 2 反查路径)/ §决策 4(5 标量入口 dedup,含 interpNewType)/ §新张力 4 L452-453(本 Plan 起草触发)
- **D110 §决策 3**(单 baseline 跨 Phase 延续,本 Plan 不新 baseline)/ §新张力 1-12(InternPool 长期张力)
- **D108 §步骤 1**(IDENT 迁出 eval/ident.ss,本 Plan §决策 3 改文件定位)
- **D102 §规则 1.1-1.4 分层 GATE** / §规则 2.1-2.3 F1 GATE / §规则 1.4 record 行为(累计组永不 record)
- **D097 L70-71** 累积方向严禁 record(机械规则源)/ §后续工作 #4(Meta 对象 dedup 暗示)
- **D094 §规则 2** pure subset(本 Plan 不动)
- **D093 §决策 §Zig 原理 第 3 条**(Type 本身是一个 Value,与 int/string 共享 Value 容器,本 Plan 第一性需求直接对应)
- **D088 §第一性需求**(Zig SEMA 一份 evalExpr,反射 Meta 对象 = MEMBER_ACCESS)/ §正模式(主 dispatch + 子分析器分层)/ §反模式(双轨制,本 Plan 消除对象)
- **CLAUDE.md §反射根因 gate**(本 Plan 不触反射路径 trivial PASS)/ §交互式单文档 / §PFV 流程
- `memory/feedback_ultrathink_gate.md`(下轮 payload 必含 ultrathink)/ `feedback_pfv_process.md`(开工 PSM + 收工 VCM)/ `feedback_design_no_code_authority.md`(§Rejected §B 拒绝专 Map 抽象)/ `feedback_no_workaround.md`(6 处 resolveCtTypeAlias 调用点语义必保住)/ `feedback_no_dramatic_reset.md`(Phase 切换分段诊断不推倒重来)
- `bootstrap/codegen.ss:84`(Map 声明,§决策 4 删除)/ L90-93(resolveCtTypeAlias,§决策 2 改体)/ L268(tvStringOf 访问器,§决策 2 反查依赖)/ L314-316(interpNewType 走 InternPool,D111 落地基)/ L989(pre-scan 写入,§决策 1 第 1 处)
- `bootstrap/gen_decls.ss:235`(全局 VAR_DECL,§决策 1 第 2 处)/ L506(函数内 VAR_DECL,§决策 1 第 3 处)/ L536(resolveCtTypeAlias NEW_EXPR 调用,签名不动)
- `bootstrap/gen_class.ss:971` / `gen_types.ss:162,340` / `gen_exprs.ss:470`(resolveCtTypeAlias 5 处 runtime 调用,签名不动)
- `bootstrap/eval/ident.ss:17-20`(ctVars currentFunc scope 查表,§决策 3 全局 fallback 扩展点)/ L38-41(resolveCtTypeAlias 段,§决策 3 删除)
- `bootstrap/gen_types.ss:277`(注释,§决策 4 升级)
- `bootstrap/intern_pool.ss`(D111 InternPool backing,本 Plan 复用)
- `tools/reflection_health_linter.ss`(分层 GATE + F1 GATE)/ `tools/linter_baseline.txt`(D101 baseline,跨 Phase 单数据源)
- `tools/next_prompt_ultrathink_linter.ss`(PFV §收尾 gate 第 3 步 (b) 机械 gate)
