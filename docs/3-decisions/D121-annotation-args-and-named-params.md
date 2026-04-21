# D121: AnnotationMeta.args 形态升级 + 注解参数命名语法 — Spring Boot 注解根因路径 Phase 2

**Status:** draft
**Depends on:**
- D088 §第一性需求 L7-13(给定对象遍历字段 + 编译期展开消除运行时反射)/ §反模式 L377-386(禁 @comptimeEmit / runtime 反射)/ §过渡策略 L304-310(@derive 不当根因)
- D120 附录 B §Execute 1 收尾实测证据 L474-540(R1/R2/R3 实测分解,R3 iteration/index 已 Done / R1 + R2 为本 Plan 根因范围)
- D120 §决策 2 L329-337(AnnotationMeta.args 形态暂缓到 Phase 2 D121+ 通道)/ §核心原则 2(复用 Meta 对象容器,不新建第六类 Meta)/ §A.3 替代方案 B/C/D 冻结
- D117 §决策 1-2(五类 Meta 对象 Done / `buildAnnotationMetaArray` @ `bootstrap/eval/interp_obj.ss:123-144` inline 取 STRING_LIT)
- D094 §规则 2(comptime pure subset,annotation 元数据构造在 codegen pre-pass)
- D095 §决策(annotation handler 机制 Done,本 Plan 不改)
- D098 §决策 2 Phase B(InternPool 5 标量 dedup / ANN|<prefix>.<name> key 已建立)
- CLAUDE.md §关键不变量 / §反射根因 gate / §交互式单文档 / §PFV 流程
- `memory/feedback_no_workaround.md` / `feedback_dual_entry_is_dual_track.md` / `feedback_no_ugly_syntax.md` / `feedback_no_new_keywords.md` / `feedback_root_cause_no_cost.md` / `feedback_ultrathink_gate.md`

**Date:** 2026-04-21
**Last Updated:** 2026-04-21

---

## 第一性需求

D120 附录 B §Execute 1 收尾实测证据(L474-540)通过四条 probe 把 D120 §A.4 #2 "Phase 2 args 形态阻塞" 单点推演分解为**双根因 + 一条 Done**:

- **R1**(形态):`AnnotationMeta.args: Array<string>` @ `prelude.ss:27` 无 `.get(key)` dispatch,`ann.args.get("value")` stdout `[comptime] unsupported array method: get` 挡路(Probe B)
- **R2**(parser):`@GetMapping(path="/search", method="GET")` 命名参数 ASSIGN 语法 stdout `parse error: expected RPAREN, found ASSIGN '='` 挡路(Probe D);`parseArgs` @ `parse_exprs.ss:570` 已识别 `IDENT + COLON` NAMED_ARG,**不识别** ASSIGN
- **R3**(iteration/index):`for (arg in ann.args)` + `ann.args[0]` 在 ct 路径**已 Done**(Probe A + Probe C GREEN @ D120 Execute 1 Phase 1 ct-array unroll 泛化覆盖),**不承接**

**否定证据**:不补 R1 + R2 → Spring Boot 路由表达式 `for m in cls.methods { for ann in m.annotations { if (ann.name == "GetMapping" && req.path == ann.args.get("value")) { ... } } }` **永不能**根因实现,仅剩 D088 §过渡策略 2 冻结的 `@comptimeEmit 字符串拼接 dispatcher` + D088 §不做的事 禁止的 runtime 反射 API 两条 workaround。

**单一判据**:
1. `grep -rn "class AnnotationMeta" bootstrap/parse/prelude.ss` → 字段形态升级
2. `@GetMapping(path: "/x", method: "GET")` 或 `@GetMapping(path="/x", method="GET")` parse 不报错
3. `ann.args.get("value")` comptime 返回字符串(非 `unsupported array method`)
4. `tests/phase5/d121_annotation_named_args.ss` 最小 test 遍历注解 + `.get(key)` 访问命名参数 GREEN

> 口号:D120 让 `reflect.classes()` 工作(对外),D117 让 `cls.fields` 工作(对内),D121 让 `ann.args.get(key)` 工作 —— annotation 参数的"形态 + 语法"根因两面同时兑现,Spring Boot 路由根因路径闭环。

---

## 核心目标 (Goal)

- **为什么**:Spring Boot `@GetMapping(path="/search")` + `ann.args.get("value")` 是 D088 §第一性需求 "对象遍历字段" 的**注解驱动扩展**,两条路径(形态 + 语法)是同一盲点两面,根因同时兑现才闭环
- **是什么**:
  - R1:升级 `AnnotationMeta.args` 形态,支持 `.get(key): string`(键-值访问)+ 保留 `args[index]` / `for arg in args` 兼容(D120 Execute 1 已兑现的行为不破)
  - R2:扩展 `parseArgs`(或只在 annotation 路径扩)识别 `key="val"` ASSIGN 语法 **或** 锚定 `key: "val"` COLON 语法作为 SS 注解命名参数官方形态
- **单一判据**:
  1. `grep -rn "args: Map" bootstrap/parse/prelude.ss` 或 `grep -rn "argsByName" bootstrap/parse/prelude.ss` ≥ 1 命中(形态升级入口存在)
  2. `bin/ss run tests/phase5/d121_annotation_named_args.ss` GREEN
  3. `./build.sh bootstrap` stage2==stage3 固定点
  4. `bin/ss run tools/reflection_health_linter.ss` GATE PASS + 结构组 M3b/M4/M6/M7a/M7b/N4/N5 不升

---

## 核心原则 (Principles)

1. **根因不绕路** — 禁 `@comptimeEmit` 字符串拼接 / 禁 runtime 反射 / 禁 ct* 辅助函数白名单扩展
2. **不新建第六类 Meta** — args 形态升级**只动** `AnnotationMeta` 内部字段类型 / `buildAnnotationMetaArray` 构造路径 / ct dispatch 路由,不新建 `AnnotationArgMeta` 之类容器(D120 §核心原则 2)
3. **Java/TS 语法优先,优先复用不自创** — 注解命名参数语法在 `@Ann(key: "val")` COLON(SS 已支持 NAMED_ARG,TypeScript/TSX 风格)与 `@Ann(key="val")` ASSIGN(Java/Spring 风格)二选一;**若** COLON 可满足 Spring Boot 用户期望,优先复用不新增 parser 分支(feedback_no_ugly_syntax / feedback_no_new_keywords);**若** 用户坚持 ASSIGN 风格,扩展 parseArgs 接受 ASSIGN 作为**等价** COLON 的 AST 映射(同构不新增 kind)
4. **单一形态 anti-dual** — args 不做 "Array<string> + Map<string,string> 双 API",feedback_dual_entry_is_dual_track 明禁双入口。形态选**单一** Map<string,string> 或**单一**结构化容器
5. **comptime-only** — 所有 `ann.args.get(...)` 访问必须在 comptime block 内展开,runtime 分支走 comptimeMustBeKnown 报错
6. **向后兼容可接受底线** — D120 Execute 1 Phase 1 已兑现的 `ann.args[0]` / `for arg in ann.args` 行为**必须**保留(不破已 GREEN 的 test);若形态升级后语义变化,必须同步改已有 test 的访问形态并在 D 文档明述升级路径
7. **AST driven** — 归属 D093 Zig 原理 + D094 pure subset;R1/R2 都读 / 改编译期 AST / 注册表 state,不破 comptime purity

---

## 1. Context Management

### 必读清单

1. 本文档
2. `CLAUDE.md` §关键不变量 / §项目技术规则 / §反射根因 gate
3. `docs/3-decisions/D120-reflect-classes-global-enumeration.md` 附录 B §Execute 1 收尾实测证据 L474-540(R1/R2/R3 划分,**权威输入**)
4. `docs/3-decisions/D117-reflection-meta-objects-and-class-instance-dedup.md` §决策 1-2
5. `docs/3-decisions/D088-comptime-zig-route.md` §第一性需求 / §反模式 / §不做的事
6. `bootstrap/parse/prelude.ss:25-28`(AnnotationMeta 当前形态)
7. `bootstrap/parse/parser.ss:247-267`(`parseAnnotationList` — annotation AST 构造)
8. `bootstrap/parse/parse_exprs.ss:556-587`(`parseArgs` — named arg 识别入口)
9. `bootstrap/eval/interp_obj.ss:118-144`(`buildAnnotationMetaArray` — AnnotationMeta 实例构造)
10. `bootstrap/gen/exprs/exprs_ct_builtin.ss:180-239`(`ctArrayMethod` / `ctMapMethod` 当前 dispatch)

### 关键代码位置

| 文件 | 行号 | 角色 |
|---|---|---|
| `bootstrap/parse/prelude.ss` | 25-28 | `class AnnotationMeta { name: string; args: Array<string> }` — **R1 形态升级锚点** |
| `bootstrap/parse/parser.ss` | 247-267 | `parseAnnotationList` — annotation AST 节点构造,`nSetList(aId, aArgs)` 存 parseArgs 结果 |
| `bootstrap/parse/parse_exprs.ss` | 556-587 | `parseArgs` — NAMED_ARG 当前识别 `IDENT + COLON`(L570),**R2 扩展锚点** |
| `bootstrap/parse/parse_exprs.ss` | 569-578 | NAMED_ARG 分支:`nSetS1(naId, naName)` + `nSetI1(naId, valId)` — **R1 形态升级后 buildAnnotationMetaArray 读取入口** |
| `bootstrap/eval/interp_obj.ss` | 123-144 | `buildAnnotationMetaArray` — inline 取 STRING_LIT(L136),**R1 升级必须同步读 NAMED_ARG 结构** |
| `bootstrap/gen/exprs/exprs_ct_builtin.ss` | 180-213 | `ctArrayMethod` — 当前 `.get` 未收录(L212 unsupported);**R1 Map 形态后走 `ctMapMethod`** |
| `bootstrap/gen/exprs/exprs_ct_builtin.ss` | 216-239 | `ctMapMethod` — `.get` / `.has` / `.keys` / `.size` 已 Done,**R1 升级后复用** |
| `bootstrap/parse/parse_stmts.ss` | 8 | `parseAnnotationList` 顶层 stmt 调用点 |

### Stable Facts (Live Repo)

| 项 | 值 |
|---|---|
| 当前阶段 | D120 Accepted(Execute 1 Phase 1 Done at `a364e4b`);D121 draft 起草中 |
| 反射 baseline commit | `9e20f26`(D097 frozen)|
| `AnnotationMeta.args` 类型 | `Array<string>`(`prelude.ss:27`)|
| `parseArgs` NAMED_ARG 识别 | 仅 `IDENT + COLON`(`parse_exprs.ss:570`);`IDENT + ASSIGN` parse error |
| `buildAnnotationMetaArray` args 过滤 | 仅 STRING_LIT(`interp_obj.ss:136`);NAMED_ARG / INT_LIT 被跳过 |
| `tests/phase5/spring_web_params.ss` 状态 | RED — 4 处 undefined(`SpringApplication` / `dispatcherServlet` 等,Phase 3 D122 范围,**不**本 Plan) |
| 入口命令 | `./build.sh bootstrap` / `bin/ss run tools/reflection_health_linter.ss` |
| 测试基线 | `bin/ss test tests/phase5/` 159 PASS(D120 Phase 1 Done 后)|

### 禁止的 Context 操作

- ❌ 读 `bootstrap/pir/` / `bootstrap/gen/class/class.ss`(与本决策无关)
- ❌ 扫 runtime `ss_*` 反射路径(D117 后已无 sidecar)
- ❌ 触 SpringApplication / dispatcherServlet 实现(D122 Phase 3 范围)

---

## 2. Tool System

### 必备工具

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| Claude 内置 | `Read` / `Edit` / `Grep` / `Bash` | 文件操作 |
| 项目构建 | `./build.sh bootstrap` | 固定点验证(stage2==stage3)|
| 度量 gate | `bin/ss run tools/reflection_health_linter.ss` | 14 指标 + F1 行数 baseline 比对 |
| RED 证据 | `ls docs/3-decisions/D121-*.md`(Plan) / `grep "args: Map" prelude.ss`(Execute R1) / 试编 `@Ann(k=v)` probe(Execute R2)| 现 Plan 轮 RED,Execute 轮兑现 |
| 测试 | `bin/ss test tests/phase5/` | comptime 回归 |

### 禁止引入

- ❌ 新 AST kind(NAMED_ARG 已存在,复用即可)
- ❌ 新关键字 / 新 lexer token(ASSIGN / COLON 都已存在)
- ❌ 新 Meta 类型(只动 AnnotationMeta 内部字段)
- ❌ 双 API Array<string> + Map<string,string>(违反原则 4)

---

## 3. Execution Orchestration

### 总体节奏

本 D121 范围:**R1 + R2 双根因独立 Execute 轮**,每轮一个独立 commit,互不相依(可任意顺序,但建议 R2 先行 —— parser 通了才能给 R1 输入命名参数)。

### Phase 2a (Execute 1): R2 注解参数 parser 扩展

- **决策锚点**:§决策 2 — COLON 复用 or ASSIGN 新增(见附录 A.3 替代方案对比)
- **若选 COLON 复用(推荐)**:**零代码改动 parser**,annotation 路径已经走 `parseArgs`(`parser.ss:257`),`parseArgs` 已识别 COLON NAMED_ARG → parser 侧 R2 **Done by Inspection**
- **若选 ASSIGN 新增**:`parse_exprs.ss:570` 扩展 `kindAt(tPos + 1) == "COLON" || kindAt(tPos + 1) == "ASSIGN"`,pAdvance 后按 ASSIGN 跳 `=` token,其余逻辑同 COLON 分支;**或**仅在 `parseAnnotationList` 内部识别 ASSIGN(范围收紧到 annotation,避免污染函数调用 named arg 约定)
- **验证**:`@GetMapping(path="/x", method="GET")` 或 `@GetMapping(path: "/x", method: "GET")` parse 不报错;AST 节点 kind 均为 NAMED_ARG

### Phase 2b (Execute 2): R1 AnnotationMeta.args 形态升级 + ct `.get(key)` dispatch

- **决策锚点**:§决策 1 — 形态选择(见附录 A.3 替代方案对比)
- **入口 1 — prelude.ss:27**:`args: Array<string>` → `args: Map<string, string>`(或 `argsByName: Map<string, string>` + 保留 args,见 A.3 方案评估)
- **入口 2 — interp_obj.ss:136**:`buildAnnotationMetaArray` 循环读 `nGetList(aId)`:
  - 当前:`STRING_LIT` 直接 push args Array
  - 升级后:
    - **位置参数 STRING_LIT**:按 Java 惯例映射到 key `"value"`(单参)或 `"0"` / `"1"` / `"2"`(多参索引字符串化)
    - **NAMED_ARG**:`nGetS1(argId)` 读 name,`nGetI1(argId)` 读 value expr(STRING_LIT 取 S1;其他 kind 留后续支持或 comptimeError)
    - `interpMapSet(argsMap, key, interpNewString(val))` 写入
- **入口 3 — exprs_ct_builtin.ss:212**:`ctArrayMethod` 未支持 `.get`;形态升级后 `ann.args` 类型为 Map,访问走 `ctMapMethod`(L216-239)原生路径,**零新增 dispatch**
- **验证**:`tests/phase5/d121_annotation_named_args.ss` 最小 test:3 个 class 各带 `@Ann(key: "val")` / `@Ann("positional")`,ct 遍历 annotations 验证 `.get(k)` / `.get("value")`(单参映射)返回正确

### Phase 3 合流(非本 Plan 承接,D122 范围)

- `SpringApplication` + `dispatcherServlet` 实现 + `spring_web_params.ss` E2E GREEN → D122 独立承接

### 本 D121 执行范围锁定

**仅 Phase 2a + Phase 2b**,各自独立 commit(互不相依,任意顺序,建议 2a 先行)。D122 Spring Boot E2E 在 D121 双根因兑现后触发。

### 反模式

- ❌ 把 Phase 2a + 2b 合并单次 commit(破"每步独立验证")
- ❌ 顺手改 D122 SpringApplication 实现(越界)
- ❌ 引入 dual API args + argsByName(违反原则 4)
- ❌ 新建 AnnotationArgMeta 类型(违反 D120 §核心原则 2)
- ❌ Execute 2 阶段 NAMED_ARG value 非 STRING_LIT(如 INT_LIT)直接 silently skip,应 comptimeError 或明述留后续

---

## 4. State & Memory

### 关键 state

| 变量 | 文件 | 角色 |
|---|---|---|
| `AnnotationMeta.args` 类型 | `bootstrap/parse/prelude.ss:27` | R1 形态锚点(Array<string> → Map<string,string>)|
| ANNOTATION node `nList` | `bootstrap/parse/parser.ss:262` | 注解 args AST 子节点 id csv,存 STRING_LIT / NAMED_ARG 混合 |
| NAMED_ARG node(S1=name, I1=valExpr)| `bootstrap/parse/parse_exprs.ss:575-577` | 命名参数 AST 节点,buildAnnotationMetaArray 读取入口 |
| `tvMap["${amId}\|args"]` | `bootstrap/eval/interp_obj.ss:140` | AnnotationMeta 实例 args 字段存储(TypedValue array id → Map id 转型)|
| `internPool "ANN\|<prefix>.<name>"` | `bootstrap/lexer/intern_pool.ss` | Phase B dedup key,R1 升级后 key 不变(ann name 维度)|

### 中间产物

- `bin/ss_stage1` / `stage2` / `stage3` — 固定点验证
- `tests/phase5/d121_annotation_named_args.ss` — 最小验证 test(Execute 2 产出)
- (Optional)`tests/phase5/d121_annotation_assign_syntax.ss` — Execute 1 ASSIGN 语法 probe(若选方案乙)

### 会话间持久化

- `git log` — 进度真相源
- 本文档附录 B — 实施日志(Execute 后追加)

### 禁止 state 操作

- ❌ 进度写 `.claude/next_prompt.md` 累积(per CLAUDE.md 硬约束)
- ❌ 新建第三份 annotation 注册表
- ❌ 改 InternPool `ANN|` key schema(Phase B 已稳定)

---

## 5. Evaluation & Observation

### 判据(Phase 2a + 2b Execute 后每 Step 完成必跑)

| # | 类型 | 命令 / 检查 | 通过条件 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | stage2==stage3 固定点通过 |
| 2 | 测试 | `bin/ss test tests/phase5/` | 不新增 fail(D120 Execute 1 后 159 PASS baseline)|
| 3 | 收敛 | `grep -rn "args: Map\|argsByName" bootstrap/parse/prelude.ss` | Phase 2b 后 ≥ 1 命中 |
| 4 | 行为(R2)| Execute 1 完成后试编 `@Ann(k: "v")` 或 `@Ann(k="v")`(按决策 2)probe | parse 不报错,AST NAMED_ARG 正确生成 |
| 5 | 行为(R1)| `bin/ss run tests/phase5/d121_annotation_named_args.ss` | 输出命名参数值(如 `path=/search`)|
| 6 | 度量 | `bin/ss run tools/reflection_health_linter.ss` | GATE PASS + M1/M2/M3a/M4/M5/M7b 结构组不升(新增函数需 Step 0 预削减抵消)|
| 7 | 根因 | `grep "@comptimeEmit\|comptimeEmitString" bootstrap/` | 不新增 workaround 调用 |
| 8 | 向后兼容 | D120 Phase 1 已有 test `tests/phase5/d120_reflect_classes.ss` 仍 GREEN | 原 `ann.args[0]` / iteration 行为未破 |

### 回归信号(任一出现 = 立即停下)

- ⚠ bootstrap 固定点失败(stage2 != stage3)
- ⚠ linter GATE BLOCKED(任一结构组指标高于 baseline)
- ⚠ `d120_reflect_classes.ss` 或其他 phase5 测试新增 fail
- ⚠ 引入 dual API / 新 Meta 类型(违反原则 4 / D120 §核心原则 2)

### spot check

```bash
# R1 形态升级:args 类型已改
grep -n "args:" bootstrap/parse/prelude.ss | grep AnnotationMeta -A 1

# R2 parser:ASSIGN or COLON named arg 识别
grep -n "ASSIGN\|COLON" bootstrap/parse/parse_exprs.ss | head

# ct .get dispatch 路径验证
grep -n 'method == "get"' bootstrap/gen/exprs/exprs_ct_builtin.ss
```

---

## 6. Constraints & Recovery

### 硬约束(违反 = 立即回滚)

- CLAUDE.md §Root Cause 优先:禁止 workaround,同 workaround 第二次出现必须停下修根因
- CLAUDE.md §反射根因 gate:触碰反射路径必须跑 linter,任一物理指标高于 baseline 阻断 commit
- D088 §反模式 L377-386:禁 @comptimeEmit / ct* 白名单扩展 / @derive 字符串拼接 handler
- D120 §核心原则 2:不新建第六类 Meta
- feedback_dual_entry_is_dual_track:args 形态单一,不 Array + Map 双轨
- feedback_no_ugly_syntax:优先复用 SS 既有 NAMED_ARG COLON 语法
- feedback_600_split_not_inline:改动不致任何文件超 ≤ 600 baseline(纯字段类型改 + 小扩展,LOC 增量 < 50)

### 失败模式 + 恢复

| 信号 | 恢复 |
|---|---|
| Phase 2b 固定点失败(interp_obj.ss 逻辑 regression)| `git reset --soft HEAD^` → 检查 `buildAnnotationMetaArray` 循环对位置 STRING_LIT 的 key 映射是否破坏 |
| Phase 2a 扩展 ASSIGN 后函数调用 named arg 意外生效(越界)| 限定到 `parseAnnotationList` 内部识别,`parseArgs` 主干保持 COLON only |
| `ann.args[index]` 旧行为破坏(Phase 2b 后)| 位置参数映射回"0"/"1"/"2" key,保留 `args["0"]` / `args.get("0")` 等价语义;或在 A.3 锁定兼容方案 |
| linter 结构组 REGRESSION | 先削减后推进(Step 0 模式,D111 §步骤 0 模板)|
| NAMED_ARG value 非 STRING_LIT | comptimeError `unsupported annotation arg value kind: ${kind}`,留 D121+ 或独立决策扩展 |

### 回滚策略

- 任何 Step 失败 → `git reset --soft HEAD^`
- 禁止"先 commit 再修"
- Phase 2b 启动前必须 Phase 2a 完整兑现(若走 ASSIGN 方案乙);若走 COLON 方案甲,2a Done by Inspection 无代码改动 → 可直接进 2b

---

# 附录 A: 决策细节

## A.1 问题

D120 附录 B §Execute 1 收尾实测证据通过四条 probe(A/B/C/D)把 D120 §A.4 #2 "args 形态 Phase 2 阻塞" 单点推演分解为两条实测根因:

- **R1**:`ann.args.get("value")` stdout `[comptime] unsupported array method: get` — `AnnotationMeta.args: Array<string>` 类型上不支持 `.get(key)` dispatch,ctArrayMethod(`exprs_ct_builtin.ss:212`)无 `.get` 入口
- **R2**:`@GetMapping(path="/search", method="GET")` stdout `parse error at line X: expected RPAREN, found ASSIGN '='` — `parseArgs`(`parse_exprs.ss:556-587`)NAMED_ARG 分支(L570)只接受 `IDENT + COLON`,不接受 `IDENT + ASSIGN`

**单参位置参数已 Done**:Probe A(`ann.args[0]`)+ Probe C(`for arg in ann.args`)GREEN(D120 Execute 1 Phase 1 ct-array unroll 泛化覆盖)。

**盲点结构**:R1 和 R2 是同一个 Spring Boot 根因路径的"存储形态 + 输入语法"两面 —— Java `@GetMapping(path="/x")` 经 parse 后 AST 结构 → interp_obj 构造 AnnotationMeta.args → 用户代码 `ann.args.get("path")` 访问,三级链路任一环缺失 Spring Boot 注解驱动路由都不能根因兑现。

## A.2 决策(§决策 1-3)

### §决策 1 — `AnnotationMeta.args` 形态升级(R1)

**当前**:`args: Array<string>` @ `prelude.ss:27`;ct 访问 `args[i]` / `for arg in args` GREEN;ct 访问 `args.get(key)` RED(`unsupported array method`)。

**选择锚点**:见 A.3 方案评估表 **R1-A / R1-B / R1-C**。**推荐 R1-A**(单一 Map<string,string>,位置参数按 Java 惯例单参 → `"value"`,多参 → `"0"/"1"/"2"` 索引字符串化,保持 `args.get("0")` / `args.get("value")` 一致形态)。

**实现**(假定 R1-A):

```ss
// bootstrap/parse/prelude.ss:25-28
class AnnotationMeta {
    name: string
    args: Map<string, string>   // ← 升级:Array<string> → Map<string,string>
}

// bootstrap/eval/interp_obj.ss:123-144 (buildAnnotationMetaArray 核心改造)
function buildAnnotationMetaArray(annListId: int, annPoolPrefix: string): int {
    // ... 原 outer 结构保持
    const argsMap = interpNewMap("")   // ← Array → Map
    let positionalIdx = 0
    let positionalCount = countPositionalArgs(aId)
    for (arp in nGetList(aId).split(",")) {
        const argId = parseInt(arp)
        if (argId <= 0) { continue }
        const k = nGetKind(argId)
        if (k == "STRING_LIT") {
            // 位置参数:单参映射 "value",多参索引字符串化
            const key = positionalCount == 1 ? "value" : `${positionalIdx}`
            interpMapSet(argsMap, key, interpNewString(nGetS1(argId)))
            positionalIdx = positionalIdx + 1
        } else if (k == "NAMED_ARG") {
            const name = nGetS1(argId)
            const valId = nGetI1(argId)
            if (nGetKind(valId) == "STRING_LIT") {
                interpMapSet(argsMap, name, interpNewString(nGetS1(valId)))
            } else {
                // Phase 2b 范围收紧:非 STRING_LIT value 留后续,当前 comptimeError
                comptimeError(`unsupported annotation arg value kind: ${nGetKind(valId)}`)
            }
        }
        // 其他 kind 跳过(保持向后兼容)
    }
    tvMap.set(`${amId}|args`, `${argsMap}`)
    // ...
}
```

**集成点**:ct 访问 `ann.args.get(key)` 自然走 `ctMapMethod`(`exprs_ct_builtin.ss:216-239`)`.get` 入口,**零新增 dispatch**。

**兼容性**:`ann.args[0]` 升级后等价 `ann.args.get("0")` —— SS Map 支持 `m[k]` 语法取值?**Execute 轮必查**(若不支持 → `ann.args[0]` 破坏,需同步改 D120 已有 test `d120_reflect_classes.ss` 或修 Map 索引语法)。

### §决策 2 — 注解参数 parser 语法(R2)

**选择锚点**:见 A.3 方案评估表 **R2-A / R2-B / R2-C**。**推荐 R2-A**(复用 COLON NAMED_ARG,零 parser 改动,SS 与 TypeScript 风格一致)。**若用户期望 Java 风格**,选 R2-B(ASSIGN 扩展,范围限定 `parseAnnotationList`)。

**实现**(假定 R2-A):

- **零代码改动**。`parseAnnotationList` @ `parser.ss:257` 已调 `parseArgs`,`parseArgs` @ `parse_exprs.ss:570` 已识别 `IDENT + COLON` NAMED_ARG。`@GetMapping(path: "/search", method: "GET")` 开箱可 parse
- 用户代码形态:`@GetMapping(path: "/search", method: "GET")`(与 Spring Boot Java `@GetMapping(path="/search", method="GET")` 等价语义,SS 风格标点差异)

**实现**(假定 R2-B):

```ss
// bootstrap/parse/parse_exprs.ss:556-587 (parseArgs 扩展,或新建 parseAnnotationArgs 范围收紧)
function parseArgs(): string {
    // ... 原结构保持
    } else if (curKind() == "IDENT" &&
              (kindAt(tPos + 1) == "COLON" || kindAt(tPos + 1) == "ASSIGN")) {
        const naName = curValue()
        pAdvance()
        pAdvance()   // skip COLON or ASSIGN
        const valId = parseExpr()
        const naId = newNode("NAMED_ARG")
        nSetS1(naId, naName)
        nSetI1(naId, valId)
        args = listAppend(args, naId)
    }
    // ...
}
```

**范围权衡**:
- **扩 parseArgs 主干**:函数调用 `foo(k=v)` 也生效 → 污染函数调用约定,Java/TS 函数都不用 ASSIGN named arg
- **范围收紧到 annotation**:新建 `parseAnnotationArgs()` 或在 `parseAnnotationList` 内部临时切换 ASSIGN 开关 → parser 双轨,feedback_dual_entry_is_dual_track 风险

### §决策 3 — ct `.get(key)` dispatch(R1 配套)

**形态升级自然兑现**:R1 形态为 Map<string,string> 后,`ann.args.get(key)` ct 路径走 `ctMapMethod`(`exprs_ct_builtin.ss:216-239`)原生 `.get` 入口,**零新增 dispatch**。

若选 R1-C(dual API 保留 Array<string> args + 新增 argsByName Map)→ 需在 ctArrayMethod 加 `.get(index): string` 支持(L212 unsupported 扩),双路径增加 M7b 预算。**不推荐**。

---

## A.3 替代方案对比 + 隐藏假设挑战(Plan 型 VCM ④ 替换)

### R1 方案评估 — AnnotationMeta.args 形态

| # | 方案 | 描述 | 取舍 | 推荐度 |
|---|---|---|---|---|
| **R1-A** | **单一 Map<string,string>,位置参数按 Java 惯例**(单参→"value" / 多参→"0"/"1"/"2") | args 形态统一,Java Spring Boot `ann.args.get("value")` 直接工作;位置参数 `ann.args[0]` 升级为 `ann.args.get("0")`(若 SS Map 不支持 `m[k]` 索引语法,此方案破 D120 已有 test 兼容)| 单一形态,feedback_dual_entry_is_dual_track 合规;Spring Boot 语义贴合 Java 惯例;需查 SS Map 索引语法 | **推荐** |
| R1-B | 单一 Map<string,string>,位置参数**不支持**(只要求命名参数)| 形态最干净,只要求用户全写命名参数 `@GetMapping(value="/x")` 不写 `@GetMapping("/x")` | 破坏 D120 已有 `@RequestMapping("/api")` 位置参数用法 + Spring Boot 约定(`@RequestMapping("/api")` 实质是 `value="/api"` 隐式赋值),**不推荐** | 不推荐 |
| R1-C | **dual API**:保留 `args: Array<string>`(位置)+ 新增 `argsByName: Map<string,string>`(命名)| 向后 100% 兼容;Spring Boot 混合形态(位置 + 命名)直接工作 | **违反** feedback_dual_entry_is_dual_track 原则;**违反** 原则 4 单一形态;**违反** D120 §核心原则 2 扩展精神(args + argsByName 就是形态双轨);两个字段同义不同名,rename 迁移又起一轮 | **拒绝** |

### R2 方案评估 — 注解参数语法

| # | 方案 | 描述 | 取舍 | 推荐度 |
|---|---|---|---|---|
| **R2-A** | **COLON 复用 `@Ann(k: "v")`** — SS 既有 NAMED_ARG 语法 | **零代码改动**;parser 已识别;SS 与 TypeScript decorator 风格一致(TS 装饰器参数用 object literal `@Ann({k:"v"})` 同语义等价);feedback_no_ugly_syntax / feedback_no_new_keywords 合规 | 用户从 Java 迁移心理成本:`=` → `:`;Spring Boot 文档示例需标注 SS 方言 | **推荐** |
| R2-B | **ASSIGN 新增 `@Ann(k="v")`** — 范围限定 annotation(新建 parseAnnotationArgs)| Java/Spring 用户零心理成本;parser 双轨但范围隔离(不污染函数调用 named arg 约定)| 新增 parser 分支(+ ~10 LOC);parser 双轨 feedback_dual_entry_is_dual_track 风险(尽管范围限定);JavaScript/TypeScript 生态无此语法 | 可选(用户偏好) |
| R2-C | ASSIGN 扩展 parseArgs 主干 | parser 改动最小;函数调用 `foo(k=v)` 也生效 | **污染函数调用约定**;Java/TS 函数都不用 ASSIGN named arg;破坏 SS `foo(k: v)` 一致性 | **拒绝** |

### 隐藏假设挑战

1. **假设**:SS Map 支持 `m[k]` 索引语法访问。**挑战**:若不支持 → R1-A 升级后 `ann.args[0]` 必须改为 `ann.args.get("0")`,破坏 D120 已有 test `d120_reflect_classes.ss` 兼容(若该 test 有 `args[0]` 访问)。**验证**:Execute 轮第一步 `grep -n 'args\[' tests/phase5/d120_reflect_classes.ss` + `grep -n "m\[key\]\|map\[key\]\|Map.*\[" bootstrap/`,确认 SS 是否有 Map 索引语法;若无 → 同步改 D120 test 或评估 Map 索引语法补齐(独立 D 文档,不属 D121 范围)

   **迁移路径**(2026-04-21 实测追补,Plan 轮 5 族 INDEX_ACCESS grep + D120 test `args[` 核验 + `ann.args` 全库使用点扫描):

   - **5 族 INDEX_ACCESS 实测分布**:
     - Lexer:`LBRACKET`/`RBRACKET` token 已发射(`bootstrap/lexer/lexer.ss:72-73`)
     - Parser:`INDEX_ACCESS` 节点构造 `nSetI1=obj / nSetI2=idx`(`bootstrap/parse/parse_exprs.ss:199`)
     - Checker:`bootstrap/checker/check_exprs.ss:218-236` 仅对 **class 实例**非 STRING_LIT dynamic field name 报错(`dynamic field name on class 'X'`),**Map 对象不进此 branch**,通行无障
     - Comptime eval:`bootstrap/eval/index_access.ss:11` 明确分派 `ot == "object" || ot == "map"` → `interpGetField(objP, interpAsStr(payload(idx)))` —— **Map `m[k]` comptime 已支持**,按 string-key 查
     - Runtime codegen:`bootstrap/gen/exprs/exprs_simple.ss:42-65` `genIndexAccess` 仅两分支 — class 实例 field(`emitFieldLoad`)+ 一律 `ss_arrayGet` —— **runtime Map 分派缺失**
   - **D120 兼容核验**:`grep "args\[" tests/phase5/d120_reflect_classes.ss` 0 命中;该 test(24 行)仅遍历 `reflect.classes()` 读 `c.name`,不触 `ann.args` 任何形态 → **R1-A 升级对 D120 已有 test 零破坏**
   - **全库 `ann.args` 使用点**:`grep -rn "ann\.args" tests/ bootstrap/ lib/` 0 命中(除 D 文档自身)→ D120 Phase 1 Done 之后暂无真实用户代码消费 args,D121 Execute 2 新建的 `d121_annotation_named_args.ss` 是首个消费者,兼容面干净
   - **综合结论**:SS Map 索引语法 **comptime 支持 / runtime 未支持**,假设 #1 在 R1-A 所需的 **comptime 路径维度** = **真**
   - **对 R1-A 的影响**:
     - D121 §核心原则 5 "所有 `ann.args.get(...)` 访问必须在 comptime block 内展开" → runtime 未支持**不影响** R1-A 可行性
     - R1-A 升级后 comptime 访问 `ann.args["path"]`(STRING_LIT key)走 `ot==map` 分支 → `interpGetField(argsMap, "path")` 自然兑现
     - R1-A 升级后 comptime 访问 `ann.args[0]`(INT_LIT key)依赖 `interpAsStr(payload(idx))` 对 int `0` 是否字符串化为 `"0"` —— 若是 → 自动命中 R1-A 位置参数 key `"0"/"1"/...`,旧 Array 语义 `args[0]` 等价保留;若否 → 用户需写 `args.get("0")`,或 R1-A 位置 key 随 `interpAsStr(INT)` 实际形态调整。**Execute 2 轮动作项 (a)**:`grep -n "function interpAsStr" bootstrap/eval/` 读实现或 comptime probe `{ const m=new Map(); m.set("0","x"); return m[0] }` 实测
     - 不在 D121 范围:runtime 路径 `genIndexAccess` 对 Map 的分派补齐(需加 `inferType startsWith "Map<"` 走 `ss_map_get`)—— D122 Spring Boot 路由若需要 runtime Map 索引访问则另起独立 D 文档(D126+?)承接;D121 Phase 2b comptime-only 范围**不依赖** runtime Map 索引
   - **结论落地**:假设 #1 挑战被实测**化解**,原"若无 → 同步改 D120 test 或评估 Map 索引语法补齐(独立 D 文档)"路径 **不触发** —— D120 test 不触 args 不需改 / Map 索引语法在 comptime 维度已具备不需独立 D 文档。Execute 2 遗留单点:`interpAsStr(INT)` 字符串化行为(动作项 (a))
2. **假设**:`buildAnnotationMetaArray` 升级后 args InternPool dedup(`ANN|<prefix>.<name>` key)不破。**挑战**:R1-A 形态从 Array tvId → Map tvId,`tvMap["${amId}|args"]` 值类型变,但 key schema 未变 → InternPool dedup 仍按 ANN 名维度工作,不受影响。**验证**:Execute 2 后跑 reflection_health_linter M3b(ANN pool dedup 计数)确认
3. **假设**:`@RequestMapping` 单参映射到 `"value"` key 符合 Java 惯例 + Spring Boot 用户期望。**挑战**:部分注解的位置参数不叫 `value`,如 `@Autowired` 无参、`@Qualifier("beanName")` 位置参数是 `value`(Java spec)—— 大部分情况确实叫 `value`,但存在反例(罕见)。**对策**:R1-A 方案接受"单参 → value" 惯例,罕见反例留独立 edge case D 文档;对反例注解用户可写 `@Custom(actualKey="val")` 显式命名
4. **假设**:多参位置参数映射 `"0"/"1"/"2"` 索引字符串化不与命名参数 key 冲突。**挑战**:若用户写 `@Ann("a", "b", k: "c")`,按 R1-A 会生成 `{"0": "a", "1": "b", "k": "c"}` → 混合形态可行,但若用户命名参数 key 取名 "0" / "1" 会冲突。**对策**:Execute 轮在 buildAnnotationMetaArray 内检测 key 冲突,comptimeError `annotation arg name conflicts with positional index "0"`;用户极少用数字字符串作 key,实际冲突近乎不会出现
5. **假设**:`tests/phase5/d120_reflect_classes.ss`(D120 Execute 1 test)当前不访问 `ann.args` —— 是的,D120 test 只遍历 `cls.name`,未触 args,所以 R1-A 升级不影响 D120 test 兼容。**验证**:Execute 2 前 `grep -n "args" tests/phase5/d120_reflect_classes.ss` 确认
6. **假设**:Execute 2 升级 `buildAnnotationMetaArray` 会触发反射 baseline linter 的 M 组/N 组指标变化。**挑战**:此函数在 interp_obj.ss(eval family),不在反射统计口径内 / 在(待实测);Map tvId 分配可能增 M7b / N4(TypedValue 容器计数)。**对策**:Step 0 预削减 M7b ≥ -1 抵消 1 个新函数 / 新 Map 分配 + Execute 2 后跑 linter 确认无 REGRESSION

---

## A.4 单一判据兜底

Execute Phase 2a(R2)完成后:
- `@GetMapping(path: "/x")`(方案 R2-A)或 `@GetMapping(path="/x")`(方案 R2-B)试编 parse 不报错
- `./build.sh bootstrap` → stage2 == stage3 固定点
- `bin/ss test tests/phase5/` → 不新增 fail
- (方案 R2-B)`grep -n "ASSIGN" bootstrap/parse/parse_exprs.ss` ≥ 1 扩展命中

Execute Phase 2b(R1)完成后:
- `grep -rn "args: Map\|args: Map<string" bootstrap/parse/prelude.ss` ≥ 1 命中
- `bin/ss run tests/phase5/d121_annotation_named_args.ss` → GREEN,验证 `ann.args.get("path")` / `.get("value")` / `.get("0")` 多种访问形态
- `grep -n 'NAMED_ARG' bootstrap/eval/interp_obj.ss` ≥ 1 命中(buildAnnotationMetaArray 读 NAMED_ARG 入口)
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS + 结构组 M3b/M4/M6/M7a/M7b/N4/N5 不升
- D120 已有 test `d120_reflect_classes.ss` 仍 GREEN(向后兼容)

Phase 3(D122 范围)单一判据不本 Plan 承载。

---

# 附录 B: 实施日志

### Plan(起草轮) [x] Done at 2026-04-21

- 2026-04-21:起草 D121 Plan,范围锁定 R1(AnnotationMeta.args Array→Map 形态升级)+ R2(注解参数 parser 命名语法)双根因,每轮独立 Execute。R3(iteration/index)已 Done 不承接,D120 Phase 1 ct-array unroll 泛化覆盖
- 依据 D120 附录 B §Execute 1 收尾实测证据 L474-540 Probe A/B/C/D 实测分解,相比 D120 §A.4 #2 单点推演给出更精准的三支根因划分
- A.3 替代方案对比:R1 推荐方案 A(单一 Map + Java 惯例),R2 推荐方案 A(COLON 复用 零代码改动);R1-C dual API 拒绝(dual_entry_is_dual_track),R2-C ASSIGN 主干扩展拒绝(污染函数调用约定)
- 隐藏假设 6 条:SS Map 索引语法 / InternPool dedup 不破 / Java 单参"value"惯例 / 数字 key 冲突 / D120 test 不触 args / 反射 baseline M7b 预算

### Execute 1(Phase 2a): R2 注解参数 parser 命名语法 [ ] Planned

- 待用户确认方案(R2-A COLON 复用 / R2-B ASSIGN 新增 范围限定 annotation)
- R2-A:零代码改动 Done by Inspection,直接验证 `@Ann(k: "v")` parse 通过
- R2-B:扩展 `parseAnnotationArgs`(新建)或 parseArgs 限定分支,接 ASSIGN 作 NAMED_ARG 等价入口

### Execute 2(Phase 2b): R1 AnnotationMeta.args 形态升级 + ct `.get(key)` dispatch [ ] Planned

- 待用户确认方案(R1-A Map + Java 惯例 推荐 / R1-B 单一 Map 放弃位置 / R1-C dual API 已拒绝)
- R1-A:`prelude.ss:27` Array<string> → Map<string,string>;`interp_obj.ss:123-144` buildAnnotationMetaArray 循环读 NAMED_ARG / 位置映射 value|0|1|2
- 新建 `tests/phase5/d121_annotation_named_args.ss` 最小 test
- 反射 linter M7b Step 0 预削减抵消新函数

### Phase 3 [→] Deferred to D122

- D122 范围:`SpringApplication` + `dispatcherServlet`(`lib/spring/boot/`)+ `tests/phase5/spring_web_params.ss` E2E GREEN
- 触发点:本 D121 Phase 2a + 2b 双根因兑现后,Spring Boot 注解路由编译期展开全链路通

---

## 反模式 / 正模式

### ❌ 反模式
- args dual API(Array<string> + Map<string,string>)违反 feedback_dual_entry_is_dual_track
- 新建 AnnotationArgMeta 第六类 Meta 违反 D120 §核心原则 2
- ASSIGN 扩展污染 parseArgs 主干(破坏 SS / TS / Java 函数调用 named arg 一致性)
- 位置参数 `@RequestMapping("/api")` 放弃支持(破 Spring Boot Java 惯例 + D120 已有 test 兼容)
- `@comptimeEmit` 字符串拼接生成(D088 §过渡策略 2 冻结)
- runtime 反射 API(D088 §不做的事)
- Phase 2a + 2b 合并单轮 Execute(破每步独立验证)

### ✅ 正模式
- args 单一形态 Map<string,string>,位置参数按 Java 惯例单参→"value" / 多参→"0"/"1"/"2"
- 注解参数命名语法复用 SS COLON NAMED_ARG(TypeScript decorator 风格,零 parser 改动)
- ct 访问 `ann.args.get(key)` 走 ctMapMethod 原生 `.get`,零新增 dispatch
- R1 / R2 双根因各自独立 commit,用户可分轮确认方案
- NAMED_ARG value 非 STRING_LIT 当前 comptimeError,留独立 D 文档扩展

---

## 参考

- D088 §第一性需求 L7-13 / §反模式 L377-386 / §不做的事 L312-318 / §过渡策略 L304-310
- D120 附录 B §Execute 1 收尾实测证据 L474-540(R1/R2/R3 实测分解)/ §决策 2 L329-337(暂缓通道)/ §核心原则 2(不新建 Meta)
- D117 §决策 1-2(五类 Meta + `buildAnnotationMetaArray`)
- D098 §决策 2 §Phase B(InternPool ANN key dedup)
- D094 §规则 2(comptime pure subset)
- D095 §决策(annotation handler,不改)
- `bootstrap/parse/prelude.ss:25-28`(AnnotationMeta 形态锚点)
- `bootstrap/parse/parser.ss:247-267`(parseAnnotationList)
- `bootstrap/parse/parse_exprs.ss:556-587`(parseArgs 含 NAMED_ARG COLON)
- `bootstrap/eval/interp_obj.ss:123-144`(buildAnnotationMetaArray)
- `bootstrap/gen/exprs/exprs_ct_builtin.ss:180-239`(ctArrayMethod + ctMapMethod)
- CLAUDE.md §反射根因 gate / §交互式单文档 / §PFV 流程
- `memory/feedback_no_workaround.md` / `feedback_dual_entry_is_dual_track.md` / `feedback_no_ugly_syntax.md` / `feedback_ultrathink_gate.md`
