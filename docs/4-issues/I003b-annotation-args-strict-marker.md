# I003b — Annotation args 严格 tv kind marker

**父决策:** D127 §A.1 I003 收尾衍生
**状态:** Draft
**颗粒度:** ~3-5 万 token
**依赖:** I003(已落)
**创建:** 2026-04-22

## 上下文

I003 把 `AnnotationMeta.args` 从 `Map<string, string>` 改成 `Map<string, int>`,value 存 AstNodeId,由 `getString`/`getInt`/`getBool`/`getDouble` 经 `evalAnnotationArg` 按节点 kind eval。但实现侧**无法区分**:

- 「annotation args Map,value 是 AstNodeId,需 eval」
- 「普通用户代码 `Map<string, int>`,value 是原生 int」

当前兜底:`exprs_ct_builtin.ss:229-236` 对 `interpType(rawTv) == "int"` 才 eval,否则原样返。这是**歧义 fallback**:用户若写 `let m = new Map<string,int>(); m.set("k", 42); m.getInt("k")`,42 会被当 AstNodeId 去 `nGetKind(42)`,行为**偶发**(42 若恰好是活跃 AST 节点则产出错误值,否则返 null)。

## 范围

- 新增 marker 机制:annotation args Map 独立 tv kind(如 "annotation_args_map")或在 args Map 上打标记(sidecar set)
- `evalAnnotationArg` 只对**明确标注**的 annotation args 生效,普通 Map.getInt 走原生路径
- I003 当前 typed getter 分派改:先查 marker,非 annotation map → 退回 `interpMapGet` 原样返
- 保留向后兼容:已落地 annotation 测试继续 PASS

## 影响面调查

```bash
grep -rn "getInt\|getBool\|getDouble" bootstrap/gen/exprs/exprs_ct_builtin.ss
grep -rn "buildAnnotationMetaArray\|AnnotationMeta" bootstrap/
grep -rn "interpNewMap\|interpMapSet" bootstrap/eval/
```

估算:marker 定义 + 分派改 1 点,consumer 侧 0 点(getter 分派内部改即可)。

## 步骤

1. 在 `bootstrap/eval/interp_value.ss`(或 `interp_map.ss`)加 marker 字段,或新增 kind "annotation_args_map"
2. `buildAnnotationMetaArray` 建 args Map 时打 marker
3. `ctMapMethod.getString`/`getInt`/`getBool`/`getDouble` 先查 marker → 有 marker 走 `evalAnnotationArg`,无 marker 走 `interpMapGet` 原样返
4. 新测试:
   - `tests/phase5/i003b_regular_map_no_eval.ss` —— 用户 `Map<string,int>` + `getInt` 返原生 int(非 eval 结果)
   - 现有 `tests/phase5/i003_annotation_value_types.ss` 继续 PASS(marker 路径)
5. bootstrap 固定点

## 反向

不做 → 用户代码 `let m: Map<string, int>; m.getInt(k)` 在 I003 语义下是"取 AstNodeId eval",与自然语言直觉冲突 → 编译器"annotation 吸收"效应暴露成用户面 bug

## 验收 RED 命令

```bash
bin/ss run tests/phase5/i003b_regular_map_no_eval.ss      # PASS(现尚未实现,返错误值/null)
bin/ss run tests/phase5/i003_annotation_value_types.ss    # PASS(I003 已通,本 issue 不能打破)
./build.sh bootstrap
```

## 备注

- 本 issue 纯为**消除 I003 兜底歧义**,不是新功能
- 若 marker 实现成"Map 全局 side set",注意清理;若实现成 tv kind 扩,注意 Meta 构建路径更新
- 优先级:低(I003 兜底 fallback 未引发测试红),但跨 I004-I006 扩展前建议先落,否则每个新 kind eval 都要 care 歧义路径
