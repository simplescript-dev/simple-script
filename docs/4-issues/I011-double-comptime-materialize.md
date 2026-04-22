# I011 — double 类型 comptime materialize bug

**父决策:** D127 §A.1 I003 收尾发现的 pre-existing bug
**状态:** Draft
**颗粒度:** ~1-2 万 token(定位明确)
**依赖:** 无(I003 已实装 DOUBLE_LIT → interpNewDouble,本 issue 修阻断路径)
**创建:** 2026-04-22

## 上下文

I003 `evalAnnotationArg` 里 DOUBLE_LIT 分支已实装:

```ss
if (kind == "DOUBLE_LIT") { return interpNewDouble(parseDouble(nGetS1(nodeId))) }
```

但 `tests/phase5/i003_annotation_value_types.ss` **不敢**加 `@M(pi = 3.14)` + `a.args.getDouble("pi")` 的 double 覆盖 test,因为 comptime → runtime materialize 侧有 pre-existing bug:

```ss
// bootstrap/gen/gen_types.ss:261(推测,需再 grep 确认)
// interpAsStr(double_tv) 取 tvS1 而非 tvD1 —— double 值无法 serialize 成 LLVM IR 字面量
```

触发路径:comptime 里算出 double tv,return 回 runtime 域时走 materialize → 产出错误 IR(取 string slot 而非 double slot)。

## 范围

- `bootstrap/gen/gen_types.ss` / `bootstrap/eval/eval_expr.ss` 双 materialize 路径,找 `interpAsStr(xx_double_tv)` 的误用
- 修法二选一:
  - (a) 给 double tv 单独 materialize 分支,取 tvD1 生成 `double 3.14`
  - (b) `interpAsStr` 对 double tv 内部 coerce 成 string 再返(若只是 IR 字面量需求)
- 新测试:`@M(pi = 3.14)` + `a.args.getDouble("pi")` 断言 `== 3.14`

## 影响面调查

```bash
grep -rn "interpAsStr.*double\|DoubleLit\|DOUBLE_LIT" bootstrap/gen/ bootstrap/eval/
grep -rn "materialize" bootstrap/
```

待定位精确行号(I003 收尾只 desk-read 定位到 gen_types.ss:261 附近,未确认)。

## 步骤

1. 定位:grep materialize + double tv 使用点
2. 读代码判:是 tvD1 访问错 slot,还是分派表漏 double 分支
3. 修:按 (a) 或 (b) 方案,优先 (a)(清晰分派)
4. 新测试 `tests/phase5/i011_annotation_double_arg.ss`
5. bootstrap 固定点

## 反向

不做 → annotation value 支持 string/int/bool,**不支持 double**,annotation schema 少一原语
→ Spring Boot 复刻进阶场景(`@Retry(backoffMultiplier = 1.5)`)无法落地

## 验收 RED 命令

```bash
# 现状(pre-fix)
cat > /tmp/red_double.ss <<'EOF'
@M(pi = 3.14)
class P { x: int }
function main() {
    const r = comptime {
        let acc = 0.0
        for (a in P.annotations) { acc = a.args.getDouble("pi") }
        return acc
    }
    if (r != 3.14) { println("FAIL") }
}
EOF
bin/ss run /tmp/red_double.ss                    # 预期 FAIL 或 IR 错

# 修后
bin/ss run tests/phase5/i011_annotation_double_arg.ss    # PASS
./build.sh bootstrap
```

## 备注

- 本 issue **独立于 I003**:I003 eval 层已正确,I011 修的是下游 materialize
- 发现于 I003 收尾,属 pre-existing bug,不算 I003 新引入
- I003 test 文件已在 docstring 里点名此限制(`tests/phase5/i003_annotation_value_types.ss` 开头注释)
- 优先级:中(Phase 1 核心不用 double,但 ORM / 配置 annotation 常用 double)
