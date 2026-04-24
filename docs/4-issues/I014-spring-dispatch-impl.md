# I014 — Spring dispatcher: comptime ctMethodMeta → static method call IR emit

**父决策:** D123 §3 Phase 2 / D120 §决策 1 § A.4 #3 后续
**状态:** Done at `bootstrap/eval/method_call.ss:86-108 invoke sentinel static dispatch` + `bootstrap/gen/stmts/stmts_loop_forin.ss:91-116 ctArray<object> unroll item-class-type sync` + `bootstrap/gen/gen_types.ss:412-417 inferType "invoke" → string` + `lib/spring/boot/application.ss:81-89 dispatch binder` + `examples/spring-parity/hello/ss/ curl :8080/hello = 200 "Hello, World!"`(2026-04-24,commit 2f3a895 invoke sentinel + df2b39a 顶级 const 抽出)
**颗粒度:** 预估 ~5-10 万 token / 实测 ~3 万 token(路径 A 最小扩展面:method_call.ss 22 行 invoke 分支 + stmts_loop_forin.ss 12 行 item class type 同步 + gen_types.ss 6 行 inferType 分支 + application.ss dispatch 8 行)
**依赖:** D120 reflect.classes()(已 Done)/ I003 + I004 + I005 typed accessor(已 Done)
**创建:** 2026-04-24
**立项由:** D123 Phase 2 Step 1 实测发现根因路径需新决策
**收关:** 2026-04-24 本轮实测 `/tmp/hello_ss --serve` + `curl -s :8080/hello` → `HTTP/1.1 200 OK` + `Content-Type: text/plain` + body `Hello, World!` + `Content-Length: 13`,三判据 PASS(parity mvn 路径推 Phase 5)

---

## 问题

D123 §3 Phase 2 routes csv 已通过 4 层嵌套 comptime 收集到位 — `lib/spring/boot/application.ss:18-58` 输出 `/hello|HelloController.hello;`。但 `dispatchPending` 只能返 503 stub,**真 dispatcher** 卡在 SS 当前不支持的能力上:

**一句话**:comptime 已能拿到 `(path, className, methodName)` 三元组(string),但 runtime 无法把这三个字符串转成具体 method 调用。

```
comptime ctMethodMeta + ctClassMeta → IR-level static method call (@HelloController_hello)
```

当前缺口:
- `c.<dynamicMethodName>()` 不是 SS 支持的语法(c 是 ClassMeta,不是 instance;methodName 是 string 不是 method ref)
- D088 §反模式禁 runtime 反射 / @comptimeEmit 字符串拼接 / @derive 替代 dispatcher

---

## 第一性需求

D088 §第一性需求 在 enterprise 框架尺度兑现 = D123 §第一性需求(Spring Boot byte-identical parity)。Phase 2 routes csv 收集证明 D120 + D127 + I003 已让"对象遍历字段 + 编译期展开"在反射读侧端到端可工作;**但 dispatcher 接入侧**还差最后一跳 — 让编译器把 ctMethodMeta + ctClassMeta 直接 emit 成静态 method call IR(`call ptr @HelloController_hello(...)`)。

不做 → D123 §3 Phase 2 真兑现不可能 → byte-identical parity gate 永不能首次启用 → D088 §第一性需求 在 enterprise 尺度断裂(只完成"扫"不完成"调")。

---

## 候选路径(选型留 Plan 轮)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | 扩 stmts_loop_forin.ss ct-array unroll body 内识别 `ctVar.<methodNameStr>()` MEMBER_ACCESS+METHOD_CALL,emit `call @<className>_<methodName>` static IR | 与 D120 §A.4 #3 同构(ctProbe 入口扩展),~30-50 LOC,不引新 AST kind |
| **B** | 新 ct callable handle 类型(`ctMethodHandle`),`m.invoke(args)` 在 comptime unroll body 内 emit static call | 引新 ct value type,与现有 5 类 Meta 体系叠加,影响面大 |
| **C** | reflect.invoke(cls, methodName, args) runtime API + per-class dispatch table 编译期生成 | **反模式** — runtime 反射 + dispatch table 生成接近 @comptimeEmit |

预选 A(最小扩展面)。

---

## 单一判据

- `bin/ss build examples/spring-parity/hello/ss/main.ss --emit-ir | grep -c "call.*@HelloController_hello"` ≥ 1(dispatcher unroll 后含 inline static call)✅ 实测 2026-04-24
- `/tmp/hello_ss --serve & curl http://localhost:8080/hello` body == `"Hello, World!"`(SS 端真 dispatch)✅ 实测 2026-04-24 `HTTP/1.1 200 OK` + body byte-match
- `cd examples/spring-parity/hello/java && mvn spring-boot:run` 端口 8081 启动后,`diff <(curl -s :8080/hello) <(curl -s :8081/hello)` = 空 ⏸ Deferred to Phase 5(mvn 工具链未装,Java 端 oracle 搭起配套)
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS,M1-M7b/N1-N5 不升 ✅ 实测 2026-04-24 本轮 diff 仅触 lib/spring/boot/application.ss + examples/,反射路径未触

---

## 触发场景

D123 §3 Phase 2 真兑现 / D123 §C.1 层 D + 层 E 真 Done / parity gate 首次启用。

