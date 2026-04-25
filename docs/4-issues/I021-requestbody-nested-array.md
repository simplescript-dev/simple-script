# I021-requestbody-nested-array:嵌套 `Array<Class>` 反序列化 + lib/json.ss array iter 扩接口

> 父档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层嵌套 user class 字段端到端)
> 祖档:[I021-requestbody.md](./I021-requestbody.md)(commit 8165370 — Phase 4 §247 第二支柱端到端兑现)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody 域含嵌套](../3-decisions/D129-request-param-class-domain.md)

## 问题

I021-requestbody-nested v0(commit b79aa97)端到端兑现单层嵌套 user class **scalar 字段**(`Order { customer: Customer, addr: Address }`),`emitClassDeserializeFn` 在 `bootstrap/gen/gen_deserialize.ss` 已加 `else if (isUserClass(ft) == 1)` 分支(jnGetField + 递归调 `<Nested>_deserialize` + 直接 store transfer ownership)。

I021-requestbody-nested.md line 70 §留下轮锚 1 已声明:"**I021-requestbody-nested-array** — 嵌套 `Array<Class>`(`Order { items: Array<Item> }`)反序列化(涉 lib/json.ss jnArrayLen / jnArrayGet + Array<Class> 字段所有权递归)" — **scope 显式留本子档**。

enterprise REST API 真实业务 `@PostMapping("/orders") createOrder(@RequestBody Order order)` 其中 `Order { items: Array<Item> }` — list resource POST(创建订单含明细行)是 Spring 生态最高频出现形态;SS 现状 codegen 检测到 `Array<Class>` 字段无对应 emit 分支,要么静默生成空数组要么报"@RequestBody 当前不支持 Array/Map 字段"(I021-requestbody.md line 102 父档父档已锚)。

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套 + collection)** + Jackson/Gson 反序列化器 | HTTP body")。

SS 用户写:

```ss
class Item { name: string; price: int }
class Order { customer: string; items: Array<Item> }

@PostMapping("/orders")
function createOrder(@RequestBody order: Order): string {
    let total = 0
    for (let i = 0; i < order.items.length; i = i + 1) {
        total = total + order.items[i].price
    }
    return "customer=" + order.customer + ",total=" + total
}
```

行为 byte-identical Java Spring:

```java
public class Item { String name; int price; }
public class Order { String customer; List<Item> items; }

@PostMapping("/orders")
public String createOrder(@RequestBody Order order) {
    int total = 0;
    for (Item it : order.items) total += it.price;
    return "customer=" + order.customer + ",total=" + total;
}
```

curl `POST /orders -H 'Content-Type: application/json' -d '{"customer":"alice","items":[{"name":"a","price":10},{"name":"b","price":20}]}'` → `customer=alice,total=30`。

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 nested v0 plumbing + lib/json.ss 扩 jnArrayLen / jnArrayGet + emitClassDeserializeFn 加 `Array<Class>` 字段 case**(`else if (isArrayClass(ft) == 1)`):lib 端 jnArrayLen 拿 JsonNode 数组 length;循环 jnArrayGet(node, i) 拿每元素子 nodeId;若元素是 user class → 递归调 `<Item>_deserialize` + ss_array_push_class element-wise;若元素是 primitive → 直接 jnGetInt/Double/String/Bool 分派 | nested v0 plumbing 已就绪零额外设计;Array<T> push 已 [D013 list-append 标准化](../3-decisions/D013-list-append-standardization.md) 含 ss_array_push_class;jnGetField + 子 nodeId 模式与 nested v0 一致;[D018](../3-decisions/D018-object-layout-typeinfo.md) per-class deserializer transitive closure 已 [b79aa97 单遍 BFS](../../bootstrap/gen/gen_deserialize.ss) cover Item;[D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md) ✅ |
| B | 独立 nested array deserializer 模块(`lib/spring/boot/array_deserializer.ss`)桥接 lib/json.ss + per-class deserialize | nested v0 已 plumbed,B 重起独立模块违反「编译器吸收复杂度」+ 双轨制风险 ❌ |
| C | runtime 反射递归遍历 array 元素元数据自动 deserialize | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— nested v0 plumbing 已就绪 + lib/json.ss array iter helper 扩接口 + emitClassDeserializeFn `Array<Class>` 字段 case 落地。

## v0 scope 切分说明(本子档)

**落地**:

- 单层嵌套 `Array<Class>` 字段(`Order { items: Array<Item> }`,Item 是 scalar 字段 user class)
- lib/json.ss 扩 `jnArrayLen(node: int): int` + `jnArrayGet(node: int, index: int): int`(仅声明 + 内部走 lib/json.ss 内部 array repr 分派,具体实现 RED 阶段诊断)
- bootstrap/gen/gen_deserialize.ss `emitClassDeserializeFn` 加 `Array<Class>` 字段 case(类比 b79aa97 user-class 分支)
- per-class deserializer transitive closure 自动覆盖 Item(b79aa97 deserializerTargets BFS 已 cover field types,Array<Item> 字段推入 Item 即可)
- 测试 IR 锚:`grep "@Item_deserialize\|jnArrayLen\|jnArrayGet" /tmp/t_i021_array.ll` ≥ 3
- 全链路 raw HTTP POST `/orders` byte-identical Java oracle

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立):

- **I021-requestbody-nested-array-primitive** — 嵌套 `Array<int>` / `Array<string>` 等 primitive 元素数组(本子档 v0 仅含 `Array<Class>`;primitive 数组走 jnArrayGet + jnGetInt/String 直接路径,scope 留独立子档)
- **I021-requestbody-nested-array-array** — `Array<Array<Class>>` 嵌套数组(2D matrix 类 DTO,涉 RC 双层契约累积)

**v0 scope 不做**:

- 不实现 `Array<int>` / `Array<string>` 等 primitive 元素数组(留 -array-primitive)
- 不实现 `Array<Array<Class>>` 嵌套数组(留 -array-array)
- 不实现 `Map<K, Class>` 嵌套(留 [I021-requestbody-nested-map](./I021-requestbody-nested-map.md))
- 不实现 N>1 层嵌套(留 [I021-requestbody-nested-deep](./I021-requestbody-nested-deep.md))
- 不实现 nullable Array(留 [I021-requestbody-nested-optional](./I021-requestbody-nested-optional.md))
- 不引入新关键字 / 新语法

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   # RED 1: lib/json.ss 无 array iter helper
   grep -cE "^function jnArrayLen|^function jnArrayGet" lib/json.ss
   # before: 0 (或 1,若已部分实现) after: 2
   
   # RED 2: codegen 无 Array<Class> 字段 case
   grep -cE "isArrayClass|Array<.*Class>" bootstrap/gen/gen_deserialize.ss
   # before: 0 after: ≥ 1 (字段类型 dispatch)
   
   # RED 3: 端到端 silent
   bin/ss build tests/phase5/i021_requestbody_nested_array.ss -o /tmp/t_i021_array_red --emit-ir 2>&1 | grep -cE "@Item_deserialize"
   # before: 0 (若漏 closure) 或 RUN 时 items.length = 0 (若 codegen 静默)
   # after: ≥ 2 (define + call)
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss** 加 `class Item` + `class Order { customer: string; items: Array<Item> }` + `@PostMapping("/orders") createOrder(@RequestBody order: Order)`;Java oracle 同步 `examples/spring-parity/hello/java/.../HelloController.java`(注:与 nested v0 已加的 `class Order { customer: Customer, addr: Address }` 命名冲突 → 本子档独立 controller 文件 `OrderListController.ss` 或换 class 名 `OrderList { customer; items: Array<Item> }`,Execute 轮拍板)。

3. **tests/phase5/i021_requestbody_nested_array.ss** 新建 ~120 行 5 case:
   - case 1:单层 `Array<Item>` 字段 length=2 + 元素 scalar 字段访问 `order.items[0].name == "a"`
   - case 2:`Array<Item>` 空数组 `[]` length=0 RC 契约不破裂
   - case 3:`Array<Item>` length=10 大数组 element-wise deserialize(性能 + RC 链不爆栈)
   - case 4:全链路 raw HTTP POST `/orders -d '{"customer":"alice","items":[...]}'`
   - case 5:IR 锚 `grep "@Item_deserialize\|jnArrayLen\|jnArrayGet" /tmp/t_i021_array.ll` ≥ 3

4. **lib/json.ss array iter 扩接口**:

   ```ss
   function jnArrayLen(node: int): int { /* lib/json.ss 内部 array repr length 提取 */ }
   function jnArrayGet(node: int, index: int): int { /* lib/json.ss 内部 array repr element nodeId 提取 */ }
   ```

   具体实现按 lib/json.ss 现状 array node 内部 repr 走(可能已有内部 helper 仅缺导出);RED 阶段 grep 现状 + 诊断决定扩还是 wrap。

5. **bootstrap fix(codegen 主路径)**:

   ```ss
   // bootstrap/gen/gen_deserialize.ss emitClassDeserializeFn 字段循环内
   else if (isArrayClass(ft) == 1) {
       let elemType = arrayElemType(ft)
       // 拿 field 子 nodeId
       let fieldNode = emitJnGetField(parentNode, fieldName)
       // 拿数组 length
       let arrayLen = emitJnArrayLen(fieldNode)
       // 分配 SS Array<elemType>
       let arrayPtr = emitArrayAlloc(elemType, arrayLen)
       // 循环 emit element-wise deserialize + ss_array_push_class
       emitArrayLoop(arrayPtr, arrayLen, fieldNode, elemType)
       // 直接 store(无 retain;子已 transfer ownership)
       emitFieldStore(targetPtr, fieldOffset, arrayPtr)
   }
   ```

   `emitArrayLoop` 内部:循环 `jnArrayGet(fieldNode, i)` 拿子 nodeId → 若 elemType 是 user class 调 `<Class>_deserialize` 拿子 ptr,否则调 jnGetInt/Double/String/Bool primitive helper → ss_array_push_class / ss_array_push_int 等。

6. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。

7. **commit + push**:format `feat(I021-requestbody-nested-array,D123,D129): 嵌套 Array<Class> 反序列化 + lib/json.ss array iter 扩接口 — Phase 4 §247 第二支柱嵌套深化第二轮`。

## 反向 / 备选

(同上候选 A 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-array.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:见 §步骤 §1 RED 命令(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_array.ss` exit 0,5 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders -d '{...,"items":[...]}'` 返 byte-identical Java oracle
- **Execute 轮 after**:`grep "@Item_deserialize\|jnArrayLen\|jnArrayGet" /tmp/t_i021_array.ll` ≥ 3(IR + lib helper 锚)
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions

## 风险 / 表面 / 下轮升根路径

1. **Array<Class> 元素 RC 递归契约严审**(承接 nested.md line 124-128 父档已锚单层嵌套契约):
   - 子 `<Item>_deserialize` 返新分配 ptr(rc=1, mimalloc mi_calloc)
   - element-wise loop:**直接 ss_array_push_class(arrayPtr, itemPtr)** —— 子 deserialize 已一次性 transfer ownership,push 不再 retain
   - `ss_array_push_class` 内部:存 itemPtr 到 array element slot,**不 retain**(对齐 nested v0 字段 store 直接 transfer)
   - 父 `ss_drop_<Outer>` 链:遍历 Array<Item> 字段 emit 逐元素 ss_release —— 自动级联触发 `ss_drop_<Item>` 释放每元素;`ss_drop_<Outer>` 后 free Array 容器
   - **若契约破裂**(push 时 retain → 元素 rc=2,Array drop 后元素 rc=1 leaked)→ Execute 必须严审 `ss_array_push_class` 实现路径

2. **lib/json.ss array iter helper 现状不明**:
   - `jnArrayLen` / `jnArrayGet` 可能已有内部实现仅缺导出,RED 阶段 grep 现状决定扩还是 wrap
   - 若 lib/json.ss array repr 与 SS Array<T> repr 不同(JSON node array vs SS Array<int> 头),helper 必须做转换;Execute 轮深入 `lib/json.ss` 当前 array node 形态后决策

3. **Array<int> / Array<string> primitive 元素留 -array-primitive 子档**:本子档 v0 仅 cover `Array<Class>`(高频 enterprise DTO 场景);primitive 元素数组走 jnArrayGet + jnGetInt/String 直接路径,scope 切分独立子档以聚焦 RC 契约严审

4. **Array<Array<Class>> 嵌套数组留 -array-array 子档**:N=2 数组层 RC 双层契约累积 + 内层 array element drop 链是另一维度复杂度,scope 切分

**Plan 阶段 plumbing 完整**:本子档 Execute 轮无表面遗留,RC 契约严审 + transitive closure(b79aa97 已 cover element class)+ lib/json.ss array iter 扩接口 alignment 编译期展开。

## 触发场景

- 接到 enterprise REST API 业务实现含 list resource POST(`@PostMapping("/orders") order: Order { items: Array<Item> }`)
- D129 §94 "@RequestBody | 任意 class(含嵌套 + collection)" 域语义 collection 维度兑现
- I021-requestbody-nested.md line 70 §留下轮锚 1 承接
- I021-requestbody.md line 116 父档父档显式 backlog "I021-requestbody-array — JSON Array → SS Array<T> 反序列化(`@RequestBody users: Array<User>`)" 部分承接(本子档处理嵌套场景,顶层 `@RequestBody users: Array<User>` 留 I021-requestbody-array 平级独立子档)

## 备注

- 本子档**纯文档起立轮**,Execute 留下下轮(按 §交互式单文档:每轮一目标)
- nested.md line 70 §留下轮锚 1 + line 124-128 父档已锚 RC 契约,本子档承接
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)已 Decided,本子档执行不再辨析
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化第二轮(深化 = collection 维度;首轮 nested.md = 单层 user class 字段维度)
