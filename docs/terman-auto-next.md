# Terman 下轮提示词自动注入

> 用户在 terman session 中运行 Claude Code。当前轮结束时，把下轮提示词写进文件，
> 触发脚本 → 自动 `/clear` + 粘贴 + 回车，进入下一轮。Claude 自己不执行这一步，
> 由用户（或用户的自动化）触发。

## 判断是否在 terman session

```bash
echo $TERMAN_NAME    # 非空 = 在 terman session 内；为空 = 脚本会报错
```

环境变量由 terman 进入 session 时注入：`TERMAN=1`、`TERMAN_ID=<uuid>`、`TERMAN_NAME=<session-name>`。

## 脚本与用法

脚本：`tools/send_next.ss`

```bash
bin/ss run tools/send_next.ss <prompt-file>
# 示例
bin/ss run tools/send_next.ss .claude/next_prompt.md
```

## 执行流程

1. **Phase 1 — /clear**：`terman send $TERMAN_NAME '/clear'` + Enter，清空当前 Claude 上下文。
2. **Phase 2 — bracketed paste 注入**：用 `ESC[200~ ... ESC[201~` 包裹 prompt 文本发给 terminal。
   TUI（ink / Claude Code）把其中的 `\n` 当字面换行保留，不会在每行触发提交。
3. **Phase 3 — 30s 观察窗口**：prompt 已经显示在输入框但**还没提交**，你有 30s 审阅文本；
   Ctrl+C 可中断脚本，prompt 留在输入框里由你手动决定下一步。
4. **Phase 4 — Enter**：30s 过后自动发回车，提交 prompt，新一轮开始。

若 Claude Code 不支持 bracketed paste，把脚本顶部 `USE_BRACKETED_PASTE` 改为 `0`，
回退到反斜杠续行模式（`\n` → `\<newline>`）。

## 与 handoff 规则的关系

- **每轮必做(默认动作,不是可选)**：Claude 把本轮结尾的下轮提示词**同时**
  输出到对话**和**覆盖写入 `.claude/next_prompt.md`,两处内容严格一致。
  这是 §收尾 gate 步骤 3 的强制动作,理由见 `feedback_dual_output_next_prompt`:
  - 对话显示 → 用户审阅措辞,发现问题可以修;脚本 30s 观察窗口期间可 Ctrl+C 中断
  - 文件写入 → 用户跑 `bin/ss run tools/send_next.ss .claude/next_prompt.md` 一键触发下轮,
    省掉"复制对话文本 → 粘贴到新一轮输入框"的手动环节
  两路是 UX 的一对,缺一套都破坏工作流,不要只做其中一路。
- **仍然禁止**：用 handoff 文件做跨轮**状态累积** / 进度摘要。
  Phase 进度只写在 `docs/3-decisions/D0NN-*.md`,不写进 `.claude/next_prompt.md`。
  每轮用 `.claude/next_prompt.md` 时**覆盖写**,不追加,不保留历史 —— 它是单次 payload 不是日志。
- `.claude/next_prompt.md` 的定位:**单次 payload**,生命周期 = 从 Claude 写入 → 用户执行 send_next.ss → 下一轮启动。下一轮启动后该文件即失效,内容参考价值等于零(但**不删除**,等下一轮 Claude 再覆盖写入)。

## 相关文件

- `tools/send_next.ss` — 注入脚本本体
- `.claude/next_prompt.md` — 集成测试用的 prompt 文件（可被覆盖）
- `$TERMAN_NAME` — 脚本必读环境变量
