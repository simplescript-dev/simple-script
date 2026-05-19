# I027 — comptime `shellOutput` 硬编码 `/tmp/ss_comptime_exec.tmp` 临时路径非并发安全

**父决策:** 无(独立 root cause —— comptime intrinsic `shellOutput` 的实现缺陷,与 I026 `cmdRun` 同 bug 类「编译期固定共享 `/tmp` 路径」但不同函数、不同子系统)
**状态:** Resolved at `b0e272c` —— comptime `shellOutput` 分支 delegate 到既有 `shell` builtin(`popen` 直捕 stdout),零 /tmp 中转文件;回归测试 `tests/phase5/i027_shelloutput_comptime_tmp_path.ss`
**颗粒度:** 立项轮 = 纯文档(本文件);修复 = `ctCallDispatch` 的 `shellOutput` 分支单点把 `soTmp` 改为进程唯一路径,对标 I026,标准改档
**依赖:** 无。`shell` builtin 现成(I026 已实证 `shell` 经 popen 捕获 stdout),修复不依赖未落地能力
**创建:** 2026-05-19
**立项由:** I026(`cmdRun` 硬编码 `/tmp/ss_run_output` 非并发安全)Execute 轮 —— PSM §字段 9 `same_pattern` 排查时发现 `shellOutput` 同类固定共享路径;按 MNK §衍生 issue 归档「非阻挡 + 独立 root cause → 立项」拆出,不混入 I026 修复 commit `fc3b35d`(禁第三态)

---

## 现象

comptime intrinsic `shellOutput`(`bootstrap/gen/exprs/exprs_ct_call.ss:114-122`)把命令 stdout 捕获经 **硬编码** 中转文件 `/tmp/ss_comptime_exec.tmp`:

```
const soTmp = "/tmp/ss_comptime_exec.tmp"
system(`${soCmd} > ${soTmp} 2>/dev/null`)
return ctVal(interpNewString(readFile(soTmp)))
```

→ 任意两个编译进程并发执行 comptime `shellOutput` 时,二者在 `/tmp/ss_comptime_exec.tmp` 上竞争:一方 `system(cmd > tmp)` 覆写时另一方 `readFile(tmp)` 读到撕裂内容 / 他命令的 stdout —— 非确定的 comptime 求值结果。

## 当前为何休眠(不阻挡)

`grep -rn 'shellOutput' bootstrap lib tools tests` 实证:`shellOutput` 当前 **0 usage** —— 仅 `exprs_ct_call.ss:114` 的 intrinsic 定义本身,无任何 `.ss`(含 stdlib / 测试)调用它。无调用 → 无并发触发 → 隐患休眠。

**触发条件**:任意 ≥ 2 个 `.ss` 在 comptime 块调 `shellOutput`,且被 `bin/ss test` 的 `MAX_JOBS=$(nproc)` 并行 runner 并发编译 → 二者 comptime 在 `/tmp/ss_comptime_exec.tmp` 上 race。

## root cause

与 I026 同 bug 类:编译期辅助逻辑用进程间共享的固定 `/tmp` 路径做中转,无进程隔离。`shellOutput` 在 comptime 子系统、`cmdRun` 在 run 驱动 —— 不同函数、不同子系统,故独立立项而非 I026 的 `same_pattern` 残留。业界对标同 I026:每次调用用唯一临时路径(`mktemp` 风格)。

## 修复(Execute 轮已坐实 —— commit `b0e272c`)

立项轮 prescription 为「`soTmp` 改 `mktemp` 进程唯一路径,对标 I026 `fc3b35d`」。Execute 轮按 MNK §字段 11 ladder 上推一格修正:`mktemp` 仅令中转路径唯一、**仍保留 temp-file 中转**,非最根。

**实际修复(更深根因层)**:`shellOutput` 分支直接 delegate 到既有 `shell` builtin —— body 由 `soTmp` + `system(cmd>tmp)` + `readFile(tmp)` 三步改为单行 `return ctVal(interpNewString(shell(`${soCmd} 2>/dev/null`)))`。`shell`(`bootstrap/gen/rt/gen_rt_shell.ss`)用 `popen` + 动态扩 buffer 直接捕获子进程 stdout,**零中转文件 → 无路径 → 无 race → 无清理 → 无 guard**。`2>/dev/null` 在命令串补回,保留原 `shellOutput` 丢弃 stderr 的语义。

**为何不照搬 I026 的 `mktemp`**:I026 `cmdRun` 的 `.ll`/`.o`/二进制是 `llc`/`musl-gcc` 物理必需的磁盘文件、不可消除(`mktemp` 是其最深可达层);I027 的 stdout 捕获缓冲 `popen` 可直接消除 —— 同为「固定 /tmp 路径 race」表象,最深可达层不同。方案对比见 `i027_shelloutput_comptime_tmp_path.options.md`(`bug_options_linter` 6/6),因果证据见 `tools/bugfix_reports/2026-05-19-i027-shelloutput-comptime-tmp-path.bugfix`(`bugfix_linter` 6/6)。

## 反向

不立项 → 这个 comptime 并发隐患仅留在 I026 收尾对话,下轮 Claude 读不到(MNK §核心原则 4);未来 stdlib / 用户代码新增 `shellOutput` comptime 用法时表现为无法复现的 comptime flaky,与 I026 / I025 同类误判风险。
