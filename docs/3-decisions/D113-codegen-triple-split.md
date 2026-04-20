# D113: codegen.ss 激进三层切分 — SEMA / IR / 驱动物理独立(T2 并行 D112)

**Status:** Plan 起草中(Execute 未启动,本文档产出即 Plan 落地)
**Depends on:**
- D088 §第一性需求 L7-13(Zig SEMA 一份 evalExpr,反射 Meta 对象 = MEMBER_ACCESS)/ §背景 Zig 的根 L65-80(编译器即解释器,类型是一等值)
- D098 §Value 共享容器(Type-as-Value 并入 ctVars/MaybeVal,Phase B 展开)
- D102 §规则 2.1 R1-R5 L109-113(F1 GATE)/ §规则 2.4 防规避 L149-155(一拆二 / 分裂伪移硬阻)/ §首次 record baseline L123 `F1:bootstrap/codegen.ss=1277`(现 `tools/linter_baseline.txt` 1267 D111 Execute 后 record)
- D108 §步骤 1 IDENT 迁出(eval/ 子目录成熟模式,11 文件 dispatcher 分切)
- D112 §决策 1-4(ongoing Execute 2/3 `comptimeTypeAliases` → `ctVars` 并入,动区:codegen.ss:84,89-99,989 + gen_decls.ss:235,506 + eval/ident.ss:38-41)
- D093 §决策 §Zig 原理 第 3 条(Type 本身是一个 Value,与 int/string 共享 Value 容器)
- CLAUDE.md §交互式单文档 / §PFV 流程 / `memory/feedback_no_workaround.md` / `memory/feedback_f1_gate_semantic.md`

**Date:** 2026-04-20

---

## 第一性需求

`bootstrap/codegen.ss` 1266 行单文件物理承载 **3 层架构职责**(D088 §反模式 "双轨制" 残留):

1. **SEMA 解释器层** — TypedValue 容器 + `interp*` 族(codegen.ss:139-681),~540 行
2. **IR 原语层** — `ir*` LLVM IR 文本构造器(codegen.ss:694-791),~100 行
3. **Codegen 驱动层** — init/reset/generateToFile/registerAllDecls/emitGlobalsAndCode + 全局状态 + Comptime 执行驱动(flush\* / preScan\*),~627 行

D088 §第一性需求 L7-13 目标 "Zig SEMA 一份 evalExpr,反射 Meta 对象 = MEMBER_ACCESS" 要求 SEMA 解释器是**独立模块**(Zig 原理 "编译器即解释器")。当前 SEMA interp\* 作为 codegen.ss 的内部章节寄生在代码生成器文件里,物理上没有独立模块身份,逻辑上默认"SEMA 是 codegen 的工具函数"—— D088 §反模式 "独立解释器 + 字符串 mixin" 的物理残留。

**否定证据**:

1. **D098 Phase B 扩展无处落地** —— Phase B 计划 `interp*` 全迁 InternPool + Value 共享容器扩展到 class instance / Meta 对象,新增代码只能继续堆进 codegen.ss,文件增量膨胀。D111 Execute 2 commit 32a8f6d 已经在 codegen.ss:314-316 加了 InternPool 调用,就是这种膨胀的预演
2. **D102 §规则 R3 ≤600 硬上限永远达不到** —— codegen.ss baseline 1267,当前 1266,R1 单调压回每轮只能压 1-10 行(D112 Execute 1 压 4 行),线性速度到 ≤600 需 ~100 轮
3. **跨模块定位 SEMA 代码 3x 成本** —— D112 §当前事实表格(L40-58)就是证据:`resolveCtTypeAlias` / `ctLookupTypeVal` / `interpNewType` / `tvStringOf` / `evalIdent ctVars` 的 line number 全在 codegen.ss 里遍布,每次改动都要在 1266 行文件里定位,review 负担持续累积

**收益链**:

```
三层物理分离(SEMA → eval/interp_core + eval/ct_driver)
  → SEMA 解释器独立模块身份就位,D088 §第一性需求 "Zig SEMA 一份 evalExpr" 物理载体可着手
  → D098 Phase B Value 共享容器扩展所有新增 interp* 落在 eval/interp_core.ss
  → IR 原语独立 gen/ir_builder.ss,和 SEMA 解耦清晰
  → codegen.ss 从 1266 → ≤ 600,R4 触发 baseline 条目删除(14 文件清单 -1)
  → F1 GATE 向 D102 §最终目标"全 ≤ 600"推进一大步
```

---

## 当前事实(2026-04-20 snapshot,commit 13f5b3e D112 Execute 1 后)

| 项 | 值 / 位置 |
|---|---|
| codegen.ss 当前行数 | `wc -l` 实测 **1266** |
| codegen.ss F1 baseline | `tools/linter_baseline.txt` `F1:bootstrap/codegen.ss=1267` |
| `bootstrap/eval/` 现状 | 11 文件 dispatcher(D108 §步骤 1 建立):array_lit/call/ident/index_access/member_access/method_call/new_expr/postfix_inc/short_circuit/template_lit/ternary |
| `bootstrap/gen/` 现状 | **空占位目录**(本 Plan 激活)|
| `bootstrap/lexer/` / `bootstrap/parse/` | 空占位(不在本 Plan 范围)|
| SS import 机制 | `main.ss` 的 `resolveImports()` 递归内联所有 `.ss`;全局 `let` 变量 + 全局 `function` 合并到单一词法 scope,跨模块自动可见 —— 拆分 = 物理搬运,不需要 export 关键字 |
| `eval/ident.ss` 案例 | 直接调 `isCt` / `ctVal` / `interpFindScopeKey` / `interpNewType` / `ctLookupTypeVal` / `genIdent` 不 import(依赖 resolveImports 全局 scope),43 行 |
| D112 动区行范围 | codegen.ss:**84**(`comptimeTypeAliases`) / **89-99**(`ctLookupTypeVal` + `resolveCtTypeAlias`) / **989**(pre-scan set)/ gen_decls.ss:235,506 / eval/ident.ss:38-41 |

### codegen.ss 分段盘点(精确行号 + 归属)

| 段 | 行号 | 函数/职责 | 行数 | 归属 |
|---|---|---|---|---|
| 顶部注释 + import | 1-8 | — | 8 | codegen.ss 保留 |
| 全局状态变量声明 | 9-88 | `irBuf` / `strConsts` / `regCount` / `regTable` / `ctVars` / `ctInvalidated` / `ctFuncNodes` / `ctScopeStack` / `ctCallCounter` / `comptimeDepth` / `labelCount` / `varTypes` / `varTypesReady` / `currentFunc` / `terminated` / `varCounter` / `varAliases` / `globalAliases` / `varAliasReady` / `breakLabel` / `continueLabel` / `enumValues` / `enumTypes` / `enumDeclNodes` / `enumReady` / `isThreadClosure` / `comptimeExprType` / `comptimeExprLiteral` / `comptimeConsts` / `pendingCtClassIds` / `comptimeTypeAliases`(D112 动区)| ~80 | codegen.ss 保留 |
| `ctLookupTypeVal` + `resolveCtTypeAlias` | 89-99 | D112 动区 | 11 | codegen.ss 保留(D112 Execute 完成前不动) |
| varAliases 族 | 34-64(穿插)| `initVarAliases` / `allocVarName` / `llVarName` / `varRef` | ~30 | codegen.ss 保留 |
| `initCodegen` / `emitIR` / `nextReg` / `nextLabel` | 113-137 | codegen 入口 + IR buffer 基础原语 | 25 | codegen.ss 保留 |
| **TypedValue 容器** | 139-283 | `ctVal` / `isCt` / `payload` / `constVal` / `reg` / `materialize` / `initTypedValue` / `allocTv` / `newTvInt` / `newTvString` / `newTvType` / `newTvBool` / `newTvNull` / `newTvArray` / `tvKindOf` / `tvIntOf` / `tvStringOf` | ~145 | **→ eval/interp_core.ss** |
| **interp\* 族** | 285-681 | `interpType` / `interpAsInt` / `interpAsStr` / `interpNewInt` / `interpNewString` / `interpNewBool` / `interpNewNull` / `interpNewType` / `interpNewArray` / `interpCompoundOp` / `interpShouldStop` / `interpCheckLoopExit` / `interpGetField` / `interpSetField` / `interpArrayPush` / `interpArraySet` / `interpArrayLen` / `interpArrayGet` / `interpNewMap` / `interpMapSet` / `interpMapGet` / `interpMapHas` / `interpMapDelete` / `interpMapGetKeys` / `interpMapGetSize` / `interpGetComptimeIR` / `interpGetComptimeSS` / `interpClearComptimeIR` / `interpClearComptimeSS` / `interpEnsureComptimeRoot` / `interpTruthy` / `interpNewDouble` / `interpFindScopeKey` / `interpNewVal` / `interpToStr` / `interpIntOp` / `interpDoubleOp` / `interpBuildTypeInfo` / `interpValEquals` / `interpCollectFields` / `isKnownClass` / `interpCtFieldsArray` / `interpFindMethod`(42 个)| ~397 | **→ eval/interp_core.ss** |
| Annotation | 683-691 | `registerAnnotation` / `collectClassAnnotations` / `emitAnnotationInits` | 9 | codegen.ss 保留 |
| **ir\* 原语** | 694-791 | `irLabel` / `irAlloca` / `irLoad` / `irStore` / `irGEP` / `irICmp` / `irBr` / `irBrCond` / `irRet` / `irRetVoid` / `irAdd` / `irSub` / `irMul` / `irCall` / `irCallVoid` / `irSext` / `irZext` / `irSelect` / `irSDiv` / `irOr` / `irTrunc` / `irPtrToInt` / `irIntToPtr` / `irLoadArrayData`(24 个)| ~98 | **→ gen/ir_builder.ss** |
| `addStringConst` | 793-826 | 字符串常量池 | 34 | codegen.ss 保留 |
| `registerFuncDeclNode` | 828-884 | 函数注册 | 57 | codegen.ss 保留 |
| **Comptime 执行驱动** | 885-1013 | `flushComptimeSS` / `flushComptimeIR` / `fullyRegisterCtClass` / `preScanCodegenCtClassesInStmts` / `flushPendingCtClasses` | ~128 | **→ eval/ct_driver.ss** |
| `registerAllDecls` / `isTopLevelDecl` | 1014-1083 | 顶层声明遍历 | 70 | codegen.ss 保留 |
| `emitGlobalsAndCode` | 1084-1134 | 全局初始化 + 主 pass | 51 | codegen.ss 保留 |
| `resetCodegen` | 1135-1201 | 状态重置 | 67 | codegen.ss 保留 |
| `ctPopScope` | 1202-1215 | comptime scope 出栈 | 14 | codegen.ss 保留 |
| `buildRuntimeCache` | 1216-1244 | 运行时缓存构建 | 29 | codegen.ss 保留 |
| `generateToFile` | 1245-1266 | codegen 入口 | 22 | codegen.ss 保留 |

**行数预算**:
- `gen/ir_builder.ss` ≈ **100 行**(24 ir\* 函数 + 模块头注释)
- `eval/interp_core.ss` ≈ **550 行**(TypedValue 145 + interp\* 397 + 模块头注释)—— 接近 R3 ≤ 600 上限,Phase B 膨胀时需再细分(参照 eval/ 11 文件模式)
- `eval/ct_driver.ss` ≈ **140 行**(Comptime 执行驱动 128 + 模块头注释)
- `codegen.ss` 剩余 ≈ **500 行**(1266 - 98 - 542 - 128 = 498,保守估 500)—— 达成 D102 §规则 R4,codegen.ss baseline 条目**删除**,F1 14 文件清单 -1

---

## 决策

### [ ] Planned §决策 1 — 三层物理分离 + 子目录归属

遵循 D108 §步骤 1 `eval/` 子目录模式平行复用 `bootstrap/gen/` 空占位目录。

| 层 | 目标文件 | 承载 | 估行 |
|---|---|---|---|
| **SEMA 解释器层** | `bootstrap/eval/interp_core.ss` | TypedValue 容器(ctVal/isCt/payload/newTv\*/tv\*Of)+ interp\* 全族(42 函数)| ~550 |
| **SEMA 驱动分文件** | `bootstrap/eval/ct_driver.ss` | Comptime 执行驱动(flushComptimeSS/flushComptimeIR/fullyRegisterCtClass/preScanCodegenCtClassesInStmts/flushPendingCtClasses)| ~140 |
| **IR 原语层** | `bootstrap/gen/ir_builder.ss` | ir\* 24 个 LLVM IR 文本构造器 | ~100 |
| **Codegen 驱动层** | `bootstrap/codegen.ss`(保留)| init/reset/generateToFile/emitGlobalsAndCode/registerAllDecls + 全局状态 + emitIR/nextReg/nextLabel/addStringConst/registerFuncDeclNode + varAliases 族 + Annotation + D112 动区(ctLookupTypeVal/resolveCtTypeAlias/comptimeTypeAliases)| **目标 ≤ 500** |

"激进三切" 语义:三个**架构层**物理分离。SEMA 层内部因行数约束分 `interp_core.ss` + `ct_driver.ss` 两文件(R3 ≤ 600 硬约束),IR 层 + 驱动层各一文件。

### [ ] Planned §决策 2 — 不拆的项(留 codegen.ss 驱动层)

| 项 | 原因 |
|---|---|
| 全局状态变量(30+ 个 `let`)| SS `let` 跨模块自动共享,留 codegen.ss 顶部是自然入口,搬走无净收益 |
| `emitIR` / `nextReg` / `nextLabel` / `addStringConst` | 紧绑 `irBuf` / `regCount` / `strConsts` 状态,和 codegen 驱动同体 |
| `initCodegen` / `resetCodegen` / `generateToFile` / `emitGlobalsAndCode` / `registerAllDecls` / `buildRuntimeCache` | codegen 入口 + 生命周期,留 codegen.ss 是按职责命名的自然归属 |
| `registerFuncDeclNode` | 函数注册和 codegen 驱动耦合 |
| varAliases 族(initVarAliases/allocVarName/llVarName/varRef)| 变量名分配和 codegen 驱动耦合 |
| Annotation(registerAnnotation/collectClassAnnotations/emitAnnotationInits)| class 注册 + codegen 驱动耦合 |
| `ctLookupTypeVal` / `resolveCtTypeAlias` / `comptimeTypeAliases` | **D112 ongoing Execute 动区**,本 Plan 零触碰(§决策 3)|
| `ctPopScope` | comptime scope 出栈,Phase B 再处理 |

### [ ] Planned §决策 3 — D112 ongoing 协调(T2 并行零冲突)

D112 §决策 1-4 动区定位:

| D112 动区 | 文件:行 | 本 Plan 触碰? |
|---|---|---|
| `comptimeTypeAliases` 声明 | codegen.ss:84 | **不**(留 codegen.ss 全局状态段) |
| `ctLookupTypeVal` 函数体 | codegen.ss:89-96 | **不**(留 codegen.ss 驱动层) |
| `resolveCtTypeAlias` 函数体 | codegen.ss:97-99 | **不**(留 codegen.ss 驱动层) |
| pre-scan set(preScanCodegenCtClassesInStmts 内)| codegen.ss:989 | ⚠ **preScanCodegenCtClassesInStmts 整体迁 eval/ct_driver.ss**(Execute 4)—— D112 §决策 1 第 1 处改到 codegen.ss:989 是**行内 .set 调用**,迁文件后行号变为 `eval/ct_driver.ss:<new-line>`,D112 Execute 需同步更新引用 |
| `gen_decls.ss:235` / `gen_decls.ss:506` | 不在本 Plan 动区 | **不** |
| `eval/ident.ss:38-41` | 不在本 Plan 动区 | **不** |

**冲突点唯一**:Execute 4(迁 Comptime 驱动到 ct_driver.ss)会把 `preScanCodegenCtClassesInStmts` 从 codegen.ss:947-998 整体搬到 `eval/ct_driver.ss`。

**协调策略(二选一)**:

- **协调 A(推荐)**:D113 Execute 4 在 D112 Execute 2/3 完成后启动。D112 Execute 2/3 合入时 `preScanCodegenCtClassesInStmts` L989 `comptimeTypeAliases.set` 已改为 `ctVars.set`,D113 Execute 4 整体搬文件时函数体已稳定,搬运后 D112 §当前事实表格 L46 的 `bootstrap/codegen.ss:989` 锚点回写为 `bootstrap/eval/ct_driver.ss:<new-line>`
- **协调 B**:D113 Execute 1-3 先做(不动 Comptime 驱动 → 不碰 codegen.ss:989),Execute 4 延后到 D112 全部完成。Execute 1-3 完成时 codegen.ss ≈ 628 行,**未达 ≤ 600 目标**,本轮 <600 目标降级为分两步(先 ≈628 等 D112,后 ≈500)

**本 Plan 选协调 A**:Execute 1-3 可立即启动(零冲突)、Execute 4 启动前查 D112 Status 是否已 Execute 完成,未完成则暂停等 D112 合入。

### [ ] Planned §决策 4 — Execute 分步(风险递增)

| Execute | 内容 | 估改动 | D112 冲突? | 风险 |
|---|---|---|---|---|
| **Execute 1** | 创建 `bootstrap/gen/ir_builder.ss`,迁 ir\* 24 函数。main.ss 加 import(参照 `import { evalExpr } from "./eval_expr"` 模式)。codegen.ss 1266 → ~1168 | ~100 行 | 零 | 低(ir\* 纯 IR 文本构造,无状态耦合;调用点在 gen_decls/gen_stmts/gen_exprs 等已存在)|
| **Execute 2** | 创建 `bootstrap/eval/interp_core.ss`,迁 TypedValue 容器(`ctVal` / `isCt` / `payload` / `constVal` / `reg` / `materialize` / `initTypedValue` / `allocTv` / `newTv*` / `tvKindOf` / `tvIntOf` / `tvStringOf`,15 函数)。codegen.ss ~1168 → ~1023 | ~145 行 | 零(TypedValue 不涉 D112 动区)| 低-中(被 interp* + evalExpr 大量调用,但函数体独立) |
| **Execute 3** | 续迁 interp\* 全族(42 函数)到 `eval/interp_core.ss`。codegen.ss ~1023 → ~626 | ~397 行 | 零 | 中(函数量大,但每个独立;grep 调用点 eval/* + gen_* 多处,需确保 resolveImports 覆盖 interp_core.ss) |
| **Execute 4** | 创建 `bootstrap/eval/ct_driver.ss`,迁 Comptime 执行驱动(`flushComptimeSS` / `flushComptimeIR` / `fullyRegisterCtClass` / `preScanCodegenCtClassesInStmts` / `flushPendingCtClasses`,5 函数)。**启动前检查 D112 Status = Accepted / Execute 2-3 Done**。codegen.ss ~626 → ~498 | ~128 行 | ⚠ **preScanCodegenCtClassesInStmts 行号变动**(协调 A)| 中-高(和 D112 时序协调,Execute 4 启动前必须验 D112 动区已稳定) |

每步后机械 gate:
1. `./build.sh bootstrap` 固定点(seed → stage1 → stage2 → stage3,stage2 == stage3)
2. `bin/ss test tests/` 全绿
3. `bin/ss run tools/reflection_health_linter.ss` 无 GATE BLOCKED(D097 14 指标 + D102 F1 GATE)
4. F1 baseline 处理:
   - Execute 1 后:新增 `F1:bootstrap/gen/ir_builder.ss=~100`(R3 ≤ 600 自动通过),codegen.ss baseline 1267 → ~1168(R1 PROGRESS record)
   - Execute 2 后:新增 `F1:bootstrap/eval/interp_core.ss=~245`(R3 ≤ 600 通过),codegen.ss baseline ~1168 → ~1023
   - Execute 3 后:interp_core.ss baseline ~245 → ~550(R1 同文件 REGRESSION 阻!)→ **Execute 2+3 合并为单 commit record**(单次新增 interp_core.ss baseline = 550,不是先 245 再 550)
   - Execute 4 后:新增 `F1:bootstrap/eval/ct_driver.ss=~140`,codegen.ss baseline ~626 → ~498(**R4 触发**: ≤ 600 → baseline 条目**删除**)

### [ ] Planned §决策 5 — F1 GATE baseline 处理细则

D102 §规则 R3 / R4 对本 Plan 的具体应用:

1. **R3 新文件硬约束**:新建 `gen/ir_builder.ss` / `eval/interp_core.ss` / `eval/ct_driver.ss` 创建时 cur 不得 > 600 —— 三者预估 100 / 550 / 140,全部过 R3。**interp_core.ss 最紧**:550 / 600 余量 50 行,Phase B 扩展时必须同步细分(见 §后续 eval/ 细分预案)
2. **R1 同文件单调**:codegen.ss 在每个 Execute 内单调下降(1266 → 1168 → 1023 → 626 → 498),每步 record 新 baseline
3. **R4 baseline 删除**:Execute 4 完成 codegen.ss ≈ 498 ≤ 600 → F1 baseline 条目 `F1:bootstrap/codegen.ss=1267` **从 `tools/linter_baseline.txt` 删除**,14 文件清单 → 13 文件
4. **D102 §最终目标 L115 "全 ≤ 600" 进度**: 本 Plan 完成后 14 → 13;D113 单轮贡献 1 个文件达标。
5. **Execute 2+3 合并**:§决策 4 备注已说明,interp_core.ss 单次新增 record baseline = 550,避免 R1 自阻

### [ ] Planned §决策 6 — eval/ 细分后续预案(Phase B 膨胀时启用)

interp_core.ss 550 行 / 600 硬上限余量 50 行。D098 Phase B 扩展 interp\* 到 class instance / Meta 对象时可能触发 R1 阻断。预案:

参照 D108 §步骤 1 `eval/` 11 文件模式,把 interp_core.ss 再切 2-3 文件:

- `eval/interp_value.ss` — TypedValue 容器 + newTv\* + tv\*Of + interpNewXxx 标量构造(~200 行)
- `eval/interp_op.ss` — interpIntOp / interpDoubleOp / interpCompoundOp / interpTruthy / interpToStr / interpValEquals 运算(~100 行)
- `eval/interp_obj.ss` — interpGetField / interpSetField / interpArray\* / interpMap\* / interpBuildTypeInfo / interpCollectFields / interpFindMethod 对象容器(~250 行)

本 Plan 不执行 §决策 6 —— Phase B 触发 R1 阻断时再按此预案处理。

---

## 隐藏假设 + Execute 前验证

| # | 假设 | 验证 |
|---|---|---|
| 1 | SS `let` 变量跨模块自动共享 | ✅ 已验(eval/ident.ss 直接访问 ctVars/currentFunc/comptimeDepth 无 import) |
| 2 | SS 同一函数可被多文件 import | Execute 1 前最小样例:gen_decls.ss + gen_stmts.ss 同时 `import { irAlloca } from "./gen/ir_builder"`,bootstrap 固定点通过即确认 |
| 3 | interp\* 互相调用闭合在新文件内 | Execute 3 前 grep `interp[A-Z]\w*\(` 交叉调用,确认 interp_core.ss 内闭合(无 codegen.ss 反向依赖) |
| 4 | Comptime 驱动不反向依赖 interp\* 核心 | Execute 4 前验证 flushComptimeSS/preScanCodegenCtClassesInStmts 调用链仅前向到 interp_core.ss(已 Execute 2+3) |
| 5 | D098 Phase B 未扩大 interp\* 动区 | D098 Status 查询:目前 Phase A Execute(D100-D112 序列),Phase B Planned 未启动(2026-04-20 snapshot) |
| 6 | D112 §决策 1-4 行号变动可跟踪 | Execute 4 前 D112 Status 必须 = Accepted / Execute 2-3 Done,`comptimeTypeAliases` 已被 ctVars 吸收后再搬文件 |
| 7 | `main.ss` import 列表扩充不超 F1(main.ss baseline 630) | Execute 1-4 每步 + 1 import 行,共 +3 行 import(interp_core / ct_driver / ir_builder 的 dispatcher 声明),main.ss 633 → R1 REGRESSION 阻!→ **方案**: 把 import 加在 `eval_expr.ss`(现 129 行,F1 无 baseline,R2 ≤600 极充裕)或 `codegen.ss`(本 Plan 已削到 498,加 3 行仍 501 ≤ 600 勉强过)。**推荐 codegen.ss**,因新文件是 codegen 的物理拆分,import 位置和语义对齐 |

---

## 路线连线

- **D088 §第一性需求 L7-13** → SEMA 解释器物理独立(eval/interp_core.ss + eval/ct_driver.ss)→ 为 "Zig SEMA 一份 evalExpr,反射 Meta 对象 = MEMBER_ACCESS" 提供模块载体
- **D098 Phase B**(Planned)→ interp\* 全迁 InternPool + Value 共享容器扩展 → 本 Plan 提供 `eval/interp_core.ss` 承载,Phase B 新增代码直接落在该文件(不再膨胀 codegen.ss)
- **D102 §规则 R4** → codegen.ss ≈ 498 ≤ 600 → baseline 条目删除 → 14 文件清单 → 13 文件
- **D102 §最终目标 L115** "全 ≤ 600" → 本 Plan 推进 1 步(14 → 13)
- **D108 §步骤 1 eval/ 子目录模式** → 本 Plan 平行复用(eval/ 扩 interp_core + ct_driver;gen/ 空目录激活 ir_builder)
- **D112 §决策 1-4**(ongoing)→ 零动区重叠(T2 并行可行),Execute 4 协调 A 锁时序
- **D093 §决策 §Zig 原理 第 3 条** "Type 本身是一个 Value,与 int/string 共享 Value 容器" → TypedValue 容器迁 eval/interp_core.ss 后,Value 语义边界从文件位置上可见

---

## 下一步

**Execute 1**:创建 `bootstrap/gen/ir_builder.ss`,迁 ir\* 24 函数(codegen.ss:694-791),codegen.ss 顶部加 `import { irLabel, irAlloca, irLoad, irStore, irGEP, irICmp, irBr, irBrCond, irRet, irRetVoid, irAdd, irSub, irMul, irCall, irCallVoid, irSext, irZext, irSelect, irSDiv, irOr, irTrunc, irPtrToInt, irIntToPtr, irLoadArrayData } from "./gen/ir_builder"`,`./build.sh bootstrap` 固定点 + `bin/ss test tests/` 全绿 + `tools/reflection_health_linter.ss` 无 GATE BLOCKED + F1 record(codegen.ss baseline 1267 → ~1168,gen/ir_builder.ss 新 baseline ≈ 100)。
