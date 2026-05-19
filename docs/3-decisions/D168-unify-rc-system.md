# D168: 统一双 RC 系统为 Perceus 主线

**Status:** Phase 1 String closed 2026-05-10;Phase 2 closed;**Phase 3 进行中** —— Map value RC(§C.10-map)+ §C.11 `emitReleaseVarList` 收口(2026-05-19:codegen-local RC 全栈 magic 分派 `ss_*_any` + `isRcManaged` 门;`ss_mapSet`-update/`ss_mapDelete` 真实 release)closed;Map header→ObjHeader 子设计见 §D(P3.1-P3.3,2026-05-19 drafted)。d095(`docs/4-issues/I024`)/I025「半迁移不平衡」根因经 §C.11 消除
**Depends on:** axiom C2/C4/V4(`docs/1-axioms.md:8,10,19`);相关 D164(PIR liveness 落地证据)
**Date:** 2026-05-10
**Last Updated:** 2026-05-19

---

## 核心目标 (Goal)

- **为什么**:当前编译器并存双 RC 系统 — 旧 `ss_rc_retain/release`(string/Array/Map,libc malloc + tag-字段析构)与新 `ss_retain/release`(class 实例,mimalloc + TypeInfo.drop_fn vtable);emitRetainForType / emitReleaseForType 在 `bootstrap/gen/class/class.ss:140-155` 通过 isUserClass 二元分派,**容器类型未享受 Perceus PIR liveness 自动 release + REUSE 优化**,与 axiom C4 "Deterministic memory management only (Perceus RC)" 部分背离;新增容器类型(Set/Queue/Channel)必须二选一入轨,带累积复杂度 carrying liability。
- **是什么**:把 string / Array<T> / Map<K,V> 切到统一 `[rc:i32 \| TypeInfo*]` ObjHeader + mimalloc 分配 + per-type `ss_drop_X / ss_deep_clone_X / ss_shallow_clone_X` 函数 + 接入 PIR liveness pass,删除 `ss_rc_*` legacy 系统;`emitRetainForType` 退化为单一 `call @ss_retain`。
- **单一判据**:Phase 5 完成后(a) `grep -rn "ss_rc_retain\|ss_rc_release" bootstrap/ lib/` 命中 = 0(b) `bootstrap/gen/class/class.ss` emitRetainForType 单分支(无 isUserClass)(c) PIR liveness pass 覆盖 String/Array/Map 变量(d) bootstrap 三阶段 bit-identical(e) 全测继承基线 0 regression。

> 双 RC 是 SS 编译器最大 carrying architectural debt;统一是必做项,**只剩"何时 + 何步"**。

---

## 核心原则 (Principles)

1. **Perceus 主线根因解决** — 选 L4(PIR 集成统一)非 L1/L2/L3,避免名义改名 / dispatch 隐藏 / ABI 改但 PIR 缺口的次优解;axiom C4 不可议。
2. **业界对标演化** — Lean 4 Perceus、Koka、Swift ARC、Rust `Rc<T>` 全单 RC 路径,双 RC 是 SS 初始 debt 不是合理设计;N 年返工度判据下双系统后续优化全做两遍。
3. **分阶段是为自举可验证,不是为节省工程量** — Phase 1-5 每阶段独立通过 stage2==stage3 bit-identical + 全测,失败仅丢一域工作量;禁大爆炸合并步骤。
4. **ABI 决策一次锁定全编译器适配** — 字面量 immortal 方案 / Array<T> TypeInfo 参数化策略 / RC 字段宽度选择 选错则全栈 GEP 偏移要再改;§未决策段必须用户 close 才进 Phase 1。
5. **设计阶段不把既有代码当架构权威** — 旧 RC tag 分派 / `+16 user ptr` 偏移 / immortal `rc<0` 不是不变量,是 legacy 实现细节,新设计从 Perceus 原理出发(`feedback_design_no_code_authority`)。
6. **lib/java/sql.ll 等 IR artifact 跟随重生** — 顶部 `; ModuleID = 'simplescript'` 表明是 stage 编译产物,不需手工改;关注 `lib/*.ss` 源 + `bootstrap/`。
7. **PIR 接入是终局价值兑现点** — Phase 5 把 30+ 处 codegen 路径手工 emit retain/release 消除,这是统一的最大长期收益;前 4 阶段都是为它铺路。

---

## §A.1 候选方案对比 — "统一"语义层级

| 层 | 含义 | 解决根因? | 取舍 |
|---|---|---|---|
| **L1 名义统一** | `ss_rc_retain` 改名 `ss_retain`,内部仍双轨 | ❌ workaround | 否决 — 零根因 |
| **L2 dispatch 统一** | 上层只见一个 emitRetainForType,内部隐藏分派 | ❌ 现状已是 L2 | **否决 — 现状已是,未解决任何痛点** |
| **L3 ABI 统一** | string/Array/Map 切到 `[rc:i32 \| TypeInfo*]` 头 + mimalloc + vtable 析构 | ✅ 消除分配器/头/tag 三大碎片 | 留 PIR 缺口,需再做一次 |
| **L4 PIR 集成统一** | string/Array/Map 也参与 PIR liveness,享受自动 release + REUSE | ✅✅ 终局 | **选定** — 符合 axiom C4 + 业界对标 + N 年返工度最低 |

**决策:选 L4**,Phase 1-4 实施 L3 ABI 切换为 L5 铺路,Phase 5 兑现 PIR 集成终局价值。

理由(按 CLAUDE.md "Root Cause 优先 第一法则,无例外" + "禁按工程量最小排序" + "长久/演化必入"):
- L1/L2 是名义 workaround,与 axiom C4 部分背离不消除
- L3 留 PIR 缺口 = 后续 escape analysis / specialization / GC 实验 / REUSE 全覆盖都要在容器侧再做一遍,N 年返工度极高
- L4 一次到位,业界对标 Lean 4 / Koka 演化路径

---

## §A.2 隐藏假设挑战

| # | 假设 | 状态 | 实证 / 证据 |
|---|---|---|---|
| H1 | 字面量 immortal 路径可直接复用旧机制 | **破裂** | 旧 `ss_rc_retain/release` 通过 `rc<0` (i64 slt) 跳过(`gen_runtime.ss:289,314,379`),新 `ss_retain/release` **无 immortal 检查**(`gen_runtime.ss:511-548`)→ Phase 1 必答 |
| H2 | 用户指针位置是不变量 | **破裂** | 旧系统 user ptr = malloc'd raw + 16(`[rc:i64 \| tag:i32 \| pad:i32]` 后),新系统 user ptr = struct base + 0(GEP 直接到字段)→ ABI 切换全栈 GEP 偏移修正 |
| H3 | Array / Map TypeInfo 是单例 | **破裂** | class 实例每类型一个 `@ClassName_type_info`,但 `Array<int>` / `Array<string>` / `Array<Dog>` 各自需独立 TypeInfo(deep_clone_fn 知道元素类型);Phase 2 monomorphization |
| H4 | lib/java/sql.ll 是手写 IR 需手工改 | **不破裂** | 文件顶部 `; ModuleID = 'simplescript'` 是 stage 编译输出 artifact,跟随编译器重生 — 不阻塞 |
| H5 | 旧 RC 系统已在用户层暴露 | **不破裂** | grep `lib/` 下源代码 0 行 `ss_rc_*` 调用(全由 codegen 自动 emit)→ 用户层透明,统一不破坏用户代码 |
| H6 | PIR 算法本身可泛化到容器 | **未实证** | pir_lower / pir_opt 当前 isOwnedRefType 判据未审,Phase 5 入口实测;失败 fallback 仅 L3 |
| H7 | bootstrap 三阶段固定点不破 | **延迟实证** | Phase 1 入口实测,本 Phase 0 仅起 SSoT 不触发 |
| H8 | RC 字段宽度 i32 足够 | **延迟决策** | i32 上限 ≈ 21 亿;字符串字面量 immortal `0xFFFFFFFF` = -1 占用大值,溢出风险评估留 §未决策 |

---

## §未决策 — 已 close

**Status:** [x] All closed at 2026-05-10(本对话 ultrathink 业界对标 + 用户 "全部接受推荐" 表态)

| 决策项 | 选项 | 影响面 | 最终锁定(见 §A.3) |
|---|---|---|---|
| **D1 字面量 immortal 方案** | A:boxed 字面量 `@.str.N = { i64 -1, ptr @String_type_info, [N x i8] }` 与 ObjHeader ABI 一致,字面量 +16 字节(D3=ii i64 后)<br>B:`ss_retain/release` 增加 sentinel 跳过路径,字面量保持裸 `[N x i8]` 但需"指针不携头"特殊语义 | A:全栈 string GEP 偏移调整;B:string 字面量与运行时 string 双布局,运行时检测 RC 时分支 | **A** ✅ |
| **D2 Array<T> / Map<K,V> TypeInfo 参数化** | a:每实例化生成 monomorphic TypeInfo `@Array_int_type_info`(Rust Vec<T> 风格)<br>b:运行时 element_drop_fn 字段(Java generic erasure)<br>c:混合(Lean 4 路径)— Array TypeInfo 分 scalar/ref 两份,ref 元素 release 走元素自身 ObjHeader vtable | a 嵌套泛型 IR 体积 O(N!) 最坏;b 函数指针间接调用 5-15% 慢;c 复用现有 ObjHeader vtable 机制零新概念 | **c** ✅(ultrathink 修订:从 a 改 c,根因度更高,Lean 3→4 退路证据 + 嵌套泛型 O(1) + Perceus 论文作者 Leijen 实战选 c) |
| **D3 RC 字段宽度** | i:保持 i32 与 ObjHeader 一致<br>ii:升级 i64 + 留多余 bit 打包未来状态(weak/unowned/finalize) | i:`{i32+padding, ptr}` = 16 字节;ii:`{i64, ptr}` = 16 字节(实际占用相同,padding 4 字节升级为有意义 RC 高位) | **ii** ✅(ultrathink 修订:从 i 改 ii,零空间代价 + Swift/CPython 路径 + future-proof) |

> 三项已 close,§A.3 锁定决策段是 SSoT。**下下轮启动 Phase 1 String 切轨 spike**(本轮收尾,下一轮 Phase 1 子设计 §B 附录 + 用户授权 spike 启动)。

---

## §A.3 锁定决策

**Closed at:** 2026-05-10(本对话 ultrathink 业界对标问询轮 + 用户 "全部接受推荐" 表态)

| 项 | 锁定 | 业界锚点 | 根因证据 / 修订记录 |
|---|---|---|---|
| **D1 字面量 immortal** | **A — boxed 字面量 `@.str.N = { i64 -1, ptr @String_type_info, [N x i8] }`** | Lean 4 `lean_object` `m_rc<0` persistent + CPython 3.12+ `_Py_IMMORTAL_REFCNT`(PEP 683)+ Swift `InlineRefCounts` immortal bit | 与原推荐一致;业界三大工业 RC 系统(Lean 4 / CPython / Swift)一致选 boxed + sentinel 路径;字面量 +16 字节(含 D3=ii i64)是 ABI 统一对价 |
| **D2 TypeInfo 参数化** | **c — 混合(Lean 4 路径):Array TypeInfo 分 `@Array_scalar_type_info` / `@Array_ref_type_info` 两份,ref 元素 release 走元素自身 ObjHeader.TypeInfo.drop_fn vtable** | Lean 4 `lean_array_object` 单一 + element vtable 分派 / .NET CLR reference shared / Swift Array<T> default path | **从 a (mono) 修订为 c (mixed)**,根因证据:(1) c 复用 SS 现有 ObjHeader vtable 分派机制(`gen_runtime.ss:545-547`)零新概念;(2) Lean 3→4 退路证据 — a 嵌套泛型 IR 体积 O(N!) 实战不可承受;(3) 嵌套 Array<Map<K, Array<T>>> 场景 c 自然 O(1);(4) Perceus 论文作者 Leijen 本人在 Lean 4 实战选 c;(5) c → a selective monomorphization 单向可升级,a → c 不可退化 |
| **D3 RC 字段宽度** | **ii — i64** | Swift `InlineRefCounts` 64-bit / CPython `Py_ssize_t` / Rust `Rc<T> usize` 64-bit | **从 i (i32) 修订为 ii (i64)**,根因证据:(1) ObjHeader `{i64 rc, ptr TypeInfo}` = 16 字节,与 `{i32 rc + 4-byte padding, ptr TypeInfo}` 实际占用相同(零空间代价);(2) padding 4 字节升级为有意义 RC 高位 = future-proof,留多余 bit 为未来 weak/unowned/finalize 状态打包(Swift 路径);(3) immortal sentinel 升级 i64 -1,RC 范围 2^63 绝对不溢出 |

### 衍生一致性约束(Phase 1+ 必遵)

- **ObjHeader 唯一形态**:`%ObjHeader = type { i64, ptr }`(D3 i64 升级)
- **String 实例 layout**:`{ i64 rc, ptr @String_type_info, ptr buffer, i64 len, i64 cap }`(待 §B Phase 1 子设计精化字段顺序 + 是否 inline buffer)
- **String 字面量 layout**:`@.str.N = { i64 -1, ptr @String_type_info, [N x i8] }`(D1=A boxed)
- **Array TypeInfo 分类**:`@Array_scalar_type_info`(int/double/bool/所有 scalar 共享,drop 时不释放元素)+ `@Array_ref_type_info`(string/class/嵌套泛型共享,drop 时元素 ss_release 走元素 vtable)
- **immortal 检查路径**:`ss_retain` / `ss_release` 入口加 `icmp slt i64 %rc, 0` 跳过(与 D1 boxed 字面量配合);旧 ss_rc_retain/release 的 `rc<0` 检查作为参考实现迁移
- **emitRetainForType / emitReleaseForType**:Phase 1 String 切轨后,string 走 `ss_retain` 路径而非 `ss_rc_retain`;dispatch 入口暂保留双分支兜底,Phase 4 删除旧路径

---

## §Phase 收关锚

| Phase | 内容 | 状态 | 验证 |
|---|---|---|---|
| **Phase 0** | D 文档建立 + §未决策 ABI 三项列出 + PSM 通过 | [x] 本轮 | `ls docs/3-decisions/D168-unify-rc-system.md` GREEN |
| **Phase 0.5** | 用户 close §未决策 D1/D2/D3 → §A.3 锁定(D1=A / D2=c / D3=ii) | [x] 2026-05-10 | 本对话 ultrathink 业界对标轮 + 用户 "全部接受推荐" |
| **Phase 1** | **String 切轨** — `[rc:i64 \| TypeInfo*]` ObjHeader + mimalloc + `@String_type_info` + 字面量 boxed immortal(D1=A) + 全栈 string GEP 偏移修正(§B 9 节子设计落地) | [x] 2026-05-10 | P1.1 `cd72998` + P1.2 `9edf09b` + P1.3 `0583e6a`;bootstrap stage2==stage3 PASS;全测 310/17/327 0 regression;P1.4 (b)(c) 路径全测隐式覆盖,性能 bench 推 Phase 5 |
| **Phase 2** | **Array 切轨** — `Array<T>` 双份 TypeInfo(D2=c scalar/ref)+ 元素 retain/release 走元素 vtable + Array slice/concat 适配(§C 10 节子设计 + P2.1-P2.4 子分阶段) | [ ] Planned | bootstrap + Array 测试 |
| **Phase 3** | **Map 切轨** — value retain + Map-death release(§C.10-map)+ §C.11 `emitReleaseVarList` 收口(codegen-local RC magic 分派 + update/delete 真实 release)落地 2026-05-19;Map header→ObjHeader 子设计 §D(P3.1-P3.3) | [~] value-RC 半 done(§C.10-map+§C.11);header 迁移半 §D drafted,P3.1-P3.3 Planned | bootstrap 三阶段 bit-identical ✓ + 全测 324/4 = baseline 0 regression |
| **Phase 4** | **删除旧系统** — 移除 `ss_rc_retain/release/release_no_children/destroy_array_ptrs/destroy_map`,`emitRetainForType` 退化为单一 `call @ss_retain` | [ ] Planned | bootstrap + grep `ss_rc_*` 命中 = 0 |
| **Phase 5** | **PIR 全覆盖** — pir_lower/pir_opt 把 string/Array/Map 纳入 liveness,删除 codegen 路径手工 emit retain/release(消除 30+ 调用点) | [ ] Planned | bootstrap + 性能 micro-bench(可选) |

---

## §第一性需求(axiom 引用)

| Axiom | 内容 | 当前状态 | 本 D 触达 |
|---|---|---|---|
| **C2** `docs/1-axioms.md:8` | No handwritten runtime, mimalloc allowed | ✅ 已达成 | Phase 1-4 把 string/Array/Map 也接入 mimalloc,C2 全覆盖 |
| **C4** `docs/1-axioms.md:10` | No GC. Deterministic memory management only (Perceus RC) | **部分达成**:class 实例已 Perceus,容器未享受 PIR liveness | **本 D 第一性需求** — Phase 5 完成 C4 全覆盖 |
| **V4** `docs/1-axioms.md:19` | Core logic in SS | ✅ 已达成 | 不变(本 D 仅改 codegen 端 IR 生成,纯 SS) |

---

## 附录 B:Phase 1 String 切轨子设计

**Status:** Drafted at 2026-05-10(§A.3 锁定后 spike 启动前最后子决策锁定层)
**Scope:** B1-B9 子决策 + P1.1-P1.4 内部子分阶段;Phase 1 spike Execute 启动前必读

---

### §B.1 String 实例 layout — 锁定选项 1 间接 buffer

| 选项 | layout | 业界 | Phase 1 评估 |
|---|---|---|---|
| **1 间接 buffer** | `{ i64 rc, ptr TypeInfo, ptr buffer, i64 len, i64 cap }` + buffer 单独 mi_calloc | Rust `String { vec: Vec<u8> }` / Lean 4 `lean_string_object` | ✅ **选定** — 与现有 string 间接 buffer 模式连续,改动最小;immutable 语义无扩容路径 |
| 2 inline FAM | `{ i64 rc, ptr TypeInfo, i64 len, i64 cap, [N x i8] }` flexible array | CPython `PyUnicodeObject`(immutable inline body) | ⚠ 字面量更紧凑但运行时 String 大小动态,LLVM `[0 x i8]` FAM 处理 + GEP 计算 dynamic offset 复杂 |
| 3 SSO | short ≤ 15 inline + long heap | Swift String / libc++ `std::string` | ❌ 留 §F 远期 — codegen 复杂度过高,违反 Phase 1 KISS |

**锁定 B1 = 选项 1**:
- **字面量** `@.str.N = { i64 -1, ptr @String_type_info, ptr @.bytes.N, i64 len, i64 len }` + `@.bytes.N = constant [N x i8] c"hello\00"`(双 LLVM 全局常量)
- **运行时 String**:header 5 字段单次 `mi_calloc(40, 1)` + buffer 单次 `mi_calloc(cap, 1)`
- **字段顺序**:rc(i64) at offset 0、TypeInfo(ptr) at offset 1、buffer(ptr) at offset 2、len(i64) at offset 3、cap(i64) at offset 4(ObjHeader 原型 [0,1] + 业务 [2,3,4])
- **Immutable 语义**:SS 现有字符串不可变,"修改"返回新 String,**无扩容路径**(简化 RC 系统对扩容 dangling ref 的担忧)

### §B.2 字面量 IR 升级路径

**改动入口**:gen_emit.ss / gen_decls.ss 字面量发射函数(spike 前 grep `@.str` 锁定具体函数,粗预估改动 +20 ~ +40 行)。

**升级前**:
```llvm
@.str.0 = constant [6 x i8] c"hello\00"
```

**升级后**:
```llvm
@.bytes.0 = constant [6 x i8] c"hello\00"
@.str.0 = constant %String { i64 -1, ptr @String_type_info, ptr @.bytes.0, i64 5, i64 5 }
```

用户代码 reference 全局符号从 `@.bytes.N` → `@.str.N`(切换发射点 + reference site)。

### §B.3 Immortal 跳过实现

`bootstrap/gen/gen_runtime.ss::ss_retain` (line 511-523) / `::ss_release` (line 527-548) 加 immortal 跳过路径,对照旧 `ss_rc_retain` line 289 实现迁移:

```llvm
define void @ss_retain(ptr %p) {
  ; null check ...
  %rc = load i64, ptr %p
  %immortal = icmp slt i64 %rc, 0    ; D3=ii i64 sentinel = -1 表 immortal
  br i1 %immortal, label %done, label %inc
inc:
  %rc1 = add i64 %rc, 1
  store i64 %rc1, ptr %p
done:
  ret void
}
```

ss_release 同模式 + rc=0 触发 TypeInfo.drop_fn(已有逻辑保留)。

### §B.4 mimalloc 字符串分配切换 — 锁定双轨过渡

| 选项 | 路径 | Phase 1 评估 |
|---|---|---|
| **双轨过渡** | 新增 `ss_alloc_string(i64 size)` 走 mimalloc(对照 `gen_runtime.ss::ss_alloc` line 555-559);旧 `ss_rc_alloc` 保留供 Array/Map | ✅ **选定** — RC ABI 已是 hard break,分配器再切叠加双 hard break 难定位;双轨可逐步定位 bootstrap 失败 root cause |
| 一次切完 | Phase 1 `ss_rc_alloc` 在 string context 全替换为 mi_calloc | ⚠ Lean 4 实战可行(单分配器),但 SS 工程现实 KISS 选双轨 |

**实施**:
- 新增 `gen_runtime.ss::ss_alloc_string(i64 size) → ptr` 走 `mi_calloc(1, size)`
- gen_rt_string.ss 内 string 创建路径切到 ss_alloc_string
- Phase 4 删除旧 `ss_rc_alloc`(string 路径)统一全 mimalloc

### §B.5 String per-type 函数生成

对照 `bootstrap/gen/gen_type_ops.ss::emitClassTypeInfo` (line 210-233),新增 `emitStringTypeInfo()`:

```ss
function emitStringTypeInfo() {
    emitIR("@String_type_info = constant %TypeInfo { ptr @ss_drop_String, ptr @ss_deep_clone_String, ptr @ss_shallow_clone_String, i64 40, ptr @.string_typename, i32 -1, ptr null }")
    emitDropString()
    emitDeepCloneString()
    emitShallowCloneString()
}
```

- **`@ss_drop_String(ptr %p)`**:`mi_free(buffer)` + `ss_dealloc(p)`
- **`@ss_deep_clone_String(ptr %p)`**:mi_calloc 新 header + 新 buffer + memcpy bytes + 设置新 rc=1
- **`@ss_shallow_clone_String(ptr %p)`**:**immutable string 等价 ss_retain**(buffer 共享,实际就是 retain self 后返回)— 利用 String immutable 语义零拷贝

`size = 40`:5 字段 × 8 字节(i64+ptr+ptr+i64+i64)
`class_id = -1`:表非用户 class,reflection 区分

### §B.6 emitRetainForType / emitReleaseForType 路由

`bootstrap/gen/class/class.ss::emitRetainForType` (line 140-145) 升级,string 走 ss_retain:

```ss
function emitRetainForType(reg: string, ssType: string) {
    if (isUserClass(ssType) == 1 || ssType == "string") {
        emitIR(`  call void @ss_retain(ptr ${reg})`)
    } else {
        emitIR(`  call void @ss_rc_retain(ptr ${reg})`)
    }
}
```

emitReleaseForType 对称(line 149-155)。Phase 4 全部容器切完后,dispatch 退化为单一 `call @ss_retain`。

### §B.7 全栈 string GEP 偏移修正清单

**ABI 变更核心**:
- 旧 user ptr = `malloc'd raw + 16`(`[rc:i64 \| tag:i32 \| pad:i32]` 后),user ptr 直接是 bytes 起点
- 新 user ptr = struct base + 0,bytes 通过 `GEP %String %p, i32 0, i32 2; load buffer; ...` 间接访问

**改动范围**:`bootstrap/gen/rt/gen_rt_string.ss` 内所有 string bytes 访问点(spike 前 grep `gep.*str\|getelementptr.*str` 锁定);string concat / slice / equality / format / charAt / substring 等。

**性能损失评估**:每次 string 操作多一次 indirect load(buffer ptr 加载),非 hot loop 关键路径(string 操作典型频率 << class 实例操作);PIR Phase 5 接入后 LLVM 可 speculation 优化部分。

### §B.8 RED 命令(最小 spike 路径)— 锁定 (a)

| 候选 | RED 程序 | 触发路径 | Phase 1.X 归属 |
|---|---|---|---|
| **(a) 字面量 + 函数参数** | `let s = "hello"; println(s)` | 字面量 IR 升级(B2)+ ss_retain immortal 跳过(B3)+ println 调用 | **P1.1 + P1.2 起首** |
| (b) retain 路径 | `let s = "hello"; let s2 = s; println(s2)` | 上 + ss_retain inc 路径(实际 immortal 仍跳过) | P1.4 |
| (c) 跨函数返回 | `function foo(): string { return "hello" }` | 上 + 跨函数调用约定 + 返回值 retain | P1.4 |

**RED 命令**(spike 前实测):
```bash
cat > /tmp/d168_p1_spike.ss <<'EOF'
function main() {
    let s = "hello"
    println(s)
}
EOF
bin/ss build /tmp/d168_p1_spike.ss --emit-ir 2>&1 | grep -E '@\.str\.0|@String_type_info|ss_retain'
```

**spike 前预期**:仅 `@.str.0 = constant [6 x i8] c"hello\00"` 命中,无 `@String_type_info` 命中
**spike 后预期**:`@.str.0 = constant %String { i64 -1, ptr @String_type_info, ... }` + `@String_type_info` 全局定义命中

### §B.9 Bootstrap hard break 策略 — 标准三阶段,不冻结 seed

memory `project_perceus_design.md` "Plan A: freeze seed compiler" **不复用**,根因:
- RC ABI 改动是 codegen 内部细节,**seed 编译器(bin/ss)不受影响**(seed 自身用旧 ABI 运行 OK)
- stage1 = seed 编译 bootstrap/*(stage1 内部仍旧 ABI,但 stage1 输出新 ABI)
- stage2 = stage1 编译 bootstrap/*(stage2 内部新 ABI)
- stage3 = stage2 编译 bootstrap/*
- 验证 stage2 == stage3 bit-identical

**风险点**:stage2 启动若 string runtime 函数链有 bug → segfault;失败 `git reset --soft HEAD^` + 修。Bootstrap 单次约 55s,迭代成本可承受。

**与 D164 PIR liveness 落地同模式**:D164 commit `26d656c` 三阶段 PASS,String 切轨同样走标准三阶段,无需 Plan A。

---

### §B Phase 1 内部子分阶段(每子步独立 commit + bootstrap 验证)

| 子阶段 | 范围(实施时 ultrathink 修正) | 触达 | Status / Commit |
|---|---|---|---|
| **P1.1** | ObjHeader RC i32→i64 全栈升级 + B3 immortal 跳过路径(`icmp slt i64 %rc, 0`) | gen_runtime.ss / class_register.ss / gen_type_ops.ss / gen_arrows.ss | [x] commit `cd72998` 2026-05-10(bootstrap PASS + 全测 0 regression) |
| **P1.2** | B5 emitStringTypeInfo dead-code 元数据(`%String` 类型 + `@String_type_info` + ss_drop_String / ss_deep_clone_String / ss_shallow_clone_String;P1.3 才连接到字面量 + dispatch) | gen_runtime.ss(emitStringTypeInfo 函数 + 内嵌 75 行 IR) | [x] 本 commit 2026-05-10(bootstrap PASS + 全测 0 regression + IR 命中;§扩容申报-P1.2 bump M3b/F1) |
| **P1.3** | **大改合并**:B2 字面量 IR 升级 boxed + B6 dispatch string 路由 + B7 全栈 string runtime GEP 偏移修正 + B4 mimalloc 字符串分配切换。**实测扩散到容器层(array/map/shell)+ 表达式层(calls/methods/exprs_str_conv)+ codegen.ss IR 拼装顺序**(实测偏差 +120% 已 §扩容申报失准记录) | gen_emit.ss / gen_runtime.ss / gen_rt_string.ss / gen_rt_io.ss / gen_rt_system.ss / gen_rt_array.ss / gen_rt_map.ss / gen_rt_shell.ss / class.ss / codegen.ss / gen_calls.ss / gen_methods.ss / exprs_str_conv.ss | [x] 本 commit 2026-05-10(bootstrap PASS + 全测 310/17/327 0 regression + reflection bump 6 metrics)|
| **P1.4** | 综合大测 + 性能 micro-bench(可选)+ 残尾收尾(retain 路径 B8 b、跨函数返回值 B8 c) | 全测 + 性能脚本 | [ ] Planned |

**P1.X 范围调整记录**:原划分(B5+B3+B6 / B2+B7 / B4 / 大测)在 P1.2 实施时 ultrathink 发现"字面量 boxed 与 string runtime GEP 适配不可分",修正为:P1.1=ObjHeader+B3、P1.2=B5 dead-code、P1.3=B2+B6+B7+B4 合并大改、P1.4=综合大测。原划分按子决策 ortho 切分,修正后按"独立可 commit + bootstrap 验证"切分,更符合 §B.9 三阶段验证原则。

**子阶段间硬约束**:
- 任一子阶段 bootstrap 失败 → `git reset --soft HEAD^` + 修,**不允许带失败 commit**
- 子阶段独立 commit,**禁打包**(便于回滚定位)
- P1.1 必须 P1.2 前完成(类型基础设施先于字面量切换)
- P1.4 必须 P1.1-P1.3 全 GREEN 后启动

---

## §扩容申报-P1.2-emitStringTypeInfo

| metric | bm_old | bm_new | delta | 业务理由 |
|---|---|---|---|---|
| M3b | 2010 | 2050 | +40 | emitStringTypeInfo() emit ~75 行 IR(`%String` 类型 + `@String_type_info` + 三 per-type 函数定义 + 类型名常量),反射可见 IR 行数 cur 2042;buffer +8 行预留 P1.3 字面量切轨追加。§B.5 落地证据。 |
| F1:bootstrap/gen/gen_runtime.ss | 623 | 700 | +77 | 同上,emitStringTypeInfo() 函数定义 + 内嵌 IR 字符串 75 行,文件 cur 693;buffer +7 行预留。§B.5 落地证据。 |

**根因解决度**:P1.2 是 D168 §B.5 子决策落地(emit String 类型元数据 dead-code 占位 SSoT),P1.3 才连接到字面量发射 + dispatch 路由。本扩容是 §B.5 直接副作用,非冗余实现 — 与 `emitClassTypeInfo` (`gen_type_ops.ss:210-233`) 同模式,IR emit 量是不可压缩的元数据底座。

**对账(预估 vs 实测)**:预估 ~75 行(emit IR 字符串数固定),实测 +80 行(F1 delta 含函数定义 + 调用点注释)。预估偏差 < 7%(±5 行),无需写入 §扩容申报失准段。

---

## §扩容申报-P1.3-string-abi-切轨

| metric | bm_old | bm_new | delta | 业务理由 |
|---|---|---|---|---|
| M2 | 83300 | 84600 | +1300 | string runtime 全切轨:gen_rt_string.ss 17 函数 + gen_rt_io.ss 6 函数 + gen_rt_system.ss 多函数 + 扩散修(map/array/shell/calls/methods/exprs_str_conv)新增 GEP buffer + load 模式;AST 节点 cur 84566 |
| M3a | 13050 | 13400 | +350 | 同上,call 边数 cur 13366 |
| M3b | 2050 | 2250 | +200 | 同上,最大入度 cur 2213 |
| N2 | 416000 | 423000 | +7000 | 同上,Halstead vol cur 422830 |
| N3 | 575500 | 584000 | +8500 | 同上,AST 深度和 cur 583462 |
| F1:bootstrap/gen/gen_runtime.ss | 700 | 730 | +30 | P1.3 helpers ss_alloc_string + ss_string_from_cstr 追加 ~35 行(P1.2 693 → P1.3 728) |

**根因解决度**:§B.2/§B.4/§B.6/§B.7 合并大改的直接副作用 — 字面量 boxed + dispatch 路由 + 全栈 string runtime GEP 适配 + mimalloc 切换不可分。改动模式机械化(GEP buffer + load + 给 C 函数),非冗余实现。扩散修复(map/array/shell/calls/methods/exprs_str_conv/codegen 拼装顺序)是 ABI 切轨的根因连锁。

**对账(预估 vs 实测)**:预估 ~120 行,实测 +520/-256 = 净 +264 行。**预估偏差 ~120%(超出 2 倍)— 写入 §扩容申报失准段**。根因:原预估只覆盖 io+system 主任务,**未含容器层(map/array/shell)+ 表达式层(calls/methods/exprs_str_conv)+ codegen IR 拼装顺序连锁修**。下次 string ABI 类大改前置必含"容器层 + 表达式层 + 测试输出路径"全栈连锁评估,不仅看主调用路径。

---

## §扩容申报-P2.1-emitArrayTypeInfo

| metric | bm_old | bm_new | delta | 业务理由 |
|---|---|---|---|---|
| M3a | 13400 | 13700 | +300 | emitArrayTypeInfo() 函数体内 SS 端 emit 节点(双份 TypeInfo + 6 per-type 函数 IR + ss_alloc_array helper)增加反射路径 call 边数;cur 13559 |
| M3b | 2250 | 2470 | +220 | 同上,反射可见 IR 行数 cur 2405;ref deep_clone/shallow_clone 是循环 + phi block 实现,每函数 ~25 行 IR string emit,合计远大于 P1.2 String 三函数(string immutable 实现极简) |
| F1:bootstrap/gen/gen_runtime.ss | 730 | 985 | +255 | emitArrayTypeInfo() 函数定义 + 内嵌 IR 字符串 ~228 行(双份 TypeInfo + 6 per-type 函数 + 2 typename 常量 + ss_alloc_array helper);文件 728 → 958;buffer +27 行预留 |

**根因解决度**:P2.1 是 D168 §C.3/§C.4 子决策落地(emit Array 类型双份元数据 + ss_alloc_array helper dead-code 占位 SSoT),P2.2 才连接到字面量发射 + GEP +3 + dispatch 路由。本扩容是 §C.3/§C.4 直接副作用,非冗余实现 — 与 emitStringTypeInfo / emitClassTypeInfo 同模式;ref Array 双份 TypeInfo 比 String 单份 TypeInfo 多 1 倍函数(scalar/ref 各 3 函数 = 6),且 ref 函数循环 + phi block 实现 IR 体积放大,emit 量是不可压缩的元数据底座。

**对账(预估 vs 实测)**:预估 +150 行(F1)/ +100 行(M3b),实测 +228 行(F1) / +155 行(M3b)。**F1 预估偏差 +52%、M3b 预估偏差 +55%(均 > 20%)— 写入 §扩容申报失准段**。根因:原预估按"6 函数 + helper 共 ~150 行"按 P1.2 String 三函数模式直接外推,**未实测 ref 元素 deep_clone/shallow_clone 是循环 + phi block 而非 String 简单 retain self;每个 ref 循环函数 ~25 行 emit 字符串,且 §C.10 ss_drop_Array_ref 全文 IR 是 phi 节点循环 ~30 行**(对比 String shallow_clone 仅 3 行 IR)。下次 vtable 元数据扩容预估前置:**循环 / phi block 实现的 per-type 函数按 ~25-30 行 IR string emit 估算,而非按 P1.2 String 简单实现外推**;且 M3a 项 P2.1 prompt 漏报(实测 +193 → 必入 bump),next prompt §扩容申报 表必含 M3a / M3b / F1 三项最小集。

---

## §扩容申报-P2.2-scalar-array-切轨

| metric | bm_old | bm_new | delta | 业务理由 |
|---|---|---|---|---|
| (无 bump) | — | — | — | 所有指标实测均 PROGRESS(M2 -72 / M3a -8 / M4 -3 / N2 -360 / N3 -137);仅 M3b +2 / M6 / N1 已是 baseline 状态。F1 gen_runtime.ss 958 → 958(emitArrayTypeInfo 内 `%Array = type` 删除 + mi_realloc declare 加 1 = 净 0)。 |

**根因解决度**:P2.2 是**ABI 切轨改造**(改 emit 模式 + GEP 偏移),非新增 IR — 旧 ss_rc_calloc + 旧 GEP 偏移代码删除 + 新 ss_alloc_array + GEP +3 代码替换 = 净改动量小;`ss_arraySlice/Concat` 旧 tag 分派(GEP -8 + retain 循环)替换为 TypeInfo 分派(GEP 1 + ss_retain 循环)字符等量。

**对账(预估 vs 实测)**:**预估极度悲观**(M2 +1600 实测 -72 / M3a +400 实测 -8 / N2 +9000 实测 -360 / N3 +10000 实测 -137)。**预估偏差 -100% 以上 — 写入 §扩容申报失准段**。根因:本 prompt §扩容申报-P2.2 预估按 P1.3 String ABI 切轨实测 +1300/+264 同等扩散面外推(且加 buffer),未实测 P2.2 与 P1.3 的本质区别 — **P1.3 是"新增 emit + 容器 / 表达式 / codegen 拼装顺序连锁修"(实测 +520/-256 净 +264 行),P2.2 是"emit 模式替换"(行数等量替换)**。下次 ABI 切轨预估必区分:
- **新增 emit 类型**(P1.2 String type-info dead-code 元数据 / P2.1 Array type-info dead-code)→ 按 emit IR 行数线性估算
- **替换 emit 类型**(P1.3 字面量 + dispatch + GEP 全栈 / P2.2 GEP +3 + emit 转发)→ **行数等量替换,反射指标几乎不变,M2/M3a/N2/N3 预估 ±0**

---

## §扩容申报-Phase3-map

| metric | bm_old | bm_new | delta | 业务理由 |
|---|---|---|---|---|
| F1:bootstrap/gen/gen_runtime.ss | 985 | 1000 | +15 | §C.10-map:`ss_retain_any`/`ss_release_any` 通用 RC 分派(`emitAnyRcDispatch` helper + 2 调用)+ `ss_rc_destroy_map` swap;cur 991。已 DRY-factored(原拟 2 内联函数 ~48 行 → helper 24 + 调用 6),emit IR 是 RC 基础设施不可压缩底座,与 P1.2 `emitStringTypeInfo` / P2.1 `emitArrayTypeInfo` 同模式。 |
| F1:bootstrap/gen/gen_calls.ss | 740 | 750 | +10 | **P2.3a(`c95797a`)遗留未申报** —— `genArrayLit` 固定/spread retain 补丁致 cur 746 > 旧 bm 740(`git diff HEAD -- gen_calls.ss` 证本轮 diff 不触此文件);D168 同族 RC 续作一并 regularize budget 登记,非本轮新增代码。 |

**根因解决度**:gen_runtime 扩容是 §C.10-map RC 分派基础设施落地的直接副作用,`emitAnyRcDispatch` DRY-factor 后已压到不可再降;gen_calls 是 P2.3a 历史 budget 登记遗漏的补全(代码本身 P2.3a 已 commit)。本轮 `map_rc.options.md` 未预估反射指标(value RC 改动以行为正确为主目标),无预估对账基线。

---

## 附录 C:Phase 2 Array 切轨子设计

**Status:** Drafted at 2026-05-10(Phase 1 close 后 P2.1 spike 启动前最后子决策锁定层)
**Scope:** C1-C10 子决策 + P2.1-P2.4 内部子分阶段;Phase 2 spike Execute 启动前必读
**前置:** §A.3 D2=c 锁定(Array TypeInfo 分 scalar/ref 两份,ref 元素走元素 ObjHeader vtable);Phase 1 ObjHeader i64 + immortal sentinel 已落地,Array 直接复用

---

### §C.1 Array 字面量决策 — 锁定 B runtime 创建(D2' 子决策)

| 选项 | 含义 | 业界 | Phase 2 评估 |
|---|---|---|---|
| A boxed immortal | `[1,2,3]` 编译为 `@.arr.N = constant %Array { i64 -1, ... }` 直接引用 | 类比 string 字面量 | ❌ 与 Array mutable 默认语义冲突;`arr.push(4)` 触发 mut immortal 内存;COW 机制违反 KISS |
| **B runtime 创建** | `[1,2,3]` 编译为 `ss_alloc_array(N) + ss_arraySet × N` runtime 调用 | Java `newarray + iastore` JVM bytecode | ✅ **选定** — 与 SS mutable 默认语义一致,延续旧实现路径,Phase 2 仅切分配器 |
| C const detect | `const arr = [1,2,3]` 走 boxed,`let arr = [1,2,3]` 走 runtime | Rust `const ARR: [T; N]` `.rodata` | ❌ 留 §F 远期 — SS const 现状不传递字面量 layout,需新机制 |

**锁定 D2' = B**:Array 字面量保持 `ss_alloc_array(N) + ss_arraySet × N` runtime 创建模式,字面量本身不 boxed/immortal,仅 alloc 路径从 `ss_rc_calloc` 切到 mimalloc。**与 D1=A(string boxed)分歧**根因:string immutable 可 boxed,Array mutable 不可。

### §C.2 Array 实例 layout — 锁定选项 1 间接 buffer

| 选项 | layout | 业界 | Phase 2 评估 |
|---|---|---|---|
| **1 间接 buffer** | `{ i64 rc, ptr TypeInfo, ptr buffer, i64 len, i64 cap }` 40B + buffer 单独 mi_calloc | Lean 4 `lean_array_object` / Rust `Vec<T>` / Java `T[]` JNI 视图 | ✅ **选定** — 与 §B.1 String layout 字段顺序对称(rc@0 + TypeInfo@1 + 业务[2,3,4])可机械化迁移 GEP,扩容只 realloc buffer header ptr 不变(外部 RC 引用稳定) |
| 2 inline FAM | `{ i64 rc, ptr TypeInfo, i64 len, i64 cap, [N x i64] }` flexible array | CPython `PyListObject`(部分场景)| ⚠ 扩容必须 realloc 整个对象 + memcpy header,外部 RC 引用全部失效,违反 Perceus 假设 |
| 3 segmented | 多段 chunk linked list(rope-like) | 数据库 vector ext | ❌ 复杂度过高,SS 现状不需要 |

**锁定 C2 = 选项 1**:
- **header 5 字段**:rc(i64)@0、TypeInfo(ptr)@1、buffer(ptr)@2、len(i64)@3、cap(i64)@4
- **运行时 Array**:header `mi_calloc(40, 1)` + buffer `mi_calloc(elem_size × cap, 1)`
- **扩容路径**:仅 `realloc` buffer + 更新 buffer 字段 + 更新 cap 字段,**header ptr 保持不变**(外部 RC 引用稳定,Perceus owned/borrow 不受扰动)
- **空间代价**:旧 24B header + 单独 data → 新 40B header + 单独 buffer = +16B/array,长期收益(Perceus PIR 集成 + 统一 vtable drop)远 > 短期空间代价

### §C.3 Array per-type 函数生成 — 双份 TypeInfo(D2=c 核心)

对照 emitClassTypeInfo / emitStringTypeInfo,新增 `emitArrayTypeInfo()`(双份):

```ss
function emitArrayTypeInfo() {
    // ── scalar 共享:int / double / bool / char / 任意 LLVM scalar ──
    emitIR("@Array_scalar_type_info = constant %TypeInfo { ptr @ss_drop_Array_scalar, ptr @ss_deep_clone_Array_scalar, ptr @ss_shallow_clone_Array_scalar, i64 40, ptr @.array_scalar_typename, i32 -2, ptr null }")
    emitDropArrayScalar()           // mi_free(buffer) + ss_dealloc(p) — 元素 noop(无 RC)
    emitDeepCloneArrayScalar()      // mi_calloc 新 header + 新 buffer + memcpy bytes
    emitShallowCloneArrayScalar()   // = ss_retain self(buffer 共享,scalar Array 等价 immutable view)

    // ── ref 共享:string / class / interface / Generic<...> / Map / Array 嵌套 ──
    emitIR("@Array_ref_type_info = constant %TypeInfo { ptr @ss_drop_Array_ref, ptr @ss_deep_clone_Array_ref, ptr @ss_shallow_clone_Array_ref, i64 40, ptr @.array_ref_typename, i32 -3, ptr null }")
    emitDropArrayRef()              // 循环 i=0..len: ss_release(buffer[i]) 走元素自身 vtable + mi_free(buffer) + ss_dealloc(p)
    emitDeepCloneArrayRef()         // mi_calloc + 循环 deep_clone(buffer[i]) 走元素 vtable
    emitShallowCloneArrayRef()      // mi_calloc + 循环 ss_retain(buffer[i]) 走元素 vtable
}
```

**关键不变量**:`@ss_drop_Array_ref` 内部循环调 `call void @ss_release(ptr %elem)`,而 `ss_release` 入口已有 immortal sentinel 跳过 + TypeInfo.drop_fn 分派(P1.1/P1.2 落地),**ref 元素不论是 string / class / interface / Map / 嵌套 Array 都自动正确递归释放,零特殊化**。这是 D2=c "复用现有 ObjHeader vtable 机制零新概念" 的根因兑现点。

`size = 40`:5 字段 × 8 字节;`class_id = -2`(scalar) / `-3`(ref)对照 String -1、用户 class ≥0,reflection 区分。

### §C.4 mimalloc Array 分配切换 — 锁定双轨过渡

| 选项 | 路径 | Phase 2 评估 |
|---|---|---|
| **双轨过渡** | 新增 `ss_alloc_array(i64 elem_size, i64 cap, ptr type_info) → ptr` 走 mimalloc;旧 `ss_rc_calloc` 保留供 Map(Phase 3 切) | ✅ **选定** — 类比 §B.4 String 切轨,RC ABI 已 hard break,分配器再切叠加双 hard break 难定位;双轨可逐步定位 bootstrap 失败 root cause |
| 一次切完 | Phase 2 `ss_rc_calloc` 在 Array context 全替换为 mi_calloc,Map 暂保留旧路径 | ⚠ 与双轨同语义但合并在 P2.2,失败定位粒度更粗 |

**实施**:
- 新增 `gen_runtime.ss::ss_alloc_array(i64 elem_size, i64 cap, ptr type_info) → ptr`:
  - header `mi_calloc(40, 1)`(rc=1, TypeInfo=type_info, buffer=mi_calloc(elem_size × cap), len=0, cap=cap)
  - 字面量路径 alloc 后 ss_arraySet × N 填入元素
- gen_rt_array.ss 内 Array 创建路径切到 ss_alloc_array(scalar/ref 由 emit 端选 type_info)
- Phase 4 删除 `ss_rc_calloc` 在 Array 路径(Map 切完后)

### §C.5 emitRetainForType / emitReleaseForType 路由 — 加 isArrayType 分支

`bootstrap/gen/class/class.ss::emitRetainForType` 升级:

```ss
function emitRetainForType(reg: string, ssType: string) {
    if (isUserClass(ssType) == 1 || ssType == "string" || isArrayType(ssType) == 1) {
        emitIR(`  call void @ss_retain(ptr ${reg})`)
    } else {
        emitIR(`  call void @ss_rc_retain(ptr ${reg})`)
    }
}
```

`isArrayType(ssType: string) → int`:实现需对应 `ssType.startsWith("Array<") || ssType == "Array"`(裸 Array 旧泛型形)+ Generic Array 形。precise 实现 spike 前 grep `isArrayType\|Array<` 确定 SS 类型字符串归一化路径。

emitReleaseForType 对称(同条件,改 `ss_release`)。Phase 4 全容器切完后,dispatch 退化为单一 `call @ss_retain`(无 if 条件链)。

### §C.6 全栈 Array GEP 偏移修正清单

**ABI 变更核心**:
- 旧 user ptr = `ss_rc_calloc'd raw + 16`(`[rc:i64 \| tag:i32 \| pad:i32]` 后),user ptr 直接是 `[len, cap, data]` 起点 → GEP `%arr, 0` = len
- 新 user ptr = struct base + 0,新 layout `[rc, TypeInfo, buffer, len, cap]` → GEP `%arr, 3` = len(偏移 +3)、GEP `%arr, 4` = cap、GEP `%arr, 2` = buffer ptr

**改动范围**:`bootstrap/gen/rt/gen_rt_array.ss` 17 函数 GEP 偏移系统调整:

| 旧 GEP 偏移 | 新 GEP 偏移 | 字段 | 影响函数 |
|---|---|---|---|
| GEP 0 (i64 load) | GEP 3 (i64 load) | len | ss_arrayLen / ss_arrayPush(头长更新)/ ss_arrayPop / ss_arraySlice / ss_arrayConcat |
| GEP 1 (i64 load) | GEP 4 (i64 load) | cap | ss_arrayPush(扩容判断) |
| GEP 2 (i64 ptrtoint load) → bitcast | GEP 2 (ptr load) | buffer | ss_arrayGet / ss_arraySet / ss_arrayPush(realloc 后写回)/ ss_arraySlice / ss_arrayConcat |
| 新增 | GEP 0 | rc | RC 路径(由 ss_retain/release 内部访问) |
| 新增 | GEP 1 | TypeInfo | drop 分派(由 ss_release 内部访问) |

**改动模式**:每个 GEP 加 +3 偏移(len/cap)或 buffer 字段访问统一为 `load ptr` 而非旧 `load i64 + inttoptr`。

**性能损失评估**:每次 array 操作多 1 次 indirect load(buffer ptr),与 String 同模式;非 hot loop 关键路径(array push/pop 频率 << 索引访问)。PIR Phase 5 接入后 LLVM 可 speculation 优化部分 buffer ptr 重复 load。

### §C.7 RED 命令 — 三档 spike 路径

| 候选 | RED 程序 | 触发路径 | P2.X 归属 |
|---|---|---|---|
| **(a) Array<scalar>** | `let arr = [1,2,3]; println(arr[0])` | 字面量 runtime 创建 + scalar TypeInfo + ss_arrayGet GEP +3 | **P2.1 + P2.2 起首** |
| (b) push 扩容 | `let arr = []; arr.push(1); arr.push(2); arr.push(3); arr.push(4); arr.push(5)` 触发 cap 4 → 8 realloc | 上 + 扩容 realloc buffer + cap 更新 GEP 4 | P2.2 |
| (c) Array<string> ref | `let arr = ["hello", "world"]; println(arr[0])` | 上 + ref TypeInfo + 元素 string vtable + 字面量 element retain | **P2.3 起首** |
| (d) Array<class> 元素 release | `let arr = [new Dog()]; arr = []` 触发 ss_drop_Array_ref 循环 → 元素 ss_release 走 Dog vtable | 上 + 嵌套 retain/release | P2.3 |
| (e) Array<Map<K,V>> 嵌套 | `let arr = [new Map(), new Map()]` | 上 + Map 元素未切的 dispatch 兜底(双轨过渡期) | P2.4 |

**RED 命令(spike 前实测)**:
```bash
cat > /tmp/d168_p2_spike.ss <<'EOF'
function main() {
    let arr = [1, 2, 3]
    println(arr[0])
}
EOF
bin/ss build /tmp/d168_p2_spike.ss --emit-ir 2>&1 | grep -E '@Array_scalar_type_info|@.array_scalar_typename|ss_alloc_array'
```

**spike 前预期**:全部命中 = 0(emitArrayTypeInfo dead code)
**P2.1 后预期**:`@Array_scalar_type_info` + `@Array_ref_type_info` + 6 per-type 函数全部命中(dead-code 已发射)
**P2.2 后预期**:用户代码 `[1,2,3]` 字面量编译触发 `ss_alloc_array(8, 3, @Array_scalar_type_info)` 调用命中

### §C.8 Bootstrap hard break 策略 — 标准三阶段,不冻结 seed

与 §B.9 String 切轨同策略:
- RC + ABI 改动是 codegen 内部细节,seed 编译器不受影响(seed 自身用旧 ABI 运行 OK)
- stage1 = seed 编译 bootstrap/*(stage1 内部仍旧 ABI,但 stage1 输出新 ABI)
- stage2 = stage1 编译 bootstrap/*(stage2 内部新 ABI)
- stage3 = stage2 编译 bootstrap/*
- 验证 stage2 == stage3 bit-identical

**风险点**:stage2 启动若 Array runtime 函数链有 bug → segfault;失败 `git reset --soft HEAD^` + 修。Bootstrap 单次约 55s,迭代成本可承受。

**与 P1.X 落地经验对照**:P1.3 实测扩散到容器层(map/array/shell)+ 表达式层(calls/methods/exprs_str_conv)+ codegen IR 拼装顺序,**P2 类比预估必含同等扩散维度**(具体见 §扩容申报-P1.3 对账记录的"全栈连锁评估"教训);P2 字面量是 runtime 创建路径,不触发 codegen IR 拼装顺序问题(与 P1.3 字面量 boxed 不同),扩散面预估略低于 P1.3。

### §C.9 Array 扩容路径 RC 处理

**关键不变量**:`ss_arrayPush` 通过 realloc 扩容 buffer,**header ptr 不变**,所以外部对 array 的 RC 引用稳定(Perceus owned 不破)。

**push elem 时元素 RC**:
- elem 是 ref 类型 → push 入 buffer 前调 `ss_retain(elem)`(让 array 持有该 elem 一份引用)
- elem 是 scalar 类型 → 直接写 buffer,无 RC 操作

**pop 时元素 RC**:
- buffer 槽位元素 ref 类型 → pop 返回前 `ss_retain(elem)`(caller 持有),buffer 槽位无需 release(转移所有权);但若调用方丢弃 pop 结果,Perceus liveness pass(Phase 5)负责自动 release
- 旧实现 `ss_arrayPop` 直接返回 i64,无 retain;P2.3 切到 emitRetainForType/emitReleaseForType dispatch

**slice/concat**:
- 创建新 Array,**所有 ref 元素 retain**(浅拷贝语义);scalar 元素 memcpy
- 旧实现 ss_rc_retain 手工调用 → P2.3 切 dispatch

### §C.10 ref 元素 drop 循环 vtable 调用 — `ss_drop_Array_ref` 实现

```llvm
define void @ss_drop_Array_ref(ptr %arr) {
entry:
  %lenp = getelementptr inbounds %Array, ptr %arr, i32 0, i32 3
  %len = load i64, ptr %lenp
  %bufp = getelementptr inbounds %Array, ptr %arr, i32 0, i32 2
  %buffer = load ptr, ptr %bufp
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %dealloc, label %loop_check
loop_check:
  %i = phi i64 [ 0, %entry ], [ %inext, %loop_body ]
  %done = icmp uge i64 %i, %len
  br i1 %done, label %dealloc, label %loop_body
loop_body:
  %elemp = getelementptr i64, ptr %buffer, i64 %i
  %elem_i = load i64, ptr %elemp
  %elem = inttoptr i64 %elem_i to ptr
  call void @ss_release(ptr %elem)    ; 走元素自身 ObjHeader.TypeInfo.drop_fn vtable
  %inext = add i64 %i, 1
  br label %loop_check
dealloc:
  call void @mi_free(ptr %buffer)
  call void @ss_dealloc(ptr %arr)
  ret void
}
```

**根因证据**:`ss_release` 入口路径(`gen_runtime.ss:527-548` Phase 1 落地版)已有(a) null 检查(b) immortal sentinel `slt i64 %rc, 0` 跳过(c) RC dec → if 0 触发 `TypeInfo.drop_fn(p)`,所以 ref 元素是 string / class / interface / Map / Array 嵌套 全自动正确递归。**这是 D2=c 选 c 而非 a/b 的兑现** — 单一通用 vtable 路径,零元素类型特化,IR 体积 O(1)。

---

### §C Phase 2 内部子分阶段(每子步独立 commit + bootstrap 验证)

| 子阶段 | 范围 | 触达 | Status |
|---|---|---|---|
| **P2.1** | §C.3 emitArrayTypeInfo 双份 dead-code(scalar + ref TypeInfo + 6 per-type 函数 + typename 常量)+ §C.4 ss_alloc_array helper(dead-code,P2.2 才连接到字面量)| gen_runtime.ss(emitArrayTypeInfo +~150 行 IR) | [x] commit `daa40e8` 2026-05-10 |
| **P2.2** | §C.1 字面量 runtime 创建路径切到 ss_alloc_array(emitNewArrayFn 内部转发,所有调用方零改动)+ §C.6 gen_rt_array.ss 17 函数 GEP +3 全栈修正(len@3 / cap@4 / buffer@2 ptr load 直接,irLoadArrayData helper 归一化)+ §C.5 emitRetainForType isArrayType dispatch + ss_arraySlice/Concat TypeInfo 替代 tag 分派 + scalar Array 切轨完成 | gen_rt_array.ss / class.ss / ir_builder.ss / gen_runtime.ss(mi_realloc declare)/ codegen.ss(%Array prepend) | [x] 本 commit 2026-05-10(bootstrap stage2==stage3 PASS;全测 307/20/327 0 regression with P2.1 baseline;反射 gate PASS 无 bump 需要;失准段见下) |
| **P2.3** | **数组内部 RC**(2026-05-19 范围重定义,见 §C.9-exec):§C.9 push/slice/concat 元素 retain/release + §C.10 ss_drop_Array_ref vtable + ref 数组元素 retain owned/borrowed 协议(codegen 调用点)。`emitReleaseVarList` 局部变量释放切换**移出本阶段** → 独立 §C.11 收口(全局总出口,前置 Phase 3)| gen_rt_array.ss + gen_builtins/gen_calls 元素协议 | [x] close 2026-05-19(P2.3a `c95797a` + P2.1/P2.2 runtime;bootstrap 固定点 + 全测 323/5 0 regression)|
| **P2.4** | 综合大测 + Array<嵌套泛型> 验证(Array<Map<K,V>> / Array<Array<T>>)+ Phase 2 close | 全测 + 性能 micro-bench(可选)| [ ] Planned |

**子阶段间硬约束**:
- 任一子阶段 bootstrap 失败 → `git reset --soft HEAD^` + 修,**不允许带失败 commit**
- 子阶段独立 commit,**禁打包**(便于回滚定位)
- P2.1 必须 P2.2 前完成(类型基础设施先于字面量切换)
- P2.3 必须 P2.2 GREEN 后启动(scalar 路径稳定再切 ref,失败定位粒度更细)
- P2.4 必须 P2.1-P2.3 全 GREEN 后启动

**Phase 2 close 判据**:
- bootstrap 三阶段 bit-identical
- 全测 0 regression
- `grep ss_rc_calloc bootstrap/gen/rt/gen_rt_array.ss` 命中 = 0(只剩 Map 路径 Phase 3 切)
- `emitRetainForType` 加 isArrayType dispatch ✅,Array<T> 走 ss_retain
- `@Array_scalar_type_info` + `@Array_ref_type_info` 双份 IR 命中,`@ss_drop_Array_ref` 循环 vtable 调用命中

---

### §C.9-exec — P2.3 执行规划:f21271d 半成品归账(2026-05-18 锁定)

**触发**:I023→I024 链路 —— `f21271d`("add",un-MNK 巨型 commit)introduced d095 编译器 SIGSEGV;I024 Execute 轮 within-commit bisect 收敛、用户裁决「路径 1 = 完成 P2.3」。详证:`docs/4-issues/I024-double-comptime-annotation-codegen-segfault.md §2026-05-18(Execute)` + repo root `d095_setter_mixed.options.md`。

**f21271d 归账(核对)**:`f21271d` 把一处 **codegen 局部变量 RC tracking** 改动(`gen_rc.ss` `emitReleaseVarList` type-aware `Array→ss_release` 分派 + `localPtrVars` `name:type` schema + `gen_decls.ss` `genVarDecl` Array retain 分派 + `gen_arrows/gen_builtins` dispatch)**自行 mislabel 为「§C.9」并 un-MNK 落地**。但本 D **§C.9 的设计是 `gen_rt_array.ss` 运行时数组函数(push/pop/slice/concat)的元素 RC + §C.10 `ss_drop_Array_ref`** —— 与 codegen 局部变量 RC tracking 无关。`f21271d` 实为 P2.3 的 **un-MNK 半成品**:做了 codegen-local 释放侧(`emitReleaseVarList→ss_release`)、**未做** runtime 侧(§C.9/§C.10 仍是 P2.1 emit 的 dead-code)→ 数组 RC **半迁移不平衡** → 借入数组局部 `ss_release` over-free → d095 use-after-free(崩 `ss_arrayPush`,core 实证)。f21271d 同时把全测从 d062c18 的 307/20/327 劣化到 282/46/328。

**实测约束(I024 Execute 轮,各候选已建编译器全测对照)**:`f21271d` 的 4 个 RC 文件**部分 revert 必产生半迁移不一致并 regress**(revert `emitReleaseVarList` 单 hunk → 留借入数组局部泄漏;双侧 revert → regress `generic_constraint_basic`;整体 revert {gen_rc,gen_decls} → 与 gen_arrows/gen_builtins 不一致)。故 P2.3 须**整体推进到新系统一致态**,不可半留半 revert;且 `gen_builtins:140-143` 的 `emitRetainForType`(SS-LIM-6 §E corruption 闭合修法,见 I023 §备注)须保留。

**P2.3 子步分解**(bootstrap 三阶段 Stage2=Stage3 + 全测 0 regression + 反射 gate;**子步非全可独立 commit** —— 见下 §2026-05-18(P2.3 方案坐实)):

| 子步 | 范围 | 验收 |
|---|---|---|
| **P2.3a** | 实施真 §C.9/§C.10:`gen_rt_array.ss` `ss_arrayPush/Pop/Slice/Concat` 元素 retain/release 走 `emitRetainForType`/`emitReleaseForType` dispatch;wire P2.1 dead-code `ss_drop_Array_ref` 到 `@Array_ref_type_info.drop_fn` | §C.7 RED (c)(d);`@ss_drop_Array_ref` 循环 vtable 调用命中 |
| **P2.3b** | ref Array 切轨:`Array<string>`/`Array<class>` 字面量 + 局部 emit 选 `@Array_ref_type_info`;codegen-local 释放(`emitReleaseVarList`)与 runtime 侧对齐为**一致**新系统 | d095 RED→GREEN(`bin/ss build tests/phase5/d095_setter_mixed.ss` + 运行 exit 0) |
| **P2.3c** | f21271d 残留归正:借入/owned 数组局部 retain/release 平衡核验(与 I023 `isOwnedExpr` METHOD_CALL 协议对齐,避免 over-release) | 全测 fail 数 ≤ d062c18 baseline(20),0 新 regression |
| **P2.3d** | 综合:bootstrap 三阶段 bit-identical + `reflection_health_linter` GATE + §C.9/§C.10 + Phase 2 close 判据全过 | Phase 2 P2.3 close |

**衍生 issue**:`tests/phase5/generic_multi_constraint.ss` —— 已立项 `docs/4-issues/I025-generic-multi-constraint-rc-miscompile.md`(2026-05-18)。同根(P2.3 数组 RC 半迁移)、不同症(泛型多约束 codegen 非确定 miscompilation);**实测订正**:「d062c18 standalone 确定性 fail」精确为「d062c18 编译器 + 原版 `exit(1)` 形态」,当前 `bin/ss` 对原版 standalone 稳定 PASS、缺陷是 codegen 非确定。不混入 P2.3 regression 计数。

**与 I023 链路**:P2.3 完成、d095 修复、干净 baseline 还原后,I023 才可对原版候选 A 测真实 regression delta(I023 §状态)。

**2026-05-18(P2.3 方案坐实)**:P2.3 Execute 轮蓝图 = repo root `d168_p2.3_array_rc.options.md`(`bug_options_linter` 5/5 GATE OK)。要点:
- **选定候选 C**(系统审计 + 一致切换)—— A=`f21271d` 数据层 patch 已证崩、B 接口层 trap 留 runtime/审计缺口、D(数组纳入 PIR liveness)属 Phase 5。
- **P2.3 非全子步可独立 commit**:`emitReleaseVarList` 切类型分派(P2.3b)+ owned/borrowed 协议(P2.3c)+ string `let` 局部连带 **必须同 commit** —— 任何中间态(切 release 未修协议、或反之)即 `f21271d` 崩溃态(§实测约束 已证「部分推进必 regress」);仅 P2.3a(`ss_arrayPush` 元素 retain,runtime 侧)可独立先行。
- **唯一不一致点**:`emitReleaseVarList`(gen_rc.ss:108)一律 `ss_rc_release`,与 `emitReleaseForType` 类型分派割裂;`localPtrVars` `name:type` 的 type 段已存、reader 待启用。
- **3 个假设破裂入口**((a) 新旧布局 no-op 掩盖 / (b) `isOwnedExpr` 误判借入数组无配对 retain / (c) `genReturn` declRet 退化致 CALL 返 borrowed)+ 完整改动清单(runtime/codegen/协议)详 options.md §2/§5;Execute 前必读。

**2026-05-19(P2.3 Execute — P2.3a 落地 + P2.3b 实测受阻)**:

- **P2.3a 完成**(commit `c95797a`)— ref 数组元素 retain 纳入 `isOwnedExpr` owned/borrowed 协议(`gen_builtins` `.push()` 加 `isOwnedExpr` 门 + `gen_calls` `genArrayLit` 固定/spread 两路径补 retain):数组持有元素一份引用,borrowed 元素才 retain、owned 元素自带 +1 转移。bootstrap 三阶段固定点 + 全测 323/5 0 regression。

- **options.md §5-1 修正**(commit `bab548c`)— 原「`ss_arrayPush` runtime 加 retain」实测错位:`.push()` 元素 retain 早在 codegen `gen_builtins.ss:140-143`(runtime 再加 = double-retain)、ARRAY_LIT 固定字面量走 `ss_arraySet` 不经 `ss_arrayPush`、owned/borrowed 是编译期 AST 信息 runtime 不可判 → 元素 retain 决策只能在 codegen 层。

- **P2.3b 受阻 —— `emitReleaseVarList` 切换依赖 Phase 3(Map RC)先落地**。实测两障碍:
  - **障碍 1(切 string → string-in-Map UAF)**:`emitReleaseVarList` 把 string 局部切真实 `ss_release` 后,string 存进无类型注解 `Map()`(`mapValueIsPtr` 仅认 `Map<K,V>` 注解 → val_type=0 → `ss_mapSet` 不 retain value、`ss_drop_Map` 用旧 `ss_rc_release`)时,string 局部 release → Map value 悬空 → UAF。全测 303/25(`stdlib_json/ini/url`、`i021_requestbody_nested_*`、`d096_reactive` 等 ~20 个 string-in-Map 崩)。
  - **障碍 2(收窄只切 Array 仍 over-release)**:`emitReleaseVarList` 只对 `isArrayType` 切 `ss_release`(string/Map 留旧)→ 全测 322/6,`stdlib_sort`(纯 scalar `Array<int>`)mimalloc corrupted-free-list、形态敏感非确定崩 —— Array 局部真实 release 后仍有未平衡持有点。
  - **根因**:`emitReleaseVarList` 切真实 release 让所有局部容器真实死,牵动整个 RC 协议网 —— **Map 必须先参与新系统 RC**(string/Array/class 都能存进 Map,Map 是值的汇容器),否则 X-in-Map 必悬空。这是 **Phase 顺序问题**:`emitReleaseVarList` 局部变量真实 RC 切换依赖 **Phase 3(Map RC)**,而 §C.9-exec 把它放在 P2.3b(Phase 2)= 依赖反置。`f21271d`「部分推进必 regress」实测约束是同一根因的另一面(此前未识别为「依赖 Phase 3」)。
  - **决策(2026-05-19 自定,不另裁决)**:`emitReleaseVarList` 是**所有类型局部变量的统一释放出口**,切真实 `ss_release` 是「全或无」全局原子操作 —— 不能按容器类型分 Phase(切了就对 string/Array/Map/class 一切局部生效,而这些可被 Map 持有)。**P2.3 重定义 = 数组内部 RC**(元素 retain/release owned/borrowed 协议 + §C.9/§C.10 runtime),P2.3a(`c95797a`)+ P2.1/P2.2 已落地 → **P2.3 close**。`f21271d`「部分推进必 regress」= 同一根因(`emitReleaseVarList` 全或无)的另一面。
  - **§C.11(新增,Phase 3 之后)— `emitReleaseVarList` 收口**:局部变量真实释放切换独立成阶段。前置 = String(P1 ✓)+ Array(P2 ✓)+ **Map(Phase 3)** 三容器 retain 侧全切完 —— 否则 Array/string 局部真回收后存进未切的 Map 即 value 悬空 UAF(本轮实测全测 303/25)。Map RC 完成后:`emitReleaseVarList` 按类型全切 `ss_release` + 所有 retain 侧(`genVarDecl`/`genAssign`/构造函数/容器 `set`)对齐。消 Array/string 局部泄漏、d095(I024)/I025 根因消除 = §C.11 判据。options.md §5-2/5 作废(随 P2.3 重定义)。**[x] 2026-05-19 落地 —— 详 §C.11 段。原文「`emitReleaseVarList` 按类型全切 `ss_release`」经 spike 实证有误(编译期类型名分派精度不足致 UAF),修正为 `ss_*_any` magic 运行时分派 + `isRcManaged` 门。**

### §C.10-map — Phase 3 执行规划:Map value RC(2026-05-19 落地)

**触发**:`next_prompt` 启动「D168 Phase 3 Map RC」—— §C.11 `emitReleaseVarList` 收口的 hard 前置(§C.11 明示「前置 = String✓ + Array✓ + Map(Phase 3)retain 侧全切完」)。蓝图 = repo root `map_rc.options.md`(`bug_options_linter` 6/6 GATE OK,选候选 B 接口层)。

**RED**:`grep -n ss_rc_retain bootstrap/gen/gen_builtins.ss` → 235(`genMapMethod("set")` ptr value retain 硬编码 OLD `ss_rc_retain`);Map value-release 三处硬编码 OLD `ss_rc_release`。OLD RC 函数靠 magic@-4 守卫,对 NEW-系统 value(string/Array/class,P1/P2 后)magic 不匹配 → 静默 no-op → Map 既不真 retain 也不真 release NEW value。

**本轮(2026-05-19)落地 = Map value retain + Map-death release**:

| 子项 | 改动 | 文件 |
|---|---|---|
| 通用 RC 分派 | 新增 `ss_retain_any` / `ss_release_any`(`emitAnyRcDispatch` helper):magic@-4 守卫 → OLD 对象走 `ss_rc_*` / NEW 对象走 `ss_*`。retain/release 同按**运行时 magic** 分派,不依赖编译期类型名精度 | `gen_runtime.ss` |
| value retain | `genMapMethod("set")` ptr value retain `ss_rc_retain` → `ss_retain_any`,加 `isOwnedExpr`/`pushNonOwning` 门(borrowed 才 retain、owned +1 转移)— 与 array push `gen_builtins.ss:140` 同协议 | `gen_builtins.ss` |
| val_type 推断 | `.set()` 处按实际 value LLVM 类型 emit val_type flag@516 —— 覆盖无类型注解 `Map()`(`mapValueIsPtr` 仅认 `Map<K,V>` 注解的推断缺口) | `gen_builtins.ss` |
| Map-death release | `ss_rc_destroy_map` value-release `ss_rc_release` → `ss_release_any` | `gen_runtime.ss` |

**`ss_mapSet`-update + `ss_mapDelete` value-release 移出本轮 → §C.11**(实证驱动范围修正):

- 实测:三处 value-release 全切真实 release → 全测 318/10,`d095_*`(I024)standalone 编译器 SIGSEGV。
- **根因**:`map.get`(string)走 `ss_mapGetString` **不 retain** → map value 是无 RC 保护的 borrowed 引用。`ss_mapSet`-update / `ss_mapDelete` 真实 release 在 **scope 中段** free 旧值 → borrow-then-mutate(编译器 `nGetS1` 借出字符串 → `nStr1.set` 覆写)的借入引用悬空 → UAF。`ss_rc_destroy_map` 安全(scope 末尾,借用者已结束)—— 故 retain + destroy 安全、update/delete 不安全。
- update/delete 真实 release **hard-depends on §C.11 get 侧 retain**(owned/borrowed 协议)—— 与 §C.9-exec「§C.11 依赖 Phase 3」对称的依赖发现。本轮不做,留 §C.11。`gen_rt_map.ss` 两处保留 `ss_rc_release` + 注释锚 §C.11。

**§C.11 前置达成**:§C.11 需「Map retain 侧切完」+「Map-death 释放 value」。本轮 retain(`ss_retain_any`)+ destroy(`ss_release_any`)精确交付二者 → **§C.11 Map 前置 ✓**。§C.11 自身 scope 含 get 侧 retain + update/delete 真实 release 对齐。

**验收**:bootstrap 三阶段 Stage2==Stage3 bit-identical(本轮多次重建均 PASS);全测**稳定**失败集 = baseline(`harness_bug`/`d096_p4_l2_reactive`/`harness_task`/`spring_web_params` 4 项 pre-existing,~10 次 run 恒定)。`bin/ss test` 并发下 generic 族(`generic_constraint_multi`/`generic_constraint_basic` 等)**非确定 flap**(逐 run 命中项与计数变,322/6 ~ 323/5)= I025(§C.9-exec「codegen 非确定」+「不混入 regression 计数」):standalone 15/15 + binary 50/50 PASS、bootstrap stage2==stage3 bit-identical 证编译器确定且正确 → 非本轮 codegen regression。观察:I025 对源路径 `//` vs `/`、build 上下文敏感(补记 `docs/4-issues/I025`)。

**§实证回填**(`map_rc.options.md §实证 (c)` spike):spike(retain + destroy_map)= 全测 324/4 0 regression → 「retain + Map-death release」假设成立;全量(+ update/delete)= 318/10 d095 SIGSEGV → 「update/delete 真实 release」假设破裂,回方案层 → update/delete 移 §C.11。

### §C.11 — emitReleaseVarList 收口(2026-05-19 落地)

**触发**:`next_prompt` 启动「§C.11 emitReleaseVarList 收口」—— Phase 3 Map RC(§C.10-map)落地后前置达成。蓝图 = repo root `c11_release_varlist.options.md`(`bug_options_linter` 6/6 GATE OK,选候选 B 接口层 trap)。

**RED**:`grep -n ss_rc_release bootstrap/gen/gen_rc.ss` → 117 `emitReleaseVarList` 一律旧 `ss_rc_release`;对 NEW-系统 string/Array/class 局部 magic@-4 不匹配 → no-op → 局部泄漏。

**落地 = codegen-local RC 全栈统一为 magic 运行时分派**:

| 子项 | 改动 | 文件 |
|---|---|---|
| 释放出口 | `emitReleaseVarList` `ss_rc_release` → `isRcManaged` 判定后 `ss_release_any` | `gen_rc.ss` |
| RC-managed 判定 | 新增 `isRcManaged`(OLD Map/Set + NEW string/Array/class 正列表)+ `rcEntryType` reader | `gen_rc.ss` |
| binding-retain | `genVarDecl` borrowed-retain / `genAssign` 重赋值 retain+release → `ss_*_any`(isRcManaged 门) | `gen_decls.ss` / `gen_assigns.ss` |
| return-retain | `genReturn` 借入返回值 retain → `ss_retain_any`(按**声明返回类型** isRcManaged 判定,非 `inferType(valId)`) | `gen_decls.ss` |
| 复合赋值 | `genAssign`/`genFieldAssign`/`genStaticFieldAssign` string `+=` 旧值 release → `ss_release_any` | `gen_assigns.ss` |
| Map mutation | `ss_mapSet`-update / `ss_mapDelete` value-release `ss_rc_release` → `ss_release_any`(§C.10-map 留锚消除) | `gen_rt_map.ss` |

**§实证 —— spike 三轮(MNK §字段 12:蓝图关键假设破裂 → 回方案层修正,非全量 Execute)**:

1. **轮 1 — type-based 分派 → bootstrap stage3 SIGSEGV**。options.md 候选 B 原设计 = `emitReleaseForType`/`emitRetainForType`(按编译期类型名分派)。崩。根因:`genReturn` return-retain `emitRetainForType(val, inferType(valId))` —— `inferType` 对 method-call 返回式(`x.reverse()`/`.concat()`)不精确 → 落 noop `ss_rc_retain`;§C.11 release 侧已 real → 返回值 over-release → freed-while-returned UAF(最小复现 `Sort.descending`:`let sorted = quickSort(arr); return sorted.reverse()`)。**假设破裂**:「编译期类型名分派足够」不成立。
2. **轮 2 — magic 分派,无门 → `ref_basic`/`channel_basic`/`channel_bounded` SIGSEGV**。修正为 `ss_*_any`(magic@-4 运行时分派,§C.10-map 为消类型名精度依赖而建)。bootstrap PASS、`stdlib_sort` 修复,但 Ref/Channel 崩。根因:`Ref`(`%__Ref` calloc 32)/`Channel`(`%__Channel` calloc 168)是**第三类对象** —— 无 OLD magic@-4、亦非 NEW ObjHeader;`ss_release_any` 二分法误判为 NEW → `ss_release` 按 ObjHeader 布局解读 → 调垃圾 drop_fn → 崩。**假设破裂**:「对象非 OLD 即 NEW」不成立。
3. **轮 3 — magic 分派 + `isRcManaged` 正列表门 → GREEN**。`ss_*_any` 仅对 `isRcManaged`(OLD Map/Set + NEW string/Array/class)局部发射;Ref/Channel/Thread 等第三类对象 `isRcManaged=0` 跳过(D082 自管生命周期,与 §C.11 前同样泄漏不崩)。bootstrap 三阶段 Stage2==Stage3 **bit-identical**;全测 **324/4** 三轮稳定,4 失败 = 基线 pre-existing(`harness_bug`/`d096_p4_l2_reactive`/`harness_task`/`spring_web_params`),0 regression;`stdlib_sort`/`ref_basic`/`channel_basic`/`channel_bounded`/`thread_capture` 全 PASS。

**根因订正(修正 §C.9-exec / §C.10-map 的诊断)**:§C.9-exec 把「切 emitReleaseVarList 即崩」归因「依赖 Phase 3 Map RC」;§C.10-map 据此把 update/delete release 留 §C.11「依赖 get 侧 retain」。spike 实证:Phase 3 完成后 §C.11 仍崩两轮 —— **真实根因非 Map 顺序**,而是 (1) codegen RC 分派依赖编译期类型名精度,`inferType` 对方法调用返回式不精确;(2) RC 对象有**三类**(OLD magic / NEW ObjHeader / Ref·Channel·Thread calloc'd),`emitReleaseForType` 二分法不覆盖第三类。修法:codegen-local RC 全栈 magic 运行时分派(`ss_*_any`)+ `isRcManaged` 正列表门控第三类。「Map 须先切」仍是真前置(§C.10-map 后 string-in-Map 才不悬空),但**非充分条件**。

**判据达成**:消 string/Array 局部「emitReleaseVarList no-op」泄漏(RC-managed 局部真实 `ss_release_any`);d095(I024)/I025「半迁移不平衡」根因消除(retain/release 全栈 magic 对称,杜绝 real-noop 失配);`ss_mapSet`-update/`ss_mapDelete` 真实 release 落地。回归测试 `tests/phase5/c11_release_varlist.ss`(覆盖 return-localVar-method / Ref 局部 / Map mutation)。**§C.11 close**。

**残留(非 §C.11 scope)**:`isOwnedExpr(METHOD_CALL)=0` 对返回 owned 的方法调用误判 borrowed → binding 侧双 retain → +1 计数泄漏(非崩)= `docs/4-issues/I023-methodcall-class-rc-leak.md` A 类(已立项 Planned)。§C.11 后该泄漏由「`emitReleaseVarList` no-op 不释放」形态转为「`genVarDecl`/`genReturn` 双 retain」形态,泄漏量不变,根因(`isOwnedExpr` METHOD_CALL 未按返回类型分派)留 I023 修。

---

## 附录 D:Phase 3 Map header→ObjHeader 切轨子设计

**Status:** Drafted at 2026-05-19(§C.10-map + §C.11 close 后,Map header 迁移 spike 启动前最后子决策锁定层)
**Scope:** D.1-D.9 子决策 + P3.1-P3.3 内部子分阶段;Map header 迁移 Execute 启动前必读
**前置:** §A.3 ObjHeader `{i64 rc, ptr TypeInfo}` + immortal sentinel(Phase 1 落地);§C.10-map Map value RC(`ss_retain_any`/`ss_release_any` magic@-4 分派)+ §C.11 `emitReleaseVarList` 收口(codegen-local RC 全栈 `ss_*_any`)已落地 —— **Map value 的 retain/release 已就位,§D 仅迁 Map 对象头本身**,是 Phase 4 删 `ss_rc_*` 的最后 gateway。

---

### §D.1 Map 实例 layout 决策 — 锁定选项 1 inline buckets

| 选项 | layout | 业界 | Phase 3 评估 |
|---|---|---|---|
| **1 inline buckets** | `%Map = { i64 rc, ptr TypeInfo, [64 x ptr] buckets, i32 size, i32 val_type }` 536B 单次 `mi_calloc` | Go `hmap` bucket 内联 / 定长开链哈希表 | ✅ **选定** — 保留 OLD 固定 64 桶 inline 设计,仅 16B 头由 `[rc\|tag\|magic]` 负偏移换 `[rc\|TypeInfo]` 正偏移;桶数固定永不 realloc → header ptr 天然稳定;改动 = 全栈 GEP 机械 +16 |
| 2 indirect bucket buffer | `%Map = { i64 rc, ptr TypeInfo, ptr buckets, i32 size, i32 val_type }` + buckets 单独 `mi_calloc(512)` | 形式对称 §B.1/§C.2 String/Array | ⚠ §B.1/§C.2 选间接是为「扩容 realloc buffer 时 header ptr 稳定」;**Map 桶数固定 64 永不 realloc → 该理由不成立**,indirect 反在每次 hash lookup 热路径多 1 次 buckets ptr load,零收益 |
| 3 inline + rehashing 重设计 | indirect + 动态桶数 + 负载因子 rehash | Java `HashMap` / Rust `hashbrown` | ❌ 留 §F 远期 — hashtable 算法重设计,超出「header 迁移」task scope,违反 §B.4/§C.4「RC ABI hard break 不叠加第二 hard break」 |

**锁定 D.1 = 选项 1 inline buckets**(与 §B.1/§C.2 String/Array「间接 buffer」**刻意分歧**):
- **根因**:本 §D scope = 对象头迁移,非 hashtable 重设计。选项 1 精确做头迁移,blast radius 最小。
- **Map 桶固定 64**:§C.2 间接 buffer「扩容只 realloc buffer、header ptr 不变」对 Map **不适用**(Map 无桶增长);照搬 §B/§C 形式 = 假对称、热路径多一次 indirect load 换零收益 = 过度工程。
- **长久演化**:唯一想要 indirect 桶的场景是 rehashing(选项 3),而 rehashing 是 §F 远期无 roadmap;届时它本身是 hashtable 算法决策、touch 所有桶逻辑,与头迁移弱耦合 → 选项 1 的 N 年返工度低。
- **`%Map` struct**:`{ i64, ptr, [64 x ptr], i32, i32 }` = 536B(16 头 + 512 桶 + 4 size + 4 val_type),8 对齐;承 §B 衍生约束「ObjHeader 原型 [0,1] + 业务 [2,3,4]」,业务字段 [2]=桶数组、[3]=size、[4]=val_type。

---

### §D.2 ObjHeader 迁移核心 + mimalloc 分配切换

**ABI 变更**:
- **旧**:`ss_mapNew` → `ss_rc_calloc(520, 2)` — libc `malloc` 出 `[rc:i64@-16 \| tag:i32@-8 \| magic:i32@-4]` 16B 头 + 520B 清零体,user ptr = raw+16;`tag=2` 供 `ss_rc_release` 内部分派 `ss_rc_destroy_map`。
- **新**:`ss_mapNew` → `mi_calloc(1, 536)` — mimalloc 出 `%Map`,user ptr = struct base+0;rc@0、`@Map_type_info`@8、桶/size/val_type 由 calloc 清零。

`ss_mapNew` 升级后(`ss_mapNew` 是 Map 唯一分配点 —— `grep -rn ss_mapNew bootstrap/` 证 `class.ss:280` `new Map()/new Set()` + `gen_deserialize.ss:231` + `gen_registry.ss` 全转发此单函数):

```llvm
define ptr @ss_mapNew() {
entry:
  %m = call ptr @mi_calloc(i64 1, i64 ptrtoint (ptr getelementptr (%Map, ptr null, i32 1) to i64))
  %rcp = getelementptr %Map, ptr %m, i32 0, i32 0
  store i64 1, ptr %rcp, align 8
  %tip = getelementptr %Map, ptr %m, i32 0, i32 1
  store ptr @Map_type_info, ptr %tip, align 8
  ret ptr %m
}
```

- **不设独立 `ss_alloc_map` helper**(与 §B.4 `ss_alloc_string` / §C.4 `ss_alloc_array` 分歧):那二者多调用点(字面量路径 + …)才抽 helper;**Map 单分配点**,`ss_mapNew` 自身即分配函数,抽 helper 是空层。
- **`%Map` 类型声明**:加入 `codegen.ss` `typeDecl` prepend 行(与 `%String`/`%Array` 同行)。Map 无字面量、不需 prepend 的 constant-initializer 排序约束,但同处声明 zero-cost 消除「`emitRuntimeTypes` 先于 `emitRuntimeMap`」的顺序耦合假设。
- **immortal**:Map 永远 runtime 创建(无 `@.map.N` 字面量常量),rc 从 1 起永不为负 → `ss_retain`/`ss_release` 的 `slt i64 %rc,0` immortal 路径对 Map 永不触发,无需特殊处理(比 §B String 字面量 boxed immortal 简单)。
- **MapEntry 节点**:`{ key:ptr@0, value:i64@8, next:ptr@16 }` 24B,**保持 libc `malloc`/`free`** —— entry 是内部开链节点、非 RC 对象、不调 `ss_rc_*` → 不阻 Phase 4;mimalloc 统一是 C2 纯度 §F 远期。`ss_drop_Map` 内 entry 用 `free`、Map 头用 `ss_dealloc`(mi_free)—— 各 alloc 配各自 free,不可错配。

---

### §D.3 Map per-type 函数生成 — `emitMapTypeInfo()`

对照 `emitStringTypeInfo`(`gen_runtime.ss:622`)/ `emitArrayTypeInfo`(`:727`),新增 `emitMapTypeInfo()`,`emitRuntimeRC` 末尾(`emitArrayTypeInfo` 后)调用:

```llvm
@.rt.str.Map = private constant [4 x i8] c"Map\00"

@Map_type_info = constant %TypeInfo {
  ptr @ss_drop_Map,
  ptr @ss_deep_clone_Map,
  ptr @ss_shallow_clone_Map,
  i64 ptrtoint (ptr getelementptr (%Map, ptr null, i32 1) to i64),
  ptr @.rt.str.Map,
  i32 -4,
  ptr null
}
```

- **`@ss_drop_Map(ptr %map)`** — 即 `ss_rc_destroy_map`(`gen_runtime.ss:426`)按 NEW 布局重写 + **末尾 `ss_dealloc(map)`**:读 val_type@532 → 遍历 64 桶(buckets@16,typed GEP)→ 逐 entry:存 next、`free(entry.key)`(§D.4)、val_type==1 则 `ss_release_any(entry.value)`、`free(entry)` → 全桶完后 `call void @ss_dealloc(ptr %map)`。**关键结构差异**:OLD `ss_rc_destroy_map` 只「析构内容」、Map 块由 `ss_rc_release` 的 `free(raw)` 释放;NEW 体系 `drop_fn` 一手包办**含释放对象块**(对照 `ss_drop_String`:`mi_free(buf)+ss_dealloc(p)`)。
- **`@ss_deep_clone_Map` / `@ss_shallow_clone_Map`** — 均 = `ss_retain(self)` + 返 self(3 行 IR,对称 `ss_shallow_clone_String`)。Map 是引用/容器类型,shallow = 共享。`ss_deep_clone_Map` 经 `ss_deep_clone_Array_ref`(`gen_runtime.ss:861` 元素 vtable 分派)的 `Array<Map>` 深拷贝路径**可达** —— 现状 OLD Map 无 TypeInfo,该路径读 OLD-Map offset 8(桶[1])当 TypeInfo → 调垃圾 fn 崩;§D 给 Map 真 TypeInfo 后此路径**变安全**(retain-self 即共享内层 Map,语义为浅但不崩)。真实逐 entry 深拷贝(new map + strdup key + value vtable deep_clone)是 Map value 语义独立设计,留 §F;P3.3 / Phase 2 P2.4(`Array<Map>` 验证)轮再评估是否需升级。

**单 `@Map_type_info` + val_type runtime flag,不学 §C Array 双 TypeInfo**:§C D2=c 给 Array 分 `scalar`/`ref` 两 TypeInfo,因 Array 元素类型在字面量/alloc 时**已知**(`[1,2,3]` scalar / `["a"]` ref)。Map **不可**:无类型注解 `new Map()` 在 `ss_mapNew` 时**不知** value 是否 ptr —— 延迟到首次 `.set()` 才由 codegen 写 val_type flag(`gen_builtins.ss:247`「typed + 无注解 Map() 统一覆盖」)。compile-time 选 TypeInfo 对 untyped Map 不可行 → **val_type@532 runtime flag 是 untyped Map 的根因所需**,保留(非 §C 体系遗漏)。`class_id=-4`(String -1 / Array -2,-3 / Map -4;Set 共用 `@Map_type_info` → 同 -4,与 OLD 双 tag=2 不可分同等)。

---

### §D.4 MapEntry.key 去 `ss_rc_strdup`

**RED**:`grep -n ss_rc_strdup bootstrap/gen/rt/gen_rt_map.ss` → `ss_mapSet` insert(`:108`)`ss_rc_strdup(ikey_buf)` 出一份 **OLD-RC** 裸 cstr 存 `entry.key`;`ss_rc_destroy_map`/`ss_mapDelete` 用 `ss_rc_release(key)` 释放。

`ss_rc_strdup` 内部走 `ss_rc_alloc`,`ss_rc_release` 是 Phase 4 明令删除的函数 —— **entry.key 不脱 `ss_rc_*` → Phase 4 无法删 `ss_rc_release`**(entry.key 仍是其调用点)。§D 作为 Phase 4 gateway **必须**含 entry.key 去 RC 化。

**改法**:entry.key 本是哈希表内部 cstr(refcount 恒 1、entry 独占、永不共享、生命周期 = entry)—— 从来不需要 RC,`ss_rc_strdup` 是 OLD-RC 机制的偶然耦合。
- `ss_mapSet` insert:`ss_rc_strdup(ikey_buf)` → `@strdup(ikey_buf)`(`strdup` 已 `declare`,`gen_runtime.ss:52`)。
- `ss_drop_Map` / `ss_mapDelete`:`ss_rc_release(key)` → `free(key)`。
- entry.key 保持**裸 cstr** 形态 → `find_entry` 的 `strcmp(ek, key_buf)` + `ss_mapKeys` 的 `strlen(ek)` + `ss_mapKeysArray` 的 `ss_string_from_cstr(ek)` **全不变**(只是 alloc/free 原语换 libc 原生)。

去化后 Map 路径 `ss_rc_*` 残留仅 `ss_mapKeys` 的 newline-join scratch buffer(`ss_rc_alloc`/`ss_rt_ensure_cap`/`ss_rc_release`)—— 非 Map header、是跨运行时共享 string-build idiom(`ss_rt_ensure_cap` 多函数复用)→ **明确划归 Phase 4**,§D 不动(spike 前 `grep ss_rt_ensure_cap` 确认跨域)。

---

### §D.5 emitRetainForType / emitReleaseForType 路由 — 加 isMapType 分支

**RED**:`class.ss:140-155` `emitRetainForType`/`emitReleaseForType` 现 `isUserClass||string||isArrayType → ss_retain` 否则 `ss_rc_retain`;`isUserClass("Map")==0`(`class.ss:124`)→ Map 落 `else` 走 `ss_rc_retain`。§D 后 Map 是 NEW 对象 —— `ss_rc_retain(NEW Map)` 读 magic@-4 = 垃圾 ≠ 1397969747 → 守卫失败 → no-op → **Map 永不释放 = 泄漏**。

**改法**(P3.2):`class.ss` 加 `isMapType(t)`(对称 `isArrayType`:`t=="Map" || t.startsWith("Map<") || t=="Set" || t.startsWith("Set<")`),`emitRetainForType`/`emitReleaseForType` 条件加 `|| isMapType(ssType)==1` → Map/Set 走 `ss_retain`/`ss_release`。

- `emitReleaseVarList`(§C.11)/ `genVarDecl` / `genReturn` 已用 `ss_*_any` —— `_any` 按运行时 magic 分派:§D 前 Map 有 magic→`ss_rc_*`,§D 后 Map 无 magic→`ss_*`,**自动适配,零改动**(`ss_*_any` 正是 §C.10-map 为消类型名精度依赖而建)。`isRcManaged`(`gen_rc.ss:55`)已含 Map → 不变(注释「OLD(Map/Set)」§D 后过时,P3.2 顺手订正为 NEW)。仅类型名静态分派的 `emitRetainForType`/`emitReleaseForType` 需 §D.5。
- 触达点:Map 作 class 字段时 `ss_drop_<Class>` 经 `emitReleaseForType(field,"Map")` 释放;Map 作 class 字段 share 分支 `emitRetainForType(val,"Map")`(`gen_type_ops.ss:381`)。二者 §D.5 后正确路由 NEW。
- Phase 4:全容器切完后 `emitRetainForType`/`emitReleaseForType` 退化为单一 `ss_retain`/`ss_release`(D168 §核心目标 + §A.3),`isMapType`/`isArrayType` 分支一并消除。

---

### §D.6 全栈 GEP 偏移修正清单

**ABI 偏移**(inline buckets,全字段 +16):

| 字段 | OLD | NEW | 访问 | 影响函数 |
|---|---|---|---|---|
| rc | raw-16 (i64) | **0** (i64) | `ss_retain`/`ss_release` 内部 | RC 路径 |
| tag / magic | -8 / -4 (i32) | **删除** | — | OLD 头碎片消除 |
| TypeInfo | (无) | **8** (ptr) | `ss_release` drop 分派 | drop 路径 |
| buckets[64] | 0..511 | **16..527** | `irMapBucketPtr` typed 5-operand GEP | find_entry / ss_mapSet(insert) / ss_mapDelete / ss_mapKeys / ss_mapKeysArray / ss_drop_Map |
| size | 512 (i32) | **528** (i32) | i8-offset +16 | ss_mapSet(insert) / ss_mapSize / ss_mapDelete(dec) / ss_mapKeysArray |
| val_type | 516 (i32) | **532** (i32) | i8-offset +16 | ss_mapSet(update) / ss_mapDelete / ss_drop_Map〔runtime〕;gen_builtins.ss:250 / gen_decls.ss:673 / gen_deserialize.ss:234〔codegen〕|

**桶 GEP helper**:6 处桶访问现为 `irGEP(…,"ptr","%map",idx)`(把 `%map` 当 ptr 数组基址,= `map+idx*8`)。inline 桶在字段 2 → 统一经新 helper `irMapBucketPtr(name, mapReg, idxReg)`(`ir_builder.ss`)emit `getelementptr %Map, ptr %map, i32 0, i32 2, i64 %idx`(= `map+16+idx*8`,结果同为 ptr-to-bucket)。DRY,对照 §C P2.2 `irLoadArrayData` 归一。

**精确化(订正本轮 task 给定清单)**:`ss_mapGet` / `ss_mapGetString` / `ss_mapHas` 自身**无 Map-struct GEP** —— 只调 `find_entry` + 读 entry 节点(`entry+8` value);`find_entry` 桶 GEP 修好后三者**传递覆盖、零自身改动**。`find_entry` 的 `getelementptr %String,%key,…,2` 取 key buffer 是 P1 §B.7 既有(key 是 NEW String header),§D 不变。`hash_str` 纯函数无 Map 访问。

**codegen 侧 val_type 写**(3 处 emit-string 字面量 516→532):`gen_builtins.ss:250`(`.set()` ptr value 标记)/ `gen_decls.ss:673`(类型注解标记)/ `gen_deserialize.ss:234`(反序列化)。**必须与 runtime 偏移同 commit** —— 否则 val_type 写进 OLD 偏移(516 落 NEW 桶[62] 内)= 桶链表损坏。

**`ss_rc_destroy_map` + `ss_rc_release` tag-2 分支**:§D 后无 Map 带 tag → 二者均 dead code;§D **不删**(保持 P3.2 diff 聚焦 migration),Phase 4「删旧系统」统一 sweep。

---

### §D.7 RED 命令 + 最危险假设 + spike

**RED**(spike 前实测):
```bash
cat > /tmp/d168_p3_spike.ss <<'EOF'
function main() {
    let m = new Map()
    m.set("k", "v")
    println(m.getString("k"))
}
EOF
bin/ss build /tmp/d168_p3_spike.ss --emit-ir 2>&1 | grep -E '@Map_type_info|ss_drop_Map|%Map = type'
grep -c 'ss_rc_calloc' bootstrap/gen/rt/gen_rt_map.ss
```
- **spike 前**:`grep` 三符号 0 命中;`ss_rc_calloc` 计数 = 1(`ss_mapNew`)。
- **P3.1 后**:`@Map_type_info` + `ss_drop_Map` + `%Map = type` 命中(dead-code emit);`ss_rc_calloc` 仍 1。
- **P3.2 后**:`ss_mapNew` 内 `mi_calloc` + `@Map_type_info` 写入命中;`ss_rc_calloc` 在 `gen_rt_map.ss` = **0**(单一判据)。

**最危险假设**:**P3.2「全或无」可一次性原子完成不崩** —— Map 头一旦切 NEW,所有桶/size/val_type GEP + retain/release 路由必须同时正确,**无半迁移中间态**。§C.9-exec `f21271d` + §C.11 spike 三轮已实证「部分推进必 regress」;P3.2 不可拆,Execute 走 §D.8 标准三阶段、崩则整体 `git reset --soft HEAD^`。次危险假设:NEW Map 传 `ss_*_any` 时 magic@-4 OOB 读无害 —— **已被 §C.11 string/Array/class 实证**(三者全 mi_calloc'd NEW 对象、324/4 baseline);Map 同为 mi_calloc'd NEW 对象,复用同机制,非新风险。

**spike**:P3.1(dead-code,bootstrap-safe)即天然 spike —— 验 `emitMapTypeInfo` emit 正确 + bootstrap 固定点;P3.2 因原子不可拆,其「spike」= 全量实施 + 三阶段,失败 reset(§M§字段12 与「一次性改完」不矛盾的特例:原子改动无 1-2 处子 spike 空间)。

---

### §D.8 Bootstrap hard break 策略 — 标准三阶段,不冻结 seed

与 §B.9 / §C.8 同策略:RC + ABI 改动是 codegen 内部细节,seed 编译器(`bin/ss`)不受影响 —— stage1=seed 编译 bootstrap(stage1 内部旧 ABI、输出新 ABI)、stage2=stage1 编译、stage3=stage2 编译,验 stage2==stage3 bit-identical。

**风险点**:P3.2 后 stage2 启动若 Map runtime 函数链有 bug → segfault;失败 `git reset --soft HEAD^` + 修。Bootstrap 单次约 55s。

**与 P1/P2 落地经验对照**:P1.3 字面量 boxed 触发 codegen IR 拼装顺序连锁、P2 是 runtime 创建无此问题;**Map 同 runtime 创建(无字面量)→ 扩散面预估近 §C.8 Array 量级**。但 Map 是编译器自身重度依赖的数据结构(`nKind`/`pirKind` 等全局 Map),P3.2 崩面比 Array 更广、定位更难 → P3.1 dead-code 先行隔离 emit 正确性的价值高于 §B/§C。

---

### §D.9 §D 内部子分阶段(每子步 bootstrap 验证)

> §C.10-map + §C.11 是 Phase 3 的 **value-RC 半**(已 close);本 §D 是 **header 迁移半**,P3.x 编号专指 header 迁移子步。

| 子阶段 | 范围 | 触达 | Status |
|---|---|---|---|
| **P3.1** | §D.3 `emitMapTypeInfo` dead-code 元数据(`%Map` type 入 `codegen.ss` typeDecl + `@Map_type_info` + `ss_drop_Map` + `ss_deep_clone_Map`/`ss_shallow_clone_Map`;P3.2 才连接到 `ss_mapNew` + dispatch)| gen_runtime.ss(`emitMapTypeInfo`)/ codegen.ss(`%Map` prepend) | [ ] Planned |
| **P3.2** | **全或无原子大改**:§D.2 `ss_mapNew`→`mi_calloc` ObjHeader + §D.6 全栈 GEP(6 桶 GEP 经 `irMapBucketPtr` / size 512→528 / val_type 516→532 runtime+codegen 6 处)+ §D.4 entry.key `ss_rc_strdup`→`strdup` + §D.5 `emitRetain/ReleaseForType` 加 `isMapType`。任何中间态即崩(§C.9-exec/§C.11「全或无」实证)| gen_rt_map.ss / ir_builder.ss(`irMapBucketPtr`)/ gen_builtins.ss / gen_decls.ss / gen_deserialize.ss / class/class.ss | [ ] Planned |
| **P3.3** | 综合大测 + `Map<嵌套>` / `Set` / Map-as-class-field / `Array<Map>` 验证 + Phase 3 close | 全测 + bootstrap | [ ] Planned |

**子阶段间硬约束**:
- 任一子阶段 bootstrap 失败 → `git reset --soft HEAD^` + 修,不带失败 commit。
- **P3.1 必须 P3.2 前完成**(类型元数据基础设施先于切换,dead-code 隔离 emit 正确性)。
- **P3.2 原子不可再拆** —— `ss_mapNew` alloc 切换、桶/size/val_type GEP、entry.key、dispatch 路由必须同 commit;任何子集单独推进即半迁移崩溃态(§C.9-exec `f21271d` + §C.11 spike 实证)。
- P3.3 必须 P3.1+P3.2 全 GREEN 后启动。

**Phase 3 close 判据**(§D 完成 = Phase 3 全 close):
- bootstrap 三阶段 bit-identical;
- 全测 0 regression(基线 = §C.11 close 的 324/4);
- `grep ss_rc_calloc bootstrap/gen/rt/gen_rt_map.ss` 命中 = 0;
- `@Map_type_info` + `ss_drop_Map` + `%Map = type` IR 命中,`ss_mapNew` 内 `mi_calloc` 命中;
- `emitRetainForType`/`emitReleaseForType` 加 `isMapType` 分支,Map/Set 走 `ss_retain`/`ss_release`;
- §Phase 收关锚 Phase 3 行回写 `[x]`,Phase 4 解锁(`ss_rc_destroy_map` + tag-2 分支等成 dead code 可删)。

---

## §F 远期(本 D 范围外)

| 项 | 内容 | 前置依赖 |
|---|---|---|
| **F1** | Array<int> / Array<double> 等标量元素特化(消除 RC + TypeInfo 头) | Phase 5 完成 + escape analysis spike |
| **F2** | mimalloc REUSE 全编译器范围 audit + 关键热路径手工标注 reuse 槽位 | Phase 5 完成 |
| **F3** | Stack-allocate 短生命周期容器(escape analysis) | Phase 5 + F1 |
| **F4** | RC i32 → i64 升级(若实测溢出) | 实测信号 |

---

## 影响面统计(Phase 0 摸底)

| 维度 | 数值 | 来源 |
|---|---|---|
| 旧系统调用点 | retain 14 行 + release 35 行 = 49 行 | `grep -c "ss_rc_retain\|ss_rc_release" bootstrap/ lib/` |
| 新系统调用点 | retain 11 行 + release 15 行 = 26 行 | `grep -c "ss_retain\|ss_release" bootstrap/` |
| dispatch 入口 | `bootstrap/gen/class/class.ss:140-155` emitRetainForType / emitReleaseForType | 手动 read |
| 旧系统运行时实现 | `bootstrap/gen/gen_runtime.ss:276-498` ss_rc_retain/release/release_no_children/destroy_array_ptrs/destroy_map | 手动 read |
| 新系统运行时实现 | `bootstrap/gen/gen_runtime.ss:510-567` ss_retain/release/alloc/dealloc | 手动 read |
| ObjHeader 类型定义 | `bootstrap/gen/gen_runtime.ss:189-192` `%TypeInfo` + `%ObjHeader` | 手动 read |
| 新系统对象头 GEP 引用 | `bootstrap/gen/gen_type_ops.ss:260-266` rc + TypeInfo 字段写入 | 手动 read |
| PIR liveness 入口 | `bootstrap/pir/pir_opt.ss:11-117` pirLivenessPass + `bootstrap/pir/pir_lower.ss:43-87` block 处理 | Explore agent 报告 |
| lib/ 用户层 ss_rc_* 引用 | 0 行 | `grep -r "ss_rc_" lib/` |
| 编译器 RC 相关源码体量(粗估) | ~1500 行(gen_runtime + gen_type_ops + class + pir_opt + pir_lower) | 手动统计 |

---

## §反模式 / 正模式

### ❌ 反模式
- **L1 名义改名一刀切**:把 `ss_rc_retain` 全 sed 改名 `ss_retain` 而内部仍双轨 — 消耗工程量但零根因,违反 `feedback_root_cause_no_cost`
- **跳过 §未决策 直接进 Phase 1**:ABI 决策错位致全栈 GEP 偏移 / TypeInfo 布局再改一次,违反 H2 + H3 实证
- **Phase 1-5 大爆炸合并**:bootstrap 三阶段固定点失败时无法定位回滚锚点,违反原则 3
- **`feedback_design_no_code_authority` 违反**:把现有 ss_rc_* tag 分派当不变量传到新系统(应从 Perceus 原理 + ObjHeader 重写)

### ✅ 正模式
- **§未决策列空槽**:用户 close 才进 Phase 1,避免方向漂移
- **每 Phase 独立 commit + bootstrap 验证**:固定点失败 reset --soft HEAD^ 仅丢一域
- **PIR 集成留终局**:Phase 5 兑现 30+ 调用点消除的最大长期价值

---

## 参考

- 业界对标:Lean 4 Perceus(Leijen et al. 2021)/ Koka memory management / Swift ARC / Rust `std::rc::Rc<T>`
- axiom 引用:`docs/1-axioms.md:8,10,19` C2 / C4 / V4
- 相关 D 文档:`D164-pir-liveness-helper-fn-loop-class-method-drop.md`(PIR liveness 落地证据)
- 研究报告对话锚:本对话 Phase 0 研究输出(双 RC 系统对照表 + L1-L4 语义层 + 业界对标 + N 年返工度论证)
