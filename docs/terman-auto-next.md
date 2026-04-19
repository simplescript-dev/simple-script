# Terman 下轮提示词自动注入

> 用户在 terman session 中运行 Claude Code。当前轮结束时,Claude 只把下轮提示词
> 写进 `.claude/next_prompt.md` 并 stop。terman 内建的 `claude-next` preset 观察
> PTY 空闲 + 光标在 prompt 处 + 文件存在,自动 `/clear` + bracketed paste + 30s
> 观察窗口 + Enter,下一轮启动。Claude 不执行任何脚本,整条链路由 terman preset
> 完成。

## 机制

terman 的 preset engine(PTY master + Rhai 脚本,每秒 tick 一次)读 PTY 输出,
追踪 idle 时长。`claude-next.rhai`(built-in preset)触发条件与动作:

**触发条件(全部满足)**:

- `context.idle_ms >= 30000`:TUI 静默 >= 30 秒
- `context.text` 含 `❯`:光标处于 Claude Code 输入框 prompt
- 不在确认 / 权限对话框里(跳过 Yes/No / Allow / "Do you want to")
- `read_file(".claude/next_prompt.md")` 返回非空(路径相对 term cwd 解析)

**动作序列(全部异步 spawn,不阻塞脚本 tick)**:

1. 立即:`send_text("/clear\r")` 清当前上下文
2. 1 秒后:`\x1b[200~...\x1b[201~` 包裹 payload bracketed paste 到输入框
3. 31 秒后:`send_text("\r")` 提交(= paste 后 30s 观察窗口)
4. 同步消费:`delete_file(".claude/next_prompt.md")`,防止同一份 payload 被下一次
   tick 重复触发

## 启用 preset

默认 `enabled: false`。启用一次即可:

```bash
terman preset toggle claude-next
```

状态持久化到 term 的 meta.json,重启 session 保留。查看当前状态:

```bash
terman preset screen <term-id>   # 调试用,dump PTY text 看 preset 能看到什么
```

(切换、状态查看的 CLI 命令以 `terman --help` 为准。)

## Claude 每轮职责(两步自闭环)

1. 对话最后一段**输出下轮提示词**(1-3 句、单段、命令式、模仿用户原始风格,
   让用户在 PTY 滚动缓冲里看到措辞)
2. **覆盖写入** `.claude/next_prompt.md`(单次 payload,两处内容严格一致)

然后本轮 stop。**不**执行脚本、**不**调 `terman send`、**不**自己触发下一轮。

## 用户在 30s 观察窗口能做什么

- **不动**:Enter 到点自动打入 → 下一轮开始
- **Ctrl+C 或键入任何字符**:TUI 的 idle_ms 立刻重置,preset 不会再次触发;提
  示词文本已经 paste 在输入框里,你可以编辑后手动 Enter,也可以删掉重来
- paste 是 bracketed paste,多行完整保留,不会被换行字符提前提交

## 跨轮状态累积仍然禁止

- `.claude/next_prompt.md` 是**单次 payload**,preset 读完即 `delete_file` 消费。
  下一轮 Claude 必须覆盖写入新内容,不追加、不保留历史
- Phase 进度 / 决策摘要 / 历史总结一律写 `docs/3-decisions/D0NN-*.md`,不写进
  `.claude/next_prompt.md`

## 例外:Claude 不该写 next_prompt 的场景

以下情况本轮**不要**写 `.claude/next_prompt.md`(停下等人类裁决):

- bootstrap 失败 / 测试红 / reflection linter GATE 阻断
- 用户明说"这轮不要进下轮" / "停下"
- `$TERMAN_NAME` 为空(非 terman session)—— preset 不会跑,写了也无效

没写文件 → preset `read_file` 返回空 → early return,不触发下一轮。这是降级的
天然机制。

## 已知小缺陷

`send_text(text, delay_ms)` 在 terman 内是 spawn 后台线程,不可 cancel。意味着:
paste 后 30s 观察窗口里,若用户提前手动按 Enter 提交,后面那个延时 31s 的 `\r`
仍会发出,打进新一轮的输入框多一个空回车(不会误提交,只是残留空行)。第一版
接受,后续 terman 可以改 `send_text` API 加取消 token。

## 相关文件

- `.claude/next_prompt.md` — 当前轮的单次 payload(Claude 覆盖写,preset 读完消费)
- `~/.terman/presets/claude-next.rhai` — preset 脚本磁盘副本(由 terman 启动时内
  建 `BUILTIN_CLAUDE_NEXT` 覆盖同步,手动改会在下次启动被刷掉;改逻辑要改
  terman 源码 `src/term_mon/preset.rs`)
- `$TERMAN_NAME` — 非 terman session 的检测信号(空 → preset 不跑,降级为仅对话 +
  写文件;文件写了也不会被消费,下次 preset 生效时会被读取——所以非 terman 环
  境下记得清理该文件)
