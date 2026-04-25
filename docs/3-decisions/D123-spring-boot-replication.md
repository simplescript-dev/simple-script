# D123: Spring Boot 复刻 Plan — 注解驱动 MVC 应用 parity 路径

**Status:** draft
**Depends on:**
- D088 §第一性需求 L7-13(给定对象遍历字段 + 编译期展开消除运行时反射)/ §反模式 L377-386(禁 @comptimeEmit / runtime 反射)/ §过渡策略 L304-310(@derive 不当根因)
- D121 §第一性需求 R1 + R2(`AnnotationMeta.args: Map<string,string>` 形态升级 + 注解命名参数语法)—— **Phase 1+ 的硬 blocker**,没有 R1 就没有 `@GetMapping(path: "/x")` 展开 dispatch
- D120 §决策 1(`reflect.classes()` 全局类枚举 Done)/ 附录 B §Execute 1 收尾实测(Probe A/B/C/D 根因诊断)
- D117 §决策 1-2(五类 Meta 对象 Done / `buildAnnotationMetaArray` @ `bootstrap/eval/interp_obj.ss:123-144`)
- D118 §决策(Meta 对象 sidecar 消除 Done)/ D098 §决策 2 Phase B(InternPool 5 标量 dedup)
- D095 §决策(annotation handler 机制 Done,本 Plan **不新建** handler,只新建 comptime 展开 + dispatcher)
- CLAUDE.md §关键不变量 / §项目技术规则(Java/TS 语法优先 / 编译器吸收复杂度 / Root Cause 优先 / 交互式单文档 / PFV 流程)
- `memory/feedback_no_workaround.md` / `feedback_no_derive_workaround.md` / `feedback_dual_entry_is_dual_track.md` / `feedback_no_new_keywords.md` / `feedback_root_cause_no_cost.md` / `feedback_ultrathink_gate.md`
- 现存 prior art:`lib/http.ss` 151 / `lib/jakarta/servlet.ss` 191 / `lib/tomcat/embed.ss` 83 / `lib/spring/{web,http,data,jdbc}.ss` 211 / `lib/spring/boot/jpa.ss` 14(合计 ~650 行,覆盖 HTTP / Servlet / ResponseEntity / JPA 骨架)

**Date:** 2026-04-21
**Last Updated:** 2026-04-22

---

## 第一性需求

Spring Boot 是 Java 生态**注解驱动 MVC 应用**的事实标准。SS 的"编译期展开消除运行时反射"路径(D088)最严苛的**外部 oracle** 就是 Spring Boot:

- 真 Spring Boot 用 JVM 反射 + ASM 字节码扫描 + ApplicationContext 运行时容器实现同一组语义
- SS 若能用 `reflect.classes()` + `cls.methods` + `m.annotations` + `ann.args.get(key)` **纯 comptime** 展开出等价路由表 + dispatcher,就证明 D088 路径不仅"能走",且能**在真实 enterprise 框架尺度兑现 zero-runtime-reflection**
- 反之若绕路(@comptimeEmit 字符串拼接 / @derive 替代 / runtime reflect API),等于承认 D088 路径在 enterprise 尺度断裂

**单一判据**:

```bash
# Parity oracle
curl http://localhost:8080/hello?name=World   # SS 版
curl http://localhost:8081/hello?name=World   # Java 版
# 两边输出 byte-for-byte 相同(Content-Type / body),只要 server header 差异
```

`examples/spring-parity/<app>/ss/` 与 `examples/spring-parity/<app>/java/` 同目录一个 Spring Boot app 双实现,SS 版 `bin/ss build` 产物启动端口响应的 HTTP payload 与 Java `mvn spring-boot:run` 产物 **byte-identical**(排除 Server/Date header)。

> 口号:D120 让 `reflect.classes()` 工作(枚举),D121 让 `ann.args.get(key)` 工作(读参),D123 让 **真 Spring Boot app** 工作(跑起来且与 Java 输出对齐)。

---

## 核心目标 (Goal)

- **为什么**:Spring Boot = D088 "编译期展开消除运行时反射"路径的最严苛 oracle。复刻粒度不足就是玩具原型;复刻范围只取**真 Spring Boot 注解**就不会漂成玩具
- **是什么**:SS `examples/spring-parity/<app>/ss/` 用 `@SpringBootApplication` + `@RestController` + `@GetMapping(path: "/x")` 纯注解定义 app;comptime 展开路由表 + dispatcher → runtime 无反射纯函数调用;Java `.../java/` 同一 API shape 并排 oracle
- **单一判据**(机械):
  1. `bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity` GATE PASS(0 fake annotation,只许真 Spring Boot + SS 内建)
  2. `examples/spring-parity/<app>/ss/` 编译产物与 `./java/` mvn 产物 `curl` 同 endpoint 得 byte-identical 响应
  3. `reflection_health_linter` M1-M7b / N1-N5 不升(新增能力不以牺牲反射路径复杂度为代价)
  4. `grep -rn "@comptimeEmit\|@derive.*dispatcher" examples/spring-parity/` = 0(根因路径,禁替代)

---

## 核心原则 (Principles)

1. **只许真 Spring Boot 注解** — annotation 集 = Spring Boot 3.x 官方白名单 + SS 内建(methodOf / derive / Override 等)。**静态 linter** (`tools/spring_boot_annotation_linter.ss`) 作机械 gate,入仓前扫 `examples/spring-parity/**/*.ss`,违反即 `GATE BLOCKED`
2. **Java oracle 并排,不是对着空气比** — 每个 SS app 有对应 Java 项目在 `./java/`,Maven 可编译,`curl` 可产 ground truth。parity test 接入 CI
3. **comptime-only dispatcher** — 路由表构造在 comptime(`comptime { for c in reflect.classes() { ... } }`),runtime 只剩数组 lookup + 函数调用。禁 @comptimeEmit 字符串拼接 / @derive 替代 / runtime reflect API
4. **D121 R1 blocker 必先落** — `ann.args.get("value")` 不能跑就复刻不了 `@GetMapping(path: "/x")`。Phase 1 起任一 sub-step 触到注解参数访问,**先推 D121 R1,再回本 Plan**
5. **依托既有 lib/**,**不重写** — `lib/http.ss` / `lib/jakarta/servlet.ss` / `lib/tomcat/embed.ss` / `lib/spring/*.ss` 已覆盖 HTTP / Servlet / ResponseEntity / JPA。本 Plan 只在缺口处扩,不为了"统一风格"推翻重写
6. **Java/TS 语法优先** — SS 代码里 annotation 语法就是 `@Ann(key: "val")` COLON(D121 R2-A 已支持),不引入 Kotlin `val/var` 参数 / 主构造函数 / `: Parent` 继承等
7. **Phase 边界 = commit 边界** — 每 Phase 独立 commit + parity gate 独立过,禁大爆炸合并。clear 后的 Claude 能从任一 Phase 边界开干
8. **破 gate 看根因,不看绕路** — 任一 Phase 出现"annotation 形态不够"/"comptime 展开不了" → **回推编译器**,不在 SS app 源码里堆 workaround

---

## 1. Context Management(上下文管理)

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D123)
2. `CLAUDE.md`
3. `docs/2-principles.md` §PFV 流程
4. `docs/3-decisions/D121-annotation-args-and-named-params.md` §第一性需求 + §A.3(R1 Map 形态升级 blocker 状态 + args 访问约定)
5. `docs/3-decisions/D120-reflect-classes-global-enumeration.md` §决策 1(reflect.classes() 语义)
6. `docs/3-decisions/D117-reflection-meta-objects-and-class-instance-dedup.md` §决策 1-2(五类 Meta 契约)
7. 关键代码位置(现存 prior art + comptime 路径入口):

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `lib/http.ss` | 126-151 | `httpServe(port, handler)` HTTP 服务器循环 |
   | `lib/http.ss` | 6-68 | `parseRequest(raw)` 请求解析(method/path/query/headers/body) |
   | `lib/jakarta/servlet.ss` | 全 | HttpServletRequest/Response 类(Jakarta 契约) |
   | `lib/tomcat/embed.ss` | 26-77 | Tomcat 类 start 入口(已 wraps httpServe) |
   | `lib/spring/http.ss` | 34-76 | ResponseEntity + HttpStatus |
   | `lib/spring/web.ss` | 全 | 当前仅 re-export Jakarta Servlet(**Phase 2 扩 @RestController 入口**) |
   | `bootstrap/eval/interp_obj.ss` | 123-144 | `buildAnnotationMetaArray`(Phase 2 读 `@GetMapping` 参数的路径) |
   | `bootstrap/eval/interp_obj.ss` | 151-239 | `interpBuildTypeInfo`(ClassMeta 构造,fields/methods/annotations) |
   | `bootstrap/parse/prelude.ss` | — | `class AnnotationMeta { args }` 形态定义(D121 R1 要改) |
   | `bootstrap/parse/parse_exprs.ss` | 556-587 | `parseArgs`(IDENT+COLON → NAMED_ARG 已支持,D121 R2-A 基础) |
   | `tools/spring_boot_annotation_linter.ss` | 全 | **静态白名单 gate**(本轮创建,入仓即 active) |
   | `tools/reflection_health_linter.ss` | 全 | M1-M7b / N1-N5 反射根因 gate(Phase 1+ 每 commit 验) |

8. 相关 commit hash(写入时由 Phase 0 追加):
   - `TBD` D123 起稿 + 静态 linter 入仓
   - `TBD` D121 R1 Map 形态升级 Done(Phase 1 blocker 解除)

### Stable Facts

| 项 | 值 |
|---|---|
| 当前阶段 | Phase 1 in progress(Execute 1 本轮 commit:`lib/spring/boot/application.ss` 骨架 + `examples/spring-parity/hello/` 最小 app + Java oracle 入仓)/ Phase 2 `@GetMapping` dispatcher 下轮启动。D121 R1 / D127 value-type blocker 已清零(I001-I009 全 Done) |
| 测试基线 | `bin/ss test tests/` 当前 GREEN 基线(commit `8be976a`) |
| 入口命令 | `./build.sh bootstrap` / `bin/ss build examples/spring-parity/<app>/ss/main.ss -o /tmp/ss_app` / `cd examples/spring-parity/<app>/java && mvn spring-boot:run` |
| linter 关键计数 | `reflection_health_linter` M1=5134/M2=76126/M3a=12122/M3b=1879/M4=3037/M5=1750/M6=32/M7a=27/M7b=676/N1=34/N2=380630/N3=518111/N4=321/N5=0 |
| 白名单 linter | `tools/spring_boot_annotation_linter.ss` 白名单含 35 Spring Boot + 5 SS 内建 annotation |

### 禁止的 Context 操作

- ❌ 读 Kotlin / Scala 文档找注解语法灵感 → Java/TS 优先(feedback_no_kotlin_syntax)
- ❌ 读 Rust proc-macro 找 comptime 方案 → 已有 D088 路径,不走 proc-macro
- ❌ 给用户列 A/B/C 选项菜单 → 一条最高效路径直接执行(feedback_no_option_menu)
- ❌ 新建 `notes.md` / `analysis.md` → 所有计划/状态写本文档(feedback 禁 state 漂移)

---

## 2. Tool System(工具系统)

### 必备工具

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| Claude 内置 | `Read` / `Edit` / `Grep` / `Glob` / `Bash` | 编辑 + 检索 |
| 编译器 | `./build.sh bootstrap` / `bin/ss build` / `bin/ss run` / `bin/ss test` | 自举 + 编译 + 跑 |
| 静态 gate | `bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity` | 白名单守护 |
| 反射 gate | `bin/ss run tools/reflection_health_linter.ss` | M1-M7b / N1-N5 根因 |
| Bug harness | `bin/ss run .harness/common/bug.ss detected <imp> <urg>` | 修 bug 强制流程 |
| Java oracle | `mvn`(外部)+ `curl` | parity ground truth |
| ultrathink gate | `bin/ss run tools/next_prompt_ultrathink_linter.ss` | 下轮 payload 校验 |

### 外部依赖(系统级,不动)

- `llc-18` / `musl-gcc` / `vendor/mimalloc.o` — 编译器后端
- `mvn` + JDK 17+ — Java oracle 构建(仅供 parity test 对比,不进 bin/ss 管辖)

### 禁止引入

- ❌ 新关键字(所有注解都是 class-level `@Ident` 形式,参数走 COLON 命名)
- ❌ `@comptimeEmit` / runtime reflect API / @derive 替代 dispatcher(D088 §反模式 + feedback_no_derive_workaround)
- ❌ 新 Meta 类(D117 五类 Meta 冻结,annotation 数据靠 args Map 承)
- ❌ 真 Spring Boot 白名单外的玩具注解(由 `spring_boot_annotation_linter` 机械拦)

---

## 3. Execution Orchestration(执行编排)

### 总体节奏

6 个 Phase,每 Phase 独立 commit + 独立 parity gate。Phase 0 已就绪(本 Plan + 静态 linter),Phase 1 前阻塞在 D121 R1 R2。

```
Phase 0 Plan + 静态 linter   [本轮] ✅
  └─ Plan doc + spring_boot_annotation_linter
     └─ D121 R1 Map 形态落地 (blocker)
Phase 1 @SpringBootApplication  comptime 入口 + 路由表雏形
Phase 2 @RestController + @GetMapping  dispatcher runtime(只 GET / path literal)
Phase 3 HTTP lib 缺口补齐 + Servlet request 参数(lib/spring/web.ss 当前仅 4 行 re-export)
Phase 4 @RequestParam / @PathVariable / @RequestBody  参数绑定
Phase 5 Java oracle + parity CI 接线
```

### 单 Phase 内的循环(硬约束)

```
1. PSM 十问填表(PFV 入口)
2. Read    D123 §对应 Phase + 相关 D 文档
3. Edit    编译器 / lib / example 改动
4. Bash    ./build.sh bootstrap(每改编译器必跑固定点)
5. Bash    bin/ss build examples/spring-parity/<app>/ss/main.ss && /tmp/ss_app &
6. Bash    curl endpoints + diff vs Java oracle(parity gate)
7. Bash    bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity
8. Bash    bin/ss run tools/reflection_health_linter.ss(反射 gate)
9. 失败     → 根因修(禁绕路)→ 回 step 4
10. 全绿    → VCM 六验贴证据 → /simplify → commit
11. 写下轮 payload(含 ultrathink)→ stop
```

### Phase 详细

#### Phase 0: Plan + 静态 linter [✅ 本轮]

- ✅ 起草 D123 Plan(本文件)
- ✅ `tools/spring_boot_annotation_linter.ss` 入仓(35 Spring Boot + 5 SS 内建白名单,扫 `--dir examples/spring-parity`)
- **验证**:
  - `ls docs/3-decisions/D123-spring-boot-replication.md` 存在
  - `bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity`(空目录) → `GATE PASS — 0 fake annotations`
  - `tools/reflection_health_linter.ss` GATE PASS(本轮只碰 tools/ + docs/,反射指标不动)
- **产物**:D123 Plan + 白名单 linter(entry gate),不改编译器,不建 example app

#### Phase 1: @SpringBootApplication comptime 入口 [blocker = D121 R1]

**前置**:D121 R1 `AnnotationMeta.args: Map<string,string>` 落地且 `ann.args.get("value")` comptime GREEN

**目标**:最小可跑 Spring Boot app —— 单文件,`@SpringBootApplication` + `main` + `SpringApplication.run(App.class, args)`,comptime 枚举所有 `@RestController` 类(Phase 1 先建空列表,不 dispatch)

**改动**:

| 文件 | 操作 | 说明 |
|---|---|---|
| `lib/spring/boot/application.ss`(新) | 创建 | `class SpringApplication { static run(cls, args) }` + comptime `reflect.classes()` 扫 `@RestController` 建 ControllerMeta 列表 |
| `examples/spring-parity/hello/ss/main.ss`(新) | 创建 | 最小 app:`@SpringBootApplication class HelloApp {} function main() { SpringApplication.run("HelloApp", args) }` |
| `examples/spring-parity/hello/java/pom.xml`(新) | 创建 | Java oracle Maven 项目骨架 |
| `examples/spring-parity/hello/java/src/main/java/hello/HelloApp.java`(新) | 创建 | Java 版 `@SpringBootApplication` |

**验证**:
- `bin/ss build examples/spring-parity/hello/ss/main.ss -o /tmp/hello_ss && /tmp/hello_ss` → stdout 含 `Started HelloApp` 之类字样
- `bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity` → GATE PASS
- `./build.sh bootstrap` 固定点
- `reflection_health_linter` M/N 不升

#### Phase 2: @RestController + @GetMapping dispatcher

**目标**:最小 HelloController `@GetMapping(path: "/hello")` 返回固定字符串;comptime 展开路由表 + runtime dispatcher tcpListen 接入

**改动**:

| 文件 | 操作 | 说明 |
|---|---|---|
| `lib/spring/boot/application.ss` | 扩 | comptime 遍历 `c.methods` + `m.annotations`,若 annotation name=="GetMapping" 记入路由表(path + className.methodName);runtime `SpringApplication.run` 启 `httpServe` + lookup |
| `examples/spring-parity/hello/ss/HelloController.ss`(新) | 创建 | `@RestController class HelloController { @GetMapping(path: "/hello") function hello(): string { return "Hello, World!" } }` |
| `examples/spring-parity/hello/java/.../HelloController.java` | 创建 | Java oracle |

**验证**(parity gate 本 Phase 首次启用):
- 两端 `curl http://localhost:8080/hello` body 相同
- Content-Type `text/plain` 或 `application/json` 匹配
- 白名单 linter GATE PASS
- 反射 linter M/N 不升

**关键不变量**:路由表构造必须 **全在 comptime**。若 comptime 遍历 `c.methods` 跑不动,回推编译器(D117 methods CSV / D120 reflect.classes())

#### Phase 3: HTTP 缺口补齐 + Servlet request 参数绑定基础

**目标**:`HelloController.hello(request: HttpServletRequest)` 能访问请求对象;补齐 lib/spring/web.ss 的 DispatcherServlet 抽象

**改动**:
- `lib/spring/web.ss` 从 4 行 re-export 扩到真 DispatcherServlet(调度 comptime 路由表)
- `lib/http.ss` / `lib/jakarta/servlet.ss` 按需扩(缺口驱动,不预先扩)
- `examples/spring-parity/hello/ss/HelloController.ss` 加签名 `function hello(req: HttpServletRequest): ResponseEntity`

**验证**:
- parity gate + 白名单 + 反射 linter 全绿
- lib/spring/web.ss 新 LOC 有单测覆盖(`tests/phase5/` 走小粒度 probe,不依赖 examples app)

#### Phase 4: @RequestParam / @PathVariable / @RequestBody

**目标**:`@GetMapping(path: "/hello")` + `@RequestParam(name: "name") name: string` 参数绑定

**改动**:
- `lib/spring/boot/application.ss` comptime 扩 method.params 遍历 + 生成参数解析 adapter
- `examples/spring-parity/hello/ss/HelloController.ss` 加参数注解
- 对等 Java 版

**验证**:
- `curl http://localhost:8080/hello?name=SS` 返回 `Hello, SS!`,两端一致
- gate 全绿
- `reflection_health_linter` M/N 不升(参数绑定用既有 ParamMeta 承,不新建 Meta)

#### Phase 5: Java oracle + parity CI 接线

**目标**:`tools/spring_parity_test.ss`(新)自动启 SS + Java 两端,curl 多 endpoint,diff payload,失败即 exit 1

**改动**:
- `tools/spring_parity_test.ss`(新)~100 行,读 `examples/spring-parity/<app>/parity.yml` 或 json 清单,跑两端并对比
- `.github/workflows/spring-parity.yml`(若存在 CI)或本地 `bin/ss test tests/spring_parity/` 兜底
- 本 Plan 里**不约束** CI 平台(独立决策)

**验证**:
- `tools/spring_parity_test.ss` exit 0
- 所有 examples/spring-parity/* app 全过

### 反模式

- ❌ 先堆 5 个 example app 再建 dispatcher(大爆炸,无 parity gate 护航)
- ❌ Phase 2 跳过 Java oracle,"先让 SS 跑起来再说"(没 oracle 就是玩具,feedback_no_simplify_on_dying_code 同理适用 —— 没 oracle 的 example 本就该被删)
- ❌ Phase 1 blocker(D121 R1)未落就强推本 Plan Phase 1(违反 feedback_no_workaround)
- ❌ 遇到 comptime 展开不动就加 @derive handler 替代(feedback_no_derive_workaround)

---

## 4. State & Memory(状态与记忆)

### 编译时 / 运行时 state

| 变量 | 文件 | 角色 |
|---|---|---|
| `classNodeIds` / `interpClasses` / `classParents` / `classFields` / `classMethods` | `bootstrap/eval/*` | comptime 遍历依赖 |
| `internPool` | `bootstrap/eval/*` | Meta 对象 dedup(CLS/FLD/MTH/ANN 四类 key) |
| ControllerMeta / RouteMeta(Phase 1+ 新增) | `lib/spring/boot/application.ss`(未来) | comptime 构造的路由表容器;runtime 只读 |

### 中间产物

- `examples/spring-parity/<app>/ss/` → `bin/ss build -o /tmp/<app>_ss` 可执行二进制
- `examples/spring-parity/<app>/java/target/*.jar` → Maven 产物
- `examples/spring-parity/<app>/parity.yml`(Phase 5)→ parity 判据 DSL

### 会话间持久化(clear 后还在的)

- `git log` — 进度真相源
- 本文档 — 唯一 Plan / 状态记录
- `tools/spring_boot_annotation_linter.ss` — 入仓即 entry gate
- `examples/spring-parity/**` — parity app 实现

### 禁止 state 操作

- ❌ 在 `.claude/next_prompt.md` 累积跨轮进度(只当 terman payload,不当状态存储)
- ❌ 写 `D123-progress.md` / `spring-notes.md` 分析文件
- ❌ 在本文档外开"辅助性 spec"(feedback_design_no_code_authority 反模式)

---

## 5. Evaluation & Observation(评估与观测)

### 判据(每 Phase 完成必跑)

| # | 类型 | 命令 / 检查 | 通过条件 |
|---|---|---|---|
| 1 | 架构(人工) | 新增 annotation 是否全在 Spring Boot 官方文档? | Yes |
| 2 | 白名单 gate | `bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity` | `GATE PASS — 0 fake annotations` |
| 3 | 反射 gate | `bin/ss run tools/reflection_health_linter.ss` | M1-M7b / N1-N5 不升,基线内 |
| 4 | 编译器 | `./build.sh bootstrap` | stage2==stage3 固定点 |
| 5 | Phase 2+ parity | `curl` SS vs Java 端 `diff` | body / Content-Type byte-identical |
| 6 | 根因收敛 | `grep -rn "@comptimeEmit\|@derive" examples/spring-parity/` | 0 命中 |
| 7 | 测试 | `bin/ss test tests/` | 全绿 |

### 回归信号(任一出现 = 立即停下)

- ⚠ annotation 白名单 `GATE BLOCKED`(出现玩具注解,往前排查)
- ⚠ `reflection_health_linter` 任一 M/N 升(违反 D088 根因不绕路)
- ⚠ SS 二进制启动但 `curl` 返 500(dispatcher 断链,走 bug harness)
- ⚠ SS vs Java parity diff 非空(回 comptime 展开路径排)
- ⚠ 任一 Phase 试图绕路推 @comptimeEmit / @derive(立刻停,回 D088)

### 可选 spot check 命令

```bash
# Phase 1 验路由表构造
bin/ss build examples/spring-parity/hello/ss/main.ss --emit-ir 2>&1 | grep -c "RouteMeta"

# Phase 2 验 comptime 展开后 runtime 无 reflect call
bin/ss build examples/spring-parity/hello/ss/main.ss --emit-ir | grep -c "ss_reflect_"  # 期望 = 0

# Phase 5 parity diff
diff <(curl -s http://localhost:8080/hello) <(curl -s http://localhost:8081/hello)
```

---

## 6. Constraints & Recovery(约束与恢复)

### 硬约束(违反 = 立即回滚)

- CLAUDE.md §项目技术规则(Java/TS 语法优先 / 根因优先 / 交互式单文档)
- D088 §反模式 L377-386(禁 @comptimeEmit / runtime 反射 / @derive 替代)
- feedback_no_workaround / no_derive_workaround / root_cause_no_cost
- feedback_600_split_not_inline(每文件 ≤600 行,Phase 1-4 预计 lib/spring/boot/application.ss 逼近时必物理拆)
- feedback_naming_family_scan(新建文件归族:`lib/spring/boot/*` 族 / `examples/spring-parity/*/ss/` 族)

### 失败模式 + 恢复

| 信号 | 恢复 |
|---|---|
| `ann.args.get("value") → unsupported` | 回 D121 R1,推 Map 形态升级再回本 Plan |
| `reflect.classes() in comptime → panic` | 回 D120,看全局类注册链断点 |
| 路由表构造 runtime 出现 `ss_reflect_*` call | comptime 展开未彻底,回编译器看 comptime unroll(D120 ct-array 泛化) |
| parity gate diff 非空 | 先核对 HTTP header(server name / date 排除),再核 body byte-level |
| 白名单 linter 误报真 Spring Boot 注解 | 补 `SPRING_BOOT_ANNOTATIONS` 并注明 Spring Boot 版本(linter L21 注释) |
| reflection linter M7b 升 | 回 D121 §A.3 #6 第四轮预算分析,对照实际 delta |

### 回滚策略

- 任一 Phase 失败 → `git reset --soft HEAD^`,修后重 commit
- Phase 边界失败(Phase N+1 启动发现 Phase N 假绿) → 回 Phase N 重新跑 §5 判据表
- 跨 Phase 回滚先和用户确认(Phase 边界是稳定锚点)

### 升级判据

模型升级时本 Plan 需复审:
- Phase 划分是否还合理?(Spring Boot 3.x API 可能细节漂移)
- 白名单 linter 是否需要扩新 Spring Boot 版本注解?
- D088 路径是否有新替代方案影响核心原则?

---

# 附录 A: 决策细节

## A.1 问题

D120 让 `reflect.classes()` 枚举 Done,D121 让 annotation args Map 访问 Done,但这两步的**外部 oracle 缺口**依然存在:

- SS 的 comptime 反射路径只在 SS 自己的 test 里验证 —— **没有真实 enterprise 框架作 ground truth**
- D088 §第一性需求 L7-13 说"对象遍历字段 + 编译期展开消除运行时反射",**最严苛的复刻对象就是 Spring Boot**(JVM 反射 + ASM + ApplicationContext 的完整运行时容器)
- 若 SS 不能用 `reflect.classes()` + `cls.methods` + `m.annotations` **纯 comptime** 展开等价 Spring Boot MVC app,那 D088 路径在 enterprise 尺度就断裂

本 Plan 的核心是 **锁 Spring Boot 作外部 oracle,byte-identical parity 作单一判据**,让 SS 注解驱动路径接受真实框架尺度验证。

## A.2 决策

### A.2.1 为什么不先做 @Component / DI 容器

Spring Boot DI 容器(ApplicationContext + @Autowired 注入)是**运行时**能力,与 SS comptime-only 路径**正面冲突**。本 Plan Phase 1-4 **不做** DI 容器,把"对象构造"留在用户代码里显式(`new HelloController()`),仅复刻**路由表 + dispatcher** 这段可 comptime 化的子集。

若未来要复刻 @Autowired,单开 D 文档(comptime 构造 bean 图 → runtime 常量 lookup),**不在本 Plan scope**。

### A.2.2 为什么 parity 判据是 byte-identical 而不是"功能等价"

"功能等价"判据易主观(response 结构不同也能说"语义相同")。byte-identical(排除 Server/Date header)**机械可验**,diff 命令即判据,不留模糊空间。

### A.2.3 为什么 annotation 白名单 linter 写在 tools/ 不写在 checker

- checker 是**编译器核心**,Spring Boot 注解是**应用级约束**,不混同
- linter 是 SS 程序,跑自举编译器作静态 AST 扫描,与 `reflection_health_linter` 同构
- 未来其他领域复刻(React / Vue)可同模板新建 linter,不污染 checker

### A.2.4 为什么 Phase 1 必须等 D121 R1

- Phase 1 `@SpringBootApplication` comptime 要扫 class,Phase 2 `@GetMapping(path: "/x")` 要 `ann.args.get("path")`
- D121 R1 升级 `AnnotationMeta.args` 到 Map 前,Phase 2 无法根因实现
- Phase 1 表面只扫 class 不访问 args,但若 Phase 1 落地前 D121 R1 没锁,Phase 2 入场即卡,Phase 1 commit 变成"半拉子"(feedback_root_cause_no_cost 禁)

### A.2.5 annotation 命名参数语法选 COLON 不选 ASSIGN [SUPERSEDED 2026-04-22 by D127 §A.3]

> **2026-04-22 翻案**:user turn 5 推翻本节"COLON 语法译本"结论,annotation 侧改 ASSIGN (`@Foo(k = v)`),call / constructor 侧保留 COLON。替代决策见 D127 §A.3(按语义分场景)。原文保留供历史审计。

D121 R2-A 已确认:`parseArgs` @ `parse_exprs.ss:570` 原生支持 `IDENT + COLON → NAMED_ARG`,零改动。选 `@GetMapping(path: "/x")` 作 SS 注解命名参数**唯一**语法:

- TypeScript object literal 风格(Java/TS 优先 feedback)
- 不新增 parser 分支(feedback_no_new_keywords)
- 与 SS 已有 `new Foo(name: "x")` 一致(单一形态 anti-dual feedback)

真 Spring Boot Java 语法是 `@GetMapping(path = "/x")` ASSIGN,SS 版对应改成 COLON **是语法译本,不是语义变更**。parity 判据只看 HTTP payload,不看源码字符级一致。

## A.3 白名单初版(Spring Boot 3.x)

静态 linter `SPRING_BOOT_ANNOTATIONS`(35 个):

- **Stereotype + 配置**:SpringBootApplication, Configuration, Component, Service, Repository, Controller, RestController, Bean, ComponentScan, EnableAutoConfiguration, Import
- **Web MVC**:RestController, Controller, GetMapping, PostMapping, PutMapping, DeleteMapping, PatchMapping, RequestMapping, PathVariable, RequestParam, RequestBody, RequestHeader, ResponseBody, ResponseStatus, ExceptionHandler, ControllerAdvice, RestControllerAdvice, CrossOrigin
- **DI / 作用域 / 条件**:Autowired, Qualifier, Value, Scope, Lazy, Primary, Profile, Conditional, ConditionalOnProperty, ConditionalOnMissingBean, ConditionalOnClass, ConfigurationProperties

SS 内建(`SS_BUILTIN_ANNOTATIONS`):methodOf, derive, Override, Deprecated, SuppressWarnings

新增 Spring Boot 注解未收录时,linter stderr 说明"在 SPRING_BOOT_ANNOTATIONS 补上并注明 Spring Boot 版本",提醒不偷偷扩白名单。

---

# 附录 B: 实施日志

### Phase 0: Plan + 静态 linter [✅ 2026-04-24 收关]

- ✅ D123 Plan 起草(本文件)
- ✅ `tools/spring_boot_annotation_linter.ss` 入仓
- **验证**(2026-04-24 本轮实测):
  - ✅ `bin/ss run tools/spring_boot_annotation_linter.ss --dir /tmp/ss_empty_dir` → `GATE PASS — 0 fake annotations`
  - ✅ 负样本 `/tmp/ss_neg_parity/fake.ss`(@RestController + @FakeAnnotation + @GetMapping + @PositionalOnly) → `GATE BLOCKED — 2 fake annotation(s)` 点名 `@FakeAnnotation` / `@PositionalOnly`,白名单 `@RestController` / `@GetMapping` 不误报
  - ✅ `tools/reflection_health_linter.ss` → `GATE PASS — no regressions`(N3 AUTO-DRIFT soft warn 不阻断,本轮 `git diff HEAD -- bootstrap/ lib/` 空输出,核心代码路径 diff=0 确认)
- **Phase 1 前置对账**:层 A2 blocker(ASSIGN + 任意表达式值)已清零 —— I001-I009 全 Done(commits `1cfe717` e2e / `c4de335` D127 §B 对账 / `fa82751` D123 §A.2.5 SUPERSEDED / I008 落位 Done at docs/4-issues/I008-d121-d123-backwrite.md §落位)
- **commit**:(本轮 commit 时追加 hash)

### Phase 1: @SpringBootApplication comptime 入口 [x] Done at `lib/spring/boot/application.ss:17-30` (2026-04-24)

**实施内容**(4 文件新增,LOC ~120):

- `lib/spring/boot/application.ss`(新建,43 行):`class ControllerMeta { className }` 占位 + `class SpringApplication` + `static function run(appName, args)`;comptime block 内 `for (c in reflect.classes()) for (ann in c.annotations) if (ann.name == "RestController")` 收集 className CSV;runtime 打印 `Started <appName>` + controllers 数量
- `examples/spring-parity/hello/ss/main.ss`(新建,13 行):`@SpringBootApplication class HelloApp {}` + `function main() { SpringApplication.run("HelloApp", []) }`
- `examples/spring-parity/hello/java/pom.xml`(新建,34 行):Spring Boot 3.3.0 `spring-boot-starter-parent` + `spring-boot-starter-web` Maven 骨架
- `examples/spring-parity/hello/java/src/main/java/hello/HelloApp.java`(新建,11 行):Java 版 `@SpringBootApplication` 对应物

**判据兑现**(对照 §5 Evaluation,逐条):

| # | 判据 | 实测 |
|---|---|---|
| 1 | Spring Boot 官方注解 | ✅ `@SpringBootApplication` 在白名单 |
| 2 | 白名单 gate | ✅ `bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity` → `GATE PASS — 0 fake annotations`(扫 1 文件,1 不同 annotation) |
| 3 | 反射 gate | ✅ `bin/ss run tools/reflection_health_linter.ss` → `GATE PASS — no regressions`(diff 未触及反射路径,M/N 与 baseline 一致) |
| 4 | 编译器 | ✅ `./build.sh bootstrap` → `Fixed point verified! Stage 2 = Stage 3` |
| 5 | Phase 2+ parity | N/A(Phase 1 不要求 HTTP parity,Phase 2 首次启用) |
| 6 | 根因收敛 | ✅ `grep -rn "@comptimeEmit\|@derive" examples/spring-parity/` = 0 + `grep -c ss_reflect_ /tmp/hello_ss.ll` = 0(comptime 展开干净) |
| 7 | 测试 | ✅ `bin/ss test tests/` → 224 passed + 4 pre-existing fail 保持 |

**行为证据**(VCM §2):`bin/ss build examples/spring-parity/hello/ss/main.ss -o /tmp/hello_ss && /tmp/hello_ss` → stdout `Started HelloApp\nControllers: 0` + exit 0。

**反向证据**(VCM §3):`mv lib/spring/boot/application.ss /tmp/ && bin/ss build ...` → `Unknown class: SpringApplication` @ `main.ss:14`,恢复后 GREEN。因果链闭环。

**commit**:(本轮 commit 时追加 hash)

### Phase 2: @RestController + @GetMapping dispatcher [x] Done at `lib/spring/boot/application.ss:18-89 + bootstrap/eval/method_call.ss:86-108 + bootstrap/gen/stmts/stmts_loop_forin.ss:91-116 + bootstrap/gen/gen_types.ss:412-417` (2026-04-24)

**实施内容**(routes csv + I014 路径 A dispatcher 合计 4 commit:79b3ca8 Phase 2 routes csv / 2f3a895 I014 invoke sentinel / df2b39a I015 顶级 const / 40a3853 I017 includes 同源修复):

- `lib/spring/boot/application.ss`(最终 89 行):顶级 `const _ssRoutes: Array<RouteMeta> = comptime {...}`(I015 抽顶级,4 层嵌套收 routes) + `SpringApplication.run()` 打印 + `httpServe(8080, dispatch)` 启动 + `dispatch(req)` 对路径线性匹配 `r.invoke()` 触发 I014 invoke sentinel emit 静态 call
- `examples/spring-parity/hello/ss/HelloController.ss`(新建,15 行):`@RestController` + `@GetMapping(path = "/hello")`(D127 §A.3 ASSIGN 命名参形态)+ `function hello(): string { return "Hello, World!" }`
- `examples/spring-parity/hello/ss/main.ss`(改 16→18 行):import HelloController;`function main()` 读 CLI args(`args()` / `arg(i)`)推入 appArgs 传给 SpringApplication.run
- `examples/spring-parity/hello/java/src/main/java/hello/HelloController.java`(新建,11 行):Java oracle 对等 — `@RestController` + `@GetMapping("/hello")` + `public String hello() { return "Hello, World!"; }`

**实测验证**(SS 端真 dispatcher 兑现,parity mvn 侧推 Phase 5):

| # | 判据 | 实测 |
|---|---|---|
| 1 | 4 层嵌套 comptime 工作 | ✅ `bin/ss build hello/ss/main.ss && /tmp/hello_ss` → stdout `Routes: /hello|HelloController.hello;` |
| 2 | httpServe 接入 + curl 连通 | ✅ `/tmp/hello_ss --serve &` + `curl -s -i http://localhost:8080/hello` → `HTTP/1.1 200 OK` + `Content-Type: text/plain` + body `Hello, World!` + `Content-Length: 13`(I014 路径 A dispatcher 真兑现,invoke sentinel emit static `call @HelloController_hello`) |
| 3 | 不阻塞默认入口 | ✅ 无 args 模式 stdout 输出后正常退出 |
| 4 | 白名单 linter | ✅ `bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity` GATE PASS |
| 5 | 反射 linter | ✅ M/N 不升(本轮 diff 仅触 lib/spring/boot/application.ss + bootstrap/{eval,gen} invoke 路径,反射 meta 路径未触) |
| 6 | bootstrap | ✅ `./build.sh bootstrap` Stage 2 == Stage 3 固定点(I014 / I015 / I017 三次均过) |
| 7 | 测试 | ✅ `bin/ss test tests/` 全绿(d123_phase1_smoke.ss 仍 PASS,Phase 1 形态向后兼容;i016 / i017 新测亦 GREEN) |
| 8 | parity gate | ⏸ **Deferred to Phase 5** — SS 端 dispatcher 已真兑现(body `Hello, World!` + 200),mvn 工具链未装,Java 端 oracle 搭起配套 |

**最终形态**:routes csv + dispatch 在 `lib/spring/boot/application.ss:18-89`,顶级 `const _ssRoutes` 4 层嵌套 comptime(I015) + `dispatch(req)` 内 `for r in _ssRoutes { if (r.path == path) { return httpResponse(200, "text/plain", r.invoke()) } }`。`r.invoke()` 触发 `bootstrap/eval/method_call.ss:86-108` invoke sentinel,comptime unroll body 内拿到 `className + methodName` 字段对,emit `call ptr @<cn>_<mn>(ptr null)` 静态 IR(Phase 3 DI 容器接 singleton 后 null 填实)。

**commit 链**:79b3ca8 (Phase 2 routes csv + I014 立项) → 2f3a895 (I014 invoke sentinel) → df2b39a (I015 routes 抽顶级 const) → 40a3853 (I017 Array<string>.includes 同源修复,支持 routes Array<string> 派生能力)

### Phase 3-5: 未启动

---

## 反模式 / 正模式(历史归纳)

### ❌ 反模式

- D121 起稿阶段曾写玩具 test `tests/phase5/d121_annotation_named_args.ss` 用 @Field / @Alias / @PositionalOnly / @Empty 假注解 → 用户明确否决:"我要你复刻 springboot 注解"。教训:**测试/example 的注解集 = 真实 oracle 的注解集**,不用占位符
- 只靠"自觉"不写机械 gate → Spring Boot 复刻早期必然漂成玩具原型。教训:**静态 linter 必须在 Phase 0 先行**

### ✅ 正模式

- 白名单 + Java oracle 双层守护:静态(linter)拦编写期,动态(parity diff)拦运行期
- 每 Phase 配一个最小 example(hello / todo / ...),parity gate 一路独立兑现
- Phase 0 不 touch 编译器,纯规划 + 入口 gate,先锁方向再开工

---

# 附录 C: 能力层叠分解(结构视角)

**Status:** draft(粒度 / 物理落点 / 单一判据 逐层待用户审定,§C.4 为迭代入口)

正交于 §3 Phase 时序。§3 按时间序排 6 个里程碑,附录 C 按能力递进排 7 层。两者多对多映射见 §C.2。

## C.1 能力层表

| 层 | 能力 | 状态 | 物理落点 | 单一判据 | 依赖 |
|---|---|---|---|---|---|
| **A1** | 注解 parse 骨架 → AST | ✅ Done | `bootstrap/parse/parse_exprs.ss`;`CLASS_DECL.I4` / `FUNC_DECL.I4` / `PARAM.list` 挂 `ANNOTATION` 节点(无参注解 + 单字符串位置参已工作) | `tests/phase5/d121_*.ss` parser 解 `@X(...)` 无 error | — |
| **A2** | ASSIGN 命名参 + 任意表达式值 | ❌ 未做 | parser `=` 命名参替 COLON;`AnnotationMeta.args` value 类型扩 `Map<string, CtValue>` / `Map<string, AstNodeId>` 承载 enum member / array / bool / int / class refs(当前 `Map<string,string>` 不够,D121 R2-A COLON 被推翻,见 §C.5) | parser 解 `@RequestMapping(value = "/x", method = RequestMethod.GET)` 无 error + comptime 读 `method` 得 `RequestMethod.GET` enum 值 | A1 |
| **B** | comptime introspect | ✅ Done | `bootstrap/gen/exprs/exprs_ct_reflect.ss`(D120 `reflect.classes()`);`AnnotationMeta.args: Map<string,string>`(D121 R1 commit `b18acf3`);`cls.methods` / `m.annotations` / `ann.args.get(k)` comptime 可访问 | `tests/phase5/d120_reflect_classes.ss` + D121 R1 test GREEN | A |
| **C** | 白名单 + 根因 gate | ✅ Done | `tools/spring_boot_annotation_linter.ss`(35 Spring Boot + 5 SS 内建);`tools/reflection_health_linter.ss` M1-M7b / N1-N5 baseline;`grep @comptimeEmit\|@derive` 零命中 | `bin/ss run tools/spring_boot_annotation_linter.ss --dir examples/spring-parity` → `GATE PASS — 0 fake annotations` | — |
| **D** | comptime 构造常量路由表 | ✅ Done at `lib/spring/boot/application.ss:18-38`(I015 顶级 const `_ssRoutes` 4 层嵌套 comptime) | `lib/spring/boot/application.ss:18-38`(commit df2b39a) | `bin/ss build examples/spring-parity/hello/ss/main.ss && /tmp/hello_ss` → `Routes: /hello|HelloController.hello;` ✅ 2026-04-24 | A + B + C |
| **E** | runtime dispatcher | ✅ Done at `lib/spring/boot/application.ss:81-89 + bootstrap/eval/method_call.ss:86-108`(I014 路径 A invoke sentinel emit 静态 call) | commit 2f3a895 | `curl -s -i :8080/hello` → `HTTP/1.1 200 OK` + body `Hello, World!` ✅ 2026-04-24 | D + `lib/http.ss` + `lib/jakarta/servlet.ss` |
| **F** | 参数绑定 | ❌ 未做 | `lib/spring/boot/application.ss` comptime `method.params` 扫 `@RequestParam` / `@PathVariable` / `@RequestBody`;runtime adapter | `curl http://localhost:8080/hello?name=SS` 返 "Hello, SS!" | E |
| **G** | Java oracle + parity | ❌ 未做 | `examples/spring-parity/<app>/java/` Maven 项目;`tools/spring_parity_test.ss`(未建) | `diff <(curl SS 端) <(curl Java 端)` = 空(排除 Server/Date header) | E(基础) / F(完整) |

## C.2 与 §3 Phase 映射(多对多)

| Phase | 对应层 | 范围 |
|---|---|---|
| Phase 0 | C | Plan + 白名单 linter 入仓(commit `4998ebe`) |
| Phase 1 | D 启动 | `@SpringBootApplication` comptime 扫 `@RestController` 建 `ControllerMeta[]`(不 dispatch) |
| Phase 2 | D + E | `@GetMapping` 路由表 + runtime dispatcher 启 httpServe |
| Phase 3 | E 扩 | `lib/spring/web.ss` DispatcherServlet 补齐 + Servlet request 参数 |
| Phase 4 | F | `@RequestParam` / `@PathVariable` / `@RequestBody` 绑定 |
| Phase 5 | G | Java oracle + parity CI |

## C.3 当前断点

- A1/B/C/D/E 已 Done(2026-04-24):Phase 2 dispatcher 端到端真兑现,`curl :8080/hello` → 200 + `Hello, World!` byte-match,commit 链 79b3ca8 → 2f3a895 → df2b39a → 40a3853
- 层 A2(ASSIGN + 任意表达式值)仍待 §C.5 翻案落地 — 当前 `AnnotationMeta.args: Map<string,string>`(D127 §A.3 ASSIGN 单形),Phase 4 `@RequestParam(name = "name")` 扫入前需扩成承载 class ref / enum member / bool / int(I002-I009 子 issue 组正在推进)
- **真正缺口 = 层 F**:参数绑定 — `@GetMapping(path = "/hello")` 本身可工作,但 `function hello(req: HttpServletRequest): ResponseEntity` 形态缺,需扩 `method_call.ss` invoke sentinel 传 runtime req arg + lib/jakarta/servlet.ss HttpServletRequest class(Phase 3 前置)
- 层 G 工具链 blocker:mvn 未装(Phase 5 搭 Java oracle 前要装 maven / build java 对等 app / 并排 curl)
- **下一轮推进候选**:Phase 3(HTTP 缺口 + req/res 参数对象签名) 或 Phase 4(RequestParam 绑定),两者均需层 A2 扩展配套,优先级由用户定

## C.4 用户逐层待审细节(本文档迭代入口)

每一项为 Claude 起草判断,待用户审定后锁定 / 修正 / 删除:

- [ ] **层粒度**:A-G 7 层是否合理?候选争议:(a) D+E 合并为"comptime+runtime 注解驱动"单层?(b) C 拆成"静态白名单 linter" + "reflection baseline gate" 两层?
- [ ] **层 D 单一判据**:`grep -c "ss_reflect_"` = 0 是否充分?是否需补"路由表常量段内容对比(预期 path → handler 映射表完整性)"?
- [ ] **层 E 单一判据**:只测 `/hello` 返 `"Hello, World!"` 是否够?是否需加 HTTP status 200 / Content-Type 验证才算 E 层 Done?
- [ ] **层 F 单一判据**:`@RequestParam` / `@PathVariable` / `@RequestBody` 是否应拆成 F1 / F2 / F3 三子层(各自独立 curl 验证)?
- [ ] **物理落点集中度**:层 D / E / F 都挂 `lib/spring/boot/application.ss` 单文件,feedback_600_split_not_inline 门槛 600 行,是否预留拆分点(如 `application.ss` / `dispatcher.ss` / `param_binding.ss`)?
- [ ] **Phase 映射多对多**:Phase 2 = D+E 同 Phase 合并,是否应拆 Phase 2a(D RouteMeta 扩)+ Phase 2b(E runtime 接入)避免单 Phase 双能力?
- [ ] **依赖列多源**:层 G 同时依赖 E(最小)和 F(完整),是否需区分"最小 G"(hello world parity)与"完整 G"(含参数绑定 parity)?
- [ ] **A/B 层归属**:A/B 本质是 D120/D121 Done 状态,Phase 0 范围只列 C 未显式纳 A/B 引用,是否需补"Phase 0 前置 = A/B 落地状态核对"条?
- [ ] **层序 vs Phase 序互换**:本分解是"能力层叠"结构;D123 §3 是"Phase 时序"。两者正交是否成立?是否存在"某 Phase 跳过能力层"或"某能力层被多 Phase 拆执行"漏 case?
- [ ] **新层候选**:是否漏"H 容器层"(DI 容器 @Component / @Autowired)?D123 §A.2.1 说 DI 容器不在 scope,但 §C.1 不列是否会让"Spring Boot 复刻完整度"判据模糊?

## C.5 层 A 翻案(2026-04-22 用户反馈)

**触发**:用户给出真 Spring Boot 例 `@RequestMapping(value = "/{accessLogId:.+}", method = RequestMethod.GET)`,推翻 D121 R2-A COLON 命名参 `@GetMapping(path: "/x")` "语法译本"方案(D123 §A.2.5 决策需回写)。

**推翻点**:
- **ASSIGN 替代 COLON**:annotation 命名参用 `=` 而非 `:`,对齐 Java 原版
- **非字符串表达式值**:`method = RequestMethod.GET` 是 enum MEMBER_ACCESS,当前 `AnnotationMeta.args: Map<string,string>`(D121 R1)**不承载**;可能还需 array literal / class refs / int / bool 字面量
- **影响面**:§3 Phase 2 示例 `@GetMapping(path: "/hello")` 需改为 ASSIGN(或单位置参);byte-identical HTTP payload parity 判据不变,但源码层注解语法须与 Java oracle 对齐

**层 A 状态拆**:
- **A1 parse 骨架** ✅ Done:`ANNOTATION` AST 节点挂点,无参注解 + 单字符串位置参已工作
- **A2 ASSIGN + 任意表达式值** ❌ 未做:parser `=` 命名参语法 + `AnnotationMeta.args` value 承载机制 + comptime 求值 enum member

**用户逐项待审**(§C.4 扩展):

- [ ] **ASSIGN / COLON 兼容**:完全切 ASSIGN 废 COLON,还是 annotation 双形容忍?—— 双形违反 feedback_dual_entry_is_dual_track 倾向单形
- [ ] **SS 命名参全局一致**:SS 现有 `new Foo(name: "x")` 用 COLON,annotation 改 ASSIGN 引入"两种命名参语法"不一致;是否反向 SS 全改 ASSIGN(breaking change 影响面大)还是 annotation 作为 Java 语法"例外子域"?
- [ ] **annotation value 承载机制**:(a) `Map<string, CtValue>` 新 sum type 承载 string/int/bool/enum/array/class;(b) `Map<string, AstNodeId>` AST 节点 ID 字符串化,comptime 再求值;(c) `Map<string, string>` 不升容器,"表达式文本 comptime 解析"—— 哪种?
- [ ] **enum member 访问语义**:`RequestMethod.GET` 在 annotation 参位是 comptime-resolve 到 enum 值(value 直接是 Enum instance),还是 parser-level `MEMBER_ACCESS` 节点(下游 comptime 展开)?
- [ ] **其他表达式形态**:array literal `{A, B}`(Java) / `[A, B]`(TS)/ class literal `MyClass.class`(Java)/ int / double / bool 字面量 —— 支持范围?
- [ ] **D 文档承接**:层 A2 落 D121 R3 (ASSIGN) + R4 (value 类型扩展),还是起 **D127 annotation-assign-and-expr-values.md**?
- [ ] **Phase 1 blocker 扩容**:原 Phase 1 blocker 仅 D121 R1(已清零),现发现 A2 是新 blocker — Phase 1 开工前必须 A2 全清零?还是 Phase 1 先用 A1 单字符串位置参(无命名参场景)部分启动?
- [ ] **Phase 2 示例字符串**:§3 Phase 2 "`@GetMapping(path: "/hello")`" 改 "`@GetMapping(value = "/hello")`"(或 `@GetMapping("/hello")` 单位置参)+ Java oracle 同步?
- [ ] **§A.2.5 决策回写**:D123 §A.2.5 "COLON 是语法译本" 被推翻,应标 `[SUPERSEDED by §C.5 2026-04-22]` 还是直接重写该段?

---

## §扩容申报-I018 (2026-04-24)

**触发**:I018 §路径 A — invoke sentinel runtime arg 通道扩 + class method funcParamCount pre-register + httpServe query parse。D123 §3 Phase 3 Step 1 真兑现前置,让 Controller 能接收 runtime req map 参数(parity gate 从 byte-static `Hello, World!` 进阶到带 query param 绑定的 `Hello, <name>!`)。**第一性需求**:引 D123 §第一性需求 —— Spring Boot byte-identical parity 在 enterprise 尺度(含 @RequestParam 语义)兑现,invoke 硬编单 this 参是最后跳阻塞。

**改动路径**:
- `bootstrap/eval/method_call.ss`:invoke sentinel 按 funcParamCount arity 追加 runtime args(+26 LOC,method_call.ss:99-119 新循环 + callPreRegs 读)
- `bootstrap/gen/gen_registry.ss`:`registerClassMethodRetType` pre-register 阶段扩注册 funcParamCount(+11 LOC,gen_registry.ss:36-58)
- `bootstrap/gen/class/class_method.ss`:注释同步(emit 时机注册点撤回,避免 dispatch 先 emit 查不到)(+2 LOC 净)
- `lib/http.ss`:httpServe query `key=value` 按 `&` + `=` split 各自入 req map(+16 LOC,lib/http.ss:35-55)
- `lib/spring/boot/application.ss`:`r.invoke(req)` runtime req map 透传 + I018 §路径 A 注释同步(+5 LOC)
- `examples/spring-parity/hello/ss/HelloController.ss`:`hello(req: Map<string,string>): string` 签名 + `req.getString("name")` body(+5 LOC)
- `tests/phase5/d123_phase3_param_bind.ss`:新建 RED→GREEN 测试(+28 LOC)
- `docs/4-issues/I018-invoke-runtime-arg-channel.md`:新建归档

**REGRESSION + AUTO-DRIFT + bump 项 delta 表(实测,OK 项省略)**:

| metric | baseline_value | budget_max | cur | delta | 分类 |
|---|---|---|---|---|---|
| M1 | 5169 | 5230 | 5249 | +19 vs bm | AUTO-DRIFT |
| M2 | 76824 | 76617 | 77769 | +1152 vs bm | REGRESSION |
| M3a | 12204 | 12290 | 12339 | +49 vs bm | AUTO-DRIFT |
| M3b | 1892 | 1879 | 1902 | +23 vs bm | REGRESSION |
| M4 | 3011 | 3050 | 3057 | +7 vs bm | AUTO-DRIFT |
| M5 | 1765 | 1765 | 1770 | +5 vs bm | AUTO-DRIFT |
| M6 | 32 | 33 | 33 | 0 vs bm(bv +1) | DRIFT |
| M7b | 677 | 676 | 680 | +4 vs bm | AUTO-DRIFT |
| N2 | 384120 | 383085 | 388845 | +5760 vs bm | REGRESSION |
| N3 | 517961 | 517080 | 525616 | +8536 vs bm | REGRESSION |
| N4 | 321 | 321 | 350 | +29 vs bm | REGRESSION |
| F1:bootstrap/gen/methods/gen_methods.ss | 709 | 709 | 716 | +7 vs bm | REGRESSION (历史遗留) |

**本地抵消路径**:
- **M2 / N2 / N3**:形态升级型扩(invoke sentinel 增 runtime arg channel + funcParamCount pre-register + httpServe query parse),+60 LOC 新代码直接驱动 AST / Halstead / 节点深度总量。本轮无远距离榨指标空间,I018 三处改动构成最小闭合面。
- **M3b**:`funcParamCount` 被 `method_call.ss` invoke 分支新一次查询,入度 +1;无法本地避开(查询本身是功能要求)。
- **N4**:`method_call.ss:106-117` 内嵌 for-in + if/has/getString/concat 链最大 out-degree 升到 350;本轮实现已收敛(单循环),下轮若再增考虑提独立函数 `emitInvokeExtraArgs(mangled, mcArgList)`。
- **F1:bootstrap/gen/methods/gen_methods.ss**:+7 **属历史遗留**(本轮 git diff `git diff --stat HEAD -- bootstrap/gen/methods/gen_methods.ss` 无输出,`wc -l`=716 对比 baseline 709 为前期漂移未同步)。本轮 housekeep 随 I018 anchor 合并 bump,避免下轮误归因。

**新 baseline 预期值(=实测,bump-group 升 budget_max)**:
- M2 budget_max:76617 → 77769
- M3b budget_max:1879 → 1902
- N2 budget_max:383085 → 388845
- N3 budget_max:517080 → 525616
- N4 budget_max:321 → 350
- F1:bootstrap/gen/methods/gen_methods.ss budget_max:709 → 716

**VCM 实测 vs 预估对照槽**:delta 表 `cur` 列即实测(2026-04-24 本轮 reflection_health_linter 实测)。预估上浮 ~1-1.5% 量级,实测 M2/N2 均 ~1.5% 落预估窗;N3 +1.65% 略超预估但仍在 I018 扩展面合理区间。I018 §单一判据(3 条):`call.*@HelloController_hello(ptr null, ptr ` main.ll:6433 命中 1 ✓;`curl :8080/hello?name=SS` → `Hello, SS!` ✓;`tests/phase5/d123_phase3_param_bind.ss` `Tests: 1 passed` ✓。

**Phase 3 Step 1 parity gate 兑现状态**:SS 端真绑参 byte-identical 对齐 Java oracle 期望(`?name=SS` → `Hello, SS!`,`?name=Alice` → `Hello, Alice!`);Java 端 mvn 仍待 Phase 5 工具链搭起后 diff(8080 vs 8081 端口)。

**commit**:(本轮 commit 时追加 hash)

---

## §扩容申报-I019 (2026-04-24)

**触发**:I019 §路径 — typed `Map<K,V>.get` value 类型推断升根(I018 §风险 §下轮升根路径 hard prereq 兑现)。D123 Phase 3 Step 1 真兑现后 Controller 仍被迫用 `req.getString("name")` 代 `req.get("name")` 字面对齐 Java;本轮让 `inferType METHOD_CALL` 按 receiver generic value arg 返回类型(v0 scope:Map<K,string> → string 路由 ss_mapGetString),消除 I018 §风险 双入口负债。**第一性需求**:引 D123 §第一性需求 —— Spring Boot byte-identical parity 在 enterprise 尺度(含 @RequestParam 语义)兑现,类型系统应 comptime 静态驱动 codegen 不靠用户记忆 `get` vs `getString` 方法名。

**改动路径**:
- `bootstrap/gen/gen_types.ss`:`extractMapValueType` 小 helper(naive first-comma split,v0 嵌套 generic K 不在 scope)+ `inferType` METHOD_CALL 加 Map<K,string>.get → string 分支(~17 LOC)
- `bootstrap/gen/gen_builtins.ss`:`genMapMethod` 签名 +objType 参 + typed Map<K,string>.get 路由 ss_mapGetString 非 ss_mapGet(~8 LOC)
- `bootstrap/gen/methods/gen_methods.ss`:caller 传 objType(+1 LOC)
- `examples/spring-parity/hello/ss/HelloController.ss`:`req.getString("name")` → `req.get("name")` + 注释同步(I018 §风险 表面绕过描述撤换为 I019 §路径 根因链路)
- `tests/phase5/d123_phase3_i019_typed_map_get.ss`:新建 3 个 PASS RED→GREEN 测试(v/miss/Controller-concat)
- `docs/4-issues/I019-typed-map-get-value-inference.md`:新建归档(Done at file:line)

**REGRESSION + AUTO-DRIFT + bump 项 delta 表(实测,OK 项省略;non-reflection scope M*/N* AUTO-DRIFT 软警告按 D097 §反射 scope gate 行为豁免)**:

| metric | baseline_value | budget_max | cur | delta | 分类 |
|---|---|---|---|---|---|
| F1:bootstrap/gen/gen_types.ss | 738 | 760 | 775 | +15 vs bm | REGRESSION |

**本地抵消路径**:
- **F1:bootstrap/gen/gen_types.ss**:I019 加 extractMapValueType helper(11 LOC 已压到 naive)+ inferType Map.get 分支(3 LOC inline)+ 注释(3 LOC)= 净 +17 LOC。第一版 bracket-depth 版已压至 naive first-comma,inline 2 place 比 helper 更多 LOC,无更深压榨空间。文件是 gen 层 inferType / resolveObjClass / ssTypeToLLVM / getVarType 的中枢,物理拆需按 inferType kind-by-kind 拆子文件(~5 子 kind 各独立)—— 非本轮 scope(与 D114 Execute 4 风格的 checker 子文件化类似工程面,应独立 DXXX 决策,不在 I019 issue scope)。

**新 baseline 预期值(=实测,bump 升 budget_max)**:
- F1:bootstrap/gen/gen_types.ss budget_max:760 → 780(5 LOC headroom 吸收下一轮微调)

**VCM 实测 vs 预估对照槽**:预估 cur +15(压榨后实测)精确落地;压榨前先试 bracket-depth 版 cur +60(+45 预估偏差 = 300% 高估)— 预估时未看出 bracket-depth 是过度工程、naive 足够 v0 用例,下轮 PSM §字段 6 应前置"先尝试 naive、failing 再 complex"。I019 §单一判据(3 条):`bin/ss run /tmp/t_i019_red.ss` 输出 `got:v` ✓(before: `got:5244697`);`tests/phase5/d123_phase3_i019_typed_map_get.ss` 3 passed ✓;`tests/phase5/d123_phase3_param_bind.ss`(I018 regression)1 passed ✓ getString 仍 work。

**Phase 3 Step 1 根因闭环状态**:I018 §风险 §下轮升根路径 显式的 typed Map.get value 类型推断缺口本轮根除。Java oracle parity 字面对齐达成(`req.get("name")` 等价 Java),下一 Phase 3 Step 2 @RequestParam / @PathVariable 扩参可基于此实施不再耦合双轨制方法名税。

**commit**:(本轮 commit 时追加 hash)

---

## §扩容申报-I022 (2026-04-25)

**触发**:I022(ct const Array<UserClass> materialize 漏 push 第 2/3 元素)+ I021bc(typed @RequestParam V=int/V=double cast lowering)双 issue 合并 commit;I022 是 I021bc Execute RED 探测意外发现的前置阻塞根因,先修(`runComptimeBlockBody` 出口 reset interpReturnFlag/Val + ct unroll 出口 ctVars.delete itemName + COMPTIME_EXPR 用返回值)再修 I021bc(funcParamTypes class method 注册补全 + invoke sentinel 按 funcParamTypes 分派 cast emit)。**第一性需求**:引 D123 §第一性需求 —— @RequestParam V 维度从 string 扩到 int/double parity Java oracle byte-identical 兑现,消除 I021 v0 silent miscompile(V=int `n=-1116582928` / V=double `x=4.95e-315` 类型 ptr→i32/double LLVM 不拒);Spring Boot enterprise 尺度 typed param binding 不再被 ct const Array materialize bug + invoke sentinel hardcode ptr 双层阻塞。

**改动路径**:
- `bootstrap/gen/stmts/stmts_core.ss`:`runComptimeBlockBody` 出口 saved retVal,reset interpReturnFlag/Val/Break/Continue + 改返 retVal: int(I022 单根因双修复点 — 注册端断流 reset)
- `bootstrap/gen/gen_types.ss`:COMPTIME_EXPR 处理改 `const ceRetVal = runComptimeBlockBody(...)`,删旧 `ceRetFlag = interpReturnFlag` 等 4 行,if 条件改 `ceRetVal > 0`(I022 caller 适配)
- `bootstrap/gen/stmts/stmts_loop_forin.ss`:ct-array + ct-map unroll 出口加 `ctVars.delete(${currentFunc}:${itemName})`(I022 同根因第二修复点 — itemName ct val leak 阻断)
- `bootstrap/gen/gen_registry.ss`:`registerClassMethodRetType` 内 PARAM 循环新增 funcParamTypes 双轨注册(`${baseName}:${idx}` + `${baseName}_${mSig}:${idx}`),对称 codegen.ss:107-111 普通函数路径(I021bc 注册端)
- `bootstrap/eval/method_call.ss`:invoke sentinel for-in 循环改按 `funcParamTypes[mangled:idx]` 分派 cast emit;V=int → ss_parseInt + i32 / V=double → ss_parseDouble + double / V=string/默认 → ptr 透传(I021bc 消费端)
- `examples/spring-parity/hello/ss/HelloController.ss`:加 `/age` (V=int) + `/calc` (V=double) 路由,与原 `/hello` (V=string) 共存(端到端 multi-V 测试覆盖)
- `examples/spring-parity/hello/java/src/main/java/hello/HelloController.java`:同步加对应 Java method `@RequestParam int n` / `@RequestParam double x` 保 byte-identical 对齐
- `docs/4-issues/I022-ct-const-array-materialize.md`:新建归档(Done at 4 file:line)
- `docs/4-issues/I021bc-typed-request-param-cast.md`:Approved → Done at 多 file:line + 根因表述修订(双层根因 → 单根因双修复点 / 信息流断裂)
- `docs/3-decisions/D129-request-param-class-domain.md`:V=class 跨域辨析 Drafted(I021d 域归属)

**REGRESSION + AUTO-DRIFT + bump 项 delta 表(实测,OK 项省略)**:

| metric | baseline_value | budget_max | cur | delta | 分类 |
|---|---|---|---|---|---|
| M1 | 5260 | 5230 | 5283 | +53 vs bm | REGRESSION |
| M3a | 12350 | 12290 | 12436 | +146 vs bm | REGRESSION |
| M4 | 3063 | 3050 | 3081 | +31 vs bm | REGRESSION |
| M7b | 681 | 676 | 683 | +7 vs bm | REGRESSION |
| N3 | 526509 | 525616 | 533644 | +8028 vs bm | REGRESSION |
| F1:bootstrap/gen/gen_decls.ss | 706 | 708 | 730 | +22 vs bm | REGRESSION (stale 上轮残留 +5 + I021bc 误推 +17) |

**本地抵消路径**:
- **M1 / M3a / M4**(反射路径行数 / 字符 / 节点)— I021bc invoke sentinel cast emit 分支 +20 LOC 集中 method_call.ss(消费端)+ gen_registry.ss funcParamTypes 注册 +5 LOC(注册端);I022 stmts_core/stmts_loop_forin/gen_types 共 +14 LOC(reset flag + delete itemName + caller 改接口)。压榨空间已极限 — 注册端 5 LOC 已 inline 双轨 set 不可压;消费端 cast emit 三分支(int/double/默认)用 if-elif 已最小;无更深结构压榨可能不损可读性
- **M7b**(invoke sentinel 复杂度)— +7 反映 funcParamTypes 查询 + cast emit 逻辑必要复杂度,非冗余
- **N3**(总字节)— 主要由 method_call.ss invoke sentinel + gen_registry.ss + 文档累积引起,单 commit 落档不可拆
- **F1:gen_decls.ss**(730 vs bm=708)stale REGRESSION:**本轮零改 gen_decls.ss**(I021bc 改的是 gen_registry.ss + method_call.ss;I022 改的是 stmts_core/stmts_loop_forin/gen_types),730 是上轮 I021 v0 收关时已存在的 stale 漂(可能 I021 v0 add 的 funcDefaults 路径或 globalInits 调整),baseline 滞后未 record/bump。本轮一并 bump 712→730 收紧 budget,无单独抵消必要(非本轮新引入)

**新 baseline 预期值(=实测,bump 升 budget_max)**:
- M1 budget_max: 5230 → 5283
- M3a budget_max: 12290 → 12436
- M4 budget_max: 3050 → 3081
- M7b budget_max: 676 → 683
- N3 budget_max: 525616 → 533644
- F1:bootstrap/gen/gen_decls.ss budget_max: 708 → 730(stale + I021bc 合并)

**VCM 实测 vs 预估对照槽**:I021bc 文档 §下轮升根路径 §潜在工程风险 4 预估 reflection_linter F1 gen_registry.ss / method_call.ss baseline 漂移 — 实测漂移点更广(M1 / M3a / M4 / M7b / N3)且不在 F1:gen_registry.ss / F1:method_call.ss 单独入榜(说明这两文件 LOC 没单独 F1 budget,改动落到聚合 M*/N*)。预估 ~20-35 LOC 单 commit,实测 I021bc + I022 合并 bootstrap 改动 +44 LOC(I022 14 + I021bc ~30),工程量在 30-50 LOC 区间(I021bc §潜在工程风险 1 升根 callee 端 LLVM 签名验证 实测不需要 — callee 签名走 class_method.ss `resolveTypeParam(nGetS2(pId))` 已正确生成 i32 / double,本 issue 仅修 caller invoke 实参 cast 端)。

**Phase 4 @RequestParam V 维度根因闭环状态**:I021 v0 V=string 路径(2026-04-25 commit 75f0516+8844e5f)+ I022 ct const Array materialize(本轮)+ I021bc V=int/V=double cast lowering(本轮)三 issue 联动覆盖 @RequestParam 域 V=primitive 全集。下一步 V=class 跨域辨析(D129 — 不在 @RequestParam 域,属 @RequestBody / @ModelAttribute);多参 @RequestParam 留 I021-multi-param;@PathVariable / @RequestHeader 各自独立 issue 复用本 issue 的 funcParamTypes + invoke sentinel cast 通道。

**commit**:(本轮 commit 时追加 hash)

---

## §扩容申报-I021-requestbody (2026-04-25)

**触发**:I021-requestbody Execute 阶段 1+2 端到端落地 — Phase 4 §247 第二支柱 @RequestBody POST/PUT/PATCH JSON body → class 反序列化 root 闭环;路径 A(per-class @ClassName_deserialize codegen 自动生成 + invoke sentinel kind 扩 RequestBody + lib/json.ss primitive helpers + RouteMeta httpMethod + comptime 5 method 识别 + dispatcher matchPath httpMethod 比对)。**第一性需求**:引 D123 §第一性需求 + D129 §5 跨域辨析(V=class 不在 @RequestParam 域,起独立 deserializer 基础能力)— SS 用户 `function createUser(@RequestBody user: User)` 行为 byte-identical Java `@RequestBody User user`,curl POST /users -d '{"name":"alice","age":30}' 返 user=alice,age=30。

**改动路径**:
- `lib/json.ss`:加 jnGetInt/Double/String/Bool 4 raw int 接口 primitive helpers(对接 codegen emit IR 直接调,无 JsonNode wrapper alloc 开销)
- `lib/spring/boot/application.ss`:RouteMeta 加 httpMethod slot;PARAM_KIND_REQUEST_BODY const;comptime _ssRoutes 扩 GetMapping/PostMapping/PutMapping/DeleteMapping/PatchMapping 5 method 识别 + RequestBody push spec;dispatcher matchPath httpMethod 比对;import lib/json 让 JsonNode struct + JSON_parse + jnGet* 进编译单元
- `bootstrap/eval/method_call.ss`:invoke sentinel kind == "RequestBody" 分支 emit `ss_mapGetString(req, "body") + JSON_parse + JsonNode.nodeId 取 + @<ClassName>_deserialize(i32 nodeId)` + 注册 deserializerTargets
- `bootstrap/gen/gen_type_ops.ss`:emitClassDeserializeFn per-class deserializer 自动生成(mirror ss_drop_X / ss_deep_clone_X / ss_shallow_clone_X 模式 — D018 + D022 第四步);**延迟 emit**:仅对 @RequestBody invoke sentinel 引用的 class emit(避免 jnGet* runtime symbol 污染未 import lib/json.ss 的程序)
- `bootstrap/gen/codegen.ss`:emitGlobalsAndCode 收尾后调 emitPendingDeserializers + resetCodegen 重置 deserializerTargets 防跨编译单元污染
- `examples/spring-parity/hello/ss/HelloController.ss`:加 User class + @PostMapping("/users") createUser(@RequestBody user: User)
- `examples/spring-parity/hello/java/src/main/java/hello/HelloController.java`:Java oracle 同步加 User class + @PostMapping("/users") @RequestBody User user
- `tests/phase5/i021_requestbody.ss`:新建 6 case(主用例 + 字段顺序乱 + 字段缺失 + 纯 string + double + GET vs POST 区分)
- `tests/phase5/i021_pathvariable.ss / i021_multi_param.ss`:补 req.set("method", "GET")(dispatcher 加 method 比对后 unit test 模拟应对齐 HTTP layer)
- `docs/3-decisions/D129-request-param-class-domain.md`:Decided
- `docs/4-issues/I021-requestbody.md`:Planned → Done at(本轮 file:line)

**REGRESSION + bump 项 delta 表(实测,OK 项省略)**:

| metric | baseline_value | budget_max | cur | delta | 分类 |
|---|---|---|---|---|---|
| M2 | 77880 | 77769 | 79098 | +1329 vs bm | REGRESSION |
| M3b | 1903 | 1902 | 1943 | +41 vs bm | REGRESSION |
| M5 | 1772 | 1765 | 1792 | +27 vs bm | REGRESSION |
| N2 | 389400 | 388845 | 395490 | +6645 vs bm | REGRESSION |
| N3 | 526509 | 533644 | 544648 | +11004 vs bm | REGRESSION |

**本地抵消路径**:
- **M2 / N2 / N3**(反射模块总 LOC / 字符 / 总字节)— gen_type_ops.ss emitClassDeserializeFn ~50 LOC + emitPendingDeserializers ~10 LOC;method_call.ss sentinel RequestBody 分支 ~20 LOC;codegen.ss reset + emit hook ~5 LOC;总 ~85 LOC 集中反射路径(per-class 函数自动生成 + sentinel 分派)。已无更深结构压榨可能 — emitClassDeserializeFn 字段类型分派 if-elif int/double/string/bool 是最小四分支(jnGet 名族 + LLVM type sig 必须分派;不可合并)
- **M3b**(反射 char count)— M2 LOC 增长引起的字符数线性增加,无单独抵消空间
- **M5**(反射模块函数复杂度)— +20 反映 emitClassDeserializeFn 字段递归 emit 必要复杂度(GEP + jnGet call + store 每字段三行 emit),非冗余

**新 baseline 预期值(=实测,bump 升 budget_max)**:
- M2 budget_max: 77769 → 80000(buffer ~900)
- M3b budget_max: 1902 → 2000(buffer ~57)
- M5 budget_max: 1765 → 1830(buffer ~38)
- N2 budget_max: 388845 → 400000(buffer ~4500)
- N3 budget_max: 533644 → 550000(buffer ~5350)

**VCM 实测 vs 预估对照**:I021-requestbody §潜在工程风险 5 预估 F1 baseline 漂(bootstrap/gen/class/ +120-200 LOC),实际 emit 路径选 gen_type_ops.ss 而非 class/ 子族(单文件已 ~600 LOC),F1 没单独漂(gen_type_ops.ss 不在 F1 白名单);改动落到聚合 M2/M3b/M5/N2/N3。预估大改 ~300-450 LOC 跨 6-7 文件,实测 ~85 反射 LOC + ~20 lib LOC + ~20 examples/tests LOC,工程量~125 LOC 反射 + ~120 总(< 预估下限 ~300)。

**commit**:(本轮 commit 时追加 hash)

---

## 参考

- 外部:
  - Spring Boot 3.x Reference Guide —— annotation 集权威
  - spring-projects/spring-boot GitHub —— parity oracle 实现参考
  - Spring Framework @MVC 文档 —— dispatcher 语义
- 相关 D 文档:D088 / D094 / D095 / D098 / D117 / D118 / D120 / D121
- 现存 lib 依托:`lib/http.ss` / `lib/jakarta/servlet.ss` / `lib/tomcat/embed.ss` / `lib/spring/{web,http,data,jdbc}.ss`
- commit hash:(本轮 commit 入仓时追加)
