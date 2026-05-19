# I031 — `bin/ss test` 把崩溃测试子进程的 core 转储抛到 repo 根

**父决策:** 无(独立 root cause —— `bin/ss test` 测试驱动 `cmdTest` 的缺陷,与 I026 `cmdRun` / I027 comptime `shellOutput` / I029 `cmdTest` 同 family「测试基建不隔离」;但 I026/I027/I029 隔离的是 `/tmp` **具名路径**,本 bug 是 OS core dump 走 **CWD(非具名路径)** 逃逸该沙箱 —— 正交维度)
**状态:** Resolved(本轮立项 + 修复同 commit,`git log --grep I031`)—— `cmdTest` 拼并行测试脚本时 `#!/bin/bash` 之后加 `ulimit -c 0`,收束整棵测试子进程树的 `RLIMIT_CORE`=0;回归测试 `tests/phase5/i031_cmdtest_core_dump_pollution.ss`
**颗粒度:** 立项 + 修复同轮(用户 next_prompt 授权);修复 = `cmdTest` 脚本字符串加一行 `ulimit -c 0`,标准改档
**依赖:** 无。`ulimit` 是 bash 内建、`par.sh` 已是 bash 脚本;修复不依赖未落地能力
**创建:** 2026-05-19
**立项由:** 上轮 Plan 型调研诊断(`bin/ss test` 每轮向 repo 根抛 core 转储);next_prompt 指定本轮专项立项 + 修复

---

## 现象

`bin/ss test`(`cmdTest`,`bootstrap/main.ss:420`)每轮跑动后,repo 根多出 ≈1GB 的 `core.<PID>` 文件。

`cmdTest` 拼并行测试脚本(`:437`)`let script = "#!/bin/bash\nMAX_JOBS=$(nproc)\nRUNNING=0\n"` —— 只规约并发度,**不收束子进程树的资源限界**:

- `RLIMIT_CORE` 默认 `unlimited`,跨 `fork`+`exec` 继承 → 测试二进制、嵌套 `bin/ss build`/`bin/ss run`、`ss_run_output.*` 孙进程全继承。
- OS core dump 落点 = 崩溃进程 CWD;进程链 `bin/ss test` → `bash par.sh` → `( … timeout 5 ${outBin} … ) &` → 测试二进制 → `bin/ss run` → `ss_run_output.*` 全程不改 CWD → 继承自 `bin/ss test` 调用处 = repo 根。
- 环境 `core_pattern`=`core` + `core_uses_pid`=`1` → 崩溃写 `core.<PID>` 到 repo 根。

具体触发者:`tests/phase5/run_exitcode_truncation.ss:22` 为验证 `bin/ss run` 信号透传(`exit(128+sig)`),**有意**经嵌套 `bin/ss run` 跑一个除零(`1/d`,`d==0`)fixture → SIGFPE → `ss_run_output.*` 孙进程崩溃。该崩溃是测试设计使然(非编译器 bug);待修的是「测试驱动放任崩溃 core 落源码树」。

实测:嵌套 `bin/ss run` 跑除零 fixture,CWD=temp 目录 → `core.2004626` = 1,073,979,392 B(`ELF core file, from '/tmp/ss_run_output.N12weL'`)。`core` 不在 `.gitignore` → 进 `git status`,有误 `git add` 风险 + 磁盘累积(每轮 +≈1GB)。

## 为何此前未被根治

崩溃归类「其他 —— 测试故意制造的信号崩溃」,易被当作「测试正常副产物」忽略;`git status` 偶尔被手动清理掩盖累积。I026/I027/I029 修了 `/tmp` **具名路径** race,但 OS core dump 走 **CWD(非具名)** —— 与具名路径正交,逃逸了 family 此前三轮的沙箱化。

## root cause

`cmdTest` 在「生成并行测试运行脚本」这一步,只规约了**并发度**(`MAX_JOBS`)一个进程树属性,漏掉**资源限界**(`RLIMIT_CORE`)。脚本不携带任何对崩溃副产物的约束,而测试套件本就含故意崩溃的测试(`run_exitcode_truncation`)→ 假设「测试子进程树除退出码外不产生需落盘副产物」破裂。业界对标 `docs/1-axioms.md §V3`:`go test` / `cargo test` / CI 沙箱不把崩溃副产物留进源码树。

## 修复(Execute 轮坐实)

按 bug 修复 harness,`i031_cmdtest_core_dump_pollution.options.md`(`bug_options_linter` 6/6 GATE OK)对比 5 候选:A 数据层事后 `rm -f core.*`(1GB 照写 + 并发互删 race)、B 接口层 `par.sh` 行首 `ulimit -c 0`、C 架构层 CWD 沙箱(只搬家不阻写、撞相对路径 `bin/ss` 回归)、D 架构层 `setrlimit` builtin(`cmdTest` 走 `system` 出 bash 无插入点 + bootstrap 两步)、E 系统级 `core_pattern`(scope 错位)。

**实际修复(候选 B —— 接口层 trap)**:`cmdTest` 拼 `par.sh` 时 `script` 字面值 `#!/bin/bash` 之后加一行 `ulimit -c 0`(`bootstrap/main.ss:437` 区域)。`ulimit -c 0` 是 bash 内建、映射 `setrlimit(RLIMIT_CORE,{0,0})`,跨 `fork`+`exec` 继承 → 整棵测试子进程树(含嵌套 `bin/ss run` 的 `ss_run_output.*` 孙进程)`RLIMIT_CORE`=0 → 崩溃时内核**零 core 写盘**。信号与退出码不变 → `run_exitcode_truncation` 仍 PASS;顺带覆盖任何「测试自身崩溃」的同类污染。

**为何不选 C 架构层 CWD 沙箱**:CWD 沙箱只把 core「搬家」到 `testRunDir` 再 `rm -rf`,≈1GB core 仍写盘(零 I/O 收益反多浪费),且 `run_exitcode_truncation`/`i026`/`i027` 三测用相对路径 `bin/ss`、CWD≠repo 根则不解析 → blast radius 外溢。B 在「脚本生成点」用 `RLIMIT_CORE`(POSIX 唯一管 core 写否的旋钮)直接阻止写盘,根因解决度更高且 scope 收敛。

**为何不改 `.gitignore`**:`ulimit -c 0` 已根除 `bin/ss test` 路径全部 core,I031(`bin/ss test` 污染)100% 闭合。`.gitignore core` 不修 I031,仅对 standalone `bin/ss run` 崩溃这一**另一面**兜底 —— 不属本 issue scope。

验证:RED `grep -rn "ulimit" bootstrap/` 空 → GREEN 命中;`./build.sh bootstrap` 三阶段固定点(stage2==stage3);`bin/ss test tests/` 334 passed / 3 failed(3 失败全 pre-existing 编译期失败 `reactive`/`dispatcherServlet` 未定义 + `llc` 类型错,0 新增 regression);`bin/ss test` 后 repo 根 0 个 `core.*`(端到端坐实)。`bug_options_linter` 6/6 + `bugfix_linter` 6/6 ALL GATES PASSED。因果证据 `tools/bugfix_reports/2026-05-19-i031-cmdtest-core-dump-pollution.bugfix`,回归测试 `tests/phase5/i031_cmdtest_core_dump_pollution.ss`(源码核对法,无 race —— 对标 I028/I029)。

## 反向

不立项 → 这个测试驱动污染隐患仅留在上轮对话与诊断,下轮 Claude 读不到具体修复(MNK §核心原则 4);`bin/ss test` 每轮继续向 repo 根抛 ≈1GB core,污染 `git status`、累积磁盘,且与「测试故意崩溃」混淆易被长期当噪声忽略。
