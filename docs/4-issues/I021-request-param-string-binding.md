# I021 — @RequestParam string 绑参 (v0: 单参 + V=string 优先 mirror I019 + ParamMeta annotations + MethodMeta.params 填充 + comptime 静态 unpack adapter)

**父决策:** D123 §247-259 §Phase 4 §第一性需求 / D123 §253 "参数绑定用既有 ParamMeta 承,不新建 Meta"
**状态:** Done at `lib/spring/boot/application.ss:37-79` (RouteMeta.paramSpecs + comptime block 遍历 + dispatch ct unroll)+ `bootstrap/eval/interp_obj.ss` MethodMeta.params 填充段(ParamMeta InternPool key `PRM|${typeName}.${mName}.${pName}` 三段 + buildAnnotationMetaArray 复用)+ `bootstrap/parse/prelude.ss` ParamMeta.annotations 字段(对称 MethodMeta/FieldMeta/ClassMeta annotations 模式)+ commit 75f0516(@RequestParam string v0 反射 Meta 三层 + dispatcher paramSpecs-driven)+ commit 8844e5f(codegen module-level const literal comptime ref 喷顶层 load 双轨修)。**V 维度续作分流**(2026-04-25 §Root Cause 第一法则按根因解决度):V=int + V=double 同根因合并 → `docs/4-issues/I021bc-typed-request-param-cast.md`(Planned);V=class 跨域辨析 → `docs/3-decisions/D129-request-param-class-domain.md`(Drafted,**不在 @RequestParam 域**)
**颗粒度:** 预估 ~70-100 LOC 大改 (prelude.ss +1 ParamMeta 字段 / interp_obj.ss +15-20 MethodMeta.params 填充 / application.ss +30-40 RouteMeta.paramSpecs + comptime block 扩 + dispatcher invoke 静态展开 / HelloController.ss 净 +1 / Java HelloController.java 净 +1 / test 新建 ~40)。**解析层 0 LOC** —— 2026-04-25 立项实测 RED probe 证实 `parser.ss:702-755 parseParams` line 710-723 + 750 已支持单 param-level annotation(`@RequestParam(name = "n") n: string` 解析为 PARAM 节点 + nSetI4 ANNOTATION 节点),无需扩解析层(下方 §步骤 §解析层校正 anchor)
**依赖:** I019(Done, typed Map.get V=string 路由 ss_mapGetString) + I020a/I020b/I020c(Done, typed Map.get V=int/double/class lowering 全解锁,本 issue v0 仅用 V=string 但留下轮 I021-int/double/class 跨族扩展空间)+ I014(Done, invoke sentinel 静态派发 + funcParamCount pre-register)+ I018(Done, invoke sentinel runtime arg 透传 + httpServe query parse)+ D121 R1(Done, AnnotationMeta.args Map<string,string> 形态)+ D127 ASSIGN(Done, `@Ann(key = "val")` annotation arg 语法)+ D120 §决策 1(reflect.classes() Done)+ D117 §决策 1-2(五类 Meta 契约 Done)
**创建:** 2026-04-25
**立项由:** D123 Phase 3 Step 1 真兑现后,Phase 4 §第一性需求 (`curl :8080/hello?name=SS → "Hello, SS!"` byte-identical Java parity) hard prereq 触发。下游 typed Map.get V case 全 V (I019/I020a/b/c) 已 Done,Phase 4 prerequisite 就位;父 D123 §247-259 §改动条目明示 "lib/spring/boot/application.ss comptime 扩 method.params 遍历 + 生成参数解析 adapter / HelloController.ss 加参数注解 / 对等 Java 版"。

---

## 问题

D123 Phase 3 Step 1 收关后 HelloController.ss:17 仍是 `req: Map<string,string>` + `req.get("name")` 手工 unpack req map(I018/I019 兑现的 typed Map.get 让字面对齐 Java `req.get("name")` 但**形参签名**仍与 Java `@RequestParam String name` 偏差):

- ✅ **解析层已通**(2026-04-25 立项实测):`bootstrap/parse/parser.ss:702-755 parseParams` line 710-723 检测 ANNOTATION token + parseArgs (D127 ASSIGN 兼容)+ line 750 `nSetI4(pId, paramAnn)` 把单个 annotation 节点存到 PARAM.I4 slot,**无需扩解析层**。RED 探针实测:写 `function f(@RequestParam(name = "n") n: string)` 编译通过(parser/checker/codegen 全过)
- ❌ `bootstrap/parse/prelude.ss:35-38` `class ParamMeta { name: string; type: string }` **缺 annotations 字段**(对比 `MethodMeta { name; params; returnType; annotations }` / `FieldMeta` 同类已支持 annotations);param-level `@RequestParam` annotation 解析后**虽存到 PARAM.I4 但反射 ParamMeta 无承载位**
- ❌ `bootstrap/eval/interp_obj.ss:259-281` MethodMeta 构造仅填 `name` + `annotations`,**完全跳过 params**(`tvMap.set(${mmId}|params, ...)` 缺失);comptime 路径 `m.params` 反射读取**永远空**(RED 探针实测:`for (p in m.params) { println(p.name) }` for-in 不进入,stdout 空)
- ❌ `lib/spring/boot/application.ss:14-40` `RouteMeta` 仅记 `path / className / methodName` 三元组,**无 paramSpecs 容器**;dispatcher 89 行 `r.invoke(req)` 单参 透 req map 路径(I018 路径 A 收关形态)
- 用户被迫双轨制:用 SS 写 `function hello(req: Map<string,string>)` + `req.get("name")` vs Java 写 `function hello(@RequestParam String name)` 形参签名两套并存,违反 CLAUDE.md §编译器吸收复杂度

一句话:**param-level annotation 的反射通道断在反射 Meta 三层**(数据层 ParamMeta 缺字段 + 构造层 MethodMeta.params 不填充 + 应用层 RouteMeta 无 paramSpecs),解析层已通,Phase 4 @RequestParam 反射三层缺一不可。

---

## 第一性需求

SS 用户写 `function hello(@RequestParam(name = "name") name: string): string` 直接拿 string 入参,与 Java `public String hello(@RequestParam(name = "name") String name)` 字面对齐,不再被迫手工 unpack req map。Why 两层:

- **Why1**:不做 → Spring parity 用户每个 Controller method 都得手写 `req: Map<string,string>` 然后 `req.get("name")` 解 query,字面对齐 Java `@RequestParam String name` 永久断裂;参数语义信息(name / kind / type / required)只能在 Controller body 内部用注释或 magic string 表达,反射路径(comptime 静态生成路由表)对参数零知识 → 违反 CLAUDE.md §编译器吸收复杂度
- **Why2**:→ Phase 4+ @PathVariable(`/users/{id}`)/@RequestBody(JSON body 反序列化) / @RequestHeader 同模式扩展全线不可达(三者都依赖 param-level annotation 反射读取);Phase 5 Java oracle parity diff `<(curl ...)` 字面比对持续把"SS 手 unpack vs Java 形参签名"差异作为 byte 偏差误判;D088 §第一性需求"编译期展开消除运行时反射"在**参数绑定层**永久断裂(只能"调"+"绑整个 req map",不能"绑参数")

可观测否定证据(2026-04-25 立项实测 RED 凭据):
- `grep -c '@RequestParam' lib/spring/boot/application.ss = 0`(白名单收录但反射消费者 0)
- `grep -c '@RequestParam' examples/spring-parity/hello/ss/HelloController.ss = 0`
- `grep -c '|params' bootstrap/eval/interp_obj.ss = 0`(MethodMeta 构造未 set params 字段)
- `grep -c 'annotations: Array<AnnotationMeta>' bootstrap/parse/prelude.ss = 2`(MethodMeta + ClassMeta 各 1,**ParamMeta 0**)
- **comptime 反射 m.params probe 实测**:`/tmp/t_i021_probe.ss`(写 `for (p in m.params) { println("param=" + p.name + ...) }`)实测 stdout = 空(for-in 不进入,m.params 反射读永远空数组)→ 数据层 + 构造层 + 应用层三缺口闭环证据

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | 三层闭环:① ParamMeta 加 `annotations: Array<AnnotationMeta>` 字段;② interp_obj.ss MethodMeta 构造遍历 FUNC_DECL.params 填充 `params: Array<ParamMeta>`(每参从 nList 读 ANNOTATION_LIST + buildAnnotationMetaArray 复用);③ application.ss `_ssRoutes` RouteMeta 扩 `paramSpecs: Array<ParamSpec>`,comptime block 遍历 method.params + param.annotations 提取 (kind, name, type) 三元组;④ dispatcher 按 paramSpecs 静态展开 invoke 实参表(mirror I014/I018 sentinel:`r.invoke(req.get("name"))` 而不是 `r.invoke(req)`)。v0 仅 `@RequestParam(name=string) param: string` 单参 string 路径解锁。 | 最小三层对称扩展(数据 + 构造 + 应用),mirror I019 v0 string 优先策略;ParamMeta annotations 字段对称 MethodMeta/FieldMeta/ClassMeta 已就位的 annotations 模式;MethodMeta.params 填充对称已有 buildAnnotationMetaArray helper 复用;invoke sentinel 已支持运行时 ptr 透传(I018),paramSpecs comptime → invoke 实参表静态展开是 I014/I018 路径自然延伸 ✅ |
| **B** | 仅扩 dispatcher,application.ss 直接硬编 `r.invoke(req.get("name"))` 不走反射 | 字符串硬编 controller 形参名,等于 D088 §反模式 @comptimeEmit 字符串拼接;Phase 4+ @PathVariable / @RequestBody 不可扩 ✗ |
| **C** | 新增 D095 annotation handler `@RequestParam` 在编译期改写 Controller 函数体 | feedback_no_derive_workaround;@RequestParam 是用户级 Spring 注解非 SS 内建 handler 范畴,且违反"不在 SS app 源码里堆 workaround"原则 ✗ |
| **D** | 新增 RequestParamMeta 类专门承 param annotation | D123 §253 明示 "参数绑定用既有 ParamMeta 承,不新建 Meta";违反 reflection_health_linter Meta 类数量基线 ✗ |

---

## v0 scope 切分说明

**做**(本 issue):
- ParamMeta 加 `annotations: Array<AnnotationMeta>` 字段(数据层基础能力,所有 V 类型 + 所有 param annotation 共享受益)
- MethodMeta 构造填充 `params: Array<ParamMeta>`(构造层基础能力,同上共享)
- application.ss RouteMeta 扩 `paramSpecs: Array<ParamSpec>` + comptime 遍历 method.params + param.annotations(应用层基础能力,所有 param-level annotation 共享受益)
- dispatcher 按 paramSpecs 静态展开 invoke 实参表(mirror I014/I018 sentinel 路径)
- v0 limit:**仅** `@RequestParam(name = "<name>") <param>: string` **单参** string 类型识别 + 路由(其他 paramSpec 走 fallback "整 req map" backward compat)
- HelloController.ss 改 `hello(req: Map<string,string>)` → `hello(@RequestParam(name = "name") name: string)`
- Java oracle HelloController.java 同步改 `@RequestParam(name = "name") String name`(Java 端无变化,但 oracle 文件需对齐显式 name= 形态保持 byte-identical 形参签名描述能力)
- tests/phase5/i021_request_param_string.ss 新建覆盖:① 单参 @RequestParam string hit / ② miss(query 缺 key)→ 空串(走 ss_mapGetString miss 默认 `@.rt.str.empty`)/ ③ I018/I019 backward compat regression(Phase 3 Step 1 `req: Map<string,string>` 形态仍 work)/ ④ 静态 IR 锚:`grep "call ptr @HelloController_hello(ptr null, ptr %.*ss_mapGetString" main.ll` ≥ 1

**留下轮**(独立 issue / 决策档):
- **I021bc** — `@RequestParam` V=int + V=double 同根因合并(silent miscompile RED:V=int `Hello, -591256928!` / V=double `Hello, 2.67057e-315!`;双层根因 `bootstrap/eval/method_call.ss:107` invoke sentinel hardcode `, ptr ${aReg}` + `bootstrap/gen/gen_registry.ss:42-58 registerClassMethodRetType` 漏 set funcParamTypes;按 CLAUDE.md §Root Cause 第一法则同根因合并,**不**按 V 类型分 I021b/I021c)→ `docs/4-issues/I021bc-typed-request-param-cast.md`
- **I021d 域归属辨析** — `@RequestParam` V=class **跨域问题**,非 I020c mirror(query string `?user=...` → User class 实例无 deserializer 路径;@RequestParam 域契约 = url-encoded primitive/string,V=class 反序列化属 @RequestBody / @ModelAttribute 域)→ `docs/3-decisions/D129-request-param-class-domain.md` 独立讨论;未来 V=class 反序列化能力起独立 I021-modelattribute(query string 多 key → class 多字段 binding)/ I021-requestbody(JSON body → class)issue
- **I021-multi-param** — 多参 @RequestParam(`function f(@RequestParam(name="x") x: string, @RequestParam(name="y") y: string)`)
- **I021-pathvariable** — `@PathVariable` 路径占位符绑参(`/users/{id}` → 需 dispatcher 路径模式匹配 + 占位提取,工程量大)
- **I021-requestbody** — `@RequestBody` JSON 反序列化绑参(需 lib/json.ss + class 反射构造;V=class 反序列化路径 D129 §5 决策段)
- **I021-optional-defaults** — `@RequestParam(required = false, defaultValue = "x")` 可选参数 + 默认值

**不做**:
- 不删 Phase 3 Step 1 backward compat 路径(`function hello(req: Map<string,string>)` 形态保留;dispatcher 见到 RouteMeta.paramSpecs 为空 / 单 ParamMeta 无 @RequestParam annotation 时,fallback 透 req map 单参,行为对齐 I018)
- 不删 `methodRetTypes.set("get", "i64")` fallback(I019 兑现,继续保留)
- 不改 lib/http.ss query parse(I018 已按 `&` / `=` split,本 issue 无需改 lib/http.ss)
- 不改 checker side check_types.ss(checker 对 `@RequestParam(name = "n") n: string` 形参 type 检查走既有路径,annotation 仅在 comptime 反射端消费,不影响 checker 的形参类型 check)
- 不改 reflection_health_linter baseline(本 issue 不动反射 14 指标 Meta 类数,扩 ParamMeta 字段不增 Meta 类数;若实测 LOC 扩张触发 F1 baseline 漂移,按 D097 §扩容申报走 D123 §扩容申报-I021 anchor)

---

## 步骤

1. **RED 最小隔离测试**:`/tmp/t_i021_probe.ss` comptime 探针(写 `for (p in m.params) { println("param=" + p.name + " type=" + p.type + " anns=[" + p.annotationsStr + "]") }`)。改前实测 stdout = **空**(m.params 反射读永远空数组)→ 改后实测 stdout `param=n type=string anns=[RequestParam]` 三反射通道闭环
   - **解析层校正 anchor**:本 step 立项实测 `bin/ss build /tmp/t_i021_red.ss` 编译通过(parser.ss:702-755 单 annotation 已支持),原 step 设想"parser/checker 报错"修正为"反射 m.params probe 空"。解析层 0 LOC,工作量集中在反射 Meta 三层
2. **数据层**:`bootstrap/parse/prelude.ss:35-38` `ParamMeta` 加 `annotations: Array<AnnotationMeta>` 字段(对称 MethodMeta/FieldMeta/ClassMeta 已有的 annotations 字段)
3. **构造层**:`bootstrap/eval/interp_obj.ss:259-281` MethodMeta 构造扩 `tvMap.set(${mmId}|params, ${pArr})` 段:① interpNewArray 创 pArr / ② 遍历 nGetList(mId)("FUNC_DECL.params" CSV;parser.ss:751 `params = listAppend(params, pId)` 累积 PARAM 节点 ID)/ ③ 每参 interpNewVal("object", "ParamMeta") + 填 name(`nGetS1(pId)` 直读 PARAM.S1)+ type(`nGetS2(pId)` 直读 PARAM.S2)+ annotations(读 PARAM.I4 ANNOTATION 节点 ID 走 buildAnnotationMetaArray 复用 + ParamMeta InternPool key `PRM|${typeName}.${mName}.${pName}`)/ ④ interpArrayPush(pArr, ppId)
4. **应用层 - Meta 数据**:`lib/spring/boot/application.ss:14-18` 扩 `class RouteMeta { path; className; methodName; **paramSpecs: Array<ParamSpec>** }` + 新增 `class ParamSpec { kind: string; name: string; type: string }` (kind = "RequestParam" / "RequestBody" / "PathVariable" / fallback "RequestMap" 含义"传入整 req map")
5. **应用层 - comptime block**:`_ssRoutes` comptime block 遍历 `m.params` + 每参 `p.annotations` 扫描:若 annotation name == "RequestParam" 提取 args.getString("name") + p.type → ParamSpec(kind: "RequestParam", name: <ann.args.name>, type: <p.type>);若 ParamMeta 无 @RequestParam annotation 且 type == "Map<string, string>" → ParamSpec(kind: "RequestMap", name: <p.name>, type: <p.type>)兜底 backward compat;否则 v0 不识别 fallback 透 req map(留下轮 I021-pathvariable / I021-requestbody 扩 kind)
6. **应用层 - dispatcher**:`function dispatch(req: Map<string, string>): string` 改写,按 r.paramSpecs comptime 静态展开 invoke 实参表 → mirror I014/I018 invoke sentinel:`r.invoke(req.get(spec.name))` (V=string 单参,I020a/b/c 兑现的 typed cast 对其他 V 类型留下轮);若 r.paramSpecs[0].kind == "RequestMap" backward compat → `r.invoke(req)` 单 ptr 透传(I018 行为)
7. **app 层**:`examples/spring-parity/hello/ss/HelloController.ss:17` 改 `function hello(req: Map<string, string>): string { return "Hello, " + req.get("name") + "!" }` → `function hello(@RequestParam(name = "name") name: string): string { return "Hello, " + name + "!" }`
8. **Java oracle**:`examples/spring-parity/hello/java/src/main/java/hello/HelloController.java` 改 `public String hello() { return "Hello, World!"; }` → `public String hello(@RequestParam(name = "name") String name) { return "Hello, " + name + "!"; }` + import `org.springframework.web.bind.annotation.RequestParam`
9. **测试**:`tests/phase5/i021_request_param_string.ss` 新建,4 case(@RequestParam string hit / miss 默认空串 / I018 backward compat regression / 静态 IR 锚 grep)
10. **bootstrap 固定点**:`./build.sh bootstrap` Stage 2 = Stage 3
11. **gate**:`bin/ss run tools/reflection_health_linter.ss`(预估若触 F1 prelude.ss/interp_obj.ss/application.ss baseline 漂移,按 D097 §扩容申报走)+ `bin/ss run tools/d_doc_index_linter.ss`(D123 §扩容申报-I021 新段落 anchor 验证)
12. **parity**:`/tmp/hello_ss --serve` + `curl "http://localhost:8080/hello?name=SS"` = `Hello, SS!` ✅;Java gradle `cd examples/spring-parity/hello/java && ./gradlew bootRun` + `curl "http://localhost:8081/hello?name=SS"` = `Hello, SS!` byte-identical ✅(Phase 5 gradle 工具链未接前可仅验证 SS 单端 + Java 单端手动启动对比)

---

## 反向 / 备选

**备选 B(dispatcher 硬编)**:
- 优点:单文件改,工程量最小
- 缺点:违反 D088 §反模式 @comptimeEmit 字符串拼接;Phase 4+ @PathVariable / @RequestBody 不可扩;反射路径架构层永久断裂 ✗

**备选 C(D095 annotation handler @RequestParam)**:
- 优点:复用既有 handler 机制
- 缺点:违反 feedback_no_derive_workaround;@RequestParam 是 Spring 用户级注解非 SS 内建 handler 范畴 ✗

**备选 D(新增 RequestParamMeta)**:
- 优点:专一类语义清晰
- 缺点:违反 D123 §253 "用既有 ParamMeta 承不新建 Meta";Meta 类数增加触发 reflection_health_linter Meta count baseline ✗

**不做 → 后果**:
- Phase 4 §第一性需求 永远不可达,Spring parity gate 在 query param 维度永久 BLOCKED
- D088 §第一性需求 "编译期展开消除运行时反射" 在参数绑定层永久断裂(只能调 + 绑整 req map,不能绑参数)
- 用户每个 Controller method 手 unpack req map,Java parity 字面差异 long-term 累积技术债
- @PathVariable / @RequestBody 永久不可扩(三者都依赖 param-level annotation 反射通道 == 本 issue 设计的能力)

---

## 验收 RED 命令

```bash
# RED 最小隔离测试 - comptime 反射 m.params 探针 (本轮立项 2026-04-25 实测 stdout = 空,反射通道断证据)
echo 'class ParamProbe { pName: string; pType: string; pAnnNames: string }
@RestController
class TC {
    @GetMapping(path = "/x")
    function f(@RequestParam(name = "n") n: string): string { return "got:" + n }
}
const probes: Array<ParamProbe> = comptime {
    let arr: Array<ParamProbe> = []
    for (c in reflect.classes()) {
        if (c.name == "TC") {
            for (m in c.methods) {
                if (m.name == "f") {
                    for (p in m.params) {
                        let annNames = ""
                        for (a in p.annotations) {
                            if (annNames != "") { annNames = annNames + "," }
                            annNames = annNames + a.name
                        }
                        arr = arr.push(new ParamProbe(pName: p.name, pType: p.type, pAnnNames: annNames))
                    }
                }
            }
        }
    }
    return arr
}
function main() { for (p in probes) { println("param=" + p.pName + " type=" + p.pType + " anns=[" + p.pAnnNames + "]") } }' > /tmp/t_i021_probe.ss && bin/ss run /tmp/t_i021_probe.ss
# before (本轮立项实测): stdout 空 (m.params 反射空 → for-in 不进入 → 无 println);编译通过 (parser.ss:702 单 annotation 已支持)
# after 期望: stdout = "param=n type=string anns=[RequestParam]"

# 静态 IR 锚 (端到端验 dispatcher comptime unpack 已生效)
bin/ss build examples/spring-parity/hello/ss/main.ss -o /tmp/hello_i021 --emit-ir > /tmp/hello_i021.ll
grep -c "call ptr @HelloController_hello(ptr null, ptr %.*ss_mapGetString" /tmp/hello_i021.ll  # 期望 ≥ 1

# 单测
bin/ss run tests/phase5/i021_request_param_string.ss                        # 4 PASS
bin/ss run tests/phase5/d123_phase3_param_bind.ss                           # I018 backward compat regression
bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss                   # I019 V=string regression
bin/ss run tests/phase5/i020a_typed_map_get_int.ss                          # I020a regression
bin/ss run tests/phase5/i020b_typed_map_get_double.ss                       # I020b regression
bin/ss run tests/phase5/i020c_typed_map_get_class.ss                        # I020c regression

# 工程
./build.sh bootstrap                                                         # Stage 2 = Stage 3 固定点
bin/ss test tests/                                                           # ≥ 233 passed (I020c 收关基线 232 + 本 issue +1 test)

# parity 端到端
/tmp/hello_i021 --serve &                                                   # SS 端 8080
cd examples/spring-parity/hello/java && ./gradlew bootRun &                # Java 端 (Phase 5 gradle 工具链未接前可手动启)
curl -s "http://localhost:8080/hello?name=SS"                               # 期望: Hello, SS!
curl -s "http://localhost:8080/hello?name=Alice"                            # 期望: Hello, Alice!
curl -s "http://localhost:8080/hello"                                       # 期望: Hello, ! (miss 走 ss_mapGetString 默认空串)

# gate
bin/ss run tools/reflection_health_linter.ss                                # F1 GATE PASS (若触 baseline 漂移按 D097 扩容申报走 D123 §扩容申报-I021)
bin/ss run tools/d_doc_index_linter.ss                                      # OK
```

---

## 风险 / 表面 / 下轮升根路径

**本 issue v0 设计层根解决**(三层架构面闭环 - 数据 / 构造 / 应用):消除"用户写 `req: Map<string,string>` 手 unpack"双轨制,从 ParamMeta annotations + MethodMeta.params 填充 + comptime 静态 adapter 三层修。不变量锚:`bootstrap/parse/prelude.ss:35-38 ParamMeta + annotations` / `bootstrap/eval/interp_obj.ss:259-281 MethodMeta.params 填充段` / `lib/spring/boot/application.ss:14-40 RouteMeta.paramSpecs + comptime 遍历 method.params + param.annotations` / `lib/spring/boot/application.ss:83-91 dispatch 按 paramSpecs 静态 unpack invoke 实参`。

**v0 scope 限定**(非表面,是 scope 切分 mirror I019/I020a/b/c 模式):
- V=string 单参先解锁 80% 用例(Spring 多数 @RequestParam 是 string)
- V=int / V=double / V=class 留 I021b/c/d(对应 I020a/b/c 已兑现的 typed Map.get cast lowering 直接复用,工程量小)
- 多参 @RequestParam 留 I021-multi-param(funcParamCount 已支持 ≥ 1,但本 issue 仅端到端验证 1 参 mirror I018 §下轮升根路径)
- @PathVariable 留 I021-pathvariable(需 dispatcher 路径模式匹配 + 占位提取,工程量大)
- @RequestBody 留 I021-requestbody(需 lib/json.ss + class 反射构造)
- @RequestParam(required = false, defaultValue = "x") 留 I021-optional-defaults

**潜在工程风险**:

1. ~~**parseParams 对 FUNC_DECL.params 的 param-level annotation 支持完整度未知**~~ → **已澄清(2026-04-25 立项实测)**:`parser.ss:702-755 parseParams` line 710-723 + 750 单 annotation 已支持,RED probe 实测编译通过。**遗留小风险**:`if (paramAnn > 0) { nSetI4(pId, paramAnn) }` 仅存单个 annotation,多个 param annotation(如 `@RequestParam @Validated x: int`)第二个会被吞;v0 单 @RequestParam 不触发,留 I021-multi-annotation 后续(若 Execute 轮发现 user 写多 annotation,parser.ss:710 while 循环结构需扩为"按 ANNOTATION token 反复解析" + nSetI4 改为 ANNOTATION_LIST 节点列表;预估 ~10-15 LOC)

2. **interp_obj.ss MethodMeta.params 填充顺序与 InternPool dedup key 设计** — ParamMeta InternPool key 形如 `PRM|${typeName}.${mName}.${pName}`(对称 `MTH|${typeName}.${mName}` / `FLD|${typeName}.${fName}` / `CLS|${typeName}` / `ANN|${ownerKey}.${aName}` 五类已就位的 InternPool prefix);但 ParamMeta 同名 ≠ 同语义(method `f(x: int)` vs `g(x: int)` 的 `x` 不能 dedup),**key 必须含 method scope** `${typeName}.${mName}.${pName}` 三段。**风险**:若实测发现 InternPool dedup 误吞跨 method 同名 param,需扩 ParamMeta InternPool 一层。**下轮升根**:Execute 轮 §步骤 4 实测后,核对 InternPool dedup 行为,若误吞,扩 key 形态(本 issue §步骤 4 已预留 `PRM|${typeName}.${mName}.${pName}` 三段 key)

3. **dispatcher invoke 静态展开实参表与 funcParamCount pre-register 协同** — I014/I018 invoke sentinel 已支持按 funcParamCount 动态追加 ptr,本 issue paramSpecs comptime 静态展开 `req.get(spec.name)` 后传入 invoke 等于多了一层"实参表内容由 paramSpec 驱动"的 codegen 决策面;invoke sentinel 内部仅查 funcParamCount 决定 arity,实参表内容由 caller 提供 → 与本 issue paramSpecs comptime 展开自然兼容(应用层调用 `r.invoke(req.get("name"))` mirror I014/I018,sentinel 不需改)。**风险**:若实测发现 invoke sentinel 内部对实参表内容有形态约束(如必须是 ptr 类型且来自 runtime 单 reg)→ 本 issue 需扩 invoke sentinel 形态约束,工程量 +1 维度。**下轮升根**:Execute 轮 §步骤 7 实测,核对 invoke sentinel 实参表形态契约

4. **reflection_health_linter F1 baseline 漂移可能** — ParamMeta annotations 字段扩 + MethodMeta.params 填充段 + RouteMeta.paramSpecs + comptime block 扩 + dispatcher 重写,合计预估 ~80-120 LOC 三文件分散(prelude.ss / interp_obj.ss / application.ss);interp_obj.ss 在反射路径上,F1 行数可能漂。**下轮升根**:Execute 轮 §步骤 12 跑 reflection_health_linter,若 REGRESSION 走 D097 §B 路径扩容申报登 D123 §扩容申报-I021 anchor

**无表面接受**:本 issue 全程不接受任何表面绕过,凡发现需要表面补丁(如 dispatcher 硬编 / @RequestParam handler / 新 Meta 类)立即停手回 PSM 重新 RCA;遇到工程难点优先扩本 issue §步骤 而非降级 v0 scope。

---

## 触发场景

- D123 §247-259 §Phase 4 §第一性需求 hard prereq 触发
- I019 / I020a/b/c 全 Done 后 Phase 4 prerequisite 就位
- Spring parity `?name=X` query param 维度 byte-identical Java parity 真兑现
- Phase 4+ @PathVariable / @RequestBody / @RequestHeader 同模式扩展前置基础能力
- Phase 5 Java oracle parity CI 端到端 diff 不因"SS req unpack vs Java 形参签名"误判 byte-identical 失败

---

## 备注

- **根因锚**:本 issue 修 D123 Phase 4 §第一性需求 单根因"param-level annotation 反射通道全断"在 **三层架构面**:`prelude.ss:35-38 ParamMeta` 加 annotations 字段 + `interp_obj.ss:259-281 MethodMeta.params 填充` + `application.ss:14-40 RouteMeta.paramSpecs + comptime 遍历`。三层缺一不可,单层补丁(如仅扩 dispatcher)等于 D088 §反模式硬编。
- **mirror I019 v0 策略**:V=string 单参先解锁 80% 用例,其他 V 类型 / 多参 / 其他 param annotation 留下轮 I021b/c/d,与 I020a/b/c 已兑现的 typed Map.get cast lowering 自然衔接(I021b 对应 I020a / I021c 对应 I020b / I021d 对应 I020c,工程量小且模式对称)
- **D123 §253 "不新建 Meta"alignment**:扩 ParamMeta 字段 + 新增 ParamSpec(应用层 lib/spring/boot/application.ss 内的 spec 容器,**非 Meta 类**,不影响 reflection_health_linter Meta count baseline)严格合规
- **Phase 3 Step 1 backward compat 不删**:HelloController 用户可保留 `function hello(req: Map<string,string>)` 形态(走 fallback ParamSpec(kind: "RequestMap")),与 I018 invoke sentinel runtime arg 透传路径行为对齐
- **预估对照**:本 issue 大档 ~80-120 LOC,跨三文件(prelude.ss / interp_obj.ss / application.ss)+ 应用层 2 文件(HelloController.ss / HelloController.java)+ 1 test 文件,执行轮档位**大改**(LOC > 100 + 多文件)。Execute 轮独立 commit 禁打包(MNK §改动分层 §大改 After Done)
- **预估失准前置预警**(参考 I019 §教训 / I020a §教训):若 ParamMeta annotations 字段扩需要 InternPool dedup key 重新设计,或 MethodMeta.params 填充段触发跨 method 同名 param 误吞,工程量可能从 ~80-120 LOC 漂到 ~150-200 LOC。Execute 轮 PSM §字段 6 步骤应前置 "先核对 InternPool dedup 行为,若误吞先扩 key 形态再写填充段",避免反复 trial-and-error
