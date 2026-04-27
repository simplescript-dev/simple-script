# D141: SS Lambda 参数类型推断 + Interface Dispatch 集成

**Status:** Phase 0 — D 文档落盘(Plan)
**Depends on:** D025(interface dispatch)/ D137(JdbcTemplate prepared retcon — §F9 follow-up 锚)
**Date:** 2026-04-27
**Last Updated:** 2026-04-27

---

## 核心目标 (Goal)

- **为什么**:lambda `(s) => s.setInt(...)` 无类型注解时 SS interface method dispatch 走错路径,setInt 静默不写入 MysqlPreparedStatement.paramTypes/paramValues,prepared INSERT executeUpdate 全 result=-1。最小隔离 spike `/tmp/spike_lambda_typed.ss` 实证:typed `(s: PreparedStatement) =>` result=1 / untyped `(s) =>` result=-1。D137 Phase 2-3 已落 10 处显式注解 workaround(`lib/spring/data.ss` 6 处 + `tests/d134_mysql/integration_test.ss` 4 处),根因未修则未来任何 fn/method 实参 lambda 类型推断 bug 持续累积。
- **是什么**:在 lambda 作 fn/method 实参时,从 callee 签名查 `funcParamTypes` 反推 ARROW_FUNC 各 PARAM 类型,checker 阶段回填 `nSetS2(paramId, type)`;后续 codegen `gen_arrows.ss:135` 直读 PARAM s2 路径不变,信息源单点回填。配合 `check_types.ss:51` ARROW_FUNC 不再返单一 "fn",改返 `fn(P1, P2, ...): R` 结构化签名。
- **单一判据**:untyped lambda spike(去掉 `(s: PreparedStatement)` 注解仅写 `(s) =>`)= D137 §F9 现状走错路径 result=-1;**根因修后实测 result=1**,且 lib/spring/data.ss + tests/d134_mysql 10 处显式注解可全删(workaround cleanup 推 Phase 4)。

> 一句口号:lambda 参数类型从调用上下文反推,用户不必每处显式标注。

---

## 核心原则 (Principles)

1. **接口层 trap,非数据层 patch** — 信息源单点回填(checker 阶段 ARROW_FUNC PARAM s2),codegen 路径不变;不在 method_call.ss / gen_methods.ss / vtable dispatch 多处零散补 fallback
2. **bidirectional type checking 局部** — 仅 lambda 作 fn/method 实参场景反推,不扩到全编译器全表达式 contextual typing(scope 防爆炸)
3. **TS / Java 8+ contextual typing 主线** — TS 既有能力(`fn arg lambda inferred from param type`)+ Java 8 explicit lambda type 作 fallback(用户仍可手写 `(s: PreparedStatement) =>` override 推断,Java 8+ 风格保留)
4. **workaround 回收推 Phase 4** — Phase 1-3 修编译器 + Phase 4 grep + 删 lib/spring/data.ss + tests/d134_mysql 10 处显式注解(根因修后 cleanup 落锚)
5. **bootstrap 隔离破例** — D137 §核心原则 9 是单 sub-D scope 硬约束(D137 不动 bootstrap 修 lib/spring),D141 本 sub-D scope 就是修 bootstrap(checker + 局部 codegen),与 D137 隔离不冲突
6. **interface dispatch 不破** — D025 `interface PreparedStatement` 契约(setInt/setString/setLong 等)+ vtable indirect dispatch 路径(`gen_methods.ss:209-230`)不动;PARAM s2 回填后 vtable 路径自然走通
7. **funcParamTypes SSoT** — 信息源 `bootstrap/gen/gen_registry.ss:9-10 + 56`(`funcParamTypes` Map "funcName:paramIndex" → SS type),checker 反推时直接消费,不重复注册
8. **零破坏既有 lambda** — 现有 lambda 显式注解(D137 落锚 10 处 + 全项目 lambda 测试 100+)继续走 PARAM s2 直读,推断仅在 s2 = "" 时 fallback 反推,显式优先级 > 推断
9. **F4 D138 编号冲突独立** — 本 D 占 D141(避开 D138/D139 留作 F4 编号冲突修复回收),D 治理后续轮 F4 处理 D136 §R4(line 362)+ §F1(line 386)双指 D138 冲突
10. **Phase 计划独立 commit** — 大改档位:Phase 0 D 文档落盘 + Phase 1+ bootstrap 改各独立 commit,§MNK 大改档不打包
11. **VCM 六验全跑** — bootstrap 三阶段固定点 + tests/ 不降 + d134_mysql 5/5 + d136_prepared_statement 1/1 + reflection_health_linter GATE PASS no regressions

---

## 1. Context Management(上下文管理)

> clear 后的 Claude 动手前 5 分钟内必须加载完本节内容。

### 必读清单(按顺序)

1. 本文档(D141)
2. `CLAUDE.md`(§Java/TS 语法优先 + §Root Cause 优先 第一法则 + §高层架构)
3. 依赖 D 文档:
   - D137 §F9 follow-up(line 418 + 460 + 543 + 552)
   - D025 interface dispatch(`interface PreparedStatement` 契约)
4. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/parse/parse_exprs.ss` | 270-308 | `parseArrowFunc()` — ARROW_FUNC 节点构造,PARAM s1=name / s2=type(无注解时空)|
   | `bootstrap/checker/check_types.ss` | 51 | `if (kind == "ARROW_FUNC") { return "fn" }` — **当前**单一类型,信息丢失 |
   | `bootstrap/checker/check_thread.ss` | 36 | `if (kind == "ARROW_FUNC") { return }` — thread closure check 跳过 ARROW_FUNC,**Phase 2 是否同模式扩到 PARAM 反推待评估** |
   | `bootstrap/checker/check_exprs.ss` | 169 | `if (tsFirstArgId > 0 && nGetKind(tsFirstArgId) == "ARROW_FUNC")` — 已有"fn 实参 + ARROW_FUNC 实参"识别先例,Phase 2 沿此模式扩到通用 fn/method 实参反推 |
   | `bootstrap/gen/gen_arrows.ss` | 105-140 | `genArrowFunc()` — line 135 `nGetS2(pId)` 直读 PARAM s2,无注解时 `ssTypeToLLVM("")` 走默认(**破裂入口**)|
   | `bootstrap/gen/gen_arrows.ss` | 188 | `setVarType(capName, capType)` — capture 类型已设,PARAM 类型未设(同模式扩 PARAM 反推后调 `setVarType(paramName, paramType)`)|
   | `bootstrap/gen/gen_calls.ss` | 231 | `resolveCallArgs(callee, argList, typeCallee)` — fn 调用 args 解析入口,Phase 2 在此识别 ARROW_FUNC 实参 + 查 funcParamTypes 反推 |
   | `bootstrap/gen/gen_registry.ss` | 9-10 + 56 | `funcParamTypes` Map "funcName:paramIndex" → SS type — **信息源 SSoT**,checker 反推时直接消费 |
   | `bootstrap/gen/methods/gen_methods.ss` | 209-230 | vtable indirect dispatch — PARAM s2 回填后,lambda body `s.setInt(...)` 走 vtable indirect 自然 GREEN |
   | `bootstrap/eval/method_call.ss` | 4-120 | `evalMethodCall()` 入口 — comptime + runtime method dispatch,Phase 2 是否需扩待评估 |
   | `lib/spring/data.ss` | (workaround 6 处)| D137 Phase 2 落锚 6 处 `(s: PreparedStatement) =>` 显式注解 — Phase 4 cleanup 删除目标 |
   | `tests/d134_mysql/integration_test.ss` | (workaround 4 处)| D137 Phase 3 落锚 4 处显式注解 — Phase 4 cleanup 删除目标 |
   | `/tmp/spike_lambda_typed.ss` | 全文 | spike 实证 typed PASS 路径(test 1 + test 2);**Phase 1 需补 untyped 版本 spike 实证 result=-1 RED**|

### 加载策略

- 总体 ~2500 行(parse_exprs 80 + check_types 50 + check_exprs 30 + gen_arrows 180 + gen_calls 50 + gen_registry 80 + gen_methods 60 + method_call 120 + lib/spring/data 110 + tests 200 + spike 50)
- Phase 1 spike 复现先,Phase 2 checker 反推实施后,Phase 3 测试覆盖,Phase 4 workaround cleanup
- 不动 D137(Phase 4 cleanup 是回收 D137 workaround,与 D137 §核心原则 9 不冲突 — D137 scope 是 spring/data,D141 scope 是 bootstrap;cleanup 写 D141 commit 不写 D137 commit)

---

## 2. Tools(工具)

| 工具 | 用途 | 触发时机 |
|------|------|----------|
| `./build.sh bootstrap` | 三阶段固定点验证 | Phase 1+ bootstrap 改后必跑(VCM §1)|
| `bin/ss test tests/` | 全测试不降 | VCM §1 + Phase 4 cleanup 验证 |
| `bin/ss test tests/d134_mysql` | D137 + D141 关键路径覆盖 | VCM §2/§3(实测 typed/untyped lambda 双路径)|
| `bin/ss test tests/d136_prepared_statement` | prepared driver 路径不破 | VCM §1 |
| `bin/ss run tools/reflection_health_linter.ss` | 反射路径 GATE | Phase 1+ bootstrap 改后(checker / codegen 触碰反射可能性低,但仍跑)|
| `bin/ss run tools/d_doc_index_linter.ss` | D 文档死指针 / 孤立 | Phase 0 落盘后必跑 + Phase 4 cleanup 后 |
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt 三检查 | After Done 收尾 |
| `bin/ss run /tmp/spike_lambda_untyped.ss` | Phase 1 RED 复现(待写)| Phase 1 起首 |
| `git log --oneline D137*` | D137 5 Phase commit hash 锚 | 沟通时引用 commit hash |

---

## 3. Orchestration(编排)

### 多 Phase 顺序

| Phase | 目标 | 关键产出 | 验证 |
|-------|------|----------|------|
| **Phase 0** | D 文档落盘(本 Phase)| `docs/3-decisions/D141-*.md` | d_doc_index_linter F1 = 0 + ultrathink_linter PASS |
| **Phase 1** | RED 复现 + 信息源探查 | `/tmp/spike_lambda_untyped.ss` 实证 result=-1 + 探查 funcParamTypes 在 checker 阶段是否已 ready(parser 后 → checker 前 → codegen 前) | Phase 1 spike 实测 result=-1(RED 成立)+ funcParamTypes 注册时机文档化 |
| **Phase 2** | checker 反推实施 | `bootstrap/checker/check_types.ss` ARROW_FUNC 改 `fn(P1,P2,...):R` 结构化签名 + `bootstrap/checker/check_exprs.ss` lambda 作 fn/method 实参时反推 PARAM s2 回填 | bootstrap 固定点 PASS + spike untyped → result=1(GREEN)|
| **Phase 3** | 测试覆盖 + 隐藏假设挑战 | `tests/d141_lambda_inference/` 新增(typed lambda / untyped lambda + setter / 嵌套 lambda / 多参 lambda / 推断失败 fallback 报错诊断)| 5+ test case 全绿 + 隐藏假设 H1-H5 全 PASS |
| **Phase 4** | workaround cleanup | grep + 删 `lib/spring/data.ss` 6 处 + `tests/d134_mysql/integration_test.ss` 4 处 显式 `(s: PreparedStatement) =>` 注解 | bootstrap 固定点 PASS + d134_mysql 5/5 + d136_prepared_statement 1/1 不降 |

### Phase 间依赖

- Phase 0 → 1:D 文档落盘后用户审,Phase 1 下一轮起
- Phase 1 → 2:RED 成立才启 Phase 2 实施;funcParamTypes 时机不就位 → 调整 Phase 2 入口(改在 codegen 阶段反推 vs checker 阶段反推)
- Phase 2 → 3:bootstrap 固定点 PASS + spike GREEN 才启 Phase 3 测试覆盖
- Phase 3 → 4:测试覆盖完整(隐藏假设全 PASS)才启 Phase 4 workaround cleanup;若 Phase 3 发现边界场景失败,回 Phase 2 修

---

## 4. State(状态管理)

### 跨 Phase 状态依据

- **funcParamTypes 注册时机**:`gen_registry.ss:71-72` `funcParamCount = Map() + funcParamTypes = Map()` 在何时清空 / 何时注册满载 — Phase 1 必读 `gen_registry.ss` + `codegen.ss` `initFuncRetTypes` 时序
- **ARROW_FUNC 在 AST 哪个阶段才能识别 callee**:parser 阶段 ARROW_FUNC 是嵌套表达式(parseArrowFunc 在 parsePrimary 内被调),callee 信息要等 outer FUNC_CALL / METHOD_CALL 节点构造完才完整;checker 阶段 ARROW_FUNC 检查时 outer call 节点已就位
- **PARAM s2 回填位置**:`nSetS2(paramId, inferredType)` — 在 checker `check_exprs.ss` 处理 fn/method call 时,识别 args 中 ARROW_FUNC 节点 + 查 funcParamTypes + 回填 ARROW_FUNC PARAMs;**回填时机必须早于** `genArrowFunc()` 调用(否则 codegen line 135 仍读到空)

### 信息源 SSoT

- `funcParamTypes` `gen_registry.ss:10` — `"funcName:paramIndex" → SS type`,普通函数 / class method 重载均注册
- 反推查询模板:`funcParamTypes.get(\`${calleeName}:${argIndex}\`)` → 反推 lambda 第 argIndex 参数类型
- callee 名提取:fn 调用 = IDENT 名 / method 调用 = `${className}_${methodName}` mangled 名

---

## 5. Evaluation(评估)

### 单一判据(必须 GREEN)

```bash
# Phase 1 RED:untyped lambda + setter 走错路径
bin/ss run /tmp/spike_lambda_untyped.ss 2>&1 | grep "result = -1"
# 期望命中(根因未修)

# Phase 2 GREEN:untyped lambda + setter 走对路径
bin/ss run /tmp/spike_lambda_untyped.ss 2>&1 | grep "result = 1"
# 期望命中(根因修后)

# Phase 4 GREEN:lib/spring/data.ss + tests/d134_mysql 显式注解 cleanup
grep -c "(s: PreparedStatement)" lib/spring/data.ss tests/d134_mysql/integration_test.ss
# 期望 ≤ 总数 - 10(workaround 全删)
```

### Phase 2 关键验证

- bootstrap 三阶段固定点 PASS(stage2 == stage3 字节比较)
- d134_mysql 5/5 全绿(D137 业务路径不破)
- d136_prepared_statement 1/1 全绿(D136 driver 路径不破)
- tests/ 259/4/263 baseline 不降(全项目 lambda 测试 100+ 不破)
- reflection_health_linter GATE PASS no regressions(checker 改触碰反射可能性低,但仍验)

### Phase 3 测试覆盖(隐藏假设挑战)

- typed lambda 显式注解保留(`(s: PreparedStatement) => s.setInt(1, 1)`)— H8 显式优先级 > 推断
- untyped lambda 单参反推(`(s) => s.setInt(1, 1)`)— H1 反推单参 PASS
- untyped lambda 多参反推(`(s, ctx) => { s.setInt(1, ctx.id) }`)— H2 反推多参 PASS
- 嵌套 lambda(`(s) => () => s.setInt(...)`)— H3 嵌套 capture + 反推 PASS
- 推断失败 fallback(callee 不在 funcParamTypes / arity 不匹配)→ 编译期报错(non-silent miscompile)— H4 失败诊断 PASS
- interface upcast(`MysqlPreparedStatement` implements `PreparedStatement`,反推得 `PreparedStatement` 接口类型,vtable indirect dispatch 走 D025 路径)— H5 interface dispatch PASS

---

## 6. Constraints(约束)

### 硬约束

- **不引入 bidirectional type checking 全局**(候选 3 架构层 refactor 已废,scope 爆炸)
- **不动 D025 interface dispatch 契约**(setInt/setString/setLong 等接口方法签名)
- **不动 D137 lib/spring/jdbc.ss / lib/spring/data.ss 业务逻辑**(Phase 4 仅删显式注解,不动语义)
- **不引入 SS 泛型 / generic constraint**(F2 RowMapper 才需要,F9 不依赖)
- **bootstrap 改不许超过 800 LOC delta**(`feedback_600_split_not_inline.md` + `feedback_structure_not_linecount.md`)— 实际预估 ≤ 200 LOC(check_types.ss + check_exprs.ss 局部改)

### 软约束

- 推断失败时**优先编译期报错**而非 silent fallback 默认类型(避免再次产生 result=-1 类 silent miscompile)
- 显式注解仍优先级最高(Java 8+ override 推断风格,D137 既有 10 处 workaround 短期内仍 GREEN)
- 反推查 callee `funcParamTypes` 时,callee 必须已 register(`registerFuncs` / `registerClassMethods` 已跑)— Phase 1 文档化时序保证

---

## A.1 候选方案对比(§MNK §M §字段 10 内容)

| 候选 | 层次 | 描述 | 假设破裂入口 | 优势 | 劣势 | 决策 |
|---|---|---|---|---|---|---|
| **C1** | **数据层 patch** | 仅 `gen_arrows.ss:135` 改 fallback — 无类型注解时 fallback 默认类型 / 报错 | 破裂入口在 PARAM s2 留空 → ssTypeToLLVM("") 默认;C1 仅在该单点补 fallback,不消除根因 | LOC 极小 5-10 行;不动 checker | 零散 patch — method_call.ss / gen_methods.ss vtable dispatch 等多处都用 PARAM s2(后续若 lambda body 有 nested method call 仍走错);信息源不单点 | **不选** — 数据层不消除根因(`feedback_root_cause_no_cost.md` 红线)|
| **C2** | **接口层 trap** | checker 阶段 ARROW_FUNC 作 fn/method 实参时,查 callee `funcParamTypes` 反推回填 PARAM s2;`check_types.ss:51` ARROW_FUNC 改 `fn(P1,P2,...):R` 结构化签名 | **彻底消除** — PARAM s2 在 codegen 之前就被回填,gen_arrows.ss:135 直读 s2 路径不变,所有下游(method_call.ss / vtable dispatch / setVarType)信息源一致 | 单点信息源回填;TS contextual typing 主线;codegen 路径 100% 不变;workaround 10 处可全删 | LOC 中等 ~150-200(check_types.ss + check_exprs.ss + 局部 gen_calls.ss);需考虑嵌套 lambda / 多参 lambda / interface upcast 边界 | **选** — 接口层 trap 消除根因 + scope 可控 |
| **C3** | **架构层 refactor** | 全编译器 bidirectional type checking — checker 改成 expected/actual 双向类型检查,所有表达式从调用上下文反推类型(包括 lambda + array literal + object literal + ternary) | 消除根因 + 消除其他类似 silent miscompile(array literal 类型推断 / object literal 类型推断等) | 类型系统统一性最高;未来扩 SS 泛型 D026/D027 时直接复用 | scope 爆炸 LOC > 2000 + 多 sub-D + bootstrap 重写多个核心文件;F9 单 sub-D scope 远超(D141 不应承载架构层 refactor)| **不选** — scope 远超 D141 单 sub-D 范围;未来若启 D026/D027 generic 实施时再开 D 文档评估 |

**决策行**:**选 C2 接口层 trap** 因 (a) 单点信息源回填,消除 PARAM s2 缺失的假设破裂入口;(b) codegen 路径 100% 不变,gen_arrows.ss:135 直读 s2 仍 GREEN;(c) workaround 10 处可全删(Phase 4 cleanup 落锚);(d) scope 可控 ~200 LOC delta。**为何不选 C1**:数据层 zero-spread,不消除根因(`feedback_root_cause_no_cost.md` 红线 — 数据层 patch 多处零散补 fallback)。**为何不选 C3**:scope 爆炸 — bidirectional type checking 全局 refactor 远超 D141 单 sub-D scope,留作未来 D026/D027 generic 实施时再评估。

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套)

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | funcParamTypes 在 checker 阶段已 ready(parser → checker 前已 register) | 实施层失败 — checker 反推时 funcParamTypes 留空,反推查不到 callee 签名 | Phase 1 探查 `gen_registry.ss:71-72` + `codegen.ss initFuncRetTypes` 时序;Phase 2 startup 阶段 dump funcParamTypes 验证 | funcParamTypes 时机不就位 → 调整 Phase 2 入口(改 codegen 阶段 lazy 反推 vs checker 阶段反推)|
| H2 | ARROW_FUNC 多参反推不破嵌套作用域 | `(s, ctx) => { s.setInt(1, ctx.id) }` 多参反推时 ctx 类型也需正确 — 若 ctx 在 outer scope 是 class instance,反推查 callee:1 → ctx.id 调用走 vtable 路径正常 | Phase 3 测试 `tests/d141_lambda_inference/multi_param.ss`(多参 lambda + 多 setter call)| 多参反推失败 → fallback 退到单参反推 + 用户多参时仍需显式注解(Java 8 风格)|
| H3 | 嵌套 lambda 反推不破 capture 链 | `(s) => () => s.setInt(...)` 内层 lambda capture 外层 s — capture 类型已通过 `setVarType(capName, capType)` 设置(gen_arrows.ss:188),嵌套反推链路不破 | Phase 3 测试 `tests/d141_lambda_inference/nested.ss` | 嵌套反推失败 → 嵌套场景不反推 + 用户嵌套时仍显式注解 |
| H4 | 推断失败 fallback 编译期报错(非 silent fallback)| callee 不在 funcParamTypes / arity 不匹配 → 必须编译期 hard error,不许 fallback 默认类型(否则再次产生 result=-1 类 silent miscompile)| Phase 2 实施 `inferLambdaParamFromCallee` 失败时 emit checker error;Phase 3 测试 `tests/d141_lambda_inference/inference_fail.ss` 编译期报错 | 推断失败 silent fallback → 回 Phase 2 修硬错路径 |
| H5 | interface upcast 反推得接口类型,vtable indirect dispatch 走 D025 路径 | `MysqlPreparedStatement` implements `PreparedStatement`,callee 签名是 `(s: PreparedStatement) =>`,反推得 PreparedStatement 接口类型;lambda body `s.setInt(...)` 走 vtable indirect dispatch(`gen_methods.ss:209-230`)而非 static dispatch | Phase 3 测试 `tests/d141_lambda_inference/interface_dispatch.ss`(用 interface 类型 callee 签名 + 实际传 implementor 实例)| interface upcast 失败 → 回 Phase 2 修 vtable 路径 |
| H6 | 显式注解优先级 > 推断 | 用户写 `(s: PreparedStatement) =>` 时,PARAM s2 已有值,反推 skip(显式优先)| Phase 2 实施 `if (nGetS2(paramId) == "") { 反推回填 }`;Phase 3 测试 `tests/d141_lambda_inference/explicit_override.ss` 显式注解仍走原路径 | 显式优先级失败 → 回 Phase 2 修条件判断 |
| H7 | tests/ 259/4/263 baseline 不降 | 全项目现有 lambda 测试 100+ 都走显式注解 / 单语句 lambda — Phase 2 反推不影响显式路径(H6 显式优先);Phase 4 cleanup 仅 D137 10 处 | Phase 2 后跑 `bin/ss test tests/` 全跑 + baseline 比 | tests/ 红 → 回 Phase 2 修条件判断或 fallback 路径 |
| H8 | reflection_health_linter GATE 不破 | checker 改 `check_types.ss:51` ARROW_FUNC 返结构化 fn 签名 — 是否破反射路径 14 指标(M1-M7b + N1-N5)| Phase 2 后跑 `bin/ss run tools/reflection_health_linter.ss` GATE PASS | GATE BLOCK → 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段)|

---

## A.3 废案

- **C1 数据层 patch 全废**(零散 fallback,不消除根因)
- **C3 架构层 refactor 全废**(scope 爆炸,远超 D141 单 sub-D)
- **C4 编译期 lint 警告强制用户加注解**(被动 — 用户每写 lambda 必写注解,违反 CLAUDE.md §编译器吸收复杂度,反向退化到 Java 8+ 风格强制)
- **C5 全 lambda 默认类型 ptr / Object**(SS 无 Object 顶级类型,且 `interface PreparedStatement` 反推不出 setInt 子类型,vtable dispatch 走错)

---

## Phase 收关锚

### Phase 0: D 文档落盘 [✓ 进行中,本轮收尾]

- 本文档落盘 + Status / 核心目标 / 核心原则 / Context / Tools / Orchestration / State / Evaluation / Constraints / §A.1 候选方案对比 / §A.2 隐藏假设挑战 / §A.3 废案 / Phase 0-N 计划
- d_doc_index_linter F1 = 0 验证(D141 加入未破 referenced Ds)
- next_prompt_ultrathink_linter PASS 3/3
- VCM 六验(Plan 型):§① 跳过(diff=0 in bootstrap/lib/tools)+ §④ 替换为「替代方案对比 + 隐藏假设挑战」§A.1+§A.2 ✓

### Phase 1: RED 复现 + 信息源探查 [ ] Planned

- 写 `/tmp/spike_lambda_untyped.ss`(parsed from `/tmp/spike_lambda_typed.ss`,删除 `(s: PreparedStatement)` 注解仅留 `(s) =>`)
- 跑 `bin/ss run /tmp/spike_lambda_untyped.ss 2>&1 | grep "result = -1"` 期望命中(RED 成立)
- 探查 `gen_registry.ss:71-72` + `codegen.ss initFuncRetTypes` funcParamTypes register 时序
- 探查 `parse_exprs.ss:270` parseArrowFunc + `check_exprs.ss:169` ARROW_FUNC 实参识别先例
- 文档化 funcParamTypes ready 时机 + checker 反推入口选址

### Phase 2: checker 反推实施 [ ] Planned

- `bootstrap/checker/check_types.ss:51` ARROW_FUNC 改返 `fn(P1,P2,...):R` 结构化签名(向后兼容:`startsWith("fn")` 判断仍走原路径)
- `bootstrap/checker/check_exprs.ss` lambda 作 fn/method 实参时反推 PARAM s2 回填:
  ```
  for (argId in args) {
      if (nGetKind(argId) == "ARROW_FUNC") {
          for (paramId in nGetList(argId)) {
              if (nGetS2(paramId) == "") {  // H6 显式优先
                  const inferredType = funcParamTypes.get(`${calleeName}:${argIndex}`)
                  if (inferredType != "") {
                      nSetS2(paramId, inferredType)
                  } else {
                      checkerError(`cannot infer lambda param type for ${calleeName} arg ${argIndex}`)  // H4 hard error
                  }
              }
          }
      }
  }
  ```
- bootstrap 三阶段固定点 PASS + spike untyped → result=1(GREEN)
- d134_mysql 5/5 + d136_prepared_statement 1/1 baseline 不降

### Phase 3: 测试覆盖 + 隐藏假设挑战 [ ] Planned

- `tests/d141_lambda_inference/` 新增 6+ test case:
  - `typed_explicit.ss` — 显式注解仍走原路径(H6)
  - `untyped_single.ss` — 单参 lambda 反推(H1)
  - `untyped_multi.ss` — 多参 lambda 反推(H2)
  - `nested.ss` — 嵌套 lambda 反推 + capture(H3)
  - `inference_fail.ss` — 推断失败编译期硬错(H4 — 测试用 `// expect-error` 标记)
  - `interface_dispatch.ss` — interface upcast vtable indirect dispatch(H5)
- bootstrap + tests/ + d134_mysql + d136_prepared_statement 全绿
- reflection_health_linter GATE PASS no regressions

### Phase 4: workaround cleanup [ ] Planned

- grep `(s: PreparedStatement) =>` lib/spring/data.ss + tests/d134_mysql/integration_test.ss 共 10 处
- 删除显式类型注解(保留 lambda 体不变)
- bootstrap 三阶段固定点 + d134_mysql 5/5 + d136_prepared_statement 1/1 全绿
- 三轨 RED 全 GREEN:
  - `grep -c "(s: PreparedStatement)" lib/spring/data.ss tests/d134_mysql/integration_test.ss` = 0(workaround 全删)
  - `grep -c "(s) =>" lib/spring/data.ss tests/d134_mysql/integration_test.ss` ≥ 10(untyped lambda 接管)
  - `bin/ss test tests/d134_mysql tests/d136_prepared_statement` 全绿(根因修后业务路径仍 GREEN)

### Phase 5: 全 Phase 收关 [ ] Planned

- §全 Phase 收关锚 4 Phase commit hash 全列(Phase 0 / 1 / 2 / 3 / 4)
- 兑现成果总结(C2 接口层 trap 落地 + workaround 10 处全删 + 隐藏假设 H1-H8 全 PASS + bootstrap 隔离破例 D137 §核心原则 9 接受 + axiom 红线 grep / nm = 0 永久 + d_doc_index_linter F1 = 0 永久 + reflection_health_linter GATE PASS)
- §Followup 锚明确(预留 — 例:其他类似 silent miscompile 类型推断 bug / array literal / object literal contextual typing / 等)

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | array literal contextual typing | `[1, 2, 3]` 在 fn 实参 `Array<int>` 时反推元素类型 — 是否同模式复用 D141 反推机制 |
| F2 | object literal contextual typing | `{ name: "X" }` 在 fn 实参 `class User` 时反推字段类型 — 同模式复用 |
| F3 | ternary contextual typing | `cond ? a : b` 在 fn 实参 `Maybe<int>` 时反推分支类型 |
| F4 | interface method overload 反推 | `setInt(1, x)` 在 `PreparedStatement` interface 多 setInt 重载(setInt:i / setInt:l / setInt:d)时反推 x 类型 — 依赖 D026/D027 generic |
| F5 | bidirectional type checking 全局 | C3 候选废案,留作未来 SS 类型系统 v2 评估(D026/D027 落地后再开 D 文档)|
| F6 | F4 D138 编号冲突独立 | D 治理后续轮处理 D136 §R4 + §F1 双指 D138 冲突,与 D141 独立 |

---

## Status 时间线

- 2026-04-27 Phase 0 D 文档落盘(本轮)
- (Phase 1+ 进度在用户对话指示后下一轮起)
