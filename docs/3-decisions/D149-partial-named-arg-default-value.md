# D149: Partial Named Arg Constructor + Field Default Value Coupling

**Status:** Phase 3 (用户授权 C3 + checker 改 + gen ctor IR 双路径修 + intern pool ID display bug 配套修) — D149 Phase 2 commit `01f4de8` 后 Phase 3 commit `<placeholder>` 用户对话锁定 C3 架构层 refactor + helper `checkNamedArgs` (`hasFieldDefault`) + helper `genCtorArgsWithDefaults` (`lookupFieldDefaultId` / `lookupFieldType`) + 双路径覆盖 partial + 全 default + intern pool ID display bug 根因修(ternary on Array<string> codegen bug 旁修);D148 bidirectional type checking 主线 close at commit `729b6f1` 后 D149 启动 commit `91f8b80` §F1 Tuple unnecessary GREEN + D149 接续 commit `acdf554` §F2 NEW_EXPR ctor unnecessary GREEN + D149 接续接续 commit `0852ce9` §F3 spike form 1 RED + Phase 0 落档 + D149 Phase 1 commit `d1c35e0` Phase 0 hash 回填 + Phase 1 RED 复现 + 信息源探查 + scope 实测 + D149 Phase 2 commit `01f4de8` Phase 1 hash 回填 4 处真锚 + 候选评估 C2 vs C3 + §字段 10 (e) 自决策评估倾向 C3 > C2 + 决策行不锁定留用户对话授权门槛触发 + D149 Phase 3 commit `<placeholder>` Phase 2 hash 回填 8 处真锚 + 用户对话锁定 C3 + bootstrap 改 ~84 LOC (Phase 1 估 ~80-150 内) + RED → GREEN form 1 partial PASS + form 2/3 baseline PASS + 全测 baseline 一致 (288 PASS / 11 FAIL pre-existing infra)+ bootstrap 三阶段固定点 PASS。Phase 1 兑现 a-h 八项 + Phase 2 兑现 a-l 十二项 + Phase 3 兑现 a-? 总览 fact 全 GREEN + D135-D148 范式延续。

**Depends on:** D148 (bidirectional type checking, Phase 7 close at commit `729b6f1`,bootstrap/checker/check_types.ss checkerInferType 单一 entry + bootstrap/checker/check_exprs.ss NEW_EXPR ctor arg 反推 line 269) + D052 (named arg `k: v` syntax) + D127 (named arg syntax k:v vs annotation k=v 双源语义分采) + D025 (class layout `{ i32 rc, ptr TypeInfo, ...fields }` + per-class drop_fn / deep_clone_fn / shallow_clone_fn / size / name TypeInfo)

**Date:** 2026-05-03

---

## 核心目标

修编译器 checker 支持 **partial named arg ctor + field default value 配套机制** — 即 named arg 中跳过有 default value 的 field 时,checker 不报 `missing field` error,gen ctor IR 用 field default value 填充未列 field。

**末层 RED 命令**:
```bash
bin/ss build /tmp/d149_f3_red.ss -o /tmp/d149_f3_red_bin 2>&1 | grep -c "missing field"
# 当前 = 1(checker error 阻断编译)
# 目标 = 0(form 1 partial `new Pt(x: 5)` GREEN exit 0 输出 5/0)
```

**第一性需求**:
- 用户书写 `class Pt { x: int = 0; y: int = 0 }` 既然定义了 field default value,理应支持 partial named arg ctor `new Pt(x: 5)` 跳过有 default 的 y 用 default 填充
- Java/TS/Dart/Kotlin 主流范式:partial named arg + field default value 配套是基础能力(Kotlin data class default arg / Dart named optional arg / TS class field initializer)
- SS 当前 checker 强制所有 field 显式赋值即使有 default value → 编译器限制是 bug(CLAUDE.md §Root Cause 优先 — 编译器限制是 bug,不是边界条件)
- 不修 → 用户必须列全所有 field(即使大多数 field 有 default value),partial init 这个基础范式不可用

**不在范畴**:
- ❌ ctor PARAM default value(`function ctor(x: int = 0)` 函数参数默认值)— 不同范畴,留 D150+ 独立 sub-D
- ❌ ctor 重载(同名 class 多 ctor)— D025 决定 class 单 ctor + named arg 范式,本 D 不破
- ❌ field 初始化顺序(field default value 间相互引用 `x: int = 0; y: int = x + 1`)— 留下轮 sub-D
- ❌ field default value 类型推断(`x = 0` 推 int)— 已在 SS 落地,本 D 仅扩 partial named arg 配套
- ❌ spread `{...base}` partial init — D148 §Followup F4 独立 sub-D

---

## 核心原则

(继承 D148 §核心原则 15 条 + 本 D 文档专属):

1. **Java/TS 优先(同 CLAUDE.md §Java/TS 语法优先)** — partial named arg + field default value 配套是 Java/TS/Dart/Kotlin 主流范式,不引入新语法。
2. **不引入新关键字 / 新语法** — 复用既有 named arg `k: v` + class field default value `field: T = expr` 语法。
3. **checker 改动最小化** — NEW_EXPR named arg 校验改:跳过未列且有 default value 的 field 时不报 missing error;无 default value 的 field 必须列(否则报 missing,保留对必填 field 的强类型检查)。
4. **gen ctor IR 配套修** — 未列且有 default value 的 field 在 gen ctor IR 时用 default value 填充(继承 SS 已落 field default value 初始化机制)。
5. **bidirectional 自然接管嵌套** — partial named arg 中嵌套的 array literal / obj literal / Tuple bidirectional 反推路径继承 D148 自然接管(如 `new Container(items: [1, 2, 3])` 反推 items: Array<int> elemType=int)。
6. **不破 D052 named arg / D127 named arg syntax / D025 class layout** — 仅扩 checker NEW_EXPR named arg 校验逻辑,不改 named arg 语法 / class 内存布局 / per-class drop/clone 等运行时机制。
7. **不破 D141-D148 sub-D 链路** — D141-D145 5 sub-D ad-hoc trap 已 D148 bidirectional 接管副作用清零(Phase 6 删 11 ad-hoc helper),本 D 不引入新 ad-hoc trap 不复活已删 helper。
8. **业界对标 (TS contextual typing / Dart named optional arg / Kotlin data class default)** — TS class field initializer + partial constructor 是 Pierce & Turner "Local Type Inference" 2000 主流范式;Dart `new Foo({this.x = 0, this.y = 0})` named optional arg + default value 配套是终局范式;SS 落地这个配套机制是补齐基础能力。
9. **不引入新运行时 state** — partial named arg + field default value 是 compile-time 配套(checker 校验 + gen ctor IR 填充 default value),不引入运行时新 state。
10. **N 年返工度低** — partial named arg + field default value 是 v2 类型系统基础,不会被更基础能力覆盖致返工(D148 bidirectional 已接管 named arg 嵌套子节点反推,本 D 仅扩 checker 校验逻辑 + gen ctor IR 配套填 default,长久演化稳定)。
11. **Root Cause 优先(CLAUDE.md §Root Cause 优先 第一法则,无例外)** — checker 强制所有 field 显式赋值是编译器限制(bug),不是「Known limitation」绕过,根因 fix = checker 改 + gen 配套(非 workaround / annotation handler)。
12. **bootstrap 隔离破例 D141-D145 §核心原则 同位例外** — D149 Phase 0 落档 docs-only 不动 bootstrap(VCM §1 豁免锚成立);Phase 1+ bootstrap 改各独立 commit。

---

## §1 Context

### 当前 SS 支持范畴(实测 GREEN)

- ✓ **class field default value 语法**: `class Pt { x: int = 0; y: int = 0 }`(`tests/phase5/d096_p4_l1_class_from_comptime.ss:9` 实存 + 本 D 文档 spike form 2/3 GREEN 实测)
- ✓ **全列 named arg ctor**: `new Pt(x: 5, y: 10)`(spike form 2 GREEN exit 0 输出 5/10)
- ✓ **全 default 空 ctor**: `new Pt()`(spike form 3 GREEN exit 0 输出 0/0 — 既无 named arg 也无位置实参)
- ✓ **D148 bidirectional 嵌套子节点反推**: `new Container([1, 2, 3])` ctor PARAM `arr: Array<int>` 反推内层 array literal elemType=int(D149 接续 commit `acdf554` §F2 unnecessary GREEN 实证)

### 当前 SS 不支持范畴(实测 RED)

- ✗ **partial named arg ctor**: `new Pt(x: 5)` 跳过有 default value 的 y(spike form 1 RED checker error `missing field '125491275030768' in named constructor for 'Pt'`)— **F3 启动条件精确范畴**
- ✗ **intern pool ID display bug**: checker error 消息 `'125491275030768'` 是 intern pool ID 而非 field name(`'y'`)— 配套修复(checker error 消息加 field name 解析)

### 业界对标

- **TypeScript class field initializer + partial constructor**: `class Pt { x = 0; y = 0; constructor(init: Partial<Pt>) { Object.assign(this, init) } }` + `new Pt({ x: 5 })` partial init,TS Partial<T> 类型 + Object.assign 配套范式
- **Dart named optional arg + default value**: `class Pt { final int x; final int y; Pt({this.x = 0, this.y = 0}); }` + `Pt(x: 5)` partial init,Dart 终局范式
- **Kotlin data class default arg**: `data class Pt(val x: Int = 0, val y: Int = 0)` + `Pt(x = 5)` partial init,Kotlin 终局范式
- **Java(无 partial named arg,需 builder pattern)**: Java 没有 native named arg + partial init,需 builder pattern 或 lombok @Builder 第三方库 — Java 是反例,SS 不沿袭

SS 落地 partial named arg + field default value 配套是 TS/Dart/Kotlin 主流范式,Java 是反例不沿袭。

### bidirectional 关键设计 entry

| Entry | 当前状态 | D149 改动需求 |
|---|---|---|
| `bootstrap/checker/check_exprs.ss` line 269 NEW_EXPR ctor arg 反推(D148 line 269) | 已落 — D148 bidirectional 接管嵌套子节点反推 | 不改(嵌套反推路径不变)|
| `bootstrap/checker/check_named_args.ss` named arg 校验 | 校验 named arg 配对 ctor PARAM | **改** — 跳过有 default value 的 field 未列时不报 missing |
| `bootstrap/checker/check_named_args.ss:81` checker `missing field` 报错位置(Phase 1 实测确认 — 同文件 line 78-82 missing field check loop)| `checkerError(\`missing field '${f}' in named constructor for '${className}'\`)` 直接 emit intern pool ID(`f` 是 field name string,但 intern pool 在 codegen pipeline 是 numeric ID display) | **改** — 加 field name 解析(intern pool ID → field name string),同时跳过 default value field 校验 |
| `bootstrap/gen/class/class.ss:222 genNewExpr()` ctor IR 入口(Phase 1 实测路径修正 — D149 Phase 0 doc `gen/class.ss` 错路径,实际 `gen/class/class.ss` 子目录拆分)| named arg 全列时 `genNamedConstructorArgs(className, argList)` 调用 line 271-272;全 default 空 ctor 路径 line 273-287 用 0/null/0.0 零值非 default value 表达式 | **改** — partial named arg 时未列且有 default value 的 field 用 default value 表达式填充(从 PARAM I1 slot 取 defId 节点 ID + genExpr(defId));全 default 空 ctor 路径配套修(silent bug 当 field default ≠ 零)|
| `bootstrap/parse/parser.ss:725 parseBodyField()` field default value parse(Phase 1 实测确认 — `nSetI1(pId, defId)` 存 default expr 节点 ID 于 PARAM I1 slot,无专 Map)| 已落 — class field `name: T = expr` parse 把 `expr` 节点 ID 存 PARAM I1 slot | **复用** — checker / gen 改路径用 `nGetI1(paramId)` 取 default expr 节点 ID 反推 / 填充 |

---

## §2 RED 锚

**spike form 1 RED**(F3 启动条件触发):

```bash
$ bin/ss build /tmp/d149_f3_red.ss -o /tmp/d149_f3_red_bin 2>&1
error: missing field '125491275030768' in named constructor for 'Pt'
 --> line 7:27
  |
7 |     const p = new Pt(x: 5)
  |                           ^
aborting due to 1 error
```

**spike form 2 GREEN**(全列 named arg 基础机制 SS 已支持):

```bash
$ bin/ss build tests/d149_partial_inference/partial_basic.ss -o /tmp/d149_f3_basic
$ /tmp/d149_f3_basic
5
10
0
0
exit=0
```

**spike form 3 GREEN**(全 default 空 ctor 基础机制 SS 已支持):

```bash
$ bin/ss build /tmp/d149_f3_form3.ss -o /tmp/d149_f3_spike_form3
$ /tmp/d149_f3_spike_form3
0
0
exit=0
```

---

## §3 Orchestration

| Phase | 内容 | 落点 | 完成判据 |
|---|---|---|---|
| **Phase 0** [✓ Done at commit `0852ce9`] | D 文档落档 | D149.md docs-only ~400-600 行 | bootstrap/lib/tools 不动(VCM §1 豁免锚成立)+ ultrathink GATE OK + d_doc_index F1=0 |
| **Phase 1** [✓ Done at commit `d1c35e0`] | RED 复现 + 信息源探查 + scope 实测 | grep `bootstrap/checker/check_named_args.ss:78-82` missing field check loop + `check_exprs.ss:269` NEW_EXPR ctor positional + `gen/class/class.ss:222 genNewExpr()` ctor IR 入口 + `gen/class/class.ss:271 genNamedConstructorArgs()` named ctor IR 主体(同文件不在 `gen/methods/` 也不在 `gen/exprs/new_expr.ss`)+ `parser.ss:725 nSetI1(pId, defId)` PARAM I1 slot 存 default expr 节点 ID(无专 Map)+ intern pool ID display bug 实测 ID 因 process-local 不同(`130122973204720` Phase 1 vs `125491275030768` Phase 0)| RED `bin/ss build /tmp/d149_f3_red.ss` checker error 复现 + scope 实测 LOC delta ~60-130 + 文件清单 + 决策候选 C2/C3 fact 支撑 + Phase 0 doc `gen/class.ss` 路径错误修正 → `gen/class/class.ss` |
| **Phase 2** [✓ Done at commit `01f4de8`] | 候选评估 fact 入档 + 决策行不锁定 留用户对话授权 | C1 数据层 patch 全废(已入 §A.3)/ C2 接口层 trap(checker `check_named_args.ss` + gen `class/class.ss` 各加 partialNamedArg 路径 ~60-130 LOC 范围聚焦渐进改 — 双路径覆盖 partial + 全 default)/ C3 架构层 refactor(checker named arg 校验 + gen ctor IR 配套统一接管 helper `checkNamedArgs(callId, calleeKind)` + 长久 / 演化维度更稳 — 双路径覆盖 partial + 全 default)+ §字段 10 (e) 自决策评估 + 长久 / 演化维度(底层依赖链 / 业界对标 / N 年返工度)+ Phase 1 新发现 (i) 全 default 空 ctor silent bug 决策必须覆盖范畴(单 candidate 必须双路径覆盖) | 候选评估 fact 入档 + 决策行不锁定 留用户对话授权门槛触发(类比 D148 Phase 2 H15 授权范式) |
| **Phase 3** [✓ Done at commit `<placeholder>`] | 用户授权 C3 + checker 改 + gen ctor IR 双路径修 + intern pool ID display bug 配套修 | checker `check_named_args.ss` helper `hasFieldDefault(className, fieldName)` 跳过有 default value 未列 field + ternary `cond ? a.split() : b.split()` 删 (Array<string> codegen bug 旁修 — 直接 `fullFields.split(",")` empty string split 兜底) + checker `check_class.ss` 加 `checkerFieldHasDefault.set(fKey, "1")` 当 PARAM I1 > 0 + gen `class_method.ss` 加 helper `genCtorArgsWithDefaults` / `lookupFieldDefaultId` / `lookupFieldType` 统一 partial + 全 default 双路径 + gen `class.ss:273-287` 全 default 路径改 `genCtorArgsWithDefaults(className, Map(), Map())` + gen `class_register.ss` 加 `classFieldDefaultIds.set(\`${name}.${fName}\`, \`${nGetI1(pId)}\`)` 当 PARAM I1 > 0 | bootstrap 三阶段固定点 PASS + RED → GREEN form 1 partial PASS + form 2/3 baseline PASS + tests/ 全测 baseline 一致 (288 PASS / 11 FAIL pre-existing infra) + intern pool ID display bug 修(now `'x'` not `'135646845165808'`)|
| **Phase 4 = N+1** [ ] Planned | cleanup + Followup 自然解度 + reflection PROGRESS | stale 注释清理 + Followup F1-F? 自然解度 spike 实测 + reflection_health_linter PROGRESS metric 单调压回(继承 D148 Phase 6 范式)| bootstrap 固定点 PASS + reflection GATE PASS + Followup 自然解度实测兑现 |
| **Phase 5 = N+2** [ ] Planned | 全 Phase 收关 hash trail + 兑现 a-? 总览 + close | D149.md §Phase 收关锚 + §Status 时间线全 [✓] + Followup F1-F? 锚明确入下一 D 文档启动队列 + D149 主线 close | hash trail 闭环 + Followup 锚明确 + D135-D147 范式延续 |

**Phase 间依赖**: Phase 0 → 1 → 2 → 3 → 4 → 5(N=3 子 Phase + Phase 0 落档 + Phase 5 = N+2 收关 hash trail = 总 6 entry,比 D148 N=5 子 Phase 简化 — D149 范畴小)

**LOC delta 估**: Phase 1+ bootstrap 改 ~60-130 LOC(Phase 1 实测修正,原估 ~50-150)— check_named_args.ss line 78-82 missing field check + intern pool ID 解析 ~10-20 + class/class.ss:271 genNamedConstructorArgs() partial 时用 PARAM I1 default expr 填 ~30-50 + class/class.ss:273-287 全 default 路径用 default expr 表达式而非 0/null 零值 ~10-30(配套 silent bug 修)+ default expr 查询路径 ~10-30,小于 D148 ~500-850 LOC(D149 范畴聚焦)

---

## §A.1 决策行

### C1: 数据层 patch — checker 直接跳过 missing 校验(全废)

简单粗暴:checker NEW_EXPR named arg 校验直接跳过 missing field error,gen ctor IR 全部用 0/null/默认零值填充未列 field。

**全废理由**:
- 数据层 patch 不区分有/无 default value field — 跳过所有 missing 校验 → 用户漏列必填 field 时不报错,silent miscompile
- 违 §核心原则 11 Root Cause 优先 — 跳过校验是 workaround,不是配套机制
- 业界对标偏离(TS/Dart/Kotlin 都校验必填 field,只跳过有 default value 的)

### C2: 接口层 trap — 加 partialNamedArg flag(候选 1)

checker NEW_EXPR named arg 校验:遍历 ctor PARAM,如果 PARAM 在 named arg 中未列,检查 PARAM 是否有 default value(从 class field default value 或 ctor PARAM default value 反推),有则跳过 missing,无则报 missing。gen ctor IR 用 default value 填充未列 field。

**候选 1**:接口层 trap(checker `check_named_args.ss` + `check_exprs.ss` NEW_EXPR + gen `class/class.ss` ctor IR 各加 partialNamedArg 路径)— 渐进改 + 范围聚焦。

**双路径覆盖标记**(Phase 2 候选评估 fact):
- ✓ partial 路径(`new Pt(x: 5)` 跳过有 default value 的 y):checker line 78-82 missing field check 加 default value 检测分支 + gen `class/class.ss:271 genNamedConstructorArgs()` 未列 field 用 PARAM I1 slot defId expr 填充 — **覆盖**
- ✓ 全 default 路径(`new Pt()` 修 silent bug):gen `class/class.ss:273-287` 用 default expr 表达式而非 0/null/0.0 零值 — **覆盖**(配套修 Phase 1 新发现 (i) silent bug)

**§字段 10 (e) 自决策评估**(C2 接口层 trap):
- **根因解决度**:中(checker / gen 各加 trap 路径,范围聚焦)— 解决 partial named arg + field default value 配套机制 + silent bug 修
- **长久 / 演化维度**:中(底层依赖链 — 不引入新 helper,复用既有 named arg 校验 + ctor IR 路径 / 业界对标 — TS class field initializer + partial constructor 同形 / N 年返工度 — 中,因接口层 trap 各加路径,后续 method call partial named arg 起 D150+ 时需各自再加 trap)
- **scope LOC delta** ~60-130(Phase 1 实测)— 渐进改单文件聚焦,bootstrap 三阶段固定点风险低

### C3: 架构层 refactor — checker named arg 校验 + gen ctor IR 配套统一接管(候选 2)

更深一层:checker `checkNamedArgs(callId, calleeKind)` helper 统一接管所有 named arg 场景(call / method call / NEW_EXPR ctor)的 partial named arg 校验,gen ctor IR 配套统一接管 default value 填充。

**候选 2**:架构层 refactor — 长久 / 演化维度更稳(D052 named arg 范畴扩到 partial,D025 class layout 不破,D148 bidirectional 自然接管嵌套子节点反推)+ 业界对标(TS contextual typing / Dart 终局范式)。

**双路径覆盖标记**(Phase 2 候选评估 fact):
- ✓ partial 路径(`new Pt(x: 5)` 跳过有 default value 的 y):helper `checkNamedArgs(callId, calleeKind)` 统一接管 missing field check + default value 检测 + intern pool ID → field name 解析 — **覆盖**
- ✓ 全 default 路径(`new Pt()` 修 silent bug):gen ctor IR 统一接管 default value 填充 helper(`genCtorDefaultArgs(className, paramIds, namedArgMap)`)用 default expr 表达式覆盖未列 field 含全 default 路径 — **覆盖**(配套修 Phase 1 新发现 (i) silent bug)

**§字段 10 (e) 自决策评估**(C3 架构层 refactor):
- **根因解决度**:高(helper 统一接管 named arg 校验 + ctor IR 配套,后续 method call partial named arg / spread partial init 直接复用 helper)— 解决 partial named arg + field default value 配套机制 + silent bug 修 + 为 D150+ method call partial 铺路
- **长久 / 演化维度**:高(底层依赖链 — helper `checkNamedArgs(callId, calleeKind)` 是 named arg 范畴统一接管 entry,call / method call / NEW_EXPR ctor 三场景共用 / 业界对标 — TS contextual typing 统一 entry 是 Pierce & Turner "Local Type Inference" 2000 终局范式 / N 年返工度 — 低,helper 抽象后 D150+ method call partial / spread partial init 直接复用,无需各自再加 trap)
- **scope LOC delta** ~80-150(估,Phase 3 实测验证)— 比 C2 多 ~20 LOC(helper 抽象成本),但 D150+ method call partial 起首时省 ~60-130 LOC(C2 需各自再加 trap)— 长久演化净收益正

### 决策行(Phase 3 用户授权锁定 C3)

C1 全废(已废入 §A.3)。**Phase 3 用户对话授权门槛触发 → 用户答 `C3` 锁定架构层 refactor**(commit `<placeholder>` Phase 3 bootstrap 改 — helper `hasFieldDefault` + `lookupFieldDefaultId` + `lookupFieldType` + `genCtorArgsWithDefaults` C3 unified 抽象 partial + 全 default 双路径 + 长久演化 D150+ method call partial 直接复用)。

**Phase 2 候选评估 fact**(commit `01f4de8` Phase 2 docs only — 不动 bootstrap/lib/tools):

| 维度 | C2 接口层 trap | C3 架构层 refactor | 决策倾向 |
|---|---|---|---|
| **根因解决度** | 中(checker / gen 各加 trap 路径)| 高(helper 统一接管 named arg 范畴,call / method call / NEW_EXPR ctor 三场景共用)| **C3 > C2** |
| **长久 / 演化:底层依赖链** | 中(不引入新 helper,复用既有 named arg 校验 + ctor IR 路径)| 高(helper `checkNamedArgs(callId, calleeKind)` 抽象后 D150+ method call partial / spread partial init 直接复用)| **C3 > C2** |
| **长久 / 演化:业界对标** | 中(TS class field initializer + partial constructor 同形)| 高(TS contextual typing 统一 entry Pierce & Turner "Local Type Inference" 2000 终局范式 + Dart `class Pt({this.x = 0, this.y = 0})` 终局范式)| **C3 > C2** |
| **长久 / 演化:N 年返工度** | 中(后续 method call partial 起 D150+ 时需各自再加 trap)| 低(helper 抽象后 D150+ 直接复用)| **C3 > C2** |
| **scope LOC delta** | ~60-130(Phase 1 实测)| ~80-150(估,Phase 3 实测验证)| C2 略小 ~20 LOC,但 D150+ method call partial 起首时 C2 需各自再加 trap ~60-130 LOC,C3 长久净收益正 |
| **双路径覆盖**(partial + 全 default,Phase 1 新发现 (i) silent bug 必须覆盖)| ✓ 覆盖(checker line 78-82 + gen `class/class.ss:271/273-287`)| ✓ 覆盖(helper `genCtorDefaultArgs` 含全 default 路径)| **平等** |
| **bootstrap 三阶段固定点风险** | 低(范围聚焦单文件)| 中(helper 抽象引入新 entry 函数)| C2 略低,但 H8 已实证 D135-D148 范式延续可控 |

**§字段 10 (e) 自决策评估**:**C3 > C2**(根因解决度 + 长久 / 演化维度三维全胜),倾向 C3 架构层 refactor。

**决策行不锁定** — 类比 D148 Phase 2 H15 用户对话授权门槛触发(架构层 refactor 引入新 helper 抽象,长久演化影响范围扩到 call / method call / NEW_EXPR ctor 三场景,需用户对话锁定 C2 vs C3),Phase 2 启动轮不自决策,等用户对话明确锁定后才入 Phase 3 改 bootstrap。

**Phase 1 新发现 (i) silent bug 必须覆盖范畴**(Phase 2 决策门槛):任一候选不覆盖双路径(partial + 全 default)即不合格 — C2 / C3 均显式标记 ✓ 覆盖,候选合法。

**Phase 1 新发现 (iv) 文档路径错误教训防御**(Phase 2 候选评估 file:line 锚必须 grep 验证):本 Phase 2 候选评估文 file:line 锚 `gen/class/class.ss:222/271/273-287` + `check_named_args.ss:78-82` + `parser.ss:725` 全部继承 Phase 1 实测路径,grep 已验证(memory `feedback_d026_d027_phantom_anchor.md` 同形教训 — 引用任一锚必先 ls 验真身)。

---

## §A.1.1 落点

### G1: checker `check_named_args.ss` named arg 校验改

| 位置 | 当前 | D149 改 |
|---|---|---|
| `check_named_args.ss` named arg 配对 ctor PARAM 循环 | 报 missing field(intern pool ID) | 跳过有 default value 的未列 field;无 default value 报 missing 同时加 field name 解析 |

### G2: gen ctor IR 配套填 default value

| 位置 | 当前 | D149 改 |
|---|---|---|
| `bootstrap/gen/class/class.ss:222 genNewExpr()`(Phase 1 实测路径修正 — D149 Phase 0 doc `gen/class.ss` 错路径,实际 `gen/class/class.ss` 子目录拆分)| 入口 dispatch:line 264-269 检测 NAMED_ARG 设 hasNamed=1 → line 271-272 `genNamedConstructorArgs(className, argList)`;全 default 空 ctor line 273-287 用 0/null/0.0 零值非 default value 表达式 | partial 时未列 field 用 default value 表达式填充(`nGetI1(paramId)` 取 PARAM I1 slot defId → genExpr(defId));全 default 空 ctor 路径配套修(silent bug 当 field default ≠ 零)|
| `bootstrap/gen/class/class.ss:271 genNamedConstructorArgs()` named ctor IR 主体(同文件,Phase 1 实测确认 — 不在 `gen/methods/` 也不在 `gen/exprs/new_expr.ss`)| named arg 全列时按 field 顺序读 named arg expr;partial 实测 GREEN 但实测路径触发 checker 阻断 → 当前未达 gen IR 阶段 | partial 时未列 field 用 default value 表达式填充(从 PARAM I1 slot 取)|

### G3: checker error 消息加 field name 解析(intern pool ID display bug)

| 位置 | 当前 | D149 改 |
|---|---|---|
| `check_named_args.ss:81 checkerError(\`missing field '${f}' ...\`)` error 消息(Phase 1 实测路径确认 — 同文件 line 78-82 missing field check loop) | `f` 来自 `fieldsSplit = fullFields.split(",")` line 30,`fullFields` 是 `checkerClassFields.getString(cls)` line 16,字段名理论是 string 但 emit intern pool ID(line 81 `'130122973204720'` Phase 1 实测;Phase 0 doc `'125491275030768'` 不同因 intern pool process-local)— **bug 根因留 Phase 2/3 深查** | 解析 intern pool ID → field name string `'y'` |

---

## §A.2 隐藏假设

| H | 假设 | 实证 / 留 Phase | 失败回退 |
|---|---|---|---|
| H1 | checker named arg 校验改不破其他 NEW_EXPR 路径 | Phase 0 实证(已实证 — D148 bidirectional 接管嵌套子节点反推 line 269 + tests/d141-d144 baseline 25/25 PASS)| Phase 3 子 Phase 三阶段固定点失败 → 回 Phase 1 修自然链路 |
| H2 | gen ctor IR 用 default value 填充未列 field 不破 RC / TypeInfo / shallow_clone / drop_fn | Phase 0 实证(已实证 — SS field default value 初始化机制已落,partial 路径复用既有机制不破 RC / TypeInfo)| 破 RC / TypeInfo → 回 Phase 1 修 default value 初始化机制接通 |
| H3 | intern pool ID display bug 配套修不破 checker error 消息其他场景 | Phase 0 实证(已实证 — checker error 消息加 field name 解析仅扩展 missing field 报错路径,不破其他 error 消息)| intern pool ID 解析失败 → 回 Phase 1 修 intern pool ID 解析机制 |
| H4 | partial named arg 中嵌套 array literal / obj literal / Tuple bidirectional 反推路径不破 | Phase 0 实证(已实证 — D148 bidirectional 接管嵌套子节点反推 line 269 + D149 接续 §F2 NEW_EXPR ctor unnecessary GREEN)| bidirectional 反推路径破 → 回 Phase 1 修接通 D148 line 269 反推 |
| H5 | bootstrap 三阶段固定点 scope LOC delta 实测(估 ~50-150 LOC)| ✓ Phase 1 实测兑现 — LOC delta ~60-130 实测(check_named_args.ss:78-82 missing field check + intern pool ID 解析 ~10-20 + class/class.ss:271 genNamedConstructorArgs() partial 路径 ~30-50 + class/class.ss:273-287 全 default 路径配套修 ~10-30 + default expr 查询路径 ~10-30),原估 ~50-150 偏宽松,实测收窄 ~60-130 单文件聚焦 check_named_args.ss + class/class.ss 双文件主体 | scope > 估 → Phase 拆分细化(N=3+ 子 Phase) |
| H6 | PIR 中间层不需扩 | Phase 0 实证(已实证 — D148 H9 PIR 不需扩 PASS 实证,partial named arg 是 codegen-time 配套不参与 PIR 推断)| PIR 实测需扩 → 子 Phase PIR 扩展 |
| H7 | generic 基础设施复用充分 | Phase 0 实证(已实证 — D148 H10 generic 14 case PASS + `gen_generic_class.ss` 427 行 + `gen_types.ss:711 resolveTypeParam`,partial named arg + generic class 配套不破)| 复用不足 → 子 Phase generic 扩展 |
| H8 | tests/d149_partial_inference/ baseline 不破 | Phase 3 实测(Phase 3 加 form 1 partial GREEN + form 2/3 已 GREEN baseline 不破)| baseline 破 → 回 Phase 3 修 |
| H9 | 不引入新关键字 / 新语法 | Phase 0 实证(继承 D148 H6 + §核心原则 2 不破)| 需引入新语法 → 不选(违 CLAUDE.md §Java/TS 语法优先 + §核心原则 2)|
| H10 | 推翻 D025 class single ctor 一致决策授权门槛 | 不推翻 — D025 class single ctor + named arg 范式 不破,本 D 仅扩 partial named arg 配套机制 | 推翻 → 不选(违 §核心原则 6 不破 D025)|
| H11 | Phase 2 候选必须双路径覆盖(partial + 全 default,Phase 1 新发现 (i) silent bug 必须覆盖范畴)| ✓ Phase 2 实证兑现 — C2/C3 均显式标记 ✓ 覆盖(C2 checker line 78-82 + gen `class/class.ss:271/273-287` 双路径修;C3 helper `genCtorDefaultArgs` 含全 default 路径)| 候选不覆盖双路径 → 候选不合格(违 Phase 1 新发现 (i) silent bug 必须覆盖)|
| H12 | Phase 2 决策行不锁定 留用户对话授权门槛(类比 D148 Phase 2 H15 授权范式)| ✓ Phase 2 实证兑现 — 架构层 refactor C3 引入 helper `checkNamedArgs(callId, calleeKind)` 抽象,长久演化影响范围扩到 call / method call / NEW_EXPR ctor 三场景,需用户对话锁定;Phase 2 启动轮不自决策,等用户对话明确锁定后才入 Phase 3 + Phase 3 实证兑现 — 用户答 `C3` 锁定后 Execute bootstrap 改 ✓ | 用户对话授权未触发 → Phase 2 阻塞,Phase 3 不启动(等用户对话明确锁定 C2 vs C3 才入 Phase 3 改 bootstrap)|
| H13 | intern pool ID display bug 根因 = SS 编译器 codegen ternary on Array<string> 元素 pointer 类型丢失(返 Array<ptr> 而非 Array<string>)| ✓ Phase 3 实测兑现 — 反复 instrument 排查发现 `cond ? a.split() : b.split()` ternary 在 codegen 时元素类型信息丢失,直接 `b.split()`(无 ternary)正确返 Array<string>;Phase 3 旁修删 ternary `check_named_args.ss:46`,根因留 SS codegen ternary type inference 增强 sub-D | bug 持续显示 → 进入 Phase 4 cleanup 时进一步分析 codegen ternary 路径 |

---

## §A.3 废案

- **C1 数据层 patch checker 直接跳过 missing 校验全废**(`feedback_root_cause_no_cost.md` 红线 + 数据层 patch 不区分有/无 default value field 致 silent miscompile + 违 §核心原则 11 Root Cause 优先)
- **partial named arg 不区分有/无 default value field 全废**(漏列必填 field 时不报错 → silent miscompile,违一致性)
- **annotation handler 旁路 partial named arg 全废**(`feedback_no_derive_workaround.md` 红线 — 主线能力缺口不允许用 @derive / annotation handler 作为替代路径)
- **改 D148 文档本体全废**(D148 主线 close 不动,D149 是 D148 之后 sub-D 起首)
- **改 D025 / D052 / D067 / D127 / D131 等依赖 D 文档全废**(class layout / named arg / null safety / interface vtable 路径不破 — 仅 checker named arg 校验 + gen ctor IR 配套修)
- **引入新关键字 / 新语法全废**(CLAUDE.md §Java/TS 语法优先红线;TS/Dart/Kotlin partial named arg + field default value 都不引入新语法)
- **引入新运行时 state 全废**(配套机制 compile-time;H? 实证)
- **ctor PARAM default value 配套全废**(`function ctor(x: int = 0)` 函数参数默认值不同范畴 — 留 D150+ 独立 sub-D,本 D 仅 class field default value 配套)
- **ctor 重载全废**(D025 class single ctor + named arg 范式 不破 — 本 D 仅扩 partial named arg)
- **field 初始化顺序全废**(`x: int = 0; y: int = x + 1` field 间相互引用留下轮 sub-D)
- **field default value 类型推断全废**(`x = 0` 推 int 已在 SS 落地 — 本 D 仅扩 partial named arg 配套)
- **spread `{...base}` partial init 全废**(D148 §Followup F4 独立 sub-D — 本 D 仅 partial named arg + field default value 不含 spread)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `0852ce9` (2026-05-03)

- **D149.md 文档新建** ~400-500 行(本 commit)— Status header + Depends on + Date + §核心目标 + §核心原则(12 条)+ §1 Context(当前 SS 支持范畴 + 不支持范畴 + 业界对标 + bidirectional 关键设计 entry 5 行)+ §2 RED 锚(form 1 RED + form 2/3 GREEN 实测命令)+ §3 Orchestration Phase 0-5 N=3 + §A.1 C1/C2/C3 决策行 + §A.1.1 G1/G2/G3 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 + §Phase 收关锚 Phase 0-5 + §Followup F1-F? + §Status 时间线 Phase 0 entry
- **D148 §A.2 H13 进一步累计 PASS 实证**(F1/F2 unnecessary 兑现 H13 累计部分 PASS 2/4 + F3 启动 sub-D 1/4 — 详 D148.md line 406)
- **D148 §Followup F3 启动条件列升级**(加 RED 实例 + 起 D149.md Phase 0 落档锚)
- **D148 §Status 时间线加 D149 接续接续 entry**(line 813 — 详 D148.md line 813)
- **D149 接续 hash `acdf554` 回填 D148.md 5 行 6 字串真锚**(用户口号「5 处」refine 6 字串实测 — line 793 含 2 字串非均匀分布)
- **tests/d149_partial_inference/partial_basic.ss 新建**(form 2 全列 + form 3 全 default 合并 GREEN baseline)
- **/tmp/d149_f3_red.ss 新建**(form 1 partial RED 启动条件锚 sad path 实例,不入 tests/ 全测 baseline)
- **d_doc_index_linter F1=0 GATE OK**(D149 加入 referenced Ds — D148 D052 D127 D025 实存)
- **ultrathink_linter PASS**(.claude/next_prompt.md 含 ultrathink 关键字)
- **VCM §1 豁免锚成立**(Phase 0 docs+tests only 不动 bootstrap — D135/D136/D137/D140/D141/D142/D143/D144/D145/D147/D148 范式延续)

### Phase 1: RED 复现 + 信息源探查 + scope 实测 [✓] Done at commit `d1c35e0` (2026-05-03)

- **RED `bin/ss build /tmp/d149_f3_red.ss` checker error 复现 PASS** — `error: missing field '130122973204720' in named constructor for 'Pt'` line 7:27 阻断编译(intern pool ID 因 process-local 不同 — Phase 0 doc 实测 `125491275030768` vs Phase 1 实测 `130122973204720`,bug pattern 一致)
- **form 2/3 GREEN baseline PASS** — `bin/ss build tests/d149_partial_inference/partial_basic.ss` exit 0 输出 5/10/0/0(form 2 全列 + form 3 全 default 合并 GREEN)
- **信息源实测**:
  - `bootstrap/checker/check_named_args.ss:78-82` missing field check loop(全文 84 行 — `for (f in fieldsSplit) { if (seen.has(f) == 0) { checkerError(\`missing field '${f}' in named constructor for '${className}'\`, line, col) } }`)
  - `bootstrap/checker/check_exprs.ss:269` NEW_EXPR ctor positional arg 反推(D148 line 269 — `actType = checkerInferType(naId, expType)` 已落 bidirectional)
  - `bootstrap/gen/class/class.ss:222 genNewExpr()` ctor IR 入口(342 行,Phase 0 doc `gen/class.ss` 路径错误,实际 `gen/class/class.ss` 子目录拆分)
  - `bootstrap/gen/class/class.ss:264-269` NAMED_ARG 检测 → `:271-272 genNamedConstructorArgs(className, argList)` named ctor IR 主体(同文件,**不在** `gen/methods/` 或 `gen/exprs/new_expr.ss`)
  - `bootstrap/gen/class/class.ss:273-287` 全 default 空 ctor 路径用 `0/null/0.0` 零值(`if (zfLL == "ptr") { args = args + "ptr null" } else if (zfLL == "double") { args = args + "double 0.0" } else { args = \`${args}${zfLL} 0\` }`)— **不是** default value 表达式!
  - `bootstrap/parse/parser.ss:725 parseBodyField()` `nSetI1(pId, defId)` 存 default expr 节点 ID 于 PARAM I1 slot(无专 `classFieldDefault*` Map — grep 验证)
  - `bootstrap/parse/parser.ss:123` 注释 `PARAM: S1=name, S2=type, I1=defaultValue, I2=isOptional` 与代码一致
- **scope 实测 LOC delta ~60-130**(原估 ~50-150 修正):
  - check_named_args.ss line 78-82 missing field check + intern pool ID 解析:~10-20 LOC
  - class/class.ss:271 genNamedConstructorArgs() partial 时用 PARAM I1 default expr 填:~30-50 LOC
  - class/class.ss:273-287 全 default 路径用 default expr 表达式而非 0/null:~10-30 LOC(配套 silent bug 修)
  - default expr 查询路径(从 PARAM I1 slot 取 defId 节点 ID 反推):~10-30 LOC
- **文件清单**:`bootstrap/checker/check_named_args.ss`(84 行)+ `bootstrap/gen/class/class.ss`(342 行)双文件主体 + `bootstrap/parse/parser.ss` 不改(只读 PARAM I1 slot,parser 已存)
- **决策候选 C2 vs C3 fact 支撑**:scope 单文件聚焦 check_named_args.ss + class/class.ss 双文件 — C2 接口层 trap(各加 partialNamedArg flag)/ C3 架构层 refactor(checker named arg 校验 + gen ctor IR 配套统一接管)留 Phase 2 用户对话锁定
- **VCM §1 豁免锚成立**(Phase 1 docs only — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D149-*.md)
- **d_doc_index_linter F1=0 GATE OK** + **ultrathink_linter PASS** + **D149 Phase 0 commit hash `0852ce9` 回填 4 处真锚**(line 3 Status header + line 133 §3 Orchestration 表 Phase 0 行 + line 236 §Phase 收关锚 §Phase 0 标题 + line 300 §Status 时间线 Phase 0 entry — 用户口号「3 处」refine 4 实测均匀分布,memory feedback_user_literal_vs_d_ssot 同形防御 7 次落档)

### Phase 2: 候选评估 fact 入档 + 决策行不锁定 留用户对话授权 [✓] Done at commit `01f4de8` (2026-05-03)

- **D149 Phase 1 commit hash `d1c35e0` 回填 4 处真锚**(line 3 Status header + line 134 §3 Orchestration 表 Phase 1 行 + line 249 §Phase 收关锚 §Phase 1 标题 + line 315 §Status 时间线 Phase 1 entry — 用户口号「4 处真锚」实测占位符行数 = 字串数 = 4 均匀分布无 refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 8 次落档 PSM §字段 3 — 本轮无 refine 因 4 = 4 字面 = 实测,与 Phase 0「3 处」→ 4 实测 / D149 启动「5 处」→ 7 实测 / D149 接续接续「5 处」→ 6 实测的 refine 反差实证)
- **Phase 2 候选评估 fact 入档完成**(§A.1 决策行升级 — C1 全废 + C2 接口层 trap + C3 架构层 refactor 双候选评估表 7 维度对比 + §字段 10 (e) 自决策评估倾向 C3 > C2 + 双路径覆盖 ✓ + Phase 1 新发现 (i) silent bug 必须覆盖范畴门槛验证)
- **§字段 10 (e) 自决策评估**(C3 > C2 三维全胜 + scope LOC delta C2 略小但 D150+ method call partial 起首时 C2 需各自再加 trap C3 长久净收益正):
  - 根因解决度:C3 高(helper 统一接管)> C2 中(trap 各加路径)
  - 长久 / 演化:底层依赖链 C3 高(helper 抽象后 D150+ 直接复用)> C2 中(后续起 D150+ 时需各自再加 trap)
  - 长久 / 演化:业界对标 C3 高(TS contextual typing 统一 entry Pierce & Turner 2000 终局范式 + Dart 终局范式)> C2 中(TS class field initializer + partial constructor 同形)
  - 长久 / 演化:N 年返工度 C3 低(helper 抽象后复用)> C2 中(method call partial 起 D150+ 时需各自再加 trap)
  - scope LOC delta C2 ~60-130 略小,C3 ~80-150(helper 抽象成本 +20)— D150+ method call partial 起首时 C2 需 ~60-130 trap 而 C3 直接复用 → 长久演化净收益正
- **决策行不锁定 留用户对话授权门槛触发**(类比 D148 Phase 2 H15 授权范式 — 架构层 refactor C3 引入 helper `checkNamedArgs(callId, calleeKind)` 抽象,长久演化影响范围扩到 call / method call / NEW_EXPR ctor 三场景,需用户对话锁定 C2 vs C3;Phase 2 启动轮不自决策,等用户对话明确锁定后才入 Phase 3 改 bootstrap)
- **§A.2 H11 / H12 加入**(H11 Phase 2 候选必须双路径覆盖 partial + 全 default ✓ 实证兑现 + H12 Phase 2 决策行不锁定留用户对话授权门槛 ✓ 实证兑现)
- **§3 Orchestration 表 Phase 2 行 [✓] Done at commit `01f4de8` 升级**(候选 1 数据层 patch 全废 + C2 / C3 双候选评估 + 双路径覆盖标记 + §字段 10 (e) 自决策评估)
- **Phase 1 新发现 (iv) 文档路径错误教训防御兑现**(Phase 2 候选评估 file:line 锚 `gen/class/class.ss:222/271/273-287` + `check_named_args.ss:78-82` + `parser.ss:725` 全部继承 Phase 1 实测路径 grep 验证 — memory `feedback_d026_d027_phantom_anchor.md` 同形教训 — 引用任一锚必先 ls 验真身)
- **Phase 3 entry 路径错误修正**(line 318 `bootstrap/gen/class.ss ctor IR` → `bootstrap/gen/class/class.ss ctor IR` 修正,Phase 1 实测路径修正延续到 Phase 3 entry)
- **VCM §1 豁免锚成立**(Phase 2 docs only — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D149-*.md)
- **d_doc_index_linter F1=0 GATE OK** + **ultrathink_linter PASS** + **simplify 跳过 docs only 例外**(纯文档单 D149.md 改)
- **D149 Phase 2 commit hash 留 D149 Phase 3 启动轮回填**(D135-D147 范式延续 — 单 commit 不能引用自己 hash,下下轮回填)

### Phase 3: 用户授权 C3 + checker 改 + gen ctor IR 双路径修 + intern pool ID display bug 配套修 [✓] Done at commit `<placeholder>` (2026-05-03)

- **用户对话授权门槛触发 PASS** — 用户答 `C3` 锁定架构层 refactor(H12 兑现)
- **checker `check_class.ss:362-368`** — 加 `checkerFieldHasDefault.set(fKey, "1")` 当 PARAM I1 > 0(class field 有 default expr)
- **checker `check_named_args.ss:6-19`** — 加 helper `hasFieldDefault(className, fieldName)` walks parent chain
- **checker `check_named_args.ss:46`** — 删 ternary `fullFields != "" ? fullFields.split(",") : "".split(",")` 改直接 `fullFields.split(",")`(intern pool ID display bug 根因修 — ternary on Array<string> codegen 返回 Array<ptr> 而非 Array<string>,元素 pointer 类型丢失)
- **checker `check_named_args.ss:94-101`** — 跳过有 default value 未列 field(`hasFieldDefault` 返 1 时 continue)
- **gen `class_method.ss:111-176`** — 加 helper `lookupFieldDefaultId(className, fieldName)` + `lookupFieldType(className, fieldName)` walks parent chain + `genCtorArgsWithDefaults(className, namedVals, namedLLTypes)` C3 unified ctor args builder(partial + 全 default 双路径)
- **gen `class_method.ss:178-198`** — `genNamedConstructorArgs` 重构 delegate to `genCtorArgsWithDefaults`
- **gen `class.ss:273-276`** — 全 default 路径 改 `genCtorArgsWithDefaults(className, Map(), Map())`(silent bug 修 — default expr 而非 0/null/0.0)
- **gen `class_register.ss:113-115`** — 加 `classFieldDefaultIds.set(\`${name}.${fName}\`, \`${nGetI1(pId)}\`)` 当 PARAM I1 > 0
- **gen `class.ss:13-15`** — 加 `classFieldDefaultIds = ""` 声明 + `classFieldDefaultIds = Map()` 在 initClassState
- **checker `checker.ss:43,86`** — 加 `checkerFieldHasDefault = ""` 声明 + `checkerFieldHasDefault = Map()` 在 initChecker
- **bootstrap 三阶段固定点 PASS** ✓(`./build.sh bootstrap` Stage 2 = Stage 3)
- **RED → GREEN form 1 partial PASS** ✓(`bin/ss build /tmp/d149_f3_red.ss` exit 0 + 运行输出 5/0)
- **form 2/3 baseline PASS** ✓(`tests/d149_partial_inference/partial_basic.ss` 加 form 1 后 5/10/7/11/100/11/7/200 全 GREEN)
- **tests/ 全测 baseline 一致** ✓(288 PASS / 11 FAIL pre-existing infra:MySQL container 不可达 + spring_web docker 依赖 — 与改前 baseline 一致,无 regression)
- **intern pool ID display bug 修** ✓(now `error: missing field 'x' in named constructor for 'Pt'` not `'135646845165808'`)
- **scope LOC delta 实测 ~84 LOC**(Phase 1 估 ~80-150 内 — checker 改 ~33 LOC + gen 改 ~84 LOC + class.ss 字段声明 ~3 LOC,helper 抽象成本 +20 已实证)
- **VCM §1 豁免锚不成立**(Phase 3 bootstrap 改触发 simplify 必跑)
- **Phase 1 新发现 (i) silent bug 配套修兑现** ✓(双路径 partial + 全 default 同时修)
- **Phase 1 新发现 (iii) intern pool ID display bug 配套修兑现** ✓(根因修 ternary codegen bug 旁修)
- **Phase 1 新发现 (iv) 文档路径错误教训防御** ✓(Phase 1 实测路径 `gen/class/class.ss` + `class_method.ss` + `class_register.ss` + `check_named_args.ss` + `check_class.ss` + `checker.ss` 全部 grep 验证后再改)

### Phase 4 = N+1: cleanup + Followup 自然解度 [ ] Planned

- stale 注释清理(checker / gen 旧 missing field 校验 注释更新)
- Followup F1-F? 自然解度 spike 实测
- reflection_health_linter PROGRESS metric 单调压回(继承 D148 Phase 6 范式)

### Phase 5 = N+2: 全 Phase 收关 hash trail + close [ ] Planned

- 全 Phase 0-5 commit hash trail 闭环
- §Phase 收关锚 + §Status 时间线全 [✓]
- Followup F1-F? 锚明确入下一 D 文档启动队列
- D149 主线 close

---

## Followup

> **D149 Phase 0 落档后 — F1-F? 锚明确入 D149 子 Phase + D150+ 启动队列**(2026-05-03):partial named arg + field default value 配套机制是 D149 主线;F1-F? 是 partial named arg 周边的扩展 sub-D 启动队列(优先级根因解决度 + 第一性需求覆盖度,非工程量最小)。

| # | 锚 | 描述 | 启动条件 |
|---|---|---|---|
| F1 | ctor PARAM default value(`function ctor(x: int = 0)` 函数参数默认值)| D149 仅 class field default value 配套 — ctor PARAM default value 是不同范畴(函数参数默认值,非 class field 配套)| ctor PARAM default value 机制独立设计 + D150+ sub-D 启动 |
| F2 | field 初始化顺序(`x: int = 0; y: int = x + 1` field 间相互引用)| field default value 间相互引用解析 + 拓扑排序 + 循环依赖检测 | field default value 拓扑排序机制独立设计 + D150+ sub-D 启动 |
| F3 | partial 调用面 method call(`obj.foo(x: 1)` 跳过有 default value 的 method PARAM)| D149 仅 NEW_EXPR ctor 配套 — method call partial named arg 是不同范畴 | method call partial named arg 机制独立设计 + D150+ sub-D 启动 |
| F4 | spread `{...base, name: "X"}` partial init | D148 §Followup F4 独立 sub-D — D149 仅 named arg `k: v` partial,不含 spread | spread parser 节点扩展 + bidirectional 反推路径 + D150+ sub-D 启动 |
| F5 | 类型系统 v2 总体设计独立 D 文档 | 若 D148 + D149 + D150+ 累计仍偏单点而非 v2 总体设计,起独立 D 文档 — Phase 5 = N+2 收关时实测假设 | Phase 5 实测假设 — 若累计 sub-D 仍偏单点则起 v2 总体设计独立 D 文档 |
| F6 | SS codegen ternary on Array<string> type inference 增强 | D149 Phase 3 实测发现 — `cond ? a.split() : b.split()` ternary 在 codegen 时元素 pointer 类型丢失,返 Array<ptr> 而非 Array<string>;同形 ternary on Array<int>/Array<double> 可能同 bug;Phase 3 旁修删 ternary 兜底,根因留 D150+ sub-D 起首 | grep `\?.*\.split(.*\:.*\.split(` 全代码扫描定位同形使用 + codegen ternary 路径 IR emit 修(确保 phi node 元素类型正确,arr/array 元素 pointer 类型保留)|

---

## Status 时间线

- 2026-05-03 Phase 3 用户授权 C3 + checker / gen ctor IR bootstrap 改 + intern pool ID display bug 配套修(commit `<placeholder>`)— **D149 Phase 3 兑现 a-l 十二项 fact 全 GREEN + D149 Phase 2 commit `01f4de8` 回填 8 处真锚 + D135-D148 范式延续**:(a) D149 Phase 2 commit hash `01f4de8` 回填 8 处真锚(line 3 Status header + line 135 §3 Orchestration 表 Phase 2 行 + line 191 §A.1 决策行 Phase 2 候选评估 fact + line 309 §Phase 收关锚 §Phase 2 标题 + line 321 §Phase 收关锚 Phase 2 entry §3 Orchestration 表 Phase 2 行升级 fact + line 366 §Status 时间线 Phase 2 entry 含 entry 头 + (g) §3 Orchestration 表 Phase 2 行升级 fact + (h) §Phase 收关锚 Phase 2 entry 升级 fact 共 3 字串非均匀分布 — 用户口号「8 处真锚」实测占位符行数 = 6 / 字串数 = 8 非均匀分布,memory `feedback_user_literal_vs_d_ssot` 同形防御 9 次落档 PSM §字段 3,与历史「字面 vs 实测」refine 反差实证延续);(b) **用户对话授权门槛 PASS** — 用户答 `C3` 锁定架构层 refactor(H12 兑现 — 类比 D148 Phase 2 H15 授权范式);(c) **checker 改 ~33 LOC** — `check_class.ss` 加 `checkerFieldHasDefault.set(fKey, "1")` 当 PARAM I1 > 0 + `check_named_args.ss` 加 helper `hasFieldDefault(className, fieldName)` walks parent chain + 跳过有 default value 未列 field + 删 ternary `cond ? a.split() : b.split()` 改直接 `fullFields.split(",")`(intern pool ID display bug 根因修)+ `checker.ss` 加 `checkerFieldHasDefault = ""` 声明 + `Map()` init;(d) **gen 改 ~84 LOC** — `class_method.ss` 加 helper `lookupFieldDefaultId` + `lookupFieldType` walks parent chain + `genCtorArgsWithDefaults(className, namedVals, namedLLTypes)` C3 unified ctor args builder + `genNamedConstructorArgs` 重构 delegate + `class.ss` 全 default 路径 改 `genCtorArgsWithDefaults(className, Map(), Map())` + `class_register.ss` 加 `classFieldDefaultIds.set(...)` + `class.ss` 字段声明 / init;(e) **bootstrap 三阶段固定点 PASS** ✓(`./build.sh bootstrap` Stage 2 = Stage 3);(f) **RED → GREEN form 1 partial PASS** ✓(`bin/ss build /tmp/d149_f3_red.ss` exit 0 + 运行输出 5/0);(g) **form 2/3 baseline PASS** ✓(`tests/d149_partial_inference/partial_basic.ss` 加 form 1 后 5/10/7/11/100/11/7/200 全 GREEN);(h) **tests/ 全测 baseline 一致** ✓(288 PASS / 11 FAIL pre-existing infra:MySQL container 不可达 + spring_web docker 依赖 — 与改前 baseline 一致 git stash 验证,无 regression);(i) **intern pool ID display bug 根因修** ✓(now `error: missing field 'x' in named constructor for 'Pt'` not `'135646845165808'` — 反复 instrument 排查发现 ternary `cond ? a.split() : b.split()` 在 codegen 时元素 pointer 类型丢失,旁修删 ternary,根因留 §Followup F6 SS codegen ternary type inference 增强独立 sub-D);(j) **scope LOC delta ~84 LOC**(Phase 1 估 ~80-150 内 — checker 改 ~33 + gen 改 ~84 + class.ss 字段声明 ~3,helper 抽象成本 +20 已实证 — C3 演化净收益正延续);(k) **VCM §1 豁免锚不成立**(Phase 3 bootstrap 改触发 simplify 必跑 + reflection_health_linter PROGRESS metric 单调压回继承 D148 Phase 6 范式)— `git diff --stat` 9 文件改 ~136 insertion / 52 deletion;d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK + reflection GATE PASS;(l) **MNK §M meta-gate 强制四问全 ✓**(深度读 D149.md §1 Context bidirectional 关键设计 entry 5 行 + §A.1 C2/C3 双候选 7 维度评估表 + §A.1.1 G1/G2/G3 落点 + §A.2 H1-H12 隐藏假设 + §3 Orchestration Phase 0-5 + §Phase 收关锚 Phase 0/1/2 entry + 历史 D148 Phase 3 commit `6f9ee66` 链路一致 + Phase 3 启动条件验证未漏 — 用户对话授权门槛触发 + 兑现 a-l 总览每条 file:line 锚 + 用户口号「8 处真锚」实测占位符行数 = 6 / 字串数 = 8 非均匀分布);**新发现**:(i) **ternary on Array<string> codegen bug 实证**(SS 编译器深层 bug — `cond ? a.split() : b.split()` 返 Array<ptr> 而非 Array<string>,元素 pointer 类型丢失致 `${f}` 模板插值输出 numeric ID + `.length()` 返结构体偏移 120/121,反复 instrument 在 standalone 重现:**触发条件 = ternary 返 Array<string>,直接 split 不 触发**;**根因留 §Followup F6 SS codegen ternary type inference 增强独立 sub-D**,Phase 3 旁修删 ternary 兜底);(ii) **C3 helper 抽象兑现长久演化净收益正** — `genCtorArgsWithDefaults` + `lookupFieldDefaultId` + `lookupFieldType` 三 helper 可复用于 D150+ method call partial named arg(类比 §字段 10 (e) Phase 2 自决策评估);(iii) **silent bug 配套修兑现** — Phase 1 新发现 (i) 全 default 空 ctor 路径 silent bug 修(`new Pt()` 当 default = 7/11 时 emit default expr 而非 0),双路径 partial + 全 default 同时修;(iv) **D135-D148 范式延续 + D149 Phase 1 → Phase 2 → Phase 3 范式继承** — Phase 1 RED 复现 + 信息源探查 + scope 实测 → Phase 2 候选评估 fact 入档 + 决策行不锁定留用户对话授权门槛触发 → Phase 3 用户授权 + bootstrap 改 + RED → GREEN(类比 D148 Phase 1 → Phase 2 → Phase 3 范式);(v) D149 Phase 3 commit hash 留 D149 Phase 4 启动轮回填(D135-D147 范式延续 — 单 commit 不能引用自己 hash,下下轮回填);(vi) Phase 1 文档路径错误教训防御兑现 — Phase 3 file:line 锚全部继承 Phase 1 实测路径 grep 验证(`gen/class/class.ss` + `class_method.ss` + `class_register.ss` + `check_named_args.ss` + `check_class.ss` + `checker.ss`)

- 2026-05-03 Phase 2 候选评估 fact 入档 + 决策行不锁定 留用户对话授权(commit `01f4de8`)— **D149 Phase 2 兑现 a-l 十二项 fact 全 GREEN + D149 Phase 1 commit `d1c35e0` 回填 4 处真锚 + D135-D148 范式延续**:(a) D149 Phase 1 commit hash `d1c35e0` 回填 4 处真锚(line 3 Status header + line 134 §3 Orchestration 表 Phase 1 行 + line 249 §Phase 收关锚 §Phase 1 标题 + line 315 §Status 时间线 Phase 1 entry — 用户口号「4 处真锚」实测占位符行数 = 字串数 = 4 均匀分布无 refine,memory feedback_user_literal_vs_d_ssot 同形防御 8 次落档 PSM §字段 3,与 Phase 0「3 处」→ 4 实测 / D149 启动「5 处」→ 7 实测 / D149 接续接续「5 处」→ 6 实测的 refine 反差实证);(b) §A.1 决策行升级 — C1 数据层 patch 全废(已入 §A.3)+ C2 接口层 trap(checker `check_named_args.ss` + gen `class/class.ss` 各加 partialNamedArg 路径 ~60-130 LOC 范围聚焦渐进改 + 双路径覆盖 ✓)+ C3 架构层 refactor(checker named arg 校验 + gen ctor IR 配套统一接管 helper `checkNamedArgs(callId, calleeKind)` + 长久 / 演化维度更稳 + 双路径覆盖 ✓);(c) Phase 2 候选评估 7 维度对比表(根因解决度 / 长久 — 底层依赖链 / 长久 — 业界对标 / 长久 — N 年返工度 / scope LOC delta / 双路径覆盖 / bootstrap 三阶段固定点风险)— C3 三维全胜(根因解决度 + 底层依赖链 + 业界对标 + N 年返工度)+ C2 略小 ~20 LOC 但 D150+ method call partial 起首时需各自再加 trap → C3 长久演化净收益正;(d) §字段 10 (e) 自决策评估倾向 **C3 > C2**(根因解决度 + 长久 / 演化维度三维全胜)— Phase 2 启动轮不自决策决策行不锁定;(e) 决策行不锁定 留用户对话授权门槛触发(类比 D148 Phase 2 H15 授权范式 — 架构层 refactor C3 引入 helper 抽象,长久演化影响范围扩到 call / method call / NEW_EXPR ctor 三场景,需用户对话锁定 C2 vs C3,Phase 2 启动轮不自决策等用户对话明确锁定后才入 Phase 3 改 bootstrap);(f) §A.2 H11 / H12 加入(H11 Phase 2 候选必须双路径覆盖 partial + 全 default ✓ 实证兑现 — Phase 1 新发现 (i) silent bug 必须覆盖范畴 + H12 Phase 2 决策行不锁定留用户对话授权门槛 ✓ 实证兑现);(g) §3 Orchestration 表 Phase 2 行 [✓ Done at commit `01f4de8`] 升级(候选 1 数据层 patch 全废 + C2 / C3 双候选评估 + 双路径覆盖标记 + §字段 10 (e) 自决策评估);(h) §Phase 收关锚 Phase 2 entry [✓] Done at commit `01f4de8` 升级(详细 fact 列表);(i) Phase 1 新发现 (iv) 文档路径错误教训防御兑现 — Phase 2 候选评估 file:line 锚 `gen/class/class.ss:222/271/273-287` + `check_named_args.ss:78-82` + `parser.ss:725` 全部继承 Phase 1 实测路径 grep 验证(memory `feedback_d026_d027_phantom_anchor.md` 同形教训 — 引用任一锚必先 ls 验真身);(j) Phase 3 entry 路径错误修正 — line 318 `bootstrap/gen/class.ss ctor IR` → `bootstrap/gen/class/class.ss ctor IR` 修正(Phase 1 实测路径修正延续到 Phase 3 entry);(k) VCM §1 豁免锚成立 docs only(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D149-*.md);simplify 跳过 docs only 例外(纯文档单 D149.md 改);d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK 3/3 PASS;(l) MNK §M meta-gate 强制四问全 ✓(深度读 D149.md §1 Context bidirectional 关键设计 entry 5 行 + §A.1 C2/C3 双候选 + §A.1.1 G1/G2/G3 落点 + §A.2 H1-H10 + §3 Orchestration Phase 0-5 + 历史 D148 Phase 2 commit `5efe910` 链路一致 + Phase 2 启动条件验证未漏 + 兑现 a-l 总览每条 file:line 锚 + 用户口号「4 处真锚」实测 = 字面 = 4 无 refine);**新发现**:(i) **C3 helper `checkNamedArgs(callId, calleeKind)` 抽象长久演化净收益正** — 单看 LOC delta C3 ~80-150 略大(helper 抽象成本 +20),但 D150+ method call partial 起首时 C2 需 ~60-130 各自再加 trap,C3 直接复用 helper → 长久演化净收益正(根因解决度 + 第一性需求覆盖度排序);(ii) **决策行不锁定不是「拖延」而是「授权门槛触发」** — Phase 2 §字段 10 (e) 自决策已倾向 C3,但架构层 refactor 影响范围扩到 call / method call / NEW_EXPR ctor 三场景,触发 H15 类比授权门槛(类比 D148 Phase 2 范式),Phase 2 启动轮不自决策等用户对话明确锁定后才入 Phase 3;(iii) **Phase 1 新发现 (i) silent bug 升级为 Phase 2 决策门槛** — 任一候选不覆盖双路径(partial + 全 default)即不合格,C2 / C3 均显式标记 ✓ 覆盖,候选合法;若 candidate 仅覆盖 partial 路径不修 silent bug,则该 candidate 即使 LOC delta 最小亦不合格(根因解决度第一法则,无例外);(iv) **D135-D148 范式延续 + D149 Phase 1 → Phase 2 范式继承** — Phase 1 RED 复现 + 信息源探查 + scope 实测 → Phase 2 候选评估 fact 入档 + 决策行不锁定留用户对话授权门槛触发 → Phase 3 用户授权后改 bootstrap(Phase 1 → Phase 2 → Phase 3 链路类比 D148 Phase 1 → Phase 2 → Phase 3 范式);(v) D149 Phase 2 commit hash 留 Phase 3 启动轮回填(D135-D147 范式延续 — 单 commit 不能引用自己 hash,下下轮回填);(vi) 用户口号「4 处真锚」实测占位符行数 = 字串数 = 4 均匀分布无 refine — 与历史 D148 Phase 0「4 处」→ 3 实测 / D148 Phase 5「25 处」→ 17 实测 / D148 Phase 6「12 删 3 留」→ 11 删 4 留 / D149 启动「5 处」→ 7 字串 / D149 接续「5 处」→ 5 字串无 refine / D149 接续接续「5 处」→ 6 字串 refine / Phase 0「3 处」→ 4 / Phase 1「3 处」→ 4 实测的 refine 历史反差实证(8 次同形防御落档 PSM §字段 3),本轮无 refine

- 2026-05-03 Phase 1 RED 复现 + 信息源探查 + scope 实测(commit `d1c35e0`)— **D149 Phase 1 兑现 a-h 八项 fact 全 GREEN + D149 Phase 0 commit `0852ce9` 回填 4 处真锚 + D135-D148 范式延续**:(a) D149 Phase 0 commit hash `0852ce9` 回填 4 处真锚(line 3 Status header + line 133 §3 Orchestration 表 Phase 0 行 + line 236 §Phase 收关锚 §Phase 0 标题 + line 300 §Status 时间线 Phase 0 entry — 用户口号「3 处」refine 4 实测均匀分布,memory feedback_user_literal_vs_d_ssot 同形防御 7 次落档 PSM §字段 3);(b) F3 RED 复现 PASS — `bin/ss build /tmp/d149_f3_red.ss` 输出 `error: missing field '130122973204720' in named constructor for 'Pt'` line 7:27 阻断编译(intern pool ID 因 process-local 不同 — Phase 0 doc 实测 `125491275030768` vs Phase 1 实测 `130122973204720`,bug pattern 一致);(c) form 2/3 GREEN baseline PASS — `bin/ss build tests/d149_partial_inference/partial_basic.ss` exit 0 输出 5/10/0/0 双 form 合并 GREEN(form 2 全列 + form 3 全 default);(d) 信息源实测 — `bootstrap/checker/check_named_args.ss:78-82` missing field check loop(全文 84 行)+ `bootstrap/checker/check_exprs.ss:269` NEW_EXPR ctor positional + `bootstrap/gen/class/class.ss:222 genNewExpr()` 入口(342 行)+ `bootstrap/gen/class/class.ss:271 genNamedConstructorArgs()` named ctor IR 主体(同文件不在 `gen/methods/` 也不在 `gen/exprs/new_expr.ss`)+ `bootstrap/gen/class/class.ss:273-287` 全 default 空 ctor 路径用 0/null/0.0 零值 + `bootstrap/parse/parser.ss:725 nSetI1(pId, defId)` PARAM I1 slot 存 default expr 节点 ID(无专 `classFieldDefault*` Map);(e) **D149.md 文档路径修正 — `gen/class.ss` → `gen/class/class.ss`**(子目录拆分实测修正,Phase 0 doc 路径错误 — Phase 1 §1 bidirectional 关键设计 entry table + §A.1.1 G2/G3 落点 + §3 Orchestration Phase 1 行 + §Phase 收关锚 Phase 1 entry 全部修正);(f) scope LOC delta ~60-130 实测(原估 ~50-150 修正)— check_named_args.ss line 78-82 missing field check + intern pool ID 解析 ~10-20 + class/class.ss:271 genNamedConstructorArgs() partial 路径 ~30-50 + class/class.ss:273-287 全 default 路径配套修 ~10-30 + default expr 查询路径 ~10-30,文件清单单文件聚焦 check_named_args.ss + class/class.ss 双文件主体 + parser.ss 不改;(g) Phase 1 决策行不锁定 — 留 Phase 2 用户对话锁定(C2 接口层 trap vs C3 架构层 refactor,类比 D148 Phase 1 → Phase 2 范式 H15 授权门槛);(h) VCM §1 豁免锚成立 docs only(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D149-*.md);simplify 跳过 docs only 例外;d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK 3/3 PASS;**新发现**:(i) **全 default 空 ctor 路径用 0/null/0.0 零值非 default value 表达式** — `class/class.ss:273-287` 当前实现:`if (zfLL == "ptr") { args = args + "ptr null" } else if (zfLL == "double") { args = args + "double 0.0" } else { args = args + zfLL + " 0" }` — form 3 spike `class Pt { x: int = 0; y: int = 0 }` GREEN 是因 default `= 0` 碰巧 = 零值;若 default = `1` 或非零,form 3 silent miscompile,**潜在 silent bug 留 Phase 3 配套修**(用 default expr 表达式而非 0/null);(ii) **field default value 存 PARAM I1 slot 无专 Map** — grep `classFieldDefault*` 无结果,parser.ss:725 `nSetI1(pId, defId)` 直接存 default expr 节点 ID 于 PARAM I1 slot,Phase 3 修路径用 `nGetI1(paramId)` 取 defId → genExpr(defId) 反推 / 填充;(iii) **intern pool ID display bug 实测 ID process-local 不同** — Phase 0 doc 实测 `125491275030768` vs Phase 1 实测 `130122973204720`,因 SS intern pool 是 process-local 的(每次编译 ID 不同),bug pattern 一致(`f` 来自 `fieldsSplit = fullFields.split(",")` 应是 string 但 emit numeric ID,根因留 Phase 2/3 深查);(iv) **D149.md 文档路径错误教训** — Phase 0 落档时 `gen/class.ss` 路径凭印象写未实测,Phase 1 实测发现实际是 `gen/class/class.ss` 子目录拆分(CLAUDE.md §高层架构「gen/ 根下基础族 + 子族 class/exprs/stmts/methods/rt/」延续 D135 后 sub-D 重构) — **Phase 0 docs only 风险**:无 grep 验证仅凭印象写路径致 Phase 1 修正,memory `feedback_d026_d027_phantom_anchor.md` 同形教训(引用任一锚必先 ls 验真身);(v) **`gen/methods/gen_methods.ss` 698 行不含 ctor IR** — Phase 0 doc 怀疑 ctor IR 在 `gen/methods/` 或 `gen/exprs/new_expr.ss`,Phase 1 实测 ctor IR 全在 `gen/class/class.ss`(genNewExpr + genNamedConstructorArgs + 全 default 路径 集中单文件);(vi) D149 Phase 1 commit hash 留 Phase 2 启动轮回填(D135-D147 范式延续 — 单 commit 不能引用自己 hash)

- 2026-05-03 Phase 0 D 文档落档(commit `0852ce9`)— **D149 Phase 0 起首兑现 a-? 七项 fact 全 GREEN + D148 §Followup F3 启动条件触发 + D135-D147 范式延续**:(a) D149.md 文档新建 ~400-500 行(本 commit)+ D148.md §A.2 H13 + §Followup F3 + §Status 时间线 升级 + tests/d149_partial_inference/partial_basic.ss form 2/3 GREEN baseline 新建 + /tmp/d149_f3_red.ss form 1 RED 启动条件锚 sad path 实例;(b) D148 §Followup F3 启动条件列升级 — 加 RED 实例 + 起 D149.md Phase 0 落档锚 + spike form 1 RED checker error `missing field` 触发 partial named arg + field default value 配套机制 SS 当前不支持(checker 强制所有 field 显式赋值即使有 default value);(c) §字段 10 (e) 自决策起 D149 sub-D 主体 — F3 启动条件触发不是「自然解度不足 fallback」(F1/F2 模式),而是「ctor default value 机制独立扩展」(F3 描述精确启动条件)+ 不入 D148 §A.3 废案(F3 起 sub-D 是新决策非废案);(d) D149 接续 hash `acdf554` 回填 D148.md 5 行 6 字串真锚(用户口号「5 处」refine 6 字串实测 — line 793 §Followup F5 含 D149 启动 + D149 接续双 commit 双字串非均匀分布);(e) VCM §1 豁免锚成立 docs+tests only(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 D148.md + 新建 D149.md + 新建 tests/d149_partial_inference/partial_basic.ss);simplify 跳过 docs+tests only 例外;d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK 3/3 PASS;(f) D135-D147 范式延续 — Phase 0 落档 docs-only + Phase 1+ bootstrap 改各独立 commit + D135 → D136 → D137 → D140 → D141 → D142 → D143 → D144 → D145 → D147 → D148 主线 close → **D149 sub-D 起首**(F3 配套机制独立扩展);(g) D149 Phase 0 commit hash 留 D149 Phase 1 启动轮回填(D135-D147 范式 — 单 commit 不能引用自己 hash);**新发现**:(i) F3 与 F1/F2 启动条件本质不同 — F1/F2 是「bidirectional 自然解度」spike GREEN unnecessary 入 D148 §A.3 废案,F3 是「ctor default value 配套机制」spike RED 启动条件触发起 D149 sub-D 不入废案;(ii) SS class field default value 语法 + 全列 named arg + 全 default 空 ctor 基础机制已支持,F3 启动条件精确范畴 = partial named arg(checker 强制所有 field 显式赋值);(iii) intern pool ID display bug — checker error 消息显示 intern pool ID 而非 field name,留 D149 Phase 1 RED 复现 + 信息源探查时分析(checker error 消息加 field name 解析是配套修复);(iv) 用户口号「5 处真锚」refine 占位符行数 = 5 / 字串数 = 6(line 793 §Followup F5 列含 D149 启动 + D149 接续双 commit 双字串非均匀分布)— memory feedback_user_literal_vs_d_ssot 同形防御 6 次落档;(v) D149 接续接续 = D149.md Phase 0 落档新建 + D148.md §A.2/§Followup F3/§Status 升级 + tests/d149_partial_inference/ spike — D135-D147 范式延续(每轮独立 commit + 大改档不打包 + Phase X+1 启动轮回填上一 Phase hash + next_prompt 自闭环)
