# I021bc — Typed @RequestParam V=int + V=double cast lowering(invoke sentinel + funcParamTypes 单根因双修复点)

**父决策:** I021 §v0 scope 切分说明 §留下轮 / D123 §247-259 §Phase 4 §第一性需求
**状态:** Done at `bootstrap/gen/gen_registry.ss:42-62` + `bootstrap/eval/method_call.ss:94-130` + `tests/phase5/i021bc_typed_request_param_cast.ss` + `examples/spring-parity/hello/ss/HelloController.ss` + `examples/spring-parity/hello/java/src/main/java/hello/HelloController.java`(2026-04-25 — Approved → Done in same Execute 轮,前置 I022 阻塞同轮解 + 单根因双修复点闭环 + 端到端 curl /age?n=42=`n=42` /calc?x=3.14=`x=3.14` byte-identical Java parity)
**颗粒度:** 预估 ~20-35 LOC bootstrap(`gen_registry.ss` +5-7 funcParamTypes set 对称 codegen.ss 普通函数路径 / `method_call.ss` +15-25 invoke sentinel 按 funcParamTypes 分派 cast emit)+ ~50 LOC test。**ss_parseInt + ss_parseDouble runtime helper 已就位**(`bootstrap/gen/rt/gen_rt_string.ss:243` + `:250`),无需补 lib 层,工程量降至最小单根因双修复点闭环
**依赖:** I021(Done at `lib/spring/boot/application.ss:37-79` + `bootstrap/eval/interp_obj.ss MethodMeta.params` + `bootstrap/parse/prelude.ss ParamMeta.annotations` + commit 75f0516 + 8844e5f) + I014(Done, invoke sentinel 静态派发 + funcParamCount pre-register) + I018(Done, invoke runtime arg 透传 + httpServe query parse)+ I020a(Done, typed Map<K,int>.get trunc lowering 模式参考)+ I020b(Done, typed Map<K,double>.get bitcast lowering 模式参考)+ ss_parseInt(Done at `bootstrap/gen/rt/gen_rt_string.ss:243`)+ ss_parseDouble(Done at `bootstrap/gen/rt/gen_rt_string.ss:250`)
**创建:** 2026-04-25
**立项由:** I021 v0 收关后,V 维度两破裂表现 silent miscompile(V=int `Hello, -591256928!` / V=double `Hello, 2.67057e-315!`)触发 CLAUDE.md §Root Cause 优先(commit 3744f4a + d0a109f)第一法则。**唯一根因**:`@RequestParam` 类方法的参数 SS 类型信息没有从声明端流通到 dispatcher invoke 的 codegen 端 → 无法按目标 LLVM 类型 emit cast。**两个修复 touch points 而非两个根因**:`bootstrap/gen/gen_registry.ss:42-58 registerClassMethodRetType` 漏 set funcParamTypes(注册端断流)+ `bootstrap/eval/method_call.ss:107` invoke sentinel hardcode `, ptr ${aReg}` 不查 callee 形参类型(消费端不取流)→ 反事实验证:只修一边都闭不了环(只修注册端 → sentinel 不取 → 仍 ptr;只修消费端 → 注册无 → 取空降级 ptr)。按根因解决度分流应**合并** V=int + V=double 为单 issue,而非按 V 类型分 I021b/I021c(后者会导致同根因被两次穿越,违反 §Root Cause 第一法则 (b) 大重构 vs 小补丁)

---

## 问题

I021 v0 仅完成 V=string 路径的 invoke 实参透传(`req.get(spec.name)` 返 ptr,直接 `r.invoke()`,callee 形参 SS 类型 string,LLVM 签名 ptr → ptr 自然 OK,**仅这一种 V** 偶然 work)。V=int / V=double 场景**单一根因 = 类方法参数 SS 类型信息没有从声明端流通到 dispatcher invoke 的 codegen 端**;此根因表现在两个 touch points 同时缺位:

- ❌ **修复点 1(注册端 — 信息断流)**:`bootstrap/gen/gen_registry.ss:42-58 registerClassMethodRetType` 仅 set `funcRetTypes` + `funcParamCount`,**漏 set `funcParamTypes`**;对比 `bootstrap/gen/codegen.ss:107-111` 普通函数路径 `funcParamTypes.set(${fname}:${pCount}, nGetS2(fpId))` 已就位 → class method 路径 `funcParamTypes.has("HelloController_hello:0") == 0` 实测,callee 形参 SS 类型对 invoke sentinel **不可见**(信息源没存)
- ❌ **修复点 2(消费端 — 信息不取)**:`bootstrap/eval/method_call.ss:107` invoke sentinel runtime args 循环 `invokeExtraArgs = ${invokeExtraArgs}, ptr ${aReg}` —— **所有实参强制 LLVM `ptr` 类型**,不查 callee 形参类型分派 cast。即使修复点 1 补 funcParamTypes,sentinel 依然按 ptr 透传(LLVM IR 显式 `ptr`)(信息存了不取)
- **反事实证根因唯一**:只修注册端 → sentinel 不查询 funcParamTypes,实参仍 ptr,V=int/double silent miscompile 不变;只修消费端 → funcParamTypes class method 路径空,sentinel 查询命中 0 次,默认 fallback 仍 ptr。两点缺一不可,因为它们是**同一根因的两个端点**(注册端 + 消费端 = 信息流的源 + 汇),不是两个独立根因。修这一根因 = 把信息流接通,必经两端

可观测否定证据(silent miscompile RED — **无 LLVM 编译错**,运行时垃圾值):

- **V=int 表现**:`HelloController.ss` 写 `function hello(@RequestParam(name="age") age: int): string { return "Hello, " + age + "!" }` + `curl :8080/hello?age=42` → 实测 stdout = `Hello, -591256928!`(query string `"42"` ptr 被 LLVM 当 i32 截断 + ss_int_to_string 把 ptr 低 32 位印出)
- **V=double 表现**:`HelloController.ss` 写 `function hello(@RequestParam(name="x") x: double): string { return "Hello, " + x + "!" }` + `curl :8080/hello?x=3.14` → 实测 stdout = `Hello, 2.67057e-315!`(query string `"3.14"` ptr 被 LLVM 当 double 位重解释 + ss_double_to_string)
- **静态 IR 锚**:`grep -E 'call (i32|double) @HelloController_hello' main.ll` = 0(invoke 仍 `call ptr @HelloController_hello(ptr null, ptr %...ss_mapGetString)`,实参类型签名仍 ptr,callee 函数签名期望 i32/double mismatch 但 LLVM 不拒,silent miscompile)
- **funcParamTypes 注册漏证据**:实测 `funcParamTypes.has("HelloController_hello:0") == 0`(class method 路径)+ `funcParamTypes.has("HelloController_hello_s:0") == 0`(mangled overload 路径)— 根因注册端 dom

一句话:**invoke sentinel 类型分派契约缺位 — 数据层 funcParamTypes class method 漏注册 + 分派层 hardcode ptr,V=int/double silent miscompile**。V=string 偶然 work 因 ptr→ptr 类型自然对齐,掩盖契约缺位。

---

## 第一性需求

invoke sentinel 按 callee 形参 LLVM 类型分派 emit cast,@RequestParam V 维度 int / double 与 string parity:

1. `funcParamTypes` class method 路径补全注册(对称 `codegen.ss:107-111` 普通函数已就位的 `funcParamTypes.set(${fname}:${pCount}, nGetS2(fpId))` 模式,key 形态 `${baseName}:${pCount}` + `${baseName}_${mSig}:${pCount}` 双轨)
2. invoke sentinel 按 `funcParamTypes[mangled:idx]` 查 SS 类型,分派 emit cast:
   - SS string → `, ptr ${aReg}` (现状,V=string 路径不变)
   - SS int → emit `%pi_${idx} = call i32 @ss_parseInt(ptr ${aReg})` 然后 `, i32 %pi_${idx}`(string 反序列化为 i32)
   - SS double → emit `%pd_${idx} = call double @ss_parseDouble(ptr ${aReg})` 然后 `, double %pd_${idx}`(string 反序列化为 double)
3. `ss_parseInt` + `ss_parseDouble` runtime helper 已就位(`bootstrap/gen/rt/gen_rt_string.ss:243` + `:250`),无需补 lib 层

Why 两端必修:

- **Why1**:不做 → @RequestParam V 维度只支持 V=string,V=int(`/hello?age=42`) / V=double(`/calc?x=3.14`)用户被迫手写 `parseInt(req.get("age"))` 在 controller body 内 — 等于 I019 v0 之前"双轨制 method 名"再次回潮(用户记忆 `get` vs `getString` 的 method-name 双轨制 vs 用户记忆 `parseInt(req.get(...))` 的 manual-cast 双轨制),违反 CLAUDE.md §编译器吸收复杂度;父 issue I021 §第一性需求"`function hello(@RequestParam ... age: int)` 直接拿 int 入参"在 V 维度永久断裂
- **Why2**:→ Phase 4+ @PathVariable(`/users/{id}` 中 `id: int`) / @RequestHeader(`X-Count` 中 `count: int`)等 param-level annotation V=int/double 路径全线不可达;invoke sentinel 类型分派契约缺位 = 整个 reflective dispatch 系统 V 维度永久 string-only,Spring parity enterprise 尺度兑现仅 50%;Java oracle parity diff `<(curl ...)` 字面比对持续在 int/double 维度看到 SS silent miscompile vs Java 正常,byte-identical gate 在 typed param 维度永久 RED

可观测否定证据(2026-04-25 立项预测 RED 凭据,Execute 轮第一步 RED 实测对齐):

- V=int silent miscompile:`/tmp/t_i021bc_int.ss` HelloController + `curl :8080/hello?age=42` → stdout `Hello, -591256928!`(预期 `Hello, 42!`)
- V=double silent miscompile:`/tmp/t_i021bc_double.ss` HelloController + `curl :8080/calc?x=3.14` → stdout `Hello, 2.67057e-315!`(预期 `Hello, 3.14!`)
- 静态 IR 锚 RED:`grep -cE 'call (i32|double) @HelloController_hello' /tmp/t_i021bc_*.ll` = 0(invoke 实参仍 ptr,callee 期望 i32/double silent type mismatch);改后期望 ≥ 1 各 case
- funcParamTypes 漏注册实测:`/tmp/t_funcParamTypes_probe.ss` comptime probe(写 `println(funcParamTypes.has("HelloController_hello:0"))`)实测 stdout `0`(class method 路径漏);改后期望 stdout `1`

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | 单根因双修复点闭环:① `bootstrap/gen/gen_registry.ss:42-58 registerClassMethodRetType` 内 PARAM for-in 循环新增 `funcParamTypes.set(${baseName}:${pCount}, nGetS2(pId))` + `funcParamTypes.set(${baseName}_${mSig}:${pCount}, nGetS2(pId))` 双轨注册(对称 `codegen.ss:107-111` 普通函数已就位);② `bootstrap/eval/method_call.ss:97-115` invoke sentinel for-in mcArgParts2 循环改:按 `funcParamTypes.has(${mangled}:${consumed})` 查,SS=int → emit `%pi_${consumed} = call i32 @ss_parseInt(ptr ${aReg})` + 拼 `, i32 %pi_${consumed}` / SS=double → emit `%pd_${consumed} = call double @ss_parseDouble(ptr ${aReg})` + 拼 `, double %pd_${consumed}` / SS=string / 默认 → 现状 `, ptr ${aReg}` | 最小单根因双修复点闭环(注册端 + 消费端 = 信息流两端),mirror I020a/I020b 兑现的 V-type-driven cast lowering 模式;funcParamTypes Map 已就位(`gen_registry.ss:10`)+ codegen.ss:109 普通函数路径已注册,本 issue 仅补 class method 路径对称;每加一种 V 类型不再扩 sentinel(funcParamTypes 已通,sentinel 单层 dispatch 表添新分支即可)✅ |
| **B** | 仅给 V=int / V=double 在 method_call.ss invoke sentinel 内硬编 mangled 字符串特例分支(`if mangled == "HelloController_hello"`...) | 字符串硬编 controller 形参类型 = D088 §反模式 + 每加一种 controller 都得改 sentinel,违反根因(funcParamTypes 数据层修才是根) ✗ |
| **C** | 在 application.ss dispatcher 侧 ct emit cast,改 `r.invoke(parseInt(req.get(spec.name)))` 应用层处理 | 应用层堆 cast = 把"反序列化"责任推给 SS app 用户而非编译器吸收;违反 CLAUDE.md §编译器吸收复杂度;Phase 4+ 每个 ParamSpec 都要 ct emit cast 链,SpringApplication.run 反复 ct 反射穿插 cast 节点,反射路径架构层污染 ✗ |
| **D** | 新增 ss_invoke_with_typed_args runtime 反射分派(运行时按 mangled 查 paramTypes table 自动 cast) | D088 §反模式 — 编译期可知的类型信息不该走运行时反射;funcParamTypes 已是 ct 数据,sentinel ct emit 即可 ✗ |

---

## v0 scope 切分说明

**做**(本 issue):
- `gen_registry.ss:42-58` class method 路径补 set funcParamTypes(对称 `codegen.ss:107-111` 普通函数路径)
- `method_call.ss:97-115` invoke sentinel runtime args 循环改:按 funcParamTypes[mangled:idx] 分派 emit cast
  - SS string → `, ptr ${aReg}` 现状(I018 路径 A 行为不变)
  - SS int → emit `call i32 @ss_parseInt` + `, i32 %`
  - SS double → emit `call double @ss_parseDouble` + `, double %`
- HelloController.ss 加 V=int / V=double 端到端测试路由(单参,mirror v0 string 模式;**与 V=string 共存**,保 I021 v0 backward compat)
- Java oracle HelloController.java 同步加 V=int / V=double 路由(`@RequestParam(name="age") int age` / `double x`)保 byte-identical 对齐
- `tests/phase5/i021bc_typed_request_param_cast.ss` 新建,4 case:① V=int hit / ② V=double hit / ③ V=string regression(I021 v0 不破)/ ④ 静态 IR 锚 grep `call (i32|double) @HelloController_*` 各 ≥ 1

**留下轮**(独立 issue / 决策档):
- **I021d 域归属辨析** — V=class **不在 @RequestParam 域**,起独立 D129 决策档讨论域归属(query string → User class 实例无 deserializer 路径;@RequestParam 域契约 = url-encoded primitive/string,V=class 反序列化属 @RequestBody / @ModelAttribute 域)→ docs/3-decisions/D129-request-param-class-domain.md
- **I021-multi-param** — 多参 @RequestParam(`function f(@RequestParam(name="x") x: int, @RequestParam(name="y") y: double)`混合 V 类型,本 issue 修完单参 V=int/double 后多参自然衔接,但 funcParamCount 多参 + invokeExtraArgs 多次拼接路径需独立验证)
- **I021-pathvariable** — `@PathVariable` 路径占位符绑参(`/users/{id}` 中 `id: int` 复用本 issue 的 funcParamTypes + invoke cast 通道,但需 dispatcher 路径模式匹配 + 占位提取另起 issue)
- **I021-optional-defaults** — `@RequestParam(required = false, defaultValue = "100")` 可选参数 + 默认值反序列化(本 issue v0 假设 query 必有 key,miss 走 ss_mapGetString 默认空串 + ss_parseInt("") = 0 fallback;optional/defaults 语义独立)

**不做**:
- 不动 V=class(D129 域归属辨析独立讨论,**不在 @RequestParam 域**)
- 不动多参 @RequestParam(留 I021-multi-param)
- 不动 @PathVariable / @RequestBody / @RequestHeader(各自独立 issue)
- 不改 application.ss dispatcher comptime 展开逻辑(本 issue 改动止于 invoke sentinel 内部 cast emit + gen_registry 注册补全,应用层零改)
- 不改 lib/http.ss query parse(I018 已按 `&` / `=` split 入 req map)
- 不改 checker side(checker 对 `@RequestParam(name="age") age: int` 形参 type 检查走既有路径,annotation 仅 ct 反射端消费)
- 不补 ss_parseInt / ss_parseDouble runtime helper(已就位)
- **不直接动 reflection_health_linter baseline**(本 issue 实施轮跑 linter,若 REGRESSION 走 D097 §B 路径扩容申报登 D123 §扩容申报-I021bc anchor;**本 Decision 落档轮不触代码,baseline 不变**)

---

## 步骤(实施轮 — 再下下轮)

1. **RED 最小隔离测试**:
   - V=int:`/tmp/t_i021bc_int.ss` 写 `class HelloController { ... function hello(@RequestParam(name="age") age: int): string { return "Hello, " + age + "!" } }` + main 启动 SpringApplication;`bin/ss build /tmp/t_i021bc_int.ss -o /tmp/t_i021bc_int && /tmp/t_i021bc_int --serve` + `curl :8080/hello?age=42` 实测 stdout = `Hello, -591256928!`(silent miscompile RED)
   - V=double:同模式 `?x=3.14` → `Hello, 2.67057e-315!`(silent miscompile RED)
   - funcParamTypes probe:`/tmp/t_funcParamTypes_probe.ss` ct probe `funcParamTypes.has("HelloController_hello:0")` = 0 实测(注册漏证据)
2. **数据层注册补全**:`bootstrap/gen/gen_registry.ss:42-58 registerClassMethodRetType` 内 for-in PARAM 循环新增:
   - `funcParamTypes.set(${baseName}:${pCount}, nGetS2(pId))`(基础 key)
   - `if (mSig != "") { funcParamTypes.set(${baseName}_${mSig}:${pCount}, nGetS2(pId)) }`(overload mangled key)
   - 严格对称 `codegen.ss:107-111` 普通函数路径,差异仅在 className 前缀(`${baseName}` = `${className}_${funcName(methodId)}` 已就位 line 43)
3. **分派层 cast emit**:`bootstrap/eval/method_call.ss:97-115` invoke sentinel for-in mcArgParts2 循环改:
   ```
   const ptKey = `${mangled}:${consumed}`
   if (funcParamTypes.has(ptKey) == 1) {
       const ssType = funcParamTypes.getString(ptKey)
       if (ssType == "int") {
           const intReg = nextReg()
           emitIR(`  ${intReg} = call i32 @ss_parseInt(ptr ${aReg})`)
           invokeExtraArgs = `${invokeExtraArgs}, i32 ${intReg}`
       } else if (ssType == "double") {
           const dblReg = nextReg()
           emitIR(`  ${dblReg} = call double @ss_parseDouble(ptr ${aReg})`)
           invokeExtraArgs = `${invokeExtraArgs}, double ${dblReg}`
       } else {
           invokeExtraArgs = `${invokeExtraArgs}, ptr ${aReg}`  // string / 默认
       }
   } else {
       invokeExtraArgs = `${invokeExtraArgs}, ptr ${aReg}`  // funcParamTypes 漏的 fallback
   }
   ```
   注:`nextReg()` 是 codegen 内寄存器分配 helper(参考 invoke sentinel 上文 line 123),emitIR 是单行 IR 发射;cast 在 invoke 之前发射,确保寄存器在 invoke 实参前就绪
4. **callee 端 LLVM 签名验证**:`bin/ss build --emit-ir /tmp/t_i021bc_int.ss` 后 grep `define.*@HelloController_hello.*age` 期望 callee 函数签名形参 LLVM type 已根据 SS type `int` 正确生成 `i32 %age`(应已通过 `gen_methods.ss` 既有路径,本 issue 仅修 invoke 实参 cast 端,callee 端无需改 — 若实测 callee 签名错,扩本 issue scope 到 gen_methods.ss class method LLVM type 推断)
5. **HelloController.ss 端到端测试 controller**:
   - `examples/spring-parity/hello/ss/HelloController.ss` 加 `@GetMapping(path = "/age") function age(@RequestParam(name="n") n: int): string { return "n=" + n }` + `@GetMapping(path = "/calc") function calc(@RequestParam(name="x") x: double): string { return "x=" + x }`
   - 同步 `examples/spring-parity/hello/java/src/main/java/hello/HelloController.java` 加对应 Java method `@RequestParam int n` / `@RequestParam double x` 保 byte-identical 对齐
6. **新建测试**:`tests/phase5/i021bc_typed_request_param_cast.ss` 4 case
   - case 1:V=int hit `?age=42` → `Hello, 42!`
   - case 2:V=double hit `?x=3.14` → `Hello, 3.14!`(注:double 字面化精度容忍,assertEqual 对 `x=3.14` 字符串等比)
   - case 3:V=string regression `?name=SS` → `Hello, SS!`(I021 v0 不破)
   - case 4:静态 IR 锚 grep `call (i32|double) @HelloController_(age|calc)\(` 各 ≥ 1
7. **bootstrap 固定点**:`./build.sh bootstrap` Stage 2 = Stage 3
8. **gate**:`bin/ss run tools/reflection_health_linter.ss`(预估 F1 method_call.ss / gen_registry.ss baseline 漂移可能,按 D097 §B 路径扩容申报登 D123 §扩容申报-I021bc anchor 处理)+ `bin/ss run tools/d_doc_index_linter.ss`(I021bc + D129 引用验证)
9. **parity 端到端**:SS 端 `/tmp/hello_i021bc --serve` + `curl :8080/age?n=42` = `Hello, 42!` ✅;Java 端 `cd examples/spring-parity/hello/java && ./gradlew bootRun` + `curl :8081/age?n=42` = `Hello, 42!` byte-identical(Phase 5 gradle 工具链未接前可单端验证)

---

## 反向 / 备选

**备选 B(invoke sentinel 硬编 mangled)**:
- 优点:不改注册层,单文件改
- 缺点:违反根因 — funcParamTypes 数据层修才是根;每加 controller 都得改 sentinel ✗

**备选 C(application.ss dispatcher 侧 ct emit cast)**:
- 优点:invoke sentinel 不改
- 缺点:应用层堆 cast = 编译期 ct 反射穿插 cast 节点,反射路径架构层污染;违反 CLAUDE.md §编译器吸收复杂度 ✗

**备选 D(运行时反射分派 ss_invoke_with_typed_args)**:
- 优点:运行时灵活
- 缺点:D088 §反模式 — 编译期可知不走运行时;funcParamTypes 已是 ct 数据,无运行时反射必要 ✗

**不做 → 后果**:
- @RequestParam V 维度永久 string-only,V=int / V=double 用户被迫手写 `parseInt(req.get(...))` 双轨制
- @PathVariable / @RequestHeader 等 param-level annotation V=int/double 路径全线不可达
- Java oracle byte-identical parity gate 在 typed param 维度永久 RED
- I021 §第一性需求 在 V 维度永久断裂

---

## 验收 RED 命令

```bash
# RED 最小隔离测试 - V=int silent miscompile
echo 'class HelloController {
    @GetMapping(path = "/age")
    function age(@RequestParam(name = "n") n: int): string { return "n=" + n }
}
function main(args: Array<string>) { SpringApplication.run("test", args) }' > /tmp/t_i021bc_int.ss
bin/ss build /tmp/t_i021bc_int.ss -o /tmp/t_i021bc_int && /tmp/t_i021bc_int --serve &
sleep 1 && curl -s "http://localhost:8080/age?n=42"
# before 期望: n=-591256928 (或类似垃圾 i32) — silent miscompile RED
# after 期望:  n=42 — invoke sentinel 按 funcParamTypes 分派 ss_parseInt + i32 cast OK

# RED 最小隔离测试 - V=double silent miscompile
echo 'class HelloController {
    @GetMapping(path = "/calc")
    function calc(@RequestParam(name = "x") x: double): string { return "x=" + x }
}
function main(args: Array<string>) { SpringApplication.run("test", args) }' > /tmp/t_i021bc_double.ss
bin/ss build /tmp/t_i021bc_double.ss -o /tmp/t_i021bc_double && /tmp/t_i021bc_double --serve &
sleep 1 && curl -s "http://localhost:8080/calc?x=3.14"
# before 期望: x=2.67057e-315 (或类似垃圾 double) — silent miscompile RED
# after 期望:  x=3.14 — invoke sentinel 按 funcParamTypes 分派 ss_parseDouble + double cast OK

# 静态 IR 锚 (端到端验 invoke sentinel cast emit 已生效)
bin/ss build /tmp/t_i021bc_int.ss -o /tmp/t_i021bc_int --emit-ir > /tmp/t_i021bc_int.ll
grep -cE 'call i32 @ss_parseInt\(ptr' /tmp/t_i021bc_int.ll       # 期望 ≥ 1
grep -cE 'call i32 @HelloController_age' /tmp/t_i021bc_int.ll    # 期望 ≥ 1 (callee 签名 i32)

bin/ss build /tmp/t_i021bc_double.ss -o /tmp/t_i021bc_double --emit-ir > /tmp/t_i021bc_double.ll
grep -cE 'call double @ss_parseDouble\(ptr' /tmp/t_i021bc_double.ll  # 期望 ≥ 1
grep -cE 'call double @HelloController_calc' /tmp/t_i021bc_double.ll # 期望 ≥ 1 (callee 签名 double)

# funcParamTypes 注册补全验证
echo '@reflective function probe() {
    println(funcParamTypes.has("HelloController_age:0") + "")  // 期望: 1
    println(funcParamTypes.getString("HelloController_age:0"))  // 期望: int
}' # ct probe (实施轮按 ct probe 模板调整)

# 单测
bin/ss run tests/phase5/i021bc_typed_request_param_cast.ss             # 4 PASS
bin/ss run tests/phase5/d123_phase3_param_bind.ss                       # I018 backward compat regression
bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss               # I019 V=string regression
bin/ss run tests/phase5/i020a_typed_map_get_int.ss                      # I020a regression
bin/ss run tests/phase5/i020b_typed_map_get_double.ss                   # I020b regression
bin/ss run tests/phase5/i020c_typed_map_get_class.ss                    # I020c regression

# 工程
./build.sh bootstrap                                                     # Stage 2 = Stage 3 固定点
bin/ss test tests/                                                       # ≥ 234 passed (I021 v0 收关基线 + 本 issue +1 test)

# parity 端到端
/tmp/hello_i021bc --serve &
curl -s "http://localhost:8080/age?n=42"                                 # 期望: Hello, 42!
curl -s "http://localhost:8080/calc?x=3.14"                              # 期望: Hello, 3.14!
curl -s "http://localhost:8080/hello?name=SS"                            # 期望: Hello, SS! (I021 v0 regression)

# gate
bin/ss run tools/reflection_health_linter.ss                             # F1 GATE PASS (若漂按 D097 §B 申报 D123 §扩容申报-I021bc)
bin/ss run tools/d_doc_index_linter.ss                                   # OK (I021bc + D129 引用通)
```

---

## 风险 / 表面 / 下轮升根路径

**本 issue v0 设计层根解决**(单根因双修复点闭环 — 注册端 + 消费端 = 信息流两端):消除"V 维度 silent miscompile",从 funcParamTypes class method 路径补全注册 + invoke sentinel 按 funcParamTypes 分派 cast emit。不变量锚:`bootstrap/gen/gen_registry.ss:42-58 registerClassMethodRetType + funcParamTypes` / `bootstrap/eval/method_call.ss:97-115 invoke sentinel cast dispatch` / `bootstrap/gen/rt/gen_rt_string.ss:243 ss_parseInt + :250 ss_parseDouble` 复用。

**v0 scope 限定**(非表面,是 scope 切分 mirror I021/I020a/b):
- V=int + V=double 单参先解锁,**V=class 跨域独立 D129 域归属辨析**
- 多参 @RequestParam 留 I021-multi-param
- @PathVariable / @RequestBody / @RequestHeader 各自独立 issue
- @RequestParam(required = false, defaultValue = "100") 留 I021-optional-defaults

**潜在工程风险**:

1. **callee 端 LLVM 签名 vs invoke 实参签名一致性** — 本 issue 改 invoke 实参 cast(caller 端),**前提**是 callee 端 LLVM 函数签名已按 SS 形参类型正确生成(如 `function age(@RequestParam ... n: int)` callee 签名 `define ptr @HelloController_age(ptr %this, i32 %n)`)。**风险**:若 callee 签名因 class method 路径与普通函数路径不对称漏推,本 issue 改完 invoke caller 端 cast 但 callee 端仍 ptr,LLVM 直接拒(类型 mismatch RED)。**下轮升根**:Execute 轮 §步骤 4 验证 callee 签名,若 RED 扩本 issue scope 到 `bootstrap/gen/methods/gen_methods.ss` class method LLVM type 推断对称化(预估 +5-10 LOC),工程量从 ~20-35 漂到 ~30-50 LOC

2. **funcParamTypes overload mangled key 与 invoke sentinel mangled 一致性** — invoke sentinel 在 `bootstrap/eval/method_call.ss:97 funcParamCount.has(mangled)` 用的 `mangled` 是 baseName 还是 baseName_mSig?需 Execute 轮 §步骤 3 实测核对:若 sentinel 用 baseName 查 funcParamCount 但本 issue 双轨注册的 baseName_mSig key 漏匹配,需调整查询顺序(先 mangled 后 baseName fallback)。**下轮升根**:Execute 轮 §步骤 3 实测后,核对 mangled 路径,若误吞需扩 sentinel 查询 fallback 链

3. **double 字面化精度容忍** — V=double `?x=3.14` 经 ss_parseDouble + ss_double_to_string 后字面是否严格 `3.14` 还是 `3.140000` 或 `3.1400000000000001` 需实测;Java oracle 端 `String.valueOf(3.14)` = `3.14` 字面;若 SS 端字面差异超容忍,本 issue 需扩 ss_double_to_string 字面格式化策略(独立 issue 或本 issue +5 LOC)

4. **reflection_health_linter F1 baseline 漂移** — `gen_registry.ss` +5-7 LOC + `method_call.ss` +15-25 LOC,合计 ~20-35 LOC 集中两文件;两文件均在反射路径上(funcRetTypes / funcParamCount 注册族 + invoke sentinel 分派族),F1 行数大概率漂。**下轮升根**:Execute 轮 §步骤 8 跑 reflection_health_linter,若 REGRESSION 走 D097 §B 路径扩容申报登 **D123 §扩容申报-I021bc** anchor 处理(用户 2026-04-25 立项明示)

**无表面接受**:本 issue 全程不接受任何表面绕过,凡发现需要表面补丁(如 sentinel 硬编 mangled / dispatcher 侧 ct cast / 运行时反射)立即停手回 PSM 重新 RCA;遇到工程难点优先扩本 issue §步骤 而非降级 v0 scope。

---

## 触发场景

- I021 §v0 scope §留下轮 显式 hard prereq(V=int + V=double silent miscompile)
- CLAUDE.md §Root Cause 优先(commit 3744f4a + d0a109f)第一法则按根因解决度合并:V=int + V=double 同根因 (funcParamTypes 信息流断裂 — `gen_registry.ss:42-58` 漏 set 注册端断流 + `method_call.ss:107` hardcode `ptr` 消费端不取流,同根因两端),**不**按 V 类型分 I021b/I021c
- Spring parity `?age=42` / `?x=3.14` query param 维度 byte-identical Java parity 真兑现
- Phase 4+ @PathVariable / @RequestHeader 同模式扩展前置基础能力
- Phase 5 Java oracle parity CI 端到端 diff 不因"SS V=int/double silent miscompile vs Java parseInt 正常"误判 byte-identical 失败

---

## 备注

- **根因锚**:本 issue 修 I021 v0 遗留"@RequestParam V 维度 silent miscompile"**单一根因 = funcParamTypes 信息流断裂**;在两个修复点同时缺位 — `gen_registry.ss:42-58 registerClassMethodRetType` 漏 set funcParamTypes(注册端 — 信息源没存)+ `method_call.ss:107` invoke sentinel hardcode `, ptr ${aReg}` 不查 callee 形参类型(消费端 — 信息存了不取)。两点缺一不可因为它们是同一根因的源 + 汇,反事实证(只修一边都不闭环)成立 → 一次穿越同根因双端,符合 §Root Cause (b) "大重构 vs 小补丁 → 选大重构" 原则
- **mirror I020a/I020b 模式**:V=int trunc / V=double bitcast lowering 在 typed Map.get 路径已兑现(I020a/I020b Done),本 issue invoke sentinel cast emit 风格平行(string→int 走 ss_parseInt / string→double 走 ss_parseDouble),不引入新 lowering 形态
- **§Root Cause 第一法则按根因解决度分流**:V=int + V=double 合并 I021bc(同根因)/ V=class 独立 D129(跨域 — 不在 @RequestParam 域)/ 多参留 I021-multi-param(funcParamCount 多参路径独立)/ 其他 param annotation 各自独立 issue。**禁按 V 类型机械分 I021b/I021c/I021d/I021e**(那是按 V 表面分,违反根因解决度)
- **本 Decision 落档轮不触代码**:用户 2026-04-25 立项明示。本 issue 创建后 reflection_linter stale REGRESSION(`gen_decls.ss cur=730 vs bm=708`)留下下轮 Execute 实施轮按 D097 §B 路径扩容申报登 D123 §扩容申报-I021bc anchor 处理
- **预估对照**:本 issue 中档 ~20-35 LOC(单根因双修复点闭环),跨两文件(gen_registry.ss 注册端 + method_call.ss 消费端);Execute 轮独立 commit
- **预估失准前置预警**(参考 I019 §教训 / I020a §教训 / I020c §收关):若 callee 端 LLVM 签名 class method 路径漏推,工程量从 ~20-35 漂到 ~30-50 LOC;Execute 轮 PSM §字段 6 步骤应前置"先 grep callee 签名 LLVM type 是否已正确生成,若 RED 扩 scope 到 gen_methods.ss",避免反复 trial-and-error
