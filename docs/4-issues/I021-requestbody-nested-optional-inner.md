# I021-requestbody-nested-optional-inner:容器 inner nullable 反序列化(`Array<Tag?>` / `Map<string, Tag?>`)— D130 SSoT 设计意图首次实测验证

> 父档:[I021-requestbody-nested-optional.md](./I021-requestbody-nested-optional.md)(commit 29c3148 — 单层 nullable user class 字段端到端)
> 祖档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层非空嵌套字段)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱嵌套深化](../3-decisions/D123-spring-boot-replication.md) + [D129 §94 @RequestBody 含嵌套](../3-decisions/D129-request-param-class-domain.md) + [D130 deserializer SSoT](../3-decisions/D130-deserializer-ssot-converge.md) + **D067 null safety(概念锚 — 物理 D 文档不存在,SSoT 见 memory `project_null_safety_design.md` + bootstrap/checker `check_stmts.ss:57/218/325` + `check_narrow.ss:12-26`)**

## 问题

I021-requestbody-nested-optional v0(commit 29c3148)端到端兑现**单层嵌套 nullable user class 字段**(`Order { addr: Address? }`),配合 D067 T? narrow + classFieldNullable Map 局部 metadata + jnIsNullOrMissing lib helper,emitDeserializeForType 加 `nullable T?` case(7 路 case 之前优先 dispatch),alloca slot 持值跨 block load 替 phi。

但 nullable 维度尚未覆盖**容器 inner**层 — `Array<Tag?>`(数组元素 nullable)/ `Map<string, Tag?>`(Map value nullable)是 enterprise REST API 真实业务高发场景:订单含 tag 列表部分元素可被删除标记 null / 库存 Map 值可空表 SKU 下架。

D130 SSoT 设计意图("per-class deserializer 单点解码,inner emit 委托同一 emitDeserializeForType 递归")**理论上自动 cover** 容器 inner nullable —— stripNullableCG(`Array<Tag?>`) = `Array<Tag?>` 不变(`?` 不在末尾),走 `isArrayDeserializable` case → emitArrayDeserializeInto inner 递归调 emitDeserializeForType(`Tag?`, ...)→ commit 29c3148 加的 nullable case 触发 ✓。

**本子档纯文档起立轮(Plan 型),Execute 留下下轮**:任务是锁定 v0 scope + 候选选定 + 根因预审 + 风险锚,实测验证 D130 SSoT 自动 cover 假设留 Execute 轮(若实测命中假设 → 仅加测试 + spring-parity 不动 codegen,**SSoT 设计意图首次实测兑现**;若不命中 → 升根 D130 emitDeserializeForType 字段类型透传路径)。

## 第一性需求

引 [D123 §第一性需求 + §247](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON → class 反序列化 | **任意 class(含嵌套含 nullable)** + Jackson/Gson 反序列化器") + [D130 §SSoT](../3-decisions/D130-deserializer-ssot-converge.md)("per-class deserializer 单点 emitDeserializeForType inner 委托") + D067 null safety("Kotlin/Dart 风格,默认非空,T? 可空")。

SS 用户写:

```ss
class Tag { name: string }
class Order { customer: string; tags: Array<Tag?> }   // 数组元素可空

@PostMapping("/orders/tags")
function createOrder(@RequestBody order: Order): string {
    let count = 0
    let nullCount = 0
    for (t in order.tags) {
        if (t != null) {
            // D067 T? narrow:此分支内 t 视为 Tag 非空
            count = count + 1
        } else {
            nullCount = nullCount + 1
        }
    }
    return "customer=" + order.customer + ",tags=" + count + ",nulls=" + nullCount
}
```

行为 byte-identical Java Spring(Jackson `List<Tag>` 元素 null 透传 store):

```java
public class Tag { String name; }
public class Order { String customer; List<Tag> tags; }   // 元素默认 nullable

@PostMapping("/orders/tags")
public String createOrder(@RequestBody Order order) {
    int count = 0, nullCount = 0;
    for (Tag t : order.tags) {
        if (t != null) { count++; } else { nullCount++; }
    }
    return "customer=" + order.customer + ",tags=" + count + ",nulls=" + nullCount;
}
```

curl 场景:

- `POST /orders/tags -d '{"customer":"alice","tags":[{"name":"a"},null,{"name":"c"}]}'` → `customer=alice,tags=2,nulls=1`
- `POST /orders/tags -d '{"customer":"alice","tags":[null,null]}'` → `customer=alice,tags=0,nulls=2`
- Map<string, Tag?> 类似:`{"items":{"sku-1":{"name":"x"},"sku-2":null}}` → 值 null 直接 store ptr null

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 commit 29c3148 emitDeserializeForType nullable T? case 的 D130 SSoT 自动 cover 路径** — `Array<Tag?>` 字段 → stripNullableCG 不变 → isArrayDeserializable 走 emitArrayDeserializeInto → inner element emit `emitDeserializeForType(Tag?, ...)` 递归 → 29c3148 nullable case 触发 → alloca slot + jnIsNullOrMissing check + 委托 stripped Tag 路径;Map<string,Tag?> 同理走 emitMapDeserializeInto → emitDeserializeForType(Tag?, jnGetField(...)) 递归 nullable case 自动激活 | **D130 SSoT 设计意图首次实测验证场景**(non-bypass) — 若假设命中 Execute 仅加测试 + spring-parity 不动 codegen,根因方案 ✓;若假设不命中(inner ft 透传断点)→ 升根 D130 emitDeserializeForType 字段类型透传(独立 D 文档),本轮锚为 §风险 2 |
| B | 给 emitArrayDeserializeInto / emitMapDeserializeInto 各自单独加 inner nullable case(不复用 emitDeserializeForType nullable case) | 违反 D130 SSoT(per-class deserializer 单点解码,inner 递归委托主路径);引入并行 codegen 路径致维护双轨 ❌ |
| C | runtime 反射元素类型 nullable 元数据自动检测 | 违反 [D088 §第一性需求](../3-decisions/D088-comptime-zig-route.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— D130 SSoT 设计意图自动 cover + commit 29c3148 nullable case 复用 + 测试 / spring-parity 兑现 Execute 主线。

## v0 scope 切分(本子档)

**In scope**(本轮 Plan,下下轮 Execute):

| In scope | 描述 |
|---|---|
| `Array<UserClass?>` 元素 nullable | 数组元素 store ptr null 逐元素分流;ss_drop_array_ptrs 自动级联 ss_release(ptr null)走 isnull guard(D018 + D023 ObjectLayout RC@0 + ptr null 不触发 mi_free,与 commit 29c3148 父档 §风险 1 实测 ss_release 自带 isnull guard line 289-290 同源)|
| `Map<string, UserClass?>` value nullable | Map.set transfer 时 value=ptr null 不触发 retain(retain 路径 isnull guard);ss_rc_destroy_map value 释放路径 isnull guard 同源 |
| inner nullable + 容器本身非 null | 容器层为 `Array<Tag?>` / `Map<string,Tag?>` 而非 `Array<Tag>?` / `Map<string,Tag>?`(容器自身 nullable 留独立 -optional-container 子档)|
| RC 契约严审 | Map ss_rc_destroy_map / Array ss_rc_destroy_array_ptrs 自动级联 ss_release(ptr null)→ no-op(D018 + D023 isnull guard 与父档 commit 29c3148 §风险 1 实测同源)|
| Cover 2-3 cell:数组元素 nullable + Map value nullable + 双 case 混合 RC stress(50 次 alloc/release 循环)| |

**Out of scope**(留独立子档,不混入本子档):

| Out of scope | 留子档名 | 描述 |
|---|---|---|
| `Array<int?>` / `Array<string?>` 元素 nullable primitive | `-optional-inner-primitive` | nullable primitive 走 boxing / 特殊 sentinel(D082 nullable primitive boxing 待立 / 已立诊断决定),涉独立 codegen 路径 |
| `Map<string, int?>` / 其他 nullable primitive value | `-optional-inner-primitive` | 同上 |
| `Array<Tag>?` / `Map<string,Tag>?` 容器自身 nullable | `-optional-container` | 容器自身 ptr null 路径(jnHasField + 全字段跳过 emit),完全不同 codegen 路径(jnIsNullOrMissing → store ptr null + skip inner emit)|
| `Array<Array<Tag?>>` / `Map<string, Map<string, Tag?>>` N=2 双层 nullable | `-deep-optional` | N=2/3/4 层嵌套 + nullable 元素正交维度;依本子档 + nested-deep(commit f301e76)双 v0 收关后独立验证 |
| `Tag??` 双 nullable | 留独立(语义不明,可能拒绝 — Kotlin/Dart 两层 nullable 等价单层)| |

**v0 scope 不做**:
- 不动 codegen(D130 SSoT 自动 cover 假设 Execute 阶段实测验证;命中 = 0 codegen 改动,不命中 = 升根独立 D 文档)
- 不动 lib/json.ss(commit 29c3148 jnIsNullOrMissing 已就绪,inner emit 复用)
- 不引新关键字 / 新语法(D067 T? + D130 SSoT 已就绪)
- 不实现 nullable primitive(留 -optional-inner-primitive)
- 不实现容器自身 nullable(留 -optional-container)
- 不实现 N=2 双层 nullable(留 -deep-optional)

## 根因预审(D130 SSoT 自动 cover 假设链)

**当前 emitDeserializeForType nullable case dispatch 路径**(commit 29c3148 bootstrap/gen/gen_deserialize.ss):

```
emitDeserializeForType(ft, ...) 入口
├── if ft endsWith "?" → 加的 nullable case(本轮基线)
│   ├── alloca i8* slot
│   ├── call @jnIsNullOrMissing(node)
│   ├── br i1 → opt_null label: store ptr null to slot, br opt_done
│   │       → opt_present label: stripped = stripNullableCG(ft), 委托递归 emitDeserializeForType(stripped, ...) → store result to slot, br opt_done
│   └── opt_done: load slot
└── 7 路 case (string/int/double/bool/Array/Map/UserClass) 后续 dispatch
```

**容器 inner nullable 自动 cover 链验证**(本子档 §假设):

1. **`Array<Tag?>` 字段类型** stripNullableCG = `Array<Tag?>` 不变(`?` 在 inner 不在末尾)→ **不**走 nullable case
2. dispatch 落 `isArrayDeserializable` case → 走 `emitArrayDeserializeInto`
3. emitArrayDeserializeInto 内部对每个 array element emit `emitDeserializeForType(elemType=`Tag?`, jnArrayGet(arrNode, i))` 递归
4. 递归入口 elemType=`Tag?` endsWith `?` ✓ → **触发 nullable case**(commit 29c3148 加的)
5. nullable case 内 jnIsNullOrMissing(elemNode) → null → store ptr null;非 null → 委托 `emitDeserializeForType(Tag, ...)` 递归 → ss_Tag_deserialize → store ptr
6. **D130 SSoT 设计意图首次自动验证** ✓(per-class deserializer inner 递归委托主路径,nullable case 复用零额外代码)

**Map<string, Tag?> value nullable 自动 cover 链同源**:emitMapDeserializeInto inner emit `emitDeserializeForType(vType=Tag?, jnGetField(mapNode, key))` 递归 → nullable case 触发 → store ptr null 或 ss_Tag_deserialize 结果。

**实测验证义务(Execute 阶段)**:

```bash
# 测试 1: emit-ir 看 Array<Tag?> 字段是否自动包含 jnIsNullOrMissing call + opt_present/opt_done label
bin/ss build /tmp/t_optional_inner.ss --emit-ir -o /tmp/t.ll
grep -E "@jnIsNullOrMissing|opt_present|opt_done|opt_null" /tmp/t.ll | wc -l
# 预期: ≥ 4 (nullable case 在 inner emit 时被激活)

# 测试 2: 端到端 raw HTTP POST /orders/tags
curl -X POST 'http://localhost:8080/orders/tags' -H 'Content-Type: application/json' \
  -d '{"customer":"alice","tags":[{"name":"a"},null,{"name":"c"}]}'
# 预期: customer=alice,tags=2,nulls=1
```

**假设破裂回退路径**:若 emit-ir 未自动激活 nullable case(说明 emitArrayDeserializeInto / emitMapDeserializeInto 内部 elemType / vType 透传时 strip 掉了 `?` 后缀)→ 升根:

- D130 SSoT 升级:emitDeserializeForType 字段类型透传不丢 nullable 修饰
- 独立 D 文档讨论(本子档锚为 §风险 2,Execute 阶段实测决定升根触发)

## 步骤(Execute 轮按序)

1. **RED 命令**(Plan 起立轮已跑;Execute 阶段重跑验证状态):

   ```bash
   # RED 1: 测试文件不存在
   ls tests/phase5/i021_requestbody_nested_optional_inner.ss 2>&1 | grep -c "No such"
   # before: 1, after: 0

   # RED 2: spring-parity OrderTags fixture 缺失
   grep -cE "class Tag|Array<Tag\?>|tags.*Array" examples/spring-parity/hello/ss/HelloController.ss
   # before: 0, after: ≥ 2

   # RED 3: D130 SSoT 自动 cover 假设实测
   bin/ss build /tmp/t_optional_inner.ss --emit-ir -o /tmp/t.ll && \
     grep -cE "@jnIsNullOrMissing|opt_present" /tmp/t.ll
   # before: 0 (测试源文件不存在), after: ≥ 4 (假设命中) 或 0 (假设破裂 → 升根)
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss + .java** 加 `class Tag` + `class OrderTags { customer:string; tags: Array<Tag?> }` + `@PostMapping("/orders/tags") createOrderTags(@RequestBody order: OrderTags)`(注:与 commit 29c3148 已加 OrderOpt + Address 命名隔离);Java oracle 同步加 `List<Tag> tags`。

3. **tests/phase5/i021_requestbody_nested_optional_inner.ss** 新建 ~140 行 7 case:
   - case 1:`Array<Tag?>` 元素 [{...},null,{...}] → tags=2,nulls=1
   - case 2:`Array<Tag?>` 全 null → tags=0,nulls=N
   - case 3:`Array<Tag?>` 全非 null → tags=N,nulls=0
   - case 4:`Map<string, Tag?>` value null vs object → 双路径分流
   - case 5:`Map<string, Tag?>` 全 null value → 全 ptr null 走 ss_release isnull guard 不 segfault
   - case 6:全链路 raw HTTP POST `/orders/tags` 三场景 byte-identical Java
   - case 7:RC stress 50 次循环(混合 null + 非 null 元素)→ no leak / no segfault

4. **D130 SSoT 自动 cover 假设实测 + 分流**:
   - **假设命中**(emit-ir 自动激活 nullable case)→ Execute 阶段**零 codegen 改动**,仅加测试 + spring-parity + lib/json.ss / bootstrap/gen/gen_deserialize.ss 不动;**D130 SSoT 设计意图首次自动兑现**,commit message 明锚"D130 SSoT 设计意图自动 cover 验证 — 零 codegen 改动"
   - **假设破裂**(inner ft 透传断点) → 升根 D130 emitDeserializeForType 字段类型透传补齐 → 独立 D 文档讨论(本子档 Execute 轮停手,改写 next_prompt 立 D 文档子决策)

5. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。纯文档轮 simplify 豁免。

6. **commit + push**:format `feat(I021-requestbody-nested-optional-inner,D123,D129,D130,D067): 容器 inner nullable Array<T?> / Map<string,V?> 反序列化 — D130 SSoT 设计意图首次自动 cover 验证 — Phase 4 §247 第二支柱嵌套深化第八轮`。

## 反向 / 备选

(同上候选 A/B/C 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-optional-inner.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)+ `grep -cE "Array<.*\?>|Map<.*,.*\?>|nullable inner|inner.*nullable" docs/4-issues/I021-requestbody-nested-optional*.md` 当前 = 1(本轮 Write 后 ≥ 5)+ `grep -cE "D067|D123|D129|D130" docs/4-issues/I021-requestbody-nested-optional-inner.md` ≥ 4
- **Execute 轮 RED before**:见 §步骤 §1(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_optional_inner.ss` exit 0,7 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders/tags` 三场景 byte-identical Java oracle
- **Execute 轮 after(假设命中分支)**:`git diff --stat HEAD -- bootstrap/ lib/` 空输出(零 codegen 改动)+ emit-ir grep `@jnIsNullOrMissing|opt_present|opt_done` ≥ 4
- **Execute 轮 after(假设破裂分支)**:停手转 D 文档子决策,bootstrap/ 不直改,改写 next_prompt
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions

## 风险 / 表面 / 下轮升根路径

1. **D130 SSoT 自动 cover 假设破裂检测**:Execute 阶段第一步必须 emit-ir 实测验证 — 若 `@jnIsNullOrMissing` / `opt_present` / `opt_done` 未在 Array element / Map value 路径出现 → 假设破裂,**停手转 D 文档子决策**(emitArrayDeserializeInto / emitMapDeserializeInto 内 elemType / vType 透传 strip `?` bug)。**禁止**为绕过假设破裂在 emitArrayDeserializeInto / emitMapDeserializeInto 内独立加 nullable check(走候选 B 路径违反 D130 SSoT)。

2. **D130 SSoT 升根路径预案**(假设破裂触发):
   - 立 `docs/3-decisions/D131-emit-deserialize-inner-type-pass-through.md`(暂名)D 文档子决策
   - 修 emitArrayDeserializeInto / emitMapDeserializeInto 内 elemType / vType 字段类型透传保留 `?` 后缀(类比 commit 29c3148 classFieldNullable Map 局部 metadata 模式)
   - 跨 Layer Decision,本子档 Execute 阶段触发但不主动改 codegen(单轮 Layer 不混)

3. **inner element ss_release(ptr null) RC 契约严审**:
   - `Array<Tag?>` 元素 store ptr null 时 ss_drop_array_ptrs 释放路径自动 ss_release(ptr null)
   - 父档 commit 29c3148 §风险 1 实测 ss_release 自带 isnull guard(line 289-290),空值不触发 mi_free 行为定义良好
   - 本子档 v0 假设同源(数组元素 ss_release 与字段 ss_release 走同一 ss_release 函数,isnull guard 等价覆盖)
   - **若实测发现 ss_drop_array_ptrs 不走 ss_release 而走低层路径** → 升根 ss_drop_array_ptrs 加 isnull guard(本子档 §风险 锚)

4. **Map<string, Tag?> retain / release 契约**:
   - Map.set value=ptr null 时不应触发 retain(retain 自带 isnull guard 同源)
   - ss_rc_destroy_map value 释放路径 isnull guard 同源
   - 实测命令:`bin/ss test tests/phase5/i021_requestbody_nested_optional_inner.ss` 全绿 + Valgrind / mimalloc no-leak 报告

5. **D067 T? narrow 编译期配合 element 维度**:
   - 用户写 `for (t in order.tags) { if (t != null) { t.name } }` checker T? narrow 应在 for-in body 内激活
   - check_stmts.ss:325 加的 narrow 路径覆盖 if-then 但**未必覆盖 for-in body 内的 IDENT t**(commit 29c3148 父档 §风险 3 已锚 D067 narrow 限 IDENT 形态)
   - 若实测发现 for-in body 内 narrow 不生效 → 用户绕路 `let a = t; if (a != null) { a.name }`(D067 现状合法用法,与父档 OrderOpt 路径同源)
   - 升根:扩 D067 narrow cover for-in body element(独立 D067 子档,本子档不主动改 checker)

6. **`-optional-array` vs `-optional-inner` 锚名 scope 重叠分工**:
   - 父档 line 86 已锚 `-optional-array`(scope:`Array<Class>?` 容器自身 + `Array<Class?>` 元素 — 双层 nullable 维度)
   - 本子档 `-optional-inner`(scope:`Array<UserClass?>` 元素 + `Map<string, UserClass?>` value — inner 元素 nullable 维度,**按 nullable 位置切**而非按 collection 类型切)
   - **分工调整**(本子档 Plan 起立时间晚 + 优先 ship):本子档主导 inner 维度;父档 line 86 `-optional-array` 锚精神被本子档(inner)+ 未来 `-optional-container`(容器自身)合并取代,**本子档 §备注 显式说明分工**;父档 line 86 不主动改写(避免污染父档 history),保持追加 `-optional-inner` 锚即可

## 触发场景

- 接到 enterprise REST API 含可空容器元素 DTO(`Order { tags: Array<Tag?> }` / `Inventory { items: Map<string, Item?> }` / 部分 element 删除标记 null / Map value 表示 SKU 下架)
- D123 §247 Phase 4 §第二支柱嵌套深化第八轮(commit 29c3148 第七轮 nullable 字段后续 nullability 维度向 inner 扩展)
- D130 SSoT 设计意图首次实测验证场景(per-class deserializer inner 递归委托主路径,nullable case 复用零额外 codegen)
- D129 §94 "@RequestBody | 任意 class(含嵌套含 nullable 含容器 inner nullable)" 域语义全维度兑现
- D067 null safety T? narrow 在容器 element 维度反序列化路径实测覆盖

## Execute 阶段第一步实测验证记录(2026-04-26)

**D130 SSoT 自动 cover 假设破裂确认** —— 实测命令:

```bash
bin/ss build /tmp/t_optional_inner.ss --emit-ir -o /tmp/t.ll > /tmp/t.ll
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

**根因定位**:`isArrayDeserializable("Array<Tag?>")` → et = "Tag?" → `isUserClass("Tag?")` = 0(classFields.has("Tag?") = 0,注册的是 "Tag" 不带 `?`)→ 谓词返回 0 → emitDeserializeForType 字段层走 fallback `add i64 0, 0`,**根本进不到 emitArrayDeserializeInto**;子档 §风险预案诊断方向"emitArrayDeserializeInto / emitMapDeserializeInto 内 elemType / vType 透传 strip `?`"方向对但物理位置在更上游谓词层(extractContainerElemType + emitArrayDeserializeInto:174+199 / emitMapDeserializeInto:222+254 透传实际正确保留 `?`)。

**升根 D131 子决策**:[D131-deserialize-predicate-strip-nullable-inner.md](../3-decisions/D131-deserialize-predicate-strip-nullable-inner.md) Decided(2026-04-26)— 谓词层 `isArrayDeserializable` / `isMapDeserializable` 加 `stripNullableCG(et/vt)` 后再判 isUserClass(et)/Array(et)/Map(et)/primitive(et) 路径;extractContainerElemType + emitArrayDeserializeInto/emitMapDeserializeInto 内透传不动,nullable case 复用 commit 29c3148 emitDeserializeForType 主路径。

**本子档 Execute 阶段路径**(D131 GREEN + I021 v0 ship 同轮 commit 74ddc48 兑现):
- D131 §4 修 `bootstrap/gen/gen_deserialize.ss:14-19 isArrayDeserializable + :28-33 isMapDeserializable + :64-72 emitPendingDeserializers BFS`(谓词内 stripNullableCG inner) ✓
- D131 §4.5 同源补 `bootstrap/gen/gen_types.ss:417 inferType .get + bootstrap/gen/gen_builtins.ss:302-313 genMapMethod .get`(Execute 阶段实测发现的 §4 边界扩 — extractMapValueType 返 "Tag?" 后 classFields.has 不命中导致 LET 分配 ptr 而 RHS i64 → llc store mismatch) ✓
- 新建 `tests/phase5/i021_requestbody_nested_optional_inner.ss` 7 case(本子档 §步骤 §3) ✓
- spring-parity hello + Java oracle 对称(本子档 §步骤 §2) ✓
- emit-ir grep `@jnIsNullOrMissing` = 3 + `opt_present|opt_done` = 8 + Tag_deserialize = 1(BFS strip 入队验证) ≥ 1 ✓
- bootstrap 三阶段固定点 stage2==stage3 PASS + reflection_health_linter F1 GATE PASS(gen_types.ss cur=791 ≤ bm=792)+ phase4 27/27 + phase5 192/196(0 regression — 4 baseline FAIL 与改动前一致) ✓

**本子档 status**:Done at <bootstrap/gen/gen_deserialize.ss:14-19,28-33,64-72 + bootstrap/gen/gen_types.ss:417 + bootstrap/gen/gen_builtins.ss:302-313 + tests/phase5/i021_requestbody_nested_optional_inner.ss + examples/spring-parity/hello/{ss,java}/HelloController.{ss,java}>(commit 74ddc48 — Phase 4 §247 第二支柱嵌套深化第八轮收关)

## 备注

- 本子档**Plan 起立(commit c68d443)+ Execute 阶段第一步实测验证(commit 待本轮)** —— Execute 主线落地(谓词修 + 7 case + spring-parity)留下轮(按 §交互式单文档:每轮一目标 + 子档预审 §风险 2 锚跨 Layer Decision 单 Layer 不混)
- D067 物理 D 文档不存在(`ls docs/3-decisions/D067*.md` = No such file),SSoT 在 memory `project_null_safety_design.md` + bootstrap/checker `check_stmts.ss:57/218/325` + `check_narrow.ss:12-26`;本子档**显式标 D067 概念锚不创新死链 markdown link**(feedback `feedback_user_literal_vs_d_ssot.md` 引用前 ls 真身防虚锚);父档既有 `[D067 null safety](../3-decisions/D067-null-safety.md)` 死链沿用 issue 层惯例(d_doc_index_linter scope 不含 docs/4-issues/),本子档不主动修父档死链(out of scope)
- D123 §247 Phase 4 §第二支柱已 Decided + 第七轮 Done,本子档执行不再辨析
- D129 §94 @RequestBody 域含嵌套含 nullable 已 Decided,本子档接续 nullable 维度向 inner 扩展
- D130 SSoT 已 Decided + 第六/第七轮自动 cover 验证(c52e9b5 Map<string, Class> + 95eb282 Map<string, primitive> + b18850e nested cartesian 都走 SSoT inner 委托零 codegen 改动),本子档将 SSoT 验证扩展到 nullable 维度(第八轮 — 首次容器 inner nullable 实测)
- D067 null safety 已落实编译期 T? narrow + extractNullCheckVar IDENT 形态,本子档 v0 不动 checker 仅复用父档 commit 29c3148 codegen + lib 路径
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化**第八轮**(深化维度递进:首轮 nested.md 单层非空 → 二轮 nested-array Array → 三轮 nested-map Map → 四轮 nested-deep N>1 层 → 五轮 nested-cartesian 笛卡尔积 → 六轮 nested-map-primitive primitive value → 七轮 nested-optional 单层 nullable 字段 → **八轮 nested-optional-inner 容器 inner nullable**)
- **依赖关系**:本子档 Execute 轮可独立于 -optional-container / -optional-deep-optional / -optional-inner-primitive 推进(nullability 位置维度正交 — inner element vs container 自身 vs N=2 双层 vs primitive vs class);Execute 顺序建议 -optional-inner(本子档) → -optional-container → -deep-optional → -optional-inner-primitive(complexity + scope 风险递进)
- **scope 重叠分工**:父档 line 86 `-optional-array` 锚的 "数组本身可空 vs 元素可空" 双层维度被本子档(`-optional-inner` inner element)+ 未来 `-optional-container`(容器自身 nullable)合并取代;本轮**追加** `-optional-inner` 锚到父档 line 86 后,**不主动改写或删除**已锚 `-optional-array`(避免 churn);未来 `-optional-container` 子档立时再做父档 line 86 §留下轮锚的统一收敛
