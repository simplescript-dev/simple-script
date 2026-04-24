# I015 — Spring Boot routes 顶级 const 提取(comptime Array<RouteMeta> DRY)

**父决策:** D123 §3 Phase 3(或独立 D128 决策)
**状态:** Draft
**颗粒度:** 预估 ~20-50 LOC(取决于 SS 顶级 const Array<UserClass> comptime 绑定支持验证)
**依赖:** I014 §路径 A(已 Done,本轮引入 comptime Array<RouteMeta> ct-array unroll 路径)
**创建:** 2026-04-24
**立项由:** I014 §路径 A simplify reuse 发现 comptime block 重复(SpringApplication.run + dispatch 各跑一次 routes 收集)

---

## 问题

`lib/spring/boot/application.ss` 当前 I014 §路径 A 落地后:
- `SpringApplication.run` 里 `const routes = comptime { ... return Array<RouteMeta> }` 构造一次(打印 Routes csv 摘要)
- `dispatch(req)` 里 `const routes = comptime { ... return Array<RouteMeta> }` 再构造一次(for-in unroll dispatch)

**两份 comptime block 完全相同**。虽编译期开销 O(N) interpClasses 扫两遍(可接受),但:
- **读者认知负担**:相同逻辑重复 = 易漂移(一侧改一侧忘)
- **DRY 违反** feedback_human_readable_code(b)"去冗余 let"rubric
- **未来扩展压力**:@PostMapping / @RequestMapping 加入后,每新增 dispatcher 方法就要再 copy 一次块

## 第一性需求

D088 §第一性需求 enterprise 尺度兑现路径上**不允许**"comptime 逻辑块跨函数 copy-paste"这种 maintenance 债累积。

**触发条件**:Phase 3 接入 DispatcherServlet / 参数绑定 / @RequestBody 时,dispatch 方法体会进一步扩膨;若 comptime routes block 重复再 embed 多份 copy,代码 review 与 refactor 成本翻倍。

## 候选路径

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | 顶级 `const _ssRoutes = comptime { ... return Array<RouteMeta> }` 全局绑定 → `SpringApplication.run` + `dispatch` 都引用 `_ssRoutes` | SS 顶级 const<Array<UserClass>> 的 comptime 绑定需验证支持(gen_decls.ss 已扩 COMPTIME_EXPR array/object/map CONST ctVars 路径,顶级 context 尚未实测) |
| **B** | 抽 `function _ssCollectRoutes(): Array<RouteMeta> { return comptime { ... } }` helper,两处调用 `_ssCollectRoutes()` | comptime block 在 function body 每次调用重跑一遍(非缓存),Benefit 仅 DRY 不 save 编译期开销 |
| **C** | 编译器内置 annotation handler 自动生成 dispatch(e.g. @RestController 触发 auto-gen)| **反模式**(D095 @methodOf handler 机制虽存在,但"生成顶层 dispatcher function"违反 P10 最小 API 扩展;且 handler 不是用户代码可见形态) |

**预选路径 A**(最干净,若 SS 顶级 ctArray binding 支持)。

## 单一判据

- `lib/spring/boot/application.ss` 文件内 `comptime {` 出现次数 **≤ 1**(grep)
- `bin/ss build examples/spring-parity/hello/ss/main.ss -o /tmp/hello_ss && /tmp/hello_ss --serve & curl /hello` 仍返 "Hello, World!" byte-identical
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS,M/N 不升
- bootstrap 固定点

## 触发场景

D123 Phase 3 接 DispatcherServlet / 参数绑定时,或 Spring Boot 第二个 example app(hello 之外)加入时优先启动。

## 风险

- SS 顶级 `const X: Array<UserClass> = comptime { ... }` 绑定在 I014 本轮未实测(仅实测 function-local CONST ctArray 绑定)。若顶级 context 走 `emitGlobalVars` 路径未支持 ctVars 绑定,需额外编译器扩展 → 起 D128 决策评估。
- 顶级 ctVar 跨函数 reference 需 `evalIdent` 走 `ctVars` global scope key(`":${name}"`)查询 — 本轮 I014 未验证该路径对 ctArray 是否工作,需实测。
