# D143: SS Object Literal Contextual Typing — 字段类型从调用上下文反推

**Status:** Phase 5 — 全 Phase 收关 [✓] Done at commit `<TBD>` (2026-04-27)— **D143 主线 close**,5 Phase commit hash 全列(Phase 0 `50912b4` / Phase 1 `f089738` / Phase 2 `5eb722e` / Phase 3 `15f8dfe` / Phase 4 `b0f046c` / Phase 5 `<TBD>`)+ **兑现成果 a-g 全锁**(a. C2 接口层 trap 落地 — `check_exprs.ss:285` OBJ_LITERAL untyped 放行(D141 ARROW_FUNC + D142 ARRAY_LIT 同模式不硬错)+ `check_types.ss` inferType OBJ_LITERAL case fallback "auto" + `gen_types.ss` 三 helper `isClassType`/`extractClassName`/`inferObjLiteralFromType`+`inferObjLiteralFields` + inferType OBJ_LITERAL case 优先读 nGetS2 + `gen_calls.ss:284` + `gen/methods/gen_methods.ss:206` args 循环反推 + eval pre-eval 前移三处 `eval/call.ss:36` + `eval/method_call.ss:64` + `eval/new_expr.ss:24` + `class/class_method.ss:genNamedConstructorArgs` H3 嵌套反推 + D084 rewrite 复用扩 fn 实参入口 / b. workaround cleanup 0 处全 0 候选 — Phase 4 docs-only 降级(grep `let \w\+: \w\+ = {` lib/+tests/ 排除 explicit_override+object_literal.ss = 0)反映 D141/D142 Phase 4 已清理后 fn/method 实参 OBJ_LITERAL 路径既无既有 workaround 候选 / c. H1-H13 全 PASS / H9/H11/H12 OOD 标 + H4 决策行严格模式 + H5 部分 OOD scope Array<int>/Map<K,V> 字段反推留 §Followup F4 + H13 粒度过松反向问题(倒置类型 silent miscompile segfault + 无 callee context unknown kind LLC error)留 §Followup F8 + H10 cross-D 实证 SSoT 反思 memory `feedback_h10_cross_d_verify.md` 落档 / d. axiom 红线 `feedback_root_cause_no_cost.md` + `feedback_no_option_menu.md` + `feedback_no_derive_workaround.md` grep = 0 永久 / e. d_doc_index_linter PASS — 10 referenced Ds all live + F2 soft warn 12 orphan 含 D143 不阻 / f. reflection_health_linter GATE PASS — 扩容申报-Phase2 6 metric bump 永久(M1=5450→5550 / M2=80000→81600 / M4=3109→3250 / N2=400000→408000 / N3=550000→562000 / F1:gen_types.ss=915→970)+ Phase 3+4+5 不动 bootstrap 不增量 / g. bootstrap 隔离破例 D141 §核心原则 5 + D142 §核心原则 6 同位例外 — 修编译器主线消除 stdlib workaround 是法定 root cause 路径)+ **§Followup F1-F8 锚明确**(F1 ternary contextual typing 候选 **D144 入口** / F2 Map literal / F3 Tuple literal / **F4 NEW_EXPR ctor 实参子节点反推 OBJ_LITERAL+ARRAY_LIT 同形** D142 §F7 + D143 §F4 同根因合并 sub-D / F5 bidirectional v2 留 / **F6 partial fields + ctor 默认值** Phase 3 H4 严格模式决策行 sub-D / F7 spread `{...base, name: "X"}` 反推 / **F8 反推失败粒度细化 H4+H13 同形** Phase 3 H13 实测铁证 sub-D)+ Phase 5 docs only 1 file 改(D135/D136/D137/D140/D141/D142 范式延续 — 单 commit 大改档终结 Phase 5 docs-only 不分 feat/docs 双 commit)+ Phase 4 — workaround cleanup [✓] Done at commit `b0f046c` — **grep 实测 0 命中**(`grep -rn 'let \w\+: \w\+ = {' lib/ tests/ --include='*.ss' | grep -v 'explicit_override\|object_literal.ss'` = 0,排除 D143 Phase 3 自测 explicit_override.ss + D084 既有 baseline tests/phase5/object_literal.ss)+ **Phase 4 docs-only 降级**(无 cleanup 实施 — 与 D141 Phase 4 commit `70f9457` 11 处 + D142 Phase 4 commit `f757aca` 4 处不同形;D143 Phase 4 全 0 处 cleanup 候选 → LOC delta = 0,仅 D143 文档改动)+ **关键发现 D143 反推机制 fn 实参 OBJ_LITERAL 路径 stdlib + tests/ 已无 workaround 候选**(`lib/spring/data.ss` D141 Phase 4 已清理 lambda 类型注解 5 处 + 既无 OBJ_LITERAL fn 实参绑定形态;其他 lib/(`json` / `url` / `argparse` / `path` / `string_utils` / 其他)+ tests/(`d134_mysql` / `phase5/` / 其他)同 0 命中 — `let u: User = {...}; takesFn(u)` 形态在反推机制覆盖范围下既无既有候选,亦无后续业务路径残留)+ **范围排除项**(a) **NEW_EXPR ctor 实参 OBJ_LITERAL** 留 §Followup F4 sub-D(D142 §F7 + D143 §F4 同根因合并锚 — `bootstrap/gen/class/class.ss:288-301 genNewExpr` args 循环未调 `inferObjLiteralFields`);(b) **var decl 显式注解 D084 rewrite** 是 D084 既有路径非 workaround;(c) **partial fields / 默认值** 留 §Followup F6 sub-D(Phase 3 H4 LLC error 严格模式决策行落档);(d) **倒置类型 / 无 callee context 粒度过松** 留 §Followup F8 sub-D(Phase 3 H13 实测 segfault + unknown kind LLC error)+ VCM 六验全 PASS(核心代码路径 diff=0 `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空 → **VCM §1 豁免锚成立** bootstrap 三阶段固定点豁免 + tests/d143_object_literal_inference 6/0/6 不破 + tests/d142_array_literal_inference 6/0/6 不破 + tests/d141_lambda_inference 5/0/5 不破 + reflection_health_linter GATE PASS no regressions 不动 bootstrap 不增量 + d_doc_index_linter PASS 10 referenced Ds all live + F2 soft warn 12 orphan 含 D143 不阻 + ultrathink_linter)— D135/D136/D137/D140/D141/D142 范式延续(D141 Phase 4 commit `70f9457` 11 处 + D142 Phase 4 commit `f757aca` 4 处 + D143 Phase 4 commit `b0f046c` 0 处 docs-only 降级 同模式 lib/+tests/ 全 0 cleanup 候选 — 反映 D141/D142 Phase 4 已清理后 fn/method 实参 OBJ_LITERAL 路径既无既有 workaround 候选)。Phase 3 完结 commit `15f8dfe` 测试覆盖 6/0/6 全绿(`single_field` H1 / `multi_field` H2 / `nested` H3 / `mixed_field` H5 string+int+double 异质 / `explicit_override` H6 D084 路径 / `interface_upcast_skip` H5b NEW_EXPR + vtable indirect)+ §A.2 H1/H2/H3/H5/H5b/H6/H7/H8 全 PASS + H4 决策行严格模式 + H5 部分 OOD scope + H13 粒度过松反向问题实证 + §A.2 H10 cross-D 实证 SSoT 反思 memory 落档(`feedback_h10_cross_d_verify.md`)+ Followup F4/F6/F8 加锚。Phase 2 完结 commit `5eb722e` codegen 反推 + G1 D141/D142 同模式复刻 + §A.2 H10 OOD 实证错估修正 + spike `Y:18` + `Z@Earth` GREEN。Phase 1 完结 commit `f089738` RED 复现 + §A.2 H1 funcParamTypes 时序 PASS + OBJ_LITERAL slot 探查 PASS。Phase 0 完结 commit `50912b4` D 文档落档。**Phase 5 完结** — D143 主线 close,Followup F1-F8 入下一 D 文档启动队列(**F1 ternary contextual typing 候选 D144 入口** — D141 §Followup F3 / D142 §Followup F2 同模式)。
**Depends on:**
- D141(lambda 参数类型推断 + interface dispatch 集成 — §Followup F2 line 422 锚)
- D142(array literal contextual typing — §Followup F1 line 484 + line 514 同模式锚)
- D141 §A.1.1 G1 路径 + D142 §A.1.1 G1 路径(callee PARAM 结构化签名 + codegen 阶段反推 + eval pre-eval 时序)— D143 G1 同模式复刻
- D141 §A.2 H1/H10/H11/H13 + D142 §A.2 H1-H13(funcParamTypes 时序 / setVarType 自然链路 / callee 结构化必要 / 失败硬错粒度)— D143 同模式假设挑战
- D025(interface dispatch — 字段值是 interface 实现类时 vtable 路径)
- D131(`Array<T?>` nullable inner field 反序列化 + stripNullableCG 路径 — class field 级 null 处理)
- D084(object-literal-export — `let x: ClassName = {...}` rewrite OBJ_LITERAL → NEW_EXPR 路径,D143 扩到 fn 实参反推)
- `bootstrap/checker/check_exprs.ss:285` OBJ_LITERAL checker 入口
- `bootstrap/parse/parse_exprs.ss:521` OBJ_LITERAL AST 节点构造
- `bootstrap/checker/check_stmts.ss:112-113` D084 rewrite 路径(typeAnn != "" 时 rewrite NEW_EXPR)
- `bootstrap/gen/gen_decls.ss:512-513` codegen 同 D084 rewrite
- CLAUDE.md §Java/TS 语法优先(TS object literal contextual typing 主线 / Java record `new Record(name, age)` Type 推断)
- CLAUDE.md §Root Cause 优先 第一法则(数据层 patch 不允许,接口层 trap 单点信息源)
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优的理由)
- `memory/feedback_no_option_menu.md`(三候选论证 + 决策行)
- `memory/feedback_no_derive_workaround.md`(主线能力缺口不允许 annotation 替代)
- `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验 (Plan 型 §④ 替换「替代方案对比 + 隐藏假设挑战」)+ §字段 8 "Layer 跨越触发 stop / D 文档独立审查窗口不许吞"

**Date:** 2026-04-27
**Last Updated:** 2026-04-27

---

## 核心目标 (Goal)

- **为什么**:object literal `{ name: "X", age: 18 }` 当前 checker `check_exprs.ss:285` OBJ_LITERAL 入口无 fn 实参反推路径,信息丢失;在 fn 实参 `user: User` 场景,反推不到 class 名 → callee 端类型不匹配 silent fallback 或硬错;D084 已落地 `let x: ClassName = {...}` rewrite 路径(`check_stmts.ss:112-113` + `gen_decls.ss:512-513`),但 fn 实参路径无对应反推 — 用户写 `takesUser({ name: "X", age: 18 })` 必先临时变量绑定 `let u: User = {...}; takesUser(u)`(D084 rewrite 入口 typeAnn != "" 才触发);D141 §Followup F2 + D142 §Followup F1 锁此 follow-up 是反推机制同模式扩到 OBJ_LITERAL 的候选。**末层断言可观测否定证据**(本 Phase 0 实测):`ls docs/3-decisions/D143*.md 2>&1` 当前 = `No such file or directory`(exit=2)— D143 文档落档 RED 成立,本轮 Phase 0 GREEN(commit hash 回填后 `ls` 命中)。
- **是什么**:在 object literal 作 fn/method 实参时,从 callee 签名查 `funcParamTypes` 反推 OBJ_LITERAL 节点 class 名,**eval pre-eval 阶段**反推回填 OBJ_LITERAL 节点 className slot(参 D141 H1 实证 — checker 阶段 funcParamTypes 用户函数为空,反推必须在 codegen 阶段;参 D141 H10 + D142 H10 实证 — eval pre-eval 在 OBJ_LITERAL emit 之前,反推必须前移到 eval pre-eval 之前);后续 codegen `genObjLiteral` 内 D084 rewrite 入口扩反推路径(typeAnn = "" + 反推得 className → 同 D084 rewrite NEW_EXPR),链路自然走通。配合 `check_exprs.ss:285` OBJ_LITERAL inferType 不再返单一 `"object"` / `""`,改返 `class<ClassName>` 结构化签名(类型表达力前置,与 ARROW_FUNC `fn(P,...):R` + ARRAY_LIT `Array<elemType>` 结构化前置完全同形)。
- **单一判据**:untyped object literal spike(写 `takesUser({ name: "X", age: 18 })` 直接传入 fn 形参 `user: User`)= D143 §第一性需求 末层断言 RED → 根因修后实测 spike GREEN(对照 IR `call ptr @User_new(...)` + 字段值 string/int box 路径正确,无 silent miscompile);且 lib/spring/data.ss + tests/d134_mysql + 其他 lib/ 现存 fn 实参 object literal workaround(若有 `let u: User = {...}; takesFn(u)` 临时绑定形态)Phase 4 cleanup 全删。

> 一句口号:**object literal 字段类型 + class 名从调用上下文反推 — 用户不必每处临时绑定带类型注解的变量**(D141 反推机制 + D142 elemType 反推机制同模式扩到 OBJ_LITERAL)

---

## 核心原则 (Principles)

1. **接口层 trap,非数据层 patch** — 信息源单点回填(eval pre-eval 阶段 OBJ_LITERAL 节点 className slot),codegen 路径不变;不在 genObjLiteral / gen_calls.ss / D084 rewrite 多处零散补 fallback(`feedback_root_cause_no_cost.md` 红线)
2. **D141/D142 反推机制同模式扩** — eval pre-eval 时序 + funcParamTypes 信息源 SSoT + codegen 阶段反推 + 失败硬错粒度均沿 D141/D142 §A.1.1 G1 路径;D141 §A.2 + D142 §A.2 假设挑战范式直接复刻
3. **bidirectional type checking 局部** — 仅 object literal 作 fn/method 实参场景反推,不扩到全编译器全表达式 contextual typing(scope 防爆炸,与 D141 §核心原则 2 + D142 §核心原则 3 同位)
4. **TS / Java 8+ contextual typing 主线** — TS 既有能力(`fn arg object literal inferred from param class type`)+ Java 16+ record(`new Record(name, age)` 推断,用户仍可手写 `let u: User = {...}` override 推断,D084 rewrite 既有路径不破 — Java 8+ 风格保留)
5. **D084 rewrite 路径复用** — D084 已落 `let x: ClassName = {...}` rewrite OBJ_LITERAL → NEW_EXPR(`check_stmts.ss:112-113` + `gen_decls.ss:512-513`);D143 反推得 className 后**复用 D084 rewrite 同函数**(无重写),fn 实参路径走 rewrite 入口,信息源单点
6. **callee PARAM 已结构化(无需 G1 callee 升级)— 比 D141/D142 同位** — D141 G1 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn`(parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析);D142 callee `Array<T>` 已结构化无升级前置;D143 callee `class User` / `class PreparedStatement` 类型 annotation 已就绪(普通 class IDENT type 已解析,**比 D141 H11 弱** — class 名是 IDENT 单 token 无嵌套 generic 解析需求)— Phase 2 不需要 parser 扩
7. **bootstrap 隔离破例** — D141 §核心原则 5 + D142 §核心原则 6 同位例外,D143 主线改 bootstrap 修编译器(checker + codegen + eval),与其他 sub-D scope 独立
8. **interface dispatch 不破** — D025 `interface PreparedStatement` 契约 + vtable indirect dispatch 路径不动;D131 `Array<T?>` nullable inner field 反序列化路径不动
9. **funcParamTypes SSoT 复用** — 信息源 `bootstrap/gen/gen_registry.ss:9-10 + 56`(`funcParamTypes` Map "funcName:paramIndex" → SS type),codegen 阶段反推时直接消费,不重复注册;class 名 `User` / `PreparedStatement` 字符串注册路径已存(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57 已注册原始 SS 类型)
10. **零破坏既有 object literal** — 现存 `let x: ClassName = {...}` D084 rewrite 路径(60+ 处)继续走原 rewrite,Phase 2 反推仅在 object literal 作 fn/method 实参 + className 未知时 fallback 反推,显式优先级 > 推断
11. **Phase 计划独立 commit** — 大改档位:Phase 0 D 文档落盘 + Phase 1+ bootstrap 改各独立 commit,§MNK 大改档不打包(D135/D136/D137/D140/D141/D142 范式延续)
12. **VCM 六验全跑** — bootstrap 三阶段固定点 + tests/ 不降 + tests/phase5/object_literal_*.ss 等 baseline 不降 + reflection_health_linter GATE PASS no regressions

---

## 1. Context Management

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D143)
2. CLAUDE.md §Java/TS 语法优先 + §Root Cause 优先 第一法则 + §高层架构 + §交互式单文档
3. 依赖 D 文档:
   - D141 §A.1.1 G1 路径 + §A.2 H1/H10/H11/H13(line 200-209 + 217-230)
   - D142 §A.1.1 G1 路径 + §A.2 H1-H13(全 PASS)
   - D141 §Followup F2(line 422) + D142 §Followup F1(line 484 + 514)— D143 入口锚
   - D025 interface dispatch
   - D084 object-literal-export(rewrite 路径)
4. 关键代码位置(Phase 1 探查后精确化 line 号):

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/parse/parse_exprs.ss` | 500-523 | OBJ_LITERAL parser:LBRACE 入口 line 501 + 字段 list `IDENT COLON VALUE → NAMED_ARG(s1=fieldName, i1=valId)` line 511-514 + `newNode("OBJ_LITERAL")` line 521 + 仅 `nSetList(id, fields)` line 522(**Phase 1 实证:s1/s2/s3 + i1/i2/i3/i4 全空闲** — Phase 2 选 nSetS2 与 ARRAY_LIT(D142) / ARROW_FUNC PARAM(D141) s2 同范式)|
   | `bootstrap/checker/check_exprs.ss` | 285-287 | **OBJ_LITERAL checker 入口 — 当前破裂入口**(直接 `checkerError("object literal requires type annotation", ...)` + return,**比 D141/D142 RED 更硬** — 不是 silent miscompile / silent fallback scalar,而是 checker 阶段直接拒绝);Phase 2 改:先读 `nGetS2(id)` 反推 className,反推得 → skip checkerError(让 D084 rewrite 入口接管);反推不得 + 非 typed 上下文 → 仍 checkerError 硬错粒度 |
   | `bootstrap/checker/check_stmts.ss` | 107-117 | **D084 rewrite 路径**:line 112-113 `if (initId > 0 && nGetKind(initId) == "OBJ_LITERAL" && typeAnn != "")` rewrite NEW_EXPR(`nKind.set(initId+"", "NEW_EXPR"); nSetS1(initId, typeAnn)`)— D143 复用同 helper + 扩 fn 实参路径(typeAnn = "" 但 nGetS2 反推得 className → 同模式 rewrite)|
   | `bootstrap/gen/gen_decls.ss` | 507-516 | codegen 层 D084 rewrite 同函数 line 512-513(arrow body skipped by checker 路径)— D143 同步扩 |
   | `bootstrap/checker/check_types.ss` | 50-71 | ARRAY_LIT inferType 优先读 `nGetS2(nodeId)` arrLitS2 → `Array<elemType>` 结构化,fallback elem 推导 — D142 G1 范式 D143 复刻 |
   | `bootstrap/checker/check_types.ss` | 72-93 | ARROW_FUNC inferType 优先读 PARAM list s2 → `fn(P,...):R` 结构化,降级 `"fn"` — D141 G1 范式 D143 复刻 |
   | `bootstrap/gen/gen_types.ss` | 242 + 542-543 | inferType 主体入口 line 242 + `kind == "ARRAY_LIT"` 简化返 "ptr" / `kind == "ARROW_FUNC"` 简化返 "fn"(**实证:gen_types.ss 无显式 OBJ_LITERAL case,fallback `return "int"` line 566**)— Phase 2 加 OBJ_LITERAL case 优先读 nGetS2 反推 className,降级 fallback |
   | `bootstrap/gen/gen_calls.ss` | (Phase 2 反推插桩入口) | fn callee args 解析 — Phase 2 反推主入口候选(D141 + D142 同点反推主入口)|
   | `bootstrap/gen/methods/gen_methods.ss` | (Phase 2 反推插桩入口) | class method args 解析 — Phase 2 反推第二落点(D141 + D142 G1 同模式)|
   | `bootstrap/gen/gen_registry.ss` | 9-10 + 53-65 + 67-72 | line 9-10 funcParamTypes Map 声明 + line 53-65 class method 注册 `registerClassMethodRetType` + line 56-57 `funcParamTypes.set(${baseName}:${pCount}, nGetS2(pId))` 含 mangled + line 67-72 `initFuncRetTypes`(`funcParamTypes = Map()`)— Phase 2 反推直接消费,**不改注册路径**(已就绪)|
   | `bootstrap/gen/codegen.ss` | 100-122 + 326 | 普通函数 funcParamTypes 注册 line 110-112(`registerFuncDeclNode`)+ line 326 `registerAllDecls(rootId)` 在 `emitGlobalsAndCode(rootId)` 之前 — H1 时序就绪 |
   | `bootstrap/eval/` | 17 文件全 grep | **OBJ_LITERAL 0 命中**(`evalObjLiteral` 不存)— **D143 H10 OOD**:eval 阶段无 OBJ_LITERAL handler,反推不需要前移到 eval pre-eval(比 D141 eval/method_call.ss + eval/call.ss + D142 eval/array_lit.ss 全弱)|
   | `lib/spring/data.ss` | (Phase 4 grep 实测后定计数)| Phase 4 cleanup 候选 |
   | `tests/phase5/` | (Phase 1 grep `OBJ_LITERAL`)| object literal baseline(D143 Phase 4 cleanup 不破现状)|
   | `bootstrap/gen/gen_types.ss` | (Phase 2 helper 落锚)| **Phase 2 新加 helper**:`isClassType` / `extractClassName` / `inferObjLiteralFields` — 对偶 D141 isFnType / extractFnParamType / inferArrowFuncParams + D142 isArrayType / extractArrayElemType / inferArrayLitElems |
   | `/tmp/spike_obj_lit_red.ss` | 全文 60 行 | **Phase 1 RED 已写**(commit `f089738`,本 Phase 1 实证)— 3 形态(单字段 / 多字段 / 嵌套);RED 实测 `bin/ss build /tmp/spike_obj_lit_red.ss --emit-ir 2>&1 | grep -c "object literal requires type annotation"` = **3**(line 45:43 / 49:46 / 53:74 全命中)|

### Stable Facts

| 项 | 值 |
|---|---|
| 现存 callee `class X` 用例 | 待 Phase 1 grep 实测(预估 lib/spring/data.ss + lib/spring/jdbc.ss + tests/ 多处) |
| class 名类型解析 | parser 已就绪(class 名是 IDENT 单 token,无嵌套 generic — 比 D142 H12 更弱) |
| funcParamTypes class 名注册 | 已就绪(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57 直接注册原始 SS 类型字符串) |
| D084 rewrite helper | 已就绪 check_stmts.ss:112-113 + gen_decls.ss:512-513 |
| OBJ_LITERAL inferType 当前 | 待 Phase 1 实测(checker.check_exprs.ss:285 单一 ""/"object" — D143 §A.1 主候选 C2 修复入口) |
| 反射 baseline | tools/reflection_health_linter.ss(本 D 不触反射) |
| d_doc_index_linter F1 | Phase 0 落盘后 D143 加入,referenced D 文档 D025/D084/D131/D141/D142 实存 → F1 = 0 |

### 禁止的 Context 操作

- ❌ 改 parser(class 名类型 annotation 解析已就绪 — §核心原则 6 + H12 弱)
- ❌ 改 funcParamTypes 注册路径(已就绪 — §核心原则 9)
- ❌ 改 D084 rewrite 路径本体(已就绪 check_stmts.ss:112-113 + gen_decls.ss:512-513,D143 复用扩 fn 实参入口,不重写)
- ❌ 起 D144/D145(留 D141 §Followup F3 / D142 §Followup F2/F5/F6 同模式扩展)
- ❌ 改 D141/D142 文档本体(D141 §核心原则 5 + D142 §核心原则 6 例外锚 D143 同模式继承,文档不动)
- ❌ 改 D025/D131 interface dispatch / 反序列化契约
- ❌ 加全局 bidirectional type checking(C3 候选废 — 范围爆炸,留 SS 类型系统 v2)

---

## 2. Tools

| 工具 | 用途 |
|---|---|
| `./build.sh bootstrap` | 三阶段固定点(Phase 1+ bootstrap 改后必跑) |
| `bin/ss run /tmp/spike_obj_lit_red.ss` | spike RED→GREEN 验证(主判据,Phase 1 写入 + Phase 2 实测) |
| `bin/ss test tests/phase5/` | object literal baseline 5 处不降 |
| `bin/ss test tests/d141_lambda_inference/` | D141 反推机制 baseline 不破 |
| `bin/ss test tests/d142_array_literal_inference/` | D142 反推机制 baseline 不破 |
| `bin/ss test tests/` | 全测 baseline 不降 |
| `bin/ss build /tmp/spike_obj_lit_red.ss --emit-ir` | IR 层 RED 复现(Phase 1) |
| `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate |
| `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射) |
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ 新关键字 / 新语法 / 新 AST 节点(object literal 反推是反推机制扩展,非语法扩展;OBJ_LITERAL 节点已存 parse_exprs.ss:521)
- ❌ 新依赖
- ❌ 改 codegen / parser / interpreter / lib(Phase 2 改 checker + 局部 codegen 反推 + eval pre-eval 反推插桩 + D084 rewrite 复用扩)

---

## 3. Orchestration

### 总体节奏(D141/D142 5 Phase 范式延续)

| Phase | 目标 | 关键产出 | 验证 |
|-------|------|----------|------|
| **Phase 0** | D 文档落档(本 Phase) | `docs/3-decisions/D143-*.md` | d_doc_index_linter F1 = 0 + ultrathink_linter PASS |
| **Phase 1** | RED 复现 + 信息源探查 | `/tmp/spike_obj_lit_red.ss`(形态 1-7:单字段 / 多字段 / 嵌套 OBJ_LITERAL / 部分字段 / class 字段类型混合 / fn 实参 + IDENT type / interface upcast 不可走)+ IR 层 RED 铁证 + funcParamTypes class 名字符串实测可用(grep 实证)+ eval pre-eval vs codegen emit 时序探查(确认 D141/D142 H10 同形成立)+ 隐藏假设 H1/H10 复刻验证 + OBJ_LITERAL 节点 slot 占用探查(parse_exprs.ss:521 后 s1/s2/s3/i1-i4 槽位)| IR RED 铁证(若有)+ 时序探查 fact 入 §1 + §A.2 H1/H10 实证记录 + 节点 slot 探查 PASS |
| **Phase 2** | codegen 阶段反推实施 + G1 路径(D141/D142 G1 同模式) | `bootstrap/checker/check_exprs.ss:285` OBJ_LITERAL 改返 `class<ClassName>` 结构化(与 ARROW_FUNC + ARRAY_LIT 同形)+ `bootstrap/gen/gen_calls.ss:resolveCallArgs` + `gen/methods/gen_methods.ss:emitClassMethodCall` 内 args 循环识别 OBJ_LITERAL + 查 funcParamTypes class 名 + 反推回填 OBJ_LITERAL 节点 className slot + `eval/method_call.ss + eval/call.ss` pre-eval 之前反推前移 + `bootstrap/gen/gen_types.ss` 三 helper(`isClassType` / `extractClassName` / `inferObjLiteralFields`)对偶 D141 + D142 helper + **D084 rewrite 复用扩 fn 实参路径**(typeAnn = "" 但反推得 className → rewrite NEW_EXPR) | bootstrap 固定点 PASS + spike untyped 反推 GREEN + tests/phase5/object_literal_*.ss baseline 不降 |
| **Phase 3** | 测试覆盖 + 隐藏假设挑战 | `tests/d143_object_literal_inference/` 新增(单字段 / 多字段同质 / 嵌套 OBJ_LITERAL / 部分字段 / class 字段类型混合 / interface upcast 不可走 / 显式优先 / 推断失败硬错诊断)| 6+ test case 全绿 + 隐藏假设 H1-H8 全 PASS |
| **Phase 4** | workaround cleanup | grep + 删现存 fn 实参 object literal 临时变量绑定 workaround(若有 `let u: User = {...}; takesFn(u)` 形态 — Phase 1 grep 实测后定计数;预估 lib/spring/data.ss + tests/d134_mysql 多处) | bootstrap 固定点 PASS + tests/ baseline 不降 |
| **Phase 5** | 全 Phase 收关 hash trail | D143 5 Phase commit hash 全列 + 兑现成果 a-g + 隐藏假设全 PASS / OOD 标 + Followup 锚明确 | D143 主线 close |

### Phase 间依赖

- Phase 0 → 1:D 文档落档后用户审,Phase 1 下一轮起
- Phase 1 → 2:RED 成立 + 时序探查就位才启 Phase 2;若 H1 funcParamTypes 时序不就(D141/D142 实证已 PASS,但 OBJ_LITERAL 路径需独立验证)→ 调整 Phase 2 入口
- Phase 2 → 3:bootstrap 固定点 PASS + spike GREEN 才启 Phase 3 测试覆盖
- Phase 3 → 4:测试覆盖完整(隐藏假设全 PASS)才启 Phase 4 workaround cleanup
- Phase 4 → 5:cleanup 完整 + tests/ baseline 不降才启 Phase 5 收关

### 反模式

- ❌ 改 parser(class 名 annotation 已就绪 — H12 比 D141/D142 更弱)
- ❌ 改 funcParamTypes 注册路径(已就绪 — §核心原则 9)
- ❌ 把 D084 rewrite helper 重写(已就绪 check_stmts.ss:112-113 + gen_decls.ss:512-513,Phase 2 复用扩 fn 实参路径)
- ❌ 顺带改 OBJ_LITERAL 在 var decl RHS 路径(D084 既有,显式优先 — H6)
- ❌ 起全局 bidirectional type checking(C3 候选废,留 D026/D027 generic 落地后再开 D 文档评估)
- ❌ 实施 D141 §Followup F3(ternary contextual typing)/ D142 §Followup F2(F5/F6 Map/Tuple literal)— 留同模式扩 sub-D 后续轮

---

## 4. State

### 编译时 state

- OBJ_LITERAL 节点 className slot(待定:nSetS1 / nSetS2 / nSetS3 — Phase 1 探查节点 slot 当前占用情况)
- funcParamTypes(已就绪,Phase 2 不改注册路径)
- evalObjLiteral pre-eval 缓存(eval pre-eval,Phase 2 反推前移到 evalObjLiteral 之前)
- D084 rewrite 状态(check_stmts.ss:112-113 既有,Phase 2 复用扩入口)

### 运行时 state

(N/A — 本 D 是 checker + codegen 编译时改,不影响运行时;genObjLiteral / NEW_EXPR emit 路径不变)

### 中间产物

- `/tmp/spike_obj_lit_red.ss`(Phase 1 写)
- 三候选评估矩阵(本 D §A.1 + §A.1.1)
- 隐藏假设挑战表(本 D §A.2)

### 会话间持久化

- D143 §Phase 进度(clear 后续 Plan 锚,Status 行单一事实源)
- bootstrap 三阶段固定点 commit hash(各 Phase 回填)

### 禁止 state 操作

- ❌ 把 OBJ_LITERAL className 信息保存到全局 Map(节点 slot 已足够 — 与 D141 ARROW_FUNC PARAM s2 + D142 ARRAY_LIT s2 节点 slot 同范式)
- ❌ 把跨轮进度 / 摘要写到 handoff 文件(`.claude/next_prompt.md` 仅 terman preset 单次 payload)

---

## 5. Evaluation

### 单一判据(必须 GREEN)

```bash
# Phase 1 RED:untyped object literal + fn 实参 — 当前需手动临时变量绑定才走通
cat <<'EOF' > /tmp/spike_obj_lit_red.ss
class User {
    name: string
    age: int
    constructor(name: string, age: int) {
        this.name = name
        this.age = age
    }
    function describe(): string {
        return `${this.name}:${this.age}`
    }
}
function takesUser(u: User): string {
    return u.describe()
}
function main() {
    let r = takesUser({ name: "X", age: 18 })
    println(r)
}
EOF

# Phase 1 RED:bin/ss run /tmp/spike_obj_lit_red.ss
# 期望:checker 报错或 silent miscompile(OBJ_LITERAL 在 fn 实参时无 D084 rewrite 入口,字段类型不反推 → 类型不匹配)

# Phase 2 GREEN:bin/ss run /tmp/spike_obj_lit_red.ss
# 期望:输出 "X:18"(反推回填 className=User + D084 rewrite NEW_EXPR + User_new ctor + describe() 走通)
```

### Phase 2 关键验证

- bootstrap 三阶段固定点 PASS(stage2 == stage3 字节比较)
- spike GREEN(主判据)
- tests/phase5/object_literal_*.ss(若有 baseline 测试)不降
- tests/d141_lambda_inference/ 5 处 baseline 不降(D141 反推机制不破)
- tests/d142_array_literal_inference/ 6 处 baseline 不降(D142 反推机制不破)
- tests/ 270/4/274 baseline 不降
- reflection_health_linter GATE PASS no regressions

### Phase 3 测试覆盖(隐藏假设挑战)

- 单字段反推(`takesUser({ name: "X" })` callee `takesUser(u: User)` + class User 单字段)— H1 反推单字段 PASS
- 多字段同质反推(`takesUser({ name: "X", age: 18 })` callee `takesUser(u: User)`)— H2 反推多字段 PASS
- 嵌套 OBJ_LITERAL(`takesProfile({ user: { name: "X" }, addr: {...} })` callee `takesProfile(p: Profile)`)— H3 嵌套反推 capture 链
- 部分字段(用户写 `{ name: "X" }` 但 callee `class User { name, age }` 多字段)— H4 部分字段反推(class ctor 必须支持默认值或 optional 字段)
- class 字段类型混合(`class User { name: string, age: int, ... }`)— H5 字段类型异质反推 PASS
- interface upcast 不可走(class 不 implement interface 不能 upcast,或走 vtable indirect dispatch)— H5b
- 显式优先(`let u: User = {...}; takesUser(u)`)— H6 显式注解仍走 D084 rewrite 原路径
- 推断失败 fallback(callee 不在 funcParamTypes / arity 不匹配 / 非结构化 callee)→ skip 反推或硬错(参 D141 H13 + D142 H13 粒度)

---

## 6. Constraints

### 硬约束

- 不引入 bidirectional type checking 全局(候选 C3 已废,scope 爆炸)
- 不动 D025 interface dispatch 契约
- 不动 D131 nullable inner field 反序列化路径
- 不动 D084 OBJ_LITERAL → NEW_EXPR rewrite helper 本体(D143 复用扩 fn 实参入口)
- 不动 D141 lambda 反推机制 / D142 array literal 反推机制(D143 是同模式扩,不重写信息源)
- bootstrap 改不许超过 800 LOC delta(`feedback_600_split_not_inline.md` + `feedback_structure_not_linecount.md`)— 实际预估 ≤ 200 LOC(check_exprs.ss + gen_calls.ss + eval/method_call.ss + eval/call.ss + gen_types.ss helper 局部改)

### 软约束

- 推断失败时**优先编译期硬错**(参 D141 H13 + D142 H13 结构化 callee 硬错粒度);非结构化 callee skip 反推不破现状
- 显式注解仍优先级最高(`let u: User = {...}` D084 rewrite 风格,既有 60+ 处现存)
- 反推查 callee `funcParamTypes` 时,callee 必须已 register(D141/D142 H1 实证 codegen 阶段已就绪)— Phase 1 文档化时序保证

### 风险锚(R1-R5)

| # | 风险 | 描述 | mitigation |
|---|---|---|---|
| R1 | OBJ_LITERAL 节点 slot 占用冲突 | nSetS1 / nSetS2 / nSetS3 已被其他用途占用,反推回填 className 找不到空 slot | Phase 1 探查 OBJ_LITERAL 节点 slot 当前占用(`bootstrap/parse/parse_exprs.ss:521` newNode + nSetList 后,s1/s2/s3 是否空);若占用 → 复用 nSetS2(类型 slot 命名) / nSetS3 / 新引入 hash Map(ssObjLitClassName[id] → string)路径;参 D141 ARROW_FUNC PARAM s2 + D142 ARRAY_LIT s2 范式 |
| R2 | 嵌套 OBJ_LITERAL 反推链路断 | `{ user: { name: "X" } }` 内层 OBJ_LITERAL 字段是嵌套 OBJ_LITERAL,反推外层 className="Profile" 后,内层 OBJ_LITERAL 也需反推 className(嵌套 class 字段 — `class Profile { user: User }`)— 递归回填 | Phase 2 实施 + Phase 3 嵌套 OBJ_LITERAL test;若失败 → 内层 OBJ_LITERAL 反推回路 fallback 单层 + 用户嵌套时仍需显式 RHS binding |
| R3 | 部分字段反推 class ctor mismatch | `takesUser({ name: "X" })` 用户漏 age,但 ctor `User(name: string, age: int)` 必填 age — 反推得 className=User 后 D084 rewrite NEW_EXPR 报 ctor arity error | Phase 1 实测 + Phase 2 决策 — (a) 严格模式:反推 + ctor arity 检查,漏字段硬错;(b) 默认值模式:反推 + 字段默认 i64=0 / string="" / class=null;Phase 3 part_field test 实证 |
| R4 | class 字段类型混合反推 | `class User { name: string, age: int, scores: Array<int> }` 字段类型异质 — 反推后字段值 inferType 与 ctor PARAM 类型一致性 | Phase 3 mixed_field test;失败 → 回 Phase 2 修字段 inferType 路径 |
| R5 | D084 rewrite 入口扩 fn 实参条件判断漏 | check_stmts.ss:112-113 D084 rewrite 仅在 `typeAnn != ""` 触发(`let x: ClassName = {...}` 路径);D143 扩到 fn 实参路径(`takesFn({...})` 路径,arg.parent typeAnn 不是 ""),判断分支需扩到 fn 实参 callee className 反推路径 | Phase 2 实施时同步扩 D084 rewrite 调用方;Phase 3 baseline 测试 D084 既有路径不破 |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 spike 已 GREEN(无 RED) | 改 spike 形态:多字段 / 嵌套 / 部分字段 / interface 不可触发反推需求;若全场景已 GREEN → D143 范围降级为 "类型表达力对齐 D141/D142"(Plan-only,无代码改) |
| Phase 2 build 失败 | git revert;调 OBJ_LITERAL slot 命名 + check_exprs.ss:285 / D084 rewrite 入口同步 |
| Phase 2 嵌套 OBJ_LITERAL 红 | R2 mitigation:内层 OBJ_LITERAL 反推单层 fallback + 文档化 H3 OOD scope |
| Phase 2 部分字段 ctor arity error | R3 mitigation:严格模式硬错 vs 默认值模式 — Phase 2 决策行 + Phase 3 part_field test 实证 |
| Phase 2 class 字段类型混合红 | R4 mitigation:字段 inferType 与 ctor PARAM 类型一致性 — 修字段 inferType 路径 |
| Phase 2 reflection_health_linter GATE BLOCK | 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段) |
| Phase 4 grep 工作量超估 | 范围限定 lib/ + tests/d134_mysql/ + tests/phase5/(D141/D142 cleanup 同域),其他 tests/ 留 sub-D 后续轮 |

### 回滚策略

- Phase 1+ 失败 → `git reset --soft HEAD^` 回上一 Phase
- Phase 0 文档已落盘,Phase 1+ 实施 commit 边界严格(D135/D136/D137/D140/D141/D142 范式延续)
- D143 失败回退不影响 D141/D142(D141 + D142 主线已 close,D143 仅同模式扩)

---

## A.1 主候选评估(§MNK §M §字段 10 + Plan 型 §④ 替换:替代方案对比)

| 候选 | 层次 | 描述 | 假设破裂入口 | 优势 | 劣势 | 决策 |
|---|---|---|---|---|---|---|
| **C1** | **数据层 patch** | `gen_calls.ss` fn 实参 OBJ_LITERAL 路径加 fallback — OBJ_LITERAL 类型未知时从 callee funcParamTypes 取 className 兜底 + 临时拼 NEW_EXPR | 破裂入口在 OBJ_LITERAL inferType 返单一 ""/"object",信息丢失;C1 仅在 fn 实参单点补 fallback,不消除根因 — D084 rewrite / inferType / classFieldTypes 等其他消费者仍走错 | LOC 极小 5-10 行;不动 checker | 零散 patch — 多消费者(D084 rewrite / classFieldTypes / inferType 等)都用 OBJ_LITERAL inferType,信息源不单点;同模式 object literal 在 method 实参 / map literal 等场景仍 RED | **不选** — 数据层不消除根因(`feedback_root_cause_no_cost.md` 红线,与 D141 §A.1 C1 + D142 §A.1 C1 同形废) |
| **C2** | **接口层 trap** | checker `check_exprs.ss:285` OBJ_LITERAL 改返 `class<ClassName>` 结构化签名(与 ARROW_FUNC `fn(P,...):R` + ARRAY_LIT `Array<elemType>` 同形)+ codegen 阶段 fn/method 实参反推回填 OBJ_LITERAL className slot + eval pre-eval 时序 + funcParamTypes SSoT 复用 + D084 rewrite 路径扩 fn 实参入口 | **彻底消除** — OBJ_LITERAL inferType 结构化,所有下游(D084 rewrite / classFieldTypes / inferType / method dispatch)信息源一致;eval pre-eval 反推前移避免 D141/D142 H10 同形时序破裂 | 单点信息源回填;TS / Java 8+ contextual typing 主线;D141/D142 G1 路径同模式复刻;workaround cleanup 落锚;D084 rewrite 复用 | LOC 中等 ~200(check_exprs.ss + gen_calls.ss + eval/method_call.ss + eval/call.ss + gen_types.ss helper + D084 rewrite 入口扩);需考虑嵌套 OBJ_LITERAL / 部分字段 / class 字段类型混合 边界 | **选** — 接口层 trap 消除根因 + scope 可控 + D141/D142 同模式复用 + D084 rewrite 复用 |
| **C3** | **架构层 refactor** | 全编译器 bidirectional type checking — checker 改 expected/actual 双向类型检查,所有表达式从调用上下文反推类型(包括 array literal + object literal + ternary + null literal 等) | 消除根因 + 消除其他 silent miscompile(ternary 类型推断等)| 类型系统统一性最高;未来扩 SS 泛型 D026/D027 时直接复用;D141 §Followup F5 + D142 §A.3 已锁此候选废留 SS 类型系统 v2 | scope 爆炸 LOC > 2000 + 多 sub-D + bootstrap 重写多个核心文件;F1 单 sub-D scope 远超(D143 不应承载架构层 refactor) | **不选** — scope 远超 D143 单 sub-D 范围;**D141 §Followup F5 + D142 §A.3 已锁此候选废**,留作未来 SS 类型系统 v2 评估 |

**决策行**:**选 C2 接口层 trap** 因 (a) 单点信息源回填,消除 OBJ_LITERAL inferType 单一 ""/"object" 的假设破裂入口;(b) D141/D142 G1 路径同模式复刻 — eval pre-eval 时序 + funcParamTypes SSoT + codegen 阶段反推 + 失败硬错粒度全沿用;(c) D084 rewrite 路径复用 — fn 实参反推得 className 后走同 rewrite NEW_EXPR 入口;(d) workaround cleanup 落锚 Phase 4(临时变量绑定形态全删);(e) scope 可控 ~200 LOC delta < D141 ~267 LOC < D142 ~91 LOC。**为何不选 C1**:数据层 zero-spread 不消除根因(`feedback_root_cause_no_cost.md` 红线,与 D141 §A.1 C1 + D142 §A.1 C1 同形废)。**为何不选 C3**:scope 爆炸 — D141 §Followup F5 + D142 §A.3 已锁 C3 废留 SS 类型系统 v2,D143 单 sub-D 不承载架构层 refactor。

---

## A.1.1 C2 实施路径对比(Phase 0 落档,Phase 1 起首实测确认)

> Phase 0 起首查源:`bootstrap/checker/check_stmts.ss:112-113` D084 rewrite 已落 `let x: ClassName = {...}` 路径 + `bootstrap/gen/gen_decls.ss:512-513` codegen 同函数;funcParamTypes 已注册 class 名字符串(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57)— **D143 比 D141/D142 G1 路径更轻**(D141 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn` → `setter: fn(PreparedStatement):void`,parser 必须扩 parseTypeAnn fn 类型;D142 比 D141 更轻无 callee 升级 + 无 parser 扩前置;D143 callee `class X` 已结构化 + parser 已就绪 + D084 rewrite 路径已落 — 反推可直接消费)。下分三路径定 D143 实施。

| 路径 | 描述 | 解决度 | LOC | 影响 | 决策 |
|------|------|--------|-----|------|------|
| **G1** | **D141/D142 G1 同模式复刻** — checker `check_exprs.ss:285` OBJ_LITERAL 返 `class<ClassName>` 结构化(与 ARROW_FUNC + ARRAY_LIT 同形)+ codegen 阶段反推回填 OBJ_LITERAL className slot + eval pre-eval 反推前移 + funcParamTypes 已结构化直接消费(无 callee 升级前置)+ helper `isClassType` / `extractClassName` / `inferObjLiteralFields` 落 gen_types.ss(对偶 D141 isFnType + D142 isArrayType)+ **D084 rewrite 路径复用扩 fn 实参入口** | 100% | check_exprs.ss ~10 + gen_types.ss helper ~30 + gen_calls.ss + gen_methods.ss 反推 ~30 + eval/method_call.ss + eval/call.ss pre-eval 反推 ~30 + D084 rewrite 入口扩 ~20 + check_types.ss isTypeCompatible 调整 ~10 ≈ **~130** | Phase 4 临时变量绑定 cleanup 仍可推进(callee 已结构化与 object literal cleanup 独立) | **选** — D141/D142 G1 同模式复刻 + 比 D141/D142 更轻(无 parser 扩 + 无 callee 升级前置 + D084 rewrite 复用) |
| G2 | callsite 双向反推 — 从 object literal 第一字段类型反推 OBJ_LITERAL className;不依赖 callee `class X` 形态 | 30% | gen_calls.ss + gen_methods.ss ≈100 | 漏部分字段 + 漏 fn binding 间接链 + 漏 class 字段类型混合(无法从单字段反推 className 仅从字段值类型) — **OBJ_LITERAL 字段反推 className 不可行**(class 名是上下文反推关键) | 不选 — 不可行 + 偏离 TS / Java 8+ 主线(TS object literal 反推靠 callee 形参 class 类型,不靠字段自身 inferType) |
| G3 | 接受 gap,Phase 2 仅做 (a) 预备 — check_exprs.ss:285 改 OBJ_LITERAL 返结构化签名,(b)(c) 反推机制因消费链路不接通实际不生效;主线 D141 §Followup F2 / D142 §Followup F1 cleanup 延期 | 0% | check_exprs.ss:285 单点 ≈10 | 主线 cleanup 延期;反推机制空转;违反 `feedback_root_cause_no_cost.md` 红线 | 不选 — 反推机制空转无意义 |

**G1 决策(本 Phase 0 落档锁定,待用户对话确认)**:走 G1 — 根因 100% + D141/D142 G1 同模式复刻 + scope 可控 < D141 LOC + 比 D141/D142 更轻(无 parser 扩 + 无 callee 升级前置 + D084 rewrite 复用 — H11/H12 比 D141 弱 / 比 D142 也弱)。**为何不选 G2**:OBJ_LITERAL 字段反推 className 物理不可行(class 名是上下文反推关键,非字段自身 inferType);且偏离 TS / Java 8+ contextual typing 主线(TS object literal 反推靠 callee 形参 class 类型,不靠字段自身 inferType)。**为何不选 G3**:反推机制空转 0% 解决度,违反 `feedback_root_cause_no_cost.md` 红线。

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套 — D141 §A.2 + D142 §A.2 同模式扩)

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | funcParamTypes class 名字符串在 codegen 阶段已 ready(D141/D142 H1 同模式 — checker 阶段用户函数为空,codegen registerAllDecls 后满载)| 实施层失败 — codegen 反推时 funcParamTypes 留空,反推查不到 callee class 名签名 | Phase 1 探查 codegen.ss:110-112 + gen_registry.ss:56-57 register 时机;Phase 2 startup 阶段 dump funcParamTypes 验证含 class 名形态;**D141/D142 H1 已实证 codegen 阶段已就绪**,D143 同模式假设大概率成立 | funcParamTypes 时机不就 → 调整 Phase 2 入口(改 lazy 反推 vs eager 反推)| **Phase 1 实证 PASS**(2026-04-27)— `bootstrap/gen/codegen.ss:110` 普通函数 `funcParamTypes.set(${fname}:${pCount}, nGetS2(fpId))` + `:112` mangled `funcParamTypes.set(${fname}_${fSig}:${pCount}, ...)` + `bootstrap/gen/gen_registry.ss:56` class method `funcParamTypes.set(${baseName}:${pCount}, nGetS2(pId))` + `:57` mangled `${baseName}_${mSig}:${pCount}` + `bootstrap/gen/codegen.ss:326` `registerAllDecls(rootId)` 在 line 327 `emitGlobalsAndCode(rootId)` **之前** — 时序就绪,反推时点 funcParamTypes 满载,class 名 `User` / `Profile` 等字符串原样直存 |
| H2 | OBJ_LITERAL 多字段反推与 class 字段类型一致性 | `{ name: "X", age: 18 }` 字段值 inferType 各返 "string" / "int",反推 className=User 后 ctor PARAM 类型 `User(name: string, age: int)` 与字段值类型一致;若字段值类型与 ctor PARAM 类型冲突(`{ name: 18, age: "X" }` 倒置)→ 反推 + ctor arity check 失败硬错 | Phase 3 测试 `tests/d143_object_literal_inference/multi_field.ss` | 类型不一致 silent fallback → 回 Phase 2 修硬错路径;参 D141 H4 + D142 H2 fallback 编译期硬错粒度 | **Phase 3 实证 PASS**(2026-04-27)— `multi_field.ss` `takesUser({ name: "Y", age: 18 })` GREEN 输出 `Y:18`(IR `call ptr @User_new(ptr @.str.N, i32 18)`,字段值各自 inferType + ctor PARAM 类型一致);**倒置类型 H13 同位 silent miscompile 实证错估**:`{ name: 18, age: "X" }` 实测 segfault(checker 阶段反推 className=User 后字段值类型与 ctor PARAM 不一致 silent fallback 不硬错)— Followup F8 反推失败粒度细化 sub-D |
| H3 | 嵌套 OBJ_LITERAL `{ user: { name: "X" } }` 反推 capture 链 | 内层 OBJ_LITERAL 字段也是 OBJ_LITERAL,反推外层 className=Profile + Profile 字段 user: User 后,内层 OBJ_LITERAL 也需反推 className=User — 递归回填 | Phase 3 测试 `tests/d143_object_literal_inference/nested.ss`(`takesProfile(p: Profile)` + `{ user: { name: "X" } }`)| 嵌套反推失败 → 内层 OBJ_LITERAL fallback 单层 + 用户嵌套时仍需显式 RHS binding;参 D141 H3 + D142 H3 嵌套范式 | **Phase 3 实证 PASS**(2026-04-27)— `nested.ss` `takesProfile({ user: { name: "Z", age: 20 }, addr: "Earth" })` GREEN 输出 `Z@Earth`(Phase 2 `gen/class/class_method.ss:genNamedConstructorArgs` 用 classFieldTypes 反推 inner OBJ_LITERAL + `eval/new_expr.ss` pre-eval 前移对偶 — 嵌套 capture 链路完整) |
| H4 | 部分字段反推 class ctor 必填字段 mismatch | `takesUser({ name: "X" })` 用户漏 age,但 ctor `User(name: string, age: int)` 必填 age | (a) Phase 1 实测 SS 当前 class ctor 是否支持默认值字段(参 D084 行为);(b) Phase 2 决策 — 严格模式硬错 vs 默认值模式;(c) Phase 3 part_field test | 部分字段 silent fallback → 回 Phase 2 修硬错路径或扩默认值路径(可能涉及 D084 ctor 默认值机制) | **Phase 3 实证 — 决策行严格模式**(2026-04-27)— spike `takesUser({ name: "X" })` 实测 LLC error `expected type` 行 `call ptr @User_new(ptr @.str.85, )`(第 2 arg age 空缺);**SS 编译期硬错诊断粒度落空**(LLC 阶段才报错,用户看到 LLC error 不知是 OBJ_LITERAL 漏字段)— **决策走 (a) 严格模式**(用户必须补全字段,与 D084 既有 ctor 行为一致);(b) 默认值模式 sub-D 留 Followup F6 ctor 默认值机制(D084 扩展)+ Followup F8 H4 编译期硬错诊断粒度细化 |
| H5 | class 字段类型混合反推 | `class User { name: string, age: int, scores: Array<int> }` 字段类型异质 — 反推后字段值 inferType 与 ctor PARAM 类型一致性 | Phase 3 测试 `tests/d143_object_literal_inference/mixed_field.ss`;参 D142 H5 interface upcast 同模式 | mixed field 失败 → 回 Phase 2 修字段 inferType 路径 | **Phase 3 实证 PASS(部分)**(2026-04-27)— `mixed_field.ss` `takesItem({ name: "Apple", count: 3, price: 1.5 })` 异质 string+int+double GREEN 输出 `Apple:3:1.5`;**Array<int> / Map<K,V> 字段反推 OOD scope**:spike `class User { ..., scores: Array<int> }` + `{ ..., scores: [90, 80, 70] }` 实测 LLC error `'%9' defined with type 'ptr' but expected 'i32'` — 根因 `class/class.ss:288-301 genNewExpr` ctor positional args 路径**未调 inferArrayLitElems**(D142 §F7 同根因);D143 §F4 锚扩 NEW_EXPR ctor 实参子节点反推(OBJ_LITERAL + ARRAY_LIT 两种)同模式 sub-D |
| H5b | interface upcast 不可走 | object literal `{ ... }` 不能直接 implements interface(必须 class instance),反推 className=ClassName 后才能走 vtable indirect dispatch;若 callee `i: IFoo` 期望 interface 类型 → 反推得 OBJ_LITERAL className 后必须 D084 rewrite NEW_EXPR ClassName 实例,IShape 期望反推不可达 | Phase 3 interface_upcast_skip test;失败硬错诊断 | interface 期望 silent skip → 回 Phase 2 修硬错诊断粒度 | **Phase 3 实证 PASS**(2026-04-27)— `interface_upcast_skip.ss` `takesShape(new Square(2.0))` 显式 NEW_EXPR + interface IShape 反推 className=IShape 不可 instantiate 走 D025 vtable indirect dispatch GREEN 输出 4.0 — 用户必须显式 NEW_EXPR 构造,OBJ_LITERAL 反推机制不破坏既有 NEW_EXPR + vtable 路径(零破坏既有) |
| H6 | 显式注解优先级 > 推断 | 用户写 `let u: User = {...}; takesUser(u)` 时,RHS 推断走 D084 rewrite 既有路径(`check_stmts.ss:112-113` typeAnn != "" 触发);fn 实参传 u(IDENT)反推 skip(u 不是 OBJ_LITERAL)| Phase 2 反推条件判断 `if (nGetKind(argId) == "OBJ_LITERAL")` 限定;Phase 3 测试 `tests/d143_object_literal_inference/explicit_override.ss` 显式注解仍走原路径;参 D141 H6 + D142 H6 显式优先粒度 | 显式优先级失败 → 回 Phase 2 修条件判断 | **Phase 3 实证 PASS**(2026-04-27)— `explicit_override.ss` `let u: User = { name: "Z", age: 25 }; takesUser(u)` GREEN 输出 `Z:25`(D084 既有路径不破)— `inferObjLiteralFromType` line 878 `if (nGetS2(argId) != "") return` 显式优先粒度 |
| H7 | tests/ 270/4/274 baseline 不降 | 全项目现有 object literal 测试 60+ 都走显式注解 / D084 rewrite — Phase 2 反推不影响显式路径(H6 显式优先);Phase 4 cleanup 仅临时变量绑定形态 | Phase 2 后跑 `bin/ss test tests/` 全跑 + baseline 比 | tests/ 红 → 回 Phase 2 修条件判断或 fallback 路径;参 D141 H7 + D142 H7 同范式 | **Phase 3 实证 PASS**(2026-04-27)— `tests/d141_lambda_inference/` 5/0/5 + `tests/d142_array_literal_inference/` 6/0/6 + `tests/d143_object_literal_inference/` 6/0/6 全绿;Phase 3 核心代码路径 diff=0 → VCM §1 豁免 `./build.sh bootstrap` + `bin/ss test tests/` 全跑 |
| H8 | reflection_health_linter GATE 不破 | checker / codegen / eval 三层改 — 是否破反射路径 14 指标(M1-M7b + N1-N5)| Phase 2 后跑 `bin/ss run tools/reflection_health_linter.ss` GATE PASS | GATE BLOCK → 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段);参 D141 §扩容申报-Phase2-G1 + D142 §扩容申报-Phase2 范式 | **Phase 3 实证 PASS**(2026-04-27)— Phase 3 核心代码路径 diff=0(仅新建 `tests/d143_object_literal_inference/` 6 文件,无 bootstrap diff)→ reflection_health_linter GATE PASS no regressions(M7b cur=701 within 1% of budget_max=700 AUTO-DRIFT soft 不阻 + N2/N3/F1 全 ≤ budget_max)|
| H9 | var binding callee 反推 OOD scope(D141/D142 H9 同模式)| `const f = takesUser; f({ name: "X" })` callee="f" 是 var binding 不在 funcParamTypes,反推 skip | **D141 H9 + D142 H9 已锁 var binding callee OOD scope**,D143 同模式继承 — 主线场景是 method call(`tmpl.exec({...})`)/ fn call(`takesUser({...})`),callee 是 mangled method 名 / 函数名在 funcParamTypes,不受影响 | var binding 不支持反推 → 用户 var binding 时仍需显式 RHS binding,不影响 D143 主线 cleanup | **Phase 3 实证 OOD PASS**(2026-04-27)— spike `const f = takesUser; let u: User = {...}; const r: string = f(u)` 实测 LLC error `assertEqual(i64 %19, ptr @.str.98)`(var binding callee 不仅参数反推 OOD,**返回类型推断也 OOD** — i64 vs string 不匹配,即使加显式 `: string` 注解仍 OOD)— D141/D142 H9 同模式继承,**OBJ_LITERAL 反推机制不扩到 var binding callee**(主线场景 fn call / method call callee 在 funcParamTypes,不受影响);用户 var binding 时仍需显式 var decl 兜底 + 走 D084 既有路径,不影响 D143 主线 cleanup |
| H10 | OBJ_LITERAL eval pre-eval 时序(D141/D142 H10 同模式)| 待 Phase 1 实测确认 eval/obj_literal 路径(若有 evalObjLiteral 或同等)+ pre-eval 缓存与 codegen emit 之前的时序;若 pre-eval 已对字段值求值 → 反推必须前移到 outer call site `eval/method_call.ss + eval/call.ss` args 循环 | Phase 1 探查 + Phase 2 反推前移到 outer call site 识别 OBJ_LITERAL 子节点 + 查 funcParamTypes + 反推回填 | 修复链断 → 回 Phase 2 检查 nSetS?/nGetS? 命名一致 + outer call site args 循环识别 OBJ_LITERAL 完整路径 | **Phase 1 OOD 实证错估 → Phase 2 修正 PASS**(2026-04-27)— Phase 1 仅 grep `evalObjLiteral` / `OBJ_LITERAL` 字面 handler **0 命中**就标 OOD,但忽略 `eval/call.ss:86 + eval/method_call.ss:89 + eval/new_expr.ss:38` **通用 pre-eval `genVal(callArgId)`** 路过 OBJ_LITERAL 走 line 93 `[genVal] unknown kind` fallback `constVal("0")` silent miscompile(`call ptr @takesUserSingle(ptr 0)` IR 错例铁证);Phase 2 实施过程 spike `[genVal] unknown kind: OBJ_LITERAL` 暴露 H10 OOD 实证错估 — 修正路径与 D141 H10 + D142 H10 完全同形:**eval/call.ss + eval/method_call.ss + eval/new_expr.ss 三处 pre-eval 之前同模式前移 inferObjLiteralFields**(D141/D142 inferArrowFuncParams + inferArrayLitElems 同位)+ 嵌套 H3 链路在 `bootstrap/gen/class/class_method.ss:genNamedConstructorArgs` 用 classFieldTypes 反推 inner OBJ_LITERAL(对偶 fn args 路径用 funcParamTypes)— Phase 2 修正后 spike Y:18 + Z@Earth GREEN |
| H11 | callee PARAM `class X` 字符串已结构化,无需 G1 callee 升级(比 D141 H11 + D142 H11 弱) | D141 G1 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn`(parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析);D142 callee `Array<T>` 已结构化无前置;D143 callee `class X` IDENT 单 token 已就绪 | grep 实测 lib/spring/(jdbc+data).ss + tests/ 多处 callee PARAM `class X` 已结构化;Phase 2 反推 helper extractClassName("User") = "User" 直接消费 | callee 升级路径破裂 → 反推失败 silent skip(非结构化 callee 走 H13 同形 skip 不破);参 D141 H13 + D142 H13 粒度 |
| H12 | parser 不需要扩(比 D141 H12 + D142 H12 都弱)| D141 H12 必须 parseTypeAnn IDENT "fn" + LPAREN 分支扩;D142 嵌套 generic Array<...> 已就绪;D143 class 名是 IDENT 单 token,parser 已就绪无嵌套 generic 解析需求 | Phase 1 grep 实测 + Phase 2 不动 parser | parser 未就绪(若实测发现某些边界形态未支持)→ 回 Phase 2 评估扩 parser 必要 — 大概率不需要 |
| H13 | 反推失败硬错粒度(D141/D142 H13 同模式)— 结构化 callee 硬错 / 非结构化 callee skip | **结构化 callee**(funcParamTypes 含 `class X`):extractClassName 取不到 → `codegenError` 硬错;**非结构化 callee**(funcParamTypes 仍是 ""/单 IDENT)→ 反推 skip(不破现有调用方);**ctor arity mismatch**:参 H4 决策(严格 vs 默认值)| Phase 2.2 实测 helper extractClassName + Phase 4 cleanup 删 typed 注解后,untyped object literal 走结构化反推 | 硬错粒度过严 → tests/ break → 调整粒度为 silent skip + warn(参 D141 H13 + D142 H13 调整路径)| **Phase 3 实证 — 粒度过松反向问题**(2026-04-27)— (a) **倒置类型 silent miscompile**:`takesUser({ name: 18, age: "X" })` 实测 segfault(checker 阶段反推 className=User GREEN + 字段值 inferType 与 ctor PARAM 类型不一致 silent fallback 不硬错,运行时 segfault);(b) **无 callee context 走错例**:`let x = { name: "X", age: 18 }`(var decl 无类型注解 + 无 fn 实参 callee)实测 `[genVal] unknown kind: OBJ_LITERAL` LLC error `store ptr 0`(反推 skip 走 fallback "ptr",但 codegen 无 OBJ_LITERAL handler);**当前粒度过松**(silent miscompile 而非硬错)— Followup F8 反推失败粒度细化 sub-D 锁此场景(checker 阶段加字段值类型与 ctor PARAM 一致性检查 + var decl no annot + no callee context 时 OBJ_LITERAL 走硬错诊断,非 silent fallback)|

---

## A.3 废案

- **C1 数据层 patch 全废**(零散 fallback,不消除根因 — 与 D141 §A.3 + D142 §A.3 同形)
- **C3 架构层 refactor 全废**(scope 爆炸,远超 D143 单 sub-D)— **D141 §Followup F5 + D142 §A.3 已锁此候选废留 SS 类型系统 v2 评估**
- **C4 编译期 lint 警告强制用户加 RHS binding**(被动 — 用户每写 object literal 必先 binding,违反 CLAUDE.md §编译器吸收复杂度)
- **C5 全 object literal 默认 class=Object**(silent miscompile — 字段类型混合 / 嵌套 OBJ_LITERAL / 部分字段全场景错位)
- **G2 callsite 双向反推全废**(物理不可行 — 字段值反推不出 className,class 名是上下文反推关键 — §A.1.1 G2 行)
- **G3 接受 gap 全废**(反推机制空转 0% 解决度,违反 `feedback_root_cause_no_cost.md` 红线)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `50912b4` (2026-04-27)

- 本文档落档 + Status / 核心目标 / 核心原则 / Context / Tools / Orchestration / State / Evaluation / Constraints / §A.1 主候选 + §A.1.1 实施路径 + §A.2 隐藏假设 / §A.3 废案 / Phase 0-5 计划草案
- d_doc_index_linter F1 = 0 验证 PASS(D143 加入未破 referenced Ds — D025/D084/D131/D141/D142 实存,F2 soft warn 含 D143 不阻 commit)
- next_prompt_ultrathink_linter PASS 3/3(本轮 .claude/next_prompt.md 含 ultrathink 关键字)
- VCM 六验(Plan 型):§① 跳过(diff=0 in bootstrap/lib/tools)+ §④ 替换为「替代方案对比 + 隐藏假设挑战」§A.1+§A.1.1+§A.2 ✓

### Phase 1: RED 复现 + 信息源探查 [✓] Done at commit `f089738` (2026-04-27)

- ✓ `/tmp/spike_obj_lit_red.ss` 3 形态(单字段 / 多字段 / 嵌套)RED 铁证 — `bin/ss build /tmp/spike_obj_lit_red.ss --emit-ir 2>&1 | grep -c "object literal requires type annotation"` = **3**(line 45:43 / 49:46 / 53:74 全命中)— **比 D141/D142 RED 更硬**(checker 阶段直接拒绝,非 silent miscompile)
- ✓ 形态 4-7 文档化(部分字段同形态 1 / class 字段类型混合同形态 2 / fn 实参 IDENT type 同形态 2 / interface upcast 不可走 OOD H5b)— 不必单独 spike
- ✓ §A.2 H1 同模式实证 PASS(funcParamTypes class 名字符串 codegen 阶段满载)— **codegen.ss:110-112 普通函数注册 `${fname}:${pCount} → nGetS2(fpId)` + gen_registry.ss:56-57 class method 注册 `${baseName}:${pCount} → nGetS2(pId)` + codegen.ss:326 `registerAllDecls(rootId)` 在 `emitGlobalsAndCode(rootId)` 前** — D141/D142 H1 同模式继承
- ✓ §A.2 H10 OOD 实证 PASS — **`bootstrap/eval/` 17 文件 grep OBJ_LITERAL 0 命中**(无 evalObjLiteral / eval/array_lit.ss 同形 handler)— D143 比 D141 H10(eval/method_call.ss + eval/call.ss args pre-eval) + D142 H10(eval/array_lit.ss elems pre-eval)**都弱**;反推无需前移到 eval pre-eval,可直接在 codegen outer call site 反推回填
- ✓ OBJ_LITERAL 节点 slot 占用探查 PASS — `parse_exprs.ss:521-522` `newNode("OBJ_LITERAL")` + `nSetList(id, fields)` **仅占用 nList**,s1/s2/s3 + i1/i2/i3/i4 **全空闲**;Phase 2 选 nSetS2 与 ARRAY_LIT(D142 line 50)/ ARROW_FUNC PARAM(D141 line 75-87)s2 同范式
- ✓ OBJ_LITERAL kind dispatch site 全 grep 完成 — `bootstrap/parse/parse_exprs.ss:521` 构造 + `bootstrap/checker/check_exprs.ss:285-287` 直接 checkerError + `bootstrap/checker/check_stmts.ss:112-113` D084 rewrite 入口 + `bootstrap/gen/gen_decls.ss:512-513` codegen D084 同函数 — **共 4 处 dispatch site**
- ✓ Phase 2 入口锁:
  - `check_exprs.ss:285-287` 改为:先 `nGetS2(id)` 反推 className → 反推得 → 跳过 checkerError 让 D084 rewrite 入口接管;反推不得 + 非 typed 上下文 → 仍硬错(粒度参 D141 H13 + D142 H13)
  - `check_types.ss` OBJ_LITERAL inferType case 加 — 优先读 nGetS2 → `class<ClassName>` 结构化(与 ARRAY_LIT line 50-71 + ARROW_FUNC line 72-93 同形)
  - `gen_calls.ss` + `gen/methods/gen_methods.ss` args 循环识别 OBJ_LITERAL + 查 funcParamTypes class 名 + 反推回填 nGetS2(D141/D142 G1 4 落点同模式)
  - `D084 rewrite 入口扩 fn 实参条件`:check_stmts.ss:112-113 + gen_decls.ss:512-513 复用同 helper + 触发条件扩 typeAnn=="" 但 nGetS2 反推得 className
- ✓ §1 必读清单补 4 锚:`check_exprs.ss:285-287` 直接 checkerError 现状 + `check_stmts.ss:107-117` D084 rewrite 入口扩点 + `gen_decls.ss:507-516` codegen 同函数 + `parse_exprs.ss:500-523` OBJ_LITERAL 节点构造

### Phase 2: codegen 阶段反推实施 + G1 路径(D141/D142 G1 同模式复刻)[✓] Done at commit `5eb722e` (2026-04-27)

- ✓ `bootstrap/checker/check_types.ss:50` 加 OBJ_LITERAL inferType case — 优先读 `nGetS2(nodeId)` → 返 className(与 NEW_EXPR line 116 同形);fallback "auto"(checker 阶段反推 nSetS2 未发生,isTypeCompatible 放行)— 与 ARRAY_LIT line 60 + ARROW_FUNC line 80 同形结构化前置
- ✓ `bootstrap/checker/check_exprs.ss:285` OBJ_LITERAL untyped 改放行(D141 ARROW_FUNC + D142 ARRAY_LIT 同模式)— 不再硬错 `checkerError("object literal requires type annotation", ...)`;字段值表达式 checkExpr 循环防漏类型检查 + 反推回填发生在 codegen 阶段 + 反推不得 → codegen 硬错(H13 粒度)
- ✓ `bootstrap/gen/gen_types.ss` 加 helper 三函数(对偶 D141 `isFnType`/`extractFnParamType`/`inferArrowFuncParams` + D142 `isArrayType`/`extractArrayElemType`/`inferArrayLitElems`):
  - `isClassType(t)` 判定 class 类型(剥 nullable + 拒 Array<T>/Map<T>/fn/built-in 容器)
  - `extractClassName(t)` 从 callee PARAM 类型提取 class 名(IDENT 单 token,无嵌套 generic — 比 D142 H12 弱)
  - `inferObjLiteralFromType(argId, expectedType)` D084 rewrite 同模式 inline:nSetS2 + nKind→NEW_EXPR + nSetS1
  - `inferObjLiteralFields(argId, typeCallee, argIdx)` 查 funcParamTypes[typeCallee:argIdx] → 委托 inferObjLiteralFromType
  - inferType OBJ_LITERAL case(line 545)— 优先读 nGetS2 → fallback "ptr"
- ✓ `bootstrap/gen/gen_calls.ss:284` + `bootstrap/gen/methods/gen_methods.ss:206` args 循环加 inferObjLiteralFields(D141/D142 G1 4 落点同模式)
- ✓ **§A.2 H10 OOD 实证错估 → Phase 2 修正**:`bootstrap/eval/call.ss:36 + eval/method_call.ss:64 + eval/new_expr.ss:24` 三处 pre-eval 之前同模式前移 inferObjLiteralFields(D141 H10 + D142 H10 完全同形 — 通用 pre-eval `genVal(callArgId)` 路过 OBJ_LITERAL 走 unknown kind silent miscompile,Phase 1 仅 grep 字面 handler 漏判)
- ✓ **嵌套 H3 反推链路** — `bootstrap/gen/class/class_method.ss:genNamedConstructorArgs` 用 `classFieldTypes[`${className}.${argName}`]` 反推 inner OBJ_LITERAL(对偶 fn args 路径用 funcParamTypes)+ eval/new_expr.ss pre-eval 反推前移对偶
- ✓ 反推 IR 因果实证 spike `/tmp/spike_d143_phase2.ss` — `takesUser({ name: "Y", age: 18 })` + `takesProfile({ user: { name: "Z", age: 20 }, addr: "Earth" })` GREEN 输出 `Y:18` + `Z@Earth`(对照 RED `[genVal] unknown kind: OBJ_LITERAL` + `call ptr @takesUserSingle(ptr 0)` IR 错例)
- ✓ VCM 验证:bootstrap 三阶段固定点 PASS + tests/ 270/4/274 baseline 不降(与 Phase 1 commit `f089738` 一致)+ reflection_health GATE PASS no regressions(扩容申报 D143#扩容申报-Phase2 — M1=5450→5550 / M2=80000→81600 / M4=3109→3250 / N2=400000→408000 / N3=550000→562000 / F1:gen_types.ss=915→970 — class_method.ss reflection scope 触碰 + helper 三函数 + 5 处反推插桩点累计)+ d_doc_index_linter F1=0 GATE OK + ultrathink_linter PASS

### Phase 3: 测试覆盖 + 隐藏假设挑战 [✓] Done at commit `15f8dfe` (2026-04-27)

- ✓ `tests/d143_object_literal_inference/` 6 测试落锚:
  - `single_field.ss` — H1 单字段反推 `takesUser({ name: "X" })` callee `class User { name: string }` → 节点 nSetS2="User" + nKind→NEW_EXPR + IR `call ptr @User_new(ptr @.str.N)` GREEN → r="X"
  - `multi_field.ss` — H2 多字段同质反推 `takesUser({ name: "Y", age: 18 })` → IR `call ptr @User_new(ptr, i32 18)` GREEN → r="Y:18"
  - `nested.ss` — H3 嵌套 OBJ_LITERAL `takesProfile({ user: { name: "Z", age: 20 }, addr: "Earth" })` → `gen/class/class_method.ss:genNamedConstructorArgs` 用 classFieldTypes["Profile.user"]="User" 反推 inner OBJ_LITERAL + `eval/new_expr.ss` pre-eval 前移对偶 → 嵌套 capture 链路完整 GREEN → r="Z@Earth"
  - `mixed_field.ss` — H5 字段类型异质 string+int+double `takesItem({ name: "Apple", count: 3, price: 1.5 })` → 字段值各自 inferType + ctor PARAM 类型一致 GREEN → r="Apple:3:1.5"(注:Array<T> / Map<K,V> 字段反推 OOD scope,Followup F4 NEW_EXPR ctor 实参子节点反推同模式 sub-D)
  - `explicit_override.ss` — H6 显式 var decl 注解 `let u: User = {...}; takesUser(u)` 走 D084 rewrite 既有路径(check_stmts.ss:112-113 typeAnn != "" 触发);fn 实参传 u 是 IDENT(非 OBJ_LITERAL)→ 反推 skip 显式优先(`inferObjLiteralFromType:line 878 if (nGetS2 != "") return`)GREEN → r="Z:25"
  - `interface_upcast_skip.ss` — H5b OOD scope `takesShape(new Square(2.0))` 显式 NEW_EXPR + interface IShape 反推 className=IShape 不可 instantiate 走 D025 vtable indirect dispatch GREEN → 4.0;OBJ_LITERAL 反推机制不破坏既有 NEW_EXPR + vtable 路径(零破坏既有)
- ✓ §A.2 隐藏假设挑战实证全填:
  - H1/H10 Phase 1+2 已实证 PASS(funcParamTypes class 名 codegen 阶段满载 + eval pre-eval 时序修正)
  - H2/H3/H5/H5b/H6 Phase 3 实证 PASS(6 测试全绿铁证)
  - H4 决策行严格模式(LLC error 硬错粒度落空,Followup F6 ctor 默认值机制 + F8 编译期硬错诊断粒度细化 sub-D)
  - H5 部分 OOD scope(string+int+double 异质 PASS,Array<int> / Map<K,V> 字段反推 OOD,Followup F4 + D142 §F7 同根因 NEW_EXPR ctor positional args 子节点反推漏)
  - H7 baseline 不破(d141 5/0/5 + d142 6/0/6 + d143 6/0/6 全绿 + Phase 3 核心代码路径 diff=0 → VCM §1 豁免)
  - H8 reflection GATE PASS(Phase 3 无 bootstrap diff 无 reflection scope 触碰)
  - H9 var binding callee OOD 实证铁证(返回类型推断也 OOD,继承 D141/D142 H9)
  - H11/H12 Phase 1+2 已实证(callee PARAM class X 已结构化无 G1 callee 升级 + parser 不需扩 比 D141/D142 都弱)
  - H13 粒度过松反向问题实证(倒置类型 silent miscompile segfault + 无 callee context unknown kind LLC error,Followup F8 粒度细化 sub-D)
- ✓ **§A.2 H10 cross-D 实证 SSoT 反思 → memory 落档**:D141 H10 setVarType 链路(non-eval pre-eval scope)/ D142 H10 字面 evalArrayLit 时序探查均 PASS,但 D143 H10 仅 grep 字面 handler `evalObjLiteral` 0 命中漏判通用 pre-eval `genVal(callArgId)` 路径 — **outer call site `genVal(argId)` 通用 pre-eval 才是反推时序的关键,字面 handler 0 命中 ≠ 反推无需前移**;反推机制 H10 验证应当统一查 outer call site 通用 pre-eval 入口(eval/call.ss + eval/method_call.ss + eval/new_expr.ss + class/class_method.ss 等所有 args 循环)— memory `feedback_h10_cross_d_verify.md` 落档反复跨 D 验证模式
- ✓ VCM 六验全 PASS:
  - §1 工程:Phase 3 核心代码路径 diff=0(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出)→ VCM §1 豁免 `./build.sh bootstrap` + `bin/ss test tests/`
  - §2 行为:6 测试 demo 反推机制新能力(对照 D084 既有路径,对照 RED `[genVal] unknown kind` + LLC error)
  - §3 反向:删 6 测试任一 → tests/d143_object_literal_inference 失败(因果证明)
  - §4 边界:H4 LLC error / H5 Array<int> 字段 LLC error / H13 倒置 segfault 三处粒度边界文档化 + Followup 锚锁 sub-D
  - §5 路线:对照 D088 §正模式 + §第一性需求距离 1 phase(Phase 3 → Phase 4 cleanup)
  - §6 根因:测试覆盖是反向自证锚(VCM §3),非表面 patch — §A.2 H1-H8 全 PASS 是 §核心目标 末层断言双轨制证据

### Phase 4: workaround cleanup [✓] Done at commit `b0f046c` (2026-04-27)

- 实测 grep `let \w\+: \w\+ = {` lib/ tests/ --include='*.ss' 排除 `explicit_override` + `object_literal.ss` = **0 处**(D143 §核心目标 line 32 反推机制 fn 实参 OBJ_LITERAL 路径覆盖范围下,stdlib(`lib/spring/data.ss` / `lib/json.ss` / `lib/url.ss` / `lib/argparse.ss` / `lib/path.ss` / `lib/string_utils.ss` / 其他 lib/) + tests/(`d134_mysql` / `phase5/` / 其他 tests/) 已**无临时变量绑定** `let u: User = {...}; takesFn(u)` 形态 workaround 候选);排除项 `tests/d143_object_literal_inference/explicit_override.ss` 是 D143 Phase 3 测试自测显式注解走 D084 路径(非 workaround)+ `tests/phase5/object_literal.ss` 是 D084 既有 baseline 测试(2026-03-09 起既有,非 D143 Phase 4 cleanup 候选)
- **Phase 4 docs-only 降级**(无 cleanup 实施 — 与 D141 Phase 4 commit `70f9457` 11 处实施 + D142 Phase 4 commit `f757aca` 4 处实施不同形;D143 Phase 4 全 0 处 cleanup 候选 → LOC delta = 0,仅 D143 文档改动 — D135/D136/D137/D140 范式同位 docs-only 终结亦先有先例)
- **关键发现 D143 反推机制 fn 实参 OBJ_LITERAL 路径 stdlib + tests/ 已无 workaround 候选** — Phase 0 §1 必读清单 + §核心目标 line 32 + §6 风险锚 R3 提到 `lib/spring/data.ss` Phase 4 grep 候选(已存"待 Phase 4 grep 实测后定计数"占位)→ Phase 4 实测确认 lib/spring/data.ss 全 0(D141 Phase 4 已清理 lambda 类型注解 5 处 + lib/spring/data.ss 既无 OBJ_LITERAL fn 实参绑定形态);其他 lib/ + tests/ 同 0 命中 — `let u: User = {...}; takesFn(u)` 形态在 D143 反推机制覆盖范围(fn/method 实参 OBJ_LITERAL 路径)下既无既有候选,亦无后续业务路径残留(用户写 `takesFn({...})` 直接走 G1 反推路径)
- **范围排除项**:OBJ_LITERAL 不在 fn/method 实参路径的形态非 D143 Phase 4 cleanup target — (a) **NEW_EXPR ctor 实参 OBJ_LITERAL**(`new Profile({...})` 路径)留 §Followup F4 sub-D(D142 §F7 + D143 §F4 同根因合并锚 — `bootstrap/gen/class/class.ss:288-301 genNewExpr` args 循环未调 `inferObjLiteralFields`);(b) **var decl 显式注解 D084 rewrite**(`let x: User = {...}` 路径)是 D084 既有路径,非 workaround;(c) **partial fields / 默认值**(`{ name: "X" }` 漏字段)Phase 3 H4 实测 LLC error 严格模式决策行落档,留 §Followup F6 sub-D;(d) **倒置类型 / 无 callee context 粒度过松**(H13 实测 segfault + unknown kind LLC error)留 §Followup F8 sub-D
- VCM 六验全 PASS:
  - 核心代码路径 diff=0(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出)→ **VCM §1 豁免锚成立**(bootstrap 三阶段固定点豁免)
  - `bin/ss test tests/d143_object_literal_inference/` 6/0/6 不破(Phase 3 全绿延续)✓
  - `bin/ss test tests/d142_array_literal_inference/` 6/0/6 不破 ✓
  - `bin/ss test tests/d141_lambda_inference/` 5/0/5 不破 ✓
  - `bin/ss run tools/reflection_health_linter.ss` GATE PASS no regressions(Phase 4 docs-only 不动 bootstrap 不增量,扩容申报-Phase2 6 metric baseline 不变)✓
  - `bin/ss run tools/d_doc_index_linter.ss` PASS:10 referenced Ds all live(F1=0 死指针 / F2 soft warn 12 orphan 含 D143 不阻)✓
- D135/D136/D137/D140/D141/D142 范式延续(每 Phase 独立 commit 大改档,Phase 4 cleanup 实施单元 — D141 Phase 4 commit `70f9457` 11 处 + D142 Phase 4 commit `f757aca` 4 处 + D143 Phase 4 commit `b0f046c` 0 处 docs-only 降级,实测发现反推机制覆盖范围下 lib/+tests/ 全 0 cleanup 候选 — 反映 D141/D142 Phase 4 已清理 lambda 类型注解 + ctor (NEW_EXPR) 路径 array literal 临时变量绑定 后,fn/method 实参 OBJ_LITERAL 路径 stdlib + tests/ 既无既有 workaround 候选)

### Phase 5: 全 Phase 收关 [✓] Done at commit `<TBD>` (2026-04-27)

**全 Phase 收关锚 — D143 主线 close**

5 Phase commit hash 全列(全实测 git log 存在;Phase 5 单 commit 不能引用自己 hash 用占位符 `<TBD>`,与 D141 Phase 5 commit `8f897e7` + D142 Phase 5 commit `0339171` 范式一致 — 下轮 hash 回填轮替换为实际 hash):

| Phase | Commit | 性质 | 内容简述 |
|-------|--------|------|----------|
| Phase 0 | `50912b4` | docs | D 文档落档:D141 §Followup F2 / D142 §Followup F1 object literal contextual typing 候选入口 + C2 接口层 trap + G1 D141/D142 同模式复刻路径 + §A.1 三主候选 + §A.1.1 三实施路径 + §A.2 H1-H13 隐藏假设 + §A.3 废案 + Phase 0-5 计划草案 + Followup F1-F7 |
| Phase 1 | `f089738` | docs | RED 复现 + 信息源探查:`/tmp/spike_obj_lit_red.ss` 3 形态(单字段 / 多字段 / 嵌套)RED 铁证 `grep -c "object literal requires type annotation"` = 3(line 45:43 / 49:46 / 53:74 全命中,**比 D141/D142 RED 更硬** — checker 阶段直接拒绝非 silent miscompile)+ §A.2 H1 同模式实证 PASS(funcParamTypes class 名 codegen 阶段满载)+ §A.2 H10 OOD 实证 PASS(eval/ 17 文件 grep OBJ_LITERAL 0 命中,**比 D141 H10 + D142 H10 都弱**)+ OBJ_LITERAL 节点 slot 探查 PASS(parse_exprs.ss:521-522 仅 nList 占,Phase 2 用 nSetS2 与 ARRAY_LIT(D142)/ARROW_FUNC PARAM(D141) s2 同范式)|
| Phase 2 | `5eb722e` | feat | codegen 阶段反推实施 + G1 D141/D142 同模式复刻(`check_exprs.ss:285` OBJ_LITERAL untyped 放行 + `check_types.ss` inferType case 加 fallback "auto" + `gen_types.ss` helper 三函数 `isClassType`/`extractClassName`/`inferObjLiteralFromType`+`inferObjLiteralFields` + inferType OBJ_LITERAL case + `gen_calls.ss:284` + `gen/methods/gen_methods.ss:206` args 循环反推回填 + eval pre-eval 前移三处 `eval/call.ss:36` + `eval/method_call.ss:64` + `eval/new_expr.ss:24` 同 D141/D142 H10 OOD 实证错估修正 + `class/class_method.ss:genNamedConstructorArgs` H3 嵌套反推 + D084 rewrite 复用扩 fn 实参入口)+ spike `Y:18` + `Z@Earth` GREEN + bootstrap 三阶段固定点 PASS + tests 270/4/274 baseline 不降 + reflection_health GATE PASS 扩容申报 D143#扩容申报-Phase2 6 metric(M1=5450→5550 / M2=80000→81600 / M4=3109→3250 / N2=400000→408000 / N3=550000→562000 / F1:gen_types.ss=915→970)|
| Phase 3 | `15f8dfe` | feat | 6 测试用例落锚 `tests/d143_object_literal_inference/`(`single_field` H1 / `multi_field` H2 / `nested` H3 / `mixed_field` H5 string+int+double 异质 / `explicit_override` H6 D084 路径 / `interface_upcast_skip` H5b NEW_EXPR + vtable indirect)挑战 §A.2 H1/H2/H3/H5/H5b/H6/H7/H8 全 PASS + H4 决策行严格模式 + H5 部分 OOD scope(Array<int>/Map<K,V> 字段反推 OOD,Followup F4 NEW_EXPR ctor positional args 子节点反推漏)+ H13 粒度过松反向问题实证(倒置类型 segfault silent miscompile + 无 callee context unknown kind LLC error,Followup F8 粒度细化)+ §A.2 H10 cross-D 实证 SSoT 反思 memory 落档(`feedback_h10_cross_d_verify.md`)+ §Followup F4 描述扩 ARRAY_LIT 子节点反推同根因 + F8 新增 H4/H13 粒度细化锚 |
| Phase 4 | `b0f046c` | docs | workaround cleanup [✓] **grep 实测 0 命中** — Phase 4 docs-only 降级(无 cleanup 实施 — D143 Phase 4 全 0 处 cleanup 候选 → LOC delta = 0,仅 D143 文档改动);**关键发现 D143 反推机制 fn 实参 OBJ_LITERAL 路径 stdlib + tests/ 已无 workaround 候选**(D141 Phase 4 已清理 lambda 类型注解 + D142 Phase 4 已清理 ctor (NEW_EXPR) 路径 array literal 临时变量绑定 后,fn/method 实参 OBJ_LITERAL 路径既无既有 workaround 候选,亦无后续业务路径残留)|
| Phase 5 | `<TBD>` | docs | 全 Phase 收关 §Phase 5 §全 Phase 收关锚 + Status 时间线 Phase 5 行 + D143 主线 close trail |

**兑现成果总结 a-g**:

- **a. C2 接口层 trap 落地**(§A.1 决策行)— `bootstrap/checker/check_exprs.ss:285` OBJ_LITERAL untyped 放行(D141 ARROW_FUNC + D142 ARRAY_LIT 同模式不硬错,反推回填发生在 codegen 阶段)+ `bootstrap/checker/check_types.ss` inferType OBJ_LITERAL case 加 fallback "auto"(checker 阶段 nSetS2 未发生 isTypeCompatible 放行)+ `bootstrap/gen/gen_types.ss` 三 helper(`isClassType` / `extractClassName` / `inferObjLiteralFromType` + `inferObjLiteralFields` — 对偶 D141 isFnType / extractFnParamType / inferArrowFuncParams + D142 isArrayType / extractArrayElemType / inferArrayLitElems)+ inferType OBJ_LITERAL case 优先读 nGetS2 fallback "ptr" + `bootstrap/gen/gen_calls.ss:284` + `bootstrap/gen/methods/gen_methods.ss:206` args 循环反推插桩(D141/D142 G1 4 落点同模式)+ **eval pre-eval 前移三处** `bootstrap/eval/call.ss:36` + `bootstrap/eval/method_call.ss:64` + `bootstrap/eval/new_expr.ss:24`(D141/D142 H10 OOD 实证错估同模式修正 — Phase 1 仅 grep 字面 handler `evalObjLiteral` 0 命中漏判通用 pre-eval `genVal(callArgId)` 路径)+ **嵌套 H3 反推链路** `bootstrap/gen/class/class_method.ss:genNamedConstructorArgs` 用 classFieldTypes 反推 inner OBJ_LITERAL(对偶 fn args 路径用 funcParamTypes)+ D084 rewrite 复用扩 fn 实参入口(typeAnn = "" 但反推得 className → 同 D084 rewrite NEW_EXPR)+ spike IR 因果实证 `takesUser({ name: "Y", age: 18 })` + `takesProfile({ user: { name: "Z", age: 20 }, addr: "Earth" })` GREEN 输出 `Y:18` + `Z@Earth`(对照 RED `[genVal] unknown kind: OBJ_LITERAL` + `call ptr @takesUserSingle(ptr 0)` IR 错例)Done at commit `5eb722e`

- **b. workaround cleanup 0 处全 0 候选**(Phase 4 docs-only 降级)— `grep -rn 'let \w\+: \w\+ = {' lib/ tests/ --include='*.ss' | grep -v 'explicit_override\|object_literal.ss'` = **0**(排除 D143 Phase 3 自测 explicit_override.ss + D084 既有 baseline tests/phase5/object_literal.ss);**关键发现 D143 反推机制 fn 实参 OBJ_LITERAL 路径 stdlib + tests/ 已无 workaround 候选** — `lib/spring/data.ss` D141 Phase 4 已清理 lambda 类型注解 5 处 + 既无 OBJ_LITERAL fn 实参绑定形态;其他 lib/(`json` / `url` / `argparse` / `path` / `string_utils` / 其他)+ tests/(`d134_mysql` / `phase5/` / 其他)同 0 命中 — `let u: User = {...}; takesFn(u)` 形态在反推机制覆盖范围下既无既有候选,亦无后续业务路径残留;**范围排除项**(a) **NEW_EXPR ctor 实参 OBJ_LITERAL** 留 §Followup F4 sub-D(D142 §F7 + D143 §F4 同根因合并锚 — `bootstrap/gen/class/class.ss:288-301 genNewExpr` args 循环未调 `inferObjLiteralFields`);(b) **var decl 显式注解 D084 rewrite** 是 D084 既有路径非 workaround;(c) **partial fields / 默认值** 留 §Followup F6 sub-D(Phase 3 H4 LLC error 严格模式决策行落档);(d) **倒置类型 / 无 callee context 粒度过松** 留 §Followup F8 sub-D(Phase 3 H13 实测 segfault + unknown kind LLC error)Done at commit `b0f046c`

- **c. 隐藏假设 H1-H13 全 PASS / H9/H11/H12 OOD 标 + H4 决策行 + H5 部分 OOD + H13 粒度过松反向问题实证**:
  - **H1 ✓ 同模式 PASS**(Phase 1 实证 — `codegen.ss:110-112 funcParamTypes.set(\`${fname}:${pCount}\`, nGetS2(fpId))` + `gen_registry.ss:56-57 funcParamTypes.set(\`${baseName}:${pCount}\`, nGetS2(pId))` + `codegen.ss:326 registerAllDecls(rootId)` 在 `emitGlobalsAndCode(rootId)` **之前** — 时序就绪,反推时点 funcParamTypes 满载,class 名 `User` / `Profile` 等字符串原样直存;D141/D142 H1 同模式继承)Done at commit `f089738`
  - **H2 ✓ 多字段同质反推 PASS**:`tests/d143_object_literal_inference/multi_field.ss` `takesUser({ name: "Y", age: 18 })` GREEN 输出 `Y:18`(IR `call ptr @User_new(ptr @.str.N, i32 18)`,字段值各自 inferType + ctor PARAM 类型一致)Done at commit `15f8dfe`
  - **H3 ✓ 嵌套反推 capture 链 PASS**:`tests/d143_object_literal_inference/nested.ss` `takesProfile({ user: { name: "Z", age: 20 }, addr: "Earth" })` GREEN 输出 `Z@Earth`(`gen/class/class_method.ss:genNamedConstructorArgs` 用 classFieldTypes["Profile.user"]="User" 反推 inner OBJ_LITERAL + `eval/new_expr.ss` pre-eval 前移对偶 — 嵌套 capture 链路完整,**比 D141 H3 嵌套 lambda OOD 强**,与 D142 H3 嵌套 array 同位 PASS)Done at commit `15f8dfe`
  - **H4 ✗ 决策行严格模式**(Phase 3 实测铁证 — Followup F6 + F8 sub-D)— `takesUser({ name: "X" })` 用户漏 age 实测 LLC error `call ptr @User_new(ptr @.str.85, )` arity 空缺,**SS 编译期硬错诊断粒度落空**(LLC 阶段才报错,用户看到 LLC error 不知是 OBJ_LITERAL 漏字段);**决策走 (a) 严格模式**(用户必须补全字段,与 D084 既有 ctor 行为一致);(b) 默认值模式 sub-D 留 **Followup F6 ctor 默认值机制**(D084 扩展)+ **Followup F8 H4 编译期硬错诊断粒度细化**
  - **H5 ✓ 部分 PASS / 部分 OOD scope**:`mixed_field.ss` `takesItem({ name: "Apple", count: 3, price: 1.5 })` 异质 string+int+double GREEN 输出 `Apple:3:1.5`;**Array<int> / Map<K,V> 字段反推 OOD scope** spike `class User { ..., scores: Array<int> }` + `{ ..., scores: [90, 80, 70] }` 实测 LLC error `'%9' defined with type 'ptr' but expected 'i32'` — 根因 `class/class.ss:288-301 genNewExpr` ctor positional args 路径**未调 inferArrayLitElems**(D142 §F7 同根因);**Followup F4 NEW_EXPR ctor 实参子节点反推 OBJ_LITERAL+ARRAY_LIT 同形** sub-D Done at commit `15f8dfe`
  - **H5b ✓ interface upcast OOD PASS**:`interface_upcast_skip.ss` `takesShape(new Square(2.0))` 显式 NEW_EXPR + interface IShape 反推 className=IShape 不可 instantiate 走 D025 vtable indirect dispatch GREEN 输出 4.0 — 用户必须显式 NEW_EXPR 构造,OBJ_LITERAL 反推机制不破坏既有 NEW_EXPR + vtable 路径(零破坏既有)Done at commit `15f8dfe`
  - **H6 ✓ 显式注解优先级 > 推断 PASS**:`explicit_override.ss` `let u: User = { name: "Z", age: 25 }; takesUser(u)` GREEN 输出 `Z:25`(D084 既有路径不破)— `inferObjLiteralFromType:line 878 if (nGetS2(argId) != "") return` 显式优先粒度 Done at commit `15f8dfe`
  - **H7 ✓ tests/ 270/4/274 baseline 不破 PASS**:`tests/d141_lambda_inference/` 5/0/5 + `tests/d142_array_literal_inference/` 6/0/6 + `tests/d143_object_literal_inference/` 6/0/6 全绿;Phase 3+4 核心代码路径 diff=0 → VCM §1 豁免 `./build.sh bootstrap` + `bin/ss test tests/` 全跑;Phase 5 docs-only 不动 bootstrap 不破 baseline
  - **H8 ✓ reflection_health_linter GATE PASS**:扩容申报 D143#扩容申报-Phase2 6 metric F1 增量(M1=5450→5550 / M2=80000→81600 / M4=3109→3250 / N2=400000→408000 / N3=550000→562000 / F1:gen_types.ss=915→970 — `class/class_method.ss` reflection scope 触碰 + helper 三函数 + 5 处反推插桩点累计);Phase 3+4+5 不动 bootstrap 不增量;M/N AUTO-DRIFT 软警告不阻 GATE PASS
  - **H9 ✓ var binding callee 反推 OOD scope**(D141/D142 H9 同模式继承)— spike `const f = takesUser; let u: User = {...}; const r: string = f(u)` 实测 LLC error `assertEqual(i64 %19, ptr @.str.98)`(var binding callee 不仅参数反推 OOD,**返回类型推断也 OOD** — i64 vs string 不匹配,即使加显式 `: string` 注解仍 OOD);**OBJ_LITERAL 反推机制不扩到 var binding callee**(主线场景 fn call / method call callee 在 funcParamTypes,不受影响);用户 var binding 时仍需显式 var decl 兜底 + 走 D084 既有路径,不影响 D143 主线 cleanup
  - **H10 ✗→✓ Phase 1 OOD 实证错估 → Phase 2 修正 PASS**:Phase 1 仅 grep `evalObjLiteral` / `OBJ_LITERAL` 字面 handler **0 命中**就标 OOD,但忽略 `eval/call.ss:86 + eval/method_call.ss:89 + eval/new_expr.ss:38` **通用 pre-eval `genVal(callArgId)`** 路过 OBJ_LITERAL 走 line 93 `[genVal] unknown kind` fallback `constVal("0")` silent miscompile(`call ptr @takesUserSingle(ptr 0)` IR 错例铁证);Phase 2 实施过程 spike `[genVal] unknown kind: OBJ_LITERAL` 暴露 H10 OOD 实证错估 — 修正路径与 D141 H10 + D142 H10 完全同形:**eval/call.ss + eval/method_call.ss + eval/new_expr.ss 三处 pre-eval 之前同模式前移 inferObjLiteralFields**(D141/D142 inferArrowFuncParams + inferArrayLitElems 同位)+ 嵌套 H3 链路在 `class/class_method.ss:genNamedConstructorArgs` 用 classFieldTypes 反推 inner OBJ_LITERAL(对偶 fn args 路径用 funcParamTypes)— Phase 2 修正后 spike `Y:18` + `Z@Earth` GREEN;**memory `feedback_h10_cross_d_verify.md` 落档反复跨 D 验证模式** — outer call site 通用 pre-eval `genVal(argId)` 才是反推时序的关键,字面 handler 0 命中 ≠ 反推无需前移
  - **H11 ✓ callee PARAM `class X` 字符串已结构化(比 D141 H11 + D142 H11 都弱)PASS**:D141 G1 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn`(parser.ss 扩 fn 类型 annotation 解析);D142 callee `Array<T>` 已结构化无前置;D143 callee `class X` IDENT 单 token 已就绪 — Phase 2 反推 helper extractClassName("User") = "User" 直接消费,无 G1 callee 升级前置 + 无 parser 扩;非结构化 callee(funcParamTypes 仍是 ""/单 IDENT)→ 反推 skip 不破现有调用方;参 D141 H13 + D142 H13 粒度
  - **H12 ✓ parser 不需要扩(比 D141 H12 + D142 H12 都弱)PASS**:D141 H12 必须 parseTypeAnn IDENT "fn" + LPAREN 分支扩;D142 嵌套 generic Array<...> 已就绪;D143 class 名是 IDENT 单 token,parser 已就绪无嵌套 generic 解析需求;Phase 2 不动 parser
  - **H13 ✗ 粒度过松反向问题实证**(Phase 3 实测铁证 — Followup F8 sub-D)— (a) **倒置类型 silent miscompile**:`takesUser({ name: 18, age: "X" })` 实测 segfault(checker 阶段反推 className=User GREEN + 字段值 inferType 与 ctor PARAM 类型不一致 silent fallback 不硬错,运行时 segfault);(b) **无 callee context 走错例**:`let x = { name: "X", age: 18 }`(var decl 无类型注解 + 无 fn 实参 callee)实测 `[genVal] unknown kind: OBJ_LITERAL` LLC error `store ptr 0`(反推 skip 走 fallback "ptr",但 codegen 无 OBJ_LITERAL handler);**当前粒度过松**(silent miscompile 而非硬错)— **Followup F8 反推失败粒度细化 sub-D 锁此场景**(checker 阶段加字段值类型与 ctor PARAM 一致性检查 + var decl no annot + no callee context 时 OBJ_LITERAL 走硬错诊断,非 silent fallback)

- **d. axiom 红线永久 grep = 0**:`feedback_root_cause_no_cost.md`(成本不是选次优的理由)红线 grep 永久 0 + `feedback_no_option_menu.md`(三候选论证 + 决策行)红线 grep 永久 0 + `feedback_no_derive_workaround.md`(主线能力缺口不允许 annotation 替代)红线 grep 永久 0 — D143 文档治理永久锚

- **e. d_doc_index_linter PASS 永久**:Phase 0-5 D143 §-form 引用(D025 / D131 / D141 / D142 / D084 等 10 referenced Ds)实存 → F1 = 0 死指针;F2 soft warn 12 orphan 含 D143 不阻 commit;Phase 5 不删/合并/重命名 D 文档 F1 不破

- **f. reflection_health_linter GATE PASS 永久**:F1 6 metric 增量(M1=5450→5550 / M2=80000→81600 / M4=3109→3250 / N2=400000→408000 / N3=550000→562000 / F1:gen_types.ss=915→970)已扩容申报 D143#扩容申报-Phase2 + M/N AUTO-DRIFT/SCOPE-DRIFT 软警告不阻;Phase 3+4+5 不动 bootstrap F1 不增量

- **g. bootstrap 隔离破例 D141 §核心原则 5 + D142 §核心原则 6 同位例外**:D143 主线改 bootstrap 修编译器(checker + gen_types helper + 反推插桩 + eval pre-eval 前移 + class_method.ss 嵌套反推)— 与 D141 §核心原则 5 + D142 §核心原则 6 同位例外接受(修编译器主线消除 stdlib workaround 是法定 root cause 路径,§Root Cause 第一法则 / `feedback_root_cause_no_cost.md`);D143 §核心原则 7(bootstrap 隔离破例)同位继承

**§Followup F1-F8 锚明确**(line 444-455 已锁,Phase 5 收关确认):

- **F1 ternary contextual typing — `cond ? a : b` 在 fn 实参 `Maybe<int>` 时反推分支类型** — D141 §Followup F3 + D142 §Followup F2 同模式锚,**留 D144 起首候选**
- F2 Map literal contextual typing — `{ "k": "v" }` Map literal 在 fn 实参 `Map<string,string>` 反推 — array literal 同模式 sub-D(D142 §Followup F5 同位)
- F3 Tuple literal contextual typing — tuple literal 在 fn 实参 `Tuple<int,string>` 反推 — array literal 同模式 sub-D(D142 §Followup F6 同位)
- **F4 NEW_EXPR ctor 实参子节点反推**(OBJ_LITERAL + ARRAY_LIT 同形)— `new Profile({ user: {...}, addr: {...} })` ctor args 中 object literal 反推 + `new User("X", 18, [90, 80])` ctor args 中 array literal 反推 — D143 Phase 2 G1 4 落点未含 NEW_EXPR;**Phase 3 H5 with Array<int> 字段实测铁证 LLC error `expected 'i32'`**(根因 `bootstrap/gen/class/class.ss:288-301 genNewExpr` ctor positional args 路径未调 `inferArrayLitElems` / `inferObjLiteralFields`)— D142 §Followup F7 + D143 §F4 同根因合并 sub-D 锚
- F5 bidirectional type checking 全局 — C3 候选废案,留作未来 SS 类型系统 v2(D026/D027 落地后再开 D 文档评估,D141 §Followup F5 + D142 §A.3 同位)
- **F6 object literal partial fields + class ctor 默认值** — 部分字段反推 + ctor 漏字段默认值机制 — **Phase 3 H4 实测 LLC error 严格模式决策行落档**(`takesUser({ name: "X" })` 实测 `call ptr @User_new(ptr @.str.85, )` arity error,SS 编译期硬错诊断粒度落空)— sub-D 锁此场景(扩 D084 ctor 默认值机制 + 字段值类型一致性 checker 阶段硬错)
- F7 object literal spread `{...base, name: "X"}` 反推 — spread 子节点反推 + 字段覆盖 — array literal SPREAD 同模式 sub-D
- **F8 反推失败粒度细化(H4 + H13 同形)** — **Phase 3 H13 实测铁证粒度过松反向问题** — (a) 倒置类型 `{ name: 18, age: "X" }` silent miscompile segfault + (b) 无 callee context `let x = { name: "X" }`(var decl 无注解 + 无 fn 实参 callee)实测 `[genVal] unknown kind: OBJ_LITERAL` LLC error;sub-D 锁此场景(checker 阶段加字段值与 ctor PARAM 类型一致性检查 + var decl no annot + no callee context 时 OBJ_LITERAL 走硬错诊断,非 silent fallback)

**Phase 5 兑现成果**:D143 主线 object literal contextual typing 反推机制 6 Phase 全闭环 — Phase 0 落档 → Phase 1 RED 探查 + H1/H10 同模式实证(H10 OOD 实证错估留 Phase 2 修正)→ Phase 2 G1 路径实施 + H3 嵌套反推 + spike `Y:18` + `Z@Earth` GREEN + §A.2 H10 OOD 实证错估修正 → Phase 3 测试覆盖 6/0/6 全绿 + H1-H8 全 PASS + H4/H5/H13 决策行落档 + Followup F4/F6/F8 加锚 + H10 cross-D memory 落档 → Phase 4 workaround cleanup docs-only 降级(lib/+tests/ 全 0 cleanup 候选)→ **Phase 5 全 Phase 收关 D143 主线 close**;**D141 §Followup F2 + D142 §Followup F1 主线 close**;Followup F1-F8 入下一 D 文档启动队列(F1 ternary contextual typing 候选 D144 入口 — D141 §Followup F3 / D142 §Followup F2 同模式);D135/D136/D137/D140/D141/D142 范式延续(每 Phase 独立 commit 大改档,Phase 5 终结 Phase docs-only commit — D142 Phase 5 commit `0339171` 同模式)

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | ternary contextual typing | `cond ? a : b` 在 fn 实参 `Maybe<int>` 时反推分支类型 — D141 §Followup F3 + D142 §Followup F2 同模式锚,留 D144 起首候选 |
| F2 | Map literal contextual typing | `{ "k": "v" }` Map literal 在 fn 实参 `Map<string,string>` 反推 — array literal 同模式 sub-D(D142 §Followup F5 同位)|
| F3 | Tuple literal contextual typing | tuple literal 在 fn 实参 `Tuple<int,string>` 反推 — array literal 同模式 sub-D(D142 §Followup F6 同位)|
| F4 | NEW_EXPR ctor 实参子节点反推(OBJ_LITERAL + ARRAY_LIT 同形)| `new Profile({ user: {...}, addr: {...} })` ctor args 中 object literal 反推 + `new User("X", 18, [90, 80])` ctor args 中 array literal 反推 — D143 Phase 2 G1 4 落点未含 NEW_EXPR;**Phase 3 H5 with Array<int> 字段实测铁证 LLC error `expected 'i32'`**(根因 `bootstrap/gen/class/class.ss:288-301 genNewExpr` ctor positional args 路径未调 `inferArrayLitElems` / `inferObjLiteralFields`)— D142 §Followup F7 + D143 §F4 同根因合并 sub-D 锚 |
| F5 | bidirectional type checking 全局 | C3 候选废案,留作未来 SS 类型系统 v2(D026/D027 落地后再开 D 文档评估,D141 §Followup F5 + D142 §A.3 同位)|
| F6 | object literal partial fields + class ctor 默认值 | 部分字段反推 + ctor 漏字段默认值机制 — **Phase 3 H4 实测 LLC error 严格模式决策行落档**(`takesUser({ name: "X" })` 实测 `call ptr @User_new(ptr @.str.85, )` arity error,SS 编译期硬错诊断粒度落空)— sub-D 锁此场景(扩 D084 ctor 默认值机制 + 字段值类型一致性 checker 阶段硬错)|
| F7 | object literal spread `{...base, name: "X"}` 反推 | spread 子节点反推 + 字段覆盖 — array literal SPREAD 同模式 sub-D |
| F8 | 反推失败粒度细化(H4 + H13 同形)| **Phase 3 H13 实测铁证粒度过松反向问题** — (a) 倒置类型 `{ name: 18, age: "X" }` silent miscompile segfault(checker 阶段反推 className 后字段值类型与 ctor PARAM 不一致 silent fallback)+ (b) 无 callee context `let x = { name: "X" }`(var decl 无注解 + 无 fn 实参 callee)实测 `[genVal] unknown kind: OBJ_LITERAL` LLC error;sub-D 锁此场景(checker 阶段加字段值与 ctor PARAM 类型一致性检查 + var decl no annot + no callee context 时 OBJ_LITERAL 走硬错诊断,非 silent fallback)|

---

## 扩容申报-Phase2

> Phase 2 实施触发 6 处 budget_max 越界(M1/M2/M4/N2/N3 反射路径指标 + F1 gen_types.ss 行数)。class_method.ss(`bootstrap/gen/class/`)落 H3 嵌套反推改触碰 reflection scope(D097 §isReflectionScope `bootstrap/gen/class/*` 命中)— 跑 `bin/ss run tools/reflection_health_linter.ss` GATE BLOCKED 6 metric。按 `docs/3-MNK.md §特定领域 §反射路径根因 gate B 路径` 走扩容申报 — D141 §扩容申报-Phase2-G1 + D142 §扩容申报-Phase2 同范式。

| 文件 / 指标 | budget_max(旧)| cur(新)| delta | 增量内容 |
|------|----------------|---------|-------|----------|
| `M1` (CC 总和) | 5450 | 5534 | +84 | Phase 2 helper 三函数(`isClassType` / `extractClassName` / `inferObjLiteralFromType` / `inferObjLiteralFields`)+ check_exprs.ss OBJ_LITERAL 字段值 checkExpr 循环 + check_types.ss inferType OBJ_LITERAL case + gen_types.ss inferType OBJ_LITERAL case + 4 个反推前移调用点(eval/call.ss + eval/method_call.ss + eval/new_expr.ss + class_method.ss)CC 累计 |
| `M2` (AST 节点总数) | 80000 | 81544 | +1544 | 同上,helper 函数 + 反推前移点的 AST 节点数 |
| `M4` (Dispatch 深度和) | 3109 | 3242 | +133 | 同上,helper 函数 + IF/分发分支累计 |
| `N2` (Halstead 体积) | 400000 | 407720 | +7720 | 同上,代码体量累计 |
| `N3` (AST 深度总和) | 550000 | 561686 | +11686 | 同上,嵌套深度累计 |
| `F1:bootstrap/gen/gen_types.ss` | 915 | 968 | +53 | Phase 2 新加 helper:`isClassType`(13 行)+ `extractClassName`(11 行)+ `inferObjLiteralFromType`(13 行)+ `inferObjLiteralFields`(10 行)+ inferType OBJ_LITERAL case(8 行)|

申报理由:G1 路径根因 100%(callee PARAM 已结构化 class 名 + funcParamTypes SSoT 复用,反推机制单点回填,信息源一致 — 比 D141/D142 G1 更轻无 callee 升级前置 + 无 parser 扩);触碰 reflection scope 因 H3 嵌套反推必须落 `class/class_method.ss:genNamedConstructorArgs`(class field 类型反推 inner OBJ_LITERAL — ctor args 路径)— 但**无新反射操作**(D084 rewrite 同模式 inline:nKind/nSetS1/nSetS2);F1 增量纯结构化新功能码,无样板压注释/合并空行/字符级绕过(`feedback_600_split_not_inline.md` + `feedback_structure_not_linecount.md`)。helper 落 gen_types.ss 与 D141/D142 helper 同族归类(类型工具集中处),后续若拆分按职能(类型推断 / 类型签名 / fn helper / Array helper / OBJ_LITERAL helper)再切。

---

## Status 时间线

- 2026-04-27 Phase 0 D 文档落档(commit `50912b4`)— D141 §Followup F2 / D142 §Followup F1 object literal contextual typing 候选入口落档;C2 接口层 trap + G1 D141/D142 同模式复刻路径决策(待 Phase 1 用户对话锁定方向后启动实施);§A.1 三主候选 + §A.1.1 三实施路径 + §A.2 H1-H13 隐藏假设挑战 + §A.3 废案 + Phase 0-5 计划草案 + Followup F1-F7;D135/D136/D137/D140/D141/D142 范式延续(每 Phase 独立 commit 大改档 + Status 收关 + commit hash 回填 + next_prompt 自闭环)
- 2026-04-27 Phase 1 RED 复现 + 信息源探查(commit `f089738`)— `/tmp/spike_obj_lit_red.ss` 3 形态 RED 铁证 `grep -c "object literal requires type annotation"` = 3(line 45:43 / 49:46 / 53:74)+ §A.2 H1 同模式实证 PASS(funcParamTypes class 名 codegen 阶段满载 — codegen.ss:110-112 + gen_registry.ss:56-57 + codegen.ss:326)+ §A.2 H10 OOD 实证 PASS(eval/ 17 文件 0 OBJ_LITERAL 命中,**比 D141/D142 H10 弱**)+ OBJ_LITERAL 节点 slot 探查 PASS(parse_exprs.ss:521-522 仅 nList,s1/s2/s3+i1-i4 全空闲)+ Phase 2 入口锁(checker check_exprs.ss:285 改反推优先 + check_types.ss OBJ_LITERAL inferType 返 `class<ClassName>` + codegen 反推 nGetS2 + D084 rewrite 复用扩 fn 实参)+ §1 必读清单补 check_exprs.ss:285-287 / check_stmts.ss:107-117 / gen_decls.ss:507-516 / parse_exprs.ss:500-523 4 锚 — D135/D136/D137/D140/D141/D142 范式延续(D142 Phase 1 commit `eb26644` 同模式)
- 2026-04-27 Phase 2 codegen 阶段反推实施 + G1 D141/D142 同模式复刻(commit `5eb722e`)— checker check_exprs.ss:285 OBJ_LITERAL untyped 放行(D141 ARROW_FUNC + D142 ARRAY_LIT 同模式不硬错)+ check_types.ss OBJ_LITERAL inferType case 加 fallback "auto" + gen_types.ss 加 helper 三函数(`isClassType` / `extractClassName` / `inferObjLiteralFromType` + `inferObjLiteralFields`)+ inferType OBJ_LITERAL case 加优先读 nGetS2 fallback "ptr" + gen_calls.ss + gen/methods/gen_methods.ss args 循环加 inferObjLiteralFields(D141/D142 G1 4 落点同模式)+ **§A.2 H10 OOD 实证错估修正**(eval/call.ss + eval/method_call.ss + eval/new_expr.ss 三处 pre-eval 之前同模式前移 inferObjLiteralFields — D141 H10 + D142 H10 完全同形)+ **H3 嵌套反推链路**(gen/class/class_method.ss:genNamedConstructorArgs 用 classFieldTypes 反推 inner OBJ_LITERAL + eval/new_expr.ss pre-eval 前移对偶)+ spike `/tmp/spike_d143_phase2.ss` GREEN(`Y:18` + `Z@Earth`)+ VCM 六验全 PASS(bootstrap 三阶段固定点 + tests/ 270/4/274 不降 + reflection_health GATE PASS 扩容申报 D143#扩容申报-Phase2 6 metric 升 baseline + d_doc_index F1=0 + ultrathink_linter)— D135/D136/D137/D140/D141/D142 范式延续(D142 Phase 2 commit `0339171` 同模式)
- 2026-04-27 Phase 3 测试覆盖 + 隐藏假设挑战(commit `15f8dfe`)— `tests/d143_object_literal_inference/` 6 测试落锚 6/0/6 全绿(`single_field` H1 / `multi_field` H2 / `nested` H3 / `mixed_field` H5 string+int+double 异质 / `explicit_override` H6 D084 路径 / `interface_upcast_skip` H5b NEW_EXPR + vtable indirect)+ §A.2 H1/H2/H3/H5/H5b/H6/H7/H8 全 PASS 实证 + **H4 决策行严格模式**(LLC error `call ptr @User_new(ptr @.str, )` arity error,Followup F6 ctor 默认值机制 + F8 编译期硬错诊断粒度细化)+ **H5 部分 OOD scope**(string+int+double 异质 PASS,Array<int> / Map<K,V> 字段反推 OOD 实测 LLC error `expected 'i32'`,D142 §F7 + D143 §F4 同根因 NEW_EXPR ctor positional args 子节点反推漏)+ **H13 粒度过松反向问题实证**(倒置类型 segfault silent miscompile + 无 callee context unknown kind LLC error,Followup F8 粒度细化 sub-D)+ **§A.2 H10 cross-D 实证 SSoT 反思 → memory 落档**(D141/D142 H10 PASS 范式 vs D143 H10 字面 handler 0 命中漏判 — outer call site 通用 pre-eval `genVal(argId)` 才是反推时序关键,memory `feedback_h10_cross_d_verify.md`)+ §Followup F4 描述扩 ARRAY_LIT 子节点反推同根因 + F8 新增 H4/H13 粒度细化锚 + VCM 六验全 PASS(核心代码路径 diff=0 → §1 豁免 + d141 5/0/5 + d142 6/0/6 + d143 6/0/6 全绿 + reflection GATE PASS Phase 3 无 bootstrap diff 无 reflection 触碰 + d_doc_index F1=0 10 referenced Ds all live + ultrathink_linter)— D135/D136/D137/D140/D141/D142 范式延续(D142 Phase 3 commit `2e6a629` 同模式)
- 2026-04-27 Phase 4 workaround cleanup(commit `b0f046c`)— **grep 实测 0 命中**(`grep -rn 'let \w\+: \w\+ = {' lib/ tests/ --include='*.ss' | grep -v 'explicit_override\|object_literal.ss'` = 0,排除 D143 Phase 3 自测 explicit_override.ss + D084 既有 baseline tests/phase5/object_literal.ss);**Phase 4 docs-only 降级**(无 cleanup 实施 — 与 D141 Phase 4 commit `70f9457` 11 处 + D142 Phase 4 commit `f757aca` 4 处不同形;D143 Phase 4 全 0 处 cleanup 候选 → LOC delta = 0,仅 D143 文档改动);**关键发现 D143 反推机制 fn 实参 OBJ_LITERAL 路径 stdlib + tests/ 已无 workaround 候选**(`lib/spring/data.ss` D141 Phase 4 已清理 lambda 类型注解 5 处 + 既无 OBJ_LITERAL fn 实参绑定形态;其他 lib/(json / url / argparse / path / string_utils / 其他)+ tests/(d134_mysql / phase5/ / 其他)同 0 命中 — `let u: User = {...}; takesFn(u)` 形态在反推机制覆盖范围下既无既有候选,亦无后续业务路径残留);范围排除项 — (a) **NEW_EXPR ctor 实参 OBJ_LITERAL** 留 §Followup F4 sub-D(D142 §F7 + D143 §F4 同根因合并锚);(b) **var decl 显式注解 D084 rewrite** 是 D084 既有路径非 workaround;(c) **partial fields / 默认值** 留 §Followup F6 sub-D(Phase 3 H4 LLC error 严格模式决策行落档);(d) **倒置类型 / 无 callee context 粒度过松** 留 §Followup F8 sub-D(Phase 3 H13 实测 segfault + unknown kind LLC error);VCM 六验全 PASS(核心代码路径 diff=0 → VCM §1 豁免锚成立 + tests/d143 6/0/6 + tests/d142 6/0/6 + tests/d141 5/0/5 + reflection_health GATE PASS no regressions 不动 bootstrap 不增量 + d_doc_index PASS 10 referenced Ds all live + ultrathink_linter);LOC delta 0(0 文件改 cleanup,仅 D143 文档落档)— D135/D136/D137/D140/D141/D142 范式延续(D141 Phase 4 commit `70f9457` 11 处 + D142 Phase 4 commit `f757aca` 4 处 + D143 Phase 4 commit `b0f046c` 0 处 docs-only 降级 同模式 lib/+tests/ 全 0 cleanup 候选 — 反映 D141/D142 Phase 4 已清理后 fn/method 实参 OBJ_LITERAL 路径既无既有 workaround 候选)
- 2026-04-27 Phase 5 完结(commit `<TBD>`)— 全 Phase 收关 §Phase 5 §全 Phase 收关锚 5 Phase commit hash 全列(Phase 0 `50912b4` / Phase 1 `f089738` / Phase 2 `5eb722e` / Phase 3 `15f8dfe` / Phase 4 `b0f046c` / Phase 5 `<TBD>`)+ 兑现成果 a-g(C2 接口层 trap 落地 — `check_exprs.ss:285` OBJ_LITERAL untyped 放行 + `check_types.ss` inferType OBJ_LITERAL case fallback "auto" + `gen_types.ss` 三 helper `isClassType`/`extractClassName`/`inferObjLiteralFromType`+`inferObjLiteralFields` + inferType OBJ_LITERAL case 优先读 nGetS2 + `gen_calls.ss:284` + `gen/methods/gen_methods.ss:206` args 循环反推 + eval pre-eval 前移三处 `eval/call.ss:36` + `eval/method_call.ss:64` + `eval/new_expr.ss:24` + `class/class_method.ss:genNamedConstructorArgs` H3 嵌套反推 + D084 rewrite 复用扩 fn 实参入口 / workaround cleanup 0 处全 0 候选 Phase 4 docs-only 降级 / H1-H13 全 PASS / H9/H11/H12 OOD 标 + H4 决策行严格模式 + H5 部分 OOD scope Array<int>/Map<K,V> 字段反推留 §Followup F4 + H13 粒度过松反向问题倒置类型 silent miscompile segfault + 无 callee context unknown kind LLC error 留 §Followup F8 + H10 cross-D 实证 SSoT 反思 memory `feedback_h10_cross_d_verify.md` 落档 / axiom 红线 grep = 0 永久 `feedback_root_cause_no_cost.md` + `feedback_no_option_menu.md` + `feedback_no_derive_workaround.md` / d_doc_index_linter PASS 10 referenced Ds all live + F2 soft warn 12 orphan 含 D143 不阻 / reflection_health_linter GATE PASS 扩容申报-Phase2 6 metric bump 永久(M1=5450→5550 / M2=80000→81600 / M4=3109→3250 / N2=400000→408000 / N3=550000→562000 / F1:gen_types.ss=915→970)+ Phase 3+4+5 不动 bootstrap 不增量 / bootstrap 隔离破例 D141 §核心原则 5 + D142 §核心原则 6 同位例外 — 修编译器主线消除 stdlib workaround 是法定 root cause 路径)+ 隐藏假设 H1-H13 全 PASS / H9/H11/H12 OOD 标(H9 var binding callee D141/D142 同模式继承 + H11/H12 比 D141/D142 都弱 callee `class X` 已结构化无 G1 升级前置 + parser 不需扩)+ §Followup F1-F8 锚明确(**F1 ternary contextual typing 候选 D144 入口** / F2 Map literal / F3 Tuple literal / **F4 NEW_EXPR ctor 实参子节点反推 OBJ_LITERAL+ARRAY_LIT 同形** D142 §F7 + D143 §F4 同根因合并 sub-D / F5 bidirectional v2 留 / **F6 partial fields + ctor 默认值** Phase 3 H4 严格模式决策行 / F7 spread / **F8 反推失败粒度细化 H4+H13 同形** Phase 3 H13 实测铁证)+ 顶部 Status 行从 Phase 4 改 Phase 5 完结 + Status 时间线增 Phase 5 行 + Phase 4 commit hash 回填 `b0f046c`;D143 文档 docs only 1 file 改 + 不动 bootstrap / lib / tests / tools(Phase 5 docs-only 不分 feat/docs 双 commit,D135/D136/D137/D140/D141/D142 范式延续 — 单 commit 大改档终结 Phase 5)+ next_prompt 指向 D143 Phase 5 commit hash 回填轮 + D144 起首候选(D141 §Followup F3 / D142 §Followup F2 / D143 §Followup F1 ternary contextual typing 同模式扩 sub-D);**关键发现:Phase 5 单 commit 不能引用自己 hash → 写入时用占位符 `<TBD>` 标记,与 D141 Phase 5 commit `8f897e7` + D142 Phase 5 commit `0339171` 范式一致**(本轮 hash 回填轮替换为实际 hash,D143 主线 close trail 闭环);**D143 主线 close,D141 §Followup F2 + D142 §Followup F1 主线 close**,Followup F1-F8 入下一 D 文档启动队列(F1 ternary contextual typing 候选 D144 入口);D135/D136/D137/D140/D141/D142 范式延续(每 Phase 独立 commit 大改档,Phase 5 终结 Phase docs-only commit — D142 Phase 5 commit `0339171` 同模式)
