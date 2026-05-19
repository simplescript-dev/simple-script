# I026 — `cmdRun` 硬编码 `/tmp/ss_run_output` 输出路径非并发安全

**父决策:** 无(独立 root cause —— `bin/ss run` driver 缺陷,与 `run_exitcode_truncation` 退出码截断同函数 `cmdRun` 不同根)
**状态:** Planned —— 休眠隐患,当前未触发(全测套件中仅 `tests/phase5/run_exitcode_truncation.ss` 一个测试在运行时 `system("bin/ss run ...")`,其 5 次调用串行、无自竞争;无第二个并发 `bin/ss run` 测试)
**颗粒度:** 立项轮 = 纯文档(本文件);修复 = `cmdRun` 单函数把 `outBin` 改为进程唯一路径,标准改档
**依赖:** 无强依赖。若改用 `getpid()` 唯一化而 SS 运行时无此 builtin,则须先补 —— 立项未核实,Execute 轮 PSM §字段 12 实证
**创建:** 2026-05-19
**立项由:** `run_exitcode_truncation`(`bin/ss run` 退出码截断 bugfix)收尾 `/simplify` 审查 —— efficiency 代理发现;按 MNK §特定领域 §衍生 issue 归档「非阻挡 + 独立 root cause → 立项」拆出,不混入退出码截断 commit(禁第三态)

---

## 现象

`cmdRun`(`bootstrap/main.ss:379`)把被运行程序编译到 **硬编码** 路径 `outBin = "/tmp/ss_run_output"`;`compile()` 再由 `outputFile` 派生 `/tmp/ss_run_output.ll` / `.o` / `.ll.str` 等中间产物。

→ 任意两个 `bin/ss run` 进程并发执行时,二者在 `/tmp/ss_run_output{,.ll,.o,.ll.str}` 上竞争:`musl-gcc`/`llc-18` 并发写同一路径、一方 `rm -f` 另一方仍在读的中间文件、截断的二进制被 exec —— 非确定的编译失败 / 错误二进制 / flaky 测试。

## 当前为何休眠(不阻挡)

`bin/ss test tests/` 的并发 runner(`MAX_JOBS=$(nproc)`)对**编译每个测试**用 per-index 路径(`/tmp/ss_test_${idx}`),不走 `cmdRun`。`cmdRun` 仅由 `bin/ss run` 命令进入。全测套件中目前**只有** `tests/phase5/run_exitcode_truncation.ss` 在运行时 `system("bin/ss run ...")`,且其 5 次调用串行 —— 故当前无并发 `bin/ss run`,隐患休眠。

**触发条件**:再加入第二个运行时 `system("bin/ss run ...")` 的测试,且与 `run_exitcode_truncation.ss` 被 runner 并发调度 → 二者 `bin/ss run` 内层在 `/tmp/ss_run_output` 上 race。

## root cause

`cmdRun` 用进程间共享的固定路径做编译输出,无进程隔离。业界对标:`go run` / `cargo run` 用每次唯一的临时目录(`mktemp` 风格)。

## 修复方向(Execute 轮坐实)

`cmdRun` 的 `outBin` 由固定 `/tmp/ss_run_output` 改为进程唯一(如 `/tmp/ss_run_output_<pid>` 或 `mktemp` 风格)。连带同步:`bootstrap/main.ss:591` 清理 glob 内的 `/tmp/ss_run_output` 项。Execute 轮按 bug 修复 harness 走 `<bug>.options.md` + `bug_options_linter` GATE + `.bugfix` 6 gate。

## 反向

不立项 → 这个 driver 并发隐患仅留在 `run_exitcode_truncation` 收尾对话与 `/simplify` 代理输出,下轮 Claude 读不到(MNK §核心原则 4);未来新增并发 `bin/ss run` 测试时表现为无法复现的 flaky,易误判为 codegen 非确定(参 I025 同类误判史)。
