# MNK: 解决问题流程闸门(单一事实源)

> 本文档是 SimpleScript 项目八股流程层闸门的**单一事实源**。PSM 九问、VCM 六验、改动分层、收尾 gate、八股自检、rule 问答收敛循环,以及所有前后文流程反射规则,全部收敛在这里。
>
> 跨轮 Claude 读 `CLAUDE.md` + 本文档即可覆盖整套流程规则,不必再追分散 memory。
>
> 结构按用户骨架:**Before Code(M 个问题)→ After Code(N 个问题)→ After Lint(K 个问题)→ Continue NK 循环 → After Done(收尾)**。

---

## 核心原则(5 条)

1. **八股 = 形式满足规则但对核心产出零贡献** —— 判据是**反身性**("去掉它核心产出会少什么?"),linter 只查形态不查意图
2. **终极闸门双支柱**:(a) 高发形态机械 linter 倒逼(覆盖形态) + (b) 用户抽查 + 流程反思强制审视(覆盖内核);新 gate 前自问"升 (a) 还是升 (b)",缺一不可
3. **反思不是仪式** —— 无改进候选时显式写"无" + 丢弃原因,档位门槛(微改豁免)防反思本身变 checklist 表演
4. **表面解决必须记账** —— 机械 linter 只校验格式不判真假时,PSM 字段 9 标"下轮升根路径",不藏表面为根
5. **结论立即落 D 文档或本文档锚** —— 跨轮讨论结论若只留对话缓冲区或 memory,下轮 Claude 读不到,只能偶然命中

---

## 改动分层(档位,决定走哪些 gate)

**每轮开工第一句声明档位自报**(格式:"本轮档位:<微改|标准改|大改>(LOC ~N + M 文件)"):

| 档位 | 判据 | M (Before Code) | N (After Code) | NK 循环 | After Done |
|---|---|---|---|---|---|
| **微改** | LOC delta ≤ 5 **且** 1 文件 **且** 无签名变 | **豁免** | **豁免** | 豁免 | 仅 next_prompt(simplify 豁免,commit 可合并) |
| **标准改** | LOC delta 6-100 **或** 2-5 文件 | 字段 1-5 必填(6-10 可省) | 六验全 | 必做 | 全四步 |
| **大改** | LOC delta > 100 **或** > 5 文件 **或** 新增 D 文档 | 九问全 | 六验全 | 必做 | 全四步 + **独立 commit 禁打包** |

**判定细则**:

- 多维度叠加**取最严档**(LOC 120 + 1 文件 → 大改;LOC 3 + 3 文件 → 标准改)
- **函数签名变**(入参 / 返回类型 / 名改)一律升档至 ≥ 标准改(即使 LOC ≤ 5)
- **新增 D 文档**(即便仅 `[ ] Planned` 骨架)一律大改
- **删文件 / 重命名文件计入"文件数"**,与修改文件同档位影响不打折(元规则巡检 / 批量 deprecation 等清理型任务典型触发;2026-04-24 Phase 2 memory 合并 7 删 + 3 改起初判标准改 VCM §4 才回写大改事件)
- 档位自报错档 → After Code 发现实际超自报档 → 回写档位 + 补齐缺省 gate,**不许**宣告完成
- 纯文档 / 纯配置改动仍按档位判(simplify 豁免细则见 §After Done §1 例外)
- 纯审阅 / 纯问答 / 0 文件 0 代码改动任务 → 档位低于微改,PSM / N / K 全豁免,仅输出答案;用户若明示要求流程反思(如"列候选"),按要求执行
- **多 issue 串跑判定**(与 feedback_interactive_one_doc 协同):
  - 一轮内允许跑 **≥ 2 个 issue** 的唯一条件:全部命中**微改**档位(LOC ≤ 5 + 1 文件 + 无签名变)
  - 全微改 → After Done simplify / 流程反思豁免;**commit 可合并**,但 message 里每个 issue 一项对照 `docs/4-issues/IXXX-*.md` 的 "去掉少什么"(commit_footer Q1)
  - 任一 issue 触及**标准改 / 大改** → 一轮**只做一个 issue**,其余 issue 立项推迟到下轮 next_prompt
  - `bin/ss run /loop-planner`(若未来实装)或手工规划时必须先按上表判每个 issue 档位,不许靠"感觉这轮能全做完"蒙混
  - 不守此规的典型后果:bootstrap × N 次 trial-and-error 把对话拖到 compact,中途改动丢上下文 → 跨 issue 耦合失控

---

## M — Before Code: 写代码前的 M 个问题(开工 gate)

**强制**:接到任意任务(含用户明确指定的),**第一次修改性 tool call(Edit / Write / Bash 带变动 / commit / push)之前**必须用纯文字把九问 PSM 表格写在回复正文里。核对性 tool call(Read / Grep / Glob / ls / git status / git log)**不触发** PSM 义务 —— 字段 1 "D 文档对照"天然要求先跑核对命令,严格"0 工具调用填 PSM"只能靠记忆推断字段 1,漂移风险高。

> 历史:原锚点"第一次工具调用之前"(含核对性)于 2026-04-24 R1 统一放宽至通用规则(原仅 §特定领域 §Compact 恢复 gate 例外),消除场景分裂,理由:核对性命令填充 PSM §字段 1 D 文档对照是合理前置而非漂移。

### 九问 PSM (Problem Statement Module)

| # | 字段 | 问什么 | 约束 |
|---|---|---|---|
| 1 | 总体 | 服务于哪个上层目标? | **必须先引 D 文档 §第一性需求 段落**,再接子表(禁跳子表);引用的**每一条** D 文档段落**必须同时附** grep / test / ls 命令证明 `[已达成 / 未达成 / 部分达成]`;不跑对照 → 任务拒绝;对照结果与 D 文档描述不一致(语态矛盾 / 标注过时 / 代码已移动) → 先回写 D 文档状态标注(P19 `[x] Done at <file:line>`)再开工。防漂移**跨轮传播的入口 gate**(与 §收尾 Execute 型 RED 凭据构成两道闸) |
| 2 | 第一性需求 | 真正根本痛点(不是症状)?"为什么"**至少 2 层**,末层必须断言可观测否定证据("不做 → 出现 X 现象") | Why 链 < 2 层 → 字段不算填齐,回去补 |
| 3 | 核心目标 | 完成后可观测的具体能力变化;**必须含一条 RED 命令**(形如 `bin/ss run <file> 2>&1 \| grep <pattern>`),证明现状未达成 | **第一个工具调用必须是这条命令**;已 GREEN → 任务不成立,停下报告。**文件拆分类任务**的 RED **不许**只用 `wc -l ≤ 600`,必须两步:(a) `grep '^(function|let|const)\s+\w+' <file>` 列 top-level 声明;(b) 按职责归类,**≥ 3 类 → RED 成立**;仅 wc -l → PSM 作废重填(P10.1 配套);**表行增删类任务**的 RED 必须限定**表唯一锚**(表标题关键字 / 列值组合,如 `^\| 6 \| 根因`),避免裸 grep 跨表命中其他表同编号行造成假 RED(2026-04-22 MNK §N 增 §6 行首次 RED `grep -c '^\| 6 \|'` 命中 PSM §6 步骤致差值失真事件)。**用户 prompt RED 实测不成立**(如 `grep -c "@HelloController_hello" = 0` 但实测 =1 因函数 def 占位)→ Claude **主动 refine pattern** 更精确化(限定 `call.*@X` / match 非定义行 / 表唯一锚),PSM 字段 3 显式注明"重构自用户 RED:原 `<pattern>` 实测 = N(命中 define/meta noise),精确化为 `<new-pattern>` 实测 = 0"。不许直接放弃任务,也不许模糊复述让实测判据失真(2026-04-24 I014 §路径 A 本轮 RED grep 原 pattern 命中 define 行事件)。**runtime 反常行为最小变量隔离义务**:诊断 SS 运行时 bug(Map.get 返指针 / Array.indexOf 返 -1 / 模板插值异常 等)**前**,必须先做 one-liner 最小隔离测试 —— **每个可疑 API/操作单独 println**,避免多可疑点一揽子怀疑导致误诊 + 绕道式 workaround(与 feedback_root_cause_no_cost 同族,执行层细化)。违规例:同一个测试里既用模板字符串又入 Map 再 get,观测到错乱直接判"模板和 Map 都有问题"并全改 concat;正例:先 `println(\`${x}:${y}\`)` 不入 Map 验证模板本身 OK,再 `m.set("k","v")` + `println(m.get("k"))` 验证 get 本身 → 精确锁定 Map<string,string>.get 是唯一可疑点。**触发事件**:2026-04-24 D 文档死指针清零轮 — Claude 误把 Map.get string 返指针 bug 锅丢给字符串模板 concat,用户纠正 "模板那么好用怎么不用" |
| 4 | 规则 | 本任务硬约束(引用 CLAUDE.md / 本文档 / D088 等具体段落) | |
| 5 | 界定 | 做什么 + **不做什么**,两清单都填;**SSoT 术语改名扩展**:改本文档 / CLAUDE.md / D088 等 SSoT 文档的术语(如"五验→六验" / gate 重命名 / 字段重编号)前,**必须** `grep -rn <旧术语> CLAUDE.md docs/` 核对外链,界定里**显式列每处**"同步更新 / 保留为史实"的处理,漏扫 → 跨轮术语分裂(2026-04-22 MNK "五验→六验" 后 CLAUDE.md 两处漏扫事件) | 场景触发型扩展义务见 §特定领域 gate(命名前缀族扫描 / 反射路径根因 gate B 路径) |
| 6 | 步骤 | 可执行序列,> 30 min 步骤拆 L4 子表(见 §Fractal) | |
| 7 | 对照实验 | **不做这件事,§第一性需求 会被卡吗?** | 必答 yes/no + 一句证据;no → 本轮任务**降级为 backlog 不做**(除非用户明说偏离授权) |
| 8 | Plan vs Execute + Layer | (a) **Execute**(代码改动)/ **Plan**(方向、清单、调研、巡检);(b) **Layer**: **Issue**(执行单元,docs/4-issues/IXXX) / **Decision**(设计单元,docs/3-decisions/DXXX) / **Implementation**(实施单元,代码 + 测试 + lib + 配置) | Plan 型 VCM ④ 边界 替换为「替代方案对比 + 隐藏假设挑战」;**Layer 跨越触发 stop**:本轮 Layer ≠ PSM 字段 1 引用的上层 D 文档/issue 同 Layer 时,**stop 让用户授权或拆轮**(默认不跨层)。例外:issue 文档 §风险节 / §候选路径节明示 "若 X 则起 DXXX 决策" 类 hard prereq,实测命中即视为本轮跨层授权,但 Decision 文件**必须**先于 Implementation 落地(D 文档独立审查窗口不许吞)。**触发事件**:2026-04-24 I015 §收尾反思 R4 候选 2 — I015 (issue) 实测后内嵌起 D128 (decision) + 实施(implementation) 三层混在一轮,跨多轮反复(I014 同模式),根因是 PSM 字段 8 是 Plan vs Execute 二分缺 Layer 维度。**清单型 Execute 二次校验义务**:Plan 型产出"删/合并/保留"清单(元规则巡检表 / 批量 deprecation 列表 / 批量重命名清单),Execute 阶段**不许**按 Plan 判定一刀切批量执行,必须**为清单每项独立跑 PSM §字段 9 表面/根判定**(含字段 9 新增的"删除前 grep 验证")。Plan 阶段判定是清单层(粗粒度按元规则 yes/no),Execute 阶段判定是实例层(细粒度按"目标已落实"验证),两层不可互相吸收。**触发事件**:2026-04-24 元规则巡检 Plan 判 A11/A14/A18 = N 直接删,Execute 阶段未跑独立判定 → commit 前 grep 验证才发现 3 项均未在合并目标落实,撤回删除。 |
| 9 | 表面 vs 根 | 本任务**和每个产出项**:根解决 / 表面解决? | **根** → 一句话给出消除的双轨制 / 架构根因;**表面** → 必须同时写「本轮接受表面的成本理由」+「下一轮如何升级到根」;多产出项任务**对每一项**单独标记。**删除 / 合并 / deprecate 类操作专属 gate**:删 memory / 合并 D 文档 / 删除既有规则 / 移除 file:line 锚 前,**必须**先 grep 目标合并位置验证内容已落实(同等 file:line 锚 + 类型语义不丢失 + 触发条件不缺);未落实 → 先迁移再删,不许 Plan 阶段判定"细节 patch / 已合并"即立即 Execute 删除。**grep 不是形式匹配,是语义覆盖** —— 对要删的 memory 或规则块,Why/How to apply 每分句独立 grep,每句都能在合并目标 file:line 找到等价表达;单一关键词 substring 命中不足以判 ✓(2026-04-24 Phase 2 收尾 §字段 9 首次实战补强)。**触发事件**:2026-04-24 元规则巡检 Plan 判 A11 invoke_sentinel = N 直接删,commit 前 grep 发现 D128/I014 都没保留 method_call.ss:75-102 file:line 锚,撤回删除恢复;后续 A14/A18 同理保守缩窄到"合并目标已落实的 A20"删。 |

### 唯一例外

用户明确说「我知道这不在 Zig 路线上,但本轮就要做 X」→ 接受,回复里显式标记「⚠ 偏离 Zig 路线,用户授权」。

---

## 八股自检(元规则,贯穿 Before / During / After)

任意即将编辑代码 / 文档 / 测试之前,**每次**先过一遍:

**"去掉这个改动,任务的核心产出会少什么?"**

- 答"不会少任何东西" → **停手,这是八股,禁止落盘**
- 答"XYZ 功能 / 验证 / 说明缺一块" → 不是八股,继续

**典型形态**:详见 §附录 B.2(6 种已识别形态)。

**不通过时回路**:
- 扩容超 tol → 走 §特定领域 §反射路径根因 gate B 路径(申报 + 升 baseline),不绕道
- 规则假命中 → 质疑规则**向用户报告**,不是绕规则
- 其他 → 停手想清楚,不要用八股填补

---

## N — After Code: 写代码后的 N 个问题(收工 gate)

**强制**:任务完成宣告之前必须用六验 VCM 表格逐项打勾,**每项贴证据**(命令输出 / 代码片段 / IR / 行为日志)。

### 六验 VCM (Verification Cross-check Module)

| # | 验证 | 内容 | 防造假属性 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` 固定点 + `bin/ss test tests/` 全绿 | 客观自动 |
| 2 | 行为 | 写一段 demo 新能力的最小代码,前 ≠ 后(不得引用既有测试) | 防空改 |
| 3 | 反向 | 删除新实现 → 必须看到失败 | 强制证明因果 |
| 4 | 边界 | 极限 / 异常 / 空 / 类型边界输入(Plan 型替换为「替代方案对比 + 隐藏假设挑战」) | 防 happy path bias |
| 5 | 路线 | (a) 对照 D088 §正模式 / §反模式 / §验证标准 §核心验证 逐条打勾; (b) **第一性需求距离**:本轮产出和 D088 §第一性需求 实现路径间距(用 phase 衡量),≥ 2 phase → 警告"可能绕道",必须论证"为何先做 phase X"; (c) **K 收敛 GREEN**(见 §K 章) | 防离开主线 + 防八股跨轮沉积 |
| 6 | 根因 | 反身性灵魂问:**本轮改动是真的是根因解决吗?**(a) 逐项复查 PSM 字段 9 "根 / 表面" 标记,落地后再答一次 —— "根"项给出消除的双轨制 / 架构证据(引 file:line 或 D 文档段);"表面"项给出"下轮升级到根"的落点(issue 文件名 / D 文档章节),不许"已考虑 / 已规避"空话;(b) 追问:**如果明天用户质疑这是 workaround,我能拿 file:function 或不变量名反驳吗?** 答不出具体锚 → 视作表面,回 PSM 字段 9 改标记并补"下轮升级路径";(c) 与 §5 (a) 正 / 反模式不同 —— §5 问"是不是走主线",§6 问"主线上这步是不是真根治",两层分立不互相吸收 | PSM 字段 9 自证 + VCM §6 事后他证,双轨消除"根标记靠自觉"的漂移;防表面伪装根 |

**硬规则**:
- 任一未通过 → 任务未完成,**禁止说「完成 / 收工 / done」**
- 六验**不能 self-attest**(不能用同一证据填两项)
- 证据必须能被**独立第三方复跑**

**§验 1 豁免条款**:本轮改动**核心代码路径 diff=0**(`git diff HEAD -- bootstrap/ lib/ tools/` 空输出 —— 即改动仅落在 `docs/` / `tests/` / `.claude/` / `.harness/` / 配置等非编译器产出路径)可显式豁免 `./build.sh bootstrap` 固定点 + `bin/ss test tests/`,声明"核心代码路径 diff=0"即可;豁免证据**必须贴** `git diff --stat HEAD -- bootstrap/ lib/ tools/`(空输出 = PASS),在 VCM §5 (c) 自证,不许隐式跳。Execute 型代码改动(`bootstrap/` / `lib/` / `tools/` diff ≠ 0)无此豁免。

**旧判据 "纯文档 / 纯配置" 已废**:原判据基于改动**类型**(主观归类 "这算文档还是配置?"),升级为基于改动**证据**(grep diff 机械可校验),天然覆盖 `tests/` 单测 / `docs/` D 文档 / `.claude/` payload / `.harness/` 脚本等非核心路径,消除 "test-only 改动仍按 Execute 型跑全测试" 冗余开销;同时杜绝把 `bootstrap/` 小改 prompt 塞进 "文档类" 的漂移。2026-04-24 I008 落位(对应反思候选 (4))。

**扩容申报类任务**叠加"预估 vs 实测"对账,累计组任一指标预估偏差 > 50% → 写入 D 文档 §扩容申报 §预估失准段,下轮 PSM 开工前必读(对账步作为 commit_radius Q2 "跨族 justified 与否"证据之一)。

---

## K — After Lint: 跑 lint 后的 K 个问题(rule 问答收敛循环)

### M-linter-K-M 问答收敛循环(当前 M=2,K=6)

本轮**所有**改动进入收敛循环:M 个 rule linter 各提 N 问 → 单轮问题总数 **K = ΣN** → 被查者逐条作答 → M 个 rule linter 独立读答案重判 → 任一 rule 仍有新问题 → 再轮;所有 rule 0 新问题 → **收敛 GREEN**。

**收敛判据**:
- (i) **≤ 3 轮收敛**:PASS 入 VCM 下一验
- (ii) **> 3 轮未收敛** / **累计 ≥ 2 条"空话"答案**(单字 / 与改动无关 pattern / 重复上轮答):FAIL,任务未完成,回 PSM 重构
- (iii) **红线问必过**:见各 rule 红线问栏

**rule 库(当前 M=2)**:子问卷 + 扩展规则详见 §附录 A。

---

## Continue Code: 循环 NK 反复

写代码 → **N 六验** → **K 收敛** → 不过关 → **改代码** → 再 N → 再 K → ……

直到当前问题的 N 和 K **全 pass**,才能进入 After Done。

---

## After Done: 收尾 gate 四步必做

VCM 通过 ≠ 回合结束。宣告「完成」到实际 stop 之间还有**四步必做**动作,按顺序执行,缺一条不许 stop。

**顺序重排说明(2026-04-24 R3 方案 A)**:原顺序 `simplify → commit → 反思 → next_prompt` 有执行层 bug —— 反思候选在 §3 提出后,§4 next_prompt 紧跟 + Claude stop + terman 30s clear 窗口 → 用户回应时间 > 30s 概率高 → 反思落位窗口被 clear 吞掉 → "用户抽查 = 内核闸门"失效。新顺序**反思前置到 commit 之前**,反思 Ok 项的落位改动进入同一条 commit,证据链完整。

### 1. 代码审查:`/simplify`

对本轮新增 / 修改的代码做质量审查,修复发现的问题。

**例外**:
- 改动**纯文档 / 纯配置**可跳过并显式说明
- 代码**命运已定为消除**(同一轮或上一轮决策判定要被消除 / 替换) → 显式跳过并说明"属于 X 决策要消除的范围,审查无意义"
- **禁止**把跳过理由写成"时间不够" / "改动很小" / "对齐风格无益"(这些是绕过,不是合理跳过)

**simplify 采纳/拒绝记账(档位门槛)**:标准改 / 大改的 commit message 必须加一行,格式 `simplify 采纳: <项>; 拒绝: <项>(<≤20 字依据>)`,依据必须点**否决类目**(可读性 / scope 错位 / 反例具体命名),禁 "本轮限 X scope" / "与任务无关" 这种套话;**无 simplify 建议或全采纳 → 不写这行**(不凑"无")。微改 / 纯文档 / 纯配置豁免。目的:补位 `feedback_human_readable_code` 可读性对 reuse/quality/efficiency 的 veto 行权留痕 —— memory 跨 compact 可失、对话缓冲区跨轮丢,git log 是唯一持久可 grep 入口。

### 2. 流程反思(档位门槛)[反思前置 —— 方案 A]

基于本轮实际走过的流程,审视是否有规则 / gate / 文本需要升级。列 0-N 条候选(无候选**显式写"无"**),以紧凑列表交用户确认。

**反思层级颗粒度硬规则**(2026-04-24 R4 新增):反思候选**必须含至少 1 条结构性反思**(关于 PSM gate / VCM / 工具 / 角色边界 / 层级耦合 / 流程时序的根本机制问题)。**结构性 vs 细节 patch 判据**:"如果本轮没做这件事,下一轮 Claude 接到**任意任务**还会同样卡这一类问题吗?"答 yes → 结构性;答 no → 细节 patch,列入回复末尾的 "follow-up todo" section 不算反思候选。**纯细节 patch 列表**(全部"答 no")= 反思失败,本轮反思候选作废,Claude 必须重做。理由:细节是无穷的,反思方法论必须强制 anchor 到 meta-pattern,否则退化为 patch 表演(B.2 第 7 形态)。**触发事件**:2026-04-24 I015 §收尾反思 R4 — Claude 默认列了"MNK 加 1 行 / 立 1 issue / 改 5 行注释"3 条全细节 patch,被用户当场指出"反思应该从高维层面解决,而不是从细节里面解决,因为细节是无穷的"。

**ultrathink 预置反思 + Claude 自主反思并存规则**(2026-04-24 新增):用户 prompt 里显式预置"反思候选 X" / "ultrathink 反思 Y" 等主题时,预置候选**不吞掉** Claude 同轮主动反思义务 —— Claude 必须**独立于 prompt 预置**再列 0-N 条结构性候选,即使预置主题已涵盖本轮核心反思,也要扫"prompt 预置没覆盖的结构性盲点"(如 runtime bug 诊断方法论 / 工具误判修正 / 层级跨越识别 等)。两者并存的理由:反思机制的内核闸门属性靠 Claude 自主盲点扫描,不靠上轮 prompt 外供;若预置 = 唯一源,反思退化为"命题作文"失去主动性。**触发事件**:2026-04-24 D 文档死指针清零轮 — 用户 prompt 预置"反思候选 1 = 新增 D 文档治理 gate",Claude 同轮又自主发现 (a) 多因素 runtime bug 诊断应隔离变量、(b) ultrathink 预置反思的反身性风险,两条补位结构性候选。

**回应窗口 stop 规则**(方案 A 硬约束):
- Claude 输出反思候选后,本轮回复**必须在此处 stop**(不连续写 §3 commit / §4 next_prompt)
- Claude stop 后在对话主循环等用户回应,用户三态:
  - **Ok** → 同轮继续:落位改动(`principles.md` / 本文档 / D 文档 / `tools/` 新 linter / memory)→ §3 commit(落位改动入同一条 commit,证据链完整)→ §4 next_prompt
  - **No** → 本轮对话记录里点名"丢弃原因"防下轮重提 → 继续 §3 commit → §4 next_prompt
  - **待定(立项下轮独立 issue)** → 写 `docs/4-issues/IXXX-*.md`(按 §特定领域 §衍生 issue 归档 命名规范)→ 继续 §3 commit → §4 next_prompt。判据:候选 LOC 估算 > 50 **或** 需前置设计决策未完成 → 立项;同轮落位成本低 → 走 Ok 分支
- 用户在对话主循环超时未回应(Claude stop 后 terman 30s 窗口 clear) → 反思候选**丢弃**,不跨轮保留(方案 A 硬规则;若本 gate 多次事件发生,未来再加方案 B `.claude/reflection_queue.md` 跨轮兜底)
- 反思候选**无**时显式写"无" + 跳过 stop,直接连续进入 §3 commit

**档位门槛**:标准改 / 大改必做;微改豁免。

反思不是仪式 —— 是把"用户回合间抽查八股"从隐式习惯升为显式 gate,消除"八股自检元规则靠 Claude 主动提出才触发"的隐式依赖。不写反思段 → 下轮 Claude 不主动想起 → 八股讨论产出丢对话缓冲区 → 跨轮复用脆弱。

**反思落位后 token 预算 gate**:流程反思候选被用户裁决并落位(或 No 丢弃 / 待定立项下轮)后,检查当前上下文已用 token(粗估或 /cost):

- **< 10 万 tokens** → 本轮**继续直接执行**剩余任务(compact 前用户授权的推迟候选 / 简单 Edit / 连带 simplify 补正),**不** stop,不写 next_prompt 进 §4
- **10-15 万 tokens**(灰区) → 按剩余任务复杂度判:纯替换 / 微改继续,结构性 / 大改 stop 进 §4
- **> 15 万 tokens** → 立即停手走 §4 下一步提示词(必含 ultrathink 由下轮接管),剩余任务**禁止**在本轮压上下文硬推

**显式打印(强制)**:判断完成后**必须**在对话回复里、§4 下一步提示词**之前**单独打印两行供用户审阅:

```
token 使用量: ~N 万(粗估 / /cost)
推荐: 继续本轮 / 灰区(简单继续 / 结构 stop)/ 新循环
```

不打印 = 判断过程不透明,用户无从质疑估算偏差或档位误判。

目的:反思落位后 Claude 容易惯性 stop 进 §4,丢失"本轮尚可做 + 授权仍在"的执行窗口;上限 15 万防止本轮强推超长对话 → compact 风险 → 跨 compact 授权衔接漏洞(见本文档 §Compact 恢复 gate §跨 compact 用户授权范围收缩)。

### 3. 提交:commit

`git status` 有未提交改动 → commit(`/commit` 或手工),消息遵循 conventional commits。commit **必须**落在同一轮对话里,**不许跨轮补**。**§2 反思 Ok 项的落位改动必须进入同一条 commit**(不许拆成两个 commit —— 拆分 = 反思证据链断,commit log 失去"反思驱动本轮改动"的唯一 grep 入口)。

### 4. 下一步提示词(自闭环两步)

**(a) 最后一条回复**直接输出**下一步简短提示词**(1-3 句、单段、命令式、模仿用户原始风格)

**(b) 同时覆盖写入** `.claude/next_prompt.md`(terman `claude-next` preset 的**单次 payload**,见 `docs/terman-auto-next.md`)

preset 监测 PTY 空闲 30s + 光标在 prompt 处,自动 `/clear` + bracketed paste + 30s 观察窗口 + Enter 触发下一轮;两处内容**严格一致**,用户在 30s 窗口内 Ctrl+C / 键入字符可中断。Phase 进度仍只落在 D 文档,`.claude/next_prompt.md` **不**承载跨轮状态累积 / 进度摘要。

Claude 本轮**不执行**任何脚本或 `terman send` —— stop 后 preset 自动接管。

**覆盖写**不追加不累积 —— 它是单次 payload 不是日志;preset 读完会 `delete_file` 消费掉,下一轮 Claude 必须重新写。

**格式硬约束**:
- 1-3 句、单段、命令式
- **禁用** markdown 引用块 `> ...` 包装(复制粘贴时竖线跟进污染)
- **必含关键字 `ultrathink`**(由 `tools/next_prompt_ultrathink_linter.ss` 三检查机械校验:存在 / 非空 / 含 ultrathink;任一 FAIL → stdout 出现 `GATE BLOCKED` 即阻断 stop)

**Execute 型**(动词"改 X / 重写 X / 去掉 Y / 修复 Z / 实现 W")**必须**附**本轮已跑过**的 **RED 命令 + 输出**作为凭据,证明 X 尚未达成。RED 无效(已 GREEN / 命令不成立 / 代码已是目标形态) → **不许写 Execute 型**,改为:
- (a) 宣告「本轮已覆盖 X + 证据」终止本线路;或
- (b) 降级为 **Plan 型**「验证 / 巡检 X 现状,若发现 Y 再推进」,把诊断权交回下一轮

**Plan 型**(动词"验证 / 调研 / 巡检 / 对照")不要求 RED,但**不得**带"改 / 重写 / 去掉 / 修复 / 实现"等变更动词。

**例外**(不写 payload,停下等裁决):
- 用户明说"不 simplify" / "不 commit" / "不反思" / "不要下一步"
- 本轮出现未解决 blocker(bootstrap 失败 / 测试红 / reflection_linter GATE 阻断)
- `$TERMAN_NAME` 为空(非 terman session),preset 不跑(天然降级)

这是防漂移**跨轮传播的出口 gate** —— 与 §M §字段 1 D 文档 grep 对照构成两道闸:上一轮关闭出口,下一轮关闭入口。

---

## 特定领域 gate(按需触发)

### Bug 修复 Harness

修 bug 必须运行:

```bash
bin/ss run .harness/common/bug.ss detected <importance> <urgency>
# 读 stdout 输出的指令执行

# 修复后
bin/ss run .harness/common/bug.ss fixed <round> <certainty>
# 按输出决定下一步
```

**且**产出 `.bugfix` 证据文档通过 `tools/bugfix_linter.ss` 的 **6 gate**:

- G1 字段完整性 / G2 因果证明(重跑测试) / G3 root cause 质量(字段长度 + 同模式 = 0) / G4 结构性 delta(净新增条件分支) / G5 bootstrap 重验 / G6 全量测试重验

**全 PASS** 才允许 commit。机械指标基于不可变特征(exit code / bootstrap 字节比较 / 重新测量数值),**不依赖变量名 grep**(可改名规避)。

**自检 trigger**:想跳过 `.harness/common/bug.ss` / 直接 grep code 找 bug 凭直觉改的瞬间,必须停下问"这是 bug 吗?是 → 必走 harness 双阶段(detected → fixed)+ `.bugfix` 6 gate;否 → 显式写明非 bug 类别(refactor / 新功能 / 文档 / 测试补)"。把"想跳"念头当 trigger,而不是把"必须跑"当事后清单。

### 反射路径根因 gate

触碰反射路径(`bootstrap/gen/class.ss` / `gen_stmts.ss` `.fields/.methods/.annotations/.args` / `genForInUnrolled` / `classXxxAnnotation*` / `comptimeConsts __*` sidecar)必须在 commit 前跑 `bin/ss run tools/reflection_health_linter.ss`。

**判据**:
- **G1-G4 任一升高** → 走错方向,别 commit,回去想根因
- **G5 升高** = 正向进展(Meta 对象在被使用)
- **baseline 下调**只允许真 refactor 的语义迁移,**不允许累积扩容后自行更新 baseline**

**REGRESSION 分流**:触发 BLOCK 后按本轮性质分 A / B 路径:

**A. refactor 型(半径内抵消)**

reflection linter REGRESSION 被 gate BLOCK 时,**不允许**改动跟当前任务无关的代码(远距离)去榨 CC / M5 / AST 节点抵消。改动分类:

- **本地(反射路径内)** — 新增代码本身的简化(合并条件、去冗余 let)**合法**
- **半径内(同文件其他函数)** — 职能相近且本轮任务明显覆盖(如 `interpMapGetKeys` / `interpMapDelete` 在改 Map 扩容时一起削)**合法**,但 commit message 必须说明相关性
- **远距离(跨子族、无语义关联)** — **禁止**,除非有独立 justification 写进 commit message 且不提"为压 gate"

远距离改动一旦出现 → **立即停手**,回归 B 路径扩容申报。

**B. 形态升级型(扩容申报)**

**trigger**:涉及"反射路径形态升级"(容器类型 Array→Map / AST 字段扩 / Meta kind 变更)。

- **指标表列粒度**:**REGRESSION + AUTO-DRIFT + bump 项** 必须全列(M1-M7b + N1-N5 中任一超 baseline_value 的);**OK 项可省**(linter soft warn 日志对 AUTO-DRIFT 自动覆盖,OK 项无信息量)。实务 15 个标量指标平均 5-8 个需列,**不允许** 15 个全列(读者信息密度低)或只列 REGRESSION 漏 AUTO-DRIFT(后者虽不 bump 但 cur>bv 反映真实漂移面)
- 结构组任一 > 0 或累计组任一超 tol → **三选一**:
  - (a) 本地抵消(列具体削减点,限 A 路径半径规则)
  - (b) 升 baseline + D 文档 §扩容申报
  - (c) 拆 commit(除非用户明确拒绝分轮)
- D 文档 §扩容申报段**必含**:扩容理由(引用 §第一性需求)/ REGRESSION + AUTO-DRIFT + bump 项 delta 表 / 本地抵消路径 + 具体函数 / 新 baseline 预期值(=实测预估)/ VCM 实测 vs 预估对照槽

> 2026-04-24 I014 §路径 A 扩容段列全 14 指标含 10 项 AUTO-DRIFT/OK 噪声,读者提取 5 项真实 REGRESSION 要跳过一半信息;规则由"全 14 指标"放宽为"REGRESSION + AUTO-DRIFT + bump 项",精简信息密度。

规则 / baseline / 工具位置见 `docs/3-decisions/D097-reflection-root-cause-metrics.md`。

**自检 trigger**:想直接改 `bootstrap/gen/class.ss` / `gen_stmts.ss` `.fields/.methods/.annotations/.args` / `genForInUnrolled` / `classXxxAnnotation*` / `comptimeConsts __*` sidecar 等反射路径而**不跑** `tools/reflection_health_linter.ss` 时,停下问"本次改动会动到 14 指标(M1-M7b + N1-N5)的某项吗?如答 yes 或不确定 → 必跑 linter,REGRESSION 走 A/B 路径分流(A 半径内抵消 / B 形态升级扩容申报)"。

### Reset 双重 gate(行为规则)

**面对"是根儿上还是假装"质询时禁止**:

- 全盘否定前期工作 → 推荐 `git reset` / `git revert` / 推倒重来
- 用"承认全错"戏剧动作替代"定位具体节奏缺陷"细致诊断
- 把"必要地基工作"(修悬空引用让 bootstrap 能过)打成"假装"
- 把整个分支 / 整个 Phase 打上一致"假装"标签

**真正诊断区分三类**:

1. **必要地基**(修编译错误 / 补悬空符号) — 本身不配测试是合理的
2. **装修 / 实现功能** — 必须紧跟测试验证
3. **节奏缺陷** — 地基完成后没立刻接测试是缺陷,**但不等于地基工作本身是假装**

**提议 reset 前 bootstrap 双重验证**:

- 提议 `git reset --hard <target>` / 切换到历史 commit 作为"重新起点"前,**必须先 checkout 跑 `./build.sh bootstrap` GREEN**
- 目标点不 GREEN → 提议必须明写"目标点本身需要再修 N 错误",不允许隐瞒
- **禁止仅靠 `git log --oneline` + commit 主题判断干净起点**(commit 主题是作者自我声明,不是机器验证事实)

**自检 trigger**:想写 "reset 重做" / "推倒重来" / "全部回滚" / "整个 branch 都假装" 时,必须停下问:"我是不是在用戏剧性方案替代细致诊断?"

### Compact 恢复 gate

**trigger**:context compact 后 Claude 从 summary 恢复继续工作。summary 只描述**意图**,不是工作树状态的直接证据;跨会话状态(其他会话改动 / 手动操作 / 工具副产物)**不在 summary 覆盖范围内**。

**硬规则**:

- **Compact 后第一个工具调用**必须是 `git status --short` + `git log --oneline -5`,核对工作树实况
- summary 声称已完成但工作树仍有未提交改动 → 先 commit 清理,再继续
- summary 未提及的改动(其他会话产物 / 大范围删除 / untracked 测试副产物 / 系统文件) → **显式排除在本轮 commit 范围外**,按 §附录 A §commit_radius §前置约束 精准 `git add <file>`
- **禁止**仅凭 summary 就假定工作状态,下游 commit 按 summary 意图盲 stage 全量变更
- **PSM 九问填表锚点**:已在 §M 主规则通用化(2026-04-24 R1),本段不重复;Compact 恢复场景下此锚点的收益(频繁核对 → PSM 时机不滑向事后)天然继承自 §M 通用规则
- **跨 compact 用户授权范围收缩**:compact 前用户授权 N 候选,恢复后 Claude 审视后执行 M < N 条,未执行的 N-M 条**必须**写入 next_prompt 显式列 + 每条推迟原因,交下轮用户裁决;**禁止**隐式消化(靠自觉不提 = 与用户意图脱钩)

**自检 trigger**:看到"Continue the conversation from where it left off" / summary 块时,必须停下先 `git status`,**不许**直接按 summary 末尾建议的 next step 动手。

### 命名前缀族归位扫描

**trigger**:涉及"创建 `bootstrap/X/<prefix>_Y.ss`"类新文件任务。

```bash
filepref=$(basename <new_file> .ss | cut -d_ -f1-2)
find bootstrap -name "${filepref}*" -type f | awk -F/ '{OFS="/"; $NF=""; print}' | sort -u
```

- 输出 ≥ 1 个族目录 → 新建文件**归同目录**,除非 D 文档**显式写脱族理由**
- 输出 0 个 → 按 P10.1 自由决定
- 不做扫描 → Plan 路径决策漂,**任务拒绝**

**自检 trigger**:`Write` 一个 `bootstrap/X/<prefix>_Y.ss` 新文件之前,必须先跑上面的 find 族归位扫描,否则**任务拒绝**。看到 PSM 字段 5 缺 "命名前缀族扫描:`<filepref>` 命中族目录 = ..." 字串 → 立即回填扫描结果再开 Write。

### COMPTIME_EXPR 非标量返回扩展 gate

**trigger**:改动让 `comptime { ... return X }` 的 X 是 array / object / map / tuple / Map<K,V> / Set 等**非标量**类型(历史仅支持 int / double / string / bool / type 五类)。

**硬规则**:必须**同步扩 3 处**,缺一则 alloca i32 vs load ptr 必撞类型错(2026-04-24 I014 §路径 A Array<RouteMeta> 返回三处同步扩事件):

1. `bootstrap/gen/gen_types.ss` `inferType COMPTIME_EXPR`:加新 kind 分支,`comptimeExprType.set(ceKey, <kind>)` + `comptimeExprLiteral.set(ceKey, <tvId-or-representation>)`
2. `bootstrap/eval/eval_expr.ss` `COMPTIME_EXPR` 分支:对新 kind 返 `ctVal(payload)` 而非 runtime literal(runtime literal 只对 scalar 有意义)
3. `bootstrap/gen/gen_decls.ss` `genVarDecl` `COMPTIME_EXPR` 分支:CONST 绑定 ctVars 跳 runtime alloca(非 CONST 形态暂不支持,let 可变 ctArray 需另扩 ctInvalidated 链路)

**配套 test**:`tests/phase5/d<N>_comptime_<kind>_return.ss` 最小验证(let acc = Array<X> / return acc 后消费走 for-in unroll + member access + CONST 绑定全链)。

**自检 trigger**:准备在 `inferType` 加 `comptimeExprType.set(..., "int")` fallback 回落代码时,停下问"是否有新 kind 没覆盖?";若 comptime 块 return 表达式类型不在 int/double/string/bool/type 五类白名单,必须扩三处,不许让 fallback 静默 miscompile。

### untracked test fail 诊断流程

**trigger**:`bin/ss test tests/` 实测 fail 数超过 Phase 基线记录(如 D123 Phase 1 "224 passed + 4 pre-existing fail"),但怀疑是**环境 drift**(untracked test dir / `.harness/` 丢失 / 上一会话残留测试)而非本轮代码 regression。

**分流流程**:

1. 先看 `git status --short | grep '??'` + `git ls-files --others --exclude-standard tests/` 列 untracked test 目录
2. 怀疑 pre-existing →`git stash push bootstrap/eval/<files> bootstrap/gen/<files> bin/ss` 把本轮改动 stash(保留 docs / lib / example 不 stash)
3. `./build.sh bootstrap` 重 build 回到改动前 bin/ss 状态
4. `bin/ss build <疑 test> -o /tmp/t && /tmp/t` 单独验证 — 还 fail → **pre-existing**,不是本轮引入
5. `git stash pop` + `./build.sh bootstrap` 恢复
6. VCM §5 (c) 写"revert 全部本轮 X 个编译器文件后再 bootstrap rebuild <test> 仍 <症状>,证明 pre-existing"

**反 case**:
- `bin/ss test` 并发 race(多 test binary 抢 /tmp 资源)可能导致 flaky fail;单独跑 `/tmp/<test-bin>` 与并发版行为不一致 → 记入 VCM §5 (c) + 立项 docs/4-issues/ 追并发 race 诊断(不阻当前任务)
- 不许用"手动跑 `/tmp/<bin>` exit=0"单个证据 absolve,`bin/ss test` 并发是 authoritative 判据

**自检 trigger**:看到 "5 failed 比 baseline 4 多 1" 类数字差时,**立即 stash+revert+rebuild 验证**,不依赖"这个 test 看起来是 untracked" 直觉(2026-04-24 I014 §路径 A harness_bug / harness_task 误判事件)。

### 衍生 issue 归档(feedback_interactive_one_doc 的执行层配套)

**trigger**:`/loop` 主任务执行中发现 root cause 与当前 issue 不同的新问题。

**二分法**(阻挡性 → 处理方式):

| 状态 | 判据 | 处理 |
|---|---|---|
| **阻挡** | 不修 → 本轮主任务 BLOCK(测试红 / bootstrap 失败 / reflection GATE BLOCK / N 六验过不去) | **本轮修**,不许推迟。理由附在 commit message 或 VCM §5 (c) |
| **非阻挡** | 独立 root cause + 不 BLOCK 本轮主任务 VCM 通过 | **立项修**:写 `docs/4-issues/IXXX-*.md`(用下节命名规范),不许只对话提 / 只 commit msg 提 / 只 memory 记 |

**硬规则**:
- **禁止第三态**("顺手修无关 bug" / "打包修 2 个标准改以上 issue")—— 要么阻挡本轮必修,要么独立立项,不许混入主任务 commit
- 若本轮修了阻挡性衍生问题,**commit 拆 2 条**(主 issue 一条 + blocker 修复一条),commit message 显式说明 blocker 关联
- 非阻挡问题**必写 issue 文件**,对话 / commit msg 提到 "IXXX" 而目录不存在 → `derived_issue_linter` BLOCK
- **多 issue 串跑白名单**:多个**全微改**档位 issue 可一轮合并(合并条件 + commit 拆法见 §改动分层 §判定细则 §多 issue 串跑判定),本节"禁第三态"规则不阻此场景

**命名规范**:

| 场景 | 编号规则 | 举例 |
|---|---|---|
| **同 scope 子扩展** | 父 issue + 字母后缀 | I00X → I00Xa(细拆)/ I00Xb(同路径增强) |
| **独立 root cause** | 取当前 top IXXX +1 | 若最高是 I009,新 issue 为 I010 / I011 / ... |
| **跨 D 文档挂载** | 文件名前缀保持 IXXX,父决策字段指向所属 D | `I0XX-*.md` 父决策可以指向任意 D 文档 |

**P4 机械校验**(`tools/derived_issue_linter.ss`,§After Done §2 commit 前跑):

- 扫 `git log --grep='I0' HEAD~1..` / `.claude/next_prompt.md` / 当前 `git diff` 里的 `IXXX` / "后续 issue" / "下轮处理" / "衍生问题" pattern
- 对照 `docs/4-issues/` 文件存在性(`ls docs/4-issues/IXXX-*.md`)
- 发现文本引用但目录缺文件 → stdout `GATE BLOCKED: derived issue IXXX not archived`
- 有 GATE BLOCKED → 不许 commit / 不许 stop,回去补 issue 文件

**自检 trigger**:
- 想写"这个 bug 我先绕过,后续再处理"时 → 必须先答"阻挡 or 非阻挡?",再按上表分流
- 对话里出现 "IXXX 待后续" / "下轮修" / "先搁置" → 立即开 issue 文件,不许靠对话记忆跨轮

### memory 治理 gate

**trigger**:任何**删除 / 合并 / 移动**`~/.claude/projects/.../memory/feedback_*.md` 类操作 + MEMORY.md 索引行任何改动。

**硬规则**:
- 删 / 合并 / deprecate 一条 memory 前,**必须**先按 §M §字段 9 "删除 / 合并 / deprecate 类操作专属 gate" 跑 grep 验证目标已落实(file:line 锚 + 类型语义不丢失);未落实 → 先迁移再删
- 改完 MEMORY.md 索引或 memory 文件**必须**跑 `bin/ss run tools/memory_index_linter.ss`(F1 索引漂移 BLOCK / F2 孤立文件 soft warn);**有 GATE BLOCKED → 不许 commit**
- linter 默认目标 `~/.claude/projects/-root-code-simplescript-dev-simple-script/memory/`,跨项目可传第 1 参数覆盖
- linter 未机械化的元规则判定层(N/Y\*/Y)仍由人工 + 元规则原文判,linter 只校验"指针有没有指向真实文件",不判"该不该有这条 memory"

**自检 trigger**:看到 "memory 已 stale" / "这个 feedback 不需要了" / "合并到 D 文档" / "批量 deprecate memory" 类念头时,停下问"目标位置 grep 已落实?跑过 memory_index_linter?"。把"想删"念头当 trigger,不是把"已删"当事后清单。

### D 文档治理 gate

**trigger**:任何**删除 / 合并 / 重命名** `docs/3-decisions/D*.md` 类操作 + 源码注释内 `D\d{3}\s*§` 引用任何改动 / 移除。

**硬规则**:
- 删 / 合并 / deprecate 一个 D 文档前,**必须**先按 §M §字段 9 "删除 / 合并 / deprecate 类操作专属 gate" 跑 grep(`grep -rn "DNNN §" bootstrap/ tools/ CLAUDE.md docs/3-MNK.md`)验证源码注释里该 D 号的每一处 § 引用都有迁移目标(活 D § 段 / MNK §XX / memory feedback_*);未迁移 → 先迁移再删
- 改完 `docs/3-decisions/` 或 bootstrap / tools / CLAUDE.md / docs/3-MNK.md 里任一 D 引用**必须**跑 `bin/ss run tools/d_doc_index_linter.ss`(F1 死指针 BLOCK / F2 孤立 D 文档 soft warn);**有 GATE BLOCKED → 不许 commit**
- linter 默认 project root = `pwd`,跨目录可传第 1 参数覆盖
- linter 扫描 scope 刻意**不含** `docs/3-decisions/` 自身:D 文档之间互相引用是历史演进痕迹(合法);scope 是"源码 / 流程文档读到 D 号 → 期望 ls 能命中实文件"这条路径
- linter pattern 刻意限 `§` 后缀:`DNNN#` 形态(`linter_baseline.txt` bump trail)是 commit footer 式溯源戳,不属于规则引用
- F2 孤立 D 文档 soft warn 不阻 commit:纯 Plan/业务 D 文档未必需要在源码注释里引,linter 仅提示人工审视

**自检 trigger**:看到 "D 文档已 stale" / "这个 D 可以删了" / "合并到 MNK" / "批量 deprecate D" 类念头时,停下问"源码注释里该 D § 引用 grep 迁移已落实?跑过 d_doc_index_linter?"。把"想删"念头当 trigger,不是把"已删"当事后清单。对称 memory 治理 gate,两层形成 "ls → 源码注释" 双轨消歧。

---

## Fractal 承载(L0-L4 递归)

九问六验在所有层级递归适用。每层向上引用,**不重复内容**。

| 层 | 粒度 | 承载 | 形式 |
|---|---|---|---|
| **L0 项目** | 永恒 | `docs/1-axioms.md` + `docs/2-principles.md` + 本文档 | 完整文档 |
| **L1 路线** | 月级 | `docs/3-decisions/Dxxx.md`(如 D088) | D 文档顶部 1 屏 |
| **L2 决策** | 周级 | `docs/3-decisions/Dxxx.md`(如 D089) | D 文档顶部 1 屏,引用 L1 |
| **L3 轮任务** | 单轮对话 | 对话首条回复(**不写文件**) | 紧凑九问表格,引用 L2 |
| **L4 子步骤** | < 30 min | TaskCreate description | 一行 inline |

**禁止**:

- L3 / L4 跨层跳过 L1 / L2 直接引用 L0
- D 文档脚注里的「独立后续 / 候选 / 列为 D0NN 范围」被当作路线指引(**永远不是**)
- harness 工具(TaskCreate / Plan)在九问填齐之前调用

---

## 反 over-engineer 警告

本文档是**机制 hook**,不是模板堆。任何「再加一个文档 / 层级 / 字段」的冲动 → 先问「它能让 M / N / K 更短吗?」,答否就不加。

**成功判据**:**下一轮 Claude 接到任意任务能在 5 分钟内填齐九问**,不是「流程文档完整度」。

---

# 附录 A: rule 库详表

## 初始 M=2(K=6)

| rule | N | linter 实装 | 归属 | 红线问 |
|---|---|---|---|---|
| **commit_radius** | 3 | `tools/commit_radius_linter.ss`(`--cached` 子族分布 ≥ 3 soft warn) | 本文档 §K | 无 |
| **commit_footer** | 3 | `tools/commit_footer_bagu_linter.ss`("去掉少什么:" 字串存在校验) | 本文档 §K | **Q1**:每项过"去掉少什么"元规则均答"有缺";任一"不会少"未处理 → 直接 FAIL 不进入下轮 |

## 子问卷

### commit_radius(N=3)

**前置约束**:答 Q1-Q3 前,必须先 `git status --short` 核对本轮范围。不属于本任务的 unstaged / untracked 改动(其他会话产物 / 系统副产物 / 大范围删除) **显式排除在本 commit 外** —— 精准 `git add <file1> <file2>`,**禁用** `git add -A / .` / `git commit -a`。排除清单列入答 Q1 的头部(格式:"排除:<file1>, <file2>, ..."),未列 = 视为隐式包含,Q1 FAIL。

- **Q1**:本 commit 跨几个子族?列 `familyOf(path) = 前 2 段` 分布
- **Q2**:跨族分类(同任务扩展 / 元流程改进 / 远距离榨指标) + 理由
- **Q3**:缩到 1-2 子族能完成任务吗?给耦合证据(no + 证据 PASS / yes FAIL 要求拆 commit)

### commit_footer(N=3)

- **Q1(红线)**:每项改动过"去掉它核心产出会少什么"元规则均答"有缺"?任一"不会少"未 revert / commit message 未点名 → **直接 FAIL 不进入下轮**
- **Q2**:commit message 含 "去掉少什么:" 行数 ≥ 改动文件数
- **Q3**:每条答案含具体 file:function / 概念引用(非"无" / "不少"空话)

## linter 角色

**机械材料提供者**:

- `commit_radius` 输出子族统计 = Q1 原始材料,Q2/Q3 语义解释由**被查者**给
- `commit_footer` 输出"去掉少什么:"字串存在 = Q2 机械判定,Q1/Q3 由**被查者**给

协议层不改 linter 代码。

## 扩展

- **M 扩展**(新 rule):追加一行 `rule / N / linter 实装 / 归属 / 红线问`,M 自动升
- **N 扩展**(单 rule 加问):只改子问卷,N 自动升
- **接入 pre-commit hook**:当前**人工执行**(被查者在 VCM §5 (c) 手动跑)。自动化升级策略(`PreToolUse` hook / 结构化问答格式 / 收敛记录归档)留下轮 D 文档讨论

---

# 附录 B: 八股形态索引

## B.1 已机械化层(8 个 linter)

| 层 | 工具 | 判据 | 抑制的八股形态 |
|---|---|---|---|
| 反射扩容 | `reflection_health_linter.ss` | 14 指标 vs `budget_max`(scope-aware) | 远距离榨指标(间接:超 tol 逼申报) |
| 下轮 payload | `next_prompt_ultrathink_linter.ss` | 文件存在 + 非空 + 含 ultrathink | 下轮退化成浅 reasoning |
| bug 修复 | `bugfix_linter.ss` | 证据文档 + 6 gate | 修 bug 无诊断靠感觉 |
| 双入口 | `dual_track_linter.ss` | scope 特征 | 双轨伪装成"兼容架构" |
| commit 差半径 | `commit_radius_linter.ss` | 子族分布 ≥ 3 | 远距离榨指标(直接,soft warn) |
| commit footer | `commit_footer_bagu_linter.ss` | "去掉少什么:" 字串存在 | VCM 复盘凑仪式(格式强制) |
| 衍生 issue 归档 | `derived_issue_linter.ss` | IXXX 引用 vs `docs/4-issues/` 存在 | 非阻挡衍生问题只对话提失踪 |
| memory 索引一致性 | `memory_index_linter.ss` | `~/.claude/.../memory/MEMORY.md` 索引 vs `feedback_*.md` 文件双向校验(F1 索引漂移 BLOCK / F2 孤立文件 soft warn) | 跨 session memory 索引漂移(指针指向不存在的文件)+ 孤立 memory 文件不被加载;**触发时机**:删/合并 memory 后必跑 + commit 前(配 §特定领域 §memory 治理 gate) |
| D 文档引用一致性 | `d_doc_index_linter.ss` | 4 路径(bootstrap/tools/CLAUDE.md/docs/3-MNK.md)`D\d{3}\s*§` 引用 vs `docs/3-decisions/D\d{3}*.md` 实存双向校验(F1 死指针 BLOCK / F2 孤立 D 文档 soft warn) | 跨轮 D 文档指针漂移(源码注释指向已删/合并的 D 文档)+ 孤立 D 文档人工审视;**触发时机**:删/合并/重命名 D 文档后必跑 + commit 前(配 §特定领域 §D 文档治理 gate) |

## B.2 未机械化层(6 种形态)

1. **远距离榨指标** —— 改无关代码压 CC/M5(commit_radius soft 覆盖,未根解)
2. **凑 VCM 仪式** —— 每项打 ✓ 没真对照(commit_footer 格式外化,未根解)
3. **grep 摆样子** —— 跑命令只为满足 PSM 字段 1 槽(未机械化:意图判断)
4. **编造 D 文档段** —— 为让引用有物现起草(未机械化:意图判断)
5. **文档膨胀** —— 500 字解释其实一句话够(未机械化:价值判断)
6. **checklist 表演** —— TaskCreate 微步骤凑进度条(未机械化:意图判断)
7. **细节 patch 反思** —— §After Done §2 反思候选全是 "MNK 加 1 行 / 立 1 issue / 改 N 行注释" 等局部修补,无 meta-pattern 反思(2026-04-24 R4 加硬规则;判据见 §After Done §2 反思层级颗粒度硬规则)
8. **字符级压缩绕过 gate 阈值** —— F1 / 反射等指标 gate 阈值临近时,用压缩注释 / 合并样板 / 删空行 / 把 overload 族压成大 dispatcher / 多 let 合并单行等**字符级手段**挤进阈值,信号被压没但复杂度仍在(2026-04-20 D113 interp_core.ss 头注释 4→2 行未增功能事件;memory feedback_600_split_not_inline 锚同步;判据:任何"行数即将超 gate 但内容未职责变化"的简化建议 → 改提拆文件 / 拆函数,不改字符密度)

**原理限制**:八股 = "形式上满足规则,对任务核心产出零贡献",判据是**反身性**(回看自己刚写的)+ **语义**(核心产出定义依赖上下文)。linter 查**可观测特征**(指标数、关键字、路径、字串存在),看不见**意图**。同一 for-in→while 改动 D121 场景是八股、独立 refactor 场景合法,linter 无法区分。

## B.3 元悖论:流程本身会八股化

- 九问 PSM 填齐 ≠ 想清楚
- 六验 VCM 逐项 ✓ ≠ 真对照
- 收尾 gate N 步走完 ≠ 真产出
- **流程反思步骤若退化为"每轮答'无'" ≠ 真反思**

档位自报(微改 / 标准改 / 大改)是对这层的部分反制 —— 档位错报 + 实际超档 → 收工 gate 回写补齐暴露漂移。但档位判定本身也可被压字符绕过。

**终极闸门双支柱**(详见 §核心原则 (2)):覆盖形态的机械 linter + 覆盖内核的用户抽查 / 流程反思 —— 缺一不可。

---

# 附录 C: 历史事件索引

| 事件 | 形态 | 诱因 gate | 消除路径 |
|---|---|---|---|
| 2026-04-14 D091 + dispatch 重排漂移 | 不过 gate 就动手 | harness 强化结构化执行偏见 | PFV 十问 / 六验 gate |
| 2026-04-15 D092 branch 戏剧性 reset | 用整体否定替代细致诊断 | 无 reset 双重验证 | §特定领域 §Reset 双重 gate |
| 2026-04-15 @derive 漂移 | D 文档应然被当实然 | PSM 字段 1 无 grep 对照 + 收尾无 RED | §字段 1 grep 对照 + §收尾 Execute 型 RED 凭据 |
| 2026-04-20 D113 codegen.ss 492 行 R4 宣告 | 行数达成 ≠ 结构清晰 | F1 硬阻无结构判据 | P10.1 拆分判据升级 |
| 2026-04-20 D116 gen_rt_cache.ss 漏归 rt/ 子族 | Plan 路径决策漂 | PSM 字段 5 未扫命名前缀族 | §特定领域 §命名前缀族归位扫描 |
| 2026-04-21 D121 R1-A Execute 2 newTvArray 远距离榨指标 | 远距离 | 反射 14 指标粗 gate | §反射路径根因 gate scope-aware + §K commit_radius |
| D124 Execute 5 次 bump 串跑 | 仪式 O(N) | bump 单指标粒度 | §反射路径根因 gate B 路径 bump-group |
| 10e2c8b rowMap "bv:bm" + tuple 裸露 | 可读性失真 | simplify 3 维度缺 readability | §After Done §1 simplify 采纳/拒绝记账段显式 veto 引用 `feedback_human_readable_code` (commit message 留痕)+ memory 同步 |
| F1 600 字符级塞字符 | 压缩 / 合并 / 删空行 | F1 硬阻无 soft warn | §B.2 形态 8 "字符级压缩绕过 gate 阈值" + §M §字段 3 拆分类 RED grep 职责类别 ≥ 3 + memory `feedback_600_split_not_inline` 锚同步 |
| 简单改也十问 PSM | 仪式不分层 | PFV 粗粒度强制 | §改动分层 三档门槛 |
| 2026-04-22 VCM (d) 沉积复盘靠自觉 | 八股沉积 | §VCM 无 commit footer 强制 | §K commit_footer |
| 2026-04-22 八股讨论结论留对话缓冲区 | 跨轮丢失 | 无流程反思 gate | §收尾 gate 第 3 步流程反思 |
| 2026-04-22 流程层规则分散 3 处 | 跨轮 Claude 读不全 | 无单一事实源 | **本文档归档(docs/3-MNK.md)** |
| 2026-04-22 I003 收尾 3 衍生问题只对话提 | 非阻挡问题失踪 | 无 issue 归档 gate | §特定领域 §衍生 issue 归档 + `tools/derived_issue_linter.ss` |
| 2026-04-22 VCM 缺独立根因验 | 表面伪装根 | "表面 vs 根"只作 §5 (c) 子项被主勾覆盖 | §N VCM §6 根因独立大验 + 五验→六验 |
| 2026-04-22 VCM §6 RED 跨表假命中 | 表行 RED 裸 grep | §M §字段 3 无表行域内唯一约束 | §M §字段 3 追加表唯一锚约束 |
| 2026-04-22 CLAUDE.md 五验外链漏扫 | SSoT 术语改后外链分裂 | §M §字段 5 无术语外链扫描义务 | §M §字段 5 追加 SSoT 术语扩展扫描 |
| 2026-04-24 反思候选跨 clear 丢失 | §After Done 顺序 commit→反思→next_prompt,反思确认窗口被 30s terman clear 吞掉;跨轮断链 → "用户抽查 = 内核闸门"失效 | §核心原则 (2) 内核闸门与执行层时机脱钩;§3 Ok/No 二分未覆盖"待定立项下轮"三态;§M 锚点"第一次工具调用之前"与 §字段 1 "grep 对照"前置义务字面矛盾 | §After Done 顺序重排为 simplify→反思前置→commit→next_prompt(R3 方案 A,反思候选 stop 等用户回应)+ §After Done §3 Ok/No 扩三态含"待定立项下轮"(R2)+ §M PSM 锚点通用化至"第一次修改性 tool call"(R1)|
| 2026-04-24 D 文档死指针跨轮漂移 | 源码 / 流程文档注释引用 `D\d{3} §` 指向已删/合并的 D 文档,跨轮 Claude 读源码找不到决策背景 hallucinate | `§特定领域 §memory 治理 gate` 已建立 MEMORY.md 层双轨消歧但 D 文档层无对称 gate;A7 follow-up `reflection_health_linter.ss:55,75` D102 注释 stale 属同类漂移 | §特定领域 §D 文档治理 gate + `tools/d_doc_index_linter.ss`(F1 死指针 BLOCK / F2 孤立 D 文档 soft warn);首次实战 10 死 D 号全修(D102/D108/D109/D110/D111/D117/D118/D124/D125/D126 → D097 / D098 / D120 / MNK §XX / feedback_f1_gate_semantic)|

---

# 参考

- `docs/1-axioms.md`(项目公理)
- `docs/2-principles.md`(原则,§PFV 流程 指针指向本文档)
- `docs/3-decisions/D088-*.md`(Zig 路线主 D 文档)
- `docs/3-decisions/D097-reflection-root-cause-metrics.md`(反射根因指标体系 + baseline 2 列制 + AUTO-DRIFT + bump-group 规则)
- `docs/terman-auto-next.md`(下轮提示词自动注入机制)
- `CLAUDE.md` §项目技术规则(交互式单文档 / MNK 流程 / 根因优先)
