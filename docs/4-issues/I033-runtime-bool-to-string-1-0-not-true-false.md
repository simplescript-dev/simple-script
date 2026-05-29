# I033 — runtime bool→string 显示 "1"/"0" 而非 "true"/"false"(genExprAsString bool 分支缺失)

**父决策:** D171 §下一步 finding A(runtime scalar 数组 .join 段错)修复轮衍生。finding A 修复让 bool 数组 `.join` 不再段错,但显示走 runtime scalar→string 的既有缺陷输出 "1"/"0",偏离 comptime oracle + JS 语义。
**状态:** **[ ] Planned**(backlog;非阻挡 finding A 段错核心,独立 root cause)。
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

`genExprAsString`(exprs_str_conv.ss)是 runtime scalar→string 单一真相源,分派 string/double/i64/ptr,**bool 落到最后的 `ss_int_to_string`**(行 42)→ i32 0/1 格式化为 "0"/"1"。缺 bool 专属分支(应走 `ss_bool_to_string` → @.rt.str.true/.false)。模板插值(gen_calls.ss:611)、`+` 拼接(exprs_binary.ss:7)、finding A 后的 `_ss_joinBool`/`_ss_joinInt`(bool 字面量推断为 int)全部复用 genExprAsString,故同一缺陷三处显形。

## 候选路径(待 Execute 轮 PSM §字段 10 展开)

- **接口层 trap(推荐方向)**:`genExprAsString` 补 bool 分支 `if (vType == "bool") { call ss_bool_to_string }`,单一真相源修一处惠及模板/拼接/join 全部,对齐 comptime + JS。**风险**:改变模板插值 `${bool}` 全局行为("1"→"true"),需全测验证 + 排查既有依赖 `${bool}`="1" 的测试(若有则那些测试本身违背 JS 语义应一并修正)。
- **数据层 patch**:仅 `_ss_joinBool` 内部三元 `arr[i]==true?"true":"false"` —— 制造 join 与模板插值不一致(`${b}`="1" vs `[b].join()`="true"),违反单一真相源,**劣**。

## 为何独立(不混入 finding A)

finding A 核心 = **段错**(scalar 位值当 ptr 解引用),根因在 join codegen 错置 + 元素类型推断。bool 显示 "1"/"0" 是 **genExprAsString 既有缺陷**(先于 join,模板插值早已如此),独立 root cause。混入会扩 finding A scope 至"全局 runtime scalar→string 行为变更"+ commit_radius 跨子族。MNK §衍生 issue 归档:非阻挡 → 立项不混入。
