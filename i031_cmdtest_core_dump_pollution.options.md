# I031 — `bin/ss test` 把崩溃测试子进程的 core 转储抛到 repo 根 — 修复方案对比(MNK §轨 1)

**bug**: `cmdTest`(`bootstrap/main.ss:437`)`let script = "#!/bin/bash\nMAX_JOBS=$(nproc)\nRUNNING=0\n"` —— 生成的并行测试脚本只设并发度(`MAX_JOBS`),**不收束子进程树的资源限界**。`RLIMIT_CORE` 默认 `unlimited` 被整棵测试子进程树继承,任一测试(或其嵌套 `bin/ss run` 派生的 `ss_run_output.*` 孙进程)崩溃 → OS 把 ≈1GB core dump(`core.<PID>`)写到继承自 `bin/ss test` 的 CWD = repo 根。

**父约束**: 独立 root cause(I031,父决策「无」)。与 I026 `cmdRun` / I027 comptime `shellOutput` / I029 `cmdTest` 同 family「测试基建不隔离」,但前三者隔离的是 `/tmp` **具名路径**,本 bug 是 OS core dump 走 **CWD(非具名路径)** 逃逸该沙箱 —— 不同维度。业界对标 `docs/1-axioms.md §V3`(mature compilers best practices)—— `go test` / `cargo test` 不把崩溃副产物留进源码树。

**结论**: **选 B —— `cmdTest` 拼 `par.sh` 时行首加 `ulimit -c 0`**(见 §4 决策行)。

---

## 1. 根因机理(坐实)

`bin/ss test` 的 `cmdTest` 流程:`collectTestFiles` → `testRunDir = mktemp -d`(I029)→ 拼 `par.sh` 脚本字符串 → `writeFile(scriptPath)` → `system("bash ${scriptPath}")` → 收集结果 → `rm -rf ${testRunDir}`。

`par.sh` 脚本字符串(`bootstrap/main.ss:437` 起)只含:`#!/bin/bash` / `MAX_JOBS=$(nproc)` / 每测试一行 `(${selfBin} build … && timeout 5 ${outBin} …) &` / `wait`。**全程不出现任何 `ulimit` / 资源限界设置**。

OS core dump 落点 = 崩溃进程的 CWD。进程链 `bin/ss test`(CWD=repo 根)→ `system("bash par.sh")` → `( … timeout 5 ${outBin} … ) &` 子 shell → 测试二进制 → (若测试内 `system("bin/ss run …")`)`bin/ss run` → `system(/tmp/ss_run_output.XXX)` → `ss_run_output.XXX` 二进制。**全链不改 CWD**,崩溃进程 CWD 一路继承 = repo 根。

环境:`/proc/sys/kernel/core_pattern`=`core` + `core_uses_pid`=`1` + `ulimit -c`=`unlimited` → 崩溃写 `core.<PID>` 到 CWD=repo 根。实测单个 core ≈ **1.07 GB**(`core.2004626` = 1,073,979,392 B,几乎全是 mimalloc 预留 arena),每轮 `bin/ss test` 攒一个;`core` 不在 `.gitignore` → 进 `git status`,有误 `git add` 风险。

具体触发者:`tests/phase5/run_exitcode_truncation.ss:22` 故意写一个除零(`1 / d`,`d==0`)fixture 经嵌套 `bin/ss run` 跑 —— 这是该测试为验证 `bin/ss run` 信号透传(`exit(128+sig)`)**有意制造的 SIGFPE**,崩溃本身非 bug;待修的是「测试驱动放任崩溃 core 落源码树」。

## 2. 假设破裂入口

`let script = "#!/bin/bash\nMAX_JOBS=$(nproc)\nRUNNING=0\n"`(`bootstrap/main.ss:437`)隐含一个**未校验假设**:

- **假设**「测试子进程树除退出码外不产生需落盘的副产物 / `RLIMIT_CORE` 无需在测试驱动层收束」—— **破裂**:测试套件本就含**故意崩溃**的测试(`run_exitcode_truncation` 为测信号透传必须 SIGFPE 一个子程序),且任意测试的真实 SIGSEGV/SIGABRT 亦同。`RLIMIT_CORE` 默认 `unlimited`、跨 `fork`+`exec` 继承,崩溃即落 ≈1GB core 到 CWD。

该假设破裂的根:`cmdTest` 在「为并行测试运行生成脚本」这一步,只规约了**并发度**(`MAX_JOBS`)这一个进程树属性,漏掉了**资源限界**(`RLIMIT_CORE`)—— 脚本不携带任何对崩溃副产物的约束。

## 3. 候选方案对比

| 候选 | 层次 | 改动 | 评估 |
|---|---|---|---|
| A | 数据层 patch | `cmdTest` 收尾在 `rm -rf ${testRunDir}` 旁加 `rm -f core.*` 清 repo 根 | 仅事后清理。**不消除假设破裂**:崩溃照发生、≈1GB core 照写盘,只是删掉 —— 每轮仍付 1GB 写+删 I/O 浪费。并发 `bin/ss test` 时 A 进程的 `rm -f core.*` 会删 B 进程同时段崩溃留下、B 尚未察看的 core(跨进程误删,I029 同类 race 史)。glob `core.*` 还可能误删用户 standalone 调试留下的 core。表面解,不解根因 |
| B | 接口层 trap | `cmdTest` 拼 `par.sh` 时 `#!/bin/bash` 之后加一行 `ulimit -c 0` | 在「脚本被生成」的确切点(`script` 字面值)拦截,直接收束整棵测试子进程树的 `RLIMIT_CORE`=0。`ulimit -c 0` 是 bash 内建、映射 `setrlimit(RLIMIT_CORE,{0,0})`,跨 `fork`+`exec` 继承 → 测试二进制、嵌套 `bin/ss build`/`bin/ss run`、`ss_run_output.*` 孙进程全继承 → 崩溃时内核**根本不写 core**(零 I/O)。假设「子进程树资源限界无需收束」被直接修正。**零新 builtin、零 CWD 复杂度、单 commit、seed 直接可编译**(`ulimit` 只是脚本字符串内容,不涉编译器能力)。信号与退出码不变 → `run_exitcode_truncation` 仍 PASS。顺带覆盖任何「测试自身崩溃」的同类污染 |
| C | 架构层 refactor | `cmdTest` 把每个测试执行的 CWD 沙箱进 `testRunDir`(`( cd ${testRunDir} && … timeout 5 ${outBin} … )`,延续 I029 目录沙箱) | 泛化到「所有 CWD 相对产物」(core + 测试误写的相对路径文件)。但:(1) **不阻止 core 写盘** —— 假设破裂照发生,≈1GB core 照写,只是落到 `testRunDir` 再随 `rm -rf` 删 → 仍付 1GB 写 I/O,相对 B 零增益反多浪费;(2) **撞回归** —— `run_exitcode_truncation`/`i026`/`i027` 三测用**相对路径** `bin/ss`(`system("bin/ss run …")`),CWD 一旦≠repo 根则 `bin/ss` 不解析,须额外 symlink/PATH 处理,blast radius 外溢。架构层但对本 bug(core 维度)非更根,纯多改 |
| D | 架构层 refactor | 新增 `setrlimit` builtin(checker `intFns` + `gen_registry` + runtime `ss_setrlimit` emit `call @setrlimit`),`cmdTest` 子进程 spawn 前调用 | `setrlimit(RLIMIT_CORE,0)` 是 B 的 `ulimit` 的 libc 直绑,语义同。但:(1) `cmdTest` 走 `system("bash par.sh")` 出 bash 子进程,**无 `fork`/`exec` 之间的控制点**可插 `setrlimit` —— 要么进程自身先 `setrlimit` 再 `system`(`bin/ss test` 自身崩溃也无 core,可能不期望),要么仍得靠脚本,builtin 反而用不上;(2) 新 builtin 被编译器自身(`main.ss`)调用 → seed 不识别 → **bootstrap 两步**(违独立 commit);(3) 为单一内部调用点引语言面全局 builtin = 过度扩面(I026 拒候选 B `getpid` 同款理由)。底层依赖链:D 依赖未落地的 `setrlimit` builtin,须先做基础 |
| E | 架构层(系统级) | 改 OS `/proc/sys/kernel/core_pattern` 指向 `/tmp` 或 `core_uses_pid`/`RLIMIT_CORE` 全局配置 | **scope 完全错位**:`core_pattern` 是内核全局配置,影响整机所有进程、非 repo 内可落地、非编译器可控、需 root 持久化。修一个编译器测试驱动的污染却动系统级旋钮 —— 物理上不属 `cmdTest` 修复范围。再上推一格即出本编译器 scope(印证 §字段 11 ladder 上界) |

## 4. 决策行

**选 B 因** 它在「`par.sh` 脚本被生成」的确切发生点(`cmdTest` 的 `script` 字面值)用 OS 标准的资源限界原语 `ulimit -c`(`setrlimit(RLIMIT_CORE)`)直接收束整棵测试子进程树 —— 5 候选中根因解决度最高且 scope 最收敛:`RLIMIT_CORE` 是 POSIX 中唯一决定「崩溃是否写 core」的 resource,置 0 后内核**零盘写**,跨 `fork`+`exec` 自动覆盖嵌套 `bin/ss run` 的 `ss_run_output.*` 孙进程,1 行字符串改动、零新 builtin、单 commit。**不选 A** 因事后 `rm` 不消除假设破裂(1GB 照写)且并发 `bin/ss test` 互删 core race。**不选更深的 C** 因 CWD 沙箱只「搬家」不阻 core 写盘(仍付 1GB I/O)、对本 bug 相对 B 零增益,还撞三个测试相对路径 `bin/ss` 回归。**不选更深的 D** 因 `cmdTest` 走 `system` 出 bash 无 `setrlimit` 插入控制点,且新 builtin 致 bootstrap 两步 + 过度扩面。**不选 E** 因 OS `core_pattern` 是系统级配置,scope 错位、非编译器可控。排序依据为根因解决度 + scope 收敛度 + 零 I/O 浪费,非工程量。

## 5. 长久评估

`ulimit -c` / `setrlimit(RLIMIT_CORE)` 是 POSIX 40+ 年稳定的资源限界原语,`go test`(`os/exec` 子进程不继承调用者 core 行为靠测试环境约束)/ CI 沙箱 / `pytest` 临时工作区均以「测试运行不留崩溃副产物进源码树」为基线 —— 无演化返工风险。**底层依赖链**:B 不依赖任何未落地能力(`ulimit` 是 bash 内建、`par.sh` 已是 bash 脚本),可独立单 commit 落地;D 依赖未落地的 `setrlimit` builtin,须先做基础。**N 年返工度** ≈ 0:`RLIMIT_CORE` 语义不变。唯一相邻演化点 —— 若未来 `bin/ss test` 改用 SS runtime 原生 `posix_spawn`/`fork` 而非 `system("bash …")`,届时可把脚本里的 `ulimit -c 0` 演进为 spawn 前 `setrlimit`(即候选 D)—— 但那是相邻架构增强,非本 bug 的「更根解」,B 当前即根因解决(core 维度)。

## 6. §实证(MNK §字段 12)

**根因定位 grep 证据**:

```
$ grep -rn "ulimit" bootstrap/
（无输出,exit 1 —— par.sh 生成全程无任何资源限界设置,坐实假设破裂)
$ grep -n '#!/bin/bash' bootstrap/main.ss
437:    let script = "#!/bin/bash\nMAX_JOBS=$(nproc)\nRUNNING=0\n"   ← 脚本字面值,改点
$ cat /proc/sys/kernel/core_pattern ; cat /proc/sys/kernel/core_uses_pid ; ulimit -c
core / 1 / unlimited   ← 崩溃写 core.<PID> 到 CWD,RLIMIT_CORE 默认无限
$ grep -rln "ulimit\|setrlimit\|RLIMIT" bootstrap/gen/
（无输出 —— SS 运行时无 setrlimit builtin,坐实候选 D 须先补 builtin)
```

**最危险假设最小 spike** —— 候选 B 最危险假设:「`par.sh` 行首 `ulimit -c 0` 能被整棵测试子进程树(含嵌套子 shell 派生的崩溃孙进程)继承,使崩溃零 core」:

```
# 上轮已实测核机制:嵌套 bin/ss run 跑除零 fixture,CWD=temp 目录 →
#   core.2004626 (1,073,979,392 B) ELF core file, from '/tmp/ss_run_output.N12weL'
#   → 坐实「崩溃 core 落继承的 CWD」「无 ulimit 时 RLIMIT_CORE=unlimited 写 1GB」
# 本轮 spike:对照「par.sh 结构脚本 ± ulimit -c 0」跑崩溃子进程,验证 ulimit -c 0
#   行首一次置 0 即令整棵 ( … ) & 子 shell 树继承、崩溃零 core(VCM §2 行为验证坐实)。
```

spike 与上轮核机制实证共同确证:`RLIMIT_CORE` 跨 `fork`+`exec` 继承是 POSIX 保证,`ulimit -c 0` 置于 `par.sh` 行首即覆盖全子进程树。回归测试 `tests/phase5/i031_cmdtest_core_dump_pollution.ss` 用确定性源码核对手法(对标 I028/I029 —— `cmdTest` 行为驱动测试会在 `bin/ss test` 内嵌套 `bin/ss test` 与外层并行 runner race):提取 `bootstrap/main.ss` 的 `cmdTest` 函数体,断言其含 `ulimit -c 0`。完整 bootstrap 三阶段固定点 + 全测见 `tools/bugfix_reports/2026-05-19-i031-cmdtest-core-dump-pollution.bugfix` §verify。
