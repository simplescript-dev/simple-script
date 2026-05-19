# I025 — `generic_multi_constraint.ss` broken test:D168 P2.3 数组 RC 半迁移致编译器自身 codegen 形态敏感非确定 miscompilation

**父决策:** D168《统一双 RC 系统为 Perceus 主线》§C.9-exec(P2.3 数组 RC 半迁移);与 `I024` 同根不同症
**状态:** Planned —— 根因 = D168 P2.3 数组 RC 半迁移(`f21271d` un-MNK 半成品),与 I024 d095 segfault 同根。本 issue **无独立修复代码**:D168 P2.3a/P2.3b 完成、编译器自身数组 RC 迁移到一致新系统后,本 miscompilation 自动消解,届时按 §步骤 复验关闭
**颗粒度:** 立项轮 = 纯文档(本文件);"修复" = D168 P2.3 子集,无独立 LOC
**依赖:** 根因依赖 D168 P2.3(P2.3a runtime 侧 §C.9/§C.10 + P2.3b codegen-local 侧对齐)。P2.3 完成前本 issue 不可独立关闭
**创建:** 2026-05-18
**立项由:** I024 §E + D168 §C.9-exec §衍生 issue —— I024 Execute 轮 within-commit bisect 发现 `f21271d` 的 miscompilation「意外掩盖」generics 测试既存 latent bug;`generic_multi_constraint.ss` 在 d062c18 干净基线 standalone 确定性 fail,按 MNK §衍生 issue 归档「非阻挡 → 独立立项」拆出,不混入 D168 P2.3 / I024 的 regression 计数

---

## 现象 — 版本 + 形态依赖的非确定 miscompilation

`tests/phase5/generic_multi_constraint.ss` 测泛型多约束(`<T extends Printable & Scorable>` 双约束 / 三约束 / mixed / 泛型 class `Wrapper<T>` / 显式 type args)。测试本身**语义正确**;问题在编译它的**编译器**(SS 自举编译器二进制)codegen 阶段不稳定。

实测矩阵(d062c18 编译器 vs 当前 `bin/ss` = `dac2258`;原版 + 3 个 `main` 形态变体,interface/class/泛型函数定义完全相同):

| `main` 形态 | d062c18 | 当前 `bin/ss`(dac2258) |
|---|---|---|
| 原版:`const rN=fn()` + `if(rN!=lit){exit(1)}` | build OK / **run `exit 1` 确定 6/6** | build OK / run `exit 0` 稳定 20/20 |
| 变体①:直接 `println(\`${fn()}\`)`,无 `const` | build OK / run OK | **build 偶发 `error: llc failed`(实测 1/22)** / 否则 run OK |
| 变体②:`const rN=fn()` + `println(\`${rN}\`)` | build OK / run OK 3/3 | build OK 15/15 / run OK |
| 变体③:原版结构,`exit(1)`→`println("FAIL...")` | build OK / run OK 全 "done" 3/3 | build OK / run OK 3/3 |

**两条客观异常**:
1. **同编译器、同源文件、同一 `build` 命令两次结果不同** —— 当前 `bin/ss` 编译变体① 首次 `llc failed`、立即重跑 `compiled`,即 codegen **非确定**(生成的 `.ll` 偶发非法,llc 拒收)。
2. **结果对 `main` 形态的微小改动翻转** —— d062c18 下原版 `exit(1)` 版确定 fail,但仅把 `exit(1)` 换成 `println(...)`(变体③)、或把 `if` 换 `println`(变体②)、或去掉 `const`(变体①),全部翻转为 PASS。`if` 条件 `rN != lit` 的求值结果受 **then 分支体内容** 影响 —— 逻辑上不可能,只能是 codegen RC 调度产物。

## 对既有描述的订正(诚实声明)

I024 §C / §E 与 next_prompt 称本 test「broken / d062c18 standalone 确定性 fail」。实测**精确化**:
- 「确定性 fail」仅成立于 **d062c18 编译器 + 原版 `exit(1)` 形态**(run `exit 1`)。
- **当前 `bin/ss`(dac2258)对原版 standalone 稳定 PASS(20/20)** —— 下轮勿误以为当前编译器跑此 test 必 fail。
- 当前编译器的真实缺陷是 codegen **非确定**(变体① 偶发 `llc failed`),原版恰好落在「毒值不命中」区。
- I024 dac2258 收尾节记「`generic_multi_constraint` 并发 flaky」—— `bin/ss test` 并发 race(MNK §特定领域)叠加本 codegen 非确定,使 runner 计数在 pass/fail 间抖动。

## root cause 方向(待 D168 P2.3 Execute 坐实)

证据链指向**编译器自身**数组 RC 半迁移 use-after-free —— 与 I024 d095 同根:

1. 对编译器版本敏感(d062c18 / dac2258 落地的 RC 改动不同)→ RC 路径。
2. 对源码形态敏感(`const` / `if`-then-body / 局部变量数 → PIR liveness → release 插入点)→ RC release 调度。
3. codegen 非确定(`llc failed` 偶发)→ freed block 是否被 mimalloc reuse、reuse 成什么内容,运行时非确定 → use-after-free 典型特征。
4. I024 §B 已 core-dump 实证编译器自身 `ss_arrayPush` UAF(`r12=0xdedededededede` mimalloc freed 毒值),栈 `genClassDecl→runComptimeAnnotationCall→…→ss_arrayPush`。
5. I024 §C 明示 `f21271d` 的 miscompilation「意外掩盖 generics 测试既存 latent bug(`generic_multi_constraint`)」。

根因 = D168 P2.3 数组 RC **半迁移**(`f21271d` un-MNK 半成品:codegen-local 释放侧切 `ss_release`、runtime 侧 §C.9/§C.10 仍 dead-code → 数组 RC 不平衡 → 编译器自身用于 codegen 的数组被 over-release / UAF)。详 D168 §C.9-exec、I024 §A/§B。

## 与 I024 的关系 —— 同根不同症

| | I024(d095) | I025(本 issue) |
|---|---|---|
| 症状 | `@Getter`+`@Setter` 双注解 codegen **SIGSEGV** | 泛型多约束 codegen **非确定 miscompile**(`llc failed` / d062c18 run-fail) |
| 触发面 | comptime 注解处理器向类方法数组 `.push()` | 泛型实例化 codegen 的数组中间状态 |
| 当前态 | Resolved —— Candidate A 表面消除 d095 症状(`dac2258`) | Planned —— 症状仍在(非确定 codegen) |
| 根因 | **同一个:D168 P2.3 数组 RC 半迁移** | **同一个** |

I024 Candidate A 仅撤销 `emitReleaseVarList` 的 `Array→ss_release` 单 hunk —— **表面消除 d095 这一个症状**,根因(半迁移)未除(I024 §残留 + D168 §C.9-exec 子步 P2.3c 已记账 over-retain 泄漏)。本 issue 是同根因的**另一个症状暴露面**,佐证「Candidate A 是表面修复,根因须 D168 P2.3」。

## 步骤(修复 = D168 P2.3,本 issue 仅复验)

1. 本 issue **不写独立修复代码** —— 根因修复 = D168 P2.3(P2.3a runtime §C.9/§C.10 + P2.3b codegen-local 对齐一致新系统)。
2. P2.3a/P2.3b 落地后,在本 issue 复验关闭判据:
   - `bin/ss build tests/phase5/generic_multi_constraint.ss` × ≥ 20 全 `exit 0`(codegen 确定,无 `llc failed`)。
   - 原版 + 变体①②③ 四形态 × ≥ 10 次全 build + run `exit 0`。
   - `bin/ss test tests/` 并发 runner 下 `generic_multi_constraint` 稳定计 pass(连续 ≥ 3 次全测)。
3. 全 GREEN → 本 issue §状态 改 Resolved,记录关闭 commit。

## 反向

不立项 → 这个 broken/flaky test 仅散落在对话与 commit message,下轮 Claude 读不到(MNK §核心原则 4);`bin/ss test` 并发 runner 对它的 pass/fail 抖动持续污染 regression baseline → D168 P2.3 与 I023 的「全测 0 regression」判据建立在脏 baseline 上(I024/I023 已被同类污染坑过一次 —— d095 误归因,见 I023 §2026-05-18(订正))。

## 流程教训

- `f21271d` un-MNK 巨型 commit("add" 单词 message、396 insertion)一次性引入 d095 segfault(I024)+ generic miscompile(本 issue)+ SS-LIM-6 §E 修法,三者纠缠;任何**部分** revert 都 regress(I024 §C 实证)。根因之一是 un-MNK commit 绕过档位 / VCM / 全测 gate。
- 本 issue 立项前,`generic_multi_constraint` 仅以「broken test」出现在 I024 §C/§E 与 next_prompt 的散述中,且描述不精确(「确定性 fail」实为版本 + 形态依赖)。MNK §衍生 issue 归档要求「非阻挡 → 必写 issue 文件,不许只对话 / commit msg / memory 记」—— 本文件兑现并订正之。

---

## 2026-05-19 补记(D168 Phase 3 Map RC 落地观察)

D168 §C.10-map(Map value RC,`gen_runtime`/`gen_builtins`/`gen_rt_map`)落地后,`bin/ss test` 并发 runner 下 generic 族(`generic_constraint_multi`/`generic_constraint_basic`/`generic_multi_constraint` 等)**非确定 flap** —— 逐 run 命中项与计数变(322/6 ~ 323/5),稳定失败的 4 项非 generic 测试恒定。

**新观察 —— 路径 / build-上下文 敏感**:`generic_constraint_multi` standalone(`bin/ss build tests/phase5/...` 单斜杠)实测一个 15/15 PASS streak、binary run 50/50 exit 0;`bin/ss build tests//phase5/...`(**双斜杠**,`bin/ss test` harness 用 `testDir + "/" + entry` 拼出)实测一个 12/12 exit-1 streak —— 但其后 `bin/ss test` run 又见 `generic_constraint_multi` PASS。即 codegen 输出对**源路径字符串 + build 上下文(顺序/并发堆状态)** 敏感,跨上下文非确定(印证 §C.9-exec「codegen 非确定」=读到未初始化/UAF 内存,堆状态决定结果)。关闭判据(§步骤)须补**双斜杠路径形态**。

**与 D168 的关系**:本 issue 根因 = D168 RC 半迁移;每个 RC 迁移子步(P2.3 数组、Phase 3 Map)扰动编译器堆分配 → I025 触发面翻面。`generic_constraint_multi` 翻 fail **不计入** D168 Phase 3 regression(§C.9-exec「I025 不混入 regression 计数」+ bootstrap stage2==stage3 bit-identical 证编译器确定且正确)。
