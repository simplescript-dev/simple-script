# I028 — 运行时 IR 缓存子系统死代码:`buildRuntimeCache` 确定性 llc 失败 + 无消费者

**父决策:** 无(独立 root cause —— `gen_rt_cache.ss` 缓存子系统缺陷;与 I026/I027 **不同 bug 类**:I026/I027 是「固定共享 `/tmp` 路径并发 race」,本 issue 经实测**证伪并发假设**,真根因是「确定性 llc 失败 + 子系统无消费者」)
**状态:** Resolved at 8578b0e(2026-05-19 — Execute 轮按 bug 修复 harness 选候选 C 架构层「删整个 dead 缓存子系统」修复;RED→GREEN + bootstrap 三阶段固定点 + 回归测试 tests/phase5/i028_runtime_cache_dead_subsystem.ss;bug_options_linter 6/6 + bugfix_linter 6/6)
**颗粒度:** 立项轮 = 纯文档(本文件);修复 = Execute 轮按 bug 修复 harness,档位视候选(删整个 dead 子系统 标准改 / 补 typedecl 微改 / 接活缓存 大改)
**依赖:** 无。修复若走「删子系统」零依赖
**创建:** 2026-05-19
**立项由:** I027 收尾后下一轮 —— next_prompt 指定专项调研 `gen_rt_cache.ss`,**假设** 其 `/tmp/ss_rt_cache.*` 固定路径在并行 test runner 下 race(疑 I026/I027 同族)。调研按 MNK §M §字段 12 对继承假设开工实证 → **并发 race 假设被证伪**(单进程 serial `bin/ss test` 即确定性重现错误,0 并发);实测发现真根因,按 §衍生 issue归档以真根因立项

---

## 现象(实测)

清空缓存后,**单个 serial `bin/ss test`(零并发)** 即确定性重现:

```
$ rm -f /tmp/ss_rt_cache.*
$ bin/ss test /tmp/ss_i028_probe          # 单测试目录
llc-18: error: /tmp/ss_rt_cache.ll:375:34: error: base element of getelementptr must be sized
  %datap = getelementptr %Array, ptr %arr, i32 0, i32 2
                                 ^
1 passed, 0 failed, 1 total
$ ls /tmp/ss_rt_cache.*
ls: cannot access '/tmp/ss_rt_cache.*': No such file or directory
```

`bin/ss test` 仍报 `1 passed` —— 错误被 `buildRuntimeCache` 失败路径(`gen_rt_cache.ss:21-24` llc 非零 → `rm -f` + return)吞掉,**非阻挡**;但每次 `bin/ss test` 都把这条 `llc-18: error` 喷到终端。

## 对 next_prompt 并发假设的证伪

next_prompt 假设:`bin/ss test` 并行 runner(`MAX_JOBS=nproc`)下多个编译进程在 `/tmp/ss_rt_cache.ll` 上 race,一方 `writeFile(rtLL)` 重写时另一方 `llc-18` 读到撕裂 IR。

**该假设错误。** 实测以**单进程、零并发**重现完全相同的错误 → 错误是**确定性**的,与并发无关。静态佐证:`buildRuntimeCache()` 唯一调用点 `main.ss:428`(`cmdTest` 内),serial 跑完在并行 runner(`main.ss:448-449`)**之前**;并行 runner 每个 job 是独立 `bin/ss build` 子进程(`main.ss:442`),`cmdBuild`(`main.ss:317-341`)不设 `useRuntimeCache`,子进程既不调 `buildRuntimeCache` 也不碰 `/tmp/ss_rt_cache.*`。∴ 单次 `bin/ss test` 内 `buildRuntimeCache` 独占运行,本就无并发可言。

## root cause(两层)

**层 1 —— 确定性 llc 失败(直接因)**:`buildRuntimeCache()`(`gen_rt_cache.ss:11-33`)把 `emitRuntimeDefs()` 输出经 `; ModuleID` 头(`:20`)直接喂 `llc-18`(`:21`)。但 `emitRuntimeDefs`(`gen_runtime.ss:13`)只定义 `%TypeInfo`(`:191`)/ `%ObjHeader`(`:194`),**不定义** `%String`/`%Array`/`%Map` —— 后三者唯一定义点是 `generateToFile` 的 `typeDecl` 常量(`codegen.ss:352`)。`buildRuntimeCache` 不 prepend `typeDecl`,而运行时 IR 含 `getelementptr %Array, ...`(实测 rtLL `:375`)→ GEP 引用未定义/opaque 类型 → llc verifier `base element of getelementptr must be sized`。普通 `bin/ss build` 路径无此问题:`generateToFile` 在 `codegen.ss:352` 显式 prepend `%String/%Array/%Map`,故 `./build.sh bootstrap` 与全测套件正常。

**层 2 —— 缓存子系统是死代码(根因)**:即使层 1 修好让 llc 成功,`buildRuntimeCache` 产出的 `/tmp/ss_rt_cache.{o,decls}` **也无人读取**。缓存读取分支(`codegen.ss:332-333`、`main.ss:640`)均 gated on `useRuntimeCache==1`;`useRuntimeCache` 仅 `main.ss:429` 置 1(`cmdTest` 父进程),而父进程置 1 后**不在进程内 `compile()`**(只拼脚本 `system()` 之);真正编译的 `bin/ss build` 子进程恒 `useRuntimeCache=0`。`gen_rt_cache.ss:1` 注释提的 "CLI `--rt-cache` driver" 全仓不存在(`grep -rn -- --rt-cache` 仅命中该注释)。∴ `buildRuntimeCache` 每次 `bin/ss test` 构建一份**从未被读、且当前还构建失败**的缓存 —— 子系统整体无效。

## 并发安全性(附带结论 —— 非本 issue headline)

`buildRuntimeCache` 确实用无隔离的固定共享路径 `/tmp/ss_rt_cache.{ll,o,decls}`(无 `mktemp`/`flock`/原子 `rename`/content-addressed;`main.ss:428` 的 `fileExists` 入口 guard 是 TOCTOU)—— 形态上属 I026/I027 family。但该并发面**三重休眠**:(a) 单次 `bin/ss test` 内 serial 独占;(b) 确定性失败 → `.o` 永不产出 → 无「成功缓存」可被并发污染;(c) 死代码无消费者。∴ 它**不是** I026/I027 那种「静默 race 产出错误结果」的可执行隐患,而是 broken+dead。修复(删子系统)天然连带消除该并发面 → 不单列并发 issue。

## I027 triage 补正

I027 `.bugfix`(`tools/bugfix_reports/2026-05-19-i027-shelloutput-comptime-tmp-path.bugfix:24-26`)same_pattern 排查曾命中 `gen_rt_cache.ss`,判「write-once 共享缓存子系统(缓存按设计即共享资源)→ 非同一 bug 模式 → `same_pattern_count=0`」。`same_pattern` 计数对 I027 自身正确(`gen_rt_cache` 不在 I027 修复范围),但该 triage 假设「缓存能工作、只是设计上共享」;实测表明缓存**从不工作**(确定性 llc 失败)且**无人读**(死代码)。I028 补正:此处真问题不是「共享」,是「失效 + 死」。

## 修复方向(Execute 轮 options.md 坐实,本立项轮不锁)

按 bug 修复 harness,options.md ≥3 候选含层次标。研究指向最深可达层 = **架构层:删整个 dead 缓存子系统**(对标 I027 `b0e272c`「删多余机制」根层手法):删 `gen_rt_cache.ss`、`useRuntimeCache`/`runtimeCacheObj`/`runtimeCacheDecls`、`main.ss:428-429`、`codegen.ss:332-337` 的 cache 分支(保留 `emitRuntimeDefs()` else 行为)、`main.ss:640` 的 `rtObj`、`main.ss:595` clean glob 的 `ss_rt_cache.*`。次选:数据层补 `typeDecl` 让它能 build(给死功能续命无意义);或接活缓存(子进程 `--rt-cache` opt-in)——工程量大、价值未证。最深层由 Execute 轮 PSM §字段 10/11 按根因解决度决策。

## 关联观察(不在本 issue scope,候选未来 issue)

本区域真正的 I026/I027-family 并发隐患不在 `gen_rt_cache.ss`,而在 `cmdTest` 自身:`/tmp/ss_test_par.sh`、`/tmp/ss_test_${idx}`、`/tmp/ss_res_${idx}`(`main.ss:440-449`)均是固定路径(per-index 但 index 每次调用从 0 重数)→ ≥2 个 `bin/ss test` 并发会 race(一方编译 `/tmp/ss_test_N` 时另一方覆写 → exec 撕裂二进制可致段错误)。I027 收尾观测的「段错误」若与并发同现,此为最可能来源 —— 但与 `gen_rt_cache.ss` 无关,本轮不立,留作下游 issue 候选。

## 反向

不立项 → 这个确定性失效 + 每次 `bin/ss test` 喷 `llc-18: error` 的终端噪音继续误导(I027 收尾已误判一次 —— 把确定性 bug 当 concurrency race),下轮 Claude 读不到(MNK §核心原则 4),与 I025/I026/I027 同类反复误诊。
