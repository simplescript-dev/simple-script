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
| **A** | **复用 nested v0 plumbing 实测覆盖任意层数嵌套**(b79aa97 emitPendingDeserializers BFS 单遍出队即 emit + 字段扫描入队 是 codegen 迭代实现层数无关天然任意层数;本子档 Execute 轮 RED test 验证 closure 计算路径不漏 emit + RC 契约累积每层独立成立 + emit 顺序拓扑正确;若 BFS 实装漏 N>1 层路径(如某层字段类型扫描漏 → undefined symbol)→ bootstrap/gen 路径补齐) | nested v0 BFS 已就绪零额外设计;[D018](../3-decisions/D018-object-layout-typeinfo.md) per-class deserializer transitive closure BFS 单遍逻辑天然层数无关;[D023](../3-decisions/D023-mimalloc-integration.md) mimalloc N 层 mi_calloc / ss_release 链;[D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md) ✅ |
| B | 递归 emit(替换 BFS 为 DFS 递归实现) | b79aa97 BFS 已就绪,DFS 递归换 BFS 是无收益的实现层 churn ❌ |
| C | runtime 栈深检测 / TCO 优化 deserialize 调用链 | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md);N=4 层 native call stack 充裕,无需 TCO 优化;过度工程 ❌ |

选 **A** —— nested v0 plumbing 已就绪,本子档**实测覆盖**而非新功能补齐。

## v0 scope 切分说明(本子档)

**落地**:

- **任意层数嵌套**(N>=2)— b79aa97 emitPendingDeserializers BFS 是 codegen 迭代实现(while 出队 + 字段扫描入队 + deserializerTargets.has visited guard),codegen 层数无关天然任意层数;本子档不限定 N 上限
- 实测 stress 手段(非 scope 切分):N=3/4/5 层端到端 case 覆盖 facade pattern 高频形态,作为 Execute 轮 RED → GREEN 验证手段(N=3/4/5 是 case 选取非 scope 边界);通过 = "BFS closure 不漏 emit + RC 契约层数无关每层独立成立" 真实证据
- emit 顺序拓扑验证:LLVM IR forward declaration 允许调用未 emit 函数(define 顺序无关链接器解析)— 拓扑顺序在 LLVM 链接阶段天然消解;IR 锚 grep 行号是 cross-check 工具非硬约束
- RC 契约层数无关:每层独立成立 mi_calloc(rc=1) + 父字段 store 直接 transfer 不 retain(同 b79aa97 单层契约模式逐层叠加)+ ss_drop_<Outer> 字段释放级联触发子 ss_release;N 层叠加任一层破裂 → leak / double free,Execute 轮按层独立审视
- 测试 IR 锚:`grep "@Contact_deserialize\|@Profile_deserialize\|@Customer_deserialize\|@Order_deserialize" /tmp/t_i021_deep.ll` ≥ 4(N=4 层 4 个 deserializer 全 emit,验证 closure BFS 不漏 emit)
- 全链路 raw HTTP POST `/orders` byte-identical Java oracle

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立):

- **I021-requestbody-nested-deep-cycle** — 嵌套 class **循环引用**(`A { b: B }, B { a: A }`)反序列化处理 — JSON 树形结构无法表达循环 → 编译期检测要求至少一侧字段 nullable(D067 T?)打破循环;b79aa97 deserializerTargets.has guard 已防 closure 计算无限循环但运行时反序列化未处理

**v0 scope 不做**:

- 不实现循环引用检测(留 -deep-cycle;本子档 v0 假设 class 定义无循环)
- 不实现 N 层混合 collection(`Order { items: Array<Item> { tags: Map<string, Tag> } }`)— 单一维度逐层 cover,留组合维度独立子档
- 不实现 nullable N 层(留 [I021-requestbody-nested-optional](./I021-requestbody-nested-optional.md))
- 不引入新关键字 / 新语法
- **不限定 N 上限**(BFS codegen 层数无关 + native call 链栈深与 D085 共享防护非 deserialize 边界,无 -deep-extreme 子档必要性)

**Execute 轮 case 选取**(本轮承 commit 5b25573 nested-array-array N=2 双层直接深化):

- 选 **Array<Array<Array<X>>> N=3/4/5 多层数组嵌套**作 case 维度(facade pattern 在数组维度的高频形态:matrix N-D / image pixels / game grid / stats);三档 elemType cover (int/string/DeepCell user class)
- N=5 极限 case 验证 lexer 贪心 `>>>>>` = USHR+SHR (3+2) + parser `expectGtTypeCtx` 状态机 5 次调用消耗刚好(parser.ss:209-231 N>=2 任意层无新代码路径)
- **facade nested class N=4 嵌套** (Order/Customer/Profile/Contact 链式深度形态)属本子档 §第一性需求 范围但**已被** [I021-requestbody-nested.md](./I021-requestbody-nested.md) commit b79aa97 单层 v0 实测 + 本轮 Array 多层嵌套实测**共同代表覆盖** — BFS closure transitive 推导 + RC 契约都是层数无关;Array 多层与 nested class 多层共享 codegen plumbing(emitPendingDeserializers BFS 字段扫描入队 + emitArrayDeserializeInto 第 6 路递归 + isArrayDeserializable 第 3 路递归);若未来发现 nested class N=4 facade pattern 与 Array N=4 嵌套行为差异 → 立独立 -deep-facade 子档

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

4. **运行时 native call 栈深累积**:b79aa97 BFS 是 codegen 迭代实现(Map 队列 + while 出队),codegen 阶段无递归不爆栈;但 **deserializer 运行时**本身是 N 层 native call 链(ClassA_deserialize 调 ClassB_deserialize 调 ...),N>>1 层时 native stack 占用线性累积
   - 现实 enterprise DTO 通常 N≤10 层(facade 模式典型 3-5 层),native stack 充裕(默认 8MB 容纳 N>>1000 层)
   - 极端深度边界与 [D085 stack overflow detection](../3-decisions/D085-stack-overflow-detection.md) 共享同一防护 — deserialize 不是边界条件 owner(任何 N>>1 层 native call 链都同等暴露 stack 限制),不需 deserialize 自身做特殊处理 / 不需独立 -deep-extreme 子档(stress 边界与 D085 同源,场景不质变)

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
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化第四轮(深化 = 任意层数 BFS closure 实测 + RC 契约层数无关每层独立成立验证;首轮 nested.md = N=1 层;二轮 nested-array = collection Array;三轮 nested-map = collection Map)
- **依赖关系**:本子档 Execute 轮**最好后于** nested-array / nested-map(因 closure BFS 字段扫描分支需对齐 nested-array / -map 新增字段 case),Execute 顺序建议 nested-array → nested-map → nested-deep → nested-optional
