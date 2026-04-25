# I021-requestheader — @RequestHeader HTTP header → 形参绑参(__hdr_ prefix 独立 namespace)

**父决策:** D123 §247-259 §Phase 4 §第一性需求 + §440 Web MVC 注解词典(含 RequestHeader)+ §550 表 F 行 + §561 Phase 4 F + §742 Phase 4 收关 "@PathVariable / @RequestHeader 各自独立 issue 复用 funcParamTypes + invoke sentinel cast 通道" + D129 §5 line 129 第二半 I021-modelattribute Dropped 同轮承诺起 I021-requestheader 替代第四主流注解
**状态:** Planned (2026-04-25 立项 — 本轮 next_prompt option A 用户拍 A+C 锁定;Execute 留下轮)
**颗粒度:** 预估 ~80-120 LOC 跨 5 文件(`lib/http.ss` parseRequest header 写入加 `__hdr_` prefix +1-3 / `lib/spring/boot/application.ss` PARAM_KIND_REQUEST_HEADER const + comptime _ssRoutes RequestHeader 分支 +6-10 / `bootstrap/eval/method_call.ss` invoke sentinel kind 扩 RequestHeader 分支(共享 RequestParam/PathVariable cast 通道,加 `__hdr_<lower-name>` lookupKey 分派)+5-10 / `examples/spring-parity/hello/ss/HelloController.ss` 加 endpoint +5-8 + `examples/spring-parity/hello/java/.../HelloController.java` Java oracle 同步 +5-8 / `tests/phase5/i021_requestheader.ss` 新建 ~50-70)
**依赖:** I021(Done at `lib/spring/boot/application.ss:42-83` paramSpecs comptime block)/ I021bc(Done at 9ca4077 funcParamTypes typed cast)/ I021-multi-param(Done at 065d803 invoke sentinel useParamSpecs 数据驱动展开)/ I021-pathvariable(Done at 2f5dd1b matchPath buffered commit + sentinel kind 共享 cast 通道)/ I021-requestbody(Done at 8165370 sentinel kind 集合扩 + per-class deserializer 自动生成)/ `lib/http.ss:6 parseRequest`(Done — header lowercase normalize + req map 写入已就位,line 76 `hName.toLowerCase()` + line 78 `req.set(hName, hVal)`)/ D123 §253 不扩 Meta(本 issue alignment,RouteMeta/ParamMeta 数据形态零变更)
**创建:** 2026-04-25
**立项由:** I021-requestbody 收关后(Phase 4 §247 三支柱 PathVariable / RequestParam / RequestBody 全闭环);next_prompt 第一推 I021-modelattribute(D129 §5 line 129 第二半承诺)被用户判定"现代 REST 不主流可弃" → A+C 重排:首推 I021-requestheader(第四主流注解,JWT/Auth/CORS 业务高频使用)+ 同步更新 D129 §5 line 129 标 @ModelAttribute Dropped(详 D129 §9 "I021-modelattribute Dropped 锚")。本 issue 起子档不动代码,Execute 留下轮按"决策归档后 next_prompt 直接 Execute 不 Plan"原则单轮端到端

---

## 问题

I021-requestbody 收关后,Phase 4 第四主流注解 @RequestHeader 仍 100% 不可表达,根因是 **header namespace 隔离 + comptime annotation 识别 + sentinel kind 分派** 三层缺口齐发:

- ✅ 反射 Meta 三层(ParamMeta.annotations / MethodMeta.params 填充 / RouteMeta.paramSpecs)已通(I021)
- ✅ HTTP header parse 入 req map 已通(`lib/http.ss:62-81` parseRequest 头解析,line 76 `hName.toLowerCase()` + line 78 `req.set(hName, hVal)`)
- ✅ invoke sentinel kind 集合 = {RequestParam, PathVariable, RequestBody, RequestMap} 已建立(I021-pathvariable + I021-requestbody)
- ❌ `lib/http.ss:78 req.set(hName, hVal)` **无 namespace prefix**,header 直接入 req 与 query string keys 同 namespace —— `?content-type=fake` 与 HTTP `Content-Type:` header 撞 key,后写覆盖前写;违反 I021-pathvariable __pv_ namespace 严格分离精神
- ❌ `lib/spring/boot/application.ss:42-83` _ssRoutes comptime block 无 `pAnn.name == "RequestHeader"` 分支,@RequestHeader 标注的形参不进 paramSpecs(走 fallback 静态路径)
- ❌ `bootstrap/eval/method_call.ss:135 §useParamSpecs` invoke sentinel kind 集合不含 RequestHeader,该 kind 无 emit 路径

silent 行为画像(预估 RED,Execute 轮实测确认):
```bash
$ cat > /tmp/t_i021_hdr_red.ss <<'EOF'
import { dispatch } from "@/lib/spring/boot/application"
@RestController
class TC {
    @GetMapping(path = "/agent")
    function agent(@RequestHeader(name = "user-agent") ua: string): string { return "ua=" + ua }
}
function main() {
    let req: Map<string, string> = new Map()
    req.set("path", "/agent")
    req.set("method", "GET")
    req.set("user-agent", "SimpleScript/1.0")    # I021-requestheader v0 头入 req 已 lowercase normalize
    println(dispatch(req))
}
EOF
$ bin/ss run /tmp/t_i021_hdr_red.ss 2>&1 | grep -oE "ua=[^[:space:]]+|not found|silent"
# 预估 before: not found(comptime 无 RequestHeader 分支 → 形参不进 paramSpecs → fallback null)
# 期望 after:  ua=SimpleScript/1.0
```

一句话:**lib/http.ss 头入 req 无 namespace prefix** + **comptime 无 RequestHeader 分支** + **sentinel 无 RequestHeader kind** 三层缺口齐发,Phase 4 第四主流注解(JWT/Auth/CORS/X-Trace-Id)永久不可表达。

---

## 第一性需求

SS 用户写 `function agent(@RequestHeader("User-Agent") ua: string)` HTTP header → 形参绑参 Controller,curl `-H "User-Agent: SimpleScript/1.0" /agent` 行为字面对齐 Java `@RequestHeader("User-Agent") String userAgent`:byte-identical body,无 silent 4xx,无 silent type miscompile。

Why 两层:

- **Why1**:不做 → JWT Bearer auth(`@RequestHeader("Authorization") token: string`)/ X-API-Key 认证 / X-Request-ID 链路追踪 / Content-Type 内容协商 / User-Agent 客户端识别 / X-Forwarded-For 反向代理识别 / X-CSRF-Token CSRF 防护 等**所有 HTTP header 业务**永久无 SS 表达;现代 REST API 第四主流注解(@PathVariable / @RequestParam / @RequestBody 三支柱已闭环 + @RequestHeader)永久断裂
- **Why2**:→ Phase 4 三支柱 + 第四注解(D123 §440 Web MVC 注解词典)在 SS Spring parity enterprise 尺度兑现仅 75% + Phase 5 Java oracle parity diff 在所有 header-bound endpoint 永久 BLOCKED + JWT/CORS/Auth 类企业 REST API 业务在 SS 永久 RED,Spring Boot enterprise 尺度兑现残废

**末层可观测否定证据**:不做 → curl `-H "Authorization: Bearer xxx" :8080/api/me` 永久 silent 4xx,Phase 5 Java oracle parity CI header-bound 测试列永久 RED + tests/phase5/spring_web_params.ss line 26 `function agent(@RequestHeader userAgent: string)` 历史测试在新 dispatch 路径下永久 silent miscompile

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | **`lib/http.ss:78` parseRequest 头入 req 加 `__hdr_` prefix**(`req.set("__hdr_" + hName, hVal)`)+ comptime _ssRoutes block 加 `pAnn.name == "RequestHeader"` push spec(kind="RequestHeader", name=pAnn.args.getString("name").toLowerCase())+ invoke sentinel kindStr == "RequestHeader" 分支 emit `lookupKey = "__hdr_" + nameStr` lookup(nameStr 在 comptime push spec 时已 lowercase normalize,sentinel emit 不重复),共享 RequestParam/PathVariable cast 通道(int/double/ptr 分派)| 接口层 trap;mirror I021-pathvariable __pv_ namespace 严格分离精神;header lowercase normalize 一致 alignment Spring 行为(Spring `@RequestHeader("User-Agent")` 接受大小写不敏感);sentinel cast 通道复用,不另开路径 ✅ |
| B | header 直接入 req 无 prefix(保留 `lib/http.ss:78` 现状),sentinel `lookupKey = nameStr.toLowerCase()` 直接 lookup | 工程量略小(无 prefix 字符串拼接);但 query namespace 与 header namespace 同 key 撞(如 `?content-type=fake` 与 `Content-Type:` header 撞)→ 后写覆盖前写,违反 I021-pathvariable __pv_ namespace 严格分离精神 ✗ 表面方案 |
| C | header 入独立 Map<string, string> headers 字段(req map + headers map 双 map ABI),sentinel emit `ss_mapGetString(headers, name)` | namespace 严格分离;但 invoke sentinel ABI 大改(单 map 升双 map),backward compat 全 null 第二参 ~150 LOC,工程量爆 + 与 I021-pathvariable __pv_ 单 map + prefix 模式不一致 ✗ |
| D | 走 jakarta/servlet HttpServletRequest.getHeader(name) Java-style API + 用户手工调用,SS 不做 @RequestHeader 反射注入 | 用户负担重,非 Spring `@RequestHeader` 反射注入风格;Java parity 断裂(Spring 默认走 @RequestHeader 反射),未来用户混淆 ✗ 数据层 patch |

**选 A 因 mirror I021-pathvariable __pv_ namespace 严格分离精神 + sentinel cast 通道完全复用 + header lowercase normalize 一致 alignment Spring 行为 + RouteMeta/ParamMeta 数据形态零变更(D123 §253 不新建 Meta 完全合规)**

---

## v0 scope 切分说明

**做**(本 issue Execute 轮):

- `lib/http.ss`:
  - line 78 `req.set(hName, hVal)` → `req.set("__hdr_" + hName, hVal)` (1 行 edit;hName 已 lowercase normalize 走 line 76,prefix 即 __hdr_<lower-name>)
  - 注释段加锚:`// I021-requestheader: header 入 __hdr_ namespace 与 query 严格分离`
- `lib/spring/boot/application.ss`:
  - 加常量 `const PARAM_KIND_REQUEST_HEADER = "RequestHeader"`
  - **comptime _ssRoutes block** 加 `pAnn.name == "RequestHeader"` 分支 push spec(kind=PARAM_KIND_REQUEST_HEADER, name=pAnn.args.getString("name").toLowerCase(), type=p.type) — name lowercase normalize 与 lib/http.ss:76 一致
- `bootstrap/eval/method_call.ss` invoke sentinel `useParamSpecs` 分支:
  - 把 `if (kindStr == "RequestParam" || kindStr == "PathVariable")` 升 `if (kindStr == "RequestParam" || kindStr == "PathVariable" || kindStr == "RequestHeader")` 共享代码块
  - 加 if-elseif-else 链分派 lookupKey:`PathVariable → "__pv_" + nameStr` / `RequestHeader → "__hdr_" + nameStr` / 其他(默认 RequestParam,RequestBody/RequestMap 在外层 kind 分派 short-circuit)→ `nameStr` (nameStr 在 comptime push 时已 lowercase normalize,sentinel emit 处不重复 toLowerCase)
  - cast 通道(int/double/ptr 分派)复用,不另开 sentinel 路径
- `examples/spring-parity/hello/ss/HelloController.ss`:加 `@GetMapping("/agent")` + `function agent(@RequestHeader("user-agent") ua: string)`(Spring `@RequestHeader("User-Agent")` 大小写不敏感 alignment,SS lowercase 习惯写法)
- `examples/spring-parity/hello/java/.../HelloController.java`:Java oracle 同步加 `@GetMapping("/agent")` + `@RequestHeader("User-Agent") String ua`
- `tests/phase5/i021_requestheader.ss`:新建,5+ case + IR 锚:
  - ① 单 header(`User-Agent` → ua: string 主用例)
  - ② typed cast int(`X-Count: 42` → count: int,复用 I021bc cast 通道)
  - ③ typed cast double(`X-Score: 3.14` → score: double)
  - ④ 多 header 共一 endpoint(`Authorization` + `X-Request-ID` 双形参)
  - ⑤ header 缺失 fallback(req map 无对应 key,ss_mapGetString 返空字符串)
  - ⑥ 静态 IR 锚 shell-level grep `ss_mapGetString.*__hdr_user-agent`

**留下轮**(独立 issue,本 issue Execute 收关后立):

- **I021-requestheader-required** — `@RequestHeader(name="X-Required", required=true)` 缺失 → 4xx 响应(v0 fallback 默认值,严格 required 校验留 issue)
- **I021-requestheader-default** — `@RequestHeader(name="X-Optional", defaultValue="fallback")` 缺失走默认值
- **I021-requestheader-multi-value** — 同 header name 重复(`Cache-Control: no-cache` + `Cache-Control: no-store`)→ List<String> 接收(Spring `@RequestHeader("Cache-Control") List<String> values` 模式)
- **I021-requestheader-cookie** — `@CookieValue("sessionId")` 共享 header parse 基础能力(Cookie header 二级 parse)

**不做**:
- 不扩 invoke sentinel ABI(单 map + namespace prefix `__hdr_` 已合规,与 I021-pathvariable __pv_ 模式一致)
- 不动 ParamMeta / ParamSpec / RouteMeta 数据形态(D123 §253 完全合规;ParamSpec.kind 字面值集合扩大不算 Meta 扩字段)
- 不实现 `@RequestHeader(required=false)` / 默认值 / 重复 header List 接收(留 I021-requestheader-required / -default / -multi-value)
- 不依赖 `lib/jakarta/servlet.ss` HttpServletRequest.getHeader(应用层不走 servlet 抽象,Spring 反射注入风格)
- 不动 reflection_health_linter baseline(改动可能触 F1 漂,Execute 跑后按 D097 §B 申报)
- 不动 D129 §3 域归属辨析正文 / D123 §440 Web MVC 注解词典(SSoT 词典层 Spring 真实存在,本 issue 仅落 SS 实施)

---

## 步骤(Execute 轮按序)

1. **RED 最小隔离测试**:`/tmp/t_i021_hdr_red.ss` 写 `function agent(@RequestHeader("user-agent") ua: string)` Controller + dispatch 模拟,实测 stdout `not found`(comptime 无 RequestHeader 分支 → 形参不进 paramSpecs → fallback null)+ IR 锚 grep `ss_mapGetString.*__hdr_` = 0
2. **lib/http.ss parseRequest 头入 req 加 prefix**:line 78 `req.set("__hdr_" + hName, hVal)` 1 行 edit
3. **lib/spring/boot/application.ss**:
   - PARAM_KIND_REQUEST_HEADER const
   - comptime _ssRoutes block 加 `pAnn.name == "RequestHeader"` push spec(kind, name lowercase normalize, type)
4. **bootstrap/eval/method_call.ss invoke sentinel kind 扩**:`||  kindStr == "RequestHeader"` 升 if 条件 + `lookupKey` 三元嵌套或 if-elseif 链分派(__pv_ / __hdr_ / 默认 nameStr)
5. **HelloController.ss + Java oracle 同步**
6. **tests/phase5/i021_requestheader.ss** 5+ case + IR 锚
7. **bootstrap 固定点** `./build.sh bootstrap` Stage 2 = Stage 3
8. **gate** `bin/ss run tools/reflection_health_linter.ss` + `bin/ss run tools/d_doc_index_linter.ss`
9. **parity 端到端** `/tmp/hello_hdr --serve` + `curl -H "User-Agent: SimpleScript/1.0" :8080/agent` 期望 `ua=SimpleScript/1.0` byte-identical Java
10. **simplify**(`/simplify` skill)+ commit

---

## 反向 / 备选

**备选 B(header 直接入 req 无 prefix)**:
- 优点:工程量略小(无 prefix 字符串拼接,lib/http.ss 不动)
- 缺点:query namespace 与 header namespace 同 key 撞;违反 I021-pathvariable __pv_ namespace 严格分离精神 ✗ 表面方案

**备选 C(双 map ABI:req + headers)**:
- 优点:namespace 严格分离 + ABI 表达力强
- 缺点:invoke sentinel ABI 大改 ~150 LOC,backward compat 全 null 第二参,工程量爆;与 I021-pathvariable __pv_ 单 map + prefix 模式不一致 ✗

**备选 D(jakarta servlet HttpServletRequest.getHeader 用户手工调用)**:
- 优点:无新 plumbing 需求
- 缺点:用户负担重,非 Spring `@RequestHeader` 反射注入风格;Java parity 断裂 ✗ 数据层 patch

**不做 → 后果**:
- Phase 4 第四主流注解 @RequestHeader 永久断裂
- JWT Bearer auth / X-API-Key / X-Request-ID / Content-Type / User-Agent / X-Forwarded-For / X-CSRF-Token 等所有 header 业务在 SS 永久无 SS 表达
- Phase 5 Java oracle parity diff 在所有 header-bound endpoint 永久 BLOCKED
- D088 §第一性需求 编译期展开消除运行时反射 在 header 注解维度永久断裂
- tests/phase5/spring_web_params.ss line 26 `function agent(@RequestHeader userAgent: string)` 历史测试在新 dispatch 路径下永久 silent miscompile

---

## 验收 RED 命令

```bash
# RED 1: comptime RequestHeader 分支不存在
grep -c '"RequestHeader"' lib/spring/boot/application.ss
# before: 0  after: ≥ 2 (PARAM_KIND_REQUEST_HEADER const + comptime 分支)

# RED 2: invoke sentinel 无 RequestHeader kind 分支
grep -cE '"RequestHeader"' bootstrap/eval/method_call.ss
# before: 0  after: ≥ 2 (kind 比对 + 注释)

# RED 3: lib/http.ss 头入 req 无 __hdr_ prefix
grep -c '"__hdr_"' lib/http.ss
# before: 0  after: ≥ 1 (parseRequest 头入 req 加 prefix)

# RED 4: 端到端 silent 4xx
cat > /tmp/t_i021_hdr_red.ss <<'EOF'
import { dispatch } from "@/lib/spring/boot/application"
@RestController
class TC {
    @GetMapping(path = "/agent")
    function agent(@RequestHeader(name = "user-agent") ua: string): string { return "ua=" + ua }
}
function main() {
    let req: Map<string, string> = new Map()
    req.set("path", "/agent")
    req.set("method", "GET")
    req.set("__hdr_user-agent", "SimpleScript/1.0")
    println(dispatch(req))
}
EOF
bin/ss run /tmp/t_i021_hdr_red.ss 2>&1 | grep -oE "ua=SimpleScript/1.0|not found"
# before: not found
# after:  ua=SimpleScript/1.0

# RED 5: 静态 IR 锚 — sentinel emit __hdr_ prefix lookup
bin/ss build /tmp/t_i021_hdr_red.ss --emit-ir > /tmp/t_i021_hdr_red.ll 2>&1
grep -c "ss_mapGetString.*__hdr_user-agent" /tmp/t_i021_hdr_red.ll
# before: 0  after: ≥ 1

# 单测
bin/ss run tests/phase5/i021_requestheader.ss

# 多 issue backward compat regression
bin/ss run tests/phase5/i021_request_param_string.ss      # I021 v0 hello string
bin/ss run tests/phase5/i021bc_typed_request_param_cast.ss   # I021bc int/double
bin/ss run tests/phase5/i021_multi_param.ss               # I021-multi-param 多参
bin/ss run tests/phase5/i021_pathvariable.ss              # I021-pathvariable 占位符
bin/ss run tests/phase5/i021_requestbody.ss               # I021-requestbody JSON body

# 工程
./build.sh bootstrap                                       # Stage 2 = Stage 3 固定点
bin/ss test tests/                                         # 全绿

# parity 端到端
/tmp/hello_hdr --serve &
curl -s -H "User-Agent: SimpleScript/1.0" "http://localhost:8080/agent"
# 期望: ua=SimpleScript/1.0 byte-identical Java oracle
curl -s "http://localhost:8080/hello?name=SS"              # I021 v0 backward compat: Hello, SS!
curl -s "http://localhost:8080/users/42"                   # I021-pathvariable backward compat: user=42
curl -s -X POST -H "Content-Type: application/json" "http://localhost:8080/users" -d '{"name":"alice","age":30}'
# I021-requestbody backward compat: user=alice,age=30

# gate
bin/ss run tools/reflection_health_linter.ss
bin/ss run tools/d_doc_index_linter.ss
```

---

## 风险 / 表面 / 下轮升根路径

**本 issue 设计层根解决**(`__hdr_` namespace prefix 隔离 + comptime kind 分支 + sentinel kind 集合扩 RequestHeader):消除 header / query namespace 撞 key + alignment I021-pathvariable __pv_ 模式。不变量锚:`lib/http.ss:78 parseRequest "__hdr_" prefix` / `lib/spring/boot/application.ss PARAM_KIND_REQUEST_HEADER + comptime` / `bootstrap/eval/method_call.ss:135 §useParamSpecs RequestHeader kind 分支`。

**潜在工程风险**:

1. **header name 大小写规范**:Spring `@RequestHeader("User-Agent")` 接受大小写不敏感(Spring HeaderMap 内部 lowercase normalize)。SS alignment:lib/http.ss:76 已 `hName.toLowerCase()` normalize,本 issue comptime push spec 时 `pAnn.args.getString("name").toLowerCase()` 同步 normalize → sentinel emit `lookupKey = "__hdr_" + nameStr` (nameStr 已 lowercase),保证 lookup 一致命中
2. **string.toLowerCase() 内置存在性**:Execute 轮 grep `lib/string.ss\|toLowerCase\|@ss_string_to_lower` 验证 SS string.toLowerCase() 内置已就位;若缺需先补 lib 层 string helper(scope 微扩,留 I021-requestheader-strlower 子档评估)
3. **__hdr_ namespace backward compat**:`lib/http.ss:78` 加 prefix 后,任何使用旧形式(`req.get("user-agent")` 直接读 header)的代码会断;**全仓 grep** `req\.get\(.*"(user-agent|content-type|authorization|...)"` 等已知 header name 直接 lookup 模式,迁移到 `__hdr_<name>`;预期 v0 仅 `tests/phase5/spring_web_params.ss` 历史测试涉及(若走 dispatch 路径需迁移),Execute 轮 grep 验证
4. **多 header 同 endpoint cast 通道**:`function full(@RequestBody body: User, @RequestHeader contentType: string, @RequestHeader xRequestId: string)` 三 spec 共享同一 invoke sentinel,`useParamSpecs` 数据驱动展开应直接覆盖(I021-multi-param 已建模);本 issue 在 tests/phase5/i021_requestheader.ss case ④ 验证多 header 共 endpoint
5. **F1 baseline 漂**:`lib/http.ss` 1 行 edit,`lib/spring/boot/application.ss` +6-10,`bootstrap/eval/method_call.ss` +5-10;若 method_call.ss 接近 F1 600 行需评估拆分(§structure_not_linecount + §600_split_not_inline 原则);按 D097 §B 申报登 D123 §扩容申报-I021-requestheader anchor

**v0 已 plumbing 完整**(无表面遗留):本 issue 全程根因解决,header namespace prefix 隔离 + sentinel kind 集合扩 RequestHeader + comptime 数据驱动 spec 推送。下轮独立 issue:required / 默认值 / 重复 header List 接收 / @CookieValue 共享 header parse 基础能力。

---

## 触发场景

- D123 §247 §Phase 4 第四主流注解 @RequestHeader 端到端
- I021-requestbody 收关后 Phase 4 三支柱闭环 + 第四注解起立(JWT/Auth/CORS 业务覆盖)
- Phase 4+ @CookieValue / @RequestPart(multipart 表单字段)同模式扩展前置基础能力(共享 header parse + namespace prefix 隔离精神)
- Phase 5 Java oracle parity CI 端到端 diff 在 header-bound endpoint 不再 silent 4xx
- tests/phase5/spring_web_params.ss line 26 历史测试在新 dispatch 路径下 GREEN 兑现

---

## 备注

- **根因锚**:本 issue 修 D123 Phase 4 第四主流注解 @RequestHeader 单根因 — `__hdr_` namespace prefix 隔离 + comptime kind 分支 + sentinel kind 集合扩 RequestHeader(接口层 trap),非 dispatcher 字面 lookup 同 namespace 跨 query/header 撞 key(数据层 patch)或双 map ABI 大改(架构层 refactor 但工程量爆)
- **mirror 主源**:I021-pathvariable(`__pv_<name>` namespace prefix + sentinel kind 共享 cast 通道)+ I021-requestbody(sentinel kind 集合扩 RequestBody + per-class deserializer 自动生成);本 issue 共享 cast 通道 + namespace prefix 维度扩 `__hdr_<lower-name>`,sentinel kind 集合纳入 RequestHeader,不另开 sentinel 路径
- **D123 §253 alignment**:不扩 RouteMeta / ParamMeta / MethodMeta 数据形态,只扩 ParamSpec.kind 字面值集合(标量值不算 Meta 扩展)
- **D088 §第一性需求 alignment**:RequestHeader 形参绑定编译期展开消除运行时反射,sentinel emit 静态 `ss_mapGetString(req, "__hdr_<name>")` IR;codegen 路径完全编译期展开,无运行时 typeName 字符串分派
- **D129 §5 line 129 兼容性**:本 issue 与 D129 第二半 ModelAttribute Dropped Status 同轮决策(本轮 next_prompt option A+C 锁定);@RequestHeader 与 @ModelAttribute 域语义不同(header → 形参绑参 vs query string 多 key → class 多字段 binding),本 issue 不触 D129 域归属辨析正文
- **预估对照**:本 issue 大改 ~80-120 LOC 跨 5 文件;Execute 轮独立 commit 禁打包(MNK §改动分层 §大改 After Done);因 mirror I021-pathvariable / I021-requestbody 模板成熟,设计风险极低(zero design risk),Execute 轮可单轮端到端
- **本轮(立项轮)零代码改动**:仅 docs/4-issues/I021-requestheader.md 新建 + docs/3-decisions/D129-request-param-class-domain.md §5 line 129 加 Status: Dropped 标注 + §9 追加 deferred-reason 锚;Execute 留下轮按 feedback `feedback_execute_when_doc_locked` "决策归档后 next_prompt 直接 Execute 不 Plan" 原则单轮端到端
