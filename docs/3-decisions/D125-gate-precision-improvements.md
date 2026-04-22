# D125: Gate 精准化改进 — 消除数值 / 字符代理失真诱发的八股

**Status:** [ ] Planned(Plan 型,锁决策不动代码;Execute 另轮触发)
**Depends on:** D097(反射根因 14 指标 gate)、D102(F1 行数 gate)、D124(baseline 2 列制 + bump CLI)、`feedback_auto_simplify`、`feedback_bagu_self_check`、`feedback_no_distant_offset`、`feedback_reflection_expansion_protocol`、`feedback_human_readable_code`、`feedback_ultrathink_gate`、`feedback_600_split_not_inline`
**Date:** 2026-04-22
**Last Updated:** 2026-04-22

---

## 核心目标 (Goal)

- **为什么**:现有 gate 用**数值单调** / **字符匹配**代理**质量 / 语义**,代理粒度粗 → 夹缝宽 → 诱发八股(远距离榨指标、凑申报仪式、牺牲可读换简洁)。历史已累积 7+ 条 feedback 作事后补丁(no_distant_offset / bagu_self_check / reflection_expansion_protocol / human_readable_code / 600_split_not_inline 等)——八股仍反复发作,根因是 gate 本身不精准。
- **是什么**:gate 升级三维度:(a) **scope-aware** 数值单调(按改动触及的路径白名单过滤误伤)、(b) **bundled 申报**(一次能力扩展覆盖多指标单 audit trail)、(c) **simplify 加可读性维度**(refactor 时可读赢简洁)。辅以小幅 delta 豁免 + 仪式触发条件精细化。
- **单一判据**:Execute 完成后,D121 R1-A 同等能力扩展(AST 形态升级触发 5+ 指标累积升)的申报成本从"5 次 bump CLI + 扩容申报段独占 D 文档位"降至"1 次 `bump-group` CLI + 1 段 §扩容申报"; D121 newTvArray 类远距离榨指标诱因消除;simplify 审查不再出现 `rowMap "bv:bm"` / tuple 无解包 / `check*` 返 int 作 bool 这三类反模式。

> 口号:gate 查病因,不查症状;病因清则八股自灭。

---

## 核心原则 (Principles)

1. **代理失真优先于代理精度** — 代理(LOC / M1-M7 / grep 命中)都有失真,本决策不追求"完美代理"而是**让 gate 失真时的八股代价 ≤ gate 命中时的收益**。不追求 0 false positive,追求可接受 false positive。
2. **scope 第一,数值第二** — REGRESSION 判定先看改动 scope(patch 是否触及反射路径白名单),再看数值。非反射改动踩 M1/M2 属**误伤**不阻 commit。
3. **合法扩容无仪式障碍** — 能力扩展(主线第一性需求)必升物理指标,申报路径成本应 **O(1)**(一次 CLI + 一次文档段),不是 O(N 个指标)。
4. **simplify 的可读性优先** — simplify agent 第 4 维度 `readability` 升为 hard rubric,可读性反模式(见 `feedback_human_readable_code` 5 条)直接拒 simplify 建议,不再让"减重复"单维度奖励。
5. **仪式按 blast radius 分层** — 小改动(注释 / rename / 单行 fix)豁免 PSM 十问 + simplify;大改动(新文件 / 函数签名改 / LOC delta >= 50)保持全仪式。gate 当红灯不当路障。
6. **字符匹配降为兜底** — ultrathink keyword linter / grep 对照段落等**纯字符**规则,作为"宁可误拒不可漏过"的兜底。主判据升语义(D 文档段落实际承载该含义 / 提示词实际暗示 extended thinking),字符是次判据。

---

## 1. Context Management

### 必读清单

1. 本文档
2. `docs/2-principles.md` §PFV 流程 + §收尾 gate(仪式现状)
3. `docs/3-decisions/D097-reflection-root-cause-metrics.md`(反射 gate 基线)
4. `docs/3-decisions/D102-f1-file-line-gate.md`(F1 行数 gate,若存在)/ 否则直接 read `tools/reflection_health_linter.ss` F1 段
5. `docs/3-decisions/D124-linter-baseline-budget-two-column.md`(2 列制 + bump CLI)
6. `~/.claude/projects/.../memory/feedback_*.md` 全扫,识别所有"事后补丁规则"作反向 gate 需求来源
7. `tools/reflection_health_linter.ss`(主战场)+ `tools/next_prompt_ultrathink_linter.ss`(关键字匹配样例)

### Stable Facts

| 项 | 值 |
|---|---|
| 现有 gate 数 | 反射 14 + F1 8 + simplify + PSM + ultrathink + bump CLI + bugfix harness,共 7 族 |
| 事后补丁 feedback 数 | ≥7(`feedback_no_distant_offset` / `bagu_self_check` / `human_readable_code` / `600_split_not_inline` / `reflection_expansion_protocol` / `psm_field1_grep` / `next_prompt_verify`)|
| 基线当前态 | D124 Execute 轮完成,14 指标 + 8 F1 全 2 列制 GATE PASS |
| 本 Plan 改动范围 | tools/ + docs/ + memory/ 规则升位;bootstrap/ 不动 |

### 禁止的 Context 操作

- ❌ 扫 bootstrap/ 源码 — 本 Plan 不动编译器,纯工具链 + 文档
- ❌ 扩大 scope 到"gate 全废" — feedback 规则是历史教训的 distillation,不能扔,只能升精准

---

## 2. Tool System

### 必备工具

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| Claude 内置 | `Read` / `Edit` / `Grep` | 改 linter + D 文档 + memory |
| 项目 | `bin/ss run tools/reflection_health_linter.ss` | 反射 gate 验证 |
| 项目 | `bin/ss run tools/next_prompt_ultrathink_linter.ss` | 字符匹配 gate 样例 |
| 项目 | `bin/ss run tools/reflection_health_linter.ss bump / bump-group` | 扩容申报 CLI(Execute 后扩) |
| 验证 | `git diff --name-only HEAD` | scope-aware gate 的 diff 输入 |

### 禁止引入

- ❌ 新 gate 工具(本决策是**精准化既有 gate**,不是加新 gate)
- ❌ 新依赖 / 新关键字
- ❌ NLP 语义匹配复杂化(字符匹配兜底足够,见原则 6)

---

## 3. 改进方向 P1-P6

### P1 — simplify 加 readability 第 4 维度(最高优先,最低成本)

**现状**:`Skill simplify` 3 agents 并跑(reuse / quality / efficiency),奖励减重复。结果:上轮(`10e2c8b`)reviewer 建议合并两 Map → `rowMap "bv:bm"` 是最典型失真 — 减行数但失可读性,commit 后发现须再一轮 `44e0dfd` 回校。

**改进**:simplify 内建 agent prompt 加第 4 agent `readability`,rubric = `feedback_human_readable_code` 5 条:
- (a) 结构化数据禁 string 编码塞 `Map<string, string>`
- (b) `Array<int>` 作 tuple 返回调用方必立即解包
- (c) `int` 作 bool 命名必 `is*` / `has*` / `matches*`
- (d) 抽 helper 必**增加语义**不只减行数
- (e) "陌生人单函数秒懂"自检

readability agent 对其他三维度有**否决权**:reuse agent 建议"合并两 Map" 若 readability 判违反 (a),simplify 不采纳。

**实施**:`~/.claude/skills/simplify.md`(若存在)或等价 skill 定义加第 4 agent 调用;不动代码只改 prompt 文本。

**成本**:估 30 行 prompt 编辑;验证 = 下轮 simplify 实际跑时触发 readability agent 输出。

**收益**:根除 `feedback_human_readable_code` 对应的三类反模式源头;本轮教训不复发。

---

### P2 — 反射 gate 加 scope-aware 过滤(高优先)

**现状**:`tools/reflection_health_linter.ss` 对 `bootstrap/` 全量 scan,M1-M7 + N1-N5 不区分改动 scope。非反射路径改动(例如 `bootstrap/pir/pir_opt.ss` 加一个优化 pass)若推高 M1/M2 会被 14 指标 gate REGRESSION 阻,实际与反射无关 → 误伤 → 诱发远距离榨指标八股。

**改进**:linter 读 `git diff --name-only HEAD`,判改动文件集是否**触及反射路径白名单**(D097 §开发流集成已列:`bootstrap/gen/class/*.ss` / `bootstrap/gen/stmts/*.ss` / `bootstrap/checker/check_stmts.ss` / `bootstrap/gen/codegen.ss` reflection 段 / 新加 `classXxxAnnotation*` 全局)。

- 触及反射路径:M1-M7 + N1-N5 全 gate 保留(原行为)
- 未触及反射路径:M1-M7 + N1-N5 **仅 report 不阻**(降为 DRIFT 信息提示);F1 行数 gate 保留(每文件 size ≤ budget_max 仍硬阻)

**实施**:linter `main()` 开头加 `diffFiles = listDiffFiles()` + `isReflectionScope(diffFiles): int` helper;`compareAndReport` 按 scope 切 hard/soft 模式。

**成本**:估 50-80 行 linter 代码增量;需 bin/ss 支持 `bash("git diff --name-only HEAD")` 或等价 — 可能需要扩 runtime function。

**收益**:消除非反射改动误伤;`feedback_no_distant_offset` 补丁(其实只补了"不许远距离抵消",未补"不许误伤")升为 gate 层面根解。

---

### P3 — bump-group 一次申报多指标(中优先)

**现状**:D121 R1-A 能力扩展同时推高 M1/M2/M3a/M5/N2 五指标,D124 Execute 实际跑了 5 次 `bump` CLI,每次单独 trail=D121#扩容申报,audit trail 冗长。

**改进**:新增 CLI `bump-group <doc_anchor> <metric1>=<budget1> <metric2>=<budget2> ...` 一次性申报多指标,audit trail 写成单行 `# bump-group M1=5168 M2=76617 M3a=12158 M5=1765 N2=383085 trail=D121#扩容申报 date=2026-04-22`。逐项校验(每项 newBudget >= bmOld)+ 原子写入(任一失败全拒)。

**实施**:linter `bumpCmd` 旁加 `bumpGroupCmd`,共享校验逻辑(可复用 `isRegression` / `mapGetIntOrNeg`);`main()` dispatch 加 `bump-group` branch。

**成本**:估 60 行代码;保持现有 `bump` 单指标兼容。

**收益**:能力扩展申报从 O(N 指标) 降到 O(1);D 文档 §扩容申报段保持单段 + 列表形态。

---

### P4 — 小幅 delta 豁免申报(中优先,需阈值定标)

**现状**:任何 cur > budget_max 都走 bump 申报流程(CLI + D 文档锚 + section grep 命中)。即便 M4+1(新加一个小 case 分支)也要走全路径 → 申报成本 > 改动成本 → 诱发榨指标抵消而非申报。

**改进**:引入 soft DRIFT 区间:
- `cur > budget_max` 且 `cur <= budget_max * (1 + TOL_PCT)` → **AUTO-DRIFT**:gate 不阻,linter 输出 `⚠ AUTO-DRIFT: ${metric} cur=${cur} within ${TOL_PCT*100}% of budget`,建议但不强制 bump
- `cur > budget_max * (1 + TOL_PCT)` → REGRESSION 原行为(硬阻,须 bump / bump-group 或回压)

阈值取 `TOL_PCT = 0.01`(1%)— 量级上覆盖"新增 1 个 case 分支"级的主线微扩,排除"新加 Map 容器"级的结构扩容。初值可议。

**实施**:`reportDelta` 在 `cur > bm` 分支加 soft DRIFT 计算;`writeBaseline` 对 AUTO-DRIFT 允许 record 升 bv 到 cur(类似 §决策 2.1 DRIFT 行)。

**成本**:估 20 行 linter 代码 + D097/D124 文档同步;引入一个魔数 `TOL_PCT`。

**收益**:小幅主线微扩无仪式;榨指标抵消动机消失;保持大扩容走申报严格路径。

**争议点**:阈值 1% vs 0.5% vs 动态阈值,需用户裁决。0.5% 是旧单列 tol 值,1% 是新估算(D121 R1-A M1+0.66% 属 AUTO-DRIFT 边缘)。偏向 1% 但留用户定。

---

### P5 — PFV 仪式按 blast radius 分层(中优先)

**现状**:CLAUDE.md §PFV 流程强制"接到任意任务,第一次工具调用之前必须按 PSM 填表;任务完成宣告之前必须按五验 VCM 逐项贴证据;VCM 通过后必须走收尾 gate"。"任意"粗粒度 → 简单改动(改一行注释 / rename 一个变量)也要填十格 PSM + 跑 simplify + 写下轮 next_prompt → 凑仪式。

**改进**:按 blast radius 分**三档**,仪式对应:
- **微改**(LOC delta ≤ 5 且只改 1 个文件且无函数签名变):**豁免 PSM + simplify**,直接 commit;收尾 gate 只保留 next_prompt 写入
- **标准改**(LOC delta 6-100 或 2-5 文件):PSM 字段 1-5 + VCM + simplify + 收尾 gate 全走
- **大改**(LOC delta > 100 或 > 5 文件或新增 D 文档):全十问 PSM + 五验 VCM + simplify + 收尾 gate + 独立 commit 不合并

Blast radius 判定可自动(linter 读 `git diff --shortstat`)或自报(用户 / Claude 在开工时声明档位)。

**实施**:`docs/2-principles.md` §PFV 流程段分层改写;可加 `tools/pfv_scope_detector.ss` 自动判档(可选)。

**成本**:规则文档升位,无代码改动强制;若加 detector 工具估 40 行。

**收益**:消除"改一行注释也要走十问"仪式八股;保持大改动严格性。

**争议点**:档位边界(5 / 100)取值、自动判 vs 自报、detector 是否必要。

---

### P6 — 字符匹配 gate 加语义兜底(低优先,长尾)

**现状**:`next_prompt_ultrathink_linter` grep `ultrathink` 字面;PSM 字段 1 grep 对照 D 文档段落字面。语义等价但字面不同的写法被误拒。

**改进**:字符匹配作**主判据**(简单、机械、可机校),不升复杂 NLP。但**兜底规则**:字符未命中时,允许用户 / Claude 在下一次工具调用前**显式声明 bypass 理由**(例如写入 `.claude/gate_bypass.txt` 单行 `<gate-name>: <reason>`),bypass 声明本身被下轮 gate 扫描并 audit trail 记录。

**实施**:linter 支持读 bypass 文件;bypass 消费后清空;audit 写 `git log` commit message。

**成本**:估 30 行;引入新 state 文件(轻微)。

**收益**:语义等价的写法不再需重写;刻板字符匹配边缘案例有通路。

**优先级放最低**:当前字符匹配误拒率低,P6 是锦上添花;若 P1-P5 做完 P6 可砍。

---

## Execute 优先级排序

| # | 方向 | 成本 | 收益 | 争议度 | 建议优先级 |
|---|---|---|---|---|---|
| P1 | simplify + readability 第 4 维 | 低(prompt) | 高(根除上轮教训源头) | 低 | ★★★★★ |
| P2 | 反射 gate scope-aware | 中(50-80 行) | 高(误伤根解) | 中(需 bin/ss bash 能力) | ★★★★ |
| P3 | bump-group CLI | 中(60 行) | 中(能力扩展仪式 O(1)) | 低 | ★★★ |
| P4 | 小幅 delta 豁免 | 低(20 行 + 文档) | 中(微扩无仪式) | 中(阈值取值) | ★★★ |
| P5 | PFV 仪式分层 | 规则改写为主 | 高(微改八股消除) | 中(档位 + detector) | ★★★★ |
| P6 | 字符匹配语义兜底 | 中 | 低(边缘案例) | 低 | ★ |

**建议 Execute 入口**:P1 + P5(仪式层)先 Execute 作为第一批 — 立竿见影 + 成本低 + 无代码争议;P2 + P3 + P4(工具层)作为第二批 Execute — 涉及 linter 改动,需与 D097/D124 同步。P6 延后或砍。

---

## 4. State & Memory

### 编译时 / 运行时 state

| 变量 | 文件 | 角色 |
|---|---|---|
| `baselineMap` / `budgetMap` | `tools/reflection_health_linter.ss` | 14 指标 + 8 F1 baseline(D124 落地,本 Plan 不动) |
| `TOL_PCT` | 新增 const,候选 `tools/reflection_health_linter.ss` | P4 soft DRIFT 阈值 |
| diff scope | runtime(Execute 后) | P2 scope-aware 判据输入 |

### 会话间持久化

- `git log` — 本 Plan 起草 commit 作历史锚
- 本文档 — Plan 唯一记录
- `feedback_*.md` — Plan 依据的历史教训快照

### 禁止 state 操作

- ❌ 把八股历史事件逐条列入代码注释(已在 feedback memory 里,不重复)
- ❌ Plan 阶段改代码

---

## 5. Evaluation & Observation

### Plan 阶段判据(本轮 commit 前)

| # | 类型 | 检查 | 通过条件 |
|---|---|---|---|
| 1 | 架构判据 | P1-P6 每项都答"哪个八股消除 + 代价几何 + 争议点是什么" | 是 |
| 2 | 文档判据 | D125 文档覆盖 Goal / Principles / P1-P6 / Execute 优先级 / 依赖闭环 | 是 |
| 3 | 依赖判据 | `grep -l "feedback_human_readable_code\|feedback_bagu_self_check\|feedback_no_distant_offset" MEMORY.md` | 3 命中 |
| 4 | 代码判据 | `git diff --stat` 仅 docs/ 改动,bootstrap/ + tools/ 零改动 | 是 |

### Execute 阶段判据(另轮)

按选定 Execute 入口(P1/P5 或 P2/P3/P4)分批设计,本 Plan 不预写。

### 回归信号

- ⚠ Plan 阶段若出现"必须立即改 gate"冲动 — 违反 interactive_one_doc,停下等用户指认入口
- ⚠ Plan 写着写着变 6000 字大文档 — 违反 Plan 型精简原则,重写压缩

---

## 6. Constraints & Recovery

### 硬约束

- Plan 型不动代码(`feedback_design_no_code_authority` + `feedback_interactive_one_doc`)
- 不为"完美精准"牺牲 Plan 可落地性(P1 低成本优先抓手必放最前)
- 本 Plan 内容不再被 commit 后调整;后续调整起 D125.x 或合入 Execute 轮 commit message

### 失败模式 + 恢复

| 信号 | 恢复 |
|---|---|
| P1-P6 之外发现新八股形态 | 起草新 Px 或合入 P5 仪式分层;不挤 D125 已定章节 |
| 用户否决某 Px | `git commit --amend` 前只改 D125 §决策段;已 push 则起 D125.1 |
| Execute 轮实测收益 < 预估 | 回头改 D125 §Execute 优先级;不扩 scope |

### 升级判据

模型 / 反射路径设计升级时本文档需要复审:
- "数值单调代理失真"的清单是否还成立?
- P2 白名单路径是否还是真反射路径?(D118 sidecar cleanup / D120 reflect classes global 后路径变化)
- P4 TOL_PCT 阈值是否匹配新基线规模?

---

# 附录 A: 决策细节

## A.1 问题 — 八股现象分类

历史事件归类(从 `feedback_*.md` + git log 还原):

| 事件 | 何时 | 八股形态 | 诱因 gate |
|---|---|---|---|
| D121 newTvArray 远距离榨指标 | 2026-04-21 Execute 2 事件链 | 改 checker 反射路径外代码压 M5/CC | 反射 14 指标粗 gate |
| D124 Execute 轮 5 次 bump 串跑 | 2026-04-22 | 能力扩展申报仪式 O(5) | bump CLI 单指标粒度 |
| 10e2c8b rowMap "bv:bm" + tuple 裸露 + checkXxx 返 int | 2026-04-22 本轮 | simplify 奖励减重复牺牲可读 | simplify 3 维度缺 readability |
| F1 600 字符级塞字符 | 早期 D102 事件 | 压缩注释 / 合并样板 / 删空行 | F1 行数硬阻无 soft warn |
| 简单改动也填十问 PSM | 反复发作 | PSM 字段 grep 摆样子 | PFV 仪式不分层 |

**共性**:gate 强制一个粗代理,人为绕代理保命。治代理不治症状。

## A.2 根因推演

gate 设计者的心智模型:**"如果 cur 不升,质量就不降"**。失真点:

1. **代理假设失真**:M1 CC 总和升 ≠ 质量降。新 kind 分支是能力扩展(好),复制粘贴逻辑也升 CC(坏)—— 数值不区分两者。
2. **场景不等权**:反射路径触碰 vs 非反射路径触碰对 14 指标的"负担"语义不同,但 gate 等权处理。
3. **仪式无量纲**:PSM 十问对"改一行注释"和"新 AST 节点"等难度,但工作量失衡。
4. **字符匹配刻板**:`ultrathink` 关键字成"暗号",写作者被迫机械插入而非主动深度思考。
5. **申报成本结构**:O(N 指标)线性,与主线第一性需求的 batched 扩容天然矛盾。

## A.3 Plan / Execute 边界

本 Plan 只决"做什么 + 优先级"。每个 Px 的实施细节(函数签名 / 数据结构 / 阈值取值)由 Execute 轮起草 PSM 细化,可能分 Px → Px.1 / Px.2 拆步。

---

# 附录 B: 实施日志

### Plan(起草轮) [x] Done at 2026-04-22 ← 本轮

- D125 起草:八股分类 + 根因 + P1-P6 改进方向 + Execute 优先级排序
- 依赖锁定:7 条 feedback 历史补丁 + D097/D102/D124 gate 基线
- 代码零改动,仅 docs/3-decisions/D125-*.md 新增
- **验证**:Plan 阶段 4 判据通过(架构 / 文档 / 依赖闭环 / 代码边界)

### Execute(第一批)[ ] Planned — 待用户指认 Px 切入点

候选:P1(simplify + readability)+ P5(PFV 仪式分层)并行

### Execute(第二批)[ ] Planned

候选:P2 + P3 + P4 工具层联动;P6 延后

---

## 反模式 / 正模式

### ❌ 反模式
- 认为 "加 gate = 提升质量",忽视 gate 代理失真
- 给每个八股形态补 feedback 规则但不回头修 gate 本身(治症不治因)
- Plan 里堆 10 个改进方向每个只讲 1 句 → 没法 Execute

### ✅ 正模式
- gate 升级先问"这个 gate 消除哪个八股形态"而不是"这个 gate 监控什么"
- feedback 规则作历史线索定位 gate 精准化入口
- Plan 按成本-收益-争议度三维度排 Execute 优先级,不按主观热度

---

## 参考

- `feedback_bagu_self_check`(元规则:八股识别)
- `feedback_no_distant_offset`(P2 抓手来源)
- `feedback_reflection_expansion_protocol`(P3 抓手来源)
- `feedback_human_readable_code`(P1 抓手来源)
- `feedback_600_split_not_inline`(P4 抓手来源)
- D097 / D102 / D124(gate 基线)
- commit `44e0dfd`(readable refactor 教训)
- commit `10e2c8b`(原 simplify 反模式样例)
