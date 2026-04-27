# D142: SS Array Literal Contextual Typing — 元素类型从调用上下文反推

**Status:** Phase 3 — 测试覆盖 + 隐藏假设挑战 [✓] Done at commit `<TBD>` — 6 测试用例落锚 `tests/d142_array_literal_inference/`(untyped_single + untyped_multi + nested_array + empty_array + interface_upcast + explicit_override)挑战 §A.2 H1/H2/H3/H4/H5/H6 全 PASS + H7 baseline 不降 + H8 reflection GATE PASS + H9 var binding callee OOD scope 标(D141 H9 同模式继承)+ H10/H11/H12/H13 Phase 1+2 已实证;VCM 六验全 PASS(bootstrap 三阶段固定点 + tests/d142_array_literal_inference 6/0/6 全绿 + tests/d141_lambda_inference 5/0/5 不破 + tests 264/4/268 baseline 不降 + reflection GATE PASS no regressions + d_doc_index F1 = 0)+ Phase 2 — codegen 阶段反推实施 + G1 路径 [✓] Done at commit `781d0d5` — 6 文件 +91 LOC delta 实施(`check_types.ss:50` ARRAY_LIT inferType 返 Array<elemType> 结构化 + `gen_types.ss` 三 helper isArrayType/extractArrayElemType/inferArrayLitElems 对偶 D141 isFnType/extractFnParamType/inferArrowFuncParams + `gen_calls.ss:279` resolveCallArgs + `gen/methods/gen_methods.ss:202` emitClassMethodCall + `eval/method_call.ss:61` + `eval/call.ss:33` 4 落点反推 + `gen_calls.ss:631-731` genArrayLit 优先读节点 nGetS2)+ IR 因果实证(`lenShapes([])` ss_newArray→ss_newArrayPtr line 5490 stash 双向对照)+ VCM PASS(bootstrap 三阶段 + 264/4/268 不降 + d141 5/0/5 不破 + reflection GATE PASS via 扩容申报-Phase2 bump 3 处 F1)+ Phase 1 — RED 复现 + 信息源探查 [✓] Done at commit `eb26644` — `/tmp/spike_array_lit_red.ss` 形态 6/7(空数组 + interface upcast)IR 层 RED 铁证 `%5 = call ptr @ss_newArray(i32 0)` ⚠️ 应是 `ss_newArrayPtr`(silent fallback scalar)+ LLC error `'%1' defined with type 'ptr' but expected 'i32'`(method dispatch elemType 漏)+ H1 同模式实证 PASS(`codegen.ss:110-112` + `gen_registry.ss:56-57` Array<T> 字符串原样注册,`codegen.ss:326 registerAllDecls` 在 `emitGlobalsAndCode` 之前 — codegen 阶段满载)+ H10 同模式实证 PASS(`eval/array_lit.ss:13-19` `genVal(elemId)` 在 arrPreRegs 缓存 line 48 + genArrayLit line 60 之前 — 反推必须前移到 outer call site evalMethodCall/evalCall args 循环)+ ARRAY_LIT slot 占用探查 PASS(`parse_exprs.ss:496-498` 仅 nList 占,s1/s2/s3/i1-i4 全空)— Phase 2 入口锁 codegen 阶段反推 + checker `check_types.ss:50` + `check_class.ss:33` 改返 `Array<elemType>` 结构化(与 ARROW_FUNC 同形)
- Phase 0 — D 文档落档 [✓] Done at commit `3fb3ea2` — D141 §Followup F1 array literal contextual typing 候选入口落档(`[1, 2, 3]` 在 fn 实参 `Array<int>` 时反推元素类型);D141 反推机制同模式扩(callee PARAM 已结构化 `Array<T>` SSoT 复用 + codegen 阶段反推 + eval pre-eval 时序回填 + funcParamTypes 信息源单点)

**Depends on:**
- D141(lambda 参数类型推断 + interface dispatch 集成 — §Followup F1 array literal 锚 line 421 + 464)
- D141 §A.1.1 G1 路径(callee PARAM 结构化签名 + codegen 阶段反推 + eval pre-eval 时序)— D142 G1 同模式复刻
- D141 §A.2 H1/H10/H11/H13(funcParamTypes 时序 / setVarType 自然链路 / callee 结构化必要 / 失败硬错粒度)— D142 同模式假设挑战
- D025(interface dispatch — array element class instance vtable 路径)
- D131(`Array<T?>` nullable inner elem 反序列化 + stripNullableCG 路径)
- `bootstrap/checker/check_types.ss:50` 既有破裂入口(`if (kind == "ARRAY_LIT") { return "Array" }` 单一类型,与 D141 ARROW_FUNC 返单一 "fn" 完全同形)
- `bootstrap/gen/gen_types.ss:126 inferArrayElemType()` 既有 helper(信息源已就绪)
- `bootstrap/gen/gen_calls.ss:630 genArrayLit()` codegen 入口(元素 inferType 链路)
- `bootstrap/eval/array_lit.ss evalArrayLit()` eval pre-eval `arrPreRegs` 缓存路径(D141 H10 同形 — 反推前移到 eval pre-eval 之前)
- CLAUDE.md §Java/TS 语法优先(TS array literal contextual typing 主线 / Java 8+ collection literal `List.of(1,2,3)` Type 推断)
- CLAUDE.md §Root Cause 优先 第一法则(数据层 patch 不允许,接口层 trap 单点信息源)
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优的理由)
- `memory/feedback_no_option_menu.md`(三候选论证 + 决策行)
- `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验 (Plan 型 §④ 替换「替代方案对比 + 隐藏假设挑战」)+ §字段 8 "Layer 跨越触发 stop / D 文档独立审查窗口不许吞"

**Date:** 2026-04-27
**Last Updated:** 2026-04-27

---

## 核心目标 (Goal)

- **为什么**:array literal `[1, 2, 3]` 当前 checker `inferType` 返单一 `"Array"`(`bootstrap/checker/check_types.ss:50`),元素类型信息丢失;在 fn 实参 `arr: Array<int>` 场景,反推不到元素类型 → genArrayLit `inferType(elemId)` 落到元素表达式自身推断(单元素正常,但混合元素 / 空数组 / 嵌套 array / interface upcast 全场景 fallback 默认 i64);D141 §Followup F1 锁此 follow-up 是反推机制同模式扩的候选。**末层断言可观测否定证据**(本 Phase 0 实测):`ls docs/3-decisions/D142*.md 2>&1` = `No such file or directory`(exit=2)— D142 文档落档 RED 成立,本轮 Phase 0 GREEN(commit hash 回填后 `ls` 命中)。
- **是什么**:在 array literal 作 fn/method 实参时,从 callee 签名查 `funcParamTypes` 反推 ARRAY_LIT 元素类型,**eval pre-eval 阶段**回填 ARRAY_LIT 节点 elemType slot(参 D141 H1 实证 — checker 阶段 funcParamTypes 用户函数为空,反推必须在 codegen 阶段;参 D141 H10 实证 — eval pre-eval 在 genArrayLit 之前,反推必须前移到 eval pre-eval 之前);后续 codegen `genArrayLit` 内 `inferType(elemId)` 直读已回填的元素类型,链路自然走通。配合 `check_types.ss:50` ARRAY_LIT 不再返单一 `"Array"`,改返 `Array<elemType>` 结构化签名(类型表达力前置,与 ARROW_FUNC `fn(P,...):R` 结构化前置完全同形)。
- **单一判据**:untyped array literal spike(写 `takesArr([1, 2, 3])` 直接传入 fn 形参 `Array<int>`)= D142 §第一性需求 末层断言 RED → 根因修后实测 spike GREEN(对照 IR `call ptr @ss_newArray(i32 3)` + 元素 i64 box 路径正确,无 silent miscompile);且 lib/url.ss + lib/sort.ss + tests/d134_mysql 现存 fn 实参 array literal workaround(若有 `let arr: Array<int> = [...]; takesFn(arr)` 临时绑定形态)Phase 4 cleanup 全删。

> 一句口号:**array literal 元素类型从调用上下文反推 — 用户不必每处临时绑定带类型注解的变量**(D141 反推机制同模式扩到 ARRAY_LIT)

---

## 核心原则 (Principles)

1. **接口层 trap,非数据层 patch** — 信息源单点回填(eval pre-eval 阶段 ARRAY_LIT 节点 elemType slot),codegen 路径不变;不在 genArrayLit / gen_calls.ss / emitValueToI64 多处零散补 fallback(`feedback_root_cause_no_cost.md` 红线)
2. **D141 反推机制同模式扩** — eval pre-eval 时序 + funcParamTypes 信息源 SSoT + codegen 阶段反推 + 失败硬错粒度均沿 D141 §A.1.1 G1 路径;D141 §A.2 H1/H10/H11/H13 假设挑战范式直接复刻
3. **bidirectional type checking 局部** — 仅 array literal 作 fn/method 实参场景反推,不扩到全编译器全表达式 contextual typing(scope 防爆炸,与 D141 §核心原则 2 同位)
4. **TS / Java 8+ contextual typing 主线** — TS 既有能力(`fn arg array literal inferred from param type`)+ Java 8+ `List.of(1,2,3)` Type 推断(用户仍可手写 `let arr: Array<int> = [1,2,3]` override 推断,Java 8+ 风格保留)
5. **callee PARAM 已结构化(无需 G1 callee 升级)** — D141 G1 必须先升级 `setter: fn` → `setter: fn(PreparedStatement):void`(parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析);D142 callee `Array<T>` 类型字符串已存在(lib/sort.ss 18 处 / lib/url.ss URL_encodeQuery 等),`bootstrap/parse/parser.ss:792-793` Array<Array<Tag>?> 嵌套 generic 解析已就绪 — D142 **比 D141 更轻**,Phase 2 不需要 parser 扩
6. **bootstrap 隔离破例** — D141 §核心原则 5 同位例外,D142 主线改 bootstrap 修编译器(checker + codegen + eval),与其他 sub-D scope 独立
7. **interface dispatch 不破** — D025 interface 元素 `Array<IShape>` 反推 + vtable indirect dispatch 路径不动;D131 `Array<T?>` nullable inner elem 反序列化路径不动
8. **funcParamTypes SSoT 复用** — 信息源 `bootstrap/gen/gen_registry.ss:9-10 + 56`(`funcParamTypes` Map "funcName:paramIndex" → SS type),codegen 阶段反推时直接消费,不重复注册;Array<T> 字符串注册路径已存(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57 已注册原始 SS 类型)
9. **零破坏既有 array literal** — 现存 `let arr: Array<int> = [...]` 显式注解(lib/sort.ss / lib/url.ss / tests/d134_mysql 60+ 处)继续走原路径(初始化 RHS 推断由 gen_decls.ss:566-571 处理),Phase 2 反推仅在 array literal 作 fn/method 实参 + 元素类型未知时 fallback 反推,显式优先级 > 推断
10. **Phase 计划独立 commit** — 大改档位:Phase 0 D 文档落盘 + Phase 1+ bootstrap 改各独立 commit,§MNK 大改档不打包(D135/D136/D137/D140/D141 范式延续)
11. **VCM 六验全跑** — bootstrap 三阶段固定点 + tests/ 不降 + tests/phase5/array_*.ss 5 处 baseline 不降 + reflection_health_linter GATE PASS no regressions

---

## 1. Context Management

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D142)
2. CLAUDE.md §Java/TS 语法优先 + §Root Cause 优先 第一法则 + §高层架构 + §交互式单文档
3. 依赖 D 文档:
   - D141 §A.1.1 G1 路径 + §A.2 H1/H10/H11/H13(line 200-209 + 217-230)
   - D141 §Followup F1(line 421 + 464)— D142 入口锚
   - D025 interface dispatch
4. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/parse/parse_exprs.ss` | 469-498 | array literal parser:LBRACKET 入口 + 元素 list + SPREAD_ELEM 嵌入 + `newNode("ARRAY_LIT")` + nSetList |
   | `bootstrap/checker/check_types.ss` | 50 | `if (kind == "ARRAY_LIT") { return "Array" }` — **当前破裂入口,信息丢失**;Phase 2 改返 `Array<elemType>` 结构化(与 ARROW_FUNC line 51-71 同形) |
   | `bootstrap/checker/check_types.ss` | 237-245 | `isTypeCompatible` Generic types 比对 base type(`Array<int>` compat with `Array` — imprecise but safe);Phase 2 评估是否需扩 elemType 严格比对(若反推后 strict)— 可能与 D141 isTypeCompatible fn 双向兼容同模式扩 |
   | `bootstrap/checker/check_class.ss` | 33 | `if (kind == "ARRAY_LIT") { return "Array" }` — normalizeGeneric 同形破裂(method dispatch 入口);Phase 2 同步改 |
   | `bootstrap/checker/check_exprs.ss` | 281 | ARRAY_LIT checker 入口(已存在,元素逐个 checkExpr) |
   | `bootstrap/gen/gen_types.ss` | 126-151 | `inferArrayElemType()` — **信息源 helper 已就绪**(IDENT varType `Array<X>` 提取 X / METHOD_CALL split → string / filter/slice/reverse/sort 递归 / MEMBER_ACCESS classFieldTypes);Phase 2 直接复用 |
   | `bootstrap/gen/gen_types.ss` | 542 | `if (kind == "ARRAY_LIT") { return "ptr" }` — codegen 层 LLVM 类型(不动) |
   | `bootstrap/gen/gen_types.ss` | 209-213 + 486 + 559 | `inferArrayElemType` 既有调用(INDEX_ACCESS / 成员访问 / 表达式推断)— Phase 2 反推回填后,这些链路自然消费新 elemType |
   | `bootstrap/gen/gen_calls.ss` | 630-718 | `genArrayLit()` — 元素逐个 `inferType(elemId)` + ssTypeToLLVM + emitValueToI64 + ss_newArrayPtr/ss_newArray dispatch;Phase 2 反推回填 ARRAY_LIT 节点 elemType slot 后,line 643 inferType / 711 inferType 路径自然消费 |
   | `bootstrap/gen/gen_calls.ss` | 231 | `resolveCallArgs(callee, argList, typeCallee)` — fn 调用 args 解析入口,**Phase 2 反推主入口候选**(D141 同点反推主入口) |
   | `bootstrap/gen/gen_calls.ss` | 300 | `inferArrayElemType(spreadArrExpr)` 既有调用(SPREAD 路径)— Phase 2 不动 |
   | `bootstrap/gen/gen_decls.ss` | 380 + 561-571 | array literal 在 var decl RHS 时 `inferArrayElemType` + setVarType `Array<${aeType}>` — Phase 2 不动(显式 var decl 路径既有) |
   | `bootstrap/gen/gen_registry.ss` | 9-10 + 56 + 71-72 | `funcParamTypes` Map "funcName:paramIndex" → SS type(`Array<int>` / `Array<string>` 等已注册);Phase 2 反推直接消费 |
   | `bootstrap/gen/codegen.ss` | 110-112 + 252 + 326 | 普通函数 funcParamTypes 注册 line 110-112(`registerFuncDeclNode`)+ class method gen_registry.ss:56-57 — Phase 2 不改注册路径 |
   | `bootstrap/eval/array_lit.ss` | 4-58 | `evalArrayLit()` — 对称三段式(空数组 / comptime 全 ct / runtime arrPreRegs);**eval pre-eval 时序入口**(D141 H10 同形,反推必须前移到 eval pre-eval 之前) |
   | `bootstrap/eval/eval_expr.ss` | 79 | `if (k == "ARRAY_LIT") { return evalArrayLit(astId) }` — eval dispatch 入口 |
   | `bootstrap/eval/method_call.ss` | 4-120 | `evalMethodCall()` — 包含 args pre-eval `genVal(argId)` 路径(D141 反推前移落点);Phase 2 反推插桩在 args 循环 ARRAY_LIT 检测处 |
   | `bootstrap/eval/call.ss` | (查 grep — fn callee args pre-eval 路径)| Phase 2 反推插桩第二落点 |
   | `lib/sort.ss` | 16-209 | 18 处 `Array<int>` callee PARAM(sortMergeTwo / sortInsert / Sort_quickSort / Sort_mergeSort / Sort_insertionSort / Sort_isSorted / Sort_binarySearch / Sort_unique / Sort_merge / Sort_shuffle / Sort_min / Sort_max)— **反推机制最大消费者**,Phase 2 后用户可直接 `Sort_quickSort([3,1,2])` 不需临时变量 |
   | `lib/url.ss` | 244 | `URL_encodeQuery(keys: Array<string>, values: Array<string>): string` — 反推消费者 |
   | `tests/phase5/array_fn_elem.ss` | 全文 | `Array<fn>` callee + array literal `[twice, thrice]` 现状(已 GREEN,Phase 2 反推不破) |
   | `tests/phase5/array_class_elem.ss` | 全文 | `Array<UserClass>` 元素类型 baseline |
   | `tests/phase5/array_methods.ss` | 全文 | array methods baseline(filter/map/sort/etc) |
   | `tests/phase5/array_untyped_access.ss` | 全文 | untyped 访问 baseline(D142 不破现状) |
   | `bootstrap/gen/codegen.ss` | 100-122 | `registerFuncDeclNode()` 内 `funcParamTypes.set(\`${fname}:${pCount}\`, nGetS2(fpId))` line 110 — Array<T> 原文(如 `"Array<int>"`)直接注册;`codegen.ss:326 registerAllDecls(rootId)` 在 `emitGlobalsAndCode(rootId)` line 327 之前调,**codegen 阶段满载用户函数 funcParamTypes**(H1 同模式实证 PASS) |
   | `bootstrap/gen/gen_registry.ss` | 19-25 + 67-72 | `initFuncRegistry()` 启动只满载 builtin(line 22 `initBuiltinMap()`)+ `initFuncRetTypes()` 内 line 72 `funcParamTypes = Map()` 清空 — 用户函数 funcParamTypes 启动时空,等 codegen registerAllDecls 才满载 |
   | `bootstrap/eval/array_lit.ss` | 4-19 + 48-60 | evalArrayLit `genVal(elemId)` line 16 在 arrPreRegs 缓存 line 48 + `genArrayLit(astId)` line 60 之前 — **反推必须前移到 outer call site evalMethodCall/evalCall args 循环**,在 evalArrayLit 内已迟(H10 同模式实证 PASS) |
   | `bootstrap/parse/parse_exprs.ss` | 496-498 | `newNode("ARRAY_LIT") + nSetList(id, elems)` — **仅 nList 占,s1/s2/s3/i1-i4 全空**(slot 探查 PASS,Phase 2 用 s2 存 elemType 与 ARROW_FUNC PARAM s2 同范式) |
   | `/tmp/spike_array_lit_untyped.ss` | 全文 | Phase 1 RED 五形态 spike(单元素 / 多元素 / 空数组 / 嵌套 / interface upcast)— 形态 1-5 行为 GREEN(元素 inferType 自身可推)|
   | `/tmp/spike_array_lit_typed.ss` | 全文 | Phase 1 typed 对照 spike(显式 RHS 临时变量绑定)— 行为 GREEN,IR 形态 5 `ss_newArrayPtr` 同 untyped(单元素能推路径不破) |
   | `/tmp/spike_array_lit_red.ss` | 全文 | **Phase 1 RED 精确入口**(空数组 + callee `Array<IShape>`)— IR `%5 = call ptr @ss_newArray(i32 0)` ⚠️ + LLC error `'%1' defined with type 'ptr' but expected 'i32'` + run 时 build 失败(silent miscompile 链:空数组无元素 inferType 来源 → fallback ss_newArray scalar → 元素期望 ptr 类型错配 → method dispatch 入口 elemType="Array" 漏) |

### Stable Facts

| 项 | 值 |
|---|---|
| 现存 callee `Array<T>` 用例 | lib/sort.ss 18 处 + lib/url.ss 1 处 + lib/argparse.ss 2 处 + lib/json.ss 4 处 + lib/path.ss 2 处 + lib/string_utils.ss 4 处 + tests/d134_mysql 8 处 + 其他 lib/spring/boot 等 4 处(总 40+ 处) |
| Array<T> 类型解析 | parser.ss:792-793 嵌套 generic `Array<Array<Tag>?>` 已就绪(无 Phase 2.0 parser 扩需求) |
| funcParamTypes Array<T> 注册 | 已就绪(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57 直接注册原始 SS 类型字符串) |
| inferArrayElemType helper | 已就绪 gen_types.ss:126-151 |
| genArrayLit codegen 路径 | 已就绪 gen_calls.ss:630-718 |
| evalArrayLit eval pre-eval 路径 | 已就绪 eval/array_lit.ss(arrPreRegs 缓存) |
| ARRAY_LIT inferType 当前 | 单一 "Array"(checker.check_types.ss:50 + check_class.ss:33)— **D142 §A.1 主候选 C2 修复入口** |
| 反射 baseline | tools/reflection_health_linter.ss(本 D 不触反射) |
| d_doc_index_linter F1 | Phase 0 落盘后 D142 加入,referenced D 文档 D141/D025/D131 实存 → F1 = 0 |

### 禁止的 Context 操作

- ❌ 改 parser(Array<T> 类型 annotation 解析已就绪 — 与 D141 G1 必须扩 parseTypeAnn 不同 — §核心原则 5 + H12)
- ❌ 改 funcParamTypes 注册路径(已就绪 — §核心原则 8)
- ❌ 改 inferArrayElemType helper 本体(已就绪 — Phase 2 直接复用,不重写)
- ❌ 改 genArrayLit 本体逻辑(line 643/711 inferType 路径反推回填后自然消费,不动函数体)
- ❌ 起 D143/D144(留 D141 §Followup F2/F3/F4 同模式扩展)
- ❌ 改 D141 文档本体(D141 §核心原则 5 例外锚 D142 同模式继承,文档不动)
- ❌ 改 D025/D131 interface dispatch / 反序列化契约
- ❌ 加全局 bidirectional type checking(C3 候选废 — 范围爆炸,留 SS 类型系统 v2)

---

## 2. Tools

| 工具 | 用途 |
|---|---|
| `./build.sh bootstrap` | 三阶段固定点(Phase 1+ bootstrap 改后必跑) |
| `bin/ss run /tmp/spike_array_lit_untyped.ss` | spike RED→GREEN 验证(主判据,Phase 1 写入 + Phase 2 实测) |
| `bin/ss test tests/phase5/array_fn_elem.ss tests/phase5/array_class_elem.ss tests/phase5/array_methods.ss tests/phase5/array_push_storeback.ss tests/phase5/array_untyped_access.ss` | array baseline 5 处不降 |
| `bin/ss test tests/d141_lambda_inference/` | D141 反推机制 baseline 不破 |
| `bin/ss test tests/` | 全测 baseline 不降 |
| `bin/ss build /tmp/spike_array_lit_untyped.ss --emit-ir` | IR 层 RED 复现(Phase 1) |
| `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate |
| `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射) |
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ 新关键字 / 新语法 / 新 AST 节点(array literal 反推是反推机制扩展,非语法扩展)
- ❌ 新依赖
- ❌ 改 codegen / parser / interpreter / lib(Phase 2 改 checker + 局部 codegen 反推 + eval pre-eval 反推插桩)

---

## 3. Orchestration

### 总体节奏(D141 5 Phase 范式延续)

| Phase | 目标 | 关键产出 | 验证 |
|-------|------|----------|------|
| **Phase 0** | D 文档落档(本 Phase) | `docs/3-decisions/D142-*.md` | d_doc_index_linter F1 = 0 + ultrathink_linter PASS |
| **Phase 1** | RED 复现 + 信息源探查 | `/tmp/spike_array_lit_untyped.ss`(本 Phase 写)+ IR 层 RED 铁证 + funcParamTypes Array<T> 字符串实测可用(grep 实证)+ eval pre-eval vs codegen emit 时序探查(确认 D141 H10 同形是否成立)+ 隐藏假设 H1/H10 复刻验证 | IR RED 铁证(若有)+ 时序探查 fact 入 §1 + §A.2 H1/H10 实证记录 |
| **Phase 2** | codegen 阶段反推实施 + G1 路径(D141 G1 同模式) | `bootstrap/checker/check_types.ss:50` ARRAY_LIT 改返 `Array<elemType>` 结构化(与 ARROW_FUNC 同形)+ `bootstrap/checker/check_class.ss:33` 同步改 + `bootstrap/gen/gen_calls.ss:resolveCallArgs` + `gen/methods/method_call.ss:emitClassMethodCall` 内 args 循环识别 ARRAY_LIT + 查 funcParamTypes Array<T> + extract elemType + 反推回填 ARRAY_LIT 节点 elemType slot + `eval/method_call.ss + eval/call.ss` pre-eval 之前反推前移 | bootstrap 固定点 PASS + spike untyped 反推 GREEN + tests/phase5/array_*.ss baseline 不降 |
| **Phase 3** | 测试覆盖 + 隐藏假设挑战 | `tests/d142_array_literal_inference/` 新增(单元素反推 / 多元素同质 / 嵌套 array `[[1,2],[3,4]]` / 空数组反推 / interface upcast / 显式优先 / 推断失败硬错诊断)| 6+ test case 全绿 + 隐藏假设 H1-H8 全 PASS |
| **Phase 4** | workaround cleanup | grep + 删现存 fn 实参 array literal 临时变量绑定 workaround(若有 `let arr: Array<int> = [1,2,3]; takesFn(arr)` 形态 — Phase 1 grep 实测后定计数)| bootstrap 固定点 PASS + tests/ baseline 不降 |
| **Phase 5** | 全 Phase 收关 hash trail | D142 5 Phase commit hash 全列 + 兑现成果 a-g + 隐藏假设全 PASS / OOD 标 + Followup 锚明确 | D142 主线 close |

### Phase 间依赖

- Phase 0 → 1:D 文档落档后用户审,Phase 1 下一轮起
- Phase 1 → 2:RED 成立 + 时序探查就位才启 Phase 2;若 H1 funcParamTypes 时序不就(D141 实证已破裂,但 ARRAY_LIT 路径需独立验证)→ 调整 Phase 2 入口
- Phase 2 → 3:bootstrap 固定点 PASS + spike GREEN 才启 Phase 3 测试覆盖
- Phase 3 → 4:测试覆盖完整(隐藏假设全 PASS)才启 Phase 4 workaround cleanup
- Phase 4 → 5:cleanup 完整 + tests/ baseline 不降才启 Phase 5 收关

### 反模式

- ❌ 改 parser parseTypeAnn(Array<T> 解析已就绪 — H12 比 D141 弱)
- ❌ 改 funcParamTypes 注册路径(已就绪 — §核心原则 8)
- ❌ 把 inferArrayElemType helper 重写(已就绪 gen_types.ss:126-151,Phase 2 复用)
- ❌ 顺带改 array literal RHS var decl 路径(gen_decls.ss:566-571 既有,显式优先 — H6)
- ❌ 起全局 bidirectional type checking(C3 候选废,留 D026/D027 generic 落地后再开 D 文档评估)
- ❌ 实施 D141 §Followup F2/F3(object literal / ternary contextual typing)— 留同模式扩 sub-D 后续轮

---

## 4. State

### 编译时 state

- ARRAY_LIT 节点 elemType slot(待定:nSetS2 / nSetS3 / 新引入 list 槽位 — Phase 1 探查节点 slot 当前占用情况)
- funcParamTypes(已就绪,Phase 2 不改注册路径)
- evalArrayLit arrPreRegs(eval pre-eval 缓存,Phase 2 反推前移到 evalArrayLit 之前)

### 运行时 state

(N/A — 本 D 是 checker + codegen 编译时改,不影响运行时;genArrayLit emit 路径不变)

### 中间产物

- `/tmp/spike_array_lit_untyped.ss`(Phase 1 写)
- 三候选评估矩阵(本 D §A.1 + §A.1.1)
- 隐藏假设挑战表(本 D §A.2)

### 会话间持久化

- D142 §Phase 进度(clear 后续 Plan 锚,Status 行单一事实源)
- bootstrap 三阶段固定点 commit hash(各 Phase 回填)

### 禁止 state 操作

- ❌ 把 ARRAY_LIT elemType 信息保存到全局 Map(节点 slot 已足够 — 与 D141 ARROW_FUNC PARAM s2 节点 slot 同范式)
- ❌ 把跨轮进度 / 摘要写到 handoff 文件(`.claude/next_prompt.md` 仅 terman preset 单次 payload)

---

## 5. Evaluation

### 单一判据(必须 GREEN)

```bash
# Phase 1 RED:untyped array literal + fn 实参 — 当前需手动临时变量绑定才走通
cat <<'EOF' > /tmp/spike_array_lit_untyped.ss
function takesArr(arr: Array<int>): int {
    let sum = 0
    for (x in arr) { sum = sum + x }
    return sum
}
function main() {
    let r = takesArr([1, 2, 3])
    println(`r=${r}`)
}
EOF

# Phase 1 RED:bin/ss run /tmp/spike_array_lit_untyped.ss
# 期望(待 Phase 1 实测确认):若元素类型自身可推(int literal),当前路径可能已 GREEN(r=6);
# 若 RED 则锁定根因路径;若已 GREEN 则 spike 改成多元素混合 / 空数组 / interface upcast 形态以触发反推需求

# Phase 2 GREEN:bin/ss run /tmp/spike_array_lit_untyped.ss
# 期望:r=6(反推回填 elemType=int + ss_newArray + emitValueToI64 路径正确)
```

### Phase 2 关键验证

- bootstrap 三阶段固定点 PASS(stage2 == stage3 字节比较)
- spike GREEN(主判据)
- tests/phase5/array_*.ss 5 处 baseline 不降(array_fn_elem / array_class_elem / array_methods / array_push_storeback / array_untyped_access)
- tests/d141_lambda_inference/ 5 处 baseline 不降(D141 反推机制不破)
- tests/ 264/4/268 baseline 不降
- reflection_health_linter GATE PASS no regressions

### Phase 3 测试覆盖(隐藏假设挑战)

- 单元素反推(`takesArr([1])` callee `takesArr(arr: Array<int>)`)— H1 反推单元素 PASS
- 多元素同质反推(`takesArr([1, 2, 3])`)— H2 反推多元素同质 PASS
- 嵌套 array(`takesNested([[1,2], [3,4]])` callee `takesNested(arr: Array<Array<int>>)`)— H3 嵌套反推 capture 链
- 空数组反推(`takesArr([])` callee `takesArr(arr: Array<int>)`)— H4 空数组反推 PASS(无元素无 inferType 来源,反推机制兜底)
- interface upcast(`takesShapes([new Square(2.0), new Circle(3.0)])` callee `takesShapes(arr: Array<IShape>)`,arr.area() vtable indirect)— H5 interface dispatch PASS
- 显式优先(`let arr: Array<int> = [1,2,3]; takesArr(arr)`)— H6 显式注解仍走原路径
- 推断失败 fallback(callee 不在 funcParamTypes / arity 不匹配 / 非结构化 callee `arr: Array`)→ skip 反推或硬错(参 D141 H13 粒度)

---

## 6. Constraints

### 硬约束

- 不引入 bidirectional type checking 全局(候选 C3 已废,scope 爆炸)
- 不动 D025 interface dispatch 契约
- 不动 D131 nullable inner elem 反序列化路径
- 不动 D141 lambda 反推机制(D142 是 D141 同模式扩,不重写 D141 信息源)
- bootstrap 改不许超过 800 LOC delta(`feedback_600_split_not_inline.md` + `feedback_structure_not_linecount.md`)— 实际预估 ≤ 250 LOC(check_types.ss + gen_calls.ss + eval/method_call.ss + eval/call.ss 局部改)

### 软约束

- 推断失败时**优先编译期硬错**(参 D141 H13 结构化 callee 硬错粒度);非结构化 callee `arr: Array` skip 反推不破现状
- 显式注解仍优先级最高(`let arr: Array<int> = [...]` Java/TS 风格,既有 60+ 处现存)
- 反推查 callee `funcParamTypes` 时,callee 必须已 register(D141 H1 实证 codegen 阶段已就绪)— Phase 1 文档化时序保证

### 风险锚(R1-R5)

| # | 风险 | 描述 | mitigation |
|---|---|---|---|
| R1 | ARRAY_LIT 节点 slot 占用冲突 | nSetS2 / nSetS3 已被其他用途占用,反推回填 elemType 找不到空 slot | Phase 1 探查 ARRAY_LIT 节点 slot 当前占用(`bootstrap/parse/parse_exprs.ss:496` newNode + nSetList 后,s1/s2/s3 是否空);若占用 → 复用 nSetS2 (类型 slot 命名) / nSetS3 / 新引入 hash Map(ssArrayLitElemType[id] → string)路径;参 D141 ARROW_FUNC 用 PARAM s2 范式 |
| R2 | 嵌套 array 反推链路断 | `[[1,2], [3,4]]` 内层元素是 ARRAY_LIT,反推外层 elemType="Array<int>" 后,内层 ARRAY_LIT 也需反推 elemType="int" — 递归回填 | Phase 2 实施 + Phase 3 嵌套 array test;若失败 → 内层 ARRAY_LIT 反推回路 fallback 单层 + 用户嵌套时仍需显式 RHS binding |
| R3 | 空数组反推无元素无来源 | `takesArr([])` 内无元素,inferType 单元素 fallback 失效;反推必须从 callee `Array<int>` 直接取 elemType | Phase 2 反推路径不依赖元素来源 — 直接从 callee Array<T> extract T 回填 ARRAY_LIT elemType slot;genArrayLit hasPtrElem/hasScalarElem 当前依赖 elemList 遍历 inferType,空数组 fallback 走 ss_newArray 默认 i64 — Phase 2 改成读节点 elemType slot 优先 |
| R4 | interface upcast 元素类型反推 | `Array<IShape>` 元素是实际 implementor 类(Square / Circle),反推后元素类型 slot = "IShape",vtable indirect dispatch 走 D025 路径 | Phase 3 interface upcast test;失败 → 回 Phase 2 修 vtable 路径 |
| R5 | check_class.ss:33 normalizeGeneric 同步改 | check_types.ss:50 改后,check_class.ss:33 ARRAY_LIT method dispatch normalizeGeneric 也需同步返结构化(否则 method dispatch 入口看 "Array" 走 normalize 路径,后续 dispatch 漏 elemType) | Phase 2 实施时同步修(2 处一齐改,LOC ~+5);Phase 3 array_methods.ss baseline 不降验证 |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 spike 已 GREEN(无 RED) | 改 spike 形态:多元素混合 / 空数组 / interface upcast / 嵌套 array 触发反推需求;若全场景已 GREEN → D142 范围降级为 "类型表达力对齐 D141"(Plan-only,无代码改) |
| Phase 2 build 失败 | git revert;调 ARRAY_LIT slot 命名 + check_types.ss:50 / check_class.ss:33 双向同步 |
| Phase 2 嵌套 array 红 | R2 mitigation:内层 ARRAY_LIT 反推单层 fallback + 文档化 H3 OOD scope |
| Phase 2 tests/phase5/array_*.ss 红 | R5 mitigation:check_class.ss:33 normalizeGeneric 同步漏改 — 补 |
| Phase 2 reflection_health_linter GATE BLOCK | 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段) |
| Phase 4 grep 工作量超估 | 范围限定 lib/ + tests/d134_mysql/(D141 cleanup 同域),其他 tests/ 留 sub-D 后续轮 |

### 回滚策略

- Phase 1+ 失败 → `git reset --soft HEAD^` 回上一 Phase
- Phase 0 文档已落盘,Phase 1+ 实施 commit 边界严格(D135/D136/D137/D140/D141 范式延续)
- D142 失败回退不影响 D141(D141 主线已 close,D142 仅同模式扩)

---

## A.1 主候选评估(§MNK §M §字段 10 + Plan 型 §④ 替换:替代方案对比)

| 候选 | 层次 | 描述 | 假设破裂入口 | 优势 | 劣势 | 决策 |
|---|---|---|---|---|---|---|
| **C1** | **数据层 patch** | `gen_calls.ss:643/711 inferType(elemId)` 路径加 fallback — 元素类型未知时从 callee funcParamTypes 取 elemType 兜底 | 破裂入口在 ARRAY_LIT inferType 返单一 "Array",信息丢失;C1 仅在 genArrayLit 单点补 fallback,不消除根因 — check_class.ss:33 method dispatch / inferArrayElemType 等其他消费者仍走错 | LOC 极小 5-10 行;不动 checker | 零散 patch — 多消费者(genArrayLit / inferArrayElemType / classFieldTypes 等)都用 ARRAY_LIT inferType,信息源不单点;同模式 array literal 在 method 实参 / map literal 等场景仍 RED | **不选** — 数据层不消除根因(`feedback_root_cause_no_cost.md` 红线,与 D141 §A.1 C1 同形废) |
| **C2** | **接口层 trap** | checker `check_types.ss:50` ARRAY_LIT 改返 `Array<elemType>` 结构化签名(与 ARROW_FUNC `fn(P,...):R` 同形)+ codegen 阶段 fn/method 实参反推回填 ARRAY_LIT elemType slot + eval pre-eval 时序 + funcParamTypes SSoT 复用 | **彻底消除** — ARRAY_LIT inferType 结构化,所有下游(genArrayLit / inferArrayElemType / classFieldTypes / method dispatch)信息源一致;eval pre-eval 反推前移避免 D141 H10 同形时序破裂 | 单点信息源回填;TS / Java 8+ contextual typing 主线;D141 G1 路径同模式复刻;workaround cleanup 落锚 | LOC 中等 ~250(check_types.ss + check_class.ss + gen_calls.ss + eval/method_call.ss + eval/call.ss + helper);需考虑嵌套 array / 空数组 / interface upcast 边界 | **选** — 接口层 trap 消除根因 + scope 可控 + D141 同模式复用 |
| **C3** | **架构层 refactor** | 全编译器 bidirectional type checking — checker 改 expected/actual 双向类型检查,所有表达式从调用上下文反推类型(包括 array literal + object literal + ternary + null literal 等) | 消除根因 + 消除其他 silent miscompile(object literal / ternary 类型推断等)| 类型系统统一性最高;未来扩 SS 泛型 D026/D027 时直接复用;D141 §Followup F5 已锁此候选废留 SS 类型系统 v2 | scope 爆炸 LOC > 2000 + 多 sub-D + bootstrap 重写多个核心文件;F1 单 sub-D scope 远超(D142 不应承载架构层 refactor) | **不选** — scope 远超 D142 单 sub-D 范围;**D141 §Followup F5 已锁此候选废**,留作未来 SS 类型系统 v2 评估 |

**决策行**:**选 C2 接口层 trap** 因 (a) 单点信息源回填,消除 ARRAY_LIT inferType 单一 "Array" 的假设破裂入口;(b) D141 G1 路径同模式复刻 — eval pre-eval 时序 + funcParamTypes SSoT + codegen 阶段反推 + 失败硬错粒度全沿用;(c) workaround cleanup 落锚 Phase 4(临时变量绑定形态全删);(d) scope 可控 ~250 LOC delta < D141 ~267 LOC。**为何不选 C1**:数据层 zero-spread 不消除根因(`feedback_root_cause_no_cost.md` 红线,与 D141 §A.1 C1 同形废)。**为何不选 C3**:scope 爆炸 — D141 §Followup F5 已锁 C3 废留 SS 类型系统 v2,D142 单 sub-D 不承载架构层 refactor。

---

## A.1.1 C2 实施路径对比(Phase 2 起首,2026-04-27)

> Phase 2 起首查源:`lib/sort.ss` 18 处 + `lib/url.ss` 1 处 + `tests/d134_mysql` 8 处 + 其他 lib 共 40+ 处 callee PARAM 类型 annotation 已写为 `Array<T>` 结构化签名;funcParamTypes 已注册原始 SS 类型字符串(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57)— **D142 比 D141 G1 路径更轻**(D141 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn` → `setter: fn(PreparedStatement):void`,parser 必须扩 parseTypeAnn fn 类型;D142 callee 端已结构化,parser 已就绪,反推可直接消费)。下分三路径定 D142 实施。

| 路径 | 描述 | 解决度 | LOC | 影响 | 决策 |
|------|------|--------|-----|------|------|
| **G1** | **D141 G1 同模式复刻** — checker `check_types.ss:50` ARRAY_LIT 返 `Array<elemType>` 结构化(与 ARROW_FUNC line 51-71 同形)+ codegen 阶段反推回填 ARRAY_LIT elemType slot + eval pre-eval 反推前移 + funcParamTypes 已结构化直接消费(无 callee 升级前置)+ helper `isArrayType` / `extractArrayElemType` 落 gen_types.ss(对偶 D141 isFnType / extractFnParamType) | 100% | check_types.ss ~10 + check_class.ss ~3 + gen_types.ss helper ~30 + gen_calls.ss + gen_methods.ss 反推 ~30 + eval/method_call.ss + eval/call.ss pre-eval 反推 ~30 + check_types.ss isTypeCompatible 调整 ~10 ≈ **~115** | Phase 4 临时变量绑定 cleanup 仍可推进(callee 已结构化与 array literal cleanup 独立) | **选** — D141 G1 同模式复刻 + 比 D141 更轻(无 parser 扩 + 无 callee 升级前置) |
| G2 | callsite 双向反推 — 从 array literal 第一个非空元素类型反推 ARRAY_LIT elemType;不依赖 callee `Array<T>` 形态 | 70% | gen_calls.ss + gen_methods.ss ≈100 | 漏空数组(`[]` 无元素无来源)+ 漏 fn binding 间接链(`const f = [1,2]; takesFn(f)`)+ 漏异质元素混合(`[1, "a"]` 反推取第一元素 → 类型错位) | 不选 — 漏 3 类边界 + 偏离 TS / Java 8+ 主线(TS 是从 callee 形参反推 array literal,不是 array literal 自反) |
| G3 | 接受 gap,Phase 2 仅做 (a) 预备 — check_types.ss:50 改 ARRAY_LIT 返结构化签名,(b)(c) 反推机制因消费链路不接通实际不生效;主线 D141 §Followup F1 cleanup 延期 | 0% | check_types.ss:50 单点 ≈10 | 主线 cleanup 延期;反推机制空转;违反 `feedback_root_cause_no_cost.md` 红线 | 不选 — 反推机制空转无意义 |

**G1 决策(本 Phase 0 落档锁定,待用户对话确认)**:走 G1 — 根因 100% + D141 G1 同模式复刻 + scope 可控 < D141 LOC + 比 D141 更轻(无 parser 扩 + 无 callee 升级前置 — H11/H12 比 D141 弱)。**为何不选 G2**:漏空数组 + fn binding + 异质混合 3 类边界;且偏离 TS / Java 8+ contextual typing 主线(TS array literal 反推靠 callee 形参签名,不靠元素自身 inferType)。**为何不选 G3**:反推机制空转 0% 解决度,违反 `feedback_root_cause_no_cost.md` 红线。

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套 — D141 §A.2 同模式扩)

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | funcParamTypes Array<T> 字符串在 codegen 阶段已 ready(D141 H1 同模式 — checker 阶段用户函数为空,codegen registerAllDecls 后满载)| 实施层失败 — codegen 反推时 funcParamTypes 留空,反推查不到 callee Array<T> 签名 | Phase 1 探查 codegen.ss:110-112 + gen_registry.ss:56-57 register 时机;Phase 2 startup 阶段 dump funcParamTypes 验证含 Array<T> 形态;**D141 H1 已实证 codegen 阶段已就绪**,D142 同模式假设大概率成立 | funcParamTypes 时机不就 → 调整 Phase 2 入口(改 lazy 反推 vs eager 反推)|
| H1 实证(Phase 1)| **✓ 同模式 PASS** — `bootstrap/gen/codegen.ss:100-122` `registerFuncDeclNode()` 内 line 110 `funcParamTypes.set(\`${fname}:${pCount}\`, nGetS2(fpId))` — `nGetS2(fpId)` 是 PARAM s2 原文(`Array<int>` / `Array<string>` / `Array<IShape>` 等结构化字符串原样注册);`gen_registry.ss:67-72 initFuncRetTypes` 内 line 72 `funcParamTypes = Map()` 清空,启动 `main.ss:264 initFuncRegistry()` 只填 builtin(D141 实证已确);`codegen.ss:326 registerAllDecls(rootId)` 在 line 327 `emitGlobalsAndCode(rootId)` 之前调 — codegen 阶段满载用户函数 funcParamTypes;`gen_registry.ss:42-65 registerClassMethodRetType()` 内 line 56 `funcParamTypes.set(\`${baseName}:${pCount}\`, nGetS2(pId))` — class method 路径同源同步注册 | grep 实证:`bootstrap/gen/codegen.ss:110-112` 普通函数注册 + `gen_registry.ss:56-57` class method 注册 + `lib/sort.ss:16-17` Array<int> 字符串原文(`function sortMergeTwo(a: Array<int>, b: Array<int>): Array<int>`)`nGetS2` 直接拿到结构化签名 — **Phase 2 反推 helper `extractArrayElemType("Array<int>") = "int"` 直接消费,无 callee 升级前置(比 D141 G1 更轻 — D141 必须先 lib/spring/(jdbc+data).ss 7 处 setter: fn → setter: fn(...):...)** | Phase 2 反推主入口在 `gen_calls.ss:231 resolveCallArgs` + `gen/methods/method_call.ss` 内,checker 阶段反推路径不必走(H1 实证下 codegen 阶段足够) |
| H2 | ARRAY_LIT 多元素同质反推不破元素 inferType 链路 | `[1, 2, 3]` 元素 inferType 各返 "int",反推回填 elemType="int" 与元素 inferType 一致;若元素 inferType 与反推 elemType 冲突(`[1, 2, "a"]` 异质)→ 反推失败硬错 | Phase 3 测试 `tests/d142_array_literal_inference/multi_elem.ss` + `异质_硬错.ss` | 异质混合 silent fallback → 回 Phase 2 修硬错路径;参 D141 H4 fallback 编译期硬错粒度 |
| H3 | 嵌套 array `[[1,2],[3,4]]` 反推 capture 链 | 内层 ARRAY_LIT 元素也是 ARRAY_LIT,反推外层 elemType="Array<int>" 后,内层 ARRAY_LIT 也需反推 elemType="int" — 递归回填 | Phase 3 测试 `tests/d142_array_literal_inference/nested.ss`(`takesNested(arr: Array<Array<int>>)` + `[[1,2],[3,4]]`)| 嵌套反推失败 → 内层 ARRAY_LIT fallback 单层 + 用户嵌套时仍需显式 RHS binding;参 D141 H3 嵌套 lambda OOD 范式 |
| H4 | 空数组反推无元素无来源 | `takesArr([])` 内无元素,反推必须从 callee `Array<int>` 直接取 elemType(不依赖元素 inferType)| Phase 3 测试 `tests/d142_array_literal_inference/empty_array.ss`(`takesArr([])` callee `Array<int>` 期望反推 elemType="int" + ss_newArray + 空数组无元素 emit) | 空数组反推失败 → genArrayLit 内 elemList="" 路径走默认 ss_newArray (i64) fallback,反推 elemType slot 未消费 → 修 genArrayLit 优先读节点 elemType slot |
| H5 | interface upcast 反推得接口类型,vtable indirect dispatch 走 D025 路径 | `takesShapes([new Square(2.0), new Circle(3.0)])` callee `Array<IShape>`,反推得 elemType="IShape" + Square/Circle implements IShape,arr.area() 走 vtable indirect | Phase 3 测试 `tests/d142_array_literal_inference/interface_upcast.ss`;参 D141 H5 interface upcast 同模式 | interface upcast 失败 → 回 Phase 2 修 vtable 路径 |
| H6 | 显式注解优先级 > 推断 | 用户写 `let arr: Array<int> = [1,2,3]; takesArr(arr)` 时,RHS 推断走 gen_decls.ss:566-571 既有路径(arr varType="Array<int>");fn 实参传 arr(IDENT)反推 skip(arr 不是 ARRAY_LIT)| Phase 2 反推条件判断 `if (nGetKind(argId) == "ARRAY_LIT")` 限定;Phase 3 测试 `tests/d142_array_literal_inference/explicit_override.ss` 显式注解仍走原路径;参 D141 H6 显式优先粒度 | 显式优先级失败 → 回 Phase 2 修条件判断 |
| H7 | tests/ 264/4/268 baseline 不降 | 全项目现有 array literal 测试 60+ 都走显式注解 / RHS binding — Phase 2 反推不影响显式路径(H6 显式优先);Phase 4 cleanup 仅临时变量绑定形态 | Phase 2 后跑 `bin/ss test tests/` 全跑 + baseline 比 | tests/ 红 → 回 Phase 2 修条件判断或 fallback 路径;参 D141 H7 同范式 |
| H8 | reflection_health_linter GATE 不破 | checker / codegen / eval 三层改 — 是否破反射路径 14 指标(M1-M7b + N1-N5)| Phase 2 后跑 `bin/ss run tools/reflection_health_linter.ss` GATE PASS | GATE BLOCK → 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段);参 D141 §扩容申报-Phase2-G1 + §扩容申报-Phase3 范式 |
| H9 | var binding callee 反推 OOD scope(D141 H9 同模式)| `const f = takesArr; f([1,2,3])` callee="f" 是 var binding 不在 funcParamTypes,反推 skip | **D141 H9 已锁 var binding callee OOD scope**,D142 同模式继承 — 主线场景是 method call(`tmpl.exec([1,2,3])`)/ fn call(`takesArr([1,2,3])`),callee 是 mangled method 名 / 函数名在 funcParamTypes,不受影响 | var binding 不支持反推 → 用户 var binding 时仍需显式 RHS binding,不影响 D142 主线 cleanup |
| H10 | genArrayLit codegen 内 inferType(elemId) 链路自然走通(D141 H10 同模式)| `gen_calls.ss:643/711 inferType(elemId)` 当前依赖元素表达式自身推断 — 单元素正常,空数组 fallback 默认 i64,异质混合元素 fallback 第一元素;Phase 2 反推回填 ARRAY_LIT elemType slot 后,genArrayLit 优先读节点 elemType slot,不依赖元素 inferType | **核心修复链**:ARRAY_LIT elemType slot 一旦回填,genArrayLit hasPtrElem/hasScalarElem 判定 + arrCtor 选择 + emitValueToI64 box 路径自然走通;**不需另外加路径调整**,gen_calls.ss line 643/711 改成优先读节点 elemType slot 即可 | 修复链断 → 回 Phase 2 检查 elemType slot 命名是否与 inferType 调用方一致 |
| H10 实证(Phase 1)| **✓ 同模式 PASS** — `bootstrap/eval/array_lit.ss:4-19` evalArrayLit 入口:line 5 `nGetList(astId)` + line 13-19 `for (ap in arrParts) { const ev = ... ? genVal(nGetI1(elemId)) : genVal(elemId); ... }` —— **`genVal(elemId)` 在 line 16 在 arrPreRegs 缓存(line 48 `arrPreRegs = new Map()`)+ genArrayLit 调用(line 60)之前**;一旦进入 evalArrayLit 内,元素已被 genVal 求值 + 反推时机已过;`bootstrap/eval/method_call.ss:4-120 evalMethodCall` 含 args 循环 `genVal(argId)` 路径,`bootstrap/eval/call.ss` 同形 — **反推必须前移到这两处的 args 循环**,识别 ARRAY_LIT 子节点 + 查 funcParamTypes + 反推回填 ARRAY_LIT 节点 elemType slot + 后续 evalArrayLit 走原路径自然消费(genArrayLit line 643/711 改成优先读节点 s2 slot,不破 elemList 既有遍历)| `bootstrap/parse/parse_exprs.ss:496-498` `newNode("ARRAY_LIT") + nSetList(id, elems)` — 仅 nList 占,s1/s2/s3/i1-i4 全空;Phase 2 选 **nSetS2 存 elemType**(与 ARROW_FUNC 返回类型 PARAM s2 同范式 — D141 nSetS2 PARAM 节点回填类型,D142 nSetS2 ARRAY_LIT 节点回填 elemType,符号 mangling 完全同形)| 修复链断 → 回 Phase 2 检查 nSetS2/nGetS2 命名一致 + outer call site args 循环识别 ARRAY_LIT 完整路径 |
| H11 | callee PARAM `Array<T>` 字符串已结构化,无需 G1 callee 升级(比 D141 H11 弱) | D141 G1 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn` → `setter: fn(PreparedStatement):void`(parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析);D142 callee `Array<T>` 已结构化(lib/sort.ss 18 处 / lib/url.ss / tests/d134_mysql 等 40+ 处),反推可直接消费 funcParamTypes Array<T> 字符串 | grep 实测 `lib/sort.ss` Array<int> 18 处 + `lib/url.ss:244` URL_encodeQuery + 其他 lib 40+ 处 callee PARAM 已结构化;Phase 2 反推 helper extractArrayElemType("Array<int>") = "int" 直接消费 | callee 升级路径破裂 → 反推失败 silent skip(非结构化 callee 走 H13 同形 skip 不破);参 D141 H13 粒度 |
| H12 | parser 不需要扩(比 D141 H12 弱)| D141 H12 必须 parseTypeAnn IDENT "fn" + LPAREN 分支扩 fn 类型 annotation 解析;D142 Array<T> 类型 annotation 已就绪(parser.ss:792-793 嵌套 generic `Array<Array<Tag>?>` 已就绪)| Phase 1 grep 实测 + Phase 2 不动 parser | parser 未就绪(若实测发现某些边界形态未支持)→ 回 Phase 2 评估扩 parser 必要 — 大概率不需要 |
| H13 | 反推失败硬错粒度(D141 H13 同模式)— 结构化 callee 硬错 / 非结构化 callee skip | **结构化 callee**(funcParamTypes 含 `Array<T>`):extractArrayElemType 取不到 → `codegenError` 硬错;**非结构化 callee**(funcParamTypes 仍是 "Array")→ 反推 skip(不破现有 `Array` 单一字符串调用方)| Phase 2.2 实测 helper extractArrayElemType + Phase 4 cleanup 删 typed 注解后,untyped array literal 走结构化反推 | 硬错粒度过严 → tests/ break → 调整粒度为 silent skip + warn(参 D141 H13 调整路径)|

---

## A.3 废案

- **C1 数据层 patch 全废**(零散 fallback,不消除根因 — 与 D141 §A.3 同形)
- **C3 架构层 refactor 全废**(scope 爆炸,远超 D142 单 sub-D)— **D141 §Followup F5 已锁此候选废留 SS 类型系统 v2 评估**
- **C4 编译期 lint 警告强制用户加 RHS binding**(被动 — 用户每写 array literal 必先 binding,违反 CLAUDE.md §编译器吸收复杂度)
- **C5 全 array literal 默认元素类型 i64**(silent miscompile — 异质混合 / interface upcast / 嵌套 array 全场景错位)
- **G2 callsite 双向反推全废**(漏空数组 + fn binding + 异质混合 3 类边界 — §A.1.1 G2 行)
- **G3 接受 gap 全废**(反推机制空转 0% 解决度,违反 `feedback_root_cause_no_cost.md` 红线)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `3fb3ea2` (2026-04-27)

- 本文档落档 + Status / 核心目标 / 核心原则 / Context / Tools / Orchestration / State / Evaluation / Constraints / §A.1 主候选 + §A.1.1 实施路径 + §A.2 隐藏假设 / §A.3 废案 / Phase 0-5 计划草案
- d_doc_index_linter F1 = 0 验证 PASS(D142 加入未破 referenced Ds — D141/D025/D131 实存,F2 soft warn 15 orphan 含 D142 不阻 commit)
- next_prompt_ultrathink_linter PASS 3/3(本轮 .claude/next_prompt.md 含 ultrathink 关键字)
- VCM 六验(Plan 型):§① 跳过(diff=0 in bootstrap/lib/tools)+ §④ 替换为「替代方案对比 + 隐藏假设挑战」§A.1+§A.1.1+§A.2 ✓

### Phase 1: RED 复现 + 信息源探查 [✓] Done at commit `eb26644` (2026-04-27)

- 写 `/tmp/spike_array_lit_untyped.ss` + `/tmp/spike_array_lit_typed.ss` + `/tmp/spike_array_lit_red.ss` 三 spike;形态 1-5(单元素 / 多元素同质 / 空数组 / 嵌套 / interface upcast)untyped 行为 GREEN(元素 inferType 自身可推 — int literal/class instance/inner ARRAY_LIT 全可推);**形态 6/7(空数组 + callee `Array<IShape>`)RED 铁证**:`bin/ss run /tmp/spike_array_lit_red.ss` LLC error `'%1' defined with type 'ptr' but expected 'i32'`(method dispatch 入口 elemType="Array" 漏 → `arr.length` 路径走错)+ IR `%5 = call ptr @ss_newArray(i32 0)` ⚠️ silent fallback scalar(空数组无元素 inferType 来源 → 应反推 callee Array<IShape> elemType="IShape" 走 ss_newArrayPtr)
- IR 层对比 typed/untyped 双路径完成:形态 1-5 两版本 IR 路径完全一致(typed `let a5: Array<IShape> = [new Square(2.0), new Circle(3.0)]; takesShapes(a5)` 与 untyped `takesShapes([new Square(2.0), new Circle(3.0)])` 同走 `ss_newArrayPtr(i32 2)`),反推机制必要性在**空数组 + interface 期望 ptr** + **method dispatch 入口结构化必要**两点暴露
- **§A.2 H1 同模式实证 PASS**:`codegen.ss:110 funcParamTypes.set(\`${fname}:${pCount}\`, nGetS2(fpId))` + `codegen.ss:326 registerAllDecls` 在 `emitGlobalsAndCode` 之前调 — codegen 阶段满载用户函数 + class method funcParamTypes,Array<T> 字符串原样注册;Phase 2 反推 helper `extractArrayElemType("Array<int>") = "int"` 直接消费,无 callee 升级前置(比 D141 G1 更轻)
- **§A.2 H10 同模式实证 PASS**:`eval/array_lit.ss:13-19` `genVal(elemId)` 在 line 16 在 arrPreRegs 缓存(line 48)+ genArrayLit(line 60)之前 — 反推必须前移到 outer call site `eval/method_call.ss + eval/call.ss` args 循环
- **ARRAY_LIT 节点 slot 探查 PASS**:`parse_exprs.ss:496-498` `newNode("ARRAY_LIT") + nSetList(id, elems)` — 仅 nList 占,s1/s2/s3/i1-i4 全空;Phase 2 选 **nSetS2 存 elemType**(与 ARROW_FUNC 返回类型 PARAM s2 同范式)
- ARRAY_LIT kind dispatch site 全 grep 完成:`check_types.ss:50` + `check_class.ss:33` 双破裂入口确认(Phase 2 同步改返结构化)+ `gen_decls.ss:67` + `gen_types.ss:542` + `check_exprs.ss:281` + `exprs.ss:68` + `interp_obj.ss:182` 各非破裂消费 site 路径分类,Phase 2 仅改前两 + 反推插桩 codegen 路径(`gen_calls.ss:resolveCallArgs` + `gen/methods/method_call.ss`)+ eval pre-eval 前移(`eval/method_call.ss + eval/call.ss`)
- §1 必读清单补 `bootstrap/gen/codegen.ss:100-122` + `bootstrap/gen/gen_registry.ss:19-25 + 67-72` + `bootstrap/eval/array_lit.ss:4-19 + 48-60` + `bootstrap/parse/parse_exprs.ss:496-498` + `/tmp/spike_array_lit_untyped.ss` + `/tmp/spike_array_lit_typed.ss` + `/tmp/spike_array_lit_red.ss` 7 个锚
- §A.2 H1 实证 + H10 实证 双行入档(实证标 `✓ 同模式 PASS`)

### Phase 2: codegen 阶段反推实施 + G1 路径(D141 G1 同模式复刻)[✓] Done at commit `781d0d5` (2026-04-27)

- `check_types.ss:50` ARRAY_LIT inferType 改返 `Array<elemType>` 结构化(与 ARROW_FUNC line 51-71 同形 + 优先读节点 nGetS2 / 元素同质推断 / 全空 / 异质 / SPREAD 降级 "Array")
- `check_class.ss:33` 评估**保持不改** — `inferCheckerClass` 是 method dispatch 入口走 base name 仍正确,改 `Array<X>` 反破 `lookupMethodRetType`(本 Phase 实证决策)
- `check_types.ss isTypeCompatible` 评估**不需扩** — line 240-244 generic base 比对已覆盖 `Array<X>` ↔ `Array` 兼容,反推后 actual=`Array<X>` 与 declared=`Array<Y>` 通过 base 比对 PASS
- `gen_types.ss` helper 落锚 line 802-845:`isArrayType`(8 行)+ `extractArrayElemType`(11 行)+ `inferArrayLitElems`(13 行 — 对偶 D141 isFnType / extractFnParamType / inferArrowFuncParams)
- `gen_calls.ss:279 resolveCallArgs` + `gen/methods/gen_methods.ss:202 emitClassMethodCall` 内 args 循环识别 ARRAY_LIT + 调 `inferArrayLitElems(argId, typeCallee, argIdx)` 反推回填(D141 G1 4 落点同模式复刻)
- `eval/method_call.ss:61 + eval/call.ss:33` pre-eval 之前反推前移(D141 H10 同模式)
- `gen_calls.ss:631-731 genArrayLit` 改:开头读 `nGetS2(id)` 拿反推 elemType + 反推优先 hasPtr/hasScalar 选择 + 两处 emitValueToI64 elemType 反推优先(异质混合 / interface upcast / fn 元素 / 空数组场景生效;H6 显式优先 — 用户显式 `let arr: Array<int> = [...]` 走 RHS 推断 gen_decls.ss:566-571 不走反推路径)
- 反推 IR 因果实证:`/tmp/spike_array_lit_d142_green.ss` 形态 C(`lenShapes([])` 空数组 + Array<IShape>)— 反推前 IR `ss_newArray(i32 0)` ⚠️ silent fallback scalar / 反推后 IR `ss_newArrayPtr(i32 0)` ✓(对照 stash + ./build.sh bootstrap 重 build 双向实测,line 5490)
- spike 形态 A/B/D 行为不变(元素 inferType 自身可推 — 形态 1-5 baseline 一致 GREEN)
- VCM 验证:bootstrap 三阶段固定点 PASS + tests 264/4/268(baseline 不降,4 失败均预存 — spring_web_params / harness_task / d096_p4_l2_reactive / harness_bug,与 D142 反推无关)+ tests/d141_lambda_inference/ 5/0/5 不破 + reflection_health GATE PASS(扩容申报-Phase2 bump 3 处 F1 budget_max — gen_methods 722→726 / gen_calls 718→740 / gen_types 873→915)+ d142_green spike 形态 A-D 全 GREEN(a=6 / b=0 / c=0 / d=32.26)
- LOC delta 实测 +91(预估 ≤ 250,远低 §Constraints 800 LOC 上限) — 6 文件改:check_types.ss +23 / gen_types.ss +39 / gen_calls.ss +29 / gen_methods.ss +2 / eval/call.ss +2 / eval/method_call.ss +2

### Phase 3: 测试覆盖 + 隐藏假设挑战 [✓] Done at commit `<TBD>` (2026-04-27)

- 6 测试用例落锚 `tests/d142_array_literal_inference/`(Phase 3 实施 6/0/6 全绿,无 Phase 2 兑现漏点 — Phase 2 G1 路径 codegen 反推 + ARRAY_LIT 节点 nSetS2 回填路径完整覆盖 H1-H6 全场景):
  - `untyped_single.ss` — H1 单元素反推 `takesArr([1])` callee `Array<int>` → 节点 nSetS2="int" + ss_newArray(i32 1) + i64 box GREEN → r=1
  - `untyped_multi.ss` — H2 多元素同质反推 `takesArr([1, 2, 3])` → 节点 nSetS2="int" + ss_newArray(i32 3) + 3x i64 box GREEN → r=6
  - `nested_array.ss` — H3 嵌套 `Array<Array<int>>` 反推 capture 链 `takesNested([[1,2],[3,4]])` → 外层 nSetS2="Array<int>" + ss_newArrayPtr(i32 2) + 内层 ARRAY_LIT 递归反推 nSetS2="int" + ss_newArray(i32 2) GREEN → r=10(R2 嵌套递归回填路径实证生效,无需 fallback 单层)
  - `empty_array.ss` — H4 空数组反推无元素来源 `takesArr([])` → 节点 nSetS2="int"(callee Array<int> 直接取 elemType,不依赖元素 inferType)+ ss_newArray(i32 0) GREEN → r=0(R3 反推不依赖元素来源路径实证 — 反推前 silent fallback scalar / 反推后 callee 端直供 elemType)
  - `interface_upcast.ss` — H5 `Array<IShape>` interface upcast vtable indirect dispatch `takesShapes([new Square(2.0), new Circle(3.0)])` → 节点 nSetS2="IShape" + ss_newArrayPtr + arr.area() 走 D025 vtable indirect GREEN → r=32.26(4.0 + 28.26;Square Circle 各 implements IShape)
  - `explicit_override.ss` — H6 显式注解 > 推断 `let arr: Array<int> = [1,2,3]; takesArr(arr)` → IDENT 走原 RHS 推断 gen_decls.ss:566-571 路径(arr varType="Array<int>")+ fn 实参传 arr 是 IDENT 反推 skip,既有显式路径不破 → r=6
- VCM 六验全 PASS:
  - `./build.sh bootstrap` 三阶段固定点 stage2==stage3 ✓
  - `bin/ss test tests/d142_array_literal_inference/` 6/0/6 全绿 ✓
  - `bin/ss test tests/d141_lambda_inference/` 5/0/5 不破 ✓
  - `bin/ss test tests/` 270/4/274 baseline 不降(Phase 2 baseline 264/4/268 + 6 D142 = 270/4/274,4 失败均预存与 D142 反推无关:spring_web_params / harness_task / d096_p4_l2_reactive / harness_bug)✓
  - `bin/ss run tools/reflection_health_linter.ss` GATE PASS no regressions(F1 全 PASS — Phase 2 已申报扩容覆盖)✓
  - `bin/ss run tools/d_doc_index_linter.ss` PASS:10 referenced Ds all live ✓
- §A.2 隐藏假设挑战实证:
  - H1 ✓(Phase 1 实证 — funcParamTypes Array<T> 字符串 codegen 阶段满载)
  - H2 ✓ untyped_multi(同质 [1,2,3] 反推 elemType="int" 与元素 inferType 一致,r=6)
  - H3 ✓ nested_array(嵌套 [[1,2],[3,4]] 内层 ARRAY_LIT 递归反推 nSetS2="int",r=10 — R2 嵌套回路无需 fallback)
  - H4 ✓ empty_array(空数组 [] 反推 elemType="int" 不依赖元素来源,r=0 — R3 callee 端直供路径)
  - H5 ✓ interface_upcast(Square + Circle vtable indirect 32.26 — R4 D025 路径不破)
  - H6 ✓ explicit_override(IDENT 反推 skip,既有显式路径不破)
  - H7 ✓ baseline 不降 270/4/274
  - H8 ✓ reflection GATE PASS no regressions
  - H9 — var binding callee OOD scope 标(D141 H9 同模式继承,主线场景 method/fn callee 在 funcParamTypes,不影响 D142 主线 cleanup)
  - H10 ✓(Phase 1 实证 — eval pre-eval 之前 outer call site 反推前移)
  - H11/H12 ✓(Phase 1+2 实证 — callee `Array<T>` 已结构化 + parser 已就绪,无 callee 升级 + 无 parser 扩前置)
  - H13 ✓(D141 H13 同模式 — 结构化 callee 走反推 + 非结构化 callee skip 不破)

### Phase 4: workaround cleanup [ ]

- grep 实测 fn 实参 array literal 临时变量绑定 workaround(`let arr: Array<int> = [...]; takesFn(arr)` 形态)— 范围限定 lib/ + tests/d134_mysql/(D141 cleanup 同域)
- cleanup 删除(若有)+ 业务路径 untyped 直接传 GREEN
- VCM 六验全 PASS:bootstrap 固定点 + tests/ baseline 不降 + tests/phase5/array_*.ss 不降 + tests/d142_array_literal_inference/ 6 处全绿

### Phase 5: 全 Phase 收关 [ ]

- 5 Phase commit hash 全列(Phase 0/1/2/3/4 hash)
- 兑现成果 a-g(C2 接口层 trap 落地 / workaround cleanup / 隐藏假设全 PASS / OOD 标 / axiom 红线 grep / d_doc_index F1 / reflection_health GATE)
- §Followup F1+ 锚明确(F1 留 D141 §F2/F3 object literal / ternary contextual typing 同模式扩 sub-D)
- D135/D136/D137/D140/D141 范式延续 — 每 Phase 独立 commit 大改档 + Status 收关 + commit hash 回填

---

## 扩容申报-Phase2

> Phase 2 G1 路径实施触发 3 处 F1 budget_max 越界,均为非反射路径(M/N 含 SCOPE-DRIFT 软警告但 diff 未触白名单,无 BLOCK)。新加 helper / 反推机制自然增量,跑 `bin/ss run tools/reflection_health_linter.ss` GATE BLOCKED 3 file。按 `docs/3-MNK.md §特定领域 §反射路径根因 gate B 路径` + D142 §A.2 H8 实证锚走扩容申报。

| 文件 | budget_max(旧)| cur(新)| delta | 增量内容 |
|------|----------------|---------|-------|----------|
| `bootstrap/gen/methods/gen_methods.ss` | 722 | 724 | +2 | Phase 2 emitClassMethodCall args 循环 inferArrayLitElems 反推一行 + 注释 一行 |
| `bootstrap/gen/gen_calls.ss` | 718 | 737 | +19 | Phase 2 resolveCallArgs 内 inferArrayLitElems 反推 ~3 行 + genArrayLit 优先读节点 nGetS2 重写 hasPtr/hasScalar 选择 + 两处 emitValueToI64 elemType 反推优先 ~16 行 |
| `bootstrap/gen/gen_types.ss` | 873 | 912 | +39 | Phase 2 新加 helper:`isArrayType`(8 行)+ `extractArrayElemType`(11 行)+ `inferArrayLitElems`(13 行)+ section header / 注释 ~7 行 |

申报理由:G1 路径根因 100%(callee PARAM 已结构化签名 SSoT 复用 + ARRAY_LIT 节点 nSetS2 单点回填),反推机制单点信息源,信息丢失消除;非反射路径触碰(M2/M4/N2/N3 SCOPE-DRIFT 软警告,diff 未触白名单);F1 增量纯结构化新功能码,无样板压注释/合并空行/字符级绕过。`feedback_600_split_not_inline.md` + `feedback_structure_not_linecount.md` 拆分判据是结构清晰(职责单一 / 依赖单向),gen_types.ss 已是类型工具集中处,array literal helper 入此族符合结构归类(对偶 D141 isFnType / extractFnParamType / inferArrowFuncParams);后续若 gen_types.ss 拆分按职能(类型推断 / 类型签名 / fn helper / array helper)再切。

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | object literal contextual typing | `{ name: "X", age: 18 }` 在 fn 实参 `class User` 时反推字段类型 — D141 §Followup F2 同模式锚,留 D143+ sub-D |
| F2 | ternary contextual typing | `cond ? a : b` 在 fn 实参 `Maybe<int>` 时反推分支类型 — D141 §Followup F3 同模式锚,留 D144+ sub-D |
| F3 | array method first-class param 反推 | `arr.filter((x) => x > 0)` lambda 参数从 array elemType 反推 — D141 反推机制 + D142 elemType 联动 sub-D |
| F4 | bidirectional type checking 全局 | C3 候选废案,留作未来 SS 类型系统 v2(D026/D027 落地后再开 D 文档)— D141 §Followup F5 同位 |
| F5 | Map literal contextual typing | `{ "k": "v" }` Map literal 在 fn 实参 `Map<string,string>` 反推 — array literal 同模式 sub-D |
| F6 | Tuple literal contextual typing | tuple literal 在 fn 实参 `Tuple<int,string>` 反推 — array literal 同模式 sub-D |

---

## Status 时间线

- 2026-04-27 Phase 0 D 文档落档(commit `3fb3ea2`)— D141 §Followup F1 array literal contextual typing 候选入口落档;C2 接口层 trap + G1 D141 同模式复刻路径决策(待 Phase 1 用户对话锁定方向后启动实施);§A.1 三主候选 + §A.1.1 三实施路径 + §A.2 H1-H13 隐藏假设挑战 + §A.3 废案 + Phase 0-5 计划草案 + Followup F1-F6;D135/D136/D137/D140/D141 范式延续(每 Phase 独立 commit 大改档 + Status 收关 + commit hash 回填 + next_prompt 自闭环)
- 2026-04-27 Phase 3 测试覆盖 + 隐藏假设挑战(commit `<TBD>`)— 6 测试用例落锚 `tests/d142_array_literal_inference/` 全绿(untyped_single H1 + untyped_multi H2 + nested_array H3 + empty_array H4 + interface_upcast H5 + explicit_override H6);§A.2 H1-H8 实证标 PASS(H1/H10 Phase 1 已实证 + H2-H6 Phase 3 测试实证 + H7 baseline 不降 + H8 reflection GATE PASS)+ H9 var binding callee OOD scope 标(D141 H9 同模式继承)+ H11/H12/H13 Phase 1+2 已实证;Phase 2 G1 路径 codegen 反推 + ARRAY_LIT 节点 nSetS2 回填路径完整覆盖 H1-H6 六场景,无 Phase 2 兑现漏点 — D141 Phase 3 同模式简化(D141 Phase 3 实施时 Phase 2 漏点 4 处合并入 commit;D142 Phase 2 G1 同模式更彻底覆盖完整,Phase 3 仅写测试无代码改);VCM 六验全 PASS(bootstrap 固定点 + 6/0/6 + d141 5/0/5 + 270/4/274 baseline 不降 + reflection GATE PASS + d_doc_index 10 referenced Ds all live)— D135/D136/D137/D140/D141 范式延续
- 2026-04-27 Phase 2 codegen 阶段反推实施(commit `781d0d5`)— G1 D141 同模式复刻完结:`check_types.ss:50` ARRAY_LIT inferType 返 `Array<elemType>` 结构化(优先读节点 nGetS2 + 元素同质推断 + 全空 / 异质 / SPREAD 降级 "Array";`check_class.ss:33` 评估保持不改 — method dispatch 入口走 base name);`gen_types.ss:802-845` 三 helper(`isArrayType`/`extractArrayElemType`/`inferArrayLitElems`)对偶 D141 isFnType/extractFnParamType/inferArrowFuncParams;`gen_calls.ss:279` + `gen/methods/gen_methods.ss:202` + `eval/method_call.ss:61` + `eval/call.ss:33` 4 落点反推插桩(D141 G1 同模式复刻);`gen_calls.ss:631-731 genArrayLit` 优先读节点 nGetS2(空数组 + interface upcast + fn 元素 + 异质混合场景生效);IR 因果实证 `lenShapes([])` 反推前 `ss_newArray(i32 0)` ⚠️ → 反推后 `ss_newArrayPtr(i32 0)` ✓(stash + rebootstrap 双向对照);VCM PASS(bootstrap 三阶段 + 264/4/268 baseline 不降 + d141 5/0/5 不破 + reflection_health GATE PASS — 扩容申报-Phase2 bump 3 处 F1: gen_methods 722→726 / gen_calls 718→740 / gen_types 873→915);LOC delta 实测 +91(6 文件)— D135/D136/D137/D140/D141 范式延续
- 2026-04-27 Phase 1 RED 复现 + 信息源探查(commit `eb26644`)— `/tmp/spike_array_lit_red.ss` 形态 6/7 RED 铁证(空数组 + callee Array<IShape> → IR `%5 = call ptr @ss_newArray(i32 0)` ⚠️ silent fallback scalar + LLC error type mismatch);H1 同模式实证 PASS(funcParamTypes Array<T> 字符串 codegen 阶段满载 — `codegen.ss:110-112` + `gen_registry.ss:56-57` + `codegen.ss:326 registerAllDecls`);H10 同模式实证 PASS(`eval/array_lit.ss:13-19` `genVal(elemId)` 在 arrPreRegs 缓存 + genArrayLit 之前 — 反推必须前移到 outer call site evalMethodCall/evalCall args 循环);ARRAY_LIT 节点 slot 探查 PASS(`parse_exprs.ss:496-498` 仅 nList 占,Phase 2 用 nSetS2 与 ARROW_FUNC PARAM s2 同范式);Phase 2 入口锁 codegen 阶段反推 + checker 双破裂入口同步改(`check_types.ss:50` + `check_class.ss:33` 返 `Array<elemType>` 结构化)— D141 G1 同模式复刻范式延续
