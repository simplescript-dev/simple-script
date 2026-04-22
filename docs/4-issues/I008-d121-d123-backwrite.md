# I008 — D121 R2-A / D123 §A.2.5 决策回写

**父决策:** D123 §C.5 层 A 翻案 第 9 项
**状态:** Draft
**颗粒度:** ~5 千 token
**依赖:** I001-I007 全部 Done(否则回写依据不全)
**创建:** 2026-04-22

## 上下文

D121 R2-A 原决策 "annotation 参数用 COLON" 被 user turn 5 推翻。
D123 §A.2.5 原决策 "COLON as syntax translation" 同被推翻。
需回写两处历史决策,避免后人读时按旧方案实施做重复工。

## 范围

- `docs/3-decisions/D121-*.md` §R2-A:
  - 状态改 `[REVERSED 2026-04-22]`
  - 补一行链接到 D127(或 D121 R3 扩展)和 I001-I007
- `docs/3-decisions/D123-spring-boot-replication.md` §A.2.5:
  - 选项 1:整段重写,反映新 ASSIGN 方向
  - 选项 2:标 `[SUPERSEDED 2026-04-22 by §C.5 + D127]`,保留原文以备 audit

## 推荐

**D121 R2-A**:标 `REVERSED`(保留 COLON 原方案作为"备选 C - 已拒绝"的历史证据)
**D123 §A.2.5**:标 `SUPERSEDED`,链接 §C.5 + I001-I007 / D127

理由:历史决策的"为何拒绝"本身是 D 文档的审计价值,不应直接覆盖。

## 步骤

1. 等 I001-I007 全部 Done,最终 ASSIGN + 值类型方案已落地
2. Edit D121 R2-A 状态行 + 补链接
3. Edit D123 §A.2.5 标注 SUPERSEDED + 补链接
4. 新 D127 末尾补 "D121 R2-A / D123 §A.2.5 已反向 / 被替代,详见各文件状态行"

## 反向

不做 → 未来后人读 D121 / D123 时按旧 COLON 实施,做重复工 → 文档债

## 验收 RED 命令

```bash
grep -n "REVERSED\|SUPERSEDED" docs/3-decisions/D121*.md docs/3-decisions/D123*.md
# 必有至少 2 条匹配
```

## 备注

- 此 issue 最后做(I001-I007 全 Done 后)
- 回写仅**标记**,不删除原文
- 若 I002 决策采"扩 D121 R3/R4"而非"新建 D127",则本 issue 的链接目标相应调整
