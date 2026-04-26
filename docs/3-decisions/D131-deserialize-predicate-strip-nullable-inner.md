# D131: isArrayDeserializable / isMapDeserializable 谓词 inner type 识别保留 nullable —— 容器内层 `?` 后缀 stripNullableCG bug 修

> 上层规则:[D130 §SSoT 收敛](./D130-deserializer-ssot-converge.md) + [D067 null safety 概念锚](../../bootstrap/checker/check_narrow.ss)(memory `project_null_safety_design.md` SSoT) + [CLAUDE.md §Root Cause 优先 §第一法则无例外](../../CLAUDE.md)
> 触发:I021-requestbody-nested-optional-inner Execute 阶段 emit-ir 实测 D130 SSoT 自动 cover 假设破裂(commit c68d443 子档 Plan 起立 §风险 1 + §风险 2 升根触发)

## 1. 触发证据

I021-requestbody-nested-optional-inner Plan 起立(commit c68d443)子档 §假设链:`Array<Tag?>` 字段类型 → stripNullableCG 不变 → isArrayDeserializable case → emitArrayDeserializeInto inner 递归调 emitDeserializeForType(`Tag?`, ...) → commit 29c3148 nullable case 触发。

**Execute 阶段第一步实测验证(D130 SSoT 自动 cover 假设破裂检测义务)**:

```bash
# 实测源 /tmp/t_optional_inner.ss(class Tag + class OrderTagsArr { tags: Array<Tag?> } + @PostMapping)
bin/ss build /tmp/t_optional_inner.ss --emit-ir -o /tmp/t.ll > /tmp/t.ll 2>&1
grep -cE '@jnIsNullOrMissing' /tmp/t.ll  # = 1(仅 lib/json.ss 函数定义,反序列化路径 0 处)
grep -cE 'opt_present|opt_done' /tmp/t.ll  # = 0(nullable case 完全未触发)
```

**OrderTagsArr_deserialize body emit IR**(`/tmp/t.ll:11445-11450`):
```llvm
%6 = getelementptr %OrderTagsArr, ptr %new, i32 0, i32 3   ; tags 字段
%7 = call i32 @jnGetField(i32 %nodeId.arg, ptr @.str.421)
%8 = add i64 0, 0          ; ← emitDeserializeForType fallback(line 163-165)
%9 = inttoptr i64 %8 to ptr
store ptr %9, ptr %6, align 8  ; → store ptr null,完全丢弃 tags 字段数据
```

**OrderTagsMap_deserialize body** items 字段同样走 fallback `add i64 0, 0`(`/tmp/t.ll:11467-11471`)。

**假设破裂物理证据**:emitDeserializeForType 在字段层就走 fallback 路径(根本进不到 emitArrayDeserializeInto / emitMapDeserializeInto),nullable case 复用链断在更上游谓词层。

## 2. 根因定位

### 2.1 调用链反向追踪

字段 `tags: Array<Tag?>` 反序列化 emit 路径:

```
emitClassDeserializeFn 字段循环(gen_deserialize.ss:307-313)
├── ft = classFieldTypes.getString("OrderTagsArr.tags") = "Array<Tag?>"
│   └── ✓ class_register.ss:109 stripNullableCG 只 strip 字段顶层 `?` 不递归 strip inner
├── classFieldNullable["OrderTagsArr.tags"] == 0(顶层非 nullable)→ ft 不加 `?`
└── 委托 emitDeserializeForType("Array<Tag?>", childNodeR)

emitDeserializeForType("Array<Tag?>", ...) 入口(gen_deserialize.ss:90)
├── stripNullableCG("Array<Tag?>") = "Array<Tag?>"(末尾 `>` 不是 `?`)→ stripped == ssType → 不走 nullable case
├── ssType != "int|double|string|bool"
├── isUserClass("Array<Tag?>") = 0(classFields 注册 "OrderTagsArr"/"Tag" 不含 `Array<...>`)
├── isArrayDeserializable("Array<Tag?>"):
│   ├── startsWith("Array<") = 1, endsWith(">") = 1 ✓
│   ├── et = extractContainerElemType("Array<Tag?>") = "Tag?"   ← 内层正确保留 `?`
│   ├── isUserClass("Tag?") = 0   ← ❌ classFields.has("Tag?") = 0(注册的是 "Tag")
│   ├── isArrayDeserializable("Tag?") = 0
│   ├── isMapDeserializable("Tag?") = 0
│   ├── et != "int|double|string|bool"
│   └── 返回 0 ❌
├── isMapDeserializable("Array<Tag?>") = 0
└── fallback(line 163-165): emit `add i64 0, 0`(默认值占位)
```

### 2.2 根因物理位置

**`bootstrap/gen/gen_deserialize.ss:12-23 isArrayDeserializable`**:

```ss
function isArrayDeserializable(ft: string): int {
    if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const et = extractContainerElemType(ft)
    if (isUserClass(et) == 1) { return 1 }              // ❌ et = "Tag?" 含 nullable 后缀,isUserClass 不识别
    if (isArrayDeserializable(et) == 1) { return 1 }
    if (isMapDeserializable(et) == 1) { return 1 }
    if (et == "int" || et == "double" || et == "string" || et == "bool") { return 1 }
    return 0
}
```

**`bootstrap/gen/gen_deserialize.ss:25-34 isMapDeserializable`**:

```ss
function isMapDeserializable(ft: string): int {
    if (ft.startsWith("Map<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const vt = extractContainerElemType(ft)
    if (isUserClass(vt) == 1) { return 1 }              // ❌ vt = "Tag?" 同根因
    if (isArrayDeserializable(vt) == 1) { return 1 }
    if (isMapDeserializable(vt) == 1) { return 1 }
    if (vt == "int" || vt == "double" || vt == "string" || vt == "bool") { return 1 }
    return 0
}
```

**根因**:谓词在 inner et / vt 类型识别时未对其做 `stripNullableCG`,导致带 nullable inner 的容器(`Array<Tag?>` / `Map<string, Tag?>`)在容器谓词判定阶段就被误判为"不可反序列化"。

### 2.3 子档预案诊断方向 vs 实际根因位置

I021-requestbody-nested-optional-inner 子档 §风险 1+2 预案诊断:**emitArrayDeserializeInto / emitMapDeserializeInto 内 elemType / vType 透传 strip `?` bug**。

实测发现:**方向对(都属 inner type pass-through 层)但物理位置在更上游谓词层** —— `isArrayDeserializable` / `isMapDeserializable` 谓词层 et/vt 类型识别先判,emitArrayDeserializeInto / emitMapDeserializeInto 内透传(extractContainerElemType + emitDeserializeForType 递归)实际正确保留 `?` 后缀(line 174+199 / 222+254 验证),但根本进不到 emitArrayDeserializeInto/emitMapDeserializeInto。

D131 修法物理位置:谓词层 `isArrayDeserializable` / `isMapDeserializable` 加 stripNullableCG。

## 3. 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **谓词层 stripNullableCG inner et/vt** —— `isArrayDeserializable` / `isMapDeserializable` 在递归判 et/vt 前做 `stripNullableCG`,使 "Tag?" 识别为 "Tag" 后走 isUserClass = 1 路径返回 1;emitDeserializeForType 字段层正确 dispatch 到 emitArrayDeserializeInto → inner 递归 emitDeserializeForType(et="Tag?", ...) → commit 29c3148 nullable case 触发 → @jnIsNullOrMissing + opt_present/opt_done labels emit | **根因方案** ✅ — 谓词层修(D130 SSoT 单点) + 复用 emitDeserializeForType nullable case 主路径 + extractContainerElemType + 透传保留 `?` 后缀的既有正确实现;新增容器 inner nullable 维度自动 cover(`Array<Array<Tag?>>` / `Map<string, Array<Tag?>>` 等递归层级);RC 契约不变(emitDeserializeForType nullable case 走 alloca slot + jnIsNullOrMissing + 委托 stripped 路径) ✅ |
| B | 给 emitArrayDeserializeInto / emitMapDeserializeInto 内独立加 nullable inner 处理 | 违反 D130 SSoT(per-class deserializer 单点解码,inner 递归委托主路径);引入并行 codegen 路径致维护双轨 ❌(子档 §风险 1 已锚禁止) |
| C | classFieldTypes 注册阶段递归 stripNullableCG inner | 谓词识别阶段就 strip 掉 inner `?` 后缀 → emitDeserializeForType 字段层失去 nullable 元数据 → null element 走 ss_<C>_deserialize segfault(因为 _deserialize 不处理 null jsonNode)❌ —— inner nullable 元数据**必须保留**到 emitDeserializeForType 递归调到 inner element 那一层才能触发 nullable case |

选 **A** —— 谓词层 stripNullableCG + 复用 D130 SSoT emitDeserializeForType nullable case + extractContainerElemType inner 透传保留 `?` 既有实现。

## 4. 决策

### 4.1 isArrayDeserializable 修

```ss
function isArrayDeserializable(ft: string): int {
    if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const et = extractContainerElemType(ft)
    const etStripped = stripNullableCG(et)               // ← 新增:strip inner nullable
    if (isUserClass(etStripped) == 1) { return 1 }
    if (isArrayDeserializable(etStripped) == 1) { return 1 }
    if (isMapDeserializable(etStripped) == 1) { return 1 }
    if (etStripped == "int" || etStripped == "double" || etStripped == "string" || etStripped == "bool") { return 1 }
    return 0
}
```

### 4.2 isMapDeserializable 修

```ss
function isMapDeserializable(ft: string): int {
    if (ft.startsWith("Map<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const vt = extractContainerElemType(ft)
    const vtStripped = stripNullableCG(vt)               // ← 新增:strip inner nullable
    if (isUserClass(vtStripped) == 1) { return 1 }
    if (isArrayDeserializable(vtStripped) == 1) { return 1 }
    if (isMapDeserializable(vtStripped) == 1) { return 1 }
    if (vtStripped == "int" || vtStripped == "double" || vtStripped == "string" || vtStripped == "bool") { return 1 }
    return 0
}
```

### 4.3 emitArrayDeserializeInto / emitMapDeserializeInto 不动

extractContainerElemType("Array<Tag?>") = "Tag?" 既有正确返回(`bootstrap/gen/gen_rc.ss:220-232`);emitDeserializeForType(elemType="Tag?", ...) 透传至 line 199 / 254 既有正确实现;nullable case 复用 commit 29c3148 加的 alloca slot + jnIsNullOrMissing + opt_present/opt_done labels 主路径。

### 4.4 emitPendingDeserializers BFS 字段扫描

`emitPendingDeserializers`(gen_deserialize.ss:41-)BFS 字段扫描需配合 stripNullableCG —— 待 Execute 阶段实测决定是否需要扩(若 `class Outer { tags: Array<Tag?> }` 字段扫描未把 Tag 入队 → 需补)。

## 5. RC 契约保留(D131 修不动 RC 语义)

| 类型 T | RC 契约(D131 修前) | RC 契约(D131 修后) |
|---|---|---|
| `Array<Tag?>` 字段 | fallback `add i64 0, 0` → store ptr null(数据丢弃) | emitArrayDeserializeInto + inner emitDeserializeForType(Tag?) → null element store ptr null;非 null element 走 ss_Tag_deserialize transfer ✓ |
| `Map<string, Tag?>` 字段 | fallback `add i64 0, 0` → store ptr null(数据丢弃) | emitMapDeserializeInto + inner emitDeserializeForType(Tag?) → null value store ptr null;非 null value 走 ss_Tag_deserialize transfer ✓ |
| element ss_release(ptr null) | n/a(数据丢弃) | ss_release 自带 isnull guard(D018 + D023 + 父档 commit 29c3148 §风险 1 实测同源)→ ptr null 不触发 mi_free ✓ |

双 RC 系统(D018 + D022)/ Map drop 链(ss_rc_destroy_map → ss_release ptr null 自动 isnull guard 跳过)/ TypeInfo vtable 不变。

## 6. 验证

### RED 命令(D131 修前 全 = 0 或 fallback)

- `bin/ss build /tmp/t_optional_inner.ss --emit-ir -o /tmp/t.ll > /tmp/t.ll && grep -cE '@jnIsNullOrMissing' /tmp/t.ll` = 1(仅 lib 函数定义)
- `grep -cE 'opt_present\|opt_done' /tmp/t.ll` = 0
- `grep -nA 5 'OrderTagsArr_deserialize' /tmp/t.ll | grep -c 'add i64 0, 0'` ≥ 1(fallback emit)

### GREEN 验收(D131 修后)

- `bin/ss build /tmp/t_optional_inner.ss --emit-ir -o /tmp/t.ll > /tmp/t.ll && grep -cE '@jnIsNullOrMissing' /tmp/t.ll` ≥ 3(1 lib 函数定义 + Array element 路径 + Map value 路径)
- `grep -cE 'opt_present\|opt_done' /tmp/t.ll` ≥ 4(每个 nullable inner emit 至少 1 对 label)
- `grep -nA 30 'OrderTagsArr_deserialize' /tmp/t.ll | grep -c 'jnArrayLen\|arr_loop'` ≥ 1(emitArrayDeserializeInto 触发)
- `grep -nA 30 'OrderTagsMap_deserialize' /tmp/t.ll | grep -c 'jnObjectKeys\|map_loop'` ≥ 1(emitMapDeserializeInto 触发)
- `bin/ss test tests/phase5/i021_requestbody_nested_optional_inner.ss` 7 case 全 PASS(测试源在 D131 GREEN 阶段同轮新建)
- bootstrap 三阶段固定点 PASS(stage2 == stage3)
- reflection_health_linter GATE PASS no regressions
- 全套 phase4/5 无 regression(对比 commit c68d443 baseline)

## 7. 影响

### 代码改动范围

| 文件 | 改动类型 | 行数估计 |
|---|---|---|
| `docs/3-decisions/D131-deserialize-predicate-strip-nullable-inner.md` | 新增(本 D 文档) | ~190 行 |
| `bootstrap/gen/gen_deserialize.ss` isArrayDeserializable / isMapDeserializable | 谓词内 stripNullableCG inner | +2 行 / 函数 |
| `tests/phase5/i021_requestbody_nested_optional_inner.ss` | 新增 7 case | ~140 行 |
| `examples/spring-parity/hello/ss/HelloController.ss` | 加 Tag/OrderTagsArr/OrderTagsMap DTO + @PostMapping | +20 行 |
| `examples/spring-parity/hello/java/.../HelloController.java` | Java oracle 对称 | +20 行 |

### 后续 issue 自动 cover

- I021-requestbody-nested-optional-inner v0(本 D131 GREEN 后 Execute 阶段 ship)— 7 case + spring-parity + RC stress 50 次循环
- I021-requestbody-nested-optional-container(留 — 容器自身 nullable `Array<Tag>?` / `Map<string,Tag>?` ptr null 路径,完全不同 codegen 逻辑)
- I021-requestbody-nested-deep-optional(留 — N=2 双层 nullable `Array<Array<Tag?>>` / `Map<string, Map<string,Tag?>>`,本 D131 修后 stripNullableCG inner 递归自动 cover N=2,实测验证留 -deep-optional 子档)
- I021-requestbody-nested-optional-inner-primitive(留 — `Array<int?>` / `Map<string,int?>` nullable primitive boxing 涉独立 codegen 路径)

### Phase 4 §247 第二支柱嵌套深化第八轮

承接 commit c68d443(I021-requestbody-nested-optional-inner Plan 起立 + D130 SSoT 假设预审 + D131 风险锚)→ 本 D131 D 文档 + I021-requestbody-nested-optional-inner Execute 阶段 codegen 落地 + 测试 + spring-parity 同轮 commit。

### D130 SSoT 设计意图回观

D130 §SSoT 收敛假设"per-class deserializer 单点 emitDeserializeForType inner 委托零 codegen 改动"在 commit c52e9b5/95eb282/b18850e(Map<string, Class>/Map<string, primitive>/笛卡尔积)三轮自动 cover 兑现,但**容器 inner nullable 维度**揭露**谓词层 inner type 识别盲点** —— D131 修后 D130 SSoT 真正全维度 cover(后续 enum / Optional<T> / Tuple 等容器嵌套类型 inner 维度自动验证 stripNullableCG 谓词层不漏)。

## 8. 反向 / 备选

(见 §3 候选路径 — B/C 否决)

## 9. 备注

- **触发事件**:2026-04-26 I021-requestbody-nested-optional-inner Execute 阶段第一步 emit-ir 实测(子档 §风险 1+2 升根触发);本 D131 D 文档 + 子档 Execute 同轮落地(Decision + Implementation 双层 — 子档 §风险 2 锚明跨 Layer Decision,本 D131 D 文档承载 Decision 层,子档 Execute 阶段承载 Implementation 层,**本轮先 D 文档 + next_prompt,Execute 留下轮**)
- **Layer 跨越**:D131 D 文档 = Decision 层,本轮单 Layer 写 D 文档 + 不主动改 codegen / 测试(避免单轮 Layer 混 — feedback `feedback_interactive_one_doc.md` + MNK §字段 8)
- **本 D 文档 status**:Decided(2026-04-26 谓词层 stripNullableCG inner 修方案锁定);Done at <bootstrap/gen/gen_deserialize.ss:isArrayDeserializable + isMapDeserializable + emitPendingDeserializers BFS>(待 Execute 阶段下轮兑现)
- **不变量保留**:D018 ObjectLayout(RC@0 + TypeInfo@1) + D022 clone 语义 + D088 编译期展开消除运行时反射 + D130 emitDeserializeForType SSoT 单点解码 + D067 null safety T? 概念锚(memory `project_null_safety_design.md`) + commit 29c3148 emitDeserializeForType nullable case alloca slot + jnIsNullOrMissing + opt_present/opt_done labels 主路径
- **回头观察点**:
  - emitPendingDeserializers BFS 字段扫描是否需配合 stripNullableCG inner(若 `class Outer { tags: Array<Tag?> }` BFS 未把 Tag 入队 → 需补)— Execute 阶段实测决定
  - `Array<Tag?>?` 容器自身 + inner 双层 nullable(留 I021-requestbody-nested-optional-container 子档,本 D131 不 cover 双层 nullable 仅 cover inner 单层)
  - 后续 enum / Optional<T> / Tuple<X, Y> 加 emitDeserializeForType case 时,谓词层 isXxxDeserializable 是否需对称加 stripNullableCG inner(预期是 — 本 D131 修法成模版可复制)
