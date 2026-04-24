# I018 — Spring dispatcher invoke sentinel runtime arg 通道 + Controller req map 参数绑定

**父决策:** D123 §3 Phase 3 Step 1 / I014 §路径 A 后续
**状态:** Done at `bootstrap/eval/method_call.ss:80-133 invoke sentinel runtime arg 通道扩展` + `bootstrap/gen/gen_registry.ss:36-58 registerClassMethodRetType 扩 funcParamCount pre-register` + `lib/http.ss:35-55 httpServe query parse 按 & 拆 key-value` + `lib/spring/boot/application.ss:85 r.invoke(req)` + `examples/spring-parity/hello/ss/HelloController.ss:12-17 hello(req: Map<string,string>)` + `tests/phase5/d123_phase3_param_bind.ss RED→GREEN` + `curl :8080/hello?name=SS → "Hello, SS!"`(2026-04-24)
**颗粒度:** 预估 ~40-80 LOC 标准改 / 实测 ~60 LOC(method_call.ss 26 行 invoke 分支扩 + gen_registry.ss 11 行 param count pre-register + http.ss 16 行 query parse + application.ss 注释同步 + HelloController body 1 行 + test 新建 28 行)
**依赖:** I014(已 Done, invoke sentinel 静态派发) / D123 Phase 2(已 Done, routes csv + dispatcher 真兑现) / D127(annotation ASSIGN) / D088 §反模式(禁 runtime 反射)
**创建:** 2026-04-24
**立项由:** D123 Phase 3 Step 1 实测发现 invoke sentinel 硬编 `(ptr null)` 单 this 参,runtime req map 无法透传到 Controller(curl `:8080/hello?name=SS` 返 `Hello, World!` 而非 `Hello, SS!`)
**收关:** 2026-04-24 本轮三判据 PASS
- (a) `bin/ss run tests/phase5/d123_phase3_param_bind.ss` → `Tests: 1 passed, 0 failed` ✅
- (b) `examples/spring-parity/hello/ss/main.ll:6433` call `@HelloController_hello(ptr null, ptr %7)` + `:6469` define `@HelloController_hello(ptr %this.ptr, ptr %req.arg)` arity 匹配 ✅
- (c) `/tmp/hello_ss --serve` + `curl "http://localhost:8080/hello?name=SS"` → body `Hello, SS!`;`?name=Alice` → `Hello, Alice!`;`?name=` / 无 query → `Hello, !`(空 value / 无 key 走 getString 默认空串,未炸)✅

(Java oracle parity mvn 路径推 Phase 5)

---

## 问题

I014 §路径 A 让 `r.invoke()` sentinel 能 emit `call @<cn>_<mn>(ptr null)` 静态 IR 完成 comptime (path, cn, mn) → runtime static call 的 symbolic gap 消除,但 **硬编单 this 参**阻止 Controller 接收 runtime req map → @PathVariable / @RequestParam 语义 byte-identical Java parity 不可能。

一句话:invoke sentinel 已接通"调",但 call site 缺 runtime arg 透传通道 → "绑参"未通。

缺口清单:
- `bootstrap/eval/method_call.ss:99/103` 硬编 `call @<cn>_<mn>(ptr null)` 与 class method 形参签名无对称(改前 method define 只接 `ptr %this.ptr` 单参,改后 define 可接 `ptr %this.ptr, ptr %req.arg` 但 call 仍单参 → link 失败或 null ptr crash)
- `funcParamCount` 仅注册 top-level func(`bootstrap/gen/codegen.ss:116`),class method 未入表,invoke sentinel 无法按 callee arity 动态追加 `, ptr <reg>` 后续参
- `lib/http.ss:37` 只把 query 存整串 `req["query"]`,未按 `&` 拆 `key=value` → Controller 用 `req.get("name")` 查不到

---

## 第一性需求

Spring Boot enterprise parity(含 URL query / path param 绑定)→ invoke sentinel call/define arity 对称 + callPreRegs runtime reg 透传 + httpServe 契约扩 → Controller 能真正接收 URL query param。Why 两层:

- **Why1**:不做 → Controller 永远 body-static,Java `@GetMapping("/hello")` 带 `@RequestParam String name` 的场景 SS 侧完全不可达
- **Why2**:→ D123 §3 Phase 3 真兑现不可能 → Spring Boot enterprise parity gate 永不启用 → D088 §第一性需求 在 enterprise 尺度断裂(只能"调"不能"绑参")

可观测否定证据:改前 `curl -s :8080/hello?name=SS` = `Hello, World!`,Java oracle 期望 `Hello, SS!`。

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | invoke sentinel 查 funcParamCount 动态追加 callPreRegs runtime regs(`callPreRegs[mcArgId]` 读侧);class method 在 pre-register 阶段(`gen/gen_registry.ss registerClassMethodRetType`)注册 param count,保证 dispatch 函数 emit 时可查;httpServe 扩 `&` / `=` split query | 最小扩展面 ~60 LOC,对称 codegen.ss:116 top-level func 注册;禁 runtime 反射 ✅ |
| **B** | invoke 固定 variadic 透传全部 args 不查 arity | call/define arity mismatch 链接失败,不 robust;无法区分 0 形参场景 ✗ |
| **C** | comptime emit IR 字符串拼接 runtime arg list | D088 §反模式,禁 ✗ |

---

## 单一判据(收关依据)

- `grep -c "call.*@HelloController_hello(ptr null, ptr " examples/spring-parity/hello/ss/main.ll` ≥ 1 ✅(6433 命中)
- `bin/ss run tests/phase5/d123_phase3_param_bind.ss` `Tests: 1 passed` ✅
- `/tmp/hello_ss --serve` + `curl "http://localhost:8080/hello?name=SS"` = `Hello, SS!` ✅
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS / M1-M7b/N1-N5 不升 ✅(见收尾 §反射 gate)
- `bin/ss run tools/d_doc_index_linter.ss` F1 no dead ref ✅(新注释 I014/I018 § 引用符号无死指针)

---

## 风险 / 表面解决 / 下轮升根路径

**Map<K,V>.get value 类型推断缺口** — `Map.get` fallback 返 i64(`gen_registry.ss:177 methodRetTypes.set("get", "i64")`),`Map<string,string>.get` 不按 generic value 类型返 string;Controller 被迫用 `getString` 而非 `get` **表面绕过**。

- 表面成本:HelloController.ss / test 写 `req.getString("name")`,与 Java `req.get("name")` 字面偏差
- **下轮升根**:立 **I019-typed-map-get-value-inference**(独立 issue) 扩 checker/gen `Map<K,V>.get` 驱动 value 类型返回 string / int / double 等,让用户写 `req.get("name")` 直接 pass

**多形参透传** — 本轮 invoke sentinel 支持 0 或 >=1 形参(按 funcParamCount consumed loop 截断),但仅 1 形参在 HelloController 场景端到端验证。>=2 形参未专项覆盖。

- 成本:保留扩展点(`consumed < expectedPC` loop 已 generalize),未额外测试
- 下轮升根:D123 Phase 3 Step 2(或并入) 增 >=2 形参 e2e case(如 `@GetMapping path = "/user/{id}" + @RequestParam age`)

---

## 触发场景

- D123 §3 Phase 3 Step 1 真兑现 first 启用
- Spring Boot @RequestParam enterprise 尺度 byte-identical parity 前置
- Phase 5 mvn Java oracle 对齐工具链搭起后,可执行 `diff <(curl -s :8080/hello?name=X) <(curl -s :8081/hello?name=X)`(Java 端 8081)
