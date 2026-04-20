# D114: checker.ss 按职责细分 5 文件(types / scope / func / class / driver)

**Status:** Plan Done / Execute 1 [x] Done at `bootstrap/checker/check_types.ss` / Execute 2 [x] Done at `bootstrap/checker/check_scope.ss` / Execute 3 [x] Done at `bootstrap/checker/check_func.ss` / Execute 4 [x] Done at `bootstrap/checker/check_class.ss:1` (15 函数 511 行,checker.ss 962 → 466 ≤ 600,F1 baseline `F1:bootstrap/checker/checker.ss=1299` 删除)

**目录重组(2026-04-20)**: `bootstrap/checker.ss` + `check_*.ss` 5 文件统一迁至 `bootstrap/checker/` 子目录(族成员 ≥ 6 启用子目录风格,见 `feedback_subdir_split_style.md`)。本文档后文 `bootstrap/checker.ss` / `bootstrap/check_*.ss` 路径均指向子目录下同名文件。F1 baseline 条目同步 `bootstrap/checker/checker.ss=1299` / `bootstrap/checker/check_stmts.ss=1083`。
**Depends on:**
- D088 §第一性需求 L9-13(Zig 路线 SEMA 目标 evalExpr 吸收 kind dispatch)/ §正模式 L387(渐进拆分 SEMA 模块)
- D102 §规则 2.1 R1-R5 L109-113(F1 GATE)/ §规则 2.2 L121 `F1:bootstrap/checker.ss=1299`(已 grep 对照 `tools/linter_baseline.txt:29`)/ §规则 2.4 防规避 L149-155(一拆二 / 分裂伪移硬阻)/ §最终目标 L115"全 ≤ 600"
- D113-codegen-triple-split(Execute 分步模板;gen/ + eval/ 子目录模式)
- D067 null safety 落地(Nullable helper 族的来源)
- P10.1 拆分判据结构清晰 = 单一职责 + 单向依赖,≥ 3 职责类别即不清晰
- CLAUDE.md §交互式单文档 / §PFV 流程 / `memory/feedback_no_workaround.md` / `memory/feedback_600_split_not_inline.md` / `memory/feedback_structure_not_linecount.md` / `memory/feedback_ultrathink_gate.md`

**Date:** 2026-04-20

---

## 第一性需求

`bootstrap/checker.ss` 1299 行单文件物理承载 **5 层职责**(P10.1 反模式"≥ 3 职责类别即不清晰"的 1.67× 超标):

1. **驱动层** — 30+ 全局 state + `initChecker` / `checkerError` / `check` 入口(L1-52 + L54-315 + L757-787 + L1186-1299),~460 行
2. **scope 层** — `pushScope` / `popScope` / `defineVar` / `lookupVar` / `isVarConst`(L316-365),~50 行
3. **func 层** — `defineFunc` / `lookupFunc` / `defineFuncParams` + 参数数量校验 `countParamRange` / `checkArgCount` / `countArgs` / `hasSpreadArg`(L519-541, L705-756),~75 行
4. **class 层** — `resolveCheckerClass` / `inferCheckerClass` / `checkInterfaceImpl` / `checkAbstractImpl` + method/继承/构造器 lookup + `registerCheckerClassDecl` / `preScanComptimeClasses`(L367-517, L542-703, L1006-1185),~493 行
5. **types 层** — Nullable helper 5(`isNullableType` / `isPrimitiveNullable` / `stripNullable` / `makeNullable` / `getNarrowedType`)+ `checkerInferType` + subtyping `baseTypeName` / `extractElemType` / `isTypeCompatible`(L789-1005),~217 行

P10.1 §"单一文件职责单一"原则:"出现 ≥ 3 职责类别即不清晰",checker.ss 5 职责层在同一文件意味着每次 review / 改动必须跨 5 个心智模型,是 D113 §第一性需求"跨模块定位 3x 成本"的等价症状。

**否定证据**:

1. **F1 R4 ≤ 600 目标不可达** —— checker.ss baseline 1299,R1 单调压回每轮最多 -10 行(D100 Execute 1 实测),线性速度到 ≤ 600 需 ~70 轮。D102 §最终目标"全 ≤ 600"14 文件清单里 checker.ss 条目永不消失,R4 永远不触发
2. **反射根因 gate 改 checker 代价持续累积** —— D097 14 指标 + D102 F1 GATE 每次改 checker 都在 1299 行文件定位 5 职责层,即便改 types 层一个 Nullable 规则也要与 initChecker 262 行 + check 入口 114 行同文件滚动审查
3. **D088 §第一性需求 Zig SEMA 子模块分层阻塞** —— SEMA 未来"evalExpr 单函数吸收所有 kind dispatch"需要 types/class/func 分层独立,当前混在 checker.ss 里无物理载体,D113 已把 codegen 的 SEMA 层物理独立(eval/interp_core.ss + eval/ct_driver.ss),checker 的对等分层是这条路线的必经步骤

**收益链**:

```
5 层物理分离(types / scope / func / class / driver)
  → 每文件职责单一,P10.1 结构清晰 gate 达标
  → checker.ss 1299 → ~470,R4 触发 baseline 条目删除(14 文件清单 -1)
  → F1 GATE 向 D102 §最终目标"全 ≤ 600"推进一大步
  → SEMA 类型查询层(check_types)物理独立,对齐 D088 SEMA 子模块分层
  → 后续 checker.ss 改动只触 driver 层 ≤ 500 行,review 成本减半
```

---

## 当前事实(2026-04-20 snapshot,commit 7d21b57 D113 Execute 4 后)

| 项 | 值 / 位置 |
|---|---|
| checker.ss 当前行数 | `wc -l` 实测 **1299** |
| checker.ss F1 baseline | `tools/linter_baseline.txt:29` `F1:bootstrap/checker.ss=1299` |
| `bootstrap/` 已分层子目录 | `eval/`(11 + D113 的 interp_core + ct_driver)/ `gen/`(D113 的 ir_builder)/ `lexer/` `parse/`(空占位)|
| 待分层子目录 | `bootstrap/check/`(**本 Plan 不激活**,5 文件仍放 `bootstrap/` 同层,遵循 `check_stmts.ss` / `check_suggest.ss` 现有扁平模式;未来 check 族膨胀再考虑迁子目录)|
| SS import 机制 | `resolveImports()` 递归内联全部 `.ss`,全局 `let` + 全局 `function` 合并到单一词法 scope,跨模块自动可见 —— 拆分 = 物理搬运,不需要 export 关键字 |
| `check_stmts.ss` / `check_suggest.ss` 现状 | 已在 `bootstrap/` 扁平,L1 注释"Used by checker.ss via textual import" —— 本 Plan 新文件沿用此模式 |
| `check_stmts.ss` 里 Nullable 相关调用 | `rejectPrimitiveNullable`(L95)调 `isPrimitiveNullable`(通过全局 scope)—— Execute 1 后函数物理迁至 check_types.ss,全局 scope 自动接续 |
| main.ss 现有 import | `import { check } from "./checker"`(L6)—— checker.ss 保留 check() 后此 import 不变 |
| F1 baseline 主清单 | 14 条超 600 + `F1:bootstrap/gen/ir_builder.ss=101`(D113 新文件)|

### checker.ss 分段盘点(精确行号 + 归属表)

| 段 | 行号 | 函数/职责 | 行数 | 归属 |
|---|---|---|---|---|
| 顶部注释 + import | 1-8 | — | 8 | **checker.ss 保留** |
| 全局 state 声明 | 11-52 | 30+ 个 `let`(scopeId/currentScope/scopeParent/varNames/varConst/funcNames/ifaceMethods/funcParamMin/funcParamMax/classConsMin/classConsMax/checkerClassParents/methodParamMin/methodParamMax/currentCheckerClass/checkerFieldsForInVars/constFields/checkerFieldTypes/checkerClassFields/funcParamTypes/funcOverloaded/methodParamTypes/methodRetTypes/currentFuncRetType/currentTypeParams/checkerGenericClasses/narrowedTypes/privateFields/privateMethods/protectedFields/protectedMethods/staticMethods/staticFields/currentStaticMethod/abstractClasses/abstractMethods/classMethodNames/checkerDeferredAliases)| ~42 | **checker.ss 保留**(SS let 跨模块共享,搬无收益) |
| `initChecker` | 54-315 | 注册所有 builtin func / method 签名(D063 funcRetTypes + methodRetTypes)| 262 | **checker.ss 保留**(驱动层 lifecycle) |
| **scope 族** | 316-365 | `pushScope` / `popScope` / `defineVar` / `lookupVar` / `isVarConst` | ~50 | **→ check_scope.ss** |
| **class 族 part 1** | 367-517 | `resolveCheckerClass` / `inferCheckerClass` / `checkInterfaceImpl` / `checkAbstractImpl` | ~151 | **→ check_class.ss** |
| **func/method 族** | 519-703 | `defineFunc` / `lookupFunc` / `defineFuncParams` / `registerMethodParams` / `lookupMethodParams` / `lookupMethodParamType` / `lookupMethodRetType` / `lookupPrivateOwner` / `lookupProtectedOwner` / `isSubclassOf` / `totalConstructorParams` / `lookupConsParamType` | ~185 | **→ check_func.ss(pure func 部分)+ check_class.ss(method/继承/构造器 部分)** |
| **arg count 族** | 705-756 | `countParamRange` / `checkArgCount` / `countArgs` / `hasSpreadArg` | ~52 | **→ check_func.ss** |
| `checkerError` | 757-787 | 错误上报 + suggestion 格式化 | 31 | **checker.ss 保留**(跨族共用,留驱动层) |
| **types 族**(**Execute 1**) | 789-1005 | `isNullableType` / `isPrimitiveNullable` / `stripNullable` / `makeNullable` / `getNarrowedType` / `checkerInferType` / `baseTypeName` / `extractElemType` / `isTypeCompatible` | ~217 | **→ check_types.ss** |
| **class 族 part 2** | 1006-1185 | `registerCheckerClassDecl` / `preScanComptimeClasses` | ~180 | **→ check_class.ss** |
| `check` 入口 | 1186-1299 | 主 pass 遍历 | 114 | **checker.ss 保留**(驱动层 entry) |

**行数预算**(每文件余量 ≥ 100 行,方便后续扩展):

| 文件 | 估行 | ≤ 600 余量 |
|---|---|---|
| `bootstrap/check_types.ss` | **~217**(9 函数 + 模块头注释)| 383 |
| `bootstrap/check_scope.ss` | **~55**(5 函数 + 模块头)| 545 |
| `bootstrap/check_func.ss` | **~80**(7 函数:pure func 部分 + arg count)| 520 |
| `bootstrap/check_class.ss` | **~500**(class + method/继承/构造器 + registerCheckerClassDecl + preScanComptimeClasses)| ~100(紧) |
| `bootstrap/checker.ss` 剩余 | **~470**(8 import 行 + 42 globals + initChecker 262 + checkerError 31 + check 114 + 空行 ≈ 470)| 130 |

**check_class.ss 余量最紧 ~100 行**:Phase 扩展(D068/D071/D078 后续扩展私有 / 抽象 / 静态)需要盯紧;触发 R1 阻断时按 §决策 6 细分预案切 `check_class_decl.ss`(registerCheckerClassDecl + preScanComptimeClasses)+ `check_class_impl.ss`(interface / abstract 实现 + lookup 族)。

---

## 决策

### §决策 1 — 5 文件物理分层 + 扁平路径

遵循现有 `bootstrap/check_stmts.ss` / `check_suggest.ss` 扁平模式(非 `bootstrap/check/` 子目录):check 族成员少、`check_stmts.ss` 长期存在 `bootstrap/` 同级,激活子目录无净收益且增加 import 路径变动。

| 层 | 目标文件 | 承载 | 估行 |
|---|---|---|---|
| **types** | `bootstrap/check_types.ss` | Nullable 5(isNullableType/isPrimitiveNullable/stripNullable/makeNullable/getNarrowedType)+ inferType(checkerInferType)+ compat 3(baseTypeName/extractElemType/isTypeCompatible)| ~217 |
| **scope** | `bootstrap/check_scope.ss` | 词法作用域:pushScope/popScope/defineVar/lookupVar/isVarConst | ~55 |
| **func** | `bootstrap/check_func.ss` | 函数签名 + 参数数量:defineFunc/lookupFunc/defineFuncParams/countParamRange/checkArgCount/countArgs/hasSpreadArg | ~80 |
| **class** | `bootstrap/check_class.ss` | class 结构 + 方法/继承:resolveCheckerClass/inferCheckerClass/checkInterfaceImpl/checkAbstractImpl/registerMethodParams/lookupMethodParams/lookupMethodParamType/lookupMethodRetType/lookupPrivateOwner/lookupProtectedOwner/isSubclassOf/totalConstructorParams/lookupConsParamType/registerCheckerClassDecl/preScanComptimeClasses | ~500 |
| **driver** | `bootstrap/checker.ss`(保留)| 30+ 全局 state + initChecker + checkerError + check + import 入口 | **目标 ≤ 470** |

**"5 层"语义**:types / scope / func / class / driver 五个**架构层**物理分离,每层映射一个 `.ss` 文件。check_class.ss 内部再膨胀触 R1 时按 §决策 6 二次细分。

### §决策 2 — 不拆的项(留 checker.ss 驱动层)

| 项 | 原因 |
|---|---|
| 30+ 全局 state `let`(L11-52)| SS `let` 跨模块自动共享,留 checker.ss 顶部是自然入口,搬走无净收益(与 D113 §决策 2 同理)|
| `initChecker`(262 行)| 驱动层 lifecycle:builtin func / method 签名批量注册,跨所有 check 族使用,留驱动层是自然归属 |
| `checkerError`(31 行)| 错误上报 + suggestion 格式化,被 check_stmts / check_types / check_class / check_func 全族调用,留驱动层核心 |
| `check`(114 行)| 主 pass 入口,main.ss 的 `import { check }` 锚点,留驱动层 |
| `import` 块(L5-7)| parser + lexer + check_stmts 的 import 是驱动层需求,保留不动 |

### §决策 3 — 函数族归属裁决(细粒度)

**scope vs class 边界**:`defineVar` 定义 `"class"` 类型(作为符号绑定)而非 class 实例构造 → 归 **scope**(变量名 → 类型的一维绑定)。`resolveCheckerClass` / `inferCheckerClass` 做继承链遍历 → 归 **class**(class 结构图遍历)。

**func vs class 边界**:`defineFunc` / `lookupFunc` / `defineFuncParams` / `countParamRange` / `checkArgCount` / `countArgs` / `hasSpreadArg` 纯函数维度 → 归 **func**。`registerMethodParams` / `lookupMethodParams` / `lookupMethodParamType` / `lookupMethodRetType` / `lookupPrivateOwner` / `lookupProtectedOwner` / `isSubclassOf` / `totalConstructorParams` / `lookupConsParamType` 涉及 class 上下文(ClassName 作为第一参数)→ 归 **class**。

**types vs class 边界**:`checkerInferType` 调 `inferCheckerClass`(class)/ `lookupMethodRetType`(class)/ `lookupVar`(scope)/ `lookupFunc`(func),是 types 层的**消费方**。全局 scope 自动可见,不产生循环依赖(class/scope/func → types 反向无调用)。

**裁决结果**:

- **check_scope.ss**:pushScope / popScope / defineVar / lookupVar / isVarConst(5 函数,L316-365)
- **check_func.ss**:defineFunc / lookupFunc / defineFuncParams / countParamRange / checkArgCount / countArgs / hasSpreadArg(7 函数,L519-541 + L705-756)
- **check_class.ss**:resolveCheckerClass / inferCheckerClass / checkInterfaceImpl / checkAbstractImpl / registerMethodParams / lookupMethodParams / lookupMethodParamType / lookupMethodRetType / lookupPrivateOwner / lookupProtectedOwner / isSubclassOf / totalConstructorParams / lookupConsParamType / registerCheckerClassDecl / preScanComptimeClasses(15 函数,L367-517 + L542-703 + L1006-1185)
- **check_types.ss**:isNullableType / isPrimitiveNullable / stripNullable / makeNullable / getNarrowedType / checkerInferType / baseTypeName / extractElemType / isTypeCompatible(9 函数,L789-1005)

### §决策 4 — Execute 分步(风险递增)

| Execute | 内容 | 估改动 | 风险 |
|---|---|---|---|
| **Execute 1** [x] Done | 创建 `bootstrap/check_types.ss`(~217 行 9 函数:Nullable 5 + inferType 1 + compat 3)。checker.ss 删 L789-1005,1299 → ~1082(R1 单调 -217 PROGRESS)。types 层函数对 scope/func/class 是**单向消费**(前向调用),无反向依赖,最低风险 | 219 行实测 | 低(物理搬运,全局 scope 自动接续;仅 check_stmts.ss `rejectPrimitiveNullable` L95 隔文件调 `isPrimitiveNullable` 需验证)|
| **Execute 2** [x] Done | 创建 `bootstrap/check_scope.ss`(~55 行 5 函数)。checker.ss 删 L316-365,~1082 → ~1027(R1 -55)| 52 行实测 | 低(5 纯函数,state 读 varNames/varConst/scopeParent/scopeVarNames,写同名 state)|
| **Execute 3** [x] Done | 创建 `bootstrap/check_func.ss`(~80 行 7 函数)。checker.ss 删 defineFunc/lookupFunc/defineFuncParams 三连 + countParamRange/checkArgCount/countArgs/hasSpreadArg 四连,1035 → 962(R1 -73)| 81 行实测 | 低(7 纯函数,state 读 funcNames/funcParamMin/funcParamMax/allFuncNameList)|
| **Execute 4** [x] Done | 创建 `bootstrap/check_class.ss`(511 行 15 函数)。checker.ss 删 15 函数段(原 L319-L632 13 函数 + 原 L668-L847 2 函数),962 → 466(**R4 达成**: ≤ 600 → baseline 条目 `F1:bootstrap/checker/checker.ss=1299` 从 `tools/linter_baseline.txt` 删除)| 511 行实测 | 中(15 函数量最大,但均为物理搬运;registerCheckerClassDecl + preScanComptimeClasses 大段迁移已精准 offset)|

**每步后机械 gate**:

1. `./build.sh bootstrap` 固定点(seed → stage1 → stage2 → stage3,stage2 == stage3)
2. `bin/ss test tests/` 全绿
3. `bin/ss run tools/reflection_health_linter.ss` 无 GATE BLOCKED(D097 14 指标 + D102 F1 GATE)
4. F1 baseline 处理:
   - Execute 1 后:新增 `F1:bootstrap/check_types.ss=217`(R3 ≤ 600 通过,直接入 baseline),checker.ss baseline 1299 → ~1082(R1 PROGRESS record)
   - Execute 2 后:新增 `F1:bootstrap/check_scope.ss=~55`(R3 通过),checker.ss baseline ~1082 → ~1027
   - Execute 3 后:新增 `F1:bootstrap/check_func.ss=~80`(R3 通过),checker.ss baseline ~1027 → ~947
   - Execute 4 后:新增 `F1:bootstrap/check_class.ss=~500`(R3 ≤ 600 通过),checker.ss baseline ~947 → ~470(**R4 触发**: ≤ 600 → baseline 条目**删除**)

### §决策 5 — F1 GATE baseline 处理细则

D102 §规则 R3 / R4 对本 Plan 的具体应用:

1. **R3 新文件硬约束**:check_types(217)/ check_scope(~55)/ check_func(~80)/ check_class(~500),四者全 ≤ 600 过 R3
2. **R1 同文件单调**:checker.ss 每步单调下降(1299 → ~1082 → ~1027 → ~947 → ~470),每步 record 新 baseline
3. **R4 baseline 删除**:Execute 4 完成 checker.ss ~470 ≤ 600 → F1 baseline 条目 `F1:bootstrap/checker.ss=1299` **从 `tools/linter_baseline.txt` 删除**,14 文件清单 → 13 文件
4. **D102 §最终目标 L115 "全 ≤ 600" 进度**:本 Plan 完成后 14 → 13(与 D113 codegen.ss R4 候补并列,两者合入后总清单 12)
5. **Execute 4 check_class 紧张**:估 ~500 行逼近 600,若实测 > 600 → 激活 §决策 6 二次细分

### §决策 6 — check_class.ss 细分预案(Execute 4 触 R3 或 Phase 扩展触 R1 时启用)

若 check_class.ss ~500 行后续膨胀(D068/D071/D078 Phase 扩展私有 / 抽象 / 静态规则),触发 R1 阻断时按结构拆:

- **check_class_decl.ss**(~180 行)—— `registerCheckerClassDecl` + `preScanComptimeClasses`:类声明注册 + comptime class 预扫
- **check_class_impl.ss**(~320 行)—— `resolveCheckerClass` / `inferCheckerClass` / `checkInterfaceImpl` / `checkAbstractImpl` + method 族(registerMethodParams / lookupMethodParams / lookupMethodParamType / lookupMethodRetType)+ 继承/构造器族(lookupPrivateOwner / lookupProtectedOwner / isSubclassOf / totalConstructorParams / lookupConsParamType):类语义解析 + 接口实现检查 + 方法/继承 lookup

本 Plan 不执行 §决策 6 —— Phase 扩展触 R1 阻断时再按此预案处理。

---

## 隐藏假设 + Execute 前验证

| # | 假设 | 验证 |
|---|---|---|
| 1 | SS `let` 变量 / `function` 跨模块自动共享(全局 scope)| ✅ 已验(D113 §假设 1 已落地;eval/ident.ss 直接访问 ctVars / currentFunc / genIdent 不 import)|
| 2 | check_types 迁 L789-1005 不触 class 层全局(narrowedTypes / currentCheckerClass / checkerClassParents / funcNames / classConsMin / checkerFieldTypes / ifaceMethods / currentTypeParams)| ✅ 已 grep:上述 state 均在 checker.ss L11-52 声明,SS 全局 scope 自动可见 |
| 3 | check_stmts.ss `rejectPrimitiveNullable`(L95) `isPrimitiveNullable` 隔文件调用 | ✅ Execute 1 前已 grep `bootstrap/check_stmts.ss:95` 调 isPrimitiveNullable,函数搬 check_types.ss 后全局 scope 自动接续 |
| 4 | main.ss `import { check } from "./checker"` 保留 | ✅ check 入口留 checker.ss(§决策 2),main.ss L6 无需改 |
| 5 | 物理迁 9 函数 ~217 行 bootstrap 固定点不变 | Execute 1 后 `./build.sh bootstrap` seed → stage1 → stage2 → stage3 验证 |
| 6 | F1 baseline R1 允许 checker.ss 1299 → ~1082(降)PROGRESS 路径 | ✅ D102 §规则 2.1 R1 单调下降 PROGRESS 不阻 + record |
| 7 | check_types.ss 新增对 M/N 累计指标影响在容差 | Execute 1 后观测 linter 输出;D113 Execute 2 同类动作 M2 +259 / N2 约 +100 均在 ±0.5% 容差内 |

### 替代方案对比(Plan 强制填,Execute 部分在 VCM)

| 方案 | 收益 | 代价 | 选否 |
|---|---|---|---|
| **A(本方案):5 文件扁平拆**| P10.1 结构清晰直接达标;每文件职责单一;扁平路径对齐 check_stmts / check_suggest | 文件数 +4;check_class 紧张 | **选** |
| B:3 文件(合 scope+func / 拆 class 为 impl+decl)| 文件数 +2;check_class_impl 行数更宽松 | scope 和 func 职责不同(名绑定 vs 签名),合并违 P10.1;用户指定 5 文件方案 | 否 |
| C:R1 线性压回不拆 | 保持单文件 | ~70 轮才达 ≤ 600;D088 §第一性需求 SEMA 子模块分层永久阻塞 | 否(feedback_600_split_not_inline:禁止压不拆)|
| D:拆到 `bootstrap/check/` 子目录 | 子目录语义边界清 | check_stmts / check_suggest 现扁平,激活子目录需重排 import 路径;check 族当前仅 5 员无必要 | 否(遵循现有模式)|

---

## 路线连线

- **D088 §第一性需求 L9-13** → checker types 层(check_types.ss)物理独立 → 为 Zig SEMA"evalExpr 单函数吸收所有 kind dispatch"提供类型查询模块载体,与 D113 的 eval/interp_core.ss 对等
- **D102 §规则 R4** → checker.ss ~470 ≤ 600 → baseline 条目删除 → 14 文件清单 → 13 文件
- **D102 §最终目标 L115** "全 ≤ 600" → 本 Plan 推进 1 步(与 D113 codegen.ss R4 候补并列)
- **D113 §决策模板** → Execute 分步风险递增 + 每步机械 gate + 协调策略,本 Plan 平行复用
- **P10.1** → 5 文件每文件职责单一(types / scope / func / class / driver)且依赖单向(driver → class/func/scope/types 前向,types → class/func/scope 前向,无反向),结构清晰 gate 达标
- **D067 null safety** → Nullable helper 族独立 check_types.ss,后续 D067 Phase 3(泛型 null 约束)扩展有物理承载

---

## 下一步

**已完成**:§决策 4 全四步 Execute 1 / 2 / 3 / 4(check_types.ss 219 + check_scope.ss 52 + check_func.ss 78 + check_class.ss 511)。checker.ss 1299 → 466 ≤ 600,baseline 条目删除。

**F1 清单(checker.ss / codegen.ss 已降 ≤ 600 但 baseline 条目仍在 linter_baseline.txt 内的累计组 DRIFT 阻 record 问题独立处理)继续压**:check_stmts.ss 1083 / gen_exprs.ss / gen_class.ss / gen_stmts.ss / parser.ss 813 等逐个按类似多层分层方案拆。
