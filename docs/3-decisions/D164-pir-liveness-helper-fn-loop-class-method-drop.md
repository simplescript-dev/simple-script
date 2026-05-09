# D164: SS 编译器 PIR liveness helper fn + while/for loop body + class instance method call 模式下误标 last-use 致 use-after-free segfault 修法

**Status:** [/] Phase 0 D 文档落档 at commit `<phase0-hash>` + [ ] Phase 1 minimum repro 隔离 spike + ≥3 case RED-as-spike + LLVM IR inspect 真根因(对比 helper fn vs main() 体内 IR 差异)at commit `<phase1-hash>` + [ ] Phase 2 bootstrap/pir liveness 修法(pir_lower.ss 或 pir_opt.ss)+ 三阶段固定点 stage2==stage3 PASS + Phase 1 spike 重跑全 GREEN at commit `<phase2-hash>` + [ ] Phase 3 D163 §Phase 3 重启 + D160 §Phase 4 wire 真值反射重启 + 在线 docker `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN at commit `<phase3-hash>` + [ ] Phase 4 D164 主线 close + D163 §F5 重启锚回填 + D160 §F9 重启锚回填 at commit `<phase4-hash>` + [ ] D164 主线 close at commit `<phase4-hash>` — D163 §Phase 2 codegen MEMBER_ACCESS 类型解析修法 wire 落地 commit `ae16073` 后 D160 §Phase 4 wire 真值反射重启实测 8 case 仍 segfault → /tmp/d160_t18.ss 17 行最小 repro 揭露独立 root cause #2 = PIR liveness 在 helper fn + while loop ≥ 2 次 + class instance.method() 模式下误标 last-use 在 while body 内,每次循环 ss_drop class instance,第 2 次循环 use-after-free segfault → D163 §Phase 3 hold + D164 起首脱胎 commit `29a7487`,D135-D163 编译器主线范式延续。修 SS 编译器 PIR liveness analysis 让 helper function 内 class instance 在 while/for loop body 内仅 borrow 不 last-use,drop 推到 while.after 块 — 不接受次优 / workaround / 节省路径(用户对话锁)。

## 起首脱胎
- D163 §Phase 2 修了 root cause #1(`bootstrap/gen/gen_types.ss:249` resolveObjClass MEMBER_ACCESS 分支 +1 行 ifaceMethodsCG.has 守护)wire 落地 at commit `ae16073` — Phase 1 spike 3 case 全 GREEN + 三阶段固定点 stage2==stage3 PASS — 但 D160 §Phase 4 wire 真值反射重启实测 8 case 仍 segfault,推翻 D163 §A.2 H5 假设(修编译器后 D160 wire drain 代码不动即 GREEN)
- D163 §Phase 3 hold 实测在线 docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait MySQL 8.0 healthy 后 `bin/ss test tests/d160_callable_statement/` 全 segfault(test runner 路径 / direct binary `/tmp/d160_int` exit=139)at commit `29a7487`
- 最小 repro 隔离 `/tmp/d160_t18.ss` 17 行 完全脱离 D160 wire 路径:`function dropAllProcs() { const tmpl = new JdbcTemplate(URL); let i = 0; while (i < 2) { tmpl.execute("DROP ..."); i = i + 1 } } function main() { dropAllProcs() }` 实测 segfault(exit=139);改 `while (i < 1)` 1 次循环即 GREEN;改 helper fn 内同样代码搬到 main() 体内即 GREEN(`/tmp/d160_t10.ss` 类似形)— **bug 触发条件 = helper function + while loop ≥ 2 次 + class instance.method() 调用**
- LLVM IR inspect:`bin/ss build /tmp/d160_t18.ss --emit-ir` 显示 dropAllProcs 函数 IR while.body 块内出现 `call void @ss_drop_JdbcTemplate(ptr %tmpl)` — **PIR liveness 误标 tmpl 在 while body 内 last-use**,每次循环 drop tmpl,第 2 次循环重新 load 已 free 的 tmpl pointer 即 use-after-free segfault;对比同样代码在 main() 体内的 IR(t10),drop 正确放在 while.after 块外 — 仅 helper function 路径错
- bug scope:任何 `function helper() { let x = new Class(...); while (...) { x.method(...); } }` 模式触发 — 影响范围远超 D160(stdlib JdbcTemplate / 用户代码 helper fn 任一 class instance loop method call)
- D135-D163 编译器主线范式延续(Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设挑战 + §A.3 废案 + §Followup)
- Depends on:无新前置依赖(SS 编译器 PIR 修法 + D163 §Phase 2 codegen 修法已就位)— 但本 D close 后回填 D163 §F5 重启锚 + D160 §F9 重启锚 + D163 §Phase 3 重启 + D160 §Phase 4 wire 真值反射重启 GREEN

## 核心目标 (Goal)

落地后:
1. `bootstrap/pir/pir_lower.ss` 或 `bootstrap/pir/pir_opt.ss` liveness analysis 修法,helper function 内 class instance 在 while/for loop body 内 last-use 时,`ss_drop_*` 必须放到 while.after 块外而非 while.body 块
2. minimum repro spike `tests/d164_pir_liveness_helper_fn_loop_class_method/phase1_repro_spike_test.ss` 3 case RED→GREEN(Case 1 helper fn + while loop ≥ 2 次 + simple class.method / Case 2 helper fn + for loop + class.method / Case 3 nested helper fn + nested loop + 多 class instance)
3. `/tmp/d160_t18.ss` 17 行最小 repro 实测 exit=0(从 segfault → GREEN)
4. `./build.sh bootstrap` 三阶段固定点 stage2==stage3 bit-identical PASS
5. **D163 §Phase 3 重启 + D160 §Phase 4 wire 真值反射重启**:在线 `docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait` 后 `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN(getInt(2)=20 / getInt(1)=15 / 多 OUT / 三态 mode / getString / getDouble / wasNull)
6. baseline 全继承 + reflection_health_linter no regression(尤其 F1 bootstrap/pir/*.ss budget 评估)+ d_doc_index_linter F1=0 + next_prompt_ultrathink_linter PASS

**RED**(本 D 文档落档前实测):
- `/tmp/d160_t18.ss` 17 行(helper fn `dropAllProcs` + while loop ≥ 2 次 + JdbcTemplate.execute)实测 exit=139 segfault
- `/tmp/d160_t18.ss` 改 `while (i < 1)` 1 次循环 → exit=0 GREEN(确认 ≥ 2 次循环触发)
- `/tmp/d160_t18.ss` 改 helper fn 内代码搬 main() 体内 → exit=0 GREEN(确认 helper fn 路径触发)
- `bin/ss test tests/d160_callable_statement/` 8 case 全 segfault(在线 docker MySQL 8.0 healthy 状态)
- LLVM IR inspect:while.body 块出现 `call void @ss_drop_JdbcTemplate(ptr %tmpl)` 每次循环 drop tmpl

## 核心原则 (Principles)

1. **Root Cause 优先 + 不接 workaround / 节省路径**(用户对话锁 / CLAUDE.md "Root Cause 优先 — 不接受次优 / workaround / 节省" 第一法则):**不**改 D160 wire drain 用 closure 模拟,**不**在 driver 拆 helper fn 内 loop body 为单次 single-iteration,**不**在 stdlib/JdbcTemplate 加 sticky retain — 修 SS 编译器 PIR liveness root cause
2. **Java/TS 业界对标必修**:helper function 内 class instance + loop method call 是 Java + TypeScript + Kotlin + Scala 全部支持的标准模式,行为一致(helper fn 内 vs main 内不应有差异);SS 缺它必拖累后续每条 sub-D 用 helper fn + loop + class.method 形态
3. **Perceus IR 范式严守**(reference counting + last-use insertion):while body 内 method call 不应触发 class instance last-use(class instance 仍 borrow,drop 推到 loop after);main() 体内行为正确,helper function 体内必须一致
4. **业界对标 Koka / Roc 等 Perceus-style 语言**:liveness analysis 必正确处理 borrow vs last-use,loop body 内 borrow 不 drop,loop after 一次 drop;helper function vs main function 路径对称
5. **bootstrap 三阶段固定点必走**:任何 `bootstrap/pir/` 修改必走 `./build.sh bootstrap` 三阶段 stage2==stage3 bit-identical 验证(D162 §Phase 2 / D163 §Phase 2 范式延续)— 自举 ≈ 55s
6. **D135-D163 主线范式延续**:Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设 + §A.3 废案 + §Followup
7. **N 年返工度极高**:不修 → 后续每条用 helper fn + class instance + loop 模式(stdlib JdbcTemplate / 用户代码任一 helper fn 内 loop class.method)全部 segfault → 必修
8. **PIR Map key int 转 string 范式 + visited 守 idempotent 范式**(CLAUDE.md §关键不变量 + D161 §Phase 2 / D162 §Phase 2 visited 范式延续)
9. **scope 限单 sub-D**:本 D 仅修 PIR liveness analysis 在 helper fn + loop body + class instance method call 模式下的 last-use 误标 — 不引入 PIR 表示形态改动 / 全局 PIR Map key 类型化 / 跨 D 通用 control-flow 重写
10. **依赖链不破**:D163 §Phase 2 codegen MEMBER_ACCESS 类型解析修法(commit `ae16073`)+ D162 §F7 vtable + non-0-arg overload child class bug 修法系列(commit `7d91d73`)+ 本 D PIR liveness 修法 三者正交并存,各修各根因,任一回退都破依赖链;Phase 2 修法后 D162/D163 spike 重跑 GREEN 守护(§A.2 H3 实证)

## A.1 主候选评估(§MNK §M §字段 10)

| 候选 | 层次 | 含 | 不含 | 决策 |
|------|------|-----|------|------|
| **C1** | workaround:driver `lib/spring/jdbc.ss` 改用 closure 模拟 / 全局 Map<conn_id, tmpl> 模拟 / helper fn 拆 single-iteration loop body | + 暂时绕过 SS 编译器 PIR liveness bug,driver 端走 closure 捕获 / 全局 state / 单次 iteration unroll workaround | 编译器 bug 不修,后续每条 sub-D 用 helper fn + loop + class.method 形态(常见 stdlib helper / 用户代码 helper fn)全断链 | **不选** — 用户对话锁不接 workaround;违反 ROOT CAUSE 第一法则 |
| **C2** | **编译器 PIR liveness 修法(根因)** | + 修 SS 编译器 `bootstrap/pir/pir_lower.ss` 或 `pir_opt.ss` liveness analysis 让 helper fn 内 class instance 在 while/for loop body 内仅 borrow 不 last-use,drop 推到 while.after 块外 + bootstrap 三阶段固定点 + minimum repro spike GREEN + D163 §Phase 3 重启 + D160 §Phase 4 wire 真值反射重启 8 case docker e2e 全 GREEN | 高级模式(generic class loop / nested helper fn 多 closure capture / async/await control flow / try/catch unwind drop)留 §F1/F2/F3 远期 | **选** — 根因解决:N 年返工度极高 + 业界对标 Java/TS/Kotlin/Scala/Koka/Roc + 与 D162 §F7 / D163 §Phase 2 编译器修法系列同源延续 + 不破依赖链 |
| **C3** | 架构层 refactor:全面审视 Perceus IR 系统(pir.ss + pir_lower.ss + pir_opt.ss)+ 多 Perceus pass 对齐(borrow / last-use / drop reorder / dup elide / reuse hint)+ if/else / try/catch / async/await / generator 等高级控制流统一处理 | + 完整 PIR 体系审查 + 跨 D 通用 control-flow drop semantics + multi-pass 一致性证明 | scope 远超 D164 单 sub-D — 跨 D104 mimalloc REUSE / D060 Perceus 主线 / D018 vtable 等所有 PIR / RC 系统 sub-D 联动 | **不选** — scope 远超 + N 年路径,本 D 仅修当前 corner case 不动整体 PIR 系统 |

**决策行**:**选 C2 编译器 PIR liveness 修法(根因)**(用户对话锁 — 不接次优 / workaround / 节省)— 因 (a) Root Cause 第一法则下编译器 bug 必修;(b) 业界对标 Java / TypeScript / Kotlin / Scala 全部支持 helper fn + loop + class.method 模式且行为与 main 一致,Perceus-style Koka / Roc 同样要求 liveness analysis 正确处理 loop body 内 borrow vs last-use;(c) D162 §F7 vtable + non-0-arg overload child class bug 修法 + D163 §Phase 2 ifaceMethodsCG.has 守护修法系列同源 corner case 延续;(d) D160 §Phase 4 wire 真值反射重启 + D163 §Phase 3 重启依赖此修;(e) **N 年返工度极高** — 后续每条用 helper fn + class instance + loop 模式的 sub-D(常见 ORM helper / wrapper class / adapter class / stdlib helper)全部 segfault;(f) scope 中等可控(单 PIR pass + ~10-30 LOC + Phase 1-3 spike + Phase 4 close 5 commit 切片);(g) D135-D163 主线范式延续。

## A.2 隐藏假设挑战

| H | 假设 | 挑战 | 实证锚 |
|---|------|------|--------|
| H1 | PIR liveness root cause 在 `bootstrap/pir/pir_lower.ss`(初始 schedule 计算阶段 — `pirSchedule[stmtId]` set 入口路径 helper fn vs main 不对称)| pir_lower.ss `genStmt` 后 `pirEmitScheduled()` 发射 release(CLAUDE.md §关键不变量 PIR Map key 段)— 路径在 helper fn 内 while loop body 末尾 stmt 错把 class instance 视为 last-use 在 body schedule 而非 while.after schedule;main() 路径下 release 推到 main 末尾(loop after fall-through 范式) | Phase 1 LLVM IR inspect + 加 trace println / DEBUG dump 在 pirSchedule set 入口对比 helper fn vs main 体内同一段代码差异 |
| H2 | PIR liveness root cause 在 `bootstrap/pir/pir_opt.ss`(优化阶段 dead code elim 误判 while body 末尾 = last-use)| pir_opt.ss 走 dup elide / drop reorder pass — 可能 helper fn 路径下 fold 把 while.after 的 drop 提前到 while.body 末尾(优化误判 fall-through 等价性);main() 路径下不触发优化或优化保守 | Phase 1 用 DEBUG=1 dump pir_opt 前后 IR 差异 isolate;若 pir_opt 前已错则根因在 pir_lower(H1),否则 pir_opt(H2) |
| H3 | 修法对 D162 §F7 vtable + non-0-arg overload child class bug 修法 + D163 §Phase 2 ifaceMethodsCG.has 守护修法兼容 | 本 D 修 PIR pass(中间层),D162 §F7 / D163 §Phase 2 修 codegen pass(下游),正交不冲突;但 PIR 修法影响所有 codegen 路径,需 D162/D163 spike 重跑 GREEN 守护 | Phase 2 修法后跑 D162/D163 spike 重跑 GREEN + 全 `bin/ss test tests/` 净不退化(305/16/321 baseline) |
| H4 | 修法对 reflection scope 14 指标无 regression(尤其 F1 `bootstrap/pir/pir_lower.ss` + `pir_opt.ss` LOC 增量)| Phase 2 修法估 +10~+30 LOC 对 F1 budget 影响小;若超 budget_max 需 `bump` / `bump-group` 申报扩容(D097 §扩容协议) | Phase 2 修法后跑 reflection_health_linter no regression GATE,任一物理指标 > budget_max 阻断 commit |
| H5 | D163 §Phase 3 重启 + D160 §Phase 4 wire 真值反射重启 8 case 全 GREEN — 修 PIR liveness root cause #2 后,D163 §Phase 2 codegen 修法 + D160 wire drain 实现代码不动即 GREEN | 假设 PIR liveness 是 D160 segfault 的唯一独立根因(root cause #2 单一),无 root cause #3;若 Phase 3 docker e2e 仍 fail 需 §A.2 H5 修正记录 + 起首独立 sub-D | Phase 3 docker e2e 重跑 `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN(在线 MySQL 8.0 healthy 状态);Phase 4 D164 主线 close + D163 §F5 / D160 §F9 重启锚回填 |
| H6 | 修法对 `bootstrap/pir/pir.ss` PIR 表示形态(`pirKind` / `pirStr*` / `pirInt1` / `pirList` / `pirSchedule` Map int 转 string key 范式)不破坏 | CLAUDE.md §关键不变量 PIR Map key 段:所有 PIR Map 访问必须 `id + ""` 将 int 转 string,否则 key 错配;本 D 修法仅触 schedule 计算逻辑,不改 Map 表示形态 | Phase 2 修法落地后跑 D135-D163 全部已落地 spike 重跑 GREEN(若任一退化必排查 PIR Map key 误用) |
| H7 | helper function 路径与 main() 路径在 PIR 阶段处理对称(genFunc 入口对 main 与 helper 共用同一 codepath,仅差 function name 与 return type)| `bootstrap/gen/methods/gen_methods.ss` + `bootstrap/pir/pir_lower.ss` genFunc 入口已统一处理 user fn(无论 main 还是 helper),但本 D 实测发现 PIR liveness 仅在 helper 路径错 — 暗示 schedule 计算 / 优化 pass 内部某条 branch 隐式区分 helper vs main(或基于 fn local var 个数 / 局部 borrow 集合判定)| Phase 1 LLVM IR inspect helper fn 路径与 main 路径对照 + 加 trace 在 genFunc 入口 dump fnName + schedule 入口数据 |

## A.3 废案

- **C1 driver workaround**(用户对话锁不接 workaround / 节省路径;违反 ROOT CAUSE 第一法则;`memory/feedback_root_cause_no_cost.md` 第一法则触发)
- **C3 架构层 refactor**(scope 远超 D164 单 sub-D — 完整 PIR 体系审查留 §F3 远期独立 sub-D)
- **改 D160 wire drain 把 helper fn 内 loop 拆为多个 single-iteration**(workaround;违反 §核心原则 1;D160 wire drain 实现代码已就位,不应回调)
- **在 stdlib `lib/spring/jdbc.ss` JdbcTemplate 加 cyclic retain / sticky reference 强保留 tmpl**(workaround;反 RC 范式 + memory leak 风险)
- **标记 helper fn class instance 为 noinline / volatile / captureSingleton**(SS 类型系统不支持 + 反 user-friendly 范式 + 跨 D 范畴破坏)
- **临时跳过 segfault test 留远期处理**(违反核心目标 + 用户对话锁 docker 在线验证 wire 真值是核心目标)
- **改 PIR Map key 类型化**(架构层 refactor — D135-D163 范式延续 PIR Map int 转 string,本 D 不动 PIR 表示形态;留 §F3 远期)
- **强制 SS 标记 class instance 在 helper fn 内为 unsafe / @ScopeStable / @LoopStable annotation**(SS 类型系统不支持 + 反 user-friendly 范式 + 用户对话锁 + memory `feedback_no_derive_workaround.md` annotation 不当根因第一法则触发)
- **D164 与 D163 §Phase 3 重启 + D160 §Phase 4 wire 真值反射重启 同 commit 落地**(scope 失控 — D164 是编译器层 PIR 根因 + D163 §Phase 3 + D160 §Phase 4 是应用层 wire 验证,二者分开切片 — D164 主线 close → D163 §Phase 3 重启 → D160 §Phase 4 重启 跨 D 起首回填范式延续)
- **改 PIR liveness analysis 为保守化全程 retain/release**(在 helper fn 入口先 retain 一次 class instance,helper fn 出口 release 一次 — 不依赖 schedule 计算)— 反 Perceus 范式 + 性能退化 + memory pressure 增加(每 helper fn call 多 1 retain + 1 release pair),违反 D060 Perceus 主线核心目标
- **改 PIR pass 顺序(把 pir_opt 在 pir_lower 前跑)**(架构层 refactor;违反 SS 编译器现有 PIR pass 顺序 lexer→parse→checker→pir_lower→pir_opt→codegen,scope 远超本 D)
- **临时回退 D162 §F7 vtable + non-0-arg overload child class bug 修法 / D163 §Phase 2 ifaceMethodsCG.has 守护修法**(回退已 wire 落地的根因修法 — 违反 ROOT CAUSE 第一法则 + 破依赖链 + scope 失控)

## Phase commit hash 总览

| Phase | 内容 | Commit |
|-------|------|--------|
| 0 | D 文档落档(§核心目标 + §核心原则 + §A.1-A.3 + §Phase 收关锚 Phase 0-4 + §Followup F1-F5 + §Status 时间线)+ 跨 D 起首回填 D163 §Phase 2 hash `ae16073`(root cause #1 wire 落地)+ D163 §Phase 3 hold hash `29a7487`(D164 起首脱胎)至 D164.md ≥3 处实际语义位 | `<phase0-hash>` |
| 1 | minimum repro `tests/d164_pir_liveness_helper_fn_loop_class_method/phase1_repro_spike_test.ss` ≥3 case RED-as-spike(Case 1 helper fn + while loop ≥ 2 次 + simple class.method / Case 2 helper fn + for loop + class.method / Case 3 nested helper fn + nested loop + 多 class instance)+ LLVM IR inspect 对比 helper fn 路径 vs main() 体内同样代码差异 + 加 trace println / DEBUG dump 在 pir_lower.ss + pir_opt.ss schedule 计算入口 isolate H1 vs H2 + Phase 2 修法 target 锁定 file:line + LOC 估算 | `<phase1-hash>` |
| 2 | bootstrap/pir/pir_lower.ss 或 pir_opt.ss liveness 修法(基于 Phase 1 H1 vs H2 实证锁定的 PIR pass)+ ./build.sh bootstrap 三阶段固定点 stage2==stage3 bit-identical PASS + Phase 1 spike 重跑 3 case 全 GREEN + LLVM IR 验证 grep ss_drop_<ClassName> 在 while.body 块 = 0(从 ≥1 → 0)+ reflection_health_linter no regression(M1-M7+N1-N5)+ bin/ss test tests/ 净不退化 305/16/321 + 跨 D 起首回填 D164 §Phase 1 hash `<phase1-hash>` 至 D164.md ≥4 处 | `<phase2-hash>` |
| 3 | D163 §Phase 3 重启 + D160 §Phase 4 wire 真值反射重启 — `docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait` MySQL 8.0 healthy 后 `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN(Case 1 H1 + Case 2 OUT INTEGER 真值=20 H4 + Case 3 INOUT 真值=15 H4 + Case 4 multi OUT H4 + Case 5 三态 mode H3 + Case 6 getString H4 + Case 7 getDouble H4 + Case 8 wasNull SQL NULL)+ /tmp/d160_t18.ss 实测 exit=0 + 跨 D 起首回填 D164 §Phase 2 hash `<phase2-hash>` 至 D163.md(§Phase 3 重启锚)+ D160.md(§F9 row + §Phase 4 §收关锚) | `<phase3-hash>` |
| 4 | D164 主线 close + D163 §F5 重启锚回填 + D160 §F9 重启锚回填 + D163 主线 close + D160 主线 close 锚链一并清理(由 D163 §Phase 4 / D160 §Phase 4 close commit 处理,本 D 仅锚回填) | `<phase4-hash>` |

## Phase 收关锚

### Phase 0: D 文档落档 [/] In progress at commit `<phase0-hash>`

- 落地 `docs/3-decisions/D164-pir-liveness-helper-fn-loop-class-method-drop.md`(本文件)— ≥150 行 — §核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H5 + §A.3 废案 + §Phase 收关锚 Phase 0-4 + §Followup F1-F5 + §Status 时间线
- 落地 `.claude/next_prompt.md`(下轮 D164 §Phase 1 起首 — minimum repro spike 移植 + ≥3 case RED-as-spike + LLVM IR inspect 真根因)— 含 ultrathink 关键字 + 不写 docs-only 字面(防 self-recursive spin / next_prompt_ultrathink_linter C4 守护)
- **跨 D 起首回填 D163 §Phase 2 hash `ae16073`(root cause #1 codegen MEMBER_ACCESS 类型解析 wire 落地)+ D163 §Phase 3 hold hash `29a7487`(D164 起首脱胎)至 D164.md ≥3 处实际语义位**(Status header / §起首脱胎 / §Phase commit hash 总览段表 Phase 0 行 / Status 时间线 起首脱胎 entry)
- bootstrap/ + lib/ + tools/ + tests/ diff = 0(本 Phase 纯 docs/ + .claude/next_prompt.md)
- baseline:`d_doc_index_linter` F1 = 0 PASS(D147/D154/D155/D156/D157/D160/D161/D162/D163/D164 全实存,加入 D164 实存)+ `next_prompt_ultrathink_linter` PASS(下轮 D164 §Phase 1 起首含 ultrathink + 不 docs-only)+ 14 reflection 指标全继承 D163 §Phase 2 baseline(本 Phase 不动 bootstrap/ → reflection scope 不触)+ `bin/ss test tests/` 全继承 305/16/321

### Phase 1: minimum repro 隔离 spike + ≥3 case RED-as-spike + LLVM IR 真根因(对比 helper fn vs main 体内 IR 差异)[ ] Pending at commit `<phase1-hash>`

- 落地 `tests/d164_pir_liveness_helper_fn_loop_class_method/phase1_repro_spike_test.ss` 3 case RED-as-spike — Case 1 helper fn + while loop ≥ 2 次 + simple class.method(`/tmp/d160_t18.ss` 移植精简,去掉 JdbcTemplate / lib/spring 依赖,用最小自定义 class)/ Case 2 helper fn + for loop + class.method(if SS 已支持 for loop;否则 while loop 等价形)/ Case 3 nested helper fn(`fn1` calls `fn2`,`fn2` 内 while loop)+ 多 class instance(2+ class instance fields)
- `/tmp/d160_t18.ss` 移植精简后用最小 class(无外部 lib 依赖)— RED-as-spike 范式延续 D163 §Phase 1 / D162 §Phase 1 / D161 §Phase 1 同形
- LLVM IR inspect:`bin/ss build phase1_spike --emit-ir -o /tmp/d164_spike` 后对比 helper fn 路径 vs main() 体内同样代码 IR 差异 — 哪个 PIR pass(pir_lower vs pir_opt)误插 `ss_drop_*` 在 while.body 块
- 加 trace println 在 `bootstrap/pir/pir_lower.ss` `pirSchedule[stmtId]` set 入口 + `bootstrap/pir/pir_opt.ss` 优化 pass 入口,DEBUG dump pir_lower 前 / pir_lower 后 / pir_opt 后三阶段 IR isolate H1(pir_lower 路径错)vs H2(pir_opt 路径错)
- Phase 2 修法 target 锁定 file:line + LOC 估算 + 修法策略(对称 helper fn 路径与 main 路径 schedule 计算 / 修 visited 守 / 修 PIR Map key 误用 / 等)
- 跨 D 起首回填 D164 §Phase 0 hash `<phase0-hash>` 至 D164.md 4 处实际语义位(Status header / §Phase commit hash 总览段表 Phase 0 行 / §Phase 0 §收关锚 / Status 时间线 Phase 0 entry)

### Phase 2: bootstrap/pir liveness 修法 + 三阶段固定点 PASS + Phase 1 spike 全 GREEN [ ] Pending at commit `<phase2-hash>`

- **PRIMARY 修法**:`bootstrap/pir/pir_lower.ss` 或 `bootstrap/pir/pir_opt.ss` 修 helper function 路径 liveness analysis,让 class instance 在 while/for body 内不 last-use,drop 推到 while.after 块外(LOC 估 +10~+30 — 单 PIR pass,scope 中等)
- `./build.sh bootstrap` 三阶段固定点 stage2==stage3 bit-identical PASS — `Stage 2 = Stage 3 — Updated bin/ss`(自举 ≈ 55s,CLAUDE.md §构建与测试 范式延续)
- reflection_health_linter GATE PASS — no regressions(M1-M7+N1-N5 全继承 D163 §Phase 2 baseline + F1 `bootstrap/pir/pir_lower.ss` 或 `pir_opt.ss` LOC 增量评估,若超 budget_max 需 `bump` / `bump-group` 申报扩容 D097 §扩容协议)
- Phase 1 spike 重跑 3 case 全 GREEN — `bin/ss test tests/d164_pir_liveness_helper_fn_loop_class_method/` 1 passed / 0 failed / 1 total(单 file 内 3 个 test() 全 GREEN)
- LLVM IR 验证:`bin/ss build phase1_spike --emit-ir -o /tmp/d164_spike` 后 `grep -c "ss_drop_<ClassName>" /tmp/d164_spike.ll` 在 while.body 块 = 0(从 ≥1 → 0)
- bin/ss test tests/ 净不退化 305/16/321(D162 §F7 vtable 修法 + D163 §Phase 2 ifaceMethodsCG.has 修法兼容守护 — H3 实证)
- d_doc_index_linter F1=0 PASS + next_prompt_ultrathink_linter PASS(下轮 D164 §Phase 3 起首含 ultrathink)
- 跨 D 起首回填 D164 §Phase 1 hash `<phase1-hash>` 至 D164.md ≥4 处实际语义位

### Phase 3: D163 §Phase 3 重启 + D160 §Phase 4 wire 真值反射重启 + 在线 docker 8 case 全 GREEN [ ] Pending at commit `<phase3-hash>`

- D163.md Status header 改 `[/] Phase 3 hold ... at commit \`29a7487\` + [x] Phase 3 重启 ... at commit \`<phase3-hash>\``
- 在线 `docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait` MySQL 8.0 healthy 后 `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN(Case 1 H1 + Case 2 OUT INTEGER 真值=20 H4 + Case 3 INOUT 真值=15 H4 + Case 4 multi OUT H4 + Case 5 三态 mode H3 + Case 6 getString H4 + Case 7 getDouble H4 + Case 8 wasNull SQL NULL)
- `/tmp/d160_t18.ss` 17 行最小 repro 实测 exit=0(从 segfault → GREEN)
- 跨 D 起首回填 D164 §Phase 2 hash `<phase2-hash>` 至 D163.md(§Phase 3 重启锚 / Status header / §Followup F5 row 末尾上下文)+ D160.md(§F9 row 末尾上下文 / §Phase 4 §收关锚 / Status 时间线 D164 close + D163 §Phase 3 重启 entry)

### Phase 4: D164 主线 close + D163 §F5 重启锚回填 + D160 §F9 重启锚回填 [ ] Pending at commit `<phase4-hash>`

- D164 主线 close 锚:Status header `[x] Phase 0-4 + [x] D164 主线 close at commit \`<phase4-hash>\``
- D163 §Followup F5 row 末尾上下文更新 `commit \`<phase4-hash>\` D164 主线 close → D163 §Phase 3 重启 GREEN`
- D160 §Followup F9 row 末尾上下文更新 `commit \`<phase4-hash>\` D164 主线 close → D160 §Phase 4 wire 真值反射重启 GREEN`
- D163 §Phase 3 重启 + D163 主线 close + D160 §Phase 4 + D160 主线 close 一并清理(由 D163 §Phase 4 / D160 §Phase 4 close commit 处理,本 D 仅锚回填)
- 跨 D 起首回填范式延续:本 D 主线 close 后 Phase 4 hash 留 D163 §Phase 4 close + D160 §Phase 4 close commit 起首跨 D 回填(D162 §Phase 4 close → D160 §Phase 3 / D163 close → D160 §Phase 4 同形)

## Followup

| F | 内容 | 范围 |
|---|------|------|
| F1 | generic-over-class own field write loop(`function helper<T>() { let x: T = new T(...); while (...) { x.method() } }`)— 泛型 + helper fn + loop + class instance method | 与 D141-D145 contextual typing sub-D 联动,留独立 sub-D 远期 |
| F2 | nested loop 多重 class instance + nested helper fn(`fn1` calls `fn2`,`fn2` 内 nested while loop + 2+ class instance)| 多层 helper fn nest + 多 class instance — 是否本 Phase 2 修法自动覆盖待 Phase 1 spike Case 3 验证;若不覆盖留独立 sub-D |
| F3 | 完整 PIR liveness 体系审查(包括 if/else 分支 last-use / try/catch unwind drop / async/await suspend / generator yield 等高级控制流)| 跨 D 通用 PIR 主题 — 本 D 仅修当前 corner case(helper fn + while/for body + class instance method),完整体系审查留独立 sub-D 远期 |
| F4 | stage0 seed 编译影响(若 Phase 2 修法 affecting stage1+ codegen,stage0 不动 — 但若 stage1 build 后 stage0 重跑需重 seed)| 自举安全 — 留 §F 远期,Phase 2 三阶段固定点验证已覆盖大部分 |
| F5 | reflection_health_linter F1 budget 评估(`bootstrap/pir/pir_lower.ss` + `pir_opt.ss` 当前 LOC vs F1 budget;若超需 `bump` / `bump-group` 申报扩容 D097 §扩容协议)| 本 D Phase 2 修法 LOC 增量评估 — 估 +10~+30 行 — F1 评估需 reflection_health_linter 跑出 baseline 后 evaluate |
| F6 | mimalloc REUSE hint 在 helper fn + loop body 内的 idempotent 保留(D104 mimalloc 主线范式延续)| 修法不应破坏 REUSE hint 在 loop iteration 间的 alloc 复用,Phase 2 修法后跑 D104 spike 重跑 GREEN 守护 |
| F7 | `bootstrap/pir/pir.ss` PIR 节点 Map 表示形态完整性审查(pirKind / pirStr* / pirInt1 / pirList / pirSchedule Map key 一致性 + 类型化提案)| 跨 D 通用 PIR 主题 — D135-D163 范式延续 PIR Map int 转 string,本 D 不动表示形态;留独立 sub-D 远期 |

## Status 时间线

- 2026-05-09 **D164 起首脱胎 + Phase 0 D 文档落档**(commit `<phase0-hash>`)— **新建 docs/3-decisions/D164-pir-liveness-helper-fn-loop-class-method-drop.md** ≥150 行(§核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H5 + §A.3 废案 + §Phase 收关锚 Phase 0-4 + §Followup F1-F5 + §Status 时间线)+ **跨 D 起首回填 D163 §Phase 2 hash `ae16073`(root cause #1 codegen MEMBER_ACCESS 类型解析 wire 落地)+ D163 §Phase 3 hold hash `29a7487`(D164 起首脱胎)至 D164.md ≥3 处实际语义位**(Status header line 3 / §起首脱胎 line 9-10 / §Phase commit hash 总览段表 Phase 0 行 line 86 / Status 时间线 起首脱胎 entry 本 entry)— D163 §F5 起首脱胎,根因优先(用户对话锁 docker 在线验证 wire 真值实测发现独立 PIR liveness root cause #2);**RED 实测**:`/tmp/d160_t18.ss` 17 行 实测 exit=139 segfault;改 `while (i < 1)` 1 次循环 → exit=0 GREEN;改 helper fn 内代码搬 main() 体内 → exit=0 GREEN — bug 触发条件 = helper fn + while loop ≥ 2 次 + class instance.method();LLVM IR inspect:dropAllProcs 函数 IR while.body 块出现 `call void @ss_drop_JdbcTemplate(ptr %tmpl)` — PIR liveness 误标 last-use 在 body 内,每次循环 drop tmpl,第 2 次循环 use-after-free segfault;对比 main() 体内同样代码(`/tmp/d160_t10.ss`)IR drop 正确放在 while.after 块外 — 仅 helper fn 路径错;**GREEN**:D164.md 落档 + .claude/next_prompt.md 含 ultrathink + D163 §Phase 3 hold + D164 起首脱胎 entry 一致;**baseline**:bootstrap/ + lib/ + tools/ + tests/ diff = 0(本 Phase 纯 docs/ + .claude/next_prompt.md)+ d_doc_index_linter F1 = 0 PASS(D147/D154/D155/D156/D157/D160/D161/D162/D163/D164 全实存,加入 D164 实存)+ next_prompt_ultrathink_linter PASS(下轮 D164 §Phase 1 起首含 ultrathink + 不写 docs-only)+ 14 reflection 指标全继承 D163 §Phase 2 baseline(本 Phase 不动 bootstrap/ → reflection scope 不触);**simplify 跳过**(纯文档落档,§After Done §1 例外 — 同 D163 §Phase 0/1/3-hold / D162 §Phase 0/1 / D161 §Phase 0/4 / D160 §Phase 0 / D157 §Phase 0 / D156 §Phase 0 / D154 §Phase 0 / D155 §Phase 0 docs-only 范式延续);**§N §6 file:line 锚**:docs/3-decisions/D164-pir-liveness-helper-fn-loop-class-method-drop.md(本 D 落档 ≥150 行)+ docs/3-decisions/D163-class-extends-iface-typed-field-write.md(§Phase 2 hash `ae16073` + §Phase 3 hold hash `29a7487` 起首脱胎来源)+ docs/3-decisions/D160-callable-statement-out-inout.md(§F9 wire 真值反射重启锚等 D164 close 后回填)+ .claude/next_prompt.md(下轮 D164 §Phase 1 起首 ultrathink + 不写 docs-only)+ /tmp/d160_t18.ss 17 行最小 repro 文件(留 D164 §Phase 1 spike 移植起点)+ /tmp/d160_t10.ss 对比文件(同样代码在 main() 体内 GREEN — IR 对比锚);**等下轮 D164 §Phase 1** — minimum repro spike 移植 + ≥3 case RED-as-spike(Case 1 helper fn + while loop ≥ 2 次 + simple class.method / Case 2 helper fn + for loop + class.method / Case 3 nested helper fn + nested loop + 多 class instance)+ LLVM IR inspect 对比 helper fn vs main 体内 IR 差异 + 加 trace println / DEBUG dump 在 pir_lower.ss + pir_opt.ss schedule 计算入口 isolate H1(pir_lower 路径错)vs H2(pir_opt 路径错)+ Phase 2 修法 target 锁定 file:line + LOC 估算 + 跨 D 起首回填 D164 §Phase 0 hash 至 D164.md 4 处
