# MNK: 解决问题流程闸门(单一事实源)

> 本文档是 SimpleScript 项目八股流程层闸门的**单一事实源**。PSM 九问、VCM 五验、改动分层、收尾 gate、八股自检、rule 问答收敛循环,以及所有前后文流程反射规则,全部收敛在这里。
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
| **标准改** | LOC delta 6-100 **或** 2-5 文件 | 字段 1-5 必填(6-10 可省) | 五验全 | 必做 | 全四步 |
| **大改** | LOC delta > 100 **或** > 5 文件 **或** 新增 D 文档 | 九问全 | 五验全 | 必做 | 全四步 + **独立 commit 禁打包** |

**判定细则**:

- 多维度叠加**取最严档**(LOC 120 + 1 文件 → 大改;LOC 3 + 3 文件 → 标准改)
- **函数签名变**(入参 / 返回类型 / 名改)一律升档至 ≥ 标准改(即使 LOC ≤ 5)
- **新增 D 文档**(即便仅 `[ ] Planned` 骨架)一律大改
- 档位自报错档 → After Code 发现实际超自报档 → 回写档位 + 补齐缺省 gate,**不许**宣告完成
- 纯文档 / 纯配置改动仍按档位判;simplify 可显式跳过

---

## M — Before Code: 写代码前的 M 个问题(开工 gate)

**强制**:接到任意任务(含用户明确指定的),**第一次工具调用之前**必须用纯文字把九问 PSM 表格写在回复正文里。

### 九问 PSM (Problem Statement Module)

| # | 字段 | 问什么 | 约束 |
|---|---|---|---|
| 1 | 总体 | 服务于哪个上层目标? | **必须先引 D 文档 §第一性需求 段落**,再接子表(禁跳子表);引用的**每一条** D 文档段落**必须同时附** grep / test / ls 命令证明 `[已达成 / 未达成 / 部分达成]`;不跑对照 → 任务拒绝;对照结果与 D 文档描述不一致(语态矛盾 / 标注过时 / 代码已移动) → 先回写 D 文档状态标注(P19 `[x] Done at <file:line>`)再开工。防漂移**跨轮传播的入口 gate**(与 §收尾 Execute 型 RED 凭据构成两道闸) |
| 2 | 第一性需求 | 真正根本痛点(不是症状)?"为什么"**至少 2 层**,末层必须断言可观测否定证据("不做 → 出现 X 现象") | Why 链 < 2 层 → 字段不算填齐,回去补 |
| 3 | 核心目标 | 完成后可观测的具体能力变化;**必须含一条 RED 命令**(形如 `bin/ss run <file> 2>&1 \| grep <pattern>`),证明现状未达成 | **第一个工具调用必须是这条命令**;已 GREEN → 任务不成立,停下报告。**文件拆分类任务**的 RED **不许**只用 `wc -l ≤ 600`,必须两步:(a) `grep '^(function|let|const)\s+\w+' <file>` 列 top-level 声明;(b) 按职责归类,**≥ 3 类 → RED 成立**;仅 wc -l → PSM 作废重填(P10.1 配套) |
| 4 | 规则 | 本任务硬约束(引用 CLAUDE.md / 本文档 / D088 等具体段落) | |
| 5 | 界定 | 做什么 + **不做什么**,两清单都填 | 场景触发型扩展义务见 §特定领域 gate(命名前缀族扫描 / 反射路径扩容判定) |
| 6 | 步骤 | 可执行序列,> 30 min 步骤拆 L4 子表(见 §Fractal) | |
| 7 | 对照实验 | **不做这件事,§第一性需求 会被卡吗?** | 必答 yes/no + 一句证据;no → 本轮任务**降级为 backlog 不做**(除非用户明说偏离授权) |
| 8 | Plan vs Execute | 本轮产出形态:**Execute**(代码改动)/ **Plan**(方向、清单、调研、巡检) | Plan 型 VCM ④ 边界 替换为「替代方案对比 + 隐藏假设挑战」 |
| 9 | 表面 vs 根 | 本任务**和每个产出项**:根解决 / 表面解决? | **根** → 一句话给出消除的双轨制 / 架构根因;**表面** → 必须同时写「本轮接受表面的成本理由」+「下一轮如何升级到根」;多产出项任务**对每一项**单独标记 |

### 八股自检(元规则,贯穿 Before / During / After)

任意即将编辑代码 / 文档 / 测试之前,**每次**先过一遍:

**"去掉这个改动,任务的核心产出会少什么?"**

- 答"不会少任何东西" → **停手,这是八股,禁止落盘**
- 答"XYZ 功能 / 验证 / 说明缺一块" → 不是八股,继续

**典型形态**(已识别 6 种,详见 §附录 B):远距离榨指标 / 凑 VCM 仪式 / grep 摆样子 / 编造 D 文档段 / 文档膨胀 / checklist 表演

**不通过时回路**:
- 扩容超 tol → 走 §字段 5 (b) 反射扩容判定(申报 + 升 baseline),不绕道
- 规则假命中 → 质疑规则**向用户报告**,不是绕规则
- 其他 → 停手想清楚,不要用八股填补

### 唯一例外

用户明确说「我知道这不在 Zig 路线上,但本轮就要做 X」→ 接受,回复里显式标记「⚠ 偏离 Zig 路线,用户授权」。

---

## N — After Code: 写代码后的 N 个问题(收工 gate)

**强制**:任务完成宣告之前必须用五验 VCM 表格逐项打勾,**每项贴证据**(命令输出 / 代码片段 / IR / 行为日志)。

### 五验 VCM (Verification Cross-check Module)

| # | 验证 | 内容 | 防造假属性 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` 固定点 + `bin/ss test tests/` 全绿 | 客观自动 |
| 2 | 行为 | 写一段 demo 新能力的最小代码,前 ≠ 后(不得引用既有测试) | 防空改 |
| 3 | 反向 | 删除新实现 → 必须看到失败 | 强制证明因果 |
| 4 | 边界 | 极限 / 异常 / 空 / 类型边界输入(Plan 型替换为「替代方案对比 + 隐藏假设挑战」) | 防 happy path bias |
| 5 | 路线 | (a) 对照 D088 §正模式 / §反模式 / §验证标准 §核心验证 逐条打勾; (b) **第一性需求距离**:本轮产出和 D088 §第一性需求 实现路径间距(用 phase 衡量),≥ 2 phase → 警告"可能绕道",必须论证"为何先做 phase X"; (c) **表面 vs 根复检**:对照 PSM 字段 9 标记,确认没把表面伪装成根; (d) **K 收敛 GREEN**(见 §K 章) | 防离开主线 + 防八股跨轮沉积 |

**硬规则**:
- 任一未通过 → 任务未完成,**禁止说「完成 / 收工 / done」**
- 五验**不能 self-attest**(不能用同一证据填两项)
- 证据必须能被**独立第三方复跑**

**§验 1 豁免条款**:本轮改动**纯文档 / 纯配置**(无 `bootstrap/` / `lib/` / `tools/` 代码路径变动)可显式豁免 bootstrap + tests,声明"doc-only, 无代码路径变动"即可;豁免理由**必须在 VCM §5 (d) 答问里自证**(grep diff 证明 `bootstrap/` 无改动),不许隐式跳。Execute 型代码改动无此豁免。

**扩容申报类任务**叠加"预估 vs 实测"对账,累计组任一指标预估偏差 > 50% → 写入 D 文档 §扩容申报 §预估失准段,下轮 PSM 开工前必读(对账步作为 commit_radius Q2 "跨族 justified 与否"证据之一)。

---

## K — After Lint: 跑 lint 后的 K 个问题(rule 问答收敛循环)

> **本章 K 槽当前绑 M-linter-K-M 循环**,后续用户手改。

### M-linter-K-M 问答收敛循环(当前 M=2,K=6)

本轮**所有**改动进入收敛循环:M 个 rule linter 各提 N 问 → 单轮问题总数 **K = ΣN** → 被查者逐条作答 → M 个 rule linter 独立读答案重判 → 任一 rule 仍有新问题 → 再轮;所有 rule 0 新问题 → **收敛 GREEN**。

**收敛判据**:
- (i) **≤ 3 轮收敛**:PASS 入 VCM 下一验
- (ii) **> 3 轮未收敛** / **累计 ≥ 2 条"空话"答案**(单字 / 与改动无关 pattern / 重复上轮答):FAIL,任务未完成,回 PSM 重构
- (iii) **红线问必过**:见各 rule 红线问栏

### rule 库(初始 M=2)

详见 §附录 A 子问卷与扩展规则。

---

## Continue Code: 循环 NK 反复

写代码 → **N 五验** → **K 收敛** → 不过关 → **改代码** → 再 N → 再 K → ……

直到当前问题的 N 和 K **全 pass**,才能进入 After Done。

---

## After Done: 收尾 gate 四步必做

VCM 通过 ≠ 回合结束。宣告「完成」到实际 stop 之间还有**四步必做**动作,按顺序执行,缺一条不许 stop。

### 1. 代码审查:`/simplify`

对本轮新增 / 修改的代码做质量审查,修复发现的问题。

**例外**:
- 改动**纯文档 / 纯配置**可跳过并显式说明
- 代码**命运已定为消除**(同一轮或上一轮决策判定要被消除 / 替换) → 显式跳过并说明"属于 X 决策要消除的范围,审查无意义"
- **禁止**把跳过理由写成"时间不够" / "改动很小" / "对齐风格无益"(这些是绕过,不是合理跳过)

### 2. 提交:commit

`git status` 有未提交改动 → commit(`/commit` 或手工),消息遵循 conventional commits。commit **必须**落在同一轮对话里,**不许跨轮补**。

### 3. 流程反思(档位门槛)

基于本轮实际走过的流程,审视是否有规则 / gate / 文本需要升级。列 0-N 条候选(无候选**显式写"无"**),以紧凑列表交用户确认。

- 用户 **Ok** → 落位(`principles.md` / 本文档 / D 文档 / `tools/` 新 linter)
- 用户 **No** → 本轮对话记录里点名"丢弃原因"防下轮重提

**档位门槛**:标准改 / 大改必做;微改豁免。

反思不是仪式 —— 是把"用户回合间抽查八股"从隐式习惯升为显式 gate,消除"八股自检元规则靠 Claude 主动提出才触发"的隐式依赖。不写反思段 → 下轮 Claude 不主动想起 → 八股讨论产出丢对话缓冲区 → 跨轮复用脆弱。

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

### 反射路径根因 gate

触碰反射路径(`bootstrap/gen/class.ss` / `gen_stmts.ss` `.fields/.methods/.annotations/.args` / `genForInUnrolled` / `classXxxAnnotation*` / `comptimeConsts __*` sidecar)必须在 commit 前跑 `bin/ss run tools/reflection_health_linter.ss`。

**判据**:
- **G1-G4 任一升高** → 走错方向,别 commit,回去想根因
- **G5 升高** = 正向进展(Meta 对象在被使用)
- **baseline 下调**只允许真 refactor 的语义迁移,**不允许累积扩容后自行更新 baseline**

**REGRESSION 时**:
- **refactor 型** → 本地抵消(半径内),**禁止远距离榨指标**
- **形态升级型扩容**(Array→Map / 新 Meta kind / AST 字段扩) → 走 §M §字段 5 (b) 反射扩容判定

规则 / baseline / 工具位置见 `docs/3-decisions/D097-reflection-root-cause-metrics.md`。

### 远距离 vs 半径内改动分类

反射 linter REGRESSION 被 gate BLOCK 时,**不允许**改动跟当前任务无关的代码(远距离)去榨 CC / M5 / AST 节点抵消。

**改动分类**:

- **本地(反射路径内)** — 新增代码本身的简化(合并条件、去冗余 let)**合法**
- **半径内(同文件其他函数)** — 职能相近且本轮任务明显覆盖(如 `interpMapGetKeys` / `interpMapDelete` 在改 Map 扩容时一起削)**合法**,但 commit message 必须说明相关性
- **远距离(跨子族、无语义关联)** — **禁止**,除非有独立 justification 写进 commit message 且不提"为压 gate"

远距离改动一旦出现 → **立即停手**,回归扩容申报路径。

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

### 反射路径扩容判定

**trigger**:涉及"反射路径形态升级"(容器类型 Array→Map / AST 字段扩 / Meta kind 变更)。

- **强制列全 14 指标 delta 预估**(M1/M2/M3a/M3b/M4/M5/M6/M7a/M7b/N1/N2/N3/N4/N5,**不允许只列结构组漏累计组**)
- 结构组任一 > 0 或累计组任一超 tol → **三选一**:
  - (a) 本地抵消(列具体削减点,限 §半径规则)
  - (b) 升 baseline + D 文档 §扩容申报
  - (c) 拆 commit(除非用户明确拒绝分轮)
- D 文档 §扩容申报段**必含**:扩容理由(引用 §第一性需求)/ 预期 14 指标 delta / 本地抵消路径 + 具体函数 / 新 baseline 预期值(=实测预估)/ VCM 实测 vs 预估对照槽

---

## Fractal 承载(L0-L4 递归)

九问五验在所有层级递归适用。每层向上引用,**不重复内容**。

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
- **接入 pre-commit hook**:当前**人工执行**(被查者在 VCM §5 (d) 手动跑)。自动化升级策略(`PreToolUse` hook / 结构化问答格式 / 收敛记录归档)留下轮 D 文档讨论

---

# 附录 B: 八股形态索引

## B.1 已机械化层(6 个 linter)

| 层 | 工具 | 判据 | 抑制的八股形态 |
|---|---|---|---|
| 反射扩容 | `reflection_health_linter.ss` | 14 指标 vs `budget_max`(scope-aware) | 远距离榨指标(间接:超 tol 逼申报) |
| 下轮 payload | `next_prompt_ultrathink_linter.ss` | 文件存在 + 非空 + 含 ultrathink | 下轮退化成浅 reasoning |
| bug 修复 | `bugfix_linter.ss` | 证据文档 + 6 gate | 修 bug 无诊断靠感觉 |
| 双入口 | `dual_track_linter.ss` | scope 特征 | 双轨伪装成"兼容架构" |
| commit 差半径 | `commit_radius_linter.ss` | 子族分布 ≥ 3 | 远距离榨指标(直接,soft warn) |
| commit footer | `commit_footer_bagu_linter.ss` | "去掉少什么:" 字串存在 | VCM 复盘凑仪式(格式强制) |

## B.2 未机械化层(6 种形态)

1. **远距离榨指标** —— 改无关代码压 CC/M5(commit_radius soft 覆盖,未根解)
2. **凑 VCM 仪式** —— 每项打 ✓ 没真对照(commit_footer 格式外化,未根解)
3. **grep 摆样子** —— 跑命令只为满足 PSM 字段 1 槽(未机械化:意图判断)
4. **编造 D 文档段** —— 为让引用有物现起草(未机械化:意图判断)
5. **文档膨胀** —— 500 字解释其实一句话够(未机械化:价值判断)
6. **checklist 表演** —— TaskCreate 微步骤凑进度条(未机械化:意图判断)

**原理限制**:八股 = "形式上满足规则,对任务核心产出零贡献",判据是**反身性**(回看自己刚写的)+ **语义**(核心产出定义依赖上下文)。linter 查**可观测特征**(指标数、关键字、路径、字串存在),看不见**意图**。同一 for-in→while 改动 D121 场景是八股、独立 refactor 场景合法,linter 无法区分。

## B.3 元悖论:流程本身会八股化

- 九问 PSM 填齐 ≠ 想清楚
- 五验 VCM 逐项 ✓ ≠ 真对照
- 收尾 gate N 步走完 ≠ 真产出
- **流程反思步骤若退化为"每轮答'无'" ≠ 真反思**

档位自报(微改 / 标准改 / 大改)是对这层的部分反制 —— 档位错报 + 实际超档 → 收工 gate 回写补齐暴露漂移。但档位判定本身也可被压字符绕过。

**终极闸门双支柱**:

- (a) 高发形态的机械 linter 倒逼 —— 覆盖**形态**
- (b) 用户回合间抽查 + 流程反思强制审视 —— 覆盖**内核**

---

# 附录 C: 历史事件索引

| 事件 | 形态 | 诱因 gate | 消除路径 |
|---|---|---|---|
| 2026-04-14 D091 + dispatch 重排漂移 | 不过 gate 就动手 | harness 强化结构化执行偏见 | PFV 十问 / 五验 gate |
| 2026-04-15 D092 branch 戏剧性 reset | 用整体否定替代细致诊断 | 无 reset 双重验证 | §特定领域 §Reset 双重 gate |
| 2026-04-15 @derive 漂移 | D 文档应然被当实然 | PSM 字段 1 无 grep 对照 + 收尾无 RED | §字段 1 grep 对照 + §收尾 Execute 型 RED 凭据 |
| 2026-04-20 D113 codegen.ss 492 行 R4 宣告 | 行数达成 ≠ 结构清晰 | F1 硬阻无结构判据 | P10.1 拆分判据升级 |
| 2026-04-20 D116 gen_rt_cache.ss 漏归 rt/ 子族 | Plan 路径决策漂 | PSM 字段 5 未扫命名前缀族 | §字段 5 (a) 命名前缀族扫描 |
| 2026-04-21 D121 R1-A Execute 2 newTvArray 远距离榨指标 | 远距离 | 反射 14 指标粗 gate | D125 §P2 scope-aware + §K commit_radius |
| D124 Execute 5 次 bump 串跑 | 仪式 O(N) | bump 单指标粒度 | D125 §P3 bump-group |
| 10e2c8b rowMap "bv:bm" + tuple 裸露 | 可读性失真 | simplify 3 维度缺 readability | D125 §P1 4th agent |
| F1 600 字符级塞字符 | 压缩 / 合并 / 删空行 | F1 硬阻无 soft warn | D125 §P4 AUTO-DRIFT |
| 简单改也十问 PSM | 仪式不分层 | PFV 粗粒度强制 | D125 §P5 三档分层 |
| 2026-04-22 VCM (d) 沉积复盘靠自觉 | 八股沉积 | §VCM 无 commit footer 强制 | §K commit_footer |
| 2026-04-22 八股讨论结论留对话缓冲区 | 跨轮丢失 | 无流程反思 gate | §收尾 gate 第 3 步流程反思 |
| 2026-04-22 流程层规则分散 3 处 | 跨轮 Claude 读不全 | 无单一事实源 | **本文档归档(docs/3-MNK.md)** |

---

# 参考

- `docs/1-axioms.md`(项目公理)
- `docs/2-principles.md`(原则,§PFV 流程 指针指向本文档)
- `docs/3-decisions/D088-*.md`(Zig 路线主 D 文档)
- `docs/3-decisions/D097-reflection-root-cause-metrics.md`(反射根因指标体系)
- `docs/3-decisions/D124-linter-baseline-budget-two-column.md`(baseline 2 列制)
- `docs/3-decisions/D125-gate-precision-improvements.md`(数值 gate 精准化,本文档姊妹篇,后续清理)
- `docs/terman-auto-next.md`(下轮提示词自动注入机制)
- `CLAUDE.md` §项目技术规则(交互式单文档 / PFV 流程 / 根因优先)
