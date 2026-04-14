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

- **P17: Fix before add.** Open issues (`docs/4-issues/1-open/`) take priority over new features or stdlib modules. Do not add new functionality while known issues silently produce wrong code, crash, or force workarounds. ← V3, P4
- **P18: One task per context.** Each conversation context handles exactly one task (one issue fix, one feature, one refactor). When done or context runs low, update handoff and stop. External automation handles clear + `/next` for the next round. ← V6

## Workflow

- **P14: Atomic task execution.** Sequential steps of the same task (analyze → verify → commit) execute in one go. Handoff splits only at genuinely independent task boundaries. ← V6
- **P15: Simplify after verify.** After implementation is manually verified correct, review changed code for reuse, quality, and efficiency (`/simplify`). Run tests + bootstrap again after simplification. ← V5, V6
- **P16: Record decisions immediately.** Every design discussion that produces a confirmed decision → create a D-numbered doc in `docs/3-decisions/` before moving on. One decision per doc. Include: status, depends-on, decision text, reasoning, rejected alternatives, interfaces, tensions. ← V3, V5

---

## PFV 流程 (Problem-Fractal-Verification)

> 本节用中文。元工作流程，不是单条 P 原则；规范任意粒度的任务在动手前 / 完成时必须经过的两个 gate。

源于 P1 / P2 / P5 / P14 / P15 等开发流程原则，把「先验证 → 后宣告」上升为机制 hook。
**目的**：防 harness 工具（TaskCreate / Plan / D 文档 6 维度模板）强化「接到任务先结构化执行」的偏见，防 D 文档脚注里的「独立后续 / 候选 / 列为 D0NN 范围」被读成路线指引，防「基本完成 / 应该可以」的伪验证。

### 开工 gate（强制，第一次工具调用之前）

接到任意任务（含用户明确指定的），**第一次工具调用之前**必须用纯文字把七问 PSM 表格写在回复正文里。

- 任一字段空白 → 拒绝任务，提议替代
- 字段 1（总体）必须显式引用具体文件 + 段落（如 `D088 §Phase 8 缺失清单`），写「为了项目更好」不算
- 字段 1 引用不到 D088 在路线上的具体段落 → 任务不在 Zig 路线上 → 拒绝

唯一例外：用户明确说「我知道这不在 Zig 路线上，但本轮就要做 X」→ 接受，回复里显式标记「⚠ 偏离 Zig 路线，用户授权」。

#### 七问 PSM (Problem Statement Module)

| # | 字段 | 必答 |
|---|---|---|
| 1 | 总体 | 服务于哪个上层目标？显式引用具体文件 + 段落 |
| 2 | 第一性需求 | 真正的根本痛点（不是症状）。「为什么」问到底 |
| 3 | 核心目标 | 完成后用户能观测到的具体能力变化。一句话能证伪的单一判据 |
| 4 | 规则 | 本任务必须遵守的硬约束（引用 CLAUDE.md / memory / D088 等具体段落） |
| 5 | 界定 | 做什么 + 不做什么，两个清单都必填 |
| 6 | 步骤 | 具体可执行序列。每步 < 30 min；超过则递归再开一个七问 |
| 7 | 验证 | 五验 VCM 的具体填充，见下 |

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
| 5 | 路线 | 对照 D088 §正模式 / §反模式 / §验证标准 §核心验证 逐条打勾 | 防离开主线 |

### Fractal 承载

七问五验在所有层级递归适用。每层向上引用，**不重复内容**。

| 层 | 粒度 | 承载 | 形式 |
|---|---|---|---|
| **L0 项目** | 永恒 | `docs/1-axioms.md` + 本节 | 完整文档 |
| **L1 路线** | 月级 | `docs/3-decisions/Dxxx.md`（如 D088） | D 文档顶部 1 屏 |
| **L2 决策** | 周级 | `docs/3-decisions/Dxxx.md`（如 D089） | D 文档顶部 1 屏，引用 L1 |
| **L3 轮任务** | 单轮对话 | 对话首条回复（**不写文件**） | 紧凑七问表格，引用 L2 |
| **L4 子步骤** | < 30 min | TaskCreate description | 一行 inline |

**禁止**：

- L3 / L4 跨层跳过 L1 / L2 直接引用 L0
- D 文档脚注里的「独立后续 / 候选 / 列为 D0NN 范围」被当作路线指引（永远不是）
- harness 工具（TaskCreate / Plan）在七问填齐之前调用

### 反 over-engineer 警告

PFV 是机制 hook，不是模板堆。任何「再加一个文档 / 层级 / 字段」的冲动 → 先问「它能让七问五验更短吗？」，答否就不加。

本流程的成功判据：**下一轮 Claude 接到任意任务能在 5 分钟内填齐七问**，不是「流程文档完整度」。
