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

### 改动分层（blast radius，D125 §P5 初值）

**每轮开工第一句声明档位自报**（格式："本轮档位:<微改|标准改|大改>(LOC ~N + M 文件)"），detector 工具延后自报。档位决定走多少 gate：

| 档位 | 判据 | §开工 gate (PSM) | §收工 gate (VCM) | §收尾 gate |
|---|---|---|---|---|
| **微改** | LOC delta ≤ 5 **且** 改 1 文件 **且** 无函数签名变 | **豁免** | **豁免** | 仅 next_prompt 写入（simplify 豁免，commit 可与其他轮合并）|
| **标准改** | LOC delta 6-100 **或** 2-5 文件 | 字段 1-5 必填（字段 6-10 可省）| 五验全 | simplify + commit + next_prompt 全走 |
| **大改** | LOC delta > 100 **或** > 5 文件 **或** 新增 D 文档 | 十问全 | 五验全 | simplify + commit + next_prompt 全走，**独立 commit 禁与其他改动打包** |

判定细则：

- 多维度叠加**取最严档**（LOC 120 + 1 文件 → 大改；LOC 3 + 3 文件 → 标准改）
- **函数签名变**（入参 / 返回类型 / 名改）一律升档至 ≥ 标准改（即使 LOC ≤ 5）
- **新增 D 文档**（即便仅 `[ ] Planned` 骨架）一律大改
- 档位自报错档 → §收工 gate 发现实际改动超自报档 → 回写档位 + 补齐缺省 gate，**不许**宣告完成
- 纯文档 / 纯配置改动仍按档位判；只是 §收尾 gate simplify 子步骤可显式跳过（无"代码"可审查）
- detector 工具（`tools/pfv_scope_detector.ss` 读 `git diff --shortstat` 自判）**延后**。届时此节升级为"自报 + 自判双轨，不一致阻断 commit"

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
- **字段 3 对 F1 / 文件拆分类任务**的 RED 命令**不许**只用 `wc -l ≤ 600` —— 那只是 F1 下限守护,不是 P10.1 终局判据。必须两步:(a) `grep '^(function|let|const)\s+\w+' <file>` 列 top-level 声明;(b) 按职责归类数类别,**类别 ≥ 3 → P10.1 不清晰,RED 成立,任务继续;类别 ≤ 2 → GREEN,任务不成立**。仅用 `wc -l ≤ 600` 判 GREEN → §字段 3 失效,PSM 作废重填(P10.1 / feedback_structure_not_linecount.md / D102 §最终目标 配套,2026-04-20 codegen.ss=492 baseline=1166 漂移误判 GREEN 教训)
- **字段 5 对"创建 bootstrap/X/<prefix>_Y.ss"类任务**的界定阶段必须运行"命名前缀族归位扫描":`filepref=$(basename <new_file> .ss \| cut -d_ -f1-2); find bootstrap -name "${filepref}*" -type f \| awk -F/ 'NR>0{OFS="/"; $NF=""; print}' \| sort -u`。输出 ≥ 1 个族目录 → 新建文件**归同目录**,除非 D 文档**显式写出脱族理由**;输出 0 个 → 按 P10.1 自由决定。Plan 型 D 文档起草 §决策 1(路径规划)同义务,把扫描输出贴进 D 文档;Execute 型轮贴进 PSM 与 D 文档路径对照,不一致 → 先回写 D 文档路径再开工。不做扫描 → Plan 路径决策漂,**任务拒绝**(feedback_subdir_split_style / feedback_naming_family_scan 配套,2026-04-20 D116 §决策 4 Execute 1 首写 `bootstrap/gen/gen_rt_cache.ss` 漏 `gen_rt_*` 前缀归 `gen/rt/` 子族用户手工补正教训)

- **字段 5 对"反射路径形态升级"类任务**的界定阶段必须识别"扩容判定":任务是否触及反射路径(`bootstrap/gen/class.ss` / `gen_stmts.ss` `.fields/.methods/.annotations/.args` / `genForInUnrolled` / `classXxxAnnotation*` / `comptimeConsts __*` sidecar)**形态升级**(容器类型如 Array→Map / AST 字段扩 / Meta kind 变更)?若是,**强制列全 14 指标 delta 预估**(M1/M2/M3a/M3b/M4/M5/M6/M7a/M7b/N1/N2/N3/N4/N5,不允许只列结构组漏累计组)→ 结构组任一 >0 或累计组任一超 tol → 三选一:(a) 本地抵消(列具体削减点,限 `feedback_no_distant_offset` 半径内);(b) 升 baseline + D 文档 §扩容申报;(c) 拆 commit(除非用户明确拒绝分轮)。D 文档 §扩容申报段**必含**扩容理由(引用 §第一性需求)/ 预期 14 指标 delta 对齐 PSM / 本地抵消路径 + 具体函数 / 新 baseline 预期值(=实测预估)/ VCM 实测 vs 预估对照槽(Execute 后回填)。不做扩容判定 → PSM 只强制结构组(M4/N3/M7b)预估漏累计组(M1/M2/M3a/M5/N1/N2)→ Execute 爆 tol → 被迫远距离榨指标(八股)。(`feedback_reflection_expansion_protocol` 配套,2026-04-21 D121 R1-A Execute 2 M1/M2/M5/N2 累计组预估漏掉被迫改 newTvArray 远距离榨指标教训)
- **八股自检(元规则,贯穿开工/执行/收尾,不绑 PSM/VCM 固定槽)** —— 任意即将编辑代码/文档/测试之前,**每次**先过一遍:**"如果去掉这个改动,任务的核心产出会少什么?"** 答"不会少任何东西"→ 停手,**这是八股,禁止落盘**;答"XYZ 功能/验证/说明缺一块"→ 继续。八股 = 形式上满足某规则/gate 但对任务核心产出零贡献,典型形态:远距离榨指标(linter BLOCKED 后改无关代码压 CC/M5)/ 凑 VCM 仪式(逐项 ✓ 但没真对照)/ grep 摆样子(跑命令不为知道结果只为满足字段 1 槽)/ 编造 D 文档段(为让引用有物现起草)/ 文档膨胀(500 字解释其实一句话够)/ checklist 表演(TaskCreate 把微步骤拆成 task 进度条好看但产出 ≈ 0)。不通过时**不许改**,回根因:扩容超 tol → 走 `feedback_reflection_expansion_protocol`;规则假命中 → 质疑规则向用户报告,不是绕规则;其他 → 停手想清楚,不要用八股填补。这是 `feedback_no_distant_offset` / `feedback_reflection_expansion_protocol` 等具体禁令的**上位元规则**,具体规则是对症治疗八股会以新形式钻过去,"是不是八股"覆盖所有变种。(`feedback_bagu_self_check` 配套,2026-04-21 D121 R1-A Execute 2 newTvArray while→for_in 远距离榨指标事件)

唯一例外：用户明确说「我知道这不在 Zig 路线上，但本轮就要做 X」→ 接受，回复里显式标记「⚠ 偏离 Zig 路线，用户授权」。

#### 十问 PSM (Problem Statement Module)

| # | 字段 | 必答 |
|---|---|---|
| 1 | 总体 | 服务于哪个上层目标？显式引用具体文件 + 段落。**必须先引用 D 文档 §第一性需求 段落**，再给出本轮工作和它的直接连线（不允许跨 phase 跳到子表）|
| 2 | 第一性需求 | 真正的根本痛点（不是症状）。「为什么」**至少问 2 层**，最后一层必须断言可观测的否定证据（"如果不这样做，会出现 X 现象"），不能止步于"为了 Y"|
| 3 | 核心目标 | 完成后用户能观测到的具体能力变化。**必须含一条可执行 RED 命令**（形如 `bin/ss run <file> 2>&1 \| grep <pattern>`），证明现状未达成。**第一个工具调用必须是这条命令**。若已 GREEN → 任务不成立，停下向用户报告 |
| 4 | 规则 | 本任务必须遵守的硬约束（引用 CLAUDE.md / memory / D088 等具体段落）。**rule 问答收敛循环 M=2 子问卷**(凡产出 commit 的标准改 / 大改任务必答,答案在 §VCM §5 (d) 贴循环证据;rule 库登记见 D126 §附录 B): <br>**commit_radius(N=3)**: Q1 本 commit 跨几个子族?列 `familyOf(path)=前 2 段` 分布; Q2 跨族分类(同任务扩展 / 元流程改进 / 远距离榨指标) + 理由; Q3 缩到 1-2 子族能完成任务吗?给耦合证据(no+证据 PASS / yes FAIL 要求拆 commit)。<br>**commit_footer(N=3)**: Q1(**红线**) 每项改动过"去掉它核心产出会少什么"元规则均答"有缺"?任一"不会少"未 revert / commit message 未点名 → 直接 FAIL 不进入下轮; Q2 commit message 含 "去掉少什么:" 行数 ≥ 改动文件数; Q3 每条答案含具体 file:function / 概念引用(非"无"/"不少"空话) |
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
| 5 | 路线 | (a) 对照 D088 §正模式 / §反模式 / §验证标准 §核心验证 逐条打勾；(b) **第一性需求距离**：本轮产出和 D088 §第一性需求 的实现路径间距（用 phase 数衡量）。距离 ≥2 phase → 警告"可能绕道"，必须给出"为何先做 phase X 而非更靠近 §第一性需求 的工作"的论证；(c) **表面 vs 根复检**：对照 PSM 字段 10 的标记，确认本轮**没有把表面解决伪装成根解决**；(d) **八股沉积 M-linter-K-M 问答收敛循环**: 本轮**所有**改动进入收敛循环 —— M 个 rule linter(初始 M = 2: commit_radius / commit_footer;子问卷见 §PSM 字段 4 内联;rule 库登记见 D126 §附录 B)各提 N 问 → 单轮问题总数 K = ΣN → 被查者逐条作答 → M 个 rule linter 独立读答案重判 → 任一 rule 仍有新问题 → 再轮;所有 rule 0 新问题 → **收敛 GREEN**。收敛判据:(i) **≤ 3 轮收敛**: PASS 入 VCM 下一验;(ii) **> 3 轮未收敛 / 累计 ≥ 2 条被识别为"空话"的答案**(单字答 / 与改动无关 pattern / 重复上轮答): FAIL 任务未完成,回 PSM 重构;(iii) **红线问必过**: commit_footer Q1 "每项改动过'去掉它核心产出会少什么'元规则是否均答'有缺'"—— 任一项答"不会少"且未 revert / commit message 未点名 → 直接 FAIL,不进入第 2 轮(这是原元规则的收敛循环内置化,不是取消)。扩容申报类任务叠加"预估 vs 实测"对账,累计组任一指标预估偏差 >50% → 写入 D 文档 §扩容申报 §预估失准段,下轮 PSM 开工前必读(对账步作为 commit_radius Q2 "跨族 justified 与否"证据之一);(`feedback_bagu_self_check` / `feedback_reflection_expansion_protocol` 配套) | 防离开主线 + 防八股跨轮沉积 |

### 收尾 gate（强制，五验 VCM 通过之后）

VCM 通过 ≠ 回合结束。宣告"完成"到实际 stop 之间还有四步必做动作，按顺序执行，缺一条不许 stop：

1. **代码审查**：`/simplify` 对本轮新增 / 修改的代码做质量审查，修复发现的问题。改动纯文档 / 纯配置可跳过并显式说明
2. **提交**：`git status` 有未提交改动 → commit（`/commit` 或手工），消息遵循 conventional commits。commit 必须落在同一轮对话里，不许跨轮补
3. **流程反思(档位门槛)**：基于本轮实际走过的流程,审视是否有规则 / gate / 文本需要升级。列 0–N 条候选(无候选显式写"无"),以紧凑列表交用户确认。用户 Ok → 落位(principles.md / memory / D 文档 / tools/ 新 linter);用户 No → 本轮对话记录里点名"丢弃原因"防下轮重提。档位门槛:标准改 / 大改必做;微改豁免(与档位政策对齐)。反思不是仪式 —— 是把"用户回合间抽查八股"从隐式习惯升为显式 gate,消除"八股自检元规则靠 Claude 主动提出才触发"的隐式依赖。不写反思段 → 下轮 Claude 不主动想起 → 八股讨论产出丢对话缓冲区 → 跨轮复用脆弱(D126 归档配套,2026-04-22)
4. **下一步提示词(自闭环两步)**:(a) 最后一条回复**直接输出**下一步简短提示词(1-3 句、单段、命令式、模仿用户原始风格),(b) **同时**覆盖写入 `.claude/next_prompt.md`(terman `claude-next` preset 的单次 payload,见 `docs/terman-auto-next.md`)。preset 监测 PTY 空闲 30s + 光标在 prompt 处,自动 `/clear` + bracketed paste + 30s 观察窗口 + Enter 触发下一轮;两处内容严格一致,用户在 30s 窗口内 Ctrl+C / 键入字符可中断。Phase 进度仍只落在 D 文档,`.claude/next_prompt.md` 不承载跨轮状态累积 / 进度摘要。Claude 本轮**不**执行任何脚本或 terman send —— stop 后 preset 自动接管。例外:bootstrap 失败 / 测试红 / GATE 阻断 / 用户明说不要时,**不写** payload 停下等裁决 —— preset `read_file` 返回空即 early return,天然降级
   - **Execute 型**(动词形态 "改 X / 重写 X / 去掉 Y / 修复 Z / 实现 W")**必须**附**本轮已跑过**的 **RED 命令 + 输出**作为凭据,证明 X 尚未达成。RED 无效(已 GREEN / 命令不成立 / 代码已是目标形态) → **不许写 Execute 型**,改为: (a) 宣告 "本轮已覆盖 X + 证据",终止本线路, 或 (b) 降级为 **Plan 型** "验证 / 巡检 X 现状,若发现 Y 再推进",把诊断权交回下一轮
   - **Plan 型**(动词形态 "验证 / 调研 / 巡检 / 对照 X")不要求 RED 凭据,但提示词里**不得**带 "改 / 重写 / 去掉 / 修复 / 实现" 等变更动词,避免退化为未经验证的 Execute 型
   - 这是防漂移**跨轮传播**的出口 gate——与 §开工 gate §字段 1 D 文档 grep 对照构成两道闸:上一轮关闭出口,下一轮关闭入口

例外：用户明说"不 simplify" / "不 commit" / "不反思" / "不要下一步" → 按用户要求跳过。没说就必须做。

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
