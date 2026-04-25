# I021-pathvariable — @PathVariable 路径占位符绑参(matchPath + __pv_ prefix 独立 namespace)

**父决策:** D123 §247-259 §Phase 4 §第一性需求 + §550 表 F 行 + §561 Phase 4 F + §742 Phase 4 收关 "PathVariable / RequestHeader 各自独立 issue 复用 funcParamTypes + invoke sentinel cast 通道"
**状态:** Planned (2026-04-25 立项,本轮 Plan + Execute 一气呵成由用户授权)
**颗粒度:** 预估 ~120-160 LOC 大改 跨 5 文件(`lib/spring/boot/application.ss` matchPath helper + comptime PathVariable 分支 + dispatcher 升级 +35-50 / `bootstrap/eval/method_call.ss` invoke sentinel kind 扩 +8-12 / `examples/spring-parity/hello/ss/HelloController.ss` +5 / `examples/spring-parity/hello/java/.../HelloController.java` Java oracle 同步 +7 / `tests/phase5/i021_pathvariable.ss` 新建 ~60)
**依赖:** I021(Done at `lib/spring/boot/application.ss:42-83` paramSpecs comptime block)+ I021bc(Done at 9ca4077 funcParamTypes typed cast)+ I021-multi-param(Done at 065d803 invoke sentinel useParamSpecs 数据驱动展开)+ I014(Done invoke sentinel 静态派发)+ I018(Done invoke runtime arg 透传)+ ss_mapGetString(Done at `bootstrap/gen/rt/gen_rt_map.ss:135`)+ ss_parseInt(Done at `bootstrap/gen/rt/gen_rt_string.ss:243`)
**创建:** 2026-04-25
**立项由:** I021-multi-param 收关后 Phase 4 §247 第一支柱缺口 — RED 实测 `function show(@PathVariable("id") id: int)` curl `/users/42` → 404 `not found`(silent miscompile,dispatcher 仅 `r.path == path` 字面相等比对 + comptime 无 PathVariable 分支)。次级凭据:IR 显示 `if.then.265: %6 = load req.132 → %7 = ss_parseInt(req) → %8 = TC_show(null, i32 %7)` —— sentinel useParamSpecs=0 fallback + funcParamTypes[TC_show:0]="int" 双轨命中,把 req map ptr 整体当 string parseInt 成 i32 silent type miscompile(实际 if 分支不进入故运行时不触发,但 IR 已是 type-misalignment 留藏雷)。

---

## 问题

I021-multi-param 收关后,Phase 4 三支柱中 @PathVariable 仍 100% 不可表达,根因是 **dispatcher 路径匹配 + comptime annotation 识别 + sentinel kind 分派** 三层缺口:

- ✅ 反射 Meta 三层(ParamMeta.annotations / MethodMeta.params 填充 / RouteMeta.paramSpecs)已通(I021)
- ✅ 单参 typed cast(int / double / string)已通(I021bc invoke sentinel `funcParamTypes` 分派 emit ss_parseInt + i32 / ss_parseDouble + double)
- ✅ 多 spec 数据驱动 invoke 展开已通(I021-multi-param `useParamSpecs` 分支)
- ❌ `lib/spring/boot/application.ss:127-140` dispatcher 仅做精确 `r.path == path` 字面相等匹配,占位符路径(`/users/{id}` 字面 vs 实际 `/users/42`)永久不匹配 → silent 404
- ❌ `lib/spring/boot/application.ss:42-83` _ssRoutes comptime block 无 `pAnn.name == "PathVariable"` 分支,@PathVariable 标注的形参不进 paramSpecs(走 fallback 静态路径)
- ❌ `bootstrap/eval/method_call.ss:135 §useParamSpecs` invoke sentinel 仅识别 "RequestParam" / "RequestMap",PathVariable kind 无 emit 路径

silent 404 行为画像(2026-04-25 RED 实测):
```bash
$ bin/ss run /tmp/t_i021_pv_red.ss
HTTP/1.1 404 Not Found
Content-Type: text/plain
Content-Length: 9
Connection: close

not found                                          # 期望 user=42

$ grep "if.then.265:" /tmp/t_i021_pv_red.ll -A 4
if.then.265:
  %6 = load ptr, ptr %req.132, align 8             # 加载 req map ptr
  %7 = call i32 @ss_parseInt(ptr %6)               # ⚠ 把 req map ptr 当 string parseInt
  %8 = call ptr @TC_show(ptr null, i32 %7)         # ⚠ 把整个 req "parseInt" 后的垃圾 i32 当 id 传
  %9 = call ptr @httpResponse(i32 200, ...)        # 实际不会执行因 if 不进入

$ grep -c "ss_mapGetString.*__pv_" /tmp/t_i021_pv_red.ll
0                                                  # __pv_ namespace 不存在
```

一句话:**dispatcher 字面相等单形** + **comptime 无 PathVariable 分支** + **sentinel 无 PathVariable kind** 三层缺口齐发,Phase 4 RESTful resource endpoint 永久不可表达。

---

## 第一性需求

SS 用户写 `function show(@PathVariable("id") id: int)` 路径占位 Controller,curl `/users/42` 行为字面对齐 Java `@PathVariable Integer id`:byte-identical body,无 silent 404,无 silent type miscompile。Why 两层:

- **Why1**:不做 → Spring 几乎所有 RESTful resource endpoint(`/users/{id}` / `/orders/{oid}/items/{iid}` / `/api/v1/{tenant}/users/{uid}`)永久不可表达;dispatcher 只能字面相等匹配静态路由,RESTful 模式失配
- **Why2**:→ Phase 4 §247 第一支柱 @PathVariable 永久断裂 + Phase 5 Java oracle parity diff 在所有 path-template 类型 endpoint BLOCKED + Phase 4+ @PathVariable 多占位符(`/users/{uid}/orders/{oid}`)/ PathVariable + RequestParam 混合形参(`/users/{uid}?include=details`)同模式扩展全线不可达

---

## 候选路径(选 C)

| 路径 | 描述 | 取舍 |
|---|---|---|
| A | dispatcher 占位符值写回 req map 同 spec.name key + sentinel kind == "PathVariable" 等价 RequestParam | 工程量~150 LOC;backward compat 全保;**namespace 同 req map 覆盖式 v0 表面 — 边界 `/x/{a}?a=v` 后写覆盖** ✗ |
| **C** | **dispatcher 占位符值写回 req map 独立 prefix `__pv_<name>`** + sentinel kind == "PathVariable" emit `ss_mapGetString(req, "__pv_<name>")` + RouteMeta 不扩字段(D123 §253 完全合规)| ~160 LOC;**namespace prefix 严格分离精神到位** + sentinel kind 区分代码 + 静态路由走 matchPath 逐段字面等价旧 `r.path == path` 不双轨 ✅ |
| B | 扩 invoke sentinel ABI 双 map(req + pathParams)+ dispatcher 双 map 输出 | namespace 严格分离;sentinel ABI 大改 ~250 LOC,backward compat 全 null 第二参 ✗ |
| D | 新增 RouteInvoker adapter 类中间层适配(类似 Java HandlerMethodAdapter)| 中间层增,SS-Java 不对称,反射路径多走一跳冗余 ✗ |

**选 C 因 namespace prefix 隔离精神到位 + RouteMeta 数据形态零变更(D123 §253 不新建 Meta 完全合规)+ 静态路由走 matchPath 逐段字面等价旧形态不引双轨**。

---

## v0 scope 切分说明

**做**(本 issue):
- `lib/spring/boot/application.ss`:
  - 加常量 `PARAM_KIND_PATH_VARIABLE = "PathVariable"`
  - **comptime _ssRoutes block** 加 `pAnn.name == "PathVariable"` 分支 push spec(kind="PathVariable", name=pAnn.args.getString("name"), type=p.type)
  - **加 runtime helper** `function matchPath(pattern: string, path: string, req: Map<string, string>): int`:逐 segment 比对,占位符段 `{name}` 写回 `req.set("__pv_" + name, value)`,字面段不等返 0
  - **dispatcher 改** `if (matchPath(r.path, path, req) == 1)` 替换 `if (r.path == path)`
- `bootstrap/eval/method_call.ss` invoke sentinel `useParamSpecs` 分支:
  - 把 `if (kindStr == "RequestParam")` 升 `if (kindStr == "RequestParam" || kindStr == "PathVariable")` 共享代码块
  - 加 `lookupKey = kindStr == "PathVariable" ? "__pv_" + nameStr : nameStr` 决定 ss_mapGetString 第二参
  - cast 通道(int/double/ptr 分派)完全复用,不另开 sentinel 路径
- `examples/spring-parity/hello/ss/HelloController.ss`:加 `@GetMapping("/users/{id}")` + `function show(@PathVariable("id") id: int)`
- `examples/spring-parity/hello/java/.../HelloController.java`:Java oracle 同步加 `@GetMapping("/users/{id}")` + `@PathVariable Integer id`
- `tests/phase5/i021_pathvariable.ss`:新建,5 case + IR 锚:
  - ① 单占位 int(主用例)
  - ② 多占位 int+int(双 PathVariable 独立 namespace)
  - ③ 静态路由 backward compat(无占位段走 matchPath 等价旧字面相等)
  - ④ string 占位(cast 默认 ptr 分派)
  - ⑤ 404 路径段数不匹配
  - ⑥ 静态 IR 锚 shell-level grep `ss_mapGetString.*__pv_id`

**留下轮**(独立 issue):
- **I021-pathvariable-regex** — `@PathVariable("id:\d+")` 正则约束(参数验证)
- **I021-requestbody** — `@RequestBody` JSON body → class 反序列化(D129 §3 跨域 deserializer 路径)
- **I021-modelattribute** — `@ModelAttribute` query string 多 key → class 多字段 binding(同 D129 §3 跨域)
- **I021-optional-defaults** — `@RequestParam(required=false, defaultValue="x")` 可选参数 + 默认值
- **I021-requestheader** — `@RequestHeader` HTTP header → 形参绑定(同 PathVariable 模式,namespace prefix `__hdr_<name>`)

**不做**:
- 不扩 invoke sentinel ABI(双 map 调用)— 单 map + namespace prefix 已合规
- 不动 ParamMeta / ParamSpec / RouteMeta 数据形态(D123 §253 完全合规)
- 不实现 `@PathVariable(required=false)` / 默认值 / 可选(留 I021-optional-defaults)
- 不实现路径占位符正则约束 `{id:\d+}`(留 I021-pathvariable-regex)
- 不依赖 `lib/jakarta/servlet.ss:87 getPathVariable`(应用层不走 servlet 抽象)
- 不动 reflection_health_linter baseline(改动可能触 F1 漂,Execute 跑后按 D097 §B 申报)

---

## 步骤

1. **RED 最小隔离测试**:`/tmp/t_i021_pv_red.ss` 写占位符 Controller `function show(@PathVariable("id") id: int)` + dispatch 模拟(本轮立项实测 stdout `HTTP/1.1 404 ... not found`,IR `if.then.265 ss_parseInt(req)` silent type miscompile 双凭据)
2. **application.ss matchPath helper 新增**:逐 segment 比对 + 占位符段写回 `__pv_<name>` namespace
3. **application.ss comptime PathVariable 分支扩**:_ssRoutes block 加 `pAnn.name == "PathVariable"` push spec
4. **application.ss dispatcher 升级**:`if (matchPath(r.path, path, req) == 1)` 替换字面相等
5. **method_call.ss invoke sentinel kind 扩**:`||  kindStr == "PathVariable"` 升 if 条件 + `lookupKey = kindStr == "PathVariable" ? "__pv_" + nameStr : nameStr`
6. **HelloController.ss 多 endpoint** + Java oracle 同步
7. **tests/phase5/i021_pathvariable.ss 5 case**
8. **bootstrap 固定点** `./build.sh bootstrap` Stage 2 = Stage 3
9. **gate** `bin/ss run tools/reflection_health_linter.ss` + `bin/ss run tools/d_doc_index_linter.ss`
10. **parity 端到端** `/tmp/hello_pv --serve` + `curl :8080/users/42` = `user=42` byte-identical Java
11. **simplify**(`/simplify` skill)+ commit

---

## 反向 / 备选

**备选 A(占位符值写回 req map 同 spec.name key)**:
- 优点:工程量略小(无 prefix 字符串拼接)
- 缺点:边界 `/x/{a}?a=v` PathVariable 后写覆盖 query namespace,违反 Spring 规范分离 ✗ 表面方案

**备选 B(invoke sentinel ABI 扩双 map)**:
- 优点:namespace 严格分离 + ABI 表达力强
- 缺点:sentinel ABI 大改 ~250 LOC,backward compat 全 null 第二参,工程量爆 Phase 4 预算 ✗

**备选 D(RouteInvoker adapter 中间层)**:
- 优点:SS 源码层显式适配
- 缺点:SS-Java 不对称(Java 不需要 adapter),反射路径多走一跳冗余 ✗

**不做 → 后果**:
- Phase 4 §247 第一支柱 @PathVariable 永久断裂
- Spring RESTful resource 模式永久不可表达
- D088 §第一性需求 编译期展开消除运行时反射 在 path-template 维度永久断裂
- Phase 5 Java oracle parity diff 在所有 path-template endpoint 永久 BLOCKED

---

## 验收 RED 命令

```bash
# RED 1: comptime PathVariable 分支不存在
grep -c '"PathVariable"' lib/spring/boot/application.ss
# before: 0  after: ≥ 2 (PARAM_KIND_PATH_VARIABLE const + comptime 分支)

# RED 2: dispatcher 无 pathPattern 字段或模式匹配
grep -cE "matchPath|__pv_" lib/spring/boot/application.ss
# before: 0  after: ≥ 4 (matchPath def + dispatcher call + 2 处 __pv_ 字面)

# RED 3: invoke sentinel 无 PathVariable kind 分支
grep -cE '"PathVariable"' bootstrap/eval/method_call.ss
# before: 0  after: ≥ 2 (kind 比对 + 注释)

# RED 4: 端到端 silent 404
cat > /tmp/t_i021_pv_red.ss <<'EOF'
import { dispatch } from "@/lib/spring/boot/application"
@RestController
class TC {
    @GetMapping(path = "/users/{id}")
    function show(@PathVariable(name = "id") id: int): string { return "user=" + id }
}
function main() {
    let req: Map<string, string> = new Map()
    req.set("path", "/users/42")
    println(dispatch(req))
}
EOF
bin/ss run /tmp/t_i021_pv_red.ss 2>&1 | grep -oE "user=[0-9]+|not found"
# before: not found
# after:  user=42

# RED 5: 静态 IR 锚 — sentinel emit __pv_ prefix lookup
bin/ss build /tmp/t_i021_pv_red.ss --emit-ir > /tmp/t_i021_pv_red.ll 2>&1
grep -c "ss_mapGetString.*__pv_id" /tmp/t_i021_pv_red.ll
# before: 0  after: ≥ 1

# 单测
bin/ss run tests/phase5/i021_pathvariable.ss

# 多 issue backward compat regression
bin/ss run tests/phase5/i021_request_param_string.ss      # I021 v0 hello string
bin/ss run tests/phase5/i021bc_typed_request_param_cast.ss   # I021bc int/double
bin/ss run tests/phase5/i021_multi_param.ss               # I021-multi-param 多参

# 工程
./build.sh bootstrap                                       # Stage 2 = Stage 3 固定点
bin/ss test tests/                                         # 全绿

# parity 端到端
/tmp/hello_pv --serve &
curl -s "http://localhost:8080/users/42"                   # 期望: user=42
curl -s "http://localhost:8080/users/100"                  # 期望: user=100
curl -s "http://localhost:8080/hello?name=SS"              # I021 v0 backward compat: Hello, SS!
curl -s "http://localhost:8080/add?x=10&y=20"              # I021-multi-param backward compat: sum=30

# gate
bin/ss run tools/reflection_health_linter.ss
bin/ss run tools/d_doc_index_linter.ss
```

---

## 风险 / 表面 / 下轮升根路径

**本 issue 设计层根解决**(matchPath + __pv_ prefix namespace 分离):消除 dispatcher 字面相等单形 + 占位符 namespace 与 query namespace 严格分离。不变量锚:`lib/spring/boot/application.ss matchPath + dispatcher` / `bootstrap/eval/method_call.ss:135 §useParamSpecs PathVariable kind 分支`。

**潜在工程风险**:

1. **string.split 行为边界**:`"/users/42".split("/")` = ["", "users", "42"](leading 空段);`"/".split("/")` = ["", ""](pattern length 不匹配 path length 时正确返 0)。**预实测**:本 issue 步骤 8 bootstrap 固定点过后跑 ./build.sh + tests 验证 split 行为
2. **substring (start, length) 语义**:`pseg.substring(1, pl - 2)` 提取 `{name}` 中 name —— pl - 2 = 大括号外字符数,from index 1 取 pl - 2 字符 = name 正确。已对照 `lib/path.ss` 现有用法 `p.substring(0, p.length() - 1)` 验证语义
3. **占位符段 `pl < 2`**:空段 `""`(leading slash 后 split 出来)+ 单字符段 `"a"`:`pl >= 2 && charAt(0) == "{" && charAt(pl-1) == "}"` 三条件保护,空段 / 单字符段直接走字面相等比对,不误判
4. **F1 baseline 漂**:application.ss + matchPath ~25 LOC + method_call.ss +13 LOC,可能触 F1 走 D097 §B 申报登 D123 §扩容申报-I021-pathvariable anchor

**v0 已 plumbing 完整**(无表面遗留):本 issue 全程根因解决,占位符 namespace prefix 隔离精神到位。下轮独立 issue:正则约束 / required / 默认值。

---

## 触发场景

- D123 §247 §Phase 4 第一支柱 @PathVariable 端到端
- I021-multi-param 收关后 Phase 4 §247 第一支柱缺口闭环
- Phase 4+ @PathVariable 多占位符 / @RequestHeader prefix-namespace 同模式扩展前置基础能力
- Phase 5 Java oracle parity CI 端到端 diff 在 path-template endpoint 不再 silent 404

---

## 备注

- **根因锚**:本 issue 修 D123 Phase 4 第一支柱 @PathVariable 单根因 — matchPath + __pv_ prefix namespace 分离(接口层 trap),非 dispatcher 字面比对单形扩特殊 case(数据层 patch)或 sentinel ABI 双 map(架构层 refactor 但工程量爆 Phase 4 预算)
- **mirror I021-multi-param 模式**:I021-multi-param 已建立 useParamSpecs 数据驱动 invoke 展开通道,本 issue 把 kind 分派从 RequestParam/RequestMap 二分扩展到 RequestParam/RequestMap/PathVariable 三分,sentinel cast 通道完全复用,不另开 sentinel 路径
- **D123 §253 "不新建 Meta" alignment**:不扩 ParamMeta / ParamSpec / RouteMeta 数据形态,只扩 ParamSpec.kind 字面值集合(标量值不算 Meta 扩展)
- **预估对照**:本 issue 大改 ~120-160 LOC 跨 5 文件;Execute 轮独立 commit 禁打包(MNK §改动分层 §大改 After Done)
