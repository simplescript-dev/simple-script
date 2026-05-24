# D170: SUNSET marker — 过渡债漂移机械 gate 协议

**Status:** **Phase 0 Done at f3a93bd** — D170 §决策落地;**Phase 1 全闭环 Done at f3a93bd→3ff649a→72f47c3→d7b5d9c** (三层 SSoT 链);**Phase 2 全闭环 Done at 9ca0e0e/95e0bab/d8a010b** — 32 markers 全库 substance 覆盖度 100% + `--phase X` Phase Exit Gate manual gate 落地 + 2 spike doc-anchor;**Phase 协议 step 7 实战 Done at b94dc8b (C1 feat impl) + 609b465 (C2 docs exit verify)** — D170 协议**实战首例完结**(设计→工具→流程→实战**四阶段全闭环**):回流 feat/d092-sema-q1 主线 fast-forward + D093 §Phase 1.5d sibling 子轮 for/while 迁 + 2 SUNSET marker 物理清 + 2 新 spike test + Phase Exit Gate manual verify 首次实操 verdict PASS "no cleanup needed" + D093 §出口清单 段首例落地;**step 8 协议 scope 扩 spec 落档 Done at 5e9bb16** — 实战首例后元-level 自审改进:audit 揭 6 类协议 scope 设计盲点(D 文档反向锚 / 接口默认参数哨兵 / 英文模式 / IR-emit / SUNSET 域内 PERMANENT 子残留 / 协议自循环)→ §决策 A 扩 3 亚类(A.1/A.2/A.3)+ §决策 B 扩 C5-C9 软警告 spec(实现留 step 9)+ §历史语境 加 audit 续段 + sunset_linter.ss 顶端示范自循环 SUNSET 锚(A.2 自循环约束就近落地避递归);**step 9 (a) 工具实施 Done at 27f4214** — `tools/sunset_linter.ss` 扩 C5/C6/C8/C9 软警告 grep + `--audit` flag + 默认 scan 加 docs/3-decisions/ + scanFile 加 D 文档不作 SUNSET 携带方 skip + 4 spike test doc-anchor + D170 §决策 B C7 行 spec 升级路径段(spike 实证 100% 假阳留 v0.2 callsite 判定升级)+ 2 sibling stale anchor 顺手升级 + D170 hash 回填 step 8 `5e9bb16`;实测 default 31 markers GATE OK + C5 222 / C6 6 / C8 43 / C9 3 软警告汇总。**step 9 (b.1) sub-context grep 精化 Done at ef47996** — 头 10 candidate spike 实证 10/10 假阳后 prompt §字段 12 触发"改方案先扩 C5 grep 精化"分支:scanFile 加三 sub-pattern 分流(Done 段 skip + Planned 段 keep + spec/narrative 段 skip + indent-aware + per-line override)+ 加 spike test doc-anchor `sunset_linter_c5c6_subcontext_skip.ss.txt` + 更新 C5/C6 spike fixture comment 反映精化效果 + D170 §6 步序表 step 9 (b) 拆 (b.1) / (b.2) 两行 + step 9 (a) hash 回填 `27f4214`;实测 **C5 222 → 43 (-81%) + C6 6 → 0** + 默认 31 markers GATE OK + 三 linter PASS + bootstrap 三阶段固定点 + 全测 334/3 baseline 持平。**step 9 (b.2.1) audit-driven v2 精化 Done at ad9ced8** — head 10 candidate v2 spike 实证 9/10 假阳(D154:522 唯一真候选,其他在 §核心目标 §不在范畴 / §A.1 决策行 / §A.3 废案 / §A.1.1 落点 表格 cell / 1.-6. numbered H2 spec / #### Phase 0 (本轮 Plan) Plan 段)后 prompt §字段 12 再触发"改方案先扩 C5 grep 二轮精化"分支:scanFile 由 b.1 黑名单 spec H2 反转为 b.2 白名单 active commit 严控,五 sub-pattern 分流(`inActiveCommitSection` 白名单 + `inCommitListItem` list-item 限定 + `isTableCell` skip + H3/H4 Plan 段 skip + paren-style `(Planned)` 扩)+ 加 spike test `sunset_linter_c5_subcontext_v2_skip.ss.txt`(1 正证 5 反证)+ 更新 b.1 fixture 过期正证(D170:299/301 paragraph 已 b.2 skip → D154:522 list-item 作新正证)+ D170 §决策 B C5 行 v2 升级路径段 + §6 步序表 step 9 (b.2) 拆 (b.2.1) v2 精化 + (b.2.2) backfill 留下轮 + D170 hash 回填 step 9 (b.1) `ef47996`;实测 **C5 43 → 1 (-97.7%,D154:522 唯一真候选 100% 真阳率,工具可信度 audit-ready)** + C6 0 维持 + 默认 31 markers GATE OK + 三 linter PASS + bootstrap 三阶段固定点 + 全测 334/3 baseline 持平。**step 9 (b.2.2) audit-driven backfill Done at 6432f92** — D154:522 唯一真候选 audit decision 三选一 (MNK §字段 10 (e)):**选 (a) sunset_linter 加第 6 sub-pattern hash-backfill 元规则 skip 因根因解决度最高**(工具机械化协议 scope 边界永久零返工 + 长久演化对标 Rust cargo deprecate-check v0.1→v0.2 升级期同模式 — 不选 (b) driver class 12/12 落地无过渡件不适用 + 不选 (c) 破坏 D135-D153 sibling 范式 hash trail 一致性);`tools/sunset_linter.ss scanFile` 加 `isHashBackfillMetaLine` helper(同行含 `commit hash` + `回填` 双 substring OR `hash 回填` 紧贴 token → skip — D135-D153 sibling 范式 "单 commit 不能引用自己 hash 下下轮回填" D 文档元规则话术非 SUNSET 协议 scope)+ 加 spike test `sunset_linter_c5_hash_backfill_skip.ss.txt`(1 正证 D154:522 skip + 4 反证 D149:328/367 + D135:169/198 + D136:176 sibling list-item hash-backfill 同模式 0 candidate + 1 累计 C5=0 验收)+ D170 §决策 B C5 行 v0.2 形态最终固化段 + D170 hash 回填 step 9 (b.2.1) `ad9ced8`。**实测**:**C5 1 → 0(-100% 真候选最终固化 + 100% 真阳率最终态)** + D154:522 skip + 默认 31 markers GATE OK + bootstrap 三阶段固定点 + 全测 baseline + 三 linter PASS。**协议 v0.1 → v0.2 升级期九阶段全闭环 + 形态最终固化**(设计→工具→流程→实战→scope 扩 spec → C5-C9 工具实施→ sub-context grep 精化→ audit-driven v2 精化→ audit-driven backfill).
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

### Audit 续段(step 8 — 实战首例后 scope 设计盲点反思)

**触发事件**:2026-05-23 D170 step 7 实战首例完结(b94dc8b C1 + 609b465 C2)后,用户连续两次 ultrathink 拷问 — "历史上有很多 SUNSET 需要标注吧" + "应该改进流程吧" — 指出**协议设计自身有盲点 → 改协议比补 N 处漏标更根本**(CLAUDE.md §Root Cause 第一法则:根因方案 vs workaround → 选根因)。

**6 类协议 scope 设计盲点**(audit 揭出,Phase 0/1/2 立项时漏 catch;**根因列摘要** — 完整形态见 §决策 A.x / §决策 B C.y):

| # | 盲点类别 | 根因摘要 | 协议扩措施 |
|---|---|---|---|
| 1 | **D 文档反向锚** | 单向引(代码→D 文档)漏反向(D 文档 ↔ 代码) | §决策 A.3 + B C5 |
| 2 | **接口签名默认参数哨兵** | `: int = -1` 哨兵默认参数本质过渡态(callsite 未全 forward) | §决策 B C7 |
| 3 | **英文模式** | 立项实证表只 catch 中文「留 X+」,漏英文同义模式 | §决策 B C8 |
| 4 | **IR-emit-side TODO** | 立项只看源码注释,漏 codegen 输出端 `emitIR("... TODO ...")` | §决策 B C9 |
| 5 | **SUNSET 域内 PERMANENT 子残留** | 立项只二选一(SUNSET 整块清 / PERMANENT 整块留),缺嵌套语义 | §决策 A.1 + C exit `[partial-clean]` |
| 6 | **协议自循环过渡件** | 协议自身 forward-looking commitment 也是漂移源(元-level 一致性) | §决策 A.2 + B C6 |

**根本根因** = 协议立项 scope 偏窄,只 catch 显式自然语言「留 X+」源码注释一种模式(Phase 0 §决策 A canonical 模板单层 + §决策 B C1-C4 单 grep pattern)。实战首例后**真实漂移面 ⊋ 协议立项 catch 面**,故而漏 N 处实证不是症状各自孤立,而是协议本身可治理范围设计不全。

**实战首例验证机制**(后续 D 协议 sibling 模板):每个新 D 协议 / linter 推出后,**首例实战 = scope 实证 audit 触发点** — Phase 立项时 ultrathink 自审有限,实战遇到的边界案例才是 scope 充分性的真正 forcing。D170 step 7 实战 → step 8 scope 反思 + 协议扩;后续 D 协议(sibling D097 reflection_health_linter / D161-D165 等)实战首例后皆应有"实战首例完结 + scope 反思入文"环节,不止"声明完结"。**业界对标** Rust `cargo deprecate-check` v0.1 → v0.2 升级期 — 初版只 catch 显式 `#[deprecated]` attribute,v0.2 加 grep 模式扩(`// TODO(removal):` 注释 / `unimplemented!()` 调用等);SS D170 v0.1 → v0.2 同模式 scope 扩。

**本段意义**:本 audit 续段是 **D170 实证完结里程碑** — 从"声明完结"升级为"实证完结 + scope 反思入文",**协议 v0.1 → v0.2 升级期形态固化**。后续 step 9 实施 C5-C9 linter 工具 → 跑出 candidates → 人工 audit 标 SUNSET / PERMANENT / false positive → 逐项 backfill(协议扩的自然副产物,不是人工记忆 file:line 漂移)。

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

#### A.1 SUNSET 域内 PERMANENT 子残留(audit #5)

**形态**:`// SUNSET(D<NNN> §<phase>):` 块内代码段若含**永久必要逻辑**(reset / dispatch fallback / dual-write 内永久写端 / 兜底 error path 等),该子段前必加 `// PERMANENT(<reason>):` 第二层标。phase exit 时 `[clean]` 部分代码 + `[partial-clean]` 标签保 PERMANENT 段(§决策 C exit 动作清单 §2 resolve 标签扩第 4 种,见 §C 节)。

**模板**:

```ss
// SUNSET(D093 §Phase 8 §差距 #5): comptime 块降为 flag 后 comptimeDepth 可删
function exitComptimeBlock() {
    comptimeMustBeKnown = comptimeMustBeKnown - 1
    // PERMANENT(嵌套真出栈必须 reset depth — 即使 D093 §Phase 8 完结此函数不删,reset 逻辑永久必要)
    if (comptimeDepth > 0) { comptimeDepth = comptimeDepth - 1 }
}
```

**强制约束**:
- PERMANENT 子段紧邻其保护代码,**不允许跨多行隔离**(必紧接下一可执行行)
- PERMANENT reason **必填**,空 reason BLOCK
- phase exit 时 SUNSET 整块清除若误删 PERMANENT 段 → §决策 C `[partial-clean]` 标签 BLOCK + 强制人工 audit
- 不允许 PERMANENT 嵌套 SUNSET(违 SSoT;若过渡件嵌套过渡件,拆为两个独立 SUNSET marker)

**实证 sibling**(audit 揭出):`ct_driver.ss` `exitComptimeBlock` 真嵌套出栈 reset(SUNSET 域内 PERMANENT 子残留)— Phase 8 完结后整段 SUNSET 物理清若误删 reset 逻辑则嵌套层级泄漏。

#### A.2 协议自循环过渡件(audit #6)

**形态**:D 文档**自身**(尤其 D170 自己,或任何 D 文档的 §下一步 / 与现有机制关系 / 历史语境 段)出现"留 Phase X+" / "留独立轮" / "长期可考虑共享 helper 留 Phase Y+" 类 **forward-looking commitment** 时,**关联工具 / 代码 / 测试**侧必有对应 SUNSET 反向锚。**元-level 一致性要求** — 协议设计自己说要标 → 协议设计自己必须标自身过渡件(§第一性需求"过渡债不能漂移"的递归应用,协议自己也是漂移源)。

**模板**:

```ss
// 文件顶端示范(sunset_linter.ss):
// SUNSET(D170 §与现有机制关系): 长期可考虑与 d_doc_index_linter 共享 helper
//   (D170 §与现有机制关系 line 133 明示"留 Phase 2+ 优化"),
//   sibling 工具 grep D<NNN> 实存判逻辑可抽 common helper
```

**强制约束**:
- D 文档自身 forward-looking commitment 凡在 `docs/3-decisions/D*.md` 出现"留 Phase X+" / "长期可考虑 X" / "Phase Y 优化"等表达 → 关联工具(若 D 文档绑定具体 tool/linter)或代码侧必有 SUNSET 反向锚
- 反向锚 reason 字段必引 D 文档原文锚(`§<section> line <N>` 或原文 partial quote),不允许"留 Phase X" 空话(避递归 audit 漂移)
- D 文档自己**不**作 SUNSET marker 携带方(D 文档是 SSoT,SUNSET marker 在代码 / 工具 / 测试侧)
- 协议自身改造时(如本轮 D170 step 8)**禁留新"Phase 2+"承诺**,改为本轮直接 spec 落档,或 split 为独立 D 文档(避自循环递归)

**实证 sibling**(audit 揭出):D170 §与现有机制关系 line 133 字面"长期可考虑共享 helper 留 Phase 2+"但 `tools/sunset_linter.ss` 顶端无 SUNSET 反向锚(本轮 step 8 就近示范修正)。

#### A.3 D 文档反向锚(audit #1)

**形态**:D 文档 §下一步 / list-item Done 注释 / 各 phase 子项 reason 段里说"留独立轮升级" / "留 X+ 处理" / "正交关切留独立轮" 等 **forward-looking commitment**,必触代码侧对应位置有 SUNSET 反向锚。**单向引扩双向引**(原 D170 §不重复 D 文档 §下一步 节"代码侧 SUNSET → D 文档 §下一步" 单向 → "D 文档 §下一步 ↔ 代码"双向)。

**模板**:

```markdown
<!-- D 文档 §下一步 -->
- **[x] Done at <hash>** 1.5c <case> 子轮 — ... silent→loud 升级属正交 error-reporting 关切,**本轮纯字面 swap 不碰 line N**(留独立轮独立升级路径)
```

```ss
// 代码侧对应位置(file:line 28):
// SUNSET(D093 §Phase 1.5c <case>): per-element silent null 留独立轮 error-reporting 升级,
//   引 D093 §下一步 1.5c <case> 子轮 Done 注释正交关切段
if (var-not-found) { return ctVal(interpNewNull()) }
```

**强制约束**:
- D 文档 §下一步 list-item 内的 "留独立轮" / "留下轮" / "留 Phase X" / "留 X+" 类承诺,代码侧必有同 phase 引用的 SUNSET marker
- 反向锚 reason 字段必引 D 文档 list-item locator(`D<NNN> §下一步 <phase> <case-name>` 或 `line <N>`)
- linter C5 软警告检查(allow grace window — phase 可能尚未起手时无代码侧 marker 合法;phase 起首后无 marker 则触警告)
- 双向链 invariant:**D 文档说留 X ↔ 代码侧标 X**;两侧任一缺 → C5 软警告

**实证 sibling**(audit 揭出):D093 §下一步 1.5c 各子轮 Done 注释"silent null 留独立轮 error-reporting 升级"~8 处(postfix_inc / array_lit / new_expr / call / ident / ternary / short_circuit / member_access)但代码侧 0 处 SUNSET 反向锚(C5 实证)。

### B. `tools/sunset_linter.ss` 规则

**默认模式 (C1-C4)**:挂在 MNK §After Done §1 simplify 与 §2 commit 之间的新 §1.5 gate。

| Check | 规则 | 违反行为 |
|---|---|---|
| **C1 collection** | `grep -rnE "SUNSET\(D\d+ §[^)]+\)"` 全 `bootstrap/ lib/ tools/`,列所有 markers 按 D 文档 / phase 聚合 | 报告,不 BLOCK |
| **C2 D 文档实存** | 每 marker 的 `D<NNN>` 必在 `docs/3-decisions/` 实存 (沿用 d_doc_index_linter 模式) | **BLOCK commit** + 输出死指针 |
| **C3 phase 状态** | 每 marker 的 `§<phase>` 在该 D 文档 §下一步 中: (a) 有 `[ ] Planned <phase>` 项 → **PASS**;(b) 已 `[x] Done <phase>` 但 marker 还存在 → **BLOCK**;(c) § 段名不存在 → **软警告** | (b) BLOCK / (c) 软警告 |
| **C4 reason 非空** | 冒号后第一行 reason `.trim().length() > 0` | **BLOCK commit** |

**扩 grep 模式 (C5-C9 软警告)** — step 8 协议 scope 扩落档,实现留 step 9。**全部软警告不 BLOCK**(audit 反思:hard BLOCK 应只在协议清晰且 grep 模式低假阳率时启用;C5-C9 首次落地用软警告 + 人工 audit 后逐步升 hard BLOCK,对齐 D097 AUTO-DRIFT 软警告升级路径)。

| Check | 规则 | 违反行为 |
|---|---|---|
| **C5 D 文档反向锚** | 扫 `docs/3-decisions/D*.md` §下一步 / list-item Done 注释,模式 `grep -nE "留(独立轮\|下轮\|X\+\|\d+\.\d+\+\|Phase\s+\w+)"`,逐项 trace 到代码侧是否有对应 SUNSET marker;无 → 软警告(allow grace window — phase 可能尚未起手时无代码侧 marker 合法;phase 起首后无 marker 触警告)。**规则承载** §决策 A.3。**v0.1→v0.2 升级 step 9 (b.1/b.2.1/b.2.2) sub-context 精化**:b.1 commit ef47996 三 sub-pattern 黑名单(Done 段 + Planned 段 keep + spec H2 black-list)缩 222→43;b.2.1 commit ad9ced8 五 sub-pattern 白名单(`## 下一步`/`## §下一步`/`## Followup`/`## Phase 收关锚`/`## Roadmap` 白名单 + list-item 限定 paragraph wrap-up skip + table cell skip + 4-space nested narrative skip + H3/H4 Plan 段/paren-style status 扩)缩 43→1(D154:522 唯一真候选 100% 真阳率,工具可信度 audit-ready);**b.2.2 commit 6432f92 第 6 sub-pattern 协议 v0.2 形态最终固化** `isHashBackfillMetaLine`(同行含 `commit hash` + `回填` 双 substring OR `hash 回填` 紧贴 token → skip — D135-D153 sibling 范式 "单 commit 不能引用自己 hash 下下轮回填" D 文档元规则话术非 SUNSET 协议 scope;D154:522 audit-driven 唯一真候选 false positive + sibling D149:328/367 + D135:169/198 + D136:176 list-item 同模式批量 skip)缩 1→0 真候选 + 100% 真阳率最终态(MNK §字段 10 (e) 三选一选 (a) 工具机械化协议 scope 边界因根因解决度最高);**协议 v0.1 → v0.2 升级期九阶段全闭环 + 形态最终固化** | 软警告(grace window) |
| **C6 协议自循环** | D 文档自身 §下一步 / §与现有机制关系 / 历史语境 出现"长期可考虑 X" / "Phase X 优化"等 forward-looking commitment(去重避 C5"留 X" 重叠)→ 关联工具(若 D 文档绑定具体 tool/linter)或代码侧必有 SUNSET 反向锚;模式 `grep -nE "(长期可考虑\|Phase \w+\+ 优化)" docs/3-decisions/D*.md` + 跨文件 trace 工具 / 代码侧。**规则承载** §决策 A.2 | 软警告 |
| **C7 接口签名默认参数哨兵** | **step 9 未实施 — 留 v0.2 升级路径**。**spike 实证 (step 9)**:`grep -rnE ":\s*(int\|string)\s*=\s*(\"\"\|0\s*-\s*1)" bootstrap/gen/ bootstrap/eval/` 实测 8 处全是合法 `preReg/preObj` 默认参数协议(`genExprAsString` / `genIndexAccess` / `genMemberAccess` / `genMethodCall` / `genValStringCompare` / `genStringConcat` / `genBinary` 等)— **假阳率 100%**。**根因**:简单 grep 单层 catch 不到"过渡态"vs"合法 optional" 语义差异 — 需要 callsite 判定升级(扫每参数的 callsite 是否全 forward 才能区分),超本 step scope。**v0.2 升级路径**:实现 callsite scanner(per-param 收集所有调用者实参 → 若全部显式传值 = 过渡态可去默认值,触软警告;若混 default + 显式 = 合法 optional 不警告)。**spec 承载** §历史语境 audit #2(诚实承认 grep 不足 → 协议 v0.1 → v0.2 升级期形态固化 sibling D097 AUTO-DRIFT 软警告升级路径) | **未实施** — 留 v0.2 升级路径 |
| **C8 英文模式扩** | 扫 `(future use\|later use\|TBD\|deferred\|not yet\|workaround\|placeholder\|stub\|FIXME)` 中英文统一(原 D170 §历史语境表只 catch 中文「留 X+」);grep -rnEi 跨 `bootstrap/ lib/ tools/`。**规则承载** §历史语境 audit #3 | 软警告 |
| **C9 IR-emit-side TODO** | 扫 `emitIR\(.*\b(TODO\|FIXME\|XXX)\b.*\)` 等 codegen 输出端 transitional placeholder(运行时 IR 携带的过渡件);grep -rnE 跨 `bootstrap/gen/`。**规则承载** §历史语境 audit #4 | 软警告 |

**C5-C9 升级路径**(对齐 D097 AUTO-DRIFT 软警告 → hard BLOCK 升级模式):
- step 9 实施 C5-C9 后用软警告跑 N 次(N ≥ 3)累积 audit 数据 + 实测假阳率
- 单 check 假阳率 < 10% 且 candidates 收敛(连续 2 commit candidates 数 = 0) → 该 check 升 hard BLOCK
- 升 hard BLOCK 时**必同步**改 D170 §决策 B 本表"违反行为"列(SSoT 同步,不可分裂)

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
| 4 | Process | Done at **d7b5d9c** — `CLAUDE.md` §项目技术规则 新增「SUNSET marker (强制)」段 + 双链 D170 §决策 + MNK §SUNSET marker 治理 gate | 标准改 | docs/ 单子族 |
| 5a | Backfill | Done at **9ca0e0e** — 9 处显式过渡件 SUNSET marker 落地 (实证表 #1-7 + #6 sibling 拆 2 + #7 拆 2 = 9 markers, 6 文件 bootstrap/eval+gen/stmts) + sunset_linter GATE OK + bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平 | 大改 | bootstrap/ 单子族 |
| 5b | Backfill | Done at **95e0bab** — 23 处类 A 批量 backfill (D093 §0.4 Phase 2-5 candidates,13 文件) + 32 markers 全库 GATE OK + bootstrap 三阶段固定点 verified | 大改 | bootstrap/ 单子族 |
| 6 | Implementation | Done at **d8a010b** — `sunset_linter.ss --phase X` 模式实施 + MNK §SUNSET marker 治理 gate 新「Phase Exit Gate 触发流程」段 + 2 spike doc-anchor + 首次试用 | 大改 | tools/ + docs/ + tests/ |
| 7 | Implementation/实战 | Done at **b94dc8b** (C1 feat impl) + **609b465** (C2 docs exit verify) — 回流 `feat/d092-sema-q1` 主线 + D093 §Phase 1.5d sibling 子轮 (for/while 迁) 首例 SUNSET marker 实战 + Phase Exit Gate manual verify 首次实操; **sibling 第二例应用 Done at b0f8d12 (C1) + f9360f9 (C2)** — D093 §Phase 1.5e+ ext (pow_binary + null_coalesce eager 上移桥消除 + genNullCoalesce 接口扩 lPreReg/rPreReg) + 2 SUNSET marker 物理清 + §出口清单 段 sibling 第二例落地 (默认模式 verify); **sibling 第三例应用 Done at 2c1fb98 (C1) + 6dbc2de (C2)** — D093 §Phase 1.5e+ later UNARY 反向编码统一 (UNARY swap `subMv = evalExpr(childId)` 单点 dispatch + evalExpr 加 4 leaf literal case prereq INT_LIT/TRUE_LIT/FALSE_LIT/GROUPING + §字段 12 假设破裂方案修正实证) + 1 SUNSET marker 物理清 + §出口清单 段 sibling 第三例落地 (默认模式 verify); **sibling 第四例应用 Done at c233add (C1) + 90aba70 (C2)** — D093 §Phase 1.5e+ later evalExpr 余下 leaf case 收口 (evalExpr 加 4 leaf literal case STRING_LIT/NULL_LIT/DOUBLE_LIT/NAMED_ARG 直返 ctVal / 委托内层 — 物理完整覆盖 leaf literal 集 10 case 除 THIS/SUPER/ARROW_FUNC ct-depth 特例) + **0 SUNSET marker 物理清**(4 leaf case 直返 ctVal 非过渡件)+ §出口清单 段 sibling 第四例落地 0-marker sibling 应用首例 (默认模式 verify GATE OK 29 markers 持平); **sibling 第五例应用 Done at 21f8342 (C1) + 7d66eb4 (C2)** — D093 §Phase 4 起首 THIS/SUPER ct-depth 入口字面消除 (evalExpr 加 THIS/SUPER case 直返 ctVal + interpThisVal/comptimeMustBeKnown loud-error/null fallback 三态 + exprs.ss:70-73 退化 thin dispatch 走 evalExpr 主 case) + **1 SUNSET marker 物理清**(exprs.ss:71)+ §出口清单 段 sibling 第五例落地 Phase 4 sub-round 系列起手首例 (默认模式 verify GATE OK 28 markers,-1 net,前四例皆 1.5d/1.5e+ scope 第五例首次跨入 Phase 4 sub-round 系列拓展 sibling 应用模板跨 phase 复用); **sibling 第六例应用 Done at 33c65e2 (C1) + 7c0bbcf (C2)** — D093 §Phase 4 续 ARROW_FUNC ct-depth 入口字面消除 (evalExpr 加 ARROW_FUNC case 直返 ctVal(interpNewVal("fn", `${astId}`)) 单态直构 + exprs.ss:74-77 退化 thin dispatch 走 evalExpr 主 case) + **1 SUNSET marker 物理清**(exprs.ss:75)+ §出口清单 段 sibling 第六例落地 Phase 4 sub-round 系列第二例同 phase 接力 (默认模式 verify GATE OK 27 markers,-1 net,Phase 4 内多 sub-round 复用 robustness — sibling 第五/六例同 phase 接力首例); **sibling 第七例应用 Done at 060e4e4 (C1) + 5118424 (C2)** — D093 §Phase 4 续 genVal 主 dispatch 入口 ct-depth 字面消除 (evalExpr 加 COMPTIME_EMIT/TYPEINFO_EXPR/unsupported 兜底 3 case + exprs.ss:79-92 整段退化 thin dispatch 走 evalExpr 主 case — 14 行整段删替换为 `const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1` mv 反向编码) + **1 SUNSET marker 物理清**(exprs.ss:79)+ §出口清单 段 sibling 第七例落地 Phase 4 sub-round 系列第三例同 phase 接力 (默认模式 verify GATE OK 26 markers,-1 net,Phase 4 内多 sub-round 复用 robustness 累计第三例 — sibling 第五/六/七例同 phase 接力) | 大改 | bootstrap/ + docs/ + tests/ 拆 2 commit (合 D170 §决策 C 独立 commit 原则);sibling 第二/三/四/五/六/七例同 2 commit 拆 |
| 8 | Decision/scope 扩 spec | **本 commit** — 协议 scope 扩 spec 落档:实战首例后 audit 揭 6 类盲点 → §决策 A 扩 A.1/A.2/A.3 亚类(SUNSET 域内 PERMANENT 子残留 / 协议自循环 / D 文档反向锚)+ §决策 B 扩 C5-C9 软警告(实现留 step 9)+ §历史语境 加 audit 续段(6 类盲点 + 实战首例验证机制反思)+ sunset_linter.ss 顶端示范自循环 SUNSET 锚(A.2 自循环约束就近落地避递归);D093 §下一步 1.5d 整段 [~] → [x] Done at b94dc8b | 标准改 | docs/ 单子族 + tools/sunset_linter.ss 1 处自循环示范注释 |
| 9 (a) | Implementation | Done at **本 commit** — `tools/sunset_linter.ss` 扩 C5/C6/C8/C9 软警告 grep 实施(C7 留 v0.2 升级路径 — spike 实证 100% 假阳需 callsite 判定升级 spec 段)+ `--audit` flag(默认汇总 N candidates,audit 详情 file:line)+ 默认 scan 加 `docs/3-decisions/` + scanFile 加 D 文档不作 SUNSET 携带方 skip(D170 §决策 A.2 落地 — D 文档是 SSoT 不当 marker 携带方)+ 4 spike test doc-anchor `tests/d170_sunset_marker_protocol/sunset_linter_c{5,6,8,9}*.ss.txt` + 顺手 fix 2 stale anchor (sibling positive_legal + phase_exit_active_pass anchor stale `1.5d 主轮收口子步 sibling 子轮` 已 [x] Done at b94dc8b → 升级 `1.5e+ helper 抽取`) + D170 §决策 B C7 行 spec 升级路径段 + hash 回填 step 8 `5e9bb16` | 大改 | tools/ + tests/ + docs/ |
| 9 (b.1) | Implementation/精化 | Done at **ef47996** — `tools/sunset_linter.ss` 头 10 candidate spike 实证 10/10 假阳(D157/D155/D149 全在 `### Phase X [x] Done at hash` heading sub-bullet)后 prompt §字段 12 改方案 `scanFile` 加三 sub-pattern 分流:(1) Done 段 skip (`### Phase X [x] Done / [✓] Done / [ ] Pending at commit \`hash\` / 顶级 - **[x] Done list-item / - 2026- Status 时间线 / 表格 cell [✓ Done at / at commit \`hash\``) +(2) Planned 段 keep (`[ ] Planned / [~] In Progress / [ ] Blocked`) +(3) spec/narrative 段 skip(## A.2 / ## §A.2 隐藏假设 + ## 决策 + ## 历史语境 + ## 与现有机制关系 + ## 拒绝准则 + ## 第一性需求)+ indent-aware(top-level 改 state / indented sub-bullet 继承 parent)+ per-line override(行内含 Done marker 跳行);**实测**:C5 222 → 43 (-81%) + C6 6 → 0 (D170 §决策 spec 段引模式作示例全清);C8/C9 不动(.ss 源码侧 sub-context 模式不适用);+ 加 spike test `sunset_linter_c5c6_subcontext_skip.ss.txt`(三 sub-pattern 5 反/正证 shell verify)+ 更新 C5/C6 spike test fixture comment 反映精化效果 + D170 hash 回填 step 9 (a) `27f4214` | 标准改 | tools/ + tests/ + docs/ |
| 9 (b.2.1) | Implementation/v2 精化 | Done at **ad9ced8** — `tools/sunset_linter.ss` 头 10 candidate spike v2 实证 9/10 假阳(D154:522 唯一真候选,其他全在非白名单 H2 / 表格 cell / Plan 段)后 prompt §字段 12 触发"改方案先扩 C5 grep 二轮精化"分支:`scanFile` 由 b.1 黑名单 spec H2 反转为 b.2 白名单 active commit 严控,五 sub-pattern 分流:(1) `inActiveCommitSection` 白名单(`## 下一步`/`## §下一步`/`## Followup`/`## Phase 收关锚`/`## Roadmap` keep,非白名单 H2 全 skip — 反 §A.X 决策 / §A.3 废案 / 1.-6. numbered spec / §核心目标 §不在范畴 漂移);(2) `inCommitListItem` 限定 list-item(`- **[`/`- ` 起首 → 1;`  - ` 2-space sub-bullet 继承 parent;`    - ` 4-space nested narrative reasoning → skip;blank/paragraph wrap-up → skip,D170:301/303 wrap-up paragraph + D093:307 ultrathink reasoning 都 skip);(3) `isTableCell` skip(`|` 起首 markdown table row);(4) H3/H4 Plan 段 skip(`(本轮 Plan)` / `(Plan 型)` / `(本轮 落档)` → docSubContextDone = 1);(5) H3/H4 paren-style status 扩(`(Planned)` / `(In Progress)` → docSubContextDone = 0,D154 ### Phase 18+:...(Planned) 风格)+ 加 spike test `sunset_linter_c5_subcontext_v2_skip.ss.txt`(五 sub-pattern 1 正证 + 5 反证 shell verify)+ 更新 b.1 fixture `sunset_linter_c5c6_subcontext_skip.ss.txt` 正证(D170:299/301 paragraph 已 b.2 skip → D154:522 list-item 作新正证)+ D170 hash 回填 step 9 (b.1) `ef47996`。**实测**:C5 43 → 1 (-97.7%,D154:522 唯一真候选 100% 真阳率,工具可信度 audit-ready)+ C6 0 维持 + 默认 31 markers GATE OK + 三 linter PASS + bootstrap 三阶段固定点 + 全测 baseline | 大改 | tools/ + tests/ + docs/ |
| 9 (b.2.2) | Backfill/audit-driven | Done at **6432f92** — v2 精化 (b.2.1) 完结后 1 C5 真候选 (D154:522) audit decision 三选一 (MNK §字段 10 (e)):(a) sunset_linter 加第 6 sub-pattern hash-backfill 元规则 skip / (b) lib/com/mysql/ 加反向锚(不适用 — driver class 12/12 落地无过渡件)/ (c) D154 §下一步 改写删 hash 回填承诺(破坏 D135-D153 sibling 范式 hash trail 一致性) — **选 (a) 因根因解决度最高**(工具机械化协议 scope 边界永久零返工 + 长久演化对标 Rust cargo deprecate-check v0.1→v0.2 升级期同模式);`tools/sunset_linter.ss scanFile` 加 `isHashBackfillMetaLine` helper(同行含 `commit hash` + `回填` 双 substring OR `hash 回填` 紧贴 token → skip — D135-D153 sibling 范式 "单 commit 不能引用自己 hash 下下轮回填" D 文档元规则话术非 SUNSET 协议 scope)+ 加 spike test `sunset_linter_c5_hash_backfill_skip.ss.txt`(1 正证 D154:522 skip + 4 反证 D149:328/367 + D135:169/198 + D136:176 sibling list-item hash-backfill 同模式 0 candidate + 1 累计 C5=0 验收)+ D170 §决策 B C5 行 v0.2 形态最终固化段 + §6 步序表 step 9 (b.2.1) hash 回填 `ad9ced8`。**实测**:**C5 1 → 0(-100% 真候选最终固化 + 100% 真阳率最终态)** + D154:522 skip + 默认 31 markers GATE OK + bootstrap 三阶段固定点 + 全测 baseline + 三 linter PASS;**协议 v0.1 → v0.2 升级期九阶段全闭环 + 形态最终固化**(设计→工具→流程→实战→scope 扩 spec → C5-C9 工具实施→ sub-context grep 精化→ audit-driven v2 精化→ audit-driven backfill) | 标准改 | tools/ + tests/ + docs/ |

预估 **10 commit** (拆 5a/5b / step 7 C1/C2 / step 8 scope 扩 spec / step 9 (a) 工具 / step 9 (b.1) 精化 / step 9 (b.2) backfill),跨 7-9 个对话轮。

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
- **[x] Phase 1 完 (step 4) Done at d7b5d9c** — `CLAUDE.md` §项目技术规则 新增「SUNSET marker (强制)」段 sibling 强制段第四只 (对称「Bug 修复 Harness (强制)」/「反射根因 gate (强制)」/「D 文档治理 gate (强制)」) + 双链 D170 §决策 + MNK §SUNSET marker 治理 gate (SSoT 不复制规则);三层 SSoT 链 Phase 1 全闭环 (用户级 CLAUDE.md + 流程级 MNK + 设计/工具级 D170/sunset_linter)
- **[x] Phase 2 起首 (step 5a) Done at 9ca0e0e** — 9 处显式过渡件 backfill SUNSET marker (本 D 文档 §历史语境 表 #1-7 + #6 sibling 拆 for+while 2 markers + #7 拆 pow_binary+null_coalesce 2 markers,合计 9):`eval_expr.ss` UNARY/BINARY/COMPTIME_EXPR (D093 §Phase 1.5e+/§Phase 8) + `ct_driver.ss` enter/exit dual-write (D093 §Phase 8) + `interp_op.ss` interpValEquals NaN/精度 (D098 §Phase C) + `stmts_loop_classic.ss` for/while (D093 §1.5d sibling 子轮) + `pow_binary.ss`/`null_coalesce.ss` eager 上移 (D093 §Phase 1.5e+)
- **[x] Phase 2 续 (step 5b) Done at 95e0bab** — 23 处类 A 批量 backfill (D093 §0.4 Phase 2-5 candidates 跨 13 文件):Phase 2 stmt 族 8 + Phase 3 decl/assign 族 7 + Phase 4 call/expr 族 4 + Phase 5 class/enum 族 3 = 23 markers;**32 markers 全库 GATE OK** + bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平;全库自然语言「留 X+」过渡件清零,D170 §第一性需求覆盖度 100%
- **[x] Phase 2 完 (step 6) Done at d8a010b** — `tools/sunset_linter.ss` 扩 `--phase X` 模式实施(D170 §决策 C 双轨触发 manual gate 落地;`args() ≥ 3 && arg(1) == "--phase"` + arg(2..) concat 绕 bin/ss run 拆 quoted 多 token args 限制;filter markers by phase + 按 phase 在 D 文档 §下一步 状态判 verdict — [x] Done → BLOCK / [ ] Planned / [ ] Blocked / [~] In Progress → PASS 软提示 / missing → WARN) + `docs/3-MNK.md` §特定领域 §SUNSET marker 治理 gate 新「Phase Exit Gate 触发流程」段(双轨触发 auto-detect 软 + manual 硬 BLOCK + Exit 动作清单 3 步 + linter 调用) + 2 spike doc-anchor `tests/d170_sunset_marker_protocol/sunset_linter_phase_exit_{active_pass,missing_warn}.ss.txt`(各 4-5 shell verify 命令跑通) + **首次试用** `bin/ss run tools/sunset_linter.ss --phase "1.5d 主轮收口子步 sibling 子轮"` 实测列 stmts_loop_classic for/while 2 markers + phase status `[ ] Planned` + verdict PASS + exit 0 + GATE OK
- **[x] step 7 实战 起首 (C1 feat impl) Done at b94dc8b** — Phase Exit Gate 协议**实战首例 C1**:`bootstrap/gen/stmts/stmts_loop_classic.ss:16+83` for/while 入口同形 sibling 迁(`comptimeDepth > 0 → comptimeMustBeKnown == 1` 字面 rename + silent `||` 短路拆 loud `comptimeError("for|while condition not compile-time known", id)`,与 do-while ddd327c 完全一致)+ **2 SUNSET marker 物理清**(line 12 for + line 72 while,sibling 子轮 phase 完结后 markers 不再需要)+ 2 新 spike doc-anchor `tests/phase5/comptime_{for,while}_unknown_error.ss.txt`(sibling do-while spike 完全一致 — bare IDENT cond 触 loud error)+ bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平 + sunset_linter 默认 30 markers GATE OK(-2 from 32)+ `--phase` 模式 verdict PASS "no cleanup needed";**扩容申报-step-7-实战-bump-fix**:本轮顺手补 95e0bab/d8a010b 漏 bump 历史遗留 — `F1:bootstrap/gen/gen_decls.ss` 745→750(95e0bab step 5b Phase 3 SUNSET markers ×5 加在 gen_decls.ss line 35/360/455/530/687 时漏申报,本轮 step 7 一并补 bump)
- **[x] step 7 配套 C2 (docs exit verify) Done at 609b465** — D170 协议**实战首例 C2 docs exit verify**(D170 §决策 C Manual gate 触发 + Exit 动作清单 §1 独立 commit 单子族 docs/ + §2 D093 add §Phase X §出口清单 段 + §3 commit footer `Phase X exit verify` 锚 + 标准「去掉少什么:」):D093 §下一步 sibling 子轮 [ ] Planned → [x] Done at b94dc8b + D093 add §Phase 1.5d 主轮收口子步 sibling 子轮 §出口清单 段(2 行 [clean] markers 引 b94dc8b)+ D093 §下一步 追加 1.5e+ helper 抽取 anchor(simplify Reuse F1 actionable 但延后)+ D170 §Status 含 step 7 完结 + D170 §下一步 step 7 C1 转 [x] Done + commit footer "Phase 1.5d 主轮收口子步 sibling 子轮 exit verify" + 回流主线已 fast-forward 完成(feat/d092-sema-q1 HEAD = b94dc8b);D170 协议**设计→工具→流程→实战四阶段全闭环 — 6 步序 + step 7 实战 完结**
- **[x] step 7 sibling 第二例应用 (C1 feat impl) Done at b0f8d12** — D093 §Phase 1.5e+ ext sibling 应用:`bootstrap/eval/pow_binary.ss` + `null_coalesce.ss` 重构三段式 sibling 完全一致(对齐 BINARY 主 case bb0f805 — eager unify lRaw/rRaw → 段 1 ct fold → 段 2 紧 loud → 段 3 runtime forward reg)+ `genNullCoalesce` 接口扩 `lPreReg/rPreReg: string = ""` 哨兵 + `genBinary` dispatch forward + **2 SUNSET marker 物理清**(pow_binary.ss:6 + null_coalesce.ss:6)+ 默认模式 sunset_linter GATE OK 30 markers(-1 net = -2 物理清 + 1 新 valType/inferType 混合 dispatch 加锚同 eval_expr.ss:116 sibling)+ bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平。sibling 应用模板复用 step 7 实战首例范式(C1 feat impl + C2 docs exit verify 拆 2 commit)
- **[x] step 7 sibling 第二例应用 (C2 docs exit verify) Done at f9360f9** — D170 协议 sibling 第二例 C2 docs exit verify(D170 §决策 C exit 动作清单 §2 sibling 应用):D093 §下一步 1.5e+ ext [x] Done at b0f8d12(已 b0f8d12 commit 同时落地)+ D093 add §Phase 1.5e+ ext §出口清单 段(2 行 [clean] markers 引 b0f8d12 + 默认模式 verify 路径替 manual gate `--phase X` — 两 path 均 D170 §决策 C 双轨触发设计预期内)+ commit footer "Phase 1.5e+ ext exit verify";D170 协议**实战首例 + 第二例 sibling 闭环** — phase exit verify 双轨(manual gate b94dc8b/609b465 + 默认模式 b0f8d12/f9360f9)均落地实战,sibling 应用模板可重复
- **[x] step 7 sibling 第三例应用 (C1 feat impl) Done at 2c1fb98** — D093 §Phase 1.5e+ later UNARY 反向编码统一 sibling 应用:`bootstrap/eval/eval_expr.ss` UNARY case `genVal(childId) + isCt(subRaw)==1 ? subRaw : (0-subRaw-1)` 反向编码 mv 空间散布 → 直接 `subMv = evalExpr(childId)` 单点 dispatch + line 27-38 注释 trim(去 genVal 桥转换说明)+ sibling 完全一致对齐 BINARY/POW/NULL_COALESCE 主 case 三段式终态;**evalExpr 加 4 leaf literal case prereq**(INT_LIT/TRUE_LIT/FALSE_LIT/GROUPING 直返 ctVal,委托内层 — sibling `gen/exprs/exprs.ss:62-67` genVal 同 case 对称)让 evalExpr 真正成 D093 §Zig 原理 §1 "唯一求值入口" 物理落地 — §字段 12 假设破裂方案修正实证(首版纯 swap 不加 leaf case → Stage 2 bootstrap 崩 `use of undefined value '%30'` Neg case → 回方案层加 prereq leaf case 让 swap 安全)+ **1 SUNSET marker 物理清**(eval_expr.ss:49)+ 默认模式 sunset_linter GATE OK 29 markers(-1 net = -1 物理清,evalExpr 4 leaf case 不带 marker ∵ 直返 ctVal 非过渡件)+ bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平。sibling 应用模板复用 step 7 实战首例 + 第二例范式(C1 feat impl + C2 docs exit verify 拆 2 commit)
- **[x] step 7 sibling 第三例应用 (C2 docs exit verify) Done at 6dbc2de** — D170 协议 sibling 第三例 C2 docs exit verify(D170 §决策 C exit 动作清单 §2 sibling 应用):D093 §下一步 1.5e+ later UNARY [x] Done at 2c1fb98 + D093 add §Phase 1.5e+ later UNARY 反向编码统一 §出口清单 段(1 行 [clean] marker 引 2c1fb98 + 默认模式 verify path — sibling 第二例同 path)+ §出口清单 段尾 D170 step 7 sibling 范式实战完结升级文字(2 sub-round → 3 sub-round 系列 + §字段 12 假设破裂方案修正作为 sibling 应用 robustness validator)+ commit footer "Phase 1.5e+ later UNARY 反向编码统一 exit verify";D170 协议**实战首例 + 第二例 + 第三例 sibling 闭环** — phase exit verify 双轨(manual gate b94dc8b/609b465 + 默认模式 b0f8d12/f9360f9 + 2c1fb98/6dbc2de)三轮均落地实战,sibling 应用模板可重复;**§字段 12 假设破裂方案修正**也作为 sibling 应用 robustness validator(首版照 next_prompt 字面 swap 不 prereq → spike 崩 → 回方案层加 prereq leaf case → swap 安全 — 后续 sibling 应用预期假设破裂入口)
- **[x] step 7 sibling 第四例应用 (C1 feat impl) Done at c233add** — D093 §Phase 1.5e+ later evalExpr 余下 leaf case 收口 sibling 应用:`bootstrap/eval/eval_expr.ss` 加余下 4 leaf literal case(STRING_LIT/NULL_LIT/DOUBLE_LIT/NAMED_ARG)直返 ctVal / 委托内层 sibling `gen/exprs/exprs.ss:62-67+83` genVal 同 case 对称 + 让 evalExpr 真正成 D093 §Zig 原理 §1 "唯一求值入口" 物理完整覆盖 leaf literal 集(8 leaf + GROUPING + NAMED_ARG = 10 case,除 THIS/SUPER/ARROW_FUNC ct-depth 特例外 SUNSET 标 Phase 4 留)+ **0 SUNSET marker 物理清**(4 leaf case 直返 ctVal 非过渡件)+ 默认模式 sunset_linter GATE OK 29 markers 持平 + bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平 + 跨 phase 安全 prereq(1.5f genVal 主 dispatch 降 thin wrapper 后 evalExpr 真单点入口必有完整 leaf case)。sibling 应用模板复用 step 7 实战首例 + 第二例 + 第三例范式(C1 feat impl + C2 docs exit verify 拆 2 commit);**0-marker sibling 应用首例**:第四例首次落地 NULL-marker §出口清单 段,拓展 sibling 应用模板的 "marker 物理清" 维度由 ≥1 marker 缩到 0 marker
- **[x] step 7 sibling 第四例应用 (C2 docs exit verify) Done at 90aba70** — D170 协议 sibling 第四例 C2 docs exit verify(D170 §决策 C exit 动作清单 §2 sibling 应用):D093 §下一步 1.5e+ later evalExpr 余下 leaf case 收口 [x] Done at c233add + D093 add §Phase 1.5e+ later evalExpr 余下 leaf case 收口 §出口清单 段(NULL marker 行 引 c233add + 默认模式 verify path — sibling 第二/三例同 path)+ §出口清单 段尾 D170 step 7 sibling 范式实战完结升级文字(3 sub-round → 4 sub-round 系列 + 0-marker sibling 应用首例 拓展 sibling 应用模板的 "marker 物理清" 维度)+ commit footer "Phase 1.5e+ later evalExpr 余下 leaf case 收口 exit verify";D170 协议**实战首例 + 第二例 + 第三例 + 第四例 sibling 闭环** — phase exit verify 双轨(manual gate b94dc8b/609b465 + 默认模式 b0f8d12/f9360f9 + 2c1fb98/6dbc2de + c233add/90aba70)四轮均落地实战,sibling 应用模板可重复;**0-marker sibling 应用首例**也作为 sibling 应用模板的 robustness validator(4 leaf case 直返 ctVal 非过渡件 → 0 SUNSET marker 物理清 → 默认模式 sunset_linter GATE OK 29 markers 持平 — 后续 sibling 应用预期 0-marker 形态 leaf-completeness 收口子轮)
- **[x] step 7 sibling 第五例应用 (C1 feat impl) Done at 21f8342** — D093 §Phase 4 起首 THIS/SUPER ct-depth 入口字面消除 sibling 应用:`bootstrap/eval/eval_expr.ss` 加 THIS/SUPER case 直返 ctVal(interpThisVal > 0 时 ctVal(interpThisVal) / comptimeMustBeKnown == 1 时 loud error `'X' not bound in comptime context` / 否则 OLD silent ctVal(interpNewNull()) 保 sibling 行为一致)+ `bootstrap/gen/exprs/exprs.ss:70-73` THIS/SUPER 入口 ct-depth 字面双轨 dispatch 退化 thin dispatch(`comptimeDepth > 0` 时 `const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1` sibling 完全一致 BINARY/UNARY 等 mv 反向编码 pattern + runtime 路径保 `constVal(genThisExpr())`)+ **1 SUNSET marker 物理清**(exprs.ss:71)+ 默认模式 sunset_linter GATE OK 28 markers(-1 net = -1 物理清,evalExpr 加 THIS/SUPER case 不带 marker ∵ 直接终态非过渡件)+ bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平。**Phase 4 sub-round 系列起手首例 spike** — sibling 第四例 c233add evalExpr leaf case 收口后,本轮 THIS/SUPER 入口 ct-depth 字面消除是 Phase 4 sub-round 系列**首例 spike**,验证 ct-depth 残余字面消除 sub-round 的 sibling 应用模板可跨 phase 复用(评估 evalExpr 加 case 直读 interpThisVal cross-module access 假设破裂入口 — spike 单 swap 后 bootstrap + 全测 + 三 linter 三验全过,假设无破裂)。sibling 应用模板复用 step 7 实战首例 + 第二/三/四例范式(C1 feat impl + C2 docs exit verify 拆 2 commit)
- **[x] step 7 sibling 第五例应用 (C2 docs exit verify) Done at 7d66eb4** — D170 协议 sibling 第五例 C2 docs exit verify(D170 §决策 C exit 动作清单 §2 sibling 应用):D093 §下一步 Phase 4 起首 THIS/SUPER [x] Done at 21f8342 + D093 §下一步 加 [ ] Planned Phase 4 余下 sub-round 系列 anchor(sunset_linter C3 PASS prereq — Phase 4 phase 还有未完成 sub-round ARROW_FUNC + genVal:84 + gen_methods.ss:258 + ct_driver:22/26 + interp_core:75 avoid C3 FAIL "Phase 4 [x] Done but markers remain")+ D093 add §Phase 4 起首 THIS/SUPER ct-depth 入口字面消除 §出口清单 段(1 marker 行 引 21f8342 + 默认模式 verify path — sibling 第二/三/四例同 path)+ §出口清单 段尾 D170 step 7 sibling 范式实战完结升级文字(4 sub-round → 5 sub-round 系列 + Phase 4 sub-round 系列起手首例首次跨入 Phase 4 sub-round 系列拓展 sibling 应用模板跨 phase 复用维度)+ commit footer "Phase 4 起首 THIS/SUPER ct-depth 入口字面消除 exit verify";D170 协议**实战首例 + 第二例 + 第三例 + 第四例 + 第五例 sibling 闭环** — phase exit verify 双轨(manual gate b94dc8b/609b465 + 默认模式 b0f8d12/f9360f9 + 2c1fb98/6dbc2de + c233add/90aba70 + 21f8342/7d66eb4)五轮均落地实战,sibling 应用模板可重复;**Phase 4 sub-round 系列起手首例**也作为 sibling 应用模板的跨 phase 复用 robustness validator(前四例皆 1.5d/1.5e+ scope,第五例首次跨入 Phase 4 sub-round 系列 — 后续 ARROW_FUNC + genVal:84 + ct_driver/interp_core/gen_methods 等余下 SUNSET marker 系列接续)
- **[x] step 7 sibling 第六例应用 (C1 feat impl) Done at 33c65e2** — D093 §Phase 4 续 ARROW_FUNC ct-depth 入口字面消除 sibling 应用:`bootstrap/eval/eval_expr.ss` 加 ARROW_FUNC case 直返 `ctVal(interpNewVal("fn", \`${astId}\`))` — 直构造 ct value 无外部状态依赖,sibling c233add 第四例 leaf case 直返 ctVal 同形单行 case(sibling 21f8342 多态 case 不适用 ∵ interpNewVal 永远成功无 loud-error path 需求)+ `bootstrap/gen/exprs/exprs.ss:74-77` ARROW_FUNC 入口 ct-depth 字面双轨 dispatch 退化 thin dispatch(`comptimeDepth > 0` 时 `const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1` sibling 完全一致 THIS/SUPER 21f8342 + BINARY/UNARY 等 mv 反向编码 pattern + runtime 路径保 `constVal(genArrowFunc(id))`)+ **1 SUNSET marker 物理清**(exprs.ss:75)+ 默认模式 sunset_linter GATE OK 27 markers(-1 net = -1 物理清,evalExpr 加 ARROW_FUNC case 不带 marker ∵ 直接终态非过渡件)+ bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平。**Phase 4 sub-round 系列第二例 spike** — sibling 第五例 21f8342 Phase 4 起首 THIS/SUPER 起手后,本轮 ARROW_FUNC 入口 ct-depth 字面消除是 Phase 4 sub-round 系列**第二例 spike**,验证 ct-depth 残余字面消除 sub-round 的 sibling 应用模板可在 Phase 4 内部多次复用(评估 ARROW_FUNC 入口 interpNewVal 直构造 ct value 无外部状态依赖假设破裂入口 — spike 单 swap 后 bootstrap + 全测 + 三 linter 三验全过,假设无破裂)。sibling 应用模板复用 step 7 实战首例 + 第二/三/四/五例范式(C1 feat impl + C2 docs exit verify 拆 2 commit)
- **[x] step 7 sibling 第六例应用 (C2 docs exit verify) Done at 7c0bbcf** — D170 协议 sibling 第六例 C2 docs exit verify(D170 §决策 C exit 动作清单 §2 sibling 应用):D093 §下一步 Phase 4 续 ARROW_FUNC [x] Done at 33c65e2 + D093 add §Phase 4 续 ARROW_FUNC ct-depth 入口字面消除 §出口清单 段(1 marker 行 引 33c65e2 + 默认模式 verify path — sibling 第二/三/四/五例同 path)+ §出口清单 段尾 D170 step 7 sibling 范式实战完结升级文字(5 sub-round → 6 sub-round 系列 + Phase 4 sub-round 系列第二例同 phase 接力 — D170 协议 sibling 应用模板 Phase 内复用 robustness 跨 sub-round 累计验证)+ commit footer "Phase 4 续 ARROW_FUNC ct-depth 入口字面消除 exit verify";D170 协议**实战首例 + 第二例 + 第三例 + 第四例 + 第五例 + 第六例 sibling 闭环** — phase exit verify 双轨(manual gate b94dc8b/609b465 + 默认模式 b0f8d12/f9360f9 + 2c1fb98/6dbc2de + c233add/90aba70 + 21f8342/7d66eb4 + 33c65e2/7c0bbcf)六轮均落地实战,sibling 应用模板可重复;**Phase 4 sub-round 系列第二例**也作为 sibling 应用模板的 Phase 内多 sub-round 复用 robustness validator(前五例 4×1.5d/1.5e+ + 1× Phase 4 起首,第六例首次 Phase 4 内同 phase 接力 — 后续 genVal:84 主 dispatch ct-depth + ct_driver/interp_core/gen_methods 等余下 SUNSET marker 系列接续)
- **[x] step 7 sibling 第七例应用 (C1 feat impl) Done at 060e4e4** — D093 §Phase 4 续 genVal 主 dispatch 入口 ct-depth 字面消除 sibling 应用:`bootstrap/eval/eval_expr.ss` 加 COMPTIME_EMIT case `comptimeSS = \`${comptimeSS}${interpAsStr(valOf(ctEmitMv))}\`` cross-module side-effect 直写(sibling THIS/SUPER 21f8342 interpThisVal cross-module access 模板复用 — interp_core.ss:79 全局 `let comptimeSS = ""` 可跨 eval 子模块直读/写)+ 加 TYPEINFO_EXPR case 直返 `ctVal(interpBuildTypeInfo(nGetS1(astId)))` 单态直构(sibling ARROW_FUNC 33c65e2 interpNewVal 同模板)+ 加 unsupported 兜底 BINARY 主 case 之前 kind 白名单守门(`if (k != "BINARY") { if (comptimeMustBeKnown == 1) loud error else silent null }` — sibling THIS/SUPER 21f8342 loud-error path 模板;§字段 12 假设破裂方案修正 prereq 防 unsupported kind fall-through 到 BINARY ct path 致 corrupt)+ `bootstrap/gen/exprs/exprs.ss:79-92` genVal 主 dispatch 入口 ct-depth 字面双轨 dispatch 整段退化 thin dispatch(14 行整段删替换为 `const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1` sibling 完全一致 mv 反向编码 pattern 走 evalExpr 主 case 兜底)+ **1 SUNSET marker 物理清**(exprs.ss:79)+ 默认模式 sunset_linter GATE OK 26 markers(-1 net = -1 物理清,evalExpr 加 3 case 不带 marker ∵ 直接终态非过渡件)+ bootstrap 三阶段固定点 verified + 全测 baseline 334/3 持平。**Phase 4 sub-round 系列第三例 spike** — sibling 第五例 21f8342 Phase 4 起首 + 第六例 33c65e2 ARROW_FUNC 接力后,本轮 genVal 主 dispatch 入口 ct-depth 字面消除是 Phase 4 sub-round 系列**第三例 spike**,验证 ct-depth 残余字面消除 sub-round 的 sibling 应用模板可在 Phase 4 内部多 sub-round 复用(评估 COMPTIME_EMIT cross-module side-effect + TYPEINFO_EXPR 直构 + unsupported 兜底 三 case 同时迁假设破裂入口 — 一次性 swap 后 bootstrap + 全测 + 三 linter 三验全过,假设无破裂)。sibling 应用模板复用 step 7 实战首例 + 第二/三/四/五/六例范式(C1 feat impl + C2 docs exit verify 拆 2 commit)
- **[x] step 7 sibling 第七例应用 (C2 docs exit verify) Done at 5118424** — D170 协议 sibling 第七例 C2 docs exit verify(D170 §决策 C exit 动作清单 §2 sibling 应用):D093 §下一步 Phase 4 续 genVal 主 dispatch [x] Done at 060e4e4 + D093 add §Phase 4 续 genVal 主 dispatch 入口 ct-depth 字面消除 §出口清单 段(1 marker 行 引 060e4e4 + 默认模式 verify path — sibling 第二/三/四/五/六例同 path)+ §出口清单 段尾 D170 step 7 sibling 范式实战完结升级文字(6 sub-round → 7 sub-round 系列 + Phase 4 sub-round 系列第三例同 phase 接力 — D170 协议 sibling 应用模板 Phase 内复用 robustness 跨 sub-round 累计验证升级)+ commit footer "Phase 4 续 genVal 主 dispatch 入口 ct-depth 字面消除 exit verify";D170 协议**实战首例 + 第二例 + 第三例 + 第四例 + 第五例 + 第六例 + 第七例 sibling 闭环** — phase exit verify 双轨(manual gate b94dc8b/609b465 + 默认模式 b0f8d12/f9360f9 + 2c1fb98/6dbc2de + c233add/90aba70 + 21f8342/7d66eb4 + 33c65e2/7c0bbcf + 060e4e4/5118424)七轮均落地实战,sibling 应用模板可重复;**Phase 4 sub-round 系列第三例**也作为 sibling 应用模板的 Phase 内多 sub-round 复用 robustness validator(sibling 第五/六/七例同 phase 接力 — 后续 gen_methods.ss:258 + ct_driver:22/26 + interp_core:75 等余下 SUNSET marker 系列 + 1.5f genVal 主 dispatch 降 thin wrapper 主轮收口接续)
- **[x] step 8 协议 scope 扩 spec 落档 Done at 5e9bb16** — 实战首例后元-level 自审改进(audit-driven scope reflection):用户连续两次 ultrathink 拷问"历史上有很多 SUNSET 需要标注吧"+"应该改进流程吧"→ Claude 反思根因 = **漏标 N 处是症状,协议自身 scope 设计偏窄是病因**(CLAUDE.md §Root Cause 第一法则:根因方案 vs workaround → 选根因)。本 commit 落档:**§决策 A 扩 3 亚类**(A.1 SUNSET 域内 PERMANENT 子残留 + A.2 协议自循环 + A.3 D 文档反向锚)+ **§决策 B 扩 C5-C9 软警告**(C5 D 文档反向锚 / C6 协议自循环 / C7 接口默认参数哨兵 / C8 英文模式扩 / C9 IR-emit-side TODO — 实施留 step 9)+ **§历史语境 加 audit 续段**(6 类协议 scope 设计盲点表 + 实战首例验证机制 sibling 模板 + 实证完结里程碑)+ **sunset_linter.ss 顶端示范自循环 SUNSET 锚**(A.2 自循环约束就近落地避递归)+ **D093 §下一步 line 310 1.5d 剩余 prereq [~] In Progress → [x] Done at b94dc8b**(整段达成 §0.3 Phase 1 验收 5 项 ∵ 主轮收口子步 sibling 子轮 b94dc8b 完结)。**协议 v0.1 → v0.2 升级期形态固化**(业界对标 Rust cargo deprecate-check 同模式)
- **[x] Done at 27f4214** step 9 (a) C5/C6/C8/C9 sunset_linter 实施 — `tools/sunset_linter.ss` 扩 4 软警告 grep(C7 留 v0.2 升级路径:spike 实证 100% 假阳需 callsite 判定升级 spec 段)+ `--audit` flag(默认输出 N candidates 汇总,audit 详情 file:line)+ 默认 scan 加 `docs/3-decisions/` + scanFile 加 D 文档不作 SUNSET marker 携带方 skip(D170 §决策 A.2 SSoT 不当 marker 携带方)+ 4 spike test doc-anchor `tests/d170_sunset_marker_protocol/sunset_linter_c{5,6,8,9}*.ss.txt` + 顺手 fix 2 stale anchor (positive_legal + phase_exit_active_pass anchor stale `1.5d 主轮收口子步 sibling 子轮` 已 [x] Done at b94dc8b → 升级 `1.5e+ helper 抽取`) + D170 §决策 B C7 行 spec 升级路径段 + D170 hash 回填 step 8 `5e9bb16`。**实测**:默认模式 31 markers GATE OK(30 bootstrap + 1 tools)+ C5 220 candidates / C6 6 / C8 43 / C9 3 全软警告汇总输出 + bootstrap 三阶段固定点 verified + 全测 baseline 持平 + 三 linter GATE OK
- **[x] Done at ef47996** step 9 (b.1) sub-context grep 精化 — step 9 (a) C5/C6 实测 222 + 6 候选,头 10 spike 实证 **10/10 假阳**(全在 `### Phase X [x] Done at hash` heading sub-bullet / 顶级 `[x] Done` list-item / `[ ] Pending at commit \`hash\`` 非规范 status / 表格 `[✓ Done at` cell)→ prompt §字段 12 触发"改方案先扩 C5 grep 精化"分支:`tools/sunset_linter.ss` scanFile 加 **三 sub-pattern 分流**:(1) **Done 段 skip**(### Phase X [x]/[✓] Done at hash + heading 含 `at commit \`hash\`` + 顶级 `- **[x] Done` list-item + `- 2026-` Status 时间线 + 表格 cell `[✓` / `Done at ` / `at commit \``)+(2) **Planned 段 keep**(### / 顶级 list-item [ ] Planned / [~] In Progress / [ ] Blocked)+(3) **spec/narrative 段 skip**(## A.2 / ## §A.2 隐藏假设 + ## 决策 + ## 历史语境 + ## 与现有机制关系 + ## 拒绝准则 + ## 第一性需求)+ **indent-aware**(top-level `- **[X]` 无 indent 改 state;indented `  - **[X]` sub-bullet 继承 parent state — D093 §下一步 sub-round 范式)+ **per-line override**(行内含 Done marker 跳行);更新 C5/C6 spike test fixture comment 反映精化效果 + 加新 spike `sunset_linter_c5c6_subcontext_skip.ss.txt`(三 sub-pattern 5 反/正证 shell verify);D170 §6 步序表 step 9 (b) 拆 (b.1) Implementation/精化 + (b.2) Backfill 两行 + step 9 (a) hash 回填 `27f4214`。**实测**:C5 222 → 43 (-81%) + C6 6 → 0 + C8 43 / C9 3 不动(.ss 源码 sub-context 模式不适用)+ 默认模式 31 markers GATE OK + bootstrap 三阶段固定点 verified + 全测 334/3 baseline 持平 + 三 linter GATE OK(sunset / d_doc / next_prompt 全 PASS)
- **[x] Done at ad9ced8** step 9 (b.2.1) audit-driven v2 精化 — `tools/sunset_linter.ss scanFile` 由 b.1 黑名单 spec H2 反转为 b.2 白名单 active commit 严控,五 sub-pattern 分流(`inActiveCommitSection` 白名单 + `inCommitListItem` list-item 限定 + `isTableCell` skip + H3/H4 Plan 段 skip + paren-style `(Planned)` 扩);**实测** C5 43 → 1 (-97.7%) + C6 0 维持 + 默认 31 markers GATE OK + bootstrap 三阶段固定点 + 全测 baseline + 三 linter PASS;+ 加 spike test `sunset_linter_c5_subcontext_v2_skip.ss.txt`(1 正证 D154:522 keep + 5 反证 §A.1/§A.3/table cell/4-space narrative/paragraph wrap-up/H4 Plan 段 skip)+ 更新 b.1 fixture 过期正证(D170:299/301 paragraph 已 b.2 skip → D154:522 list-item 作新正证)+ D170 §决策 B C5 行 v2 升级路径段 + §6 步序表 step 9 (b.2) 拆 (b.2.1) v2 精化 + (b.2.2) backfill + D170 hash 回填 step 9 (b.1) `ef47996`
- **[ ] Planned** Phase 2+ 优化 — `tools/sunset_linter.ss` 与 `tools/d_doc_index_linter.ss` 共享 D 文档实存判 helper(D170 §与现有机制关系 line 133 锚 + `tools/sunset_linter.ss:3` SUNSET 反向锚 — A.2 自循环示范);step 9 工具实施轮已完结协议 v0.2 形态最终固化,helper 共享归 Phase 2+ 优化 future scope(双 linter 各自稳定 + 跨工具 helper 抽取属优化非主线 scope)
- **[x] Done at 6432f92** step 9 (b.2.2) audit-driven backfill — v2 精化 (b.2.1) 完结后 **1 C5 + 0 C6 真候选**(D154:522 唯一)audit decision 三选一 (MNK §字段 10 (e)):(a) sunset_linter 加第 6 sub-pattern hash-backfill 元规则 skip / (b) lib/com/mysql/ 加反向锚(不适用 — driver class 12/12 落地无过渡件)/ (c) D154 §下一步 改写删 hash 回填承诺(破坏 D135-D153 sibling 范式 hash trail 一致性) — **选 (a) 因根因解决度最高**(工具机械化协议 scope 边界永久零返工 + 长久演化对标 Rust cargo deprecate-check v0.1→v0.2 升级期同模式);`tools/sunset_linter.ss scanFile` 加 `isHashBackfillMetaLine` helper(同行含 `commit hash` + `回填` 双 substring OR `hash 回填` 紧贴 token → skip — D135-D153 sibling 范式 "单 commit 不能引用自己 hash 下下轮回填" D 文档元规则话术非 SUNSET 协议 scope;D154:522 audit-driven 唯一真候选 false positive + sibling D149:328/367 + D135:169/198 + D136:176 list-item 同模式批量 skip)+ 加 spike test `sunset_linter_c5_hash_backfill_skip.ss.txt`(1 正证 D154:522 skip + 4 反证 D149:328/367 + D135:169/198 + D136:176 sibling list-item hash-backfill 同模式 0 candidate + 1 累计 C5=0 验收)+ D170 §决策 B C5 行 v0.2 形态最终固化段 + §6 步序表 step 9 (b.2.1) hash 回填 `ad9ced8` + §下一步 step 9 (b.1) hash 回填 `ef47996`(b.2.1 commit 时漏 backfill 顺手补)。**实测**:**C5 1 → 0(-100% 真候选最终固化 + 100% 真阳率最终态)** + D154:522 skip + 默认 31 markers GATE OK + bootstrap 三阶段固定点 + 全测 baseline + 三 linter PASS;**协议 v0.1 → v0.2 升级期九阶段全闭环 + 形态最终固化**(设计→工具→流程→实战→scope 扩 spec → C5-C9 工具实施→ sub-context grep 精化→ audit-driven v2 精化→ audit-driven backfill — sibling D097 拆 commit 模板各独立审查窗口)

**回流到 `feat/d092-sema-q1`**:6 步完结后,本分支 rebase / merge 回主线;之后 1.5d sibling 子轮 (for/while 迁) 直接用 SUNSET marker 取代自然语言「留 X+」首批落地。step 7 实战已落地 — C1 feat impl `b94dc8b` + C2 docs exit verify `609b465`;**已 fast-forward 回 feat/d092-sema-q1 主线(merge-base = d092-sema-q1 tip = ddd327c,7 commit 一气 merge)**,本协议 6 步序 + step 7 实战 全闭环;step 8 scope 扩 spec 落档 (`5e9bb16`) + step 9 (a) C5/C6/C8/C9 工具实施 (`27f4214`) + step 9 (b.1) sub-context grep 精化 (`ef47996`) + step 9 (b.2.1) audit-driven v2 精化 (`ad9ced8`) + step 9 (b.2.2) audit-driven backfill(`6432f92`)**全 9 step 序闭环 + 协议 v0.2 形态最终固化** — 协议 v0.1 → v0.2 升级期九阶段全闭环完结,D154:522 唯一真候选 audit-driven false positive 已机械化 skip,后续 D 文档 hash trail sibling 范式自动同模式不触假阳累积。

**D170 协议完结**(2026-05-23):设计 (Phase 0)→ 工具 (step 2)→ 流程 (step 3-4)→ Backfill (step 5a/5b/6,32 markers 全库 + Phase Exit Gate manual gate 落地)→ 实战 (step 7,D093 §Phase 1.5d sibling 子轮 首例 + verdict PASS)→ scope 扩 spec 落档 (step 8 `5e9bb16` — §决策 A 扩 3 亚类 + §决策 B 扩 C5-C9 软警告 + §历史语境 audit 续段)→ **C5/C6/C8/C9 工具实施 (step 9 (a) `27f4214` — 4 软警告 grep + `--audit` flag + 4 spike doc-anchor + C7 留 v0.2 升级路径)→ sub-context grep 精化 (step 9 (b.1) `ef47996` — 三 sub-pattern 分流 + indent-aware + per-line override + 222 → 43 / 6 → 0)→ audit-driven v2 精化 (step 9 (b.2.1) `ad9ced8` — 白名单反转黑名单 + list-item 限定 + table cell + 4-space narrative + paren-style status 五 sub-pattern + 43 → 1 / 0 维持 / 100% 真阳率)→ audit-driven backfill (step 9 (b.2.2),`6432f92` — 第 6 sub-pattern `isHashBackfillMetaLine` hash-backfill 元规则 skip + 1 → 0 真候选最终固化 + MNK §字段 10 (e) 三选一选 (a) 工具机械化协议 scope 边界因根因解决度最高 + D135-D153 sibling list-item 同模式批量 skip) — 协议 v0.1 → v0.2 升级期九阶段全闭环 + 形态最终固化**;audit-driven false positive 已机械化 skip(D154:522 唯一真候选),后续 D 文档 hash trail sibling 范式自动同模式不触假阳累积;sibling D097 拆 commit 模板 — decision spec → linter 实现 → pattern 精化 → v2 精化 → backfill 各独立审查窗口;详细 step 序见 §下一步 / §6 步序。
