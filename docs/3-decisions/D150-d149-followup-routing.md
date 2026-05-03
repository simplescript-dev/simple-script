# D150: D149 Followup 起首选择 — F2/F3/F4 单点 sub-D vs F5 v2 总体设计

**Status:** Phase 0 落档(D149 Phase 5 commit `51781ce` 回填 10 处真锚 6 行非均匀分布(line 3 / 138 含 2 字串 + line 369 / 372 / 373 含 1 字串 + line 420 含 3 字串)+ D149 主线 close 后 followup 起首选择 + D150 sub-D 候选评估 fact 入档(C-A F2 field 拓扑排序 / C-B F3 method PARAM default codegen + method call partial named arg checker / C-C F4 spread `{...base}` / C-D F5 v2 总体设计独立 D 文档)+ §字段 10 (e) 自决策评估倾向 C-D > C-B > C-A/C-C(根因解决度 + 长久 / 演化维度 — 底层依赖链 + 业界对标 + N 年返工度 + D150+ 后续 sub-D 起首返工率 — 五维全胜)+ 决策行不锁定 留用户对话授权门槛触发(类比 D148 Phase 2 H15 / D149 Phase 2 H12 授权范式)+ docs only(VCM §1 豁免锚成立)+ d_doc_index F1=0 + ultrathink GATE OK + simplify 跳过 docs only 例外)— **D149 主线 close at commit `51781ce` 后 D150 起首选择**;后续 D150 Phase 1 = 用户对话授权 + 候选锁定 + Phase 0 hash 回填 + 候选范畴细化 + 路径分支(C-D 起 v2 总体设计 D 文档 / C-A/C-B/C-C 起 D150 主线 RED → GREEN)。

**Depends on:** D149(partial named arg ctor + field default value 配套机制,Phase 5 = N+2 close at commit `51781ce`,主线 GREEN — partial + form 2/3 baseline + bootstrap 三阶段固定点 + intern pool ID display bug 旁修;Followup F2/F3/F4 RED 启动 D150+ + F1 unnecessary 入 §A.3 + F6 启动条件留 bootstrap-context-only)+ D148(bidirectional type checking, Phase 7 close at commit `729b6f1`)+ D052(named arg `k: v` syntax)+ D127(named arg syntax k:v vs annotation k=v 双源语义分采)+ D025(class layout `{ i32 rc, ptr TypeInfo, ...fields }` + per-class drop_fn / deep_clone_fn / shallow_clone_fn / size / name TypeInfo)

**Date:** 2026-05-03

---

## 核心目标

D149 主线 close 后,F2/F3/F4 三个 RED 启动条件已具备 + F6 启动条件留 + F5 v2 总体设计实测假设触发条件具备(累计 sub-D 单点起首 ≥ 3)— **D150 起首选择 = v2 总体设计 D 文档(C-D F5)还是单点 sub-D 起首(C-A F2 / C-B F3 / C-C F4 任一)**。

**第一性需求**:
- F2/F3/F4 都是 D149 partial named arg + field default value 周边的扩展 sub-D
- F5 v2 总体设计是统一规划 D150-D155 多个 sub-D 优先级 + 范畴 + 阶段实施
- F2/F3/F4 都依赖 F5 v2 总体规划锚定优先级(底层依赖链 — F5 未做则 F2/F3/F4 单点零散起首每轮各自评估,返工率高)
- 业界对标 TS K2 compiler / Dart Sound type system v2 / Kotlin K2 都是「先总体规划再阶段实施」终局范式
- N 年返工度:F5 v2 总体规划一次评估覆盖 D150-D155;C-A/C-B/C-C 单点零散起首每轮各自评估有返工概率

**不在范畴**:
- ❌ Followup F1 ctor PARAM default value(D149 §A.3 废案 — SS 已自然支持 function PARAM default value)
- ❌ Followup F6 ternary type inference(D149 §Followup 启动条件留 bootstrap-context-only — standalone 不复现)
- ❌ 越过用户对话授权门槛自决策(类比 D148 Phase 2 H15 / D149 Phase 2 H12 范式)

---

## 核心原则

(继承 CLAUDE.md + D149 §核心原则 12 条):

1. **Java/TS 优先(同 CLAUDE.md §Java/TS 语法优先)** — 所有候选都不引入新语法,继承 D149 §核心原则 1。
2. **不引入新关键字 / 新语法** — F2 拓扑排序 / F3 method PARAM default / F4 spread / F5 v2 总体设计 都复用既有 SS 语法机制。
3. **Root Cause 优先(CLAUDE.md §Root Cause 优先 第一法则,无例外)** — 候选评估 7 维度按根因解决度 + 长久 / 演化维度排序,**禁按工程量最小 / 最经济 / 最快上线 / LOC 最少作排序依据**。
4. **业界对标(CLAUDE.md §长久 / 演化维度)** — TS contextual typing v2 / Dart Sound type system v2 / Kotlin K2 / Pierce & Turner "Local Type Inference" 2000 终局范式。
5. **N 年返工度低(CLAUDE.md §长久 / 演化维度)** — F5 v2 总体规划一次覆盖 D150-D155 vs F2/F3/F4 单点零散起首每轮各自评估返工概率高。
6. **bootstrap 隔离破例 D141-D145 §核心原则 同位例外** — D150 Phase 0 落档 docs-only 不动 bootstrap(VCM §1 豁免锚成立);Phase 1+ 实施各独立 commit。
7. **决策行不锁定 留用户对话授权门槛触发** — 类比 D148 Phase 2 H15 / D149 Phase 2 H12 授权范式,Phase 0 启动轮 §字段 10 (e) 自决策评估完整入档,**等用户对话明确锁定 C-A/C-B/C-C/C-D 后才入 Phase 1**。

---

## §1 Context

### D149 主线 close 后 followup 状态(commit `51781ce`)

- ✓ **D149 主线 GREEN** — partial named arg ctor + field default value 配套机制(form 1 partial + form 2/3 baseline + 全测 baseline 一致 288 PASS / 11 FAIL pre-existing infra + bootstrap 三阶段固定点 + intern pool ID display bug 旁修)
- ✓ **F1 unnecessary 入 §A.3 废案** — `function makeBox(v: int = 42)` 输出 42/100 exit 0,SS 已自然支持 function PARAM default value(D025 单 ctor + named arg 范式下 ctor PARAM default value 不适用,实际 F1 范畴 = function/method 自身 PARAM default value)
- ✗ **F2 RED 启动 D150+** — `class Pair { x: int = 5; y: int = x + 1 }` LLC error `use of undefined value '%x' at /tmp/.../d149_f2_bin.ll:5197:22`(field default expr 中引用 sibling field `x` 未接通 `this.x` scope)
- ✗ **F3 RED 启动 D150+** — `class Greeter { function greet(name: string = "World", excited: int = 0) }` 编译成功但运行时 segfault(exit 139)— **不限于 named arg**,即使全位置参数 / 全 default `g.greet()` / `g.greet("SS", 1)` 也 segfault,method PARAM default value 机制 codegen 未接管(D149 主线只覆盖 NEW_EXPR ctor + class field default value,method 链路独立 codepath 与 free function 不同)
- ✗ **F4 RED 启动 D150+** — `const custom = {...base, name: "myservice"}` parser error `expected identifier, found SPREAD`(SS parser 不支持 `...` 语法)
- ⚠ **F5 v2 总体设计实测假设触发条件已具备** — 累计 sub-D 单点起首 ≥ 3(F2 + F3 + F4)+ F6 启动条件留(potential 第 4 起首)
- ⚠ **F6 启动条件留 bootstrap-context-only** — `cond ? a.split() : b.split()` standalone GREEN 不复现 D149 Phase 3 实测 codegen bug,bug 触发条件 = bootstrap-context-only(可能 Map.getString + 多函数链路 + Array<string> 类型注解综合)比想象更狭窄

### 累计 sub-D 链路

D135 → D136 → D137 → D140 → D141 → D142 → D143 → D144 → D145 → D147 → D148 → **D149 close** → **D150 起首选择**(C-A F2 / C-B F3 / C-C F4 单点 vs C-D F5 v2 总体设计)

### 业界对标

- **TS K2 compiler 终局范式** — Pierce & Turner "Local Type Inference" 2000 + TS 2.0+ contextual typing v2 一次性总体规划范式
- **Dart Sound type system v2** — null safety + sound type system 总体规划阶段实施(2018 → 2020 主版本规划)
- **Kotlin K2 compiler** — K2 总体规划重写 vs K1 单点修(2022 K2 alpha → 2024 K2 stable 总体范式)
- **Java(无 v2 总体设计,反例)** — Java 类型系统每个 JEP 单点演进无总体规划致 N 年返工(Generics 2004 → Sealed 2021 → Records 2020 多次返工)

SS 落地 v2 总体设计是 TS / Dart / Kotlin 主流范式,Java 是反例不沿袭(类比 D149 §1 业界对标 Java 无 partial named arg 反例不沿袭范式延续 — Java 没 native named arg 需 builder pattern,SS 不沿袭)。

---

## §2 RED 锚

D150 Phase 0 是「起首选择」决策落档,无 RED bug 直接挂载;候选锁定后(Phase 1+)对应 RED 锚:

```bash
# C-A F2 RED:
bin/ss build /tmp/d149_f2_field_init_order.ss 2>&1 | grep "use of undefined value"
# 当前 = 1(LLC error use of undefined value '%x')
# 目标 = 0(field 拓扑排序 + this scope 接通)

# C-B F3 RED:
bin/ss build /tmp/d149_f3_method_partial.ss && /tmp/d149_f3_method_partial; echo $?
# 当前 = 139(segfault)
# 目标 = 0(method PARAM default value codegen 全接管)

# C-C F4 RED:
bin/ss build /tmp/d149_f4_spread.ss 2>&1 | grep "expected identifier"
# 当前 = 1(parser error expected identifier found SPREAD)
# 目标 = 0(spread parser 节点扩展 + bidirectional 反推)

# C-D F5 RED:无单一 RED — v2 总体设计是文档型决策,各阶段实施沿用 C-A/C-B/C-C 各 RED 锚
```

---

## §3 Orchestration

| Phase | 内容 | 落点 | 完成判据 |
|---|---|---|---|
| **Phase 0** [✓ Done at commit `<placeholder>`(留 D150 Phase 1 启动轮回填 — D135-D147 范式 单 commit 不能引用自己 hash)] | D 文档落档 + 候选评估 fact 入档 + 决策行不锁定 留用户对话授权 | D150.md docs-only ~300-500 行 — Status header + Depends on D149/D148/D052/D127/D025 + Date 2026-05-03 + §核心目标 + §核心原则 7 条 + §1 Context D149 主线 close 后 followup 状态 + §2 RED 锚 + §3 Orchestration Phase 0-2+ + §A.1 C-A/C-B/C-C/C-D 四候选评估 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 + §Phase 收关锚 + §Followup + §Status 时间线 | bootstrap/lib/tools 不动(VCM §1 豁免锚成立)+ ultrathink GATE OK + d_doc_index F1=0 + simplify 跳过 docs-only 例外 |
| **Phase 1** [ ] Planned | 用户对话授权 + 候选锁定 + Phase 0 hash 回填 + 候选范畴细化 | 用户答 `C-A` / `C-B` / `C-C` / `C-D` 锁定后 — 候选范畴细化 + 后续 Phase 路径明确 + Phase 0 hash 回填本 D 文档 | 用户对话授权门槛 PASS + 候选范畴细化 + 后续 Phase 路径明确 |
| **Phase 2+** Planned | 路径分支 — C-D 起 v2 总体设计 D 文档 / C-A/C-B/C-C 起 D150 主线 RED → GREEN | 待 Phase 1 用户授权后定:C-D 锁定 → 本 D 扩展为 v2 总体设计 D 文档 + D151-D155 sub-D 起首接力实施;C-A/C-B/C-C 锁定 → D150 主线 = F2/F3/F4 任一 RED → GREEN + 剩余 followup 留 D151+ | 路径明确后展开 |

**Phase 间依赖**: Phase 0 → 1(用户对话授权门槛触发)→ Phase 2+(路径分支:C-D v2 总体设计 / C-A/C-B/C-C 单点 RED → GREEN)

**LOC delta 估**(各候选):
- **C-A F2 field 拓扑排序**: ~50-150 LOC(field 拓扑排序 + this scope 接通 + 循环依赖检测)
- **C-B F3 method PARAM default value codegen + method call partial named arg checker**: ~80-200 LOC(method PARAM default codegen 全接管 ~50-120 + method call partial named arg checker ~30-80,helper 复用 D149 抽象 `genCtorArgsWithDefaults` / `lookupFieldDefaultId` / `lookupFieldType` 长久演化净收益正)
- **C-C F4 spread `{...base}` partial init**: ~100-250 LOC(spread parser 节点扩展 + bidirectional 反推 + obj literal 合并语义)
- **C-D F5 v2 总体设计独立 D 文档**: ~500-1500 LOC(总体设计文档 + 阶段实施分散到 D151-D155)

---

## §A.1 决策行

### C-A: F2 field 初始化顺序(field 间相互引用)起 D150 sub-D

D149 Phase 4 spike `/tmp/d149_f2_field_init_order.ss` `class Pair { x: int = 5; y: int = x + 1 }` LLC error `use of undefined value '%x' at /tmp/.../d149_f2_bin.ll:5197:22` — field default expr 中引用 sibling field `x` 未接通 `this.x` scope。

**起 D150 sub-D 主体**:field 拓扑排序机制 + this scope 接通 + 循环依赖检测。

**§字段 10 (e) 自决策评估**(C-A F2):
- **根因解决度**:中(单点起首 — 仅覆盖 field 间相互引用,不覆盖 method PARAM default / spread / v2 总体设计)
- **长久 / 演化维度**:中(底层依赖链 — F2 不依赖 F3/F4/F5,可独立起首;业界对标 — Dart `final int y; Pt({this.x = 0, this.y = x + 1})` 终局范式同形;N 年返工度 — 中,F5 v2 总体规划如未做则 F2 起首后 F3/F4/F6 各自评估)
- **scope LOC delta** ~50-150(field 拓扑排序 + this scope 接通 + 循环依赖检测)

### C-B: F3 method PARAM default value codegen 接管 + method call partial named arg checker 起 D150 sub-D

D149 Phase 4 spike `/tmp/d149_f3_method_partial.ss` + `/tmp/d149_f3_method_positional.ss` 编译成功但运行时 segfault(exit 139)— **不限于 named arg**,即使全位置参数 / 全 default `g.greet()` / `g.greet("SS", 1)` 也 segfault,method PARAM default value 机制 codegen 未接管(D149 主线只覆盖 NEW_EXPR ctor + class field default value,method 链路独立 codepath 与 free function 不同)。

**起 D150 sub-D 主体**:method PARAM default value codegen 全接管 + method call partial named arg checker 双修。

**§字段 10 (e) 自决策评估**(C-B F3):
- **根因解决度**:高(method PARAM default value codegen 全接管 + method call partial named arg checker 双修是 method 调用面的根因解决)
- **长久 / 演化维度**:中(底层依赖链 — D149 helper `genCtorArgsWithDefaults` + `lookupFieldDefaultId` + `lookupFieldType` 可复用于 method PARAM default codegen 接管,长久演化净收益正;业界对标 — TS / Dart / Kotlin method PARAM default 都是终局范式;N 年返工度 — 中,F5 v2 总体规划如未做则 F3 起首后 F2/F4/F6 各自评估)
- **scope LOC delta** ~80-200(method PARAM default codegen 全接管 ~50-120 + method call partial named arg checker ~30-80,helper 复用 D149 抽象)

### C-C: F4 spread `{...base, name: "X"}` partial init 起 D150 sub-D

D149 Phase 4 spike `/tmp/d149_f4_spread.ss` parser error `expected identifier, found SPREAD`(SS parser 不支持 `...` 语法)。

**起 D150 sub-D 主体**:spread parser 节点扩展 + bidirectional 反推 + obj literal 合并语义(D148 §Followup F4 范式延续)。

**§字段 10 (e) 自决策评估**(C-C F4):
- **根因解决度**:中(spread 语法是 obj literal 合并语义,与 partial named arg 不重叠 — 单点起首)
- **长久 / 演化维度**:中(底层依赖链 — D148 §Followup F4 范式延续 + obj literal 合并语义独立;业界对标 — TS spread `{...base}` + JS Object spread 终局范式;N 年返工度 — 中,F5 v2 总体规划如未做则 F4 起首后 F2/F3/F6 各自评估)
- **scope LOC delta** ~100-250(spread parser 节点扩展 + bidirectional 反推 + obj literal 合并语义)

### C-D: F5 类型系统 v2 总体设计独立 D 文档(候选倾向)

D149 Phase 5 实测假设兑现 — 累计 sub-D 单点起首 ≥ 3(F2 + F3 + F4)+ F6 启动条件留(potential 第 4 起首)— F5 v2 总体设计实测假设触发条件已具备。

**起 D150 sub-D 主体**(若用户授权 C-D):本 D 文档扩展为类型系统 v2 总体设计 D 文档,统一规划 D150-D155 sub-D 优先级 + 范畴 + 阶段实施。

**包含**(若 C-D 锁定 — 候选规划):
- **D150 sub-D**: F2 field 拓扑排序(单点起首,优先级 1 — 最小 scope + field 间相互引用是 D149 主线衍生)
- **D151 sub-D**: F3 method PARAM default value codegen + method call partial named arg(单点起首,优先级 2 — D149 helper 复用)
- **D152 sub-D**: F4 spread `{...base}` + obj literal 合并语义(单点起首,优先级 3 — D148 §Followup F4 范式延续)
- **D153 sub-D**: F6 ternary type inference 增强(启动条件触发,优先级 4 — bootstrap-context-only 真有 case 再起首)
- **D154 sub-D**: ctor PARAM default value 全机制(优先级 5 — function/method PARAM default 已支持,ctor PARAM 待 D025 决策行更新)
- **D155 sub-D**: bidirectional 全局深化(优先级 6 — D148 已落 NEW_EXPR ctor + array literal,扩 obj literal / Tuple / 泛型实参)

**§字段 10 (e) 自决策评估**(C-D F5 v2 总体设计):
- **根因解决度**:**高**(总体规划覆盖所有 sub-D — 锚定 D150-D155 优先级 + 范畴 + 阶段实施,不只覆盖单点)
- **长久 / 演化维度**:**高**(底层依赖链 — F2/F3/F4/F6 都依赖 F5 v2 总体规划锚定优先级,F5 未做则 F2/F3/F4 单点零散起首每轮各自评估;业界对标 — TS K2 / Dart Sound v2 / Kotlin K2 都是「先总体规划再阶段实施」终局范式 + Java 反例不沿袭;N 年返工度 — **低**,一次规划覆盖 D150-D155 vs C-A/C-B/C-C 单点零散起首每轮各自评估返工概率高)
- **scope LOC delta** ~500-1500(总体设计文档 + 阶段实施分散到 D151-D155)

### 候选评估 7 维度对比表

| 维度 | C-A F2 单点 | C-B F3 单点 | C-C F4 单点 | **C-D F5 v2 总体** | 决策倾向 |
|---|---|---|---|---|---|
| **根因解决度** | 中(field 间相互引用 单点)| 高(method PARAM default codegen + method call partial 双修)| 中(spread 语法 单点)| **高**(总体规划覆盖所有 sub-D)| **C-D ≥ C-B > C-A/C-C** |
| **长久 / 演化:底层依赖链** | 中(F2 独立可起首)| 中(F3 helper 复用 D149 抽象)| 中(F4 独立可起首)| **高**(F2/F3/F4/F6 都依赖 F5 v2 总体规划锚定优先级)| **C-D > C-A/C-B/C-C** |
| **长久 / 演化:业界对标** | 中(Dart 终局范式)| 中(TS / Dart / Kotlin 终局范式)| 中(TS spread 终局范式)| **高**(TS K2 / Dart Sound v2 / Kotlin K2 终局范式)| **C-D > C-A/C-B/C-C** |
| **长久 / 演化:N 年返工度** | 中(F5 未做则 F3/F4/F6 各自评估)| 中(F5 未做则 F2/F4/F6 各自评估)| 中(F5 未做则 F2/F3/F6 各自评估)| **低**(一次规划覆盖 D150-D155)| **C-D > C-A/C-B/C-C** |
| **scope LOC delta** | ~50-150(单点最小)| ~80-200 | ~100-250 | ~500-1500(总体最大,阶段实施分散到 D151-D155)| C-A 最小,C-D 最大 — 但 CLAUDE.md §Root Cause 优先 禁按 LOC 排序,C-D 长久演化净收益正 |
| **bootstrap 三阶段固定点风险** | 低(单文件聚焦)| 中(method PARAM default 链路 + checker 双修)| 中(spread parser 节点扩展)| 低(总体设计 docs-only;Phase 1+ 实施分散到 D151-D155 子 D 各自验证)| C-A/C-D 略低,但 H10 已实证 D135-D149 范式延续可控 |
| **D150+ 后续 sub-D 起首返工率** | 高(F3/F4/F6 各自评估)| 高(F2/F4/F6 各自评估)| 高(F2/F3/F6 各自评估)| **低**(一次规划锚定 D150-D155 优先级)| **C-D > C-A/C-B/C-C** |

**§字段 10 (e) 自决策评估**:**C-D > C-B > C-A/C-C**(根因解决度 + 长久 / 演化维度 — 底层依赖链 + 业界对标 + N 年返工度 + D150+ 后续 sub-D 起首返工率 — **五维全胜**),倾向 **C-D F5 v2 总体设计独立 D 文档**。

### 决策行(Phase 0 不锁定 留用户对话授权)

C-A / C-B / C-C / C-D 四候选评估 fact 已入档,**§字段 10 (e) 自决策评估倾向 C-D**。

**决策行不锁定** — 类比 D148 Phase 2 H15 / D149 Phase 2 H12 用户对话授权门槛触发(C-D F5 v2 总体设计涉及多个 sub-D 优先级 + 范畴定义,长久演化影响范围扩到 D150-D155,需用户对话锁定 C-A / C-B / C-C / C-D),Phase 0 启动轮不自决策,等用户对话明确锁定后才入 Phase 1 候选范畴细化 + 路径分支。

**类比范式**:
- D148 Phase 2 H15:bidirectional 接管副作用清零候选 B1 / B2,用户对话锁定 B1
- D149 Phase 2 H12:架构层 refactor C2 / C3,用户对话锁定 C3
- D150 Phase 0 H3:F5 v2 总体设计 vs F2/F3/F4 单点起首,用户对话锁定 C-A / C-B / C-C / C-D

---

## §A.1.1 落点

### G1: 用户对话授权候选锁定(Phase 1 启动条件)

| 候选 | 锁定后 Phase 1+ 落点 |
|---|---|
| C-A F2 field 拓扑排序 | D150 主线 = F2 RED → GREEN(field 拓扑排序 + this scope 接通 + 循环依赖检测);剩余 F3/F4/F6 留 D151+ sub-D 起首接力 |
| C-B F3 method PARAM default codegen + method call partial named arg | D150 主线 = F3 RED → GREEN(method PARAM default 全接管 + method call partial named arg 双修);剩余 F2/F4/F6 留 D151+ sub-D 起首接力 |
| C-C F4 spread `{...base, name: "X"}` | D150 主线 = F4 RED → GREEN(spread parser 节点扩展 + bidirectional 反推 + obj literal 合并语义);剩余 F2/F3/F6 留 D151+ sub-D 起首接力 |
| **C-D F5 v2 总体设计**(倾向)| D150 主线 = 类型系统 v2 总体设计 D 文档(本 D 扩展为 v2 总体设计) — 统一规划 D150-D155 优先级 + 范畴 + 阶段实施;D151-D155 sub-D 起首接力实施 F2/F3/F4/F6 + ctor PARAM default + bidirectional 全局深化 |

### G2: Phase 0 hash 回填 + 路径分支后子 D 文档创建

- **D150 Phase 1**:Phase 0 commit hash 回填本 D 文档(D135-D147 范式延续 — 单 commit 不能引用自己 hash 下下轮回填)
- **C-D 锁定 → D150 主线扩展为 v2 总体设计 D 文档**(本 D 文档扩展)+ D151-D155 sub-D 起首接力实施
- **C-A/C-B/C-C 锁定 → D150 主线 = F2/F3/F4 任一 RED → GREEN** + 剩余 followup 留 D151+

---

## §A.2 隐藏假设

| H | 假设 | 实证 / 留 Phase | 失败回退 |
|---|---|---|---|
| H1 | D149 主线 close 后 followup F2/F3/F4 RED 启动条件已具备 | ✓ Phase 0 实证(D149 Phase 4 spike 实测 F2 LLC error / F3 segfault / F4 parser error 三 RED — D149.md §Followup line 410-414)| 启动条件不具备 → 不起 D150,留下轮 |
| H2 | F5 v2 总体设计实测假设触发条件已具备(累计 sub-D 单点起首 ≥ 3) | ✓ Phase 0 实证(D149 Phase 4 实测 F2 + F3 + F4 三 RED 启动 D150+ + F6 启动条件留 — D149.md §Phase 收关锚 line 396 实证)| 累计 sub-D < 3 → F5 v2 实测假设留下轮(C-A/C-B/C-C 单点起首先做)|
| H3 | 用户对话授权门槛触发(类比 D148 Phase 2 H15 / D149 Phase 2 H12 范式)| Phase 1 留(用户对话明确锁定 C-A/C-B/C-C/C-D 后才入 Phase 2+)| 用户对话授权未触发 → Phase 1 阻塞 |
| H4 | C-D 锁定后 v2 总体设计 D 文档可一次规划覆盖 D150-D155 | Phase 2+ 留(若 C-D 锁定后实测 v2 总体设计 D 文档可覆盖 D150-D155 优先级 + 范畴 + 阶段实施)| v2 总体设计无法覆盖 → 退化为 C-A/C-B/C-C 单点起首 + D151+ 接力 |
| H5 | C-A F2 field 拓扑排序 scope LOC delta ~50-150(估)| Phase 1 实测验证(若 C-A 锁定 — bootstrap/parse/parser.ss field default expr 解析 + checker 拓扑排序 + this scope 接通)| scope > 估 → Phase 拆分细化 |
| H6 | C-B F3 method PARAM default codegen scope LOC delta ~80-200(估)| Phase 1 实测验证(若 C-B 锁定 — bootstrap/gen/methods/ method PARAM default codegen 全接管 + checker method call partial named arg)| scope > 估 → Phase 拆分细化 |
| H7 | C-C F4 spread scope LOC delta ~100-250(估)| Phase 1 实测验证(若 C-C 锁定 — bootstrap/parse/ spread token + parser 节点 + checker bidirectional 反推 + gen obj literal 合并)| scope > 估 → Phase 拆分细化 |
| H8 | C-D F5 v2 总体设计 scope LOC delta ~500-1500(估)| Phase 1+ 实测验证(若 C-D 锁定 — 总体设计文档 + D151-D155 阶段实施分散)| scope > 估 → Phase 拆分细化(D150-D155 多 D 文档分担)|
| H9 | bootstrap 三阶段固定点不破(D135-D149 范式延续)| Phase 2+ 留(各候选实施时验证 — `./build.sh bootstrap` Stage 2 = Stage 3)| 三阶段固定点破 → 回 Phase 1 修自然链路 |
| H10 | 不引入新关键字 / 新语法(继承 D149 H9 + §核心原则 2)| Phase 0 实证(继承 D149 H9 / D148 H6 + §核心原则 2 不破 — F2 拓扑排序 / F3 method PARAM default / F4 spread / F5 v2 总体设计 都复用既有 SS 语法机制)| 需引入新语法 → 不选(违 CLAUDE.md §Java/TS 语法优先 + §核心原则 2)|

---

## §A.3 废案

- **C 数据层 patch 起 D150 sub-D 全废**(`feedback_root_cause_no_cost.md` 红线 — 数据层 patch 不区分 F2/F3/F4 启动条件 + 违 §核心原则 11 Root Cause 优先)
- **越过用户对话授权门槛自决策全废**(类比 D148 Phase 2 H15 / D149 Phase 2 H12 范式 — Phase 0 §字段 10 (e) 自决策评估倾向 C-D 但决策行不锁定,等用户对话明确锁定后才入 Phase 1 — 范式延续)
- **Followup F1 ctor PARAM default value 起 D150 sub-D 全废**(已入 D149 §A.3 — SS 已自然支持 function PARAM default value)
- **Followup F6 ternary type inference 起 D150 sub-D 全废**(D149 §Followup 启动条件留 bootstrap-context-only — standalone GREEN 不复现,bootstrap-context-only 真有 case 再起首)
- **改 D149 主线 / D148 主线 / D025 / D052 / D127 / D067 等依赖 D 文档全废**(D149 主线已 close + D148 bidirectional 接管不破 + 依赖 D 文档不破 — D150 仅 followup 起首选择)
- **引入新关键字 / 新语法全废**(CLAUDE.md §Java/TS 语法优先红线;TS / Dart / Kotlin 都不引入新语法支持 partial named arg / spread / method PARAM default)
- **F5 v2 总体设计推翻 D135-D149 累计 14 sub-D 决策全废**(C-D F5 是「累计后总体规划」非「推翻已落决策」— D148 bidirectional / D149 partial named arg 等已落决策不破,F5 仅锚定 D150-D155 后续优先级 + 范畴 + 阶段实施)
- **annotation handler 旁路 v2 总体设计全废**(`feedback_no_derive_workaround.md` 红线 — 主线能力缺口不允许用 @derive / annotation handler 作为替代路径)

---

## Phase 收关锚

### Phase 0: D 文档落档 + 候选评估 fact 入档 + 决策行不锁定 留用户对话授权 [✓] Done at commit `<placeholder>`(留 D150 Phase 1 启动轮回填 — D135-D147 范式 单 commit 不能引用自己 hash 下下轮回填)(2026-05-03)

- **D150.md 文档新建** ~300-500 行(本 commit)— Status header + Depends on D149/D148/D052/D127/D025 + Date 2026-05-03 + §核心目标 + §核心原则(7 条)+ §1 Context(D149 主线 close 后 followup 状态 + 累计 sub-D 链路 + 业界对标 + Java 反例不沿袭)+ §2 RED 锚 + §3 Orchestration Phase 0-2+ + §A.1 C-A/C-B/C-C/C-D 四候选评估 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 + §Phase 收关锚 + §Followup + §Status 时间线 Phase 0 entry
- **D149 Phase 5 commit hash `51781ce` 回填 10 处真锚 6 行非均匀分布**(line 3 含 2 字串 Status header + line 138 含 2 字串 §3 Orchestration 表 Phase 5 行 + line 369 含 1 字串 §Phase 收关锚 §Phase 5 标题 + line 372 含 1 字串 全 Phase 0-5 hash trail Phase 5 占位 + line 373 含 1 字串 §Phase 收关锚 §3 Orchestration mention + line 420 含 3 字串 §Status 时间线 Phase 5 entry — 用户口号「6 处真锚」实测占位符行数 = 6 / 字串数 = 10 非均匀分布 line 420 含 3 字串,memory `feedback_user_literal_vs_d_ssot` 同形防御 12 次落档 PSM §字段 3,与历史「字面 vs 实测」refine 反差实证延续)
- **D150 sub-D 候选评估 fact 入档完成**(§A.1 决策行 — C-A F2 field 拓扑排序 / C-B F3 method PARAM default codegen / C-C F4 spread / C-D F5 v2 总体设计四候选评估表 7 维度对比 + §字段 10 (e) 自决策评估倾向 C-D > C-B > C-A/C-C 五维全胜 + 决策行不锁定 留用户对话授权门槛触发)
- **§字段 10 (e) 自决策评估倾向 C-D**(根因解决度 + 长久 / 演化维度 — 底层依赖链 + 业界对标 + N 年返工度 + D150+ 后续 sub-D 起首返工率 — 五维全胜)
- **决策行不锁定 留用户对话授权门槛触发**(类比 D148 Phase 2 H15 / D149 Phase 2 H12 范式 — C-D F5 v2 总体设计涉及多个 sub-D 优先级 + 范畴定义,长久演化影响范围扩到 D150-D155,需用户对话锁定 C-A/C-B/C-C/C-D)
- **§A.2 H1-H10 加入**(H1 D149 主线 close 后 followup RED 启动条件已具备 ✓ + H2 F5 v2 实测假设触发条件已具备 ✓ + H3 用户对话授权门槛触发留 Phase 1 + H4 C-D v2 总体设计可覆盖 D150-D155 留 Phase 2+ + H5-H8 各候选 scope LOC delta 实测留 Phase 1 + H9 bootstrap 三阶段固定点不破留 Phase 2+ + H10 不引入新语法 ✓)
- **VCM §1 豁免锚成立**(Phase 0 docs-only — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D149-*.md 回填 hash + 新建 docs/3-decisions/D150-*.md)
- **simplify 跳过 docs-only 例外**(纯文档 D149 hash 回填 + D150.md 新建)
- **d_doc_index_linter F1=0 GATE OK** + **ultrathink_linter PASS** + **D135-D149 范式延续**
- **MNK §M meta-gate 强制四问全 ✓**(深度读 D149.md §1 Context bidirectional 关键设计 entry 5 行 + §A.1 决策行 C3 锁定 + §A.1.1 G1/G2/G3 落点 + §A.2 H1-H13 隐藏假设 H10 OOD 其他全 PASS + §3 Orchestration Phase 0-5 全 [✓] + §Phase 收关锚 Phase 0-5 entry + §Followup F1-F6 + 历史 D148 Phase 7 commit `729b6f1` 主线 close → D149 启动 commit `91f8b80` 范式 → D149 Phase 5 commit `51781ce` 主线 close → D150 启动范式延续 + D150 启动条件验证未漏 + 兑现 a-h 总览每条 file:line 锚 + 用户口号「6 处真锚」实测 6 行 10 字串非均匀分布 line 420 含 3 字串 refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 12 次落档 PSM §字段 3)
- **D150 Phase 0 commit hash 留 D150 Phase 1 启动轮回填**(D135-D147 范式 — 单 commit 不能引用自己 hash 下下轮回填)

### Phase 1+ Planned

- 用户对话授权门槛触发 + 候选锁定(C-A / C-B / C-C / C-D)
- C-D 锁定 → 本 D 扩展为 v2 总体设计 D 文档 + D151-D155 sub-D 起首接力实施
- C-A/C-B/C-C 锁定 → D150 主线 = F2/F3/F4 任一 RED → GREEN + 剩余 followup 留 D151+

---

## Followup

> **D150 Phase 0 落档后 — 候选锁定后展开**(2026-05-03):候选锁定后(Phase 1),后续 sub-D 起首队列由 C-D F5 v2 总体设计统一规划(若锁定 C-D)或单点 sub-D 接力起首(若锁定 C-A/C-B/C-C);本 §Followup 表暂留候选锁定后填充。

| # | 锚 | 描述 | 启动条件 |
|---|---|---|---|
| F1 | D149 §F6 ternary type inference bootstrap-context-only refine | bootstrap-context-only 真有 case 再起首(standalone GREEN 不复现) | 启动条件留 bootstrap-context-only 真有 case |
| F2 | ctor PARAM default value 全机制(`function ctor(x: int = 0)` 函数参数默认值)| function/method PARAM default 已支持(D149 §A.3 废案 F1 实测兑现),ctor PARAM 待 D025 决策行更新 | 启动条件留 D025 决策行更新 |
| F3 | bidirectional 全局深化 | D148 已落 NEW_EXPR ctor + array literal,扩 obj literal / Tuple / 泛型实参 | C-D 锁定后展开 |

---

## Status 时间线

- 2026-05-03 Phase 0 D 文档落档 + 候选评估 fact 入档 + 决策行不锁定 留用户对话授权 docs only(commit `<placeholder>` 留 D150 Phase 1 启动轮回填)— **D150 Phase 0 兑现 a-h 八项 fact 全 GREEN + D149 Phase 5 commit `51781ce` 回填 10 处真锚 6 行非均匀分布(line 420 含 3 字串)+ D135-D149 范式延续**:(a) D149 Phase 5 commit hash `51781ce` 回填 10 处真锚 6 行非均匀分布(line 3 含 2 字串 Status header + line 138 含 2 字串 §3 Orchestration 表 Phase 5 行 + line 369 含 1 字串 §Phase 收关锚 §Phase 5 标题 + line 372 含 1 字串 全 Phase 0-5 hash trail Phase 5 占位 + line 373 含 1 字串 §Phase 收关锚 §3 Orchestration mention + line 420 含 3 字串 §Status 时间线 Phase 5 entry — 用户口号「6 处真锚」实测占位符行数 = 6 / 字串数 = 10 非均匀分布 line 420 含 3 字串 refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 12 次落档 PSM §字段 3,与历史 Phase 0「3 处」→ 4 实测 / Phase 1「3 处」→ 4 实测 / Phase 2「4 处」→ 4 字面=实测 / Phase 3「8 处」→ 6 行 8 字串 / Phase 4「6 处」→ 5 行 6 字串 / Phase 5「5 处」→ 5 字面=实测 / D150 启动「6 处」→ 6 行 10 字串非均匀分布的 refine 反差实证延续);(b) D150.md 新建 ~300-500 行 docs-only(本 commit)— Status header + Depends on D149/D148/D052/D127/D025 + Date 2026-05-03 + §核心目标 + §核心原则 7 条 + §1 Context D149 主线 close 后 followup 状态 + 累计 sub-D 链路 + 业界对标 + §2 RED 锚 + §3 Orchestration Phase 0-2+ + §A.1 C-A/C-B/C-C/C-D 四候选评估 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 + §Phase 收关锚 + §Followup + §Status 时间线;(c) §字段 10 (e) 自决策评估倾向 C-D > C-B > C-A/C-C(根因解决度 + 长久 / 演化维度 — 底层依赖链 + 业界对标 + N 年返工度 + D150+ 后续 sub-D 起首返工率 — 五维全胜);(d) 决策行不锁定 留用户对话授权门槛触发(类比 D148 Phase 2 H15 / D149 Phase 2 H12 范式 — C-D F5 v2 总体设计涉及多个 sub-D 优先级 + 范畴定义,长久演化影响范围扩到 D150-D155,需用户对话锁定 C-A/C-B/C-C/C-D);(e) §A.2 H1-H10 加入 + §A.3 废案 8 条;(f) VCM §1 豁免锚成立 docs-only(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D149-*.md 回填 hash + 新建 docs/3-decisions/D150-*.md);simplify 跳过 docs-only 例外;d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK 3/3 PASS;(g) MNK §M meta-gate 强制四问全 ✓(深度读 D149.md §1 Context bidirectional 关键设计 entry 5 行 + §A.1 决策行 C3 锁定 + §A.1.1 G1/G2/G3 落点 + §A.2 H1-H13 隐藏假设 H10 OOD 其他全 PASS + §3 Orchestration Phase 0-5 全 [✓] + §Phase 收关锚 Phase 0-5 entry + §Followup F1-F6 + 历史 D148 Phase 7 commit `729b6f1` 主线 close → D149 启动 commit `91f8b80` 范式 → D149 Phase 5 commit `51781ce` 主线 close → D150 启动范式延续 + D150 启动条件验证未漏 + 兑现 a-h 总览每条 file:line 锚 + 用户口号「6 处真锚」实测 6 行 10 字串非均匀分布 line 420 含 3 字串 refine);(h) D150 Phase 0 commit hash 留 D150 Phase 1 启动轮回填(D135-D147 范式 — 单 commit 不能引用自己 hash 下下轮回填);**新发现**:(i) D149 主线 close 后 D150 起首延续 D148 → D149 范式(D148 Phase 7 commit `729b6f1` 主线 close → D149 启动 commit `91f8b80` 范式 → D149 Phase 5 commit `51781ce` 主线 close → D150 启动 commit `<placeholder>` 范式延续 — 单 commit 不能引用自己 hash 下下轮回填);(ii) F5 v2 总体设计实测假设触发条件兑现 — 累计 sub-D 单点起首 ≥ 3(F2 + F3 + F4 D149 Phase 4 实测 RED 启动 D150+)+ F6 启动条件留 — D150 启动轮 §字段 10 (e) 自决策评估倾向 C-D > C-B > C-A/C-C(C-D 五维全胜:根因解决度 + 底层依赖链 + 业界对标 + N 年返工度 + D150+ 后续 sub-D 起首返工率);(iii) 决策行不锁定不是「拖延」而是「授权门槛触发」— Phase 0 §字段 10 (e) 自决策已倾向 C-D,但 v2 总体设计涉及多个 sub-D 优先级 + 范畴定义,长久演化影响范围扩到 D150-D155,触发 H3 类比授权门槛(类比 D148 Phase 2 H15 / D149 Phase 2 H12 范式),Phase 0 启动轮不自决策,等用户对话明确锁定后才入 Phase 1 候选范畴细化;(iv) D135-D149 sub-D 链路 + D150 起首选择 — 累计 14 sub-D 链路 D135 → D136 → D137 → D140 → D141 → D142 → D143 → D144 → D145 → D147 → D148 → D149 close → D150 起首选择 + 候选锁定后路径分支(C-D v2 总体设计 / C-A/C-B/C-C 单点起首);(v) D150 Phase 0 commit hash 留 D150 Phase 1 启动轮回填(D135-D147 范式 — 单 commit 不能引用自己 hash 下下轮回填);(vi) D149 主线 close + D150 起首选择 next_prompt 转向 D150 Phase 1 启动轮(用户对话授权门槛触发 + 候选锁定 + Phase 0 hash 回填)
