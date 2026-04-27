# D141: SS Lambda 参数类型推断 + Interface Dispatch 集成

**Status:** Phase 2 — codegen 阶段反推实施 + G1 路径(callee PARAM 结构化签名)(In Progress)
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
   | `bootstrap/parse/parser.ss` | 803-850 | `parseTypeAnn()` — 类型 annotation 解析入口,**Phase 2.0 扩**:IDENT "fn" + LPAREN → 解析 `fn(T1,T2):R` 结构化签名(H12)|
   | `lib/spring/jdbc.ss` | 32 + 51 + 73 + 90 + 110 | 5 处 `setter: fn` callee PARAM — Phase 2.3 升级目标 |
   | `lib/spring/data.ss` | 33 + 91 | 2 处 `setter: fn` callee PARAM — Phase 2.3 升级目标 |
   | `bootstrap/checker/check_types.ss` | 51 | `if (kind == "ARROW_FUNC") { return "fn" }` — **当前**单一类型,信息丢失 |
   | `bootstrap/checker/check_thread.ss` | 36 | `if (kind == "ARROW_FUNC") { return }` — thread closure check 跳过 ARROW_FUNC,**Phase 2 是否同模式扩到 PARAM 反推待评估** |
   | `bootstrap/checker/check_exprs.ss` | 169 | `if (tsFirstArgId > 0 && nGetKind(tsFirstArgId) == "ARROW_FUNC")` — 已有"fn 实参 + ARROW_FUNC 实参"识别先例,Phase 2 沿此模式扩到通用 fn/method 实参反推 |
   | `bootstrap/gen/gen_arrows.ss` | 105-140 | `genArrowFunc()` — line 135 `nGetS2(pId)` 直读 PARAM s2,无注解时 `ssTypeToLLVM("")` 走默认 i32(**破裂入口**)|
   | `bootstrap/gen/gen_arrows.ss` | 188 | `setVarType(capName, capType)` — capture 类型已设(对照 H10 PARAM 链路:`gen_decls.ss:26 emitParamAllocas` 已调 setVarType,无需另加)|
   | `bootstrap/gen/gen_decls.ss` | 11-26 | `emitParamAllocas(paramList, useVarAlias)` line 26 调 `setVarType(pName, pType)` — PARAM s2 一旦回填,setVarType 自然写入,lambda body method dispatch 链路自然走通(H10)|
   | `bootstrap/gen/gen_calls.ss` | 231 | `resolveCallArgs(callee, argList, typeCallee)` — fn 调用 args 解析入口,**Phase 2 反推主入口**(改 codegen 阶段反推,H1 实证 checker 阶段 funcParamTypes 用户函数为空)|
   | `bootstrap/gen/gen_registry.ss` | 9-10 + 56 + 71-72 | `funcParamTypes` Map "funcName:paramIndex" → SS type — **信息源 SSoT**;`initFuncRetTypes` line 72 清空 + builtin 满载(`main.ss:264 initFuncRegistry()` 启动调);class method 注册在 line 56-57(codegen 阶段 register class methods 时填)|
   | `bootstrap/gen/codegen.ss` | 110-112 + 252 + 326 | 普通函数 funcParamTypes 注册 line 110-112(`registerFuncDeclNode` 内,被 line 326 `registerAllDecls` 调);**`registerAllDecls` 在 codegen 阶段触发,在 `check(root)` 之后 — H1 时序破裂证据** |
   | `bootstrap/main.ss` | 264 + 593-597 | 启动 `initFuncRegistry()` 仅满载 builtin;`compile()` pipeline `parse → check(root) → generateToFile(root)` — **checker 阶段用户函数 funcParamTypes 为空**(H1 破裂铁证)|
   | `bootstrap/gen/methods/gen_methods.ss` | 209-230 | vtable indirect dispatch — PARAM s2 回填后,lambda body `s.setInt(...)` 走 vtable indirect 自然 GREEN |
   | `bootstrap/eval/method_call.ss` | 4-120 | `evalMethodCall()` 入口 — comptime + runtime method dispatch,Phase 2 是否需扩待评估 |
   | `lib/spring/data.ss` | (workaround 6 处)| D137 Phase 2 落锚 6 处 `(s: PreparedStatement) =>` 显式注解 — Phase 4 cleanup 删除目标 |
   | `tests/d134_mysql/integration_test.ss` | (workaround 4 处)| D137 Phase 3 落锚 4 处显式注解 — Phase 4 cleanup 删除目标 |
   | `/tmp/spike_lambda_typed.ss` | 全文 | spike 实证 typed PASS 路径 — IR `define i32 @__arrow_1(ptr %s.arg)` + body `call void @__iface_PreparedStatement_setInt(...)` ✅ vtable indirect |
   | `/tmp/spike_lambda_untyped.ss` | 全文 | **Phase 1 RED 铁证**(本轮新写)— IR `define i32 @__arrow_1(i32 %s.arg)` ⚠️ + body `; TODO: method call .setInt` 静默丢失;两 spike 仅在 lambda PARAM s2 注解差(H10 单点修复链验证)|

### 加载策略

- 总体 ~2800 行(parse_exprs 80 + check_types 50 + check_exprs 30 + gen_arrows 180 + gen_calls 50 + gen_registry 80 + gen_decls 30 + gen_methods 60 + codegen 50 + main 30 + method_call 120 + lib/spring/data 110 + tests 200 + spike 100)
- Phase 1 spike 复现先 + 时序探查(本 Phase 已确认 H1 破裂,Phase 2 入口挪 codegen 阶段),Phase 2 codegen 阶段反推实施后,Phase 3 测试覆盖,Phase 4 workaround cleanup
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
| `bin/ss build /tmp/spike_lambda_untyped.ss --emit-ir` | Phase 1 RED IR 复现(本轮已写)| Phase 1 + Phase 2 GREEN 验证 |
| `bin/ss run /tmp/spike_lambda_untyped.ss` | Phase 2 GREEN 实测(根因修后)| Phase 2 / Phase 4 实测 |
| `git log --oneline D137*` | D137 5 Phase commit hash 锚 | 沟通时引用 commit hash |

---

## 3. Orchestration(编排)

### 多 Phase 顺序

| Phase | 目标 | 关键产出 | 验证 |
|-------|------|----------|------|
| **Phase 0** | D 文档落盘(本 Phase)| `docs/3-decisions/D141-*.md` | d_doc_index_linter F1 = 0 + ultrathink_linter PASS |
| **Phase 1** | RED 复现 + 信息源探查 | `/tmp/spike_lambda_untyped.ss`(本轮已写)+ IR 层 RED 铁证(`define i32 @__arrow_1(i32 %s.arg)` + `; TODO: method call .setInt`)+ funcParamTypes 时序文档化(H1 破裂确认) | IR 对比 typed/untyped 双路径完成 + 时序探查 fact 入 §1 必读清单 + §A.2 H1 破裂确认 + 新假设 H9/H10 入 §A.2 |
| **Phase 2** | codegen 阶段反推实施(H1 破裂修正路径)| `bootstrap/checker/check_types.ss:51` ARROW_FUNC 改 `fn(P1,P2,...):R` 结构化签名(类型表达力前置)+ `bootstrap/gen/gen_calls.ss:231 resolveCallArgs` + `gen/methods/method_call.ss` 内 lambda 作 fn/method 实参时反推 PARAM s2 回填(funcParamTypes 在 codegen 阶段已满载)| bootstrap 固定点 PASS + spike untyped → IR `define i32 @__arrow_1(ptr %s.arg)` + body `call void @__iface_PreparedStatement_setInt(...)` GREEN |
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

### A.1.1 C2 实施路径对比(Phase 2 起首,2026-04-27 G 系列追加)

> Phase 2 起首查源:`lib/spring/(jdbc + data).ss` 7 处 callee PARAM 类型 annotation 写为 `setter: fn`(单一 "fn" 字符串,无具体形参签名)— C2 反推路径在此 callsite 取到 `inferredType="fn"`,无法提取 P1 类型,反推空转。下分三路径定 callee PARAM 类型表达力。

| 路径 | 描述 | 解决度 | LOC | 影响 | 决策 |
|------|------|--------|-----|------|------|
| **G1** | **callee PARAM 类型签名结构化** — `setter: fn` → `setter: fn(PreparedStatement):void`;parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析(`fn(T1,T2,...):R` 结构化字符串);funcParamTypes 存结构化签名;反推时 `extractFnParamType("fn(PreparedStatement):void", 0)` 提取 P1 = "PreparedStatement";**TS / Java 8+ contextual typing 主线** | 100% | parser+checker+codegen+lib(jdbc+data 7 处)≈400-500 | Phase 4 lambda 注解 cleanup 仍可推进(callee 签名结构化与 lambda 注解删除独立) | **选** |
| G2 | callsite 双向反推 — 从 lambda 实参类型反推 ARROW_FUNC PARAM(eg `f(psB)` 用 psB 类型反推 s 类型);不依赖 callee PARAM 类型签名结构化 | 70% | gen_calls.ss + gen_methods.ss ≈150 | 漏 fn binding 间接链(eg `const f = save; f(stmt)` 双重间接);不破 lib/spring/data.ss `setter: fn` 现状 | 不选 — 漏 fn binding 链 + 偏离 TS/Java 8+ 主线 |
| G3 | 接受 gap,Phase 2 仅做 (a) 预备 — check_types.ss:51 改 ARROW_FUNC 返结构化签名,(b)(c) 反推机制因 callee PARAM 仍为 "fn" 实际不生效;主线 D137 §F9 lambda cleanup 延期 | 0% | check_types.ss:51 单点 ≈10 | 主线 cleanup 延期;反推机制空转 | 不选 — 空转无意义,违反 `feedback_root_cause_no_cost.md` |

**G1 决策(2026-04-27 用户对话锁定)**:走 G1 — 根因 100% + TS / Java 8+ 主线匹配 + scope 可控。**为何不选 G2**:漏 fn binding 间接链;且偏离 TS / Java 8+ contextual typing 主线(TS `(s) => s.setInt(...)` 反推靠 callee 形参签名,不靠实参类型)。**为何不选 G3**:反推机制空转,违反 `feedback_root_cause_no_cost.md` 红线(根因解决度 0%)。

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套)

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | funcParamTypes 在 checker 阶段已 ready(parser → checker 前已 register) | 实施层失败 — checker 反推时 funcParamTypes 留空,反推查不到 callee 签名 | Phase 1 探查 `gen_registry.ss:71-72` + `codegen.ss initFuncRetTypes` 时序;Phase 2 startup 阶段 dump funcParamTypes 验证 | funcParamTypes 时机不就位 → 调整 Phase 2 入口(改 codegen 阶段 lazy 反推 vs checker 阶段反推)|
| H1 实证(Phase 1)| **❌ 已破裂** — `bootstrap/main.ss:580-597 compile()` pipeline:`parse → check(root) → generateToFile(root)`;`main.ss:264 initFuncRegistry()` 启动只满载 builtin(`println`/`parseInt` 等);用户函数 funcParamTypes 由 `codegen.ss:326 registerAllDecls(rootId)` 填,在 `check(root)` 之后;`gen_registry.ss:56-57` class method funcParamTypes 在 codegen 内 register class methods 阶段填 | Phase 2 入口必须挪到 codegen 阶段(`gen_calls.ss:231 resolveCallArgs` + `gen/methods/method_call.ss` 入口),checker 阶段反推路径废 | grep 实证:`bootstrap/main.ss:264` 调 initFuncRegistry / `codegen.ss:326` 调 registerAllDecls;`compile()` 顺序 line 593 parse + line 594 check + line 597 generateToFile | Phase 2 选 codegen 阶段反推(C2b 子路径)替代 checker 阶段反推(原 C2 主路径)— 信息源仍 funcParamTypes,scope 不变 |
| H2 | ARROW_FUNC 多参反推不破嵌套作用域 | `(s, ctx) => { s.setInt(1, ctx.id) }` 多参反推时 ctx 类型也需正确 — 若 ctx 在 outer scope 是 class instance,反推查 callee:1 → ctx.id 调用走 vtable 路径正常 | Phase 3 测试 `tests/d141_lambda_inference/multi_param.ss`(多参 lambda + 多 setter call)| 多参反推失败 → fallback 退到单参反推 + 用户多参时仍需显式注解(Java 8 风格)|
| H3 | 嵌套 lambda 反推不破 capture 链 | `(s) => () => s.setInt(...)` 内层 lambda capture 外层 s — capture 类型已通过 `setVarType(capName, capType)` 设置(gen_arrows.ss:188),嵌套反推链路不破 | Phase 3 测试 `tests/d141_lambda_inference/nested.ss` | 嵌套反推失败 → 嵌套场景不反推 + 用户嵌套时仍显式注解 |
| H4 | 推断失败 fallback 编译期报错(非 silent fallback)| callee 不在 funcParamTypes / arity 不匹配 → 必须编译期 hard error,不许 fallback 默认类型(否则再次产生 result=-1 类 silent miscompile)| Phase 2 实施 `inferLambdaParamFromCallee` 失败时 emit checker error;Phase 3 测试 `tests/d141_lambda_inference/inference_fail.ss` 编译期报错 | 推断失败 silent fallback → 回 Phase 2 修硬错路径 |
| H5 | interface upcast 反推得接口类型,vtable indirect dispatch 走 D025 路径 | `MysqlPreparedStatement` implements `PreparedStatement`,callee 签名是 `(s: PreparedStatement) =>`,反推得 PreparedStatement 接口类型;lambda body `s.setInt(...)` 走 vtable indirect dispatch(`gen_methods.ss:209-230`)而非 static dispatch | Phase 3 测试 `tests/d141_lambda_inference/interface_dispatch.ss`(用 interface 类型 callee 签名 + 实际传 implementor 实例)| interface upcast 失败 → 回 Phase 2 修 vtable 路径 |
| H6 | 显式注解优先级 > 推断 | 用户写 `(s: PreparedStatement) =>` 时,PARAM s2 已有值,反推 skip(显式优先)| Phase 2 实施 `if (nGetS2(paramId) == "") { 反推回填 }`;Phase 3 测试 `tests/d141_lambda_inference/explicit_override.ss` 显式注解仍走原路径 | 显式优先级失败 → 回 Phase 2 修条件判断 |
| H7 | tests/ 259/4/263 baseline 不降 | 全项目现有 lambda 测试 100+ 都走显式注解 / 单语句 lambda — Phase 2 反推不影响显式路径(H6 显式优先);Phase 4 cleanup 仅 D137 10 处 | Phase 2 后跑 `bin/ss test tests/` 全跑 + baseline 比 | tests/ 红 → 回 Phase 2 修条件判断或 fallback 路径 |
| H8 | reflection_health_linter GATE 不破 | checker 改 `check_types.ss:51` ARROW_FUNC 返结构化 fn 签名 — 是否破反射路径 14 指标(M1-M7b + N1-N5)| Phase 2 后跑 `bin/ss run tools/reflection_health_linter.ss` GATE PASS | GATE BLOCK → 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段)|
| H9(Phase 1 新增)| var binding 调用 vs method/fn 直接 callee 反推路径差异 | `/tmp/spike_lambda_typed.ss` Test 2 用 `const f = (s) => ...; f(psB)` — callee `f` 是 var binding 不是 function decl,IDENT lookup 不到 funcParamTypes;主线 D137 §F9 场景是 method call `tmpl.update(sql, callback)` — callee 是 mangled method 名(`Template_update`)在 funcParamTypes | Phase 1 实测 untyped spike — IR `define i32 @__arrow_1(i32 %s.arg)` ⚠️ + body 内 `; TODO: method call .setInt` 静默丢失;**var binding 反推走 RHS 推断**(`const f = (s) => ...` 时 RHS ARROW_FUNC s2="" 无法反推),**方法/函数调用反推走 callee:argIdx**;Phase 2 必须区分两条路径 | var binding 不支持反推 → 用户 var binding 时仍需显式注解(Java 8 风格 fallback 保留),不影响 D137 §F9 主线 cleanup;Phase 3 补 method call 形式 spike 验证主线场景 |
| H10(Phase 1 新增)| lambda body 内 method dispatch 链路自然走通 | `gen_decls.ss:26 emitParamAllocas` 已调 `setVarType(pName, pType)`,但 PARAM s2="" 时 setVarType(s, "") → getVarType(s) 拿不到类型 → resolveObjClass("") 失败 → method call emit `; TODO: method call .setInt` 静默丢失 | **核心修复链**:PARAM s2 一旦回填,setVarType(s, "PreparedStatement") 自然写入 → lambda body 内 `s.setInt(...)` 走 method dispatch 时 getVarType(s) = "PreparedStatement" → resolveObjClass 解析成功 → vtable indirect 路径 GREEN;**不需另外加 setVarType 调用**,emitParamAllocas:26 已存在 | Phase 1 实测对比:typed `define i32 @__arrow_1(ptr %s.arg)` + body `call void @__iface_PreparedStatement_setInt(...)` ✅;untyped `define i32 @__arrow_1(i32 %s.arg)` + `; TODO: method call .setInt` ⚠️ — 两路径差仅在 PARAM s2 回填,验证修复链单点 | 修复链断 → 回 Phase 2 检查 setVarType pType 传值是否被 ssTypeToLLVM 提前消费 |
| H11(Phase 2 新增)| callee PARAM 类型签名必须结构化才能反推 | `lib/spring/(jdbc + data).ss` 现状 7 处 `setter: fn`,funcParamTypes 存 "fn" 单一字符串无形参签名信息;反推空转 | **G1 路径**:升级 7 处 `setter: fn` → `setter: fn(PreparedStatement):void` 结构化签名;parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析(IDENT "fn" + LPAREN);funcParamTypes 存结构化字符串(无 schema 改,gen_registry.ss:56-57 仍 nGetS2 字面值);反推 helper `extractFnParamType("fn(PreparedStatement):void", 0)` 解析返 "PreparedStatement" | Phase 2.0 实测 parser 解析 `fn(T):R` 字符串 + Phase 2.3 lib/spring/(jdbc+data) 升级后 funcParamTypes 实测含结构化 + Phase 2.2 反推实测 nSetS2 回填 PreparedStatement | callee PARAM 升级后反推不通 → 检查 funcParamTypes 注册路径(普通函数 codegen.ss:110 / class method gen_registry.ss:56)是否完整存结构化 + extractFnParamType 解析逻辑 |
| H12(Phase 2 新增)| parser fn 类型 annotation 扩不破现有类型解析 | parser.ss:803 parseTypeAnn IDENT 分支扩 `name=="fn"` + LPAREN → 解析 fn(T1,T2):R;不影响 IDENT 名 != "fn" 路径;不影响 generic `Name<T>` 路径;不影响 nullable `T?` 路径 | parseTypeAnn 单点扩 + bootstrap 三阶段固定点 PASS + tests/ baseline 不降 | parser 扩破现有解析 → 撤回扩 → 改用 `Function<T,R>` / `Consumer<T>` Java 8 风格 generic 类型 + ifaceMethodsCG 注册 |
| H13(Phase 2 新增)| 反推失败硬错粒度 — 结构化 callee 硬错 / 非结构化 callee skip | **结构化 callee**(funcParamTypes 含 `fn(...):R`):extractFnParamType 取不到 → `codegenError` 硬错(用户应改 callee 签名 / 加 lambda 显式注解);**非结构化 callee**(funcParamTypes 仍是 "fn"):反推 skip(不破现有 `setter: fn` + typed lambda 显式注解路径)| Phase 2.2 实测 lib/spring/jdbc.ss 升级前(setter: fn)反推 skip / 升级后(setter: fn(PreparedStatement):void)反推回填;Phase 4 cleanup 删 typed 注解后,untyped lambda 走结构化反推 | 硬错粒度过严 → tests/ break → 调整粒度为 silent skip + warn |

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

### Phase 1: RED 复现 + 信息源探查 [✓ 完结] commit `bb96e27`

**已完成:**

- 写 `/tmp/spike_lambda_untyped.ss`(基于 typed spike 删 lambda Test 2 `(s: PreparedStatement)` 注解仅留 `(s) =>`)
- 跑 `bin/ss build /tmp/spike_lambda_untyped.ss --emit-ir` IR 层验证(无 mysql 依赖)— **RED 铁证**:
  - typed:`define i32 @__arrow_1(ptr %s.arg)` + body `call void @__iface_PreparedStatement_setInt(ptr %1, i32 1, i32 2)` ✅ vtable indirect dispatch
  - untyped:`define i32 @__arrow_1(i32 %s.arg)` ⚠️ + body `; TODO: method call .setInt` ⚠️ 静默丢失,完全无 dispatch emit
- 探查 funcParamTypes 时序 — **H1 假设破裂确认**:
  - `bootstrap/main.ss:264 initFuncRegistry()` 启动调,只满载 builtin(`println`/`parseInt` 等)
  - `bootstrap/main.ss:593-597 compile()` pipeline:`parse(tokens)` → `check(root)` → `generateToFile(root, llFile)`
  - `bootstrap/gen/codegen.ss:326 registerAllDecls(rootId)` 用户函数填 funcParamTypes(`codegen.ss:110-112`)— 在 `check(root)` 之后
  - `bootstrap/gen/gen_registry.ss:56-57` class method funcParamTypes 在 codegen 内 register class methods 阶段填
  - **结论**:checker 阶段查 funcParamTypes 用户函数为空 → 原 C2 主路径"checker 阶段反推"破裂 → Phase 2 入口必须挪到 codegen 阶段(`gen_calls.ss:231 resolveCallArgs` + `gen/methods/method_call.ss`)
- 探查 `gen_decls.ss:11-26 emitParamAllocas` line 26 已调 `setVarType(pName, pType)` — **H10 验证**:PARAM s2 一旦回填,setVarType 自然写入 → lambda body 内 `s.setInt(...)` 走 method dispatch 时 getVarType(s) lookup 成功 → vtable indirect 路径自然 GREEN(不需另外加 setVarType 调用)
- 探查 `parse_exprs.ss:270` parseArrowFunc 节点结构 + `check_exprs.ss:169` ARROW_FUNC 实参识别先例(Thread.start closure)— Phase 2 沿此模式扩到通用 fn/method 实参反推(但路径挪到 codegen 阶段)
- §A.2 H1 实证记录 + 新假设 H9(var binding vs method/fn 直接 callee 反推路径差异)+ H10(lambda body method dispatch 链路自然走通)入档
- §1 必读清单关键代码位置补全:`gen_decls.ss:11-26` + `codegen.ss:110-112+252+326` + `main.ss:264+593-597` + `/tmp/spike_lambda_untyped.ss`

**Phase 1 兑现成果:**

- (a) RED 铁证 IR 对比 typed/untyped 两路径完成,**根因路径单点定位**:PARAM s2 留空 → ssTypeToLLVM("") → i32 + setVarType("") → method dispatch 失败 emit `; TODO`
- (b) H1 假设破裂确认 → Phase 2 入口选址调整为 codegen 阶段反推(C2b 子路径,scope 不变)
- (c) H9/H10 新假设入档 → Phase 2 实施需区分 var binding vs method call 反推路径 + Phase 3 补 method call 形式 spike
- (d) H10 验证修复链单点 → setVarType 链路自然走通,PARAM s2 回填即修复

### Phase 2: codegen 阶段反推实施 + G1 路径(H1 破裂修正 + H11 callee 结构化前置)[ ] In Progress

> Phase 1 探查确认 H1 破裂 — checker 阶段 funcParamTypes 用户函数为空。Phase 2 入口从 checker 挪到 codegen,信息源仍 funcParamTypes;Phase 2 起首查源确认 `lib/spring/(jdbc+data).ss` 7 处 callee PARAM 类型 annotation 写 `setter: fn`(单一字符串无形参信息),反推空转 — 走 G1 路径(callee 类型签名结构化前置)。

**Phase 2.0** — parser 扩 fn 类型 annotation 解析:
- `bootstrap/parse/parser.ss:803 parseTypeAnn` IDENT 分支扩 `name=="fn"` + LPAREN → 解析 `fn(T1,T2,...):R` 结构化签名,返回字符串 `fn(${params}):${retT}`
- 兼容现有 `setter: fn`(无 LPAREN 跟随仍返 "fn",H12 不破)

**Phase 2.1** — `bootstrap/checker/check_types.ss:51` ARROW_FUNC inferType 返结构化签名:
- 计算 PARAM s2 + retType,返 `fn(${P1Type},${P2Type},...):${RetType}`(向后兼容:全 PARAM s2="" 降级 "fn",isTypeCompatible startsWith("fn") 判断仍走原路径)

**Phase 2.2** — codegen 阶段反推回填(主路径):
- `bootstrap/gen/gen_calls.ss:231 resolveCallArgs` + `bootstrap/gen/methods/gen_methods.ss:170 emitClassMethodCall` + `gen_methods.ss:691 genInterfaceMethodCall` 内识别 ARROW_FUNC 实参 + 查 funcParamTypes 反推 PARAM s2 回填:
  ```
  // 反推 helper:从 fn(T1,T2):R 提取 Ti
  function extractFnParamType(fnSig: string, idx: int): string { ... }

  // 在 args 循环内
  for (argId in args) {
      if (nGetKind(argId) == "ARROW_FUNC") {
          const ptKey = `${typeCallee}:${argIndex}`
          if (funcParamTypes.has(ptKey) == 1) {
              const calleeParamType = funcParamTypes.getString(ptKey)  // eg "fn(PreparedStatement):void"
              if (calleeParamType.startsWith("fn(") == 1) {  // 结构化签名才反推
                  const arrowParams = nGetList(argId).split(",")
                  let pi = 0
                  for (paramId in arrowParams) {
                      if (nGetS2(paramId) == "") {  // H6 显式优先
                          const inferredType = extractFnParamType(calleeParamType, pi)
                          if (inferredType != "") {
                              nSetS2(paramId, inferredType)  // PARAM s2 回填,gen_arrows.ss:135 直读 ptr,emitParamAllocas:26 setVarType 自然走通(H10)
                          } else {
                              codegenError(...)  // H13 结构化 callee 硬错
                          }
                      }
                      pi = pi + 1
                  }
              }
              // 非结构化(calleeParamType=="fn"):反推 skip(H13 不破现有 setter: fn 路径)
          }
      }
  }
  ```

**Phase 2.3** — `lib/spring/(jdbc + data).ss` 升级 callee PARAM 类型签名:
- jdbc.ss 5 处 + data.ss 2 处 `setter: fn` → `setter: fn(PreparedStatement):void`(setter 调用方式 `setter(stmt)` 不取返回值,确认返回类型 void)

**Phase 2.4** — 验证:
- bootstrap 三阶段固定点 PASS
- d134_mysql 5/5 + d136_prepared_statement 1/1 baseline 不降(D137 §F9 既有 10+ 处显式 lambda 注解走 H6 显式优先路径,反推 skip)
- tests/ 259/4/263 baseline 不降
- reflection_health_linter GATE PASS no regressions

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

## 扩容申报-Phase2-G1

> Phase 2 G1 路径实施触发 4 处 F1 budget_max 越界,均为非反射路径(M/N 均 OK + DRIFT,无 BLOCK)。新加 helper / 反推机制 / parser 扩 fn 类型 annotation 自然增量,跑 `bin/ss run tools/reflection_health_linter.ss` GATE BLOCKED 4 file。按 `docs/3-MNK.md §特定领域 §反射路径根因 gate B 路径` 走扩容申报。

| 文件 | budget_max(旧)| cur(新)| delta | 增量内容 |
|------|----------------|---------|-------|----------|
| `bootstrap/parse/parser.ss` | 850 | 870 | +20 | Phase 2.0 parseTypeAnn 扩 `fn(T1,T2,...):R` 结构化函数类型 annotation 解析(IDENT "fn" + LPAREN 分支 ~17 行)|
| `bootstrap/gen/methods/gen_methods.ss` | 716 | 722 | +6 | Phase 2.2 emitClassMethodCall 提前 resolve mangled name + args 循环 inferArrowFuncParams 反推 ~6 行 |
| `bootstrap/gen/gen_calls.ss` | 695 | 699 | +4 | Phase 2.2 resolveCallArgs 内 inferArrowFuncParams 反推 ~4 行 |
| `bootstrap/gen/gen_types.ss` | 792 | 847 | +55 | Phase 2.2 新加 helper:`isFnType`(8 行)+ `extractFnParamType`(15 行)+ `inferArrowFuncParams`(22 行)+ ARROW_FUNC inferType 结构化 codegen 层未改(留后续按需扩)|

申报理由:G1 路径根因 100%(callee PARAM 结构化签名前置),反推机制单点回填,信息源一致;非反射路径触碰(M/N 全 OK / DRIFT 软警告);F1 增量纯结构化新功能码,无样板压注释/合并空行/字符级绕过。`feedback_600_split_not_inline.md` + `feedback_structure_not_linecount.md` 拆分判据是结构清晰(职责单一 / 依赖单向),gen_types.ss 已是类型工具集中处,fn 类型 helper 入此族符合结构归类;后续若 gen_types.ss 拆分按职能(类型推断 / 类型签名 / fn helper / 类型工具)再切。

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

- 2026-04-27 Phase 0 D 文档落盘(commit `b1becb0`)
- 2026-04-27 Phase 1 RED 复现 + 信息源探查(commit `bb96e27`)— `/tmp/spike_lambda_untyped.ss` 落锚 + IR 层 RED 铁证(`define i32 @__arrow_1(i32 %s.arg)` + `; TODO: method call .setInt`)+ H1 假设破裂确认(checker 阶段 funcParamTypes 用户函数为空)+ 新假设 H9/H10 入档 + Phase 2 入口挪到 codegen 阶段反推
- 2026-04-27 Phase 2 起首 — G1 路径决策锁定(用户对话锁定)— Phase 2 起首查源 `lib/spring/(jdbc+data).ss` 7 处 `setter: fn` 非结构化签名 → 反推空转;§A.1.1 G1/G2/G3 候选对比,选 G1 callee PARAM 结构化签名前置;新假设 H11(结构化必要)/ H12(parser 扩不破)/ H13(反推失败硬错粒度)入档;§Phase 2 拆 2.0/2.1/2.2/2.3/2.4 子步骤;§1 必读清单补 parser.ss:803 + lib/spring/jdbc.ss + lib/spring/data.ss
