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

- **允许**：Claude 把本轮结尾的下轮提示词同时输出到对话**和**写入 `.claude/next_prompt.md`，
  供用户运行 `send_next.ss` 一键注入下一轮。两条路径的 payload 应**一致**。
- **仍然禁止**：用 handoff 文件做跨轮**状态累积** / 进度摘要。
  Phase 进度只写在 `docs/3-decisions/D0NN-*.md`，不写进 `.claude/next_prompt.md`。
  每轮用 `.claude/next_prompt.md` 时覆盖写,不在里面追加历史。
- `.claude/next_prompt.md` 的定位：**单次 payload**，生命周期 = 从 Claude 写入 → 用户执行 send_next.ss → 下一轮启动。下一轮启动后该文件即失效,内容参考价值等于零。

## 相关文件

- `tools/send_next.ss` — 注入脚本本体
- `.claude/next_prompt.md` — 集成测试用的 prompt 文件（可被覆盖）
- `$TERMAN_NAME` — 脚本必读环境变量
