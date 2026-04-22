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
- **P10.1: 拆分判据是结构清晰,不是行数。** 文件/模块拆分完成后,**禁止**以"行数 ≤ 600 / D102 R4 达成 / F1 GATE PASS"宣告结束。终局判据是**结构清晰**:(a) 单一文件职责单一 —— 内部 top-level function + let 可按职责归为**一类**,出现 ≥ 3 职责类别即不清晰;(b) 跨文件依赖单向 —— A → B 不反向。完成拆分后必须执行"结构清晰度复盘":列 top-level 声明按职责归类,职责 ≥ 3 类则按同 D 文档的细分预案继续拆,依赖回路立即修。行数 gate 和结构 gate **并列**,不可前者代替后者。← V3 (derived from 2026-04-20 D113 Execute 3+4 复盘:codegen.ss 492 ≤ 600 R4 达成但 eval/interp_core.ss 544 行内部混堆 TypedValue 容器 / 标量构造 / 控制流 flag / 对象容器操作 / Comptime buffer / scope 管理 6 个职责层)

## Code Style

- **P11: Template strings for readability.** Use `` `${var}` `` over `+` concatenation. ← V5
- **P12: No dead code.** Deprecated code is deleted, not commented out. ← V5
- **P13: Extract only when justified.** Three similar lines are better than a premature abstraction. ← V6
- **P13.1: Readable.** ← V5

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

> 本节仅作**入口速查**。**完整规则已迁至 `docs/3-MNK.md`**(PSM 十问 / VCM 五验 / 改动分层 / 收尾 gate / 八股自检 / rule 问答收敛循环 / 特定领域 gate / Fractal 承载全文)。两处内容以 `docs/3-MNK.md` 为准。

**元工作流程骨架**(`docs/3-MNK.md` 定义):

- **M — Before Code**:写代码前的 M 个问题(十问 PSM 开工 gate,第一次工具调用前必答)
- **N — After Code**:写代码后的 N 个问题(五验 VCM 收工 gate,宣告完成前必答)
- **K — After Lint**:跑 lint 后的 K 个问题(rule 问答收敛循环,M=2 默认 commit_radius / commit_footer)
- **Continue NK 循环**:N → K → 改代码 → N → K 反复,直到全 pass
- **After Done**:收尾 gate 四步(simplify → commit → 流程反思 → next_prompt 自闭环)

**档位门槛**(决定走多少 gate):微改豁免 / 标准改 字段 1-5 + 五验全 / 大改 十问全 + 五验全 + 独立 commit。

**目的**:防 harness 工具(TaskCreate / Plan / D 文档 6 维度模板)强化「接到任务先结构化执行」的偏见,防 D 文档脚注里的「独立后续 / 候选 / 列为 D0NN 范围」被读成路线指引,防「基本完成 / 应该可以」的伪验证。

详细 10 问 / 5 验 / 三档档位 / 收尾四步 / 八股自检 / rule 子问卷 / reset 双重 gate / 反射扩容协议等全部在 `docs/3-MNK.md`。每次接到任务先回头读该文件。

