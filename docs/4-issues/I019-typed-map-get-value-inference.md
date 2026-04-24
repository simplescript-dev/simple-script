# I019 — Typed Map<K,V>.get value 类型推断(v0: string value 驱动 ss_mapGetString 路由)

**父决策:** D123 §3 Phase 3 Step 1 / I018 §风险 §下轮升根路径
**状态:** Done at `bootstrap/gen/gen_types.ss:76-85 extractMapValueType helper + inferType METHOD_CALL Map.get string 分支` + `bootstrap/gen/gen_builtins.ss:216-280 genMapMethod +objType 参 → typed Map<K,string>.get 路由 ss_mapGetString` + `bootstrap/gen/methods/gen_methods.ss:567 caller 传 objType` + `examples/spring-parity/hello/ss/HelloController.ss:17 req.get("name") 撤回 getString` + `tests/phase5/d123_phase3_i019_typed_map_get.ss RED→GREEN` + `docs/3-decisions/D123-spring-boot-replication.md §扩容申报-I019` (2026-04-24)
**颗粒度:** 预估 ~60-80 LOC 大改 / 实测 ~47 LOC(gen_types.ss +17 / gen_builtins.ss +8 / gen_methods.ss +1 / HelloController.ss 净 +1 / test 新建 30 / D123 §扩容申报-I019 新段落 + I019.md 本文)
**依赖:** I018(已 Done, invoke sentinel + runtime arg + funcParamCount pre-register)/ D123 Phase 3 Step 1 parity gate
**创建:** 2026-04-24
**立项由:** I018 §风险 §下轮升根路径 显式 hard prereq —— "Map<K,V>.get value 类型推断缺口:Map.get fallback 返 i64(`gen_registry.ss:190 methodRetTypes.set("get", "i64")`),`Map<string,string>.get` 不按 generic value 类型返 string;Controller 被迫用 `getString` 而非 `get` 表面绕过"。本轮跨层授权按 MNK §字段 8 "issue §风险节 hard prereq 实测命中即视为跨层授权" 合规。
**收关:** 2026-04-24 本轮三判据 PASS
- (a) RED 最小隔离测试:`echo 'function main() { let m: Map<string, string> = new Map(); m.set("k","v"); println("got:" + m.get("k")) }' > /tmp/t_i019_red.ss && bin/ss run /tmp/t_i019_red.ss` → before: `got:5244697`(指针地址数字 i64 fallback)/ after: `got:v` ✅
- (b) `bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss` → `Tests: 3 passed, 0 failed`(typed get 返 string / miss 返空串 / Controller-style concat parity 对齐 Java)✅
- (c) `bin/ss run tests/phase5/d123_phase3_param_bind.ss`(I018 regression)→ `Tests: 1 passed` getString 入口仍 work backward compat ✅ + `bin/ss build examples/spring-parity/hello/ss/main.ss -o /tmp/hello_i019` 编译通过 + `grep -c "call ptr @ss_mapGetString" main.ll = 1` 路由生效 ✅
- (d) `bin/ss run tools/reflection_health_linter.ss` GATE PASS(F1 gen_types.ss 760→780 已 bump 申报到 D123 §扩容申报-I019,non-reflection scope M*/N* AUTO-DRIFT 软警告豁免)✅
- (e) `bin/ss run tools/d_doc_index_linter.ss` GATE OK(新 D123 §扩容申报-I019 引用 + 本 I019.md 对 D123 无死指针)✅

---

## 问题

I018 §路径 A 让 `r.invoke(req)` sentinel + runtime req map 透传到 Controller,parity gate 从 byte-static `Hello, World!` 进阶到 `Hello, SS!`。但 **`Map<string,string>.get` 返 i64 fallback** 让 Controller 必须用 `req.getString("name")` 代 `req.get("name")` 字面对齐 Java 惯用。

一句话:typed Map.get 静态类型推断缺 generic value 驱动,用户被迫记双轨制方法名 `get` / `getString`,违反 CLAUDE.md §编译器吸收复杂度"用户不应看到内部机制的语法暴露"。

缺口清单:
- `bootstrap/gen/gen_registry.ss:190` `methodRetTypes.set("get", "i64")` 是单方法名 fallback,不按 receiver 类型 generic value arg 动态推断
- `bootstrap/gen/gen_types.ss inferType METHOD_CALL` 分支对 `Channel<T>.receive` / `Thread<T>.join` / `Ref<T>.value` 已各有特化路径,`Map<K,V>.get` 无对应
- `bootstrap/gen/gen_builtins.ss genMapMethod` 对 `get` / `getString` 硬编两个运行时 entry,typed Map<K,string>.get 无自动路由到 ss_mapGetString 的 codegen 决策面

---

## 第一性需求

Spring Boot enterprise parity(含 @RequestParam 绑参语义)→ 类型系统 comptime 静态驱动 codegen 消除"双轨制方法名税"。Why 两层:

- **Why1**:不做 → SS 侧 Java parity 每新加一个 typed Map 消费者(Controller / middleware / stdlib)都要记"typed 用 getX 不用 get",编译器吸收复杂度原则被用户记忆负担击穿
- **Why2**:→ 当 Map value 类型扩展到 Map<K, MyClass> 或 Map<K, Array<int>> 等 runtime-dispatched 类型时无 getX 入口可加,泛型推断系统架构层不可用 → D088 §第一性需求"编译期展开消除运行时反射"在类型系统 runtime-dispatch 延伸含义上断裂

可观测否定证据:改前 `let m: Map<string, string> = new Map(); m.set("k","v"); println("got:" + m.get("k"))` 输出 `got:5244697`(指针地址 i64)而非 `got:v`。

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | inferType METHOD_CALL Map.get 按 receiver varType 尾部 extractMapValueType 驱动返回(v0 仅 string V)+ genMapMethod +objType 参路由 ss_mapGetString vs ss_mapGet | 最小扩展面,对称 Channel<T>.receive / Ref<T>.value / Thread<T>.join 已有特化;naive first-comma split 足够 v0(嵌套 generic K 非 Spring 典型);保留 i64 fallback backward compat ✅ |
| **B** | 新增 `ss_mapGetTyped(ptr, ptr, i32 type_tag)` 统一运行时 + ssTypeToLLVM 加 Map<K,V> 全类型 V cast | 运行时改 + 全类型表驱动,LOC 大,v0 用不到且与 D088 §反模式接触反射边界 ✗ |
| **C** | 加 getInt / getDouble / getClass 等更多 get 方法名 | 双轨制永久化,违反 CLAUDE.md §编译器吸收复杂度 ✗ |

---

## v0 scope 切分说明

**做**:Map<K,string>.get 路由 ss_mapGetString;其他 value 类型 V(int / double / class / 嵌套 generic)保留 i64 fallback(`methodRetTypes.set("get", "i64")` 不删)。

**留下轮**:Map<K,int>.get → int(需 `trunc i64 to i32` cast)/ Map<K,double>.get → double(需 `bitcast i64 to double`)/ Map<K,ClassName>.get → ClassName(需 `inttoptr i64 to ptr` + TypeInfo 头对齐检查)—— 各 value 类型的 i64→target cast lowering 是独立工程,每种需单独 runtime 契约 + codegen 路径,不与本轮"去双轨制方法名"耦合。立项 **I019-phase-2** 或等 Phase 4 @RequestParam 实务驱动触发(Java Spring 多数 @RequestParam 仍是 string,v0 解决 80% 用例)。

**不做**:
- 不改 `ss_mapGet` / `ss_mapGetString` 运行时实现(两者仅差 `inttoptr` + miss 默认值 `0` vs `@.rt.str.empty`)
- 不删 `methodRetTypes.set("get", "i64")` fallback(untyped `let m = new Map(); m.get("k")` 场景 backward compat 保留)
- 不扩 Set.values / Set.has / Array 其他泛型 API(scope 限定 Map.get)
- 不改 checker side 的 `check_types.ss` METHOD_CALL 分支(checker 对 req.get 返 "" 不触发 type mismatch error,gen side 单独修复足够;若未来 checker 层 typed 语义需要硬验证,再起 checker-side issue)

---

## 单一判据(收关依据)

- RED 最小隔离测试实测 before=`got:5244697` / after=`got:v` ✅
- `bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss` 3 PASS ✅
- `bin/ss run tests/phase5/d123_phase3_param_bind.ss`(I018 regression)1 PASS ✅
- `grep -c "call ptr @ss_mapGetString" examples/spring-parity/hello/ss/main.ll` = 1 ✅
- `grep -c "call i64 @ss_mapGet" examples/spring-parity/hello/ss/main.ll` = 1 ✅(既有 untyped Map 路径仍在, backward compat 保留)
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS(F1 bump 已登 D123 §扩容申报-I019 anchor)✅
- `bin/ss run tools/d_doc_index_linter.ss` GATE OK ✅

---

## 风险 / 表面 / 下轮升根

**本 issue 根解决**。消除 `get` vs `getString` 双入口,用户写 `get` compiler 按 declared Map<K,V> 静态推断 + codegen 路由。不变量锚:`bootstrap/gen/gen_types.ss inferType` Map<K,string>.get 分支 + `bootstrap/gen/gen_builtins.ss genMapMethod` objType 路由。

**v0 scope 限定**(非表面,是 scope 切分):Map<K,int/double/ClassName> 的 value 类型驱动留下轮或 Phase 4 实务触发 —— inferType 已能返正确 V 类型,codegen i64→非 string 类型 cast 是独立工作,不与本轮"去双轨制方法名"耦合。

**预估失准事件记录**(VCM §4 预估对照):第一版 `extractMapValueType` 用 bracket-depth 环处理嵌套 generic K,实测 +41 LOC 触 F1 REGRESSION(cur 798 vs bm 760);压榨至 naive first-comma split 版后降到 +17 LOC 仍超 bm 需 bump 到 780。**教训**:下轮 PSM §字段 6 步骤应前置"先尝试 naive、failing 再 complex",避免过度工程 300% 偏差。

---

## 触发场景

- I018 §风险 §下轮升根路径 hard prereq 兑现(跨层授权 anchor)
- D123 Phase 3 Step 1 真兑现后 Controller 字面对齐 Java `req.get("name")`
- Phase 4 @RequestParam / @PathVariable 扩参实施前,避免双轨制方法名税在 Controller 层 long-term 积累
- Phase 5 Java oracle + parity CI 端对端 diff 不因 `get` / `getString` 字面偏差误判 byte-identical parity 失败
