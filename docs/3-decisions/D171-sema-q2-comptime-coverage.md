# D171: SEMA Q2 — comptime 解释器语言覆盖度补全（走统一 evalExpr）

**Status:** draft — Phase 1-2 **[x] Done**（Ph1 闭包/arrow 可调用含捕获；Ph2 spread 数组字面量 + ct 数组 `.length`）；Phase 3-5 Planned
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
| super / 继承方法 | `super.speak()` | ❌ `[comptime] no method 'speak' on class Dog` |

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
- **[ ] Planned** Phase 3-5：super 继承方法 / try-catch / loud-gate 审计 + 覆盖度回归套件（各 Phase Execute 轮起手细化 PSM）。

**本 D 文档不触发任何 `.ss` 代码改动，不跑 bootstrap。代码改动从 Phase 1 Execute 轮开始。**

---

## 参考

- D088 §第一性需求 / §核心验证三问 / §Phase 6-8 / §反模式
- D093 §第一性需求（一份求值逻辑）/ §端到端审计（3026f14 closure 宣告）/ §差距 #3（fn 入 InternPool）
- D098 §决策 3 Type-as-Value / §决策 2 §Phase C（Part B deferred）
- D094 §规则 1 Comptime = 纯计算
- Zig comptime：编译器即解释器，Sema 覆盖完整语言 — https://ziglang.org/documentation/master/#comptime
