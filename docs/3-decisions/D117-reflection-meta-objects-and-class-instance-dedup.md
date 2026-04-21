# D117: 反射 Meta 对象完整化 + class instance dedup 设计 — Phase B 延展

**Status:** Plan ⏳(Execute 0-2 Done 2026-04-21 / Execute 3-5 未开工)
**Depends on:** D088 §第一性需求(obj.fields() + obj[name]) / D093 §决策(evalExpr 单函数 dispatch) / D097 §后续工作 1-4(五类 Meta + evalExpr 扩展 + Meta 数组通用 iteration + L2ζ-L2κ Map migrate) / D098 §决策 2 §Phase B L123-128(Meta 对象/反射迁移后引入 InternPool) / D111 §新张力 5 L455(Meta 对象 dedup 前置 class instance dedup 设计,留 D113+)/ D094 §规则 2(pure subset 白名单)/ D096 Phase 4 L1(comptime class 能在 runtime 实例化)
**Date:** 2026-04-21

---

## 第一性需求

D088 §第一性需求 "给定一个对象,遍历它的字段名和值" + D093 §决策 "evalExpr 单函数 dispatch" + D097 §后续工作 "五类 Meta + evalExpr MEMBER_ACCESS 扩展" 联合要求:反射路径**不是**独立 kind 分支 / interp_* 扩展 / sidecar Map 累积,而是**普通 Meta 对象字段访问走同一 evalExpr MEMBER_ACCESS**。

**否定证据**:不做 → 反射 Meta 路径永远走 `interpCollectFields` 字符串拼接 + split / `interpCtFieldsArray` 字符串数组,无法走 evalExpr MEMBER_ACCESS → D088 §第一性需求不可达;D098 §Phase B L123-128 承诺"Meta 对象/反射迁移后引入 InternPool"后半阙永不兑现 → Value.eql 仍 O(Map) 深比较 → Phase C 度量基线无建 → D088 §正模式"main dispatch + 子分析器分层 Zig sema.zig 同构" 反射路径永是"子支路"不是"主线"。

## 当前事实(2026-04-21 snapshot)

**已有**:
- `bootstrap/parse/prelude.ss:19-27` — `FieldMeta { name, type }` + `AnnotationMeta { name, args }` 2 类定义(D097 §后续工作 1 完成 2/5)
- `bootstrap/eval/interp_obj.ss:122-124` — `interpBuildTypeInfo(typeName): int` **占位实现** `return newTvNull()`
- `bootstrap/eval/interp_obj.ss:126-140` — `interpCollectFields(className): string` 返 `"field1,field2,..."` 字符串拼接
- `bootstrap/eval/interp_obj.ss:148-161` — `interpCtFieldsArray(className): int` 返字符串数组(不是 FieldMeta 实例数组)
- `bootstrap/eval/member_access.ss` + `bootstrap/gen/exprs/exprs_ct_obj.ss` — MEMBER_ACCESS 走 ct 路径但**不识别** Meta 对象字段读
- `bootstrap/gen/stmts/stmts_loop_forin.ss` — genForIn 对反射 Meta 数组走**专用分支**(hardcoded kind 分支)
- **Phase B InternPool 5 标量 dedup Done**(D111 Execute 2 commit `32a8f6d`)—— Meta 对象 dedup **未启**

**缺失**:
- `ClassMeta` / `MethodMeta` / `ParamMeta` 3 类定义
- `interpBuildTypeInfo` 实际实现(构造 ClassMeta 实例含 `fields: Array<FieldMeta>` + `methods: Array<MethodMeta>` + `annotations: Array<AnnotationMeta>`)
- `evalExpr` MEMBER_ACCESS 识别 Meta 对象字段(返 MaybeVal.known=true)
- Meta 数组通用 iteration(genForIn 走 evalExpr fold,不走反射专用分支)
- **class instance dedup 设计**(D111 §新张力 5 前置,本 Plan §决策 3 承载)

## 决策(分 5 §,§决策 1-2 类定义与实现,§决策 3 dedup 前置,§决策 4-5 求值与 iteration 统一)

### §决策 1 — 补齐 5 类 Meta 定义

`bootstrap/parse/prelude.ss:19-27` 后追加 3 类:

```ss
class ClassMeta {
    name: string
    fields: Array<FieldMeta>
    methods: Array<MethodMeta>
    annotations: Array<AnnotationMeta>
}

class MethodMeta {
    name: string
    params: Array<ParamMeta>
    returnType: string
    annotations: Array<AnnotationMeta>
}

class ParamMeta {
    name: string
    type: string
}
```

**语义**:5 类 = D097 §后续工作 1 "comptime reflection carrier classes" —— 由编译器在反射路径上实例化,用户代码通过 MEMBER_ACCESS 访问字段。

### §决策 2 — interpBuildTypeInfo 从占位到实现

当前 `bootstrap/eval/interp_obj.ss:122-124`:

```ss
function interpBuildTypeInfo(typeName: string): int {
    return newTvNull()
}
```

改为:构造 ClassMeta 实例,依赖 §决策 3 name-based dedup:

```ss
function interpBuildTypeInfo(typeName: string): int {
    // §决策 3 name-based dedup: InternPool key = "CLS|<typeName>"
    //   若 pool hit → 返已有 ClassMeta id
    //   否则构造:
    //     fields = interpCtFieldsArray(typeName) 改返 FieldMeta 数组
    //     methods = 新 interpCtMethodsArray 返 MethodMeta 数组
    //     annotations = 查 classAnnotations Map 返 AnnotationMeta 数组
    //   internPoolGetOrInsert("CLS|" + typeName, classMetaId)
    ...
}
```

### §决策 3 — class instance dedup 设计(Phase B 前置)

**方案对比**(5 方案,选 A):

| 方案 | 策略 | 性能 | 实现成本 | 选否 |
|---|---|---|---|---|
| **A: name-based dedup** | ClassMeta key = className;FieldMeta key = className+"."+fieldName;依此类推 | O(1) lookup + 清晰语义 | 最低(prelude.ss 不改;InternPool key 约定即可) | **选**(Phase B 起步) |
| B: structural hash | Meta 全字段序列化 + sha256 | O(字段数) 构造 + O(1) lookup | 中(需序列化访问器) | 否(Phase C 备选) |
| C: 不 dedup | 每次 interpBuildTypeInfo new 新 class | O(1) 构造 + O(字段数) eql 深比较 | 零 | 否(D098 §Phase B 收益不可达) |
| D: trait-based eq | Meta class 覆写 equals() | O(字段数) eql | 中 | 否(违 D093 单 dispatch) |
| E: hash-cons | 构造时查 pool hit 则复用 | O(字段数) hash + O(1) lookup | 高 | 否(等效 B,InternPool 原理) |

**选 A 理由**:D097 §后续工作 1 L77 "五类 comptime reflection carrier classes" 原意即 **name-keyed** —— className / fieldName / methodName 本就是自然唯一键。方案 A = **键语义天然 + 零实现成本 + 覆盖 D098 §Phase B O(1) eql**(`cls1.eql(cls2)` 退化为 `pool_id(cls1) == pool_id(cls2)` == `"CLS|"+n1 == "CLS|"+n2`)。

**Meta key 约定**(InternPool 扩):
- `CLS|<className>` — ClassMeta
- `FLD|<className>.<fieldName>` — FieldMeta
- `MTH|<className>.<methodName>` — MethodMeta
- `PRM|<className>.<methodName>.<paramName>` — ParamMeta
- `ANN|<ownerKey>.<annotationName>` — AnnotationMeta(ownerKey = CLS/FLD/MTH key)

复用 D111 §决策 1 `internPoolGetOrInsert(key, valueId)` + D111 §决策 3 原串 `|` 分隔 key 设计,不引新机制。

### §决策 4 — evalExpr MEMBER_ACCESS on Meta

`bootstrap/eval/member_access.ss` 扩展识别:
- receiver 是 Meta 对象(ClassMeta/FieldMeta/MethodMeta/AnnotationMeta/ParamMeta 实例)→ 走**普通 field read**,查 `interpFields[receiverId][fieldName]` 返 MaybeVal.known=true
- receiver 非 Meta → 保留现有逻辑

**收益**:`for f in cls.fields { println(f.name + "=" + f.type) }` 编译期全部 fold,展开 N 次 MEMBER_ACCESS,不走 interpCollectFields 字符串路径。

### §决策 5 — Meta 数组通用 iteration

`bootstrap/gen/stmts/stmts_loop_forin.ss` 对 Meta 数组(cls.fields / cls.methods / cls.annotations / m.params / m.annotations / f.annotations)**不走 hardcoded kind 分支**,走通用 fold:
- iteration 目标是编译期常量 Array<Meta> → evalExpr 展开 N 次 MEMBER_ACCESS
- 与普通 array 字面量 iteration 共享同一 fold 路径(D097 §后续工作 3 兑现)

**D097 §第一性问题 根因消除**:L13-17 "每增加一种反射字段 +1 分支/Map/sidecar/调用点" 累积路径,从 "hardcoded" 变 "通用 fold"。

## Rejected Alternatives

### §A — 扩 interp_* 独立求值器(interpExpr* / interpStmt*)承载反射语义
违 D093 §Rejected A/C/D + D097 L21 明言 "唯一合规根因路径 = D093 §决策 evalExpr 单函数 dispatch"。

### §B — Meta 对象走 C struct 编码(保留 interpCollectFields 字符串路径)
违 D088 §第一性需求(obj.fields() + obj[name] 是结构化访问) + D097 §后续工作 1 "五类 comptime class,**不是** interp.ss 里的 typed-value struct"。

### §C — class instance dedup 方案 B/C/D/E
见 §决策 3 对比表。Phase B 起步选 A(name-based);B (structural hash) 留 Phase C 评估。

### §D — Meta 对象 InternPool 承载一次做完(合 Phase B/C)
违 D098 §决策 2 "渐进 Phase A → Phase B → (可选) Phase C"。本 Plan 只做 name-based dedup(InternPool key = name),InternPool 本体 Phase B 5 标量 dedup 已 Done(D111)可直接复用,零本体改造。

### §E — 不补齐 ClassMeta/MethodMeta/ParamMeta,只扩 interpBuildTypeInfo 返 Map<string, string>
违 D097 §后续工作 1 "五类 Meta" 明示要求;Map 是结构化 Zig 路线回退,Meta 对象走 class instance 才符合 D093 §SS 本质一样骨架。

### §F — class instance dedup 设计留给独立 D 文档(不合 D117)
D111 §新张力 5 明言 "Meta 对象 dedup 前置 class instance dedup 设计,留 D113+";D113-D116 被 codegen 拆分占未开工,本 Plan 承接是自然位置。独立 D 文档反增跨文档 scope 拉扯,不选。

## 新张力(D117 引出)

1. **prelude.ss 新增 3 class 触 reflection_health_linter M/N 累积** — class 定义 = M5 +N 字段 state + N1 可能 +1(若引入新 kind)。**对策**:Execute 轮 baseline 对照,§决策 5 通用 iteration 削减(删反射专用分支/删 interpCtFieldsArray 字符串数组/删 interpCollectFields 字符串拼接路径)必须抵消三加。**D097 L70 "累积方向严禁更新 baseline"** — 新加三类必须给出三删证据,不允许"调高 baseline 让 gate 过"
2. **Meta key 含 "." 分隔符可能与 className 冲突** — 若 className 含 "."(如 nested class)会碰撞。**对策**:Execute 0 先 grep `bootstrap/parse/parser.ss` 确认 SS className 是否允许 ".",若允许需换分隔符(如 `\0` 或 `|`)。**Execute 0 结论(2026-04-21):闭合** — `lexer.ss:418-426` `lexIdent()` 仅吃 `isAlphaNum(peek())`,`lexer.ss:163-169` `isAlpha=[A-Za-z_]` + `isDigit=[0-9]`,故 SS className 字符集 = `[A-Za-z_][A-Za-z0-9_]*` **不含 "."**,`CLS|<className>.<fieldName>` / `FLD|<className>.<fieldName>` / `MTH|<className>.<methodName>` / `PRM|<className>.<methodName>.<paramName>` / `ANN|<ownerKey>.<annotationName>` 5 条 key schema 全部**无冲突风险**,§决策 3 方案 A 无需换分隔符
3. **name-based dedup 限制 structural-different same-name** — 两个 class 字段完全不同但 className 相同(如用户跨 import 重定义)会被 dedup 成同一 Meta。**对策**:SS 当前不允许 class name 重复(checker 检查),本轮范围内非问题;未来允许时 D098 §Phase C 重评
4. **interpBuildTypeInfo 从 newTvNull() 占位到 ClassMeta 实现引发 M7b +1 + 调用链扩** — interpBuildTypeInfo 现为 3 行空函数,改成 ~20 行实际构造 M2 / N2 / M3a 全升。**对策**:§决策 5 通用 iteration 删 hardcoded 分支节省 M4 + M2 抵消,Execute 轮实测 delta 定。若单项紧张,Execute 拆多轮(Execute 1 先 prelude.ss 加 3 class / Execute 2 再改 interpBuildTypeInfo)
5. **Meta 对象生命周期 vs class instance RC** — Meta 对象是 InternPool 承载的常驻对象,不应走 Perceus RC drop。**对策**:Execute 3 时 interpBuildTypeInfo 构造的 ClassMeta 实例不进入 RC 管理(与 D111 InternPool 标量一致);若触 RC 路径需在 pir_lower.ss 加例外或 Meta class 不参与 RC 设计

## 下一步(Plan 下的 Execute 顺序)

1. [x] Done at docs/3-decisions/D117-*.md §新张力 2 对策段(2026-04-21) — **Execute 0**:预削减探底 + 新张力 2 (className 分隔符) 验证完成。**两项结论**:(a) 削减候选 **0 个** — `interpCollectFields` / `interpCtFieldsArray` 调用点共 9 处(真调用 5 处 + imports 2 处 + 定义 2 处,外加 tests 注释 1 处),全部在生产路径上,无"无争议死代码可立即删":`interp_obj.ss:126/148/152`(定义+内部紧耦合,Execute 5 整体删)、`member_access.ss:92`(`cls.fields` → Execute 3 MEMBER_ACCESS on Meta 迁走)、`exprs_ct_obj.ss:11`(实例构造父类字段枚举,**非反射路径**,Execute 5 需解耦至 `nGetList` 父类链直枚举)、`exprs_ct_obj.ss:54/64`(TypeValue/object `.fields()` 方法,Execute 3 迁走)、`interp_core.ss:15` + `exprs.ss:6`(import 转发,随函数删);§新张力 1 补偿证据由 Execute 5 整体删两函数 + 5 真调用迁移承载,**不是** Execute 0 先删。(b) §新张力 2 **闭合**,见该张力段末结论(`[A-Za-z_][A-Za-z0-9_]*`,无 "."),5 条 InternPool key schema 无冲突。**classXxxAnnotations Map** 13 处集中 4 文件(`member_access.ss` / `class/class.ss` / `stmts/stmts_loop_forin.ss` / `class/class_register.ss`),§决策 2 Execute 2 自然复用,无需 Execute 0 预删
2. [x] Done at bootstrap/parse/prelude.ss:30-47(2026-04-21)— **Execute 1**:补齐 ClassMeta / MethodMeta / ParamMeta prelude.ss 定义 + reflection_health_linter baseline 对照 **GATE PASS no regressions**。**实测 delta**(3 类加入 vs pre-delta):M2 +16 / N2 +80 / N3 +29,其余 10 指标全 0。vs baseline 全部在 tol 内(M1 +15/tol 25 / M2 +353/tol 380 / M3a +29/tol 60 / N2 +1765/tol 1903 DRIFT) + 结构组 strict 全 OK / N3 -1976 PROGRESS + F1 GATE PASS(gen_decls.ss 690→690 baseline=691 PROGRESS)。**§新张力 1 "三加必配三删"抵消证据由 Execute 4-5 承载**:Execute 4 删 stmts_loop_forin.ss 反射专用分支(§决策 5 通用 fold 迁移)+ Execute 5 删 interpCollectFields / interpCtFieldsArray 字符串路径。本 Execute 1 不动,因 Execute 0 L156 探底结论"削减候选 0,全部在生产路径"—— 删任一分支/函数必破 tests,§决策 4 evalExpr MEMBER_ACCESS on Meta 前置。bootstrap 固定点通过 + tests 215 passed / 4 failed (pre-existing: spring_web_params / d096_p4_l2_reactive / harness_bug / harness_task,vs commit `90091df` 相同,**无新回归**)。
3. [x] Done at bootstrap/eval/interp_obj.ss:122-130(2026-04-21)— **Execute 2**:interpBuildTypeInfo 最小化实现 4 行函数体(`interpNewVal("object", typeName)` 创 object-kind TV → 直 `tvMap.set("id|name", ...)` 绕 interpSetField 冗余层 → `internPoolGetOrInsert("CLS|"+typeName, id)` dedup)。**零 IF / 零新函数**(M4=0 strict PASS / M7b=0 strict PASS)。**实测 delta** vs baseline:M1 +15/tol 25 DRIFT / M2 +373/tol 380 DRIFT(剩 7 预算)/ M3a +32/tol 60 DRIFT / N2 +1865/tol 1903 DRIFT(剩 38 预算)/ N3 -1868 PROGRESS / 结构组 8 项全 0 OK / F1 全 OK(gen_decls.ss 690 PROGRESS)**GATE PASS no regressions**。**Execute 2 scope 范围内妥协**:.fields/.methods/.annotations 填充延至 Execute 3(member_access.ss on Meta 迁走 cls.fields/cls.annotations 特例分支后,自然由 evalExpr fold 填);本 Execute 仅保证 `.name` 走统一 interpGetField 路径 + dedup 承载 D098 §Phase B O(1) eql。RED→GREEN:`@typeInfo(Dog).name` 正确返 "Dog",bootstrap 固定点 + tests 215 passed / 4 failed (pre-existing,vs cc1624b 相同,无新回归)。**§新张力 4 對策兑现**:"若单项紧张,Execute 拆多轮" —— 本 Execute 拆成"最小实例 + dedup"独立递交,.fields/.methods/.annotations populate 下放 Execute 3-5 承载。
4. [ ] Planned — **Execute 3**:evalExpr MEMBER_ACCESS on Meta 识别(`bootstrap/eval/member_access.ss` 扩)+ 返 MaybeVal.known=true + pure subset 白名单扩
5. [ ] Planned — **Execute 4**:genForIn Meta 数组走通用 fold(`bootstrap/gen/stmts/stmts_loop_forin.ss` 删反射专用分支)
6. [ ] Planned — **Execute 5**:迁 `interpCtFieldsArray` / `interpCollectFields` 调用点改走 evalExpr + 删原函数(D097 §后续工作 4 "L2ζ-L2κ Map migrate" 落地)+ D098 §决策 2 §Phase B "Meta 对象 InternPool 承载" §下一步 `[x] Done` 回写

---

## 参考

- D088 §第一性需求(obj.fields() + obj[name])/ D088 §决策(结构化字段访问)
- D093 §决策(evalExpr 单函数 dispatch)/ D093 §Rejected A/C/D(interp_* 独立求值器否决)
- D097 §后续工作 1-4(五类 Meta + evalExpr + Meta 数组 iteration + L2ζ-L2κ migrate)/ §第一性问题(反射累积根因)/ L70 累积方向严禁 record
- D098 §决策 2 §Phase B L123-128(Meta 对象 InternPool 承载)
- D111 §决策 1 `internPoolGetOrInsert` / §决策 3 原串 `|` 分隔 key / §新张力 5 L455(Meta 对象 dedup 前置 class instance dedup 设计,本 Plan 承接)
- D096 Phase 4 L1(comptime class 能在 runtime 实例化)
- D094 §规则 2 pure subset(Meta 对象 field read 在白名单内)
- `bootstrap/parse/prelude.ss:19-27`(FieldMeta + AnnotationMeta)/ `bootstrap/eval/interp_obj.ss:122-140`(interpBuildTypeInfo 占位 + interpCollectFields / interpCtFieldsArray)
- `tools/reflection_health_linter.ss`(本 Plan Execute 必跑 GATE)/ `tools/linter_baseline.txt`(14 指标 + F1)
- `memory/feedback_reflection_root_cause_gate.md` / `feedback_design_no_code_authority.md` / `feedback_no_workaround.md` / `feedback_pfv_process.md` / `feedback_dual_entry_is_dual_track.md`
