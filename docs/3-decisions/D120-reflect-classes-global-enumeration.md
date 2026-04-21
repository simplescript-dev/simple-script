# D120: `reflect.classes()` 全局类枚举 comptime API — Spring Boot 注解根因路径

**Status:** Plan 起草中(Execute 未启动,本文档产出即 Plan 落地)
**Depends on:**
- D088 §第一性需求 L7-13(给定对象遍历字段 → 扩展:给定编译单元遍历所有类)/ §Phase 5 L137-148(obj.fields() + obj[name] + for-in 编译期展开,本 Plan 复用)/ §过渡策略 L304-310(@derive 降为便捷层,不是主线)/ §反模式 L377-386(禁 @comptimeEmit 字符串 mixin / ct* 辅助 / runtime 反射)
- D117 §决策 1-2(五类 Meta 对象 Done:ClassMeta/FieldMeta/MethodMeta/AnnotationMeta/ParamMeta,`interpBuildTypeInfo(className)` @ `bootstrap/eval/interp_obj.ss:151` 按名字查单类)
- D098 §决策 2 §Phase B(InternPool 5 标量 dedup,本 Plan `CLS|<name>` key 复用)/ §Phase C(Array/Map/Double dedup 留后续,本 Plan Array<ClassMeta> 不 dedup)
- D094 §规则 1-3(comptime purity pure subset,本 Plan §决策 4 `reflect.classes()` 归类为"读编译期 state"不破 purity)
- D093 §决策 §Zig 原理(编译器即解释器,类型是一等值,Meta 对象是一等 comptime Value)
- D095 §决策(annotation handler 机制 Done,本 Plan 不改)
- CLAUDE.md §反射根因 gate / §交互式单文档 / §PFV 流程
- `memory/feedback_no_workaround.md` / `memory/feedback_no_derive_workaround.md` / `memory/feedback_root_cause_no_cost.md` / `memory/feedback_ultrathink_gate.md`

**Date:** 2026-04-21

---

## 第一性需求

D088 §第一性需求 L7-13:
> 给定一个对象,遍历它的字段名和值。toString、toJson、equals、hashCode、copy —— 全部是同一个需求的不同操作。

D117 Execute 5 commit `6e264fd` 已让**单类**反射完整兑现:`cls = <ClassMeta>` → `cls.fields` / `cls.methods` / `cls.annotations` 三维度全部走 evalExpr MEMBER_ACCESS,InternPool `CLS|<cls>` / `FLD|<cls>.<fld>` / `MTH|<cls>.<mth>` key-dedup,`interpCollectFields` / `interpCtFieldsArray` 双字符串路径整删。

**但 Spring Boot 风格注解驱动框架的核心能力缺失一步**:**给定编译单元,遍历所有类**。

```
Spring Boot 根因路径(用户代码形态,期望兑现后):

@RestController
class TestController {
    @GetMapping("/search") function search(req, resp) { ... }
}

function dispatcherServlet(req, resp): Response {
    for (cls in reflect.classes()) {               // ← 唯一新 API
        if (cls.annotations.has("RestController")) {
            for (m in cls.methods) {
                for (ann in m.annotations) {
                    if (ann.name == "GetMapping" && req.path == ann.args.get("value")) {
                        return invoke(cls, m.name, req, resp)
                    }
                }
            }
        }
    }
    return resp.status(404)
}
```

comptime for-in unroll(D088 Phase 5 L137-148 已 Done)展开后等价于:

```
function dispatcherServlet(req, resp) {
    if (req.path == "/api/search") { return TestController_search(req, resp) }
    if (req.path == "/api/agent")  { return TestController_agent(req, resp) }
    // ... 每条路由 inline 为静态 if,零运行时反射
    return resp.status(404)
}
```

**否定证据**:不补 `reflect.classes()` → Spring Boot 注解路由分发**永不能根因实现**。仅存两条 workaround 路径:

1. **`@comptimeEmit` 字符串拼接生成 dispatcher** —— D088 §过渡策略 2 已冻结("不再扩展"),§反模式 L378-386 明确禁止
2. **runtime 反射 API** —— D088 §不做的事 L312-318 明确禁止

两者均违反 `memory/feedback_no_workaround.md` / `feedback_no_derive_workaround.md`。

**单一判据**:`reflect.classes()` 在 comptime for-in 可展开 + `cls.annotations.has(name)` 可过滤 + `tests/phase5/spring_web_params.ss` 端到端 GREEN(当前 RED `import SpringApplication from @/lib/spring/boot` 缺 `dispatcherServlet`)。

---

## 核心目标 (Goal)

- **为什么**:Spring Boot 注解路由 = D088 §第一性需求 的跨类扩展,根因路径是 comptime 全局 class 枚举 + for-in unroll 静态 dispatch,**不是**运行时反射也**不是** `@comptimeEmit` 字符串生成
- **是什么**:补一个 comptime 内置 API `reflect.classes(): Array<ClassMeta>`,复用 D117 `interpBuildTypeInfo` + `ClassMeta` 容器,让用户代码可 `for cls in reflect.classes()` 遍历编译单元全部类
- **单一判据**:(1) `grep -rn "reflect\.classes" bootstrap/` ≥ 1 命中(现 0)+ (2) `bin/ss run tests/phase5/d120_reflect_classes.ss` GREEN(最小 test 遍历 3 个 class 打印 name)+ (3) `tests/phase5/spring_web_params.ss` E2E GREEN(端到端)

> 口号:D117 让 `cls.fields` 工作,D120 让 `reflect.classes()` 工作 —— 一个对内一个对外,反射 API 就一体化了。

---

## 核心原则 (Principles)

1. **根因不绕路** — 禁 `@comptimeEmit` 字符串拼接 / 禁 runtime 反射 / 禁 ct* 辅助函数扩展
2. **复用 Meta 对象容器** — `reflect.classes()` 返回 `Array<ClassMeta>`,每个元素走 `interpBuildTypeInfo(typeName)` factory,**不新建 Meta 类型**
3. **comptime-only** — 返回 Array 必须是编译期常量,for-in unroll 完全消除运行时反射;runtime 代码不可调用 `reflect.classes()`
4. **枚举源单一** — 唯一数据源 = `interpClasses` Map(interp layer 已注册)+ `classFields` Map(codegen layer 已注册)合集;不新建第三份注册表
5. **AST driven** — 归属 D093 Zig 原理(编译器即解释器),`reflect.classes()` 读编译期注册表**不破** D094 comptime purity

---

## 1. Context Management

### 必读清单

1. 本文档
2. `CLAUDE.md` §关键不变量 / §反射根因 gate / §交互式单文档
3. `docs/3-decisions/D088-comptime-zig-route.md` §第一性需求 / §Phase 5 / §反模式
4. `docs/3-decisions/D117-reflection-meta-objects-and-class-instance-dedup.md` §决策 1-2
5. `docs/3-decisions/D094-*.md` §规则 2 pure subset
6. `bootstrap/eval/interp_obj.ss:145-239`(`interpBuildTypeInfo` 全文)
7. `bootstrap/parse/prelude.ss:16-48`(五类 Meta 定义)

### 关键代码位置

| 文件 | 行号 | 角色 |
|---|---|---|
| `bootstrap/eval/interp_obj.ss` | 151-239 | `interpBuildTypeInfo(typeName: string): int` — 单类 → ClassMeta tvId factory |
| `bootstrap/eval/interp_obj.ss` | 241-243 | `isKnownClass(name): int` — 双注册表 classFields + interpClasses hash 探 |
| `bootstrap/gen/class/class_register.ss` | 50 | `registerClass(id)` — codegen 注册入口 |
| `bootstrap/eval/ct_driver.ss` | 42,74,114 | comptime Pass 1 CLASS_DECL 注册入口 |
| `bootstrap/parse/prelude.ss` | 43-48 | `class ClassMeta { name: string; fields: Array<FieldMeta>; methods: Array<MethodMeta>; annotations: Array<AnnotationMeta> }` |
| `bootstrap/parse/prelude.ss` | 25-28 | `class AnnotationMeta { name: string; args: Array<string> }` — **args 当前形态** |
| `bootstrap/gen/exprs/exprs_ct_builtin.ss` | - | comptime 内置 callable dispatch(`reflect.classes` 在此注册) |

### Stable Facts (Live Repo)

| 项 | 值 |
|---|---|
| 当前阶段 | D119 Accepted(Phase B Value.eql 5 标量兑现),Phase C Array/Map/Double dedup 未启动 |
| 反射 baseline commit | `9e20f26`(D097 frozen) |
| `AnnotationMeta.args` 类型 | `Array<string>`(`bootstrap/parse/prelude.ss:27`)— **本 Plan §决策 2 需再评估** |
| `tests/phase5/spring_web_params.ss` 现状 | RED — `import { SpringApplication } from @/lib/spring/boot"` / `dispatcherServlet` 未定义 / 编译 fail @ 4 处 undefined function |
| 入口命令 | `./build.sh bootstrap` / `bin/ss run tools/reflection_health_linter.ss` |

### 禁止的 Context 操作

- ❌ 读 `bootstrap/pir/` / `bootstrap/gen/class/class.ss`(与本决策无关)
- ❌ 扫 runtime `ss_*` 反射路径(D117 后已无 sidecar)
- ❌ 触 `genVal` 非 comptime 分支(本 Plan comptime-only)

---

## 2. Tool System

### 必备工具

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| Claude 内置 | `Read` / `Edit` / `Grep` / `Bash` | 文件操作 |
| 项目构建 | `./build.sh bootstrap` | 固定点验证(stage2==stage3) |
| 度量 gate | `bin/ss run tools/reflection_health_linter.ss` | 14 指标 + F1 行数 baseline 比对 |
| RED 证据 | `grep -rn "reflect\.classes" bootstrap/` | 现 0 命中 |
| 测试 | `bin/ss test tests/phase5/` | comptime 回归 |

### 禁止引入

- ❌ 新 AST kind(reflect.classes 走现有 METHOD_CALL on built-in IDENT)
- ❌ 新 Meta 类型(复用 ClassMeta)
- ❌ 新全局注册表(复用 interpClasses + classFields)
- ❌ runtime 反射入口

---

## 3. Execution Orchestration

### 总体节奏(Plan 阶段仅规划,Execute 分 3 Phase 独立 D 文档)

### Phase 1 (本 D120 核心): `reflect.classes()` 最小可用

- 新建 `bootstrap/gen/exprs/exprs_ct_reflect.ss`(命名前缀族归位扫描:`filepref=exprs_ct; find bootstrap -name "exprs_ct*"` 命中 `exprs_ct_builtin.ss` / `exprs_ct_call.ss` / `exprs_ct_enum.ss` @ `bootstrap/gen/exprs/`,**归同族**)
- `genValCtReflectClasses(astId: int): int`:遍历 `interpClasses` + `classFields` Map keys(去重合集)→ 对每个 name 调 `interpBuildTypeInfo(name)` → 走 `interpArrayPush` 进 `interpNewArray("")` → 返回 `ctVal(arrId)`
- `exprs_ct_builtin.ss` dispatch 入口识别 `MEMBER_ACCESS reflect + METHOD_CALL classes`(特殊内置 namespace `reflect.classes`)→ 派发到 `genValCtReflectClasses`
- **(§A.4 #3 实测追补,不可省)** 扩 `bootstrap/gen/stmts/stmts_loop_forin.ss:74-97` ct-array unroll 入口:ctProbe trigger 从"iterableId kind ∈ {MEMBER_ACCESS}"扩至"任意 kind,只要 `genVal(iterableId)` 返回 `isCt == 1 && interpType(payload) == "array"`"。这样 `reflect.classes()` 的 METHOD_CALL 返回 ctVal Array<ClassMeta> 自然进入 ct-array 展开路径,不需在 for-in 入口白名单加 "classes" method name case
- **验证**:`tests/phase5/d120_reflect_classes.ss` 最小 test(3 个 class,for-in 打印 `cls.name`)固定点 + GREEN + IR grep 无 `ss_arrayLen/ss_arrayGet/forin.cond` 即未命中 runtime 分支
- **单一判据命中**(2) 兑现

### Phase 2 (独立 D 文档 D121+): `AnnotationMeta.args` Map 形态

- 当前 `AnnotationMeta.args: Array<string>`,`@RequestMapping("/api")` 的 `"/api"` 以什么形态存 / 查?
- Spring Boot 需要 `ann.args.get("value")` — Map 形态
- 本 Plan **暂缓**,Phase 1 先兑现 `ann.name == "RestController"` 式判断,`ann.args` 等值访问留 D121+
- Phase 1 完成前测 `spring_web_params.ss`,会在 args 访问处触发二次阻塞 → D121 起草触发点

### Phase 3 (独立 D 文档 D122+): Spring Boot 端到端 E2E

- 实现 `lib/spring/boot/application.ss`(SpringApplication) + `lib/spring/web.ss`(dispatcherServlet 用 `reflect.classes()` + comptime for-in unroll 生成路由)
- `tests/phase5/spring_web_params.ss` 端到端 GREEN
- **单一判据命中**(3) 兑现

### 本 D120 执行范围锁定

**仅 Phase 1**。Phase 2/3 独立 D 文档,待 Phase 1 兑现后启动。

### 反模式

- ❌ 把 Phase 1+2+3 合并单次 commit(破"每步独立验证")
- ❌ 顺手改 AnnotationMeta.args 结构(Phase 2 范围,越界)
- ❌ 写 `@comptimeEmit` 生成 dispatcher(冻结方案,违反 D088 §过渡策略 2)
- ❌ 加运行时反射 API(违 D088 §不做的事)

---

## 4. State & Memory

### 关键 state

| 变量 | 文件 | 角色 |
|---|---|---|
| `interpClasses` | `bootstrap/eval/interp_*.ss` | comptime Pass 1 class 注册表 Map<name, astId> |
| `classFields` | `bootstrap/gen/class/class_register.ss` | codegen class 字段 CSV 注册表 Map<name, csv> |
| `classNodeIds` | codegen | class AST id 索引 Map<name, id> |
| `internPool` | `bootstrap/lexer/intern_pool.ss:6` | key=`CLS|<name>` → ClassMeta tvId(Phase B dedup) |
| `tvMap` / `tvI1` / `tvS1` | `bootstrap/eval/interp_value.ss` | TypedValue storage,ClassMeta 字段以 `${id}|field` key 写入 |

### 中间产物

- `bin/ss_stage1` / `stage2` / `stage3` — 固定点验证
- `tests/phase5/d120_reflect_classes.ss` — 最小验证 test(Phase 1 产出)

### 会话间持久化

- `git log` — 进度真相源
- 本文档附录 B — 实施日志(Execute 后追加)

### 禁止 state 操作

- ❌ 扩 Meta 类型 / 改 ClassMeta 结构
- ❌ 加新全局注册表(interpClasses + classFields 合集已足够)
- ❌ 进度写 `.claude/next_prompt.md` 累积(per CLAUDE.md 硬约束)

---

## 5. Evaluation & Observation

### 判据(Phase 1 Execute 后每 Step 完成必跑)

| # | 类型 | 命令 / 检查 | 通过条件 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | stage2==stage3 固定点通过 |
| 2 | 测试 | `bin/ss test tests/phase5/` | 不新增 fail(4 个 pre-existing fail 可保持) |
| 3 | 收敛 | `grep -rn "reflect\.classes" bootstrap/` | Phase 1 后 ≥ 1 命中(入口存在) |
| 4 | 行为 | `bin/ss run tests/phase5/d120_reflect_classes.ss` | 输出含 3 个 class name |
| 5 | 度量 | `bin/ss run tools/reflection_health_linter.ss` | GATE PASS + M1/M2/M3a/M4/M5 结构组不升 |
| 6 | 根因 | grep `@comptimeEmit\|comptimeEmitString` bootstrap/ | 不新增 workaround 调用 |

### 回归信号(任一出现 = 立即停下)

- ⚠ `d120_reflect_classes.ss` 未输出预期 class names 或输出顺序不稳定(`interpClasses` + `classFields` 合集 iteration order 未保证)
- ⚠ bootstrap 固定点失败(stage2 != stage3)
- ⚠ linter GATE BLOCKED(任一结构组指标高于 baseline)
- ⚠ 额外 Meta 类型引入 / 新全局注册表出现

### spot check

```bash
# Phase 1 后:reflect.classes 入口存在
grep -rn "reflect\.classes\|genValCtReflectClasses" bootstrap/

# 验证 comptime for-in 展开能力
bin/ss run tests/phase5/d120_reflect_classes.ss
```

---

## 6. Constraints & Recovery

### 硬约束(违反 = 立即回滚)

- CLAUDE.md §Root Cause 优先:禁止 workaround,同 workaround 第二次出现必须停下修根因
- CLAUDE.md §反射根因 gate:触碰反射路径必须跑 linter,任一物理指标高于 baseline 阻断 commit
- D088 §反模式 L377-386:禁 @comptimeEmit / ct* 扩展 / @derive 字符串拼接 handler
- D098 §决策 2 §Phase B:Array<ClassMeta> 不 dedup(Phase C 范围)
- feedback_600_split_not_inline:`exprs_ct_reflect.ss` LOC ≤ 600
- feedback_naming_family_scan:新文件必须归同族(`exprs_ct_*` @ `gen/exprs/`)

### 失败模式 + 恢复

| 信号 | 恢复 |
|---|---|
| Phase 1 固定点失败 | `git reset --soft HEAD^` → 检查 `interpClasses` + `classFields` 合集去重 |
| `reflect.classes()` 运行时被调 | 走 D094 comptimeMustBeKnown 检查,编译期报错 |
| 枚举顺序不稳定 | Map iteration order 依赖,对枚举合集按 name 字典序排序稳定化 |
| linter 结构组 REGRESSION | 先削减后推进(Step 0 模式) |
| `AnnotationMeta.args` 访问形态挡路 | Phase 2 独立 D 文档承接,不强塞 Phase 1 |

### 回滚策略

- 任何 Step 失败 → `git reset --soft HEAD^`
- 禁止"先 commit 再修"
- Phase 2 / 3 启动前必须 Phase 1 完整兑现 + 回归信号零

---

# 附录 A: 决策细节

## A.1 问题

D117 Execute 5 已兑现 `interpBuildTypeInfo(typeName)` 单类 Meta 构造(`bootstrap/eval/interp_obj.ss:151-239`)。反射表达三维度走同一 evalExpr MEMBER_ACCESS,`CLS|<cls>` / `FLD|<cls>.<fld>` / `MTH|<cls>.<mth>` InternPool dedup。

但 `interpBuildTypeInfo` 接受 `typeName: string` 参数,**只能查已知单类**。Spring Boot 注解驱动框架需要遍历**全部类**,当前没有 API 暴露这个入口。

## A.2 决策(§决策 1-4)

### §决策 1 — `reflect.classes()` comptime 内置 callable

**语法**:`reflect.classes()` 是 MEMBER_ACCESS(namespace `reflect`)+ METHOD_CALL(method `classes`)组合。不引新 AST kind / 不加新关键字 / 不引新 lexer token。

**返回类型**:`Array<ClassMeta>`(复用 D117 ClassMeta,不新建 Meta 类型)。

**Dispatch 位置**:`bootstrap/gen/exprs/exprs_ct_builtin.ss` 入口识别 `reflect.classes` 组合,派发到 `genValCtReflectClasses(astId)`(新建 `bootstrap/gen/exprs/exprs_ct_reflect.ss` 承载)。

**实现**:

```ss
// bootstrap/gen/exprs/exprs_ct_reflect.ss (新建 ~40 行)
function genValCtReflectClasses(astId: int): int {
    const arrId = interpNewArray("")
    // 枚举源 = interpClasses + classFields 双注册表合集,按 name 字典序去重稳定化
    const names = collectAllClassNames()
    for (name in names.split(",")) {
        if (name == "") { continue }
        const clsMetaId = interpBuildTypeInfo(name)
        interpArrayPush(arrId, clsMetaId)
    }
    return ctVal(arrId)
}

function collectAllClassNames(): string {
    // interpClasses Map keys + classFields Map keys 合集 → 字典序排序 → csv
    // 实现细节:SS Map 无原生 keys() iteration,用 .keys() 辅助或 has() 遍历已知 name 集合
    // 具体实现留 Execute 轮 grep 确认 Map API 可用方法
}
```

**集成点**:`exprs_ct_builtin.ss` dispatch 原有 `arr.contains` / `cls.fields` 等 comptime 内置,新增 `reflect.classes` case。复用既有 M3b / M4 / M7b 预算(M7b +1 新函数 `genValCtReflectClasses` 必须 Step 0 预削减抵消)。

### §决策 2 — `AnnotationMeta.args` 形态暂缓到 Phase 2

**当前**:`AnnotationMeta.args: Array<string>` @ `prelude.ss:27`。

**Spring Boot 需求**:`ann.args.get("value")` Map 形态。

**本 Plan 立场**:Phase 1 **只兑现** `ann.name == "RestController"` 式比较(D119 已让 5 标量 id==id 可用),`ann.args` 访问留 Phase 2 D121+ 独立决策。

**触发点**:`tests/phase5/spring_web_params.ss` 端到端测试时遇到 `ann.args.get("value")` 访问 → 自然阻塞 → D121 Plan 起草。

### §决策 3 — 枚举源:`interpClasses + classFields` 双注册表合集

**数据源唯一**:

- `interpClasses`: comptime Pass 1 CLASS_DECL 注册(`ct_driver.ss:42,74,114` `registerClass(id)` 入口;D092 Phase 2 遗产)
- `classFields`: codegen 阶段 class 字段 CSV 注册表(`gen/class/class_register.ss:50` `registerClass(id)` 入口)

**合集去重**:`isKnownClass(name) = classFields.has(name) == 1 || interpClasses.has(name) == 1`(@ `interp_obj.ss:241`)已有模式。新 `collectAllClassNames()` 辅助函数按字典序稳定化输出 csv。

**不新建第三份注册表**:否则违反 D088 §反模式(双轨制)+ `feedback_design_no_code_authority`。

### §决策 4 — comptime purity:`reflect.classes()` 不破 pure subset

**D094 §规则 2 pure subset**:comptime 块禁 IO / FFI / 不可确定副作用。

**`reflect.classes()` 定性**:读编译期注册表 state,**不是** runtime state。Zig 路线对齐(D093 §Zig 原理 第 1 条"编译器即解释器"):编译器读自己的 AST / 符号表是 pure operation。

**确定性**:`reflect.classes()` 在 codegen 阶段调用,此时所有 CLASS_DECL 已经 `registerClass` 完成(Pass 1 over),返回集合**确定** + **稳定**(按 name 字典序排序)。

**约束**:`reflect.classes()` **comptime-only**,runtime 代码不可调用。由 `comptimeMustBeKnown` 检查(D094 继承)+ genVal runtime fallback 报错触发。

---

## A.3 替代方案对比(VCM ④ Plan 型替换)

| 方案 | 描述 | 取舍 |
|---|---|---|
| **A (采用)** | `reflect.classes()` comptime 内置 callable + Array<ClassMeta> 返回 + 复用 `interpBuildTypeInfo` factory | 单一根因路径,D088 §第一性需求 自然扩展,零新 Meta 类型,零新注册表 |
| B | `@comptimeEmit` 重启动 + 字符串拼接生成 dispatcher | **反模式**(D088 §过渡策略 2 冻结 + §反模式 明禁) |
| C | 运行时反射 API `reflect.classes()` 在 runtime 可调 | **违反** D088 §不做的事 L312-318 + Zig 路线 compile-time expansion 原则 |
| D | `@SpringBootApplication` handler 内部生成顶层 `dispatcherServlet` 函数 | 需**顶层函数生成能力**,目前 @methodOf 只挂类方法,违反 P10 最小 API 扩展 |
| E | 扩展 `cls.fields()` 语义到 `reflect.classes()`:无参调用 = 全类 | 语义混淆,违反 D088 §Phase 5 "obj.fields() = 字段名列表" 固定语义 |
| F | 新建第三份全局 class 注册表 | 违反 §决策 3 数据源唯一 + D088 §反模式(双轨制) |

**选 A 的理由**:D088 §第一性需求 说"给定对象遍历字段",扩展面是"给定编译单元遍历全部类" —— `reflect.classes()` 是**对称扩展**,复用相同 Value 容器 + Meta 机制。所有 workaround 方案(B/C/D)都违反明确禁令。

---

## A.4 隐藏假设挑战

1. **假设**:`interpClasses` + `classFields` 双注册表在 codegen 阶段 `reflect.classes()` 被调时已全部填充。**挑战**:若 codegen 仍在生成中(某个 CLASS_DECL 的字段分析触发 comptime 块,此时其他 class 未注册),枚举返回**部分**集合。**验证**:grep `reflect.classes` 调用栈,确认必须在 **Pass 2 codegen 后期** 或**主函数 codegen**(所有全局声明已处理完)才可调。若不满足 → Phase 1 需加 codegen pass-order 检查并在 comptime 块早期调用时 `comptimeError`。
2. **假设**:`AnnotationMeta.args: Array<string>` 当前对 `@RestController`(无参注解)已足够,`ann.name` 可用。**挑战**:`@RequestMapping("/api")` 单参数 / `@GetMapping(path="/search", method="GET")` 多参数,Array<string> 如何承载?Phase 1 只用 `ann.name` 可跑最小 test,`ann.args` 等值访问**必然**触 Phase 2 阻塞。**对策**:Phase 2 D121+ 独立承接,Phase 1 不强塞。
3. **假设**:`for cls in reflect.classes()` 能被 D088 Phase 5 `for-in unroll` 编译期展开。**挑战**:D088 Phase 5 展开入口是 `obj.fields()` 和"字符串字面量数组"(@ `bootstrap/gen/stmts/stmts_loop_forin.ss:68-177`,旧引用 `gen_stmts.ss:666,677` 已随 D116 物理拆分迁此)。`reflect.classes()` 返回的是 Array<ClassMeta>(Meta 对象数组),**不是字符串数组**。展开路径需扩展到 Meta 对象数组。

   **Execute 前实测(2026-04-21,本 D 文档 Plan 轮)**:

   - **Probe**: `tests/phase5/d120_probe_array_lit_obj.ss`(ARRAY_LIT<class IDENT> 在 runtime 上下文):

     ```ss
     class Item { name: string }
     function main() {
         const a = new Item(name: "first")
         const b = new Item(name: "second")
         for (m in [a, b]) { print(m.name) }
     }
     ```

   - **命令**: `bin/ss build tests/phase5/d120_probe_array_lit_obj.ss --emit-ir` → `tests/phase5/d120_probe_array_lit_obj.ll:5093-5142`(main 全体)

   - **IR 实测结果**(runtime 分支标志逐条命中):
     - L5109 `%8 = call ptr @ss_newArrayPtr(i32 2)` + L5110-5113 两次 `ss_arraySet` — ARRAY_LIT 运行时构造(未展开成 2 条 inline body)
     - L5114 `%11 = call i32 @ss_arrayLen(ptr %8)` — 对应 `stmts_loop_forin.ss:119` 的 runtime 分支入口 `lenReg = nextReg(); emitIR(...@ss_arrayLen...)`
     - L5115-5116 `alloca i32` + `store i32 0` — 对应 `:122-123` 的 idx alloca
     - L5118-5135 `br label %forin.cond.153` + `forin.cond.153:` / `forin.body.154:` / `forin.update.156:` / `forin.after.155:` — 标准 runtime for-in 四 label 结构(对应 `:132-134` 生成),**label 后缀是 `.153/.154/.156/.155` 非 `.unroll.*`**(后者是 `genForInUnrolled :24,:42,:61` 的展开标志)
     - L5124 `%15 = call i64 @ss_arrayGet(ptr %8, i32 %13)` — 对应 `:153` runtime 分支 `ss_arrayGet`
     - **未观察到**: `alloca ptr` ( `:17` unroll 展开 itemLL 标志) / `store ptr ${strConst}, ptr %${itemLLName}` (`:38`) / `forin.unroll.after` label (`:24`)

   - **展开路径判定**:命中 `stmts_loop_forin.ss:118-176` **runtime 分支**;三条 unroll 入口全部 miss:
     - ct-array unroll(`:74-97`): `iterableId kind == "MEMBER_ACCESS"` 不成立(本 probe 是 `ARRAY_LIT`),且 runtime 上下文 `comptimeDepth == 0`
     - obj.fields unroll(`:100-108`): `getMethodName(iterableId) == "fields"` 不成立(本 probe iterable 不是 METHOD_CALL)
     - ARRAY_LIT unroll(`:110-116`): `stringLitArrayCsv(iterableId)` @ `bootstrap/checker/check_stmts.ss:22` 硬约束"每个元素 kind == STRING_LIT"拒绝 IDENT 元素 → 返回 "" → L112 `if (litCsv != "")` 跳过展开

   - **附带观察(非 §A.4 #3 核心,但 Execute 1 range out 记录)**: IR L5117 `alloca i64` / L5127 `call ptr @ss_int_to_string(i32 %16)` — `inferArrayElemType(ARRAY_LIT<class>)` 回退 i64 default,`m.name` 字段访问丢失(转字面的 int→string)。展开路径走 ctVal 绑定后自然绕开,不是 §A.4 #3 阻塞项。

   - **对 `reflect.classes()` 的外推**:`reflect.classes()` AST kind 为 METHOD_CALL。三条入口 hit 判定:
     - L76 MEMBER_ACCESS trigger: **miss**(METHOD_CALL ≠ MEMBER_ACCESS)
     - L100 method name "fields": **miss**(method name 是 "classes")
     - L110 ARRAY_LIT: **miss**(METHOD_CALL ≠ ARRAY_LIT)

     → 即使 `genValCtReflectClasses` 返回 ctVal Array<ClassMeta>,当前 for-in unroll 入口**不会认**,for-in 走 runtime 循环 → 违 §核心原则 3(comptime-only / runtime 消除反射)。

   - **结论**:§A.4 #3 挑战**成立**(假设"现有 for-in unroll 覆盖 Meta 对象数组"为假)。

   **对 Execute 1 范围的影响**:Execute 1 **必须**同批次扩展 for-in unroll 入口,不能只加 `genValCtReflectClasses`。根因路径(优先):将 L74-97 ct-array unroll 的 ctProbe trigger 从"iterableId kind 白名单"扩到"`genVal(iterableId)` 返回 `ctVal + interpType == "array"`",即任意返回 ct-array 的表达式(MEMBER_ACCESS / METHOD_CALL / IDENT comptime bound)均进入 ct-array 展开路径。这比在每个 comptime callable 处白名单加 method name / kind case 更收敛(避免 "每加一个 reflect.*() 就要在 for-in 入口加配套 case" 的双轨制)。工程量重估:+ 一个 genVal 触发路径 ≈ +15-20 LOC,低于原估 +30%。
4. **假设**:`reflect.classes()` 读 `interpClasses` + `classFields` 双注册表合集不破 `feedback_reflection_root_cause_gate`。**挑战**:本 Plan 触碰反射路径,必须跑 `tools/reflection_health_linter.ss`,M1-M7 + N1-N5 全部不升。**对策**:Execute 轮按 D111 §步骤 0 模板预削减 M7b ≥ -1 抵消新 `genValCtReflectClasses` 函数 +1,其他组 bank check。
5. **假设**:`d120_reflect_classes.ss` 最小 test 写好后能触发 `reflect.classes()` dispatch。**挑战**:`reflect` 作为 IDENT 是否需要 prelude 预声明 / 新 top-level symbol?**对策**:Execute 时若 `reflect` IDENT 未知 → 在 prelude.ss 加 `const reflect = new Reflect()` 样式声明(或内置 namespace sigil,grep 现有 `Map` / `Set` namespace 看约定)。

---

## A.5 单一判据兜底

Execute Phase 1 完成后:
- `grep -rn "reflect\.classes\|genValCtReflectClasses" bootstrap/` → ≥ 2 命中(入口 + impl)
- `bin/ss run tests/phase5/d120_reflect_classes.ss` → 输出 3 个 class names(顺序字典序稳定)
- **IR 证展开(§A.4 #3 实测配套)**:`bin/ss build tests/phase5/d120_reflect_classes.ss --emit-ir 2>&1 | grep -E "forin\.(cond|body|update|after)\.\d+|@ss_arrayLen\(ptr .*@\.ct\.cls_arr" | wc -l` → `0`(`reflect.classes()` 在 main 中的 for-in 完全展开,runtime 分支 label 和 ss_arrayLen 调用均不出现)
- `./build.sh bootstrap` → stage2 == stage3 固定点
- `bin/ss test tests/phase5/` → 不新增 fail
- `bin/ss run tools/reflection_health_linter.ss` → GATE PASS + 结构组 M3b/M4/M6/M7a/M7b/N4/N5 不升

Phase 2 / Phase 3 各自独立 D 文档兜底判据,本 D120 不承载。

---

# 附录 B: 实施日志

### Plan(本轮起草) ⏳

- 2026-04-21:起草 D120 Plan,范围锁定 Phase 1 `reflect.classes()` 最小可用 + Array<ClassMeta> 返回 + comptime-only 约束。Phase 2 `AnnotationMeta.args` 形态决策 + Phase 3 Spring Boot E2E 独立 D 文档承接
- 2026-04-21(§A.4 #3 实测轮):probe `tests/phase5/d120_probe_array_lit_obj.ss` 跑 `--emit-ir`,确认 ARRAY_LIT<class IDENT> / METHOD_CALL 均走 `stmts_loop_forin.ss:118-176` runtime 分支(IR 含 `forin.cond/body/update/after` + `ss_arrayLen/ss_arrayGet`)。§A.4 #3 验证小节 + Phase 1 §范围 for-in unroll 入口扩展追补 + Execute 1 预估 LOC 60-100 + §A.5 IR grep 判据追加。未推 Execute 1 实现(遵循 §交互式单文档 / §范围锁定)

### Execute 1(Phase 1): `reflect.classes()` 最小可用 [ ] Planned

- 待下轮启动 PSM 十问 + 五验 VCM
- 预估 LOC(**2026-04-21 重估,依据 §A.4 #3 实测**):~60-100(新文件 `exprs_ct_reflect.ss` + `exprs_ct_builtin.ss` dispatch case + prelude `reflect` 预声明 + **`stmts_loop_forin.ss:74-97` ctProbe 入口扩 +15-20 LOC**)
- 预估度量影响:M7b +1 须 Step 0 预削减抵消;M2/N2 累计组 +50~150;M3a/M4 结构组 0 或微降(复用 interpBuildTypeInfo);**stmts_loop_forin.ss 现 177 行 → 预估 +20 LOC ≈ 197 行,仍远低于 600 F1 上限**
- 依赖假设挑战 §A.4 #3(for-in unroll Meta 对象数组)**已于 2026-04-21 实测**:probe `tests/phase5/d120_probe_array_lit_obj.ss` IR 证明 ARRAY_LIT<class IDENT>/METHOD_CALL 返回 ctVal 均走 runtime for-in → §A.4 #3 验证小节见上,Execute 1 范围追补 for-in unroll 入口扩展

### Phase 2 / Phase 3 [→] Deferred to D121+ / D122+

- `AnnotationMeta.args` Map 形态决策 → D121 承接
- Spring Boot E2E(`SpringApplication` + `dispatcherServlet` 实现 + `spring_web_params.ss` GREEN)→ D122 承接

---

## 反模式 / 正模式

### ❌ 反模式
- `@comptimeEmit` 字符串拼接生成 dispatcher(D088 §过渡策略 2 冻结)
- runtime 反射 API / 字节码生成(D088 §不做的事)
- 新建第三份 class 注册表(违反 §决策 3 数据源唯一)
- 新建 Meta 类型 / 改 ClassMeta 结构(违反 §核心原则 2 复用容器)
- 把 Phase 1+2+3 合并单轮 Execute

### ✅ 正模式
- `reflect.classes()` 返回 `Array<ClassMeta>`,comptime-only,for-in unroll 消除运行时反射
- 复用 `interpBuildTypeInfo` factory + `interpClasses/classFields` 双注册表合集
- Phase 1 只兑现最小可用,args 形态留 Phase 2 阻塞触发后承接

---

## 参考

- D088 §第一性需求 L7-13 / §Phase 5 L137-148 / §过渡策略 L304-310 / §反模式 L377-386 / §不做的事 L312-318
- D117 §决策 1-2(五类 Meta 对象 Done,`interpBuildTypeInfo` factory)
- D098 §决策 2 §Phase B(InternPool dedup 范围)/ §Phase C(Array dedup 留后续,Array<ClassMeta> 不 dedup)
- D094 §规则 2 pure subset(comptime purity 边界)
- D095 §决策(annotation handler 机制,本 Plan 不改)
- D093 §决策 §Zig 原理(编译器即解释器,Meta 对象一等 Value)
- `bootstrap/eval/interp_obj.ss:151-239`(`interpBuildTypeInfo` 全文)
- `bootstrap/parse/prelude.ss:16-48`(五类 Meta 定义)
- `bootstrap/gen/exprs/exprs_ct_builtin.ss`(comptime 内置 callable dispatch)
- `tests/phase5/spring_web_params.ss`(Phase 3 E2E 目标)
- CLAUDE.md §反射根因 gate / §交互式单文档 / §PFV 流程
- `memory/feedback_no_workaround.md` / `feedback_no_derive_workaround.md` / `feedback_root_cause_no_cost.md` / `feedback_ultrathink_gate.md`
