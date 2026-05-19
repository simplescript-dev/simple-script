# map_rc.options.md — D168 Phase 3 Map value RC 方案对比表

**任务**:D168 Phase 3 Map RC(value 侧)—— `map.set` 对 ptr value 切类型分派 retain + Map 三处 runtime value-release 对 NEW-系统 value 真实 release + 无注解 `Map()` val_type 推断。是 §C.11 `emitReleaseVarList` 收口的 hard 前置(消 d095/I024 + I025 根因)。

**RED(本轮已跑)**:
- `grep -n "ss_rc_retain" bootstrap/gen/gen_builtins.ss` → `235`(`genMapMethod("set")` ptr value retain 硬编码 OLD)。
- `grep -n "ss_rc_release" bootstrap/gen/rt/gen_rt_map.ss` → `94`(`ss_mapSet` update 旧值)/`224`(`ss_mapDelete` key)/`234`(`ss_mapDelete` value)/`301`(`ss_mapKeys` 内部 buf)。
- `grep -n "ss_rc_release" bootstrap/gen/gen_runtime.ss` → `ss_rc_destroy_map` value release 在 `437`、key release 在 `430`。

非目标形态(应为 OLD/NEW 分派)→ RED 成立。

---

## 候选方案对比

| 候选 | 层次 | 含义 | 解决根因? | 假设破裂入口 |
|---|---|---|---|---|
| A | 数据层 patch | runtime 三处 `ss_rc_release` 硬改 `ss_release`;codegen set `ss_rc_retain` 硬改 `ss_retain` | ❌ | **假设破裂**:假设「所有 Map value 都是 NEW 系统」— 在 `Map<K, Map<...>>`(value 是 OLD 系统 Map header)状态下破裂:`ss_release` 按 NEW ObjHeader 偏移读 rc,对 OLD Map header(rc@-16/magic@-4 布局)错位 → 崩 |
| B | 接口层 trap | codegen set 走 `emitRetainForType` + `isOwnedExpr`/`pushNonOwning` 门(类型分派);runtime 三处 release 走新增 `ss_release_any`(magic@-4 守卫分派 OLD→`ss_rc_release` / NEW→`ss_release`);val_type flag 在 `.set()` 处按实际 value LLVM 类型 emit(覆盖无注解 `Map()`) | ✅ | **假设破裂**:假设「`isOwnedExpr` 在 Map set 处 owned/borrowed 判定正确」— 误判 owned→borrowed 即 over-retain(泄漏)、borrowed→owned 即 under-retain → 源对象先于消费点被 destroy_map 释放 → UAF。§字段 12 spike 实证此入口 |
| C | 架构层 refactor | 全 Phase 3:Map header 切 `{i64 rc, ptr TypeInfo}` ObjHeader + mimalloc + per-Map TypeInfo + `ss_drop_Map`;value release 退化为通用 `ss_release` | ✅✅(越界) | 假设破裂入口同 P1.3/P2.2 ABI 切轨(全栈 GEP 偏移)— 但 C 解的是「Map 自身 RC」正交轴,非本任务「Map value RC」轴 |
| D | Phase 5 PIR | Map value 纳入 PIR liveness pass 自动 retain/release | ✅✅✅ 终局 | D168 §Phase 收关锚明示属 Phase 5 范畴;依赖 C 先落地(统一 ObjHeader) |

## 层次:纵向(数据/接口/架构)× 横向(底层/中层/上层)

- **纵向深度**:A=数据层(硬编码替换,无分派)。B=接口层(`emitRetainForType` codegen 分派 + `ss_release_any` runtime trap,在「调用入口」处消除系统错配)。C=架构层(Map ABI 重写)。
- **横向演化(长久/N 年返工度)**:D 依赖 C(PIR 集成需统一 ObjHeader);C 依赖 B(value RC 正确是 Map 切轨前提);B **不依赖** C —— Map header 留 OLD,`ss_rc_release` 对 OLD Map header 自洽(`gen_runtime.ss:309-312` magic 守卫已 read 确证)。业界对标:Lean 4 Perceus 容器 RC 演化亦是「element/value RC 先于 container ABI 统一」。B 完整根治 value RC 轴,不会被 C/D 覆盖致返工(C/D 是不同根因轴的后续 Phase)。

## 决策

**决策:选 B,因** B 是本任务 scope(Map value RC,§C.11 hard 前置)的最深可达根因层 —— 消除「硬编码单一 RC 系统」双轨残留 + 「OLD release 对 NEW 对象静默 no-op」假设破裂,且与已落地的 array push 协议(`gen_builtins.ss:140-145` `isOwnedExpr` 门 + `emitRetainForType`)同形。**不选 A**:A 数据层 patch 在 `Map<K,Map<...>>` 嵌套场景假设破裂(value 含 OLD Map header,`ss_release` 错位崩)。**不选 C**:C(Map header ABI 切轨)解的是「Map 自身 RC」正交根因轴,非 value RC 轴的更深层;C 不落地不影响 B 完整根治 value RC,C 留 Phase 3 后续子步 / Phase 4。**不选 D**:Phase 5 PIR 范畴,依赖 C。根因解决度排序:B 完整根治 value RC 轴 > A 部分(嵌套破裂)。

## 改动清单(候选 B)

| 文件 | 位置 | 改动 |
|---|---|---|
| `gen_builtins.ss` | `genMapMethod("set")` ~235 | ptr value retain `ss_rc_retain` → `if (pushNonOwning == 0 && isOwnedExpr(valArgId) == 0) emitRetainForType(val, valType)` + `pushNonOwning = 0`(镜像 array push);ptr value 时 emit val_type flag(`getelementptr i8 objVal, 516` + `store i32 1`)覆盖无注解 `Map()` |
| `gen_runtime.ss` | `ss_release`(~560)后 | 新增 `ss_release_any(ptr)`:null guard → magic@-4 == 1397969747 → `ss_rc_release` / else `ss_release` |
| `gen_runtime.ss` | `ss_rc_destroy_map` ~437 | value release `ss_rc_release` → `ss_release_any` |
| `gen_rt_map.ss` | `ss_mapSet` update ~94 | 旧值 release `ss_rc_release` → `ss_release_any` |
| `gen_rt_map.ss` | `ss_mapDelete` ~234 | value release `ss_rc_release` → `ss_release_any` |

**不动**:Map key(`ss_rc_strdup` cstr,OLD 系统自洽);`ss_mapKeys`:301(OLD 内部 byte buf);`gen_deserialize.ss`(val_type=1 + `emitDeserializeForType` 内 retain 已是 `emitRetainForType` 分派,release 经 `ss_release_any` 自动正确);`gen_decls.ss`(`mapValueIsPtr` 对 typed `Map<K,V>` 仍正确设 val_type=1)。

---

## §实证(MNK §字段 12)

### (a) next_prompt 继承蓝图断言逐条核对(grep / read 证据)

| next_prompt 断言 | 核对命令 + 输出 | 判定 |
|---|---|---|
| 「94/224/234 行 ss_mapSet/ss_drop_Map 对 ptr value 仍旧系统」 | `grep -n ss_rc_release bootstrap/gen/rt/gen_rt_map.ss` → 94(mapSet update value)/224(mapDelete **key**)/234(mapDelete value)/301(mapKeys buf) | **部分修正**:224 是 **key** release(key 是 `ss_rc_strdup` cstr=OLD,正确,不改);无 `ss_drop_Map` 此符号,实为 `ss_rc_destroy_map`(`gen_runtime.ss:400`),value release 在 437 行 |
| 「ss_mapSet 不 retain 新 value」 | `grep -n ss_rc_retain bootstrap/gen/gen_builtins.ss` → 235 | **修正**:retain 在 codegen `genMapMethod("set")` `gen_builtins.ss:235` 硬编码 `ss_rc_retain` emit(对 NEW value no-op);runtime `ss_mapSet` 不 retain 是设计(retain 在 codegen),与 P2.3 `options.md §5-1 修正`(.push retain 在 codegen 不在 runtime)同形 |
| 「切 emitReleaseForType 类型分派」 | `emitReleaseForType` 定义 `class.ss:158`,codegen 时调用 | **修正**:Map 三处 value-release 全是 **runtime** 函数(`ss_mapSet`/`ss_mapDelete`/`ss_rc_destroy_map`),codegen `emitReleaseForType` 无法在 runtime 调用 → runtime release 改用 `ss_release_any`(magic 守卫 OLD/NEW 分派);「emitReleaseForType 分派」仅适用 codegen-side release,本任务无 codegen-side value release |
| 「mapValueIsPtr 对无注解 Map() val_type=0」 | read `gen_rc.ss:200-217` `mapValueIsPtr`:`typeAnn.startsWith("Map<")==0 → return 0`;`gen_decls.ss:674` 仅 `mapValueIsPtr==1` 才 emit val_type=1 | **确认**:无注解 `Map()` 的 mVarType 非 `Map<K,V>` 形 → val_type 恒 0 → value 永不被 destroy_map release。修法:val_type 在 `.set()` 处按实际 value LLVM 类型 emit(typed/untyped 统一覆盖) |
| OLD RC 函数对 NEW 对象行为(no-op 掩盖) | read `gen_runtime.ss:309-312` `ss_rc_release`:`magp=p-4; mag=load i32; isrc = mag==1397969747` 才进 release 分支,否则 `→done` | **确认**:NEW 对象无 magic@-4 → `ss_rc_release`/`ss_rc_retain` 静默 no-op(= `d168_p2.3_array_rc.options.md §3(a)`「新旧布局 no-op 掩盖」),故现状是泄漏而非崩,bug 潜伏 |

### (b) 最危险假设

「Map value retain/release 切真实(非 no-op)后,`isOwnedExpr` 在 Map set 处 owned/borrowed 判定正确 → 全测 0 regression」。依据:§C.9-exec §2026-05-19 P2.3b 实测「`emitReleaseVarList` 切真实 release 即全测 303/25 / 322/6 崩」— 真实 RC 一旦失衡(over-retain 泄漏 / under-retain UAF)即暴露,no-op 掩盖期不可见。

### (c) 最小 spike(试切)

**spike 范围**:retain 侧(`genMapMethod("set")` → `emitRetainForType` + `isOwnedExpr`/`pushNonOwning` 门)+ 新增 `ss_release_any` 并**仅** wire `ss_rc_destroy_map`(`ss_mapSet`-update / `ss_mapDelete` 暂留 `ss_rc_release`)→ `./build.sh bootstrap` 三阶段 + `bin/ss test tests/`。spike 态是合法中间态:delete/overwrite 路径暂泄漏(不崩),destroy 路径与 set retain 对称 — 触发「真实 retain + 真实 release」完整 RC 循环,即最危险假设。0 regression(对齐 323/5 baseline)→ 假设成立 → 全量 Execute(补 `ss_mapSet`-update + `ss_mapDelete` 两处 swap);崩 → 回方案层修正,禁全量。

**spike 结果**:spike(retain `emitRetainForType` + `ss_release_any` 仅 wire `ss_rc_destroy_map`)→ bootstrap 三阶段 PASS + 全测 324/4(对齐 baseline 323/5,差值是 I025 族非确定 generic flap)→ 最危险假设「retain + Map-death release 0 regression」**成立**。

**全量 Execute 实证(spike 后)**:全量(+ `ss_mapSet`-update + `ss_mapDelete` 真实 release)→ 全测 318/10、`d095_*`(I024)standalone 编译器 SIGSEGV → **第 2 个假设破裂**:`map.get`(string)走 `ss_mapGetString` 不 retain → map value 是无 RC 保护的 borrowed 引用;update/delete 真实 release 在 scope 中段 free 旧值 → borrow-then-mutate(`nGetS1` 借出 → `nStr1.set` 覆写)悬空 UAF。回方案层 → **候选 B 收窄 = Map value retain(`ss_retain_any`,与 `ss_release_any` 对称 magic 分派)+ Map-death release**;`ss_mapSet`-update/`ss_mapDelete` 真实 release 移 §C.11(hard-depends on get 侧 retain)。bootstrap 三阶段 fixed-point + 全测稳定集 = baseline。详见 D168 §C.10-map。
