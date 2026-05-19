# c11_release_varlist — emitReleaseVarList 收口方案对比

D168 §C.11 —— `emitReleaseVarList` 局部变量真实释放切换。Bug 修复 harness 轨 1 方案对比表(MNK §字段 10)。

## Bug 陈述

`bootstrap/gen/gen_rc.ss:108` `emitReleaseVarList` 对所有 tracked 局部 ptr 变量一律 `emitIR("call void @ss_rc_release(...)")`(line 117)。`ss_rc_release` 靠对象头 `magic@-4 == 1397969747` 守卫;D168 P1(String 切轨)/ P2(Array 切轨)后 string / Array / class 实例是 NEW-系统对象,magic 不匹配 → `ss_rc_release` 静默 no-op → **容器局部永不真实回收 = 局部泄漏**。同时双 RC 系统在 codegen-local 释放出口未统一,d095(I024)/I025「半迁移不平衡」根因、§C.10-map 留下的 `ss_mapSet`-update / `ss_mapDelete` 两处 no-op-release 均无法消除。

## RED

```
$ grep -n 'ss_rc_release' bootstrap/gen/gen_rc.ss
117:        emitIR(`  call void @ss_rc_release(ptr ${r})`)
```

line 117 在 `emitReleaseVarList` 函数体内,一律旧 RC、未类型分派。代码形态 RED(leak 类 bug 无快速行为 RED,类比文件拆分类形态 RED)。117 行仍 `ss_rc_release` → 未达成,任务成立。

## 根因 + §假设破裂入口

根因 = 双轨制(`ss_rc_*` 旧 / `ss_*` 新)在 codegen-local 释放路径未统一,`emitReleaseVarList` 是双轨割裂的最后一个 codegen-local 出口。

**§假设破裂入口**:

- **(a) 新旧布局 no-op 掩盖** — `ss_rc_release`/`ss_rc_retain` 靠 `magic@-4 == 1397969747` 守卫(`gen_runtime.ss:332`),对 NEW-系统对象 magic 不匹配 → 静默 no-op。该 no-op **掩盖**「释放从未真正发生」;`emitReleaseVarList` 切真实 release 而配对 retain 仍 no-op 时,**假设破裂**:real release − noop retain = over-release UAF。
- **(b) isOwnedExpr METHOD_CALL=0 借入假设** — `map.get`/`arr[i]` 是 METHOD_CALL/INDEX → `isOwnedExpr=0`(`gen_decls.ss:64`)→ 编译器假设「binding 侧补一个配对 retain」。binding-site retain 硬编码 `ss_rc_retain`(`gen_decls.ss:658`,对 NEW string no-op)时,「借入值获配对 retain」**假设破裂**。
- **(c) borrow-then-mutate** — `map.get` 返 borrowed 引用,后续 `map.set`-update / `map.delete` 真实 release 在 scope 中段 free 旧值 → 借入引用悬空(§C.10-map §643 实测 318/10 d095 SIGSEGV)。get 结果未在 binding 侧 retain 成 locally-owned 即遭遇容器 mutation = 破裂触发点。

## 候选方案对比

| 候选 | 层次 | 方案 | 在哪层消除/绕过假设破裂 | 长久 / 演化 |
|---|---|---|---|---|
| A | 数据层 patch | 只切 `emitReleaseVarList` 单点为类型分派,retain 侧(genVarDecl/genAssign)不动 | **不消除** — 仅切释放侧,(a) 破裂入口暴露:release real + retain noop = over-release。即 §C.9-exec P2.3b 实测态(切 string → 303/25 string-in-Map UAF;收窄切 Array → 322/6 stdlib_sort over-release) | 短期权宜 — 实测即崩,不可上线 |
| B | 接口层 trap | `emitReleaseVarList` + 配对 retain 侧(genVarDecl/genAssign borrowed-retain)+ field-assign string PLUS_ASSIGN old-release + map update/delete value-release **全部**统一经 `emitRetainForType`/`emitReleaseForType`/`ss_release_any` 类型/magic 分派 —— codegen-local + field-assign 路径零硬编码 `ss_rc_*` | **(a)(b)(c) 全消除**:retain/release 走同一分派函数 → 对任意类型强制对称(real-real 或 noop-noop,绝无 real-noop);get 结果经 binding-site retain 成 locally-owned → borrow-then-mutate 不悬空 → map update/delete 可安全真实 release | B 的统一分派 = C/Phase 5 的底座,非返工;业界(Lean4 Perceus / Swift ARC)均先 retain/release 平衡后 liveness 优化 |
| C | 架构层 refactor | 容器局部纳入 PIR liveness 分析(如 class 实例),`emitReleaseVarList` 整体消失,PIR 精确调度 release | 架构层根除「函数末尾批量释放」本身,(a)(b)(c) 不再存在 | **依赖未落地基础** —— D168 Phase 5 §F(F1/F3 明示「Phase 5 完成 + escape analysis spike」之后);B 是 C 的 hard 前置(retain/release 平衡正确是 liveness 优化前提) |
| D | 接口层(误) | `genMapMethod("get")`/`genIndexAccess` 内部 retain + `isOwnedExpr(METHOD_CALL)` 改 owned | 接口层补 get 侧,但与 (b) 协议冲突 | blast radius = 全部 method call(不止 map.get),与全栈 `isOwnedExpr(METHOD_CALL)=borrowed` 假设冲突 → N 年返工度高 |

## 决策

**选 B 因** 它是唯一同时:(1) 消除 (a) real-vs-noop 不对称崩溃根 —— retain/release 经同一分派函数强制对称;(2) 兑现 D168 §第一性需求 C4「deterministic Perceus RC for all values」容器局部确定性回收;(3) 不依赖未落地基础设施。**为何不选更深的 C(架构层)**:C(PIR 容器 liveness)物理依赖未落地的 escape analysis spike(D168 §F),属 Phase 5 scope;且 B 的统一 `emitRetainForType`/`emitReleaseForType` 分派正是 C 的底座 —— 先 B 后 C 是业界演化客观顺序(retain/release 平衡正确 → 再 liveness 优化),非短期权宜。**A** 数据层只切释放侧留不对称,§C.9-exec 已实测崩(303/25 / 322/6)。**D** blast radius 失控。根因解决度评分:B 消除 3 个假设破裂入口全部、A 消除 0、C 消除 3 但不可达、D 消除 1 引入新冲突 → B 最高且可达。

## §实证(MNK §字段 12)

### 根因定位 grep 证据

```
$ grep -n 'ss_rc_release' bootstrap/gen/gen_rc.ss
117:        emitIR(`  call void @ss_rc_release(ptr ${r})`)        # emitReleaseVarList 一律旧 RC

$ sed -n '332,334p' bootstrap/gen/gen_runtime.ss
    irICmp("isrc", "eq", "i32", "%mag", "1397969747")            # magic@-4 守卫
    irBrCond("isrc", "check", "done")                            # 不匹配 → done(no-op)

$ grep -n 'ss_rc_retain\|ss_rc_release' bootstrap/gen/gen_decls.ss bootstrap/gen/gen_assigns.ss
gen_decls.ss:658     ss_rc_retain      # genVarDecl else-branch borrowed-retain(NEW string no-op)
gen_assigns.ss:341   ss_rc_retain      # genAssign ASSIGN tracked-ptr retain
gen_assigns.ss:344   ss_rc_release     # genAssign ASSIGN tracked-ptr old-release
gen_assigns.ss:393   ss_rc_release     # genAssign PLUS_ASSIGN string local old-release
gen_assigns.ss:229   ss_rc_release     # genFieldAssign PLUS_ASSIGN string field old-release
gen_assigns.ss:458   ss_rc_release     # genStaticFieldAssign PLUS_ASSIGN string field old-release

$ grep -n 'ss_rc_release' bootstrap/gen/rt/gen_rt_map.ss
97:    irCallVoid("ss_rc_release", "ptr %oldp")     # ss_mapSet update value-release,§C.10-map 留锚 §C.11
239:   irCallVoid("ss_rc_release", "ptr %dvptr")    # ss_mapDelete value-release,§C.10-map 留锚 §C.11
```

### 继承蓝图假断言核对(next_prompt)

next_prompt「三容器 retain 侧全切完(String P1 / Array P2.3a / Map 本轮)」→ **部分假断言**。实证:容器**内部 set/push 侧**切完(`gen_builtins.ss:244` map set `ss_retain_any` ✓ / `:140` array push `emitRetainForType` ✓),但 **codegen-local binding-retain**(`genVarDecl:658` / `genAssign:341` 借入局部 retain)仍硬编码 `ss_rc_retain`。精确表述 =「容器内部 retain 切完,codegen-local binding-retain 未切」;§C.11 scope 必含后者(已纳入候选 B / 决策)。

### 8 处改动清单(候选 B,§C.9-exec「部分推进必 regress」→ 原子单元)

| # | 文件:位置 | 改动 |
|---|---|---|
| 1 | gen_rc.ss `emitReleaseVarList` | `ss_rc_release` → 读 entry type 段(新增 `rcEntryType` helper)+ `emitReleaseForType(r, type)` |
| 2 | gen_decls.ss:655-659 `genVarDecl` | if/else 收敛为 `emitRetainForType(val, trackType)`(消硬编码 `ss_rc_retain`) |
| 3 | gen_assigns.ss:341,344 `genAssign` ASSIGN | `ss_rc_retain`/`ss_rc_release` → `emitRetainForType`/`emitReleaseForType`(vType) |
| 4 | gen_assigns.ss:393 `genAssign` PLUS_ASSIGN string | `ss_rc_release` → `emitReleaseForType(r1, "string")` |
| 5 | gen_assigns.ss:229 `genFieldAssign` PLUS_ASSIGN string | `ss_rc_release` → `emitReleaseForType(r1, fType)` |
| 6 | gen_assigns.ss:458 `genStaticFieldAssign` PLUS_ASSIGN string | `ss_rc_release` → `emitReleaseForType(r1, fType)` |
| 7 | gen_rt_map.ss:97 `ss_mapSet` update | `ss_rc_release` → `ss_release_any` |
| 8 | gen_rt_map.ss:239 `ss_mapDelete` | `ss_rc_release` → `ss_release_any` |

### 最危险假设 + 最小 spike

- **最危险假设**:Phase 3 done + 全 retain 侧对齐后,`emitReleaseVarList` 切真实 release = 0 regression。§C.9-exec P2.3b 在 Phase 3 之前实测此假设**破裂**(303/25 / 322/6)。
- **spike 单元**:§C.9-exec「部分推进必 regress」—— 8 处改动是不可再分的原子相干单元(任何中间态 = real-noop 不对称崩);spike = 8 edit 协调改 + `./build.sh bootstrap` 三阶段固定点 + `bin/ss test tests/`。baseline = 323 passed / 5 failed(`harness_bug`/`d096_p4_l2_reactive`/`harness_task`/`spring_web_params` 4 项稳定 + `generic_constraint_basic` I025 非确定 flap)。
- **spike 结果**:三轮(MNK §字段 12 回方案层修正)。**轮 1** type-based 分派(候选 B 原 `emitReleaseForType`/`emitRetainForType`)→ bootstrap stage3 SIGSEGV(`genReturn` 用 `inferType(valId)` 对 method-call 返回式不精确 → return-retain 落 noop → 返回值 over-release UAF,最小复现 `Sort.descending`)。**轮 2** magic 分派 `ss_*_any` 无门 → bootstrap PASS / `stdlib_sort` 修复,但 `ref_basic`/`channel_basic`/`channel_bounded` 崩(`Ref`/`Channel` 是 calloc'd 第三类对象,无 OLD magic 亦非 NEW ObjHeader)。**轮 3** magic 分派 + `isRcManaged` 正列表门 → bootstrap 三阶段 bit-identical + 全测 324/4 三轮稳定 0 regression,**GREEN**。**候选 B 实施修正**:编译期类型名分派 → magic 运行时分派(`ss_*_any`)+ `isRcManaged` 门控第三类对象;`genReturn` 按声明返回类型(精确)判定。详 `docs/3-decisions/D168 §C.11`。
