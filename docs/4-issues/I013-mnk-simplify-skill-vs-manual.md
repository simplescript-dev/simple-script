# I013 — MNK §After Done §1 simplify skill vs 手动审等价性

**父决策:** `docs/3-MNK.md` §After Done §1 代码审查
**状态:** Draft
**颗粒度:** ~3 千 token
**创建:** 2026-04-24
**立项由:** D123 Phase 1 本轮 MNK §After Done §2 流程反思候选 4(Ok 三态 → 立项下轮)

## 上下文

MNK §After Done §1 要求"对本轮新增 / 修改的代码做 `/simplify`,修复发现的问题";但未明确:

- 手动走 4 维度(reuse / quality / efficiency / readability)审查,与 `/simplify` skill invoke(launches multi-agent review)是否等价?
- 小 scope(LOC ≤ 50 单文件 / 单族)场景下,手动精准审是否可代替 skill?还是必须一律跑 skill?

D123 Phase 1 本轮新增 ~55 LOC(4 文件),手动 4 维度审无建议,commit message 按 §simplify 采纳/拒绝记账"无建议不写记账行"合规跳过 — 但 MNK 未显式背书此路径。

## 范围

- `docs/3-MNK.md` §After Done §1:补一行"小 scope 判据 + 手动等价门槛"
- `docs/3-MNK.md` §改动分层表:若微改豁免但标准改未覆盖此场景,补档位内分档
- 术语扩展扫描(§M §字段 5 SSoT 义务):`grep -rn "/simplify\|simplify skill" CLAUDE.md docs/` 核对外链

## 推荐方向(待 PSM 扩容后锁定)

两方案待审:

- **A (宽松)**:LOC ≤ 50 + 1 族 + 单轮 Execute 型 → 手动 4 维度审可代替 skill;记账格式不变(无建议不写)
- **B (严格)**:所有标准改 / 大改必跑 `/simplify` skill,哪怕 LOC 低;手动审只对微改豁免场景背书

推荐 A:skill invoke 消耗 token 且 multi-agent 串跑耗时,小 scope 精准手动审等价且低成本。但需显式背书避免"Claude 跳 skill 偷懒"漂移。

## 步骤

1. PSM 填表(本 issue 是 SSoT 术语规则改动,必须走九问全 + §字段 5 术语扫描)
2. 决定 A / B 方向
3. Edit `docs/3-MNK.md` §After Done §1 加一行
4. 检查 `CLAUDE.md` §项目技术规则是否有外链需同步
5. VCM 六验全

## 反向

不做 → 后续 Claude 对"手动 vs skill"判断漂移,可能:
(a) 小 scope 也一律跑 skill → token 浪费
(b) 偷懒不跑任何审查 → 本条 MNK 规则名存实亡

## 验收 RED 命令

```bash
grep -c "simplify.*手动\|手动.*simplify" docs/3-MNK.md
# Draft 时 = 0;完成后 ≥ 1
```

## 备注

- 立项由 D123 Phase 1 本轮反思候选 4 → Ok 三态 → 因改 MNK SSoT 需独立 PSM(字段 5 术语扫描义务),不同轮落位 → 立项下轮独立处理
- 颗粒度估计 LOC 5-10 行 + D123 Phase 1 commit 后续独立 commit,轻量
