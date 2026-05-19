# I029 — `cmdTest` 固定共享 `/tmp` 路径(脚本 / 每测试二进制 / 结果文件)非并发安全

**父决策:** 无(独立 root cause —— `bin/ss test` 测试驱动 `cmdTest` 的缺陷,与 I026 `cmdRun` / I027 comptime `shellOutput` 同 bug 类「固定共享 `/tmp` 路径 race」但不同函数、不同子系统)
**状态:** Planned
**颗粒度:** 立项 + 修复同轮(用户 next_prompt 授权);修复 = `cmdTest` 把三类固定共享路径改为 `mktemp -d` 进程唯一目录承载 + `cmdClean` glob 同步,大改档
**依赖:** 无。`shell` builtin 现成(I026 已实证 `shell("mktemp …")` 经 popen 捕获 stdout),`mktemp -d` 是 coreutils 现成原语;修复不依赖未落地能力
**创建:** 2026-05-19
**立项由:** I028 §关联观察 明列本问题为下游 issue 候选(`docs/4-issues/I028-runtime-cache-dead-subsystem.md:53-55`);next_prompt 指定本轮专项修复

---

## 现象

`cmdTest`(`bootstrap/main.ss:420`)拼并行 test 脚本时用三类 **跨进程固定** 路径:

- `/tmp/ss_test_${idx}`(`:436`)—— 每测试编译输出二进制,`${idx}` 每次 `cmdTest` 调用从 0 重数(`:433` `let idx = 0`)
- `/tmp/ss_res_${idx}`(`:437` 拼脚本 / `:453` 读结果)—— 每测试退出码结果文件,同样 idx 从 0 重数
- `/tmp/ss_test_par.sh`(`:444` 写 / `:445` 执行)—— 并行 test 脚本本身

→ 任意两个 `bin/ss test` 进程并发执行时,二者在这些路径上竞争:

1. 进程 A 的 `bin/ss build` 写 `/tmp/ss_test_5` 时进程 B 的 `bin/ss build` 也在写同一路径 → 二进制交错损坏 / 一方 `timeout 5 ${outBin}` exec 撕裂半截二进制 → **段错误**
2. 进程 A 的 cleanup `rm -f /tmp/ss_test_* /tmp/ss_res_*`(`:465`)删进程 B 仍在运行/待运行的二进制与结果文件 → B 的 `readFile(resFile)` 读空 → 误判 FAIL
3. 二者都 `writeFile("/tmp/ss_test_par.sh", …)` → 一方覆写另一方的脚本
4. 进程 A 读 `/tmp/ss_res_${i}` 时拿到进程 B 写的退出码 → 张冠李戴

→ 非确定的 test 失败 / 段错误 / flaky,易误判为 codegen 非确定(I025/I026/I027 同类误诊史)。

## 当前为何休眠(不阻挡)

`bin/ss test tests/` 当前由 dev / CI 串行单次调用,且 `bin/ss test` 内不嵌套再调 `bin/ss test`(测试程序里若 `system("bin/ss test …")` 会与外层并行 runner race —— I028 §isolate 已据此放弃 cmdTest 的行为驱动回归测试)。无并发 `bin/ss test` → 隐患休眠。

**触发条件**:CI 矩阵并行跑多个 `bin/ss test`、开发者多终端同时 `bin/ss test`、或任意测试在运行时 `system("bin/ss test …")` 且被并行 runner 调度 → 二者在固定路径 race。

## root cause

与 I026/I027 同 bug 类:`cmdTest` 把「进程私有的测试构建中间态」用进程间共享的固定 `/tmp` 路径承载,无进程隔离。`${idx}` 是 per-index 但每次调用从 0 重数 → 跨进程必碰撞;固定脚本路径 `/tmp/ss_test_par.sh` 跨进程直接覆写。业界对标 `docs/1-axioms.md §V3`:`go test` / `cargo test` 用每次调用唯一的临时目录。

## 修复方向(Execute 轮 options.md 坐实)

按 bug 修复 harness,`i029_cmdtest_tmp_path_concurrency.options.md` 对比 ≥3 候选含层次标:A 数据层随机后缀(`srand` 秒级播种,同秒并发碰撞)、B 接口层逐路径 `mktemp`(next_prompt 字面建议 —— 共享命名空间未消除、cleanup glob 跨进程销毁残留)、C 架构层 `mktemp -d` 单进程唯一目录、D 架构层消 IPC 文件。研究指向最深可达层 = **架构层 C:一次 `mktemp -d` 取进程唯一目录,三类产物 + `bin/ss build` 派生的 `.ll`/`.o`/`.ll.str` 全落其中,cleanup `rm -rf` 自有目录**。比 next_prompt prescription「逐路径 mktemp」上推一格(同 I027 §字段 11 ladder 手法):逐路径 mktemp 只去重名字、共享命名空间仍在;`mktemp -d` 消除命名空间本身。`cmdClean` glob 连带同步。最深层由 Execute 轮 PSM §字段 10/11 按根因解决度决策。

## 反向

不立项 → 这个测试驱动并发隐患仅留在 I028 §关联观察 与本轮对话,下轮 Claude 读不到具体修复(MNK §核心原则 4);未来 CI 并行 / 多终端 `bin/ss test` 表现为无法复现的 flaky 段错误,与 I025/I026/I027 同类误诊反复。
