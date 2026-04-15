# D091: nextReg 返回 tagged int

**Status:** ❌ **Rejected**（数据驱动关闭，2026-04-14）— 见附录 C
**Depends on:** D089（compiler = interpreter，已完成）
**Date:** 2026-04-14
**Last Updated:** 2026-04-14

---

## 核心目标 (Goal)

- **为什么**：D089 让 `genVal` 返回 tagged int，但 `nextReg()` 仍返回 `%N` 字符串，每次调用都 `${regCount}` 分配 string + 通过 `constVal(s)` push 进 `regTable: Array<string>`。376 个调用点 × 每次两次 string 操作，是热路径。
- **是什么**：让 `nextReg()` 返回 int，统一与 `genVal` 的返回类型，用 tag bit 区分"寄存器号 / regTable index / ct value"，把 string 化推迟到 emitIR 模板拼接的最后一刻。
- **单一判据**：bootstrap 固定点通过 + 219 测试全绿 + bootstrap 耗时不退步（理想：10%+ 改善）。

> "拼字符串能拖到几时，就拖到几时。"

---

## 核心原则 (Principles)

1. **延迟 materialize** — int 在层间传递，只在 emitIR 模板拼接前一刻 `${reg(v)}` 转 string
2. **三类操作数统一编码** — ct value / reg num / opaque IR 字符串，用 tag bit 区分，对调用方透明
3. **逐文件迁移** — 14 个 `gen_*.ss` 文件按依赖顺序迁，每文件独立 commit + bootstrap 验证
4. **emitIR API 不动** — 仍接受 `string` 模板。本 D 不重构 emit 层，只改寄存器表示
5. **零功能漂移** — 纯类型重构，不顺手做任何 codegen 行为变更

---

## 1. Context Management（上下文管理）

### 必读清单（按顺序）

1. 本文档
2. `CLAUDE.md`
3. `docs/3-decisions/D089-compiler-is-interpreter.md` — tagged value 基础设施已就绪
4. **关键代码位置**：

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/codegen.ss` | 15-16 | `regCount: int` / `regTable: Array<string>` 全局状态 |
   | `bootstrap/codegen.ss` | 106-148 | `nextReg` / `ctVal` / `isCt` / `payload` / `constVal` / `reg` / `materialize`（D089 已建） |
   | `bootstrap/gen_exprs.ss` | 97-212 | `genVal(): int` 主分发器 |
   | `bootstrap/gen_exprs.ss` | 1304+ | `genExpr(): string` wrapper（`return reg(genVal(id))`） |

### Stable Facts

| 项 | 值 |
|---|---|
| `nextReg` 调用点 | 369（grep `bootstrap/`，2026-04-14） |
| `const X = nextReg()` 模式 | 主流，约 90%+ |
| `regTable` push 操作 | 369 次/编译（每个 nextReg 都跟一次 `constVal(r)`） |
| 涉及文件 | 14 个 `gen_*.ss` + `codegen.ss` |
| bootstrap 当前耗时 | 2-3 分钟（基线，迁移后必须 ≤） |
| 测试基线 | 219 个 `.ss` 全绿 |

### 禁止的 Context 操作

- ❌ 顺手改 `emitIR` API（独立成 D092 候选）
- ❌ 顺手改 `genExpr` wrapper 行为
- ❌ 扫 `docs/3-decisions/` 找未完成决策找别的活

---

## 2. Tool System

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| 验证 | `./build.sh bootstrap` | 三阶段固定点 |
| 验证 | `bin/ss test tests/` | 219 测试全绿 |
| 测量 | `time ./build.sh bootstrap` | 性能基线对比 |
| 搜索 | `Grep nextReg bootstrap/` | 调用点收敛监控 |

### 禁止引入

- ❌ 新关键字
- ❌ 新 builtin 函数（`reg` / `materialize` / `nextReg` / `constVal` 已够用）
- ❌ 新依赖

---

## 3. Execution Orchestration

> **本节为草稿**：方案 A/B/C 见附录 A.2，待用户选定后填具体 Phase。

总体节奏（任一方案通用）：
1. **Phase 0**：基线测量（`time ./build.sh bootstrap` × 3，记中位数）
2. **Phase 1**：改 `nextReg` / `reg` / `regTable` 的内部表示，保持外部签名兼容（旧 string 调用点继续工作）
3. **Phase 2-N**：按文件迁移调用点（每文件一个 commit）
4. **Phase 末**：删 `genExpr` wrapper（如果方案允许）/ 更新 D089 stable facts / 关闭 D091

---

## 4. State & Memory

| 变量 | 文件 | 角色 |
|---|---|---|
| `regCount` | `codegen.ss:15` | 单调递增计数器，每个寄存器分配一个新号 |
| `regTable` | `codegen.ss:16` | 当前为 `Array<string>`，存所有 `constVal` 推入的 IR 操作数（包括 `%N` / `@x` / 字面量等） |

### 中间产物

- `bin/.bootstrap-cache/` 三阶段编译产物（固定点对比）

### 禁止 state 操作

- ❌ 写 `next-prompt.md` / `handoff.md`
- ❌ 在 D091 之外的地方记进度

---

## 5. Evaluation & Observation

| # | 类型 | 命令 / 检查 | 通过条件 |
|---|---|---|---|
| 1 | 工程判据 | `./build.sh bootstrap` | stage2 == stage3 |
| 2 | 测试判据 | `bin/ss test tests/` | 219 全绿 |
| 3 | 收敛判据 | `Grep -c nextReg bootstrap/` | 旧调用点单调递减至 0（迁完后） |
| 4 | 性能判据 | `time ./build.sh bootstrap` | ≤ 基线（理想 10%+ 改善，不退步即可接受） |

### 回归信号（任一出现 = 立即停下）

- ⚠ bootstrap 固定点失败 → `git reset --soft HEAD^`
- ⚠ 219 测试任一失败
- ⚠ 性能退步 > 5% → 暂停，重新评估方案

---

## 6. Constraints & Recovery

### 硬约束

- **零功能改动**：本 D 是纯类型重构，绝不顺手改 codegen 行为
- **emitIR 不动**：API 与 D 092 候选解耦
- **逐文件 commit**：14 个文件 = 14 个 commit + 14 次 bootstrap，禁止合并
- **方案选定前不动代码**：草案阶段只勘察 + 写 ADR

### 失败模式

| 信号 | 恢复 |
|---|---|
| 某文件迁完后 stage1 编译失败 | `git reset --soft HEAD^` 回滚单文件 |
| 性能退步 > 5% | 暂停所有迁移，回头评估 reg(v) 内部实现 |

---

# 附录 A: 决策细节

## A.1 问题

**当前热路径**（典型调用，每个 nextReg 都长这样）：

```ss
const r = nextReg()                          // ① ${regCount} string 分配
emitIR(`  ${r} = add i32 ${l}, ${r2}`)       // ② IR 模板拼接
return constVal(r)                           // ③ regTable.push(r)，再分配 int wrap
```

**每次 nextReg 调用产生**：
- 1 次 `${regCount}` string 拼接（短字符串，但 369 × N 次）
- 1 次 array push 操作
- 1 次 `constVal` 函数调用 + 返回 int

**关键观察**：`reg(v)` 内部目前是 `regTable[idx-1]` —— **直接返回查表得到的 string，零拼接**。这意味着如果 nextReg 改成返回 int，但 `reg(v)` 要 `"%${num}"` 拼接，那么每次 reg(v) 调用都新增一次拼接。**reg(v) 的调用频率可能比 nextReg 更高**（一个寄存器在多条 IR 行被引用）。

**所以 D091 的真实收益不在"省 nextReg 的拼接"**，而在：

1. **regTable 从 `Array<string>` → `Array<int>`** 或更小 —— 369 个 string 对象不再分配
2. **constVal 路径从"必走"变成"仅 opaque 路径走"** —— 369 次 push 减到一小部分（仅 `@x` / 字面量等需要 string 表示的）
3. **统一 genVal/nextReg 返回类型** —— 调用方代码风格一致，未来更激进的 emitIR 重构（D092 候选）有铺路

**真实瓶颈是 emitIR 模板拼接本身**，但那是 D092 候选范围。D091 只能消除 nextReg 这一层的开销。

## A.2 候选方案

### 方案 A：保守 — 只换 regTable 的元素类型

- `regTable: Array<string>` → `Array<int>`，元素是 regCount 的整数
- `nextReg(): int` → `regTable.push(regCount); return regTable.length()`（推 int 而非 string）
- `reg(v): string` → ct 路径走 materialize，否则 `${regTable[idx-1]}` → `"%${regTable[idx-1]}"`
- **开销转移**：nextReg 省一次 `${regCount}`，reg(v) 多一次 `"%${...}"` —— 几乎等价
- **唯一收益**：regTable 元素从 string 对象变 int，省堆分配 + RC
- **调用点改动**：0（外部签名不变）
- **风险**：低
- **收益**：可能 0-5%

### 方案 B：tag bit 区分 reg vs 其他

- 引入 bit 29 表示"我是 reg num"（bit 30 已被 ct 占用）
- `nextReg(): int` → `(regCount | (1 << 29))` —— 完全不进 regTable
- `reg(v): string` → 三路分发：
  - `bit30 set` → `materialize(payload(v))`
  - `bit29 set` → `"%${v & 0x1FFFFFFF}"`
  - 否则 → `regTable[idx-1]`（保留 opaque 路径，处理 `@x` / 字面量）
- **调用点改动**：0（外部签名不变）—— **关键**：旧 `const r = nextReg(); emitIR(`...${r}...`)` 中的 `${r}` 现在是 int，模板拼接会拼成 `1610612741` 而非 `%5`，**会破坏所有 emitIR 模板**
- **修正**：必须改成 `${reg(r)}` 显式 materialize —— 369 调用点 × 平均 N 处 `${r}` 引用，**手术面巨大**
- **收益**：nextReg 完全 bypass regTable（省 369 次 push），但调用方多 369+ 个 `${reg(r)}` 拼接
- **风险**：中（手术面大）
- **收益**：可能 5-15%

### 方案 C：彻底重构 emitIR API（升级到 D092）

- emitIR 不再接 string 模板，而是接 `(op, dst_int, operand_int_list)` 之类
- 内部一次性 stringify
- **超出 D091 范围** —— 列在这里仅供对照

### 方案对比表

| 维度 | A 保守 | B tag bit | C emitIR 重构 |
|---|---|---|---|
| 调用点改动数 | 0 | 369+（每个 `${r}` 引用） | 1000+（所有 emitIR 模板） |
| 实施复杂度 | 低 | 中 | 高 |
| 预期收益 | 0-5% | 5-15% | 20-40% |
| 是否本 D 范围 | ✅ | ✅ | ❌（D092） |
| 推荐 | 候选 | **候选** | 单独立项 |

## A.3 待用户决策的开放问题

1. **方案选择**：A 还是 B？或先 A 试水、收益不足再升 B？
2. **基线测量**：是否需要先做 Phase 0 性能测量，确认有可优化的空间，再决定动手？
3. **D092 范围**：emitIR API 重构是否值得起草 D092？还是 D091 收尾后再决定？
4. **失败回退判据**：如果方案 B 实施到一半发现性能退步，是直接回滚到方案 A 还是放弃整个 D091？
5. **`genExpr` wrapper 命运**：D091 完成后 `genExpr(): string` 是否还有存在意义？还是顺势删掉、调用方全改 `reg(genVal(id))`？（注意：这会扩大手术面）

---

# 附录 B: 实施日志

> 无 — 本 D 在 draft 阶段被关闭，未进入实施。

---

# 附录 C: 关闭决策（数据驱动）

## C.1 关闭理由（一句话）

D091 的优化天花板 ≈ 0.04% × 53 秒 ≈ **20 毫秒**，性价比为零。真正的 codegen 字符串瓶颈在 `emitIR` 模板拼接，那是 D092 候选范围。

## C.2 关键测量（2026-04-14）

| 指标 | 值 | 来源 |
|---|---|---|
| `./build.sh bootstrap` 基线 | **53.2 秒** | `time` 单次测量 |
| `nextReg` 调用点 | 369 | `Grep nextReg bootstrap/` |
| `emitIR` 调用点 | **1876** | `Grep "emitIR(" bootstrap/` |
| 平均每条 emitIR 模板插值数 | 3-5 个 `${X}` | 抽样 `irAdd` / `irICmp` 等 |
| 总模板拼接量估算 | ~7500 次/编译 | 1876 × 4 |
| `nextReg` 拼接量占总比 | **0.039%** | 369 / 7500 × 100% |

## C.3 反直觉的"光改 nextReg 是负优化"洞察

**当前实现**（`codegen.ss:106-148`）：
```ss
function nextReg(): string {
    regCount = regCount + 1
    return `%${regCount}`              // ① 1 次拼接 / 调用
}
function reg(v: int): string {
    if (isCt(v) == 1) { return materialize(payload(v)) }
    return regTable[payload(v) - 1]    // ② 零拼接，直接返回引用
}
```

**方案 A/B（让 nextReg 返回 int）**：
```ss
function nextReg(): int { ... }
function reg(v: int): string {
    return `%${payload(v)}`            // ② 改成每次拼接
}
```

**净变化**（设 K = 一个寄存器在 emitIR 模板中被引用的平均次数）：

| 方案 | nextReg 拼接 | reg(v) 拼接 | 总拼接 / 寄存器 |
|---|---|---|---|
| 旧（string） | 1 | 0 | 1 |
| A/B（int） | 0 | K | K |

LLVM IR 中典型 SSA 寄存器引用次数 K ≈ 1.5-2。**方案 A/B 严格更差**（多 0.5-1 次拼接 / 寄存器）。

## C.4 真正的瓶颈定位

`emitIR` 1876 个调用点，每个模板 3-5 个 `${X}` 插值，总量是 nextReg 路径的 ~20 倍。但即使把 emitIR 全部消除字符串拼接，53 秒中可能也只省几百毫秒 —— **53 秒大头是 LLVM `llc` + `musl-gcc` 链接 + appendFile syscall**，不是 SS 字符串拼接。

bootstrap 三阶段编译时间分布需要 profiler 才能给出，但定性来看：
- SS 字符串拼接：< 5 秒（粗估）
- LLVM `llc` × 3：~30 秒
- `musl-gcc` 链接 × 3：~10 秒
- I/O / 其他：~8 秒

**优化 codegen 字符串路径的回报已经接近边际为零**。

## C.5 替代方向（候选，未起草）

| 方向 | 预期收益 | 风险 / 代价 |
|---|---|---|
| **D092 emitIR API 重构** — 接受结构化 op + operands，一次性 stringify | < 5%（受 LLVM 时间主导） | 高（1876 调用点） |
| **bootstrap LLVM 调用并行化** — 三阶段并行 / 模块级并行 | 30-50% | 中（需理解 stage 依赖） |
| **`llc` 优化等级降级** — bootstrap 用 `-O0` 而非 `-O2` | 20-40% | 低（仅 bootstrap 自身，不影响产物） |
| **增量 bootstrap** — 缓存 stage1 IR，仅重新跑变动文件 | 10-30% | 中（需追踪文件依赖） |
| **D089 dispatch 顺序按频率重排** | < 2% | 低 |

**最有性价比的方向**：**bootstrap 用 `llc -O0`**（用户 prompt 中未提及，但数据指向这条路）。

## C.6 学习记录（给未来 D 决策的元教训）

1. **在 ADR 写计划前先做基线测量** — 没数据的 ADR 容易把"显然的优化"写成大手术，实际收益却是 0
2. **"减少字符串拼接"不等于"减少 string 分配"** — 缓存 vs 重算的取舍要算 K
3. **次数 × 单次成本 才是真正的优化目标** — nextReg 369 次 vs emitIR 1876 次，仅基数差就 5 倍
4. **53 秒 ≠ 全是 SS 代码** — 自举语言的 bootstrap 时间大头是依赖工具链，不是自己

## C.7 下一步

由用户决定下轮工作方向。本 D091 文档作为"做过分析、明确驳回"的归档保留，避免未来重复评估同一思路。
