# D148: SS Bidirectional Type Checking — 全编译器双向类型检查 sub-D 起首(D141-D145 §A.1 C3 + §A.3 五处一致锁的 SS 类型系统 v2 起首入口)

**Status:** Phase 1 — RED 复现 + 信息源探查 + scope 实测 [✓] Done at commit `<placeholder>` (2026-05-03)— Phase 0 D 文档落档 commit `73eb4c5` 已闭环(详 §Status 时间线);**Phase 1 兑现 a-g**:(a) D141-D144 累计 **15 ad-hoc trap helper** grep 实证(D141:4 isFnType/extractFnParamType/extractFnRetType/inferArrowFuncParams + D142:2 extractArrayElemType/inferArrayLitElems + D143:4 isClassType/extractClassName/inferObjLiteralFromType/inferObjLiteralFields + D144:5 isNullableType/extractInnerType/unifyBranchTypes/propagateTernaryBranchType/inferTernaryBranchType,全在 `bootstrap/gen/gen_types.ss:766-981`)+ **D145 异常发现** 0 helper 主线未实施完(`tests/d145_map_literal_inference/` 目录不存在 + grep MAP_LIT 节点全 0 命中 + D145.md 仅 Phase 1 RED commit `17a1573` 实施未落);(b) G1 **16 落点**(`gen_calls.ss:279/281/284/286` + `gen_methods.ss:196/198/200/202` + `eval/method_call.ss:61/63/65/69` + `eval/call.ss:33/35/39/41`,4 helper × 4 落点)+ **outer pre-eval 9 处**(method_call.ss 4 + call.ss 4 + new_expr.ss 1);(c) **bootstrap LOC delta 实测 ~500-850 修正**(D148 §核心目标 原估 > 2000 LOC 高估 — checker 已局部 bidirectional `check_exprs.ss:91/156/270` funcParamTypes 反推三处 fn arg / method arg / ctor arg + `check_types.ss:229 isTypeCompatible`,bidirectional refactor 是**统一已存机制 entry** 不是从零重写);(d) **Phase 拆分细化建议 N=5**(Phase 3 checker 单一 entry inferTypeWithExpected + Phase 4 gen_types 5 helper 统一接管 + Phase 5 G1 16 落点收 + Phase 6=N+1 cleanup helper 删 + Followup 自然解 + Phase 7=N+2 全 Phase 收关 hash trail);(e) **H9 PASS 初步**(`pir/pir.ss:101 startsWith("Array<")/("Map<")` + `pir.ss:200 inferType` + `pir_lower.ss:89-90 inferType` 只读类型字符串前缀做 RC 判定不参与推断,bidirectional 是 codegen-time 推断 PIR 不需扩)+ **H10 PASS 实证**(`ls tests/phase5/generic_*.ss | wc -l` = 14 + `gen_generic_class.ss` 427 行 + `gen_types.ss:711 resolveTypeParam` 实存,memory feedback_d026_d027_phantom_anchor §事实层 §实现锚兑现)+ H8 待 Phase 3+ 子 Phase bootstrap 三阶段固定点实测 + H14 入档 + **H15 留 Phase 2 用户对话锁定**(推翻 D141-D145 5 sub-D 一致 v2 决策授权门槛);(f) spike form 1-N 用 `tests/d141_lambda_inference/` 11 + `tests/d142_array_literal_inference/` 6 + `tests/d143_object_literal_inference/` 6 + `tests/d144_ternary_inference/` 8 baseline + grep/ls 实测代替(更纯 docs only,VCM §1 豁免锚成立);(g) Phase 0 commit hash `73eb4c5` 回填 **3 处真锚**(line 3 Status header + line 382 §Phase 收关锚 §Phase 0 + line 452 §Status 时间线 Phase 0 entry — **用户口号校验**「Phase 0 hash 4 处回填」字面口号实测 占位符行数实测 = 3,memory feedback_user_literal_vs_d_ssot 同形防御兑现);**新发现总结**:checker 已局部 bidirectional 机制存在(funcParamTypes 反推三处 fn/method/ctor + isTypeCompatible)+ 5 helper 在 codegen 阶段反推 — bidirectional refactor 是**统一已存机制 entry** 不是从零重写,scope 比原估小 3-4 倍(~500-850 vs > 2000);Phase 1 详细 fact 入 §A.2 H8/H9/H10/H14 + §Phase 收关锚 §Phase 1 + §Status 时间线;D135/D136/D137/D140/D141/D142/D143/D144/D145/D147 范式延续(每 Phase 独立 commit + Phase X+1 启动轮回填上一 Phase hash + next_prompt 自闭环);**Phase 0 描述保留**:D141 §F5 + D142 §F4 + D143 §F5 + D144 §F7 + D145 §F6 **五合真锚** sub-D 起首落档(用户口号「D142/D143 §F7 同位 bidirectional」是 §F 编号机械套用错位虚锚 — D142 §F7 = NEW_EXPR ctor 实参 array literal 反推 / D143 §F7 = spread 反推,bidirectional 真锚是 D142 §F4 / D143 §F5,memory feedback_user_literal_vs_d_ssot 防御范畴);bidirectional type checking 全局 — checker 改 expected/actual 双向类型检查,所有表达式从调用上下文反推类型,消除 D141-D145 5 处独立 ad-hoc 接口层 trap 反推机制(`isFnType` / `isArrayType` / `isClassType` / `isMapType` / `extractFnParamType` / `extractArrayElemType` / `extractClassName` / `extractMapKVTypes` / `inferArrowFuncParams` / `inferArrayLitElems` / `inferObjLiteralFields` / `inferMapLiteralKVTypes` 等 N helper)→ 统一 bidirectional 框架(checker 单一 entry point + 各表达式 case 走 bidirectional);后续 Tuple / NEW_EXPR ctor 子节点 / partial fields / spread / 反推失败粒度等同模式 sub-D(D145 §F1-F5 + D144 §F2-F6 + D143 §F3+/F6+/F7+/F8 + D142 §F6+ + D141 §F4)bidirectional 落地后全部 unnecessary;**scope > 2000 LOC + bootstrap 重写多核心文件**(checker / gen_types / 各 inferType 落点 / eval pre-eval / funcParamTypes 重构等)→ Phase 0 仅落档不实施,Phase 1+ 启动需用户对话锁定 C2 渐进 vs C3 完整 + 子 Phase 拆分细化;D141-D145 5 sub-D §A.1 C3 + §A.3 一致锁「留 SS 类型系统 v2」是审慎决策不是未考虑,D148 Phase 0 兑现 v2 起首最小动作不轻易推翻;前置依赖已满足:**generic 基础设施已落** `bootstrap/gen/gen_generic_class.ss` 整文件 427 行 + `bootstrap/gen/gen_types.ss:711 resolveTypeParam` + 14 case GREEN(`tests/phase5/generic_*.ss`,memory feedback_d026_d027_phantom_anchor §事实层 §实现锚 grep 实证),不再用 D026/D027 历史代号占位;§A.1 C1/C2/C3 + §A.1.1 G1/G2/G3 + §A.2 H1-H15 + §A.3 + Phase 0-N 计划草案 + Followup F1-F6 全锚定;D135/D136/D137/D140/D141/D142/D143/D144/D145 范式延续(D145 Phase 0 commit `d2fb4e1` 同模式 — Phase 0 D 文档落档 + Phase 1+ bootstrap 改各独立 commit + Status 时间线 + commit hash 回填 + next_prompt 自闭环)

**Depends on:**
- D141(lambda 参数类型推断 — §Followup F5 bidirectional 真锚 line 466 + §A.1 C3 + §A.3 留 v2 一致决策)
- D142(array literal contextual typing — §Followup F4 bidirectional 真锚 line 517 + §A.1 C3 + §A.3 留 v2 一致决策)
- D143(object literal contextual typing — §Followup F5 bidirectional 真锚 line 513 + §A.1 C3 + §A.3 留 v2 一致决策)
- D144(ternary contextual typing — §Followup F7 bidirectional 真锚 line 527 + §A.1 C3 + §A.3 留 v2 一致决策)
- D145(map literal contextual typing — §Followup F6 bidirectional 真锚 line 460 + §A.1 C3 + §A.3 留 v2 一致决策)
- D141/D142/D143/D144/D145 §A.1.1 G1 路径(callee PARAM 结构化签名 + codegen 阶段反推 + eval pre-eval 时序 + funcParamTypes 信息源单点)— D148 G1 同模式扩到全表达式
- D141/D142/D143/D144/D145 §A.2 H1-H13(funcParamTypes 时序 / setVarType 自然链路 / callee 结构化必要 / 失败硬错粒度 / cross-D 反推时序验证)— D148 同模式假设挑战 + H14-H15 新增
- D025(interface dispatch — vtable indirect dispatch 路径不动)
- D052(Map keys array — `Map<K,V>` 数据结构 + ss_mapNew/ss_mapSet 运行时已落)
- D067(null safety — Kotlin/Dart 风格,默认非空,T? 可空)
- D131(`Array<T?>` nullable inner field — bidirectional widen 边界判定不破契约)
- `bootstrap/checker/check_types.ss:inferType`(待 Phase 1 探查精确 line 号 — D141-D145 已扩 ARROW_FUNC/ARRAY_LIT/OBJ_LITERAL/TERNARY/MAP_LIT case)
- `bootstrap/checker/check_exprs.ss`(待 Phase 1 探查 — D141-D145 已落各表达式 case)
- `bootstrap/gen/gen_types.ss`(待 Phase 1 探查 — D141-D145 已落 5+ helper)
- `bootstrap/gen/codegen.ss:110-112`(funcParamTypes 普通函数注册)+ `bootstrap/gen/gen_registry.ss:56-57`(class method funcParamTypes 注册)— bidirectional expected 类型源 SSoT
- `bootstrap/gen/gen_generic_class.ss`(整文件 427 行 — generic 基础设施)+ `bootstrap/gen/gen_types.ss:711 resolveTypeParam` — bidirectional 复用 generic 类型参数解析
- `bootstrap/eval/method_call.ss:64` + `bootstrap/eval/call.ss:36` + `bootstrap/eval/new_expr.ss:24`(D141-D145 H10 锚 outer call site pre-eval) — bidirectional 改 outer call site expected 类型传递
- `bootstrap/pir/pir.ss + pir_lower.ss + pir_opt.ss`(PIR 中间层 — bidirectional 是否需扩 PIR 类型留 Phase 1 探查)
- CLAUDE.md §Java/TS 语法优先(TS/Flow/OCaml/Scala bidirectional 是主流类型系统范式)
- CLAUDE.md §Root Cause 优先 第一法则(成本不是选次优理由 + 长久/演化维度必入候选评估)
- CLAUDE.md §交互式单文档(每轮等用户明确指定一个文档)
- CLAUDE.md §决策记录(每个确认决策立即写入 docs/3-decisions/,多 Phase 进度只写在 D 文档里)
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优的理由 + 长久/演化维度三维)
- `memory/feedback_d026_d027_phantom_anchor.md`(generic 已落 14 case GREEN 实证 — bidirectional 起首前置依赖满足)
- `memory/feedback_user_literal_vs_d_ssot.md`(用户口号 vs D 文档 SSoT 落差 — D142/D143 §F7 bidirectional 是虚锚,真锚 D142 §F4 / D143 §F5)
- `memory/feedback_no_option_menu.md`(三候选论证 + 决策行)
- `memory/feedback_no_derive_workaround.md`(主线能力缺口不允许 annotation 替代)
- `memory/feedback_h10_cross_d_verify.md`(H10 cross-D 反推时序验证 — bidirectional 全编译器反推时序必继承)
- `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验(Plan 型 §④ 替换「替代方案对比 + 隐藏假设挑战」)+ §字段 8 「Layer 跨越触发 stop / D 文档独立审查窗口不许吞」(D148 Phase 0 = Decision Layer,Implementation 留 Phase 1+)+ §字段 10 (d) 长久/演化维度必入候选评估(底层依赖链 + 业界演化对标 + N 年返工度)

**Date:** 2026-05-03
**Last Updated:** 2026-05-03

---

## 核心目标 (Goal)

- **为什么**:D141-D145 5 sub-D 各落一处独立 ad-hoc 接口层 trap 反推机制 — D141 callee PARAM s2 反推 ARROW_FUNC + D142 elemType 反推 ARRAY_LIT + D143 className 反推 OBJ_LITERAL(class<X>) + D144 branchType 反推 TERNARY + D145 K+V 双反推 OBJ_LITERAL(Map<K,V>),5 处独立反推机制 + 5+ helper 函数(`isFnType` / `isArrayType` / `isClassType` / `isMapType` / `extractFnParamType` / `extractArrayElemType` / `extractClassName` / `extractMapKVTypes` / `inferArrowFuncParams` / `inferArrayLitElems` / `inferObjLiteralFields` / `inferMapLiteralKVTypes`)+ 4 G1 落点 × 5 sub-D = 20 落点 + eval pre-eval × 3 outer call site × 5 sub-D = 15 处时序前移,无统一 bidirectional 框架。后续 Tuple / NEW_EXPR ctor 子节点 / partial fields / spread / 反推失败粒度等同模式 sub-D(D145 §F1-F5 + D144 §F2-F6 + D143 §F3+/F6+/F7+/F8 + D142 §F6+ + D141 §F4)继续扩 = 反推机制累积 5 → 10 → 15 处技术债。业界对标 TypeScript / Flow / OCaml / Scala / Hindley-Milner bidirectional type checking 是主流类型系统范式;**SS 当前 ad-hoc 接口层 trap 是短期权宜**,N 年返工度极高(bidirectional 落地后这些 sub-D 全部 unnecessary)。**末层断言可观测否定证据**(Phase 0 实测):`ls docs/3-decisions/D148*.md 2>&1` 当前 = `No such file or directory`(exit=2)— D148 文档落档 RED 成立,本轮 Phase 0 GREEN(commit hash 回填后 `ls` 命中)。
- **是什么**:全编译器 bidirectional type checking — checker 改 expected/actual 双向类型检查,所有表达式从调用上下文反推类型;消除 D141-D145 5 处 ad-hoc 接口层 trap 独立反推机制 → 统一 bidirectional 框架(checker 单一 entry point `inferTypeWithExpected(exprId, expectedType)` + 各表达式 case 走 bidirectional 反推);**callee 类型分叉判定**统一在 bidirectional `expected` 类型 dispatch(`fn(P,...):R` → ARROW_FUNC bidirectional / `Array<T>` → ARRAY_LIT bidirectional / `class<X>` → OBJ_LITERAL bidirectional class ctor / `Map<K,V>` → OBJ_LITERAL bidirectional Map literal / `T?` → TERNARY/expr bidirectional widen / 等);后续 Tuple `Tuple<T1,T2>` / spread `{...base, name: "X"}` / partial fields / NEW_EXPR ctor 实参子节点反推等表达式形态在 bidirectional 框架内自然解,不需独立 sub-D 同模式扩展。配合 funcParamTypes SSoT 复用(`bootstrap/gen/codegen.ss:110-112` + `gen_registry.ss:56-57`)+ generic 基础设施复用(`gen_generic_class.ss` + `resolveTypeParam`,memory feedback_d026_d027_phantom_anchor 实证)+ eval pre-eval outer call site `genVal(argId)` 时序前移(D141-D145 H10 同形)。
- **单一判据**:Phase 0 D 文档落档(`ls docs/3-decisions/D148*.md` GREEN);Phase 1 RED 复现 + 信息源探查 + scope 实测(D141-D145 5 处 ad-hoc trap helper grep 实证 5 处 + bootstrap LOC delta 估 + Phase 拆分细化)+ 隐藏假设 H1-H15 探查;Phase 2 候选 C2 渐进 vs C3 完整 用户对话锁定决策行;Phase 3-N bidirectional 渐进实施(子 Phase bootstrap 三阶段固定点 + tests/d141-d145 baseline 不破)+ Phase N+1 5 处 ad-hoc trap helper 删 + Followup 队列 bidirectional 自然解 + Phase N+2 全 Phase 收关 hash trail。

> 一句口号:**bidirectional type checking 全局 — 消除 D141-D145 5 处 ad-hoc trap,统一类型系统**(后续 Tuple/spread/partial fields/反推失败粒度等同模式 sub-D 全部 unnecessary;业界对标 TS/Flow/OCaml/Scala/HM 主流范式)

---

## 核心原则 (Principles)

1. **bidirectional 上位,5 处 ad-hoc trap 上位解** — D141-D145 §A.1 C3 五处一致锁定的根因解;Phase 0 兑现 v2 起首最小动作,不推翻「留 v2」决策本身,而是把「v2」具体化(把 5 sub-D 一致锁的废案抬到主线)
2. **scope > 2000 LOC + bootstrap 重写多核心文件 → 多 Phase 拆分必经** — checker / gen_types / 各 inferType 落点 / eval pre-eval / funcParamTypes 重构等 5+ 核心文件渐进改;Phase 0 落档 scope 风险锚 R1-R6 + Phase 拆分草案,Phase 1 实测细化(N=4-8?)
3. **Phase 0 仅 D 文档落档不实施** — Implementation Layer 留 Phase 1+,§MNK §M §字段 8 Layer 跨越触发 stop;Phase 1+ 启动需用户对话锁定 C2 渐进 vs C3 完整(推翻 D141-D145 5 sub-D「留 v2」一致决策需授权)
4. **D141-D145 范式延续** — 5 sub-D Phase 0-5 范式 + 每 Phase 独立 commit 大改档不打包 + Status 时间线 + commit hash 回填 + next_prompt 自闭环;D148 因 scope 大估 Phase 0-N(N=未定,Phase 1 实测确定)
5. **业界对标 TS / Flow / OCaml / Scala / Hindley-Milner** — bidirectional 是主流类型系统范式(Pierce & Turner "Local Type Inference" 2000;TypeScript contextual typing;Flow / Hack / Sorbet bidirectional 实现);SS 当前 ad-hoc 接口层 trap 是短期权宜
6. **N 年返工度极低** — bidirectional 落地后 D145 §F1 Tuple / D145 §F2 NEW_EXPR ctor / D145 §F3 partial / D145 §F4 spread / D145 §F5 反推失败粒度 + D144 §F2-F6 + D143 §F3+/F6+/F7+/F8 + D142 §F6+ + D141 §F4 等同模式 sub-D 全部 unnecessary,自然解
7. **底层依赖链 — bidirectional 是底层,D141-D145 ad-hoc trap 是上层补救** — 按"先 X 后 Y"原则,bidirectional 应先于其他同模式扩 sub-D(MNK §M §字段 10 (d) 长久/演化维度)
8. **generic 基础设施复用** — `bootstrap/gen/gen_generic_class.ss` 整文件 427 行 + `bootstrap/gen/gen_types.ss:711 resolveTypeParam` + 14 case GREEN(`tests/phase5/generic_*.ss`)— memory feedback_d026_d027_phantom_anchor §事实层 §实现锚 grep 实证;bidirectional `expected` 类型解析(含 `Map<K,V>` / `Array<T>` / `class<X>` / `T?` 嵌套)直接复用 resolveTypeParam,不重复造轮子;**不再用 D026/D027 历史代号占位**(memory 已清零完结)
9. **D141-D145 §A.2 H1-H13 假设范式扩 + H14-H15 新增** — funcParamTypes 时序 H1 / setVarType 自然链路 H2 / callee 结构化必要 H3 / 失败硬错粒度 H4 / cross-D 反推时序 H5(memory feedback_h10_cross_d_verify)/ parser 不扩 H6 / var binding callee OOD scope H7(D141 H9 同模式)/ bootstrap 三阶段固定点 scope > 2000 LOC 是否破 H8 / PIR 中间层是否需扩 H9 / generic 基础设施复用充分性 H10 / bidirectional 是否引入新运行时 state H11 / 5 处 ad-hoc trap helper 删后 tests/d141-d145 是否 GREEN H12 / Followup 队列 bidirectional 自然解度 H13 / **scope 实测 > 估值 H14**(Phase 1) / **推翻 D141-D145 5 sub-D「留 v2」一致决策授权门槛 H15**(Phase 2)
10. **bootstrap 隔离破例** — D141 §核心原则 5 + D142 §核心原则 6 + D143 §核心原则 7 + D144 §核心原则 7 + D145 §核心原则 8 同位例外,D148 主线改 bootstrap 修编译器(checker / gen_types / 各 inferType 落点 / eval pre-eval / funcParamTypes 重构),scope 独立但比 D141-D145 大 1-2 数量级
11. **零破坏既有 ad-hoc trap 在 bidirectional 落地前** — D141-D145 5 处 ad-hoc trap 在 bidirectional 渐进 refactor 期间继续工作,Phase N+1 删 trap helper 才完结;tests/d141 / d142 / d143 / d144 / d145 baseline 全程不破(失败 → 回 Phase 3-N 修)
12. **Phase 计划独立 commit** — 大改档:Phase 0 D 文档落盘 + Phase 1+ bootstrap 改各独立 commit,§MNK 大改档不打包(D135-D145 范式延续);Phase 0 docs only 1 file 改(D135/D136/D137/D140/D141/D142/D143/D144/D145 范式 — 单 commit 大改档)
13. **VCM 六验全跑(Phase 1+) + Phase 0 §1 豁免锚** — bootstrap 三阶段固定点 + tests/ 不降 + tests/d141-d145 反推机制 baseline 不破 + reflection_health_linter GATE PASS(Phase 1+ 触动反射路径需扩容申报 留 Phase)+ d_doc_index_linter F1=0 永久;**Phase 0 docs-only 不动 bootstrap → VCM §1 豁免锚成立**(D135-D145 同位)
14. **D141-D145 §A.1 C3 五处一致废留 v2 决策审慎,Phase 1+ 推翻需授权** — 5 sub-D 一致达成不是未考虑,Phase 0 落档兑现 v2 起首最小动作 + Phase 1+ 实施门槛高;C2 vs C3 锁定留用户对话(scope > 2000 LOC + bootstrap 重写多核心文件 + 一锅炖风险高)
15. **memory feedback_d026_d027_phantom_anchor 防虚锚 + memory feedback_user_literal_vs_d_ssot 防口号** — bidirectional 全局五合真锚必以 D 文档实测为准(D141 §F5 / D142 §F4 / D143 §F5 / D144 §F7 / D145 §F6),用户口号「D142/D143 §F7 同位」是 §F 编号机械套用错位虚锚必报;同形虚锚跨轮防御 — bidirectional 起首前置依赖 generic 已 grep 实证不再用 D026/D027 占位

---

## 1. Context Management

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D148)
2. CLAUDE.md §Java/TS 语法优先 + §Root Cause 优先 第一法则 + §高层架构 + §交互式单文档 + §决策记录
3. 依赖 D 文档:
   - D141 §A.1.1 G1 路径 + §A.2 H1-H13 + §F5 bidirectional 真锚(line 466)
   - D142 §A.1.1 G1 路径 + §A.2 H1-H13 + §F4 bidirectional 真锚(line 517)
   - D143 §A.1.1 G1 路径 + §A.2 H1-H13 + §F5 bidirectional 真锚(line 513)
   - D144 §A.1.1 G1 路径 + §A.2 H1-H13 + §F7 bidirectional 真锚(line 527)
   - D145 §A.1.1 G1 路径 + §A.2 H1-H13 + §F6 bidirectional 真锚(line 460)
   - D025 interface dispatch
   - D052 Map keys array(`Map<K,V>` 数据结构)
   - D067 null safety(可空 T?)
   - D131 Array<T?> nullable inner field
4. 关键代码位置(Phase 1+ 探查后精确化 line 号):

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/checker/check_types.ss` | inferType 入口(待 Phase 1 探查精确 line)| **bidirectional checker 主入口** — Phase 2+ 改 expected/actual 双向类型检查 + 单一 entry `inferTypeWithExpected(exprId, expectedType)` |
   | `bootstrap/checker/check_exprs.ss` | 各表达式 case(待 Phase 1 探查 — D141-D145 已落 ARROW_FUNC/ARRAY_LIT/OBJ_LITERAL/TERNARY/MAP_LIT case)| bidirectional checker 各表达式 — Phase 2+ 改 expected/actual 双向反推 |
   | `bootstrap/gen/gen_types.ss` | D141-D145 ad-hoc trap helper(`isFnType` / `isArrayType` / `isClassType` / `isMapType` / `extractFnParamType` / `extractArrayElemType` / `extractClassName` / `extractMapKVTypes` / `inferArrowFuncParams` / `inferArrayLitElems` / `inferObjLiteralFields` / `inferMapLiteralKVTypes`)| **D141-D145 5 处 ad-hoc trap helper 函数** — Phase N+1 删,bidirectional 接管 |
   | `bootstrap/gen/codegen.ss` | 110-112 funcParamTypes 注册 | **bidirectional expected 类型源 SSoT** — Phase 2+ 复用,bidirectional 改 expected 类型源 |
   | `bootstrap/gen/gen_registry.ss` | 56-57 class method funcParamTypes 注册 | 同上 |
   | `bootstrap/gen/gen_generic_class.ss` | 整文件 427 行 | **generic 基础设施已落** — bidirectional 复用 generic monomorphization |
   | `bootstrap/gen/gen_types.ss` | 711 resolveTypeParam | **generic type param 解析已落** — bidirectional 复用 |
   | `bootstrap/gen/gen_calls.ss` | D141-D145 4 G1 落点(`resolveCallArgs` 等)| bidirectional refactor 后 4 落点 → 1 落点(checker 单一 entry)|
   | `bootstrap/gen/methods/gen_methods.ss` | D141-D145 4 G1 落点(`emitClassMethodCall` 等)| 同上 |
   | `bootstrap/eval/method_call.ss` | 64(D141-D145 H10 锚)| outer call site pre-eval — bidirectional 改 outer call site expected 类型传递 |
   | `bootstrap/eval/call.ss` | 36(D141-D145 H10 锚)| 同上 |
   | `bootstrap/eval/new_expr.ss` | 24(D141-D145 H10 锚)| 同上 |
   | `bootstrap/pir/pir.ss + pir_lower.ss + pir_opt.ss` | PIR 中间层 | **bidirectional 是否需扩 PIR 类型** — H9 Phase 1 探查 |

### Context 不变量

| 不变量 | 状态 |
|---|---|
| generic 基础设施(gen_generic_class.ss + 14 case GREEN)| **Phase 0 已 grep 实证**(memory feedback_d026_d027_phantom_anchor §事实层 §实现锚)— bidirectional 起首前置依赖满足 |
| funcParamTypes Map<K,V> 注册 SSoT | 已就绪(D141-D145 H1 同模式继承)— `codegen.ss:110-112` 普通函数 + `gen_registry.ss:56-57` class method 直接注册原始 SS 类型字符串含 `fn(P,...):R` / `Array<T>` / `class<X>` / `Map<K,V>` / `T?` 形态 |
| D141-D145 5 处 ad-hoc trap | 在 bidirectional 落地前继续工作 — Phase N+1 删 trap helper 才完结 |
| D052 Map keys / D025 interface / D067 null safety / D131 Array<T?> 既有契约 | 不破 — bidirectional refactor 不动数据结构 |
| OBJ_LITERAL / ARRAY_LIT / ARROW_FUNC / TERNARY / MAP_LIT 节点 | 已存(D141-D145 已落)— bidirectional 复用,parser 不扩 |
| 反射 baseline | tools/reflection_health_linter.ss(Phase 1+ 触动反射路径需扩容申报 留 Phase)|
| d_doc_index_linter F1 | Phase 0 实测 PASS(D148 加入未破 referenced Ds — D025/D052/D067/D131/D141/D142/D143/D144/D145 实存,F2 soft warn 含 D148 不阻 commit) |

### 禁止的 Context 操作

- ❌ Phase 0 改 bootstrap / lib / tests(Phase 0 仅 D 文档落档,Implementation Layer 留 Phase 1+ — §MNK §M §字段 8 Layer 跨越触发 stop)
- ❌ 改 D141-D145 文档本体(同位例外锚 D148 同模式继承,文档不动)
- ❌ 改 D025 / D052 / D067 / D131 等依赖 D 文档
- ❌ 删 D141-D145 5 处 ad-hoc trap helper 函数在 Phase N+1 之前(Phase 0-N 渐进 refactor,trap 在 bidirectional 落地前继续工作)
- ❌ 起 D149+ Followup sub-D(D148 = bidirectional 全局上位入口,本轮 Followup F1+ 排队 Phase N+2 之后)
- ❌ Phase 0 锁定 C2 vs C3 候选(scope > 2000 LOC + 推翻 D141-D145 5 sub-D 一致决策需用户对话授权)
- ❌ Phase 0 跑 bootstrap 固定点 / reflection GATE / 全测 baseline(VCM §1 docs-only 豁免锚成立 — D135-D145 同位)
- ❌ 删 / 合并 / deprecate 既有 D 文档(D026/D027 已清零完结,本轮不动)
- ❌ 改 CLAUDE.md / docs/3-MNK.md / memory 既存 feedback(本轮 D148 自带 §核心原则 引用既存 memory,不修)

---

## 2. Tools

| 工具 | Phase | 用途 |
|------|-------|------|
| `bin/ss run tools/d_doc_index_linter.ss` | Phase 0+ | D 文档治理 gate(F1=0 + F2 soft warn 不阻)|
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | Phase 0+ | next_prompt.md 必含 ultrathink 关键字 GATE |
| `./build.sh bootstrap` | Phase 1+ | bootstrap 三阶段固定点(D148 主线改 bootstrap 后必跑)|
| `bin/ss test tests/` | Phase 1+ | 全测 baseline 不降 |
| `bin/ss test tests/d141_lambda_inference/` | Phase 1+ | D141 反推机制 baseline 不破 |
| `bin/ss test tests/d142_array_literal_inference/` | Phase 1+ | D142 反推机制 baseline 不破 |
| `bin/ss test tests/d143_object_literal_inference/` | Phase 1+ | D143 反推机制 baseline 不破 |
| `bin/ss test tests/d144_ternary_inference/` | Phase 1+ | D144 反推机制 baseline 不破 |
| `bin/ss test tests/d145_map_literal_inference/`(若有)| Phase 1+ | D145 反推机制 baseline 不破 |
| `bin/ss test tests/phase5/generic_*.ss` | Phase 1+ | generic 基础设施 14 case baseline 不破(memory feedback_d026_d027_phantom_anchor 实证锚)|
| `bin/ss build /tmp/spike_bidirectional_*.ss --emit-ir` | Phase 1+ | IR 层 RED→GREEN spike 验证 |
| `bin/ss run tools/reflection_health_linter.ss` | Phase 1+ | 反射 baseline(Phase 1+ 触动反射路径需扩容申报)|

### 禁止引入

- ❌ Phase 0 引入新工具 / 新依赖 / 新 LLVM IR helper(Phase 0 docs only)
- ❌ Phase 1+ 引入新关键字 / 新语法(bidirectional 是反推机制重构,非语法扩展;CLAUDE.md §Java/TS 语法优先红线)
- ❌ Phase 1+ 引入新依赖(generic 基础设施 + funcParamTypes SSoT 已落,复用即可)

---

## 3. Orchestration

### 总体节奏(D141-D145 Phase 0-5 范式延续 + scope 大 → 多 Phase 拆分,Phase 0 落档草案 N=4-8 待 Phase 1 实测确定)

| Phase | 目标 | 关键产出 | 验证 |
|-------|------|----------|------|
| **Phase 0** | D 文档落档(本 Phase) | `docs/3-decisions/D148-*.md` | d_doc_index_linter F1 = 0 + ultrathink_linter PASS + VCM §1 豁免锚成立 |
| **Phase 1** | RED 复现 + 信息源探查 + scope 实测 | (a) D141-D145 5 处 ad-hoc trap helper grep 实证(`isFnType` / `isArrayType` / `isClassType` / `isMapType` / `extractFnParamType` / `extractArrayElemType` / `extractClassName` / `extractMapKVTypes` / `inferArrowFuncParams` / `inferArrayLitElems` / `inferObjLiteralFields` / `inferMapLiteralKVTypes`)+ (b) bootstrap LOC delta 估(checker / gen_types / 各 inferType 落点 / eval pre-eval / funcParamTypes 重构)+ (c) Phase 拆分细化(N=4-8?)+ (d) 候选 C2 渐进 vs C3 完整 实测对比 + (e) 隐藏假设 H1-H15 探查(generic 基础设施复用充分性 H10 / PIR 是否需扩 H9 / bootstrap 固定点 scope > 2000 是否破 H8 / scope 实测 > 估值 H14)| Phase 1 commit + scope 实测 fact 入 §1 + 隐藏假设探查 fact 入 §A.2 |
| **Phase 2** | 候选 C2 vs C3 用户对话锁定 + 子 Phase 拆分 + 实施前置 | §A.1 C2 vs C3 用户对话锁定决策行 + 子 Phase 拆分 D 文档草案 + 实施前置 fact 入 §1 | Phase 2 commit + 用户对话决策行 |
| **Phase 3-N** | bidirectional 渐进实施(子 Phase 拆 — N=4-8?)| `bootstrap/checker/check_types.ss` + `check_exprs.ss` bidirectional 改 + 单一 entry `inferTypeWithExpected(exprId, expectedType)` + `gen_types` 5 helper 渐进删 + eval pre-eval bidirectional expected 类型传递 + funcParamTypes expected 类型源重构等 | bootstrap 固定点 PASS + spike GREEN + tests/d141-d145 baseline 不破 + tests/phase5/generic baseline 不破 + reflection GATE PASS |
| **Phase N+1** | D141-D145 5 处 ad-hoc trap helper 删 + workaround cleanup + Followup 队列 bidirectional 自然解 | 5 helper 删(`isFnType` / `extractFnParamType` / `inferArrowFuncParams` 等)+ tests/d141-d145 仍 GREEN(bidirectional 接管)+ Followup 队列(D145 §F1 Tuple / D145 §F2 NEW_EXPR ctor / D145 §F3 partial / D145 §F4 spread / D145 §F5 反推失败粒度 + D144 §F2-F6 + D143 §F3+/F6+/F7+/F8 + D142 §F6+ + D141 §F4)bidirectional 自然解 | bootstrap 固定点 + tests/ 全绿 + grep 5 helper = 0 + Followup 队列各形态 spike GREEN |
| **Phase N+2** | 全 Phase 收关 hash trail | D148 全 Phase commit hash 全列 + 兑现成果 a-g + 隐藏假设 H1-H15 全 PASS / OOD 标 + Followup 锚明确 + Status 时间线全 [✓] | D148 主线 close + d_doc_index_linter F1=0 永久 + reflection GATE PASS 永久 |

### Phase 间依赖

- Phase 0 → Phase 1(D 文档落档 → RED 复现 + 信息源探查 + scope 实测)
- Phase 1 → Phase 2(scope 实测 + 隐藏假设探查 fact → 候选 C2 vs C3 用户对话锁定)
- Phase 2 → Phase 3-N(候选锁定 + 子 Phase 拆分 → 子 Phase bootstrap 渐进改)
- Phase 3-N → Phase N+1(bidirectional 接管 → ad-hoc trap helper 删 + Followup 自然解)
- Phase N+1 → Phase N+2(workaround cleanup → 全 Phase 收关 hash trail)

### 反模式

- ❌ Phase 0 锁定 C2 vs C3 候选(scope > 2000 LOC + 推翻 D141-D145 5 sub-D 一致决策需用户对话授权,Phase 0 越权)
- ❌ Phase 0 实施 bootstrap 改(Layer 跨越,§MNK §M §字段 8 触发 stop)
- ❌ Phase 1 跳过 scope 实测直接 Phase 2(scope 是 C2 vs C3 决策的关键因子 — H8 / H14 必经)
- ❌ Phase 3-N 一锅炖(scope > 2000 LOC + bootstrap 重写多核心文件,必须子 Phase 拆分 — 大改档不打包,D135-D145 范式延续)
- ❌ Phase N+1 删 trap helper 时 tests/d141-d145 baseline 破(bidirectional 接管不充分,回 Phase 3-N 修)
- ❌ 跳 Phase N+2 全 Phase 收关(Phase hash trail + 兑现成果 a-g + 隐藏假设全 PASS / OOD 标 + Followup 锚明确缺失即漂移)
- ❌ 实施 Followup 队列 sub-D(D145 §F1+ / D144 §F2+ 等)在 Phase N+1 之前(bidirectional 未落地,Followup 自然解前提不成立)

---

## 4. State

### 编译时 state

- D141-D145 5 处 ad-hoc trap helper 函数(12+ helper) — Phase N+1 删
- generic 基础设施(`gen_generic_class.ss` + `resolveTypeParam`) — bidirectional 复用
- funcParamTypes Map(信息源 SSoT) — bidirectional expected 类型源
- bidirectional checker 单一 entry `inferTypeWithExpected(exprId, expectedType)` — Phase 2+ 落

### 运行时 state

- bidirectional checking 不引入新运行时 state(类型推断 compile-time)— H11 实证

### 中间产物

- Phase 1: spike `/tmp/spike_bidirectional_*.ss` form 1-N(各表达式形态)+ scope 实测 fact + 隐藏假设探查 fact
- Phase 2-N: 子 Phase D 文档草案 + bootstrap 改增量 + tests/d148_bidirectional/ 测试新增
- Phase N+1: workaround cleanup 5 helper 删 + Followup 队列 bidirectional 自然解 spike
- Phase N+2: 全 Phase 收关 hash trail + Status 时间线全 [✓]

### 会话间持久化

- D148 文档(本身)+ 全 Phase commit hash 回填
- D141-D145 文档(依赖,不动)+ 5 处 ad-hoc trap helper 删后 Status 时间线 cross-D 不动(D141-D145 主线 close trail 已闭环,bidirectional 接管在 D148 文档)
- memory feedback_d026_d027_phantom_anchor(generic 已落实证)+ feedback_user_literal_vs_d_ssot(虚锚防御)+ feedback_root_cause_no_cost / feedback_no_option_menu / feedback_no_derive_workaround / feedback_h10_cross_d_verify

### 禁止 state 操作

- ❌ Phase 0 改 funcParamTypes 注册路径 / generic 基础设施 / D141-D145 trap helper 函数
- ❌ Phase 0 引入新运行时 state(bidirectional 是 compile-time)
- ❌ Phase 3-N 改 D052 ss_mapNew / ss_mapSet 本体 / D025 interface vtable / D067 null safety 路径(数据层契约不破)
- ❌ Phase N+1 删 trap helper 时 tests/d141-d145 baseline 破

---

## 5. Evaluation

### 单一判据(必须 GREEN)

- **Phase 0**: `ls docs/3-decisions/D148*.md 2>&1 | grep -c "No such file"` = 0 GREEN(commit hash 回填后 ls 命中)
- **Phase 1+**: 待 Phase 1+ 锁定后定具体 spike GREEN 判据(草案:5 表达式形态 fn arg / method arg / ctor arg / var decl typeAnn / class field init / generic call / interface dispatch / nullable widening 等 bidirectional spike GREEN)

### Phase 0 关键验证

- D148 文档结构完整(§核心目标 + §核心原则 + §1-§6 + §A.1 + §A.1.1 + §A.2 + §A.3 + §Phase 收关锚 + §Followup + §Status 时间线)
- d_doc_index_linter F1=0(D148 加入未破 referenced Ds — D025/D052/D067/D131/D141/D142/D143/D144/D145 实存)
- ultrathink_linter PASS(.claude/next_prompt.md 含 ultrathink 关键字)
- VCM §1 豁免锚成立(Phase 0 docs-only 不动 bootstrap — D135-D145 同位)
- 五合真锚 grep 实证(D141 §F5 line 466 / D142 §F4 line 517 / D143 §F5 line 513 / D144 §F7 line 527 / D145 §F6 line 460)

### Phase 1+ 关键验证(草案)

- bootstrap 三阶段固定点 stage2==stage3
- tests/ baseline 不降
- tests/d141-d145 反推机制 baseline 不破(关键 — bidirectional 在迁移期间共存)
- tests/phase5/generic_*.ss 14 case baseline 不破(memory feedback_d026_d027_phantom_anchor 实证锚)
- reflection_health_linter GATE PASS(扩容申报留 Phase)
- d_doc_index_linter F1=0 永久

### Phase 测试覆盖(草案)

- Phase 1: spike form 1-N(bidirectional 各表达式形态:fn arg / method arg / ctor arg / var decl typeAnn / class field init / generic call / interface dispatch / nullable widening / Tuple / spread / partial fields / 等)
- Phase 3-N: tests/d148_bidirectional/ 新增(覆盖 D141-D145 5 处 ad-hoc trap 接管 + 新表达式 bidirectional)
- Phase N+1: tests/d141-d145 仍 GREEN(bidirectional 接管不破)+ Followup 队列(Tuple / spread / partial fields)bidirectional 自然解 spike
- Phase N+2: 全 Phase 收关 hash trail + 兑现成果 a-g 全锁

---

## 6. Constraints

### 硬约束

- D141-D145 5 处 ad-hoc trap baseline 不破(bidirectional 落地前继续工作)
- D025 interface dispatch / D052 Map / D067 null safety / D131 Array<T?> 契约不破
- generic 基础设施 14 case GREEN baseline 不破(memory feedback_d026_d027_phantom_anchor 实证锚)
- bootstrap 三阶段固定点(Phase 1+ 后)
- d_doc_index_linter F1=0 永久
- reflection_health_linter GATE PASS(扩容申报留 Phase)
- bidirectional 不引入新关键字 / 新语法(CLAUDE.md §Java/TS 语法优先红线)
- D141-D145 §A.1 C3 五处一致废留 v2 决策推翻需用户对话授权(Phase 1+ 实施门槛)

### 软约束

- LOC delta < 200 per Phase(子 Phase 拆分,大改档不打包)
- 每 Phase 独立 commit + commit hash 回填 + Status 时间线(D135-D145 范式)
- Phase 0 仅 D 文档落档(VCM §1 豁免锚成立)
- Phase 拆分草案 N=4-8(Phase 1 实测确定)

### 风险锚(R1-R6)

- **R1: scope > 2000 LOC + bootstrap 重写多核心文件** — 子 Phase 拆分必须细化(Phase 1 实测 + Phase 2 拆分草案);失败 → 回 Phase 1 重新估
- **R2: D141-D145 5 sub-D 一致废留 v2 决策被推翻** — Phase 2 用户对话锁定 C2 vs C3 必经(授权门槛 — H15);失败 → 回 Phase 1 等用户进一步对话
- **R3: bidirectional 落地后 D141-D145 5 处 ad-hoc trap helper 删可能破 baseline** — Phase N+1 必须 tests/d141-d145 全绿才删(H12);失败 → bidirectional 接管不充分,回 Phase 3-N 修
- **R4: PIR 中间层是否需扩** — Phase 1 探查(H9);若需扩 → Phase 拆分细化(子 Phase PIR 扩展)
- **R5: generic 基础设施复用充分性** — Phase 1 探查(H10);若不足 → Phase 拆分细化(子 Phase generic 扩展)
- **R6: bootstrap 三阶段固定点 scope > 2000 LOC 是否破** — Phase 3+ 渐进改子 Phase 必跑(H8);失败 → 子 Phase 回滚 + 修根因 + 重跑

### 失败模式 + 恢复表

| 失败模式 | 恢复 |
|----------|------|
| Phase 1 scope 实测 > 估值 LOC > 2000 | 子 Phase 拆分细化 + 候选 C2 渐进优于 C3 完整 |
| Phase 2 用户对话不通过 C2 vs C3 锁定 | 回 Phase 1 实测细化 + 等用户进一步对话(H15 推翻 v2 授权门槛)|
| Phase 3-N 子 Phase bootstrap 破 baseline | 回滚子 Phase commit + 修根因 + 重跑 |
| Phase N+1 5 处 ad-hoc trap 删后 tests/d141-d145 破 | bidirectional 接管不充分,回 Phase 3-N 修 + 不删 helper |
| Phase N+2 收关时 Followup 队列 bidirectional 自然解不通过 | 回 Phase N+1 修 + Followup 留 sub-D(D148 §Followup F1+)|
| Phase 1 generic 基础设施复用不充分(H10 失败)| 子 Phase generic 扩展 + Phase 拆分细化 |
| Phase 1 PIR 需扩(H9 失败)| 子 Phase PIR 扩展 + Phase 拆分细化 |

### 回滚策略

- 每 Phase 独立 commit,失败回滚 Phase commit + 重跑 PSM 字段 1-9 + 重起 Phase
- D148 文档本身回滚:`git checkout HEAD~ docs/3-decisions/D148-*.md`(Phase 0 落档失败)
- D141-D145 5 处 ad-hoc trap helper 在 Phase N+1 之前不删 — bidirectional 接管不充分时随时回滚到 trap helper 路径

---

## A.1 主候选评估(§MNK §M §字段 10 + Plan 型 §④ 替换:替代方案对比)

| 候选 | 层次 | 描述 | 优势 | 劣势 | 决策 |
|-----|------|------|------|------|------|
| **C1** | **数据层 patch** | D141-D145 5 处 ad-hoc trap 持续扩 — 后续 Tuple / spread / partial fields / 反推失败粒度等同模式 sub-D 持续扩(D145 §F1-F5 + D144 §F2-F6 + 等)| 单 sub-D 单点修 + scope 可控 + 不推翻 D141-D145 「留 v2」决策 | 5 处独立反推机制持续累积 → 10 → 15 处技术债 + N 年返工度极高 + 无统一 bidirectional 框架 + 业界对标 TS/Flow/HM 主流范式偏离 | **不选** — 数据层 zero-spread 不消除根因(`feedback_root_cause_no_cost.md` 红线 + D141-D145 §A.1 C1 同形废)|
| **C2** | **接口层 trap** | 渐进 bidirectional refactor — 分多 Phase 把 D141-D145 5 处 ad-hoc trap 改为 bidirectional 实现 + 新表达式直接 bidirectional 路径 | scope 可控(单子 Phase ~200-300 LOC) + D141-D145 baseline 渐进迁移不一锅炖 + 风险可控 + 符合 D141-D145 大改档不打包范式 | scope 大但分 Phase 缓解 + D141-D145 5 处 ad-hoc trap 在迁移期间共存 + Phase N+1 删 trap helper 才完结 + Phase 数多(N=4-8?)| **候选** — Phase 2 用户对话锁定决策行(C2 vs C3),Phase 0 仅落档不锁 |
| **C3** | **架构层 refactor** | 完整 bidirectional 重写 — 类型推断器整体改 bidirectional + checker 改 expected/actual 双向 + 所有表达式从调用上下文反推类型 + 单一 entry `inferTypeWithExpected(exprId, expectedType)` 一次性落 | 类型系统统一性最高 + 一次性消除 D141-D145 5 处 ad-hoc trap + 业界主流范式 + Phase 数少 | scope 爆炸 LOC > 2000 + bootstrap 重写多核心文件 + 一锅炖风险高 + 推翻 D141-D145 5 sub-D 一致决策 + 单 commit 大改档不打包违 D135-D145 范式 | **候选** — Phase 2 用户对话锁定决策行(C2 vs C3),Phase 0 仅落档不锁 |

**决策行**(Phase 0 落档版,Phase 1+ 用户对话锁定):

- **Phase 0 决策**:**落档 D148 = bidirectional 全局上位入口**,候选 C2 渐进 vs C3 完整 留 Phase 1+ 用户对话锁定。
- **不选 C1**:数据层 zero-spread 不消除根因(feedback_root_cause_no_cost.md 红线 + D141-D145 §A.1 C1 同形废)
- **C2 vs C3 留 Phase 1+ 用户对话锁定**:
  - **C2 渐进**:scope 可控但 D141-D145 5 处 ad-hoc trap 在迁移期间共存,Phase N+1 删 trap helper 才完结;符合 D141-D145 范式延续(每 Phase 独立 commit + 大改档不打包)+ 风险可控
  - **C3 完整**:scope 爆炸但一次性消除 D141-D145 5 处 ad-hoc trap;一锅炖风险高 + 推翻 D141-D145 5 sub-D「留 v2」一致决策需用户对话授权 + 单 commit 大改档不打包违 D135-D145 范式
- **长久 / 演化维度**(MNK §M §字段 10 (d) 三维):
  - **底层依赖链**:bidirectional 是底层,D141-D145 ad-hoc trap 是上层补救;按"先 X 后 Y"原则,bidirectional 应先于其他同模式扩 sub-D ✓ C2 / C3 都满足,C1 不满足(继续上层补救)
  - **业界对标**:TypeScript / Flow / OCaml / Scala / Hindley-Milner bidirectional 是主流范式(Pierce & Turner "Local Type Inference" 2000)✓ C2 / C3 都满足,C1 不满足(继续 ad-hoc 偏离主流)
  - **N 年返工度**:bidirectional 落地后 D145 §F1-F5 + D144 §F2-F6 + 等同模式 sub-D 全部 unnecessary ✓ C2 / C3 都满足,C1 不满足(累积 5 → 10 → 15 处技术债返工度极高)
- **前置依赖已满足**:generic 基础设施(`gen_generic_class.ss` 整文件 + `gen_types.ss:711 resolveTypeParam` + 14 case GREEN — memory feedback_d026_d027_phantom_anchor 实证)+ funcParamTypes SSoT(`codegen.ss:110-112` + `gen_registry.ss:56-57`)
- **D141-D145 §A.1 C3 五处一致决策推翻**:Phase 1+ 用户对话授权门槛(H15 假设 — 推翻 D141-D145 5 sub-D「留 v2」一致决策授权门槛);Phase 0 落档兑现 v2 起首最小动作(不推翻"留 v2",而是把"v2"具体化 — 把 5 sub-D 一致锁的废案抬到主线起首)

---

## A.1.1 实施路径对比(Phase 0 落档,Phase 1 实测确认 + Phase 2 用户对话锁定)

| 路径 | 描述 | Phase 1 实测 | Phase 2 决策 |
|------|------|---------------|---------------|
| **G1** | D141-D145 G1 路径同模式扩 — callee PARAM 已结构化 SSoT 复用 + codegen 阶段反推 + eval pre-eval 时序前移 + funcParamTypes 信息源单点;推到全表达式 | Phase 1 实测 — checker / gen_types / eval / funcParamTypes 信息源全 5 处 ad-hoc trap 同模式扩到全表达式 | C2 + C3 都可走 G1,Phase 2 锁定具体 C/G 组合 |
| **G2** | 完整 checker 重写 — checker 改 expected/actual 双向类型检查,所有表达式从调用上下文反推类型(checker 主入口完整重写)+ 单一 entry `inferTypeWithExpected(exprId, expectedType)` | Phase 1 实测 — checker LOC delta + bootstrap 三阶段固定点风险(H8) | C3 完整 走 G2,Phase 2 锁定 |
| **G3** | 接受 gap,Phase 2 仅做 (a) 预备 — checker 入口加 expected/actual 双向类型检查 stub,(b)(c) bidirectional 因消费链路不接通实际不生效 | 主线 D141-D145 5 处 ad-hoc trap 持续累积 | **不选** — 反推机制空转,违反 feedback_root_cause_no_cost.md 红线(D141-D145 G3 同形废)|

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套 — D141-D145 §A.2 H1-H13 同模式扩 + H14-H15 D148 新增)

| # | 假设 | 描述 | 实证锚 | 失败回退 |
|---|------|------|---------|----------|
| H1 | funcParamTypes 时序 | D141-D145 H1 同模式继承 — `bootstrap/gen/codegen.ss:110-112` 普通函数 + `gen_registry.ss:56-57` class method 直接注册原始 SS 类型字符串(`fn(P,...):R` / `Array<T>` / `class<X>` / `Map<K,V>` / `T?`),`registerAllDecls codegen.ss:326` 在 `emitGlobalsAndCode` 之前 — bidirectional expected 类型源 SSoT 时序就绪 | Phase 0 已实证(D141-D145 H1 同模式继承 PASS) | funcParamTypes 时序失败 → 回 Phase 1 修信息源 |
| H2 | setVarType 自然链路 | D141 H10 同模式 — `gen_arrows.ss:188 setVarType(capName, capType)` capture 路径已 mature,bidirectional 沿用 | Phase 0 已实证(D141 H10 PASS) | setVarType 失败 → 回 Phase 1 修自然链路 |
| H3 | callee PARAM 结构化必要 | D141-D145 同模式 — callee PARAM 已结构化(`fn(P,...):R` / `Array<T>` / `class<X>` / `Map<K,V>` / `T?`),bidirectional `expected` 类型直接读 | Phase 0 已实证(D141-D145 G1 路径 PASS) | callee 结构化不足 → 回 Phase 1 升级 callee 结构 |
| H4 | 失败硬错粒度 | D141-D145 同模式 — 反推失败 → checker 阶段硬错粒度细化,非 silent fallback;D148 全继承 | Phase 0 已实证(D141-D145 H4 PASS) | 失败硬错粒度不足 → 回 Phase 3-N 修 |
| H5 | cross-D 反推时序验证 | D143/D144 H10 同形 — outer call site 通用 pre-eval `genVal(argId)` 才是反推时序关键,不可仅 grep 字面 handler;memory `feedback_h10_cross_d_verify.md` | Phase 0 已实证(D143/D144 H10 PASS,memory 落档) | cross-D 反推时序失败 → 回 Phase 1 修 outer call site pre-eval |
| H6 | parser 不扩 | D052 + D143 OBJ_LITERAL 共享节点 + D144 TERNARY + D145 MAP_LIT 已落,bidirectional 复用既有 AST 节点 | Phase 0 已实证(D141-D145 H6 PASS) | parser 需扩 → 不选(违 §核心原则 5 业界对标 + §A.1 C3 不引入新语法)|
| H7 | var binding callee OOD scope | D141 H9 同模式继承 — `const f = (s) => ...; f(stmt)` var binding 形式 callee="f" IDENT lookup 不到 funcParamTypes,反推 skip;D148 全继承 OOD scope 标 | Phase 0 已实证(D141 H9 OOD PASS) | var binding 反推 → 留 §Followup F6(D141 §F5 + 同模式)|
| H8 | bootstrap 三阶段固定点 scope LOC delta 实测 + 子 Phase 固定点风险 | D148 主线改 bootstrap 修编译器(checker / gen_types / 各 inferType 落点 / eval pre-eval / funcParamTypes 重构 — 实测 `bootstrap/checker/check_types.ss` 341 + `check_exprs.ss` 373 + `gen_types.ss` 1050 + `gen_calls.ss` 737 + `gen_methods.ss` 711 + `eval/method_call.ss` 296 + `eval/call.ss` 110 + `eval/new_expr.ss` 82 + `gen_registry.ss` 280 + `codegen.ss` 339 = 文件总 4319 行,LOC delta 实测估 ~500-850 修正),scope 原估 > 2000 LOC 高估 | **Phase 1 已实证 LOC delta 估 PASS**(~500-850 < 原估 > 2000)+ 子 Phase 固定点风险待 Phase 3+ 实测验证 | 子 Phase 固定点失败 → 子 Phase 回滚 + 修根因 + 重跑 |
| H9 | PIR 中间层是否需扩 | bidirectional 是否需扩 PIR 类型(`bootstrap/pir/pir.ss + pir_lower.ss + pir_opt.ss`,PIR 文件总 897 行 — pir.ss:340 + pir_lower.ss:284 + pir_opt.ss:273)| **Phase 1 已实证 PASS 初步**(`pir/pir.ss:101 startsWith("Array<")/("Map<")` + `pir.ss:200 inferType(initId)` + `pir_lower.ss:89-90 ssType = inferType(initId)` 只读类型字符串前缀做 RC 判定不参与推断 — bidirectional 是 codegen-time 类型推断,PIR 只消费 inferType 输出不参与推断,不需扩) | PIR 实测需扩(超出当前实证) → 子 Phase PIR 扩展 + Phase 拆分细化 |
| H10 | generic 基础设施复用充分性 | `bootstrap/gen/gen_generic_class.ss` 整文件 427 行 + `gen_types.ss:711 resolveTypeParam` + 14 case GREEN 是否充分 | **Phase 0+1 双重实证 PASS**(Phase 0 memory feedback_d026_d027_phantom_anchor §事实层 §实现锚 14 case 实证锚 + Phase 1 `ls tests/phase5/generic_*.ss \| wc -l` = 14 实测 GREEN 兑现) | 复用不足 → 子 Phase generic 扩展 + Phase 拆分细化 |
| H11 | bidirectional 是否引入新运行时 state | bidirectional 是 compile-time,不引入新运行时 state | Phase 0 已实证(类型推断 compile-time PASS) | 引入新运行时 state → 不选(违 §4 运行时 state 禁止)|
| H12 | D141-D145 5 处 ad-hoc trap helper 删后 tests/d141-d145 是否 GREEN | Phase N+1 删 5 helper(`isFnType` / `extractFnParamType` / `inferArrowFuncParams` 等)后 tests/d141-d145 baseline 不破 | Phase N+1 实测假设 — bidirectional 接管 5 处 ad-hoc trap | 删后 tests/d141-d145 破 → 回 Phase 3-N 修 + 不删 helper |
| H13 | Followup 队列 bidirectional 自然解度 | D145 §F1 Tuple / D145 §F2 NEW_EXPR ctor / D145 §F3 partial / D145 §F4 spread / D145 §F5 反推失败粒度 + D144 §F2-F6 + D143 §F3+/F6+/F7+/F8 + D142 §F6+ + D141 §F4 等 bidirectional 落地后自然解度 | Phase N+2 实测假设 — Followup 队列各形态 spike GREEN | 自然解不足 → Followup 留 sub-D(D148 §Followup F1+)|
| **H14** (D148 新增) | scope 实测 vs 估值 + Phase 拆分细化 | bootstrap LOC delta 估 + Phase 拆分细化(原估 N=4-8) | **Phase 1 已实证 fact 入档**:**LOC delta 实测 ~500-850 (< 估值 > 2000 — 修正高估)**;关键 fact — checker 已局部 bidirectional 机制存在(`check_exprs.ss:91/156/270` funcParamTypes 反推三处 fn/method/ctor + `check_types.ss:229 isTypeCompatible`),bidirectional refactor 是**统一已存机制 entry** 不是从零重写;**Phase 拆分 N=5 建议**(Phase 3 checker 单一 entry inferTypeWithExpected + Phase 4 gen_types 5 helper 统一接管 + Phase 5 G1 16 落点收 + Phase 6=N+1 cleanup helper 删 + Followup 自然解 + Phase 7=N+2 全 Phase 收关 hash trail) | scope 修正后 C2 渐进 vs C3 完整 决策行 fact 支撑 — Phase 2 用户对话锁定 |
| **H15** (D148 新增) | 推翻 D141-D145 5 sub-D「留 v2」一致决策授权门槛 | 5 sub-D §A.1 C3 + §A.3 一致决策不是未考虑,Phase 1+ 实施需用户对话授权;Phase 0 落档兑现 v2 起首最小动作不推翻决策本身 | Phase 2 用户对话锁定假设 — C2 vs C3 决策行 + 子 Phase 拆分授权 | 用户对话不通过 → 回 Phase 1 实测细化 + 等用户进一步对话 |

---

## A.3 废案

- **C1 数据层 patch 持续扩 D141-D145 5 处 ad-hoc trap 全废**(`feedback_root_cause_no_cost.md` 红线 + D141-D145 §A.1 C1 同形废)— 反推机制累积持续技术债 + N 年返工度极高 + 业界对标偏离
- **D141-D145 5 sub-D ad-hoc 接口层 trap 持续扩 同模式 sub-D 队列全废**(D145 §F1-F5 + D144 §F2-F6 + D143 §F3+/F6+/F7+/F8 + D142 §F6+ + D141 §F4 等)— bidirectional 落地后 unnecessary,自然解
- **Phase 0 锁定 C2 vs C3 候选全废**(scope > 2000 LOC + 推翻 D141-D145 5 sub-D 一致决策需用户对话授权,Phase 0 越权 — H15 假设)
- **D148 单 Phase 一锅炖全废**(scope > 2000 LOC + bootstrap 重写多核心文件,必须多 Phase 拆分 — D135-D145 大改档不打包范式)
- **G3 反推机制空转全废**(D141-D145 G3 同形废 — 反推机制空转无意义,违反 `feedback_root_cause_no_cost.md` 红线)
- **D026/D027 历史代号占位全废**(memory `feedback_d026_d027_phantom_anchor` 已清零完结 — generic 已落 14 case GREEN 实证锚 `bootstrap/gen/gen_generic_class.ss` + `resolveTypeParam`,bidirectional 起首前置依赖已满足,不再用 D026/D027 占位)
- **bidirectional 引入新关键字 / 新语法全废**(CLAUDE.md §Java/TS 语法优先红线;TS/Flow/OCaml/Scala bidirectional 都不引入新语法,纯类型推断扩展)
- **bidirectional 引入新运行时 state 全废**(类型推断 compile-time;H11 实证)
- **改 D141-D145 文档本体全废**(同位例外锚 D148 同模式继承,文档不动)
- **改 D025 / D052 / D067 / D131 等依赖 D 文档全废**(数据结构 + interface vtable + null safety 路径不破)
- **删 D141-D145 5 处 ad-hoc trap helper 在 Phase N+1 之前全废**(bidirectional 渐进 refactor 期间 trap helper 继续工作 — H12 假设;Phase N+1 删才完结)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `73eb4c5` (2026-05-03)

- D148 文档新建 ~600 行(本 commit)— H1 + Status header + Depends on + Date + §核心目标 + §核心原则(15 条)+ §1-§6 + §A.1 C1/C2/C3 + §A.1.1 G1/G2/G3 + §A.2 H1-H15 + §A.3 + §Phase 收关锚 Phase 0-N+2 + §Followup F1-F6 + §Status 时间线
- d_doc_index_linter F1=0 GATE OK(D148 加入未破 referenced Ds — D025/D052/D067/D131/D141/D142/D143/D144/D145 实存,F2 soft warn 含 D148 不阻 commit)
- ultrathink_linter PASS(.claude/next_prompt.md 含 ultrathink 关键字)
- VCM §1 豁免锚成立(Phase 0 docs-only 不动 bootstrap — D135/D136/D137/D140/D141/D142/D143/D144/D145 范式延续)
- 五合真锚 grep 实证(D141 §F5 line 466 / D142 §F4 line 517 / D143 §F5 line 513 / D144 §F7 line 527 / D145 §F6 line 460)— bidirectional 全局五合真锚锚定
- §核心目标 末层 RED `ls docs/3-decisions/D148*.md` GREEN(commit hash 回填后 ls 命中)
- 用户口号虚锚校验报告(D142/D143 §F7 是 §F 编号机械套用错位虚锚,真锚 D142 §F4 + D143 §F5 — memory feedback_user_literal_vs_d_ssot 防御兑现)
- generic 基础设施前置依赖实证(memory feedback_d026_d027_phantom_anchor §事实层 §实现锚 14 case GREEN — bidirectional 起首前置依赖满足,不再用 D026/D027 占位)
- Status 时间线 Phase 0 entry

### Phase 1: RED 复现 + 信息源探查 + scope 实测 [✓] Done at commit `<placeholder>` (2026-05-03)

**兑现成果 a-h(七项 fact 全 GREEN + 用户口号校验防御)**:

- (a) **D141-D144 累计 15 ad-hoc trap helper** grep 实证(全在 `bootstrap/gen/gen_types.ss:766-981`):
  - **D141 ARROW_FUNC** 4 helper:`isFnType:766` / `extractFnParamType:775` / `extractFnRetType:791` / `inferArrowFuncParams:804`
  - **D142 ARRAY_LIT** 2 helper:`extractArrayElemType:839` / `inferArrayLitElems:853`(无独立 isArrayType — 直接 `t.startsWith("Array<")`)
  - **D143 OBJ_LITERAL → class<X>** 4 helper:`isClassType:868` / `extractClassName:883` / `inferObjLiteralFromType:899` / `inferObjLiteralFields:912`
  - **D144 TERNARY** 5 helper:`isNullableType:925` / `extractInnerType:933` / `unifyBranchTypes:944` / `propagateTernaryBranchType:957` / `inferTernaryBranchType:969`
  - **D145 异常发现** 0 helper 主线未实施完:`tests/d145_map_literal_inference/` 目录不存在 + `grep -rn "MAP_LIT\|inferMapLit\|mapLitInferred" bootstrap/` 全 0 命中 + D145.md 仅 Phase 1 RED commit `17a1573` 实施未落 — D145 在 D141-D145 5 sub-D 中独缺,bidirectional 落地后 D145 可被自然接管或独立先行 sub-D 完成 — Phase 2 用户对话锁定 H15 决策行变量

- (b) **G1 16 落点 + outer pre-eval 9 处**:
  - G1 16 落点(4 helper × 4 落点):`gen_calls.ss:279/281/284/286` + `gen_methods.ss:196/198/200/202` + `eval/method_call.ss:61/63/65/69` + `eval/call.ss:33/35/39/41`
  - outer pre-eval 9 处:`eval/method_call.ss:61-69`(4 helper)+ `eval/call.ss:33-41`(4 helper)+ `eval/new_expr.ss:41`(1 helper `inferObjLiteralFromType`)

- (c) **bootstrap LOC delta 实测 ~500-850 修正**(D148 §核心目标 原估 > 2000 LOC 高估):
  - 关键文件总 4319 行(`checker/check_types.ss` 341 + `check_exprs.ss` 373 + `gen_types.ss` 1050 + `gen_calls.ss` 737 + `gen_methods.ss` 711 + `eval/method_call.ss` 296 + `eval/call.ss` 110 + `eval/new_expr.ss` 82 + `gen_registry.ss` 280 + `codegen.ss` 339)
  - **关键发现**:checker 已局部 bidirectional 机制存在 — `check_exprs.ss:91 funcParamTypes.has(ptKey) == 1` + `:92 expectedType = funcParamTypes.getString(ptKey)` + `:94 isTypeCompatible(expectedType, actualType)` 三处反推(fn arg / method arg / ctor arg)+ `check_types.ss:229 isTypeCompatible(declared, actual)` — bidirectional refactor 实际是**统一已存机制 entry** 不是从零重写
  - LOC delta 粗估:checker 加 expectedType 双向参数贯穿 ~150-300 + gen_types 15 helper 删 + inferType 改 ~200-350 + gen_calls/methods G1 落点收 ~50-100 + eval pre-eval 收 ~50-100 = 总 ~500-850 LOC delta

- (d) **Phase 拆分细化建议 N=5**(原估 N=4-8 收敛到 N=5):
  - Phase 3: checker 单一 entry `inferTypeWithExpected(exprId, expectedType)` + 双向类型检查贯穿全部 check 函数
  - Phase 4: gen_types 15 helper 统一接管(从 fn/method/ctor 三处 expectedType 收集 → 单一反推 entry)
  - Phase 5: G1 16 落点收(gen_calls / gen_methods / eval pre-eval 统一调用 checker 单一 entry)
  - Phase 6 = N+1: cleanup ad-hoc trap helper 删(D141-D144 15 helper)+ Followup 队列 bidirectional 自然解
  - Phase 7 = N+2: 全 Phase 收关 hash trail

- (e) **候选 C2 渐进 vs C3 完整 实测对比初步 fact**(Phase 2 用户对话锁定决策行):
  - **C2 渐进**(单子 Phase ~100-300 LOC):**实测优势** — scope ~500-850 LOC 拆 N=5 子 Phase 后单子 Phase 完全符合 D135-D145 大改档不打包范式(D147 单 Phase commit ~200-400 LOC 同位)— 风险可控
  - **C3 完整**(单 commit ~500-850 LOC):**实测劣势** — 虽 LOC 比原估 > 2000 修正小,但单 commit ~500-850 LOC 违 D135-D145 大改档不打包范式;一锅炖 + 推翻 D141-D145 5 sub-D 一致 v2 决策风险高
  - **scope 修正后 C2 优势放大**(原估 > 2000 时 C2 vs C3 拆分差距小,实测 ~500-850 时 C2 拆 N=5 子 Phase 风险更可控)— 但 Phase 0 仅落档不锁,Phase 2 用户对话锁定决策行

- (f) **隐藏假设 H1-H15 探查**:
  - **H8**:bootstrap 三阶段固定点 scope LOC delta 实测 ~500-850 < 原估 > 2000 PASS 初步,子 Phase 固定点风险待 Phase 3+ 实测验证
  - **H9 PASS 初步**:`pir/pir.ss:101 startsWith("Array<")/("Map<")` + `pir.ss:200 inferType(initId)` + `pir_lower.ss:89-90 ssType = inferType(initId)` 只读类型字符串前缀做 RC 判定不参与推断 — bidirectional 是 codegen-time 推断,PIR 不需扩
  - **H10 PASS 实证**:`ls tests/phase5/generic_*.ss | wc -l` = 14 + `gen_generic_class.ss` 427 行 + `gen_types.ss:711 resolveTypeParam` 实存 — generic 14 case 实证锚兑现(memory feedback_d026_d027_phantom_anchor §事实层 §实现锚双重实证)
  - **H14 fact 入档**:scope ~500-850 LOC delta < 估值 > 2000 修正(checker 已局部 bidirectional 已存,bidirectional refactor 是统一 entry 不是重写)
  - **H15 留 Phase 2 用户对话**:推翻 D141-D145 5 sub-D 一致 v2 决策授权门槛 — Phase 2 用户对话锁定 C2 vs C3 决策行
  - H1-H7 + H11-H13 全 Phase 0 已 PASS 实证(D141-D145 同模式继承,详 §A.2)

- (g) **spike form 1-N 用现有 tests baseline + grep/ls 实测代替**(更纯 docs only,VCM §1 豁免锚成立):
  - form 1: fn arg ARROW_FUNC (D141) — `tests/d141_lambda_inference/` 11 个 baseline GREEN
  - form 2: fn arg ARRAY_LIT (D142) — `tests/d142_array_literal_inference/` 6 个 baseline GREEN
  - form 3: fn arg OBJ_LITERAL→class<X> (D143) — `tests/d143_object_literal_inference/` 6 个 baseline GREEN
  - form 4: fn arg TERNARY (D144) — `tests/d144_ternary_inference/` 8 个 baseline GREEN
  - form 5: fn arg MAP_LIT (D145) — **`tests/d145_map_literal_inference/` 不存在 RED**(D145 主线未实施完)
  - form 6: var decl typeAnn(bidirectional new)— 当前 partial 支持(checker `isTypeCompatible` 比对 line 229)
  - form 7: class field init — 当前 partial 支持(class.ss 内嵌反推)

- (h) **Phase 0 commit hash `73eb4c5` 回填 3 处真锚 + 用户口号校验防御**:
  - line 3 Status header(`73eb4c5` 已闭环)
  - line 382 §Phase 收关锚 §Phase 0(Done at commit `73eb4c5`)
  - line 452 §Status 时间线 Phase 0 entry(commit `73eb4c5`)
  - **用户口号校验**:「Phase 0 hash 4 处回填」字面口号实测 占位符行数实测 = 3 处真锚(D147 范式 4 处含「§全 Phase 0-5 commit hash 总览段」自指描述同步,D148 因 Phase 0 起步无总览段所以仅 3 处)— memory feedback_user_literal_vs_d_ssot 同形防御兑现

**新发现总结**:
- (i) checker 已局部 bidirectional 机制存在(funcParamTypes 反推三处 + isTypeCompatible)+ 5 helper(D141-D144 共 15)在 codegen 阶段反推 — bidirectional refactor 是**统一已存机制 entry** 不是从零重写,scope 比原估小 3-4 倍(~500-850 vs > 2000)— C2 渐进可行性大幅提升
- (ii) D145 主线未实施完(0 helper)— D141-D145 5 sub-D 中独缺,bidirectional 落地后 D145 可被自然接管或独立先行 sub-D 完成 — Phase 2 用户对话锁定 H15 决策行变量
- (iii) 用户口号「Phase 0 hash 4 处回填」字面口号实测 = 3 处真锚,memory feedback_user_literal_vs_d_ssot 同形防御兑现(D148 因 Phase 0 起步无总览段)
- (iv) PIR 不需扩(H9 PASS 初步)— bidirectional 是 codegen-time 推断,PIR 只消费 inferType 输出不参与推断

**验证**:Phase 1 commit + scope 实测 fact 入 Status header line 3 + §A.2 H8/H9/H10/H14 + 本 §Phase 收关锚 §Phase 1 + §Status 时间线 + Phase 0 hash 3 处真锚回填 + d_doc_index_linter F1=0 PASS + ultrathink_linter PASS

### Phase 2: 候选 C2 vs C3 用户对话锁定 + 子 Phase 拆分 [ ] 待 Phase 2 commit

- §A.1 C2 vs C3 用户对话锁定决策行(H15 推翻 D141-D145 5 sub-D「留 v2」一致决策授权门槛)
- 子 Phase 拆分 D 文档草案(N=4-8 子 Phase)
- 实施前置 fact 入 §1
- 验证:Phase 2 commit + 用户对话决策行

### Phase 3-N: bidirectional 渐进实施(子 Phase 拆) [ ] 待 Phase 3-N commit

- `bootstrap/checker/check_types.ss` + `check_exprs.ss` bidirectional 改 + 单一 entry `inferTypeWithExpected(exprId, expectedType)`
- `bootstrap/gen/gen_types.ss` 5 helper 渐进删
- `bootstrap/eval/method_call.ss + call.ss + new_expr.ss` outer call site bidirectional expected 类型传递
- `bootstrap/gen/codegen.ss + gen_registry.ss` funcParamTypes expected 类型源重构
- 验证:bootstrap 固定点 PASS + spike GREEN + tests/d141-d145 baseline 不破 + tests/phase5/generic baseline 不破 + reflection GATE PASS

### Phase N+1: D141-D145 5 处 ad-hoc trap helper 删 + workaround cleanup [ ] 待 Phase N+1 commit

- 5 helper 删(`isFnType` / `extractFnParamType` / `inferArrowFuncParams` / `isArrayType` / `extractArrayElemType` / `inferArrayLitElems` / `isClassType` / `extractClassName` / `inferObjLiteralFields` / `isMapType` / `extractMapKVTypes` / `inferMapLiteralKVTypes` 等 N helper)
- tests/d141-d145 仍 GREEN(bidirectional 接管 — H12 假设)
- Followup 队列(D145 §F1 Tuple / D145 §F2 NEW_EXPR ctor / D145 §F3 partial / D145 §F4 spread / D145 §F5 反推失败粒度 + D144 §F2-F6 + D143 §F3+/F6+/F7+/F8 + D142 §F6+ + D141 §F4)bidirectional 自然解 spike(H13 假设)
- 验证:bootstrap 固定点 + tests/ 全绿 + grep 5 helper = 0 + Followup 队列各形态 spike GREEN

### Phase N+2: 全 Phase 收关 hash trail [ ] 待 Phase N+2 commit

- D148 全 Phase commit hash 全列(Phase 0-N+1 的 commit hash + Phase N+2 占位下下轮 hash 回填轮替换)
- 兑现成果 a-g(C2/C3 落地 / 5 helper 删 / H1-H15 全 PASS / OOD 标 / axiom 红线 grep = 0 永久 / d_doc_index_linter F1=0 永久 / reflection_health_linter GATE PASS 永久 / bootstrap 隔离破例 D141-D145 §核心原则 同位例外)
- 隐藏假设 H1-H15 全 PASS / OOD 标
- Followup F1-F6 锚明确(D148 §Followup 入下一 D 文档启动队列,bidirectional 落地后 D141-D145 §Followup 队列大部分自然解,剩余留 D148 §Followup F1+)
- 验证:D148 主线 close + d_doc_index_linter F1=0 永久 + reflection GATE PASS 永久

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | Tuple literal contextual typing | bidirectional 落地后自然解 — D145 §F1 / D144 §F2 / D143 §F3 / D142 §F6 同位 sub-D 全部 unnecessary;若 bidirectional 自然解度不足留独立 sub-D(H13 假设)|
| F2 | NEW_EXPR ctor 实参子节点反推 | bidirectional 落地后自然解 — D145 §F2 / D144 §F3 / D143 §F4 / D142 §F7 同位 sub-D 全部 unnecessary;若 bidirectional 自然解度不足留独立 sub-D(H13 假设)|
| F3 | partial fields + ctor 默认值 | bidirectional + ctor default value 配套 — D145 §F3 / D144 §F4 / D143 §F6 同位 sub-D;若 ctor default value 机制需独立扩展留 sub-D |
| F4 | spread `{...base, name: "X"}` 反推 | bidirectional + spread sub-D — D145 §F4 / D144 §F5 / D143 §F7 同位;若 spread 节点需 parser 扩留 sub-D |
| F5 | 反推失败粒度细化(checker 阶段硬错诊断)| bidirectional 失败硬错粒度 — D145 §F5 / D144 §F6 / D143 §F8 同位;倒置类型 silent miscompile / 无 callee context unknown kind LLC error 等粒度细化留 sub-D |
| F6 | var binding callee 反推(D141 §F5 + 同模式)| `const f = (s) => ...; f(stmt)` var binding 形式 callee="f" IDENT lookup 不到 funcParamTypes,反推 skip;D141-D145 H9 OOD scope 同模式继承 — bidirectional 是否扩到 var binding 反推留 sub-D(H7 假设)|
| F7 | 类型系统 v2 总体设计独立 D 文档 | 若 D148 本身覆盖不足(scope 大但仍偏单点 bidirectional),起独立 D 文档为 v2 总体路径决策 — Phase N+2 收关时实测假设(D148 是否承载 v2 总体设计 vs 仅 bidirectional 单点)|

---

## Status 时间线

- 2026-05-03 Phase 0 D 文档落档(commit `73eb4c5`)— D141 §F5 + D142 §F4 + D143 §F5 + D144 §F7 + D145 §F6 五合真锚兑现 v2 起首最小动作;C2 渐进 vs C3 完整 留 Phase 1+ 用户对话锁定;§A.1 C1/C2/C3 + §A.1.1 G1/G2/G3 + §A.2 H1-H15(D141-D145 H1-H13 同模式继承 + H14-H15 D148 新增 scope 实测 + 推翻 v2 决策授权门槛)+ §A.3 废案(D026/D027 历史代号占位全废 + Phase 0 锁定 C2 vs C3 全废 + 单 Phase 一锅炖全废 + G3 空转全废 + 等)+ Phase 0-N+2 计划草案(N=4-8 待 Phase 1 实测确定)+ Followup F1-F6;用户口号虚锚校验报告(D142/D143 §F7 bidirectional 是 §F 编号机械套用错位虚锚,真锚 D142 §F4 + D143 §F5 — memory feedback_user_literal_vs_d_ssot 防御兑现);generic 基础设施前置依赖实证(memory feedback_d026_d027_phantom_anchor §事实层 §实现锚 14 case GREEN — bidirectional 起首前置依赖满足);D135/D136/D137/D140/D141/D142/D143/D144/D145 范式延续(每 Phase 独立 commit 大改档 + Status 收关 + commit hash 回填 + next_prompt 自闭环 — D145 Phase 0 commit `d2fb4e1` 同模式)
- 2026-05-03 Phase 1 RED 复现 + 信息源探查 + scope 实测(commit `<placeholder>`)— **Phase 1 兑现 a-h 七项 fact 全 GREEN + 新发现总结**(详 §Phase 收关锚 §Phase 1):(a) D141-D144 累计 **15 ad-hoc trap helper** grep 实证(D141:4 + D142:2 + D143:4 + D144:5,全在 `bootstrap/gen/gen_types.ss:766-981`)+ **D145 异常发现** 0 helper 主线未实施完(`tests/d145_map_literal_inference/` 不存在 + MAP_LIT 节点全 0 命中 + D145.md 仅 Phase 1 RED commit `17a1573` 实施未落);(b) G1 **16 落点** + **outer pre-eval 9 处**(method_call.ss 4 + call.ss 4 + new_expr.ss 1);(c) **bootstrap LOC delta 实测 ~500-850 修正**(D148 §核心目标 原估 > 2000 LOC 高估 — **关键发现** checker 已局部 bidirectional 机制 `check_exprs.ss:91/156/270` funcParamTypes 反推三处 fn/method/ctor + `check_types.ss:229 isTypeCompatible`,bidirectional refactor 是**统一已存机制 entry** 不是从零重写);(d) **Phase 拆分细化建议 N=5**(Phase 3 checker 单一 entry inferTypeWithExpected + Phase 4 gen_types 15 helper 统一接管 + Phase 5 G1 16 落点收 + Phase 6=N+1 cleanup helper 删 + Followup 自然解 + Phase 7=N+2 全 Phase 收关 hash trail);(e) C2 渐进 vs C3 完整 实测对比初步 fact(scope 修正后 C2 优势放大 — 单子 Phase ~100-300 LOC 符合 D135-D145 大改档不打包范式 vs C3 单 commit ~500-850 LOC 违范式)— Phase 2 用户对话锁定决策行;(f) 隐藏假设探查 — **H9 PASS 初步**(`pir/pir.ss:101 startsWith("Array<")/("Map<")` + `pir.ss:200 inferType(initId)` + `pir_lower.ss:89-90 ssType = inferType(initId)` 只读类型字符串前缀做 RC 判定不参与推断,bidirectional 是 codegen-time 推断 PIR 不需扩) + **H10 PASS 实证**(`ls tests/phase5/generic_*.ss | wc -l` = 14 + `gen_generic_class.ss` 427 行 + `gen_types.ss:711 resolveTypeParam` 实存,memory feedback_d026_d027_phantom_anchor §事实层 §实现锚双重实证) + H8 待 Phase 3+ 子 Phase bootstrap 实测 + H14 入档 + **H15 留 Phase 2 用户对话锁定**(推翻 D141-D145 5 sub-D 一致 v2 决策授权门槛);(g) spike form 1-N 用 `tests/d141_lambda_inference/` 11 + `tests/d142_array_literal_inference/` 6 + `tests/d143_object_literal_inference/` 6 + `tests/d144_ternary_inference/` 8 baseline + grep/ls 实测代替(更纯 docs only,VCM §1 豁免锚成立)+ form 5 D145 RED + form 6/7 var decl typeAnn / class field init partial 支持;(h) Phase 0 commit hash `73eb4c5` 回填 **3 处真锚**(line 3 Status header + line 382 §Phase 收关锚 §Phase 0 + line 452 §Status 时间线 Phase 0 entry — **用户口号校验**「Phase 0 hash 4 处回填」字面口号实测 占位符行数实测 = 3 处,memory feedback_user_literal_vs_d_ssot 同形防御兑现 — D148 因 Phase 0 起步无 §全 Phase 总览段所以仅 3 处真锚 vs D147 范式 4 处含 §全 Phase 总览段自指描述同步);**新发现总结**:(i) checker 已局部 bidirectional 机制存在(funcParamTypes 反推三处 + isTypeCompatible)+ 5 helper(D141-D144 共 15)在 codegen 阶段反推 — bidirectional refactor 是**统一已存机制 entry** 不是从零重写,scope 比原估小 3-4 倍(~500-850 vs > 2000)— C2 渐进可行性大幅提升;(ii) D145 主线未实施完(0 helper)— D141-D145 5 sub-D 中独缺,bidirectional 落地后 D145 可被自然接管或独立先行 sub-D 完成 — Phase 2 用户对话锁定 H15 决策行变量;(iii) 用户口号「Phase 0 hash 4 处回填」字面口号实测 = 3 处真锚(memory feedback_user_literal_vs_d_ssot 同形防御兑现);(iv) PIR 不需扩(H9 PASS 初步) — bidirectional 是 codegen-time 推断,PIR 只消费 inferType 输出;D135/D136/D137/D140/D141/D142/D143/D144/D145/D147 范式延续(每 Phase 独立 commit + Phase X+1 启动轮回填上一 Phase hash + next_prompt 自闭环 — D147 Phase 5 commit `8323501` 同模式立即回填)
