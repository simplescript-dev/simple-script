# D171: SEMA Q2 — comptime 解释器语言覆盖度补全（走统一 evalExpr）

**Status:** **DONE** — Phase 1-5 全 **[x] Done**（Ph1 闭包/arrow 可调用含捕获；Ph2 spread 数组字面量 + ct 数组 `.length`；Ph3 super / 继承方法 + 继承字段构造；Ph4 try/catch/throw/finally；Ph5 loud-gate 审计 + 覆盖度回归套件 + 高阶数组方法回调根因修复）。D171 SEMA Q2 里程碑达成 — comptime 解释器覆盖完整语言主构造,残余静默 fallback 全 loud。**收口验收 PASS（2026-05-29）**:行为级穷举 parity(46 probe,string/array/map 全方法 + 主构造值 vs runtime 逐一比对)零静默误编译,覆盖套件硬化 37→59,**合并就绪**(详见 §下一步 收口验收条 + 4 发现 **A/B/C 已修复**(A scalar.join 段错 / B slice 负 start/end 归一 / C comptime double 物化,均 follow-up)、D 已知 deferred(Map.getInt I003b))。
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
- **[x] Done — I033 runtime bool→string 显示 parity 修复(2026-05-29 follow-up,`i033_runtime_bool_display.options.md` GATE 6/6,候选 C 接口层根因双站点)**。RED `let b=true; \`${b}\`` → "1" / `[true,false].join("-")` → "1-0",偏离 comptime oracle `interpToStr`→"true"/"false" + JS `String(true)="true"`(行 165 立项兑现)。**§字段 12 实证修正 I033 issue-doc 原推荐**:"仅 `genExprAsString` 补 bool 分支" 对 inferred var / 数组 join **inert** —— 根因是 gen 层 bool→int 折叠**两站点**:**A** `gen_types.ss:274` `inferType(TRUE_LIT/FALSE_LIT)` 折叠 "int"(致 `let b=true` 传播 int + `[true,false]` dispatch `_ss_joinInt`,bool 分支不可达);**B** `genExprAsString` 缺 bool 分支落 `ss_int_to_string`。根因修复=站点 A 返 "bool" + 站点 B 补 `if(vType=="bool")`→`ss_bool_to_string`(现成 gen_rt_string.ss:308),bool 类型流过全链、三 sink(模板/拼接/join)单一真相源,零新 runtime IR/函数,bool@IR=i32 + mangling 不变无 ABI break。GREEN:inferred/annotated/bare/join/concat 全 "true"/"false",comptime parity 兑现;回归 `tests/phase5/i033_runtime_bool_display.ss` + 修正 findingA 旧 "1-0" 断言,bootstrap 三阶段固定点 + 全测 343→344(+1 新测,3 pre-existing 不变)+ `.bugfix` 6 gate PASS。**comparison/logical→bool 推断(I034 残留)/ comptime-scalar bool-return 折叠(`gen_types.ss:318`)= 另 sink 维持 backlog 不混入**。
- **[x] Done — finding B runtime `slice` 负 start/end 归一修复(2026-05-29 follow-up,`findingB_slice_negative_end.options.md` GATE 6/6,候选 B 接口层 trap,`.bugfix` 6 gate PASS)**。RED `a.slice(1,-1).join("-")` runtime 返空(comptime/JS oracle `20-30`)、`slice(-3,-1)` 越界垃圾 `[4-4]`、`slice(-10,2)` 读未初始化内存、单参 `slice(-2)`/`slice(1)` 编译报错(行 161 "范围外" / 行 165 "维持 backlog" 兑现)。根因双层:**L1** runtime `ss_arraySlice`(`gen_rt_array.ss`)仅 `end>len` 上界 clamp,缺负索引归一(`start<0→len+start` / `end<0→len+end`)+ start 下界 clamp,负 start 直入 GEP `srcp` 越界,与 comptime `ctArrayMethod` slice(`exprs_ct_builtin.ss:156-159` 已正确归一)双轨分裂;**L2** codegen `gen_builtins.ss` 无脑读 `slArgs[1]` + checker `(2,2)` 拒单参。根因修复=`ss_arraySlice` IR 加 start/end 负归一(`neg→len+neg`)+ start 下界 clamp 0 + GEP 改用 clamped `%s_c`(**runtime 函数边界单一真相源**,method call + 解构 rest 所有调用点 + 变量负索引自动受益,与 comptime 归一语义对称)+ codegen 单参 end 缺省 sentinel `2147483647`(复用解构 rest gen_decls.ss:399 既有 sentinel)+ checker `registerMethodParams Array.slice (2,2)→(1,2)`。GREEN:`slice(1,-1)→20-30`/`slice(-2)→30-40`/`slice(-3,-1)→20-30`/`slice(1)→20-30-40`/`slice(-10,2)→10-20`(越界负 start clamp)/`slice(0,-100)→空` 全对齐 comptime oracle + 变量负 end 证 runtime 归一(非 codegen 字面量 hack)+ 解构 rest 不变。回归 `tests/phase5/findingB_slice_negative_end.ss`(16 assert,含 runtime==comptime parity 4 例)。VCM §3:stash `gen_rt_array.ss` + rebuild → `slice(1,-1)` exit 1 `got ""` ↔ 恢复 all pass。bootstrap 三阶段固定点 + 全测 344→345(+1,3 pre-existing 不变)+ reflection_health GATE PASS 无 REGRESSION(漂移项 DRIFT/AUTO-DRIFT < budget_max)+ sunset GATE OK 无新 marker。net_new_ifs=1 / net_new_fns=0 / same_pattern_count=0(slice 是唯一双索引 array runtime;字符串 substring start+count 语义 JS 本身 clamp 非 len+neg,非同模式)。**finding A/B/C 全清,D(Map.getInt I003b)维持 deferred;I034 comparison→bool 推断 / comptime-scalar bool-return 折叠 gen_types.ss:318 维持 backlog 不混入。D171 §收口验收「行为级穷举 parity 零偏离」兑现**。
- **[x] Done — comptime-scalar bool-return 折叠修复(2026-05-29 follow-up,`comptime_bool_return_fold.options.md` GATE 6/6,候选 C 接口层根因 inferType 单站点 + 消费侧补全,`.bugfix` 6 gate PASS)**。RED `let b=comptime{return true}; \`${b}\`` → "1" / `comptime{return 1<2}` → "1" / 全局 `let g=comptime{return true}` → "1",偏离 comptime oracle `interpToStr`→"true"/"false" + JS `String(true)`(行 166 I033 §末「comptime-scalar bool-return 折叠 gen_types.ss:318 维持 backlog」立项兑现;**是 I033 runtime 字面量折叠的镜像同根** = gen 层 bool→int 折叠族,I033 修字面量站点 `gen_types.ss:278`,本轮修 comptime-return 站点)。根因(单一概念根 = gen 层把 comptime bool-return 折叠 int):**站点 A**(根)`gen_types.ss:324` `inferType(COMPTIME_EXPR)` 对 `ceType=="bool"` 原 `set/return "int"` → 改 `"bool"`(literal 仍 `tvIntOf`=1/0 不变,bool@IR=i32 `ssTypeToLLVM:746`/mangling:847 无 ABI break,值物化 `eval_expr.ss:102` 经 `constVal` 与 int 字节一致)→ bool 类型经 `inferType` 流过 `${b}`/拼接/join 三 sink,复用 `genExprAsString` bool 分支(`exprs_str_conv.ss:35`,I033 遗产)+ `ss_joinBool`(`gen_methods.ss:544`)单一真相源,零新 runtime IR/函数;**站点 B**(消费侧补全)`gen_decls.ss` 全局物化 `if(ceType=="int"||"bool")` + `gType=ceType`(防站点 A 改后落 `else`→`global ptr null` regression;simplify 合并 int/bool 去重 emitIR → net_new_ifs=0)。GREEN:function-local/global/comparison/logical/concat/join/多片段模板全 "true"/"false" + comptime==runtime parity;回归 `tests/phase5/comptime_bool_return_fold.ss`。VCM §3:stash `gen_types.ss`+`gen_decls.ss` + rebuild → RED test exit 1 ↔ 恢复 all pass。bootstrap 三阶段固定点 + 全测 345→346(+1,3 pre-existing 不变)+ reflection_health GATE PASS(gen_decls 747≤750 / gen_types 916≤1050,DRIFT 软)+ sunset GATE OK 无新 marker。net_new_ifs=0 / net_new_fns=0 / same_pattern_count=0(comptime bool-return 折叠唯一站点 gen_types.ss:324 已修;显示侧/值物化/全局物化均复用或已补,无第二处残留)。**I034 comparison→bool runtime 推断残留 / Map.getInt I003b 维持 backlog 不混入。D171 §收口验收「行为级穷举 parity 零偏离」comptime bool 显示族闭环**。
- **[x] Done — I034 runtime comparison/logical→bool 推断残留修复(2026-05-29 follow-up,`i034_comparison_logical_bool.options.md` GATE 6/6,候选 C 接口层根因 inferType 单站点 + 假设破裂闭合,`.bugfix` 6 gate PASS)**。RED `let b=1<2; \`${b}\`` → "1" / `true&&false` → "0" / `[1<2,3>4].join("-")` → "1-0",偏离 comptime oracle `interpNewBool`(`interp_op.ss:50-55` 比较 + short-circuit 逻辑均返 bool tv)→ "true"/"false" + JS `String(1<2)="true"`(行 166/167/168 末「I034 comparison→bool runtime 推断残留 维持 backlog」立项兑现;**是 I033 字面量站点 `gen_types.ss:278` + comptime-bool-return 站点 `gen_types.ss:324` 的镜像同根第三折叠站点** = gen 层 bool→int 折叠族)。根因(单站点 A + 假设破裂闭合,`gen_types.ss` only):**站点 A**(根)`gen_types.ss:377` `inferType(BINARY)` 对 comparison(Eq/Ne/Lt/Gt/Le/Ge)+ logical(And/Or)+ instanceof 原 `return "int"` → 改 `"bool"`(各 cmp/短路/instanceof 出口仍 `zext i1→i32`,bool@IR=i32 `ssTypeToLLVM:750`/mangling `i` 无 ABI break)→ bool 类型经 `inferType` 流过 var 传播 / 数组 join dispatch(→`ss_joinBool` `gen_methods.ss:544` findingA 遗产)/ `genExprAsString` bool 分支(`exprs_str_conv.ss:35` I033 遗产)/ Not-unary 委派(`gen_types.ss:586` → `!(a<b)` 自动得 bool)单一真相源,零新 runtime IR/函数;**假设破裂闭合**:`gen_types.ss:383` 算术/位运算 fallthrough 既有 `if(binLt=="i64")` guard 合并 `binLt=="bool"` → `if(binLt=="i64"||binLt=="bool")return "int"`(simplify 采纳,JS bool→number 强制,防 `(a<b)+1` 误显 "true" 新 parity 破裂,parity comptime `(1<2)+1`=2,附带闭合 I033-latent `true+1` 误显 "true" 漏)。**instanceof 纳入根因闭合**(同 line 376 sibling、JS `String(x instanceof Y)`→bool、IR 出口同 i32、`grep instanceof bootstrap/` 仅 eval import 零风险、tests 全 `if(x instanceof Y)` 条件态;comptime 不支持 instanceof,parity 基准 JS 语义)。GREEN:comparison 全 6 运算符 + &&/||(含短路)+ 模板/拼接/join 三 sink + Not-unary + instanceof 全 "true"/"false" + comptime==runtime parity(rt==ct 逐一比对);回归 `tests/phase5/i034_comparison_logical_bool.ss`(24 assert)。VCM §3:stash `gen_types.ss` + rebuild → RED test exit 1 ↔ 恢复 all pass。bootstrap 三阶段固定点 + 全测 346→347(+1,3 pre-existing 不变)+ reflection_health GATE PASS(gen_types 927≤1050,DRIFT 软)+ sunset GATE OK 无新 marker + `.bugfix` 6 gate PASS。net_new_ifs=0 / net_new_fns=0 / same_pattern_count=0(comparison/logical/instanceof 折叠唯一站点 `gen_types.ss:377` 已修;显示/join/Not-unary 全复用 I033/findingA 遗产,算术 fallthrough 既有 i64 guard 合并 bool 闭合,无第二处残留)。**无消费侧站点 B**:global 顶层非字面量 comparison `let g=1<2` → llc `store ptr 1` error 是 pre-existing 独立根因(全局物化 ptr null 路径,与 inferType 显示无关),非本轮 regression,维持 backlog 不混入;Map.getInt I003b deferred 维持。**D171 §收口验收「行为级穷举 parity 零偏离」runtime bool 显示族(字面量 I033 / comptime-return / comparison-logical-instanceof I034)三站点全闭环,合并就绪**。
- **[x] Done — global 非字面量 int/bool 全局物化 ptr 误用修复(2026-05-29 follow-up,`global_scalar_materialize.options.md` GATE 6/6,候选 B 接口层 trap,`.bugfix` 6 gate PASS)**。RED 全局 `let g=1<2` → llc `store ptr 1, ptr @g` "integer constant must have integer type" 硬失败(`grep -c 'error: llc'`=2);`true&&false`(逻辑)/`a+b`(算术)/`f():int`(int 函数调用)/标注 `Array<int>` array-get 全局初值同崩(**行 169 I034 末「global 顶层非字面量 comparison ... pre-existing 独立根因(全局物化 ptr null 路径)维持 backlog」立项兑现** — 根因在全局物化路径 `gen_decls.ss`,与 I033/I034 inferType 显示无关)。根因(单文件 2 站点,gen_decls.ss 全局物化接口边界):**站点 A** `genGlobalVar` else 分支对所有非 fn 类型无条件 `@x = global ptr null`,realType=int/bool 时值实为 i32(comparison `zext i1→i32` / 逻辑 `genShortCircuit` i32 / 算术 `add i32` / array-get 内部 `trunc i64→i32` / int-call `call i32`)→ 物化 ptr slot 类型错;**站点 B** `emitGlobalInits` 对称 `store ptr <i32val>` → llc 崩。根因修复=站点 A `realType==int/bool` → `@x = global i32 0, align 4` + `gType=realType`(与同函数 COMPTIME_EXPR 分支 `gen_decls.ss:258` int/bool 物化模板对齐)+ 站点 B 对称 `store i32`(读取侧 `genIdent` 经 `getVarType→ssTypeToLLVM` 自动 `load i32`,literal int 全局 `let n=5` 已验此路径),零新 runtime IR/函数,bool@IR=i32 无 ABI break,**无需额外 trunc 安全网**(genExpr 对所有在范围 int/bool 表达式均返 i32)。GREEN:comparison 全 6 运算符 + &&/|| + 算术 + int-call + 标注 array-get 全局全编译通过 + 显示 parity("true"/"false"/数值)+ comptime==runtime 值比对;回归 `tests/phase5/global_scalar_materialize.ss`(17 assert)。VCM §3:stash `gen_decls.ss` + rebuild → RED test exit 1 ↔ 恢复 all pass。bootstrap 三阶段固定点 + 全测 347→348(+1,3 pre-existing 不变)+ reflection_health GATE PASS(F1 gen_decls 759 走 **§扩容申报-global-scalar-materialize** bump 750→765,合法特性增长;N2/N3/N4 soft drift 不 bump)+ sunset GATE OK 无新 marker + `.bugfix` 6 gate PASS。net_new_ifs=2 / net_new_fns=0 / same_pattern_count=0(全局非字面量 int/bool 物化唯一 2 站点,均已对称修)。**无标注全局 array-get `let a=[..]; let m=a[1]` = 独立根因(genGlobalVar 缺 inferArrayElemType→setVarType(Array<elem>) 传播,与 genVarDecl:576-581 不对称,非标量物化)→ 立项 I035 不混入**;Map.getInt I003b deferred 维持。**D171 §收口验收「行为级穷举 parity 零偏离」comparison-area 全局物化 gap 闭环 — runtime parity 族(I033 字面量 / comptime-return / I034 comparison-logical / 本全局物化)全清,合并就绪**。
- **[x] Done — I035 无标注全局数组 var 元素类型未传播致 array-get 全局物化 llc 硬失败修复(2026-05-29 follow-up,`global_array_elem_infer.options.md` GATE 6/6,候选 B 接口层 trap,`.bugfix` 6 gate PASS)**。RED 无标注全局 `let a=[10,20,30]; let m=a[1]` → llc `store ptr %10, ptr @m`（`%10`=i64,defined with type 'i64' but expected 'ptr'）硬失败(`grep -c 'error: llc'`=2;**行 170 末「无标注全局 array-get … → 立项 I035 不混入」兑现** — array-get **推断侧** gap,与 global_scalar_materialize 标量物化侧正交)。根因(接口层,gen_decls.ss var-decl 元素类型传播契约不对称):genVarDecl(局部,:587-593)honors `typeAnn=="" && initType=="ptr"` → `inferArrayElemType` → `setVarType(Array<elem>)`,genGlobalVar(全局)else 分支**缺此传播** → 无标注全局数组 varType 退 "ptr" 丢元素类型 → 下游 `inferType(a[1])` 退化返 i64 → `@m=global ptr null` + `store ptr <i64>` → llc 崩。根因修复=genGlobalVar else 分支 annotation=="" 子支补 `else if(realType=="ptr"){ inferArrayElemType→gType=Array<elem> }`,镜像 genVarDecl:587-593(SSoT 化 local/global 元素类型契约,**不在 array-get 物化点补回查** workaround),元素类型在 decl 站点确立 → 下游推断/物化/trunc 全链自动正确(int/bool 走 global_scalar_materialize i32 slot,string 走 ptr slot),零新函数零新 runtime IR。GREEN:int/string/bool 无标注全局 array-get 编译通过 + 值/显示 + comptime==runtime(`comptime{let ca=[10,20,30];return ca[1]}` parity)+ 局部对称 working-reference;回归 `tests/phase5/global_array_elem_infer.ss`(11 assert)。VCM §3:pre-fix bin/ss run test exit 1(`store ptr %10, ptr @gI0`)↔ bootstrap 后 fixed exit 0。bootstrap 三阶段固定点 + 全测 348→349(+1,3 pre-existing 不变)+ reflection_health GATE PASS(gen_decls 759→763 ≤ bm765,**无 bump**,+4 行在既有 budget 内)+ sunset GATE OK 无新 marker + `.bugfix` 6 gate PASS。net_new_ifs=2 / net_new_fns=0 / same_pattern_count=0(var-decl 元素类型传播唯二站点 genVarDecl/genGlobalVar 现对称,genDestructureArray 逐元素语义不复用,无第三残留)。**carve-out(本轮验证衍生,正交不混入):无标注全局 double 物化(`let g=1.5+2.5` 非数组同崩=general gap / double array-get)= materialization 侧 ptr slot store double(I035 后 double 元素类型已正确传播 Array<double>,IR 实证),非 propagation 侧 → 立项 I036(global_scalar_materialize int/bool 物化家族 double 未扩);Map.getInt I003b deferred 维持**。**D171 §收口验收 runtime parity 族(I033 字面量 / comptime-return / I034 comparison-logical / global_scalar_materialize 标量物化 / 本 I035 元素类型传播)全清,合并就绪**。

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

## 扩容申报-global-scalar-materialize（reflection_health_linter）

global 非字面量 int/bool 全局物化修复（gen_decls.ss 2 站点对称物化 i32 slot）落地后 `tools/reflection_health_linter.ss` 1 项**硬 REGRESSION**（F1 `gen_decls.ss`），为**合法特性增长**：全局 comparison/逻辑/算术/int-call int/bool 物化是 D171 §收口验收 comparison-area 最后 correctness gap，补此能力须在 `genGlobalVar` else 分支 + `emitGlobalInits` 各加 int/bool 分派（net +12 行）。

**§第一性需求关联**：D171 §收口验收「行为级穷举 parity，零静默误编译 / 零硬失败」+ §第一性需求「comptime = 完整语言」的 runtime 对侧；不补则顶层 `let flag = a > b` 编译失败（语言基本能力残缺）。该增长是能力内在成本，非八股（反身性：去掉则整类全局非字面量 int/bool 不可编译）。

**delta 表**（cur = 本轮后实测）：

| 指标 | 定义 | HEAD | cur | 我的 slice | 旧 bm(来源) | 新 bm | 性质 |
|---|---|---|---|---|---|---|---|
| **F1 gen_decls.ss** | 文件行数 | 747 | 759 | +12 | 750(D170) | **765** | 2 站点 int/bool 物化分派（genGlobalVar else + emitGlobalInits）合法增长 |
| N2 | 节点字节估算 | — | 433090 | ~0 | 432000(D168) | 不 bump | AUTO-DRIFT soft（0.25% 内，主 pre-existing 累积） |
| N3 | AST 深度总和 | — | 593007 | ~0 | 592000(D171-Ph4) | 不 bump | AUTO-DRIFT soft（0.17% 内，主 pre-existing 累积） |
| N4 | 最大出度 | 352 | 360 | +0 | 350 | 不 bump | SCOPE-DRIFT soft（diff 未触反射白名单；baseline 352 已 pre-existing > bm 350，本轮 gen_decls 嵌套分支不增 max 出度） |

**本地抵消路径（A 路径不可达）**：2 站点 int/bool 分派是物化 i32 slot 的最小代码集（声明 + store 各 1 分支），削则阉割特性（回退 `global ptr null` → llc 崩）；拆 `gen_decls.ss` 为 9 行不值当（文件职能内聚：函数 decl + 全局 var + var decl + return + destructure）。**MNK §B.2 形态 8 禁止压缩注释挤 F1 阈值**（近阈值正解 = 拆文件或 bump，不改字符密度）→ 保留根因注释（本文件 I014 4 行注释先例），走 **B 路径扩容申报**只 bump F1 gen_decls 1 项硬 REGRESSION；soft AUTO/SCOPE-DRIFT（N2/N3/N4，主 pre-existing 累积非本轮）留设计豁免不 bump。

**预估 vs 实测**：bump 后 cur ≤ 新 bm（F1 gen_decls 759≤765），re-run gate 预期 PASS（实测见 VCM §1）。

---

## 参考

- D088 §第一性需求 / §核心验证三问 / §Phase 6-8 / §反模式
- D093 §第一性需求（一份求值逻辑）/ §端到端审计（3026f14 closure 宣告）/ §差距 #3（fn 入 InternPool）
- D098 §决策 3 Type-as-Value / §决策 2 §Phase C（Part B deferred）
- D094 §规则 1 Comptime = 纯计算
- Zig comptime：编译器即解释器，Sema 覆盖完整语言 — https://ziglang.org/documentation/master/#comptime
