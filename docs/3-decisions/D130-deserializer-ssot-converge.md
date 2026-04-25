# D130: per-class deserializer SSoT 收敛 — emitDeserializeForType 统一递归

> 上层规则:[D088 §第一性需求 — 编译期展开消除运行时反射](./D088-no-runtime-reflection.md)(若存在,统一引用) + [CLAUDE.md §Root Cause 优先 §第一法则无例外](../../CLAUDE.md)
> 触发:I021-requestbody-nested-map Execute 轮(commit 1473ecd 子档起立)用户洞察 — Jackson 类比反思后发现 codegen 内三轨制独立 dispatch 设计债务

## 核心目标 (Goal)

把 `bootstrap/gen/gen_deserialize.ss` 内**三处独立维护的"from JSON nodeId emit i64 of SS type T"职能**收敛到**单一递归入口 `emitDeserializeForType(ssType, jsonNodeR) -> i64 reg`**,消除三轨制双向(实际三向)同步成本,为 Phase 4 后续 enum / Optional / Tuple / Set 等容器类型扩展留干净扩展点。

## 核心原则 (Principles)

1. **D088 §第一性需求 不可逆** — SS 禁运行时反射,必须编译期展开;Jackson 类比 mismatch(Jackson 走 Java Class<?> runtime reflection)
2. **SSoT** — 同一职能不应有 N 处独立实现;每加新类型 → O(1) 添加(emitDeserializeForType 加 1 case),不再 O(3)
3. **RC 契约不变** — 收敛只是 dispatch 收口,不动 RC 语义(string retain / class transfer / array push 不 retain / map set 不 retain)
4. **嵌套递归终止条件保留** — primitive scalar(int/double/string/bool)是终止 leaf;UserClass 走 `@<C>_deserialize` 终止;容器 Array<X> / Map<K,X> 递归 emitDeserializeForType(X, ...)

## 1. Context Management(上下文管理)

### 必读清单(clear 后 Claude 动手前)

- `bootstrap/gen/gen_deserialize.ss`(本 D 文档主战场 — emitArrayDeserializeInto / emitClassDeserializeFn 字段循环 / 待新加 emitMapDeserializeInto)
- `bootstrap/gen/gen_rc.ss:220-232 extractContainerElemType`(Array<X>/Map<K,V> elem/value 提取 — 已支持两者)
- `bootstrap/gen/class/class.ss:104-129 isUserClass / emitRetainForType / emitReleaseForType`(双 RC 系统统一分派)
- `lib/json.ss:234-302 jnGetField/Int/Double/String/Bool + jnArrayLen/Get/GetInt/GetDouble/GetString/GetBool`(raw int 接口现状)
- `bootstrap/gen/rt/gen_rt_map.ss:69-117 ss_mapNew / ss_mapSet`(Map 容器 API + offset 516 val_type flag 协议)
- `bootstrap/gen/gen_runtime.ss:312-462 ss_rc_release tag-based dispatcher + ss_rc_destroy_map`(双 RC 桥接 — Map<string, Class> drop 链自动级联)
- `bootstrap/gen/gen_decls.ss:653-664`(用户层 `let m: Map<...> = new Map()` val_type=1 自动协议参考)

### 关键代码位置(本 D 文档代码改动锚)

- `bootstrap/gen/gen_deserialize.ss:emitDeserializeForType` (新增,~80 行 7 路 case)
- `bootstrap/gen/gen_deserialize.ss:emitArrayDeserializeInto` (重构 — 删 inner 6 路 dispatch,改委托 emitDeserializeForType)
- `bootstrap/gen/gen_deserialize.ss:emitMapDeserializeInto` (新增,委托 emitDeserializeForType,~50 行)
- `bootstrap/gen/gen_deserialize.ss:emitClassDeserializeFn` 字段循环 (重构 — 删 7 路 dispatch,改委托 emitDeserializeForType + type-aware store)
- `bootstrap/gen/gen_deserialize.ss:emitPendingDeserializers` (扩 BFS Map<K, Class> value 入队,Array<X> BFS 已存在)
- `bootstrap/gen/gen_deserialize.ss:isMapDeserializable` (新增,与 isArrayDeserializable 对称)
- `lib/json.ss:jnObjectKeys` (新增,Object iter raw helper,与 jnArrayLen 对称)

## 2. 问题陈述

### 破裂层 1 — codegen 内三处独立 dispatch 同一职能

| 同一职能(from nodeId emit i64 of type T) | 当前 emit 位置 | 字段类型分派路数 |
|---|---|---|
| OuterClass 字段循环 | `emitClassDeserializeFn` 字段 for-loop body | 7 路(int/double/string/bool/UserClass/Array/Map fallback) |
| Array<elemType> 内层 | `emitArrayDeserializeInto` body 内 dispatch | 6 路(UserClass/int/double/string/bool/Array) |
| Map<string, vType> 内层 | `emitMapDeserializeInto` body 内 dispatch | 1 路(Map<K,Class>;若延续模式需扩同 6 路) |

**双轨制(实际三轨制)证据**:同一个 `if elemType == "int" { emit jnGetInt + sext i64 }` 逻辑在 `emitArrayDeserializeInto`(line 112-116)和 `emitClassDeserializeFn` 字段循环(line 184-187)两处独立写;增加 enum / Optional / Tuple → 三处都要改;commit log 见 a096fd0(Array primitive)+ 5b25573(Array<Array>)+ f301e76(N=3/4/5 多层),每轮都在 emitArrayDeserializeInto 内独立加 case。

### 破裂层 2 — Jackson 类比错位

> Java Spring `@RequestBody Order order` 看起来一行就好,但 Jackson 内部 ~30 个 deserializer types + ~10 factory + ~20 contextual hooks。**只是 runtime 反射 + ObjectMapper facade 包装**。SS D088 §第一性需求 禁运行时反射 → 必须编译期展开 → Jackson runtime 那 30 个 deserializer 的逻辑被 SS 编译期 inline emit 进每个 class 的 IR。

**真问题**不是"步骤多",是 codegen 内**单一职能 N 处分散** — 这才是双轨制根因。

## 3. 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **emitDeserializeForType(ssType, jsonNodeR) -> i64 reg 单一递归入口**:7 路 case(int/double/string/bool/UserClass/Array/Map)统一处理;emitArrayDeserializeInto / emitMapDeserializeInto / emitClassDeserializeFn 字段循环全部委托 emitDeserializeForType 递归调用;每加新类型 O(1) 添加 case | SSoT 单一事实源 ✅;Jackson runtime reflection 编译期等价物 ✅;架构层 refactor 一次到位 ✅(D088 §第一性需求 alignment);新加容器(enum/Optional/Tuple/Set)只需 1 处加 case,扩展成本 O(1) ✅ |
| B | 保留三轨制,只加 Map case 到 emitClassDeserializeFn / emitMapDeserializeInto 各自独立 dispatch | 数据层 patch ❌ — 用户已否决 — 延续设计债复利 |
| C | runtime 反射通用 deserializer(类 Jackson),用 TypeInfo vtable 在 runtime 分派 | 违反 [D088 §第一性需求](./D088-no-runtime-reflection.md) 编译期展开消除运行时反射 ❌ 物理不可达 |

选 **A** — 用户授权"本轮 reset + D 文档 + 重新实施 旧的错误代码直接删除"。

## 4. 决策

### 4.1 emitDeserializeForType 签名

```ss
// 把 JSON nodeId 反序列化为 SS 类型 T,返回 i64 reg name(持反序列化结果)。
// 调用方按 T 类型语义解 i64 → 写入字段槽:
//   - i32 (int/bool):trunc i64 to i32 + store i32
//   - double:bitcast i64 to double + store double
//   - ptr (string/UserClass/Array/Map):inttoptr i64 to ptr + store ptr
// RC 契约:
//   - primitive scalar(int/double/bool):无 ptr 不 retain
//   - string:emitRetainForType(jnGetString/jnAsString 返 jnStr 内部 ptr 未持新 RC)
//   - UserClass:子 @<C>_deserialize 返新分配 ptr rc=1,transfer ownership 不 retain
//   - Array<X>:递归内层 emitDeserializeForType(elemType, jnArrayGet(...))拿 i64 + ss_arrayPush
//                返 final array ptr (新分配 rc=1) transfer
//   - Map<string, X>:ss_mapNew + val_type=1 if X is ptr + jnObjectKeys 循环 +
//                     递归内层 emitDeserializeForType(vType, jnGetField(node, key))拿 i64 +
//                     ss_mapSet(transfer ownership 不 retain)+ keys array 临时 release
function emitDeserializeForType(ssType: string, jsonNodeR: string): string
```

### 4.2 7 路 case(本 D 文档 v0)

| ssType | emit pattern | RC 契约 |
|---|---|---|
| `int` | `jnAsInt(node) -> i32 -> sext i64` | 无 |
| `double` | `jnAsDouble(node) -> double -> bitcast i64` | 无 |
| `string` | `jnAsString(node) -> ptr -> emitRetainForType -> ptrtoint i64` | retain(jnStr 内部 ptr 未持新 RC) |
| `bool` | `jnAsBool(node) -> i32 -> zext i64` | 无 |
| isUserClass(T) | `@T_deserialize(node) -> ptr -> ptrtoint i64` | transfer(子 deserialize rc=1) |
| isArray(T) | `ss_newArray/Ptr(0) + jnArrayLen 循环 + emitDeserializeForType(elemType, jnArrayGet(...)) + ss_arrayPush + return arr ptrtoint i64` | array transfer;elem 由内层 emitDeserializeForType 自身 RC 契约负责 |
| isMap(T) | `ss_mapNew + val_type=1 if vType ptr + jnObjectKeys + 循环 + emitDeserializeForType(vType, jnGetField(node, key)) + ss_mapSet + ss_rc_release(keys) + return map ptrtoint i64` | map transfer;value 由内层 emitDeserializeForType 自身 RC 契约负责;key 由 ss_mapSet 内部 ss_rc_strdup 复制 |

**Default else**:emit `i64 0`(未支持类型,符合 RC 安全的"默认值 fallback");可在未来 emitDeserializeForType 加 case 扩(enum/Optional/Tuple/Set 等)。

### 4.3 emitArrayDeserializeInto 重构

**当前(三轨制)**:emit body 内 6 路 elemType dispatch(UserClass / int / double / string / bool / Array<X>)各自独立 emit 。
**收敛后**:emit body 内**仅** `emitDeserializeForType(elemType, jnArrayGet(arr, idx))` 单一委托;其余 ss_newArrayPtr / ss_newArray + 循环 head/body/end + ss_arrayPush 框架保留(Array 容器自身职能不动)。

### 4.4 emitMapDeserializeInto(新增)

emit body 内**仅** `emitDeserializeForType(vType, jnGetField(map, key))` 单一委托;ss_mapNew + val_type=1 + jnObjectKeys + 循环 + ss_mapSet + ss_rc_release(keys array) 框架。

### 4.5 emitClassDeserializeFn 字段循环重构

**当前(三轨制)**:字段 for-loop body 内 7 路 ft dispatch(int/double/string/bool/UserClass/Array/Map fallback)。
**收敛后**:字段 for-loop body 内:

```ss
// 拿子 nodeId(字段 == 顶层字段查 jnGetField)
const childNodeR = nextReg()
emitIR(`  ${childNodeR} = call i32 @jnGetField(i32 %nodeId.arg, ptr ${keyConst})`)
// 委托 emitDeserializeForType 拿 i64 reg
const valI64R = emitDeserializeForType(ft, childNodeR)
// type-aware store(int → trunc store i32;double → bitcast store double;ptr → inttoptr store ptr)
emitFieldStoreI64(dstR, ft, valI64R)
```

⚠️ 关键差异:**primitive scalar 字段当前走 `jnGetInt/Double/String/Bool` raw helper**(直接 by-key 拿 i32/double/ptr),收敛后走 `jnGetField` 拿 nodeId 再 `jnAs*`(by-nodeId 解析)。两条路径 lib/json.ss 都已存在(jnAs* 见 JsonNode 类方法 `asInt/asDouble/asString/asBool`)— 收敛后 emit 多 1 个 i32 reg 但语义 byte-identical。**性能影响**:每字段多 1 次 jnGetField 间接 — 微秒级不计成本(与 SSoT 收敛带来的扩展性收益相比可忽略)。

### 4.6 isMapDeserializable + emitPendingDeserializers BFS Map<K,Class> 入队

```ss
function isMapDeserializable(ft: string): int {
    if (ft.startsWith("Map<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const vt = extractContainerElemType(ft)
    if (isUserClass(vt) == 1) { return 1 }
    return 0
}
```

emitPendingDeserializers BFS 字段扫描扩 Map<K, Class> value class 入队,与 Array<UserClass> BFS 同模式(line 53-66 沿用)。

### 4.7 lib/json.ss jnObjectKeys

```ss
function jnObjectKeys(node: int): Array<string> {
    let keys: Array<string> = []
    if (node <= 0) { return keys }
    const fieldList = jnStr.getString(`${node}`)
    if (fieldList == "") { return keys }
    let remaining = fieldList
    while (remaining != "") {
        let entry = remaining
        const ci = remaining.indexOf(",")
        if (ci >= 0) {
            entry = remaining.substring(0, ci)
            remaining = remaining.substring(ci + 1, remaining.length() - ci - 1)
        } else {
            remaining = ""
        }
        const colonIdx = entry.indexOf(":")
        if (colonIdx >= 0) {
            keys = keys.push(entry.substring(0, colonIdx))
        }
    }
    return keys
}
```

复用既有 `jnGetField(nodeId, key)` 拿 value 子 nodeId(不新增 jnObjectGet 别名 — 语义重合避免双轨制)。

## 5. RC 契约保留(收敛不动语义)

| 类型 T | RC 契约(收敛前) | RC 契约(收敛后,emitDeserializeForType 内承载) |
|---|---|---|
| int / double / bool | 无(primitive scalar) | 无 ✅ |
| string | jnGetString/jnArrayGetString 后 emitRetainForType | jnAsString 后 emitRetainForType ✅ |
| UserClass | @<C>_deserialize 返 rc=1 transfer | @<C>_deserialize 返 rc=1 transfer ✅ |
| Array<X> | ss_newArray/Ptr + ss_arrayPush + 内层 elem RC | 同 — 内层 RC 由递归 emitDeserializeForType(elemType, ...) 自身负责 ✅ |
| Map<string, X> | ss_mapNew + val_type=1 + ss_mapSet + ss_rc_release(keys) + 内层 value RC | 同 — 内层 RC 由递归 emitDeserializeForType(vType, ...) 自身负责 ✅ |

**双 RC 系统桥接**(D018 + D022)不变:`ss_rc_release` 是统一 dispatcher,user class tag>=10 走 ss_class_dtor → ss_drop_<C>;Map tag=2 走 ss_rc_destroy_map 内部逐 entry release ptr value → 自动级联 ss_drop_<C>。

## 6. 反向 / 备选

(见 §3 候选路径 — B/C 否决)

## 7. 单一判据 验证

### RED 命令(收敛前 全 = 0)

- `grep -cE "^function emitDeserializeForType" bootstrap/gen/gen_deserialize.ss` = 0(after = 1)
- `grep -cE "isMapDeserializable|emitMapDeserializeInto" bootstrap/gen/gen_deserialize.ss` = 0(after ≥ 2)
- `grep -cE "^function jnObjectKeys" lib/json.ss` = 0(after = 1)

### GREEN 验收(收敛后)

- bootstrap 三阶段固定点 PASS(stage2 == stage3)
- reflection_health_linter GATE PASS no regressions
- `bin/ss run tests/phase5/i021_requestbody_nested_map.ss` 4 case 全 PASS
- `bin/ss test tests/phase5/` 无 regression(对比 baseline 5 fail / nested_map 加 1 → 4 fail 总数,每 fail 与本 D 文档 codegen 无关,实测 pre-existing baseline 同样 fail 名单)
- 全套 phase4/5 无 regression(对比 commit f301e76 baseline)
- IR 锚:`grep "@Tag_deserialize\|jnObjectKeys" /tmp/t_i021_map.ll` ≥ 2
- spring-parity HelloController.ss /orders/meta byte-identical Java oracle
- **SSoT 收敛物理证据**:`grep -cE "if .ft == \\\"int\\\".|if .elemType == \\\"int\\\"." bootstrap/gen/gen_deserialize.ss` 收敛后只 1 处(在 emitDeserializeForType 内),非 2 处(emitArrayDeserializeInto + emitClassDeserializeFn 字段循环各 1 处)

## 8. 影响

### 代码改动范围

| 文件 | 改动类型 | 行数估计 |
|---|---|---|
| `docs/3-decisions/D130-deserializer-ssot-converge.md` | 新增(本 D 文档) | ~250 行 |
| `bootstrap/gen/gen_deserialize.ss` | 新增 emitDeserializeForType + isMapDeserializable + emitMapDeserializeInto + 重构 emitArrayDeserializeInto + 重构 emitClassDeserializeFn 字段循环 + 扩 emitPendingDeserializers BFS | 净 +50 / -40,总函数 +3,旧 inner dispatch 减 |
| `lib/json.ss` | 新增 jnObjectKeys | +24 行 |
| `tests/phase5/i021_requestbody_nested_map.ss` | 新增(承接 I021-requestbody-nested-map 子档 §步骤) | ~80 行 5 case |
| `examples/spring-parity/hello/ss/HelloController.ss` | 加 Tag/OrderMeta DTO + @PostMapping("/orders/meta") | +20 行 |
| `examples/spring-parity/hello/java/src/main/java/hello/HelloController.java` | Java oracle 对称 | +20 行 |

### 后续 issue 自动开启 / 简化

- `I021-requestbody-nested-map-primitive`:emitDeserializeForType vType=primitive 路径自动 cover Map<string, int|string|double|bool>;v0 测试 scope 仅 Map<string, Class>,primitive value 测试归 -primitive 子档独立 RED → GREEN
- `I021-requestbody-nested-map-typed-key`(留)— Map<int|UUID, X> 非 string key 涉编译期 cast,emitDeserializeForType 不自动 cover,留独立子档
- 后续 enum / Optional / Tuple / Set:emitDeserializeForType 加 1 case,O(1) 扩展 — 不再 O(3)

### Phase 4 §247 第二支柱嵌套深化

承接 I021-requestbody-nested-map 子档 §步骤(commit 1473ecd 起立),本 D 文档 + Implementation 一并落地:

- collection 维度 第一支柱 Array(已 commit a096fd0/5b25573/f301e76)
- collection 维度 第二支柱 Map(本轮)
- nested 嵌套 user class 字段(已 commit b79aa97)

后续 -primitive / -typed-key / -array (Map<string, Array<Class>>) / -optional 等子档 ROI 需在 emitDeserializeForType 收敛之后重新评估(可能多个被 emitDeserializeForType 自然 cover 不需独立子档)。

## 9. 备注

- **触发事件**:2026-04-25 commit 1473ecd(I021-requestbody-nested-map 子档起立)Execute 轮中,用户中断 baseline regression 验证后 Jackson 类比反思,洞察 codegen 内三轨制 — 推迟 nested-map 子档 Execute 实施,先起本 D 文档锁收敛设计,本 D 文档与 nested-map Implementation 同轮落地(Decision + Implementation 双层)
- **Layer 跨越**:用户明确授权"本轮 reset + D 文档 + 重新实施" → Decision + Implementation 同轮合理(MNK §字段 8 例外)
- **本 D 文档 status**:Decided + Done at `bootstrap/gen/gen_deserialize.ss:emitDeserializeForType + emitArrayDeserializeInto重构 + emitMapDeserializeInto + emitClassDeserializeFn 字段循环重构`(本 D 文档与 codegen 落地同轮 commit)
- **不变量保留**:RC 双系统 ss_retain/ss_release vs ss_rc_retain/ss_rc_release(D018 + D022)+ TypeInfo @<C>_type_info 布局 + per-class deserializer 编译期生成(D088)+ transitive closure BFS(b79aa97 模式)
- **回头观察点**:enum / Optional<X> / Tuple<X, Y> 加 emitDeserializeForType case 时,RC 契约和"从 nodeId 取 SS 类型"语义是否需要 D 文档级别再讨论(预期否,nominal 加 case 即可)
