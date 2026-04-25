# I021-requestbody — @RequestBody JSON body → class 反序列化(per-class deserializer codegen + invoke sentinel kind 扩 RequestBody)

**父决策:** D123 §247-259 §Phase 4 第二支柱 + §550 表 F 行 + §561 Phase 4 F + §742 Phase 4 收关 "下一步 V=class 跨域辨析(D129 — 不在 @RequestParam 域,属 @RequestBody / @ModelAttribute)" + **D129 §3 域归属辨析 + §5 决策 line 130 "起独立 I021-requestbody issue"**(2026-04-25 翻 Decided 落地)
**状态:** Planned (2026-04-25 立项,Plan + Decision 层 next_prompt option a 用户授权;Execute 留下轮 — D 文档独立审查窗口不许吞,MNK §M §字段 8 例外条款合规)
**颗粒度:** 预估大改 ~300-450 LOC 跨 6-7 文件(`lib/json.ss` JSON → primitive 字段提取 helper +30-50 / `lib/spring/boot/application.ss` PARAM_KIND_REQUEST_BODY const + comptime _ssRoutes RequestBody 分支 + dispatcher body 提取 +30-50 / `bootstrap/eval/method_call.ss` invoke sentinel kind 扩 RequestBody 分支 emit `JSON_parse → ClassName_deserialize → cast ptr` +25-45 / `bootstrap/gen/class/` 或 `bootstrap/gen/codegen.ss` per-class `@ClassName_deserialize(node: ptr): ClassName` LLVM IR 自动生成 +120-200 / `examples/spring-parity/hello/ss/HelloController.ss` +5-10 / `examples/spring-parity/hello/java/.../HelloController.java` Java oracle 同步 +7-10 / `tests/phase5/i021_requestbody.ss` 新建 ~80-100)
**依赖:** D129(Decided at 2026-04-25 §5 决策段落落地) / I021(Done at `lib/spring/boot/application.ss:42-83` paramSpecs comptime block)/ I021bc(Done at 9ca4077 funcParamTypes typed cast)/ I021-multi-param(Done at 065d803 invoke sentinel useParamSpecs 数据驱动展开)/ I021-pathvariable(Done at 2f5dd1b matchPath buffered commit + sentinel 共享 cast 通道)/ `lib/json.ss JSON.parse + jnGetField`(Done — 节点树解析能力已就位)/ D018 ObjectLayout TypeInfo(per-class size + field offsets,deserializer codegen 需读取)/ D123 §253 不扩 Meta 字段(本 issue alignment 限制) / 待立 I021-modelattribute(姊妹跨域,共享 deserializer 基础能力,本 issue 不强依赖)
**创建:** 2026-04-25
**立项由:** D129 §5 line 130 决策"未来 V=class 反序列化能力起独立 I021-requestbody / I021-modelattribute issue,本 D 文档不预设实现路径";本轮 next_prompt option a 用户选定 = D129 翻 Decided + I021-requestbody 起子档,Phase 4 §247 第二支柱起手承载

---

## 问题

I021-pathvariable 收关后,Phase 4 三支柱中 @RequestBody 仍 100% 不可表达,根因是 **JSON → class 反序列化能力 + comptime annotation 识别 + sentinel kind 分派 + per-class deserializer codegen** 四层缺口齐发:

- ✅ 反射 Meta 三层(ParamMeta.annotations / MethodMeta.params 填充 / RouteMeta.paramSpecs)已通(I021)
- ✅ HTTP req map 容器与 body 进入(I014/I018 已 split body)
- ✅ `lib/json.ss` JsonNode 节点树 parse / stringify(已就位)
- ❌ `lib/json.ss` 无 JsonNode → primitive 字段值快速提取 helper(`jnGetInt(node, key)` / `jnGetString(node, key)` 等),deserializer codegen emit 时无可调函数
- ❌ `lib/spring/boot/application.ss:42-83` _ssRoutes comptime block 无 `pAnn.name == "RequestBody"` 分支,@RequestBody 标注的形参不进 paramSpecs(走 fallback 静态路径)
- ❌ `bootstrap/eval/method_call.ss:135 §useParamSpecs` invoke sentinel 仅识别 RequestParam / RequestMap / PathVariable 三 kind,RequestBody kind 无 emit 路径
- ❌ codegen 无 per-class `@ClassName_deserialize(node: ptr): ClassName` 自动生成路径(类比 `ss_drop_X` / `ss_deep_clone_X` / `ss_shallow_clone_X` 自动生成 — D018 + D022 已建立模式,本 issue 加第四个 per-class 函数)

silent 4xx 行为画像(预估 RED,Execute 轮实测确认):
```bash
$ cat > /tmp/t_i021_rb_red.ss <<'EOF'
import { dispatch } from "@/lib/spring/boot/application"
class User { let name: string; let age: int }
@RestController
class TC {
    @PostMapping(path = "/users")
    function createUser(@RequestBody user: User): string { return "user=" + user.name + ",age=" + user.age }
}
function main() {
    let req: Map<string, string> = new Map()
    req.set("path", "/users")
    req.set("method", "POST")
    req.set("body", "{\"name\":\"alice\",\"age\":30}")
    println(dispatch(req))
}
EOF
$ bin/ss run /tmp/t_i021_rb_red.ss 2>&1 | grep -oE "user=.*age=[0-9]+|not found|silent"
# 预估 before: not found 或 silent type miscompile
# 期望 after:  user=alice,age=30
```

一句话:**lib/json.ss 缺 primitive 字段 helper** + **comptime 无 RequestBody 分支** + **sentinel 无 RequestBody kind** + **codegen 无 per-class deserializer 自动生成** 四层缺口齐发,Phase 4 RESTful POST/PUT/PATCH JSON body endpoint 永久不可表达。

---

## 第一性需求

SS 用户写 `function createUser(@RequestBody user: User)` POST body controller,curl `POST /users -d '{"name":"alice","age":30}'` 行为字面对齐 Java `@RequestBody User user`:byte-identical body, User { name: "alice", age: 30 } 反序列化通过,无 silent 4xx,无 silent type miscompile。

Why 两层:

- **Why1**:不做 → Spring REST API 第二大能力 POST/PUT/PATCH JSON body resource 永久不可表达;`/users` 创建 / `/users/{id}` 整体更新 / `/users/{id}` 部分更新 三大 REST 资源动词全线 silent 4xx
- **Why2**:→ Phase 4 §247 第二支柱永久断裂 + Phase 5 Java oracle parity diff 在所有 POST/PUT/PATCH JSON body endpoint 永久 BLOCKED + V=class 跨域 deserializer 基础能力(I021-modelattribute 姊妹也需要)永久无独立 lib 层落地 + per-class deserializer codegen 自动生成模式(类比 ss_drop_X 自动生成,Perceus RC + ObjectLayout TypeInfo 完整化第四步)永久缺位

**末层可观测否定证据**:不做 → curl `POST :8080/users -d '{"name":"alice","age":30}'` 永久 silent 4xx,Phase 5 Java oracle parity CI 测试矩阵 POST endpoint 列永久 RED + REST API 表达力残废一半(只能 GET 不能 POST/PUT/PATCH JSON body)

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | **per-class `@ClassName_deserialize(node: JsonNode): ClassName` codegen 自动生成**(mirror `ss_drop_X` / `ss_deep_clone_X` 自动生成模式)+ invoke sentinel emit `JSON_parse(body) → ClassName_deserialize(node) → cast ptr`,字段递归处理(primitive 调 jnGet*,嵌套 class 递归调 nested ClassName_deserialize)| 接口层 trap;mirror Perceus RC 已建立的 per-class 函数自动生成模式(D018+D022);所有 class 自动获得反序列化能力,用户零负担;编译期展开消除运行时反射(D088 §第一性需求 alignment) ✅ |
| B | 用户手写每 class `function User_fromJson(json: string): User`,SS 不自动生成,sentinel emit `User_fromJson(body)` | 用户负担重,Java parity 断裂(Java 不需手写,Jackson/Gson 自动);跨 class 量大,反射 V=class 跨 controller 统一接口失败 ✗ 数据层 patch |
| C | 单一全局 `JSON_deserialize(node: JsonNode, typeName: string): ptr` runtime 函数,运行时按 typeName 字符串分派字段提取 | 反射开销大;codegen 缺类型保证(返回 ptr 无静态类型);违反 D088 §第一性需求 "编译期展开消除运行时反射";违反 D018 ObjectLayout TypeInfo 编译期已知契约 ✗ 架构层 refactor 但反向 D088 |
| D | 走 Jackson-like 注解 mapping `@JsonProperty("name")` + 字段级 binding | 引入第二层 annotation 复杂度;跨 controller 注解扩散;V0 不需要(SS 字段名 = JSON key 即可);非 Spring Boot 默认行为(Spring Boot 默认按字段名匹配)✗ scope 爆 |

**选 A 因 mirror 编译期生成 per-class 函数模式(`ss_drop_X` / `ss_deep_clone_X` / `ss_shallow_clone_X` 已有先例)+ codegen 自动展开消除运行时反射(D088 §第一性需求 alignment)+ 用户零负担(零手写代码)+ D018 ObjectLayout TypeInfo + D022 clone 语义 完整化第四步 per-class deserializer**

---

## v0 scope 切分说明

**做**(本 issue):

- `lib/json.ss`:
  - 加 primitive 字段提取 helper:`function jnGetInt(node: JsonNode, key: string): int` / `function jnGetDouble(node: JsonNode, key: string): double` / `function jnGetString(node: JsonNode, key: string): string` / `function jnGetBool(node: JsonNode, key: string): int`
  - mirror 现有 `jnGetField` 接口风格,内部走 `jnGetField` + 节点 typeKind 分派 + 字段缺失 fallback 默认值(int=0 / string="" / bool=0 / double=0.0,**保留 v0 简化**;严格"字段缺失 4xx 响应"留 I021-requestbody-validation)
- `lib/spring/boot/application.ss`:
  - 加常量 `PARAM_KIND_REQUEST_BODY = "RequestBody"`
  - **comptime _ssRoutes block** 加 `pAnn.name == "RequestBody"` 分支 push spec(kind="RequestBody", className=p.type)— 注意 ParamSpec 是否需新增 `className` slot **若 ParamSpec 当前无 className 字段则需扩 slot**,D123 §253 alignment 评估:`ParamSpec.kind` 字面值集合扩大 ≠ Meta 数据形态扩字段,但 `ParamSpec.className` 是新字段,需 §253 申报或重用 `ParamSpec.name` slot 复用(权衡 Execute 轮决策段)
  - **dispatcher 改**(若需要):POST body 提取入 `req.set("__body", body_string)` 命名空间;若 dispatcher 已经在 I014 split body 时即写入 `req` 则 alignment 现有 namespace,不重复 plumbing
- `bootstrap/eval/method_call.ss` invoke sentinel `useParamSpecs` 分支:
  - 把 `if (kindStr == "RequestParam" || kindStr == "PathVariable")` 升 `if (kindStr == "RequestParam" || kindStr == "PathVariable" || kindStr == "RequestBody")`
  - kind == "RequestBody" 分支 emit:
    ```
    %body = ss_mapGetString(req, "__body")
    %node = JSON_parse(%body)            ; 复用 lib/json.ss
    %inst = @ClassName_deserialize(%node) ; 编译期生成的 per-class deserializer
    ; 然后走 ptr cast 通道(I021bc / I021-multi-param 已有路径)
    ```
- `bootstrap/gen/`(具体子族待 Execute 轮 grep `gen_class.ss` / `gen_methods.ss` / `gen_class_methods.ss` 后定位):
  - 编译期 emit `@ClassName_deserialize(node: ptr) -> ClassName`(类比 `ss_drop_X` / `ss_deep_clone_X` 自动生成),每个 user class 自动产出
  - 字段递归:遍历 `classFields["ClassName"]` 列表,逐字段:
    - primitive(int/double/string/bool)→ 调 `jnGetInt` / `jnGetDouble` / `jnGetString` / `jnGetBool`
    - 嵌套 class → 递归调 `<NestedClassName>_deserialize`(本 v0 内置 plumbing,但实测覆盖留 I021-requestbody-nested 子档)
    - Array<T> / Map<K,V> → **本 v0 不支持**(留 I021-requestbody-array / I021-requestbody-map),codegen 检测到 Array/Map 字段时报编译错"@RequestBody 当前不支持 Array/Map 字段(留 I021-requestbody-array)"
- `examples/spring-parity/hello/ss/HelloController.ss`:加 `@PostMapping(path = "/users")` + `function createUser(@RequestBody user: User): string`
- `examples/spring-parity/hello/java/.../HelloController.java`:Java oracle 同步加 `@PostMapping("/users")` + `@RequestBody User user`
- `tests/phase5/i021_requestbody.ss`:新建,5+ case + IR 锚:
  - ① 单 class 简单字段(string + int 主用例)
  - ② 字段顺序乱(JSON 字段顺序 != class 声明顺序)
  - ③ JSON 字段缺失(v0 fallback 默认值)
  - ④ 字段类型 string(纯 string 字段 class)
  - ⑤ 字段类型 double(浮点字段)
  - ⑥ 静态 IR 锚 shell-level grep `@User_deserialize\(.*JsonNode.*\)` + grep `JSON_parse.*__body`

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立):

- **I021-requestbody-nested** — 嵌套 class(`User { addr: Addr }`)深度反序列化 RC 契约 + 字段所有权传递
- **I021-requestbody-array** — JSON Array → SS Array<T> 反序列化(`@RequestBody users: Array<User>`)
- **I021-requestbody-map** — JSON Object → Map<string, V> 反序列化
- **I021-requestbody-validation** — `@Validated` 字段约束(`@NotNull` / `@Email` / `@Min/@Max`),字段缺失 / 类型不匹配 4xx 响应
- **I021-requestbody-charset** — 字符编码(UTF-8 / GBK)reverse path 处理
- **I021-modelattribute** — 姊妹跨域(query string 多 key → class 多字段),共享 deserializer 基础能力但走不同数据源(query → field map vs JSON → field map)

**不做**:

- 不扩 invoke sentinel ABI(单 map + namespace prefix `__body` 已合规)
- 不动 ParamMeta / RouteMeta 数据形态(D123 §253 alignment;ParamSpec.kind 字面值扩大不算 Meta 扩字段);若 ParamSpec.className 必须新增 → Execute 轮独立决策段记录权衡(§字段 8 评估)
- 不实现嵌套深度反序列化超过 1 层(留 I021-requestbody-nested)
- 不实现 JSON Array / Map 字段(留 I021-requestbody-array / I021-requestbody-map)
- 不实现 `@Validated` 字段约束(留 I021-requestbody-validation)
- 不引入 `@JsonProperty` / Jackson-like 注解 mapping(选 A 路径不需要)
- 不动 reflection_health_linter baseline(改动可能触 F1 漂,Execute 跑后按 D097 §B 申报)

---

## 步骤(Execute 轮按序)

1. **RED 最小隔离测试**:`/tmp/t_i021_rb_red.ss` 写 `function createUser(@RequestBody user: User)` Controller + dispatch 模拟,实测 stdout `not found` 或 silent type miscompile + IR 锚 grep 无 `User_deserialize` 函数定义
2. **lib/json.ss primitive 字段 helper**:加 `jnGetInt` / `jnGetDouble` / `jnGetString` / `jnGetBool`,内部走 `jnGetField` + typeKind 分派 + 默认值 fallback
3. **lib/spring/boot/application.ss**:
   - PARAM_KIND_REQUEST_BODY const
   - comptime _ssRoutes block 加 `pAnn.name == "RequestBody"` push spec
   - dispatcher body 入 req 命名空间(若需要)
4. **bootstrap/eval/method_call.ss invoke sentinel kind 扩**:`||  kindStr == "RequestBody"` 升 if 条件 + RequestBody 分支 emit `JSON_parse → ClassName_deserialize → cast ptr`
5. **bootstrap/gen/codegen.ss(或 gen_class.ss / gen_class_methods.ss)per-class deserializer 自动生成**:类比 `ss_drop_X` 自动生成路径,每 user class 产出 `@ClassName_deserialize(node: ptr): ClassName`,字段递归 emit 调 jnGet* / nested deserialize
6. **HelloController.ss + Java oracle 同步**
7. **tests/phase5/i021_requestbody.ss** 5+ case
8. **bootstrap 固定点** `./build.sh bootstrap` Stage 2 = Stage 3
9. **gate** `bin/ss run tools/reflection_health_linter.ss` + `bin/ss run tools/d_doc_index_linter.ss`
10. **parity 端到端** `/tmp/hello_rb --serve` + `curl -X POST :8080/users -d '{"name":"alice","age":30}'` 期望 `user=alice,age=30` byte-identical Java
11. **simplify**(`/simplify` skill)+ commit

---

## 反向 / 备选

**备选 B(用户手写 ClassName_fromJson)**:
- 优点:实现简单,无 codegen 自动生成
- 缺点:用户负担重,Java parity 断裂(Java 不需手写);跨 class 量大,反射统一接口失败 ✗ 数据层 patch

**备选 C(单一全局 JSON_deserialize runtime 函数 + typeName 字符串分派)**:
- 优点:codegen 不需扩 per-class 函数生成,统一 runtime 接口
- 缺点:运行时反射开销;违反 D088 §第一性需求"编译期展开消除运行时反射";违反 D018 ObjectLayout TypeInfo 编译期已知契约;返回 ptr 类型无静态类型保证 ✗ 架构层但反向 D088

**备选 D(Jackson-like @JsonProperty 字段映射 annotation)**:
- 优点:用户细粒度控制 JSON key / class field 映射(`@JsonProperty("user_name") name: string`)
- 缺点:引入第二层 annotation 复杂度爆;跨 controller 注解扩散;V0 不需要(SS 字段名 = JSON key 即可);非 Spring Boot 默认 ✗ scope 爆

**不做 → 后果**:
- Phase 4 §247 第二支柱 @RequestBody 永久断裂
- Spring REST API 第二大能力(POST/PUT/PATCH JSON body resource)永久不可表达
- Phase 5 Java oracle parity diff 在所有 POST/PUT/PATCH JSON body endpoint 永久 BLOCKED
- D088 §第一性需求 编译期展开消除运行时反射 在 V=class deserializer 维度永久断裂
- D018 ObjectLayout TypeInfo + D022 clone 语义 + D018 per-class 自动生成 第四步(deserializer)永久缺位,Perceus RC 跨域(序列化反序列化对称)永久不完整

---

## 验收 RED 命令

```bash
# RED 1: comptime RequestBody 分支不存在
grep -c '"RequestBody"' lib/spring/boot/application.ss
# before: 0  after: ≥ 2 (PARAM_KIND_REQUEST_BODY const + comptime 分支)

# RED 2: invoke sentinel 无 RequestBody kind 分支
grep -cE '"RequestBody"' bootstrap/eval/method_call.ss
# before: 0  after: ≥ 2 (kind 比对 + 注释)

# RED 3: lib/json.ss 无 primitive 字段提取 helper
grep -cE "^function jnGet(Int|Double|String|Bool)" lib/json.ss
# before: 0  after: ≥ 4

# RED 4: codegen 无 per-class deserializer 自动生成
grep -cE "_deserialize\b" bootstrap/gen/
# before: 0  after: ≥ 2 (gen 函数 def + emit 锚)

# RED 5: 端到端 silent 4xx
cat > /tmp/t_i021_rb_red.ss <<'EOF'
import { dispatch } from "@/lib/spring/boot/application"
class User { let name: string; let age: int }
@RestController
class TC {
    @PostMapping(path = "/users")
    function createUser(@RequestBody user: User): string { return "user=" + user.name + ",age=" + user.age }
}
function main() {
    let req: Map<string, string> = new Map()
    req.set("path", "/users")
    req.set("method", "POST")
    req.set("body", "{\"name\":\"alice\",\"age\":30}")
    println(dispatch(req))
}
EOF
bin/ss run /tmp/t_i021_rb_red.ss 2>&1 | grep -oE "user=alice,age=30|not found"
# before: not found
# after:  user=alice,age=30

# RED 6: 静态 IR 锚 — per-class deserializer + sentinel emit
bin/ss build /tmp/t_i021_rb_red.ss --emit-ir > /tmp/t_i021_rb_red.ll 2>&1
grep -c "@User_deserialize" /tmp/t_i021_rb_red.ll
# before: 0  after: ≥ 2 (define + call)
grep -c "JSON_parse.*__body" /tmp/t_i021_rb_red.ll
# before: 0  after: ≥ 1

# 单测
bin/ss run tests/phase5/i021_requestbody.ss

# 多 issue backward compat regression
bin/ss run tests/phase5/i021_request_param_string.ss      # I021 v0 hello string
bin/ss run tests/phase5/i021bc_typed_request_param_cast.ss   # I021bc int/double
bin/ss run tests/phase5/i021_multi_param.ss               # I021-multi-param 多参
bin/ss run tests/phase5/i021_pathvariable.ss              # I021-pathvariable 占位符

# 工程
./build.sh bootstrap                                       # Stage 2 = Stage 3 固定点
bin/ss test tests/                                         # 全绿

# parity 端到端
/tmp/hello_rb --serve &
curl -s -X POST -H "Content-Type: application/json" "http://localhost:8080/users" -d '{"name":"alice","age":30}'
# 期望: user=alice,age=30 byte-identical Java oracle
curl -s "http://localhost:8080/hello?name=SS"              # I021 v0 backward compat: Hello, SS!
curl -s "http://localhost:8080/users/42"                   # I021-pathvariable backward compat: user=42

# gate
bin/ss run tools/reflection_health_linter.ss
bin/ss run tools/d_doc_index_linter.ss
```

---

## 风险 / 表面 / 下轮升根路径

**本 issue 设计层根解决**(per-class deserializer codegen 自动生成 + invoke sentinel kind 扩 RequestBody):消除"V=class 反序列化无独立 lib 层"+ deserializer 与 @RequestBody / @ModelAttribute 域共享同一基础能力。不变量锚:`bootstrap/gen/<gen-class-子族>/ ClassName_deserialize 自动生成` / `bootstrap/eval/method_call.ss:135 §useParamSpecs RequestBody kind 分支` / `lib/json.ss jnGetInt/Double/String/Bool primitive helpers`。

**潜在工程风险**:

1. **ParamSpec.className 字段是否新增**:本 issue v0 设计假设 ParamSpec 有或可重用 slot 表达 class type name(用于 codegen emit `<ClassName>_deserialize`)。Execute 轮需:
   - grep `^class ParamSpec\|ParamSpec\.\|ParamSpec\(` 现有定义,定位 slot 列表
   - 若现有 slot 无 className → 评估重用 `name` slot(name 已用于 `@RequestBody name=user` 的 name 参数)vs 新增 className slot
   - 重用 vs 新增的权衡按 D123 §253 "RouteMeta 不扩字段"alignment + §字段 9 表面/根判定记录在 Execute 轮决策段
2. **per-class deserializer 自动生成 trigger 时机**:类比 `ss_drop_X` 何时 emit?`bootstrap/gen/class/<对应文件>` grep `ss_drop_` 自动生成入口,定位"每 class 处理一次"的循环点;`ss_*_deserialize_X` 应 hook 同一入口
3. **JSON 字段缺失 fallback 行为**:v0 决定走"默认值 fallback"(int=0 / string="" / bool=0 / double=0.0)而非"4xx 响应",理由是 Spring Boot 默认行为也是 fallback 默认(Jackson `FAIL_ON_NULL_FOR_PRIMITIVES=false` 默认);严格"字段缺失 4xx" 留 I021-requestbody-validation
4. **嵌套 class 字段递归 RC 契约**:User { addr: Addr } 反序列化时 Addr 实例所有权 transfer 给 User;`<Addr>_deserialize` 返回 Addr ptr,User_deserialize 字段填充时直接 store(无 retain),**Execute 轮 RC 契约严格审视**(留 I021-requestbody-nested 子档实测;本 issue v0 仅文档实测覆盖单层 class)
5. **F1 baseline 漂**:`bootstrap/gen/class/`(若拆)+~120-200 LOC;若 codegen.ss 未拆,需评估 F1 行数压力;按 D097 §B 申报
6. **lib/json.ss 行数漂**:加 4 个 primitive helper +30-50 LOC,当前 lib/json.ss 18594 bytes ~580 行,扩后 ~620-630 行需评估 F1(若 lib 未在 F1 白名单则不阻)
7. **`@PostMapping` 解析路径**:I021-pathvariable 已建立 GET endpoint,POST endpoint 是否走相同 dispatcher path 决定?预期 I014 dispatcher 已支持 method 分派(GET/POST/PUT/DELETE/PATCH),Execute 轮 grep `method == "POST"` 验证现有 plumbing;若缺,本 issue 需补 method 分派 plumbing(scope 微扩)

**v0 已 plumbing 完整设计**(无表面遗留):本 issue 全程根因解决,per-class deserializer codegen 自动生成 + invoke sentinel kind 扩 + lib/json.ss primitive helper 三层 alignment。下轮独立 issue:嵌套深度 / Array / Map / Validated / Charset / ModelAttribute 共享 deserializer 基础能力。

---

## 触发场景

- D123 §247 §Phase 4 第二支柱 @RequestBody 端到端
- D129 §5 决策 V=class 反序列化能力 lib 层独立基础能力起立
- I021-pathvariable 收关后 Phase 4 §247 第二支柱缺口闭环
- Phase 4+ @RequestBody 嵌套 class / Array / Map 同模式扩展前置基础能力
- I021-modelattribute 姊妹跨域起立时共享 deserializer 基础能力(同一 per-class deserializer 函数集)
- Phase 5 Java oracle parity CI 端到端 diff 在 POST/PUT/PATCH JSON body endpoint 不再 silent 4xx

---

## 备注

- **根因锚**:本 issue 修 D123 Phase 4 第二支柱 @RequestBody 单根因 — per-class deserializer codegen 自动生成 + invoke sentinel kind 扩 RequestBody(接口层 trap),非用户手写 fromJson(数据层 patch)或单一全局 JSON_deserialize runtime(架构层 refactor 但反向 D088)
- **mirror I021-pathvariable / I021-multi-param 模式**:I021-pathvariable 已建立 sentinel kind 三分(RequestParam/PathVariable/RequestMap),本 issue 扩四分(+ RequestBody),sentinel cast 通道完全复用,不另开 sentinel 路径
- **mirror per-class 函数自动生成模式**:D018 + D022 已建立 `ss_drop_X` / `ss_deep_clone_X` / `ss_shallow_clone_X` 三 per-class 函数自动生成模式,本 issue 加第四个 `ClassName_deserialize`,Perceus RC + ObjectLayout TypeInfo 跨"序列化反序列化对称"维度完整化
- **D123 §253 alignment**:不扩 RouteMeta / ParamMeta / MethodMeta 数据形态,只扩 ParamSpec.kind 字面值集合(标量值不算 Meta 扩展);ParamSpec.className 若必须新增,Execute 轮独立决策段记录权衡(§字段 9 表面/根判定)
- **D088 §第一性需求 alignment**:per-class deserializer 编译期生成,运行时调单一函数指针(`@User_deserialize(node)`),无 typeName 字符串分派开销;codegen 路径完全编译期展开
- **D129 §3 跨域 deserializer 路径独立**:本 issue 落地 deserializer 基础能力(JSON → class field map),I021-modelattribute 姊妹起立时共享同一 per-class deserializer 函数集(数据源不同 — query string vs JSON body),lib 层 deserializer 不重复实现
- **预估对照**:本 issue 大改 ~300-450 LOC 跨 6-7 文件;Execute 轮独立 commit 禁打包(MNK §改动分层 §大改 After Done);若 codegen 拆分多文件 + ParamSpec slot 决策段独立扩,可能需切多轮(至少 2 轮 Execute:第一轮 lib + comptime + sentinel,第二轮 codegen per-class deserializer 自动生成 + 端到端 RED→GREEN)
- **D067 T? narrow alignment**(未来):`@RequestBody user: User?` 可空形参未来若涉及 narrow check,各自子决策段引 D067 narrow 机制(类比 I020c §I020c 子决策段对 D067 alignment 模式);本 issue v0 仅支持非空 `User`,可空形参留 I021-requestbody-nullable 子档
