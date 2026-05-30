# I039 — annotation arg 负数字面量(UNARY)未支持

**父决策:** I011 复核(2026-05-30)衍生发现
**状态:** Draft
**颗粒度:** ~1-2 万 token(定位明确)
**依赖:** 无(I003 annotation arg eval 已落,本 issue 补 UNARY 分支)
**创建:** 2026-05-30

## 上下文

I011 复核时发现:annotation 参数用负数字面量报错 ——

```ss
@M(neg = -2.5)   // 或 @Range(min = -10)
class P { x: int }
```
→ `error: [comptime] annotation arg kind 'UNARY' not yet supported at line N:M`

`-2.5` 在 parser 里是 **UNARY 节点**(一元负,operand = DOUBLE_LIT `2.5`;SS 无裸负字面量,负号统一走 UNARY)。`evalAnnotationArg`(`bootstrap/eval/interp_obj.ss:170`)的 kind 分派表覆盖 STRING_LIT / INT_LIT / DOUBLE_LIT / TRUE_LIT / FALSE_LIT / MEMBER_ACCESS(enum) / ARRAY_LIT / IDENT(类名)**独缺 UNARY** → fall through 到 `comptimeError`(`interp_obj.ss:211`)。

**安全性**:loud 报错(非静默误编译),不是 correctness hazard,故 deferred 可接受。但负数 annotation 参数(`@Retry(min = -1)` / `@Range(lo = -10)`)是常见场景。

## 范围

- `evalAnnotationArg`(`interp_obj.ss:170`)加 UNARY 分支:op 为一元负(Neg)+ operand 是 INT_LIT / DOUBLE_LIT → eval operand 再取负(`interpNewInt(0 - v)` / `interpNewDouble(0.0 - d)`,复用既有 INT_LIT/DOUBLE_LIT 分支)。
- 非数值 operand 的 UNARY(如 `!x`)维持 loud(annotation value 语义无意义)。
- 新测试:`@M(i = -10, d = -2.5)` + `getInt`/`getDouble` 断言负值 + bit-exact。

## 影响面调查

```bash
grep -rn "UNARY" bootstrap/eval/interp_obj.ss bootstrap/eval/eval_expr.ss   # UNARY 节点 op/operand slot 约定
grep -rn "interpNewInt\|interpNewDouble" bootstrap/eval/interp_value.ss     # 取负后重新构造 tv
```

## 反向

不做 → annotation 参数不支持负数,`@Range(min = -10)` 类落不了,annotation schema 缺负数值原语(只能 string/正 int/正 double/bool/enum/array/类名)。

## 验收 RED 命令

```bash
cat > /tmp/i039_red.ss <<'EOF'
@M(neg = -2.5, negi = -10)
class P { x: int }
function main() {
    const d = comptime { let a = 0.0; for (x in P.annotations) { a = x.args.getDouble("neg") } return a }
    const i = comptime { let a = 0; for (x in P.annotations) { a = x.args.getInt("negi") } return a }
    println(`d=${d} i=${i}`)
}
EOF
bin/ss run /tmp/i039_red.ss     # 现状(RED): [comptime] annotation arg kind 'UNARY' not yet supported
                                # 修后(GREEN): d=-2.5 i=-10
```

## 备注

- 发现于 I011 复核(2026-05-30,probe `/tmp/i011_thorough.ss` 第 4 arg `neg=-2.5`),属 pre-existing 覆盖缺口,非新引入。
- 优先级:中(负数 annotation 参数常见,但有 loud 兜底不紧急)。
