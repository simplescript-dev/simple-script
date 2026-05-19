# I027 — comptime `shellOutput` 硬编码 `/tmp/ss_comptime_exec.tmp` 临时路径非并发安全

**父决策:** 无(独立 root cause —— comptime intrinsic `shellOutput` 的实现缺陷,与 I026 `cmdRun` 同 bug 类「编译期固定共享 `/tmp` 路径」但不同函数、不同子系统)
**状态:** Planned —— 休眠隐患,当前 **0 usage**(全 repo 无任何 `.ss` 调用 `shellOutput`,grep 实证见 §现象)
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

## 修复方向(Execute 轮坐实)

`shellOutput` 分支的 `soTmp` 由固定 `/tmp/ss_comptime_exec.tmp` 改为进程唯一(`shell("mktemp /tmp/ss_comptime_exec.XXXXXX").trim()` + 空值 guard,对标 I026 commit `fc3b35d` 的 `cmdRun` 修复)+ 读毕清理。`shell` builtin 现成。Execute 轮按 bug 修复 harness 走 `<bug>.options.md` + `bug_options_linter` GATE + `.bugfix` 6 gate + 新增 `tests/phase5` 回归测试。

## 反向

不立项 → 这个 comptime 并发隐患仅留在 I026 收尾对话,下轮 Claude 读不到(MNK §核心原则 4);未来 stdlib / 用户代码新增 `shellOutput` comptime 用法时表现为无法复现的 comptime flaky,与 I026 / I025 同类误判风险。
