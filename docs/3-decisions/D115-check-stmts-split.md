# D115: check_stmts.ss 按职责细分 6 文件(return / narrow / named_args / thread / exprs / stmts driver)

**Status:** Plan Done / Execute 1 [x] Done at bootstrap/checker/check_return.ss:5 / Execute 2 [ ] / Execute 3 [ ] / Execute 4 [ ] / Execute 5 [ ]

**Depends on:**
- D088 §第一性需求 L9-13(Zig 路线 SEMA 目标 evalExpr 吸收 kind dispatch)/ §正模式 L387(渐进拆分 SEMA 模块)
- D102 §规则 2.1 R1-R5 L109-113(F1 GATE)/ §规则 2.2 `F1:bootstrap/checker/check_stmts.ss=1083`(已 grep 对照 `tools/linter_baseline.txt:26`)/ §规则 2.4 防规避 L149-155(拆不压硬阻)/ §最终目标 L115"全 ≤ 600"
- D114-checker-split(Execute 分步模板 + checker/ 子目录扁平风格立住)
- D067 null safety Phase 2 smart narrowing(extractNullCheckVar / restoreNarrowing 的来源)
- D007 return path analysis(blockAlwaysReturns / stmtAlwaysReturns 的来源)
- D082 Phase 3 concurrency closure capture(checkThreadClosureCaptures 族的来源)
- D084 object literal + named constructor args(checkNamedConstructorArgs 的来源)
- P10.1 拆分判据结构清晰 = 单一职责 + 单向依赖,≥3 职责类别即不清晰
- CLAUDE.md §交互式单文档 / §PFV 流程 / `memory/feedback_no_workaround.md` / `memory/feedback_600_split_not_inline.md` / `memory/feedback_structure_not_linecount.md` / `memory/feedback_subdir_split_style.md` / `memory/feedback_ultrathink_gate.md`

**Date:** 2026-04-20

---

## 第一性需求

`bootstrap/checker/check_stmts.ss` 1083 行单文件物理承载 **6 层职责**(P10.1 反模式"≥3 职责类别即不清晰"的 2× 超标):

1. **stmt dispatch 层** — `checkStmt`(L130-567,438 行)19 个 kind case 主分发 + `checkBlock` / `checkStmtList` / `checkParamList`(L569-602,32 行)块/列表遍历
2. **expr dispatch 层** — `checkExpr`(L606-923,318 行)20+ 个 kind case 主分发 + `checkArgList`(L925-940,16 行)
3. **return path 分析层** — `blockAlwaysReturns` + `stmtAlwaysReturns`(L34-93,59 行),D007 所有路径必返回校验
4. **null narrow 辅助层** — `rejectPrimitiveNullable` + `extractNullCheckVar` + `restoreNarrowing`(L95-126,27 行),D067 Phase 2 smart narrowing
5. **named 构造器校验层** — `checkNamedConstructorArgs`(L943-1020,78 行),D084 字段校验 + 重复检测 + 类型检查
6. **Thread 闭包捕获层** — `checkThreadClosureCaptures` + `checkLetCapture` + `checkThreadCapturesRec`(L1024-1083,58 行),D082 Phase 3 let/const 捕获规则

另有 `stringLitArrayCsv`(L12-30,19 行)作为 checker/codegen 共享工具。

P10.1 §"单一文件职责单一"原则:"出现 ≥3 职责类别即不清晰",check_stmts.ss 6 职责层在同一文件意味着每次 review / 改动必须跨 6 个心智模型,是 D114 §第一性需求"checker.ss 5 职责层跨心智扫"的同构症状。

**否定证据**:

1. **F1 R4 ≤600 目标不可达** —— check_stmts.ss baseline 1083,R1 单调压回每轮最多 -10 行,线性速度到 ≤600 需 ~50 轮。D102 §最终目标"全 ≤ 600"11 文件清单里 check_stmts.ss 条目永不消失,R4 永远不触发
2. **反射根因 gate 改 checker 代价累积** —— D097 14 指标 + D102 F1 GATE 每次改 checker 都在 1083 行文件定位 6 职责层,即便改 return path 一个规则也要与 checkStmt 438 行 + checkExpr 318 行同文件滚动审查
3. **D088 §第一性需求 Zig SEMA 分发器分层阻塞** —— SEMA 未来"evalExpr 单函数吸收所有 kind dispatch"需要 stmt/expr 分发器物理独立,当前 checkStmt + checkExpr 混在单文件里无分层载体。D114 已让 checker.ss 分出 types/scope/func/class 四层,本 Plan 的 stmt/expr 分层是这条路线的同构延伸

**收益链**:

```
6 层物理分离(return / narrow / named_args / thread / exprs / stmts driver)
  → 每文件职责单一,P10.1 结构清晰 gate 达标
  → check_stmts.ss 1083 → ~508,R4 触发 baseline 条目删除(11 文件清单 -1)
  → F1 GATE 向 D102 §最终目标"全 ≤ 600"推进一大步
  → SEMA stmt/expr 分发器物理独立,对齐 D088 SEMA 子模块分层
  → 后续 check_stmts.ss 改动只触 stmt dispatch ≤510 行,review 成本减半
```

---

## 当前事实(2026-04-20 snapshot,commit 3a92c42 D114 Execute 4 后)

| 项 | 值 / 位置 |
|---|---|
| check_stmts.ss 当前行数 | `wc -l` 实测 **1083** |
| check_stmts.ss F1 baseline | `tools/linter_baseline.txt:26` `F1:bootstrap/checker/check_stmts.ss=1083`(11 条 baseline 中第 2 大,仅次于 `gen/codegen.ss=1166`)|
| checker/ 子目录现状 | D114 Execute 1-4 全 `[x] Done`:`checker.ss=466` + `check_types.ss=219` + `check_scope.ss=52` + `check_func.ss=78` + `check_class.ss=511` + **`check_stmts.ss=1083`(本 Plan 目标)** + `check_suggest.ss=83` |
| SS import 惯例 | checker.ss 作入口文件显式 import 其他 check_*.ss 子文件;子文件无 import 头,靠 `resolveImports()` 递归内联 + 全局 scope(`check_types.ss` L1-5 / `check_class.ss` L1-5 / `check_func.ss` L1-4 均无 import)|
| check_stmts.ss 现 import | `import { editDistance, collectVisibleNames, findSuggestion } from "./check_suggest"`(L4)—— 拆分后 checkStmt 继续用 findSuggestion(ASSIGN case L297 等),import 保留 |
| F1 baseline 主清单 | 11 条:`gen/codegen.ss=1166` / `parse/parser.ss=813` / `main.ss=628` / `gen/gen_calls.ss=695` / `gen/gen_types.ss=738` / `parse/parse_stmts.ss=617` / `gen/methods/gen_methods.ss=709` / `gen/gen_decls.ss=691` / `gen/gen_runtime.ss=621` / **`checker/check_stmts.ss=1083`** / `gen/ir_builder.ss=101`(≤600 候补删) |

### check_stmts.ss 分段盘点(精确行号 + 归属表)

| 段 | 行号 | 函数/职责 | 行数 | 归属 |
|---|---|---|---|---|
| 顶部注释 + import | 1-10 | 2 行注释 + 1 行 import + 3 行空行 + 5 行 stringLitArrayCsv 注释 | ~10 | **check_stmts.ss 保留**(import 继续服务 checkStmt) |
| `stringLitArrayCsv` | 12-30 | checker/codegen 共享工具,检查 ARRAY_LIT 元素是否全 STRING_LIT 并返回 csv | 19 | **check_stmts.ss 保留**(checker FOR_IN case L488 + codegen `gen/stmts/stmts_loop_forin.ss:220` 共用,跨族工具留 driver)|
| **return path 族** | 34-93 | `blockAlwaysReturns` / `stmtAlwaysReturns` | 59 | **→ check_return.ss** |
| **null narrow 族** | 95-126 | `rejectPrimitiveNullable` / `extractNullCheckVar` / `restoreNarrowing` | 27 | **→ check_narrow.ss** |
| `checkStmt` 主分发 | 130-567 | 19 个 stmt kind case:FUNC_DECL / CLASS_DECL / VAR_DECL / DESTRUCTURE_ARRAY / DESTRUCTURE_OBJECT / ASSIGN / MEMBER_ASSIGN / INDEX_ASSIGN / EXPR_STMT / RETURN / IF / FOR / FOR_IN/OF / WHILE / DO_WHILE / SWITCH / SWITCH_CASE / POSTFIX_INC/DEC / TRY / THROW / COMPTIME_BLOCK | 438 | **check_stmts.ss 保留**(stmt 分发器本体)|
| `checkBlock` / `checkStmtList` / `checkParamList` | 569-602 | 块/语句列表/参数列表遍历,被 checkStmt 和 checker.ss 的 `check` 入口共用 | 32 | **check_stmts.ss 保留**(stmt 遍历原语)|
| `checkExpr` 主分发 | 606-923 | 20+ 个 expr kind case:INT/DOUBLE/STRING_LIT / TRUE/FALSE/NULL / THIS / SUPER / IDENT / BINARY(含 Instanceof/As)/ UNARY / CALL / METHOD_CALL / MEMBER_ACCESS / INDEX_ACCESS / NEW_EXPR / ARRAY_LIT / OBJ_LITERAL / TERNARY / GROUPING / TEMPLATE_LIT / POSTFIX_INC/DEC | 318 | **→ check_exprs.ss**(最大一步)|
| `checkArgList` | 925-940 | 参数列表遍历(含 NAMED_ARG / SPREAD_ELEM 特殊路径),被 checkExpr CALL/METHOD_CALL/NEW_EXPR/ARRAY_LIT case 共用 | 16 | **→ check_exprs.ss**(expr 遍历原语)|
| **named 构造器族** | 943-1020 | `checkNamedConstructorArgs`(78 行):字段校验 + 重复检测 + 类型检查 + 父类字段爬链 | 78 | **→ check_named_args.ss** |
| **Thread 闭包族** | 1024-1083 | `checkThreadClosureCaptures` / `checkLetCapture` / `checkThreadCapturesRec`(入口 + let 检测 + 递归遍历)| 58 | **→ check_thread.ss** |

### 行数预算(每文件 ≤600 余量 + 头注释 8-12 行增量)

| 文件 | 函数 | 函数行 | 估文件行 | ≤600 余量 |
|---|---|---|---|---|
| `bootstrap/checker/check_return.ss` | blockAlwaysReturns + stmtAlwaysReturns | 59 | **~68**(+6 行头注释 + 3 行空行)| 532 |
| `bootstrap/checker/check_narrow.ss` | rejectPrimitiveNullable + extractNullCheckVar + restoreNarrowing | 27 | **~38**(+8 行头注释 + 3 行空行)| 562 |
| `bootstrap/checker/check_named_args.ss` | checkNamedConstructorArgs | 78 | **~88**(+8 行头注释 + 2 行空行)| 512 |
| `bootstrap/checker/check_thread.ss` | checkThreadClosureCaptures + checkLetCapture + checkThreadCapturesRec | 58 | **~70**(+10 行头注释 + 2 行空行)| 530 |
| `bootstrap/checker/check_exprs.ss` | checkExpr + checkArgList | 334 | **~350**(+12 行头注释 + section 标记 4 行)| 250 |
| `bootstrap/checker/check_stmts.ss` 剩余 | stringLitArrayCsv + checkStmt + checkBlock + checkStmtList + checkParamList | 489 | **~510**(保留现 import 4 行 + 头注释 2 行 + section 标记 6 行 + 空行 9 行)| 90 |

**check_stmts.ss 余量最紧 ~90 行**:Phase 扩展(D067 Phase 3 泛型 null 约束 / D068 私有/受保护规则细化 / D071 抽象方法新规则)可能把 checkStmt 逼近 600,触发 R1 阻断时按 §决策 6 细分预案切 `check_stmts_decl.ss`(FUNC_DECL + CLASS_DECL + VAR_DECL 声明类 case 合流)+ `check_stmts_flow.ss`(IF + FOR + WHILE + SWITCH + TRY 控制流类 case 合流)。

---

## 决策

### §决策 1 — 6 文件物理分层 + checker/ 子目录扁平

遵循 D114 立住的 checker/ 子目录扁平模式(非 `bootstrap/checker/stmts/` 二级子目录):check 族成员 7→12 仍在子目录可控范围,二级子目录反而制造 import 路径额外复杂度。

| 层 | 目标文件 | 承载 | 估行 |
|---|---|---|---|
| **return** | `bootstrap/checker/check_return.ss` | return path 分析:blockAlwaysReturns + stmtAlwaysReturns(D007)| ~68 |
| **narrow** | `bootstrap/checker/check_narrow.ss` | null narrow 辅助:rejectPrimitiveNullable + extractNullCheckVar + restoreNarrowing(D067 Phase 2)| ~38 |
| **named_args** | `bootstrap/checker/check_named_args.ss` | named 构造器参数校验:checkNamedConstructorArgs(D084)| ~88 |
| **thread** | `bootstrap/checker/check_thread.ss` | Thread 闭包捕获验证:checkThreadClosureCaptures + checkLetCapture + checkThreadCapturesRec(D082 Phase 3)| ~70 |
| **exprs** | `bootstrap/checker/check_exprs.ss` | expr 主分发 + 参数列表遍历:checkExpr + checkArgList | ~350 |
| **stmts driver** | `bootstrap/checker/check_stmts.ss`(保留)| stringLitArrayCsv 共享工具 + checkStmt 主分发 + checkBlock + checkStmtList + checkParamList + import | **目标 ≤510** |

**"6 层"语义**:stmt 分发 / expr 分发 / return 路径 / null narrow / named 构造器 / Thread 闭包 六个**架构层**物理分离,每层映射一个 `.ss` 文件。check_exprs.ss 若后续膨胀触 R1 时按 §决策 6 二次细分。

### §决策 2 — 不拆的项(留 check_stmts.ss 驱动层)

| 项 | 原因 |
|---|---|
| `stringLitArrayCsv`(L12-30 19 行)| checker FOR_IN/OF case(L488) + codegen `gen/stmts/stmts_loop_forin.ss:220` 共用工具。放 check_stmts.ss 是自然归属,SS 全局 scope 让 codegen 照常可见,迁走无净收益 |
| `checkStmt`(438 行)| stmt 分发器本体,19 kind case,是 check_stmts.ss 文件名语义的核心。留原文件 = stmts driver 层 |
| `checkBlock` / `checkStmtList` / `checkParamList`(32 行)| stmt 遍历原语,被 checkStmt 和 checker.ss 的 `check` 入口(通过 `import { checkStmtList } from "./check_stmts"`)共用。留原文件保持 checker.ss L7 import 路径不变 |
| 现有 import `"./check_suggest"`(L4)| checkStmt ASSIGN / POSTFIX_INC case 用 findSuggestion,editDistance / collectVisibleNames 虽 checkStmt 不直接用但 D114 模式下子文件无 import 头,驱动层集中 import 是惯例 |

### §决策 3 — 函数族归属裁决(细粒度)

**return vs stmt 边界**:`blockAlwaysReturns` / `stmtAlwaysReturns` 只做**节点形状判定**(纯 AST 遍历 + kind 判断),不碰 checker state(narrowedTypes / currentCheckerClass / funcNames 等),是 checkStmt FUNC_DECL case(L165)+ stmtAlwaysReturns 内部 IF case(L61)的**被调用工具**,纯函数 → **归 return**。

**narrow vs stmt 边界**:`extractNullCheckVar` / `restoreNarrowing` / `rejectPrimitiveNullable` 都只是 narrowedTypes 辅助 + nullable 语法检测的**叶子函数**,被 checkStmt IF case(L422, L440)+ FUNC_DECL / VAR_DECL(L133, L215)调用 → **归 narrow**(三个函数都是 checker 读写 state 的最小单元,逻辑独立成组)。

**named_args vs expr 边界**:`checkNamedConstructorArgs` 是 checkExpr NEW_EXPR case(L853)的**单一调用点**,内部循环 + Map 去重 + 父类字段爬链,是一个**完整子任务**。迁出后 checkExpr NEW_EXPR case 仍保留调用 → **归 named_args**。

**thread vs expr 边界**:`checkThreadClosureCaptures` 是 checkExpr METHOD_CALL case(L771,Thread.start 识别)的**单一调用点**,内部三函数递归(入口 + let 检测 + 递归遍历),是 D082 Phase 3 的完整子任务 → **归 thread**。

**exprs vs stmts 边界**:checkExpr 调 checkExpr(递归)/ checkNamedConstructorArgs / checkThreadClosureCaptures / checkArgList / checkerInferType / inferCheckerClass / lookupPrivateOwner 等 → 纯 expr 语义;checkStmt 调 checkExpr(L213 等)+ checkStmtList(递归 block)+ blockAlwaysReturns(L165)+ extractNullCheckVar / restoreNarrowing(L422 等)+ rejectPrimitiveNullable(L133 等)→ 纯 stmt 语义。**stmt → expr 单向调用**(已验,见 §假设 2),不产生循环依赖。

**裁决结果**:

- **check_return.ss**:blockAlwaysReturns / stmtAlwaysReturns(2 函数,L34-93)
- **check_narrow.ss**:rejectPrimitiveNullable / extractNullCheckVar / restoreNarrowing(3 函数,L95-126)
- **check_named_args.ss**:checkNamedConstructorArgs(1 函数,L943-1020)
- **check_thread.ss**:checkThreadClosureCaptures / checkLetCapture / checkThreadCapturesRec(3 函数,L1024-1083)
- **check_exprs.ss**:checkExpr / checkArgList(2 函数,L606-940)
- **check_stmts.ss**:stringLitArrayCsv / checkStmt / checkBlock / checkStmtList / checkParamList(5 函数保留)

### §决策 4 — Execute 分步(风险递增)

| Execute | 内容 | 估改动 | 风险 |
|---|---|---|---|
| **Execute 1** | 创建 `bootstrap/checker/check_return.ss`(~68 行 2 函数:blockAlwaysReturns + stmtAlwaysReturns)。check_stmts.ss 删 L34-93,1083 → ~1024(R1 单调 -59 PROGRESS)。return path 族对 narrow / named_args / thread / stmts / exprs 是**单向消费**(只被 checkStmt 调,无反向依赖),最低风险。checker.ss L7 后补 `import { blockAlwaysReturns, stmtAlwaysReturns } from "./check_return"` | ~60 行迁移 | 低(纯函数,state 无访问,全局 scope 零配置接续)|
| **Execute 2** | 创建 `bootstrap/checker/check_narrow.ss`(~38 行 3 函数)。check_stmts.ss 删 L95-126,~1024 → ~997(R1 -27)| ~27 行迁移 | 低(3 纯辅助,state 读写 narrowedTypes / stripNullable,全局 scope 自动接续)|
| **Execute 3** | 创建 `bootstrap/checker/check_named_args.ss`(~88 行 1 函数)。check_stmts.ss 删 L943-1020,~997 → ~919(R1 -78)| ~78 行迁移 | 低(单函数,state 读 checkerDeferredAliases / checkerClassFields / checkerClassParents / checkerFieldTypes / checkerGenericClasses,全部全局 scope)|
| **Execute 4** | 创建 `bootstrap/checker/check_thread.ss`(~70 行 3 函数)。check_stmts.ss 删 L1024-1083,~919 → ~861(R1 -58)| ~58 行迁移 | 低(三函数自成递归闭环,state 读 lookupVar / isVarConst,全局 scope 自动接续)|
| **Execute 5** | 创建 `bootstrap/checker/check_exprs.ss`(~350 行 2 函数:checkExpr + checkArgList)。check_stmts.ss 删 L606-940(实际迁时注意 section 标记 L604 `// ── Expression checking ───` 随 checkExpr 一同迁),~861 → ~510(R1 -334,**R4 达成**:≤600 → baseline 条目 `F1:bootstrap/checker/check_stmts.ss=1083` 从 `tools/linter_baseline.txt` 删除)| ~340 行迁移 | 中(最大改动,涉 20+ kind case;依赖 checkStmt → checkExpr 单向调用已 §假设 2 验,stringLitArrayCsv 留原文件,checkerError / nGet* / findSuggestion 通过全局 scope 保持接续)|

**每步后机械 gate**:

1. `./build.sh bootstrap` 固定点(seed → stage1 → stage2 → stage3,stage2 == stage3)
2. `bin/ss test tests/` 全绿
3. `bin/ss run tools/reflection_health_linter.ss` 无 GATE BLOCKED(D097 14 指标 + D102 F1 GATE)
4. F1 baseline 处理:
   - Execute 1 后:新增 `F1:bootstrap/checker/check_return.ss=~68`(R3 ≤600 通过,直接入 baseline),check_stmts.ss baseline 1083 → ~1024(R1 PROGRESS record)
   - Execute 2 后:新增 `F1:bootstrap/checker/check_narrow.ss=~38`(R3 通过),check_stmts.ss baseline ~1024 → ~997
   - Execute 3 后:新增 `F1:bootstrap/checker/check_named_args.ss=~88`(R3 通过),check_stmts.ss baseline ~997 → ~919
   - Execute 4 后:新增 `F1:bootstrap/checker/check_thread.ss=~70`(R3 通过),check_stmts.ss baseline ~919 → ~861
   - Execute 5 后:新增 `F1:bootstrap/checker/check_exprs.ss=~350`(R3 通过),check_stmts.ss baseline ~861 → ~510(**R4 触发**:≤600 → baseline 条目**删除**)

### §决策 5 — F1 GATE baseline 处理细则

D102 §规则 R3 / R4 对本 Plan 的具体应用:

1. **R3 新文件硬约束**:check_return(~68)/ check_narrow(~38)/ check_named_args(~88)/ check_thread(~70)/ check_exprs(~350),五者全 ≤600 过 R3
2. **R1 同文件单调**:check_stmts.ss 每步单调下降(1083 → ~1024 → ~997 → ~919 → ~861 → ~510),每步 record 新 baseline
3. **R4 baseline 删除**:Execute 5 完成 check_stmts.ss ~510 ≤600 → F1 baseline 条目 `F1:bootstrap/checker/check_stmts.ss=1083` **从 `tools/linter_baseline.txt` 删除**,11 文件清单 → 10 文件
4. **D102 §最终目标 L115"全 ≤600"进度**:本 Plan 完成后 11 → 10(与 D114 已完成的 checker.ss 1299 → 466 删除并列,两者合入主清单 9)
5. **check_exprs 余量 250 行安全**:2 函数 ~350 行,未来 expr kind 扩展(D067 Phase 3 / D082 Phase 4 / D093 SEMA single-dispatch)有充足空间;触 R1 时才激活 §决策 6

### §决策 6 — check_exprs.ss / check_stmts.ss 细分预案(R1 阻断时启用)

若 check_exprs.ss ~350 行后续膨胀(expr kind 扩展 / 单 case 深化),触发 R1 阻断时按结构拆:

- **check_exprs_lit.ss** — 字面量 + IDENT + THIS/SUPER case(L609-635)+ TERNARY / GROUPING / TEMPLATE_LIT(L890-914)~60 行
- **check_exprs_call.ss** — CALL / METHOD_CALL / NEW_EXPR(L668-881)~215 行
- **check_exprs_access.ss** — MEMBER_ACCESS / INDEX_ACCESS(L778-837)~60 行
- **check_exprs.ss** 保留 `checkExpr` 分发壳 + BINARY / UNARY / ARRAY_LIT / OBJ_LITERAL + checkArgList ~100 行

若 check_stmts.ss ~510 行后续膨胀,按控制流 vs 声明类拆:

- **check_stmts_decl.ss** — FUNC_DECL + CLASS_DECL + VAR_DECL + DESTRUCTURE_ARRAY/OBJECT case 合流 ~170 行
- **check_stmts_flow.ss** — IF + FOR + FOR_IN/OF + WHILE + DO_WHILE + SWITCH + TRY case 合流 ~180 行
- **check_stmts.ss** 保留 `checkStmt` 分发壳 + ASSIGN / MEMBER_ASSIGN / INDEX_ASSIGN / EXPR_STMT / RETURN / THROW / COMPTIME_BLOCK + checkBlock / checkStmtList / checkParamList + stringLitArrayCsv ~150 行

本 Plan 不执行 §决策 6 —— Phase 扩展触 R1 阻断时再按此预案处理。

---

## 隐藏假设 + Execute 前验证

| # | 假设 | 验证 |
|---|---|---|
| 1 | SS `let` / `function` 跨模块自动共享(全局 scope),check_types.ss / check_class.ss / check_func.ss 已落地无 import 头 | ✅ 已 grep 验(`check_types.ss` L1-5 / `check_class.ss` L1-5 / `check_func.ss` L1-4 均无 import,只有头注释)|
| 2 | checkStmt → checkExpr 单向调用,checkExpr 不回调 checkStmt | ✅ 已 grep 验:check_stmts.ss 中 `checkStmt\|checkExpr` 调用位置扫描 —— checkStmt 调 checkExpr 18 处(L213/236/253/303/322/323/385/386/403/408/420/469/477/502/512/516/527/559),checkExpr 调 checkExpr 递归 16 处,**无 checkExpr → checkStmt**;checkStmt 调 checkStmt 3 处(L468/470/583 via checkStmtList 递归)|
| 3 | stringLitArrayCsv 跨 checker/codegen 共用,留 check_stmts.ss 不影响 codegen | ✅ 已 grep 验:`bootstrap/gen/stmts/stmts_loop_forin.ss:220` 调 stringLitArrayCsv,SS resolveImports 通过 checker.ss L7 `import { checkStmtList } from "./check_stmts"` 间接拉入 check_stmts.ss,stringLitArrayCsv 作为全局 function 对 codegen 自动可见 |
| 4 | checker.ss 现 import 块(L5-11)迁移后需补 5 条 import | ✅ Execute 1-5 每步在 checker.ss L7 附近补一条对应 import(显式声明 D114 风格),保持 resolveImports 递归内联路径完整 |
| 5 | check_stmts.ss L4 `import { editDistance, collectVisibleNames, findSuggestion } from "./check_suggest"` 拆分后保留 | ✅ checkStmt 仍用 findSuggestion(ASSIGN L297 / POSTFIX_INC L919 等)。check_exprs.ss 新文件无 import 头依赖全局 scope —— findSuggestion 通过 check_stmts.ss L4 的 import(resolveImports 递归内联)全局可见 |
| 6 | 5 个新文件无 import 头仅靠全局 scope,checker.ss / check_stmts.ss 的 import 块覆盖依赖 | ✅ D114 已立住的模式(check_types / check_scope / check_func / check_class 四子文件均无 import 头)|
| 7 | Execute 1-5 迁移总 ~560 行,bootstrap 固定点每步不变 | 每步后 `./build.sh bootstrap` seed → stage1 → stage2 → stage3 验证 |
| 8 | F1 baseline R1 允许 check_stmts.ss 1083 → ~510 单调降路径 | ✅ D102 §规则 2.1 R1 单调下降 PROGRESS 不阻 + record |
| 9 | 新建 5 文件对 M/N 累计指标影响在容差 | Execute 1 后观测 linter 输出;D114 Execute 1-4 同类动作 M2 / N2 均在 ±0.5% 容差内 |
| 10 | checker.ss `check` 入口(主 pass 遍历)通过全局 scope 调 checkStmt/checkExpr 不受影响 | ✅ checker.ss L7 现 `import { checkStmtList } from "./check_stmts"` 保留,checkStmt 留 check_stmts.ss 天然可见;checkExpr 迁 check_exprs.ss 后需 checker.ss 补 `import { checkExpr } from "./check_exprs"`(若 checker.ss 有直接调用)—— 事实上 checker.ss 只调 checkStmtList,checkExpr 调用全在 check_stmts.ss / check_exprs.ss 内,checker.ss 不需补 import 引用 checkExpr(但仍建议加 import 指向 check_exprs 确保 resolveImports 递归包含新文件)|

---

## 替代方案对比(Plan 型 VCM ④ 边界替换)

| 方案 | 收益 | 代价 | 选否 |
|---|---|---|---|
| **A:6 文件扁平拆(本方案)** | P10.1 结构清晰直接达标;每文件职责单一(return / narrow / named_args / thread / exprs / stmts);对齐 D114 checker/ 子目录扁平风格;5 个子族均对应清晰 D 决策来源(D007/D067/D082/D084) | 文件数 +5(checker/ 12 子成员);check_stmts.ss 余量 ~90 行紧张 | **选** |
| B:3 文件(合 return+narrow 为 `check_analysis.ss` / 合 named_args+thread 为 `check_call_semantics.ss` / 保留 exprs) | 文件数 +3;合并文件余量更宽松 | return path 和 null narrow 是两个独立 D 决策(D007 vs D067),合并违 P10.1 单一职责;named_args 和 thread 职责不同(构造器校验 vs 闭包捕获),合并同样违反 | 否 |
| C:2 文件拆(`check_exprs.ss` 独立,其余 5 族留 check_stmts.ss) | 文件数 +1 最小;check_stmts.ss 跌到 ~750 | check_stmts.ss 仍 > 600 不过 R3,F1 baseline 条目仍挂清单,R4 不触发,本 Plan 核心目标(条目删除)失败 | 否 |
| D:仅 R1 线性压回不拆 | 保持单文件 | ~50 轮才达 ≤600;D088 §第一性需求 SEMA stmt/expr 分发器分层永久阻塞;D102 §最终目标 11 文件清单永不减 | 否(feedback_600_split_not_inline:禁止压不拆)|
| E:拆到 `bootstrap/checker/stmts/` 二级子目录 | 子目录语义边界更清 | 现 checker/ 子目录刚在 D114 立住一级扁平风格,二级子目录需重排 7→12 成员的 import 路径;D114 §决策 1 L97 "check 族成员少、扁平模式"共识未变,激活二级子目录无净收益 | 否(遵循 D114 模式)|
| F:激进按 kind case 全拆(checkStmt 19 case 抽 19 独立 check_stmt_* 函数) | checkStmt 分发器 438 → ~150 | 违 D088 §第一性需求"evalExpr 单函数吸收所有 kind dispatch"方向 —— 吸收方向是**合并**而非**拆散**,case 抽出是**反向动作**;拆完反而制造 19 个小文件,M3a(dispatch 层数)飙升触 D097 反射根因 gate | 否(违主线)|

---

## 路线连线

- **D088 §第一性需求 L9-13** → checker stmt/expr 分发器(check_stmts.ss / check_exprs.ss)物理独立 → 为 Zig SEMA"evalExpr 单函数吸收所有 kind dispatch"提供**两个** kind dispatch 模块载体(stmt 和 expr),后续 SEMA 吸收时按模块合流,与 D114 的 check_types.ss 对齐
- **D102 §规则 R4** → check_stmts.ss ~510 ≤600 → baseline 条目删除 → 11 文件清单 → 10 文件
- **D102 §最终目标 L115** "全 ≤600" → 本 Plan 推进 1 步(与 D114 已完成的 checker.ss R4 并列,两者合入主清单)
- **D114 §决策模板** → Execute 分步风险递增 + 每步机械 gate + 协调策略,本 Plan 平行复用(5 步对齐 D114 的 4 步模式)
- **P10.1** → 6 文件每文件职责单一(return / narrow / named_args / thread / exprs / stmts driver),依赖单向(stmts → exprs → named_args/thread;stmts → return/narrow;return/narrow/named_args/thread 不反向依赖 stmts/exprs),结构清晰 gate 达标
- **D007 return path analysis** → check_return.ss 独立承载,后续返回路径规则扩展(泛型返回类型 / async 返回约束)有物理载体
- **D067 null safety** → check_narrow.ss 独立承载,后续 D067 Phase 3(泛型 null 约束)smart narrowing 扩展不与其他层混乱
- **D082 Phase 3 concurrency** → check_thread.ss 独立承载,后续 Phase 4 actor/channel 闭包规则扩展对齐
- **D084 object literal + named constructor** → check_named_args.ss 独立承载,后续 named args 在普通函数调用的扩展(如 JS kwargs 风格)有物理入口

---

## 下一步

**已完成**:§决策 1-6 全部规划 + 替代方案 6 选 1 + 隐藏假设 10 项验证 + **Execute 1**(check_return.ss,blockAlwaysReturns + stmtAlwaysReturns,check_stmts.ss 1083 → 1020,F1 baseline 同步,GATE PASS)。

**待执行**:§决策 4 的 Execute 2-5 分步落地。每步执行一轮用户授权,逐轮走 PFV 开工 / 收工 / 收尾 gate。

**下一轮**:由用户授权启动 Execute 2(check_narrow.ss 抽出 rejectPrimitiveNullable / extractNullCheckVar / restoreNarrowing,check_stmts.ss 1020 → ~997),或用户指定其他方向。
