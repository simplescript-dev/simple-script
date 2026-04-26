# I021-requestbody-nested-optional-container:容器自身 nullable 反序列化(`Array<UserClass>?` / `Map<string, UserClass>?`)— D130 SSoT + D131 谓词层第二次实测验证(真零 codegen 场景)

> 父档:[I021-requestbody-nested-optional.md](./I021-requestbody-nested-optional.md)(commit 29c3148 — 单层 nullable user class 字段端到端)
> 兄弟子档:[I021-requestbody-nested-optional-inner.md](./I021-requestbody-nested-optional-inner.md)(commit 74ddc48 — 容器 inner nullable `Array<Tag?>` / `Map<string,Tag?>` + D131 谓词层 stripNullableCG inner 修)
> 祖档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层非空嵌套字段)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱嵌套深化](../3-decisions/D123-spring-boot-replication.md) + [D129 §94 @RequestBody 含嵌套含 nullable](../3-decisions/D129-request-param-class-domain.md) + [D130 deserializer SSoT](../3-decisions/D130-deserializer-ssot-converge.md) + [D131 谓词 stripNullableCG inner](../3-decisions/D131-deserialize-predicate-strip-nullable-inner.md) + **D067 null safety(概念锚 — 物理 D 文档不存在,SSoT 见 memory `project_null_safety_design.md` + bootstrap/checker `check_stmts.ss:57/218/325` + `check_narrow.ss:12-26`)**

## 问题

I021-requestbody-nested-optional v0(commit 29c3148)端到端兑现**单层嵌套 nullable user class 字段**(`Order { addr: Address? }`),配合 D067 T? narrow + classFieldNullable Map 局部 metadata + jnIsNullOrMissing lib helper,emitDeserializeForType 加 `nullable T?` case alloca slot 持值跨 block load 替 phi。

I021-requestbody-nested-optional-inner v0(commit 74ddc48)Execute 阶段实测 D130 SSoT 自动 cover 假设破裂 → 升根 D131 谓词层 stripNullableCG inner 修(isArrayDeserializable / isMapDeserializable 内 et/vt 先 stripNullableCG 后判 isUserClass + emitPendingDeserializers BFS strip + Map.get inferType + genMapMethod 同源补)→ 容器内层 nullable `Array<Tag?>` / `Map<string, Tag?>` 7 case 全 PASS + 0 regression。

但 nullable 维度尚未覆盖**容器自身**层 — `Array<Tag>?`(数组字段整体可空)/ `Map<string, Tag>?`(Map 字段整体可空)是 enterprise REST API PATCH 半更新 / DTO 可选集合字段高频形态:用户配置 GET 返 `tags=[]` 空集合 vs `tags=null` 显式 null vs `tags` 字段缺失三态语义区分,Spring Boot Jackson 默认 List/Map 字段 nullable + missing → null。

D130 SSoT + D131 谓词层联动**理论上自动 cover** 容器自身 nullable —— `Array<Tag>?` 字段层 stripNullableCG = `Array<Tag>` 末尾 `?` 剥离,emitDeserializeForType nullable case 触发(commit 29c3148 加的)→ opt_present label 委托递归 emitDeserializeForType("Array<Tag>", outer node) → isArrayDeserializable("Array<Tag>") = 1(D131 §4.1 修后 et="Tag" stripped="Tag" → isUserClass=1)→ emitArrayDeserializeInto + inner element @Tag_deserialize transfer ✓。

**本子档纯文档起立轮(Plan 型),Execute 留下下轮**:任务是锁定 v0 scope + 候选选定 + 根因预审 + 风险锚,实测验证 D130 SSoT + D131 自动 cover 假设留 Execute 轮(若实测命中假设 → 仅加测试 + spring-parity 不动 codegen,**SSoT 设计意图第二次实测兑现 — 真零 codegen 场景** — 第一次是 -inner 子档但**部分**命中需 D131 升根,本子档容器自身 nullable 是真零 codegen 场景对照;若不命中 → 升根独立 D 文档子决策)。

## 第一性需求

引 [D123 §第一性需求 + §247](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON → class 反序列化 | **任意 class(含嵌套含 nullable 含容器自身 nullable)** + Jackson/Gson 反序列化器") + [D130 §SSoT](../3-decisions/D130-deserializer-ssot-converge.md)("per-class deserializer 单点 emitDeserializeForType inner 委托") + [D131 §4](../3-decisions/D131-deserialize-predicate-strip-nullable-inner.md)("谓词层 stripNullableCG inner 后判 isUserClass / 容器嵌套") + D067 null safety("Kotlin/Dart 风格,默认非空,T? 可空")。

SS 用户写:

```ss
class Tag { name: string }
class OrderTagsArrOpt { customer: string; tags: Array<Tag>? }   // 数组本身可空

@PostMapping("/orders/tags-opt")
function createOrder(@RequestBody order: OrderTagsArrOpt): string {
    // D067 T? narrow:MEMBER_ACCESS 不直接 narrow,用户绕路 IDENT(父档 OrderOpt 同源)
    let tags = order.tags
    if (tags != null) {
        // narrow 内 tags 视为 Array<Tag> 非空
        return "customer=" + order.customer + ",tags=" + tags.length()
    }
    return "customer=" + order.customer + ",no-tags"
}
```

行为 byte-identical Java Spring(Jackson `List<Tag>` 字段 missing / null 都走 no-tags 分支):

```java
public class Tag { String name; }
public class OrderTagsArrOpt { String customer; List<Tag> tags; }   // 默认 nullable

@PostMapping("/orders/tags-opt")
public String createOrder(@RequestBody OrderTagsArrOpt order) {
    if (order.tags != null) {
        return "customer=" + order.customer + ",tags=" + order.tags.size();
    }
    return "customer=" + order.customer + ",no-tags";
}
```

curl 三场景(对称 -inner 子档 RC 契约):

- `POST /orders/tags-opt -d '{"customer":"alice","tags":[{"name":"a"},{"name":"b"}]}'` → `customer=alice,tags=2`
- `POST /orders/tags-opt -d '{"customer":"alice","tags":null}'` → `customer=alice,no-tags`
- `POST /orders/tags-opt -d '{"customer":"alice"}'`(tags 字段缺失)→ `customer=alice,no-tags`
- `Map<string, Tag>?` 类似:`{"customer":"bob","items":null}` → `customer=bob,no-items`

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 commit 29c3148 emitDeserializeForType nullable T? case + commit 74ddc48 D131 谓词层 stripNullableCG inner 的 D130 SSoT 联动自动 cover 路径** — `Array<Tag>?` 字段层 stripNullableCG 末尾 `?` 剥离 → nullable case 触发 alloca slot + jnIsNullOrMissing → opt_present 委托递归 emitDeserializeForType("Array<Tag>", outer node) → isArrayDeserializable("Array<Tag>") = 1(D131 §4.1 谓词内 et="Tag" stripped="Tag" → isUserClass=1)→ emitArrayDeserializeInto + inner element @Tag_deserialize transfer;`Map<string, Tag>?` 同理 emitMapDeserializeInto → emitDeserializeForType(Tag, jnGetField(outer, key)) 递归 → @Tag_deserialize transfer | **D130 SSoT + D131 谓词层第二次实测验证场景**(non-bypass) — 若假设命中 Execute 仅加测试 + spring-parity 不动 codegen,**真零 codegen 场景**(-inner 子档是首次但部分命中需 D131 升根,本子档容器自身 nullable 是真零 codegen 场景对照);若假设不命中 → 升根独立 D 文档子决策(本轮锚为 §风险 1+5)|
| B | 给 emitArrayDeserializeInto / emitMapDeserializeInto 内单独加 outer null check(不复用 emitDeserializeForType nullable case 字段层主路径) | 违反 D130 SSoT(per-class deserializer 单点解码 — emitDeserializeForType nullable case 字段层主路径已 cover outer nullable);引入并行 codegen 路径致维护双轨 ❌ |
| C | runtime 反射容器字段 nullable 元数据自动检测 | 违反 [D088 §第一性需求](../3-decisions/D088-comptime-zig-route.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— D130 SSoT + D131 谓词层联动自动 cover + commit 29c3148 nullable case + commit 74ddc48 D131 谓词层 + 测试 / spring-parity 兑现 Execute 主线。

## v0 scope 切分(本子档)

**In scope**(本轮 Plan,下下轮 Execute):

| In scope | 描述 |
|---|---|
| `Array<UserClass>?` 容器自身 nullable | 字段 missing / JSON null → store ptr null;字段非 null → 递归 emitArrayDeserializeInto + inner element @UserClass_deserialize transfer(D131 §4.1 谓词层 stripNullableCG inner 已就绪)|
| `Map<string, UserClass>?` 容器自身 nullable | 字段 missing / JSON null → store ptr null;字段非 null → 递归 emitMapDeserializeInto + inner value @UserClass_deserialize transfer(D131 §4.2 谓词层同源 + Map.get codegen 同源 §4.5 已就绪)|
| `Array<int>?` / `Array<string>?` / `Array<bool>?` / `Array<double>?` 容器自身 nullable + inner primitive | 字段层 stripNullableCG → "Array<int>" → isArrayDeserializable=1(D131 §4.1 修后 et="int" → 直走 primitive 路径)→ emitArrayDeserializeInto + jnArrayGet + jnAsInt + ss_arrayPushInt |
| `Map<string, int>?` / `Map<string, string>?` 等 nullable Map<primitive value> | 同上(D131 §4.2 同源)|
| 容器自身 nullable + inner 非 nullable | 容器层为 `Array<Tag>?` / `Map<string,Tag>?` 而非 `Array<Tag?>` / `Map<string, Tag?>`(inner 元素 nullable 已由 -inner 子档 cover) |
| RC 契约严审 | 字段 ptr null 时 ss_drop_<Outer> 链 ss_release(ptr null)自带 isnull guard(D018 + commit 29c3148 §风险 1 实测同源 line 289-290)|
| Cover 7 case:Array<Class>? null/missing/present + Map<string,Class>? null/missing/present + Array<int>? null/missing/present + 全链路 raw HTTP POST + RC stress(50 次 alloc/release 循环 / 含 null 字段 outer drop) | |

**Out of scope**(留独立子档,不混入本子档):

| Out of scope | 留子档名 | 描述 |
|---|---|---|
| `Array<Tag?>` / `Map<string, Tag?>` 容器内层 nullable(已落) | `-optional-inner`(commit 74ddc48)| 已 ship,本子档不重复 |
| `Array<Tag?>?` 容器自身 + inner 双层 nullable | `-deep-optional`(暂名 / 与 -inner-double 子档候选合并)| 笛卡尔积形态(本子档 + -inner 子档),依两侧 v0 收关后独立验证 |
| `Array<Array<Tag>>?` / `Map<string, Map<string, Tag>>?` N=2 双层嵌套 + 容器自身 nullable | `-deep-optional` | N=2/3/4 层嵌套 + 容器 outer nullable 维度,依本子档 + nested-deep(commit f301e76)双 v0 收关后独立验证 |
| `Array<int?>?` / `Map<string, int?>?` primitive 元素 nullable + 容器自身 nullable | `-optional-inner-primitive` 与 `-deep-optional` 联立 | nullable primitive 走 boxing / 特殊 sentinel(D082 待立 / 已立诊断决定),与本子档容器自身 nullable 笛卡尔积 |
| 显式默认值 `Array<Tag>? = []` 默认空集合 | `-optional-default` | 父档 line 88 已锚,本子档不 cover 默认值语义 |
| Spring `@JsonNullable` annotation(Jackson 字段 nullable 显式标) | 不立(违反 D067 T? 已显式) | |

**v0 scope 不做**:
- 不动 codegen(D130 SSoT + D131 谓词层 commit 74ddc48 已就绪;Execute 阶段实测验证;命中 = 0 codegen 改动,不命中 = 升根独立 D 文档子决策)
- 不动 lib/json.ss(commit 29c3148 jnIsNullOrMissing 已就绪,字段层 nullable case 复用)
- 不引新关键字 / 新语法(D067 T? + D130 SSoT + D131 谓词层已就绪)
- 不实现 inner element nullable(已落 -inner)
- 不实现 N=2 双层 nullable(留 -deep-optional)
- 不实现 nullable primitive(留 -optional-inner-primitive 与 -deep-optional 联立)
- 不主动改 checker(D067 T? narrow MEMBER_ACCESS 限制 — 用户绕路 IDENT narrow 父档同源验证)

## 根因预审(D130 SSoT + D131 谓词层联动自动 cover 假设链)

**当前 emitDeserializeForType nullable case dispatch 路径**(commit 29c3148 + 74ddc48 联动 bootstrap/gen/gen_deserialize.ss):

```
emitDeserializeForType(ft, jsonNodeR) 入口
├── if ft endsWith "?" → nullable case(commit 29c3148)
│   ├── alloca i8* slot
│   ├── call @jnIsNullOrMissing(node) → i1
│   ├── br i1 →
│   │   opt_null label: store ptr null to slot, br opt_done
│   │   opt_present label: stripped = stripNullableCG(ft), 委托递归 emitDeserializeForType(stripped, jsonNodeR) → store result to slot, br opt_done
│   └── opt_done: load slot
└── 7 路 case:
    ├── primitive(int/double/string/bool):jnAs* + 类型转换
    ├── isUserClass(T):@T_deserialize(node) 递归
    ├── isArrayDeserializable(T)(D131 §4.1 谓词内 stripNullableCG(et) 后判 isUserClass(et) / 嵌套 / primitive):走 emitArrayDeserializeInto
    └── isMapDeserializable(T)(D131 §4.2 同源):走 emitMapDeserializeInto
```

**容器自身 nullable 自动 cover 链验证**(本子档 §假设):

1. **`Array<Tag>?` 字段类型** stripNullableCG = `Array<Tag>` 末尾 `?` 剥离 → **走 nullable case** ✓(末尾 `?`,与 -inner 子档 `Array<Tag?>` 字段层不走 nullable case 形成对照)
2. nullable case 内:alloca i8* slot,call @jnIsNullOrMissing(node):
   - opt_null label:store ptr null to slot,br opt_done(JSON `tags=null` 或字段缺失)
   - opt_present label:stripped="Array<Tag>",委托递归 emitDeserializeForType("Array<Tag>", jsonNodeR)
3. 递归入口 `Array<Tag>`:
   - stripNullableCG("Array<Tag>") = "Array<Tag>"(末尾 `>` 不是 `?`)→ stripped == ssType → **不**走 nullable case
   - isUserClass("Array<Tag>") = 0
   - **isArrayDeserializable("Array<Tag>") = 1**(D131 §4.1 谓词:et="Tag" → etStripped="Tag" → isUserClass("Tag")=1 → 返 1)
   - dispatch 落 isArrayDeserializable case → 走 `emitArrayDeserializeInto`
4. emitArrayDeserializeInto(jsonNodeR=outer field json node):
   - jnArrayLen(outer node)拿 length
   - 循环 emit 每个 element:emitDeserializeForType(elemType="Tag", jnArrayGet(outer node, i))递归
   - 递归入口 "Tag":isUserClass=1 → @Tag_deserialize(elemNode)transfer
   - ss_arrayPush(arr, elemPtr)
5. 返 array ptr ptrtoint i64 → store to slot,br opt_done
6. opt_done:load slot → array ptr 或 ptr null
7. 字段 store ptr 走 ssTypeToLLVM("Array<Tag>?") = ptr 路径(D067 nullable 一律 ptr per `bootstrap/gen/gen_types.ss:682`)→ store ptr 既有正确 ✓
8. **D130 SSoT + D131 谓词层联动设计意图第二次自动验证** ✓(per-class deserializer nullable case 字段层主路径 + isArrayDeserializable 谓词层 stripNullableCG inner + emitArrayDeserializeInto 递归委托;真零 codegen 改动)

**`Map<string, Tag>?` 容器自身 nullable 自动 cover 链同源**:

1. stripNullableCG("Map<string, Tag>?") = "Map<string, Tag>" → 走 nullable case
2. opt_present 委托递归 emitDeserializeForType("Map<string, Tag>", jsonNodeR)
3. isMapDeserializable("Map<string, Tag>") = 1(D131 §4.2 同源)→ 走 emitMapDeserializeInto
4. emitMapDeserializeInto(outer node):ss_mapNew + val_type=1 + jnObjectKeys + 循环 emit emitDeserializeForType(vType="Tag", jnGetField(outer node, key)) 递归 → @Tag_deserialize transfer + ss_mapSet
5. 返 map ptr ptrtoint i64 → store to slot,opt_done load slot → map ptr 或 ptr null
6. 字段 store ptr 既有正确 ✓

**`Array<int>?` 容器自身 nullable + inner primitive 自动 cover 链**:

1. stripNullableCG("Array<int>?") = "Array<int>" → 走 nullable case
2. opt_present 委托递归 emitDeserializeForType("Array<int>", outer node)
3. isArrayDeserializable("Array<int>") = 1(D131 §4.1 谓词:et="int" → etStripped="int" → primitive 直接返 1)
4. emitArrayDeserializeInto + 内层 element emitDeserializeForType("int", jnArrayGet(...))递归 → primitive case jnAsInt + sext i64 + ss_arrayPushInt
5. 返 array ptr ptrtoint i64 → store to slot ✓

**实测验证义务(Execute 阶段)**:

```bash
# 测试 1: emit-ir 看 Array<Tag>? 字段是否走 nullable case + 嵌套 emitArrayDeserializeInto + Tag_deserialize 三层激活
bin/ss build /tmp/t_optional_container.ss --emit-ir -o /tmp/t.ll
grep -E "@jnIsNullOrMissing|opt_present|opt_done|opt_null|jnArrayLen|@Tag_deserialize" /tmp/t.ll | wc -l
# 预期: ≥ 6 (nullable case 字段层 + emitArrayDeserializeInto 嵌套 + Tag_deserialize 三层激活)

# 测试 2: 端到端 raw HTTP POST /orders/tags-opt 三场景
curl -X POST 'http://localhost:8080/orders/tags-opt' -H 'Content-Type: application/json' \
  -d '{"customer":"alice","tags":[{"name":"a"},{"name":"b"}]}'
# 预期: customer=alice,tags=2
curl -X POST 'http://localhost:8080/orders/tags-opt' -H 'Content-Type: application/json' \
  -d '{"customer":"alice","tags":null}'
# 预期: customer=alice,no-tags
curl -X POST 'http://localhost:8080/orders/tags-opt' -H 'Content-Type: application/json' \
  -d '{"customer":"alice"}'
# 预期: customer=alice,no-tags
```

**假设破裂回退路径**:若 emit-ir 未自动激活 nullable case 字段层 + emitArrayDeserializeInto / emitMapDeserializeInto 嵌套(说明 emitDeserializeForType nullable case opt_present label 委托链 stripped 递归字段层不正确)→ 升根:

- D130 SSoT 升级或 D131 §4 边界扩(独立 D 文档子决策)
- 本子档 §风险 1+5 锚明,Execute 阶段实测决定升根触发

## 步骤(Execute 轮按序)

1. **RED 命令**(Plan 起立轮已跑;Execute 阶段重跑验证状态):

   ```bash
   # RED 1: 测试文件不存在
   ls tests/phase5/i021_requestbody_nested_optional_container.ss 2>&1 | grep -c "No such"
   # before: 1, after: 0

   # RED 2: spring-parity OrderTagsArrOpt fixture 缺失
   grep -cE "OrderTagsArrOpt|OrderTagsMapOpt|tags.*Array<Tag>\?|items.*Map<string, *Tag>\?" examples/spring-parity/hello/ss/HelloController.ss
   # before: 0(commit 74ddc48 已加 OrderTagsArr 非 Opt),after: ≥ 4(双新 fixture + Tag 类复用既有)

   # RED 3: D130 SSoT + D131 自动 cover 假设实测
   bin/ss build /tmp/t_optional_container.ss --emit-ir -o /tmp/t.ll && \
     grep -cE "@jnIsNullOrMissing|opt_present|jnArrayLen|@Tag_deserialize" /tmp/t.ll
   # before: 0 (测试源文件不存在), after: ≥ 6 (假设命中) 或 0 (假设破裂 → 升根)
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss + .java** 加 `class OrderTagsArrOpt { customer:string; tags: Array<Tag>? }` + `class OrderTagsMapOpt { customer:string; items: Map<string, Tag>? }` + `@PostMapping("/orders/tags-opt") createOrderTagsArrOpt(@RequestBody order: OrderTagsArrOpt)` + `@PostMapping("/orders/items-opt") createOrderTagsMapOpt(@RequestBody order: OrderTagsMapOpt)`(注:与 commit 74ddc48 已加 OrderTagsArr / OrderTagsMap 命名隔离;Tag 类复用既有);Java oracle 同步 `List<Tag>` / `Map<String, Tag>`(Spring 默认字段 nullable 不需 annotation)。

3. **tests/phase5/i021_requestbody_nested_optional_container.ss** 新建 ~150 行 7 case:
   - case 1:`Array<Tag>?` 字段 present `tags=[{...},{...}]` → tags=2
   - case 2:`Array<Tag>?` 字段 JSON null `tags=null` → no-tags
   - case 3:`Array<Tag>?` 字段缺失(JSON 无 tags key)→ no-tags
   - case 4:`Map<string, Tag>?` 字段 present `items={"k1":{...}}` → items=1
   - case 5:`Map<string, Tag>?` 字段 null + 字段缺失双 case → no-items
   - case 6:`Array<int>?` 字段 nullable + inner primitive(`Array<int>?` null vs [1,2,3])
   - case 7:全链路 raw HTTP POST 三场景 + RC stress 50 次循环(混合 null + 非 null 字段 outer drop)→ no leak / no segfault

4. **D130 SSoT + D131 自动 cover 假设实测 + 分流**:
   - **假设命中**(emit-ir 自动激活 nullable case 字段层 + emitArrayDeserializeInto / emitMapDeserializeInto 嵌套)→ Execute 阶段**零 codegen 改动**,仅加测试 + spring-parity + lib/json.ss / bootstrap/gen/gen_deserialize.ss 不动;**D130 SSoT + D131 谓词层第二次自动兑现 — 真零 codegen 场景**(-inner 子档是首次但部分命中需 D131 升根,本子档容器自身 nullable 是真零 codegen 场景对照),commit message 明锚"D130 SSoT + D131 谓词层第二次实测验证 — 真零 codegen 场景"
   - **假设破裂**(emitDeserializeForType nullable case opt_present 委托链断点) → 升根独立 D 文档子决策(本子档 Execute 轮停手,改写 next_prompt 立 D 文档子决策)

5. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。纯文档轮 simplify 豁免。

6. **commit + push**:format `feat(I021-requestbody-nested-optional-container,D123,D129,D130,D131,D067): 容器自身 nullable Array<Tag>? / Map<string,Tag>? 反序列化 — D130 SSoT + D131 谓词层第二次自动 cover 验证(真零 codegen 场景)— Phase 4 §247 第二支柱嵌套深化第九轮`。

## 反向 / 备选

(同上候选 A/B/C 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-optional-container.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)+ `grep -cE "Array<.*>\?|Map<.*,.*>\?|nullable container|outer nullable|容器自身" docs/4-issues/I021-requestbody-nested-optional-container.md` ≥ 5 + `grep -cE "D067|D123|D129|D130|D131" docs/4-issues/I021-requestbody-nested-optional-container.md` ≥ 5
- **Execute 轮 RED before**:见 §步骤 §1(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_optional_container.ss` exit 0,7 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders/tags-opt` 三场景 + `/orders/items-opt` 三场景 byte-identical Java oracle
- **Execute 轮 after(假设命中分支)**:`git diff --stat HEAD -- bootstrap/ lib/` 空输出(零 codegen 改动)+ emit-ir grep `@jnIsNullOrMissing|opt_present|opt_done|jnArrayLen|@Tag_deserialize` ≥ 6
- **Execute 轮 after(假设破裂分支)**:停手转 D 文档子决策,bootstrap/ 不直改,改写 next_prompt
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions

## 风险 / 表面 / 下轮升根路径

1. **emitDeserializeForType nullable case 在容器维度的递归正确性** — `Array<Tag>?` 字段层走 nullable case opt_present 委托递归 emitDeserializeForType("Array<Tag>", jsonNodeR);**关键**:递归调时 jsonNodeR 仍是 outer field json node(不是 element node)— recursion 后 emitDeserializeForType("Array<Tag>", outer node) 的入口 isArrayDeserializable("Array<Tag>")=1 → emitArrayDeserializeInto(outer node)读 jnArrayLen(outer node)拿 length + 循环 jnArrayGet(outer node, i)读 element node;**outer node 作 array 操作正确**(jnArrayLen / jnArrayGet 都接受 outer field json array node)。Execute 阶段实测预期 ✓ 但留 §风险 锚明:若 emitDeserializeForType nullable case opt_present label 委托链 jsonNodeR 透传不正确(如 stripped 后丢失 outer node 引用 → emitArrayDeserializeInto 拿到 element 级别 jsonNodeR 反序列化失败) → 升根 emitDeserializeForType nullable case opt_present label 委托链字段类型透传修(独立 D 文档子决策,本子档 Execute 轮触发但不主动改 codegen — 单 Layer 不混)。

2. **outer null 时 RC 契约**:JSON `tags=null` 或字段缺失 → emitDeserializeForType nullable case opt_null label store ptr null;字段 ss_drop_<Outer> 链时 ss_release(ptr null)走 isnull guard no-op(D018 + D023 + 父档 commit 29c3148 §风险 1 实测同源 line 289-290)。本子档 v0 假设同源(字段层 ss_release 与 -inner 子档 element 级 ss_release 走同一 ss_release 函数 isnull guard 等价覆盖);若实测发现 ss_drop_<Outer> 链不走 ss_release 而走低层路径 → 升根 ss_drop_<Outer> 加 isnull guard(本子档 §风险 锚明,Execute 阶段实测决定升根触发)。

3. **D067 T? narrow 用户层使用限制**:用户写 `if (order.tags != null) { order.tags.length() }` MEMBER_ACCESS narrow(D067 现状 extractNullCheckVar 限 IDENT 形态;memory `project_null_safety_design.md` + bootstrap/checker `check_narrow.ss:12-26`)→ 不 narrow → checker 报错 access nullable;用户绕路 `let a = order.tags; if (a != null) { a.length() }` IDENT narrow 合法路径(父档 OrderOpt commit 29c3148 同源验证)。**本子档不动 checker**,Execute 阶段验证用户绕路 IDENT 写法编译通过(spring-parity hello fixture + 7 case 全程使用绕路 IDENT 写法保持与父档同源);若实测发现需扩 D067 narrow cover MEMBER_ACCESS → 升根 D067 配套独立 issue(本子档不主动改 checker)。

4. **inferType / classFieldTypes 对 `Array<Tag>?` / `Map<string, Tag>?` 字段类型识别保留**:classFieldTypes 注册保留 `?` 后缀(`bootstrap/gen/class/class_register.ss:109` stripNullableCG 只 strip 字段顶层 `?` 但**不 strip 字段类型 string** — 字段类型 string 含 `?` 后缀);classFieldNullable["X.tags"]=1 是局部 metadata flag,字段类型 string 仍为 "Array<Tag>?";inferType 字段 MEMBER_ACCESS 返带 `?` 类型;ssTypeToLLVM("Array<Tag>?")=ptr(D067 nullable 一律 ptr per `bootstrap/gen/gen_types.ss:682`);字段 alloca ptr 既有正确;字段 store/load 走 ptr 正确。**本风险 v0 假设命中**(emitDeserializeForType nullable case + 容器谓词 + 字段 ssTypeToLLVM 三层既有正确);若实测发现 classFieldTypes 注册阶段递归 stripNullableCG inner 误剥 → 升根 D131 §4 边界扩(本子档 §风险 锚明,Execute 阶段实测决定升根触发)。

5. **emitPendingDeserializers BFS 字段扫描容器自身 nullable strip 入队**:本轮 D131 §4.4(commit 74ddc48 兑现)已加 `ftStripped = stripNullableCG(ft)`;`Array<Tag>?` → ftStripped="Array<Tag>" → isArrayDeserializable=1 → 进 BFS 递归剥皮 inner 入队 Tag → @Tag_deserialize transitive closure emit 正确 ✓ 已 cover。**本子档 §风险 锚明**承认 D131 §4.4 已就绪不再升根,Execute 阶段实测验证(`grep "@Tag_deserialize" /tmp/t.ll` ≥ 1 表 transitive closure 入队)。

6. **N=2 双层 nullable 边界澄清**:`Array<Tag?>?`(容器自身 + inner 双层 nullable)是 -inner 子档(commit 74ddc48)+ 本子档的**笛卡尔积**形态,**Out of scope** 留 `-deep-optional` 子档(暂名,与 -inner-double 候选合并);本子档严格只测**单层 outer nullable + inner 非 nullable**(`Array<Tag>?` outer 单层 + `Tag` 非 null);Execute 阶段测试 case 严格守 boundary 不混入 inner nullable 测试(避免双层 nullable 测试干扰本子档容器自身 nullable v0 验证)。本子档 Out of scope 表锁明 `-deep-optional` 子档承接 N=2 双层与笛卡尔积形态。

## 触发场景

- 接到 enterprise REST API 含可空容器字段 DTO(`Order { tags: Array<Tag>? }` / `Inventory { items: Map<string, Item>? }` / PATCH 半更新可选集合字段 / 三态语义区分:`tags=[]` 空集合 vs `tags=null` 显式 null vs `tags` 字段缺失)
- D123 §247 Phase 4 §第二支柱嵌套深化第九轮(commit 74ddc48 第八轮 inner element nullable 后续 nullability 维度向 outer 容器扩展)
- D130 SSoT + D131 谓词层第二次实测验证场景(per-class deserializer nullable case 字段层主路径 + isArrayDeserializable / isMapDeserializable 谓词层 stripNullableCG inner 联动;真零 codegen 改动场景 — 与 -inner 首次部分命中需 D131 升根对照)
- D129 §94 "@RequestBody | 任意 class(含嵌套含 nullable 含容器自身 nullable)" 域语义全维度兑现
- D067 null safety T? narrow 在容器字段维度反序列化路径实测覆盖(用户绕路 IDENT narrow 合法路径)

## 备注

- 本子档**Plan 起立(commit 待本轮)+ Execute 留下下轮** —— Execute 主线落地(测试 + spring-parity + 假设实测分流)留下下轮(按 §交互式单文档:每轮一目标 + 子档预审 §风险 1+5 锚 Execute 阶段实测决定升根触发,单 Layer 不混)
- D067 物理 D 文档不存在(`ls docs/3-decisions/D067*.md` = No such file),SSoT 在 memory `project_null_safety_design.md` + bootstrap/checker `check_stmts.ss:57/218/325` + `check_narrow.ss:12-26`;本子档**显式标 D067 概念锚不创新死链 markdown link**(feedback `feedback_user_literal_vs_d_ssot.md` 引用前 ls 真身防虚锚);父档既有 `[D067 null safety](../3-decisions/D067-null-safety.md)` 死链沿用 issue 层惯例(d_doc_index_linter scope 不含 docs/4-issues/),本子档不主动修父档死链(out of scope)
- D123 §247 Phase 4 §第二支柱已 Decided + 第八轮 Done(commit 74ddc48),本子档执行不再辨析
- D129 §94 @RequestBody 域含嵌套含 nullable 已 Decided,本子档接续 nullable 维度向 outer 容器扩展
- D130 SSoT 已 Decided + 第六/第七/第八轮自动 cover 验证(c52e9b5 Map<string, Class> + 95eb282 Map<string, primitive> + b18850e nested cartesian + 74ddc48 inner nullable 走 SSoT inner 委托;-inner 第八轮揭露谓词层 inner type 识别盲点 → D131 升根),本子档将 SSoT 验证扩展到 outer 容器自身 nullable 维度(第九轮 — 第二次容器自身 nullable 实测,真零 codegen 场景对照 -inner 首次部分命中)
- D131 谓词层 stripNullableCG inner 已 Decided + commit 74ddc48 落地(谓词 §4.1+4.2 + BFS §4.4 + Map.get §4.5),本子档 v0 假设容器自身 nullable 由 D130 SSoT 字段层 nullable case + D131 谓词层 inner 联动**自动 cover** — 验证 D131 修后字段层 outer + 谓词层 inner 双联动设计意图全维度兑现
- D067 null safety 已落实编译期 T? narrow + extractNullCheckVar IDENT 形态,本子档 v0 不动 checker 仅复用父档 commit 29c3148 codegen + lib 路径
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化**第九轮**(深化维度递进:首轮 nested.md 单层非空 → 二轮 nested-array Array → 三轮 nested-map Map → 四轮 nested-deep N>1 层 → 五轮 nested-cartesian 笛卡尔积 → 六轮 nested-map-primitive primitive value → 七轮 nested-optional 单层 nullable 字段 → 八轮 nested-optional-inner 容器 inner nullable → **九轮 nested-optional-container 容器自身 nullable**)
- **依赖关系**:本子档 Execute 轮可独立于 -deep-optional / -optional-inner-primitive / -optional-default 推进(nullability 位置维度正交 — outer container vs inner element vs N=2 双层 vs primitive vs default);Execute 顺序建议 **-optional-inner(commit 74ddc48 已 Done)→ -optional-container(本子档)→ -deep-optional → -optional-inner-primitive**(complexity + scope 风险递进;承 -inner 子档 §备注 §依赖关系锚)
- **scope 重叠分工**:父档 line 86 `-optional-array` 锚的 "数组本身可空 vs 元素可空" 双层维度由 `-optional-inner`(commit 74ddc48 inner element)+ `-optional-container`(本子档容器自身)合并取代,本子档**追加** `-optional-container` 锚到父档 line 87 `-optional-inner` 锚之后;**不主动改写或删除**已锚 `-optional-array`(避免污染父档 history,精神已被双子档分工瓜分);未来 `-deep-optional` 子档立时再做父档 line 86 §留下轮锚的统一收敛(若必要)
