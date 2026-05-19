# I027 — comptime `shellOutput` 硬编码 `/tmp/ss_comptime_exec.tmp` 临时路径非并发安全 — 修复方案对比(MNK §轨 1)

**bug**: comptime intrinsic `shellOutput`(`bootstrap/gen/exprs/exprs_ct_call.ss:114-122`)把命令 stdout 经 **硬编码** 中转文件 `/tmp/ss_comptime_exec.tmp` 捕获 —— `const soTmp = "/tmp/ss_comptime_exec.tmp"`,`system(`${soCmd} > ${soTmp} 2>/dev/null`)` 把命令 stdout 重定向到该固定路径,再 `readFile(soTmp)` 读回。该路径是跨进程固定常量,而 comptime `shellOutput` 随每次"含 comptime shellOutput 块的 `.ss`"编译被透明触发。两个并发编译进程各自 comptime 调 `shellOutput` 时在 `/tmp/ss_comptime_exec.tmp` 上 race(一方 `system(cmd > tmp)` 覆写时另一方 `readFile(tmp)` 读到撕裂内容 / 他命令的 stdout)。

**父约束**: 独立 root cause(I027,父决策「无」)。业界对标 `docs/1-axioms.md §V3`(best practices from mature compilers)—— 编译期捕获子进程 stdout 的标准原语是 `popen`(管道,无磁盘中转),不是"重定向到固定文件再读回"。

**结论**: **选 C —— `shellOutput` 分支 delegate 到 `shell` builtin(popen 捕获 stdout,零 temp file)**(见 §4 决策行)。next_prompt / I027 §修复方向 prescription 为 B(mktemp 进程唯一路径,对标 I026);§字段 11 ladder 上推一格证 B 非最根 —— B 仍保留 temp-file 中转、只让路径唯一,C 直接消除中转文件。

---

## 1. 根因机理(坐实)

comptime `shellOutput(cmd)` 三步:`system(cmd > /tmp/ss_comptime_exec.tmp 2>/dev/null)`(命令 stdout 落固定文件、stderr 丢弃)→ `readFile(/tmp/ss_comptime_exec.tmp)`(读回)→ `ctVal(interpNewString(...))` 返回。

`/tmp/ss_comptime_exec.tmp` 是跨进程固定常量。两个并发编译进程(P1 / P2)各编译一个含 `comptime { shellOutput(...) }` 块的 `.ss`,二者 comptime 求值在该路径 race:

1. P1 的 `system(cmdA > /tmp/ss_comptime_exec.tmp)` 写入时 P2 的 `system(cmdB > /tmp/ss_comptime_exec.tmp)` 也在写 → 文件内容交错损坏
2. P1 `system` 写完、`readFile` 读之前,P2 的 `system(cmdB > tmp)` 覆写它 → P1 `readFile` 读到 cmdB 的 stdout(非 cmdA 的)
3. P1 `readFile` 读到一半时 P2 `system` 截断重写 → P1 读到撕裂内容

→ 非确定的 comptime 求值结果(comptime 块返回错误字符串),且因「非确定」易被误判为 codegen 非确定性 bug(`docs/4-issues/` I025 同类误判史)。

触发条件:任意 ≥ 2 个 `.ss` 在 comptime 块调 `shellOutput`,被 `bin/ss test` 的 `MAX_JOBS=$(nproc)` 并行 runner 并发编译。当前 `shellOutput` 全 repo 0 usage → 隐患休眠,但属真实缺陷(I026 同 bug 类已实证为真隐患并修复)。

## 2. 假设破裂入口

`const soTmp = "/tmp/ss_comptime_exec.tmp"` 隐含一个 **未校验假设**:

- **假设**「同一时刻至多一个进程在用 `/tmp/ss_comptime_exec.tmp` 这条 comptime stdout 中转路径」—— **破裂**:comptime `shellOutput` 随每次含该 intrinsic 的 `.ss` 编译被透明触发,编译进程无文件锁 / 无 PID 命名空间 / 无任何互斥;并行 test runner、CI、多终端 → 多个编译进程天然并发,各自 comptime 在同一固定路径上写读。假设在并发下必然破裂。

**更深一层的设计假设**(C 消除、B 不消除):

- **假设**「捕获子进程 stdout 必须经磁盘中转文件」—— **破裂**:`shell` builtin(`gen_rt_shell.ss`)用 `popen` + 动态扩 buffer 直接捕获子进程 stdout 为字符串,**根本不落磁盘**。`shellOutput` 的 temp-file 中转是对「捕获 stdout」这一需求的劣质重实现 —— magic 路径只是这个多余机制的副产物。B(mktemp)只修第一个假设(路径唯一化),第二个假设仍破裂;C 同时消除两者(无中转文件 → 无路径)。

该假设破裂的根:`shellOutput` 在「如何捕获命令 stdout」这一步,选了「重定向到磁盘文件再读回」而非「popen 管道直捕」。

## 3. 候选方案对比

| 候选 | 层次 | 改动 | 评估 |
|---|---|---|---|
| A | 数据层 patch | `soTmp = "/tmp/ss_comptime_exec_" + randomInt(1000000)` | 仅把常量换随机数,形式上「唯一」。**破裂**:运行时 `srand` 以 `time(NULL)` 截 i32 播种(秒级粒度,`gen_decls.ss`),两个编译进程同一秒内启动 → 同种子 → `randomInt()` 首返回值相同 → 路径仍碰撞。并发 race 的触发窗正是「同秒并发」,A 在该窗口完全失效 —— 假设「randomInt 跨进程唯一」破裂,不解根因 |
| B | 接口层 trap | `soTmp = shell("mktemp /tmp/ss_comptime_exec.XXXXXX").trim()` + 空值 guard + 读毕 `rm`(= next_prompt / I027 §修复方向 prescription,对标 I026 fc3b35d) | 在固定路径诞生点拦截,改 `mktemp` 原子唯一路径。**能消除 race**,但 **非最根**:仍保留 `system(cmd>tmp)+readFile(tmp)` 的 temp-file 中转 —— 只是让中转文件路径唯一。§字段 11 ladder 可上推一格:中转文件本身就是多余的(见 C)。B 还引入 mktemp 子进程开销 + 空值 guard 分支 + 清理调用,净增复杂度 |
| C | 架构层 refactor | `shellOutput` 分支改 `return ctVal(interpNewString(shell(`${soCmd} 2>/dev/null`)))` —— delegate 到 `shell` builtin(`popen` 直捕 stdout,零 temp file) | 在「如何捕获 stdout」这一根因点,改用业界标准原语 `popen`(经既有 `shell` builtin)。**零中转文件 → 无路径 → 无 race → 无清理 → 无 guard 分支**。`shell` 是既有 builtin(`gen_rt_shell.ss`:popen + 动态扩 buffer,任意大小 stdout,不写 exit code、不 trim),编译器自身可调(`main.ss` `cmdRun` 已用)。`2>/dev/null` 保留原 `shellOutput` 丢弃 stderr 的语义。净 LOC delta ≈ 0、net_new_ifs = 0、零新 builtin、单 commit、seed 直接可编译。根因解决度最高 |
| D | 架构层 refactor | 新增 `getpid()` builtin,`soTmp` 带 pid | PID 是进程唯一原语,但:(1) 编译器自身(`exprs_ct_call.ss`)调用新 builtin → seed(旧 `bin/ss`)不识别 → stage1 崩,须拆两 commit,违「独立 commit」;(2) 为单一内部调用点引入语言面全局 builtin = 过度扩面(违 §反 over-engineer);(3) PID 会被 OS 回收。底层依赖链:D 依赖未落地的 `getpid` builtin。且 D 仍保留 temp-file 中转(同 B 的非最根问题) |
| E | 接口层 | 删除 `shellOutput` intrinsic,新增 `shell` 为 comptime intrinsic 让 comptime 代码直接调 `shell` | 与 C 同等消除 temp file,但 **删 `shellOutput` 是 comptime intrinsic 的 API surface 变更** —— `shellOutput` 是既定 intrinsic 名,移除它属语言面接口改动,超出「修一个并发 bug」的 scope。C 在 `shellOutput` 内部 delegate 到 `shell` 已达同等根因解决度(零 temp file)且 **不动 API surface**,E 相对 C 零增益、纯多担一个接口变更风险 |

## 4. 决策行

**选 C 因** 它在「如何捕获命令 stdout」这一根因点用业界标准原语 `popen`(经既有 `shell` builtin)直接消除 temp-file 中转 —— 零中转文件即无路径、无 race、无清理、无 guard,5 候选中根因解决度最高且 scope 不外溢:`shellOutput` 单分支 3 行 body 内闭合,零新 builtin、净 LOC delta ≈ 0、单 commit、seed 可编译。**不选 next_prompt prescription B** 因 B(mktemp 唯一路径)仅修「路径是固定常量」这一表层假设,仍保留「捕获 stdout 必经磁盘中转文件」的更深破裂假设 —— §字段 11 ladder 上推一格即见 B 非最根;B 还净增 mktemp 子进程 + guard 分支 + 清理调用。**不选 A** 因 `srand` 秒级播种使 `randomInt` 在「同秒并发」(正是 race 触发窗)内跨进程不唯一,假设破裂、不解根因。**不选 D** 因新 builtin 被编译器自身调用 → bootstrap 两 commit(违独立 commit），为单一调用点引入语言面 builtin 属过度扩面,且仍保留 temp-file 中转。**不选 E** 因删 `shellOutput` 是 comptime intrinsic API surface 变更、超 bug-fix scope,C 已在不动 API 前提下达同等根因解决度。排序依据为根因解决度 + scope 收敛度,非工程量。

**与 I026 的差异(为何 next_prompt「对标 I026」过度泛化)**:I026 `cmdRun` 的中转物是 `.ll`/`.o`/二进制 —— `llc-18` / `musl-gcc` 是外部工具,其输入输出物理必经磁盘文件,**不可消除**(I026 options.md candidate E 因此被拒),故 `mktemp`(唯一化不可消除的路径)是 I026 最深可达。I027 `shellOutput` 的中转物是「stdout 捕获缓冲」—— `popen` 管道可直接消除,**不存在物理不可消除的磁盘文件**。同为「固定 /tmp 路径 race」表象,最深可达层不同:I026 = 接口层 mktemp,I027 = 架构层 delegate。

## 5. 长久评估

`popen` 是 POSIX 捕获子进程 stdout 的标准原语,`shell` builtin 已封装(`gen_rt_shell.ss`:popen + 动态扩 buffer + pclose)。Go(`exec.Command.Output()`)、Rust(`Command::output()`)、Zig(`std.process.Child` pipe)等成熟系统捕获子进程 stdout 一律走管道,无「重定向到固定文件再读回」—— 这是稳定的业界规范,无演化返工风险。**底层依赖链**:C 不依赖任何未落地能力(`shell` builtin 现成、`main.ss` 已用),可独立单 commit;B 同样不依赖未落地能力但非最根;D 依赖未落地的 `getpid` builtin。**N 年返工度** ≈ 0:C 让 `shellOutput` 落到「popen 直捕」这一不可再约的最小机制(再上推即「消除子进程」,而子进程是 `shellOutput` 的功能本身,不可约)—— 故 C 是 ladder 终点,无更根解可升级,不会被未来更基础能力覆盖致返工。

## 6. §实证(MNK §字段 12)

**蓝图断言重核**:next_prompt / I027 §修复方向 断言「对标 I026 commit fc3b35d → soTmp 改 mktemp」。读 `bootstrap/gen/rt/gen_rt_shell.ss` 证伪「必须用 temp file」:`ss_shell` 用 `popen` + `fread` 动态扩 buffer(`malloc 4096` → `realloc ×2`)+ `pclose`,捕获任意大小 stdout 为 RC string,不写 exit code、不 trim —— 与 `system(cmd>tmp 2>/dev/null)+readFile(tmp)` 行为等价(唯一差异:`shell` 不自带 stderr 重定向 → C 在命令串补 `2>/dev/null`)。结论:temp-file 中转可被 `shell` 完全替代,蓝图的 B 非最根。

**根因定位 grep 证据**:

```
$ grep -rn 'ss_comptime_exec' bootstrap/gen/exprs/exprs_ct_call.ss
117:            const soTmp = "/tmp/ss_comptime_exec.tmp"     ← 硬编码跨进程固定常量,无进程隔离
$ grep -rn 'shellOutput' bootstrap lib tools tests
bootstrap/gen/exprs/exprs_ct_call.ss:114:    if (name == "shellOutput") {   ← 仅 intrinsic 定义本身,0 调用方(隐患休眠但真实)
$ grep -n '"shell"' bootstrap/gen/gen_registry.ss
132:    funcRetTypes.set("shell", "string")    ← shell 是既有 builtin,编译器自身可调,无需新增
$ sed -n '1,2p' bootstrap/gen/rt/gen_rt_shell.ss
// ss_shell(cmd) — popen + dynamic-grow fread buffer + pclose,返回 stdout 作 RC string。
// stdout-only 场景用这个。                ← shell 即「捕获子进程 stdout」原语,zero temp file
```

**最危险假设最小 spike** —— 「`comptime { return shellOutput(...) }` 可编译可达 + buggy 编译器确实创建 `/tmp/ss_comptime_exec.tmp`」(决定回归测试设计成立):

```
$ cat /tmp/ss_i027_spike.ss
const CT = comptime { return shellOutput("echo I027_CT_OK") }
function main() { println(CT) }
$ rm -f /tmp/ss_comptime_exec.tmp
$ bin/ss build /tmp/ss_i027_spike.ss -o /tmp/ss_i027_spike_bin   → compiled: /tmp/ss_i027_spike_bin
$ ls -la /tmp/ss_comptime_exec.tmp
-rw-r--r-- 1 root root 11 ... /tmp/ss_comptime_exec.tmp       ← buggy 编译器创建该固定路径且不清理(坐实)
$ /tmp/ss_i027_spike_bin
I027_CT_OK                                                    ← comptime shellOutput 已执行并捕获 echo stdout
```

spike 确证:comptime `shellOutput` 可达,buggy 编译器把命令 stdout 落 `/tmp/ss_comptime_exec.tmp`(11 字节 = `"I027_CT_OK\n"`)且不清理。回归测试 `tests/phase5/i027_shelloutput_comptime_tmp_path.ss` 据此用确定性手法(无 race)坐实修复:`rm` 该固定路径 → `bin/ss build` 一个含 comptime `shellOutput` 的 fixture → 断言 `/tmp/ss_comptime_exec.tmp` **不再存在**(buggy 编译器创建并遗留 → 修复后 `shell()` popen 直捕、零中转文件 → 该路径永不出现)。完整 bootstrap 三阶段固定点 + 全测见 `tools/bugfix_reports/2026-05-19-i027-shelloutput-comptime-tmp-path.bugfix` §verify。
