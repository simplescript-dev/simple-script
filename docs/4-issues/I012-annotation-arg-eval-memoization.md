# I012 — evalAnnotationArg 结果 memoization

**父决策:** D127 §A.1 I003 收尾衍生
**状态:** Draft
**颗粒度:** ~2-3 万 token
**依赖:** I003(已落)
**创建:** 2026-04-22

## 上下文

I003 落地的 `evalAnnotationArg(nodeId)` 每次 annotation getter 调用都**重 eval**(反复 `nGetKind` + 字面量 parse):

```ss
// bootstrap/eval/interp_obj.ss
function evalAnnotationArg(nodeId: int): int {
    const kind = nGetKind(nodeId)
    if (kind == "STRING_LIT") { return interpNewString(nGetS1(nodeId)) }
    if (kind == "INT_LIT") { return interpNewInt(parseInt(nGetS1(nodeId))) }
    // ...
}
```

同一 annotation arg 在 `@derive` handler 循环里可能读 N 次(for 每个 field 读同 args)。每次都 parse `"42"` 成 int 42。规模小 annotation 不痛,但 I004(enum eval 可能查 enumValues map)、I006(class ref 可能走 type resolution)的 eval 成本会显著。

## 范围

- 在 `evalAnnotationArg` 入口加 cache:`ctAnnotationArgCache: Map<string, int>`,key = `nodeId + ""`,value = typed tv
- cache 命中直接返,未命中 eval + 写缓存
- cache 清理时机:comptime scope 退出 / AST 重建

## 影响面调查

```bash
grep -rn "evalAnnotationArg" bootstrap/
grep -rn "ctAnnotation\|ctAnnoCache" bootstrap/  # 现无,新增
```

估算:cache 定义 1 处 + eval 入口改 1 处 + 清理点 1-2 处。

## 步骤

1. `bootstrap/eval/interp_obj.ss`(或 ct sidecar):
   ```ss
   let ctAnnotationArgCache = new Map()
   function evalAnnotationArg(nodeId: int): int {
       const key = `${nodeId}`
       if (ctAnnotationArgCache.has(key) == 1) { return parseInt(ctAnnotationArgCache.getString(key)) }
       // ...原 eval 逻辑...
       ctAnnotationArgCache.set(key, `${result}`)
       return result
   }
   ```
2. cache 清理:`ctPopScope` / comptime exit 处 `ctAnnotationArgCache = new Map()`
3. 验证:`d096_p4_l2h_annotation_args` 的 for-in handler 循环里,同一 arg 第二次 eval 走 cache

## 反向

不做 → 大 annotation handler 每次 getter 重算,enum/class eval 成本放大
→ 不致命(性能,非正确性)

## 验收 RED 命令

```bash
# 测 cache 命中:埋打点,二次 eval 同 nodeId 不进 if/parse 分支
# 或测性能:100 次读同 arg,cache 版本 O(1),无 cache 版本 O(N)
./build.sh bootstrap                              # 固定点
bin/ss run tests/phase5/i003_annotation_value_types.ss   # 结果不变
```

## 备注

- **优先级低**:正确性无影响,纯性能
- 若 I003b marker 先落,本 issue 可合并到 marker tv 结构里(marker 结构本身就能充当 cache slot)
- 若 Zig 路线后续把 annotation eval 前置到 checker 阶段(CtValue 预 eval),本 issue 自动废弃
