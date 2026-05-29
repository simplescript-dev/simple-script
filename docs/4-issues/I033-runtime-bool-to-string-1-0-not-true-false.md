# I033 — runtime bool→string 显示 "1"/"0" 而非 "true"/"false"(genExprAsString bool 分支缺失)

**父决策:** D171 §下一步 finding A(runtime scalar 数组 .join 段错)修复轮衍生。finding A 修复让 bool 数组 `.join` 不再段错,但显示走 runtime scalar→string 的既有缺陷输出 "1"/"0",偏离 comptime oracle + JS 语义。
**状态:** **[x] Resolved at** `bootstrap/gen/gen_types.ss:278`(TRUE_LIT/FALSE_LIT→"bool")**+** `bootstrap/gen/exprs/exprs_str_conv.ss:33`(genExprAsString bool 分支→ss_bool_to_string),2026-05-29。回归 `tests/phase5/i033_runtime_bool_display.ss`,方案 `i033_runtime_bool_display.options.md`(GATE 6/6),证据 `tools/bugfix_reports/2026-05-29-i033-runtime-bool-display.bugfix`(6 gate PASS)。
**颗粒度:** 预估标准改(genExprAsString bool 分支 + 全测验证模板插值行为变更无回归;可能波及既有依赖 `${bool}`="1" 的测试)。
**依赖:** 无(genExprAsString + ss_bool_to_string 均现成,ss_bool_to_string 已 define gen_rt_string.ss:308)。
**创建:** 2026-05-29
**立项由:** finding A(`findingA_scalar_join`)runtime scalar 数组 join 段错修复轮 —— 逐 kind 隔离 bool 时实测 runtime bool→string 显示偏离。

---

## 现象(可观测,2026-05-29 实测)

```ss
println(`${true}`)               // runtime 输出 "1"  (期望 "true")
println([true, false].join("-")) // runtime 输出 "1-0"(期望 "true-false")
println(comptime { return [true, false].join("-") }) // comptime 输出 "true-false" ✓(oracle)
```

runtime 三处(模板插值 / 字符串拼接 / 数组 join)bool→string 一致输出 "1"/"0";comptime `interpToStr`(interp_op.ss:35 `tvIntOf(id)==1 ? "true" : "false"`)与 JS `String(true)="true"` 均为 "true"/"false"。**runtime/comptime parity 偏离 + 偏离 JS/TS 语义**。

## 根因

单一概念根 = **gen 层把 bool 折叠成 int,丢失显示/分派所需类型**,有**两个折叠站点**(Execute 轮 §字段 12 实证补全 — 本节原仅指站点 B,实测不足):

- **站点 A(类型推断折叠)**:`gen_types.ss:274` `inferType(TRUE_LIT/FALSE_LIT)` 返 `"int"`(非 `"bool"`)→ `let b=true` 经 `gen_decls.ss` `setVarType` 传播为 int;`[true,false]` 经 `inferArrayElemType` 首元素 `inferType="int"` → `gen_methods.ss:542` dispatch **`_ss_joinInt`**(非 `_ss_joinBool`)。**显示路径永远拿不到 `"bool"` 类型**。
- **站点 B(显示分支缺失)**:`genExprAsString`(exprs_str_conv.ss)分派 string/double/i64/ptr,**bool 落最后的 `ss_int_to_string`**(行 42)→ i32 0/1 → "0"/"1"。缺 bool 专属分支(应走 `ss_bool_to_string`→@.rt.str.true/.false)。

模板插值(gen_calls.ss:611)、`+` 拼接(exprs_binary.ss:7)、数组 `.join`(经 `_ss_joinBool`/`_ss_joinInt` body 内 `result+arr[i]`)全部复用 genExprAsString —— 故站点 B 是显示单一真相源,但**站点 A 必须同修**:否则 inferred var(`let b=true`)与数组 join(走 `_ss_joinInt`,元素 typed int)在 genExprAsString 处 vType=`int`,bool 分支不可达。

## 候选路径(已 Execute — 详 `i033_runtime_bool_display.options.md` PSM §字段 10,GATE 6/6)

**立项时推荐"仅 genExprAsString 补 bool 分支(接口层 trap)"经 §字段 12 实证修正为不足** —— 该候选(options.md 候选 B)假设"bool 值到 genExprAsString 时类型=bool",但站点 A(line 274)在前折叠 int → inferred var / 数组 join(走 `_ss_joinInt`)bool 分支不可达,仅修 annotated `let b:bool`(1/3 RED)。

**实际采纳:options.md 候选 C(接口层根因双站点)** —— 站点 A `gen_types.ss:274` TRUE_LIT/FALSE_LIT→"bool" + 站点 B `genExprAsString` 补 bool 分支→`ss_bool_to_string`。从源头同堵两个折叠站点,bool 类型完整流过 inferred var / 数组 dispatch(→`_ss_joinBool`)/ 显示全链,三 sink 复用同一 genExprAsString bool 分支单一真相源。全测 344/3(3 pre-existing)、bootstrap 固定点、parity 兑现。

- **数据层 patch(候选 A,未选)**:每 sink 内联三元 `arr[i]?"true":"false"` —— 制造 join 与模板插值不一致风险,违反单一真相源、重复 `ss_bool_to_string` 既有逻辑,**劣**。
- **架构层 refactor(候选 D,未选)**:bool 升 IR 一等类型 i1 —— bool@IR=i32 本是正确低层表示,改 i1 触发 mangling ABI break + 全量 zext/trunc,过度工程。

## 为何独立(不混入 finding A)

finding A 核心 = **段错**(scalar 位值当 ptr 解引用),根因在 join codegen 错置 + 元素类型推断。bool 显示 "1"/"0" 是 **genExprAsString 既有缺陷**(先于 join,模板插值早已如此),独立 root cause。混入会扩 finding A scope 至"全局 runtime scalar→string 行为变更"+ commit_radius 跨子族。MNK §衍生 issue 归档:非阻挡 → 立项不混入。
