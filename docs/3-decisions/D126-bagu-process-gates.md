# D126: 八股流程层闸门梳理 + 流程反思入 PFV

**Status:** [x] Done at 2026-04-22(起草 + Execute 同轮收敛,A/B/C/D 全落地)
**Depends on:** D097(反射 14 指标 gate)、D102(F1 行数 gate)、D124(baseline 2 列制)、D125(gate 精准化)、`feedback_bagu_self_check`、`feedback_no_distant_offset`、`feedback_reflection_expansion_protocol`、`feedback_human_readable_code`、`feedback_ultrathink_gate`
**Date:** 2026-04-22
**Last Updated:** 2026-04-22

---

## 核心目标 (Goal)

- **为什么**:D125 聚焦数值 gate 精准化消除了"远距离榨指标"等**具体八股形态的诱因**,但留下一个**更上位的问题**没处理 —— 八股的**内核**(反身性 + 语义判断)无法纯机械化,真正的兜底是"用户回合间抽查"。D125 之前这是隐式依赖:靠 Claude 主动提出"这是不是八股"才触发,靠用户在回合间偶然点出才被截住。流程层没有显式 gate 保证这一层防线每轮触发。
- **是什么**:把"用户回合间抽查"从隐式习惯升为**显式 gate** —— PFV §收尾 gate 新增"流程反思"步骤,强制每轮 next 前审视本轮暴露的规则/ gate / 文本改进点,列 0–N 条候选交用户确认。同时对八股两类高发形态补"边缘机械化":commit 差半径 linter(远距离榨指标形态)+ commit footer 八股自检 linter(VCM 复盘凑仪式形态)。最后把完整梳理归档为 D126,避免结论只留对话缓冲区。
- **单一判据**:PFV 收尾 gate 从 3 步扩为 4 步(加"流程反思"),例外行含"不反思";`tools/commit_radius_linter.ss` + `tools/commit_footer_bagu_linter.ss` 可跑 smoke test 输出预期格式;本 D 文档归档含"已机械化 / 未机械化 / 元悖论 / 增量方向"四段。

> 口号:机械 gate 抑制**形态**,用户抽查抑制**内核**;两者是双支柱,流程反思是把隐式支柱升为显式。

---

## 核心原则 (Principles)

1. **八股内核反身性,不能纯机械化** — 判据"对任务核心产出零贡献"是**意图**层,linter 查的是**可观测特征**。同一改动(for-in→while)在扩容 refactor 场景合法,在 gate BLOCK 压指标场景非法,linter 无法区分。承认这个天花板,不追求 0 漏过。
2. **双支柱结构** — (a) 高发形态加机械 linter(D125/D126 累积)+ (b) 流程反思显式化用户抽查。任何新 gate 设计前问"是提升 (a) 还是 (b)",不是"堆更多仪式"。
3. **反思不是仪式** — 反思步骤本身若退化为"每轮打 ✓ 走过场"也是八股。对策是**无改进候选时显式写"无"+丢弃原因**,不允许空过;档位门槛(微改豁免)防止反思本身变 checklist 表演。
4. **表面解决记账,下轮升根** — 本 D 文档的 (B)(C) 是表面机械化(只标注不判对错 / 只校验格式不判真假),PSM 字段 10 标明"下轮升级路径"。不藏表面为根。
5. **D 文档归档 = 防对话缓冲区丢失** — 八股讨论结论若不落 D 文档,跨轮 Claude 读不到,只能靠 memory feedback 偶然命中。D126 是"八股流程层梳理"的**固定锚**。

---

## 1. Context Management

### 必读清单

1. 本文档
2. `docs/2-principles.md` §PFV 流程 + §收尾 gate(含本轮新增第 3 步"流程反思")
3. `docs/3-decisions/D125-gate-precision-improvements.md`(数值 gate 精准化前置)
4. `memory/feedback_bagu_self_check.md`(元规则)
5. `memory/feedback_no_distant_offset.md`(B 来源)
6. `tools/reflection_health_linter.ss`(已机械化层样例 + D125 scope-aware 实装)

### Stable Facts

| 项 | 值 |
|---|---|
| 已机械化 linter 数 | 6(D126 前 4:reflection_health / next_prompt_ultrathink / bugfix / dual_track;D126 新增 2:commit_radius / commit_footer_bagu)|
| 未机械化八股形态 | 6(见 §附录 A)|
| PFV 收尾 gate 步骤数 | 3 → 4(新增"流程反思") |
| 改动范围 | docs/ + tools/;bootstrap/ 不动 |

### 禁止的 Context 操作

- ❌ 把未机械化形态逐条"再加一个 linter"凑完整 — 违反核心原则 1,意图判断不能纯机械化
- ❌ 扩 scope 到"完全消除八股" — 天花板承认,追求降发生率而非 0 发生

---

## 2. Tool System

### 必备工具

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| Claude 内置 | `Edit` / `Write` / `Read` / `Grep` | 改 principles.md + 建 linter + 建 D 文档 |
| 项目 | `bin/ss run tools/commit_radius_linter.ss` | B 验证 |
| 项目 | `bin/ss run tools/commit_footer_bagu_linter.ss` | C 验证 |
| 项目 | `shell("git diff --name-only HEAD")` / `shell("git log / git show ...")` | linter 的 git 数据源 |

### 禁止引入

- ❌ 新关键字 / 新 language feature(纯 tools + docs)
- ❌ NLP 语义分析(违反核心原则 1,不追求识别意图)

---

## 3. 改进 A/B/C/D 细节

### A — 流程反思入 PFV §收尾 gate(根解)

**现状**:`docs/2-principles.md` §收尾 gate 3 步(代码审查 / 提交 / 下一步提示词),没有"反思"槽。八股讨论若本轮出结论,靠 Claude 下轮主动想起或用户回合间追问 —— 隐式依赖。

**改进**:§收尾 gate 2 后、3 前插入新"3. 流程反思(档位门槛)",原 3 重编号为 4。"三步必做"改"四步必做",例外行加"不反思"支持用户明说跳过。

**档位门槛**:标准改 / 大改必做;微改豁免(与 D125 §P5 档位政策对齐,避免"改一行注释也反思"变仪式)。

**反思产出格式**:列 0–N 条候选(无候选显式写"无"),以紧凑列表交用户确认。用户 Ok → 落位(principles.md / memory / D 文档 / tools/ 新 linter);用户 No → 本轮对话记录里点名"丢弃原因"防下轮重提。

**实施**:`docs/2-principles.md` 3 处 Edit:(1) "三步"→"四步";(2) 插入"3. **流程反思(档位门槛)**..."一整段;(3) 例外行加"不反思"。

**成本**:3 处 Edit,各 1-2 行。

**收益**:消除"八股自检元规则靠 Claude 主动提出才触发"的隐式依赖;流程反思每轮必做(档位门槛内),不漏。

### B — commit 差半径 linter(表面,远距离榨指标形态机械化)

**现状**:`feedback_no_distant_offset.md` 规则"linter REGRESSION 时不改动与任务无关的代码压 CC/M5"靠自觉。D125 §P2 scope-aware 反射 gate 消除非反射误伤,但仍靠改动者本人分类"本地 / 半径内 / 远距离"。

**改进**:新 linter `tools/commit_radius_linter.ss`,扫 `git diff --name-only HEAD`,按前 2 段路径划子族("bootstrap/gen" / "tools" / "docs/3-decisions"),散点跨 ≥3 无关子族 → FLAG "疑似远距离榨指标"软警告,提示 commit message 独立 justify 或按任务拆 commit。

**软警告不阻 commit**:判据粗,机械判对错不可能(反例:跨 3 子族但语义相关的 refactor 合法)。只标注留 human review 窗口。

**实施**:~85 行 SS,复用 D125 Execute 3 `shell()` builtin。子族算法:`familyOf(path)` 返回前 2 段,边界 `<root>` 对顶层文件。

**成本**:新 linter 文件 1 个,无文档改动(引用已在 D126 + feedback_no_distant_offset)。

**表面 vs 根**:**表面** —— 只标注可疑不判对错。**下轮升级路径**:结合 commit history 基线(累积 N commit 的"常见跨族 pattern")+ 语义相关性 proxy(文件族依赖图),达根解。

### C — commit footer 八股自检 linter(表面,VCM 复盘凑仪式机械化)

**现状**:`docs/2-principles.md` §VCM §第 5 条 (d) "八股沉积复盘"要求每项改动过"去掉少什么"元规则,答"不会少"→ 本项是八股当场 revert 或 commit message 点名。靠自觉,打 ✓ 可能没真过脑。

**改进**:新 linter `tools/commit_footer_bagu_linter.ss`,校验 commit message 含 "去掉少什么:" 字串 ≥ 1 次。缺 → GATE BLOCKED exit(1)。

**格式强制产出**:不校验答案质量,只校验**格式强制存在**。写假答案("去掉少什么: 不少")成本比不写高 —— 被 commit history 公开审视,用户回合间可追。

**实施**:~60 行 SS,消费 `shell("git log -1 --format=%B <rev>")` + `shell("git show --name-only --format= <rev>")`。当前版本判据极简("存在 ≥ 1"),不苛求"每文件一条"。

**成本**:新 linter 文件 1 个。

**表面 vs 根**:**表面** —— 只校验字串存在不判真假。**下轮升级路径**:(a) "每文件一条"强制(需 SS `indexOf` 支持 offset 重启);(b) 答案长度下限;(c) 语义相关性 proxy(答案含 file:function 引用)。

### D — D126 归档八股流程层闸门梳理(根解)

**现状**:D125 Plan + Execute 5 批完成后,八股讨论结论散在 feedback memory + D125 附录 + 对话上下文。没有单一入口文档承载"已机械化 / 未机械化 / 元悖论 / 增量方向"四段梳理。

**改进**:本 D 文档作为八股流程层梳理的**固定锚**。未来八股相关讨论可直接从本文档接续,不必每次从对话缓冲区重新推演。

**实施**:本文档按 D125 格式(Goal / Principles / 六节 + 附录 A/B),聚焦**流程层**闸门,不重复数值 gate 细节(D125 已覆盖)。

**成本**:本文档。

**表面 vs 根**:**根解** —— 防对话缓冲区丢失 + 跨轮共识锚。

---

## 4. State & Memory

### 持久化 state

- `docs/2-principles.md` §收尾 gate 4 步(A 落位)
- `tools/commit_radius_linter.ss` / `tools/commit_footer_bagu_linter.ss`(B/C 落位)
- 本 D 文档(D 落位)

### 禁止 state 操作

- ❌ 新建 `.claude/*` state 文件承载"流程反思记录"(反思在对话内 + D 文档,不在 state 累积)
- ❌ `linter_baseline.txt` 扩字段(commit_radius / commit_footer 都是 stateless linter,读 git state 即得)

---

## 5. Evaluation & Observation

### Execute 阶段判据(本轮 commit 前)

| # | 类型 | 检查 | 通过条件 |
|---|---|---|---|
| 1 | 文档判据 | `grep "3. \*\*流程反思" docs/2-principles.md` | ≥ 1 命中 |
| 2 | 工具判据 | `bin/ss run tools/commit_radius_linter.ss` | 正常输出 PASS/FLAG 不 crash |
| 3 | 工具判据 | `bin/ss run tools/commit_footer_bagu_linter.ss HEAD` | 正常输出(HEAD 上一轮 commit 不含答案行,预期 FAIL exit 1) |
| 4 | 归档判据 | `ls docs/3-decisions/D126-*.md` | 存在 |

### 回归信号

- ⚠ 本轮 commit 被 commit_radius_linter FLAG(跨 3+ 子族)—— 预期如此,commit message 需 justify 本次是"元流程改进同轮收敛"的跨族 justified 改动
- ⚠ 本轮 commit 未含"去掉少什么:"答案行 —— 若 C linter 接入 pre-commit gate 会 BLOCK;本轮为 linter 创建轮,接入策略下轮讨论,本轮 commit 允许不含答案行

### 升级判据

下轮若"流程反思"步骤出现"每轮答'无'无实质候选"现象 → 档位门槛过严,下移到"大改才必做";若出现"反思候选 60% 被用户 No + 无人回头删" → 反思本身变仪式八股,需加新 gate(例如 memory/feedback_reflection_quality 规则)。

---

## 6. Constraints & Recovery

### 硬约束

- 流程反思步骤不能退化为"每轮打 ✓"(防反思变仪式)
- B/C linter 本轮只建立,**不**接入强制 pre-commit gate(接入策略下轮讨论,避免 scope 过大)
- D 文档不重复 D125 数值 gate 细节(单一职责,D125 数值 / D126 流程)

### 失败模式 + 恢复

| 信号 | 恢复 |
|---|---|
| 流程反思被用户视为冗余 | 档位门槛上调(大改才必做)或拆出独立 D 文档 |
| commit_radius FLAG 过多假阳 | RADIUS_THRESHOLD 调高(3→4),或白名单机制 |
| commit_footer 格式强制变对抗(写"去掉少什么: 不少") | 加答案长度下限 + 禁止空话 pattern |

---

# 附录 A: 八股流程层闸门梳理

## A.1 已机械化层(6 个 linter)

| 层 | 工具 | 判据 | 抑制的八股形态 |
|---|---|---|---|
| 反射扩容 | `reflection_health_linter.ss` | 14 指标 vs `budget_max`(scope-aware) | 远距离榨指标(间接:超 tol 逼申报) |
| 下轮 payload | `next_prompt_ultrathink_linter.ss` | 文件存在 + 非空 + 含关键字 | 下轮退化成浅 reasoning |
| bug 修复 | `bugfix_linter.ss` | 证据文档 + 6 gate | 修 bug 无诊断靠感觉 |
| 双入口 | `dual_track_linter.ss` | scope 特征 | 双轨伪装成"兼容架构" |
| **本轮新增** commit 差半径 | `commit_radius_linter.ss` | 子族分布 ≥ 3 | 远距离榨指标(直接,soft warn) |
| **本轮新增** commit footer | `commit_footer_bagu_linter.ss` | "去掉少什么:" 字串存在 | VCM 复盘凑仪式(格式强制) |

## A.2 未机械化层(6 种形态,引自 `feedback_bagu_self_check`)

1. **远距离榨指标** —— 改无关代码压 CC/M5(本轮 B 软覆盖,未根解)
2. **凑 VCM 仪式** —— 每项打 ✓ 没真对照(本轮 C 格式外化,未根解)
3. **grep 摆样子** —— 跑命令只为满足 PSM 字段 1 槽(未机械化:意图判断)
4. **编造 D 文档段** —— 为让引用有物现起草一段 §X.Y(未机械化:意图判断)
5. **文档膨胀** —— 500 字解释做了什么其实一句话够(未机械化:价值判断)
6. **checklist 表演** —— TaskCreate 把微步骤拆成 task 产出零但进度条好看(未机械化:意图判断)

**原理限制**:八股 = "形式上满足规则,对任务核心产出零贡献",判据是**反身性**(回看自己刚写的)+ **语义**(核心产出定义依赖上下文)。linter 查**可观测特征**(指标数、关键字、路径、字串存在),看不见**意图**。同一 for-in→while 改动 D121 场景是八股、独立 refactor 场景合法,linter 无法区分。

## A.3 元悖论:流程本身会八股化

- 十问 PSM 填齐 ≠ 想清楚
- 五验 VCM 逐项 ✓ ≠ 真对照
- 收尾 gate N 步走完 ≠ 真产出
- **本轮新增流程反思步骤若退化为"每轮答'无'" ≠ 真反思**

D125 §P5 档位自报(微改/标准改/大改)是对这层的部分反制 —— 档位错报 + 实际超档 → 收工 gate 回写补齐暴露漂移。但档位判定本身(LOC + 文件数 + 函数签名变)也可被压字符绕过。

**终极闸门双支柱**:
- (a) 高发形态的机械 linter 倒逼(D125 / D126 累积)—— 覆盖**形态**
- (b) 用户回合间抽查 + 流程反思强制审视 —— 覆盖**内核**

D126 的贡献是**把 (b) 从隐式升显式**,不是"完美消除八股"。

## A.4 增量方向 vs 真正根解

| 方向 | 形式 | 达根解? |
|---|---|---|
| (A) 流程反思入 PFV | 收尾 gate 新增第 3 步 | **根解** — 消除"靠 Claude 主动提出"隐式依赖 |
| (B) commit 差半径 linter | 子族分布标注 | **表面** — 下轮升到"历史基线 + 语义相关性"达根 |
| (C) commit footer 八股自检 | 格式强制存在 | **表面** — 下轮升到"答案质量 / 每文件一条 / 语义相关"达根 |
| (D) D126 归档 | 文档落盘 | **根解** — 防对话缓冲区丢失 + 跨轮共识锚 |

## A.5 历史事件索引

| 事件 | 形态 | 诱因 gate | 消除路径 |
|---|---|---|---|
| D121 R1-A Execute 2 newTvArray 远距离榨指标 | 1 | 反射 14 指标粗 gate | D125 §P2 scope-aware + **D126 (B)** |
| D124 Execute 5 次 bump 串跑 | 仪式 O(N) | bump 单指标粒度 | D125 §P3 bump-group |
| 10e2c8b rowMap "bv:bm" + tuple 裸露 | 可读性失真 | simplify 3 维度缺 readability | D125 §P1 4th agent |
| F1 600 字符级塞字符 | 压缩/合并/删空行 | F1 硬阻无 soft warn | D125 §P4 AUTO-DRIFT |
| 简单改也十问 PSM | 仪式不分层 | PFV 粗粒度强制 | D125 §P5 三档分层 |
| **本轮:VCM (d) 沉积复盘靠自觉** | 2 | §VCM 无 commit footer 强制 | **D126 (C)** |
| **本轮:八股讨论结论留对话缓冲区** | 跨轮丢失 | 无流程反思 gate | **D126 (A) + (D)** |

---

# 附录 B: 实施日志

### 起草 + Execute(本轮) [x] Done at 2026-04-22

- **PSM**:大改档(新增 D 文档 + 4 文件 + LOC > 100)全十问填齐,⚠ 偏离 D088 Zig 路线用户授权标记。RED 三条全 FAIL(grep "流程反思" / ls commit_*linter / ls D126*)
- **(A) 流程反思入 PFV**:`docs/2-principles.md` 3 处 Edit:(1) 126 行"三步必做"→"四步必做";(2) 130 行原 "3. **下一步提示词**" 前插入新 "3. **流程反思(档位门槛)**" 整段,原 3 重编号为 4;(3) 135 行例外加"不反思"
- **(B) commit 差半径 linter**:新建 `tools/commit_radius_linter.ss`(~85 行),`shell("git diff --name-only HEAD")` + `familyOf(path)` 前 2 段子族算法 + `RADIUS_THRESHOLD = 3` soft warn。smoke test `bin/ss run tools/commit_radius_linter.ss` → 当前 working tree 3 文件 / 3 子族(docs / .claude / &lt;root&gt;)正确 FLAG RADAR SOFT WARN 输出
- **(C) commit footer 八股自检 linter**:新建 `tools/commit_footer_bagu_linter.ss`(~60 行),`shell("git log -1 --format=%B <rev>")` + `shell("git show --name-only --format= <rev>")` + "去掉少什么:" 字串存在校验。smoke test `bin/ss run tools/commit_footer_bagu_linter.ss` → HEAD(D125 全批收敛 commit d933c0d 不含答案行)正确 FAIL GATE BLOCKED exit 1
- **(D) D126 归档**:本 D 文档,A.1-A.5 四段梳理 + 附录 B 实施日志
- **VCM 五验**:
  - ① 工程:本轮不动 bootstrap/ / 不动 lib/,无需 `./build.sh bootstrap` 全跑;2 linter smoke test 等价局部 build
  - ② 行为:新能力 = "流程反思"被强制入 PFV + 2 linter 可跑;前(上一轮) `grep "流程反思" principles.md` = 0,后 ≥ 1
  - ③ 反向:删 `tools/commit_radius_linter.ss` → `bin/ss run tools/commit_radius_linter.ss` fail(文件不存在),证明因果
  - ④ 边界:commit_radius 空 diff → `GATE OK — no changes`;commit_footer 空 commit → `GATE OK — skipping`
  - ⑤ 路线 + 八股沉积复盘:⚠ 偏离 Zig 路线(流程元改进,用户授权)。本轮所有改动回放:(A) principles.md — 去掉少什么:流程反思强制 gate 缺失;(B) commit_radius — 去掉少什么:远距离榨指标无机械标注;(C) commit_footer — 去掉少什么:VCM 复盘无格式强制;(D) D126 — 去掉少什么:八股流程层共识锚缺失。四项均答"有缺",无八股沉积
- **commit**:5 文件(principles.md + 2 linter + D126 + 本附录 B 条目)同 commit,message 含"偏离 Zig 路线用户授权"标记 + D126 引用 + "去掉少什么:"答案行(满足 C linter 自我校验)
- **争议 / 遗留**:B/C linter 本轮只建立,**不**接入 pre-commit gate。接入策略留下轮讨论(是 `.claude/settings.json` hook? 是 `/simplify` 收尾附带? 是单独 `/commit-check` slash command?)

---

## 反模式 / 正模式

### ❌ 反模式
- 认为"加 linter = 消除八股"—— 内核反身性永远漏,机械化只覆盖形态
- 把 B/C 表面 linter 升级成"判真假"—— 违反核心原则 1,NLP 语义判断复杂化无收益
- 流程反思步骤打 ✓ 没实质候选 —— 反思自身变八股

### ✅ 正模式
- 新 gate 前问"是降 (a) 形态还是升 (b) 内核"—— 不堆仪式
- 表面机械化明确写 PSM 字段 10 "下轮升根路径"—— 不藏表面为根
- 讨论结论立即落 D 文档锚 —— 不留对话缓冲区

---

## 参考

- `feedback_bagu_self_check`(元规则,八股识别)
- `feedback_no_distant_offset`(B 抓手来源)
- `feedback_ultrathink_gate`(机械字符匹配 gate 样例)
- `docs/2-principles.md` §PFV 流程 §收尾 gate(A 落位)
- D097 / D102 / D124 / D125(数值 gate 基线链,D126 是流程层姊妹篇)
- commit `d933c0d`(D125 全批收敛,本 D 文档前置锚)
