# I029 — `cmdTest` 固定共享 `/tmp` 路径非并发安全 — 修复方案对比(MNK §轨 1)

**bug**: `cmdTest`(`bootstrap/main.ss:420`)拼并行 test 脚本时用三类跨进程固定路径:`/tmp/ss_test_${idx}`(`:436`,每测试编译输出二进制)、`/tmp/ss_res_${idx}`(`:437`/`:453`,每测试退出码结果文件)、`/tmp/ss_test_par.sh`(`:444`/`:445`,并行脚本本身)。`${idx}` 是 per-index 但 `let idx = 0`(`:433`)每次 `cmdTest` 调用从 0 重数。`bin/ss test` 是无任何互斥的普通 CLI,任意两个并发执行即在这些路径上 race。

**父约束**: 独立 root cause(I029,父决策「无」)。I028 §关联观察(`docs/4-issues/I028-runtime-cache-dead-subsystem.md:53-55`)明列本问题为下游 issue 候选。业界对标 `docs/1-axioms.md §V3`(mature compilers best practices)—— `go test` / `cargo test` 用每次调用唯一临时目录,并发安全是 test 子命令的基线契约。

**结论**: **选 C —— `cmdTest` 一次 `mktemp -d` 取进程唯一目录承载全部产物**(见 §4 决策行)。

---

## 1. 根因机理(坐实)

`bin/ss test <dir>` 的 `cmdTest`:收集测试文件 → 为每个文件按 `idx` 拼一段 `(bin/ss build … -o /tmp/ss_test_${idx} && timeout 5 /tmp/ss_test_${idx}; echo $? > /tmp/ss_res_${idx}) &` 入并行脚本 → `writeFile("/tmp/ss_test_par.sh", script)` → `system("bash /tmp/ss_test_par.sh")` → 逐 `idx` `readFile("/tmp/ss_res_${idx}")` 收集退出码 → cleanup `rm -f /tmp/ss_test_par.sh /tmp/ss_test_* /tmp/ss_res_*`。

三类路径全为跨进程固定常量(`${idx}` 每次从 0 重数 → 跨进程必复用同一组 `0..N-1`)。两个并发 `bin/ss test`(进程 P1 / P2)race 实例:

1. P1 的 `bin/ss build -o /tmp/ss_test_5` 写二进制时 P2 的 `bin/ss build -o /tmp/ss_test_5` 也在写 → 二进制交错损坏;P1 的 `timeout 5 /tmp/ss_test_5` exec 时 P2 的 `build` 覆写它 → P1 exec 撕裂半截二进制 → **段错误**
2. P1 收尾 `rm -f /tmp/ss_test_* /tmp/ss_res_*` 删 P2 仍在运行/待运行的二进制与结果文件 → P2 的 `timeout 5 ${outBin}` 找不到二进制 / `readFile(resFile)` 读空 → 误判 FAIL
3. P1 与 P2 都 `writeFile("/tmp/ss_test_par.sh", …)` → 后写者覆盖先写者的脚本
4. P1 `readFile("/tmp/ss_res_3")` 时拿到 P2 写入的退出码 → 张冠李戴

→ 非确定的 test 失败 / 段错误 / flaky,且因「非确定」易被误判为 codegen 非确定性 bug(I025/I026/I027 同类误诊史;I028 收尾自述「I027 收尾观测的段错误若与并发同现,此为最可能来源」)。

## 2. 假设破裂入口

`const outBin = \`/tmp/ss_test_${idx}\``(及 `resFile` / `/tmp/ss_test_par.sh` 两个同族)隐含一个**未校验假设**:

- **假设**「同一时刻至多一个 `bin/ss test` 进程占用 `/tmp/ss_test_*` / `/tmp/ss_res_*` / `/tmp/ss_test_par.sh` 这组路径」—— **破裂**:`bin/ss test` 是普通 CLI,无文件锁 / 无 PID 命名空间 / 无任何互斥。CI 矩阵并行、开发者多终端、测试内 `system("bin/ss test …")` 嵌套 → 多个 `bin/ss test` 进程天然并发。`${idx}` 从 0 重数把「进程私有的测试构建中间态」误当「全局单例资源」,假设在并发下必然破裂。

该假设破裂的根:`cmdTest` 在「为本次 test run 选择编译输出 / 结果 / 脚本路径」这一步,选了与进程身份无关的常量(`/tmp/ss_test_par.sh`)与每次从 0 重数的索引(`${idx}`)—— 路径不携带任何 per-invocation 唯一性。

## 3. 候选方案对比

| 候选 | 层次 | 改动 | 评估 |
|---|---|---|---|
| A | 数据层 patch | `${idx}` → `/tmp/ss_test_` + `randomInt(1000000)` 随机后缀 | 仅把索引换成随机数。**实测破裂**:运行时 `srand` 以 `time(NULL)` 截 i32 播种(I026 已实证 `gen_decls.ss` `%_seedtime`),**秒级粒度**。两个 `bin/ss test` 在同一秒内启动 → 同种子 → `randomInt()` 序列相同 → 路径仍碰撞;并发 race 的触发窗正是「同秒并发」,A 在该窗口完全失效。且固定脚本路径 `/tmp/ss_test_par.sh` 与 cleanup glob `rm -f /tmp/ss_test_*` 跨进程销毁均未触及 —— 假设「randomInt 跨进程唯一」破裂,不解根因 |
| B | 接口层 trap | 三路径各自 `shell("mktemp …")`:`outBin`/`resFile` loop 内逐次 mktemp,脚本路径单次 mktemp | next_prompt 字面建议(「对标 I026 把三路径改为每次调用唯一」)。但只把固定名换成随机名,**共享 `/tmp` 命名空间未消除**:(1) `outBin`/`resFile` 在 N 个测试的 loop 内 → **2N 次 `mktemp` 子进程**调用,纯开销;(2) cleanup 无法安全 glob —— 随机名要么把 2N+1 条路径全 track 进字符串再逐条 `rm`,要么 `rm -f /tmp/ss_test.*` glob 仍命中并发 peer 的同前缀文件 → **line 465 的 cleanup 跨进程销毁 race 未根除**。假设「随机化名字 = 并发安全」破裂:命名空间仍共享,cleanup 仍是 race 参与者 |
| C | 架构层 refactor | `cmdTest` 起手一次 `const testRunDir = shell("mktemp -d /tmp/ss_test_run.XXXXXX").trim()` + 空值 guard;三类产物改 `${testRunDir}/test_${idx}` / `${testRunDir}/res_${idx}` / `${testRunDir}/par.sh`;cleanup `rm -f /tmp/ss_test_*` → `rm -rf ${testRunDir}`;`cmdClean` glob `/tmp/ss_test_* /tmp/ss_res_* /tmp/ss_test_par.sh` → `/tmp/ss_test_run.*`(`rm -f` → `rm -rf`) | 在共享命名空间**诞生的确切点**(`cmdTest` 起手)用 OS 的 race-free 唯一目录原语 `mktemp -d` 给本次 test run 一个**私有命名空间**。`mktemp -d` 原子创建唯一目录(coreutils 现成原语),`shell` 是既有 builtin(I026 已实证 popen 捕获 stdout)。**一次** mktemp(非 B 的 2N+1 次);三类产物 + `bin/ss build` 派生的 `.ll`/`.o`/`.ll.str` 全落目录内 → 整个 test run 的磁盘态进程私有;cleanup `rm -rf ${testRunDir}` 仅删本进程目录、glob-free、不可能触他进程文件 —— **同时根治 line 465 cleanup 跨进程销毁**。`cmdTest` 经 `system()` 出 `bin/ss build` 子进程、路径仅是脚本里的字符串,无 `compile()` 契约 → 改动闭合在 `cmdTest` 单函数 |
| D | 架构层 refactor | 弃 `/tmp/ss_res_${idx}` 结果文件:并行脚本每 job 改 `echo "RES <idx> $?"` 打 stdout,`system` 改 `shell` 捕获全 stdout 后解析(对标 I027 消中转文件) | 只消除三类路径里的**一类**(result files)。binary `outBin`(`bin/ss build` 物理必需的磁盘文件,`llc`/`musl-gcc`/`exec` 不可消除)与并行脚本文件仍需进程隔离 → D **仍须** C 的 `mktemp -d` 目录承载这两类。∴ D = C + 一个正交 refactor,对 binary/script 两类路径零额外根因增益,徒增 scope;且 stdout 解析比 `readFile` 退出码文件脆弱(测试自身 stdout 噪声混入)。错误建模:本 bug 根因是「路径共享」不是「有 IPC 文件」 |

## 4. 决策行

**选 C 因** 它在共享命名空间被选定的确切发生点(`cmdTest` 起手)用业界标准的 OS race-free 唯一目录原语 `mktemp -d` 给本次 test run 一个进程私有命名空间 —— 4 候选中根因解决度最高:不仅令三类路径全部进程唯一(目录唯一 → 内部 per-index 命名在单次调用内天然不冲突),还**唯一同时根治 line 465 的 cleanup glob 跨进程销毁**(`rm -rf ${testRunDir}` 锚定自有目录),且只需**一次** mktemp、`cmdTest` 单函数闭合。**不选 A** 因 `srand` 秒级播种使 `randomInt` 在「同秒并发」(正是 race 触发窗)内跨进程不唯一,且 cleanup race 完全未触,假设破裂、不解根因。**不选次优 B**(next_prompt 字面建议)因逐路径 `mktemp` 只随机化名字、共享 `/tmp` 命名空间未消除 —— cleanup 无法安全 glob(跨进程销毁 race 残留)、loop 内 2N 次 mktemp 子进程纯开销;C 比 B 上推一格(同 I027 Execute 轮按 §字段 11 ladder 上推手法)。**不选 D** 因它只消除 result files 一类、binary 与 script 两类仍须 C 的目录隔离,D = C + 正交 refactor 无额外根因增益且 stdout 解析更脆弱。排序依据为根因解决度 + cleanup race 是否根治,非工程量。

## 5. 长久评估

`mktemp -d` 是 POSIX / coreutils 的 race-free 唯一临时目录原语(原子创建 + 随机后缀 + 0700 权限),`go test` / `cargo` 均以 per-invocation 唯一临时目录承载测试构建中间态 —— 40+ 年稳定的业界规范(`docs/1-axioms.md §V3`),无演化返工风险。**底层依赖链**:C 不依赖任何未落地能力(`shell` builtin + `mktemp -d` 均现成,§6 spike 实证),可独立单 commit 落地;A 依赖「跨进程唯一随机数」(SS 运行时 `srand` 秒级播种不提供),B 依赖未消除的共享命名空间。**N 年返工度** ≈ 0:`mktemp -d` 语义不变;唯一长期演化点是若未来 SS 落地原生 `fork`-`exec`-`waitpid` runtime 能力,`cmdTest` 可演进为 SS 内编排并行、彻底不落 bash 脚本盘 —— 但那是相邻架构增强(新语言能力,独立更大项目),非本 bug 的「更根解」,C 当前即根因解决。**与 I026 拒「目录隔离」候选 D 的区别**:I026 `cmdRun` 走 `compile()`、改路径派生契约会外溢 `cmdBuild`/`cmdBuildLegacy`,故 I026 选 mktemp-file;`cmdTest` 是 `system()` 出 `bin/ss build` 子进程、路径仅脚本字符串,无 `compile()` 契约 → 「目录隔离」反对意见在此不成立,C 可用最干净的目录粒度。

## 6. §实证(MNK §字段 12)

**根因定位 grep 证据**:

```
$ grep -nE '/tmp/ss_(test|res)_\$\{|/tmp/ss_test_par\.sh' bootstrap/main.ss
436:        const outBin = `/tmp/ss_test_${idx}`            ← 每测试二进制,跨进程固定
437:        const resFile = `/tmp/ss_res_${idx}`            ← 每测试结果文件,跨进程固定
444:    writeFile("/tmp/ss_test_par.sh", script)            ← 并行脚本,跨进程固定
445:    system("bash /tmp/ss_test_par.sh")
453:        const resFile = `/tmp/ss_res_${i}`              ← 收集端同固定路径
465:    system(`rm -f /tmp/ss_test_par.sh /tmp/ss_test_* /tmp/ss_res_*`)  ← cleanup glob 跨进程销毁
591: …rm -f … /tmp/ss_test_* /tmp/ss_res_* /tmp/ss_test_par.sh           ← cmdClean(连带同步)
$ grep -n 'let idx = 0' bootstrap/main.ss
433:    let idx = 0                                         ← idx 每次 cmdTest 调用从 0 重数,坐实跨进程必碰撞
$ grep -rn '/tmp/' bootstrap/
（仅 main.ss:cmdRun 已 mktemp/I026、cmdTest 本 bug、cmdClean —— 无其它固定共享 /tmp 路径,
  same_pattern triage:cmdBuild 实测 -o 由调用方传无硬编码 → same_pattern_count = 0）
```

**最危险假设最小 spike** —— 候选 C 最危险假设:「`shell("mktemp -d …")` 创建唯一目录,`writeFile` / `bin/ss build -o` / exec 可在其中工作」:

```
$ cat /tmp/ss_i029_spike.ss
function main() {
    const d1 = shell("mktemp -d /tmp/ss_test_run.XXXXXX").trim()
    const d2 = shell("mktemp -d /tmp/ss_test_run.XXXXXX").trim()
    …(d1/d2 空 / 相等 / 前缀错 → exit 1;writeFile + bin/ss build -o + exec 任一失败 → exit 1)
}
$ bin/ss run /tmp/ss_i029_spike.ss
SPIKE OK: distinct dirs d1=/tmp/ss_test_run.tKgmzq d2=/tmp/ss_test_run.RC89A1;
         writeFile + build -o + exec inside mktemp -d dir all work
```

spike 确证:`shell` 经 popen 捕获 `mktemp -d` stdout,`.trim()` 去尾换行,两次调用得各异唯一目录;`writeFile` / `bin/ss build -o` / 子进程 exec 在该目录内全部正常。回归测试 `tests/phase5/i029_cmdtest_tmp_path_concurrency.ss` 用确定性、无 race 的源码核对法坐实修复(对标 I028 —— `cmdTest` 的行为驱动测试会嵌套 `bin/ss test` 与外层并行 runner race):核对 `bootstrap/main.ss` 的 `cmdTest` 函数体不含 `/tmp/ss_test_$` / `/tmp/ss_res_$` / `/tmp/ss_test_par` 固定共享路径、且含 `mktemp -d`。完整 bootstrap 三阶段固定点 + 全测见 `tools/bugfix_reports/2026-05-19-i029-cmdtest-tmp-path-concurrency.bugfix` §verify。
