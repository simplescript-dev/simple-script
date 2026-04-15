# D[NNN]: [短描述性标题]

**Status:** [draft | Phase X 进行中 | firm]
**Depends on:** [其他 D 文档，无则填 None]
**Date:** YYYY-MM-DD
**Last Updated:** YYYY-MM-DD

---

## 模板使用说明（写完决策后删除本节）

本模板按 Harness Engineering 6 维度组织，目的是让 **clear 后的 Claude 读完顶部 1 屏就能直接开干**，而不需要刷整个文档。

写作原则：
- **顶部稳定，附录变化**（Raschka stable prefix + cache reuse）
- **每个维度都要回答"开干前/开干中/开干后该做什么、不该做什么"**
- 用 `N/A — <理由>` 而不是默认省略
- 代码引用必须带文件路径 + 行号
- 命令必须可复制粘贴执行
- 表格优于段落（密度高，扫读快）
- 中文叙述，技术名词保留英文

参考：
- Martin Fowler / Birgitta Böckeler — https://martinfowler.com/articles/harness-engineering.html
- Anthropic — https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents

---

## 核心目标 (Goal)

- **为什么**：[问题 / 痛点，1-2 句]
- **是什么**：[解决方案的核心机制，1-2 句]
- **单一判据**：[可立即验证的成功条件]

> [可选：一句口号，提炼判据]

---

## 核心原则 (Principles)

[5-7 条，每条一句话，捕捉本决策的设计哲学。这些是后续所有 Phase / Step 的判断依据。]

1. **[原则名]** — [一句话解释]
2. ...

---

## 1. Context Management（上下文管理）

> clear 后的 Claude 动手前 5 分钟内必须加载完本节内容。

### 必读清单（按顺序）

1. 本文档
2. `CLAUDE.md`
3. 依赖的 D 文档
4. 关键代码位置：

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `path/to/file.ss` | 行号 | [一句话角色] |

5. 相关 commit hash：
   - `XXXXXXX` [简短描述]

### Stable Facts（Live Repo Context）

| 项 | 值 |
|---|---|
| 当前阶段 | [Phase X / Step Y] |
| 测试基线 | [N 个测试通过] |
| 入口命令 | [bootstrap / 测试 / build 命令] |
| 关键计数 | [被改的调用点数等] |

### 禁止的 Context 操作

- ❌ [明确禁止读什么、扫什么]

---

## 2. Tool System（工具系统）

### 必备工具（已在环境中）

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| Claude 内置 | `Read` / `Edit` / `Grep` / `Glob` / `Bash` | [文件操作、搜索] |
| 项目专属 | `[项目命令]` | [用途] |
| 验证 | `[验证命令]` | [用途] |

### 外部依赖（系统级，不动）

[列出但不要修改的依赖]

### 禁止引入

- ❌ [新依赖、新关键字、新工具]

---

## 3. Execution Orchestration（执行编排）

### 总体节奏

- [Phase / Step 划分]
- [每步独立 commit + 验证 = 硬约束]
- [禁止"边迁移边重构"]

### 单 Step 内的循环（硬约束）

```
1. Read    [读取的文件]
2. Edit    [改的内容]
3. Bash    [验证命令] (耗时)
4. 失败    → 看错误 → 修 → 回 step 3
5. Bash    [全量测试]
6. 全绿    → /simplify → git commit
7. 失败    → git reset --soft HEAD^ → 回 step 2
```

### Step 详细

#### Step 1: [简短名称]

- [具体待迁移 / 待改的列表]
- **验证**：[bootstrap + 测试 + 其他]

#### Step 2: ...

### 反模式

- ❌ [大爆炸合并步骤]
- ❌ [混入无关重构]

---

## 4. State & Memory（状态与记忆）

### 编译时 / 运行时 state

| 变量 | 文件 | 角色 |
|---|---|---|
| `[变量名]` | `[文件]` | [角色] |

### 中间产物

- [构建中间文件位置]
- [验证规则：固定点 / 二进制对比等]

### 会话间持久化（clear 后还在的）

- `git log` — 进度真相源
- **本文档** — 唯一计划/状态记录
- [测试集 / 二进制 / 其他]

### 禁止 state 操作

- ❌ 写 `next-prompt.md` / `handoff.md` / `notes.md`
- ❌ amend 已 push commit
- ❌ 把状态写到对话 / 本文档 / git 之外

---

## 5. Evaluation & Observation（评估与观测）

### N 个判据（每 Step 完成必跑）

| # | 类型 | 命令 / 检查 | 通过条件 |
|---|---|---|---|
| 1 | 架构判据（人工） | [人工 review 问题] | [是 / 否] |
| 2 | 工程判据（命令） | `[构建命令]` | [固定点通过] |
| 3 | 测试判据（命令） | `[测试命令]` | [全通过] |
| 4 | 收敛判据（命令） | `[grep / count]` | [0 命中 / N 等] |

### 回归信号（任一出现 = 立即停下）

- ⚠ [明确的失败信号 1]
- ⚠ [失败信号 2]

### 可选 spot check 命令

```bash
# [诊断命令 + 期望输出]
```

---

## 6. Constraints & Recovery（约束与恢复）

### 硬约束（违反 = 立即回滚）

- [来自 CLAUDE.md / user feedback / 项目原则的硬规则]

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| `[失败信号]` | `[恢复命令 / 思路]` |

### 回滚策略

- 任何 Step 失败 → `git reset --soft HEAD^`
- 禁止"先 commit 再修"
- 跨 Phase 回滚需先和用户确认（Phase 边界是稳定锚点）

### 升级判据（Anthropic "每升级模型必拆 harness"）

模型升级时本文档需要复审：
- "禁止" 列表是否还成立？
- "约束与恢复" 是否过度防御？
- 删除已不必要的 scaffolding

---

# 附录 A: 决策细节

## A.1 问题

[详细问题陈述，可包含代码示例]

## A.2 决策

[详细决策内容，包括：
- 数据结构设计
- 接口签名
- 设计取舍
- 代码示例
]

## A.3 [其他子节...]

---

# 附录 B: 实施日志

### Phase 0: [名称] [✅ / ⏳]

- [实施记录]
- **验证**：[bootstrap + 测试结果]

### Phase 1: ...

---

## 反模式 / 正模式（历史归纳）

### ❌ 反模式
- [已知的错误做法]

### ✅ 正模式
- [已验证的正确做法]

---

## 参考

- 外部链接（论文 / 博客 / 开源实现）
- 相关 D 文档
- commit hash
