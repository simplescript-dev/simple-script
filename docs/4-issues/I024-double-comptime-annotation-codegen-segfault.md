# I024 — `@Getter`+`@Setter` 双 comptime 注解同 class → 编译器 codegen SIGSEGV(f21271d regression)

**父决策:** `f21271d` regression —— 横跨 D168 §C.9（RC dispatch 迁移）+ SS-LIM-2（`genIndexAssign` obj-expr 重写),un-MNK 巨型 commit 悄引入
**状态:** Planned —— Execute 轮(2026-05-18)within-commit bisect 已**收敛坐实** culprit hunk(`gen_rc.ss emitReleaseVarList` 的 `Array→ss_release` 分派);但实测每个 within-I024 surgical 修法均有真实缺陷,唯一干净修法须跨 D168 设计变更(P2.3 数组 RC 全栈统一)→ 按 task escape clause **降级 Plan 交还裁决**(详见 §2026-05-18(Execute))
**颗粒度:** 预估 中 —— `f21271d` 是 396-insertion 多文件 commit,需 within-commit bisect 定位 culprit hunk + Bug Harness §轨1
**依赖:** 无(独立 root cause);**I023 依赖本 issue** —— d095 污染全测 baseline,I023 候选 A 的真实 regression delta 必须在 d095 修复后(还原干净 baseline)才能干净测量
**创建:** 2026-05-18
**立项由:** I023 2026-05-18(订正)轮 —— previous round 误把 baseline 既存的 d095 segfault 归因候选 A;本轮 bisect 证伪并按 MNK §衍生 issue 归档「非阻挡 → 独立立项」拆出

---

## 现象

`bin/ss build tests/phase5/d095_setter_mixed.ss` → 编译器 **SIGSEGV(exit 139)**,确定性 3/3 + 从源树 fresh stage1 重建后复现。崩的是编译器进程本身(SS 自举编译器),非被编译程序的 runtime crash。

`d095_setter_mixed.ss` = `@Getter`+`@Setter` 双 comptime 注解同 class `Person { name: string; age: int }`(`lib/lombok.ss` 的 lombok 式注解,各为每字段生成 `get_<f>` / `set_<f>` 方法)。

## bisect — regression 引入点(客观机器证据)

`bin/ss` git-tracked → 每 commit 二进制可直接抽出测 `build d095`:

| commit | subject | `build d095` |
|---|---|---|
| 9edf09b | D168 P1.2 | exit 0 |
| 0583e6a | D168 P1.3 | exit 0 |
| 4b4a2c0 | D168 §C-design | exit 0 |
| daa40e8 | D168 P2.1 | exit 0 |
| d062c18 | D168 P2.2 | exit 0 |
| **f21271d** | **"add"** | **SIGSEGV** ← regression 引入点 |
| b3fb14f | docs(SS-LIM-6) | SIGSEGV |
| 32dc3dd | test(I023) | SIGSEGV |

## 最小复现 — 双注解交互

| 输入 | `bin/ss build` |
|---|---|
| `@Getter` 单独(同 class) | exit 0(通过) |
| `@Setter` 单独(同 class) | exit 0(通过) |
| `@Getter` + `@Setter` 同 class | **SIGSEGV** |

→ 单注解 codegen 无缺陷;**双 comptime 注解的交互 / 跨方法状态累积**才触发。`@Getter`+`@Setter` 同 class 共生成 4 个方法(`get_name`/`get_age`/`set_name`/`set_age`)。

## crash 相位

`bin/ss build d095 --emit-ir` 实测:崩溃发生**在 codegen 中**(非 post-codegen / 非 llc 阶段)。crash-build 的 `.ll` = **5688 行 / 182091 字节**,正常(d062c18)`.ll` = **6110 行 / 202973 字节** —— IR 发射至 ~93% 中止,`.ll` 尾部停在一个 `@Getter` 方法(`Person_get_age`)之后;缺失的 ~420 行是后续 setter / `main` / per-class drop 函数等。

## root cause 方向(待 Execute 轮坐实)

`f21271d` commit message 仅 "add"、396 insertion、未走 MNK 流程,捆绑三股改动,任一均可能是 culprit:

1. **D168 §C.9 RC tracking schema 迁移**(`gen_rc.ss`):`localPtrVars` / `blockPtrVarStack` 由 `,`-flat 升级为 `name:type`(`;` 分隔)+ `|`(block 分隔);`trackPtrVar` 加 `ssType` 形参 + 多调用点改写;`emitReleaseVarList` 改 `;`-split + type-aware dispatch。**嫌疑**:跨方法 codegen 时 `blockPtrVarStack` 等 RC tracking state 是否在方法间正确 reset(`genClassMethod` / `genFuncDecl`)—— 单注解 2 方法不溢出、双注解 4 方法累积越界 的现象与此一致。
2. **SS-LIM-2 `genIndexAssign` obj-expr 重写**(`stmts_simple.ss` / `check_stmts.ss` / `parse_stmts.ss`):setter 体 `this[f.name] = v` 是 comptime-string-index 的 INDEX_ASSIGN,直接走重写后的 `genIndexAssign`。
3. `gen_arrows.ss` / `gen_builtins.ss` RC dispatch 改写。

需 **within-`f21271d` bisect**:把 `f21271d` 源逐文件 revert 到 `d062c18` 版、rebuild stage1、测 d095 → 定位 culprit 文件,再 hunk 二分。

## 步骤

1. within-`f21271d` bisect 定位 culprit 文件 → hunk
2. 走 CLAUDE.md §Bug 修复 Harness §轨1:产 `d095_setter_mixed.options.md`(≥3 候选 + 层次标 + 决策行 + 假设破裂标识),`bin/ss build tools/bug_options_linter.ss` GATE OK 才 Execute
3. 根因修复(`f21271d` 的 RC 协议大改不应在调用方加 workaround —— 修 codegen / reset 逻辑本身)
4. RED→GREEN:`bin/ss build tests/phase5/d095_setter_mixed.ss` exit 0 + 运行 exit 0
5. bootstrap 三阶段 Stage2=Stage3(`xxd` 缺失须 `cmp /tmp/ss_stage2 /tmp/ss_stage3` 自验)+ 全测 0 regression
6. 回归测试已存在(`tests/phase5/d095_setter_mixed.ss`),无需新增

## 反向

不修 → 全测 baseline 永久带一个未归档 segfault,每轮 regression 计数失真;I023 候选 A 的真实安全性无法干净评估(I023 §2026-05-18(订正))。

## 流程教训

- `f21271d` 是 "add" 单词 commit message、396 insertion、未走 MNK 八股流程的巨型 commit —— 在 `d062c18→f21271d` 间悄悄引入 d095 regression,无人测。**根因之一是 un-MNK'd 巨型 commit 绕过了档位 / VCM / 全测 gate。**
- previous round(I023 2026-05-18)误把 d095 归因候选 A,因为漏走 MNK §特定领域 §untracked-test-fail 诊断流程(stash 本轮改动 + rebuild baseline + 隔离单测,区分 pre-existing vs introduced)。

---

## 2026-05-18(Execute)—— within-commit bisect 收敛 + 根因须跨 D168 设计变更,降级 Plan

本轮按 §步骤 做 within-`f21271d` bisect,**bisect 收敛、culprit hunk 机器锁定**;但 Execute 阶段实测发现**无 within-I024 干净修法**,根因修复须跨 D168 设计变更 → 按本轮 task escape clause「within-bisect 不收敛或根因须跨 D168 设计变更则降级 Plan 交还裁决」**降级 Plan**。完整方案对比见 `d095_setter_mixed.options.md`(`bug_options_linter` 5/5 GATE OK)。

### A. within-commit bisect(feature-cluster → file → hunk,机器证据)

| 实验 | 配置 | stage2 build d095 |
|---|---|---|
| revert 全 7 compiler 文件 → d062c18 | 纯 d062c18 源 | **exit 0**(stage2/stage3 固定点)—— stage1 仍崩 |
| Test-RC:revert {gen_rc,gen_decls,gen_arrows,gen_builtins} | RC cluster | **exit 0** |
| Test-SSLIM2:revert {parse_stmts,check_stmts,stmts_simple} | SS-LIM-2 cluster | exit 139 |
| Test-U4:revert {gen_rc,gen_decls} | | **exit 0** |
| Test-U56:revert {gen_arrows,gen_builtins} | | exit 139 |
| Test-H1:`emitReleaseVarList` 的 `isArrayType→ss_release` 改回 `ss_rc_release` | 单 hunk | **exit 0** |

→ **culprit hunk**:`bootstrap/gen/gen_rc.ss` `emitReleaseVarList` 的 `if (isArrayType(ssType)==1) call ss_release else call ss_rc_release`。

**这是 miscompilation**:revert 全 7 文件 = 纯 d062c18 源,但 f21271d-seed 编译出的 stage1 仍崩、stage2 还原 GREEN —— f21271d `bin/ss` 自身误生成代码,污染它编译出的 stage1。bisect 须测 stage2。

### B. 崩溃机理(core 解析 + addr2line)

RIP = `ss_arrayPush+0x48`(`mov %r14,(%rax,%r15,8)`),`rax=0`(`array.data` NULL)、`r12=0xdedededededede`(mimalloc freed-block 毒值)→ **use-after-free**。调用栈 `genClassDecl→runComptimeAnnotationCall→runComptimeBlockBody→…→ss_arrayPush` —— 运行 `@Getter`/`@Setter` 注解处理器(`@methodOf` 向类方法数组 `.push()`)时该数组已被释放。

**根因**:新旧 RC 系统对象布局不兼容 —— 旧 `ss_rc_release`:rc@`p-16`、`p-4` 处 magic-number guard(`1397969747`),**对非旧布局对象因 guard 失配而静默 no-op**;新 `ss_release`:rc@`p+0`、**无 guard**、真实递减+经 TypeInfo vtable drop+free。f21271d D168 §C.9 把 `Array` 释放从 `ss_rc_release` 切到 `ss_release`,但数组 RC 未随 D168 P2 全栈迁移到新系统;旧 `ss_rc_release` 对新布局数组的 no-op 一直**静默掩盖** retain/release 不对称,`ss_release` 真实化即暴露 → 数组提前 free → UAF。

### C. 为何无 within-I024 干净修法(实测,各候选已建编译器全测对照)

| 候选 | 改动 | 实测缺陷 |
|---|---|---|
| A | 仅 revert `emitReleaseVarList` Array→`ss_rc_release` | d095 ✓、`generic_constraint_basic` ✓、全测 323/5 —— 但 `genVarDecl` 仍 `emitRetainForType(Array)→ss_retain` 而 release 侧 no-op → **借入 `Array<T>` `let` 局部净新增编译期泄漏**(d062c18/f21271d 均平衡对) |
| A' | revert `emitReleaseVarList` + `genVarDecl` Array-retain 两侧 | d095 ✓ —— 但 `generic_constraint_basic` standalone **8/8 regress**(d062c18 ✓ / f21271d ✓);gen_rc/gen_decls 退 d062c18 而 gen_arrows/gen_builtins 仍 f21271d → RC 半迁移不一致 |
| B | revert {gen_rc,gen_decls} 整体 | d095 ✓ —— 但半迁移不一致;扩到 revert `gen_builtins` 则 **regress SS-LIM-6 §E**(`gen_builtins:140-143` 的 `emitRetainForType` 是 SS-LIM-6 corruption 闭合修法) |
| C | 完成 D168 P2.3 数组 RC 全栈统一 | **唯一一致、无泄漏、无 regression** —— 但属 D168 设计变更 |

**纠缠实证**:f21271d 的 D168 §C.9 是**未走 MNK 的纠缠半迁移** —— 同一 commit 既引入 d095 UAF、又落地 SS-LIM-6 §E 修法、又靠 miscompilation 意外掩盖 generics 测试既存 latent bug(`generic_multi_constraint` 在 d062c18 干净基线即 standalone 6/6 fail)。任何**部分** revert 必产生不一致并 regress。

### D. 降级 Plan —— 待裁决路径

- **路径 1(根因)**:完成 D168 P2.3 数组 RC 全栈统一 → §C.9 的 `ss_release` 才正确平衡。D168 主线 Phase。
- **路径 2(regression)**:审计式 un-pick §C.9 —— RC dispatch 在 4 文件**一致**回退 d062c18,但单独保留 SS-LIM-6 §E。D168 §C.9-scope 决策。
- **路径 3(临时·不推荐)**:接受 Candidate A 作临时补丁(消 segfault、全测 0 regression,代价 = 有界编译期泄漏)。

### E. 衍生 issue

`tests/phase5/generic_multi_constraint.ss` 在 d062c18 干净基线即 standalone 确定性 fail —— 既存 broken 测试(`bin/ss test` runner 偶计 pass 掩盖之),按 MNK §衍生 issue 独立立项。
