# I026 — `bin/ss run` 编译输出路径非并发安全 — 修复方案对比(MNK §轨 1)

**bug**: `cmdRun`(`bootstrap/main.ss:379`)`const outBin = "/tmp/ss_run_output"` —— 硬编码进程间共享常量路径。`compile(inputFile, outBin, …)` 由 `outBin` 派生全部编译中间产物:`generateToFile` 写 `outBin.ll`(+ `.ll.str`)、`llc-18` 写 `outBin.o`、`musl-gcc` 链接出 `outBin` 二进制。四条路径 `/tmp/ss_run_output{,.ll,.ll.str,.o}` 全是跨进程固定常量,`bin/ss run` 又是无任何互斥的普通 CLI。任意两个 `bin/ss run` 并发执行 → 二者在这四条路径上 race。

**父约束**: 独立 root cause(I026,父决策「无」)。业界对标 `docs/1-axioms.md §V3`(mature compilers best practices)—— `go run` / `cargo run` / 传统 `cc` 驱动均为每次调用用唯一临时路径(`mktemp` 风格),并发安全是 `run` 子命令的基线契约。

**结论**: **选 C —— `cmdRun` 用 `shell("mktemp …")` 取进程唯一路径**(见 §4 决策行)。

---

## 1. 根因机理(坐实)

`bin/ss run <prog>` 的 `cmdRun` 三步:`compile(prog → /tmp/ss_run_output)` → `system("/tmp/ss_run_output <args>")` → 解码 wait-status 退出。

`compile()`(`bootstrap/main.ss:597`)由形参 `outputFile`(= `outBin`)派生中间产物路径:

- `llFile = outputFile + ".ll"` → `/tmp/ss_run_output.ll`,`generateToFile` 写入(连带 `.ll.str` 字符串表)
- `objFile = outputFile + ".o"` → `/tmp/ss_run_output.o`,`llc-18 -filetype=obj` 写入
- `outputFile` 本身 → `/tmp/ss_run_output`,`musl-gcc … -o` 链接写入
- 收尾 `rm -f ${llFile} ${llFile}.str ${objFile}`

四条路径全为跨进程固定常量。两个并发 `bin/ss run`(进程 P1 / P2)race 实例:

1. P1 的 `musl-gcc` 写 `/tmp/ss_run_output` 二进制时 P2 的 `musl-gcc` 也在写 → 二进制交错损坏
2. P1 `system()` exec `/tmp/ss_run_output` 运行时 P2 的 `musl-gcc` 覆写它 → `ETXTBSY`(gcc 写运行中可执行文件失败)或 P1 exec 到半截二进制
3. P1 的 `llc-18` 读 `/tmp/ss_run_output.ll` 时 P2 的 `generateToFile` 覆写它 → P1 的 llc 拿到撕裂 IR → 编译失败
4. P1 收尾 `rm -f /tmp/ss_run_output.o` 时 P2 的 `musl-gcc` 仍需该 `.o` → P2 链接失败

→ 非确定的编译失败 / 错误二进制 / flaky 测试,且因「非确定」易被误判为 codegen 非确定性 bug(I025 同类误判史)。

## 2. 假设破裂入口

`const outBin = "/tmp/ss_run_output"` 隐含一个**未校验假设**:

- **假设**「同一时刻至多一个 `bin/ss run` 进程占用 `/tmp/ss_run_output{,.ll,.ll.str,.o}` 这组路径」—— **破裂**:`bin/ss run` 是普通 CLI,无文件锁 / 无 PID 命名空间 / 无任何互斥。CI 流水线、并行 test runner(`bin/ss test` 的 `MAX_JOBS=$(nproc)` 并发)、开发者多终端 → 多个 `bin/ss run` 进程天然并发。固定常量路径把「进程私有的编译中间态」误当「全局单例资源」,假设在并发下必然破裂。

该假设破裂的根:`cmdRun` 在「为本次 run 选择编译输出路径」这一步,选了一个与进程身份无关的常量 —— 路径不携带任何 per-invocation 唯一性。

## 3. 候选方案对比

| 候选 | 层次 | 改动 | 评估 |
|---|---|---|---|
| A | 数据层 patch | `outBin = "/tmp/ss_run_output_" + Math.randomInt(1000000)` | 仅把常量换成随机数,形式上「唯一」。**实测破裂**:运行时 `srand` 以 `time(NULL)` 截 i32 播种(`gen_decls.ss:317-318` `%_seedtime = call i64 @time` → `srand`),**秒级粒度**。两个 `bin/ss run` 在同一秒内启动 → 同种子 → `randomInt()` 首个返回值相同 → 路径仍碰撞。并发 race 的触发时间窗正是「同秒并发」,A 在该窗口内完全失效 —— 假设「randomInt 跨进程唯一」破裂,不解根因 |
| B | 架构层 refactor | 新增 `getpid()` builtin(checker `intFns` + `gen_registry` builtinMap/funcRetTypes + runtime `ss_getpid` emit `call @getpid`),`outBin = "/tmp/ss_run_output_" + getpid()` | PID 是最直接的进程唯一原语,根因解决度高。但:(1) **bootstrap 两步** —— 编译器自身(`main.ss`)调用新 builtin,seed(旧 `bin/ss`)不识别 `getpid` → stage1 必崩;须拆「commit 1 加 builtin + bootstrap」「commit 2 用之」两提交,违「独立 commit」。(2) 为**单一内部调用点**(仅 `cmdRun`)引入一个语言面全局 builtin = 过度扩面(违 §反 over-engineer)。(3) PID 会被 OS 回收,串行两次 `bin/ss run` 可能撞同 PID → 回归测试失去确定性。底层依赖链:B 依赖未落地的 `getpid` builtin,须先做基础 |
| C | 接口层 trap | `outBin = shell("mktemp /tmp/ss_run_output.XXXXXX").trim()` + 空值 guard;`cmdRun` run 毕清理 `${outBin}*`;`cmdClean` glob 同步 `/tmp/ss_run_output` → `/tmp/ss_run_output*` | 在共享固定路径**诞生的确切点**(`cmdRun` 的 `outBin` 赋值)拦截,改由 OS 的 race-free 唯一临时文件原语 `mktemp` 生成路径。`shell` 是**既有** builtin(`gen_rt_shell.ss`:popen 捕获 stdout 作 RC string,seed 已识别),`mktemp` 是 coreutils 现成原语 —— **零新 builtin、单 commit、seed 直接可编译**。`outBin` 唯一 → 派生的 `.ll`/`.ll.str`/`.o` 全唯一,`compile()` 签名与契约**不动**。`mktemp` 原子 `O_EXCL` 创建文件、随机后缀 → 串行两次调用确定性各异(回归测试可确定性化)。run 毕清理避免 mktemp 唯一化引入的 `/tmp` 累积 |
| D | 架构层 refactor | `mktemp -d` 建每进程唯一**目录**,改 `compile()` 接收 dir、产物全落 dir 内 | 隔离粒度更粗(整目录)。但 `compile()` 被 `cmdBuild` / `cmdBuildLegacy` 共享,改其路径派生契约 → blast radius 外溢到 `build` 子命令,远超 I026「`cmdRun` 单函数」scope。且 C 的 mktemp-file 已给完整隔离(唯一 base → 派生路径全唯一),D 的「目录级」隔离相对 C 零增益 —— 纯粹多改 `compile()` 而不多解决任何 race |
| E | 架构层 refactor | `cmdRun` 弃 `system()`+磁盘中间文件,走内存 / 管道直传 `llc`/`musl-gcc` | 误判问题:`llc-18` / `musl-gcc` 是外部进程,其输入输出**必经磁盘文件**(`.ll`/`.o`/二进制),无法消除磁盘中间态。本 bug 的根因不是「有磁盘中间文件」而是「中间文件路径非进程唯一」。E 试图消除一个无法消除且非根因的东西,是对问题的错误建模 |

## 4. 决策行

**选 C 因** 它在「共享固定路径被选定」的确切发生点(`cmdRun` 的 `outBin` 赋值)用业界标准的 OS race-free 唯一化原语 `mktemp` 直接消除「进程间共享常量路径」这一根因 —— 5 候选中根因解决度最高且 scope 不外溢:`outBin` 一处唯一化即令派生的 `.ll`/`.ll.str`/`.o`/二进制全部唯一,`compile()` 契约不动、`cmdRun` 单函数闭合。**不选 A** 因 `srand` 秒级播种使 `randomInt` 在「同秒并发」(正是 race 触发窗)内跨进程不唯一,假设破裂、不解根因。**不选更深的 B** 因新 builtin 被编译器自身调用 → bootstrap 必须两提交(违独立 commit),且为单一内部调用点引入语言面 builtin 属过度扩面,PID 回收还使回归测试失确定性。**不选更深的 D** 因改 `compile()` 路径契约会外溢到 `cmdBuild`,而其「目录级隔离」相对 C 零增益。**不选 E** 因外部 `llc`/`musl-gcc` 的磁盘中间文件物理不可消除,E 错误建模了根因。排序依据为根因解决度 + scope 收敛度,非工程量。

## 5. 长久评估

`mktemp` 是 POSIX / coreutils 的 race-free 唯一临时文件原语(原子 `O_EXCL` 创建 + 随机后缀),`go run` / `cargo run` / 传统 `cc` 驱动均以 `mktemp` 风格 per-invocation 唯一路径承载编译中间态 —— 这是 40+ 年稳定的业界规范,无演化返工风险。**底层依赖链**:C 不依赖任何未落地能力(`shell` builtin + `mktemp` 均现成),B 依赖未落地的 `getpid` builtin —— 故 C 可独立单 commit 落地,B 必须先做基础 builtin。**N 年返工度** ≈ 0:`mktemp` 语义不变;唯一长期演化点是若未来 SS 落地 `getpid` / `fork`-`exec`-`waitpid` runtime 能力,`cmdRun` 可演进为 PID 命名或直接 spawn,届时 C 的 `shell(mktemp)` 自然被替换 —— 但那是相邻架构增强,非本 bug 的「更根解」,C 当前即根因解决。

## 6. §实证(MNK §字段 12)

**根因定位 grep 证据**:

```
$ grep -n 'outBin = "/tmp/ss_run_output"' bootstrap/main.ss
379:    const outBin = "/tmp/ss_run_output"          ← 硬编码固定常量,无 pid/唯一性
$ grep -n 'ss_run_output' bootstrap/main.ss
379:    const outBin = "/tmp/ss_run_output"
591: …rm -f … /tmp/ss_run_output …                   ← cmdClean 清理项(连带同步)
$ printf 'function main(){println("x")}' >/tmp/x.ss; bin/ss run /tmp/x.ss | head -1
compiled: /tmp/ss_run_output                          ← 每次 run 恒为同一常量路径(坐实)
$ grep -rn 'getpid' bootstrap/gen/
（无输出 —— SS 运行时无 getpid builtin,坐实候选 B 须先补 builtin)
$ sed -n '317,318p' bootstrap/gen/gen_decls.ss
  %_seedtime = call i64 @time(ptr null)
  …  call void @srand(i32 %_seedtime32)               ← srand 秒级播种,坐实候选 A 破裂
```

**最危险假设最小 spike** —— 候选 C 最危险假设:「`shell("mktemp …")` 捕获 stdout 且产出彼此唯一的路径」:

```
$ cat /tmp/ss_i026_spike.ss
function main() {
    const p1 = shell("mktemp /tmp/ss_run_output.XXXXXX").trim()
    const p2 = shell("mktemp /tmp/ss_run_output.XXXXXX").trim()
    …(p1=="" / p1==p2 / 前缀错 → exit 1)
}
$ bin/ss run /tmp/ss_i026_spike.ss
p1=[/tmp/ss_run_output.vVQLsn]
p2=[/tmp/ss_run_output.Z6ScJZ]
SPIKE OK: shell(mktemp) yields distinct unique paths
```

spike 确证:`shell` 经 popen 捕获 `mktemp` stdout,`.trim()` 去尾换行,两次调用得各异唯一路径。回归测试 `tests/phase5/i026_cmdrun_tmp_output_path.ss` 用确定性手法坐实修复:`bin/ss run` 编译时 `println("compiled: <outBin>")`,连跑两次解析该路径 —— 修复前两次恒等于旧硬编码 `/tmp/ss_run_output`,修复后为各异 `/tmp/ss_run_output.XXXXXX`。完整 bootstrap 三阶段固定点 + 全测见 `tools/bugfix_reports/2026-05-19-i026-cmdrun-tmp-output-path.bugfix` §verify。
