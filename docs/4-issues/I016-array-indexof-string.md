# I016 — Array<string>.indexOf 对 string 元素返 -1 compiler bug

**父决策:** 无(纯 compiler primitive 缺陷,非业务决策衍生)
**状态:** Done at `bootstrap/gen/methods/gen_methods.ss:408 genIndexOfMethod` + `bootstrap/gen/rt/gen_rt_array.ss:220 ss_arrayIndexOfStr` + `tests/phase5/i016_array_indexof_string.ss`(2026-04-24)
**颗粒度:** 预估 ~20-50 LOC(修 bootstrap/gen/methods/gen_methods.ss 里 indexOf dispatcher 对 string 分支) / 实测 ~60 LOC(runtime fn 新增 29 + dispatcher 签名+分派 10 + test 31 + 下游 d_doc_index_linter workaround 撤除 -14)
**依赖:** 无
**创建:** 2026-04-24
**立项由:** 2026-04-24 D 文档死指针清零轮 simplify reuse agent 发现内建 `Array<string>.indexOf` 已声明但实测返 -1,与预期不符

---

## 问题

`bootstrap/gen/methods/gen_methods.ss:408 genIndexOfMethod` + `:535 dispatcher` 声称支持 `Array<string>.indexOf(target)`,但实测:

```ss
let a: Array<string> = []
a = a.push("foo"); a = a.push("bar")
println(a.indexOf("bar"))  // 预期 1,实测 -1
```

`Array<int>.indexOf` 工作正常;`Array<string>.indexOf` 对已存在元素也返 -1(误报 not found)。

**影响路径**:
- `tools/d_doc_index_linter.ss:36 indexOfStr` 手写线性扫绕 bug
- 任何 SS 代码中需要 `Array<string>` 成员检查的场景

## 第一性需求

内建集合 API 语义不一致 = SS 语言可信度 erosion。`Array.indexOf` 是开发者直觉 API(JS/Java 同名),对不同元素类型返值行为分裂 → 下游开发者要么写 workaround(`indexOfStr` 手写)要么踩静默误判(not found 但实际在)。

**为什么是 bug 而非设计**:stdlib 声明 `Array<T>.indexOf(T)` 泛型,int/double 行为正确,string 被漏覆盖。

## 候选路径

1. **修 `bootstrap/gen/methods/gen_methods.ss:408 genIndexOfMethod` 对 string 分支的等值比较**
   - 可能根因:string 比较走指针 == 而非内容 ==(类似 feedback_interp_value 的 tvId 比较问题?)
   - 验证:先 grep 相关分支看 string case LLVM IR emission
2. **验证 gen_methods.ss 是否真覆盖 string**
   - 有可能 `:535 dispatcher` 只分派 int/double 路径,string 路径走默认 fallback 返 -1(静默降级)
3. **修后对称修 `Array.contains` / `Array.includes` 如存在类似问题**

## 验证标准

- RED: `let a = []; a = a.push("x"); a.indexOf("x")` 实测 -1
- GREEN: 同 snippet 实测 0
- 下游:`tools/d_doc_index_linter.ss:36 indexOfStr` 可删除,改用 `a.indexOf(x) < 0` 等价判定

## 范围

- **做**:修 string 元素比较语义 + 加 `tests/phase5/i016_array_indexof_string.ss` RED → GREEN 最小测试
- **不做**:改 Array 整体类型系统 / 引入 generic equality protocol 大 refactor(非本 issue scope)

## 父决策引用

无。Compiler primitive 类缺陷,归属 CLAUDE.md §Root Cause 优先 — "编译器限制是 bug,不是边界条件"。
