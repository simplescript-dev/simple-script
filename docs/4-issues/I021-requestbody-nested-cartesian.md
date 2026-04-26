# I021-requestbody-nested-cartesian:嵌套 collection 笛卡尔积 SSoT 端到端锁定

> 父档:[I021-requestbody-nested-map-primitive.md](./I021-requestbody-nested-map-primitive.md)(commit 95eb282 — `Map<string, primitive>` 4 vType 反序列化端到端锁定;零 codegen 改动 D130 SSoT 自动覆盖)
> 祖档:[I021-requestbody-nested-map.md](./I021-requestbody-nested-map.md)(commit c52e9b5 — `Map<string, Class>` 反序列化 + D130 emitDeserializeForType SSoT 收敛单点解码)
> 祖祖档:[I021-requestbody-nested-array-array.md](./I021-requestbody-nested-array-array.md)(commit 5b25573 — 2D `Array<Array<X>>` + emitArrayDeserializeInto SSoT helper)
> 祖祖祖档:[I021-requestbody-nested-deep.md](./I021-requestbody-nested-deep.md)(commit f301e76 — N=3/4/5 多层 `Array<Array<Array<X>>>` 反序列化实测覆盖)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody V=class 域含嵌套+collection](../3-decisions/D129-request-param-class-domain.md) + [D130 emitDeserializeForType SSoT 收敛](../3-decisions/D130-deserializer-ssot-converge.md) + [D088 §第一性需求 编译期展开消除运行时反射](../3-decisions/D088-comptime-zig-route.md)

## 问题

**用户工程节奏反思**(本轮 ultrathink 触发性反思):Phase 4 §247 第二支柱嵌套深化以来 7 轮(nested.md → nested-array → nested-array-primitive → nested-array-array → nested-deep → nested-map → nested-map-primitive)按"sub-issue 切片节奏"逐 vType / 逐容器维度独立兑现。c52e9b5 起 `D130 emitDeserializeForType` SSoT 收敛后,`emitDeserializeForType` 7 路单点解码 + `emitArrayDeserializeInto` / `emitMapDeserializeInto` inner dispatch 委托 → **每加新 vType / 新容器嵌套 O(0)**(零 codegen 新加 case)。后续 sub-issue 都是"零 codegen RED 锁",95eb282 已实证(Map<s, primitive> 4 vType 自动 cover)。

**对照 Jackson 生态**:Jackson 团队不会为每种字段类型组合写一个 issue 测一轮 — Jackson 写一个综合 `ParameterizedTypeReference` 测试一次 cover `Map<List<X>>` / `List<Map<X,Y>>` / `Map<Map<X,Y>>` 等所有笛卡尔积。**SS 当前 D130 SSoT 设计已是 Jackson 编译期对偶**,但 issue tracking 节奏切片过细,工程效率 → 0。

**改走笛卡尔积综合测试 reset**:本子档 = **D130 SSoT "每加新类型 O(1)" 设计意图首次端到端兑现轮** — 一次综合测试 cover 嵌套维度笛卡尔积 ~ 15 cell,**零 codegen 改动 = D130 SSoT 收敛设计的实证验证**;告别 nested-map-array / nested-map-typed-key 等 6-8 轮独立 sub-issue 切片节奏(注:**仅笛卡尔积可自动覆盖的维度合并** — typed-key / nullable / etc 真新 codegen 维度仍独立 sub-issue)。

**笛卡尔积维度**(15 cell):
- 5 cell:`Map<string, Array<X>>` X ∈ {int/string/double/bool/Class} — Map vType="Array<...>" → emitMapDeserializeInto 委托 emitDeserializeForType → isArrayDeserializable → emitArrayDeserializeInto
- 5 cell:`Map<string, Map<string, Y>>` Y ∈ {int/string/double/bool/Class} — emitMapDeserializeInto 自递归 vType="Map<...>" → isMapDeserializable → emitMapDeserializeInto 嵌套调用
- 3 cell:`Array<Map<string, X>>` X ∈ {int/string/Class} — emitArrayDeserializeInto elemType="Map<...>" → isMapDeserializable → emitMapDeserializeInto
- 1 cell:`Map<string, Map<string, Array<X>>>` — N=3 混合容器层(Map → Map → Array)
- 1 cell:`Array<Array<Map<string, X>>>` — N=3 反向混合容器层(Array → Array → Map)

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md) + [D130 §SSoT 收敛](../3-decisions/D130-deserializer-ssot-converge.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套 + collection)** + Jackson/Gson 反序列化器 | HTTP body")。

enterprise REST API 通用 nested DTO 形态 — 真实业务 DTO 笛卡尔积形态高频实例:

- **K8s deployment spec**:`Map<string, Array<Container>>`(container groups by namespace)、`Map<string, Map<string, string>>`(nested labels / annotations)
- **Stripe metadata**:`Map<string, Map<string, string>>`(nested key-value tags)
- **GitHub Action workflows**:`Map<string, Array<Step>>`(jobs by name)、`Map<string, Map<string, string>>`(env / inputs)
- **AWS hierarchical tags**:`Map<string, Map<string, string>>`、`Array<Map<string, Tag>>`(resource groups)
- **matrix configurations**:`Map<string, Map<string, Array<int>>>`(N=3 混合 — env × matrix × values)
- **inventory / logistics**:`Array<Array<Map<string, int>>>`(N=3 反向 — region × warehouse × stock)

SS 用户写:

```ss
class Tag { color: string; priority: int }
class BigOrder {
    customer: string
    iaGroups: Map<string, Array<int>>
    saGroups: Map<string, Array<string>>
    daGroups: Map<string, Array<double>>
    baGroups: Map<string, Array<bool>>
    caGroups: Map<string, Array<Tag>>
    iiMaps: Map<string, Map<string, int>>
    ssMaps: Map<string, Map<string, string>>
    ddMaps: Map<string, Map<string, double>>
    bbMaps: Map<string, Map<string, bool>>
    ccMaps: Map<string, Map<string, Tag>>
    iMapList: Array<Map<string, int>>
    sMapList: Array<Map<string, string>>
    cMapList: Array<Map<string, Tag>>
    deepMix: Map<string, Map<string, Array<int>>>
    deepMixR: Array<Array<Map<string, int>>>
}

@PostMapping("/orders/cartesian")
function createBigOrder(@RequestBody order: BigOrder): string { /* ... */ }
```

行为 byte-identical Java Spring(Jackson `@RequestBody` 自动反序列化任意嵌套 `List<Map<...>>` / `Map<List<...>>`)。

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **D130 SSoT 笛卡尔积一次 cover(零 codegen 改动)**:c52e9b5 `emitDeserializeForType` 7 路 + `emitArrayDeserializeInto` / `emitMapDeserializeInto` inner dispatch 委托已设计承载任意嵌套笛卡尔积。本子档 Execute = (1) `tests/phase5/i021_requestbody_nested_cartesian.ss` ~ 250-300 行 BigOrder DTO + 8 case (2) spring-parity HelloController + Java oracle 加 BigOrder DTO + `@PostMapping("/orders/cartesian")` smoke (3) bootstrap 三阶段固定点 + reflection_health_linter PASS;**LOC 量级 ~ 350,15 cell 笛卡尔积一次端到端锁定** | D130 SSoT 设计意图首次端到端兑现 + Jackson 编译期对偶模式锁(对照 §交互式单文档:每轮一目标 + feedback_root_cause_no_cost — D130 是根因层方案,本子档零 codegen 改动 = SSoT 收敛设计的兑现验证);[D088 §第一性需求 alignment](../3-decisions/D088-comptime-zig-route.md) ✅ |
| B | 反 SSoT 切片单跑 8 轮(nested-map-array / nested-map-map / nested-array-map / nested-deep-mixed-Map-Array / nested-deep-mixed-Array-Map 等)| 违反 D130 SSoT 设计意图 + Jackson 编译期对偶模式 + 工程节奏 → 0(本对话 ultrathink 否决)❌ |
| C | runtime 反射递归遍历任意嵌套容器元数据自动 deserialize | 违反 [D088 §第一性需求](../3-decisions/D088-comptime-zig-route.md) 编译期展开消除运行时反射 ❌ |

选 **A** —— D130 SSoT 笛卡尔积一次 cover + 设计意图兑现轮。

**Execute 实测发现(承本子档 Plan 风险锚 #1 D130 漏 case 暴露窗口)**:综合测试**真实暴露 D130 SSoT 用户层 Map.get 取容器 V 路径漏洞** — 原计划"零 codegen 改动"被升级为 **2 处 codegen 根因修**(对照 [feedback_root_cause_no_cost](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_root_cause_no_cost.md) 编译器 bug 必修 codegen / RC 逻辑):

1. `bootstrap/gen/gen_types.ss:412-432` `inferType` Map.get 类型推断扩 3 路 case:`bool` / `Array<X>` / `Map<K2,V2>` — 原仅 cover scalar(string/int/double)+ UserClass(返 ClassName?),漏掉 V=容器 / V=bool 推断 → 用户层 `const arr = order.iaGroups.get(key)` 推为 i64 而非 Array<int>
2. `bootstrap/gen/gen_builtins.ss:290-320` Map.get codegen 扩 2 路 case:`V=bool` ss_mapGet i64 + trunc i32(对齐 SS bool i32 编码)+ `V=Array<X> / V=Map<K2,V2>` ss_mapGet i64 + inttoptr ptr + emitRetainForType(旧 RC 容器,自带 isnull guard)— 原 fallback 直接返 i64 raw 导致 store ptr 类型不匹配

**笛卡尔积综合测试 = D130 SSoT 漏洞的真实暴露窗口** — 切片单跑(nested-map-array 等)只测 emit IR,不测用户层 .get 取出容器 V 后的字段访问 / 索引;笛卡尔积 case 2/4 用户代码 `arr[j].priority` / `m.get(...)` 才暴露 .get 返 V=容器/bool 路径漏洞。**Jackson 编译期对偶 + 用户层综合压测 = D130 SSoT 设计漏洞首次完整闭环**。

## v0 scope 切分说明(本子档)

**in scope(本轮一次性 cover,15 cell 笛卡尔积)**:

| 容器形态 | X / Y vType | cell 数 |
|---|---|---|
| `Map<string, Array<X>>` | int / string / double / bool / Class | 5 |
| `Map<string, Map<string, Y>>` | int / string / double / bool / Class | 5 |
| `Array<Map<string, X>>` | int / string / Class | 3 |
| `Map<string, Map<string, Array<X>>>` | int(N=3 混合代表) | 1 |
| `Array<Array<Map<string, X>>>` | int(N=3 反向混合代表) | 1 |
| **总计** | | **15** |

**out of scope(留独立 sub-issue,真新 codegen 维度)**:

- **I021-requestbody-nested-map-typed-key** — `Map<int, V>` / `Map<UUID, V>` 等非 string key(JSON object key 始终 string,需编译期 string→K cast,涉新 codegen 路径,nested-map.md §留下轮已锚)
- **I021-requestbody-nested-optional** — `Map<...>?` / `Array<...>?` / nullable inner X(涉 D067 null safety narrow,涉新 codegen 路径,文件已起立)

**作废承接**(关键 — 笛卡尔积 cover 包含路径,无需独立起立):

- **作废 I021-requestbody-nested-map-array**(原计划 sub-issue 名,**未起立成档**;原 scope `Map<string, Array<X>>` 5 cell 被本轮 cover);nested-map.md line 95 §留下轮锚 `nested-map-array` 由本轮收关
- **作废 I021-requestbody-nested-map-map**(原计划假设 sub-issue;`Map<string, Map<string, Y>>` 5 cell 被本轮 cover)
- **作废 I021-requestbody-nested-array-map**(原计划假设 sub-issue;`Array<Map<string, X>>` 3 cell 被本轮 cover)
- **作废 I021-requestbody-nested-deep-mixed**(原计划假设 sub-issue;N=3 混合容器层 2 cell 被本轮 cover;祖祖祖档 nested-deep `Array<Array<Array<X>>>` N=3/4/5 同质纯 Array 链 + 本轮 N=3 混合容器链 联合封顶)

**保留独立 sub-issue**:

- **I021-requestbody-nested-typed-key**(真新 codegen)
- **I021-requestbody-nested-optional**(D067 narrow,真新 codegen)
- **I021-requestbody-nested-array-array** / **nested-deep**(已落地 5b25573 / f301e76,纯 Array 多层维度)
- **I021-requestbody-nested-map-primitive**(已落地 95eb282,顶层 Map<string, primitive> 4 vType)
- **I021-requestbody-nested-map**(已落地 c52e9b5,顶层 Map<string, Class>)

**v0 scope 不做**:

- 不引入新关键字 / 新语法 / 不改 codegen / 不扩 lib/json
- 不实现非 string key Map(留 -typed-key)
- 不实现 nullable 容器 / nullable inner X(留 -optional)
- 不实现 N=4/N=5 混合容器层(若需要由后续独立 sub-issue;本轮仅 cover N=3 混合二族 — 正向 Map→Map→Array + 反向 Array→Array→Map 已足够实证 D130 自递归契约)
- 不做 RC drop 链对 N=3 混合 use-after-free / leak 量化压测(本轮综合 case 5/6 端到端 RUN exit 0 即覆盖)

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   # RED 1: 子档不存在
   ls docs/4-issues/I021-requestbody-nested-cartesian.md 2>&1 | grep -c "No such"
   # before: 1  after(本轮 Write 后): 0

   # RED 2: 测试文件不存在
   ls tests/phase5/i021_requestbody_nested_cartesian.ss 2>&1 | grep -c "No such"
   # before: 1  after: 0

   # RED 3: spring-parity HelloController + Java oracle 无 BigOrder DTO
   grep -cE "class BigOrder|/orders/cartesian" examples/spring-parity/hello/ss/HelloController.ss examples/spring-parity/hello/java/src/main/java/hello/HelloController.java
   # before: 0/0  after: ≥ 2/≥ 2(class 定义 + 路由路径)

   # RED 4: 端到端 emit IR(D130 SSoT 自动覆盖,首次跑必绿)
   bin/ss build tests/phase5/i021_requestbody_nested_cartesian.ss -o /tmp/t_i021_cartesian --emit-ir 2>&1 | grep -cE "@jnAsInt|@jnAsString|@jnAsDouble|@jnAsBool|@ss_mapNew|@ss_mapSet|@ss_newArray|@ss_arrayPush|@jnObjectKeys|@jnArrayLen|@jnArrayGet|@jnGetField"
   # 期望:首次跑必绿(D130 SSoT 笛卡尔积自动 cover);若失败必升根 D130 codegen,不在 Execute 层加 workaround
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss + Java oracle** 加 `class Tag`(已存在复用)+ `class BigOrder { ... 16 字段 ... }` + `@PostMapping("/orders/cartesian") createBigOrder(@RequestBody order: BigOrder)`:**parity smoke 仅消耗 customer + sizes 维度**(避免跨语言 double / bool / 嵌套 toString 格式差异 — full cover 在 SS 测试文件本身)。Java oracle 同步加 BigOrder DTO + 同 endpoint。

3. **tests/phase5/i021_requestbody_nested_cartesian.ss** 新建 ~ 250-300 行 8 case BigOrder DTO 综合测试(含 16 字段,覆盖 15 cell 笛卡尔积):
   - case 1:全空 BigOrder size=0 全 16 字段 — RC 不破裂(15 cell drop 链多层契约严审)
   - case 2:customer + 5 cell `Map<string, Array<X>>` 字段填(int/string/double/bool/Class 5 vType)— 5 cell 端到端 + size + key 命中
   - case 3:5 cell `Map<string, Map<string, Y>>` 字段填(int/string/double/bool/Class 5 vType)— 5 cell 端到端 + 嵌套 size + nested key 命中
   - case 4:3 cell `Array<Map<string, X>>` 字段填(int/string/Class 3 vType)— 3 cell 端到端 + Array length + Map key 命中
   - case 5:N=3 混合 `Map<string, Map<string, Array<int>>>` 字段填 — Map → Map → Array 三层嵌套
   - case 6:N=3 反向混合 `Array<Array<Map<string, int>>>` 字段填 — Array → Array → Map 三层嵌套
   - case 7:全 16 字段全填端到端 — 15 cell 笛卡尔积同 body 联合压测
   - case 8:全链路 raw HTTP POST `/orders/cartesian` byte-identical Java oracle smoke(仅消耗 customer + sizes,避格式差异)

4. **bootstrap fix**:**N/A**(D130 SSoT 已 cover)— Execute 轮如发现 emit IR 实际不通,**立即升根** D130 SSoT 漏掉的容器嵌套自递归路径(`emitArrayDeserializeInto` / `emitMapDeserializeInto` / `emitDeserializeForType` 路径),按"根因优先"rule 修,不在 Execute 层加 workaround(对照 [feedback_root_cause_no_cost](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_root_cause_no_cost.md):编译器 bug 必修 codegen / RC 逻辑)。**综合测试 RED 失败正是 D130 设计漏洞暴露窗口** — 不分散稀释失败信号,直接根因升级。

5. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。本子档 Execute 轮**测试代码 ~ 250-300 行**为主,可读性优先;笛卡尔积 cell 测试代码无 helper 抽取倾向(case-by-case 测试代码不应过度抽象,16 字段串接 toString 直观断言优于参数化抽取)。

6. **commit + push**:format `feat(I021-requestbody-nested-cartesian,D123,D129,D130): 嵌套 collection 笛卡尔积 SSoT 端到端锁定(零 codegen 改动 — D130 SSoT 设计意图首次兑现) — Phase 4 §247 第二支柱嵌套深化收关`。

## 反向 / 备选

(同上候选 A 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-cartesian.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:见 §步骤 §1 RED 命令(4 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_cartesian.ss` exit 0,8 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders/cartesian -d '{"customer":"alice",...}'` 返 byte-identical Java oracle(仅 customer + sizes 维度 smoke)
- **Execute 轮 after**:`grep -cE "@ss_mapNew|@ss_mapSet|@ss_newArray|@ss_arrayPush|@jnObjectKeys|@jnArrayLen|@jnArrayGet|@jnGetField|@jnAsInt|@jnAsString|@jnAsDouble|@jnAsBool" /tmp/t_i021_cartesian.ll` ≥ 50(15 cell × 多种容器 + 多种 vType emit 累积,laxer 估计)
- **Execute 轮 after**:`grep -c "i64 516" /tmp/t_i021_cartesian.ll` ≥ 8(8 个 ptr value Map 字段写 val_type=1 — 5 个 Map<string, Array<X>>(Array 是 ptr)+ 3 个 Map<string, Class | Map<string, ?>>(value ptr)+ 多个递归层 Map ptr value)
- **Execute 轮 after**:bootstrap 三阶段固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions(predict no F1 regression — 零 codegen 改动 + 零 lib/json 改动 + 仅测试 + spring-parity 加 1 endpoint smoke)

## 风险 / 表面 / 下轮升根路径

1. **D130 SSoT 漏 case 暴露窗口(关键)**:笛卡尔积测试是 D130 设计漏洞的**真实暴露窗口**。任一 cell RED fail → 升根 D130 `emitDeserializeForType` / `emitArrayDeserializeInto` / `emitMapDeserializeInto` inner dispatch 漏路径修。**切片单跑反而稀释失败信号** — 综合测试一次 RED 暴露所有自递归契约缺口;升根目标按失败 cell 类型推断:
   - cell 11-13(`Array<Map<string, X>>`)RED fail → emitArrayDeserializeInto elemType="Map<string, X>" → isMapDeserializable 委托链断
   - cell 6-10(`Map<string, Map<string, Y>>`)RED fail → emitMapDeserializeInto vType="Map<string, Y>" → isMapDeserializable 自递归断
   - cell 14-15(N=3 混合容器层)RED fail → 3 层自递归契约任一断,精准定位修

2. **N=3 混合容器 RC drop 链辨析(关键)**:`Map<string, Map<string, Array<int>>>` drop 链:
   - BigOrder drop → outer Map drop(`ss_rc_destroy_map` val_type=1)→ 逐 entry inner Map drop
   - inner Map drop(`ss_rc_destroy_map` val_type=1)→ 逐 entry Array drop
   - Array tag=1(int 元素 ptr=ss_newArray)→ 仅 free 容器(int 无 release)
   - **三层链断一处 use-after-free**;综合测试 case 5/6 端到端 RUN exit 0 = 三层契约联合压测

3. **Array<Map<...>> 反向容器二族 tag 对齐**:`Array<Map<X, Y>>` Array tag=5(ptr elem)→ 逐 elem `ss_release` → 走 Map drop;对齐 `Map<string, Array<X>>` Map val_type=1 + Array tag=1/5 二分;**case 4(`Array<Map<string, X>>` 3 vType)+ case 6(`Array<Array<Map<...>>>` N=3 反向)联合验 Array 容器 tag=5 ptr elem release 链路对 inner Map ptr 自动级联**

4. **Class entry value RC retain 契约**:`Map<string, Tag>` / `Array<Map<string, Tag>>` / `Map<string, Array<Tag>>` 内 Tag 通过 `ss_mapSet` / `ss_arrayPush` 转移 ownership(不 retain),drop 链通过 val_type=1 + tag=5 + Tag_drop 自动级联;**case 2 第 5 cell(Class)+ case 3 第 5 cell(Class)+ case 4 第 3 cell(Class)联合验 Class entry RC 契约多容器形态零 leak**

5. **bootstrap 时长(中等)**:综合测试 ~ 300 行 emit IR 较大(15 cell + 8 case + 16 字段 BigOrder),但 codegen 路径全是已有 D130 SSoT 重用,bootstrap 增量影响可控;预测 stage1/stage2/stage3 ≤ 70s 全程

6. **若发现某 cell D130 未自动覆盖**:正是根因升级机会,按 root_cause_no_cost 修 `emitArrayDeserializeInto` / `emitMapDeserializeInto` 漏路径,**禁止在测试层 skip 该 cell 或加 workaround**;**禁用 @derive / annotation handler 旁路**(对照 feedback_no_derive_workaround)

7. **JSON body string 长度(中等)**:case 7 全 16 字段全填 JSON body 长度可能 > 1KB,需要 lib/http 端 body 缓冲容量;现状 lib/http parser 已支持 ≤ 8KB body(I021-requestbody.md line 53 父档父档已锚),case 7 在容量内

8. **lib/json 当前依赖**:`jnAsInt` / `jnAsString` / `jnAsDouble` / `jnAsBool` / `jnObjectKeys` / `jnGetField` / `jnArrayLen` / `jnArrayGet` 全部已存在(95eb282 锁);零 lib/json 改动

**Plan 阶段 plumbing 完整**:本子档 Execute 轮无表面遗留;D130 SSoT 已设计层覆盖任意嵌套容器笛卡尔积自递归;Execute 实测发现 D130 SSoT 用户层 Map.get 取 V=容器/bool 路径漏洞,2 处 codegen 根因升级修(见 §候选路径 §A Execute 实测发现)— 笛卡尔积综合测试是 D130 SSoT 漏洞的真实暴露窗口。

## 触发场景

- 接到 enterprise REST API 业务实现含**任意嵌套 collection** DTO(K8s deployment spec / matrix configurations / Stripe metadata / GitHub Action workflows / AWS hierarchical tags / inventory logistics)
- D129 §94 "@RequestBody | 任意 class(含嵌套 + collection)" 域语义**任意嵌套**首次端到端兑现
- D130 SSoT 收敛后嵌套 collection 笛卡尔积**首次端到端实证锁定**(c52e9b5 / 95eb282 单容器单 vType 级别落,本子档承接笛卡尔积联合)
- I021-requestbody-nested-map-primitive.md line 92-95 §留下轮锚 nested-map-array 由本轮收关
- I021-requestbody-nested-map.md line 76-78 §留下轮锚 nested-map-array 由本轮收关

## 备注

- 本子档**Plan + Execute 综合一轮闭环**(取代切片节奏,工程节奏 reset)
- nested-map-primitive.md line 78 §留下轮锚 由本轮直接收关
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)+ D130 SSoT 收敛设计已 Decided,本子档执行不再辨析
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化**收关轮**(深化总轮数:第一 nested.md / 第二 nested-array / 第三 nested-array-primitive / 第四 nested-array-array / 第五 nested-deep / 第六 nested-map / 第七 nested-map-primitive / **本第八收关 nested-cartesian**)
- 本子档 Execute 轮**零 codegen / 零 lib/json 改动 = D130 SSoT 收敛设计的 Jackson 编译期对偶模式实证轮**(对照 D130 设计意图:每加新类型 O(1) 而非 O(3),本子档实测笛卡尔积 ~ 15 cell 路径 O(0) — 已就绪只需 RED 锁)
- 工程节奏 reset:本轮起,告别 D130 SSoT 自动覆盖切片节奏;后续 sub-issue 仅在**真新 codegen 维度**起立(typed-key / nullable / etc),不再为已 cover 的笛卡尔积 cell 单独切片
