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

- **每轮必做 — 自闭环三步(Claude 职责,非用户手动)**：
  1. 对话最后一段输出下轮提示词(让用户审阅措辞)
  2. 覆盖写入 `.claude/next_prompt.md`(单次 payload,给 send_next.ss 读)
  3. **Claude 本轮最后一次工具调用**执行
     `bin/ss run tools/send_next.ss .claude/next_prompt.md` → 脚本 `/clear` + 
     bracketed paste + 30s 观察窗口 + Enter,下一轮自动开始

  三处内容严格一致。用户在 30s 窗口里看一眼,要否决就 Ctrl+C 中断 Claude 的 Bash 调用,
  否则不动手 —— "简化我的时间"的设计目的就是消除所有手动敲命令的环节。
  规则全貌见 `feedback_next_prompt_auto_loop`。

- **仍然禁止**：用 handoff 文件做跨轮**状态累积** / 进度摘要。
  Phase 进度只写在 `docs/3-decisions/D0NN-*.md`,不写进 `.claude/next_prompt.md`。
  每轮用 `.claude/next_prompt.md` 时**覆盖写**,不追加,不保留历史 —— 它是单次 payload 不是日志。

- `.claude/next_prompt.md` 的定位:**单次 payload**,生命周期 = Claude 写入 → Claude 自执行 send_next.ss → 下一轮启动。下一轮启动后该文件即失效,内容参考价值等于零(但**不删除**,等下一轮 Claude 再覆盖写入)。

- **例外(跳过自执行 send_next.ss)**:
  - bootstrap 失败 / 测试红 / reflection linter GATE 阻断 —— 停下等人类裁决
  - 用户明说"这轮不要自动进下轮" / "不要跑 send_next"
  - `$TERMAN_NAME` 为空(非 terman session)—— 脚本会报错,降级为仅对话 + 写文件

## 相关文件

- `tools/send_next.ss` — 注入脚本本体
- `.claude/next_prompt.md` — 集成测试用的 prompt 文件（可被覆盖）
- `$TERMAN_NAME` — 脚本必读环境变量
