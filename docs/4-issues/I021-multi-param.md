# I021-multi-param — @RequestParam 多参绑参(invoke sentinel 自驱展开 + dispatcher 单次调用)

**父决策:** I021 §v0 scope §留下轮 / D123 §247-259 §Phase 4 §第一性需求
**状态:** Planned (2026-04-25 立项,本轮 Plan + Execute 一气呵成由用户授权)
**颗粒度:** 预估 ~80-110 LOC 大改 跨 4 文件(`bootstrap/eval/method_call.ss` invoke sentinel 数据驱动展开 +40-50 / `lib/spring/boot/application.ss` dispatch 单调用 +10-15 / `examples/spring-parity/hello/ss/HelloController.ss` 加 add 多参方法 +5 / `examples/spring-parity/hello/java/.../HelloController.java` Java oracle 同步 +5 / `tests/phase5/i021_multi_param.ss` 新建 ~30)
**依赖:** I021(Done at `lib/spring/boot/application.ss:37-79` paramSpecs comptime block)+ I021bc(Done at 9ca4077 funcParamTypes typed cast)+ I014(Done invoke sentinel 静态派发 + funcParamCount pre-register)+ I018(Done invoke runtime arg 透传)+ ss_mapGetString(Done at `bootstrap/gen/rt/gen_rt_map.ss:135`)+ ss_parseInt(Done at `bootstrap/gen/rt/gen_rt_string.ss:243`)+ ss_parseDouble(同上 :250)
**创建:** 2026-04-25
**立项由:** I021 v0 + I021bc 单参 typed cast 收关后 RED 实测 — `function add(@RP("x") x: int, @RP("y") y: int)` curl `?x=10&y=20` → body `sum=0`(silent miscompile),IR 显示 `call ptr @TC_add(ptr null, i32 %9)` 单 i32 参 vs def `(ptr, i32, i32)` 双 i32 参,y 全程不传。dispatch 内 `for (spec in r.paramSpecs)` 走第一个 spec 就 return,无法累积多 spec 成单次多参 invoke。

---

## 问题

I021 v0 + I021bc 收关后多 paramSpec 路径 silent miscompile,根因在 **dispatch ↔ invoke sentinel 实参表协议** 的双轨制:

- ✅ 反射 Meta 三层(ParamMeta.annotations / MethodMeta.params 填充 / RouteMeta.paramSpecs)已通(I021)
- ✅ 单参 typed cast(int / double / string)已通(I021bc invoke sentinel `funcParamTypes[mangled:idx]` 分派 emit ss_parseInt + i32 / ss_parseDouble + double)
- ❌ `lib/spring/boot/application.ss:122-141` dispatch 内 `for (spec in r.paramSpecs)` ct unroll 每个 spec 单独 emit `r.invoke(req.get(spec.name))` + return → **首个 spec 就吞 return,后续 spec 全部丢失**
- ❌ invoke sentinel(`bootstrap/eval/method_call.ss:100-132`)按 `mcArgList.split(",")` 取调用者写入的 N 个 mcArgId 决定实参数,**不能从 r.paramSpecs ct 元数据数据驱动展开**

silent miscompile 行为画像(2026-04-25 RED 实测):
```bash
$ /tmp/t_i021_multi_bin                           # 测试 bin 直接调 dispatch(req={x:"10",y:"20"})
HTTP/1.1 200 OK
Content-Type: text/plain
Content-Length: 5
sum=0                                              # 期望 sum=30,实际 sum=0(y 没传,x 也丢)

$ grep -c "call ptr @TC_add(ptr null, i32 %[0-9]*, i32 %[0-9]*)" /tmp/t_i021_multi_red.ll
0                                                  # 多参 call site 0 个

$ grep -c "call ptr @TC_add(ptr null, i32 %[0-9]*)$" /tmp/t_i021_multi_red.ll
4                                                  # 单参 call site 4 个(每个 spec 独立 invoke)

$ grep "define.*@TC_add" /tmp/t_i021_multi_red.ll
define ptr @TC_add(ptr %this.ptr, i32 %x.arg, i32 %y.arg)   # 函数 def 是双 i32(正确)
```

一句话:**dispatch ct unroll 多 spec 各发独立 invoke**(每个单参)+ **invoke sentinel 不读 r.paramSpecs ct 元数据**,两者协议双轨,Spring 多参 endpoint 永久 silent miscompile。

---

## 第一性需求

SS 用户写 `function add(@RP("x") x: int, @RP("y") y: int): string` 多参 Controller,curl `?x=10&y=20` 行为字面对齐 Java `(@RequestParam int x, @RequestParam int y)`:byte-identical body,无 silent miscompile。Why 两层:

- **Why1**:不做 → Spring 几乎所有非 hello-world endpoint(查询 `?from=&to=` / 登录 `?u=&p=` / 分页 `?page=&size=`)永久 silent miscompile;字面对齐 Java 多参 Controller 永久断裂;silent miscompile 比 hard error 更危险(用户不察觉直到行为异常)
- **Why2**:→ Phase 4 后续 @PathVariable 多占位符(`/users/{uid}/orders/{oid}`)/ @RequestBody + @RequestParam 混合形参(`(@RB User u, @RP("v") v: int)`)同模式扩展全线不可达;Phase 5 Java oracle parity diff 在多参 endpoint 永久 BLOCKED(byte 偏差 = 内部 ABI mismatch,oracle 无法判 SS 是 0% Spring parity)

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | **接口层 trap**:invoke sentinel 自驱展开 — `bootstrap/eval/method_call.ss` 扩 invoke sentinel,识别 ctObj 含 `paramSpecs` ct array 字段时,按 N 个 spec 自驱 emit `ss_mapGetString(req, name)` + `ss_parseInt/parseDouble` + 单次 `call @<class>_<method>(ptr null, <typed args>)`;dispatch SS 源码改为 `r.invoke(req)` 单调用(删 `for (spec in r.paramSpecs)` 嵌套).消除 dispatch spec loop 双轨 + sentinel 数据驱动 | mirror I014/I018/I021bc 路径(sentinel 元数据驱动);invoke sentinel 已经掌握 funcParamCount + funcParamTypes,加 paramSpecs 数据源是同一族扩展;invoke sentinel 是 ctVal-class 驱动的特殊形式,数据驱动展开是其设计自然延伸 ✅ |
| **B** | 数据层 patch:dispatch SS 源码硬展开多参 invoke `r.invoke(req.get("x"), req.get("y"))` — 但 SS 无 ct 实参表生成能力,N 不固定时无路径;且需用户在 dispatch 处硬编 controller 形参名 → 等于 D088 §反模式 @comptimeEmit 字符串拼接 ✗ |
| **C** | 架构层:invoke sentinel 改 LLVM vararg ABI(`i32 (...)`)— 但 musl libc + LLVM IR vararg 复杂度爆 Phase 4 预算,且 Spring callee 本就非 vararg(每个 method 形参数固定),vararg ABI 与 Spring 反射模式失配 ✗ |
| **D** | 新增 RouteInvoker 中间类 + ct compile 时生成 per-route adapter 函数 — 类似旧式 Java Spring HandlerMethodAdapter,但 ct 路径增添中间层 + Java oracle 不需要 adapter,SS 反射路径多走一跳冗余 ✗ |

---

## v0 scope 切分说明

**做**(本 issue):
- `bootstrap/eval/method_call.ss` invoke sentinel 内 `mcObjKind == "object" && mcMethod == "invoke"` 分支扩:检查 `interpGetField(ctObjId, "paramSpecs")` 返 ct array 非空 → 走**数据驱动模式**(自驱按 N 个 spec emit IR);返 null 或非 array → 走原 `mcArgList` 模式(I014/I018/I021/I021bc 路径全 backward compat)
- 数据驱动模式按 `spec.kind` 分派:
  - `"RequestParam"` → emit `ss_mapGetString(reqReg, @<spec.name>_strconst)` 取值 → 按 `spec.type` 分派 `parseInt+i32` / `parseDouble+double` / 默认 `ptr 透传`
  - `"RequestMap"` → 直接传 reqReg ptr(I018 backward compat)
- `lib/spring/boot/application.ss` dispatch 删 `for (spec in r.paramSpecs)` 嵌套 + 改为 `r.invoke(req)` 单次调用;删 `PARAM_KIND_REQUEST_MAP` 在 dispatch 处的硬分派(由 sentinel 内部数据驱动)
- `examples/spring-parity/hello/ss/HelloController.ss` 加多参 method `add(@RP("x") x: int, @RP("y") y: int)`(端到端 multi-spec 验证)
- Java oracle `HelloController.java` 同步加 `add(@RP int x, @RP int y)`
- `tests/phase5/i021_multi_param.ss` 新建,4 case:
  - ① 双参 int+int hit
  - ② 三参混合 string+int+double(若 ParamSpec 数据驱动展开多 type 都通 OK)
  - ③ I021/I021bc 单参 backward compat regression(hello/age/calc 仍 work)
  - ④ 静态 IR 锚:`grep "call ptr @HelloController_add(ptr null, i32 %.*, i32 %.*)" main.ll` ≥ 1

**留下轮**(独立 issue):
- **I021-pathvariable** — `@PathVariable` 路径占位符绑参(`/users/{id}` → 需 dispatcher 路径模式匹配 + 占位提取,工程量大)
- **I021-requestbody** — `@RequestBody` JSON body → class 反序列化(D129 §3 跨域 deserializer 路径)
- **I021-modelattribute** — `@ModelAttribute` query string 多 key → class 多字段 binding(同 D129 §3 跨域)
- **I021-optional-defaults** — `@RequestParam(required=false, defaultValue="x")` 可选参数 + 默认值
- **I021-multi-annotation** — 同形参多 annotation(`@RP @Validated x: int`),parser.ss:710 nSetI4 单 slot 限制升根

**不做**:
- 不删 backward compat 单参 dispatch path(I021 / I021bc 路径全保;sentinel 检测 paramSpecs 数据驱动模式失败 → 走原 mcArgList 模式)
- 不动 `bootstrap/parse/prelude.ss` ParamMeta(I021 v0 已扩 annotations 字段够用)
- 不动 `bootstrap/eval/interp_obj.ss` MethodMeta.params(I021 v0 已填充)
- 不改 `lib/http.ss` query parse(I018 已支持多 key)
- 不动 reflection_health_linter baseline(预估 method_call.ss 扩 ~40-50 LOC 在反射路径,可能触 F1 漂,Execute 跑后按 D097 §B 申报)
- 不实现 @RP(`required=false`)/默认值 / 可选(留独立 I021-optional-defaults)

---

## 步骤

1. **RED 最小隔离测试**:`/tmp/t_i021_multi_red.ss` 写多参 Controller `function add(@RP("x") x: int, @RP("y") y: int)` + dispatch 模拟(本轮立项实测 stdout `sum=0` ← y 漏传,silent miscompile 凭据)
2. **method_call.ss invoke sentinel 数据驱动展开**(`bootstrap/eval/method_call.ss:86-146` 扩):
   - 在 `mcObjKind == "object" && mcMethod == "invoke"` 分支内,先 `interpGetField(ctObjId, "paramSpecs")` 取 ct val
   - 若 `interpType(psSv) == "array"` 且 `interpArrayLen(psArrId) > 0`(数据驱动模式):
     - 取 mcArgList 第一个 mcArgId 的 callPreRegs reg = reqReg(dispatch 写 `r.invoke(req)` 时 req 的 LLVM reg)
     - 遍历 paramSpecs N 个 spec → 按 `spec.kind` 字面分派:
       - `"RequestParam"` → emit `${valReg} = call ptr @ss_mapGetString(ptr ${reqReg}, ptr ${nameStrConst})` + 按 `spec.type` 字面分派 cast 同 I021bc 模式
       - `"RequestMap"` → 直接 `, ptr ${reqReg}` 透传
     - 累积 invokeExtraArgs(同 I021bc 路径,只是 cast 来源从 callPreRegs 换成 sentinel 自 emit)
   - 若 `paramSpecs` 不是 array 或长度 0 → 走原 mcArgList 模式(line 102-132 不动)
3. **application.ss dispatch 重写**:
   - 删 `for (spec in r.paramSpecs)` 嵌套 + `if (spec.kind == ...)` 分派
   - 改为单次 `return httpResponse(200, "text/plain", r.invoke(req))`
   - 删 `PARAM_KIND_REQUEST_PARAM` / `PARAM_KIND_REQUEST_MAP` 在 dispatch 处的引用(常量保留,_ssRoutes comptime block 仍用 push 时的 kind 标记)
4. **HelloController.ss 多参 method**:
   - 加 `function add(@RequestParam(name = "x") x: int, @RequestParam(name = "y") y: int): string { return "sum=" + (x + y) }`
   - 加 `@GetMapping(path = "/add")`
5. **Java oracle 同步**:
   - `HelloController.java` 加 `public String add(@RequestParam(name="x") int x, @RequestParam(name="y") int y) { return "sum=" + (x + y); }`
6. **测试**:`tests/phase5/i021_multi_param.ss` 新建,4 case 覆盖
7. **bootstrap 固定点**:`./build.sh bootstrap` Stage 2 = Stage 3
8. **gate**:`bin/ss run tools/reflection_health_linter.ss`(若触 F1 baseline 漂走 D097 §B 申报)+ `bin/ss run tools/d_doc_index_linter.ss`
9. **parity**:`/tmp/hello_multi --serve` + `curl :8080/add?x=10&y=20` = `sum=30` ✅;Java 端同步对照 byte-identical
10. **simplify**(`/simplify` skill)+ commit

---

## 反向 / 备选

**备选 B(dispatch SS 源码硬展开多参 invoke)**:
- 优点:不动 method_call.ss
- 缺点:SS 无 ct 实参表生成能力,N 不固定;dispatch SS 源码硬编 controller 形参名 = D088 反模式 ✗

**备选 C(invoke sentinel 改 LLVM vararg)**:
- 优点:LLVM 自身原生支持
- 缺点:musl libc + vararg ABI 复杂度爆 Phase 4 预算;Spring callee 本就非 vararg ✗

**备选 D(新增 RouteInvoker adapter 类)**:
- 优点:SS 源码层显式适配
- 缺点:中间层增 SS-Java 不对称;ct 路径多走一跳冗余 ✗

**不做 → 后果**:
- Phase 4 §第一性需求 在多参维度永久 silent miscompile
- D088 §第一性需求 编译期展开消除运行时反射 在多参绑定层永久断裂(只能调单参,多参 silent error)
- Phase 5 Java oracle parity diff 永久 BLOCKED(byte 偏差掩盖 ABI mismatch)
- 用户每个多参 Controller 都需手动绕过(回退到 `req: Map<string,string>` 形态),Java parity 字面差异 long-term 累积技术债

---

## 验收 RED 命令

```bash
# RED 最小隔离测试 - 多参 silent miscompile 凭据
cat > /tmp/t_i021_multi_red.ss <<'EOF'
import { dispatch } from "@/lib/spring/boot/application"

@RestController
class TC {
    @GetMapping(path = "/add")
    function add(@RequestParam(name = "x") x: int, @RequestParam(name = "y") y: int): string {
        return "sum=" + (x + y)
    }
}

function main() {
    let req: Map<string, string> = new Map()
    req.set("path", "/add")
    req.set("x", "10")
    req.set("y", "20")
    println(dispatch(req))
}
EOF
bin/ss build /tmp/t_i021_multi_red.ss -o /tmp/t_i021_multi_bin --emit-ir
/tmp/t_i021_multi_bin | grep -oE "sum=[0-9-]+"
# before: sum=0 (silent miscompile, y 漏传)
# after:  sum=30

grep -c "call ptr @TC_add(ptr null, i32 %[0-9]*, i32 %[0-9]*)" /tmp/t_i021_multi_red.ll
# before: 0
# after:  ≥ 1

# 单测
bin/ss run tests/phase5/i021_multi_param.ss

# 单参 backward compat regression (I021 / I021bc 路径)
bin/ss run tests/phase5/i021_request_param_string.ss     # I021 v0 hello string
bin/ss run tests/phase5/i021bc_typed_request_param_cast.ss   # I021bc int/double

# 工程
./build.sh bootstrap                                      # Stage 2 = Stage 3 固定点
bin/ss test tests/                                        # 全绿

# parity 端到端
/tmp/hello_multi --serve &
curl -s "http://localhost:8080/add?x=10&y=20"            # 期望: sum=30
curl -s "http://localhost:8080/add?x=100&y=200"          # 期望: sum=300
curl -s "http://localhost:8080/hello?name=SS"            # I021 v0 backward compat: Hello, SS!

# gate
bin/ss run tools/reflection_health_linter.ss
bin/ss run tools/d_doc_index_linter.ss
```

---

## 风险 / 表面 / 下轮升根路径

**本 issue 设计层根解决**(invoke sentinel 数据驱动展开):消除 dispatch ↔ invoke sentinel 双轨制 — sentinel 改为按 ctObj.paramSpecs 元数据自驱展开多参 invoke,dispatch 单次 `r.invoke(req)` 调用,不再 spec loop 各发独立 invoke。不变量锚:`bootstrap/eval/method_call.ss:86-146 invoke sentinel + paramSpecs 数据驱动分支` / `lib/spring/boot/application.ss:122-141 dispatch 单调用形态`。

**潜在工程风险**:

1. **字符串常量去重**:多 spec 的 name 可能与已有 `@.str.N` 重复(如 `"x"` 在多个 endpoint 都用)— `addStringConst` 是否做去重?若不去重 → IR 体积小幅膨胀,F1 baseline 漂;若去重 → 看 helper 实测行为. **下轮升根**:Execute 实测 IR 字符串常量是否重复,若有需扩 helper 去重(独立优化 issue)
2. **paramSpecs ct array 内 ParamSpec 字段访问失败**:`interpGetField(specObjId, "kind")` 若返 null tv → kind 字面比对失败 → 跳过该 spec → silent miscompile.防御:数据驱动模式入口必须验证每个 spec 是 object kind + 含 kind/name/type 三字段,否则降级走原 mcArgList 模式 + comptime warning
3. **invoke sentinel reentrancy**:数据驱动模式内 emit ss_mapGetString 可能触发其他 ct 状态(callPreRegs / regCount / strCount).防御:数据驱动模式内只用 nextReg + addStringConst,不重入 genVal/evalMethodCall
4. **F1 baseline 漂**:method_call.ss 扩 ~40-50 LOC,若触 F1 走 D097 §B 申报登 D123 §扩容申报-I021-multi-param anchor

**无表面接受**:本 issue 全程不接受任何表面绕过,凡发现需要表面补丁(如 dispatch 硬编 / 字符串拼接 / 新 sentinel 名)立即停手回 PSM 重新 RCA。

---

## 触发场景

- D123 §247-259 §Phase 4 多参 Controller 端到端 byte-identical Java parity
- I021 / I021bc 单参 收关后 Phase 4 完整化最后单根因
- Phase 4+ @PathVariable 多占位符 / @RequestBody 混合形参 同模式扩展前置基础能力
- Phase 5 Java oracle parity CI 端到端 diff 在多参 endpoint 不再 silent miscompile

---

## 备注

- **根因锚**:本 issue 修 D123 Phase 4 多参 silent miscompile 单根因 — invoke sentinel 数据驱动展开(接口层 trap),非 dispatch 端硬展开(数据层 patch)
- **mirror I021bc 模式**:I021bc 已建立 funcParamTypes 分派 cast 的接口层路径,本 issue 把分派来源从 callPreRegs(调用者写入)扩展到 paramSpecs(ctObj 元数据),是同一族扩展
- **D123 §253 "不新建 Meta" alignment**:不扩 ParamMeta / ParamSpec 数据形态,只扩 sentinel 行为
- **预估对照**:本 issue 大改 ~80-110 LOC 跨 4 文件;Execute 轮独立 commit 禁打包(MNK §改动分层 §大改 After Done)
