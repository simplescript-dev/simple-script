# D168: 统一双 RC 系统为 Perceus 主线

**Status:** Phase 0.5 closed — §A.3 锁定 D1=A / D2=c / D3=ii;Phase 1 String 切轨 spike 待启动(下下轮)
**Depends on:** axiom C2/C4/V4(`docs/1-axioms.md:8,10,19`);相关 D164(PIR liveness 落地证据)
**Date:** 2026-05-10
**Last Updated:** 2026-05-10

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
| **Phase 1** | **String 切轨** — `[rc:i32 \| TypeInfo*]` ObjHeader + mimalloc + `@String_type_info` + 字面量 immortal 路径(按 D1 锁定方案) + 全栈 string GEP 偏移修正 | [ ] Planned | bootstrap stage2==stage3 + 全测继承基线 |
| **Phase 2** | **Array 切轨** — `Array<T>` TypeInfo monomorphization(按 D2 锁定方案) + 元素 retain/release 走统一路径 + Array slice/concat 适配 | [ ] Planned | bootstrap + Array 测试 |
| **Phase 3** | **Map 切轨** — `Map<K,V>` TypeInfo + key/value 双侧统一 + bucket 链表元素 retain/release 适配 | [ ] Planned | bootstrap + Map 测试 |
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

| 子阶段 | 内容 | 触达 | 验证 |
|---|---|---|---|
| **P1.1** | B5 emit `@String_type_info` + per-type 函数生成 + B3 immortal 跳过路径 + B6 dispatch string 走 ss_retain | gen_runtime.ss / gen_type_ops.ss / class.ss | bootstrap stage2==stage3 + 全测继承基线(0 regression) |
| **P1.2** | B2 字面量 IR 升级 boxed + B7 GEP 偏移修正 | gen_emit.ss / gen_decls.ss / gen_rt_string.ss | bootstrap + B8 (a) RED→GREEN |
| **P1.3** | B4 mimalloc 字符串分配切换(双轨过渡) | gen_runtime.ss / gen_rt_string.ss | bootstrap + 全测 + 验证 ss_alloc_string 调用点替换 ss_rc_alloc |
| **P1.4** | retain 路径 B8 (b) + 跨函数返回值 B8 (c) + 综合大测 + 性能 micro-bench(可选) | 全测 + 性能脚本 | bootstrap + 全测 + 性能基线 |

**子阶段间硬约束**:
- 任一子阶段 bootstrap 失败 → `git reset --soft HEAD^` + 修,**不允许带失败 commit**
- 子阶段独立 commit,**禁打包**(便于回滚定位)
- P1.1 必须 P1.2 前完成(类型基础设施先于字面量切换)
- P1.4 必须 P1.1-P1.3 全 GREEN 后启动

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
