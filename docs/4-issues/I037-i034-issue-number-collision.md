# I037 — issue 编号冲突:I034 被「comparison/logical→bool 显示 parity 修复」(已 Done)与「inferArrayElemType 覆盖不全致 join 段错」(Planned backlog)双重占用

**父决策:** D171 §下一步 合并就绪巡检(2026-05-29)发现的 issue 注册表编号撞车;非 D171 代码缺陷,是 §收口验收 follow-up storm 同日双线并发立项导致。
**状态:** **[x] Resolved（2026-05-30）**(非阻挡 D171 代码合并;纯 issue-doc 治理缺陷,已按 §推荐落地 —— array-elem-infer 迁 `I038` + comparison 工作补 canonical `I034-comparison-logical-bool.md`,源码↔issue 语义对齐;详见末 §解决)。
**颗粒度:** 预估微改~标准改(1 文件重命名 + 1 新 canonical 文件 + 若干引用回写;不触 bootstrap)。
**依赖:** 无。
**创建:** 2026-05-29
**立项由:** D171 合并就绪巡检 —— 顺 `bootstrap/gen/gen_types.ss` 的 I034 注释指针 `cat docs/4-issues/I034-*.md` 会落到**错误的** issue(array-elem-infer,与注释语境无关)。

---

## 现象(冲突坐实)

两个**不同根因**的工作共用编号 **I034**:

1. **comparison/logical→bool 显示 parity 修复(已 Done)** —— 引用 I034 的位置:
   - `docs/3-decisions/D171-sema-q2-comptime-coverage.md` line 169(`[x] Done — I034 runtime comparison/logical→bool 推断残留修复`)
   - commit `b3315ac`(message `fix(D171): I034 comparison/logical→bool ...`,**git 历史不可变**)
   - `i034_comparison_logical_bool.options.md` / `i034_comparison_logical_bool.bugfix`
   - `tests/phase5/i034_comparison_logical_bool.ss`
   - `bootstrap/gen/gen_types.ss` 源码注释
   - **但无 canonical `docs/4-issues/I034-comparison-*.md` 文件**。
2. **inferArrayElemType 覆盖不全致 scalar 数组 join fallback 段错(Planned backlog)** —— 占用 `docs/4-issues/I034-array-elem-type-infer-gaps-join-fallback-segfault.md`(finding A 轮 `/simplify` altitude agent 立项),且**未被 D171 §下一步 任何条目链接**(孤立 backlog)。

## 根因

D171 §收口验收 follow-up storm(2026-05-29 同日)双线并发取号失同步:

- finding A 轮 `/simplify` altitude agent 取号 I034 给「array-elem-infer」(写入 `docs/4-issues/`,但**未回写** D 文档 §下一步)。
- 主 D 文档作者从 I033 条(line 166)起把「comparison/logical→bool 残留」标为「I034」,**未察觉 I034 已被 /simplify 占用** → 后续 comparison 工作的所有 artifact(options/bugfix/test/源码注释/commit)均沿用 I034。

`tools/derived_issue_linter.ss` 只校验「IXXX 被引用 → `docs/4-issues/IXXX-*.md` 是否存在」,**不校验语义匹配** → I034 文件存在即 PASS,**漏报本冲突**(假 PASS;D171 合并就绪巡检实测 derived_issue GATE OK 但冲突仍在)。

## 候选路径(待 Execute 轮 PSM §字段 10 展开)

- **推荐(代价反转判据)**:array-elem-infer backlog(引用面**小**:仅自身文件 + finding A `/simplify` 对话 + 可能 I035 doc 提及)重命名到自由号(取当前 top +1,本 issue 落地后即 I038);为 comparison/logical→bool **已 Done** 工作补建 canonical `docs/4-issues/I034-comparison-logical-bool.md`(标 `[x] Done`,锚 commit `b3315ac` + D171 line 169 + `i034_comparison_logical_bool.options.md`)。理由:comparison 工作的 I034 引用面**大**且含**不可变** git 历史,改它代价远高于改 array-elem-infer。
- **次选**:comparison 工作改号 → 牵动 commit 历史(不可变)+ 5+ committed artifact,代价高,**不推荐**。
- **linter 增强(正交可叠加)**:`derived_issue_linter` 增「同号语义一致性」校验(检测同一 IXXX 在不同 artifact 指向不同标题/主题),防同类复发 —— 对称 `d_doc_index_linter` F1 死指针思路。

## 为何独立(不混入 D171)

D171 代码全绿(bootstrap 三阶段固定点 + 全测 350/3 + reflection/sunset/d_doc/derived/bugfix 全 gate clean);本 issue = issue 注册表编号治理缺陷,**零代码影响**,非阻挡合并。MNK §衍生 issue 归档:非阻挡独立 root cause → 立项不混入。

---

## 解决（2026-05-30,合并前执行 §推荐）

按 §推荐「代价反转」判据落地(改引用面小的一方):

1. **`git mv`** `I034-array-elem-type-infer-gaps-join-fallback-segfault.md` → **`I038-...md`**(标题 I034→I038 + §编号溯源 注;引用面仅自身 + `I035` 两处 back-ref,均同步改 I038)。
2. **补建 canonical `I034-comparison-logical-bool.md`**(标 `[x] Done`,锚 commit `b3315ac` + D171 行 169 + `i034_comparison_logical_bool.options.md`/`.bugfix`/`tests/phase5/i034_comparison_logical_bool.ss` + `gen_types.ss:376,388` 注释)—— 令所有既存 I034 引用(含**不可变** git 历史 + 源码注释)语义归位,**零改 `bootstrap/` 源码**。
3. **未动**:comparison 工作的 options/bugfix/test 文件名 + commit 历史 + 源码注释(均指 comparison,补 canonical 后即正确)。

**验证**:`bin/ss build tools/derived_issue_linter.ss` GATE OK(I034/I037/I038 引用各有实存文件);`ls docs/4-issues/I034-*.md` 现唯一指 comparison-logical-bool;`gen_types.ss` I034 注释 `cat docs/4-issues/I034-*.md` 现落到正确 issue。

**残留(正交,未本轮做)**:`derived_issue_linter` 仅校验「IXXX 文件存在」不校验语义,本冲突当时假 PASS —— §候选「linter 增强(同号语义一致性校验)」留后续(非阻挡,本次靠人工巡检已捕获)。
