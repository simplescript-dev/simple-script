# Principles

Derived from Axioms. Each traces to Constraints or Values. Can refine, not violate.

## Development Process

- **P1: Bootstrap guard.** Every change → `bin/ss test tests/` → `./build.sh bootstrap`. No exceptions. ← C1
- **P2: Test before modify.** Confirm all tests pass before touching code. ← C1
- **P3: Behavior-preserving refactoring.** Pure refactoring produces identical IR output. ← C1, V6
- **P4: Root cause first.** Fix from source, no workarounds or hacks. ← V3
- **P4a: Compiler limitation is a bug, not a boundary.** When a compiler limitation forces ugly patterns in stdlib or user code, fix the compiler first. Do NOT record it as "Known limitation" and work around it. If the same workaround appears twice, stop and fix the root cause. ← V3, C1
- **P5: Verify, don't assume.** Technical conclusions must be validated. If uncertain, say so. ← V3

## Architecture

- **P6: Dispatcher only dispatches.** No business logic in dispatch functions (genExpr, genStmt, genBinary). Each case → one-line delegation to handler. Handler ≤ 50 lines. ← V5, V6 (derived from DI-1 refactoring)
- **P7: Flat if/else over dispatch table.** SS has no Map<string, fn>. Go/Rust also use flat switch. No multi-level dispatchers. ← V5 (derived from DI-1)
- **P8: Study before designing.** Check Go/Rust/Zig/Swift compiler approach before implementing any feature. ← V3
- **P9: Complexity in compiler, not user code.** Users should never see implementation details of memory management, vtables, or other internals. ← C5, V2
- **P10: Forward-compatible refactoring.** Refactoring blocked by missing language features (struct, enum) is deferred, not hacked around. ← V6

## Code Style

- **P11: Template strings for readability.** Use `` `${var}` `` over `+` concatenation. ← V5
- **P12: No dead code.** Deprecated code is deleted, not commented out. ← V5
- **P13: Extract only when justified.** Three similar lines are better than a premature abstraction. ← V6

## Priority

- **P17: Fix before add.** Unfinished decisions in `docs/3-decisions/` (marked `[ ] Planned` / `[-] Blocked` per P19) take priority over new features or stdlib modules. Do not add new functionality while known issues silently produce wrong code, crash, or force workarounds. ← V3, P4
- **P18: One task per context.** Each conversation context handles exactly one task (one issue fix, one feature, one refactor). When done or context runs low, update handoff and stop. External automation handles clear + `/next` for the next round. ← V6

## Workflow

- **P14: Atomic task execution.** Sequential steps of the same task (analyze → verify → commit) execute in one go. Handoff splits only at genuinely independent task boundaries. ← V6
- **P15: Simplify after verify.** After implementation is manually verified correct, review changed code for reuse, quality, and efficiency (`/simplify`). Run tests + bootstrap again after simplification. ← V5, V6
- **P16: Record decisions immediately.** Every design discussion that produces a confirmed decision → create a D-numbered doc in `docs/3-decisions/` before moving on. One decision per doc. Include: status, depends-on, decision text, reasoning, rejected alternatives, interfaces, tensions. ← V3, V5
- **P19: D 文档状态标注强制分离。** D 文档(`docs/3-decisions/D*.md`)每项 phase / 过渡策略 / 需求 / 待办**必须**形式标注状态:`[ ] Planned` / `[x] Done at <file:line>` / `[-] Blocked at <blocker>`。**禁止**在同一段落同时写未来时("需要实现 / 将 / 可改用 / 计划")和过去时("已实现 / 已达成")而不带状态标注。代码达成某项描述时,**必须**同步更新 D 文档状态标注(`[ ]` → `[x] Done at <file:line>`),不得只改代码不回写。P19 是 §PFV 流程 §字段 1 D 文档 grep 对照的配套——`[x] Done at <file:line>` 里的 file:line 直接给出 grep 目标,降低对照成本,但**不**绕过对照(`[x]` 也可能过时、代码已移动)。**不要求一次性回写所有历史 D 文档**,新写 / 修改的段落必须遵守,历史段落在被 §字段 1 对照命令触发引用时按结果逐步升级(不一致 → 回写)。← V3, V5, P4 (derived from 2026-04-15 D088 §过渡策略漂移根治)

---

## PFV 流程 (Problem-Fractal-Verification)

> 本节用中文。元工作流程，不是单条 P 原则；规范任意粒度的任务在动手前 / 完成时必须经过的两个 gate。

源于 P1 / P2 / P5 / P14 / P15 等开发流程原则，把「先验证 → 后宣告」上升为机制 hook。
**目的**：防 harness 工具（TaskCreate / Plan / D 文档 6 维度模板）强化「接到任务先结构化执行」的偏见，防 D 文档脚注里的「独立后续 / 候选 / 列为 D0NN 范围」被读成路线指引，防「基本完成 / 应该可以」的伪验证。

### 开工 gate（强制，第一次工具调用之前）

接到任意任务（含用户明确指定的），**第一次工具调用之前**必须用纯文字把十问 PSM 表格写在回复正文里。

- 任一字段空白 → 拒绝任务，提议替代
- 字段 1（总体）必须显式引用具体文件 + 段落（如 `D088 §Phase 8 缺失清单`），写「为了项目更好」不算
- 字段 1 引用不到 D088 在路线上的具体段落 → 任务不在 Zig 路线上 → 拒绝
- 字段 1 必须先引用 §第一性需求 段落再引用任何子表（§Phase X / §下一批 / §待办清单），不允许跳过 §第一性需求 直接接子表
- 字段 1 引用的清单里若有「状态」/「待办」/「✅」等标记，**该标记不权威**。必须用字段 3 的 RED 命令亲自验证，不得直接信任
- 字段 1 引用的**每一条** D 文档段落,**必须同时**附一条 grep / test / ls 命令(贴命令 + 输出),证明该段落描述的代码现状是 `[已达成 / 未达成 / 部分达成]`。不跑对照 → D 文档应然被当实然传进 PSM,**任务拒绝**。对照结果与 D 文档描述不一致(语态矛盾 / 标注过时 / 代码已移动) → **先回写 D 文档状态标注(参照 P19 `[x] Done at <file:line>`),再填 PSM 开工**。这是防漂移**跨轮传播**的入口 gate——即使上一轮交接文本脑补出假任务,字段 1 对照命令在本轮开工瞬间暴露漂移,不给任务走到字段 3 RED 才被截住的机会
- 字段 2（第一性需求）的 Why 链 < 2 层 → 字段不算填齐，回去补深度
- 字段 8（对照实验）答 no → 本轮任务降级为 backlog，不做（除非用户授权偏离）
- 字段 9（Plan vs Execute）若是 Plan，必须在字段 7 的 VCM 填充里把 ④ 边界 替换为「替代方案对比 + 隐藏假设挑战」
- 字段 10（表面 vs 根）禁止只写「根」不给消除的双轨制 / 架构根因；写「表面」必须同时给出「下一轮如何升级到根」。多产出项任务（如巡检）必须**对每一项**单独标记

唯一例外：用户明确说「我知道这不在 Zig 路线上，但本轮就要做 X」→ 接受，回复里显式标记「⚠ 偏离 Zig 路线，用户授权」。

#### 十问 PSM (Problem Statement Module)

| # | 字段 | 必答 |
|---|---|---|
| 1 | 总体 | 服务于哪个上层目标？显式引用具体文件 + 段落。**必须先引用 D 文档 §第一性需求 段落**，再给出本轮工作和它的直接连线（不允许跨 phase 跳到子表）|
| 2 | 第一性需求 | 真正的根本痛点（不是症状）。「为什么」**至少问 2 层**，最后一层必须断言可观测的否定证据（"如果不这样做，会出现 X 现象"），不能止步于"为了 Y"|
| 3 | 核心目标 | 完成后用户能观测到的具体能力变化。**必须含一条可执行 RED 命令**（形如 `bin/ss run <file> 2>&1 \| grep <pattern>`），证明现状未达成。**第一个工具调用必须是这条命令**。若已 GREEN → 任务不成立，停下向用户报告 |
| 4 | 规则 | 本任务必须遵守的硬约束（引用 CLAUDE.md / memory / D088 等具体段落） |
| 5 | 界定 | 做什么 + 不做什么，两个清单都必填 |
| 6 | 步骤 | 具体可执行序列。每步 < 30 min；超过则递归再开一个十问 |
| 7 | 验证 | 五验 VCM 的具体填充，见下 |
| 8 | **对照实验** | **不做这件事，§第一性需求 会被卡住吗？** 必答 yes/no + 一句证据。答 no → 本轮任务降级为 backlog，不做（除非用户明确说"我知道这不在主路径上，但本轮就要做 X"）|
| 9 | **Plan vs Execute** | 本轮产出形态：**Execute**（代码改动）/ **Plan**（方向、清单、调研、巡检）。Plan 任务的 VCM ④ 边界 替换为「替代方案对比 + 隐藏假设挑战」，不依赖代码层验证 |
| 10 | **表面 vs 根** | 本任务**和每个产出项**：根解决 / 表面解决？**根** → 一句话给出消除的双轨制 / 架构根因（"消除的根是 X"）。**表面** → 必须同时写「本轮接受表面的成本理由」+「下一轮如何升级到根」。两者都不写 → 字段为空，任务拒绝 |

### 收工 gate（强制，任务完成宣告之前）

任务完成宣告之前**必须**用五验 VCM 表格逐项打勾，**每项贴证据**（命令输出 / 代码片段 / IR / 行为日志）。

- 任一未通过 → 任务未完成，禁止说「完成 / 收工 / done」
- 五验不能 self-attest（不能用同一证据填两项）
- 证据必须能被独立第三方复跑

#### 五验 VCM (Verification Cross-check Module)

| # | 验证 | 内容 | 防造假属性 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` 固定点 + `bin/ss test tests/` 全绿 | 客观自动 |
| 2 | 行为 | 写一段最小新能力代码，**前 ≠ 后**。前一段必须复现失败 / 不存在的能力，后一段 demo 新能力 | 不许引用现有测试 |
| 3 | 反向 | 删除新实现 → 必须看到失败 | 强制证明因果 |
| 4 | 边界 | 极限 / 异常 / 空 / 类型边界输入 | 防 happy path bias |
| 5 | 路线 | (a) 对照 D088 §正模式 / §反模式 / §验证标准 §核心验证 逐条打勾；(b) **第一性需求距离**：本轮产出和 D088 §第一性需求 的实现路径间距（用 phase 数衡量）。距离 ≥2 phase → 警告"可能绕道"，必须给出"为何先做 phase X 而非更靠近 §第一性需求 的工作"的论证；(c) **表面 vs 根复检**：对照 PSM 字段 10 的标记，确认本轮**没有把表面解决伪装成根解决** | 防离开主线 |

### 收尾 gate（强制，五验 VCM 通过之后）

VCM 通过 ≠ 回合结束。宣告"完成"到实际 stop 之间还有三步必做动作，按顺序执行，缺一条不许 stop：

1. **代码审查**：`/simplify` 对本轮新增 / 修改的代码做质量审查，修复发现的问题。改动纯文档 / 纯配置可跳过并显式说明
2. **提交**：`git status` 有未提交改动 → commit（`/commit` 或手工），消息遵循 conventional commits。commit 必须落在同一轮对话里，不许跨轮补
3. **下一步提示词**：最后一条回复**直接输出**下一步简短提示词（1-3 句、单段、命令式、模仿用户原始风格）。同一份提示词允许同时写入 `.claude/next_prompt.md` 作为 `tools/send_next.ss` 的 payload（用户触发 terman 注入下一轮），见 `docs/terman-auto-next.md`；禁止的是用 handoff 文件做跨轮状态累积 / 进度摘要，Phase 进度仍只落在 D 文档
   - **Execute 型**(动词形态 "改 X / 重写 X / 去掉 Y / 修复 Z / 实现 W")**必须**附**本轮已跑过**的 **RED 命令 + 输出**作为凭据,证明 X 尚未达成。RED 无效(已 GREEN / 命令不成立 / 代码已是目标形态) → **不许写 Execute 型**,改为: (a) 宣告 "本轮已覆盖 X + 证据",终止本线路, 或 (b) 降级为 **Plan 型** "验证 / 巡检 X 现状,若发现 Y 再推进",把诊断权交回下一轮
   - **Plan 型**(动词形态 "验证 / 调研 / 巡检 / 对照 X")不要求 RED 凭据,但提示词里**不得**带 "改 / 重写 / 去掉 / 修复 / 实现" 等变更动词,避免退化为未经验证的 Execute 型
   - 这是防漂移**跨轮传播**的出口 gate——与 §开工 gate §字段 1 D 文档 grep 对照构成两道闸:上一轮关闭出口,下一轮关闭入口

例外：用户明说"不 simplify" / "不 commit" / "不要下一步" → 按用户要求跳过。没说就必须做。

此 gate 是 `feedback_auto_simplify` / `feedback_simplify_not_terminal` / `feedback_next_prompt_terse` 三条 memory 的合流入口——下轮 Claude 读 PFV 能一次看全，不再依赖散落 memory 的偶然命中。

### Fractal 承载

十问五验在所有层级递归适用。每层向上引用，**不重复内容**。

| 层 | 粒度 | 承载 | 形式 |
|---|---|---|---|
| **L0 项目** | 永恒 | `docs/1-axioms.md` + 本节 | 完整文档 |
| **L1 路线** | 月级 | `docs/3-decisions/Dxxx.md`（如 D088） | D 文档顶部 1 屏 |
| **L2 决策** | 周级 | `docs/3-decisions/Dxxx.md`（如 D089） | D 文档顶部 1 屏，引用 L1 |
| **L3 轮任务** | 单轮对话 | 对话首条回复（**不写文件**） | 紧凑十问表格，引用 L2 |
| **L4 子步骤** | < 30 min | TaskCreate description | 一行 inline |

**禁止**：

- L3 / L4 跨层跳过 L1 / L2 直接引用 L0
- D 文档脚注里的「独立后续 / 候选 / 列为 D0NN 范围」被当作路线指引（永远不是）
- harness 工具（TaskCreate / Plan）在十问填齐之前调用

### 反 over-engineer 警告

PFV 是机制 hook，不是模板堆。任何「再加一个文档 / 层级 / 字段」的冲动 → 先问「它能让十问五验更短吗？」，答否就不加。

本流程的成功判据：**下一轮 Claude 接到任意任务能在 5 分钟内填齐十问**，不是「流程文档完整度」。
