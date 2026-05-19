# `bin/ss run` 退出码截断 — 修复方案对比(MNK §轨 1)

**bug**: `cmdRun`(`bootstrap/main.ss:383-384`)末两行 `const rc = system(cmd)` / `exit(rc)`。`system()` 是 POSIX `system(3)` 的 1:1 镜像(`ss_system` 即 `call i32 @system`),返回 `wait(2)` 格式的 raw wait-status —— 子进程正常退出时退出码在 bits 8-15(`WEXITSTATUS = status >> 8`)。`cmdRun` 直接把该 wait-status 交给 `exit()`,而 `exit()` 走 C `exit()`,进程退出码 = `参数 & 0xFF`。于是 `exit(7)` 程序经 `bin/ss run`:`system()` 返 `7<<8 = 1792` → `exit(1792)` → `1792 & 0xFF = 0`。被运行程序退出码 1-255 经 `bin/ss run` 后 `$?` 全归 0,`bin/ss run` 无法反映程序失败。

该 bug 还弱化 `tools/bugfix_linter.ss:64` 的 G2a 因果校验 —— 它用 `system("bin/ss run <test>")` 的退出码判定「回归测试通过」;`bin/ss run` 恒退 0 时,G2a 对任意测试恒判 PASS,bug 修复 harness 的因果证明形同虚设。

**父约束**: `docs/1-axioms.md §V3 Best practices from mature compilers` —— `go run` / `cargo run` / `zig run` 均把被运行程序的退出状态原样透传给 `$?`,这是编译器 `run` 子命令的业界规范契约。

**结论**: **选 C —— `cmdRun` 内联解码 wait-status**(见 §4 决策行)。

---

## 1. 根因机理(坐实)

`bin/ss run <prog>` 的 `cmdRun` 三步:`compile(prog → /tmp/ss_run_output)` → `rc = system("/tmp/ss_run_output")` → `exit(rc)`。

`system()` 经 `/bin/sh -c` 运行命令,返回 **child shell 的 termination status**,`wait(2)` 编码格式:

- 子进程正常 `exit(N)`:bits 8-15 = `N`,bits 0-7 = 0 → status = `N << 8`
- 子进程被信号 S 杀:bits 0-6 = `S`,bit 7 = core-dump 标志 → status 低字节非 0

实证(`/bin/sh` = dash):子程序 `exit(7)` → `system()` 返 `1792`(=`7<<8`);子程序整数除零被 SIGFPE 杀 → dash 把信号死亡归一为自身正常 `exit(136)` → `system()` 返 `34816`(=`136<<8`)。即经 `system()`/dash 后返回值 **恒为 WIFEXITED 形态**,真实退出码 = `rc >> 8` = `rc / 256`。

`cmdRun` 把这个 `N << 8` 形态的 wait-status 当退出码喂 `exit()`。`exit()` → C `exit()` → 进程退出码 `= 参数 & 0xFF`。`N << 8` 的低 8 位恒为 0(N ≤ 255),故 **任何非零退出码经 `bin/ss run` 后 `$?` 恒为 0**;退出码 0 因 `system()` 返 0、`exit(0)` 巧合正确。

→ `bin/ss run` 退出码语义彻底失真:程序失败(exit 1-255)与成功(exit 0)在 `$?` 上不可区分。

## 2. 假设破裂入口

`exit(rc)`(`rc = system(cmd)`)隐含两个假设,**两者皆破裂**:

- **假设 A**「`system()` 的返回值即子进程退出码」—— **破裂**:POSIX `system()` 返回 `wait()` 格式 wait-status,退出码在 bits 8-15,不是低位整数。wait-status 与 exit-code 是两套语义,被 `cmdRun` 当同一个 int。
- **假设 B**「`exit(n)` 令进程以整数 `n` 退出」—— **破裂**:C `exit()` 进程退出码 = `n & 0xFF`,`n ≥ 256` 被 mod-256 截断。`system()` 的 `N<<8`(N≠0)必 ≥ 256,必被截。

两假设叠加破裂:`exit(wait-status)` = 把一个高 8 位编码的值喂给只取低 8 位的 `exit()` → 信息全丢。

## 3. 候选方案对比

| 候选 | 层次 | 改动 | 评估 |
|---|---|---|---|
| A | 数据层 patch | `exit(rc)` → `exit(rc / 256)` | 解出 WEXITSTATUS,正常 case 全覆盖(含被信号杀的程序 —— dash 已归一为 `128+S`,含在 `rc/256` 内)。但 `system()` 在 **child shell 自身被信号终止** 时返 WIFSIGNALED 形态(低 7 位 = 信号号),此时 `rc/256` ≈ 0 → `exit(0)` 误报成功 —— **同 bug 类残留**。只补假设 A 的正常分支,漏信号分支 |
| B | 接口层 trap | 抽 `decodeWaitStatus(rc): int` 顶层函数做完整解码,`cmdRun` 调用之 | 解码逻辑与 C 相同、完整。但 wait-status 解码在本仓库 **仅 `cmdRun` 一个调用点**(其余 `system()` 调用者皆 `==0`/`!=0` 比较,不需退出码);为单调用点抽函数 = 过早抽象,平白 `net_new_fns +1` 无复用收益。第二个调用点出现时再抽不迟 |
| C | 接口层 trap | `cmdRun` 内联完整解码:`sig = rc % 128`;`sig == 0` → `exit(rc / 256)`,否则 `exit(128 + sig)` | 在 wait-status⇄exit-code 语义错配 **正好发生的边界**(`system()` 结果流入 `exit()` 处)拦截解码,一次同时消除假设破裂 A(按 wait-status 语义解码,不再当退出码)与 B(解出值 ≤ 255,`exit()` 不再截断)。`sig==0` 分支覆盖一切正常 case;`sig!=0` 分支覆盖 child shell 自身被信号杀的 case(`128+S` 是 shell 通用约定,堵住 A 的误报 0 残留)。单调用点 → 内联,不引入无复用函数 |
| D | 架构层 refactor | 改 `ss_system` 运行时 IR(`gen_rt_io.ss`),令 SS `system()` 直接返回解码后的退出码 | `system()` 是 POSIX `system(3)` 的 1:1 镜像(V3:对标 C/POSIX 原语),改其返回语义使它不再 = C `system()`。其余调用者(`runBootstrap` `!=0`、`build_xxd` `cmp -s ==0`、`bugfix_linter` G2a)虽多数 `==0` 比较仍能工作,但这是 **改一个正确的原语去掩盖单个调用方的误用** —— 缺陷在 `cmdRun` 误用,不在 `system()`。blast radius 大、违 V3 |
| E | 架构层 refactor | `cmdRun` 弃用 `system()`,改 `fork`/`exec`/`waitpid` 直接 spawn 被运行程序 | 架构上更干净(无 shell 介入、无 `runArgs` 字符串拼接的 shell 重解析隐患、`cmdRun` 直接见程序 WIFEXITED/WIFSIGNALED)。但 SS 运行时 **无 `fork`/`exec`/`waitpid` builtin**(`ss_system`/`ss_exit`/`ss_argCount` 是仅有的进程原语),E 依赖一组未落地的更基础 runtime 能力(字段 10(d) 底层依赖链)—— 须先做该 runtime 特性(独立 D 文档级决策)。且退出码截断本身被 C 完全修复,E 不是「截断 bug 更根的解」,是相邻架构增强 |

## 4. 决策行

**选 C 因** 它在 wait-status 与 exit-code 两套语义错配的 **确切发生点**(`cmdRun` 内 `system()` → `exit()` 数据流)做完整解码,是 5 候选中根因解决度最高项:一次消除假设破裂 A + B;`sig==0`/`sig!=0` 双分支覆盖正常退出与 shell 信号终止两类 wait-status 形态,无残留 success-on-failure 空洞。**不选 A** 因其漏 WIFSIGNALED 分支、留同 bug 类残留(信号终止误报 0);**不选 B** 因单调用点抽函数是过早抽象、平添无复用的 `net_new_fns`;**不选更深的 D** 因 `system()` 是正确的 POSIX 镜像原语,改它掩盖调用方误用是错层修复 + blast radius;**不选更深的 E** 因其依赖未落地的 `fork`/`exec`/`waitpid` runtime builtin(底层依赖链未就位),且截断 bug 已被 C 完全修复,E 是相邻架构增强非本 bug 更根解。排序依据为根因解决度,非工程量。

## 5. 长久评估

wait-status 解码(`WEXITSTATUS = status>>8`、信号 `128+S`)是 POSIX `wait(2)` 与所有 shell `$?` 约定的 40+ 年稳定规范,无演化返工风险。业界对标:`go run`/`cargo run`/`zig run` 的 runner 均把被运行程序退出状态完整透传(go/rust 用 `os/exec`+`ExitStatus` 直接 `waitpid`,等价 E 形态)。N 年返工度:C 修复本身 ≈ 0(解码规范不变);唯一长期演化点是 E —— 若未来 SS 落地 `fork`/`exec`/`waitpid` runtime 能力,`cmdRun` 可演进为直接 spawn,届时 C 的 `system()`+解码自然被替换。**底层依赖链**:C 不依赖任何未落地能力(`system()`/`exit()`/`%`/`/` 均现成);E 依赖未落地 runtime builtin,故 C 必先于 E,E 留作后续独立增强,不在本轮起首。

## 6. §实证(MNK §字段 12)

**根因定位 grep 证据**:

```
$ sed -n '383,384p' bootstrap/main.ss
    const rc = system(cmd)
    exit(rc)
$ grep -n 'ss_system' bootstrap/gen/rt/gen_rt_io.ss
175:    emitIR("define i32 @ss_system(ptr %cmd) {")
178:    irCall("result", "i32", "system", "ptr %cmd_buf")   ← 1:1 透传 C system() 返回值
$ printf 'function main(){exit(7)}' >/tmp/x.ss; bin/ss run /tmp/x.ss; echo $?
0                                                            ← 截断坐实(应 7)
$ bin/ss build /tmp/x.ss -o /tmp/xb && /tmp/xb; echo $?
7                                                            ← 直接二进制正确
```

→ 退出码截断的代码实例 **唯一**:`cmdRun`(`bootstrap/main.ss:384`)。`tools/bugfix_reports/2026-05-19-build-xxd-fixed-point.bugfix` 的 `[isolate]` 段已书面记述此 bug 为「`bin/ss run` 自身独立 bug,(build_xxd 轮)scope 外」—— 本轮即其下游修复。code same-pattern 残留 = 0。

**最危险假设最小 spike(试切)** —— 最危险假设:「回归测试经 `bugfix_linter` G2a 的 `bin/ss run <test>` 运行时,test 内层再 `bin/ss run <fixture>` 会因 `cmdRun` 硬编码输出 `/tmp/ss_run_output` 被复用而崩(ETXTBSY / 段错误)」:

```
$ # 外层 bin/ss run 编译 spike_test → /tmp/ss_run_output 并运行;
$ # spike_test 内部两次再调 bin/ss run(各自重编译 /tmp/ss_run_output)
$ bin/ss run /tmp/spike_test.ss
compiled: /tmp/ss_run_output
inner ws #1 = 0
inner ws #2 = 0
（外层 exit 0,无 segfault / 无 ETXTBSY)
```

嵌套 `bin/ss run` 实证安全(`ld` 重建输出前 unlink,运行中的外层进程持旧 inode 不受影响)。另 spike `system("<SIGFPE 二进制>")` 返 `34816`(=`136<<8`,WIFEXITED 形态,坐实 §1 dash 归一)、`%`/`/` 算子 codegen 确认存在。完整 bootstrap 三阶段固定点 + 全测实证见 `tools/bugfix_reports/2026-05-19-run-exitcode-truncation.bugfix` §verify。
