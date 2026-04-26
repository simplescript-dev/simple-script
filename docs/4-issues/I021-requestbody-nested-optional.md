# I021-requestbody-nested-optional:嵌套 nullable class 反序列化 + D067 T? narrow 配合

> 父档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层嵌套 user class 字段端到端)
> 祖档:[I021-requestbody.md](./I021-requestbody.md)(commit 8165370 — Phase 4 §247 第二支柱端到端兑现)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody 域含嵌套](../3-decisions/D129-request-param-class-domain.md) + [D067 null safety](../3-decisions/D067-null-safety.md)

## 问题

I021-requestbody-nested v0(commit b79aa97)端到端兑现单层嵌套 user class scalar 字段(**字段必填 / 非 null**),`emitClassDeserializeFn` 当前对缺失字段走 lib/json.ss 默认 fallback(可能返回全 default 嵌套对象 / 或运行时报错;具体行为 RED 阶段诊断)。

I021-requestbody-nested.md line 73 §留下轮锚 4 已声明:"**I021-requestbody-nested-optional** — 嵌套 nullable class(`Order { addr: Address? }`,配合 [D067 T? narrow](../3-decisions/D067-null-safety.md))反序列化时 null/missing field handling(`jnGetField == 0` 时 store ptr null vs 现行默认 fallback 走全 default 嵌套对象)" — **scope 显式留本子档**。

I021-requestbody-nested.md line 135 §风险 3 已锚:"**JSON null field 嵌套**:`{"customer": null, "addr": {...}}` 现状 v0 不支持,留 I021-requestbody-nested-optional 配合 D067 T? narrow"。

enterprise REST API 真实业务场景:可选字段 / 部分更新 / 缺失字段优雅降级 是 REST API 标准做法(PATCH 半更新 / null 值显式表示"清空字段");Spring Boot 默认 `@RequestBody` 缺失字段走 `null`(对象类型)/ default value(primitive),Jackson `DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES` 控制 strict 模式;SS 现状 D067 已确立"默认非空 + T? 显式可空"语义,但 `@RequestBody nullable class` 反序列化路径未实测覆盖。

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套)** + Jackson/Gson 反序列化器 | HTTP body") + [D067 §第一性需求](../3-decisions/D067-null-safety.md)("Kotlin/Dart 风格,默认非空,T? 可空,无 ! 逃生舱口")。

SS 用户写:

```ss
class Address { city: string; zip: string }
class Order { customer: string; addr: Address? }   // addr 可空

@PostMapping("/orders")
function createOrder(@RequestBody order: Order): string {
    if (order.addr != null) {
        // D067 T? narrow:此分支内 order.addr 视为 Address 非空
        return "customer=" + order.customer + ",city=" + order.addr.city
    }
    return "customer=" + order.customer + ",no-addr"
}
```

行为 byte-identical Java Spring(addr 字段 missing / null 都走 no-addr 分支):

```java
public class Address { String city; String zip; }
public class Order { String customer; Address addr; }   // 默认 nullable

@PostMapping("/orders")
public String createOrder(@RequestBody Order order) {
    if (order.addr != null) {
        return "customer=" + order.customer + ",city=" + order.addr.city;
    }
    return "customer=" + order.customer + ",no-addr";
}
```

curl 三场景:

- `POST /orders -d '{"customer":"alice","addr":{"city":"sh","zip":"200000"}}'` → `customer=alice,city=sh`
- `POST /orders -d '{"customer":"alice","addr":null}'` → `customer=alice,no-addr`
- `POST /orders -d '{"customer":"alice"}'`(addr 字段缺失)→ `customer=alice,no-addr`

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 nested v0 plumbing + emitClassDeserializeFn 加 nullable user class 字段 case**(`else if (isNullableUserClass(ft) == 1)`):lib 端 jnHasField / jnIsNull 检测 field 是否存在 + 是否 JSON null;字段缺失 / null → store ptr null;字段存在且非 null → 递归调 `<NestedClass>_deserialize` + 直接 store transfer ownership(对齐 nested v0 单层非空字段路径);D067 T? narrow 静态保证用户访问 `order.addr.city` 必先 `if (order.addr != null)` 编译期 check | nested v0 plumbing 已就绪零额外设计;[D067 §narrow](../3-decisions/D067-null-safety.md) 静态 T? narrow 已落,本子档 codegen 仅在反序列化路径处理 null/missing → store ptr null;[D018](../3-decisions/D018-object-layout-typeinfo.md) ObjectLayout RC@0 + ptr null 不触发 ss_release(空值 free 协议);[D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md) ✅ |
| B | 引入 Jackson-like `@JsonNullable` annotation 显式标 nullable | 违反 D067 T? 已是 nullable 显式标;A 路径不需要新 annotation ❌ |
| C | runtime 反射 nullable 字段元数据自动检测 | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— nested v0 plumbing 已就绪 + emitClassDeserializeFn nullable 字段 case 落地 + D067 T? narrow 配合静态可空保证。

## v0 scope 切分说明(本子档)

**落地**:

- 单层嵌套 nullable user class 字段(`Order { addr: Address? }`)
- 字段缺失(JSON 不含 key)→ store ptr null
- 字段为 JSON null(`{"addr": null}`)→ store ptr null
- 字段为 JSON object(`{"addr": {...}}`)→ 递归 deserialize + 直接 store transfer
- 配合 D067 T? narrow:用户访问 `order.addr.city` 必先 `if (order.addr != null)` 编译期 check(checker 阶段强制)
- lib/json.ss 扩 `jnHasField(node: int, key: string): int` + `jnIsNull(node: int): int`(具体实现 RED 阶段诊断 lib 现状)
- bootstrap/gen/gen_deserialize.ss `emitClassDeserializeFn` 加 `isNullableUserClass(ft)` 字段 case
- ss_drop_<Outer> 链:nullable 字段 store 时检 ptr != null 才 ss_release(空值 free 协议)
- 测试 IR 锚:`grep "@Address_deserialize\|jnHasField\|jnIsNull\|icmp.*null" /tmp/t_i021_optional.ll` ≥ 4
- 全链路 raw HTTP POST `/orders` byte-identical Java oracle(3 场景:addr 存在 / addr null / addr 缺失)

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立):

- **I021-requestbody-nested-optional-primitive** — nullable primitive 字段(`Order { age: int? }`)反序列化 — primitive 走 boxing / 特殊 sentinel,涉 [D082 nullable primitive boxing](../3-decisions/D082-nullable-primitive-boxing.md) 等独立路径
- **I021-requestbody-nested-optional-array** — `Array<Class>?` / `Array<Class?>` 双层 nullable(数组本身可空 vs 元素可空)
- **[I021-requestbody-nested-optional-inner](./I021-requestbody-nested-optional-inner.md)** — 容器 inner nullable(`Array<Tag?>` / `Map<string, Tag?>`)— 元素 / value nullable user class,D130 SSoT 设计意图首次实测验证(commit 29c3148 nullable case 自动 cover 假设链);scope 部分重叠上行 `-optional-array`(分工说明见子档 §备注 §scope 重叠分工)
- **[I021-requestbody-nested-optional-container](./I021-requestbody-nested-optional-container.md)** — 容器自身 nullable(`Array<Tag>?` / `Map<string, Tag>?`)— 数组 / Map 字段整体可空,D130 SSoT + D131 谓词层第二次实测验证(真零 codegen 场景对照 -inner 首次部分命中需 D131 升根);scope 与上行 `-optional-array` 分工:`-optional-inner` 元素可空 + `-optional-container` 数组本身可空合并取代 -optional-array 锚精神(分工说明见子档 §备注 §scope 重叠分工)
- **I021-requestbody-nested-optional-default** — Spring `@JsonProperty(defaultValue = "x")` 类似默认值字段(本子档仅 null,默认值留独立子档)

**v0 scope 不做**:

- 不实现 nullable primitive 字段(留 -optional-primitive)
- 不实现 nullable Array / Map / 双层 nullable(留 -optional-array / -optional-map)
- 不实现默认值字段(留 -optional-default)
- 不实现 N>1 层嵌套 nullable(留 [I021-requestbody-nested-deep](./I021-requestbody-nested-deep.md) 与本子档配合后独立验证)
- 不引入新关键字 / 新语法(D067 T? 已就绪)

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   # RED 1: lib/json.ss 无 nullable helper
   grep -cE "^function jnHasField|^function jnIsNull" lib/json.ss
   # before: 0 (或 1,若 jnHasField 已有但 jnIsNull 缺) after: 2
   
   # RED 2: codegen 无 nullable user class 字段 case
   grep -cE "isNullableUserClass|isNullable.*Class" bootstrap/gen/gen_deserialize.ss
   # before: 0 after: ≥ 1 (字段类型 dispatch)
   
   # RED 3: 端到端 silent / segfault
   bin/ss run tests/phase5/i021_requestbody_nested_optional.ss 2>&1 | grep -oE "no-addr|customer=alice,city=sh|segfault|null deref|not found"
   # before: segfault 或 null deref(若 codegen 静默走非空路径访问 null ptr)/ 或 customer=alice,city=null(若 lib fallback 走全 default)
   # after: 三场景按 fixture 输出 customer=alice,city=sh / customer=alice,no-addr / customer=alice,no-addr
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss** 加 `class Address` + `class OrderOpt { customer: string; addr: Address? }` + `@PostMapping("/orders/opt") createOrderOpt(@RequestBody order: OrderOpt)`(注:与 nested v0 已加的 `class Order { customer: Customer, addr: Address }` 命名隔离);Java oracle 同步。

3. **tests/phase5/i021_requestbody_nested_optional.ss** 新建 ~120 行 5 case:
   - case 1:`addr` 字段存在 → 走 if 分支 `customer=alice,city=sh`
   - case 2:`addr` 字段为 JSON null → 走 else 分支 `no-addr`
   - case 3:`addr` 字段缺失(JSON 无此 key)→ 走 else 分支 `no-addr`
   - case 4:全链路 raw HTTP POST `/orders/opt` 三场景 byte-identical Java
   - case 5:IR 锚 `grep "@Address_deserialize\|jnHasField\|jnIsNull\|icmp.*null" /tmp/t_i021_optional.ll` ≥ 4

4. **lib/json.ss nullable helper 扩接口**:

   ```ss
   function jnHasField(node: int, key: string): int { /* lib/json.ss 内部 dict repr key 存在性检测 */ }
   function jnIsNull(node: int): int { /* lib/json.ss 内部 nodeKind == JN_NULL */ }
   ```

   注:`jnGetField` 已存在(b79aa97 nested 走);若 `jnGetField` missing key 时返 0(sentinel)= jnHasField 等价;Execute 轮诊断决定复用还是新增显式 jnHasField 别名。

5. **bootstrap fix(codegen 主路径)**:

   ```ss
   // bootstrap/gen/gen_deserialize.ss emitClassDeserializeFn 字段循环内
   else if (isNullableUserClass(ft) == 1) {
       // 拿 field 子 nodeId(missing → 返 0 sentinel)
       let fieldNode = emitJnGetField(parentNode, fieldName)
       // 检 fieldNode == 0 (missing) 或 jnIsNull(fieldNode) == 1 (JSON null)
       let isNullBranch = emitNullableCheck(fieldNode)
       // br i1 isNullBranch, label %field_null, label %field_present
       emitBlock("field_null")
       // store ptr null 到字段 slot
       emitFieldStore(targetPtr, fieldOffset, "null")
       emitBranch("done")
       emitBlock("field_present")
       // 递归调 <Class>_deserialize 拿子 ptr + 直接 store transfer
       let nestedPtr = emitClassDeserializeCall(elemClass, fieldNode)
       emitFieldStore(targetPtr, fieldOffset, nestedPtr)
       emitBranch("done")
       emitBlock("done")
   }
   ```

   `ss_drop_<Outer>` 链:nullable 字段释放路径增 null check —— `if (field != null) ss_release(field)`,空值不触发 ss_release 防 segfault。

6. **checker 配合 D067 T? narrow**:本子档不动 checker(D067 已落 T? narrow);Execute 轮验证 `if (order.addr != null) { order.addr.city }` 编译通过 + `order.addr.city`(无 if 守卫)checker 报错。

7. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。

8. **commit + push**:format `feat(I021-requestbody-nested-optional,D123,D129,D067): 嵌套 nullable class 反序列化 + D067 T? narrow 配合 — Phase 4 §247 第二支柱嵌套深化第五轮`。

## 反向 / 备选

(同上候选 A 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-optional.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:见 §步骤 §1 RED 命令(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_optional.ss` exit 0,5 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders/opt` 三场景(存在 / null / 缺失)byte-identical Java oracle
- **Execute 轮 after**:`grep "@Address_deserialize\|jnHasField\|jnIsNull\|icmp.*null" /tmp/t_i021_optional.ll` ≥ 4(IR + lib helper + null check 锚)
- **Execute 轮 after**:checker 拒绝 `order.addr.city`(无 if 守卫)— `bin/ss check /tmp/no_narrow.ss 2>&1 | grep -c "nullable"` ≥ 1
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions

## 风险 / 表面 / 下轮升根路径

1. **nullable 字段 RC 契约严审**(承接 nested.md line 124-128 父档已锚 + nested-array.md / nested-map.md §风险 1 同模式扩展):
   - 字段非空 → 子 `<Address>_deserialize` 返新分配 ptr(rc=1),父字段 store 直接 transfer(无 retain)
   - 字段空(missing / JSON null)→ 父字段 store ptr null(rc=N/A,无对象)
   - `ss_drop_<Outer>` 链:nullable 字段释放**必加 null check** — `if (field != null) ss_release(field)`,**空值不触发 ss_release 防 segfault**
   - **若 ss_drop 路径漏 null check** → 空字段 ss_release(0) 走 mi_free(0) 行为 mimalloc 是定义良好的(no-op),但若走 ss_decref 链解引用 RC@0 则 segfault → Execute 必须严审 ss_drop_<Outer> 路径

2. **lib/json.ss nullable helper 现状**:
   - `jnGetField` 已存在(b79aa97 nested 走),missing key 行为 RED 阶段诊断(返 0 sentinel?返 -1?抛异常?)
   - `jnIsNull` 必须新增(检 nodeKind == JN_NULL),与 jnGetField 配合可表达"missing OR null"
   - 若 jnGetField missing key 返 0,jnIsNull(0) 是否合法 RED 诊断决定 — 若 jnIsNull(0) panic,nullable check 路径必须先 jnHasField 再 jnIsNull

3. **D067 T? narrow 编译期配合**:
   - 本子档 codegen 仅处理反序列化路径,checker T? narrow 已 D067 落实;Execute 轮验证 nullable 字段访问 narrow 流自动生效(无需新增 checker 路径)
   - 若 checker 现有 T? narrow 不 cover `order.addr.city` 字段访问场景 → 升根路径 D067 checker narrow 路径补齐(本子档不主动改 checker,留 D067 配套独立 issue)

4. **JSON Jackson `null` vs `"null"` 字符串歧义**:JSON `{"addr":null}` 是真正 null(JN_NULL),`{"addr":"null"}` 是字符串 "null";lib/json.ss 内部 nodeKind 应正确区分 JN_NULL vs JN_STRING;Execute 轮验证 lib 现状区分正确

5. **nullable primitive 字段(`age: int?`)留 -optional-primitive 子档**:primitive 走 boxing(SS 现状 D082 nullable primitive boxing 待立 / 已立?Execute 轮诊断)— 本子档 v0 仅 cover nullable user class 字段

**Plan 阶段 plumbing 完整**:本子档 Execute 轮无表面遗留,RC 契约严审 + transitive closure(b79aa97 已 cover field class)+ lib/json.ss nullable helper 扩接口 + D067 T? narrow 配合编译期展开。

## 触发场景

- 接到 enterprise REST API 业务实现含可选字段 DTO(`Order { addr: Address? }` / 部分更新 PATCH endpoint / 缺失字段优雅降级)
- D129 §94 "@RequestBody | 任意 class(含嵌套)" 域语义 nullable 维度兑现
- D067 T? narrow 在反序列化路径实测覆盖
- I021-requestbody-nested.md line 73 §留下轮锚 4 承接
- I021-requestbody-nested.md line 135 §风险 3 JSON null field 嵌套承接

## 备注

- 本子档**纯文档起立轮**,Execute 留下下轮(按 §交互式单文档:每轮一目标)
- nested.md line 73 §留下轮锚 4 + line 135 父档已锚 nullable,本子档承接
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)已 Decided,本子档执行不再辨析
- D067 null safety 已落实编译期 T? narrow,本子档不动 checker 仅 codegen + lib 路径
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化第五轮(深化 = nullability 维度;首轮 nested.md = 单层非空;二轮 nested-array = collection Array;三轮 nested-map = collection Map;四轮 nested-deep = N>1 层)
- **依赖关系**:本子档 Execute 轮可独立于 nested-array / nested-map / nested-deep 推进(nullability 是字段类型修饰维度,与 collection / 层数维度正交);Execute 顺序建议 nested-array → nested-map → nested-deep → nested-optional(complexity 递进,但 optional 可任意时机插入)
