# D171: SEMA Q2 — comptime 解释器语言覆盖度补全（走统一 evalExpr）

**Status:** **DONE** — Phase 1-5 全 **[x] Done**（Ph1 闭包/arrow 可调用含捕获；Ph2 spread 数组字面量 + ct 数组 `.length`；Ph3 super / 继承方法 + 继承字段构造；Ph4 try/catch/throw/finally；Ph5 loud-gate 审计 + 覆盖度回归套件 + 高阶数组方法回调根因修复）。D171 SEMA Q2 里程碑达成 — comptime 解释器覆盖完整语言主构造,残余静默 fallback 全 loud。**收口验收 PASS（2026-05-29）**:行为级穷举 parity(46 probe,string/array/map 全方法 + 主构造值 vs runtime 逐一比对)零静默误编译,覆盖套件硬化 37→59,**合并就绪**(详见 §下一步 收口验收条 + 4 发现 A/B runtime 范围外、**C 已修复**(comptime double 物化 follow-up)、D 已知 deferred)。
**Depends on:** D088（Zig 路线 / §核心验证三问 / Phase 6-8）, D093（SEMA Q1 单函数 dispatch — closure 宣告）, D094（comptime purity）, D098（SEMA Value Model — InternPool / Type-as-Value）
**Date:** 2026-05-29

---

## 第一性需求

**comptime 块里能跑的 SS 子集 = 整个 SS 语言。**

D088 Zig 路线的本质是「编译器即解释器，解释器 = 完整语言」（§Phase 8）：任意 SS 代码都能在 `comptime {}` 里跑，每补一个解释器缺口，comptime 就能多做一件事。

D093（SEMA Q1）已达成路线的**架构层**——一份 `evalExpr` 单函数 dispatch，comptime 与 runtime 共享同一求值路径（§差距 #1-#5 全 [x] Done，`grep -rn "comptimeDepth > 0" bootstrap` = 0，3026f14 端到端审计宣告 closure）。但**架构统一是必要非充分**：统一后的 `evalExpr` 仍不覆盖全部 SS 构造。2026-05-29 实测 comptime 里：

| 构造 | probe（comptime 内） | 现状 |
|---|---|---|
| 闭包 / arrow 调用 | `const add=(a,b)=>a+b; return add(3,4)` | ❌ `[comptime] unknown function: add` → **静默返 0**（应 7） |
| spread 数组字面量 | `const b=[...a, 3]; return b.length` | ✅ **Phase 2 [x] Done** — 实测根因非 spread（展平本就工作）而是 ct 数组 `.length` 走错访问器恒返 0；改走 `interpArrayLen` 后 = 3 |
| try/catch/throw | `try{throw("e")}catch(e){return e}` | ❌ throw 逃逸为 comptime error，catch 不捕获 |
| super / 继承方法 | `super.speak()` | ✅ **Phase 3 [x] Done** — 实测根因非继承链 walk 缺失(interpFindMethod 已 walk parent)/非 super 缺 this(THIS/SUPER 已返 interpThisVal),而是**注册表不对称**:顶层 class 入 classNodeIds/classParents 却被 comptime 方法解析忽略;改走 consult-both 对称 helper 后继承方法 / super 可调 |

（**已工作**：enum / class 实例化 / 数组+对象解构 / spread 调用参数 / while / for — probe 实测 GREEN，见 §历史语境。）

**消除覆盖度缺口不是锦上添花，是 Zig 路线第一性需求的兑现。** 闭包与 spread-array-lit 当前是**静默误编译**（编译"成功"但产出错误值 0），违反 D088 §Phase 8「未知 comptime expression 不静默断流，改为 exit(1)」不变量——这正是 D093 §第一性需求所说的"假装 bug"（看似过了，实则结果错）。

### 为什么（Why 链）

1. **不做** → 用户写 comptime 闭包/spread 静默得到错误值 0，编译通过但运行行为错误（可观测：`bin/ss run /tmp/d171_p1_closure.ss 2>&1 | grep -c "unknown function"` = 1）。
2. **根本上** → D088 Zig 路线本质 = "编译器即解释器，解释器 = 完整语言"。覆盖度不全 = comptime 不是完整解释器 = Zig 路线未达成。D093 关掉了"两份求值逻辑"，但没让"那一份"覆盖完整语言。

---

## 历史语境

- **D088（2026-04-13）定路线**：Phase 5（`obj.fields()` / bracket / 循环展开）[x] Done。Phase 6-8（comptime class / enum / try / closure / destructure / spread / super）在 D092 interp.ss 双轨期 `[-] Blocked` / superseded。2026-04-13 路线修正明示：「下方表格特性（ENUM_DECL / destructuring / spread / super）在 D093 骨架就位后按**新路径**补回，不按 D092 的 `interp*` 家族路径」。**D171 = 兑现这句承诺。**
- **D093（SEMA Q1，closure at 3026f14）统一架构**：一份 `evalExpr` + `MaybeVal` + `comptimeMustBeKnown` flag。§差距 #1-#5 全 [x] Done。closure 宣告把 value-storage 迁移（Part B）handoff 给 D098 §Phase C step 2 远期可选 track（trigger「深比较成瓶颈」unmet）。
- **D098 Value Model**：9 kind 全入 InternPool，`interpValEquals` 收敛 O(1) eql。Type-as-Value Phase B（Type 句柄走 InternPool）大体达成（`bootstrap/eval/interp_value.ss:179` `internPoolGetOrInsert(\`type|${className}\`, newTvType(className))`）。

**D093 关 Q1（架构 = 一份逻辑），D171 接 Q2（覆盖度 = 那一份覆盖完整语言）。** 两者正交：Q1 防"两份不同步的假装 bug"，Q2 防"一份但有洞的静默误编译"。

---

## 决策

**SEMA Q2 里程碑 = comptime 解释器语言覆盖度补全**：让 D088 Phase 6-8 残留缺口（闭包 / spread 数组字面量 / try-catch / super）在 comptime 跑通，**走 D093 统一 `evalExpr` 路径，不复活 interp.ss 双轨、不新开 comptime 专用 dispatch、不加 ct* 辅助函数**。

每 Phase 三件事：
1. 一个具体 SS 构造从 comptime ❌ → ✅（满足 D088 §核心验证 Q1「新 SS 语法能在 comptime 跑」）。
2. 该 path 的静默 fallback（`return ctVal(interpNewNull())` 等解码为 0）替换为：能求值则求值，真 runtime-only 则 loud `comptimeError`（兑现 D088 §Phase 8 不变量）。
3. 新增 `tests/phase5/d171_*.ss` 回归测试 + bootstrap 三阶段固定点 + 全测 baseline 持平。

### 为何选覆盖度（自决策，禁列菜单 — MNK §字段 10(e)）

4 个开放 SEMA 项按**根因解决度 + 第一性需求覆盖度**排（**禁按工程量排序** — CLAUDE.md §Root Cause）：

| 候选 | 层次 | 根因解决度 | 第一性需求覆盖度 | 判定 |
|---|---|---|---|---|
| **A. comptime 覆盖度补全** | 能力层 | **高** — D088 §核心验证 Q1 直接兑现 + D093 统一架构的 payoff（一份 evalExpr 后，补 case = 补能力，不复活双轨） | **最高** — "解释器 = 完整语言"是 Zig 路线本质 | **✓ 选** |
| B. Type-as-Value Phase B | 数据层 | 低 — Type 已入 InternPool（key `type|`），余 tag-bit 去除 D098 §决策 3 自判「Phase B InternPool 后 tag 位反而可去除，现在做就是负资产」 | 低 | ✗ |
| C. Part B §Phase C step 2 | 架构层 | 看似最深，但 trigger「深比较成瓶颈」**unmet** — `interpValEquals` 已 O(1)（D093 端到端审计实证 + D098 L245「9 kind dedup 已是 Zig SOTA 形态足」）；起手 = 无触发的过早优化 | 低（正交于覆盖度） | ✗ correctly deferred |
| D. 类型系统增强 | 语言层 | 中，但 D088 已 de-scope 泛型 comptime 参数「SS 已有泛型，无驱动场景」；union/intersection 等非 SEMA 路线第一性需求 | 低 | ✗ |

**(d) 业界对标（横向演化）**：Zig 演化顺序 = 先架构统一（Sema 单 dispatch）→ 后覆盖完整语言。D093 已做架构统一，候选 A 是「先 X 后 Y」的自然下一步；候选 C 依赖「深比较成瓶颈」trigger（Zig 也是瓶颈才迁 value storage），未到。**(e) 自决策单一 X = 候选 A。**

---

## Phase 拆解

按 foundational 度 + 静默误编译严重度排（闭包 / spread 静默返 0 最严重先补；super / try 至少 loud-ish 后补；loud-gate 审计收尾）。每 Phase 一个 RED → GREEN，各 Phase Execute 轮起手再细化 PSM。

| Phase | 范围 | 缺口性质 | RED（现状） | GREEN 验收 |
|---|---|---|---|---|
| **1** | 闭包 / arrow 在 comptime 可调用（含外层变量捕获） | 静默返 0 | `[comptime] unknown function` | `add(3,4)` = 7 |
| 2 | spread 数组字面量 `[...a, x]` | 静默返 0 | `[...a,3].length` = 0 | = 3 |
| 3 | super / 继承方法在 comptime | loud error | `no method on class` | 继承方法可调 |
| 4 | try / catch / throw 在 comptime | throw 逃逸 | `comptime error: err` | catch 捕获 |
| 5 | loud-gate 审计 + comptime 覆盖度回归套件 | 残余静默 fallback | 审计 evalExpr 全 case | 未覆盖构造必 loud `comptimeError`，无静默返 0 |

> 本 D 文档只锚 milestone + 第一性需求 + Phase 骨架 + Phase 1 RED。详细 Step / 关键 file:line / 反模式见各 Phase Execute 轮起手 PSM。

### Phase 1 起手目标（最孤立、半建成、最高杠杆）

**目标**：comptime 块内 `const f = (...) => ...` 绑定的 arrow 可被 `f(...)` 调用并正确求值（含外层 comptime 变量捕获）。

**根因定位（§字段 12(a) 已 grep 实测）**：

| file:line | 角色 | 现状 |
|---|---|---|
| `bootstrap/eval/eval_expr.ss:44` | ARROW_FUNC 求值 | 已建好：`if (k == "ARROW_FUNC") { return ctVal(interpNewVal("fn", \`${astId}\`)) }` —— `const add = (a,b)=>a+b` 已把 `add` 绑到一个 fn-kind 值（指向 arrow 的 astId） |
| `bootstrap/eval/eval_expr.ss:29` | 注释 | 明示「THIS/SUPER/ARROW_FUNC ct-depth 特例留 Phase 4」——**求值端建好，调用端未接** |
| `bootstrap/gen/exprs/exprs_ct_call.ss:266` | CALL 分派 fallback | 按名字查顶层函数注册表（`ctFuncNodes` / `interpClasses`）未命中 → `println("[comptime] unknown function") + return ctVal(interpNewNull())`（解码为 0）——**静默误编译的 swallow 点** |

**Phase 1 改面（走统一 evalExpr，不新开注册表）**：CALL 分派在落「unknown function」之前，先查 callee 名是否为绑定了 fn-kind 值的 `ctVar`；命中则取 ARROW_FUNC 的 astId，提取 params + body，绑定实参，**复用 `exprs_ct_call.ss:246-263` 的 body 执行 + 返回值捕获机制**求值；外层变量捕获沿 `ctVars` 作用域链解析。真顶层函数未命中 + 非 fn-value → 升 loud `comptimeError`（替换 line 266 静默 null）。

**Phase 1 RED（可观测，现状已固化 2026-05-29）**：

```bash
cat > /tmp/d171_p1_closure.ss <<'EOF'
function main() {
    const v = comptime {
        const add = (a: int, b: int) => a + b
        return add(3, 4)
    }
    println(`closure result = ${v}`)
}
EOF
bin/ss run /tmp/d171_p1_closure.ss 2>&1 | grep -c "unknown function"
# 现状(RED): 1  + 输出 "closure result = 0"(应为 7) — 静默误编译
# Phase 1 后(GREEN): 0 + 输出 "closure result = 7"
```

正式落地时固化为 `tests/phase5/d171_comptime_closure_call.ss`。

**Phase 1 拒绝准则（根因防偏 — 与 D088 §反模式 / CLAUDE.md §Root Cause 联动）**：

- 若闭包调用需要新开 `ctClosure*` / `ctArrowReg` 注册表 → **退化双轨，禁**。fn-value 已在 InternPool（D093 §差距 #3「fn 入 value pool 显式注册 `fn|${id}`」），调用端只能**消费**现有 fn-value，不另立通道。
- 若外层变量捕获需新 ct* 数据结构 → 回 `evalExpr` / `ctVars` 作用域协议修订，不在 CALL 局部 hack。
- spike 崩（捕获语义不机械 / fn-value astId 不可达 body）→ 回方案层（D088 §核心验证 Q2/Q3 复核），不全量 Execute。

---

## 核心验证三问对照（D088 §验证标准 §核心验证，每 Phase 必过）

| D088 §核心验证 | D171 适配 |
|---|---|
| **(1) 新 SS 语法能在 comptime 跑?** | **是** — 每 Phase 一个构造从 ❌ → ✅（闭包 / spread / super / try）。这是 milestone 的定义判据。 |
| **(2) 从根儿上走 Zig 路线?**（双轨制两问清零） | (a) 不是双轨根因——补的是统一 `evalExpr` 的 case 覆盖，非第二份求值器；(b) 不维持双轨——禁新开 `ctClosure` / ct* 注册表，消费现有 fn-value / InternPool。 |
| **(3) Zig 式 SEMA 架构?** | 是——所有覆盖都落在唯一 `evalExpr` dispatch 表，无 comptime 专用独立分支 / 独立文件 / 独立注册表。 |

---

## Rejected Alternatives

- **A. 复活 interp.ss / 新开 comptime 专用 dispatch** — D088 §反模式 + D093 §Rejected A/C，双轨制根因，过不了 §核心验证 Q2/Q3。
- **B. 先做 Type-as-Value Phase B tag-bit 去除** — D098 §决策 3 自判「Phase B InternPool 后 tag 位反而可去除，现在做就是负资产」；且不让任何新 SS 语法在 comptime 跑（过不了 Q1）。
- **C. 起手 Part B §Phase C step 2（interp* value 表示迁 InternPool）** — trigger「深比较成瓶颈」unmet（D093 端到端审计实证 `interpValEquals` 已 O(1)）；无触发的过早优化，违反 Zig「瓶颈才迁」演化判据。`valOf/valType` 访问器边界已隔离 caller，未来 trigger 命中可无痛起手。
- **D. 类型系统增强（泛型 comptime 参数 / union）** — D088 已 de-scope 泛型 comptime 参数；非 SEMA 路线第一性需求。
- **E. loud-gate 先行（先把所有静默 0 转 exit(1)，不补能力）** — 不让任何新语法在 comptime 跑，过不了 §核心验证 Q1（会被判「偏离」）。loud-gate 作为每 Phase 内建纪律 + Phase 5 收尾审计，**不单列前置**。

---

## 张力

1. **闭包捕获语义** — arrow 引用外层 comptime 变量（如 `let base = 100; (x)=>x+base`），`ctVars` 按 `currentFunc:name` 键存，跨 arrow body 的作用域链解析需明确（lexical capture vs 调用时查找）。Phase 1 spike 验证。
2. **fn-value 的 astId 稳定性** — ARROW_FUNC 求值返 `interpNewVal("fn", astId)`，astId 是 AST 节点 id；arrow body 的 `cloneAstNode` / 重入是否保持 astId 一致需核。
3. **try/catch 在 comptime 的异常通道** — runtime 异常走 PIR / landingpad，comptime 无 runtime 栈；comptime throw/catch 需在 `evalExpr` 层用 flag（类 `interpReturnFlag`）模拟，是 Phase 4 核心编码决策。
4. **覆盖度"终点"判据** — "完整语言"无法穷举 grep，需一套 comptime 覆盖度回归套件（Phase 5）作为可观测代理判据，而非声称"全覆盖"。

---

## 下一步

- **[x] Done** Phase 1：闭包 / arrow 在 comptime 可调用。`exprs_ct_call.ss` `ctCallDispatch` 在「unknown function」前经 `ctResolveFnNodeId(name)` 解析 callee→绑定的 fn-kind ctVar 值→ARROW_FUNC astId（作用域链镜像 `eval/ident.ss`，外层捕获沿 `ctVars` 同 key 协议解析），与顶层 `ctFuncNodes` 统一到同一 `if (ctFuncId > 0)` bind+exec（复用 lines 206-263，零重复，不新开 ct* 注册表）；静默 null fallback 升 loud `comptimeError`（D088 §Phase 8 不变量）。GREEN：`add(3,4)=7` + `grep -c "unknown function"=0`，回归测试 `tests/phase5/d171_comptime_closure_call.ss`（简单/捕获/多捕获/嵌套 4 例），bootstrap 三阶段固定点 + 全测 335→336 passed（+1 新测，3 pre-existing 不变）。
- **[x] Done** Phase 2：spread 数组字面量 `[...a, x]` + comptime 数组 `.length`。**§字段3 最小变量隔离实测翻案根因**：spread 展平（`array_lit.ss:27-40` SPREAD_ELEM 分支）**本就工作**（probe `b[0..2]` 全对），真正断流在 `.length` —— `member_access.ss:23-26` 旧路径经 `interpAsStr`（读 tvS1 字符串列）`.split(",")` 数长度,而数组数据存 `tvArrElem`/`tvI2`、tvS1 对数组恒空 → **任何 ct 数组 `.length` 恒返 0**（连普通 `[1,2].length` 亦然）。改走权威 `interpArrayLen`（`interp_obj.ss:39` 读 `tvI2`，全库 array 长度唯一源；string 分支保留 `interpAsStr().length()`）。GREEN：`[...a,3].length` 0→3 + `[1,2].length` 0→2，回归测试 `tests/phase5/d171_comptime_spread_array.ss`（RED case / 元素值 / 中间 spread / 双 spread / 普通数组 5 例），bootstrap 三阶段固定点 + 全测 336→337 passed（+1 新测，3 pre-existing 不变）。走 D093 统一 `evalExpr`/`interpArray*`，不新开 ct* 注册表（D171 §拒绝准则 / D088 §反模式）。
- **[x] Done** Phase 3：super / 继承方法在 comptime 可调用。**§字段 3 最小变量隔离实证翻案根因**:prompt 三假设 (a) interpFindMethod 未沿继承链上溯 / (c) super 缺 this 绑定 **均伪**（`interp_obj.ss:347` 早已 walk `interpClassParents` / `eval_expr.ss:40` THIS/SUPER 早已返 `interpThisVal`）;真根因 = (d) **注册表不对称** —— comptime 块内声明的 class 入 `interpClasses`/`interpClassParents`,顶层(runtime)class 入 `classNodeIds`/`classParents`（`class_register.ss:183` / `class.ss:23,75`),而 `interpFindMethod` + `resolveSuperParent` comptime 分支**只查前者** → 顶层 class 的方法在 comptime **整体断流**（PROBE 实测连非继承的顶层 `Animal.speak()` 都失败,非仅继承）。两表 scope 不同（comptime-ephemeral class 不得泄漏为 runtime LLVM struct）故不合并,改抽 `interpResolveClassNode`/`interpResolveParent` 两 helper（comptime 表优先 → 顶层表 fallback,SSoT 化 I014 §路径 A 已在 `ctNewExprDispatch` field walk 建的 "consult both" 契约）,`interpFindMethod`（方法派发）+ `resolveSuperParent` comptime 分支（super 解析）+ `ctNewExprDispatch` field walk（继承字段构造）+ `interpBuildTypeInfo` field walk（`.fields()` 反射 — `/simplify` 4 agent 复查发现的第四处同形不对称,comptime 子类 extends 顶层 class 时漏顶层父字段,实测 fields 数 1→2）四处统一走 helper。`isSubclassOf`（exprs_ct_call.ss:221）复查为**非 bug**:comptime 声明 class 经 pending-ct flush 亦入 `classParents`,实测对 comptime class = 1（已正确）。loud-gate 保留（no-method / 无父类 super / 父类缺方法均 loud `comptimeError`,D088 §Phase 8 不变量,VCM §4 三边界实证）。GREEN:`d.speak()` 继承 = "generic" + `super.speak()` 可调 + `grep -c "no method 'speak'"` 1→0 + comptime 子类 `.fields()` 1→2,回归测试 `tests/phase5/d171_comptime_super_inherited.ss`（RED canonical / super 透传 / super 增强 / 完全 override / 多级继承 / 继承字段构造 / 继承字段反射 7 例),bootstrap 三阶段固定点 + 全测 337→338 passed（+1 新测,3 pre-existing 不变）。走 D093 统一 `evalExpr`/`interpFindMethod`,不新开 ct* 注册表（D171 §拒绝准则 / D088 §反模式）。
- **[x] Done** Phase 4：try / catch / throw 在 comptime 可捕获。**§字段 3 最小变量隔离实证**：prompt 三假设 (a) throw 无异常 flag /(b) try 无 catch landing /(c) catch 无 bind **三处全断**（probe A `try` 无 throw = `tryRan` 正常 → try 执行本就 OK；probe B 裸 throw = `exit(1)`；RED catch 不运行），singular 根因 = **comptime 异常流未建模**（非单点 bug）。comptime 无 runtime 栈/landingpad（§张力 3），throw 改 raise `interpThrowFlag`/`interpThrowVal`（`interp_core.ss` 镜像 `interpReturnFlag`/`Val`，纳入 `interpShouldStop`/`interpCheckLoopExit` 中央短路 → genBlock 语句边界 / 循环 / 函数调用自动传播，无须改 loop/switch/if/call handler），`genThrow` ct 分支 set flag 替 `exit(1)`、非编译期常量 throw 值升 loud（`stmts_exc.ss`），`genTryCatch` ct 分支建 catch landing（`ctDispatchComptimeCatch` 多 clause 顺序匹配：untyped 全捕 / typed 走 `interpResolveParent` 继承链 — Phase 3 权威 consult-both 复用；bind `ctVars` 同 `${currentFunc}:${name}` key 协议；无匹配 re-raise），`ctRunComptimeFinally` save/clear/restore pending throw/return（标准 finally 语义：finally 正常结束不吞控制流 / 自身 throw/return 覆盖），未捕获在 `runComptimeBlockBody` 升 loud `comptimeError`（D088 §Phase 8 不变量，probe B 实证）。GREEN：RED `grep -c "comptime error: boom"` 1→0 + `trycatch result = boom`，回归测试 `tests/phase5/d171_comptime_trycatch.ss`（RED canonical / catch 绑值表达式 / try 正常跳 catch / 嵌套内层捕获 / 嵌套 re-raise 外层捕获 / finally return 覆盖 / finally 保留 pending / typed catch 继承链 / typed no-match 落 catch-all 9 例），bootstrap 三阶段固定点 + 全测 338→339 passed（+1 新测，3 pre-existing 不变）。reflection_health_linter 3 项硬 REGRESSION（M1/M5/N3）走 §扩容申报-Phase4 bump（非反射路径合法特性增长，flag 模拟本质赋值密集 → M5）。走 D093 统一 `evalExpr`/`genBlock` + 现有 `ctVars`/`interpResolveParent`，不新开 ct* 异常注册表（D171 §拒绝准则 / D088 §反模式）。
- **[x] Done** Phase 5：loud-gate 审计 + comptime 覆盖度回归套件。**§字段 3 最小变量隔离 probe 矩阵（12 例,/tmp/d171p5/）实测分类**「17 `return ctVal(interpNewNull())` + 10 `[comptime]` 诊断」非裸 count:**legit-null 8**（NULL_LIT / COMPTIME_EMIT void / println·print·emit·registerFunction·comptimeAssert·writeFile 6 intrinsic void 返回）/ **已 loud·dead-after-exit 4**（comptimeError 自身 / compileError exit 后 / THIS·SUPER·unsupported-expr strict 兄弟行已 loud）/ **arg-guard 1**（getTypeInfo 0-arg,checker arity 守门）/ **真·静默返 0 确认转 loud 12**（unknown class PA / cannot-call-method-on-nonobject PB / unsupported string·array·map method PC·PD·PE / ctCallValue not-fn PL / no-builtin-method·UNARY 兜底 2 防御 unreachable / postfix 未绑定 PG2 / for·while·do-while runaway 截断 PF×3）。**翻案 prompt 断言**:obj-destructuring probe PI 实测 = 已覆盖(exit 0 正确,非「已 loud 含混」);Map.getInt probe PH 坐实「已 loud 含混」(annotation arg PARAM,挂 I003b strict marker,非本 phase「静默返 0」scope)。**§衍生阻挡根因修复**:写覆盖度套件时 probe X8/X11 发现高阶数组方法（map/filter/reduce/forEach）回调**静默返 0**——`ctCallValue` 读 fn-value astId 用 `parseInt(interpAsStr(fnValId))`（空 string 槽 tvS1 恒 0 → funcNodeId=0 → genBlock 不跑），根因修复改 `interpAsInt(fnValId)`（astId 存 tvI1,sibling `ctResolveFnNodeId` 早已 interpAsInt）——阻挡 §张力 4 覆盖套件交付故本轮修（CLAUDE.md §Root Cause 第一法则:修根因不排除 .map 出套件）。12 点转 loud 走全库唯一 `comptimeError(msg, id)`（线程 `id` 入 5 builtin 函数 ctBuiltinMethod/ctStringMethod/ctArrayMethod/ctMapMethod/ctCallValue + ctNewExprDispatch,精确 line:col 诊断,不用 nodeId=0 降级）。GREEN:probe PA-PL 全 exit 1 + `error: [comptime] ... at line N:M`,sanity PI/PJ/PK/S1/S2 仍 exit 0;正向 `tests/phase5/d171_comptime_coverage.ss`（12 类 breadth:字面量/算术/pow/一元/三元 + string·array(含 map/filter/reduce)·map 方法 + 闭包+捕获 + spread + enum + class+继承+super + try/catch/finally + 解构(array/rest/obj) + while/for/do-while/for-in + 泛型,§张力 4「完整语言」终点代理判据）+ 负向 4 `tests/phase5/d171_comptime_loud_*.ss.txt`（unknown_class/unsupported_method/notfn_callback/postfix_unbound,commit-time shell verify exit 1 + 消息 + `error: [comptime]`)。bootstrap 三阶段固定点 + 全测 339→340 passed（+1 新覆盖套件,3 pre-existing 不变）。**reflection_health_linter GATE PASS — 无 REGRESSION 无 bump**（与 Phase 4 异:loud-gate 转换 = `println+return null` → `comptimeError(id)` **节点中性**,M1 5812→5812 / M5 1941→1941 不增可变 state;非 Phase 4 flag 模拟的赋值密集 → 无 §扩容申报-Phase5）。走 D093 统一 `evalExpr`/`comptimeError`,不新开 ct* 注册表（D171 §拒绝准则 / D088 §反模式）。
- **D171 SEMA Q2 里程碑达成**（Phase 1-5 全 Done）:comptime 解释器覆盖完整语言主构造,未覆盖构造（嵌套闭包返回闭包超 ctVars 平坦作用域链 — §张力 1）正确 loud comptimeError 非静默（D088 §Phase 8 不变量兑现）。残余 deferred:Map.getInt typed-getter 含混消息（I003b strict marker)、嵌套闭包 lexical capture（D098 §Phase C value-storage 远期 trigger unmet）。
- **[x] Done 收口验收（2026-05-29）— 行为级穷举 parity,核心不变量 PASS**。吸取 Phase 5 `.map` bug 根本教训（grep-站点命中 ≠ 行为穷举:方法在 dispatch 表里且 exit 0 却静默产错值),验收判据从 exit code 升级为**返回值 vs runtime oracle 逐一比对**（`/tmp/d171_acc/parity_final.ss` 46 probe）。**全集覆盖**:string 全 13 / array 全 9 / map 已覆盖 8 / 主构造 10+，**comptime 值与 runtime 完全一致 → 零静默误编译**（D088 §Phase 8 不变量行为级验证成立,§张力 4 代理判据兑现）。**4 发现逐一最小变量隔离分类（均非新静默点）**:(A) runtime `[scalar].join(sep)` **段错误**（int/double/bool 数组全崩,string/nested ref 正常;**comptime join 反而正确** `"1-2-3"`）—— **runtime codegen bug,D171 范围外**,待立项;(B) runtime `slice(start,负 end)` 返空 vs **comptime 正确**（`end<0 → len+end`）—— runtime 局限,范围外;(C) `comptime { return <double> }` → `gen_types.ss:294` 用 `interpAsStr`（读空 tvS1 而非 `tvD1`)→ llc 崩 —— **[x] 已修复（comptime double 物化 follow-up 轮,候选 B / `comptime_double_materialize.options.md`)**:根因双层 L1 跨读(tvS1 恒空)+ L2 %g 丢精,修复=`newTvDouble`(interp_value.ss:191)把 exact `doubleBits(d)` 副本存入 tvS1(原恒空) + `gen_types.ss:294` 与 `materialize()`(interp_value.ss:39)物化为 `0x<16hex>` LLVM 精确 double 常量。同根除 L1 崩(tvS1 不再空)+ L2 静默丢精(读 exact bits 非 `tvD1` %g)+ **附带修复 runtime double 常量折叠丢精**(`10.0/3.0` 旧 `store double 3.33333` → 现 `0x400aaaaaaaaaaaab` exact,共享 materialize() 根);**且同根除 D169 §POC 失败 N1**(`eval_expr.ss:50` 同源 tvS1 跨读 0.0 / -3.14 regression)。验收:`let x=comptime{return 3.5+1.25}` RED `store double ,` → GREEN + `10.0/3.0`·`0.1+0.2` comptime==runtime bit-exact + bootstrap 三阶段固定点 + 全测 340 持平(3 pre-existing baseline 实测同失败)。**残余 backlog**:chained comptime double 算术精度(`interp_op.ss:83` `parseDouble(interpToStr)` 回读 tvD1 %g)= 独立既有根因(候选 C「exact comptime double 算术」,需 bits→double 回读 builtin);`class_comptime.ss:48` annotation arg 走 human %g 十进制(class_annotation.ss:129 metadata 显示,本就正确不改 **[2026-05-29 纠正:此判定误——实测第三物化 sink LOSSY 进数值消费(非仅显示)→ 立项 I032,见末条]**）;(D) `Map.getInt` plain map → `exprs_ct_builtin.ss:238` 把 int 值当 AST 节点 id 走 `evalAnnotationArg` → loud —— 非静默,已知 deferred（I003b strict marker,本 §下一步 已列）。**oracle 反转洞见**:A/B 中 comptime 比 runtime 更正确,行为 probe 双向有效。**覆盖套件硬化**:`d171_comptime_coverage.ss` probe 37→59（+18 断言,补 trim/toLowerCase/replace/startsWith/endsWith/charAt/includes/repeat/substring 语义锁/indexOf 边界 + push storeback/forEach 捕获变异/indexOf 边界/slice 负 end + getBool/delete/keys),永久封堵 `.map` 类盲区。VCM §1 核心路径 diff=0 豁免 bootstrap,VCM §3 改坏期望值实证断言活性。**D171 合并就绪**;A 待立项,**C 已修复**(comptime double 物化 follow-up),D 维持既有 deferred。
- **[x] Done — chained comptime double 算术回读精度(2026-05-29 follow-up,`comptime_double_arith.options.md` GATE 6/6)**。RED `comptime { let t=10.0/3.0; return t*3.0 }` 物化 9.99999(`interp_op.ss:83` `interpNumericBinop` double 回读走 `parseDouble(interpToStr)` 读 tvD1=%g,中间值 t 跨操作丢精:存 "3.33333" 回读 ×3.0=9.99999)。根因修复=新增 `bitsToDouble` 反向 builtin(`gen_rt_string.ss` hex16→`strtoull(,16)`→i64→`bitcast double`,`ss_doubleBits` 逆;`declare strtoull`@gen_runtime + funcRetTypes/builtinMap/checker funcNames+allFuncNameList+oneArgFns 注册照 `parseDouble` 同形模板),`interpNumericBinop` double 回读改 `bitsToDouble(interpAsStr)` 从 tvS1 IEEE754 exact-bits 重建,与物化路径(materialize/gen_types exact-bits)**对称闭环**(算术回读=精确位 / human 显示=tvD1 %g 两路分离,interpToStr 显示路径不动)。GREEN:9.99999→10 + comptime==runtime bit-exact(parity probe)+ 单 op 不退化 + `(0.1+0.2)*10` IEEE754 residue 保真复现 runtime(反向断言非伪精确)+ 负数符号位往返。回归 `tests/phase5/d171_comptime_chained_double.ss`(6 case:chained/多级/residue 反向/混 int-double/单 op,doubleBits bit-exact 判据)。bootstrap 三阶段固定点(新 builtin 两步:先注入能力再接入回读)+ 全测 340→341(+1,3 pre-existing 不变),reflection_health GATE PASS 无 bump(M1 5811/M5 1941/N3 590846 全 budget_max 内,合法增长落 Phase 4 预算)+ sunset GATE OK 无新 marker。VCM §3:stash+rebuild 改前 chain=9.99999+新测试 FAIL ↔ 改后 GREEN。走 D093 统一 `interpNumericBinop`(1 helper×2 caller=eval_expr BINARY + pow_binary Pow),不新开 ct* 注册表(D171 §拒绝准则 / D088 §反模式)。**`/simplify` altitude 发现同根因第三物化 sink**:`class_comptime.ss:48` `rewriteIdentToLit` double 分支读 tvD1(%g)→ 裁决 probe 实测 LOSSY 进**数值消费**(`@methodOf` handler 捕获外层 comptime double 算术绑定,getRatio hex `400aaaa8eb463498`≠精确 `400aaaaaaaaaaaab`)——纠正上一轮"本就正确不改"误判(漏 `gen_decls store double` + `parseDouble` re-parse 路径),立项 **I032**(DOUBLE_LIT S1 表示契约冲突 hex-vs-十进制需独立根因设计,依赖本轮 `bitsToDouble` 底座)。
- **[x] Done — comptime double IDENT 折叠第三物化 sink(2026-05-29 follow-up,`comptime_double_ident_fold.options.md` GATE 6/6,I032 Resolved)**。RED `@methodOf` handler 捕获外层 `const ratio=10.0/3.0`,生成 `getRatio()` 返 `400aaaa8eb463498`≠精确 `400aaaaaaaaaaaab`(`rewriteIdentToLit` double 分支 `class_comptime.ss:48` 读 tvD1=%g 6 位丢精,进数值消费 `==` 返 false)。根因修复=候选 C **架构层**:fold 改 `doubleToStringExact(bitsToDouble(tvStringOf(pl)))`——新增 `doubleToStringExact` builtin(`ss_doubleToStringExact`+`@.rt.fmt.g17` `%.17g`=binary64 DBL_DECIMAL_DIG round-trip;funcRetTypes/names→ss_ 映射/checker strFns+oneArgFns 注册照 `doubleBits` 同形),`tvStringOf`=tvS1 exact-bits → `bitsToDouble` 重建 → `%.17g` 物化 round-trip 十进制 S1 + `.0` guard 补整数值小数点(LLVM `global double 3` REJECT)。**S1 单一统一契约"round-trip decimal" → 3 消费点(store double / parseDouble×2 / annArgToSrc)零改动 bit-exact**(spike 证伪候选 A hex-in-S1:llc `-0x` REJECT + atof/SS lexer 不 lex hex)。GREEN:getRatio bit-exact + `==` true;回归 `tests/phase5/d171_comptime_double_ident_fold.ss`(7 case,VCM §3 pre-fix exit 1↔fixed exit 0)。bootstrap 三阶段固定点(新 builtin 2-stage:Stage A 注册→Stage B 接入)+ 全测 342(341+1,3 pre-existing 不变)+ reflection_health GATE PASS 无 bump(record 同步)+ sunset GATE OK。**finding C 根因家族(sink1/2 materialize+gen_types · 算术回读 interpNumericBinop · 本第三 sink fold)全清**。
- **[x] Done — finding C 闭环审计(2026-05-29,`interpToStr` 显示路径穷举)**。I032 修复后唯一残余 `tvD1`(%g)读取点 = `interp_op.ss:37` `interpToStr`(`grep -rn tvD1 bootstrap/` 实证:tvD1 其余引用仅 `interp_value.ss` decl/`new Map()` init/`newTvDouble` write + 注释;数值回读 `interpNumericBinop`(`interp_op.ss:83-84`)走 `bitsToDouble(interpAsStr)`=tvS1 exact-bits **非 tvD1**)。`interpToStr` 8 caller 逐一判定**全 human 显示 / string-format,无数值消费/物化/比较路径**:template-lit(`template_lit.ss:29`)/ string `+` concat(`eval_expr.ss:153`)/ array.join(`exprs_ct_builtin.ss:137`)/ getString annotation coerce(`exprs_ct_builtin.ss:243`)/ comptimeError 诊断(`stmts_core.ss:69`)+ 3 处 `parseInt`(`exprs_ct_call.ss:36/41/53`,int 无丢精)。**关键不变量**:这些 double→string 路径的 comptime `%g`(tvD1/interpToStr)与 runtime `%g`(`ss_double_to_string`@`@.rt.fmt.g`,`exprs_str_conv.ss:24` `genExprAsString` 经 println/模板/concat 唯一源)**字节一致** → 零 parity 偏离(**非 sink**:lossy 但 comptime==runtime,与"物化/算术=exact-bits"两路分离设计对称)。行为级穷举 `/tmp/d171_findingC_audit_probe.ss` 4 probe 全 `match=1`(P1 tmpl `0.3`==`0.3` / P2 chain+disp `10`==`10` / P3 concat `v=3.33333`==`v=3.33333` / P4 join `1.5|0.3`)。**结论:无第 4 个 %g 漏精 sink,comptime double 忠实性闭环,D171 SEMA Q2 合并就绪**(finding A runtime scalar.join 段错 待立项 / D finding Map.getInt I003b deferred 维持 backlog,不混入;push/PR 待用户人工触发)。
- **[x] Done — finding A runtime scalar 数组 `.join` 段错修复(2026-05-29 follow-up,`findingA_scalar_join.options.md` GATE 6/6,候选 B 接口层 trap)**。RED `let a=[1,2,3]; a.join("-")` Segmentation fault exit 139(int/double/bool 数组全崩,string 正常;comptime 正确=oracle 反转;本 §行 161/164 "待立项"兑现)。根因双层:**R1 结构错位**——array.join 错置 `genStringMethod`(无类型信息)被 dispatch 截胡(`gen_methods.ss:546`<`550`),无条件 `_ss_join(List<string>)` 把 scalar 位值当 `String*` 解引用 → 段错;**R1b 推断路径**——`inferArrayElemType` 不处理 ARRAY_LIT,`let a=[1,2,3]`(无标注)varType 退化 `ptr` 丢元素类型(显式 `Array<int>` 标注路径不受影响)。根因修复=array.join 归位 dispatch type-dependent 区(`gen_methods.ss`,持 objId 按 `inferArrayElemType` 分派 typed prelude 变体 `_ss_joinInt`/`_ss_joinDouble`/`_ss_joinBool`,变体内 `result+arr[i]` 复用 `genExprAsString` 单一真相源)+ 删 `genStringMethod` join 错置分支(`gen_builtins.ss`)+ `inferArrayElemType` 补 ARRAY_LIT 首元素 inferType(`gen_types.ss`,`listGet` 取节点 id 非 string 索引)+ regen `prelude_embed`。**spike 两次迭代暴露真因下沉**(推断路径 ARRAY_LIT 缺失 → nGetList 逗号串非数组)。GREEN:int `1-2-3`/double `1.5-2.5`/string `x-y-z`(回归保护)/bool `1-0`(不段错)/单元素/空/标注路径全 ✅,回归 `tests/phase5/findingA_scalar_join.ss`(11 assert),bootstrap 三阶段固定点 + 全测 342→343(+1,3 pre-existing 不变)+ reflection_health GATE PASS(gen_methods/gen_types AUTO-DRIFT < budget_max,合法 LOC 增长)+ sunset GATE OK。**bool 显示 "1"/"0" vs comptime/JS "true"/"false" = `genExprAsString` bool 分支既有缺陷(模板插值 `${true}` 同样 "1",先于 join)→ 立项 I033 不混入**(非阻挡段错核心)。B(slice 负 end)/D(Map.getInt I003b)finding 维持 backlog。

**本 D 文档不触发任何 `.ss` 代码改动，不跑 bootstrap。代码改动从 Phase 1 Execute 轮开始。**

---

## 扩容申报-Phase4-comptime-trycatch（reflection_health_linter）

Phase 4（comptime try/catch/throw，flag 模拟异常通道）落地后 `tools/reflection_health_linter.ss` 3 项**硬 REGRESSION**（M1/M5/N3），均为**非反射路径的合法特性增长**：Phase 4 在 `bootstrap/gen/stmts/`（被 scope filter 粗粒度判为反射白名单域）补 comptime 异常流，而 flag 模拟（§张力 3 唯一根因方案 — comptime 无 runtime 栈/landingpad，不能走 setjmp/longjmp）**本质赋值密集**（set/clear/save/restore flag），非反射 Meta/`.fields`/`.methods` 膨胀。

**§第一性需求关联**：D171 §第一性需求「comptime = 完整语言」，try/catch 是 D088 Phase 7 明列缺口；不补则 Zig 路线未兑现。该增长是能力的内在成本，非八股（反身性：去掉则 catch 不捕获、throw exit、finally 不跑）。

**delta 表**（cur = Phase 4 后实测；HEAD = Phase 1-3 累积，3 项全 AUTO-DRIFT soft 未 bump → 本轮 Phase 4 tip 过 1% 硬线）：

| 指标 | 定义 | HEAD(Ph1-3) | Phase 4 cur | 我的 slice | 旧 bm(来源) | 新 bm | 性质 |
|---|---|---|---|---|---|---|---|
| **M1** | 节点/边计数 | 5794 | 5813 | +19 | 5750(D148) | **5830** | 代码增长 |
| **M5** | 可变 state(VAR_DECL+赋值数) | 1917 | 1941 | +24 | 1900(D148) | **1955** | flag set/clear/save/restore 本质赋值密集 |
| **N3** | AST 深度总和 | 589506 | 590609 | +1103 | 584000(D168) | **592000** | 代码增长 |
| M7b | 函数总数 | 749 | 752 | +3 | 750 | 不 bump | AUTO-DRIFT soft（3 helper，留 1% 设计豁免） |
| M3a | 调用边数 | — | 13751 | — | 13700 | 不 bump | AUTO-DRIFT soft |
| N4 | 最大出度 | 352 | 352 | +0 | 350 | 不 bump | AUTO-DRIFT soft（delta=0 非本轮） |

**本地抵消路径（A 路径不可达）**：flag set/clear/save/restore 是 finally/catch 正确语义的最小赋值集（M5 +24），typed catch 走 `interpResolveParent` 复用 Phase 3 权威解析（零新数据结构）；削 ~24 M5 / ~1103 N3 必阉割特性（去 typed catch / 去 finally 语义），违 Root Cause（不为迁就 stale 预算砍特性）。故走 **B 路径扩容申报**，只 bump 3 个硬 REGRESSION，soft AUTO-DRIFT（M7b/M3a/N4）留 1% 设计豁免不 bump。

**预估 vs 实测**：bump 后 cur ≤ 新 bm（M1 5813≤5830 / M5 1941≤1955 / N3 590609≤592000），re-run gate 预期 PASS（实测见 VCM §1）。

---

## 参考

- D088 §第一性需求 / §核心验证三问 / §Phase 6-8 / §反模式
- D093 §第一性需求（一份求值逻辑）/ §端到端审计（3026f14 closure 宣告）/ §差距 #3（fn 入 InternPool）
- D098 §决策 3 Type-as-Value / §决策 2 §Phase C（Part B deferred）
- D094 §规则 1 Comptime = 纯计算
- Zig comptime：编译器即解释器，Sema 覆盖完整语言 — https://ziglang.org/documentation/master/#comptime
