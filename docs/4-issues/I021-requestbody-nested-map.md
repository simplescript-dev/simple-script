# I021-requestbody-nested-map:嵌套 `Map<K, Class>` 反序列化 + lib/json.ss object iter 扩接口

> 父档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层嵌套 user class 字段端到端)
> 祖档:[I021-requestbody.md](./I021-requestbody.md)(commit 8165370 — Phase 4 §247 第二支柱端到端兑现)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody 域含嵌套](../3-decisions/D129-request-param-class-domain.md)

## 问题

I021-requestbody-nested v0(commit b79aa97)端到端兑现单层嵌套 user class scalar 字段;[I021-requestbody-nested-array](./I021-requestbody-nested-array.md) 兑现 collection 维度第一支柱(`Array<Class>`)。

I021-requestbody-nested.md line 71 §留下轮锚 2 已声明:"**I021-requestbody-nested-map** — 嵌套 `Map<K, Class>`(`Order { metadata: Map<string, Tag> }`)反序列化" — **scope 显式留本子档**。

enterprise REST API 真实业务下一阶硬需求:Spring 典型形态 `@PostMapping("/orders") createOrder(@RequestBody Order order)` 其中 `Order { customer: string, metadata: Map<string, Tag> }` —— 元数据 / 标签 / 自定义键值对 是 enterprise DTO 高频形态(如 K8s ConfigMap、Stripe metadata、AWS tags);SS 现状 codegen 检测到 `Map<K, Class>` 字段无对应 emit 分支,要么静默生成空 Map 要么报"@RequestBody 当前不支持 Array/Map 字段"(I021-requestbody.md line 102 父档父档已锚)。

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套 + collection)** + Jackson/Gson 反序列化器 | HTTP body")。

SS 用户写:

```ss
class Tag { color: string; priority: int }
class Order { customer: string; metadata: Map<string, Tag> }

@PostMapping("/orders")
function createOrder(@RequestBody order: Order): string {
    let urgent = order.metadata.get("urgent")
    if (urgent != null) {
        return "customer=" + order.customer + ",urgent.color=" + urgent.color
    }
    return "customer=" + order.customer
}
```

行为 byte-identical Java Spring:

```java
public class Tag { String color; int priority; }
public class Order { String customer; Map<String, Tag> metadata; }

@PostMapping("/orders")
public String createOrder(@RequestBody Order order) {
    Tag urgent = order.metadata.get("urgent");
    if (urgent != null) {
        return "customer=" + order.customer + ",urgent.color=" + urgent.color;
    }
    return "customer=" + order.customer;
}
```

curl `POST /orders -H 'Content-Type: application/json' -d '{"customer":"alice","metadata":{"urgent":{"color":"red","priority":1}}}'` → `customer=alice,urgent.color=red`。

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 nested v0 plumbing + lib/json.ss 扩 jnObjectKeys / jnObjectGet + emitClassDeserializeFn 加 `Map<K, Class>` 字段 case**(`else if (isMapClass(ft) == 1)`):lib 端 jnObjectKeys 拿 JsonNode object 所有 key 数组;循环 jnObjectGet(node, key) 拿每 value 子 nodeId;若 value 是 user class → 递归调 `<Tag>_deserialize` + ss_map_set_class element-wise;若 value 是 primitive → 直接 jnGetInt/Double/String/Bool 分派 | nested v0 plumbing 已就绪零额外设计;Map<K,V> 容器已就绪;jnGetField 模式扩展到 jnObjectKeys / jnObjectGet 与 lib/json.ss 现有内部 dict repr 一致;[D018](../3-decisions/D018-object-layout-typeinfo.md) per-class deserializer transitive closure 自动覆盖 Tag(b79aa97 BFS);[D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md) ✅ |
| B | 独立 nested map deserializer 模块(`lib/spring/boot/map_deserializer.ss`)桥接 lib/json.ss + per-class deserialize | nested v0 已 plumbed,B 重起独立模块违反「编译器吸收复杂度」+ 双轨制风险 ❌ |
| C | runtime 反射递归遍历 map entries 元数据自动 deserialize | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— nested v0 plumbing 已就绪 + lib/json.ss object iter helper 扩接口 + emitClassDeserializeFn `Map<K, Class>` 字段 case 落地。

## v0 scope 切分说明(本子档)

**落地**:

- 单层嵌套 `Map<string, Class>` 字段(`Order { metadata: Map<string, Tag> }`,Tag 是 scalar 字段 user class)
- key 类型限 `string`(JSON object key 标准形态;非 string key 走 -map-typed-key 子档)
- lib/json.ss 扩 `jnObjectKeys(node: int): Array<string>` + `jnObjectGet(node: int, key: string): int`(具体实现 RED 阶段诊断 lib 现状)
- bootstrap/gen/gen_deserialize.ss `emitClassDeserializeFn` 加 `Map<string, Class>` 字段 case(类比 nested-array element-wise loop,但走 jnObjectKeys 遍历)
- per-class deserializer transitive closure 自动覆盖 Tag(b79aa97 deserializerTargets BFS)
- 测试 IR 锚:`grep "@Tag_deserialize\|jnObjectKeys\|jnObjectGet" /tmp/t_i021_map.ll` ≥ 3
- 全链路 raw HTTP POST `/orders` byte-identical Java oracle

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立):

- **I021-requestbody-nested-map-typed-key** — `Map<int, Class>` / `Map<UUID, Class>` 等非 string key 反序列化(JSON object key 始终 string,需编译期 string→K cast,涉 [D034 tuple-types](../3-decisions/D034-tuple-types.md) / typed K cast 路径)
- **I021-requestbody-nested-map-primitive** — `Map<string, int>` / `Map<string, string>` primitive value(本子档 v0 仅 `Map<K, Class>`;primitive value 走 jnGetInt/String 直接路径)

**v0 scope 不做**:

- 不实现 `Map<int, Class>` / `Map<UUID, Class>` 等非 string key(留 -map-typed-key)
- 不实现 `Map<string, int>` / `Map<string, string>` primitive value(留 -map-primitive)
- 不实现 `Map<string, Array<Class>>` 嵌套(留 -map-array,涉 RC 三层契约累积)
- 不实现 N>1 层嵌套 Map(留 [I021-requestbody-nested-deep](./I021-requestbody-nested-deep.md))
- 不实现 nullable Map(留 [I021-requestbody-nested-optional](./I021-requestbody-nested-optional.md))
- 不引入新关键字 / 新语法

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   # RED 1: lib/json.ss 无 object iter helper
   grep -cE "^function jnObjectKeys|^function jnObjectGet" lib/json.ss
   # before: 0 (或 1,若已部分实现) after: 2
   
   # RED 2: codegen 无 Map<K, Class> 字段 case
   grep -cE "isMapClass|Map<.*Class>" bootstrap/gen/gen_deserialize.ss
   # before: 0 after: ≥ 1 (字段类型 dispatch)
   
   # RED 3: 端到端 silent
   bin/ss build tests/phase5/i021_requestbody_nested_map.ss -o /tmp/t_i021_map_red --emit-ir 2>&1 | grep -cE "@Tag_deserialize"
   # before: 0 (若漏 closure) 或 RUN 时 metadata.size = 0 (若 codegen 静默)
   # after: ≥ 2 (define + call)
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss** 加 `class Tag` + `class OrderMeta { customer: string; metadata: Map<string, Tag> }` + `@PostMapping("/orders/meta") createOrderMeta(@RequestBody order: OrderMeta)`(注:与 nested v0 已加的 `class Order` 命名隔离 → 用 `OrderMeta` 或 `OrderTagged` 区分);Java oracle 同步 `examples/spring-parity/hello/java/.../HelloController.java`。

3. **tests/phase5/i021_requestbody_nested_map.ss** 新建 ~120 行 5 case:
   - case 1:单层 `Map<string, Tag>` 字段含 1 entry + value scalar 字段访问 `order.metadata.get("urgent").color == "red"`
   - case 2:`Map<string, Tag>` 空对象 `{}` size=0 RC 契约不破裂
   - case 3:`Map<string, Tag>` 含 5 entries 大 map element-wise deserialize(性能 + RC 链不爆栈)
   - case 4:全链路 raw HTTP POST `/orders/meta -d '{"customer":"alice","metadata":{...}}'`
   - case 5:IR 锚 `grep "@Tag_deserialize\|jnObjectKeys\|jnObjectGet" /tmp/t_i021_map.ll` ≥ 3

4. **lib/json.ss object iter 扩接口**:

   ```ss
   function jnObjectKeys(node: int): Array<string> { /* lib/json.ss 内部 dict repr keys 提取 */ }
   function jnObjectGet(node: int, key: string): int { /* lib/json.ss 内部 dict repr value nodeId 提取(已存在 jnGetField 是同义?统一抑或并存 RED 诊断决定)*/ }
   ```

   注:`jnGetField` 已存在(b79aa97 nested 走 jnGetField),`jnObjectGet` 与之语义重合;Execute 轮诊断:复用 jnGetField 还是新增 jnObjectGet 别名 / 是否合并。

5. **bootstrap fix(codegen 主路径)**:

   ```ss
   // bootstrap/gen/gen_deserialize.ss emitClassDeserializeFn 字段循环内
   else if (isMapClass(ft) == 1) {
       let kType = mapKeyType(ft)
       let vType = mapValueType(ft)
       // 拿 field 子 nodeId
       let fieldNode = emitJnGetField(parentNode, fieldName)
       // 拿所有 keys
       let keysArr = emitJnObjectKeys(fieldNode)
       let keysLen = emitArrayLen(keysArr)
       // 分配 SS Map<kType, vType>
       let mapPtr = emitMapAlloc(kType, vType)
       // 循环 emit entry-wise deserialize + ss_map_set_class
       emitMapLoop(mapPtr, keysArr, keysLen, fieldNode, vType)
       // 直接 store(无 retain;子已 transfer ownership)
       emitFieldStore(targetPtr, fieldOffset, mapPtr)
   }
   ```

   `emitMapLoop` 内部:循环拿 key = keysArr[i],valueNode = jnObjectGet(fieldNode, key) → 若 vType 是 user class 调 `<Tag>_deserialize` 拿子 ptr,否则 primitive helper → ss_map_set_class(mapPtr, key, valuePtr) / ss_map_set_int 等。

6. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。

7. **commit + push**:format `feat(I021-requestbody-nested-map,D123,D129): 嵌套 Map<string, Class> 反序列化 + lib/json.ss object iter 扩接口 — Phase 4 §247 第二支柱嵌套深化第三轮`。

## 反向 / 备选

(同上候选 A 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-map.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:见 §步骤 §1 RED 命令(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_map.ss` exit 0,5 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders/meta -d '{...,"metadata":{...}}'` 返 byte-identical Java oracle
- **Execute 轮 after**:`grep "@Tag_deserialize\|jnObjectKeys\|jnObjectGet" /tmp/t_i021_map.ll` ≥ 3(IR + lib helper 锚)
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions

## 风险 / 表面 / 下轮升根路径

1. **Map<string, Class> entry RC 递归契约严审**(承接 nested.md line 124-128 父档已锚 + nested-array.md §风险 1 同模式):
   - 子 `<Tag>_deserialize` 返新分配 ptr(rc=1, mimalloc mi_calloc)
   - entry-wise loop:**直接 ss_map_set_class(mapPtr, key, valuePtr)** —— 子 deserialize 已一次性 transfer ownership,set 不再 retain
   - `ss_map_set_class` 内部:存 valuePtr 到 entry value slot,**不 retain**(对齐 nested v0 字段 store 直接 transfer)
   - 父 `ss_drop_<Outer>` 链:遍历 Map<string, Tag> 字段 emit 逐 entry value ss_release —— 自动级联触发 `ss_drop_<Tag>` 释放每 value;`ss_drop_<Outer>` 后 free Map 容器
   - **若契约破裂**(set 时 retain → entry value rc=2,Map drop 后 value rc=1 leaked)→ Execute 必须严审 `ss_map_set_class` 实现路径
   - **key string 所有权**:JSON key string 由 lib/json.ss 内部 ownership 管理,Map 存 key 时是否 share / clone 由 D022 clone 语义决定;Execute 轮严审 lib/json.ss key 返回是 const ptr 还是 transferred ptr

2. **lib/json.ss object iter helper 现状**:
   - `jnGetField` 已存在(b79aa97 nested 走 jnGetField),`jnObjectGet` 与之语义重合 → Execute 轮诊断复用还是新增别名
   - `jnObjectKeys` 可能不存在(b79aa97 nested 走静态字段名 hardcode,无需遍历 keys);Map 反序列化必须遍历 → 必须扩
   - 若 lib/json.ss object 内部 repr 不暴露 keys 数组,需扩内部 helper 提取(可能涉及 lib/json.ss 内部数据结构改动)

3. **Map<int, Class> / Map<UUID, Class> 等非 string key 留 -map-typed-key 子档**:JSON object key 始终 string,反序列化必须编译期 string→K cast(int parse / UUID parse 等),涉 typed K cast 路径独立复杂度

4. **Map<string, primitive> 留 -map-primitive 子档**:本子档 v0 仅 cover `Map<K, Class>`(高频 enterprise DTO 场景);primitive value 走 jnGetInt/String 直接路径,scope 切分

5. **Map<string, Array<Class>> 三层嵌套留 -map-array 子档**:N=3 容器层 RC 三层契约累积,scope 切分

**Plan 阶段 plumbing 完整**:本子档 Execute 轮无表面遗留,RC 契约严审 + transitive closure(b79aa97 已 cover value class)+ lib/json.ss object iter 扩接口 alignment 编译期展开。

## 触发场景

- 接到 enterprise REST API 业务实现含 metadata / tags / 自定义键值对 DTO(`@PostMapping("/orders") order: Order { metadata: Map<string, Tag> }`)
- D129 §94 "@RequestBody | 任意 class(含嵌套 + collection)" 域语义 collection 维度 Map 兑现
- I021-requestbody-nested.md line 71 §留下轮锚 2 承接
- I021-requestbody.md line 117 父档父档显式 backlog "I021-requestbody-map — JSON Object → Map<string, V> 反序列化" 部分承接(本子档处理嵌套场景,顶层 `@RequestBody m: Map<string, V>` 留 I021-requestbody-map 平级独立子档)

## 备注

- 本子档**纯文档起立轮**,Execute 留下下轮(按 §交互式单文档:每轮一目标)
- nested.md line 71 §留下轮锚 2 + line 124-128 父档已锚 RC 契约,本子档承接
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)已 Decided,本子档执行不再辨析
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化第三轮(深化 = collection 维度 Map 子分支;首轮 nested.md = 单层 user class 字段;二轮 nested-array = Array<Class>)
