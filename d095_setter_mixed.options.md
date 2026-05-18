# d095_setter_mixed segfault — 修法方案对比(I024 / 轨 1)

**bug**: `bin/ss build tests/phase5/d095_setter_mixed.ss` → 编译器 SIGSEGV(exit 139)。`@Getter`+`@Setter` 双 comptime 注解同 class。
**父决策**: `f21271d` regression,横跨 D168 §C.9(RC 协议迁移)。
**issue**: `docs/4-issues/I024-double-comptime-annotation-codegen-segfault.md`
**结论**: ⚠ **Execute 轮订正 —— 无 within-I024 干净修法,降级 Plan**(详见 §5)。

---

## 1. bisect 实证(机器证据)

| 实验 | 配置 | 判据 | 结果 |
|---|---|---|---|
| commit bisect | d062c18 / f21271d 提交内 `bin/ss` 二进制 | `build d095` | d062c18 exit 0 / f21271d **139** |
| revert 7 文件 | 7 个 compiler 文件 → d062c18,三阶段 | stage1 / stage2 测 d095 | stage1 **139** / stage2 **0**,stage2==stage3 固定点 |
| Test-RC | revert {gen_rc,gen_decls,gen_arrows,gen_builtins},stage2 测 | stage2 build d095 | **0** → culprit 在 RC cluster |
| Test-SSLIM2 | revert {parse_stmts,check_stmts,stmts_simple},stage2 测 | stage2 build d095 | **139** → 不在 SS-LIM-2 |
| Test-U4 | revert {gen_rc,gen_decls},stage2 测 | stage2 build d095 | **0** → culprit 在 {gen_rc,gen_decls} |
| Test-U56 | revert {gen_arrows,gen_builtins},stage2 测 | stage2 build d095 | **139** → 非 culprit |
| Test-H1 | `emitReleaseVarList` 的 `isArrayType→ss_release` 改回 `ss_rc_release`,stage2 测 | stage2 build d095 | **0** → culprit hunk 锁定 |

**关键**:revert 7 文件 = 纯 d062c18 源,stage1 仍崩 / stage2 还原 GREEN —— 即 f21271d `bin/ss` 自身误生成代码(**miscompilation**),bisect 须测 stage2。

**culprit hunk**:`bootstrap/gen/gen_rc.ss` `emitReleaseVarList` 的 `if (isArrayType(ssType)==1) ss_release else ss_rc_release`。

## 2. 崩溃实证(core 解析)

RIP = `ss_arrayPush+0x48`(`mov %r14,(%rax,%r15,8)`,`rax=0` array.data 为 NULL,`r12=0xdedededededede` mimalloc freed 毒值)→ **use-after-free**。调用栈 `genClassDecl→runComptimeAnnotationCall→runComptimeBlockBody→…→ss_arrayPush` —— 运行 `@Getter`/`@Setter` 注解处理器(`@methodOf` 向类方法数组 `.push()`)时,该数组已被释放。

## 3. 根因

新旧 RC 系统对象**布局不兼容**:旧 `ss_rc_release` —— rc@`p-16`、`p-4` magic guard(`1397969747`),**对非旧布局对象因 guard 失配静默 no-op**;新 `ss_release` —— rc@`p+0`、**无 guard**、真实递减+free。f21271d D168 §C.9 把 `Array` 释放从 `ss_rc_release` 切到 `ss_release`,但数组 RC 未随 D168 P2 全栈迁移 —— 旧 `ss_rc_release` 对新布局数组的 no-op 一直**静默掩盖** retain/release 不对称;`ss_release` 真实化 → 数组提前 free → UAF。

**假设破裂入口**:`emitReleaseVarList` 把释放从 `ss_rc_release` 切 `ss_release` 隐含假设「语义保持 no-op 重构 / 数组已新 RC」—— 假设破裂:`ss_rc_release` 对新布局是静默 no-op、`ss_release` 是真实 free;数组 RC 未全栈迁移。

---

## 4. 候选对比 + Execute 轮实测(每候选已建编译器全测对照)

| 候选 | 层次 | 改动 | Execute 轮实测结果 |
|---|---|---|---|
| A | 数据层 patch | 仅 revert `emitReleaseVarList` 的 Array→`ss_release` | d095 ✓、`generic_constraint_basic` ✓(8/8)、全测 323/5 —— **但** `genVarDecl` 仍 `emitRetainForType(Array)→ss_retain`、release 侧 `ss_rc_release`(no-op)→ **借入 `Array<T>` `let` 局部净新增泄漏**(d062c18/f21271d 均为平衡对,A 单向破坏) |
| B | 接口层 trap | revert {gen_rc,gen_decls} 整体到 d062c18 | d095 ✓ —— **但** gen_arrows/gen_builtins 仍 f21271d → RC 半迁移**不一致**;且若扩到 revert gen_builtins 则 **regress SS-LIM-6 §E**(`gen_builtins:140-143` 的 `emitRetainForType` 是 SS-LIM-6 corruption 闭合修法,见 I023 §备注) |
| A' | 接口层 | revert `emitReleaseVarList` + `genVarDecl` Array-retain 两侧 | d095 ✓ —— **但** `generic_constraint_basic` standalone **8/8 FAIL**(d062c18 ✓ / f21271d ✓ → A' regress 它):gen_rc/gen_decls 退到 d062c18 而 gen_arrows/gen_builtins 仍 f21271d → 半迁移不一致 |
| C | 架构层 refactor | 完成 D168 P2.3 —— 数组 RC 全栈统一到新系统 | 未实施。**唯一一致、无泄漏、无 regression 的修法**;但属 D168 设计变更(多 Phase 多文件) |

**flaky 排除**:`generic_multi_constraint` standalone 在 d062c18 / f21271d / A / A' **全部 FAIL**(6-8/各)→ 既存 broken 测试,非任何候选 regression(`bin/ss test` runner 偶计 pass);`generic_constraint_multi` 全 PASS,runner 偶 flaky —— 与 I023 §2026-05-18「generics 测试并发 flaky」一致。

**§决策行**:选 **降级 Plan** 因 A/A'/B 三个 within-I024 surgical 候选实测**各有真实缺陷**(A 净新增泄漏 / A' regress `generic_constraint_basic` / B 半迁移不一致且威胁 §E),**唯一干净修法 C 须跨 D168 设计变更(P2.3 数组 RC 全栈统一)** —— 命中 I024 task escape clause「根因须跨 D168 设计变更则降级 Plan 交还裁决」。

**为何不选 A/A'/B(deeper layer 不可达的诚实声明)**:f21271d 的 D168 §C.9 是一个**未走 MNK、纠缠**的半迁移 —— 同一个 commit 既引入 d095 UAF、又落地 SS-LIM-6 §E 修法、又靠 miscompilation 意外掩盖 generics 测试既存 latent bug。任何**部分** revert 都产生不一致(retain/release 跨新旧、4 文件迁移半留半revert),实测必 regress。一致的修法只有「整体回到 d062c18 一致态」或「整体推进到新 RC 一致态(P2.3)」,二者皆 D168 phase/设计级,非 I024 Execute 轮 scope。

## 5. 降级 Plan —— 交还裁决

within-commit bisect 已**收敛**(culprit hunk 机器锁定),但根因修复须跨 D168 设计变更。建议路径(待用户/D168 裁决):

- **路径 1(根因·长期)**:完成 D168 P2.3 —— 数组 RC 全栈统一到新系统(ObjHeader 布局 + alloc + retain + release + assign + return + 反射数组构建,全部 `ss_*`/新布局)。之后 f21271d §C.9 的 `ss_release` 才正确平衡。属 D168 主线 Phase。
- **路径 2(regression·中期)**:审计式 un-pick f21271d §C.9 —— 把 RC dispatch 在 {gen_rc,gen_decls,gen_arrows,gen_builtins} **一致**回退到 d062c18(消 UAF、消泄漏、恢复一致),但**单独保留/重落** SS-LIM-6 §E(`gen_builtins` class/string push 的 `emitRetainForType`)。须确认 §E 与旧 RC 的配对正确性。属 D168 §C.9-scope 决策。
- **路径 3(临时·不推荐)**:接受 Candidate A 作临时补丁 —— 消 d095 segfault、全测 0 regression,代价是借入数组 `let` 局部的有界编译期泄漏。仅在 segfault 紧急且路径 1/2 无法本轮落地时考虑。

## 6. follow-up

- D168 §C.9 数组/容器 RC 迁移须在 P2.3「数组 RC 全栈统一」之后、按 MNK 重做。f21271d 把它塞进未走 MNK 的 "add" 巨型 commit 且抢在 P2.3 前 = 本 regression 根因。
- `tests/phase5/generic_multi_constraint.ss` 是既存 broken 测试(d062c18 即 standalone fail)—— 按 MNK §衍生 issue 独立立项。
