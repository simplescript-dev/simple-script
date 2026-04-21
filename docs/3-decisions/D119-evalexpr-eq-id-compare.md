# D119: evalExpr `==` 改 id==id — Value.eql O(1) 度量基线

**Status:** draft (Plan)
**Depends on:** D088 §第一性需求、D093 §Zig 原理 #4、D098 §决策 2 §Phase B、D111 §下一步 #4
**Date:** 2026-04-21
**Last Updated:** 2026-04-21

---

## 核心目标 (Goal)

- **为什么**:Phase B 已让 5 类标量(int/string/bool/null/type)经 InternPool 去重 → 相同值同 tvId,但 `interpValEquals` 与 `genValStringCompare` comptime 分支仍走**深比较**(`tvStringOf(lid) == tvStringOf(rid)` / `ls == rs`),D093 §Zig 原理 #4 "Value.eql = O(1) index 比较" 未兑现,是双轨语义残留。
- **是什么**:把 comptime Value 相等判断统一降到 `tvId == tvId` 的 O(1) 索引比较,拿下 Phase B 完整收益的度量基线(D098 §决策 2 §Phase B 明文 L250)。
- **单一判据**:`grep -n "tvStringOf(lid) == tvStringOf(rid)" bootstrap/eval/interp_op.ss` + `grep -n "ls == rs\\|ls != rs" bootstrap/gen/exprs/exprs.ss` 全部 0 命中,linter GATE PASS 且 M1/M2/M3a/M4/M5 不回升。

> 口号:InternPool 既已实装,Value.eql 必须落地;否则 5 标量 dedup 的 bytes 白吃 baseline。

---

## 核心原则 (Principles)

1. **根因不绕路** — 冗余的深比较路径必须删,禁止加 cache / 新写 `interpFastEq` workaround。
2. **双轨即根因** — comptime Eq/Ne 当前分散三路径(interpIntOp 标量 / genValStringCompare 字符串 / interpValEquals 单点),目标是统一语义到 id 比较,不是局部优化其中一条。
3. **范围锁 5 标量** — Array / Map / Double 未进 InternPool(D098 §Phase C 范围),本决策显式不碰;违反即越界。
4. **度量先行** — Execute 前跑 linter 记 baseline,Execute 后跑同一 linter 对照,M1/M2/M3a/M4 单调下降或持平才算兑现。
5. **不影响运行时 IR** — runtime `@ss_string_eq` LLVM 路径(gen_exprs.ss L114/119)不动,只改 comptime `isCt(lv)==1 && isCt(rv)==1` 分支。

---

## 1. Context Management

### 必读清单

1. 本文档
2. `CLAUDE.md` §关键不变量
3. `docs/3-decisions/D098-sema-value-model.md` §决策 2 §Phase B(L240-260)
4. `docs/3-decisions/D111-phase-b-internpool-execute-2-plan.md` §下一步 L476
5. `docs/3-decisions/D093-sema-single-dispatch.md` L38 (§Zig 原理 #4)

### 关键代码位置

| 文件 | 行号 | 角色 |
|---|---|---|
| `bootstrap/eval/interp_op.ss` | 93-102 | `interpValEquals(lid, rid)` — 深比较(int/bool/string/null/double/fallback) |
| `bootstrap/eval/interp_value.ss` | 164-183 | `interpNew{Int,String,Bool,Null,Type}` — Phase B InternPool 入口,相同值同 tvId |
| `bootstrap/eval/eval_expr.ss` | 102/108/116/126 | BINARY Eq/Ne 三分散路径(genValStringCompare / interpIntOp / interpDoubleOp) |
| `bootstrap/gen/exprs/exprs.ss` | 96-134 | `genValStringCompare(op, id)` — comptime L102-107 走 `ls == rs` 深比较 |
| `bootstrap/gen/exprs/exprs_ct_builtin.ss` | 139 | `arr.contains(target)` comptime 唯一调 `interpValEquals` 的点 |
| `bootstrap/lexer/intern_pool.ss` | 9-15 | `internPoolGetOrInsert(key, ifMissAlloc)` — tag`|`payload 为 key |

### Stable Facts (Live Repo)

| 项 | 值 |
|---|---|
| 当前阶段 | D111 Phase B Execute 2 完成,Phase C 未启动 |
| 反射 baseline commit | `9e20f26`(D097 frozen) |
| 本 Plan 起草基线 linter | M1=5126 / M2=76215 / M3a=12107 / M4=2997 / M5=1739 / N2=381075 / N3=513289 / F1 gen_decls=690 (cur vs baseline=691 PROGRESS);GATE PASS |
| 入口命令 | `./build.sh bootstrap` / `bin/ss run tools/reflection_health_linter.ss` |
| 预期 LOC 变化 | -10 ~ -20(interpValEquals 塌缩 + genValStringCompare comptime 分支塌缩) |

### 禁止的 Context 操作

- ❌ 读 `bootstrap/pir/` / `bootstrap/gen/class/`(与本决策无关)
- ❌ 扫反射路径(D097/D117/D118 已闭合,本决策不触)
- ❌ 扫 runtime LLVM IR(只改 comptime 分支)

---

## 2. Tool System

### 必备工具

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| Claude 内置 | `Read` / `Edit` / `Grep` / `Bash` | 文件操作 |
| 项目构建 | `./build.sh bootstrap` | 固定点验证(stage2==stage3) |
| 度量 gate | `bin/ss run tools/reflection_health_linter.ss` | 14 指标 + F1 行数 baseline 比对 |
| RED 证据 | `grep -n "tvStringOf(lid) == tvStringOf(rid)" bootstrap/eval/interp_op.ss` | 深比较路径存在确证 |
| 测试 | `bin/ss test tests/phase5/` | comptime 覆盖回归 |

### 禁止引入

- ❌ 新 builtin / 新 interp_* 函数
- ❌ 新 InternPool key tag(Phase C 范围)
- ❌ 任何 workaround 型 cache

---

## 3. Execution Orchestration

### 总体节奏(Plan 阶段仅规划,Execute 阶段分 3 Step 独立 commit)

### Step 1: interpValEquals 塌缩为 id 比较

- 改 `bootstrap/eval/interp_op.ss:93-102`
- 5 标量(int/bool/string/null/type)合并:`if (lk == "int" || lk == "bool" || lk == "string" || lk == "null" || lk == "type") { return lid == rid ? 1 : 0 }`
- double 保留 Map key 深比较(NaN 语义 + 未进 InternPool)
- array/map fallback `lid == rid`(行为不变)
- **验证**:`./build.sh bootstrap` 固定点 PASS + `bin/ss test tests/phase5/` 全绿 + linter M1 预期 -6

### Step 2: genValStringCompare comptime 分支塌缩

- 改 `bootstrap/gen/exprs/exprs.ss:99-108`
- comptime `isCt(lv)==1 && isCt(rv)==1` 分支,Eq/Ne 改 `payload(lv) == payload(rv)` / `!= `
- Lt/Gt/Le/Ge 仍需深 string 比较(序关系无法从 id 推出),保留 `ls < rs` 等
- **验证**:固定点 PASS + `tests/phase5/comptime_*.ss` 全绿 + linter M1 预期 -4

### Step 3 (可选): BINARY Eq/Ne 统一入口

- `bootstrap/eval/eval_expr.ss:99-128` 若分散三路径合并为单 `interpValEquals` 调用可再降 M4(Dispatch 深度和),但需确认 interpIntOp Eq/Ne 与 interpValEquals 语义等价(int/bool 都是 InternPool dedup 后 tvId 比较,应等价)
- **触发条件**:Step 1+2 合计 LOC 下降 ≥ 15 且 M4 降幅 ≥ 10 时才启动;否则记 Planned 留 D120+

### 反模式

- ❌ 把 Step 1+2 合并成单次 commit(破坏"每步独立验证")
- ❌ 顺手改 double / array / map(越界 Phase C)
- ❌ 改 runtime `ss_string_eq` LLVM IR

---

## 4. State & Memory

### 关键 state

| 变量 | 文件 | 角色 |
|---|---|---|
| `internPool` | `bootstrap/lexer/intern_pool.ss:6` | key → tvId(Phase B 5 入口共享) |
| `internPoolKeyOf` | `bootstrap/lexer/intern_pool.ss:7` | tvId → key(valType 反查) |
| `tvKind/tvI1/tvS1/tvD1` | `bootstrap/eval/interp_value.ss` | TypedValue 存储,本决策不动结构 |

### 中间产物

- `bin/ss_stage1` / `stage2` / `stage3` — 固定点验证
- linter baseline snapshot 对照

### 会话间持久化

- `git log` — 进度真相源
- 本文档附录 B — 实施日志(Execute 后追加)

### 禁止 state 操作

- ❌ 扩 internPool key tag(Phase C 范围)
- ❌ 改 internPoolKeyOf 反查语义
- ❌ 把 Execute 进度写 `.claude/next_prompt.md` 累积(per CLAUDE.md 硬约束)

---

## 5. Evaluation & Observation

### 判据(每 Step 完成必跑)

| # | 类型 | 命令 / 检查 | 通过条件 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | stage2==stage3 固定点通过 |
| 2 | 测试 | `bin/ss test tests/phase5/` | 全绿(4 个 pre-existing fail 不新增) |
| 3 | 收敛 | `grep -n "tvStringOf(lid) == tvStringOf(rid)" bootstrap/eval/interp_op.ss` | Step 1 后 0 命中 |
| 4 | 收敛 | `grep -n "ls == rs\\|ls != rs" bootstrap/gen/exprs/exprs.ss` | Step 2 后 0 命中 |
| 5 | 度量 | `bin/ss run tools/reflection_health_linter.ss` | GATE PASS + M1/M2/M3a/M4/M5 单调或 DRIFT(不上升) |
| 6 | 人工 | 反射 Meta 对象 dedup / Array InternPool 是否受影响 | N — 本决策范围外 |

### 回归信号(任一出现 = 立即停下)

- ⚠ `arr.contains(target)` comptime 用例返回 `0` 变 `1`(或反之)
- ⚠ `comptime { if (a == b) {...} }` string 分支行为变化
- ⚠ bootstrap 固定点失败(stage2 != stage3)
- ⚠ linter GATE BLOCKED(任一指标高于 baseline)

### spot check

```bash
# Step 1 后:interpValEquals 应塌缩为单 if return 语句
grep -A 20 "function interpValEquals" bootstrap/eval/interp_op.ss

# Step 2 后:comptime Eq/Ne 分支应走 payload 比较
grep -B 1 -A 4 'isCt(lv) == 1 && isCt(rv) == 1' bootstrap/gen/exprs/exprs.ss
```

---

## 6. Constraints & Recovery

### 硬约束(违反 = 立即回滚)

- CLAUDE.md §Root Cause 优先:禁止 workaround,同 workaround 第二次出现必须停下修根因
- CLAUDE.md §反射根因 gate:触碰反射路径必须跑 linter(本决策不触反射,但 linter gate 仍对全部 bootstrap 生效)
- feedback_600_split_not_inline:LOC ≤ 600 硬上限,压注释绕过禁止(本决策预期 LOC 下降,不触边界)
- feedback_no_workaround:interpFastEq / 缓存 map / 绕过 interpValEquals = 红线

### 失败模式 + 恢复

| 信号 | 恢复 |
|---|---|
| Step 1 固定点失败 | `git reset --soft HEAD^` → 检查 interpValEquals 对 null / type 分支覆盖是否完整 |
| Step 2 comptime 用例失败 | 检查 Phase B 是否真覆盖所有 interpNewString 调用点(grep `newTvString\\|interpNewString`) |
| linter M1 回升 | Step 塌缩未彻底,仍留深比较残枝;不允许 baseline record(累积方向硬禁) |
| `arr.contains` 行为变化 | Phase B InternPool 未覆盖某条 interpNewString 路径 → 先定位漏网入口 → Phase C 范围,回滚本决策到规划 |

### 回滚策略

- 任何 Step 失败 → `git reset --soft HEAD^`
- 禁止"先 commit 再修"
- Step 3 可选性判断错误(M4 降幅不达标)→ 跳过并更新本文档附录 B

### 升级判据

模型升级时本文档需要复审:
- "禁止引入"是否被新能力让步 → 拒绝
- 度量 baseline 是否仍有效 → 保持

---

# 附录 A: 决策细节

## A.1 问题

Phase B(D111 commit `32a8f6d`)已让 `interpNew{Int,String,Bool,Null,Type}` 5 入口经 `internPoolGetOrInsert(key, ifMissAlloc)` 去重:

```
// bootstrap/eval/interp_value.ss:168-170
function interpNewString(s: string): int {
    return internPoolGetOrInsert(`string|${s}`, newTvString(s))
}
```

相同 string 第二次调用返回同 tvId。但 `interpValEquals` 对同一情形仍深比较:

```
// bootstrap/eval/interp_op.ss:93-102
function interpValEquals(lid: int, rid: int): int {
    const lk = tvKindOf(lid)
    const rk = tvKindOf(rid)
    if (lk != rk) { return 0 }
    if (lk == "int" || lk == "bool") { return tvIntOf(lid) == tvIntOf(rid) ? 1 : 0 }
    if (lk == "string") { return tvStringOf(lid) == tvStringOf(rid) ? 1 : 0 }  // ← 冗余
    if (lk == "null") { return 1 }
    if (lk == "double") { return tvD1.getString(lid + "") == tvD1.getString(rid + "") ? 1 : 0 }
    return lid == rid ? 1 : 0
}
```

同时 `genValStringCompare` comptime 分支也走深比较:

```
// bootstrap/gen/exprs/exprs.ss:99-108
if (isCt(lv) == 1 && isCt(rv) == 1) {
    const ls = interpAsStr(payload(lv))
    const rs = interpAsStr(payload(rv))
    if (op == "Eq") { return ctVal(interpNewBool(ls == rs ? 1 : 0)) }  // ← 冗余
    if (op == "Ne") { return ctVal(interpNewBool(ls != rs ? 1 : 0)) }  // ← 冗余
    ...
}
```

D098 §决策 2 §Phase B L250 明文 "5 标量 interpNew* 调用后 `interpNewInt(42) == interpNewInt(42)` 返回同 tvId,`a == b` 可退化为 `id == id`(evalExpr `==` op 改写留 D113+)" — 本决策承接该承诺。

## A.2 决策

| 位置 | 当前 | 目标 |
|---|---|---|
| `interp_op.ss:97` | `lk == "int" \|\| lk == "bool"` 分支深 int 比较 | 合并入 id 比较分支 |
| `interp_op.ss:98` | `lk == "string"` 深 string 比较 | 合并入 id 比较分支 |
| `interp_op.ss:99` | `lk == "null"` 返 1 | 合并入 id 比较分支(null InternPool 保证唯一 tvId) |
| `interp_op.ss:100` | `lk == "double"` Map 深比较 | **保留**(double 未 InternPool,Phase C 解) |
| `interp_op.ss:101` | fallback `lid == rid` | 保留(array/map 原本就是 id 比较) |
| `exprs.ss:102-103` | `ls == rs` / `ls != rs` 深 string 比较 | `payload(lv) == payload(rv)` / `!= ` tvId 比较 |
| `exprs.ss:104-107` | `ls < rs` 等序比较 | 保留(序关系无法从 id 推出) |

### 目标代码形态

```
// interp_op.ss 塌缩后
function interpValEquals(lid: int, rid: int): int {
    const lk = tvKindOf(lid)
    if (lk != tvKindOf(rid)) { return 0 }
    if (lk == "double") { return tvD1.getString(lid + "") == tvD1.getString(rid + "") ? 1 : 0 }
    return lid == rid ? 1 : 0
}
```

```
// exprs.ss genValStringCompare comptime 分支塌缩后
if (isCt(lv) == 1 && isCt(rv) == 1) {
    if (op == "Eq") { return ctVal(interpNewBool(payload(lv) == payload(rv) ? 1 : 0)) }
    if (op == "Ne") { return ctVal(interpNewBool(payload(lv) != payload(rv) ? 1 : 0)) }
    const ls = interpAsStr(payload(lv))
    const rs = interpAsStr(payload(rv))
    if (op == "Lt") { return ctVal(interpNewBool(ls < rs ? 1 : 0)) }
    if (op == "Gt") { return ctVal(interpNewBool(ls > rs ? 1 : 0)) }
    if (op == "Le") { return ctVal(interpNewBool(ls <= rs ? 1 : 0)) }
    return ctVal(interpNewBool(ls >= rs ? 1 : 0))
}
```

## A.3 替代方案对比(Plan 型替 VCM ④)

| 方案 | 描述 | 取舍 |
|---|---|---|
| A | 只改 `interpValEquals`,不动 `genValStringCompare` | 漏 BINARY string Eq/Ne 高频路径(eval_expr.ss:115-118),Value.eql 统一语义不达 |
| B | 只改 `genValStringCompare`,不动 `interpValEquals` | `arr.contains(target)` 仍 O(n string compare),5 标量 dedup 收益只落地一半 |
| C(采用) | 两处都改,interpValEquals 5 标量 + genValStringCompare comptime Eq/Ne 统一 tvId 比较 | 单一语义,度量基线清晰;不碰 double/array/map 留 Phase C |
| D | 升级 tvD1 存储为 InternPool tag=`double|<d>` 顺带 double dedup | 越界 Phase C,NaN/精度语义需单独评估 |

**选 C 的理由**:D098 §决策 2 §Phase B 完整收益 = 5 标量 Value.eql O(1),双入口(`interpValEquals` + `genValStringCompare` comptime)都覆盖才算兑现;double/array/map 是 Phase C 独立决策,合并会放大回归面。

## A.4 隐藏假设挑战

1. **假设**:Phase B 对所有 `interpNewString` 调用点已覆盖。**挑战**:如果 comptime 路径有直接 `newTvString(s)` 绕过 `interpNewString` 的调用,则相同 string 可能产生不同 tvId → id 比较错。**验证**:`grep -rn "newTvString\\b" bootstrap/ | grep -v interp_value.ss | grep -v intern_pool.ss`,命中点必须全走 `interpNewString` 包装。
2. **假设**:interpIntOp Eq/Ne(eval_expr.ss:126)与 interpValEquals int 分支语义等价。**挑战**:interpIntOp 直接 `a == b` raw int 比较;interpValEquals int 分支也是 raw int 比较;Phase B 后同值同 tvId,所以三者等价。但 Step 3(合并入口)需再度证:`interpNewInt(42)` 返回固定 tvId=X,`payload(lv)==payload(rv)` 与 `a==b` 都等价于 `X==X`。成立。
3. **假设**:double 保留深比较不会导致行为不一致。**挑战**:double 未入 InternPool,`interpNewDouble(0.1)` 每次产生新 tvId,所以不能用 id 比较。保留 Map key 深比较是正确行为。

## A.5 单一判据兜底

Execute 完成后:
- `grep -n "tvStringOf(lid) == tvStringOf(rid)" bootstrap/eval/interp_op.ss` → 0 命中
- `grep -n "ls == rs\\|ls != rs" bootstrap/gen/exprs/exprs.ss` → 0 命中
- linter GATE PASS 且 M1/M2/M3a/M4/M5 不回升
- bootstrap 固定点 + tests/phase5 全绿(4 pre-existing fail 不新增)

---

# 附录 B: 实施日志

### Plan(本轮起草) ⏳

- 2026-04-21:起草 D119 Plan,baseline linter 快照 M1=5126 / M2=76215 / M3a=12107 / M4=2997 / M5=1739 / F1 gen_decls=690 (PROGRESS vs baseline 691) GATE PASS
- Execute 1/2/3 Planned,下轮启动

### Execute 1: interpValEquals 塌缩 [x] Done at `bootstrap/eval/interp_op.ss:93-99`

- 2026-04-21:`interpValEquals` 10 行(5 标量分支 + fallback)塌缩为 5 行(double 1 分支 + `lid==rid` fallback)。加 2 行 WHY 注释声明 InternPool dedup 不变量依赖。
- **实测 vs 预估**(Δ from baseline D101):
  | 指标 | 预估 Δ-from-cur | 实测 Δ-from-baseline | 实测 Δ-from-pre-change | 命中 |
  |---|---|---|---|---|
  | M1 | -6 | -14(cur=5120)| **-6** | **精确** |
  | M2 | 下降 | +48(cur=76174)| -41 | 优于预估(pre-change +89 → post-change +48)|
  | M3a | 下降 | -19(cur=12103)| **-4** | **精确**(去 2 个深比较分支调用)|
  | M3b | 0 严格 | 0 | 0 | **精确** |
  | M4 | 下降 | -43(cur=2994)| **-3** | **精确**(去 3 个分支 Dispatch)|
  | M5 | 0 或下降 | -11 | 0 | **精确** |
  | M6 | 0 严格 | 0 | 0 | **精确** |
  | M7a | 0 严格 | 0 | 0 | **精确** |
  | M7b | 0 严格 | -2 | 0 | **精确**(未抽新函数)|
  | N2 | 下降 | +240 | -205 | 优于预估 |
  | N3 | 下降 | -5058 | **-236** | **精确** |
- **验证**:`./build.sh bootstrap` 固定点 PASS / `bin/ss test tests/phase5/` 158/4(4 pre-existing,stash 前后一致)/ linter GATE PASS,全 OK/PROGRESS 零 REGRESSION
- **收敛判据**:`grep "tvStringOf(lid) == tvStringOf(rid)\|tvIntOf(lid) == tvIntOf(rid)" bootstrap/eval/interp_op.ss` 0 命中 ✓
- **当前形态**:
  ```ss
  function interpValEquals(lid: int, rid: int): int {
      const lk = tvKindOf(lid)
      if (lk != tvKindOf(rid)) { return 0 }
      if (lk == "double") { return tvD1.getString(lid + "") == tvD1.getString(rid + "") ? 1 : 0 }
      return lid == rid ? 1 : 0
  }
  ```

### Execute 2: genValStringCompare comptime 分支塌缩 [x] Done at `bootstrap/gen/exprs/exprs.ss:99-111`

- 2026-04-21:`genValStringCompare` comptime 分支塌缩。Eq/Ne 2 行从 `interpAsStr(payload(lv)) == interpAsStr(payload(rv))` 深 string 比较改为 `payload(lv) == payload(rv)` tvId 比较;Lt/Gt/Le/Ge 保深比较(字典序);加 `lp/rp` 中间变量解耦 payload 调用,`const ls/rs` 下移仅 Lt/Gt/Le/Ge 路径计算;加 2 行 WHY 注释声明 InternPool dedup 不变量依赖。
- **方案演进**:初稿直接 inline `payload(lv) == payload(rv)` 导致 M3a +4(Eq/Ne 两条分支各复制 2 次 payload 调用);切换 `const lp = payload(lv); const rp = payload(rv)` 中间变量方案,payload 只 hoist 一次,M3a 回到持平。
- **实测 vs 预估**(Δ from pre-change / Δ from baseline):
  | 指标 | 预估 Δ-from-pre | 实测 Δ-from-pre | 实测 Δ-from-baseline | 命中 |
  |---|---|---|---|---|
  | M1 | -4(乐观) | **0** | -14(pre=-14,持平) | **偏差**(静态 linter 看不到 lazy eval 收益;但不回升) |
  | M2 | 0 或轻微+ | +4 | +52 | 预期内(2 行 WHY 注释+中间变量) |
  | M3a | 下降 | **0** | -19(pre=-19,持平) | **达成**(中间变量方案避免复制 payload 调用) |
  | M3b | 0 严格 | 0 | 0 | **精确** |
  | M4 | 下降 | **0** | -43(pre=-43,持平) | **偏差但不回升** |
  | M5 | 0 严格 | **0** | -11(pre=-11,持平) | **精确** |
  | M6 | 0 严格 | 0 | 0 | **精确** |
  | M7a | 0 严格 | 0 | 0 | **精确** |
  | M7b | 0 严格 | 0 | -2 | **精确** |
  | N2 | 0 或轻微+ | +20 | +260 | 轻微增(注释 token) |
  | N3 | 0 或轻微+ | +20 | -5038(pre=-5058,仍 PROGRESS) | 轻微增但 vs baseline 仍 PROGRESS |
- **验证**:`./build.sh bootstrap` 固定点 PASS / `bin/ss test tests/phase5/` 158 passed / 4 failed(spring_web_params / harness_task / d096_p4_l2_reactive / harness_bug 皆 pre-existing,stash 前后一致)/ linter GATE PASS,全 OK/PROGRESS 零 REGRESSION
- **收敛判据**:`grep -n "ls == rs\|ls != rs" bootstrap/gen/exprs/exprs.ss` 0 命中 ✓
- **M1/M3a/M4/M5 单调不回升**(用户硬约束):M1=0 / M3a=0 / M4=0 / M5=0,全部 ✓
- **当前形态**:
  ```ss
  if (isCt(lv) == 1 && isCt(rv) == 1) {
      const lp = payload(lv)
      const rp = payload(rv)
      if (op == "Eq") { return ctVal(interpNewBool(lp == rp ? 1 : 0)) }
      if (op == "Ne") { return ctVal(interpNewBool(lp != rp ? 1 : 0)) }
      const ls = interpAsStr(lp)
      const rs = interpAsStr(rp)
      if (op == "Lt") { return ctVal(interpNewBool(ls < rs ? 1 : 0)) }
      ...
  }
  ```

### Execute 3 (可选): BINARY Eq/Ne 统一入口 [ ] Planned

---

## 反模式 / 正模式

### ❌ 反模式
- 加 `interpFastEq` / cache map / short-circuit 旁路(workaround)
- 顺手改 double / array / map 的 tvId 比较(越界 Phase C)
- 把 Step 1+2 合并成单次 commit
- Step 3 触发条件不满足还强行推

### ✅ 正模式
- 先跑 linter baseline,再按 Step 独立 commit,每步对比度量
- 保留 double 深比较(InternPool 未实装该路径)
- Lt/Gt/Le/Ge 保留深 string 比较(序关系无法从 id 推)

---

## 参考

- D093 §Zig 原理 #4:`docs/3-decisions/D093-sema-single-dispatch.md:38`
- D098 §决策 2 §Phase B:`docs/3-decisions/D098-sema-value-model.md:250`
- D111 §下一步 L476:`docs/3-decisions/D111-phase-b-internpool-execute-2-plan.md:476`
- Phase B 启动 commit:`32a8f6d`
- 反射 baseline frozen commit:`9e20f26`
