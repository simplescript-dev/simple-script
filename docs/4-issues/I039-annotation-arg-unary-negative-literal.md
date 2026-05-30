# I039 — annotation arg 负数字面量(UNARY)未支持

**父决策:** I011 复核(2026-05-30)衍生发现
**状态:** Resolved(2026-05-30 — 接口层 evalAnnotationArg 补 UNARY-Neg 分支,options/bugfix GATE 6/6 + 回归测试落地)
**颗粒度:** ~1-2 万 token(定位明确)
**依赖:** 无(I003 annotation arg eval 已落,本 issue 补 UNARY 分支)
**创建:** 2026-05-30

## 解决(2026-05-30)

**Status: Resolved** — `evalAnnotationArg`(`bootstrap/eval/interp_obj.ss:170`)补 UNARY 分支(候选 A 接口层根因,`i039_unary_neg_annotation.options.md` GATE 6/6):`kind=="UNARY" && nGetS1=="Neg"` + numeric-literal 守卫(`ok==INT_LIT||DOUBLE_LIT`)+ int/double 单 ternary 分派,镜像既有 INT_LIT/DOUBLE_LIT 分支加负号(`interpNewInt(0 - parseInt(...))` / `interpNewDouble(0.0 - parseDouble(...))`);非 Neg(`!x`/`~x`)或非数值 operand 维持 fall-through loud。零新函数,`interp_obj.ss` only,不触中央 evalExpr(候选 C scope creep 排除:eval_expr double-unary-fold 是独立 deferred 项 `eval_expr.ss:50-51` line 55 punt)。

**验收**:RED `@M(neg=-2.5, negi=-10)` + getDouble/getInt → 现 `d=-2.5 i=-10`(原 `[comptime] annotation arg kind 'UNARY' not yet supported`);回归 `tests/phase5/i039_unary_neg_annotation.ss`(4 test:负 int / 负 double / 多位 bit-exact + parity / 正 double 不回归)。VCM §3:stash interp_obj.ss + rebuild → test exit 1 ↔ pop + rebuild → exit 0。bootstrap 三阶段定点 + 全测 351→352(+1,3 pre-existing 不变)+ reflection/sunset/d_doc/derived/bugfix GATE 全 PASS,net_new_ifs=2 / net_new_fns=0 / same_pattern_count=0。

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
