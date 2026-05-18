# I024 — `@Getter`+`@Setter` 双 comptime 注解同 class → 编译器 codegen SIGSEGV(f21271d regression)

**父决策:** `f21271d` regression —— 横跨 D168 §C.9（RC dispatch 迁移）+ SS-LIM-2（`genIndexAssign` obj-expr 重写),un-MNK 巨型 commit 悄引入
**状态:** Planned —— bisect 已坐实 regression commit + 最小复现已落地;within-commit root cause 待 Execute 轮精确定位
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
