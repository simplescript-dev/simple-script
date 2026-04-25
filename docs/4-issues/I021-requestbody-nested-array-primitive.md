# I021-requestbody-nested-array-primitive:嵌套 `Array<int>` / `Array<string>` / `Array<double>` / `Array<bool>` primitive 元素数组反序列化

> 父档:[I021-requestbody-nested-array.md](./I021-requestbody-nested-array.md)(commit c3361c9 — `Array<UserClass>` 元素反序列化 + lib/json array iter raw helper + arr[i].field 类型推断根因修)
> 祖档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层嵌套 user class scalar 字段端到端)
> 祖祖档:[I021-requestbody.md](./I021-requestbody.md)(commit 8165370 — Phase 4 §247 第二支柱端到端兑现)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody V=class 域含嵌套+collection](../3-decisions/D129-request-param-class-domain.md)

## 问题

I021-requestbody-nested-array v0(commit c3361c9)端到端兑现单层嵌套 `Array<UserClass>` 元素反序列化(`OrderList { customer: string; items: Array<Item> }`,Item 是 scalar 字段 user class)。`emitClassDeserializeFn` 在 `bootstrap/gen/gen_deserialize.ss:121-173` 已加 `else if (isArrayClass(ft) == 1)` 分支:`jnGetField → jnArrayLen → ss_newArrayPtr → loop:jnArrayGet → <ElemClass>_deserialize → ptrtoint i64 → ss_arrayPush`,无 retain transfer ownership。

但 `isArrayClass()` 谓词在 `bootstrap/gen/gen_deserialize.ss:18-21` **仅识别 user class 元素**:

```ss
function isArrayClass(ft: string): int {
    if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
    return isUserClass(extractContainerElemType(ft))  // ← primitive 元素返 0
}
```

故 `Array<int>` / `Array<string>` / `Array<double>` / `Array<bool>` 字段 falls through 到 `else` 默认 fallback(line 174-186):`store ptr null`,与 Java Spring `List<String>/Integer/Double/Boolean` 行为 **byte-divergence**。

I021-requestbody-nested-array.md line 74 §留下轮锚 1 已声明:"**I021-requestbody-nested-array-primitive** — 嵌套 `Array<int>` / `Array<string>` 等 primitive 元素数组(本子档 v0 仅含 `Array<Class>`;primitive 数组走 jnArrayGet + jnGetInt/String 直接路径,scope 留独立子档)" — **scope 显式留本子档**。

enterprise REST API 真实业务 `@RequestBody Order { tags: Array<string>, scores: Array<int>, prices: Array<double>, flags: Array<bool> }` — primitive 数组字段是 collection 维度真子集,Spring `List<String>/Integer/Double/Boolean` 99% enterprise DTO 业务覆盖(tags/categories/labels/scores 等)。SS 现状 codegen 检测到 primitive `Array<T>` 字段静默 store null,运行时 `order.tags.length() == 0` 即使 JSON `{"tags":["a","b","c"]}`。

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套 + collection)** + Jackson/Gson 反序列化器 | HTTP body")。

SS 用户写:

```ss
class Order {
    customer: string
    tags: Array<string>
    scores: Array<int>
    prices: Array<double>
    flags: Array<bool>
}

@PostMapping("/orders-prim")
function createOrderPrim(@RequestBody order: Order): string {
    let tagSum = ""
    for (let i = 0; i < order.tags.length; i = i + 1) { tagSum = tagSum + order.tags[i] }
    let scoreSum = 0
    for (let i = 0; i < order.scores.length; i = i + 1) { scoreSum = scoreSum + order.scores[i] }
    return "tags=" + tagSum + ",scores=" + scoreSum
}
```

行为 byte-identical Java Spring:

```java
public class Order {
    String customer;
    List<String> tags;
    List<Integer> scores;
    List<Double> prices;
    List<Boolean> flags;
}

@PostMapping("/orders-prim")
public String createOrderPrim(@RequestBody Order order) {
    String tagSum = "";
    for (String t : order.tags) tagSum += t;
    int scoreSum = 0;
    for (Integer s : order.scores) scoreSum += s;
    return "tags=" + tagSum + ",scores=" + scoreSum;
}
```

curl `POST /orders-prim -H 'Content-Type: application/json' -d '{"customer":"alice","tags":["a","b","c"],"scores":[10,20,30],"prices":[1.5,2.5],"flags":[true,false]}'` → `tags=abc,scores=60`。

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 nested-array v0 plumbing + lib/json.ss 扩 4 个 element-wise primitive helper(`jnArrayGetInt` / `jnArrayGetString` / `jnArrayGetDouble` / `jnArrayGetBool`)+ `isArrayClass` 谓词扩 primitive elemType 识别 + `emitClassDeserializeFn` Array 分支按 elemType 分派 IR**:nested-array v0 已 plumbed `jnArrayLen` / `jnArrayGet`(返子 nodeId,user class 走 `<Class>_deserialize`);primitive 元素**复用** `jnArrayGet` 拿 elem nodeId + 调 lib/json 内部 primitive 解码(parseInt/parseDouble/jnStr),但 codegen 直接 emit `call i32 @jnArrayGetInt(i32 arrNode, i32 idx)` 等 raw helper(避免 wrap parseInt 调用链);分派表 elemType→{ ss_newArray vs ss_newArrayPtr 选择 + jnArrayGet*类型 + push 前 zext/bitcast/ptrtoint } 编译期固定 | nested-array v0 plumbing 100% 复用零结构变;`ss_arrayPush(ptr, i64)` 单签家族已 D013 list-append 标准化 cover 所有 primitive(zext i32→i64 / bitcast double→i64 / ptrtoint ptr→i64);`ss_newArray` (tag=1) + `ss_newArrayPtr` (tag=5) 二分恰好对齐 primitive 三种 family(int/double/bool 用 tag=1 不 retain;string 用 tag=5 retain);transitive closure 不需扩(primitive elemType 不递归入 deserializerTargets);`emitFieldReleaseLoop` 已走 Array<X> drop 路径(gen_type_ops.ss:172,与 Array<UserClass> 同模式,内部 tag 决定逐元素 ss_release);[D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md) ✅ |
| B | 不扩 lib/json.ss helper,codegen 直接 emit jnArrayGet 拿 nodeId + 链调 jnGetField+parseInt 双层 wrap | jnGetField 是 object key 接口不接 array idx,走错语义层;codegen IR 复杂度上升(emit 多步链式 call)且与 nested-array v0 raw helper 模式不对称 ❌ |
| C | 在 lib/json.ss 加单一 `jnArrayGetPrimitive(arrNode, idx): int` 返 elem nodeId,codegen 调 parseInt/parseDouble/jnStr.getString 解码 | 仍需 codegen 知道 elemType 分派(parseInt vs parseDouble),拆 helper 是 helper 层 vs codegen 层职责切分,不简化反多一层间接;raw helper 与 codegen emit 直对接是 nested v0 + nested-array v0 已锁模式,本子档对齐避免双轨 ❌ |
| D | runtime 反射递归遍历 array 元素元数据自动 deserialize | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— nested-array v0 plumbing 100% 复用 + lib/json.ss 扩 4 primitive raw helper + `isArrayClass` 扩 primitive 识别 + `emitClassDeserializeFn` 分派表落地。

## v0 scope 切分说明(本子档)

**落地**:

- 单层 primitive 元素数组字段:`Array<int>` / `Array<string>` / `Array<double>` / `Array<bool>` 4 个 elemType 全 cover
- lib/json.ss 扩 4 个 raw helper:
  ```ss
  function jnArrayGetInt(arrNode: int, idx: int): int     // parseInt(jnInt.getString(elemNodeId))
  function jnArrayGetString(arrNode: int, idx: int): string // jnStr.getString(elemNodeId)
  function jnArrayGetDouble(arrNode: int, idx: int): double // parseDouble(jnInt.getString(elemNodeId))
  function jnArrayGetBool(arrNode: int, idx: int): int     // parseInt(jnInt.getString(elemNodeId)) — 0/1
  ```
  内部委托 `jnArrayGet(arrNode, idx)` 拿 elem nodeId 后按 elem nodeId 检索 jnInt / jnStr Map(SSoT 收敛 helper:`jnArrayGetInternalDecode(arrStr, idx, elemKind): string` 抽 jnArrayElemAt + parseXxx 公共),具体抽多少 SSoT helper Execute 轮 simplify 阶段决定
- bootstrap/gen/gen_deserialize.ss:
  - `isArrayClass` 谓词扩(改名 `isArrayDeserializable` 或保 `isArrayClass` 加 `isPrimitiveType(elemType)==1` 分支)— Execute 轮拍板(若 grep 发现 `isArrayClass` 仅 deserialize 内部用 + 改名 LOC 收敛 ≤ 5,改名;否则保名扩谓词)
  - Array 分支按 elemType 分派 4 路 IR
- per-class deserializer transitive closure 不需扩(primitive elemType 不入 `deserializerTargets`)
- 测试 IR 锚:`grep -E "@jnArrayGetInt\|@jnArrayGetString\|@jnArrayGetDouble\|@jnArrayGetBool\|ss_newArray\b" /tmp/t_i021_array_prim.ll` ≥ 5(4 helper call + ss_newArray tag=1 用)
- 全链路 raw HTTP POST `/orders-prim` byte-identical Java oracle

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立或承接):

- **I021-requestbody-nested-array-array** — `Array<Array<Class>>` / `Array<Array<int>>` 嵌套数组(2D matrix 类 DTO,涉 RC 双层契约累积 + 内层 array element drop 链)
- (其他 backlog 见 nested-array.md §留下轮 + I021-requestbody.md §backlog 区)

**v0 scope 不做**:

- 不实现 `Array<Array<...>>` 嵌套数组(留 -array-array)
- 不实现 `Map<K, primitive>` —— **已被 [D124 typed Map](../3-decisions/D124-typed-map-value-cast.md) cover**(typed Map<K,int/double/string/bool>.get value cast lowering 已落地 b79aa97 之前 commit cdec730 + 825710c 系列),@RequestBody Map<K,V> 字段反序列化路径独立留 [I021-requestbody-nested-map](./I021-requestbody-nested-map.md) 处理
- 不实现 N>1 层嵌套 primitive 数组(留 [I021-requestbody-nested-deep](./I021-requestbody-nested-deep.md))
- 不实现 nullable `Array<int>?` / `Array<string>?` 空安全(留 [I021-requestbody-nested-optional](./I021-requestbody-nested-optional.md) + D067 null safety narrow)
- 不实现顶层 `@RequestBody scores: Array<int>`(留 I021-requestbody-array 平级独立子档,本子档 scope 限"嵌套字段")
- 不引入新关键字 / 新语法

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   # RED 1: lib/json.ss 无 primitive array elem helper
   grep -cE "^function jnArrayGetInt|^function jnArrayGetString|^function jnArrayGetDouble|^function jnArrayGetBool" lib/json.ss
   # before: 0  after: 4

   # RED 2: codegen Array 分支只识别 user class elemType
   grep -nE "isArrayClass|isPrimitiveType.*Array|elemType.*int|elemType.*string" bootstrap/gen/gen_deserialize.ss
   # before: 仅 isArrayClass 谓词调 isUserClass(line 20) + Array<UserClass> 分支(line 121)
   # after: + primitive elemType 4 路分派 IR(line ~ 121-173 区扩支)

   # RED 3: 端到端 silent
   bin/ss build tests/phase5/i021_requestbody_nested_array_primitive.ss -o /tmp/t_i021_array_prim_red --emit-ir 2>&1 | grep -cE "@jnArrayGetInt|@jnArrayGetString|@jnArrayGetDouble|@jnArrayGetBool"
   # before: 0(全 fallback store null)  after: ≥ 4(每 elemType 一 helper)
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss** 加 `class OrderPrim { customer: string; tags: Array<string>; scores: Array<int>; prices: Array<double>; flags: Array<bool> }` + `@PostMapping("/orders-prim") createOrderPrim(@RequestBody order: OrderPrim)`;Java oracle 同步 `examples/spring-parity/hello/java/.../HelloController.java`(注:与 c3361c9 落地的 `class Order` / `class OrderList` 命名独立,不冲突)。

3. **tests/phase5/i021_requestbody_nested_array_primitive.ss** 新建 ~150 行 7 case:
   - case 1:`Array<string>` length=3 + 元素相加 `tags[0]+tags[1]+tags[2] == "abc"`
   - case 2:`Array<int>` length=3 + 元素求和 `scores[0]+scores[1]+scores[2] == 60`
   - case 3:`Array<double>` length=2 + 元素求和 `prices[0]+prices[1] == 4.0`
   - case 4:`Array<bool>` length=2 + 元素逻辑 `flags[0] == 1 && flags[1] == 0`
   - case 5:`Array<int>` 空数组 `[]` length=0 RC 契约不破裂(int 元素无 RC,但 ss_newArray tag=1 容器仍要 free)
   - case 6:`Array<string>` 空数组 `[]` length=0 RC 契约不破裂(string 元素 RC tag=5 但 length=0,容器 free 不触发 elem release)
   - case 7:全链路 raw HTTP POST `/orders-prim -d '{"customer":"alice","tags":["a","b","c"],"scores":[10,20,30],...}'`
   - IR 锚 `grep -E "@jnArrayGetInt\|@jnArrayGetString\|@jnArrayGetDouble\|@jnArrayGetBool\|ss_newArray" /tmp/t_i021_array_prim.ll` ≥ 6(4 primitive helper + ss_newArray tag=1 + ss_newArrayPtr tag=5)

4. **lib/json.ss primitive array helper 扩**(具体内部委托走 jnArrayElemAt + parseInt/parseDouble/jnStr 现有路径,不重复实现 array repr 解析):

   ```ss
   function jnArrayGetInt(arrNode: int, idx: int): int {
       if (arrNode <= 0) { return 0 }
       const elemId = jnArrayGet(arrNode, idx)
       if (elemId <= 0) { return 0 }
       return parseInt(jnInt.getString(`${elemId}`))
   }
   function jnArrayGetDouble(arrNode: int, idx: int): double { /* parseDouble(jnInt.getString) */ }
   function jnArrayGetString(arrNode: int, idx: int): string { /* jnStr.getString */ }
   function jnArrayGetBool(arrNode: int, idx: int): int     { /* parseInt — 0/1 */ }
   ```

   注:`jnInt.getString` 同时承载 int / double / bool primitive 字面量(lib/json.ss 内部 parsePrimitive 走 jnInt Map);Execute 轮 grep 现状确认是否需细分 jnIntStr / jnDoubleStr / jnBoolStr Map(若 lib/json 现状已细分则直接用,否则保 jnInt 单 Map 不动)。

5. **bootstrap fix(codegen 主路径)**:

   ```ss
   // bootstrap/gen/gen_deserialize.ss isArrayClass 谓词扩(option a:谓词分支)
   function isArrayDeserializable(ft: string): int {
       if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
       const et = extractContainerElemType(ft)
       if (isUserClass(et) == 1) { return 1 }
       if (et == "int" || et == "string" || et == "double" || et == "bool") { return 1 }
       return 0
   }

   // emitClassDeserializeFn Array 分支扩 elemType 分派
   } else if (isArrayDeserializable(ft) == 1) {
       const elemType = extractContainerElemType(ft)
       const arrNodeR = nextReg()
       emitIR(`  ${arrNodeR} = call i32 @jnGetField(i32 %nodeId.arg, ptr ${keyConst})`)
       const arrLenR = nextReg()
       emitIR(`  ${arrLenR} = call i32 @jnArrayLen(i32 ${arrNodeR})`)
       const initArrR = nextReg()
       // tag=1 for int/double/bool(不 retain),tag=5 for string/UserClass(retain)
       const newArrFn = (elemType == "string" || isUserClass(elemType) == 1) ? "ss_newArrayPtr" : "ss_newArray"
       emitIR(`  ${initArrR} = call ptr @${newArrFn}(i32 0)`)
       // ... loop head ...
       // body: 按 elemType 分派 4+1 路
       if (isUserClass(elemType) == 1) {
           // c3361c9 落地路径(<Class>_deserialize → ptrtoint → ss_arrayPush)
       } else if (elemType == "int") {
           emitIR(`  ${valR} = call i32 @jnArrayGetInt(i32 ${arrNodeR}, i32 ${idxR})`)
           emitIR(`  ${val64R} = sext i32 ${valR} to i64`)
           emitIR(`  ${newArrR} = call ptr @ss_arrayPush(ptr ${curArrR}, i64 ${val64R})`)
       } else if (elemType == "double") {
           emitIR(`  ${valR} = call double @jnArrayGetDouble(i32 ${arrNodeR}, i32 ${idxR})`)
           emitIR(`  ${val64R} = bitcast double ${valR} to i64`)
           emitIR(`  ${newArrR} = call ptr @ss_arrayPush(ptr ${curArrR}, i64 ${val64R})`)
       } else if (elemType == "string") {
           emitIR(`  ${valR} = call ptr @jnArrayGetString(i32 ${arrNodeR}, i32 ${idxR})`)
           // string 必须 retain(对照 emitClassDeserializeFn line 99-104:jnGetString 返 jnStr 内部 ptr 未持新 RC)
           emitRetainForType(valR, elemType)
           emitIR(`  ${val64R} = ptrtoint ptr ${valR} to i64`)
           emitIR(`  ${newArrR} = call ptr @ss_arrayPush(ptr ${curArrR}, i64 ${val64R})`)
       } else if (elemType == "bool") {
           emitIR(`  ${valR} = call i32 @jnArrayGetBool(i32 ${arrNodeR}, i32 ${idxR})`)
           emitIR(`  ${val64R} = zext i32 ${valR} to i64`)
           emitIR(`  ${newArrR} = call ptr @ss_arrayPush(ptr ${curArrR}, i64 ${val64R})`)
       }
       // ... loop end + final store ...
   }
   ```

6. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。重点:
   - reuse:`isArrayClass`→`isArrayDeserializable` 改名是否破坏外部调用(grep 现状判)
   - quality:elemType 分派 4 路 if-else 链是否可读 vs 抽 emitArrayElemDeserialize(arrNodeR, elemType, idxR) 单一函数(可读 vs reuse 权衡,可读 veto 抽函数当且仅当不损失可读性)
   - efficiency:loop body 内 4 路分派编译期已固定(elemType 是 compile-time 常量),不是运行时分支
   - readability:每路 IR emit 顺序对齐(call → cast → push)无 case 错位

7. **commit + push**:format `feat(I021-requestbody-nested-array-primitive,D123,D129): primitive 元素数组反序列化(int/string/double/bool)+ lib/json 扩 4 raw helper + codegen Array 分支 elemType 分派 — Phase 4 §247 第二支柱嵌套深化第三轮`。

## 反向 / 备选

(同上候选 A 评估表 — B/C/D 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-array-primitive.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:见 §步骤 §1 RED 命令(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_array_primitive.ss` exit 0,7 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders-prim -d '{...primitive arrays...}'` 返 byte-identical Java oracle
- **Execute 轮 after**:`grep -E "@jnArrayGetInt|@jnArrayGetString|@jnArrayGetDouble|@jnArrayGetBool|ss_newArray" /tmp/t_i021_array_prim.ll` ≥ 6
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS(predict no F1 regression — gen_deserialize.ss 当前在 baseline 容量内,4 路分派 ~ 60 LOC 增量,Execute 轮 commit message §扩容申报段对账;若超 baseline 走反射路径根因 gate B 路径)

## 风险 / 表面 / 下轮升根路径

1. **Array<string> RC retain 契约严审**(承接 nested.md line 124-128 + nested-array.md line 163-168 父档已锚契约):
   - `jnArrayGetString` 返 jnStr 内部 ptr 未持新 RC(对照 `jnGetString` 同模式,gen_deserialize.ss line 99-104 锚)
   - element-wise loop:**push 前必 retain**(`emitRetainForType(valR, "string")`)— 否则父 ss_drop_<Outer> 链遍历 Array<string> 字段 emit 逐元素 ss_release_str 时 free jnStr 仍持有的 ptr → 下一个 POST use-after-free
   - 父 ss_drop_<Outer> 链:`emitFieldReleaseLoop` Array<string> 字段 release 路径走 ss_array_release_with_drop(ptr arr, i32 elem_kind),内部 tag=5 触发逐元素 ss_release_str + free 容器(与 nested-array.md line 167-168 Array<UserClass> drop 链同模式但 elem_kind 走 string 路径)
   - **若契约破裂**(push 时不 retain → array 持非拥有 ref / free 时 double-free)→ Execute 必须严审 `emitRetainForType` 是否在 elemType=="string" 分支上调用 + 对应 `emitClassDeserializeFn` line 99-104 的双重一致性

2. **Array<int> / Array<double> / Array<bool> 直接 store 无 RC**:
   - tag=1 容器(`ss_newArray`)逐元素是 i64 stored 不 retain;`ss_drop_<Outer>` 链 Array<int> 字段 release 仅 free 容器(elem_kind 走 primitive 路径,无 elem release 调用)
   - **风险**:若 tag=1/tag=5 选择错位(int 用 ss_newArrayPtr → drop 时 elem_kind 误判 ptr 触发 invalid ss_release_str(int 值)崩)→ Execute 严审 `newArrFn` 选择条件 `(elemType == "string" || isUserClass(elemType) == 1)` 完整覆盖 vs Array<int>/double/bool 全走 ss_newArray
   - bool 是 i32 → zext i64,double 是 bitcast i64;**位宽对齐**:`ss_arrayPush(ptr, i64)` 单签强制所有 push 是 i64,int 走 sext / bool 走 zext / double 走 bitcast / ptr 走 ptrtoint;Execute 轮 IR emit 顺序必须严按 elemType 分派,绝不串味(int 用 zext 反而符号位丢 / double 用 ptrtoint 完全乱)

3. **`isArrayClass` 谓词改名 vs 保名扩 — Execute 轮拍板**:
   - 改名 `isArrayDeserializable`:语义更准(谓词不仅识别 user class,还含 primitive 可反序列化);LOC delta = grep `isArrayClass` 出现次数 × 2(replace_all)
   - 保名 `isArrayClass` + 内部扩 primitive 分支:语义不准(名仍含 "Class")但 LOC delta 最小
   - **决策依据**:Execute 轮先 grep `isArrayClass` 调用次数;若 ≤ 3 处 → 改名;若 > 3 处 → 保名扩(仅 deserialize 内部用则改名零成本)

4. **lib/json.ss `jnArrayGetInt` 内部 parseInt 缓存语义不明**:
   - `jnInt.getString(elemId)` 返 elem 文本表示("42" / "3.14" / "true" / "1"),需 parseInt / parseDouble 解码
   - 若 lib/json 解析时已把 primitive 数值预解码为 int 值再 toString,parseInt 是无谓往返(性能小幅损);若仅存原始字符串 token,parseInt 是真解码
   - **下轮升根路径**(若性能成 bottleneck):lib/json 内部增 jnIntVal Map(int 值预解码缓存)+ jnArrayGetInt 直查 jnIntVal,避开字符串往返;**v0 scope 不做**(性能优化,基本路径先打通)

5. **空数组 RC 契约不破裂**:
   - `Array<string>` 空数组 length=0:ss_newArrayPtr(i32 0) 容器分配 tag=5 但 element data 为空,父 drop 链不触发 elem release(loop 0 iter)→ 安全
   - `Array<int>` 空数组 length=0:ss_newArray(i32 0) tag=1 容器同理
   - **edge case**:JSON 字段缺失(非空数组,而是字段不存在)→ `jnGetField` 返 0 → `jnArrayLen(0)` 返 0(`if (node <= 0) { return 0 }`,lib/json.ss line 336),loop 0 iter 后 store empty array;v0 scope **接受 fallback empty array**(对齐 primitive 字段缺失 fallback 默认值);严格"字段缺失 4xx"留 I021-requestbody-validation 子档

**Plan 阶段 plumbing 完整**:本子档 Execute 轮无表面遗留,RC 契约严审(string retain + int/double/bool 直接 store)+ tag 选择对齐(tag=1 vs tag=5 双族)+ 位宽对齐(sext / zext / bitcast / ptrtoint)+ lib/json raw helper 路径与 nested-array v0 模式同构。

## 触发场景

- 接到 enterprise REST API 业务实现含 primitive 数组字段(`@RequestBody Order { tags: Array<string>, scores: Array<int> }`)
- D129 §94 "@RequestBody | 任意 class(含嵌套 + collection)" 域语义 collection 维度 primitive elemType 兑现
- I021-requestbody-nested-array.md line 74 §留下轮锚 1 承接(c3361c9 留下轮锚 — 本子档承载第三轮)
- I021-requestbody.md line 116 父档父档显式 backlog "I021-requestbody-array — JSON Array → SS Array<T>" 部分承接(本子档处理嵌套 primitive 数组,顶层 `@RequestBody scores: Array<int>` 留 I021-requestbody-array 平级独立子档)

## 备注

- 本子档**纯文档起立轮**,Execute 留下下轮(按 §交互式单文档:每轮一目标)
- nested-array.md line 74 §留下轮锚 1 + line 163-174 父档已锚 RC 契约 / lib/json array iter / 留下轮锚配伍,本子档承接
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)已 Decided,本子档执行不再辨析
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化第三轮(深化 = collection 维度 primitive elemType;首轮 nested.md = 单层 user class 字段 / 第二轮 nested-array.md = collection user class elem / 第三轮本子档 = collection primitive elem)
- 本子档 LOC ~ 250(单子档完整),与同级 nested-array.md (~ 200) / nested-deep.md / nested-map.md / nested-optional.md 量级对齐
