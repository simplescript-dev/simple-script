# I021-requestbody-nested-map-primitive:嵌套 `Map<string, int|string|double|bool>` primitive value 反序列化

> 父档:[I021-requestbody-nested-map.md](./I021-requestbody-nested-map.md)(commit c52e9b5 — `Map<string, Class>` 反序列化 + D130 emitDeserializeForType SSoT 收敛)
> 祖档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层嵌套 user class scalar 字段端到端)
> 祖祖档:[I021-requestbody.md](./I021-requestbody.md)(commit 8165370 — Phase 4 §247 第二支柱端到端兑现)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody V=class 域含嵌套+collection](../3-decisions/D129-request-param-class-domain.md) + [D130 emitDeserializeForType SSoT 收敛](../3-decisions/D130-deserializer-ssot-converge.md)

## 问题

I021-requestbody-nested-map v0(commit c52e9b5)端到端兑现 `Map<string, Class>` 反序列化(`OrderMeta { customer: string; metadata: Map<string, Tag> }`),同轮 D130 起立 `emitDeserializeForType` SSoT 7 路单点解码 + `emitMapDeserializeInto` 内部 inner value dispatch 委托递归。

I021-requestbody-nested-map.md line 78/83 §留下轮锚 已声明:"**I021-requestbody-nested-map-primitive** — `Map<string, int>` / `Map<string, string>` primitive value(本子档 v0 仅 `Map<K, Class>`;primitive value 走 jnGetInt/String 直接路径)" — **scope 显式留本子档**。

**D130 收敛后状态**(`bootstrap/gen/gen_deserialize.ss`):
- `emitDeserializeForType(ssType, jsonNodeR) -> i64 reg` 7 路 case(line 90-143):int/double/string/bool/UserClass/Array/Map
- `emitMapDeserializeInto` (line 197-239) inner value dispatch 委托:`const valI64R = emitDeserializeForType(vType, valNodeR)` (line 230)
- val_type=1 写 offset 516 条件:`if (ssTypeToLLVM(vType) == "ptr")` (line 201-205) — primitive vType (int/double/bool) 默认 0,string vType 写 1

→ **codegen 主路径自动覆盖 Map<string, primitive>**,但**未被任何 RED 端到端测试 / 全链路 parity 锁定**:
1. `ss_mapSet` i64 直存 primitive(sext int / bitcast double / zext bool / ptrtoint string)契约未被实测
2. val_type=0 (primitive) vs val_type=1 (string) 二分自动选择(emitMapDeserializeInto:201-205)未被 4 vType 端到端覆盖
3. Map drop 链对 primitive value Map(无 elem release)vs string value Map(走 ss_rc_release elem)双族契约未实测
4. `examples/spring-parity/hello/` 未含 primitive value Map DTO

enterprise REST API 高频形态:`@RequestBody Order { tags: Map<string, string>, scores: Map<string, int>, prices: Map<string, double>, flags: Map<string, bool> }` — K8s ConfigMap-like / Stripe metadata-like / config-like DTO 维度。v0 落地后,Map<K,V> 嵌套维度 V 域(class + 4 primitive)封顶。

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md) + [D130 §SSoT 收敛](../3-decisions/D130-deserializer-ssot-converge.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套 + collection)** + Jackson/Gson 反序列化器 | HTTP body")。

SS 用户写:

```ss
class OrderConfig {
    customer: string
    tags: Map<string, string>
    scores: Map<string, int>
    prices: Map<string, double>
    flags: Map<string, bool>
}

@PostMapping("/orders/config")
function createOrderConfig(@RequestBody order: OrderConfig): string {
    let env = order.tags.get("env")
    let qty = order.scores.get("qty")
    return "env=" + env + ",qty=" + qty
}
```

行为 byte-identical Java Spring:

```java
public class OrderConfig {
    String customer;
    Map<String, String> tags;
    Map<String, Integer> scores;
    Map<String, Double> prices;
    Map<String, Boolean> flags;
}

@PostMapping("/orders/config")
public String createOrderConfig(@RequestBody OrderConfig order) {
    String env = order.tags.get("env");
    Integer qty = order.scores.get("qty");
    return "env=" + env + ",qty=" + qty;
}
```

curl `POST /orders/config -H 'Content-Type: application/json' -d '{"customer":"alice","tags":{"env":"prod","region":"us"},"scores":{"qty":100,"limit":500},"prices":{"unit":1.5},"flags":{"active":true}}'` → `env=prod,qty=100`。

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 D130 SSoT 自动覆盖 + 纯 RED 测试 + parity DTO 端到端锁定**:`emitDeserializeForType` primitive 4 路(int/string/double/bool,gen_deserialize.ss:91-119)+ `emitMapDeserializeInto` inner dispatch 委托(line 230)— c52e9b5 已落,**零 codegen 新加分支** + **零 lib/json 新 helper**;本子档 Execute 轮 = (1) `tests/phase5/i021_requestbody_nested_map_primitive.ss` 加 ~120 行 6 case (2) `examples/spring-parity/hello/ss/HelloController.ss` + Java oracle 加 OrderConfig DTO + `@PostMapping("/orders/config")` (3) bootstrap 三阶段固定点 + reflection_health_linter PASS | D130 SSoT 已设计承载 vType primitive 路径,本子档**纯锁定轮**(对齐 §交互式单文档:每轮一目标 + feedback_root_cause_no_cost — D130 是根因层方案,本子档不需另起独立 codegen 路径);Execute 轮 LOC 量级 ~ 150(测试 + 2 个 DTO + 1 commit)远小于 nested-array-primitive(~ 350);[D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md) ✅ |
| B | 重新 inline emit primitive value Map 4 路独立分支(脱离 emitDeserializeForType SSoT)| 违反 D130 SSoT 设计意图 + 独立四轨制双轨化 ❌ |
| C | runtime 反射递归遍历 map entries 元数据自动 deserialize | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— D130 SSoT 自动覆盖 + 纯 RED 锁定。

## v0 scope 切分说明(本子档)

**落地**:

- 单层嵌套 `Map<string, primitive>` 字段,V ∈ {int/string/double/bool} 4 vType 全 cover
- key 类型限 `string`(JSON object key 标准形态;非 string key 留 -map-typed-key 子档,与 nested-map.md §留下轮锚同位)
- **零 codegen / 零 lib/json 改动**(D130 SSoT 已就绪;`jnAsInt/Double/String/Bool` lib/json.ss:261-279 已加,`jnObjectKeys` line 357 已加)
- 测试 IR 锚:`grep -E "@jnAsInt|@jnAsString|@jnAsDouble|@jnAsBool|@ss_mapSet|@ss_mapNew|getelementptr i8, ptr.*i64 516" /tmp/t_i021_map_prim.ll` 关键 anchor — `i64 516` (val_type 写) **仅 string vType 一字段出现**,int/double/bool vType 字段不出现(对照 D130 emitMapDeserializeInto:201-205 条件)
- 全链路 raw HTTP POST `/orders/config` byte-identical Java oracle
- spring-parity HelloController.ss + Java oracle 加 OrderConfig DTO

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立或承接):

- **I021-requestbody-nested-map-typed-key** — `Map<int, V>` / `Map<UUID, V>` 等非 string key 反序列化(JSON object key 始终 string,需编译期 string→K cast;独立复杂度,nested-map.md §留下轮已锚)
- **I021-requestbody-nested-map-array** — `Map<string, Array<X>>` / `Map<string, Map<string, Y>>` 三层嵌套(N=3 容器层 RC 三层契约累积,与 nested-array-array / nested-deep 同维度)

**v0 scope 不做**:

- 不实现 `Map<int, V>` / `Map<UUID, V>` 等非 string key(留 -map-typed-key)
- 不实现 `Map<string, Array<X>>` / `Map<string, Map<X, Y>>` 三层嵌套(留 -map-array)
- 不实现 N>1 层嵌套 Map<string, primitive>(留 [I021-requestbody-nested-deep](./I021-requestbody-nested-deep.md))
- 不实现 nullable `Map<string, int>?` 空安全(留 [I021-requestbody-nested-optional](./I021-requestbody-nested-optional.md) + D067 narrow)
- 不实现顶层 `@RequestBody scores: Map<string, int>`(留 I021-requestbody-map 平级独立子档,本子档 scope 限"嵌套字段")
- 不引入新关键字 / 新语法 / 不改 codegen / 不扩 lib/json

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   # RED 1: 测试文件不存在
   ls tests/phase5/i021_requestbody_nested_map_primitive.ss 2>&1 | grep -c "No such"
   # before: 1  after(Execute 轮 Write 后): 0

   # RED 2: spring-parity HelloController 无 OrderConfig DTO
   grep -cE "class OrderConfig|orders/config" examples/spring-parity/hello/ss/HelloController.ss
   # before: 0  after: ≥ 2(class 定义 + 路由路径)

   # RED 3: 端到端 emit IR 已自动 cover(确认 D130 SSoT 自动覆盖,无需 codegen 改动)
   bin/ss build tests/phase5/i021_requestbody_nested_map_primitive.ss -o /tmp/t_i021_map_prim --emit-ir 2>&1 | grep -cE "@jnAsInt|@jnAsString|@jnAsDouble|@jnAsBool"
   # 期望:首次跑必绿(test 文件就位即生 IR 走 D130 SSoT 4 primitive 路径)
   # 若失败:升根 D130 emitDeserializeForType / emitMapDeserializeInto,不在 Execute 层加 workaround
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss** 加 `class OrderConfig { customer: string; tags: Map<string, string>; scores: Map<string, int>; prices: Map<string, double>; flags: Map<string, bool> }` + `@PostMapping("/orders/config") createOrderConfig(@RequestBody order: OrderConfig)`(命名独立于已有 `Order` / `OrderList` / `OrderMeta` / `OrderPrim` / `DeepNest` 等);Java oracle 同步 `examples/spring-parity/hello/java/.../HelloController.java`。

3. **tests/phase5/i021_requestbody_nested_map_primitive.ss** 新建 ~120 行 6 case:
   - case 1:`Map<string, string>` size=2 + `m.get("env") == "prod"` + `m.get("region") == "us"`
   - case 2:`Map<string, int>` size=2 + `m.get("qty") == 100` + `m.get("limit") == 500`
   - case 3:`Map<string, double>` size=1 + `m.get("unit")` 用 `assertNearlyEqual(actual, 1.5, 0.001)` epsilon 容忍
   - case 4:`Map<string, bool>` size=1 + `m.get("active") == 1`(bool 在 SS 里编码为 i32,1=true / 0=false)
   - case 5:空 Map `{}` 4 vType 全空 size=0,父 OrderConfig drop 链不破裂(无 use-after-free / 无 leak)
   - case 6:全链路 raw HTTP POST `/orders/config -d '{"customer":"alice","tags":{...},"scores":{...},"prices":{...},"flags":{...}}'` byte-identical Java oracle
   - IR 锚 `grep -cE "@ss_mapNew|@ss_mapSet|@jnAsInt|@jnAsString|@jnAsDouble|@jnAsBool" /tmp/t_i021_map_prim.ll` ≥ 8 + `grep -c "i64 516" /tmp/t_i021_map_prim.ll` = 1(仅 `Map<string, string>` 字段写 val_type=1,int/double/bool 字段不写)

4. **bootstrap fix**:**N/A**(D130 SSoT 已 cover)— Execute 轮如发现 emit IR 实际不通,**立即升根** D130 SSoT 漏掉的 vType 分支按"根因优先"rule 修 `emitDeserializeForType` / `emitMapDeserializeInto` / `ss_mapSet`,不在 Execute 层加 workaround(对照 [feedback_root_cause_no_cost](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_root_cause_no_cost.md):编译器 bug 必修 codegen / RC 逻辑)。

5. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。本子档 Execute 轮**测试代码 ~ 120 行**为主,可读性优先;无 helper 抽取倾向(case-by-case 测试代码不应过度抽象)。

6. **commit + push**:format `feat(I021-requestbody-nested-map-primitive,D123,D129,D130): Map<string, int|string|double|bool> primitive value 反序列化端到端锁定(零 codegen 改动 — D130 SSoT 自动覆盖)— Phase 4 §247 第二支柱嵌套深化第七轮`。

## 反向 / 备选

(同上候选 A 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-map-primitive.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:见 §步骤 §1 RED 命令(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_map_primitive.ss` exit 0,6 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders/config -d '{...,"tags":{...},"scores":{...},"prices":{...},"flags":{...}}'` 返 byte-identical Java oracle
- **Execute 轮 after**:`grep -cE "@ss_mapNew|@ss_mapSet|@jnAsInt|@jnAsString|@jnAsDouble|@jnAsBool" /tmp/t_i021_map_prim.ll` ≥ 8
- **Execute 轮 after**:`grep -c "i64 516" /tmp/t_i021_map_prim.ll` = 1(**仅 string vType 字段写 val_type;反向断言 D130 emitMapDeserializeInto:201-205 ssTypeToLLVM 二分契约正确**)
- **Execute 轮 after**:bootstrap 三阶段固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions(predict no F1 regression — gen_deserialize.ss 当前在 baseline 容量内,本子档 Execute 轮零 codegen 改动)

## 风险 / 表面 / 下轮升根路径

1. **D130 SSoT 漏 vType 分支风险(关键)**:Plan 阶段静态 grep 已确认 `emitDeserializeForType` 7 路 + `emitMapDeserializeInto` 委托正确,但 Execute 轮端到端 RED 才能验证 `ss_mapSet` 对 sext int / bitcast double / zext bool / ptrtoint string i64 直存契约;**若 RED 失败必走 D130 升根路径**(修 emitDeserializeForType / emitMapDeserializeInto / ss_mapSet / ss_rc_destroy_map),不在 Execute 层加 workaround(对照 feedback_root_cause_no_cost:编译器 bug 必修 codegen / RC 逻辑)。

2. **val_type 二分契约严审(关键 IR 锚)**:`emitMapDeserializeInto`:201-205 `if (ssTypeToLLVM(vType) == "ptr")` 写 val_type=1 — 对 primitive vType (int/double/bool) val_type 默认 0(`ss_rc_calloc` 清零);Execute 轮 IR 锚 `grep -c "i64 516"` 必须严格按 vType 字段数:
   - `Map<string, int>` 字段 → 0 处 (val_type=0)
   - `Map<string, string>` 字段 → 1 处 (val_type=1)
   - `Map<string, double>` 字段 → 0 处
   - `Map<string, bool>` 字段 → 0 处
   - **混合 4 vType 字段 OrderConfig 共计 = 1 处**(仅 string vType);若 ≠ 1 则契约破裂,Execute 轮升根 `emitMapDeserializeInto` 二分逻辑

3. **Map drop 链对 primitive value Map 不触发 elem release**:
   - tag-based dispatcher (`ss_rc_destroy_map`) 走 val_type 字段判断;val_type=0 → 仅 free 容器(无 elem release),对齐 primitive 无 RC 协议
   - val_type=1 → 逐 entry value `ss_release` (走 string ss_release_str / class drop_C 自动级联)
   - **风险**:若 `ss_rc_destroy_map` 实现错位(对 val_type=0 仍触发 elem release → invalid free i64 数值),Execute 轮端到端 use-after-free 暴露;升根修 `ss_rc_destroy_map` 而非 `emitMapDeserializeInto`

4. **double 字段 epsilon 容忍**:case 3 `m.get("unit") == 1.5` JSON parse double 受浮点精度影响,可能需 `assertNearlyEqual(actual, 1.5, 0.001)` 而非严格 `==`;Execute 轮按 lib/json 现状决定测试断言形式(若 lib/json double parse 精确还原 1.5 则 == OK,否则 epsilon)。

5. **bool 编码 SS 内部 i32 协议对齐**:Map<string, bool>.get 返 i64 → SS 用户层用 `== 1` / `== 0` 对比(bool 在 SS 编码为 i32,Map vType 委托 emitDeserializeForType bool 路径走 `jnAsBool` + `zext i32 to i64`);Execute 轮严审用户层断言写法对齐 SS bool 编码协议(对照 nested-array-primitive case 4 同模式)。

6. **本子档 LOC 量级 ~ 200**(单文档完整;Plan + 步骤 + 风险 + 锚)— 比 nested-array-primitive ~ 280 略短(因 zero codegen 改动 + 零 helper 扩);与 nested-map ~ 200 量级对齐。

**Plan 阶段 plumbing 完整**:本子档 Execute 轮无表面遗留;D130 SSoT 已设计层覆盖 vType primitive 4 路 + val_type 二分自动正确,本子档为锁定测试 + parity DTO 兑现轮。

## 触发场景

- 接到 enterprise REST API 业务实现含 metadata / tags / config / scores 等 Map<string, primitive> 字段 DTO(K8s ConfigMap, Stripe metadata, AWS tags, configuration store)
- D129 §94 "@RequestBody | 任意 class(含嵌套 + collection)" 域语义 V 维度 primitive 兑现
- D130 SSoT 收敛后嵌套 Map primitive value 路径**首次端到端锁定**(c52e9b5 仅 Map<string, Class> v0 + 4 case;本子档承接 vType primitive 4 路)
- I021-requestbody-nested-map.md line 78/83 §留下轮锚 承接

## 备注

- 本子档**纯文档起立轮**,Execute 留下下轮(按 §交互式单文档:每轮一目标)
- nested-map.md line 168-187 父档已锚 Map<K, Class> RC 契约,本子档承接 vType primitive 维度
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)+ D130 SSoT 收敛设计已 Decided,本子档执行不再辨析
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化第七轮(深化 = collection 维度 Map vType primitive;嵌套深化轮:第一 nested.md / 第二 nested-array / 第三 nested-array-primitive / 第四 nested-array-array / 第五 nested-deep / 第六 nested-map / **本第七 nested-map-primitive**)
- 本子档 Execute 轮**零 codegen / 零 lib/json 改动 = D130 SSoT 收敛设计的兑现验证轮**(对照 D130 设计意图:每加新类型 O(1) 而非 O(3),本子档实测 vType primitive 路径 O(0) — 已就绪只需 RED 锁)
