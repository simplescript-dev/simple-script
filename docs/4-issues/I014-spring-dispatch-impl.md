# I014 — Spring dispatcher: comptime ctMethodMeta → static method call IR emit

**父决策:** D123 §3 Phase 2 / D120 §决策 1 § A.4 #3 后续
**状态:** Draft
**颗粒度:** ~5-10 万 token(预计需要扩 bootstrap/gen/exprs/exprs_ct_reflect.ss + bootstrap/gen/stmts/stmts_loop_forin.ss + 可能新 ctMethodMeta callable handle 类型)
**依赖:** D120 reflect.classes()(已 Done)/ I003 + I004 + I005 typed accessor(已 Done)
**创建:** 2026-04-24
**立项由:** D123 Phase 2 Step 1 实测发现根因路径需新决策

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

- `bin/ss build examples/spring-parity/hello/ss/main.ss --emit-ir | grep -c "call.*@HelloController_hello"` ≥ 1(dispatcher unroll 后含 inline static call)
- `/tmp/hello_ss --serve & curl http://localhost:8080/hello` body == `"Hello, World!"`(SS 端真 dispatch)
- `cd examples/spring-parity/hello/java && mvn spring-boot:run` 端口 8081 启动后,`diff <(curl -s :8080/hello) <(curl -s :8081/hello)` = 空
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS,M1-M7b/N1-N5 不升

---

## 触发场景

D123 §3 Phase 2 真兑现 / D123 §C.1 层 D + 层 E 真 Done / parity gate 首次启用。

