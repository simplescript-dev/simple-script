# I021-requestbody-nested:嵌套 class 深度反序列化 RC 递归契约(I021-requestbody §下轮第一项)

> 父档:[I021-requestbody.md](./I021-requestbody.md)(commit 8165370 — Phase 4 §247 第二支柱端到端兑现)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody 域含嵌套](../3-decisions/D129-request-param-class-domain.md)

## 问题

I021-requestbody v0(commit 8165370)端到端兑现 D123 §247 第二支柱 @RequestBody POST/PUT/PATCH JSON body → class 反序列化,**v0 实测覆盖仅顶层平坦 class**(`User { name: string, age: int }` 字段全 primitive)。

I021-requestbody v0 §v0 scope 切分(line 101)已声明:"嵌套 class → 递归调 `<NestedClassName>_deserialize`(本 v0 内置 plumbing,但实测覆盖留 I021-requestbody-nested 子档)" — **plumbed but unverified**。

I021-requestbody v0 §风险(line 262)已声明:"嵌套 class 字段递归 RC 契约:User { addr: Addr } 反序列化时 Addr 实例所有权 transfer 给 User;`<Addr>_deserialize` 返回 Addr ptr,User_deserialize 字段填充时直接 store(无 retain),**Execute 轮 RC 契约严格审视**(留 I021-requestbody-nested 子档实测;本 issue v0 仅文档实测覆盖单层 class)" — **契约未实测则不可信**。

enterprise REST API 真实业务下一阶硬需求:Spring 典型形态 `@PostMapping("/orders") createOrder(@RequestBody Order order)` 其中 `Order { customer: Customer, addr: Address }`。SS 现状未实测覆盖此路径,curl POST `/orders` 嵌套 JSON 反序列化行为不可信。

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套)** + Jackson/Gson 反序列化器 | HTTP body")。

SS 用户写:

```ss
class Address { city: string; zip: string }
class Customer { name: string; age: int }
class Order { customer: Customer; addr: Address }

@PostMapping("/orders")
function createOrder(@RequestBody order: Order): string {
    return "customer=" + order.customer.name + ",city=" + order.addr.city
}
```

行为 byte-identical Java Spring:

```java
public class Address { String city; String zip; }
public class Customer { String name; int age; }
public class Order { Customer customer; Address addr; }

@PostMapping("/orders")
public String createOrder(@RequestBody Order order) {
    return "customer=" + order.customer.name + ",city=" + order.addr.city;
}
```

curl `POST /orders -H 'Content-Type: application/json' -d '{"customer":{"name":"alice","age":30},"addr":{"city":"sh","zip":"200000"}}'` → `customer=alice,city=sh`。

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 I021-requestbody v0 plumbing 嵌套 deserialize 路径**(`<NestedClassName>_deserialize` per-class codegen 自动生成已落,本子档 Execute 轮加 RED test 实测覆盖 1 层嵌套 + 严审 RC 契约;若 v0 plumbing 嵌套 transitive closure emit 漏 → bootstrap/gen 路径补齐) | I021-requestbody v0 plumbing 已就绪零额外设计;子 deserialize 与 ss_drop_X / ss_deep_clone_X / ss_shallow_clone_X 共享 per-class 函数自动生成模式([D018](../3-decisions/D018-object-layout-typeinfo.md) + [D022](../3-decisions/D022-clone-semantics.md));RC 契约「子返新 ptr,父 raw store,父 drop 链 emit ss_release」已与 mimalloc 分配器对齐([D023](../3-decisions/D023-mimalloc-integration.md));零运行时反射([D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md)) ✅ |
| B | 起独立 nested deserializer 模块(`lib/spring/boot/nested_deserializer.ss`)桥接 lib/json.ss + per-class deserialize | I021-requestbody v0 已 plumbed,B 重起独立模块违反「编译器吸收复杂度」+ 双轨制风险 ❌ |
| C | runtime 反射递归遍历字段元数据自动 deserialize | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— I021-requestbody v0 plumbing 已就绪,本子档实测覆盖 + RC 契约严审。

## v0 scope 切分说明(本子档)

**落地**:

- 1 层嵌套(`Order { customer: Customer, addr: Address }`)实测覆盖
- 嵌套字段是 user-defined class(非 primitive 直接 jnGet*)
- per-class deserialize 已自动生成(I021-requestbody v0 plumbing line 101)
- 测试 IR 锚:`grep "@Customer_deserialize\|@Address_deserialize" /tmp/t_i021_nested.ll` ≥ 2(per-class deserializer transitive closure emit verify)
- 全链路 raw HTTP POST `/orders` byte-identical Java oracle

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立):

- **I021-requestbody-nested-array** — 嵌套 `Array<Class>`(`Order { items: Array<Item> }`)反序列化(涉 lib/json.ss jnArrayLen / jnArrayGet + Array<Class> 字段所有权递归)
- **I021-requestbody-nested-map** — 嵌套 `Map<K, Class>`(`Order { metadata: Map<string, Tag> }`)反序列化
- **I021-requestbody-nested-deep** — N>1 层嵌套(`A { b: B { c: C { d: D } } }`)反序列化栈深度 + RC 契约累积
- **I021-requestbody-nested-optional** — 嵌套 nullable class(`Order { addr: Address? }`,配合 [D067 T? narrow](../3-decisions/D067-null-safety.md))反序列化时 null/missing field handling

**v0 scope 不做**:

- 不实现 N>1 层嵌套(留 I021-requestbody-nested-deep)
- 不实现嵌套 `Array<Class>`(留 I021-requestbody-nested-array)
- 不实现嵌套 `Map<K, Class>`(留 I021-requestbody-nested-map)
- 不实现 nullable 嵌套(留 I021-requestbody-nested-optional)
- 不引入新关键字 / 新语法
- 不动 lib/json.ss(纯消费侧;jnGet* primitive helpers 已就绪)

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   bin/ss build tests/phase5/i021_requestbody_nested.ss -o /tmp/t_i021_nested_red --emit-ir 2>&1 | grep -cE "@Customer_deserialize|@Address_deserialize"
   # 预期 = 0(若 v0 plumbing 漏 transitive closure → bootstrap/gen 路径补齐)
   # 或 = 2(若 v0 plumbing 已 cover → 本轮加 RED test 即 GREEN)
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss** 加 `class Address` + `class Customer` + `class Order` + `@PostMapping("/orders") createOrder(@RequestBody order: Order)`;Java oracle 同步 `examples/spring-parity/hello/java/.../HelloController.java`。

3. **tests/phase5/i021_requestbody_nested.ss** 新建 ~120 行 5 case:
   - case 1:单层嵌套 `Order { customer: Customer { name } }` 字段访问 `order.customer.name`
   - case 2:双字段嵌套 `Order { customer: Customer, addr: Address }` 双字段访问
   - case 3:嵌套字段含 primitive int(`Customer.age`)+ string(`Customer.name`)反序列化
   - case 4:全链路 raw HTTP POST `/orders -d '{"customer":{...},"addr":{...}}'`
   - case 5:IR 锚 `grep "@Customer_deserialize\|@Address_deserialize" /tmp/t_i021_nested.ll` ≥ 2

4. **bootstrap fix(若 RED 不直接 GREEN)**:I021-requestbody v0 plumbing 若 emit 路径漏 transitive closure(Outer→field types)→ `bootstrap/gen/codegen.ss` 或 `gen/gen_type_ops.ss` `emitClassDeserializeFn` 路径补齐 closure。

5. **simplify 3 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。

6. **commit + push**:format `feat(I021-requestbody-nested,D123): 嵌套 class 深度反序列化 RC 递归契约实测覆盖 — Phase 4 §247 第二支柱深化`。

## 反向 / 备选

(同上候选 A 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:`bin/ss build tests/phase5/i021_requestbody_nested.ss -o /tmp/t_i021_nested_red 2>&1 | grep -cE "@Customer_deserialize|@Address_deserialize"` = 0(若 v0 plumbing 漏 closure)或 = 2(若 v0 plumbing 已 cover)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested.ss` exit 0,5 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders -d '{...}'` 返 byte-identical Java oracle
- **Execute 轮 after**:`grep "@Customer_deserialize\|@Address_deserialize" /tmp/t_i021_nested.ll` = 2(IR 锚)
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions

## 风险 / 表面 / 下轮升根路径

1. **嵌套字段 RC 递归契约严审**(承接 I021-requestbody.md line 262 父档已锚):
   - 子 `<NestedClass>_deserialize` 返新分配 ptr(rc=1, mimalloc mi_calloc)
   - 父 `<Outer>_deserialize` 字段填充:**直接 store(无 retain)** —— 子 deserialize 已一次性 transfer ownership
   - 父 `ss_drop_<Outer>` 链:遍历字段 emit `ss_release(子 ptr)` —— 自动级联触发 `ss_drop_<NestedClass>` 释放子
   - **若契约破裂**(父字段 store 时 retain → 子 ptr rc=2,父 drop 后子 rc=1 leaked)→ 本子档 Execute 必须严审 codegen 字段填充路径(`bootstrap/gen/gen_type_ops.ss emitClassDeserializeFn` 字段 store 处)

2. **per-class deserializer 延迟 emit transitive closure**(承接 I021-requestbody.md line 756 父档已锚 "**延迟 emit**:仅对 @RequestBody invoke sentinel 引用的 class emit"):
   - 嵌套 Customer / Address 是**间接被引用**(经 Order 字段),延迟 emit 触发链需含 transitive closure(Outer 引用 → emit Outer + 递归 emit field types)
   - 本子档 Execute 轮需严审 closure 计算路径,若漏 → 嵌套子 deserialize 函数 undefined symbol link error
   - 升根路径:`bootstrap/gen/codegen.ss emitDeserializeClosure` 函数严审

3. **JSON null field 嵌套**:`{"customer": null, "addr": {...}}` 现状 v0 不支持,留 I021-requestbody-nested-optional 配合 D067 T? narrow

4. **嵌套字段是 const**:I021-requestbody v0 plumbing 已含 const field handling([D017 field-level const](../3-decisions/D017-field-level-const.md));本子档默认嵌套字段非 const(deepClone 时 share retain 还是 deep clone 留 D022 配合);若用户写 `class Order { const customer: Customer }` 行为待 Execute 轮验证

**v0 已 plumbing 完整设计**(无表面遗留):本子档全程根因解决,RC 契约严审 + transitive closure emit + I021-requestbody v0 模式 alignment。下轮独立 issue:Array / Map / N>1 层 / Optional 共享 deserializer 基础能力。

## 触发场景

- 接到 enterprise REST API 业务实现需求(`Order { customer, addr }` / `Invoice { lineItems }` / `User { profile, address }`)
- Phase 4+ @RequestBody 嵌套 class 同模式扩展前置基础能力
- D129 §94 "@RequestBody | 任意 class(含嵌套)" 域语义兑现
- I021-requestbody.md line 113-115 父档显式 backlog 锚承接

## 备注

- 本子档**纯文档起立轮**,Execute 留下下轮(按 §交互式单文档:每轮一目标)
- I021-requestbody.md line 101 + line 113-115 + line 262 + line 756 父档已锚 backlog,本子档承接
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)已 Decided,本子档执行不再辨析
- Phase 4 主流注解清单:✅ @PathVariable / ✅ @RequestParam / ✅ @RequestBody / ✅ @RequestHeader / ❌ @ModelAttribute(D129 §5 Dropped) / ❌ @CookieValue(2026-04-25 user 拍板不做);**Phase 4 主流注解清单封顶**,本子档为 Phase 4 §第二支柱深化非新主流注解
