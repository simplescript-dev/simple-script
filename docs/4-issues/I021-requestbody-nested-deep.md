# I021-requestbody-nested-deep:N>1 层嵌套反序列化栈深度 + RC 契约累积实测覆盖

> 父档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层嵌套 user class 字段端到端)
> 祖档:[I021-requestbody.md](./I021-requestbody.md)(commit 8165370 — Phase 4 §247 第二支柱端到端兑现)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody 域含嵌套](../3-decisions/D129-request-param-class-domain.md)

## 问题

I021-requestbody-nested v0(commit b79aa97)实测覆盖**单层嵌套**(`Order { customer: Customer, addr: Address }`),emit transitive closure 走 BFS(`emitPendingDeserializers` 单遍 队列出队即 emit + 字段扫描入队),理论上**已自然支持** N>1 层嵌套(BFS 不限层数)。

I021-requestbody-nested.md line 72 §留下轮锚 3 已声明:"**I021-requestbody-nested-deep** — N>1 层嵌套(`A { b: B { c: C { d: D } } }`)反序列化栈深度 + RC 契约累积" — **scope 显式留本子档**。

I021-requestbody-nested.md line 130-133 §风险 2 已锚:"per-class deserializer 延迟 emit transitive closure" + "嵌套 Customer / Address 是间接被引用(经 Order 字段),延迟 emit 触发链需含 transitive closure(Outer 引用 → emit Outer + 递归 emit field types)" + "本子档 Execute 轮需严审 closure 计算路径,若漏 → 嵌套子 deserialize 函数 undefined symbol link error" — **closure BFS 已 b79aa97 实装 + 单层嵌套实测,但 N>1 层 closure 是否爆栈 / 漏 emit 待实测**。

enterprise REST API 真实业务场景:GraphQL-like REST API 返回深嵌套 DTO 如 `Order { customer: Customer { profile: Profile { contact: Contact } } }`(N=4 层)是 facade pattern 高频形态;SS 现状 b79aa97 closure BFS 理论支持但**未实测验证**,N>=3 层场景 codegen 行为 / 运行时 RC 契约 / emit 顺序 都需端到端验证。

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套)** + Jackson/Gson 反序列化器 | HTTP body" — "**任意嵌套**" 含 N>1 层)。

SS 用户写:

```ss
class Contact { email: string; phone: string }
class Profile { bio: string; contact: Contact }
class Customer { name: string; profile: Profile }
class Order { customer: Customer }

@PostMapping("/orders")
function createOrder(@RequestBody order: Order): string {
    return "name=" + order.customer.name +
           ",bio=" + order.customer.profile.bio +
           ",email=" + order.customer.profile.contact.email
}
```

行为 byte-identical Java Spring(N=4 层 facade DTO):

```java
public class Contact { String email; String phone; }
public class Profile { String bio; Contact contact; }
public class Customer { String name; Profile profile; }
public class Order { Customer customer; }

@PostMapping("/orders")
public String createOrder(@RequestBody Order order) {
    return "name=" + order.customer.name +
           ",bio=" + order.customer.profile.bio +
           ",email=" + order.customer.profile.contact.email;
}
```

curl `POST /orders -H 'Content-Type: application/json' -d '{"customer":{"name":"alice","profile":{"bio":"hi","contact":{"email":"a@b.com","phone":"555"}}}}'` → `name=alice,bio=hi,email=a@b.com`。

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 nested v0 plumbing 实测覆盖 N=3/N=4 层**(b79aa97 emitPendingDeserializers BFS 单遍出队即 emit + 字段扫描入队 已自然支持任意层数;本子档 Execute 轮 RED test 验证 closure 计算路径不漏 emit + RC 契约累积不漂移 + emit 顺序拓扑正确;若 BFS 实装漏 N>1 层路径(如某层字段类型扫描漏 → undefined symbol)→ bootstrap/gen 路径补齐) | nested v0 BFS 已就绪零额外设计;[D018](../3-decisions/D018-object-layout-typeinfo.md) per-class deserializer transitive closure BFS 单遍逻辑天然层数无关;[D023](../3-decisions/D023-mimalloc-integration.md) mimalloc N 层 mi_calloc / ss_release 链;[D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md) ✅ |
| B | 递归 emit(替换 BFS 为 DFS 递归实现) | b79aa97 BFS 已就绪,DFS 递归换 BFS 是无收益的实现层 churn ❌ |
| C | runtime 栈深检测 / TCO 优化 deserialize 调用链 | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md);N=4 层 native call stack 充裕,无需 TCO 优化;过度工程 ❌ |

选 **A** —— nested v0 plumbing 已就绪,本子档**实测覆盖**而非新功能补齐。

## v0 scope 切分说明(本子档)

**落地**:

- N=3 层嵌套(`Order { customer: Customer { profile: Profile } }`)实测覆盖
- N=4 层嵌套(`Order { customer: Customer { profile: Profile { contact: Contact } } }`)实测覆盖
- N=5 层嵌套(facade pattern 极限测试,验证 BFS closure 不爆栈不漏 emit)
- emit 顺序拓扑验证:依赖类先于被依赖类 emit(Contact 先于 Profile 先于 Customer 先于 Order),IR 锚验证 emit 顺序
- RC 契约累积验证:N 层 mi_calloc(rc=1) + N 层 ss_release 链 + 父字段 store 直接 transfer 不 retain(每层都遵守)
- 测试 IR 锚:`grep "@Contact_deserialize\|@Profile_deserialize\|@Customer_deserialize\|@Order_deserialize" /tmp/t_i021_deep.ll` ≥ 4(N=4 层 4 个 deserializer 都 emit)
- 全链路 raw HTTP POST `/orders` byte-identical Java oracle

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立):

- **I021-requestbody-nested-deep-cycle** — 嵌套 class **循环引用**(`A { b: B }, B { a: A }`)反序列化处理(JSON 自然不支持循环引用,但用户可能误用 → 编译期检测或运行时栈深保护)
- **I021-requestbody-nested-deep-extreme** — N>10 层极端深度(stress test,验证 closure BFS 不爆栈,与 [D085 stack overflow detection](../3-decisions/D085-stack-overflow-detection.md) 配合)

**v0 scope 不做**:

- 不实现循环引用检测(留 -deep-cycle)
- 不实现 N>10 层极端深度 stress test(留 -deep-extreme)
- 不实现 N 层混合 collection(`Order { items: Array<Item> { tags: Map<string, Tag> } }`)— 单一维度逐层 cover,留组合维度独立子档
- 不实现 nullable N 层(留 [I021-requestbody-nested-optional](./I021-requestbody-nested-optional.md))
- 不引入新关键字 / 新语法

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   # RED 1: N=4 层 closure BFS 实测前 IR 锚 < 4
   bin/ss build tests/phase5/i021_requestbody_nested_deep.ss -o /tmp/t_i021_deep_red --emit-ir 2>&1 | grep -cE "@Contact_deserialize|@Profile_deserialize|@Customer_deserialize|@Order_deserialize"
   # before: 0 (若 closure 漏 / 1-2 (若 BFS 部分 cover) / 4 (若已自然 cover - 此时本子档主要是实测验证)
   # after: ≥ 4 (4 个 deserializer 全 emit)
   
   # RED 2: 端到端 silent
   bin/ss run tests/phase5/i021_requestbody_nested_deep.ss 2>&1 | grep -oE "name=alice,bio=hi,email=a@b.com|undefined symbol|segfault|not found"
   # before: undefined symbol 或 segfault (若 closure 漏)
   # after: name=alice,bio=hi,email=a@b.com
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss** 加 `class Contact` + `class Profile` + `class Customer { profile: Profile }` + `class Order { customer: Customer }` + `@PostMapping("/orders/deep") createOrderDeep(@RequestBody order: Order)`(注:与 nested v0 已加的 `class Order { customer: Customer, addr: Address }` 命名冲突 → 用 `OrderDeep` / `DeepOrder` 区分,Execute 轮拍板);Java oracle 同步。

3. **tests/phase5/i021_requestbody_nested_deep.ss** 新建 ~120 行 5 case:
   - case 1:N=3 层嵌套基本访问 `order.customer.profile.bio`
   - case 2:N=4 层嵌套深度访问 `order.customer.profile.contact.email`
   - case 3:N=5 层嵌套(facade 极限,验证 BFS closure 不爆栈)
   - case 4:全链路 raw HTTP POST `/orders/deep -d '{深嵌套 JSON}'`
   - case 5:IR 锚 N=4 层 4 个 deserializer 全 emit + emit 顺序拓扑验证(grep 行号确认 Contact 先于 Profile 先于 Customer 先于 Order)

4. **bootstrap fix(若 RED 不直接 GREEN)**:

   - 若 N>1 层 closure BFS 漏(某层字段类型扫描漏入队)→ `bootstrap/gen/gen_deserialize.ss emitPendingDeserializers` BFS 主循环路径补齐(确认每个出队的 class 都遍历全部字段类型 + isUserClass 检测 + deserializerTargets.has guard 兼任 visited)
   - 若 N 层 RC 契约累积漂移(某层 retain 遗漏 / store 重复 retain)→ codegen 字段填充路径每层独立审视
   - 若 emit 顺序拓扑错(被依赖类晚于依赖类 emit → undefined symbol link error)→ BFS topological sort 严审

5. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。

6. **commit + push**:format `feat(I021-requestbody-nested-deep,D123,D129): N>1 层嵌套反序列化栈深度 + RC 契约累积实测覆盖 — Phase 4 §247 第二支柱嵌套深化第四轮`。

## 反向 / 备选

(同上候选 A 评估表 — B/C 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-deep.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:见 §步骤 §1 RED 命令(2 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_deep.ss` exit 0,5 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/orders/deep -d '{深嵌套 JSON}'` 返 byte-identical Java oracle
- **Execute 轮 after**:`grep "@Contact_deserialize\|@Profile_deserialize\|@Customer_deserialize\|@Order_deserialize" /tmp/t_i021_deep.ll` = 4(N=4 层 IR 锚)
- **Execute 轮 after**:`grep -n "define.*_deserialize" /tmp/t_i021_deep.ll` 行号 Contact < Profile < Customer < Order(emit 顺序拓扑验证)
- **Execute 轮 after**:bootstrap 固定点 PASS Stage 2 = Stage 3 + reflection_health_linter GATE PASS no regressions

## 风险 / 表面 / 下轮升根路径

1. **N 层 closure BFS 漏 emit**:b79aa97 emitPendingDeserializers BFS 单遍出队即 emit + 字段扫描入队,理论上层数无关,但实装路径 ALL fields 是否遍历全(嵌套 class field / Array<Class> field / Map<K,Class> field / nullable field 等)需 Execute 轮严审
   - 升根路径:`bootstrap/gen/gen_deserialize.ss emitPendingDeserializers` BFS 主循环字段类型扫描分支补齐(对齐 nested-array / nested-map / nested-optional 子档新增的字段 case)
   - 当前 b79aa97 仅 cover `isUserClass(ft)` 单层嵌套字段类型;若 nested-array / nested-map 新增 `Array<Class>` / `Map<K,Class>` 字段 case,**closure BFS 字段扫描必须同步扩**(否则深层 nested-array 内部 Class 漏入队 → undefined symbol)

2. **N 层 RC 契约累积**:每层 mi_calloc(rc=1) + 父字段 store 直接 transfer 不 retain,N=4 层叠加任一层破裂 → leak / double free
   - Execute 轮按层独立审视:N 层 deserializer 每层都跑 RC 单元测试(分配 N 个对象 + 释放后 mi_zone_size 验证 = 0)
   - 升根路径:若发现 b79aa97 单层契约在 N>1 层场景破裂(如某层默认 retain → rc=2)→ codegen 字段填充路径增 closure-aware retain skip

3. **emit 顺序拓扑**:N=4 层 4 个 deserializer 必须按拓扑序 emit(被依赖类先 emit 否则 undefined symbol),BFS 出队顺序对应入队顺序,但**入队是否拓扑**取决于字段扫描顺序(根类 Order 先入队 → 出队 emit Order 时 Customer/Profile/Contact 全在队中,emit 顺序应为 Order, Customer, Profile, Contact 即根优先)。LLVM IR 中 forward declaration 允许调用未 emit 函数(define 顺序无关链接器解析),所以拓扑顺序问题在 LLVM 链接阶段消解;但 IR 锚 grep 行号验证仍可作 cross-check 工具
   - 注:**LLVM IR 函数 define / call 顺序无关链接,emit 顺序拓扑要求弱**;若 emit 顺序问题在 SS bootstrap 编译期触发(genFuncRetTypes 推导依赖未注册类返回类型)→ 严审 codegen.ss initFuncRetTypes 注册路径

4. **N>10 层极端深度爆栈**:b79aa97 BFS 是迭代实现(Map 队列 + while 出队),无递归调用,理论不爆栈;但 deserializer 运行时本身是 N 层 native call 链(ClassA_deserialize 调 ClassB_deserialize 调 ...),N>10 层时 native stack 占用累积
   - 留 -deep-extreme 子档 stress test(N=20,N=50,N=100 层),配合 [D085 stack overflow detection](../3-decisions/D085-stack-overflow-detection.md)

5. **循环引用**:`A { b: B }, B { a: A }` JSON 自然不支持(无表示),但 SS class 定义允许;b79aa97 BFS deserializerTargets.has guard 兼任 visited 已防 closure 计算无限循环;运行时 deserialize 调用循环依赖时 — JSON 解析器先报错(JSON 树形结构无环),codegen 阶段不报错
   - 留 -deep-cycle 子档:编译期检测 class 字段循环引用,要求至少一侧字段 nullable(D067 T?)打破循环

**Plan 阶段 plumbing 完整**:本子档 Execute 轮无新功能补齐(b79aa97 BFS 已自然支持任意层数),主要是**实测覆盖** + RC 契约累积按层严审 + 与 nested-array / nested-map / nested-optional 子档新增字段 case 配合时 BFS 字段扫描分支同步扩。

## 触发场景

- 接到 enterprise REST API 业务实现含 facade pattern 深嵌套 DTO(`Order { customer: Customer { profile: Profile { contact: Contact } } }`)
- D129 §94 "@RequestBody | 任意 class(**含嵌套**)" 域语义 N>1 层兑现
- I021-requestbody-nested.md line 72 §留下轮锚 3 承接
- I021-requestbody-nested.md line 130-133 §风险 2 transitive closure 实测验证
- 与 nested-array / nested-map 子档配合 — 任一深化方向 N>1 层场景实测必走本子档

## 备注

- 本子档**纯文档起立轮**,Execute 留下下轮(按 §交互式单文档:每轮一目标)
- nested.md line 72 §留下轮锚 3 + line 130-133 父档已锚 closure,本子档承接
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)已 Decided,本子档执行不再辨析
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化第四轮(深化 = N>1 层维度实测;首轮 nested.md = N=1 层;二轮 nested-array = collection Array;三轮 nested-map = collection Map)
- **依赖关系**:本子档 Execute 轮**最好后于** nested-array / nested-map(因 closure BFS 字段扫描分支需对齐 nested-array / -map 新增字段 case),Execute 顺序建议 nested-array → nested-map → nested-deep → nested-optional
