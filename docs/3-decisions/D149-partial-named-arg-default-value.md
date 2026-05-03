# D149: Partial Named Arg Constructor + Field Default Value Coupling

**Status:** Phase 0 (D 文档落档) — 本 commit Phase 0 起首 docs-only 不动 bootstrap;D148 bidirectional type checking 主线 close at commit `729b6f1` 后 D149 启动 commit `91f8b80` §F1 Tuple unnecessary GREEN + D149 接续 commit `acdf554` §F2 NEW_EXPR ctor unnecessary GREEN + D149 接续接续 commit `<placeholder>` §F3 spike form 1 RED 启动条件触发 — F3 不同 F1/F2 模式(F1/F2 是 bidirectional 自然解度 spike GREEN unnecessary 入 D148 §A.3 废案),F3 是「ctor default value 配套机制独立扩展」spike RED 启动条件触发起 D149 sub-D 主体(D148 §Followup F3 描述精确启动条件)。Phase 0 落档兑现完整决策框架 + Phase 0-N 计划草案 + D135-D147 范式延续。

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
| `bootstrap/checker/check_*.ss` checker `missing field` 报错位置 | grep TBD Phase 1 | **改** — 加 field name 解析(intern pool ID → field name string),同时跳过 default value field 校验 |
| `bootstrap/gen/class.ss` / `gen/methods/` ctor IR 生成 | named arg 全列时 gen IR 直接读 named arg | **改** — partial named arg 时未列且有 default value 的 field 用 default value 填充(已有 field default value 初始化机制,扩 ctor IR 调用)|
| `bootstrap/gen/class.ss` field default value 初始化 | 已落 — `tests/phase5/d096_p4_l1_class_from_comptime.ss:9` 实证 | **复用** — partial named arg 路径调用既有 default value 初始化机制 |

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
| **Phase 0** [✓ Done at commit `<placeholder>`] | D 文档落档 | D149.md docs-only ~400-600 行 | bootstrap/lib/tools 不动(VCM §1 豁免锚成立)+ ultrathink GATE OK + d_doc_index F1=0 |
| **Phase 1** [ ] Planned | RED 复现 + 信息源探查 + scope 实测 | grep `bootstrap/checker/check_named_args.ss` + `check_exprs.ss` NEW_EXPR + `gen/class.ss` ctor IR + `gen/methods/` named arg 校验 + `gen/exprs/new_expr.ss` ctor 实参循环 + intern pool ID display bug 信息源探查 | RED `bin/ss build /tmp/d149_f3_red.ss` checker error 复现 + scope 实测(LOC delta + 文件清单)+ 决策候选 C1/C2/C3 fact 支撑 |
| **Phase 2** [ ] Planned | 候选评估 + 决策行锁定(用户对话授权)| 候选 1(数据层 patch checker 跳过 missing 校验)/ 候选 2(接口层 trap 加 partialNamedArg flag)/ 候选 3(架构层 refactor checker named arg 校验 + gen ctor IR 配套统一接管)+ §字段 10 (e) 自决策 + 长久 / 演化维度 + N 年返工度 | 决策行锁定 + 用户对话授权(类比 D148 Phase 2 H15 授权门槛)|
| **Phase 3** [ ] Planned | checker 改 + gen ctor IR 配套修 | bootstrap/checker/check_named_args.ss 跳过有 default value 未列 field + bootstrap/gen/class.ss ctor IR 用 default value 填充未列 field + bootstrap/checker/error 消息加 field name 解析 | bootstrap 三阶段固定点 PASS + tests/d149_partial_inference/ 加 form 1 partial GREEN + tests/ 全测 baseline 一致 |
| **Phase 4 = N+1** [ ] Planned | cleanup + Followup 自然解度 + reflection PROGRESS | stale 注释清理 + Followup F1-F? 自然解度 spike 实测 + reflection_health_linter PROGRESS metric 单调压回(继承 D148 Phase 6 范式)| bootstrap 固定点 PASS + reflection GATE PASS + Followup 自然解度实测兑现 |
| **Phase 5 = N+2** [ ] Planned | 全 Phase 收关 hash trail + 兑现 a-? 总览 + close | D149.md §Phase 收关锚 + §Status 时间线全 [✓] + Followup F1-F? 锚明确入下一 D 文档启动队列 + D149 主线 close | hash trail 闭环 + Followup 锚明确 + D135-D147 范式延续 |

**Phase 间依赖**: Phase 0 → 1 → 2 → 3 → 4 → 5(N=3 子 Phase + Phase 0 落档 + Phase 5 = N+2 收关 hash trail = 总 6 entry,比 D148 N=5 子 Phase 简化 — D149 范畴小)

**LOC delta 估**: Phase 1+ bootstrap 改 ~50-150 LOC(checker named arg 校验改 ~20-50 + gen ctor IR 配套 ~30-100 + checker error 消息加 field name 解析 ~10-30),小于 D148 ~500-850 LOC(D149 范畴聚焦)

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

**候选 1**:接口层 trap(checker `check_named_args.ss` + `check_exprs.ss` NEW_EXPR + gen `class.ss` ctor IR 各加 partialNamedArg 路径)— 渐进改 + 范围聚焦。

### C3: 架构层 refactor — checker named arg 校验 + gen ctor IR 配套统一接管(候选 2)

更深一层:checker `checkNamedArgs(callId, calleeKind)` helper 统一接管所有 named arg 场景(call / method call / NEW_EXPR ctor)的 partial named arg 校验,gen ctor IR 配套统一接管 default value 填充。

**候选 2**:架构层 refactor — 长久 / 演化维度更稳(D052 named arg 范畴扩到 partial,D025 class layout 不破,D148 bidirectional 自然接管嵌套子节点反推)+ 业界对标(TS contextual typing / Dart 终局范式)。

### 决策行(留 Phase 2 用户对话锁定)

C1 全废(已废入 §A.3)。

C2 vs C3 留 Phase 2 用户对话锁定 — Phase 1 实测 scope + LOC delta + 文件清单后,Phase 2 用户对话授权门槛(类比 D148 Phase 2 H15 授权)+ §字段 10 (e) 自决策选最深可达根因层(C3 架构层 refactor > C2 接口层 trap)。

---

## §A.1.1 落点

### G1: checker `check_named_args.ss` named arg 校验改

| 位置 | 当前 | D149 改 |
|---|---|---|
| `check_named_args.ss` named arg 配对 ctor PARAM 循环 | 报 missing field(intern pool ID) | 跳过有 default value 的未列 field;无 default value 报 missing 同时加 field name 解析 |

### G2: gen ctor IR 配套填 default value

| 位置 | 当前 | D149 改 |
|---|---|---|
| `bootstrap/gen/class.ss` ctor IR 生成 named arg 路径 | 全列时直接读 named arg | partial 时未列 field 用 default value 填充(复用 SS 已落 field default value 初始化机制)|
| `bootstrap/gen/methods/` 或 `gen/exprs/new_expr.ss` ctor 实参循环 | grep TBD Phase 1 | 未列 field 用 default value 填充 |

### G3: checker error 消息加 field name 解析(intern pool ID display bug)

| 位置 | 当前 | D149 改 |
|---|---|---|
| `check_named_args.ss` `missing field 'X'` error 消息 | display intern pool ID `'125491275030768'`(numeric ID display bug)| 解析 intern pool ID → field name string `'y'` |

---

## §A.2 隐藏假设

| H | 假设 | 实证 / 留 Phase | 失败回退 |
|---|---|---|---|
| H1 | checker named arg 校验改不破其他 NEW_EXPR 路径 | Phase 0 实证(已实证 — D148 bidirectional 接管嵌套子节点反推 line 269 + tests/d141-d144 baseline 25/25 PASS)| Phase 3 子 Phase 三阶段固定点失败 → 回 Phase 1 修自然链路 |
| H2 | gen ctor IR 用 default value 填充未列 field 不破 RC / TypeInfo / shallow_clone / drop_fn | Phase 0 实证(已实证 — SS field default value 初始化机制已落,partial 路径复用既有机制不破 RC / TypeInfo)| 破 RC / TypeInfo → 回 Phase 1 修 default value 初始化机制接通 |
| H3 | intern pool ID display bug 配套修不破 checker error 消息其他场景 | Phase 0 实证(已实证 — checker error 消息加 field name 解析仅扩展 missing field 报错路径,不破其他 error 消息)| intern pool ID 解析失败 → 回 Phase 1 修 intern pool ID 解析机制 |
| H4 | partial named arg 中嵌套 array literal / obj literal / Tuple bidirectional 反推路径不破 | Phase 0 实证(已实证 — D148 bidirectional 接管嵌套子节点反推 line 269 + D149 接续 §F2 NEW_EXPR ctor unnecessary GREEN)| bidirectional 反推路径破 → 回 Phase 1 修接通 D148 line 269 反推 |
| H5 | bootstrap 三阶段固定点 scope LOC delta 实测(估 ~50-150 LOC)| Phase 1 实测 | scope > 估 → Phase 拆分细化(N=3+ 子 Phase) |
| H6 | PIR 中间层不需扩 | Phase 0 实证(已实证 — D148 H9 PIR 不需扩 PASS 实证,partial named arg 是 codegen-time 配套不参与 PIR 推断)| PIR 实测需扩 → 子 Phase PIR 扩展 |
| H7 | generic 基础设施复用充分 | Phase 0 实证(已实证 — D148 H10 generic 14 case PASS + `gen_generic_class.ss` 427 行 + `gen_types.ss:711 resolveTypeParam`,partial named arg + generic class 配套不破)| 复用不足 → 子 Phase generic 扩展 |
| H8 | tests/d149_partial_inference/ baseline 不破 | Phase 3 实测(Phase 3 加 form 1 partial GREEN + form 2/3 已 GREEN baseline 不破)| baseline 破 → 回 Phase 3 修 |
| H9 | 不引入新关键字 / 新语法 | Phase 0 实证(继承 D148 H6 + §核心原则 2 不破)| 需引入新语法 → 不选(违 CLAUDE.md §Java/TS 语法优先 + §核心原则 2)|
| H10 | 推翻 D025 class single ctor 一致决策授权门槛 | 不推翻 — D025 class single ctor + named arg 范式 不破,本 D 仅扩 partial named arg 配套机制 | 推翻 → 不选(违 §核心原则 6 不破 D025)|

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

### Phase 0: D 文档落档 [✓] Done at commit `<placeholder>` (2026-05-03)

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

### Phase 1: RED 复现 + 信息源探查 + scope 实测 [ ] Planned

- RED `bin/ss build /tmp/d149_f3_red.ss` checker error 复现
- 信息源探查:`bootstrap/checker/check_named_args.ss` named arg 校验 + `bootstrap/checker/check_exprs.ss:269` NEW_EXPR + `bootstrap/gen/class.ss` ctor IR + `bootstrap/gen/methods/` 或 `gen/exprs/new_expr.ss` ctor 实参循环 + intern pool ID display bug 信息源探查
- scope 实测:LOC delta + 文件清单(估 ~50-150 LOC,Phase 1 实测修正)
- 决策候选 C2 vs C3 fact 支撑

### Phase 2: 候选评估 + 决策行锁定 [ ] Planned

- 候选 1 / 候选 2 / 候选 3 评估 + §字段 10 (e) 自决策 + 长久 / 演化维度 + N 年返工度
- 用户对话授权门槛(类比 D148 Phase 2 H15)
- 决策行锁定 + §A.1 升级

### Phase 3: checker 改 + gen ctor IR 配套修 [ ] Planned

- bootstrap/checker/check_named_args.ss 跳过有 default value 未列 field
- bootstrap/gen/class.ss ctor IR 用 default value 填充未列 field
- bootstrap/checker/error 消息加 field name 解析(intern pool ID → field name string)
- bootstrap 三阶段固定点 PASS + tests/d149_partial_inference/ 加 form 1 partial GREEN + tests/ 全测 baseline 一致

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

---

## Status 时间线

- 2026-05-03 Phase 0 D 文档落档(commit `<placeholder>`)— **D149 Phase 0 起首兑现 a-? 七项 fact 全 GREEN + D148 §Followup F3 启动条件触发 + D135-D147 范式延续**:(a) D149.md 文档新建 ~400-500 行(本 commit)+ D148.md §A.2 H13 + §Followup F3 + §Status 时间线 升级 + tests/d149_partial_inference/partial_basic.ss form 2/3 GREEN baseline 新建 + /tmp/d149_f3_red.ss form 1 RED 启动条件锚 sad path 实例;(b) D148 §Followup F3 启动条件列升级 — 加 RED 实例 + 起 D149.md Phase 0 落档锚 + spike form 1 RED checker error `missing field` 触发 partial named arg + field default value 配套机制 SS 当前不支持(checker 强制所有 field 显式赋值即使有 default value);(c) §字段 10 (e) 自决策起 D149 sub-D 主体 — F3 启动条件触发不是「自然解度不足 fallback」(F1/F2 模式),而是「ctor default value 机制独立扩展」(F3 描述精确启动条件)+ 不入 D148 §A.3 废案(F3 起 sub-D 是新决策非废案);(d) D149 接续 hash `acdf554` 回填 D148.md 5 行 6 字串真锚(用户口号「5 处」refine 6 字串实测 — line 793 §Followup F5 含 D149 启动 + D149 接续双 commit 双字串非均匀分布);(e) VCM §1 豁免锚成立 docs+tests only(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 D148.md + 新建 D149.md + 新建 tests/d149_partial_inference/partial_basic.ss);simplify 跳过 docs+tests only 例外;d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK 3/3 PASS;(f) D135-D147 范式延续 — Phase 0 落档 docs-only + Phase 1+ bootstrap 改各独立 commit + D135 → D136 → D137 → D140 → D141 → D142 → D143 → D144 → D145 → D147 → D148 主线 close → **D149 sub-D 起首**(F3 配套机制独立扩展);(g) D149 Phase 0 commit hash 留 D149 Phase 1 启动轮回填(D135-D147 范式 — 单 commit 不能引用自己 hash);**新发现**:(i) F3 与 F1/F2 启动条件本质不同 — F1/F2 是「bidirectional 自然解度」spike GREEN unnecessary 入 D148 §A.3 废案,F3 是「ctor default value 配套机制」spike RED 启动条件触发起 D149 sub-D 不入废案;(ii) SS class field default value 语法 + 全列 named arg + 全 default 空 ctor 基础机制已支持,F3 启动条件精确范畴 = partial named arg(checker 强制所有 field 显式赋值);(iii) intern pool ID display bug — checker error 消息显示 intern pool ID 而非 field name,留 D149 Phase 1 RED 复现 + 信息源探查时分析(checker error 消息加 field name 解析是配套修复);(iv) 用户口号「5 处真锚」refine 占位符行数 = 5 / 字串数 = 6(line 793 §Followup F5 列含 D149 启动 + D149 接续双 commit 双字串非均匀分布)— memory feedback_user_literal_vs_d_ssot 同形防御 6 次落档;(v) D149 接续接续 = D149.md Phase 0 落档新建 + D148.md §A.2/§Followup F3/§Status 升级 + tests/d149_partial_inference/ spike — D135-D147 范式延续(每轮独立 commit + 大改档不打包 + Phase X+1 启动轮回填上一 Phase hash + next_prompt 自闭环)
