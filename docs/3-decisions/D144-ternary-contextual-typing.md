# D144: SS Ternary Contextual Typing — 三元分支类型从调用上下文反推

**Status:** Phase 4 — workaround cleanup [✓] Done at commit `<placeholder>` (2026-04-28)— docs-only 降级(grep 实测 0 命中,D143 Phase 4 commit `b0f046c` 同范式锚);Phase 3 commit `959a2de` Phase 2 commit `71af131` Phase 1 commit `17a1573` Phase 0 commit `02415c9` 全锚回填;D141 §Followup F3 / D142 §Followup F2 / D143 §Followup F1 同模式合并锚扩到 TERNARY 节点(`cond ? a : b` 在 fn 实参 `int?` / `User?` / `class<T>` 等可空 / 结构化 callee 形参时反推两分支统一类型);D141 反推机制 + D142 elemType 反推机制 + D143 className 反推机制同模式扩到 TERNARY — callee PARAM 已结构化 SSoT 复用 + codegen 阶段反推 + eval pre-eval 时序前移 + funcParamTypes 信息源单点;比 D143 略轻 — TERNARY 反推目标不是字段 list 而是两分支(then/else)各自统一类型(信息流向是 callee.expectedType → 两分支 inferType,与 D141/D142/D143 callee.expectedType → 节点 slot 同模式)
**Depends on:**
- D141(lambda 参数类型推断 + interface dispatch 集成 — §Followup F3 line 422 同位锚)
- D142(array literal contextual typing — §Followup F2 line 484 + line 514 同位锚)
- D143(object literal contextual typing — §Followup F1 line 414 同模式合并锚)
- D141 §A.1.1 G1 路径 + D142 §A.1.1 G1 路径 + D143 §A.1.1 G1 路径(callee PARAM 结构化签名 + codegen 阶段反推 + eval pre-eval 时序)— D144 G1 同模式复刻
- D141 §A.2 H1/H10/H11/H13 + D142 §A.2 H1-H13 + D143 §A.2 H1-H13(funcParamTypes 时序 / setVarType 自然链路 / callee 结构化必要 / 失败硬错粒度 / cross-D 反推时序验证)— D144 同模式假设挑战
- D025(interface dispatch — 分支值是 interface 实现类时 vtable 路径)
- D067(null safety — Kotlin/Dart 风格 `T?` 可空类型 + null literal 默认非空收紧;D144 主线场景 `cond ? null : x` 在 `int?` callee 反推统一)
- D131(`Array<T?>` nullable inner field 反序列化 + stripNullableCG 路径 — 分支值含 nullable inner 时不破契约)
- `bootstrap/checker/check_exprs.ss:TERNARY case`(待 Phase 1 探查精确 line 号)— TERNARY checker 入口
- `bootstrap/parse/parse_exprs.ss:TERNARY parser`(待 Phase 1 探查精确 line 号)— TERNARY AST 节点构造(`?`/`:` 分支)
- `bootstrap/checker/check_types.ss:inferType TERNARY case`(待 Phase 1 探查精确 line 号)— TERNARY inferType 路径
- CLAUDE.md §Java/TS 语法优先(TS ternary contextual typing 主线 — `const x: number | null = cond ? null : 5` 当前 TS 已反推;Java 8+ ternary 自动 widen 类型推断同形)
- CLAUDE.md §Root Cause 优先 第一法则(数据层 patch 不允许,接口层 trap 单点信息源)
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优的理由)
- `memory/feedback_no_option_menu.md`(三候选论证 + 决策行)
- `memory/feedback_no_derive_workaround.md`(主线能力缺口不允许 annotation 替代)
- `memory/feedback_h10_cross_d_verify.md`(H10 cross-D 反推时序验证 — D143 实证教训:不可仅 grep 字面 handler,outer call site 通用 pre-eval `genVal(argId)` 才是反推时序关键)
- `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验 (Plan 型 §④ 替换「替代方案对比 + 隐藏假设挑战」)+ §字段 8 "Layer 跨越触发 stop / D 文档独立审查窗口不许吞"

**Date:** 2026-04-27
**Last Updated:** 2026-04-27

---

## 核心目标 (Goal)

- **为什么**:ternary 表达式 `cond ? a : b` 当前 checker `check_exprs.ss:TERNARY case` 入口走 then/else 分支独立 inferType + 两分支类型一致性检查 — 在 fn 实参 `n: int?` 场景反推不到 callee 期望类型 → `cond ? null : 5` 的 `null` 分支与 `5` 分支类型不一致(`null` 当前默认 ptr / 5 当前 int)→ checker 硬错或 silent fallback;D067 null safety 落地后 `T?` 可空类型已结构化(`int?` / `User?` 等),但 ternary 与 nullable callee 结合的反推链路缺失;同样在 fn 实参 `class<User>` 期望 + `cond ? new User("X", 18) : new User("Y", 20)` 显式 callee 已 OK,但 `cond ? null : new User("X", 18)` 反推到 `User?` 期望需 contextual typing。D141 §Followup F3 + D142 §Followup F2 + D143 §Followup F1 锁此 follow-up 是反推机制同模式扩到 TERNARY 的合并锚。**末层断言可观测否定证据**(本 Phase 0 实测):`ls docs/3-decisions/D144*.md 2>&1` 当前 = `No such file or directory`(exit=2)— D144 文档落档 RED 成立,本轮 Phase 0 GREEN(commit hash 回填后 `ls` 命中)。
- **是什么**:在 ternary 作 fn/method 实参时,从 callee 签名查 `funcParamTypes` 反推 TERNARY 节点 branchType 期望(callee 形参类型字符串 `int?` / `User?` / `Array<int>` 等)+ 两分支 then/else 各自 contextual checkExpr(参 D141 H1 实证 — checker 阶段 funcParamTypes 用户函数为空,反推必须在 codegen 阶段;参 D141 H10 + D142 H10 + D143 H10 实证 — eval pre-eval 在 TERNARY emit 之前,反推必须前移到 outer call site 通用 pre-eval `genVal(argId)` 之前);后续 codegen `genTernary` 内消费 branchType slot + 两分支按 branchType 走 widen / null literal 默认收紧路径,链路自然走通。配合 `check_exprs.ss:TERNARY case` 改返 `branchType` 结构化签名(类型表达力前置,与 ARROW_FUNC `fn(P,...):R` + ARRAY_LIT `Array<elemType>` + OBJ_LITERAL `class<ClassName>` 结构化前置完全同形)。
- **单一判据**:untyped ternary spike(写 `takesNullableInt((x > 0) ? null : 5)` 直接传入 fn 形参 `n: int?`)= D144 §第一性需求 末层断言 RED → 根因修后实测 spike GREEN(对照 IR null literal 走 `null int*` 不变 + `5` 分支 widen 到 nullable int* + ternary phi node 统一 i32* 路径正确,无 silent miscompile 不破 D067 null safety 契约);且 lib/ + tests/ 现存 fn 实参 ternary workaround(若有 `let n: int? = (x > 0) ? null : 5; takesFn(n)` 临时绑定形态)Phase 4 cleanup 全删。

> 一句口号:**ternary 两分支类型从调用上下文反推 — 用户不必每处临时绑定带类型注解的变量**(D141 反推机制 + D142 elemType 反推机制 + D143 className 反推机制同模式扩到 TERNARY)

---

## 核心原则 (Principles)

1. **接口层 trap,非数据层 patch** — 信息源单点回填(eval pre-eval 阶段 TERNARY 节点 branchType slot),codegen 路径不变;不在 genTernary / gen_calls.ss / check_types.ss 多处零散补 fallback(`feedback_root_cause_no_cost.md` 红线)
2. **D141/D142/D143 反推机制同模式扩** — eval pre-eval 时序 + funcParamTypes 信息源 SSoT + codegen 阶段反推 + 失败硬错粒度均沿 D141/D142/D143 §A.1.1 G1 路径;D141 §A.2 + D142 §A.2 + D143 §A.2 假设挑战范式直接复刻
3. **bidirectional type checking 局部** — 仅 ternary 作 fn/method 实参 + class field init / var decl typeAnn 反推场景,不扩到全编译器全表达式 contextual typing(scope 防爆炸,与 D141 §核心原则 2 + D142 §核心原则 3 + D143 §核心原则 3 同位)
4. **TS / Java 8+ contextual typing 主线** — TS 既有能力(`fn arg ternary inferred from param type`)+ Java 8+ ternary 自动 widen 类型推断;TS `const x: number | null = cond ? null : 5` 等价能力前置
5. **D067 null safety 路径复用** — D067 已落 `T?` nullable 类型 + null literal 默认非空收紧;D144 反推得 callee `T?` 后两分支按 nullable widen / null literal 类型化路径走原 D067 机制(无重写)— null literal 在 ternary 分支当 callee = `T?` 时走 D067 nullable 分配,callee = `T` 非空时硬错(参 D067 §第一性需求)
6. **callee PARAM 已结构化(无需 G1 callee 升级)— 比 D143 弱** — D141 G1 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn`(parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析);D142 callee `Array<T>` 已结构化无升级前置;D143 callee `class X` 已结构化 + parser 已就绪(class 名 IDENT 单 token);D144 callee `int?` / `User?` / `T?` 已结构化(D067 已落 `T?` 类型 annotation 解析)+ class IDENT / Array<T> / Map<K,V> 等结构化 callee 全已就绪 — Phase 2 不需要 parser 扩
7. **bootstrap 隔离破例** — D141 §核心原则 5 + D142 §核心原则 6 + D143 §核心原则 7 同位例外,D144 主线改 bootstrap 修编译器(checker + codegen + eval),与其他 sub-D scope 独立
8. **interface dispatch 不破** — D025 `interface IFoo` 契约 + vtable indirect dispatch 路径不动;分支值 class instance 走 NEW_EXPR 路径不变
9. **funcParamTypes SSoT 复用** — 信息源 `bootstrap/gen/gen_registry.ss:9-10 + 56`(`funcParamTypes` Map "funcName:paramIndex" → SS type,含 `T?` / `class X` / `Array<T>` 等结构化签名),codegen 阶段反推时直接消费,不重复注册
10. **零破坏既有 ternary** — 现存 ternary 路径(显式两分支同类型 `cond ? new User("X") : new User("Y")` 等)继续走原 then/else 独立 inferType + 两分支类型一致性检查路径,Phase 2 反推仅在 ternary 作 fn/method 实参 + branchType 期望未匹配时 fallback 反推,显式优先级 > 推断
11. **Phase 计划独立 commit** — 大改档位:Phase 0 D 文档落盘 + Phase 1+ bootstrap 改各独立 commit,§MNK 大改档不打包(D135/D136/D137/D140/D141/D142/D143 范式延续)
12. **VCM 六验全跑** — bootstrap 三阶段固定点 + tests/ 不降 + tests/d067_null_safety/ 等 D067 baseline 不降 + reflection_health_linter GATE PASS no regressions
13. **null safety 反推 H10 cross-D 反思继承** — D143 H10 教训(`feedback_h10_cross_d_verify.md`)— Phase 1 探查 ternary eval 时序时不能仅 grep 字面 handler `evalTernary`,必须确认 outer call site 通用 pre-eval `genVal(argId)` 是否在 ternary 子节点 emit 之前,反推必须前移到 outer call site

---

## 1. Context Management

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D144)
2. CLAUDE.md §Java/TS 语法优先 + §Root Cause 优先 第一法则 + §高层架构 + §交互式单文档
3. 依赖 D 文档:
   - D141 §A.1.1 G1 路径 + §A.2 H1/H10/H11/H13(line 200-209 + 217-230)
   - D142 §A.1.1 G1 路径 + §A.2 H1-H13(全 PASS)
   - D143 §A.1.1 G1 路径 + §A.2 H1-H13(全 PASS,H10 cross-D 反思 memory `feedback_h10_cross_d_verify.md` 落档)
   - D141 §Followup F3(line 422)+ D142 §Followup F2(line 484 + 514)+ D143 §Followup F1(line 414)— D144 入口同模式合并锚
   - D025 interface dispatch
   - D067 null safety(`T?` nullable + null literal 默认收紧)
4. 关键代码位置(Phase 1 探查后精确化 line 号):

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/parse/parse_exprs.ss` | **13-16** | TERNARY parser:`parseExpr` 顶级表达式入口 line 6-20 ternary 构造 — `newNode("TERNARY")` + `nSetI1(id, left)`(cond)+ `nSetI2(id, thenId)` + `nSetI3(id, elseId)`;**占用 i1/i2/i3,空闲 s1/s2/s3/i4 + nList** — Phase 2 选 **nSetS2** 存 branchType(D141 ARROW_FUNC PARAM s2 + D142 ARRAY_LIT s2 + D143 OBJ_LITERAL s2 同范式) |
   | `bootstrap/checker/check_exprs.ss` | **304-309** | TERNARY case `if (kind == "TERNARY") { checkExpr(nGetI1) + checkExpr(nGetI2) + checkExpr(nGetI3) }` — **当前破裂入口 1**:无两分支类型一致性检查 → silent miscompile(X mismatch RED 入口);Phase 2 改 — 加两分支类型一致性 / 反推 branchType 结构化 |
   | `bootstrap/checker/check_types.ss` | **201** | TERNARY inferType `return checkerInferType(nGetI2(nodeId))` — **当前破裂入口 2**:仅返 then 分支 inferType,信息丢失(字段访问 / phi llType 链路错位);Phase 2 改:优先读 `nGetS2(id)` branchType,fallback `inferType(nGetI2)`(对偶 D143 OBJ_LITERAL line 544-551 模式) |
   | `bootstrap/gen/gen_types.ss` | **541** | codegen inferType `if (kind == "TERNARY") { return inferType(nGetI2(id)) }` — 与 checker 同形单一 then 分支(X4-1 字段访问 RED 入口);**Phase 2 改入口**:对偶 D143 OBJ_LITERAL line 544-551 模式,优先读 `nGetS2(id)` fallback then 分支 inferType |
   | `bootstrap/gen/exprs/exprs.ss` | **68** | TERNARY genVal dispatch — 走 evalExpr → evalTernary 路径 |
   | `bootstrap/gen/codegen.ss` | **110-112 + 326** | 普通函数 funcParamTypes 注册 line 110-112 `funcParamTypes.set(\`${fname}:${pCount}\`, nGetS2(fpId))`(含 `User?` / `Array<int>?` / `class X` 结构化签名)+ line 326 `registerAllDecls(rootId)` 在 line 327 `emitGlobalsAndCode(rootId)` 之前 — H1 实证 PASS,Phase 2 不改注册路径 |
   | `bootstrap/gen/gen_registry.ss` | **56-57** | class method funcParamTypes 注册 — H1 实证 PASS,Phase 2 不改 |
   | `bootstrap/eval/method_call.ss` | **36-70** | outer call site pre-eval — D141/D142/D143 反推前移落锚 line 61(inferArrowFuncParams)+ line 63(inferArrayLitElems)+ line 65(inferObjLiteralFields);**Phase 2 D144 同点追加 line 67** `inferTernaryBranchType(mcArgIdR, mcResolvedR, mcArgIdxR)` 第 4 行 — 必须在 line 71+ pre-eval `genVal(mcArgId)` 之前 |
   | `bootstrap/eval/call.ss` | **18-43** | outer call site pre-eval — D141/D142/D143 落锚 line 33+35+39;**Phase 2 D144 同点追加 line 40** `inferTernaryBranchType(callArgIdR, callResolvedR, callArgIdxR)` |
   | `bootstrap/eval/new_expr.ss` | **24-41** | ctor args outer call site pre-eval — D143 NAMED_ARG OBJ_LITERAL 嵌套反推 line 27-41;**Phase 2 D144 落点考量**(扩 NEW_EXPR 还是留 §Followup F3 sub-D 后续轮)|
   | `bootstrap/eval/ternary.ss` | **4-33** | evalTernary handler — line 5 cond pre-eval / line 12 `ssTypeToLLVM(inferType(nGetI2(astId)))` 决定 phi llType / line 22+26 两分支 emit;**Phase 2 改 line 12**:phi llType 优先读反推 branchType,fallback 单分支 inferType |
   | `bootstrap/eval/eval_expr.ss` | **64** | evalExpr dispatch `if (k == "TERNARY") { return evalTernary(astId) }` — Phase 2 不改 |
   | `bootstrap/pir/pir_lower.ss` | **252-257** | PIR `pirCollectUsesRec` TERNARY use 分析(三子节点递归)— **Phase 2 不需改**(仅 use 收集不破反推链路)|
   | `bootstrap/checker/check_narrow.ss` | **6** | `primitive type 'int' cannot be nullable` — D067 关键不变量,**`int?` 不合法**(D144 motivating example 修正动因) |
   | `bootstrap/gen/gen_types.ss` | (Phase 2 新加 helper)| **Phase 2 helper 落锚**:`isNullableType` / `extractInnerType` / `unifyBranchTypes` — 对偶 D141 isFnType + D142 isArrayType + D143 isClassType |
   | `/tmp/spike_ternary_red.ss` + `/tmp/spike_ternary_x4_1.ss` + `/tmp/spike_ternary_x_mismatch.ss` | 全文 | **Phase 1 RED 复现**(主线 7 形态 GREEN + X4-1 LLC ptr/i32 mismatch RED + X mismatch silent 双 RED 铁证)|

### Stable Facts

| 项 | 值 |
|---|---|
| 现存 callee `int?` 用例 | **0 处 — D067 不允许 primitive nullable**(`bootstrap/checker/check_narrow.ss:6` 硬错)— D144 motivating example 修正:仅 `User?` / `Array<int>?` 等 reference 类型 nullable 合法 |
| 现存 callee `User?` / `Array<int>?` 用例 | tests/phase5/null_narrowing.ss 多处 + tests/phase5/i021_requestbody_nested_optional_container.ss `scores: Array<int>?` — Phase 4 cleanup 候选 grep 探查留 Phase 4 |
| nullable 类型 annotation 解析 | parser 已就绪(D067 落地后 `T?` annotation 已解析为结构化签名,无嵌套 generic 解析需求) |
| funcParamTypes nullable 注册 | 已就绪 H1 实证 PASS(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57 直接注册原始 SS 类型字符串含 `T?` 后缀,registerAllDecls codegen.ss:326 在 emitGlobalsAndCode 之前)|
| null literal 默认行为 | D067 已落 — null literal 默认 ptr / 期望非空时硬错 / 期望 `T?` 时类型化为 nullable |
| TERNARY inferType 当前 | **check_types.ss:201 + gen_types.ss:541 单一 `inferType(nGetI2(id))` 仅返 then 分支** — D144 §A.1 主候选 C2 修复入口锁定;Phase 2 改入口对偶 D143 OBJ_LITERAL line 544-551 模式优先读 nGetS2 fallback then 分支 |
| TERNARY checker case 当前 | **check_exprs.ss:304-309 仅依次 checkExpr 三子节点,无两分支类型一致性检查** — X mismatch RED 入口 |
| TERNARY 节点 slot 占用 | i1/i2/i3(cond/then/else),s1/s2/s3+i4+nList 全空闲 — Phase 2 选 nSetS2 |
| TERNARY kind dispatch site | 8 处:parse_exprs.ss:13 + check_exprs.ss:304 + check_types.ss:201 + gen/exprs/exprs.ss:68 + gen_types.ss:541 + eval/eval_expr.ss:64 + eval/ternary.ss:4 + pir/pir_lower.ss:252 |
| 反射 baseline | tools/reflection_health_linter.ss(本 D 不触反射) |
| d_doc_index_linter F1 | Phase 1 实测 PASS(`bin/ss run tools/d_doc_index_linter.ss` `GATE OK — 10 referenced Ds all live`,D025/D067/D131/D141/D142/D143 实存,F2 soft warn 含 D144 不阻)|

### 禁止的 Context 操作

- ❌ 改 parser(`T?` annotation 已就绪 D067 落地 — §核心原则 6 + H12 弱)
- ❌ 改 funcParamTypes 注册路径(已就绪 — §核心原则 9)
- ❌ 改 D067 null literal 默认行为本体(已就绪,D144 反推得 callee `T?` 后**复用** D067 nullable 分配路径,不重写)
- ❌ 起 D145+(留 D141 §F3+/D142 §F2+/D143 §F1+ 同模式合并队列,本 D 仅 ternary;D144 §Followup F1+ 排队后续 sub-D)
- ❌ 改 D141/D142/D143 文档本体(D141 §核心原则 5 + D142 §核心原则 6 + D143 §核心原则 7 例外锚 D144 同模式继承,文档不动)
- ❌ 改 D025/D067/D131 interface dispatch / nullable / 反序列化契约
- ❌ 加全局 bidirectional type checking(C3 候选废 — 范围爆炸,留 SS 类型系统 v2)

---

## 2. Tools

| 工具 | 用途 |
|---|---|
| `./build.sh bootstrap` | 三阶段固定点(Phase 1+ bootstrap 改后必跑) |
| `bin/ss run /tmp/spike_ternary_red.ss` | spike RED→GREEN 验证(主判据,Phase 1 写入 + Phase 2 实测) |
| `bin/ss test tests/d067_null_safety/` | null safety baseline 不降 |
| `bin/ss test tests/d141_lambda_inference/` | D141 反推机制 baseline 不破 |
| `bin/ss test tests/d142_array_literal_inference/` | D142 反推机制 baseline 不破 |
| `bin/ss test tests/d143_object_literal_inference/` | D143 反推机制 baseline 不破 |
| `bin/ss test tests/` | 全测 baseline 不降 |
| `bin/ss build /tmp/spike_ternary_red.ss --emit-ir` | IR 层 RED 复现(Phase 1) |
| `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate |
| `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射) |
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ 新关键字 / 新语法 / 新 AST 节点(ternary 反推是反推机制扩展,非语法扩展;TERNARY 节点已存 parse_exprs.ss `parseTernary`)
- ❌ 新依赖
- ❌ 改 codegen 全局 / parser / interpreter / lib(Phase 2 改 checker + 局部 codegen 反推 + eval pre-eval 反推插桩,不重写 D067 null literal 默认行为本体)

---

## 3. Orchestration

### 总体节奏(D141/D142/D143 5 Phase 范式延续)

| Phase | 目标 | 关键产出 | 验证 |
|-------|------|----------|------|
| **Phase 0** | D 文档落档(本 Phase) | `docs/3-decisions/D144-*.md` | d_doc_index_linter F1 = 0 + ultrathink_linter PASS |
| **Phase 1** | RED 复现 + 信息源探查 | `/tmp/spike_ternary_red.ss`(形态 1-7:null+T 反推 T? / T+T 显式 / 嵌套 ternary / class 实例 ternary / interface upcast / 多层 nullable / fn 返回 ternary)+ IR 层 RED 铁证 + funcParamTypes nullable 字符串实测可用(grep 实证)+ ternary eval pre-eval vs codegen emit 时序探查(确认 D141/D142/D143 H10 同形成立 — H10 cross-D 反思 outer call site 通用 pre-eval `genVal(argId)`)+ 隐藏假设 H1/H10 复刻验证 + TERNARY 节点 slot 占用探查(parse_exprs.ss `parseTernary` 后 s1/s2/s3/i1-i4 槽位)| IR RED 铁证(若有)+ 时序探查 fact 入 §1 + §A.2 H1/H10 实证记录 + 节点 slot 探查 PASS |
| **Phase 2** | codegen 阶段反推实施 + G1 路径(D141/D142/D143 G1 同模式) | `bootstrap/checker/check_exprs.ss:TERNARY case` 改返 `branchType` 结构化(与 ARROW_FUNC + ARRAY_LIT + OBJ_LITERAL 同形)+ `bootstrap/gen/gen_calls.ss:resolveCallArgs` + `gen/methods/gen_methods.ss:emitClassMethodCall` 内 args 循环识别 TERNARY + 查 funcParamTypes branchType + 反推回填 TERNARY 节点 branchType slot + `eval/method_call.ss + eval/call.ss + eval/new_expr.ss` pre-eval 之前反推前移 + `bootstrap/gen/gen_types.ss` 三 helper(`isNullableType` / `extractInnerType` / `unifyBranchTypes`)对偶 D141 + D142 + D143 helper + **D067 nullable 分配路径复用**(反推得 callee `T?` 后两分支按 nullable widen / null literal 类型化走 D067 机制) | bootstrap 固定点 PASS + spike untyped 反推 GREEN + tests/d067_null_safety/ baseline 不降 |
| **Phase 3** | 测试覆盖 + 隐藏假设挑战 | `tests/d144_ternary_inference/` 新增(null+T 反推 T? / T+T 显式 / 嵌套 ternary / class 实例 ternary / interface upcast / 多层 nullable / 显式优先 / 推断失败硬错诊断)| 6+ test case 全绿 + 隐藏假设 H1-H8 全 PASS |
| **Phase 4** | workaround cleanup | grep + 删现存 fn 实参 ternary 临时变量绑定 workaround(若有 `let n: int? = (x > 0) ? null : 5; takesFn(n)` 形态 — Phase 1 grep 实测后定计数;预估 lib/spring/jdbc.ss + lib/json/ + tests/d067/ 多处) | bootstrap 固定点 PASS + tests/ baseline 不降 |
| **Phase 5** | 全 Phase 收关 hash trail | D144 5 Phase commit hash 全列 + 兑现成果 a-g + 隐藏假设全 PASS / OOD 标 + Followup 锚明确 | D144 主线 close |

### Phase 间依赖

- Phase 0 → 1:D 文档落档后用户审,Phase 1 下一轮起
- Phase 1 → 2:RED 成立 + 时序探查就位才启 Phase 2;若 H1 funcParamTypes 时序不就(D141/D142/D143 实证已 PASS,但 TERNARY 路径需独立验证)→ 调整 Phase 2 入口
- Phase 2 → 3:bootstrap 固定点 PASS + spike GREEN 才启 Phase 3 测试覆盖
- Phase 3 → 4:测试覆盖完整(隐藏假设全 PASS)才启 Phase 4 workaround cleanup
- Phase 4 → 5:cleanup 完整 + tests/ baseline 不降才启 Phase 5 收关

### 反模式

- ❌ 改 parser(`T?` annotation 已就绪 D067 落地 — H12 比 D141/D142/D143 都弱)
- ❌ 改 funcParamTypes 注册路径(已就绪 — §核心原则 9)
- ❌ 把 D067 null literal helper 重写(已就绪,Phase 2 反推得 callee `T?` 后复用 D067 机制)
- ❌ 顺带改 ternary 在 var decl RHS / class field init 路径(scope 留 sub-D 后续轮 — H6 显式优先)
- ❌ 起全局 bidirectional type checking(C3 候选废,留 D026/D027 generic 落地后再开 D 文档评估)
- ❌ 实施 D141 §F3+ / D142 §F2+ / D143 §F1+ 后续 sub-D(Map/Tuple/spread/partial fields 等留同模式扩 sub-D 后续轮)

---

## 4. State

### 编译时 state

- TERNARY 节点 branchType slot(待定:nSetS1 / nSetS2 / nSetS3 — Phase 1 探查节点 slot 当前占用情况)
- funcParamTypes(已就绪,Phase 2 不改注册路径)
- evalTernary pre-eval 缓存(eval pre-eval,Phase 2 反推前移到 outer call site 通用 pre-eval `genVal(argId)` 之前)
- D067 nullable 分配状态(已就绪,Phase 2 反推得 callee `T?` 后调原 D067 机制)

### 运行时 state

(N/A — 本 D 是 checker + codegen 编译时改,不影响运行时;genTernary phi node + 两分支 emit 路径不变)

### 中间产物

- `/tmp/spike_ternary_red.ss`(Phase 1 写)
- 三候选评估矩阵(本 D §A.1 + §A.1.1)
- 隐藏假设挑战表(本 D §A.2)

### 会话间持久化

- D144 §Phase 进度(clear 后续 Plan 锚,Status 行单一事实源)
- bootstrap 三阶段固定点 commit hash(各 Phase 回填)

### 禁止 state 操作

- ❌ 把 TERNARY branchType 信息保存到全局 Map(节点 slot 已足够 — 与 D141 ARROW_FUNC PARAM s2 + D142 ARRAY_LIT s2 + D143 OBJ_LITERAL s2 节点 slot 同范式)
- ❌ 把跨轮进度 / 摘要写到 handoff 文件(`.claude/next_prompt.md` 仅 terman preset 单次 payload)

---

## 5. Evaluation

### 单一判据(必须 GREEN)

```bash
# Phase 1 RED:untyped ternary + fn 实参 nullable — 当前需手动临时变量绑定才走通
cat <<'EOF' > /tmp/spike_ternary_red.ss
function takesNullableInt(n: int?): int {
    if (n == null) {
        return 0
    }
    return n
}
function main() {
    let x = 5
    let r = takesNullableInt((x > 0) ? null : x)
    println(r)
}
EOF

# Phase 1 RED:bin/ss run /tmp/spike_ternary_red.ss
# 期望:checker 报错或 silent miscompile(TERNARY 在 fn 实参时无 branchType 反推,null 与 int 两分支类型不一致 → 类型不匹配)

# Phase 2 GREEN:bin/ss run /tmp/spike_ternary_red.ss
# 期望:输出 "5"(反推回填 branchType=int? + 两分支按 nullable widen + D067 null literal 类型化路径走通)
```

### Phase 2 关键验证

- bootstrap 三阶段固定点 PASS(stage2 == stage3 字节比较)
- spike GREEN(主判据)
- tests/d067_null_safety/(若有 baseline 测试)不降
- tests/d141_lambda_inference/ 5 处 baseline 不降(D141 反推机制不破)
- tests/d142_array_literal_inference/ 6 处 baseline 不降(D142 反推机制不破)
- tests/d143_object_literal_inference/ 6 处 baseline 不降(D143 反推机制不破)
- tests/ 270/4/274 baseline 不降
- reflection_health_linter GATE PASS no regressions

### Phase 3 测试覆盖(隐藏假设挑战)

- null+T 反推 T?(`takesNullableInt((x > 0) ? null : 5)` callee `int?` + 两分支 null/5)— H1 反推 nullable + H2 两分支类型 widen PASS
- T+T 显式两分支同类型(`takesInt((x > 0) ? 1 : 2)` callee `int` + 两分支 int/int)— H6 显式优先(无反推)
- 嵌套 ternary(`takesNullableInt((x > 0) ? ((y > 0) ? null : 5) : 10)` callee `int?`)— H3 嵌套反推 capture 链
- class 实例 ternary(`takesNullableUser((x > 0) ? null : new User("X", 18))` callee `User?`)— H4 class 实例反推 PASS + D067 nullable 分配
- interface upcast(`takesShape((x > 0) ? new Circle(1) : new Square(2))` callee `IShape`)— H5 interface upcast PASS via vtable indirect dispatch
- 多层 nullable(`takesNullableUser((x > 0) ? null : ((y > 0) ? null : new User("X", 18)))` 两层嵌套 nullable)— H3 嵌套反推
- 显式优先(`let n: int? = (x > 0) ? null : 5; takesNullableInt(n)`)— H6 显式注解仍走原路径(D084 rewrite + D067 null literal 类型化)
- 推断失败 fallback(callee 不在 funcParamTypes / arity 不匹配 / 非结构化 callee)→ skip 反推或硬错(参 D141/D142/D143 H13 粒度)

---

## 6. Constraints

### 硬约束

- 不引入 bidirectional type checking 全局(候选 C3 已废,scope 爆炸)
- 不动 D025 interface dispatch 契约
- 不动 D067 null literal 默认行为本体(D144 反推得 callee `T?` 后复用 D067 机制)
- 不动 D131 nullable inner field 反序列化路径
- 不动 D141 lambda 反推机制 / D142 array literal 反推机制 / D143 object literal 反推机制(D144 是同模式扩,不重写信息源)
- bootstrap 改不许超过 800 LOC delta(`feedback_600_split_not_inline.md` + `feedback_structure_not_linecount.md`)— 实际预估 ≤ 150 LOC(check_exprs.ss + gen_calls.ss + eval/method_call.ss + eval/call.ss + eval/new_expr.ss + gen_types.ss helper 局部改 — 比 D143 ~130 略轻)

### 软约束

- 推断失败时**优先编译期硬错**(参 D141 H13 + D142 H13 + D143 H13 结构化 callee 硬错粒度);非结构化 callee skip 反推不破现状
- 显式注解仍优先级最高(`let n: int? = (...)` D084 rewrite + D067 nullable 风格,既有现存)
- 反推查 callee `funcParamTypes` 时,callee 必须已 register(D141/D142/D143 H1 实证 codegen 阶段已就绪)— Phase 1 文档化时序保证

### 风险锚(R1-R5)

| # | 风险 | 描述 | mitigation |
|---|---|---|---|
| R1 | TERNARY 节点 slot 占用冲突 | nSetS1 / nSetS2 / nSetS3 已被其他用途占用,反推回填 branchType 找不到空 slot | Phase 1 探查 TERNARY 节点 slot 当前占用(`bootstrap/parse/parse_exprs.ss` `parseTernary` 后,s1/s2/s3 是否空);若占用 → 复用 nSetS2(类型 slot 命名) / nSetS3 / 新引入 hash Map(ssTernaryBranchType[id] → string)路径;参 D141 ARROW_FUNC PARAM s2 + D142 ARRAY_LIT s2 + D143 OBJ_LITERAL s2 范式 |
| R2 | 嵌套 ternary 反推链路断 | `(x > 0) ? ((y > 0) ? null : 5) : 10` 内层 ternary 字段是 ternary,反推外层 branchType=int? 后,内层 ternary 也需反推 branchType=int? — 递归回填 | Phase 2 实施 + Phase 3 嵌套 ternary test;若失败 → 内层 ternary 反推回路 fallback 单层 + 用户嵌套时仍需显式 RHS binding |
| R3 | 两分支类型不一致 + 反推 widen 边界 | `(x > 0) ? "X" : 5` 两分支 string/int 不一致,反推得 callee `int?` 后 string 分支硬错 vs widen 到 ptr 的歧义 | Phase 1 实测 + Phase 2 决策 — (a) 严格模式:两分支与 callee branchType 一致性 check,不一致硬错;(b) widen 模式:null literal widen + 其他类型严格 — 与 D067 协同;Phase 3 mismatch test 实证 |
| R4 | null literal 默认行为破坏 | D067 已落 null literal 默认非空收紧;D144 反推得 callee `T?` 后 null literal 类型化为 `T?` — 链路是否打通需 Phase 2 实测 | Phase 1 grep + Phase 2 reuse D067 nullable 分配 helper,不重写 |
| R5 | interface upcast / vtable 路径 | `cond ? new Circle(1) : new Square(2)` 两分支 class 实例,反推得 callee `IShape` 后两分支 vtable indirect dispatch 路径 | Phase 3 interface upcast test;失败 → 走 D025 vtable 既有路径,反推不破 |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 spike 已 GREEN(无 RED) | 改 spike 形态:多分支嵌套 / class 实例 / interface upcast / 多层 nullable;若全场景已 GREEN → D144 范围降级为 "类型表达力对齐 D141/D142/D143"(Plan-only,无代码改) |
| Phase 2 build 失败 | git revert;调 TERNARY slot 命名 + check_exprs.ss TERNARY case 同步 |
| Phase 2 嵌套 ternary 红 | R2 mitigation:内层 ternary 反推单层 fallback + 文档化 H3 OOD scope |
| Phase 2 两分支类型不一致硬错 | R3 mitigation:严格模式硬错 vs widen 模式 — Phase 2 决策行 + Phase 3 mismatch test 实证 |
| Phase 2 null literal 链路断 | R4 mitigation:reuse D067 nullable 分配 helper,不重写;Phase 1 grep D067 + Phase 2 反推前移到 D067 调用前 |
| Phase 2 reflection_health_linter GATE BLOCK | 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段)|
| Phase 4 grep 工作量超估 | 范围限定 lib/ + tests/d067_null_safety/ + tests/d134_mysql/(D141/D142/D143 cleanup 同域),其他 tests/ 留 sub-D 后续轮 |

### 回滚策略

- Phase 1+ 失败 → `git reset --soft HEAD^` 回上一 Phase
- Phase 0 文档已落盘,Phase 1+ 实施 commit 边界严格(D135/D136/D137/D140/D141/D142/D143 范式延续)
- D144 失败回退不影响 D141/D142/D143(D141 + D142 + D143 主线已 close,D144 仅同模式扩)

---

## A.1 主候选评估(§MNK §M §字段 10 + Plan 型 §④ 替换:替代方案对比)

| 候选 | 层次 | 描述 | 假设破裂入口 | 优势 | 劣势 | 决策 |
|---|---|---|---|---|---|---|
| **C1** | **数据层 patch** | `gen_calls.ss` fn 实参 TERNARY 路径加 fallback — TERNARY 类型未知时从 callee funcParamTypes 取 branchType 兜底 + 临时把两分支 widen | 破裂入口在 TERNARY inferType 返单一 then 分支类型,信息丢失;C1 仅在 fn 实参单点补 fallback,不消除根因 — D067 null literal 类型化 / classFieldTypes / inferType 等其他消费者仍走错 | LOC 极小 5-10 行;不动 checker | 零散 patch — 多消费者(D067 null literal / classFieldTypes / inferType 等)都用 TERNARY inferType,信息源不单点;同模式 ternary 在 method 实参 / var decl typeAnn 等场景仍 RED | **不选** — 数据层不消除根因(`feedback_root_cause_no_cost.md` 红线,与 D141 §A.1 C1 + D142 §A.1 C1 + D143 §A.1 C1 同形废)|
| **C2** | **接口层 trap** | checker `check_exprs.ss:TERNARY case` 改返 `branchType` 结构化签名(与 ARROW_FUNC `fn(P,...):R` + ARRAY_LIT `Array<elemType>` + OBJ_LITERAL `class<ClassName>` 同形)+ codegen 阶段 fn/method 实参反推回填 TERNARY branchType slot + eval pre-eval 时序 + funcParamTypes SSoT 复用 + D067 nullable 分配路径复用 + 两分支按 branchType widen / null literal 类型化 | **彻底消除** — TERNARY inferType 结构化,所有下游(D067 null literal / classFieldTypes / inferType / method dispatch)信息源一致;eval pre-eval 反推前移避免 D141/D142/D143 H10 同形时序破裂 | 单点信息源回填;TS / Java 8+ contextual typing 主线;D141/D142/D143 G1 路径同模式复刻;workaround cleanup 落锚;D067 nullable 复用 | LOC 中等 ~150(check_exprs.ss + gen_calls.ss + eval/method_call.ss + eval/call.ss + eval/new_expr.ss + gen_types.ss helper);需考虑嵌套 ternary / 两分支类型不一致 / null literal widen 边界 | **选** — 接口层 trap 消除根因 + scope 可控 + D141/D142/D143 同模式复用 + D067 nullable 复用 |
| **C3** | **架构层 refactor** | 全编译器 bidirectional type checking — checker 改 expected/actual 双向类型检查,所有表达式从调用上下文反推类型(包括 array literal + object literal + ternary + null literal + lambda + binary op 等) | 消除根因 + 消除其他 silent miscompile(binary op 类型推断等)| 类型系统统一性最高;未来扩 SS 泛型 D026/D027 时直接复用;D141 §Followup F5 + D142 §A.3 + D143 §A.3 已锁此候选废留 SS 类型系统 v2 | scope 爆炸 LOC > 2000 + 多 sub-D + bootstrap 重写多个核心文件;F1 单 sub-D scope 远超(D144 不应承载架构层 refactor) | **不选** — scope 远超 D144 单 sub-D 范围;**D141 §Followup F5 + D142 §A.3 + D143 §A.3 已锁此候选废**,留作未来 SS 类型系统 v2 评估 |

**决策行**:**选 C2 接口层 trap** 因 (a) 单点信息源回填,消除 TERNARY inferType 单一 then 分支类型的假设破裂入口;(b) D141/D142/D143 G1 路径同模式复刻 — eval pre-eval 时序 + funcParamTypes SSoT + codegen 阶段反推 + 失败硬错粒度全沿用;(c) D067 nullable 分配路径复用 — 反推得 callee `T?` 后两分支按 nullable widen / null literal 类型化走原 D067 机制;(d) workaround cleanup 落锚 Phase 4(临时变量绑定形态全删);(e) scope 可控 ~150 LOC delta < D143 ~130 LOC ≈ D142 ~91 LOC < D141 ~267 LOC。**为何不选 C1**:数据层 zero-spread 不消除根因(`feedback_root_cause_no_cost.md` 红线,与 D141 §A.1 C1 + D142 §A.1 C1 + D143 §A.1 C1 同形废)。**为何不选 C3**:scope 爆炸 — D141 §Followup F5 + D142 §A.3 + D143 §A.3 已锁 C3 废留 SS 类型系统 v2,D144 单 sub-D 不承载架构层 refactor。

---

## A.1.1 C2 实施路径对比(Phase 0 落档,Phase 1 起首实测确认)

> Phase 0 起首查源:D067 已落 `T?` nullable 类型 annotation 解析 + null literal 默认非空收紧 + nullable 分配路径(`check_types.ss isTypeCompatible nullable widen`);funcParamTypes 已注册 nullable 字符串(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57)— **D144 比 D141/D142/D143 G1 路径更轻**(D141 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn`,parser 必须扩 parseTypeAnn fn 类型;D142 比 D141 更轻无 callee 升级 + 无 parser 扩前置;D143 callee `class X` 已结构化 + parser 已就绪 + D084 rewrite 路径已落 — 反推可直接消费;D144 callee `T?` 已结构化 + parser 已就绪 + D067 nullable 分配路径已落 — 反推可直接消费 + 复用 D067 链路)。下分三路径定 D144 实施。

| 路径 | 描述 | 解决度 | LOC | 影响 | 决策 |
|------|------|--------|-----|------|------|
| **G1** | **D141/D142/D143 G1 同模式复刻** — checker `check_exprs.ss:TERNARY case` 返 `branchType` 结构化(与 ARROW_FUNC + ARRAY_LIT + OBJ_LITERAL 同形)+ codegen 阶段反推回填 TERNARY branchType slot + eval pre-eval 反推前移(三处 outer call site 通用 pre-eval `genVal(argId)` 之前)+ funcParamTypes 已结构化直接消费(无 callee 升级前置)+ helper `isNullableType` / `extractInnerType` / `unifyBranchTypes` 落 gen_types.ss(对偶 D141 isFnType + D142 isArrayType + D143 isClassType)+ **D067 nullable 分配路径复用**(反推得 callee `T?` 后两分支按 nullable widen / null literal 类型化走原 D067 机制)| 100% | check_exprs.ss ~10 + gen_types.ss helper ~30 + gen_calls.ss + gen_methods.ss 反推 ~30 + eval/method_call.ss + eval/call.ss + eval/new_expr.ss pre-eval 反推 ~30 + check_types.ss isTypeCompatible 调整 ~10 ≈ **~110** | Phase 4 临时变量绑定 cleanup 仍可推进(callee 已结构化与 ternary cleanup 独立)| **选** — D141/D142/D143 G1 同模式复刻 + 比 D141/D142 更轻(无 parser 扩 + 无 callee 升级前置 + D067 nullable 复用 — H11/H12 比 D141 弱 / 比 D142 略弱 / 比 D143 略弱)|
| G2 | callsite 双向反推 — 从 ternary 第一分支类型反推 branchType;不依赖 callee `T?` 形态 | 30% | gen_calls.ss + gen_methods.ss ≈80 | 漏 null+T 反推 T?(null 分支 inferType 不出 T?,nullable 是上下文反推关键) + 漏 fn binding 间接链 + 漏两分支类型不一致 widen — **TERNARY 分支反推 branchType 不可行**(branchType 是上下文反推关键) | 不选 — 不可行 + 偏离 TS / Java 8+ 主线(TS ternary 反推靠 callee 形参类型,不靠分支自身 inferType)|
| G3 | 接受 gap,Phase 2 仅做 (a) 预备 — check_exprs.ss TERNARY case 改返结构化签名,(b)(c) 反推机制因消费链路不接通实际不生效;主线 D141 §Followup F3 / D142 §Followup F2 / D143 §Followup F1 cleanup 延期 | 0% | check_exprs.ss TERNARY case 单点 ≈10 | 主线 cleanup 延期;反推机制空转;违反 `feedback_root_cause_no_cost.md` 红线 | 不选 — 反推机制空转无意义 |

**G1 决策(本 Phase 0 落档锁定,待用户对话确认)**:走 G1 — 根因 100% + D141/D142/D143 G1 同模式复刻 + scope 可控 < D143 LOC + 比 D141/D142/D143 更轻(无 parser 扩 + 无 callee 升级前置 + D067 nullable 复用 — H11/H12 比 D141 弱 / 比 D142 略弱 / 比 D143 略弱)。**为何不选 G2**:TERNARY 分支反推 branchType 物理不可行(branchType 是上下文反推关键,非分支自身 inferType — null 分支无法反推 T?);且偏离 TS / Java 8+ contextual typing 主线(TS ternary 反推靠 callee 形参类型,不靠分支自身 inferType)。**为何不选 G3**:反推机制空转 0% 解决度,违反 `feedback_root_cause_no_cost.md` 红线。

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套 — D141 §A.2 + D142 §A.2 + D143 §A.2 同模式扩)

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | funcParamTypes nullable / 结构化字符串在 codegen 阶段已 ready(D141/D142/D143 H1 同模式 — checker 阶段用户函数为空,codegen registerAllDecls 后满载)| 实施层失败 — codegen 反推时 funcParamTypes 留空,反推查不到 callee 期望 branchType | Phase 1 探查 codegen.ss:110-112 + gen_registry.ss:56-57 register 时机;Phase 2 startup 阶段 dump funcParamTypes 验证含 `T?` / `class X` 等 nullable / 结构化形态;**D141/D142/D143 H1 已实证 codegen 阶段已就绪**,D144 同模式假设大概率成立 | funcParamTypes 时机不就 → 调整 Phase 2 入口(改 lazy 反推 vs eager 反推)|
| H2 | TERNARY 两分支类型与 callee branchType 一致性 widen | `(x > 0) ? null : 5` 两分支 ptr/int 不一致,反推得 callee branchType=int? 后 null 分支类型化为 `int?` 0 / int 分支 widen 到 `int?` 路径;若两分支与 callee branchType 类型冲突(`(x > 0) ? "X" : 5` 期望 int?)→ widen 失败硬错 | Phase 3 测试 `tests/d144_ternary_inference/branch_widen.ss` + `mismatch_硬错.ss` | 类型不一致 silent fallback → 回 Phase 2 修硬错路径;参 D141 H4 + D142 H2 + D143 H4 fallback 编译期硬错粒度 |
| H3 | 嵌套 ternary `(x > 0) ? ((y > 0) ? null : 5) : 10` 反推 capture 链 | 内层 ternary 字段也是 ternary,反推外层 branchType=int? 后,内层 ternary 也需反推 branchType=int? — 递归回填 | Phase 3 测试 `tests/d144_ternary_inference/nested.ss`(`takesNullableInt(...)` + `(x > 0) ? ((y > 0) ? null : 5) : 10`)| 嵌套反推失败 → 内层 ternary fallback 单层 + 用户嵌套时仍需显式 RHS binding;参 D141 H3 + D142 H3 + D143 H3 嵌套范式 |
| H4 | null literal 在 ternary 分支反推 T? — D067 路径复用边界 | `cond ? null : 5` 中 null 分支 — D067 已落 null literal 默认非空收紧;D144 反推得 callee `T?` 后,null literal 类型化为 `T?` 链路是否打通?需 Phase 2 实测 | Phase 1 grep D067 null literal 处理路径 + Phase 2 反推前移到 D067 调用前 + Phase 3 part_field test | D067 链路断 → 回 Phase 2 修反推前移路径,reuse D067 helper 不重写 |
| H5 | interface upcast `(x > 0) ? new Circle(1) : new Square(2)` 反推 IShape | 两分支 class 实例,反推得 callee `IShape` 后两分支 vtable indirect dispatch 路径 — D025 既有 | Phase 3 测试 `tests/d144_ternary_inference/interface_upcast.ss` | interface upcast 失败 → 走 D025 vtable 既有路径,反推不破;参 D141 H5 + D142 H5 + D143 H5b 同模式 |
| H6 | 显式注解优先级 > 推断 | 用户写 `let n: int? = (x > 0) ? null : 5; takesFn(n)` 时,RHS 推断走 D084 rewrite + D067 既有路径(`check_stmts.ss:112-113` typeAnn != "" 触发);fn 实参传 n(IDENT)反推 skip(n 不是 TERNARY)| Phase 2 反推条件判断 `if (nGetKind(argId) == "TERNARY")` 限定;Phase 3 测试 `tests/d144_ternary_inference/explicit_override.ss` 显式注解仍走原路径;参 D141 H6 + D142 H6 + D143 H6 显式优先粒度 | 显式优先级失败 → 回 Phase 2 修条件判断 |
| H7 | tests/ 270/4/274 baseline 不降 | 全项目现有 ternary 测试都走显式两分支同类型 / D084 rewrite — Phase 2 反推不影响显式路径(H6 显式优先);Phase 4 cleanup 仅临时变量绑定形态 | Phase 2 后跑 `bin/ss test tests/` 全跑 + baseline 比 | tests/ 红 → 回 Phase 2 修条件判断或 fallback 路径;参 D141 H7 + D142 H7 + D143 H7 同范式 |
| H8 | reflection_health_linter GATE 不破 | checker / codegen / eval 三层改 — 是否破反射路径 14 指标(M1-M7b + N1-N5)| Phase 2 后跑 `bin/ss run tools/reflection_health_linter.ss` GATE PASS | GATE BLOCK → 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段);参 D141 §扩容申报-Phase2-G1 + D142 §扩容申报-Phase2 + D143 §扩容申报-Phase2 范式 |
| H9 | var binding callee 反推 OOD scope(D141/D142/D143 H9 同模式)| `const f = takesNullableInt; f((x > 0) ? null : 5)` callee="f" 是 var binding 不在 funcParamTypes,反推 skip | **D141 H9 + D142 H9 + D143 H9 已锁 var binding callee OOD scope**,D144 同模式继承 — 主线场景是 method call(`tmpl.exec(...)`)/ fn call(`takesNullableInt(...)`),callee 是 mangled method 名 / 函数名在 funcParamTypes,不受影响 | var binding 不支持反推 → 用户 var binding 时仍需显式 RHS binding,不影响 D144 主线 cleanup |
| H10 | TERNARY eval pre-eval 时序(D141/D142/D143 H10 同模式 + cross-D 反思继承)| 待 Phase 1 实测确认 evalTernary 路径 + pre-eval 缓存与 codegen emit 之前的时序;**D143 H10 cross-D 教训**:不能仅 grep 字面 handler `evalTernary`,outer call site 通用 pre-eval `genVal(argId)` 才是反推时序关键(memory `feedback_h10_cross_d_verify.md`)— 反推必须前移到 outer call site `eval/method_call.ss + eval/call.ss + eval/new_expr.ss` args 循环 | Phase 1 探查 outer call site 通用 pre-eval `genVal(argId)` 路径 + Phase 2 反推前移到三处 outer call site 识别 TERNARY 子节点 + 查 funcParamTypes + 反推回填 | 修复链断 → 回 Phase 2 检查 nSetS?/nGetS? 命名一致 + outer call site args 循环识别 TERNARY 完整路径 |
| H11 | callee PARAM `T?` / 结构化字符串已就绪,无需 G1 callee 升级(比 D141 H11 弱,比 D142 H11 同位,比 D143 H11 同位) | D141 G1 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn`(parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析);D142 callee `Array<T>` 已结构化无前置;D143 callee `class X` 已结构化无前置;D144 callee `T?` / `class X` / `Array<T>` 等已结构化(D067 落地 + class IDENT + Array generic 全已就绪) | grep 实测 lib/ + tests/ 多处 callee PARAM `T?` / `class X` 已结构化;Phase 2 反推 helper `isNullableType("int?")` = true / `extractInnerType("int?")` = "int" 直接消费 | callee 升级路径破裂 → 反推失败 silent skip(非结构化 callee 走 H13 同形 skip 不破);参 D141 H13 + D142 H13 + D143 H13 粒度 |
| H12 | parser 不需要扩(比 D141 H12 + D142 H12 + D143 H12 同位都弱)| D141 H12 必须 parseTypeAnn IDENT "fn" + LPAREN 分支扩;D142 嵌套 generic Array<...> 已就绪;D143 class 名 IDENT 单 token 已就绪;D144 `T?` 后缀已 D067 落地解析,parser 已就绪无嵌套 generic 解析需求 | Phase 1 grep 实测 + Phase 2 不动 parser | parser 未就绪(若实测发现某些边界形态未支持)→ 回 Phase 2 评估扩 parser 必要 — 大概率不需要 |
| H13 | 反推失败硬错粒度(D141/D142/D143 H13 同模式)— 结构化 callee 硬错 / 非结构化 callee skip | **结构化 callee**(funcParamTypes 含 `T?` / `class X` / `Array<T>`):helper extractInnerType 取不到 → `codegenError` 硬错;**非结构化 callee**(funcParamTypes 仍是 ""/单 IDENT 非 nullable)→ 反推 skip(不破现有调用方);**两分支类型不一致 mismatch**:参 H2 决策(严格 vs widen)| Phase 2.2 实测 helper extractInnerType + Phase 4 cleanup 删 typed 注解后,untyped ternary 走结构化反推 | 硬错粒度过严 → tests/ break → 调整粒度为 silent skip + warn(参 D141 H13 + D142 H13 + D143 H13 调整路径)|

---

## A.3 废案

- **C1 数据层 patch 全废**(零散 fallback,不消除根因 — 与 D141 §A.3 + D142 §A.3 + D143 §A.3 同形)
- **C3 架构层 refactor 全废**(scope 爆炸,远超 D144 单 sub-D)— **D141 §Followup F5 + D142 §A.3 + D143 §A.3 已锁此候选废留 SS 类型系统 v2 评估**
- **C4 编译期 lint 警告强制用户加 RHS binding**(被动 — 用户每写 ternary 必先 binding,违反 CLAUDE.md §编译器吸收复杂度)
- **C5 全 ternary 默认 branchType=ptr / Object**(silent miscompile — null+T / class 实例 / interface upcast / 嵌套 ternary 全场景错位)
- **G2 callsite 双向反推全废**(物理不可行 — null 分支反推不出 T?,branchType 是上下文反推关键 — §A.1.1 G2 行)
- **G3 接受 gap 全废**(反推机制空转 0% 解决度,违反 `feedback_root_cause_no_cost.md` 红线)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `02415c9` (2026-04-27)

- 本文档落档 + Status / 核心目标 / 核心原则 / Context / Tools / Orchestration / State / Evaluation / Constraints / §A.1 主候选 + §A.1.1 实施路径 + §A.2 隐藏假设 / §A.3 废案 / Phase 0-5 计划草案
- d_doc_index_linter F1 = 0 验证 PASS(D144 加入未破 referenced Ds — D025/D067/D131/D141/D142/D143 实存,F2 soft warn 含 D144 不阻 commit)
- next_prompt_ultrathink_linter PASS 3/3(本轮 .claude/next_prompt.md 含 ultrathink 关键字)
- VCM 六验(Plan 型):§① 跳过(diff=0 in bootstrap/lib/tools)+ §④ 替换为「替代方案对比 + 隐藏假设挑战」§A.1+§A.1.1+§A.2 ✓

### Phase 1: RED 复现 + 信息源探查 [✓] Done at commit `17a1573` (2026-04-27)

**主线 7 形态实测全 GREEN — D144 §第一性需求 motivating example 修正**(关键发现):
- `/tmp/spike_ternary_red.ss` 7 形态(null+`User?` / T+T 显式 / 嵌套 / class 实例 / interface upcast / 多层 nullable / fn 返回 ternary)`bin/ss run` 全 GREEN
- 根因:D067 不允许 primitive nullable(`bootstrap/checker/check_narrow.ss:6` `primitive type 'int' cannot be nullable`)— D144 文档原 motivating example `function takesNullableInt(n: int?): int` 不合法;改用 reference 类型 `User?` 后,**两分支 ptr 一致**(null=ptr / `new User(...)`=ptr / `Array<int>?`=ptr / IShape upcast=ptr),phi node 自然 ptr 统一,fn 实参反推机制**主线场景已 GREEN**
- D141/D142/D143 fn 实参反推主线场景**不是 D144 真战场** — D141 ARROW_FUNC 反推 PARAM s2 / D142 ARRAY_LIT 反推 elemType / D143 OBJ_LITERAL 反推 className 都是结构化签名信息丢失(callee 期望 `fn` / `Array<T>` / `class<X>`,实参节点 IR emit 前需结构化标签),而 ternary 两分支 ptr 路径已通

**真 RED 形态另立(D144 主战场修正)**:
- **X4-1 字段访问**:`((cond)?u1:u2).name` → LLC error `'%14' defined with type 'ptr' but expected 'i32'`(实测 `bin/ss run /tmp/spike_ternary_x4_1.ss` line 5278:13 store i32 ptr type mismatch)— TERNARY inferType 在字段访问链路 resolveObjClass 失败,fallback 走 i32 默认路径
- **X mismatch 两分支类型不一致**:`takesInt((cond)?1:"X")` → LLC error `global variable reference must have pointer type`(实测 `bin/ss run /tmp/spike_ternary_x_mismatch.ss` line 5112:13 string literal `@.str.78` 当 int 走 IR)— **checker `check_exprs.ss:304-309` 仅依次 checkExpr 三子节点,无两分支类型一致性检查,silent miscompile**
- **真主战场锚**:TERNARY inferType 信息源破裂 — `bootstrap/checker/check_types.ss:201` + `bootstrap/gen/gen_types.ss:541` 单一 `inferType(nGetI2(id))` 仅返 then 分支,字段访问 / phi llType 链路全错位

**§A.2 H1 同模式实证 PASS**(funcParamTypes 时序 — D141/D142/D143 H1 同模式继承):
- `bootstrap/gen/codegen.ss:110-112`(普通函数 funcParamTypes 注册):`funcParamTypes.set(\`${fname}:${pCount}\`, nGetS2(fpId))`
- `bootstrap/gen/gen_registry.ss:56-57`(class method 注册):`funcParamTypes.set(\`${baseName}:${pCount}\`, nGetS2(pId))`
- `bootstrap/gen/codegen.ss:326`:`registerAllDecls(rootId)` 在 line 327 `emitGlobalsAndCode(rootId)` 之前
- **结论**:funcParamTypes codegen 阶段已满载,含 `User?` / `Array<int>?` / `class X` 等结构化签名(`nGetS2(fpId)` 取 PARAM 节点 s2 槽位 SS 类型字符串),Phase 2 反推可直接消费,无需调整注册路径

**§A.2 H10 cross-D 反思继承 PASS**(eval pre-eval 时序 — D143 教训 `feedback_h10_cross_d_verify.md` 继承):
- `bootstrap/eval/method_call.ss:36-70` outer call site pre-eval — D141/D142/D143 反推前移落锚 line 61-65 三行(inferArrowFuncParams / inferArrayLitElems / inferObjLiteralFields),**D144 同点追加** `inferTernaryBranchType(mcArgIdR, mcResolvedR, mcArgIdxR)` **第 4 行**
- `bootstrap/eval/call.ss:18-43` outer call site pre-eval — D141/D142/D143 落锚 line 33-39 三行,**D144 同点追加第 4 行**
- `bootstrap/eval/new_expr.ss:24-41` outer call site pre-eval — D143 NAMED_ARG OBJ_LITERAL 嵌套反推前移落锚 line 27-41,**D144 落点考量**:Phase 2 决定是否扩到 NEW_EXPR(D144 §Followup F3 同位锚)
- **关键反思**:**不仅 grep 字面 handler `bootstrap/eval/ternary.ss:4` `evalTernary`**(handler 触发时 callee context 已丢),outer call site 通用 pre-eval `genVal(argId)` **才是反推时序关键** — D143 H10 cross-D 教训直接继承

**TERNARY 节点 slot 占用探查 PASS**:
- `bootstrap/parse/parse_exprs.ss:6-20` `parseExpr` 顶级表达式入口构造 ternary:`newNode("TERNARY")` + `nSetI1(id, left)` + `nSetI2(id, thenId)` + `nSetI3(id, elseId)`(line 13-16)
- **占用槽位**:i1(cond) + i2(then) + i3(else)
- **空闲槽位**:s1 / s2 / s3 / i4 + nList — Phase 2 选 **nSetS2** 存 branchType(与 D141 ARROW_FUNC PARAM s2 + D142 ARRAY_LIT s2 + D143 OBJ_LITERAL s2 同范式)

**TERNARY kind dispatch site 全 grep PASS 8 处**:
| # | 文件:line | 角色 |
|---|---|---|
| 1 | `bootstrap/parse/parse_exprs.ss:13` | parser `newNode("TERNARY")` |
| 2 | `bootstrap/checker/check_exprs.ss:304-309` | checker case(checkExpr 三子节点 — **无类型一致性检查 = X mismatch RED 入口**)|
| 3 | `bootstrap/checker/check_types.ss:201` | checker inferType `inferType(nGetI2(nodeId))` — **单一 then 分支 = 信息源破裂入口** |
| 4 | `bootstrap/gen/exprs/exprs.ss:68` | genVal dispatch(走 evalExpr → evalTernary) |
| 5 | `bootstrap/gen/gen_types.ss:541` | codegen inferType `inferType(nGetI2(id))` — **同 checker 单一 then 分支** |
| 6 | `bootstrap/eval/eval_expr.ss:64` | evalExpr dispatch `return evalTernary(astId)` |
| 7 | `bootstrap/eval/ternary.ss:4-33` | evalTernary handler — line 12 `ssTypeToLLVM(inferType(nGetI2(astId)))` 决定 phi llType |
| 8 | `bootstrap/pir/pir_lower.ss:252-257` | PIR use 分析 `pirCollectUsesRec` 三子节点 — **仅 use 收集不破反推链路**(无类型推断,Phase 2 不需改) |

**Phase 2 入口全锁**:
- `bootstrap/checker/check_types.ss:201` 改:优先读 `nGetS2(nodeId)` branchType,fallback `inferType(nGetI2(nodeId))`(对偶 D143 OBJ_LITERAL line 544-551)
- `bootstrap/gen/gen_types.ss:541` 改:同上模式优先读 nGetS2 fallback
- `bootstrap/checker/check_exprs.ss:304-309` 改:加两分支类型一致性检查(X mismatch RED 修复入口)
- `bootstrap/eval/method_call.ss:65 之后` + `bootstrap/eval/call.ss:39 之后` 追加 `inferTernaryBranchType(argId, callee, idx)` 第 4 行(D141/D142/D143 G1 4 落点同模式复刻)
- `bootstrap/eval/ternary.ss:12` 改:phi llType 优先读反推 branchType,fallback 单分支 inferType
- `bootstrap/gen/gen_types.ss` 加 helper:`isNullableType` / `extractInnerType` / `unifyBranchTypes`(对偶 D141 isFnType + D142 isArrayType + D143 isClassType)
- `bootstrap/eval/new_expr.ss` ctor 实参反推扩展考量(D144 §Followup F3 同位锚)

### Phase 2: codegen 阶段反推实施 + G1 路径(D141/D142/D143 G1 同模式复刻)[✓] Done at commit `71af131` (2026-04-27)

- `bootstrap/checker/check_exprs.ss:304` TERNARY case 加两分支类型一致性 + nSetS2 回填 — X mismatch RED 修复入口(`takesInt((cond)?1:"X")` checker 阶段两分支基础类型 `int` vs `string` mismatch 硬错;两分支同类型且非 `null` 时回填 nSetS2 让下游 inferType 直接消费)
- `bootstrap/checker/check_types.ss:201` TERNARY inferType 改:优先读 nGetS2 fallback inferType(then 分支)— 对偶 D143 OBJ_LITERAL line 544-551
- `bootstrap/gen/gen_types.ss:541` codegen inferType 同模式 + line 154 `resolveObjClass` 加 GROUPING / TERNARY case(X4-1 字段访问 RED 修复入口 — `((cond)?u1:u2).name` 走通 `resolveObjClass(TERNARY)` → "User" → classFieldTypes["User.name"]="string")
- `bootstrap/gen/gen_types.ss` 加 helper 5 函数:`isNullableType` / `extractInnerType` / `unifyBranchTypes`(对偶 D141 isFnType + D142 isArrayType + D143 isClassType)+ `propagateTernaryBranchType`(嵌套 ternary 递归回填 — H3 嵌套反推链路 `(c1)?null:((c2)?null:new User("X"))` 外层 + 所有内层共享同 branchType)+ `inferTernaryBranchType`(callee PARAM 反推回填 nSetS2 — D141 inferArrowFuncParams + D142 inferArrayLitElems + D143 inferObjLiteralFields 同模式)
- `bootstrap/gen/gen_calls.ss:285` + `bootstrap/gen/methods/gen_methods.ss:208` args 循环追加 `inferTernaryBranchType(argId, typeCallee, argIdx)`(D141 + D142 + D143 G1 4 落点同模式复刻)
- `bootstrap/eval/method_call.ss:67` + `bootstrap/eval/call.ss:40` outer call site pre-eval 追加 `inferTernaryBranchType` 第 4 行(D141/D142/D143 H10 cross-D 反思继承 `feedback_h10_cross_d_verify.md` — outer call site 通用 pre-eval `genVal(argId)` 路过 TERNARY 走 phi llType,反推必须前移到 outer call site 之前)
- `bootstrap/eval/new_expr.ss:33` ctor 实参 NAMED_ARG 内 TERNARY 也补反推(对偶 D143 inner OBJ_LITERAL,sub-D F3 NEW_EXPR 嵌套反推主线场景)
- `bootstrap/eval/ternary.ss:12` phi llType 优先读 nGetS2(astId) fallback inferType(then 分支)— `User?` 反推得 ssTypeToLLVM 自动返 ptr(line 696),class instance ternary IShape upcast 反推后 ptr 一致
- 关键 bug 修复(Phase 2 实施中实证):checker 阶段两分支同类型时排除 `"null"`(两分支都是 NULL_LIT 时不回填,等 codegen 反推 callee `T?`),否则外层 nSetS2 被错误设为 `"null"` override 后续反推
- spike RED→GREEN 双铁证:`/tmp/spike_d144_phase2_x4_1.ss` X4-1 字段访问 GREEN(输出 `Alice` + `18`)+ `/tmp/spike_d144_phase2_x_mismatch.ss` X mismatch checker 硬错 GREEN(`error: ternary branches type mismatch: 'int' vs 'string'`)
- VCM 验证:bootstrap 三阶段固定点 PASS + tests/ 276/4/280 baseline 不降(D144 反推让 6 个 test case 转 GREEN,4 failed 等于 baseline 同 4 个非反推路径回归)+ Phase 1 主线 7 形态 + 嵌套 ternary 全 GREEN + reflection_health GATE PASS 扩容申报 D144#扩容申报-Phase2(11 metric bump:M1=5550→5600 / M2=81600→82100 / M3a=12850→12880 / M3b=2000→2010 / M4=3250→3280 / M5=1830→1840 / M7b=700→710 / N2=408000→410100 / N3=562000→565400 / F1:gen_methods.ss=726→730 / F1:gen_types.ss=970→1050)

### Phase 3: 测试覆盖 + 隐藏假设挑战 [✓] Done at commit `959a2de` (2026-04-28)

**测试用例 8 个(tests/d144_ternary_inference/)全绿**:
- `null_plus_T.ss` — H1 反推 nullable + H2 两分支类型 widen — `takesNullableUser((cond)?null:new User("X"))` callee `User?` 反推 nSetS2="User?" + null/new 两分支 phi=ptr 统一 GREEN(双 case `(null)` / `Y`)
- `T_plus_T_explicit.ss` — H6 显式两分支同类型(无反推依赖)— `takesInt((cond)?1:2)` 两分支显式 int 一致性 PASS / 走原 then 分支 inferType 路径不破 GREEN
- `nested.ss` — H3 嵌套 ternary 反推 capture 链 — `(c1)?((c2)?null:new User("Z")):new User("A")` 外层 nSetS2="User?" + propagateTernaryBranchType 递归回填内层 nSetS2 三 case 全 GREEN(`(null)` / `Z` / `A`)
- `class_instance.ss` — H4 class 实例 ternary + D067 nullable 分配路径复用 — 多字段 class + 显式 ctor `(cond)?null:new User("X",18)` 反推 + phi=ptr 统一 GREEN(`(null)` / `Y:20`)
- `interface_upcast.ss` — H5 interface upcast via vtable indirect dispatch — `takesShape((cond)?new Circle(1.0):new Square(2.0))` 反推 callee `IShape` 后两分支 D025 vtable indirect dispatch GREEN(`3.0` / `4.0`)
- `multi_level_nullable.ss` — H3 嵌套 + null 多层 — `(c1)?null:((c2)?null:new User("X"))` 内外两层 null + 单值分支 三 case 全 GREEN(`(null)` / `(null)` / `Z`)
- `explicit_override.ss` — H6 显式 var decl 注解 > 推断 — `let n: User? = (cond)?null:new User("X"); takesNullableUser(n)` RHS 走 D084 rewrite + D067 既有路径 + fn 实参 IDENT 反推 skip GREEN
- `field_access.ss` — X4-1 字段访问 GREEN — Phase 2 resolveObjClass GROUPING/TERNARY case 修复入口实证 — `((cond)?u1:u2).name`/`.age` 走通 classFieldTypes["User.name"]="string" 路径 4 case 全 GREEN(`Alice`/18/`Bob`/20)

**§A.2 隐藏假设挑战 H1-H8 实证全 PASS + OOD/弱化标**:
- H1 funcParamTypes 时序 PASS(Phase 1 实证 + Phase 3 测试落地证据 — null_plus_T/class_instance/interface_upcast 三测试反推路径全通)
- H2 两分支类型 widen PASS(null_plus_T null+new User 路径 widen GREEN + nested 嵌套层 widen GREEN)
- H3 嵌套反推 capture 链 PASS(nested + multi_level_nullable propagateTernaryBranchType 递归回填实证)
- H4 null literal 在 ternary 分支反推 T? — D067 路径复用 PASS(null_plus_T + class_instance + multi_level_nullable null 分支按 D067 nullable 类型化)
- H5 interface upcast PASS(interface_upcast Circle/Square → IShape vtable dispatch GREEN)
- H6 显式注解优先级 > 推断 PASS(T_plus_T_explicit 显式 int + explicit_override let User? 显式注解 D084 rewrite 路径不破)
- H7 tests/ 全测 baseline 不降 PASS(284 passed / 4 failed / 288 total — 比 Phase 2 锁定 276/4/280 高 8 = 新增 d144 8 测试,4 failed 不变)
- H8 reflection_health_linter GATE PASS no regressions(全 14 指标 + F1 8 文件 cur=bv=bm 0 delta)
- H9 var binding callee OOD scope(D141/D142/D143 H9 同模式继承)
- H10 eval pre-eval 时序 PASS(Phase 1 + Phase 2 实证 — outer call site `genVal(argId)` 之前反推前移 D143 cross-D 反思继承)
- H11 callee `T?` / 结构化字符串已就绪,无 G1 callee 升级前置(比 D141 H11 弱)
- H12 parser 不需扩(`T?` 已 D067 落地,比 D141/D142/D143 H12 同位都弱)
- H13 反推失败硬错粒度 PASS — 结构化 callee 硬错(spike `/tmp/spike_d144_phase3_mismatch.ss` checker 输出 `error: ternary branches type mismatch: 'int' vs 'string'` line 9:39 GREEN — 不进 tests/ 因 SS 测试框架要求编译成功 + exit 0)/ 非结构化 callee skip

**Phase 3 兑现成果**:
- 8 测试 GREEN + spike checker 硬错铁证
- §A.2 H1-H8 全 PASS + H9-H13 OOD/弱化标全标
- VCM 六验全跑 PASS:bootstrap 三阶段固定点 + tests/d144 8/0/8 + tests/d141 5/0/5 + tests/d142 6/0/6 + tests/d143 6/0/6 + tests/ 284/4/288 baseline 不降 + reflection_health GATE PASS no regressions + d_doc_index F1=0(11 referenced Ds all live + F2 soft warn 16 含 D144 不阻)
- D135/D136/D137/D140/D141/D142/D143 范式延续(D143 Phase 3 commit `15f8dfe` 同模式 — 仅写测试 + 文档同步,无 bootstrap diff)

### Phase 4: workaround cleanup [✓] Done at commit `<placeholder>` (2026-04-28)

- 实测 grep `let \w+\s*:\s*\w+\??\s*=.*\?.*:` lib/ tests/ --include='*.ss' 排除 `tests/d144_ternary_inference/` + `tests/d067` = **0 处**(D144 §核心目标 line 31-32 反推机制 fn 实参 TERNARY 路径覆盖范围下,stdlib(`lib/base64.ss` / `lib/reactive.ss` / `lib/spring/data.ss` / `lib/json.ss` / 其他 lib/) + tests/(`phase5/null_narrowing.ss` / `phase5/i021_requestbody_nested_optional_container.ss` / 其他 tests/) 已**无临时变量绑定** `let n: int? = (x > 0) ? null : 5; takesFn(n)` 形态 workaround 候选);**lib/ 内现存 ternary 实地核查**(`grep -nE '\?[^?]+:[^:]+' lib/ --include='*.ss'` 6 处命中 — `lib/base64.ss:12-13` charCodeAt fallback 0 / `lib/reactive.ss:20+28` Map.has fallback "" / `lib/spring/data.ss:70` count > 0 fallback 1/0 / `lib/json.ss:475` parseInt == 1 fallback `"true"`/`"false"`)均为**显式两分支同类型 primitive int/string**,不属 fn 实参 ternary 反推 workaround 范畴 — 走原 then 分支 inferType 路径不破(H6 显式注解优先级 > 推断同模式)
- **Phase 4 docs-only 降级**(无 cleanup 实施 — 与 D141 Phase 4 commit `70f9457` 11 处实施 + D142 Phase 4 commit `f757aca` 4 处实施不同形;D144 Phase 4 全 0 处 cleanup 候选 → LOC delta = 0,仅 D144 文档改动 — D135/D136/D137/D140 范式同位 docs-only 终结 + D143 Phase 4 commit `b0f046c` docs-only 降级先例 同范式锚)
- **关键发现 D144 反推机制 fn 实参 TERNARY 路径 stdlib + tests/ 已无 workaround 候选** — Phase 0 §1 必读清单 + §核心目标 line 31-32 + §6 风险锚 R6 Phase 4 grep 工作量超估(已 mitigation 预设范围限定 `lib/` + `tests/d067_null_safety/` + `tests/d134_mysql/` 同域)→ Phase 4 实测确认 lib/ 全 0 + tests/ 排除 d144/d067 全 0(D141 Phase 4 已清理 lambda 类型注解 5 处 + D142 Phase 4 已清理 array literal 临时变量绑定 4 处 + D143 Phase 4 lib/+tests/ 全 0 命中);ternary `let n: T? = (cond)?null:v; takesFn(n)` 形态在 D144 反推机制覆盖范围(fn/method 实参 TERNARY 路径)下既无既有候选,亦无后续业务路径残留(用户写 `takesFn((cond)?null:v)` 直接走 G1 反推路径)
- **范围排除项**:TERNARY 不在 fn/method 实参路径的形态非 D144 Phase 4 cleanup target — (a) **NEW_EXPR ctor 实参 TERNARY**(`new Profile({...}, (x>0)?null:5)` 路径)留 §Followup F3 sub-D(D142 §F7 + D143 §F4 + D144 §F3 同根因合并锚 — Phase 2 已落 `bootstrap/eval/new_expr.ss:33` ctor args NAMED_ARG 内 TERNARY 反推但 NEW_EXPR 主线 G1 落点考量未含,留 sub-D);(b) **var decl 显式注解 D084 rewrite**(`let x: T? = (cond)?null:v` 路径)是 D084 + D067 既有路径,非 workaround;(c) **显式两分支同类型**(`(c)?1:2` / `(c)?"a":"b"` 等 lib/ 现存形态)走原 then 分支 inferType 路径,非反推 workaround 范畴;(d) **倒置类型 / 无 callee context 粒度过松**(H4+H13 mismatch silent miscompile 同位风险)留 §Followup F6 sub-D
- VCM 六验全 PASS:
  - 核心代码路径 diff=0(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出)→ **VCM §1 豁免锚成立**(bootstrap 三阶段固定点豁免)
  - `bin/ss test tests/d144_ternary_inference/` 8/0/8 不破(Phase 3 全绿延续)✓
  - `bin/ss test tests/d143_object_literal_inference/` 6/0/6 不破 ✓
  - `bin/ss test tests/d142_array_literal_inference/` 6/0/6 不破 ✓
  - `bin/ss test tests/d141_lambda_inference/` 5/0/5 不破 ✓
  - `bin/ss run tools/reflection_health_linter.ss` GATE PASS no regressions(Phase 4 docs-only 不动 bootstrap 不增量,扩容申报-Phase2 11 metric baseline 不变)✓
  - `bin/ss run tools/d_doc_index_linter.ss` PASS:11 referenced Ds all live(F1=0 死指针 / F2 soft warn 含 D144 不阻)✓
- D135/D136/D137/D140/D141/D142/D143 范式延续(每 Phase 独立 commit 大改档,Phase 4 cleanup 实施单元 — D141 Phase 4 commit `70f9457` 11 处 + D142 Phase 4 commit `f757aca` 4 处 + D143 Phase 4 commit `b0f046c` 0 处 docs-only 降级 + D144 Phase 4 commit `<placeholder>` 0 处 docs-only 降级,实测发现反推机制覆盖范围下 lib/+tests/ 全 0 cleanup 候选 — 反映 D141/D142/D143 Phase 4 已先后清理 lambda 类型注解 + array literal + object literal 临时变量绑定 后,fn/method 实参 TERNARY 路径 stdlib + tests/ 既无既有 workaround 候选)

### Phase 5: 全 Phase 收关 [ ] Planned

- D144 5 Phase commit hash 全列(占位符标记 Phase 5 单 commit 不能引用自己 hash + 下轮 hash 回填轮替换 — D141/D142/D143 范式延续)
- 兑现成果 a-g 全锁 + 隐藏假设全 PASS / OOD 标 + Followup 锚明确
- D144 主线 close,Followup F1+ 入下一 D 文档启动队列(F1 Map literal contextual typing 候选 D145 入口 — D142 §Followup F5 + D143 §Followup F2 同模式)
- D135/D136/D137/D140/D141/D142/D143 范式延续

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | Map literal contextual typing | `{ "k": "v" }` Map literal 在 fn 实参 `Map<string,string>` 反推 — array literal / object literal 同模式 sub-D(D142 §Followup F5 + D143 §Followup F2 同位)|
| F2 | Tuple literal contextual typing | tuple literal 在 fn 实参 `Tuple<int,string>` 反推 — array literal 同模式 sub-D(D142 §Followup F6 + D143 §Followup F3 同位)|
| F3 | NEW_EXPR ctor 实参子节点反推 | `new Profile({ user: {...}, addr: [...] }, (x > 0) ? null : 5)` ctor args 中 OBJ_LITERAL/ARRAY_LIT/TERNARY 反推 — D141/D142/D143 G1 4 落点未含 NEW_EXPR(D142 §Followup F7 + D143 §Followup F4 同根因合并 sub-D)|
| F4 | partial fields + ctor 默认值 | object literal 部分字段 + class ctor 漏字段默认值机制 — D143 §Followup F6 同位(若 Phase 1 实测 D084 ctor 不支持默认值)|
| F5 | spread `{...base, name: "X"}` 反推 | spread 子节点反推 + 字段覆盖 — array literal SPREAD + object literal SPREAD 同模式 sub-D(D143 §Followup F7 同位)|
| F6 | 反推失败粒度细化 | 倒置类型 silent miscompile / 无 callee context unknown kind LLC error 等粒度细化 — D143 §Followup F8 H4+H13 同形(本 D §A.2 H2 mismatch 同位风险)|
| F7 | bidirectional type checking 全局 | C3 候选废案,留作未来 SS 类型系统 v2(D026/D027 落地后再开 D 文档评估,D141 §Followup F5 + D142 §A.3 + D143 §A.3 同位)|

---

## Status 时间线

- 2026-04-27 Phase 0 D 文档落档(commit `02415c9`)— D141 §Followup F3 / D142 §Followup F2 / D143 §Followup F1 ternary contextual typing 候选入口落档(同模式合并锚);C2 接口层 trap + G1 D141/D142/D143 同模式复刻路径决策(待 Phase 1 用户对话锁定方向后启动实施);§A.1 三主候选 + §A.1.1 三实施路径 + §A.2 H1-H13 隐藏假设挑战(H10 cross-D 反思继承 D143 教训)+ §A.3 废案 + Phase 0-5 计划草案 + Followup F1-F7(D141/D142/D143 §Followup 合并队列重排);D135/D136/D137/D140/D141/D142/D143 范式延续(每 Phase 独立 commit 大改档 + Status 收关 + commit hash 回填 + next_prompt 自闭环)
- 2026-04-27 Phase 1 RED 复现 + 信息源探查(commit `17a1573`)— 主线 7 形态实测全 GREEN(`/tmp/spike_ternary_red.ss` null+User? / T+T 显式 / 嵌套 / class 实例 / interface upcast / 多层 nullable / fn 返回 ternary)+ D144 §第一性需求 motivating example 修正(D067 不允许 primitive nullable `int?`,改用 reference 类型 `User?`)+ 真 RED 形态另立(X4-1 字段访问 LLC `'%14' defined with type 'ptr' but expected 'i32'` + X mismatch 两分支类型不一致 LLC `global variable reference must have pointer type` 双铁证)+ §A.2 H1 同模式实证 PASS(funcParamTypes 时序)+ §A.2 H10 cross-D 反思继承 PASS(eval pre-eval 时序 — `feedback_h10_cross_d_verify.md` D143 教训继承)+ TERNARY 节点 slot 选 nSetS2 锁定 + TERNARY 8 dispatch site 全 grep PASS + Phase 2 入口全锁
- 2026-04-27 Phase 2 codegen 阶段反推实施(commit `71af131`)— G1 D141/D142/D143 同模式复刻 — checker check_exprs.ss + check_types.ss + gen_types.ss inferType + resolveObjClass + helper 5 函数(isNullableType / extractInnerType / unifyBranchTypes / propagateTernaryBranchType / inferTernaryBranchType)+ gen_calls.ss / gen_methods.ss args 循环 + eval pre-eval 三处前移(method_call.ss / call.ss / new_expr.ss)+ ternary.ss phi llType 反推 + spike X4-1 + X mismatch RED→GREEN 双铁证 + bootstrap 三阶段固定点 PASS + tests/ 276/4/280 baseline 不降 + reflection_health GATE PASS 扩容申报 D144#扩容申报-Phase2 11 metric bump;关键 bug 修复:checker 排除 `"null"` 同类型回填 + helper 完整递归(非单层 H3 嵌套反推链路)
- 2026-04-28 Phase 3 测试覆盖 + 隐藏假设挑战(commit `959a2de`)— `tests/d144_ternary_inference/` 8 测试全绿(null_plus_T / T_plus_T_explicit / nested / class_instance / interface_upcast / multi_level_nullable / explicit_override / field_access)+ spike `/tmp/spike_d144_phase3_mismatch.ss` checker 硬错铁证(`error: ternary branches type mismatch: 'int' vs 'string'`)+ §A.2 H1-H8 全 PASS + H9-H13 OOD/弱化标全标(H9 var binding OOD / H10 eval pre-eval 时序 cross-D 反思继承 PASS / H11 callee 结构化已就绪 / H12 parser 不需扩 / H13 反推失败粒度 spike 硬错铁证)+ VCM 六验全 PASS(bootstrap 三阶段固定点 + tests/d144 8/0/8 + tests/d141 5/0/5 + tests/d142 6/0/6 + tests/d143 6/0/6 + tests/ 284/4/288 baseline 不降 + reflection_health GATE PASS no regressions + d_doc_index F1=0)+ D135/D136/D137/D140/D141/D142/D143 范式延续(D143 Phase 3 commit `15f8dfe` 同模式 — 仅写测试 + 文档同步,无 bootstrap diff)
- 2026-04-28 Phase 4 workaround cleanup(commit `<placeholder>`)— **docs-only 降级 0 处 cleanup**(grep `let \w+\s*:\s*\w+\??\s*=.*\?.*:` lib/ tests/ 排除 `tests/d144_ternary_inference/` + `tests/d067` = **0 命中** + lib/ ternary 6 处实地核查 base64/reactive/spring-data/json 均显式两分支同类型 primitive int/string 非反推 workaround 范畴);LOC delta = 0 仅文档改动 — D135/D136/D137/D140 同位 docs-only 终结 + D143 Phase 4 commit `b0f046c` 0 处 docs-only 降级 同范式锚(D141 Phase 4 commit `70f9457` 11 处 + D142 Phase 4 commit `f757aca` 4 处实施不同形);**关键发现**:D144 反推机制 fn 实参 TERNARY 路径 stdlib + tests/ 已无 workaround 候选,反映 D141/D142/D143 Phase 4 已先后清理 lambda 类型注解 + array literal + object literal 临时变量绑定 后,fn/method 实参 TERNARY 路径既无既有候选亦无后续残留(用户写 `takesFn((cond)?null:v)` 直接走 G1 反推路径);VCM 六验全 PASS(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 → §1 豁免锚成立 + tests/d144 8/0/8 + tests/d143 6/0/6 + tests/d142 6/0/6 + tests/d141 5/0/5 + reflection_health GATE PASS 11 metric baseline 不变 + d_doc_index F1=0);D135/D136/D137/D140/D141/D142/D143 范式延续
- 2026-04-27 Phase 1 RED 复现 + 信息源探查(commit `17a1573`)— **重大发现**:D144 §第一性需求 motivating example `int?` callee 在 D067 下不合法(`bootstrap/checker/check_narrow.ss:6` `primitive type 'int' cannot be nullable`)+ 改用 `User?` 后主线 7 形态(null+class / T+T 显式 / 嵌套 / class 实例 / interface upcast / 多层 nullable / fn 返回)实测**全 GREEN**(两分支 ptr 一致路径 phi 自然统一);真 RED 形态另立 — (a) **X4-1**:`((cond)?u1:u2).name` 字段访问触发 LLC `'%14' defined with type 'ptr' but expected 'i32'`(TERNARY inferType 在字段访问链路 resolveObjClass 失败,fallback 走 i32 路径);(b) **X mismatch**:`takesInt((cond)?1:"X")` 两分支类型不一致触发 LLC `global variable reference must have pointer type`(checker `check_exprs.ss:304-309` 仅依次 checkExpr 三子节点不查类型一致性 silent miscompile);**真主战场**:TERNARY inferType 信息源破裂(`check_types.ss:201` + `gen_types.ss:541` 单一返 then 分支 `inferType(nGetI2(id))` — Phase 2 改入口锚已锁);§A.2 H1 实证 PASS(funcParamTypes 时序 — `gen/codegen.ss:110-112` 普通函数 + `gen/gen_registry.ss:56-57` class method + `gen/codegen.ss:326` registerAllDecls 在 emitGlobalsAndCode 之前 — D141/D142/D143 同模式继承 PASS);§A.2 H10 cross-D 反思继承 PASS(eval/method_call.ss:36-70 + eval/call.ss:18-43 + eval/new_expr.ss:24-41 三处 outer call site pre-eval `genVal(argId)` 之前 D141/D142/D143 反推前移落锚 line 61-65/33-39/27-41 — D144 同点追加 `inferTernaryBranchType(argId, callee, idx)` 第 4 行,**不仅 grep 字面 handler `evalTernary`** — D143 H10 教训继承);TERNARY 节点 slot 占用探查 PASS(`parse_exprs.ss:13-16` parseExpr ternary 占 i1/i2/i3,**s1/s2/s3+i4+nList 全空闲** — Phase 2 选 nSetS2 与 D141 ARROW_FUNC PARAM s2 + D142 ARRAY_LIT s2 + D143 OBJ_LITERAL s2 同范式);TERNARY kind dispatch 全 grep PASS 8 处(parse_exprs.ss:13 parser + check_exprs.ss:304 checker case + check_types.ss:201 checker inferType + gen/exprs/exprs.ss:68 genVal dispatch + gen_types.ss:541 codegen inferType + eval/eval_expr.ss:64 evalExpr dispatch + eval/ternary.ss:4-33 evalTernary handler + pir/pir_lower.ss:252 PIR use 分析 — PIR 仅递归收集 use 不破反推链路);D135/D136/D137/D140/D141/D142/D143 范式延续(D143 Phase 1 commit f089738 同模式)
