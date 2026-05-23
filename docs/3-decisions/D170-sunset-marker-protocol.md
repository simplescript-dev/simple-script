# D170: SUNSET marker — 过渡债漂移机械 gate 协议

**Status:** **Phase 0 Done at f3a93bd** — D170 §决策落地(canonical marker 模板 + linter C1-C4 + Phase Exit Gate 双轨触发 + 6 步序 + sibling D097 对标);**Phase 1 起首 Done at 3ff649a** — tools/sunset_linter.ss MVP C1-C4 默认模式 + 4 doc-anchor 测试 (1 positive + 3 negative) 跑通 + simplify 3 项 actionable 落实;**Phase 1 续 Done at 72f47c3** — docs/3-MNK.md §特定领域 §SUNSET marker 治理 gate (sibling 第四只) + §After Done §1.5 sunset_linter gate 接入 (simplify 与 commit 之间);**Phase 1 完 In Progress at step 4** (CLAUDE.md §项目技术规则 「SUNSET marker (强制)」段 — 用户级 SSoT 入口,本轮);**Phase 2 起首待 step 5** (8 + 40 存量 backfill);**Phase Exit Gate 落地待 step 6**。
**Depends on:** D097 (reflection_health_linter §决策 + linter 拆 commit sibling 模式), D093 (本会话 8 处过渡件实证来源 + 1.5a-d sub-round 节奏实证), D169 (sub-round 分批迁实证)
**Spawned by:** 2026-05-23 用户对话「实现过程中有些过渡阶段,等到后期,可能忘记了发生了漂移,忘记清理过渡的逻辑」+ 同对话用户锁定候选 A+B
**Date:** 2026-05-23
**Last Updated:** 2026-05-23 (Phase 0 立项)

## 第一性需求

**过渡债不能漂移。**

渐进 sub-round 实现里,每轮 MNK PSM 字段 5「不做」清单合法地把"剩余"推下一轮 —— 这本是 §改动分层档位 + commit_radius 单子族纪律的副产物。但当跨多个 sub-round 累积,代码里以**自然语言注释**「留 X+」/「Phase Y 留」记录的过渡件,**无 canonical 模板 → grep 不可枚举;无机械 gate → phase 关闭时不触发清理;无出站清算 → 默认 silent 流过**。最终漂为永久残留。

**核心机制要求**:
1. **入站规整**:每个过渡件必走 canonical marker 模板,grep 一次抓全
2. **机械 gate**:marker 引用的 phase §下一步 状态从 `[ ] Planned` → `[x] Done` 时,linter BLOCK commit
3. **出站清算**:phase 整段 Done 时,Phase Exit Gate 强制独立 commit 跑过渡债清盘,显式 resolve 每个 marker

## 历史语境(2026-05-23)

来源 = 2026-05-23 用户对话:

> "我想改进开发流程,我们先讨论。就是实现过程中有些过渡阶段,等到后期,可能忘记了发生了漂移,忘记清理过渡的逻辑。"

同对话 ultrathink 分析后用户锁定候选 A+B (SUNSET marker + Phase Exit Gate 双轨)。本 D 文档落地这两件。

**实证 8 处当下存量过渡件** (D093/D169 1.5a-d 实施中累积,均自然语言注释「留 X+」无 canonical 模板):

| # | 位置 | 当前 marker (自然语言) | target phase |
|---|---|---|---|
| 1 | `eval_expr.ss:32-34` UNARY | "Phase 1.5d genVal 桥消除后此反向转可去除" | D093 §Phase 1.5d/1.5e+ |
| 2 | `eval_expr.ss:108-111` BINARY | "Air.Inst.Ref 终态依赖 SS 数据流升级跨 phase scope 留 1.5e+" | D093 §Phase 1.5e+ |
| 3 | `eval_expr.ss:88` COMPTIME_EXPR | `if (comptimeDepth > 0)` "类 C 边界" | D093 §Phase 8 §差距 #5 |
| 4 | `ct_driver.ss:30-36` enter/exit | dual-write `comptimeDepth` + `comptimeMustBeKnown` | D093 §Phase 8 §差距 #5 |
| 5 | `interp_op.ss` `interpNumericBinop` | "NaN/精度 Phase C 留" | D098 §Phase C |
| 6 | `stmts_loop_classic.ss:12 + :71` | for/while 还是 `comptimeDepth > 0` | D093 §Phase 1.5d 主轮收口子步 sibling 子轮 |
| 7 | `pow_binary.ss` / `null_coalesce.ss` | "eager 上移留 1.5e+ 桥消除" | D093 §Phase 1.5e+ |
| 8 | `gen_decls.ss` / `call.ss` / `method_call.ss` 等 ~40 处 | 类 A `if (comptimeDepth > 0)` | D093 §Phase 2-5 |

**关键观察**:8 处用了**至少 6 种不同自然语言模板** —— "留 1.5e+" / "Phase C 留" / "Phase 8 §差距 #5" / "1.5d 桥消除后" / "终态依赖 X" / "类 C 边界"。无 grep pattern 一次抓全。**这是漂移的物理根因**:用自然语言记账,跨轮 reader 不可枚举。

## 决策

### A. canonical marker 模板

```
// SUNSET(D<NNN> §<phase>): <one-line WHY this transitional exists now>
//   <optional multi-line elaboration / sub-task reference>
```

**强制约束**:
- `SUNSET` token 必在注释第一行(不允许「SUNSET 这里...」中间出现的写法)
- `D<NNN>` 必须实存于 `docs/3-decisions/` (沿用 `tools/d_doc_index_linter.ss` 同模式校验)
- `§<phase>` 必匹配该 D 文档 §下一步 列表中存在的 phase 名 (`D097 §M1` / `D093 §Phase 1.5e+` / `D098 §Phase C` 等)
- 冒号后 1 行 reason **必填**,空 reason BLOCK
- **可选 sub-task 段** (双层锚): `// SUNSET(D093 §Phase 8 §差距 #5):` —— 主校验 phase 段(粗粒度稳定),sub-task 段是辅助导航(细粒度,§ 段名变化时软警告不 BLOCK)

**示例对比**:

```ss
// SUNSET(D093 §Phase 1.5e+): genVal 桥消除后此反向编码可去除,sibling UNARY/BINARY 同模式
const subMv = isCt(subRaw) == 1 ? subRaw : (0 - subRaw - 1)
```

```ss
// SUNSET(D093 §Phase 8 §差距 #5): comptime 块降为 flag 后 comptimeDepth 可删,
//   当前 dual-write 期 ct_driver enter/exit lockstep 维护两 flag
function enterComptimeBlock() { comptimeMustBeKnown = 1; comptimeDepth = comptimeDepth + 1 }
```

### B. `tools/sunset_linter.ss` 规则

**默认模式 (C1-C4)**:挂在 MNK §After Done §1 simplify 与 §2 commit 之间的新 §1.5 gate。

| Check | 规则 | 违反行为 |
|---|---|---|
| **C1 collection** | `grep -rnE "SUNSET\(D\d+ §[^)]+\)"` 全 `bootstrap/ lib/ tools/`,列所有 markers 按 D 文档 / phase 聚合 | 报告,不 BLOCK |
| **C2 D 文档实存** | 每 marker 的 `D<NNN>` 必在 `docs/3-decisions/` 实存 (沿用 d_doc_index_linter 模式) | **BLOCK commit** + 输出死指针 |
| **C3 phase 状态** | 每 marker 的 `§<phase>` 在该 D 文档 §下一步 中: (a) 有 `[ ] Planned <phase>` 项 → **PASS**;(b) 已 `[x] Done <phase>` 但 marker 还存在 → **BLOCK**;(c) § 段名不存在 → **软警告** | (b) BLOCK / (c) 软警告 |
| **C4 reason 非空** | 冒号后第一行 reason `.trim().length() > 0` | **BLOCK commit** |

**Phase Exit 模式** (`--phase <X>`):由 Phase Exit Gate 触发,见 §C。

### C. Phase Exit Gate (B 候选机制)

**双轨触发** (用户对话锁定):

**Auto-detect (软提示)**:`sunset_linter` 默认模式跑时,检测 D 文档某 §<phase> §下一步 全 [x] Done (无 [ ] Planned) → 输出 `[INFO] phase <X> 看起来可关闭了 (N 个 SUNSET marker 待清)` 软提示,**不 BLOCK**。允许 phase 自然完结期 grace window —— 不强迫上一个 sub-round commit 就立即 exit verify。

**Manual gate (硬 BLOCK)**:开发者在 commit message **footer 显式写** `Phase X exit verify` →  `sunset_linter --phase X` 强制跑:列所有 `§<phase=X>` markers,每个必须显式 resolve (代码已删 / 升级到 `§<Y>` / 标 `// PERMANENT(reason):`),任一未 resolve → **BLOCK commit**。

**Exit 动作清单**:

1. **独立 commit** `docs(D<NNN>): Phase X exit verify` (commit_radius 单子族,不与 implementation 混)
2. **D 文档 add §Phase X §出口清单 段**,每 marker 一行显式 resolve:
   - `[clean]` 代码已删,引 commit hash
   - `[upgrade]` 标移到 `§<Y>`,引 commit hash
   - `[permanent]` 永久保留,给永久理由 (替 SUNSET 为 `// PERMANENT(reason):`)
3. commit message footer:
   - `Phase X exit verify`
   - 标准 `去掉少什么:` footer (memory `d093-subround-backfill-needs-footer` 同协议)

## 落地 6 步序

按 sibling D097 模式 (decision + linter 拆 commit),本协议拆 6 步:

| # | Layer | 内容 | 档位 | commit_radius |
|---|---|---|---|---|
| 1 | Decision | Done at **f3a93bd** — D170 §决策落地 + next_prompt 起草 step 2 | 大改 (新 D 文档) | docs/ 单子族 |
| 2 | Implementation | Done at **3ff649a** — `tools/sunset_linter.ss` MVP (245 LOC) 默认模式 C1-C4 + 4 测试 doc-anchor `tests/d170_sunset_marker_protocol/sunset_linter_*.ss.txt` (per-doc subdir 对齐 D161-D165 sibling) | 标准改 | tools/ + tests/ 双子族 |
| 3 | Process | Done at **72f47c3** — `docs/3-MNK.md` §特定领域 §SUNSET marker 治理 gate 段 + §After Done §1.5 sunset_linter gate 接入 | 标准改 | docs/ 单子族 |
| 4 | Process | **本 commit** — `CLAUDE.md` §项目技术规则 新增「SUNSET marker (强制)」段 + 引 D170 §决策 + 引 MNK §SUNSET marker 治理 gate (双链 SSoT 不复制规则) | 标准改 | docs/ 单子族 |
| 5a | Backfill | 8 处显式过渡件 SUNSET marker 落地 (实证表 #1-7 + #6 sibling 子轮预留) | 大改 (多文件 bootstrap/) | bootstrap/ 单子族 |
| 5b | Backfill | ~40 处类 A 批量 (`gen_decls.ss` / `call.ss` / `method_call.ss` 等 D093 §Phase 2-5 candidates) | 大改 | bootstrap/ 单子族 |
| 6 | Implementation | `sunset_linter.ss --phase X` 模式 + Phase Exit Gate 落地 + 首次试用 = 回流 `feat/d092-sema-q1` 后 D093 §Phase 1.5d sibling 子轮完结时 | 标准改 | tools/ + docs/ |

预估 **6 commit** (拆 5a/5b 为 2 commit),跨 4-6 个对话轮。

## 与现有机制关系

### sibling: D097 reflection_health_linter

- D097 立项当时同形:**§决策 (M1-M7 + N1-N5 metrics + baseline 2 列制) + tools/linter 实现 + bump CLI** — 拆多 commit
- D170 沿用同模式:**§决策 (marker 模板 + linter C1-C4 + Phase Exit Gate) + tools/sunset_linter.ss 实现 + --phase X CLI**
- D097 baseline 双列制 vs AUTO-DRIFT 软警告 — D170 类比:phase Done = BLOCK 硬 gate,phase 自然完结期 = 软警告

### 复用: `tools/d_doc_index_linter.ss`

- d_doc_index_linter 校验源码注释 `D<NNN> §` 引用是否指向实存 D 文档
- sunset_linter C2 复用同模式 (D 文档 grep + 实存判)
- 长期可考虑共享 helper (但 D170 Phase 0 不抢 scope,留 Phase 2+ 优化)

### 不重复: MNK PSM 字段 5 「不做」清单

- 字段 5 是**单轮 scope 边界**,本协议是**跨轮聚合机械化补丁**
- 字段 5 写「不做 X 留下轮」时,**配套**在代码侧加 SUNSET marker (新规),让"留下轮"具备机械可追踪性
- 字段 5 规则不变,仅扩展配套行为

### 不重复: D 文档 §下一步 `[ ] Planned` 项

- D 文档 §下一步 是**单一事实源** —— phase 计划项的权威清单
- SUNSET marker 是**代码侧反向锚** —— 指回 §下一步 计划项
- 双向链:代码侧 SUNSET → D 文档 §下一步 (linter C3 校验),D 文档 §下一步 [x] Done → SUNSET marker 必须为 0 (linter C3 BLOCK)
- 不引第三方 transitional debt index 文档 (违 SSoT)

### 不重复: memory 系统

- memory 是**事实 / feedback / 用户偏好的跨轮持久化**
- SUNSET marker 是**过渡代码的机械锚**,职责不同
- 不把 SUNSET 镜像入 memory (memory 数量爆炸 + 被动 recall 不构成 gate)

## 拒绝准则 (类比 D093 §0.3)

落地中若以下情况,**先升 D170 协议再继续**:
- (1) SUNSET 模板与某 sub-domain 既有注释习惯冲突需新模板 → 升 D170 §决策再 backfill
- (2) sunset_linter 实施触发反射路径变化 → reflection_health_linter (D097) 联动判,跨族影响升 D170
- (3) backfill 发现"不可清理"的过渡件 (永久存在合理) → **显式标 `// PERMANENT(reason):` 替代 SUNSET**,记入 D 文档 §出口清单;**不允许**保留 SUNSET 假装是过渡 (违 §第一性需求)
- (4) Phase Exit Gate 实施发现某 D 文档 §下一步 无 [x] Done 终态语义 (e.g., 永久 In Progress) → 升 D170 加 §决策 §"无 exit 的 D 文档" 特例规约

## Phase 0 验收 (Done at f3a93bd)

| # | 验收项 | 实测 |
|---|---|---|
| 1 | `docs/3-decisions/D170-sunset-marker-protocol.md` 实存 | commit f3a93bd Write 184 lines |
| 2 | §第一性需求 + §决策 (A+B+C) + §6 步序 + §关系 + §拒绝准则 + §下一步 落地 | `grep -c "^## " D170-*.md` ≥ 6 |
| 3 | `tools/d_doc_index_linter.ss` GATE OK (D170 引用都活) | 本 commit 后跑验证 |
| 4 | `.claude/next_prompt.md` 重写指 step 2 (sunset_linter MVP) | 本 commit Write |
| 5 | `tools/next_prompt_ultrathink_linter.ss` C1-C5 PASS | 本 commit 后跑验证 |
| 6 | 新分支 `feat/d170-sunset-marker-protocol` from `feat/d092-sema-q1` HEAD ddd327c | 已 checkout |
| 7 | `feat/d092-sema-q1` 上 `.claude/next_prompt.md` (1.5d sibling 子轮) 保留 | 不动 |
| 8 | bootstrap 核心代码路径 diff = 0 | `git diff HEAD~1 -- bootstrap/ lib/ tools/` 空 → VCM §1 豁免 bootstrap 固定点 |

## 下一步

- **[x] Phase 0 Done at f3a93bd** — D170 §决策立项 + 6 步序落档(commit f3a93bd "docs(D170): Phase 0 立项 — SUNSET marker 过渡债漂移机械 gate 协议 §决策落地",184 行 D 文档 + 与 D097/d_doc_index_linter/MNK/§下一步/memory 关系节 + 4 条拒绝准则 + Phase 0 验收 8 项)
- **[x] Phase 1 起首 (step 2) Done at 3ff649a** — `tools/sunset_linter.ss` MVP (245 LOC) 含 C1-C4 默认模式 + 4 测试 doc-anchor `tests/d170_sunset_marker_protocol/sunset_linter_{positive_legal,negative_phase_done,negative_d_doc_dead,negative_reason_empty}.ss.txt` per-doc subdir (positive PASS exit 0 + 3 negative BLOCK exit 1 + 各 C2/C3/C4 FAIL 直射) + simplify 3 actionable 落实 (Quality F6 flatten 4-deep nested ifs ×2 处用 `&&` + Quality F4a 命名 `PHASE_PROXIMITY_THRESHOLD = 50` 常量替 magic 50 + Reuse F6 测试 path 从 `tests/phase5/` 平铺移到 `tests/d170_sunset_marker_protocol/` per-doc subdir 对齐 D161-D165 sibling 约定);6 项 sibling parity / phase scope 拒 (Reuse F1-4 duplicate helpers 已 D170 §与现有机制关系字面延迟 Phase 2+ / Quality F1-3/F5/F7-10 sibling 风格 / Efficiency F1-3 D170 step 6 cache 留 / F4-8 clean)
- **[x] Phase 1 续 (step 3) Done at 72f47c3** — `docs/3-MNK.md` §特定领域 §SUNSET marker 治理 gate 段 (sibling §memory / §D 文档 / §反射路径根因 gate 第四只 — trigger + 硬规则 6 条 + 自检 trigger) + §After Done §1.5 sunset_linter gate 接入 (simplify 与 commit 之间,微改/纯文档不豁免 sibling 三 linter 单次跑成本可控);D170 § 在 MNK 多处引用 strengthen,d_doc_index_linter D170 orphan 状态消;SSoT 不分裂 (本段不复制 D170 §决策规则,仅引)
- **[~] In Progress Phase 1 完 (step 4)** — `CLAUDE.md` §项目技术规则 新增「SUNSET marker (强制)」段 + 引 D170 + 引 MNK § link
- **[ ] Planned Phase 2 起首 (step 5a)** — 8 处显式过渡件 backfill SUNSET marker (本 D 文档 §历史语境 表 #1-7 + #6 sibling)
- **[ ] Planned Phase 2 续 (step 5b)** — ~40 处类 A 批量 backfill (D093 §Phase 2-5 candidates,`gen_decls.ss` / `call.ss` / `method_call.ss` 等)
- **[ ] Planned Phase 2 完 (step 6)** — `sunset_linter.ss --phase X` 模式 + Phase Exit Gate 双轨触发 + 首次试用 = 回流 `feat/d092-sema-q1` 后 D093 §Phase 1.5d sibling 子轮完结时

**回流到 `feat/d092-sema-q1`**:6 步完结后,本分支 rebase / merge 回主线;之后 1.5d sibling 子轮 (for/while 迁) 直接用 SUNSET marker 取代自然语言「留 X+」首批落地。
