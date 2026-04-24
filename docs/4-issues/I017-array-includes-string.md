# I017 — Array<string>.includes 对 string 元素返 false compiler bug

**父决策:** 无(I016 同源 compiler primitive 缺陷,对称修复)
**状态:** Done at `bootstrap/gen/gen_builtins.ss:132 genArrayMethod` + `:172 includes 三维分派` + `bootstrap/gen/methods/gen_methods.ss:558 调用方传 objType` + `tests/phase5/i017_array_includes_string.ss`(2026-04-24)
**颗粒度:** 预估 ~15-30 LOC(对称复用 I016 已入仓 `ss_arrayIndexOfStr`,仅 dispatcher 签名+分派) / 实测 ~40 LOC(genArrayMethod 签名改 +1 + includes 三维分派 +10 + 调用方 +1 + test 37)
**依赖:** I016(复用已入仓 `ss_arrayIndexOfStr` strcmp runtime fn)
**创建:** 2026-04-24
**立项由:** 2026-04-24 I016 commit(59e313e)落地后对称巡检,发现 `Array<string>.includes` 与 indexOf 同源 dispatch bug — CLAUDE.md §Root Cause "workaround 第二次必修根因" 触发

---

## 问题

`bootstrap/gen/gen_builtins.ss:172 genArrayMethod` 的 `includes` 分支单维 argType 盲分派:

- 数值 argType → `ss_arrayIndexOf`(i64 等值)— 正确
- 其他(含 string) → `ss_indexOf`(strstr substring 搜索)— **错误,把数组头当 C 字符串搜**

实测:

```ss
let a: Array<string> = []
a = a.push("foo"); a = a.push("bar")
println(a.includes("bar"))  // 预期 1,实测 0
```

**影响路径**:
- 任何 SS 代码中 `Array<string>.includes(target)` 判成员的场景(stdlib / 用户)
- TS/JS 直觉 API 破坏 — feedback_no_derive_workaround "主线能力缺口" 成立

## 第一性需求

`Array.indexOf` 与 `Array.includes` 语义同源(后者 `== -1` 判否),分派模型必须同构。I016 修 indexOf 时建立三维分派(objType "string" → strstr / 数值 argType → `ss_arrayIndexOf` / 否则 → `ss_arrayIndexOfStr` strcmp),`genArrayMethod.includes` 滞留单维 argType 盲分派 = 双轨制,下一次有人写 `Array<string>.includes` 仍踩同坑。

**为什么是 bug 而非设计**:checker.ss:246 `Array.includes` 已注册 `int(T)`,runtime 返值却对 string 元素静默错误 — 与 stdlib 声明矛盾。

## 候选路径

1. **`genArrayMethod` 加 objType 参数,includes 分支三维分派**(与 `genIndexOfMethod` 同构)
   - objType == "string" → `ss_indexOf`(保持 string.includes substring 语义)
   - 数值 argType → `ss_arrayIndexOf`
   - 其他 → `ss_arrayIndexOfStr`(strcmp 元素比较,I016 已入仓)
2. **纯 argType 分派,不加 objType**(更简)
   - 风险:string.includes 走 genStringMethod 之外 fallback 路径 — 当前 string 方法表没实现 includes(仅 contains),会降级到 genArrayMethod,需保留 strstr 路径
   - 结论:objType 参数不可省

**选择**:路径 1(与 I016 同构,防下一次其他 Array 方法漏分派时再补)

## 验证标准

- RED: `let a: Array<string> = []; a = a.push("bar"); a.includes("bar")` 实测 0
- GREEN: 同 snippet 实测 1 + `tests/phase5/i017_array_includes_string.ss` 9 断言 exit 0
- 不回归: I016 (`i016_array_indexof_string.ss` exit 0)、 string.includes(`"hello".includes("world")` 返 1)、 Array<int>.includes(`[10,20].includes(20)` 返 1)

## 范围

- **做**:`genArrayMethod` 签名加 objType + includes 三维分派 + 调用方传 objType + i017 最小测试(9 断言覆盖 Array<string> / Array<int> / 动态 string ptr / string.includes 不回归)
- **不做**:改 `ss_arrayIndexOfStr` runtime(I016 已入仓)/ 扩到 `genStringMethod` / 重构 `genHigherOrderMethod`/`genMapMethod`

## 父决策引用

无。同 I016,归属 CLAUDE.md §Root Cause 优先 — "编译器限制是 bug" + "workaround 第二次必修根因"(includes 若接受表面 = 第二次 workaround)。
