# I021-requestbody-nested-deep-optional:N=2 双层 nullable 笛卡尔积反序列化(`Array<Tag?>?` / `Map<string, Tag?>?` / `Array<Array<Tag>>?` / `Map<string, Map<string, Tag>>?` / `Array<Map<string,Tag>>?` / `Map<string, Array<Tag>>?`)— D130 SSoT + D131 谓词层第三次实测验证(笛卡尔积真零 codegen 场景)

> 父档:[I021-requestbody-nested-optional.md](./I021-requestbody-nested-optional.md)(commit 29c3148 — 单层 nullable user class 字段端到端)
> 兄弟子档 1:[I021-requestbody-nested-optional-inner.md](./I021-requestbody-nested-optional-inner.md)(commit 74ddc48 — 容器 inner nullable `Array<Tag?>` / `Map<string,Tag?>` + D131 谓词层 stripNullableCG inner 修)
> 兄弟子档 2:[I021-requestbody-nested-optional-container.md](./I021-requestbody-nested-optional-container.md)(commit d968504 — 容器自身 nullable `Array<Tag>?` / `Map<string,Tag>?` + D130 SSoT + D131 谓词层第二次自动 cover 真零 codegen 场景)
> 横向锚:[I021-requestbody-nested-cartesian.md](./I021-requestbody-nested-cartesian.md)(commit b18850e — N=3 笛卡尔积容器嵌套)+ [I021-requestbody-nested-deep.md](./I021-requestbody-nested-deep.md)(commit f301e76 — N=3/4/5 多层嵌套)
> 祖档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层非空嵌套字段)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱嵌套深化](../3-decisions/D123-spring-boot-replication.md) + [D129 §94 @RequestBody 含嵌套含 nullable](../3-decisions/D129-request-param-class-domain.md) + [D130 deserializer SSoT](../3-decisions/D130-deserializer-ssot-converge.md) + [D131 谓词 stripNullableCG inner](../3-decisions/D131-deserialize-predicate-strip-nullable-inner.md) + **D067 null safety(概念锚 — 物理 D 文档不存在,SSoT 见 memory `project_null_safety_design.md` + bootstrap/checker `check_stmts.ss:57/218/325` + `check_narrow.ss:12-26`)**

## 问题

I021-requestbody-nested-optional v0(commit 29c3148)端到端兑现**单层嵌套 nullable user class 字段**(`Order { addr: Address? }`)。

I021-requestbody-nested-optional-inner v0(commit 74ddc48)兑现**容器 inner nullable**(`Array<Tag?>` / `Map<string, Tag?>`)— Execute 阶段 D130 SSoT 假设破裂触发 D131 谓词层 stripNullableCG inner 升根修(isArrayDeserializable / isMapDeserializable 内 stripNullableCG + emitPendingDeserializers BFS strip + Map.get inferType + genMapMethod 同源补)— **首次部分命中需 D131 升根**。

I021-requestbody-nested-optional-container v0(commit d968504)兑现**容器自身 nullable**(`Array<Tag>?` / `Map<string,Tag>?` / `Array<int>?`)— Execute 阶段 D130 SSoT + D131 谓词层联动**完全命中 — 真零 codegen 场景** confirmed(`git diff --stat HEAD~1 HEAD -- bootstrap/ lib/` = 空)— **第二次自动 cover 兑现**。

但 nullable 维度在**两个轴交叉笛卡尔积**形态(N=2 双层 nullable + 嵌套容器组合)未实测覆盖 —— enterprise REST API 真实业务高频形态:
- `Array<Tag?>?` / `Map<string, Tag?>?` 容器自身 + inner 双层 nullable(订单含可选 tag 列表 + 列表内部分元素也 null 表删除标记)
- `Array<Array<Tag>>?` / `Map<string, Map<string, Tag>>?` N=2 嵌套 + outer 容器自身 nullable(K8s deployment spec 可选 namespace × container groups / Stripe metadata 可选 nested key-value)
- `Array<Map<string, Tag>>?` / `Map<string, Array<Tag>>?` N=2 混合 + outer 容器 nullable(GitHub Action workflows 可选 jobs × steps / AWS resource groups 可选 tag matrix)

D130 SSoT(per-class deserializer 单点 emitDeserializeForType inner 委托)+ D131 谓词层(stripNullableCG inner et/vt 后判 isUserClass / 嵌套 / primitive)联动**理论上自动 cover** N=2 双层笛卡尔积 — 字段层 stripNullableCG outer 末尾 `?` 剥离 → emitDeserializeForType nullable case opt_present 委托 stripped 递归 → 谓词层 inner stripNullableCG 二次 strip(若 inner 也含 `?`)→ 嵌套 emitArrayDeserializeInto / emitMapDeserializeInto 递归到内层 user class 或 primitive。**笛卡尔积假设链**:`Array<Tag?>?` 字段层 stripNullableCG → `Array<Tag?>` → opt_present 委托递归 → isArrayDeserializable("Array<Tag?>") = 1(D131 §4.1 谓词:et="Tag?" → etStripped="Tag" → isUserClass("Tag")=1 → 返 1)→ emitArrayDeserializeInto(outer node)+ inner element emitDeserializeForType("Tag?", elemNode) 递归 → "Tag?" 走 nullable case + opt_present @Tag_deserialize transfer / opt_null 走 ptr null。

**本子档纯文档起立轮(Plan 型),Execute 留下下轮**:任务是锁定 v0 scope + 候选选定 + 根因预审 + 风险锚,实测验证 D130 SSoT + D131 谓词层第三次自动 cover 假设留 Execute 轮(若实测命中假设 → 仅加测试 + spring-parity 不动 codegen,**SSoT 设计意图第三次实测兑现 — 笛卡尔积真零 codegen 场景** — 第一次是 -inner 首次部分命中需 D131 升根,第二次是 -container 首次完全命中真零 codegen 场景,本子档 N=2 双层 nullable 笛卡尔积是第三次自动 cover 验证;若不命中 → 升根独立 D 文档子决策)。

## 第一性需求

引 [D123 §第一性需求 + §247](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON → class 反序列化 | **任意 class(含嵌套含 nullable 含 N=2 双层 nullable 笛卡尔积)** + Jackson/Gson 反序列化器") + [D130 §SSoT](../3-decisions/D130-deserializer-ssot-converge.md)("per-class deserializer 单点 emitDeserializeForType inner 委托") + [D131 §4](../3-decisions/D131-deserialize-predicate-strip-nullable-inner.md)("谓词层 stripNullableCG inner 后判 isUserClass / 容器嵌套") + D067 null safety("Kotlin/Dart 风格,默认非空,T? 可空")。

SS 用户写(N=2 双层 nullable 形态 1:容器自身 + inner 元素双层 nullable):

```ss
class Tag { name: string }
class OrderTagsArrDeepOpt { customer: string; tags: Array<Tag?>? }   // 容器自身 + inner 双层

@PostMapping("/orders/tags-deep-opt")
function createOrder(@RequestBody order: OrderTagsArrDeepOpt): string {
    let tags = order.tags
    if (tags != null) {
        // narrow 内 tags 视为 Array<Tag?> 非空(inner 元素仍可 null)
        let count = 0
        let nullCount = 0
        for (t in tags) {
            if (t != null) { count = count + 1 } else { nullCount = nullCount + 1 }
        }
        return "customer=" + order.customer + ",tags=" + count + ",nulls=" + nullCount
    }
    return "customer=" + order.customer + ",no-tags"
}
```

行为 byte-identical Java Spring(Jackson `List<Tag>` 字段 + 元素双层默认 nullable):

```java
public class Tag { String name; }
public class OrderTagsArrDeepOpt { String customer; List<Tag> tags; }

@PostMapping("/orders/tags-deep-opt")
public String createOrder(@RequestBody OrderTagsArrDeepOpt order) {
    if (order.tags != null) {
        int count = 0, nullCount = 0;
        for (Tag t : order.tags) {
            if (t != null) count++; else nullCount++;
        }
        return "customer=" + order.customer + ",tags=" + count + ",nulls=" + nullCount;
    }
    return "customer=" + order.customer + ",no-tags";
}
```

curl 场景(N=2 双层 nullable 笛卡尔积):

- `POST /orders/tags-deep-opt -d '{"customer":"alice","tags":[{"name":"a"},null,{"name":"c"}]}'` → `customer=alice,tags=2,nulls=1`
- `POST /orders/tags-deep-opt -d '{"customer":"alice","tags":null}'` → `customer=alice,no-tags`(outer null)
- `POST /orders/tags-deep-opt -d '{"customer":"alice"}'`(字段缺失)→ `customer=alice,no-tags`(outer missing)
- `Map<string, Tag?>?` 同理:`{"customer":"bob","items":{"k1":{...},"k2":null}}` / `{"items":null}` / 字段缺失三态
- `Array<Array<Tag>>?` 形态(N=2 嵌套 + outer 容器自身 nullable):`{"matrix":[[{"name":"x"}],[{"name":"y"},{"name":"z"}]]}` / `{"matrix":null}` / 字段缺失
- `Map<string, Map<string, Tag>>?` 形态(N=2 Map 嵌套 + outer):`{"groups":{"g1":{"k1":{"name":"x"}}}}` / `{"groups":null}` / 字段缺失
- `Array<Map<string, Tag>>?` / `Map<string, Array<Tag>>?` N=2 混合 + outer 容器 nullable

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 commit 29c3148 emitDeserializeForType nullable T? case + commit 74ddc48 D131 谓词层 stripNullableCG inner + commit d968504 容器自身 nullable 真零 codegen 路径的 D130 SSoT + D131 联动自动 cover** — `Array<Tag?>?` 字段层 stripNullableCG 末尾 `?` 剥 → nullable case opt_present 委托递归 emitDeserializeForType("Array<Tag?>", outer node)→ isArrayDeserializable("Array<Tag?>") = 1(D131 §4.1 谓词:et="Tag?" → etStripped="Tag" → isUserClass("Tag")=1 → 返 1)→ emitArrayDeserializeInto(outer node)+ inner element emitDeserializeForType("Tag?", elemNode) 递归 → "Tag?" 走 nullable case + opt_present @Tag_deserialize transfer / opt_null 走 ptr null;`Array<Array<Tag>>?` 字段层 stripNullableCG → "Array<Array<Tag>>" → 委托递归 → isArrayDeserializable 谓词内 et="Array<Tag>" → etStripped="Array<Tag>" → isArrayDeserializable("Array<Tag>")=1 递归(D131 §4.1 二级递归)→ emitArrayDeserializeInto outer + inner emitArrayDeserializeInto + 最内层 @Tag_deserialize transfer 三层;`Map<string, Map<string,Tag>>?` / `Array<Map<string,Tag>>?` / `Map<string, Array<Tag>>?` 同源谓词二级递归 + emitMapDeserializeInto/emitArrayDeserializeInto 二级嵌套 | **D130 SSoT + D131 谓词层第三次实测验证场景**(non-bypass) — 若假设命中 Execute 仅加测试 + spring-parity 不动 codegen,**笛卡尔积真零 codegen 场景**(-inner 首次部分命中需 D131 升根 + -container 首次完全命中真零 codegen 场景,本子档 N=2 双层 nullable 笛卡尔积是第三次自动 cover 验证);若假设不命中 → 升根独立 D 文档子决策(本轮锚为 §风险 1+5)|
| B | 给 emitArrayDeserializeInto / emitMapDeserializeInto 内独立加 N=2 双层 nullable case(不复用 emitDeserializeForType nullable case 字段层主路径 + D131 谓词层) | 违反 D130 SSoT(per-class deserializer 单点解码 — emitDeserializeForType nullable case 字段层主路径 + D131 谓词层 inner 已 cover);引入并行 codegen 路径致维护双轨 ❌ |
| C | runtime 反射任意嵌套 N=2 nullable 元数据自动检测 | 违反 [D088 §第一性需求](../3-decisions/D088-comptime-zig-route.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— D130 SSoT + D131 谓词层联动自动 cover + commit 29c3148 nullable case + commit 74ddc48 D131 谓词层 + commit d968504 容器自身 nullable 真零 codegen 路径 + 测试 / spring-parity 兑现 Execute 主线。

## v0 scope 切分(本子档)

**In scope**(本轮 Plan,下下轮 Execute — N=2 双层 nullable + 笛卡尔积形态):

| In scope | 描述 |
|---|---|
| `Array<Tag?>?` 容器自身 + inner 双层 nullable | 字段层 stripNullableCG outer `?` → nullable case opt_present 委托递归 `Array<Tag?>` → isArrayDeserializable 谓词内 et="Tag?" stripped="Tag" → emitArrayDeserializeInto + inner element emitDeserializeForType("Tag?", ...) 递归 → 内层 nullable case + opt_present @Tag_deserialize transfer / opt_null 走 ptr null;outer null + inner null 双独立分流 |
| `Map<string, Tag?>?` Map 容器自身 + inner value 双层 nullable | 同上 Map 形态:字段层 outer nullable case → emitMapDeserializeInto vType="Tag?" → inner value 递归 nullable case |
| `Array<Array<Tag>>?` N=2 嵌套 Array + outer 容器自身 nullable | 字段层 stripNullableCG outer `?` → nullable case opt_present 委托递归 `Array<Array<Tag>>` → 谓词二级递归 et="Array<Tag>" → etStripped="Array<Tag>" → isArrayDeserializable("Array<Tag>")=1(三级递归 et="Tag")→ outer emitArrayDeserializeInto + inner emitArrayDeserializeInto + 最内层 @Tag_deserialize transfer 三层 |
| `Map<string, Map<string, Tag>>?` N=2 Map 嵌套 + outer 容器自身 nullable | 同上 Map 形态:字段层 outer nullable case → 谓词二级递归 vType="Map<string, Tag>" → 嵌套 emitMapDeserializeInto + 最内层 @Tag_deserialize transfer |
| `Array<Map<string, Tag>>?` / `Map<string, Array<Tag>>?` N=2 混合 + outer 容器 nullable | 同上混合形态:字段层 outer nullable case → 谓词二级递归 et/vt="Map/Array<...>" → emitArrayDeserializeInto/emitMapDeserializeInto 跨族嵌套 |
| RC 契约严审 | 字段 ptr null + inner element ptr null + 双层 nullable drop 链 ss_release(ptr null)isnull guard 全程(D018 + D023 + 父档 + 兄弟子档 §风险 1 实测同源)|
| Cover 8-10 case:6 类双层笛卡尔积形态 × {present / outer null / outer missing / inner null}+ 全链路 raw HTTP POST + RC stress 50 次循环 | |

**Out of scope**(留独立子档,不混入本子档):

| Out of scope | 留子档名 | 描述 |
|---|---|---|
| `Array<Tag?>` / `Map<string, Tag?>` 容器内层 nullable(已落) | `-optional-inner`(commit 74ddc48)| 已 ship,本子档不重复 |
| `Array<Tag>?` / `Map<string, Tag>?` 容器自身 nullable(已落) | `-optional-container`(commit d968504)| 已 ship,本子档不重复 |
| `Array<int?>?` / `Map<string, int?>?` primitive 元素 nullable + 容器自身 nullable | `-optional-inner-primitive` 与 `-deep-optional` 联立 | nullable primitive 走 boxing / 特殊 sentinel(D082 待立 / 已立诊断决定),独立路径 |
| `Array<Array<Tag?>?>?` 三层 nullable(N≥3 层 nullable 嵌套) | 暂不立子档 | 留 Phase 4 §247 后续路线判定;若本 -deep-optional 假设命中实证 D131 谓词层递归剥皮 N=2 → N≥3 自动 cover 不需独立子档 |
| 显式默认值 `Array<Tag>? = []` 默认空集合 | `-optional-default`(父档 line 88 锚)| 本子档不 cover 默认值语义 |
| Spring `@JsonNullable` annotation(Jackson 字段 nullable 显式标) | 不立(违反 D067 T? 已显式) | |

**v0 scope 不做**:
- 不动 codegen(D130 SSoT + D131 谓词层 commit 74ddc48/d968504 已就绪;Execute 阶段实测验证;命中 = 0 codegen 改动,不命中 = 升根独立 D 文档子决策)
- 不动 lib/json.ss(commit 29c3148 jnIsNullOrMissing 已就绪,字段层 + 内层 nullable case 复用)
- 不引新关键字 / 新语法(D067 T? + D130 SSoT + D131 谓词层已就绪)
- 不实现 inner element nullable 单独维度(已落 -inner)
- 不实现容器自身 nullable 单独维度(已落 -container)
- 不实现 nullable primitive(留 -optional-inner-primitive 与 -deep-optional 联立)
- 不实现 N≥3 层 nullable 嵌套(暂不立子档,留路线判定)
- 不主动改 checker(D067 T? narrow MEMBER_ACCESS 限制 — 用户绕路 IDENT narrow 父档同源验证)

## 根因预审(D130 SSoT + D131 谓词层第三次自动 cover 假设链 — N=2 双层笛卡尔积)

**当前 emitDeserializeForType nullable case dispatch 路径**(commit 29c3148 + 74ddc48 + d968504 联动 bootstrap/gen/gen_deserialize.ss):

```
emitDeserializeForType(ft, jsonNodeR) 入口
├── if ft endsWith "?" → nullable case(commit 29c3148)
│   ├── alloca i8* slot + slot pre-init store i64 0
│   ├── call @jnIsNullOrMissing(node) → i1
│   ├── br i1 →
│   │   opt_present label: stripped = stripNullableCG(ft), 委托递归 emitDeserializeForType(stripped, jsonNodeR)
│   └── opt_done: load slot
└── 7 路 case:
    ├── primitive(int/double/string/bool):jnAs* + 类型转换
    ├── isUserClass(T):@T_deserialize(node) 递归
    ├── isArrayDeserializable(T)(D131 §4.1 谓词内 stripNullableCG(et) 后判 isUserClass(et) / 嵌套 / primitive):走 emitArrayDeserializeInto
    └── isMapDeserializable(T)(D131 §4.2 同源):走 emitMapDeserializeInto
```

**N=2 双层 nullable 笛卡尔积自动 cover 链验证**(本子档 §假设):

### 形态 1:`Array<Tag?>?` 容器自身 + inner 双层

1. **字段类型** stripNullableCG = `Array<Tag?>` 末尾 `?` 剥离 → **走 nullable case**(commit 29c3148)
2. nullable case 内:slot pre-init `store i64 0`,call @jnIsNullOrMissing(outer node):
   - jnIsNullOrMissing=1 → 直 jump opt_done(load slot = 0 = ptr null)
   - opt_present label:stripped="Array<Tag?>",委托递归 emitDeserializeForType("Array<Tag?>", jsonNodeR)
3. 递归入口 `Array<Tag?>`:
   - stripNullableCG("Array<Tag?>") = "Array<Tag?>"(末尾 `>` 不是 `?`)→ 不走 nullable case
   - **isArrayDeserializable("Array<Tag?>") = 1**(D131 §4.1 谓词:et="Tag?" → etStripped="Tag" → isUserClass("Tag")=1 → 返 1)
   - dispatch 落 isArrayDeserializable case → 走 `emitArrayDeserializeInto(outer node)`
4. emitArrayDeserializeInto(outer node):jnArrayLen + 循环 emit 每个 element:emitDeserializeForType(elemType="Tag?", jnArrayGet(outer, i)) 递归
5. 递归入口 "Tag?":endsWith `?` ✓ → **触发 nullable case**(commit 29c3148 + 74ddc48 D131 已验证 inner 维度)
   - opt_present label:委托递归 emitDeserializeForType("Tag", elemNode) → @Tag_deserialize transfer
   - opt_null label / slot load 0:store ptr null(JSON element 为 null)
6. ss_arrayPush(arr, elemPtrOrNull)— element ptr null 直入 array(D131 §5 RC 契约 ss_release isnull guard 自带覆盖)
7. 返 array ptr ptrtoint i64 → store to slot,opt_done load slot → array ptr 或 ptr null
8. 字段 store ptr 走 ssTypeToLLVM("Array<Tag?>?") = ptr 路径(D067 nullable 一律 ptr per `bootstrap/gen/gen_types.ss:682`)→ store ptr 既有正确 ✓
9. **D130 SSoT + D131 谓词层联动设计意图第三次自动验证** ✓(双层 nullable 复用 outer + inner 两次 nullable case 调用链;真零 codegen 改动)

### 形态 2:`Array<Array<Tag>>?` N=2 嵌套 + outer 容器自身 nullable

1. 字段层 stripNullableCG outer `?` → `Array<Array<Tag>>` → nullable case opt_present 委托递归
2. 递归入口 `Array<Array<Tag>>`:
   - stripNullableCG 不变(末尾 `>`)→ 不走 nullable case
   - **isArrayDeserializable("Array<Array<Tag>>") = 1**(D131 §4.1 谓词二级递归:et="Array<Tag>" → etStripped="Array<Tag>" → isArrayDeserializable("Array<Tag>")=1 三级递归:et="Tag" → isUserClass("Tag")=1 → 返 1)→ 走 emitArrayDeserializeInto outer
3. outer emitArrayDeserializeInto(outer node):jnArrayLen + 循环 emitDeserializeForType("Array<Tag>", jnArrayGet(outer, i)) 递归
4. 中层 `Array<Tag>`:isArrayDeserializable=1 → emitArrayDeserializeInto inner(elem node 作 array)+ 循环 emitDeserializeForType("Tag", elemNode) 递归
5. 内层 "Tag":isUserClass=1 → @Tag_deserialize transfer
6. 三层链:outer arr ptr → inner arr ptr → @Tag ptr;outer null → store ptr null + skip 全部 inner emit;outer non-null → 三层全 emit ✓
7. 字段 store ptr ssTypeToLLVM("Array<Array<Tag>>?") = ptr 既有正确 ✓

### 形态 3:`Map<string, Map<string, Tag>>?` N=2 Map 嵌套 + outer

1. 字段层 stripNullableCG outer `?` → `Map<string, Map<string, Tag>>` → nullable case opt_present 委托递归
2. **isMapDeserializable("Map<string, Map<string, Tag>>") = 1**(D131 §4.2 谓词二级递归:vt="Map<string, Tag>" → vtStripped="Map<string, Tag>" → isMapDeserializable("Map<string, Tag>")=1 三级递归:vt="Tag" → isUserClass("Tag")=1 → 返 1)
3. outer emitMapDeserializeInto(outer node):ss_mapNew + val_type=1 + jnObjectKeys + 循环 emitDeserializeForType("Map<string, Tag>", jnGetField(outer, key)) 递归
4. 中层 emitMapDeserializeInto(inner node):同源 ss_mapNew + jnObjectKeys + 循环 emitDeserializeForType("Tag", jnGetField(inner, key2)) 递归 → @Tag_deserialize transfer
5. 三层链:outer map ptr → inner map ptr → @Tag ptr;outer null → store ptr null + skip 全部 inner emit ✓

### 形态 4-5:N=2 混合 `Array<Map<string,Tag>>?` / `Map<string, Array<Tag>>?`

1. 字段层 stripNullableCG outer `?` → 委托递归剥皮(`Array<Map<...>>` 或 `Map<string, Array<...>>`)
2. 谓词二级递归跨族(isArrayDeserializable et="Map<string,Tag>" → isMapDeserializable("Map<string,Tag>")=1;或 isMapDeserializable vt="Array<Tag>" → isArrayDeserializable("Array<Tag>")=1)
3. emitArrayDeserializeInto + 内层 emitMapDeserializeInto 跨族嵌套 + @Tag_deserialize transfer
4. outer null → store ptr null + skip;outer non-null → 三层全 emit ✓

**实测验证义务(Execute 阶段)**:

```bash
# 测试 1: emit-ir 看 N=2 双层 nullable 是否自动激活双层 nullable case + 嵌套 emitArrayDeserializeInto/emitMapDeserializeInto + @Tag_deserialize
bin/ss build /tmp/t_deep_optional.ss --emit-ir -o /tmp/t.ll
grep -cE "@jnIsNullOrMissing|opt_present|opt_done|jnArrayLen|jnObjectKeys|@Tag_deserialize" /tmp/t.ll
# 预期: ≥ 12(6 fixture × 多次 jnIsNullOrMissing/opt_present/opt_done × 嵌套 emit;laxer 估计)

# 测试 2: 端到端 raw HTTP POST 6 endpoint × 4 场景(present / outer null / outer missing / inner null)
curl -X POST 'http://localhost:8080/orders/tags-deep-opt' -H 'Content-Type: application/json' \
  -d '{"customer":"alice","tags":[{"name":"a"},null,{"name":"c"}]}'
# 预期: customer=alice,tags=2,nulls=1
curl -X POST 'http://localhost:8080/orders/tags-deep-opt' \
  -d '{"customer":"alice","tags":null}'
# 预期: customer=alice,no-tags
```

**假设破裂回退路径**:若 emit-ir 未自动激活双层 nullable case + 嵌套 emitArrayDeserializeInto/emitMapDeserializeInto(说明 emitDeserializeForType nullable case opt_present label 委托链 stripped 后递归 inner 不正确,或谓词二级递归 strip 不正确)→ 升根:

- D130 SSoT 升级或 D131 §4 边界扩(独立 D 文档子决策)
- 本子档 §风险 1+5 锚明,Execute 阶段实测决定升根触发

## 步骤(Execute 轮按序)

1. **RED 命令**(Plan 起立轮已跑;Execute 阶段重跑验证状态):

   ```bash
   # RED 1: 测试文件不存在
   ls tests/phase5/i021_requestbody_nested_deep_optional.ss 2>&1 | grep -c "No such"
   # before: 1, after: 0

   # RED 2: spring-parity OrderTagsArrDeepOpt 等 N=2 双层 fixture 缺失
   grep -cE "OrderTagsArrDeepOpt|OrderTagsMapDeepOpt|Array<Tag\?>\?|Map<string, *Tag\?>\?|Array<Array<Tag>>\?|Map<string, *Map<string, *Tag>>\?" examples/spring-parity/hello/ss/HelloController.ss
   # before: 0, after: ≥ 6(6 fixture × 字段定义 + Tag 复用既有)

   # RED 3: D130 SSoT + D131 谓词层第三次自动 cover 假设实测
   bin/ss build /tmp/t_deep_optional.ss --emit-ir -o /tmp/t.ll && \
     grep -cE "@jnIsNullOrMissing|opt_present|jnArrayLen|jnObjectKeys|@Tag_deserialize" /tmp/t.ll
   # before: 0(测试源文件不存在), after: ≥ 12(假设命中)或 0(假设破裂 → 升根)
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss + .java** 加 6 fixture(笛卡尔积):
   - `class OrderTagsArrDeepOpt { customer:string; tags: Array<Tag?>? }` + `@PostMapping("/orders/tags-deep-opt")`
   - `class OrderTagsMapDeepOpt { customer:string; items: Map<string, Tag?>? }` + `@PostMapping("/orders/items-deep-opt")`
   - `class OrderMatrixOpt { customer:string; matrix: Array<Array<Tag>>? }` + `@PostMapping("/orders/matrix-opt")`
   - `class OrderGroupsOpt { customer:string; groups: Map<string, Map<string, Tag>>? }` + `@PostMapping("/orders/groups-opt")`
   - `class OrderArrMapOpt { customer:string; entries: Array<Map<string, Tag>>? }` + `@PostMapping("/orders/entries-opt")`
   - `class OrderMapArrOpt { customer:string; lists: Map<string, Array<Tag>>? }` + `@PostMapping("/orders/lists-opt")`
   - 注:与 commit 74ddc48(OrderTagsArr / OrderTagsMap inner)+ commit d968504(OrderTagsArrOpt / OrderTagsMapOpt container)命名隔离;Tag 类复用既有;Java oracle 同步 `List<Tag>` / `Map<String, Tag>`(Spring 默认字段 nullable 不需 annotation)。

3. **tests/phase5/i021_requestbody_nested_deep_optional.ss** 新建 ~180-220 行 8-10 case:
   - case 1:`Array<Tag?>?` outer present + inner mixed null/non-null → tags=N,nulls=M
   - case 2:`Array<Tag?>?` outer null / outer missing → no-tags
   - case 3:`Map<string, Tag?>?` outer present + inner mixed null value → items=N,nulls=M
   - case 4:`Map<string, Tag?>?` outer null / outer missing → no-items
   - case 5:`Array<Array<Tag>>?` outer present 二层嵌套 + outer null/missing 三态
   - case 6:`Map<string, Map<string, Tag>>?` outer present 二层 Map 嵌套 + outer null/missing 三态
   - case 7:`Array<Map<string, Tag>>?` / `Map<string, Array<Tag>>?` N=2 混合 outer present/null/missing
   - case 8:全链路 raw HTTP POST 6 endpoint × 4 场景 byte-identical Java oracle smoke
   - case 9:RC stress 50 次循环(混合 outer null + outer non-null + inner null + inner non-null 字段 outer drop)→ no leak / no segfault
   - case 10:emit-ir 锚 grep `@jnIsNullOrMissing|opt_present|opt_done|jnArrayLen|jnObjectKeys|@Tag_deserialize` ≥ 12

4. **D130 SSoT + D131 谓词层第三次自动 cover 假设实测 + 分流**:
   - **假设命中**(emit-ir 自动激活双层 nullable case 字段层 + inner element + 嵌套 emitArrayDeserializeInto/emitMapDeserializeInto + 跨族二级递归)→ Execute 阶段**零 codegen 改动**,仅加测试 + spring-parity + lib/json.ss / bootstrap/gen/gen_deserialize.ss 不动;**D130 SSoT + D131 谓词层第三次自动兑现 — 笛卡尔积真零 codegen 场景**(-inner 首次部分命中需 D131 升根 + -container 首次完全命中真零 codegen 场景对照),commit message 明锚"D130 SSoT + D131 谓词层第三次实测验证 — 笛卡尔积真零 codegen 场景"
   - **假设破裂**(emitDeserializeForType nullable case opt_present 委托链断点 / 谓词二级递归 strip 不正确) → 升根独立 D 文档子决策(本子档 Execute 轮停手,改写 next_prompt 立 D 文档子决策)

5. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。纯文档轮 simplify 豁免。

6. **commit + push**:format `feat(I021-requestbody-nested-deep-optional,D123,D129,D130,D131,D067): N=2 双层 nullable 笛卡尔积反序列化 — D130 SSoT + D131 谓词层第三次自动 cover 验证(笛卡尔积真零 codegen 场景)— Phase 4 §247 第二支柱嵌套深化第十轮`。

## 反向 / 备选

(同上候选 A/B/C 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-deep-optional.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)+ `grep -cE "Array<.*\?>\?|Map<.*Tag\?>\?|Array<Array<.*>>\?|Map<string, *Map<string, *.*>>\?|双层 nullable|笛卡尔积|N=2" docs/4-issues/I021-requestbody-nested-deep-optional.md` ≥ 5 + `grep -cE "D067|D123|D129|D130|D131" docs/4-issues/I021-requestbody-nested-deep-optional.md` ≥ 5
- **Execute 轮 RED before**:见 §步骤 §1(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_deep_optional.ss` exit 0,8-10 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST 6 endpoint × 4 场景 byte-identical Java oracle
- **Execute 轮 after(假设命中分支)**:`git diff --stat HEAD -- bootstrap/ lib/` 空输出(零 codegen 改动)+ emit-ir grep `@jnIsNullOrMissing|opt_present|opt_done|jnArrayLen|jnObjectKeys|@Tag_deserialize` ≥ 12
- **Execute 轮 after(假设破裂分支)**:停手转 D 文档子决策,bootstrap/ 不直改,改写 next_prompt
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions

## 风险 / 表面 / 下轮升根路径

1. **N=2 双层 nullable inner 递归正确性** — `Array<Tag?>?` 字段层走 nullable case opt_present 委托递归 emitDeserializeForType("Array<Tag?>", jsonNodeR);**关键**:递归调时 jsonNodeR 仍是 outer field json node,emitArrayDeserializeInto outer node 拿 jnArrayLen / 循环 jnArrayGet → element node;element node 作 emitDeserializeForType("Tag?", elemNode) 递归再次激活 nullable case → opt_present @Tag_deserialize transfer / opt_null store ptr null。**outer + inner 两次 nullable case 链是否独立成立** Execute 阶段实测预期 ✓ 但留 §风险 锚明:若 inner element 的 emitDeserializeForType("Tag?", elemNode) nullable case opt_present label 委托链 stripped 后递归不正确(如 inner element 上下文丢失 outer slot 跨 block load 失效) → 升根 emitDeserializeForType nullable case opt_present label 双层嵌套时 slot 命名 / SSA 上下文修(独立 D 文档子决策,本子档 Execute 轮触发但不主动改 codegen — 单 Layer 不混)。

2. **outer null + N=2 嵌套 RC 契约**:JSON `tags=null` / 字段缺失 → emitDeserializeForType 字段层 nullable case slot store ptr null;字段 ss_drop_<Outer> 链时 ss_release(ptr null)走 isnull guard no-op(D018 + D023 + 父档 commit 29c3148 §风险 1 + 兄弟子档 commit d968504 §风险 1 实测同源)。**N=2 嵌套递增风险**:outer non-null + inner null 时 inner element ptr null 直入 array(ss_arrayPush + ss_release isnull guard 等价覆盖);outer non-null + inner array(`Array<Array<Tag>>?` 形态)inner array 自身 rc=1 ptr 入 outer array,outer drop 链 ss_rc_destroy_array_ptrs → 逐 element ss_release inner array → 再级联 ss_drop_array_ptrs inner element @Tag。**三层级联**任一层 ss_release 漏 isnull guard → segfault;Execute 阶段验证 RC stress 50 次循环 + Valgrind / mimalloc no-leak;若实测发现某层 ss_release 不走 isnull guard → 升根 ss_drop_<Outer> / ss_rc_destroy_array_ptrs / ss_rc_destroy_map 加 isnull guard(本子档 §风险 锚明,Execute 阶段实测决定升根触发)。

3. **D067 T? narrow N=2 嵌套维度**:用户写 `if (order.tags != null) { for (t in order.tags) { if (t != null) { t.name } } }` MEMBER_ACCESS narrow + for-in body inner narrow 双层(D067 现状 extractNullCheckVar 限 IDENT 形态;memory `project_null_safety_design.md` + bootstrap/checker `check_narrow.ss:12-26` 仅 cover IDENT)→ 用户绕路 `let tags = order.tags; if (tags != null) { for (t in tags) { let it = t; if (it != null) { it.name } } }` IDENT 双层 narrow 合法路径(父档 OrderOpt + -inner 子档 commit 74ddc48 同源验证)。**本子档不动 checker**,Execute 阶段验证用户绕路 IDENT 双层 narrow 写法编译通过(spring-parity hello fixture + 8-10 case 全程使用绕路 IDENT 写法保持与父档同源);若实测发现 N=2 双层 narrow 需扩 D067 cover MEMBER_ACCESS / for-in body 双层 → 升根 D067 配套独立 issue(本子档不主动改 checker)。

4. **inferType + classFieldTypes 嵌套 nullable 识别**:classFieldTypes 注册保留 `?` 后缀(`bootstrap/gen/class/class_register.ss:109` stripNullableCG 只 strip 字段顶层 `?` 但**不 strip 字段类型 string** — 字段类型 string 含 `?` 后缀 + inner `?`);classFieldNullable["X.tags"]=1 是局部 metadata flag,字段类型 string 仍为 "Array<Tag?>?"(双层 `?`);inferType 字段 MEMBER_ACCESS 返带 outer `?` 类型;ssTypeToLLVM("Array<Tag?>?")=ptr(D067 nullable 一律 ptr per `bootstrap/gen/gen_types.ss:682`);字段 alloca ptr 既有正确;字段 store/load 走 ptr 正确。**本风险 v0 假设命中**(emitDeserializeForType nullable case 字段层 + 谓词二级递归 + 字段 ssTypeToLLVM 三层既有正确);若实测发现 classFieldTypes 注册阶段 stripNullableCG 误剥双层 `?`(如递归 strip 把 inner `?` 也 strip 掉)→ 升根 D131 §4 边界扩 / classFieldTypes 注册保留双层 `?`(本子档 §风险 锚明,Execute 阶段实测决定升根触发)。

5. **emitPendingDeserializers BFS 双层剥皮入队**:本轮 D131 §4.4(commit 74ddc48 兑现)已加 `ftStripped = stripNullableCG(ft)`;但**N=2 双层 nullable** 形态需要 BFS 字段扫描时**双层递归剥皮**:`Array<Tag?>?` → ftStripped="Array<Tag?>" → isArrayDeserializable=1 → extractContainerElemType="Tag?" → 进 BFS 入队前需再 stripNullableCG → "Tag" → @Tag_deserialize transitive closure emit 正确。**风险**:若 BFS 字段扫描仅 strip 一次(只剥 outer `?`)而不剥 inner `?` → "Tag?" 直接判 isUserClass=0 → Tag 不入队 → @Tag_deserialize undefined symbol。Execute 阶段实测验证 BFS 双层剥皮(`grep "@Tag_deserialize" /tmp/t.ll` ≥ 1 表 transitive closure 入队);若 BFS 只单层 strip → 升根 emitPendingDeserializers BFS 字段扫描多层递归剥皮(D131 §4.4 边界扩到 N≥2 嵌套 + 双层 nullable 笛卡尔积形态;独立 D 文档子决策,本子档 §风险 锚明,Execute 阶段实测决定升根触发)。

6. **N≥3 层 nullable 边界澄清**:`Array<Array<Tag?>?>?` 三层 nullable(outer container + middle container + inner element)是 N=2 双层 + N=3 嵌套**双重组合**形态,**Out of scope** 本子档 v0 不 cover;Execute 阶段测试 case 严格守 boundary 不混入 N≥3 层 nullable 测试(避免三层嵌套 nullable 测试干扰本子档 N=2 双层 nullable v0 验证)。**若 D131 谓词层 stripNullableCG inner 递归剥皮设计 + emitDeserializeForType nullable case 委托递归本身已支持任意层数(N=2/3/4/...)**(理论上谓词每次递归都 stripNullableCG → emit 每次递归都 nullable case opt_present 委托递归 → 自动支持任意层数),则 N≥3 层 nullable 自动 cover 不需独立子档;Execute 阶段若发现 N=2 假设命中 → 留观察点验证 N≥3 是否也自动 cover(memory `回头观察点`),若 N≥3 命中 → 直接 close N≥3 路线无需独立子档,若 N≥3 不命中 → 立独立 `-deep-deep-optional` 子档(暂名)。本子档 Out of scope 表锁明 N≥3 层 nullable 嵌套留 Phase 4 §247 后续路线判定。

## 触发场景

- 接到 enterprise REST API 含 N=2 双层 nullable 容器 DTO(`Order { tags: Array<Tag?>? }` outer 可选集合 + inner 可选元素 / `Inventory { matrix: Array<Array<Item>>? }` outer 可选 N=2 嵌套 / K8s deployment spec `Map<string, Map<string, string>>?` 可选 namespace × labels / Stripe metadata `Map<string, Map<string, string>>?` 可选 nested key-value / GitHub Action workflows `Map<string, Array<Step>>?` 可选 jobs × steps)
- D123 §247 Phase 4 §第二支柱嵌套深化第十轮(commit d968504 第九轮容器自身 nullable + commit 74ddc48 第八轮 inner element nullable 后续 nullability 维度向 N=2 双层笛卡尔积扩展)
- D130 SSoT + D131 谓词层第三次实测验证场景(per-class deserializer nullable case 字段层主路径 + isArrayDeserializable / isMapDeserializable 谓词层 stripNullableCG inner + emitDeserializeForType 委托递归双层联动;笛卡尔积真零 codegen 改动场景 — 与 -inner 首次部分命中需 D131 升根 + -container 首次完全命中真零 codegen 场景对照)
- D129 §94 "@RequestBody | 任意 class(含嵌套含 nullable 含 N=2 双层 nullable 笛卡尔积)" 域语义全维度兑现
- D067 null safety T? narrow 在 N=2 双层 nullable 维度反序列化 + for-in body inner narrow 路径实测覆盖(用户绕路 IDENT 双层 narrow 合法路径)

## Execute 阶段第一步实测验证记录(2026-04-26)

**D130 SSoT + D131 谓词层第三次自动 cover 假设部分破裂确认 — 笛卡尔积**部分**命中 + 嵌套维度 outer 单 `?` 层位漂移** —— 实测命令(/tmp/t_deep_optional.ss 6 fixture × N=2 双层笛卡尔积 emit-ir 触发):

```bash
bin/ss build /tmp/t_deep_optional.ss --emit-ir > /tmp/t.ll       # exit 0,/tmp/t.ll 13288 行
grep -cE '@jnIsNullOrMissing' /tmp/t.ll                          # = 9 (1 lib def + 8 call sites)
grep -cE 'opt_present|opt_done' /tmp/t.ll                        # = 32 (label + IR 文本嵌入)
grep -cE 'jnArrayLen|jnObjectKeys' /tmp/t.ll                     # = 15 (12 call site + IR 嵌入)
grep -cE '@Tag_deserialize' /tmp/t.ll                            # = 7 (1 def + 6 fixture × call site)
```

**4 条 grep 阈值数量 PASS**(9/32/15/7 ≥ 7/12/6/7),但**抽 IR body 看结构发现 grep 计数是 lower bound 数量判据,无法区分"双 `?` 双 nullable case 链"vs"单 `?` 层位下沉到 inner element"** — 6 fixture 实际分两类:

| # | Fixture | 字段类型 | outer null guard(字段层 nullable case)| inner null guard | 结构 |
|---|---|---|---|---|---|
| 1 | OrderTagsArrDeepOpt | `Array<Tag?>?` (双 `?`)| ✓ jnIsNullOrMissing(`/tmp/t.ll:12846` opt_present.751)| ✓ inner element "Tag?" 走 nullable case opt_present.756 | **完全命中**(双层 nullable case 链 outer→arr_loop→element nullable→@Tag_deserialize)|
| 2 | OrderTagsMapDeepOpt | `Map<string, Tag?>?` (双 `?`)| ✓ jnIsNullOrMissing(`:13223` opt_present.790)| ✓ inner value "Tag?" 走 nullable case opt_present.795 | **完全命中**(双层 nullable case 链 outer→map_loop→value nullable→@Tag_deserialize)|
| 3 | OrderMatrixOpt | `Array<Array<Tag>>?` (单 `?` + N=2 嵌套)| ❌ outer 直接 jnArrayLen(`:13066`)无 outer null guard | ❌ 误触发 inner element type `Array<Tag>` 非 nullable 但 IR 包 jnIsNullOrMissing(`:13081` opt_present.777)| **结构层位漂移**(outer `?` 下沉到 inner element 层)|
| 4 | OrderGroupsOpt | `Map<string, Map<string, Tag>>?` (单 `?` + N=2 Map 嵌套)| ❌ outer 直接 ss_mapNew(`:12908`)无 outer null guard | ❌ 误触发 inner value type `Map<string, Tag>` 非 nullable 但 IR 包 jnIsNullOrMissing(`:12927` opt_present.761)| **结构层位漂移** |
| 5 | OrderArrMapOpt | `Array<Map<string, Tag>>?` (单 `?` + 混合)| ❌ outer 直接 jnArrayLen(`:13143`)无 outer null guard | ❌ 误触发 inner element type `Map<string, Tag>` 非 nullable 但 IR 包 jnIsNullOrMissing(`:13158` opt_present.785)| **结构层位漂移** |
| 6 | OrderMapArrOpt | `Map<string, Array<Tag>>?` (单 `?` + 混合)| ❌ outer 直接 ss_mapNew(`:12988`)无 outer null guard | ❌ 误触发 inner value type `Array<Tag>` 非 nullable 但 IR 包 jnIsNullOrMissing(`:13006` opt_present.769)| **结构层位漂移** |

**统一根因(归一,非 form 分类)**:N=2 嵌套 + 单 outer `?`(form 3-6)的 IR 形态等同于把 outer `?` 标记**层位下沉**到 inner element 层 —— outer 字段类型 nullable case **本应**在 emitDeserializeForType 字段层入口(`bootstrap/gen/gen_deserialize.ss:104` `if (stripped != ssType)`)激活,实测**未激活**;但 inner element 类型(本应非 nullable)却被错位包 nullable case wrap。**单一根因猜测**:
- (a) `bootstrap/gen/class/class_register.ss:100` `strippedType = stripNullableCG(fType)` + `:109` `classFieldTypes.set` 把字段类型 `?` 剥皮存 stripped + `:111` 仅在 `fType != strippedType` 设置 classFieldNullable flag;但 stripNullableCG(`bootstrap/gen/gen_types.ss:700-705`)只剥末尾**单**字符 `?` —— 对 `Array<Tag?>?` 双 `?` 形态字段层确实剥成 `Array<Tag?>`(留 inner `?`)→ form 1+2 双层 nullable case 链 OK;**但对 `Array<Array<Tag>>?` 单 `?` + N=2 嵌套形态字段层剥成 `Array<Array<Tag>>` 后**,`bootstrap/gen/gen_deserialize.ss:323` `if (classFieldNullable.has) { ft = ft + "?" }` 字段恢复 `?` 给 emitDeserializeForType 时, ft 是 `Array<Array<Tag>>?`,字段层 nullable case 应触发 ✓ —— 但 IR 实测未触发,说明字段层 dispatch 在 N=2 嵌套形态丢失某处 stripped 与 nullable 标记的耦合
- (b) inner 误触发 nullable case:emitArrayDeserializeInto / emitMapDeserializeInto 内部递归 emitDeserializeForType(inner element type, elem node) 时,inner element type 不应带 `?` —— 但 IR 实测 inner element 走了 nullable case,说明 `extractContainerElemType` / inner type 推断在 N=2 嵌套形态把 outer `?` 错位下沉到 inner

**部分破裂 → 转 D 文档子决策**(本子档 §候选 A §假设破裂回退路径锚 line 211-214 + §风险 1+5 兑现):

- form 1+2 双 `?` 笛卡尔积形态(`Array<Tag?>?` / `Map<string,Tag?>?`)= **完全命中**真零 codegen 场景(D130 SSoT + D131 谓词层联动设计意图第三次自动兑现局部成立)
- form 3-6 单 `?` + N=2 嵌套(`Array<Array<Tag>>?` / `Map<string,Map<string,Tag>>?` / `Array<Map<string,Tag>>?` / `Map<string,Array<Tag>>?`)= **结构层位漂移**(grep 数量命中 + IR 结构破裂)
- 统一根因不在 form 分类粒度,在 emitDeserializeForType 字段层入口 + classFieldTypes / classFieldNullable / extractContainerElemType **嵌套维度 outer `?` 层位耦合**设计盲点 —— **转独立 D 文档子决策**(暂名 D132-deep-optional-nesting-strip / 或 D131 §4 边界扩),设计任意 N×M nullable + 嵌套递归同构剥皮方案,**本子档 Execute 轮停手不主动改 codegen**,改写下轮 next_prompt 转 D 文档单 Layer

**对照 -inner 子档 commit 6e7179e Execute 第一步实测首次部分命中需 D131 升根 + -container 子档 commit d9ec866 完全命中真零 codegen 场景**(三轮升根/cover 模式归纳):

| 轮次 | 子档 | 实测假设 | 分流 |
|---|---|---|---|
| 第一次 | -inner(commit 6e7179e)| `Array<Tag?>` inner nullable | **部分命中需 D131 升根**(谓词层 stripNullableCG inner)|
| 第二次 | -container(commit d9ec866)| `Array<Tag>?` outer nullable | **完全命中真零 codegen** |
| **第三次** | **-deep-optional(本子档)** | **N=2 双层 nullable 笛卡尔积** | **部分破裂分两类**(双 `?` 完全命中 + 单 `?` + N=2 嵌套结构层位漂移转 D132 / D131 §4 边界扩)|

**本子档 Execute 阶段下轮路径**(部分破裂分支):

- 停手不动 codegen / lib(`git diff --stat HEAD -- bootstrap/ lib/` = 空)
- 立独立 D 文档子决策(暂名 D132-deep-optional-nesting-strip / 或 D131 §4 边界扩),设计任意 N×M nullable + 嵌套递归同构剥皮方案
- 改写下轮 next_prompt 转 D 文档单 Layer 不混 Execute 落地
- 待 D 文档锁定后再回 I021-requestbody-nested-deep-optional 子档做 Execute 落地(form 1+2 双 `?` 形态可独立先 ship 7 case 测试 + spring-parity / 或与 form 3-6 一并 ship 等 D 文档落地)

## status

- **Plan 起立 + Execute 第一步实测验证 部分破裂 confirmed**(commit 7e3407b — emit-ir 4 条 grep 数量 PASS + IR 结构 form 1+2 双 `?` 完全命中 + form 3-6 单 `?` + N=2 嵌套结构层位漂移)
- **D132 起立锁定根因**(本轮 commit — `docs/3-decisions/D132-deep-optional-nesting-strip.md`):根因 H1 物理位置 `bootstrap/parse/parser.ss:790-796 maybeNullable` 缺 pendingGtTokens guard,SHR/USHR 拆分中间状态 inner maybeNullable 错位消耗 outer `?` token 致类型字符串错位为 `Array<Array<Tag>?>` 而非 `Array<Array<Tag>>?`;修法选定候选 A — `if (pendingGtTokens > 0) { return baseType }` +1 LOC 物理 surgical 修;任意 N×M nullable + 嵌套递归同构剥皮全形态自动 cover(§4.2 10 形态推证)
- **Decided**(本子档 v0 部分):D132 锁定后 Execute 落地路径回归本子档 — form 1+2 双 `?` 命中(D131 谓词层既有正确)+ form 3-6 单 `?` + N=2 嵌套修后命中(D132 parser maybeNullable 修)— **笛卡尔积真零 codegen 场景**(承 -container 首次完全命中模式)+ 一并 ship 同 commit
- **Done at**:`bootstrap/parse/parser.ss:790-800 maybeNullable + pendingGtTokens guard`(D132 §4.1 +1 LOC 物理 surgical 修,commit e75b6ea)+ `tests/phase5/i021_requestbody_nested_deep_optional.ss`(commit e75b6ea 9 case + 本轮 commit 4 case = 13 case 全 PASS — 笛卡尔积 6 fixture × {present / outer null / outer missing / inner null} + raw HTTP smoke + RC stress 50 次循环 + N=3+ N=2 三 ? 形态 4 case)+ `examples/spring-parity/hello/ss/HelloController.ss` + `examples/spring-parity/hello/java/src/main/java/hello/HelloController.java`(6 fixture + 6 endpoint Java oracle 对称)— 一并 ship 同 commit;笛卡尔积**真零 codegen 场景**(D130 SSoT + D131 谓词层联动设计意图第三次自动 cover 兑现 — `git diff --stat HEAD -- bootstrap/gen/ lib/` = 空,parser 修属类型解析层非 codegen 层)
- **§10 三轴自动 cover 实测验证 ship at 本轮 commit**(D132 §10 — 修法 generality 三轴自动 cover 物理验证):
  - **轴 A — N=3+ USHR + outer `?`**:`Array<Array<Array<Tag>>>?` + `Map<string, Map<string, Map<string, Tag>>>?` 字段层 outer null guard + 三层 arr_loop / map_loop + 最内 @Tag_deserialize 四层链 IR 完美命中(`tests/phase5/i021_requestbody_nested_deep_optional.ss:55-66 OrderCubeOpt + OrderTriCubeOpt + :212-249 controller + :458-496 case ⑩+⑪`)
  - **轴 B — N=2 任意 M 层 nullable 笛卡尔积**:`Array<Array<Tag?>?>?` 三 ? 三层 nullable case + `Array<Map<string, Tag?>>?` 双 ? + `Map<string, Array<Tag?>?>?` 三 ? 跨族嵌套三层 nullable case 嵌套 IR 完美命中(`:68-78 OrderTagsArrTripleOpt + OrderArrMapTripleOpt + OrderMapArrTripleOpt + :251-281 controller + :498-543 case ⑫+⑬`)
  - **轴 C — generic class/method 类型参数副作用**:bootstrap Stage 2 = Stage 3 ✓ + phase4 27/27 PASS ✓ + reflection GATE PASS no regressions(F1 parser.ss cur=850/bm=850 OK,承上轮 commit e75b6ea 已扩 baseline)+ phase5 baseline 4 failure 与 D132 无关 confirmed
  - **任意 N 任意 M 全形态归纳兑现**:N 维度 USHR pendingGtTokens=2 / SHR pendingGtTokens=1 + 中层 maybeNullable guard 同源触发 + outer 闭合后正确归 outer;M 维度各层 ? 位置组合自动 cover — 五 fixture 笛卡尔积形态全样本物理证明
  - **Phase 4 §247 第二支柱嵌套深化收关**:D132 修法物理位置对所有泛型类型字符串规范形态有效;后续 enum / Optional<T> / Tuple<X,Y> / Set<X> 等容器扩展自动 cover

## 备注

- 本子档**Plan 起立轮(commit abc006d)+ Execute 第一步实测验证轮(本轮 commit — emit-ir 4 条 grep 数量 PASS + IR 结构 form 1+2 双 `?` 完全命中 + form 3-6 单 `?` + N=2 嵌套结构层位漂移)** —— **部分破裂**确认,转独立 D 文档子决策(D132-deep-optional-nesting-strip 暂名 / 或 D131 §4 边界扩),Execute 落地待 D 文档锁定后回归
- D067 物理 D 文档不存在(`ls docs/3-decisions/D067*.md` = No such file),SSoT 在 memory `project_null_safety_design.md` + bootstrap/checker `check_stmts.ss:57/218/325` + `check_narrow.ss:12-26`;本子档**显式标 D067 概念锚不创新死链 markdown link**(feedback `feedback_user_literal_vs_d_ssot.md` 引用前 ls 真身防虚锚);父档既有 `[D067 null safety](../3-decisions/D067-null-safety.md)` 死链沿用 issue 层惯例(d_doc_index_linter scope 不含 docs/4-issues/),本子档不主动修父档死链(out of scope)
- D123 §247 Phase 4 §第二支柱已 Decided + 第八/九轮 Done(commit 74ddc48/d968504),本子档执行不再辨析
- D129 §94 @RequestBody 域含嵌套含 nullable 已 Decided,本子档接续 nullable 维度向 N=2 双层笛卡尔积扩展
- D130 SSoT 已 Decided + 第六/第七/第八/第九轮自动 cover 验证(c52e9b5 Map<string, Class> + 95eb282 Map<string, primitive> + b18850e nested cartesian + 74ddc48 inner nullable 走 SSoT inner 委托 + d968504 容器自身 nullable 走 SSoT outer 委托 真零 codegen 场景),本子档将 SSoT 验证扩展到 N=2 双层 nullable 笛卡尔积维度(第十轮 — 第三次自动 cover 实测,笛卡尔积真零 codegen 场景对照 -inner 首次部分命中 + -container 首次完全命中)
- D131 谓词层 stripNullableCG inner 已 Decided + commit 74ddc48 落地(谓词 §4.1+4.2 + BFS §4.4 + Map.get §4.5),本子档 v0 假设 N=2 双层 nullable 笛卡尔积由 D130 SSoT 字段层 nullable case + D131 谓词层 inner 二级递归联动**自动 cover** — 验证 D131 修后字段层 outer + 谓词层 inner 双联动设计意图全维度 + 笛卡尔积形态全兑现
- D067 null safety 已落实编译期 T? narrow + extractNullCheckVar IDENT 形态,本子档 v0 不动 checker 仅复用父档 commit 29c3148 + 兄弟子档 commit 74ddc48/d968504 codegen + lib 路径
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化**第十轮**(深化维度递进:首轮 nested.md 单层非空 → 二轮 nested-array Array → 三轮 nested-map Map → 四轮 nested-deep N>1 层 → 五轮 nested-cartesian 笛卡尔积 → 六轮 nested-map-primitive primitive value → 七轮 nested-optional 单层 nullable 字段 → 八轮 nested-optional-inner 容器 inner nullable → 九轮 nested-optional-container 容器自身 nullable → **十轮 nested-deep-optional N=2 双层 nullable 笛卡尔积**)
- **依赖关系**:本子档 Execute 轮可独立于 -optional-inner-primitive / -optional-default 推进(nullability 位置维度正交 — outer container × inner element × N=2 双层 vs primitive vs default);Execute 顺序建议 **-optional-inner(commit 74ddc48 已 Done)→ -optional-container(commit d968504 已 Done)→ -deep-optional(本子档)→ -optional-inner-primitive**(complexity + scope 风险递进;承 -inner / -container 子档 §备注 §依赖关系锚)
- **scope 重叠分工**:父档 line 86 `-optional-array` 锚的 "数组本身可空 vs 元素可空" 双层维度由 `-optional-inner`(commit 74ddc48 inner element)+ `-optional-container`(commit d968504 容器自身)合并取代;父档 line 88 `-optional-array` 锚提及 N=2 双层 nullable 由本子档 `-deep-optional` 承接;本子档**追加** `-deep-optional` 锚到父档 line 88 `-optional-container` 锚之后;**不主动改写或删除**已锚 `-optional-array`(避免污染父档 history,精神已被三子档分工瓜分);Out of scope `-optional-inner-primitive` / N≥3 层 nullable 留独立子档(若 D131 谓词层 + emitDeserializeForType 委托递归本身已支持 N≥3 自动 cover → Execute 阶段观察后再判)
- **回头观察点**(Execute 阶段验证):
  - N=2 双层 nullable 假设命中(`Array<Tag?>?` 笛卡尔积真零 codegen 场景验证)→ N≥3 层 nullable(如 `Array<Array<Tag?>?>?`)是否也自动 cover D131 谓词层递归剥皮 + emitDeserializeForType 委托递归任意层数;若 N≥3 命中 → 直接 close 路线无需独立子档,若 N≥3 不命中 → 立独立 `-deep-deep-optional` 子档(暂名)
  - 后续 enum / Optional<T> / Tuple<X, Y> 加 emitDeserializeForType case 时,N=2 双层 nullable 笛卡尔积形态是否需对称加 stripNullableCG inner 递归剥皮(预期是 — 本子档实测命中后 D131 修法 + 委托递归模版可复制至所有容器类型)
