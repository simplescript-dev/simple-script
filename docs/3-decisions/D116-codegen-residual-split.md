# D116: codegen.ss 剩余层按职责细分 4 文件(emit / var_alias / rt_cache / ct_alias 归位 + annotation 迁移)

**Status:** Plan Done / Execute 4/5 完成(Execute 1 at `gen/rt/gen_rt_cache.ss` + Execute 2 at `gen/gen_var_alias.ss` + Execute 3 at `gen/gen_emit.ss` + Execute 4 at `eval/ct_driver.ss:155`;剩 Execute 5)

**Depends on:**
- D088 §第一性需求 L7-13(Zig SEMA 一份 evalExpr)/ §背景 Zig 的根 L64-80(编译器即解释器)
- D102 §规则 2.1 R1-R5 L109-113(F1 GATE)/ §最终目标 L115"全 ≤ 600 + P10.1 结构清晰 并列 gate"
- D113 §第一性需求 L17-24 / §决策 1-6(codegen.ss 1266 → 492 三层分离,本 D116 处理**剩余层内部职责混堆**,是 D113 的延续章节)
- D115 §决策 4 Execute 分步模板(5 步风险递增 + 每步机械 gate)
- D112 §决策 1(ctVars 吸收 comptimeTypeAliases,commit 13f5b3e 已稳定)
- P10.1(`principles.md:21`)拆分判据结构清晰不是行数
- **PFV §字段 3 F1 特例**(`principles.md:64`)"2026-04-20 codegen.ss=492 baseline=1166 漂移误判 GREEN 教训" 明文指名本文件
- `feedback_structure_not_linecount.md` / `feedback_subdir_split_style.md` / `feedback_600_split_not_inline.md` / `feedback_ultrathink_gate.md`(下轮 payload 必含 ultrathink)
- CLAUDE.md §交互式单文档 / §PFV 流程

**Date:** 2026-04-20

---

## 第一性需求

`bootstrap/gen/codegen.ss` 492 行 ≤ 600 F1 R4 外观通过,但 `grep '^(function|let|const)\s+\w+'` 输出 **67 条 top-level 声明**(22 函数 + 45 let),按职责归类 **7 类**(P10.1 阈值 ≥ 3 即不清晰,本文件 2× 超标):

1. **Codegen 驱动 + 顶层遍历**(主职责)—— `initCodegen` / `resetCodegen` / `generateToFile` / `emitGlobalsAndCode` / `registerAllDecls` / `isTopLevelDecl` / `registerFuncDeclNode`,~230 行
2. **IR 基础 buffer + reg/label 原语 + 字符串常量池**(D113 分出 `ir_builder.ss` 后的**对称底层**)—— `emitIR` / `nextReg` / `nextLabel` / `addStringConst` + `irBuf` / `strConsts` / `regCount` / `labelCount` 等 state,~85 行
3. **变量别名层**(LLVM 变量名 mangling)—— `initVarAliases` / `allocVarName` / `llVarName` / `varRef` + 4 state,~40 行
4. **D112 ctVars / comptime type alias 胶水**(SEMA scope 查询)—— `ctLookupTypeVal` / `resolveCtTypeAlias` / `ctPopScope` + 6 state,~32 行
5. **Annotation stub 占位**(Phase 3 eval core 未落地)—— `registerAnnotation` / `collectClassAnnotations` / `emitAnnotationInits` + 2 array,~11 行
6. **运行时缓存 build**(CLI 子命令独立驱动)—— `buildRuntimeCache` + 3 state,~32 行
7. **无归属纯 let 共享容器**(跨 ≥ 5 gen/ 子文件读写)—— `enumValues/types/...` + `generic*` + `breakLabel` / `continueLabel` / `isThreadClosure` 等 25+ let,~30 行

## 否定证据

1. **PFV §字段 3 F1 特例 自身的第一个执行案例未兑现** —— `principles.md:64` 明文 "codegen.ss=492 baseline=1166 漂移误判 GREEN 教训" 已落 principles,但本文件自身未被复盘过。**不执行 D116 = 规则自身成为没兑现的文字**,PFV §字段 3 gate 永无第一次试用
2. **linter baseline 漂移证据**(A 类)—— `tools/linter_baseline.txt:16` 仍是 `F1:bootstrap/gen/codegen.ss=1166`(实际 492 差 **-674**),D113 Execute 4 commit 声明 "R4 达成 → baseline 条目删除" 但实际未删。不做 D116 = 漂移继续蒙混 F1 GATE
3. **D098 Phase B / D088 SEMA 路线连带阻塞** —— Phase B 将扩 interp\* 到 class instance + Meta 对象,`ctVars` 扩到 class 字段读写又要在 codegen.ss 打补丁,`interp_core.ss` 544/600 余量被迫让位给 codegen 驱动层杂物

**收益链**:

```
7 职责按 P10.1 单一化物理分离(emit / var_alias / rt_cache 新建 + ct_alias 并入 ct_driver + annotation 迁 class_annotation)
  → codegen.ss 492 → ~310,职责类别 7 → 2(驱动 + state registry)P10.1 达标
  → linter_baseline.txt L16 漂移真正清,A 类数值漂移修
  → D102 §最终目标 "行数 + 结构 双 gate" 本 Plan 第一个走完双 gate 的案例
  → ctVars / ctPopScope 落 eval/ct_driver.ss,D088 SEMA 子模块分层进一步收敛
  → 后续 codegen.ss 改动仅触驱动 ≤310 行,review 成本减半
```

---

## 当前事实(2026-04-20 snapshot,commit 40b84e7 D115 关闭后)

| 项 | 值 / 位置 |
|---|---|
| codegen.ss 当前行数 | `wc -l` 实测 **492** |
| codegen.ss F1 baseline | `tools/linter_baseline.txt:16` `F1:bootstrap/gen/codegen.ss=1166`(**A 类漂移 -674**,D113 Execute 4 遗留未 R4 删除)|
| codegen.ss top-level 声明数 | `grep '^(function\|let\|const)\s+\w+'` 实测 **67**(22 函数 + 45 let)|
| 职责类别数 | **7 类** ≥ 3 → P10.1 不清晰 → RED 成立 |
| `bootstrap/eval/ct_driver.ss` | 139 行,余量 461(承载 D116 Execute 4 扩展 +31 → 170 充裕) |
| `bootstrap/gen/class/class_annotation.ss` | 156 行,余量 444(承载 D116 Execute 5 迁 annotation stub +11 → 167 充裕) |
| `bootstrap/gen/` 根扁平现状 | D113 后 15 文件 + 5 子族(class/ exprs/ stmts/ methods/ rt/);本 Plan 在 gen/ 根新增 2(gen_emit + gen_var_alias)→ 17,在 gen/rt/ 扩族 +1(gen_rt_cache,8 → 9)—— 按命名族归位,不破根扁平 |

### codegen.ss 分段盘点(精确行号 + 归属决策)

| 段 | 行号 | 函数/职责 | 行数 | 归属 |
|---|---|---|---|---|
| 顶部注释 + import | 1-10 | — | 10 | codegen.ss 保留 |
| 核心 IR buffer state | 14-20 | `irBuf` / `strConsts` / `strCount` / `irOutFile` / `strOutFile` / `regCount` / `regTable` | 7 | **→ gen/gen_emit.ss** |
| SEMA ctVars state | 21-26 | `ctVars` / `ctInvalidated` / `ctFuncNodes` / `ctScopeStack` / `ctCallCounter` / `comptimeDepth` | 6 | **→ eval/ct_driver.ss** |
| `labelCount` state | 27 | IR label 计数 | 1 | **→ gen/gen_emit.ss** |
| 基础 codegen state | 28-31 | `varTypes` / `varTypesReady` / `currentFunc` / `terminated` | 4 | codegen.ss 保留 |
| varAliases state | 32-35 | `varCounter` / `varAliases` / `globalAliases` / `varAliasReady` | 4 | **→ gen/gen_var_alias.ss** |
| varAliases 族 | 37-67 | `initVarAliases` / `allocVarName` / `llVarName` / `varRef` | 31 | **→ gen/gen_var_alias.ss** |
| 无归属 state registry | 70-77 | `breakLabel` / `continueLabel` / `enum*` / `isThreadClosure` | 8 | codegen.ss 保留(**state registry 类**)|
| Comptime 缓存 state | 80-84 | `comptimeExprType` / `comptimeExprLiteral` / `comptimeConsts` | 5 | codegen.ss 保留 |
| D112 ct alias 族 | 89-100 | `ctLookupTypeVal` / `resolveCtTypeAlias` | 12 | **→ eval/ct_driver.ss** |
| Generic state | 103-111 | `genericFuncNodes` / `specializedFuncs` / ... 8 个 | 9 | codegen.ss 保留(state registry)|
| `initCodegen` | 113-117 | 入口初始化 | 5 | codegen.ss 保留 |
| emit 族 | 119-135 | `emitIR` / `nextReg` / `nextLabel` | 17 | **→ gen/gen_emit.ss** |
| Annotation stub | 138-148 | 2 array + 3 空函数 | 11 | **→ gen/class/class_annotation.ss**(三 stub 全活见 §决策 5)|
| `addStringConst` | 150-176 | 字符串常量池 | 27 | **→ gen/gen_emit.ss** |
| `registerFuncDeclNode` | 185-238 | 函数注册 | 54 | codegen.ss 保留 |
| `registerAllDecls` / `isTopLevelDecl` | 240-308 | 顶层声明遍历 | 69 | codegen.ss 保留 |
| `emitGlobalsAndCode` | 310-359 | 全局 + 主 pass | 50 | codegen.ss 保留 |
| `resetCodegen` | 361-426 | 状态重置 | 66 | codegen.ss 保留 |
| `ctPopScope` | 428-436 | comptime scope 出栈 | 9 | **→ eval/ct_driver.ss** |
| runtime cache state | 438-440 | 3 个 let | 3 | **→ gen/rt/gen_rt_cache.ss** |
| `buildRuntimeCache` | 442-469 | 运行时缓存构建 | 28 | **→ gen/rt/gen_rt_cache.ss** |
| `generateToFile` | 471-489 | codegen 主入口 | 19 | codegen.ss 保留 |

### 行数预算

| 文件 | 承载 | 估行 | 余量 ≤ 600 |
|---|---|---|---|
| `bootstrap/gen/gen_emit.ss`(新)| 7 state + emitIR + nextReg + nextLabel + addStringConst | **~85** | 515 |
| `bootstrap/gen/gen_var_alias.ss`(新)| 4 state + initVarAliases + allocVarName + llVarName + varRef | **~45** | 555 |
| `bootstrap/gen/rt/gen_rt_cache.ss`(新)| 3 state + buildRuntimeCache | **~40** | 560 |
| `bootstrap/eval/ct_driver.ss`(扩)| 139 → **~170**(+31:6 state + ctLookupTypeVal + resolveCtTypeAlias + ctPopScope)| 170 | 430 |
| `bootstrap/gen/class/class_annotation.ss`(扩)| 156 → **~167**(+11 annotation stub)| 167 | 433 |
| `bootstrap/gen/codegen.ss`(保留)| initCodegen + registerFuncDeclNode + registerAllDecls + isTopLevelDecl + emitGlobalsAndCode + resetCodegen + generateToFile + state registry 25 let | **目标 ~310** | 290 |

---

## 决策

### §决策 1 — 3 新文件 + 2 现有文件扩 + 按 gen/ 子目录命名族归位

按 P10.1 单一职责 + `feedback_subdir_split_style` "按职能归族,族即子目录" 共识:
- **gen/ 根扁平**新建 2 文件:`gen_emit.ss`(IR 原语 + state)+ `gen_var_alias.ss`(变量别名),归入驱动族
- **gen/rt/ 扩族**新建 1 文件:`gen_rt_cache.ss`(buildRuntimeCache + 3 state),与现存 `gen_rt_io/system/map/array/string/ref/thread/channel` 八文件同族命名(`gen_rt_*`)
- 扩 `eval/ct_driver.ss`(吸收 ctVars / ctLookupTypeVal / ctPopScope 等 SEMA scope 族)+ `gen/class/class_annotation.ss`(吸收 annotation stub 族)各一族

### §决策 2 — codegen.ss 保留项裁决(P10.1 ≤ 2 类)

codegen.ss 剩余 = **驱动** + **state registry** 两类:
- **驱动**:initCodegen / registerFuncDeclNode / registerAllDecls / isTopLevelDecl / emitGlobalsAndCode / resetCodegen / generateToFile(codegen 顶层生命周期)
- **state registry**:25 个纯 let(enum\* / generic\* / break/continueLabel / isThreadClosure / varTypes / currentFunc / terminated / comptimeExpr\* / comptimeConsts 等),跨 ≥ 5 gen/ 子文件读写,SS `let` 全局 scope 模型下集中在驱动入口文件顶部是自然归属。P10.1 允许 ≤ 2 类——驱动 + registry 两类并存不违反

### §决策 3 — 函数族归属裁决(细粒度)

**emit vs 驱动边界**:`emitIR` / `nextReg` / `nextLabel` / `addStringConst` 共享 `irBuf` / `strConsts` / `regCount` / `labelCount` state,是 IR 文本输出**基础原语层**(和 D113 分出的 ir_builder.ss 低层 24 函数对称)→ **归 gen_emit.ss**。

**var_alias vs 驱动边界**:`initVarAliases` / `allocVarName` / `llVarName` / `varRef` 4 函数 + 4 state 封闭,无外层函数调用,叶子模块 → **归 gen_var_alias.ss**。

**ct_alias vs driver 边界**:`ctLookupTypeVal` / `resolveCtTypeAlias` / `ctPopScope` 操作 `ctVars` / `ctScopeStack` 6 state,与 eval/ct_driver.ss 现有 `flushComptimeSS` / `preScanCodegenCtClassesInStmts` 是 **SEMA 解释器 scope 管理的同一逻辑层** → **扩 eval/ct_driver.ss**。D112 §决策 1 commit 13f5b3e 已稳定(`comptimeTypeAliases` 吸收到 ctVars),无行号冲突。

**rt_cache 独立**:`buildRuntimeCache` 是 CLI `ss build --rt-cache` 子命令驱动,与主 codegen pass(generateToFile)无函数调用关系,3 state 仅本函数读写,完全独立 → **归 gen_rt_cache.ss**。

**Annotation stub 归并**(§决策 5 详述):3 空函数 + 2 空 array 全部调用链**活**(codegen:266/278 + gen_decls:315 + ct_driver:32/64/104)。**不删,迁 gen/class/class_annotation.ss**——与 annotation 实体代码同族。

### §决策 4 — Execute 分步(风险递增)

| Execute | 内容 | 估改动 | 冲突 | 风险 |
|---|---|---|---|---|
| **Execute 1** `[x] Done at gen/rt/gen_rt_cache.ss:11` | 创建 `bootstrap/gen/rt/gen_rt_cache.ss`(~40 行,buildRuntimeCache + 3 state)。codegen.ss 删 L438-469,492 → ~452(R1 PROGRESS -40;R3 新文件 ≤ 600 PASS)。gen/rt/ 子族 8 → 9 成员,与 gen_rt_io/system/array 等命名一致。实测 492 → 460(-32;simplify 后微差)。| ~35 行迁移 | 零 | 低(独立 CLI 子命令,叶子模块,0 主 pass 调用)|
| **Execute 2** `[x] Done at gen/gen_var_alias.ss:12` | 创建 `bootstrap/gen/gen_var_alias.ss`(42 行,initVarAliases + allocVarName + llVarName + varRef + 4 state)。codegen.ss 删 L33-36 + L38-68(4 state + 4 函数),实测 460 → 425(R1 -35)。main.ss L7 去除过时 `initVarAliases` import spec(SS 全局 scope 经 codegen.ss import 自动接续)。P10.1 top-level 63 → 55,职责类别 6 → 5。| ~35 行迁移 | 零 | 低(叶子模块,SS 全局 scope 自动接续)|
| **Execute 3** `[x] Done at gen/gen_emit.ss:16` | 创建 `bootstrap/gen/gen_emit.ss`(62 行,emitIR + nextReg + nextLabel + addStringConst 4 函数 + 8 state:irBuf / strConsts / strCount / irOutFile / strOutFile / regCount / regTable / labelCount)。codegen.ss 删 7 state + labelCount + emit 3 函数 + addStringConst,实测 425 → 373(R1 -52)。P10.1 top-level 55 → 43,职责类别 5 → 4(驱动 + state registry + ct_* 待迁 Execute 4 + annotation stub 待迁 Execute 5)。跨文件 emitIR/strOutFile/regTable 调用 15+ 处(gen_calls/gen_type_ops/gen_arrows/gen_generic_class/interp_value 等)全靠 SS 全局 scope 接续,0 import 新增。bootstrap 固定点通过。| ~50 行迁移 | 零 | 中(emitIR 高频调用,跨所有 gen/ 子文件;纯函数 SS 全局 scope 接续;bootstrap 固定点验证)|
| **Execute 4** `[x] Done at eval/ct_driver.ss:155` | 扩 `bootstrap/eval/ct_driver.ss` 139 → 177:新增 ctLookupTypeVal + resolveCtTypeAlias + ctPopScope + 6 ctVars state。codegen.ss 删 L18-23 + L46-60 + L342-350,实测 373 → 343(R1 PROGRESS -30)。codegen.ss L7 import 扩 ctVars/ctFuncNodes/ctScopeStack/ctCallCounter/comptimeDepth(5 state,按本文件直接使用归族)。P10.1 top-level 43 → 34,职责类别 4 → 3(驱动 + state registry + annotation stub 待迁 Execute 5)。跨文件 ctVars/ctScopeStack 读写(gen_assigns 等)靠 SS 全局 scope 自动接续。bootstrap 固定点通过,4 test fail 全 pre-existing(stash + Execute 3 baseline rebuild 对照证实 spring_web_params 在 pre-Execute4 同样 undefined function 'dispatcherServlet';d096_p4_l2_reactive 明写"预期 fail";harness_bug/harness_task 为 untracked WIP)。| ~32 行迁移 | 零(D112 §Execute 1 稳定)| 中-低(ctVars 跨文件读写 gen_assigns/gen_calls/gen_types 等,SS 全局 scope 自动接续;ct_driver 177 ≤ 600 充裕)|
| **Execute 5** | 迁 annotation stub 到 `bootstrap/gen/class/class_annotation.ss` 156 → ~167:annClassNodeIds + annClassAnnNames + 3 空函数。codegen.ss 删 L138-148,~325 → ~314。**同步收尾 record 清 `tools/linter_baseline.txt:16` `codegen.ss=1166` 漂移条目**(R4 触发 → baseline 条目删除)| ~11 行迁移 | 零 | 低(空 stub)|

**每步后机械 gate**:

1. `./build.sh bootstrap` 固定点(seed → stage1 → stage2 → stage3,stage2 == stage3)
2. `bin/ss test tests/` 全绿
3. `bin/ss run tools/reflection_health_linter.ss` 无 GATE BLOCKED(D097 14 指标 + D102 F1 GATE)
4. **PFV §字段 3 F1 特例复检**:`grep '^(function|let|const)\s+\w+' bootstrap/gen/codegen.ss` 归类数单调下降,Execute 5 收尾 ≤ 2 时宣告 P10.1 达标
5. F1 baseline 处理:
   - Execute 1-4:gen_rt_cache(40)/ gen_var_alias(45)/ gen_emit(85)/ ct_driver 170 全 ≤ 600 过 R3;codegen.ss baseline 1166 每步 record 自动从高位单调下降(1166 一路降到 314 以下触发 R4)
   - **Execute 5 关键**:收尾 record 必须验证 `tools/linter_baseline.txt:16` 的 `F1:bootstrap/gen/codegen.ss=1166` **真正从文件删除**(D113 Execute 4 声明了但未兑现,本 Plan 是修这一漂移的实际动作)

### §决策 5 — Annotation stub 归并细则

3 stub 调用链验证(2026-04-20 grep):
- `registerAnnotation` — codegen.ss:266 registerAllDecls annotationMapping case(**活**)
- `collectClassAnnotations` — codegen.ss:278 + eval/ct_driver.ss:32/64/104(**活 × 4**)
- `emitAnnotationInits` — gen_decls.ss:315(**活**)

全 6 个调用点活跃 → **不删除**。迁移目标:`bootstrap/gen/class/class_annotation.ss`(156 行,当前承载 `@derive` 生成 annotation 实体代码)—— 三 stub 与 annotation 实体代码**同族**,Phase 3 eval core 落地时 body 填充也在同一文件,符合 "关联代码同体" 原则。迁后 class_annotation.ss = ~167 ≤ 600。

### §决策 6 — F1 baseline 处理细则 + A 类漂移清理

D102 §规则 R1 / R3 / R4 对本 Plan 的具体应用:

1. **R1 同文件单调**:codegen.ss 每 Execute 单调下降(492 → 452 → 416 → 355 → 325 → 314)
2. **R3 新文件 ≤ 600**:gen_rt_cache(40)/ gen_var_alias(45)/ gen_emit(85)全过 R3
3. **R4 baseline 删除**:linter_baseline.txt:16 的 `F1:bootstrap/gen/codegen.ss=1166` 是 **D113 Execute 4 遗留未删的 A 类漂移** baseline。Execute 5 收尾 record 必须 verify 该条目从文件删除(D102 §方案 3.4 `writeBaseline` L276-278 `if (cur > F1_LIMIT)` 逻辑自然不写入即删除)
4. **D102 §最终目标 "全 ≤ 600 + P10.1" 双 gate**:
   - 下限 gate:`linter_baseline.txt` 10 条 F1 主清单 → 9 条(与 D114 删 checker.ss / D115 删 check_stmts.ss 并列)
   - 结构 gate:codegen.ss 职责 7 → 2 类达标
5. **不在本 Plan 处理的 baseline 漂移**(留独立轮):
   - L23 `gen_decls.ss=691` vs wc 690 差 -1(A 类微,下次 bootstrap record 自然修)
   - L25-30 6 条 B 类语义漂移(新文件 ≤ 600 误挂 baseline,是 R3 "入库" vs R4 "降到 600 删除" 的规则冲突,本 Plan 不碰,待 D102 §规则 clarification 独立轮)

### §决策 7 — codegen.ss 后续细分预案(若 state registry 膨胀触 R1)

codegen.ss 目标 ~310,余量 290 充裕。若 D098 Phase B 扩 state 触 R1 阻断,按结构拆:

- `gen/gen_state.ss` — enum / generic / thread / control-flow state 容器
- `gen/codegen.ss` 保留 — initCodegen / registerFuncDeclNode / registerAllDecls / emitGlobalsAndCode / resetCodegen / generateToFile + basic state

本 Plan 不执行 §决策 7,Phase B 触 R1 时再启动。

---

## 替代方案对比(Plan 型 VCM ④ 边界)

| 方案 | 收益 | 代价 | 选否 |
|---|---|---|---|
| **A:4 新文件 + 2 扩 + annotation 迁(本方案)** | P10.1 职责 7 → 2 类达标;ct 族归并 ct_driver 避免新子目录膨胀;annotation 合流 class_annotation 语义自然;A 类漂移 baseline 一并清 | gen/ 根扁平 15 → 18 成员(可控);ct_driver 139 → 170;class_annotation 156 → 167 | **选** |
| B:6 文件激进全拆(含 ct_alias 独立 + state registry 独立)| 每职责独立文件 | ct_alias 12 行独立文件太小(P13 反例);state registry 独立文件就是 25 let 容器,意义薄 | 否(过分割)|
| C:只拆 emit + var_alias 2 文件(保守)| 文件数 +2 最小;codegen.ss 492 → ~370 | 未触 P10.1 ≤ 2 类(仍 rt_cache / ctVars / annotation 3+ 类混堆)| 否(职责混堆未根治)|
| D:不拆,只 record 修漂移(光修 L16 1166 → 492)| 一行改动 | PFV §字段 3 F1 特例 第一个执行案例不兑现;P10.1 结构 gate 永不达标;下轮改 codegen 仍跨 7 心智模型 | 否(违 PFV §字段 3 本意)|
| E:Annotation stub 直接删除 | 更简洁,死代码清理 | 三 stub 全活(6 个调用点),删除需同步重构 registerAllDecls + ct_driver + gen_decls —— 扩大本 Plan 变动面 | 否(§决策 5 Execute 5 已选"迁不删")|
| F:全部拆到 `bootstrap/gen/codegen/` 二级子目录 | 语义边界更清 | 违 feedback_subdir_split_style "gen/ 根扁平" 2026-04-20 共识;import `../../eval` → `../../../eval` 跨族深度 +1 | 否(违 feedback)|

---

## 隐藏假设 + Execute 前验证

| # | 假设 | 验证 |
|---|---|---|
| 1 | SS `let` / `function` 跨模块自动共享(全局 scope),新文件可 0-import 接续现有调用 | ✅ D113 / D115 已多次验;本 Plan grep 已证 varAliases(gen_calls 读写)/ ctVars(gen_assigns 读写)/ enumValues(gen_methods/types 读)等跨文件 0-import 共享 |
| 2 | emitIR 跨 gen/ 所有子文件调用,迁 gen_emit.ss 后全局 scope 自动接续 | ✅ 已 grep 验:gen_calls / gen_types / gen_decls / gen_stmts / stmts_* / exprs_* / methods/ / class/ / rt/ 全部 0-import 直调 emitIR,SS resolveImports 递归内联保持接续 |
| 3 | ctVars / ctScopeStack 迁 eval/ct_driver.ss 后 gen_assigns.ss L266-303 语义不变 | ✅ grep 验:gen_assigns L266-303 直读写 ctVars/ctScopeStack 无 import,全局 scope 接续;ct_driver 扩后调用链 eval/ident.ss:22 等自然可见 |
| 4 | `tools/linter_baseline.txt:16` 的 codegen.ss=1166 在 Execute 5 record 时 R4 触发删除 | 读 `reflection_health_linter.ss` writeBaseline 实现验证:L276-278 `if (cur > F1_LIMIT) { text = text + F1:... }` —— cur=314 < 600 不写入 = 删除 ✅ |
| 5 | Annotation 3 stub 全活,迁 class_annotation.ss 后调用链不断 | ✅ grep 已验 6 个调用点(codegen:266/278 + gen_decls:315 + ct_driver:32/64/104)全活;迁后 SS 全局 scope 接续 |
| 6 | ct_driver 139 +31 → 170 ≤ 600 R3 通过 | 预算可控,bootstrap 固定点验证 |
| 7 | class_annotation 156 +11 → 167 ≤ 600 R1 通过(已在 baseline? 需查)| `linter_baseline.txt` 无 class_annotation 条目(≤ 600 无需 baseline),+11 → 167 仍 R2 状态 ≤ 600 OK ✅ |
| 8 | 新建 3 文件 + 扩 2 文件对 M/N 累计指标在 ±0.5% 容差 | D113 / D115 同类动作已证 M2 / N2 在容差内;本 Plan 每步后观察 linter 输出 |

---

## 路线连线

- **D088 §第一性需求 L7-13** → SEMA scope 管理(ctLookupTypeVal / ctPopScope + ctVars)迁 eval/ct_driver.ss → 继续收敛 SEMA 子模块,为 "Zig SEMA 一份 evalExpr" 扫清驱动层杂物
- **D102 §规则 R4** → codegen.ss A 类漂移 baseline 条目真正删除 → 10 条主清单 → 9 条
- **D102 §最终目标 L115 "全 ≤ 600 + P10.1 结构清晰 并列 gate"** → 本 Plan 是该 "并列双 gate" 第一个走完两边的案例(D113 只达成行数下限,未触 P10.1)
- **D113 §第一性需求 L17-24 延续** → 三层物理分离后,本 Plan 处理"驱动层 492 内部剩余 7 职责混堆",是 D113 的第二阶段
- **D115 §决策 4 模板** → Execute 5 步风险递增 + 每步机械 gate 复用
- **D112 §决策 1** → commit 13f5b3e 已稳定,本 Plan Execute 4 迁 ct 族无动区冲突
- **P10.1 `principles.md:21`** → 本 Plan 核心判据,codegen.ss 7 → 2 职责服从该原则
- **PFV §字段 3 F1 特例 `principles.md:64`** → 本 Plan 是该规则自身 "codegen.ss=492 baseline=1166 漂移误判 GREEN 教训" 的**第一次执行案例**,兑现规则
- **feedback_subdir_split_style** → gen/ 根扁平 15 → 18 成员符合共识,不建 `codegen/` 二级子目录

---

## baseline 漂移清单(附,`tools/linter_baseline.txt` 30 条条目 vs 实际 wc -l)

| # | Line | baseline 条目 | wc -l 实测 | 漂移 | 类别 | 本 Plan 处理 |
|---|---|---|---|---|---|---|
| 1 | L16 | `F1:bootstrap/gen/codegen.ss=1166` | **492** | **-674** | **A 数值(巨)** | ✅ Execute 5 收尾 record 触 R4 删除 |
| 2 | L17 | `F1:bootstrap/parse/parser.ss=813` | 813 | 0 | OK | — |
| 3 | L18 | `F1:bootstrap/main.ss=630` | 630 | 0 | OK | — |
| 4 | L19 | `F1:bootstrap/gen/gen_calls.ss=695` | 695 | 0 | OK | — |
| 5 | L20 | `F1:bootstrap/gen/gen_types.ss=738` | 738 | 0 | OK | — |
| 6 | L21 | `F1:bootstrap/parse/parse_stmts.ss=617` | 617 | 0 | OK | — |
| 7 | L22 | `F1:bootstrap/gen/methods/gen_methods.ss=709` | 709 | 0 | OK | — |
| 8 | L23 | `F1:bootstrap/gen/gen_decls.ss=691` | **690** | **-1** | **A 数值(微)** | ❌ 不处理,下次 record 自然修 |
| 9 | L24 | `F1:bootstrap/gen/gen_runtime.ss=621` | 621 | 0 | OK | — |
| 10 | L25 | `F1:bootstrap/checker/check_return.ss=63` | 63 | 0 | **B 语义** | ❌ 不处理,留 D102 R3/R4 clarification 轮 |
| 11 | L26 | `F1:bootstrap/checker/check_narrow.ss=35` | 35 | 0 | **B 语义** | ❌ 同上 |
| 12 | L27 | `F1:bootstrap/checker/check_named_args.ss=84` | 84 | 0 | **B 语义** | ❌ 同上 |
| 13 | L28 | `F1:bootstrap/checker/check_thread.ss=65` | 65 | 0 | **B 语义** | ❌ 同上 |
| 14 | L29 | `F1:bootstrap/checker/check_exprs.ss=339` | 339 | 0 | **B 语义** | ❌ 同上 |
| 15 | L30 | `F1:bootstrap/gen/ir_builder.ss=101` | 101 | 0 | **B 语义** | ❌ 同上 |

**漂移分类总结**:
- **A 类(数值漂移)2 条** — L16(-674 巨)+ L23(-1 微):record 流程遗漏 update。本 Plan Execute 5 收尾清 L16;L23 下次 bootstrap record 自然修
- **B 类(语义漂移)6 条** — L25-30:新建文件 ≤ 600 却误挂 baseline。根因是 `reflection_health_linter.ss` `writeBaseline` L276-278 对 D102 §规则 2.1 R3 "入库" 语义的实现选择——`cur <= F1_LIMIT` 时是否写 baseline 二选一。当前选了 "不写" 的实现,但 linter_baseline.txt 里还有 L25-30 残留,可能是历史 record 时某次 buggy 写入。**本 Plan 不处理**,需 D102 §规则 R3/R4 clarification 独立轮
- **C 类(职责混堆漂移)1 条** — codegen.ss 492 ≤ 600 外观过 F1,但 P10.1 结构不清晰。**本 D116 核心消除对象**

---

## 下一步

D116 Plan 关闭:§决策 1-7 + 替代方案 6 选 1 + 隐藏假设 8 项 + baseline 漂移清单 A/B/C 三类全落盘。

**Execute 启动前**:由用户审阅 D116 措辞 + 方案 A-F 选择,明确授权后再启动 Execute 1。

本 Plan **不承诺 Execute 时间**,Execute 交独立一轮发起(PFV §字段 3 要求 Execute 型任务附**本轮已跑过的** RED 命令 + 输出作凭据,Execute 启动轮再附)。
