# I032 — comptime double IDENT 折叠走 tvD1(%g)丢精(D171 finding C 第三物化 sink)

**父决策:** D171 §第一性需求「comptime = 完整语言」/ finding C(comptime double 精度)。本 issue = tvD1=%g 跨读丢精根因的**第三个物化 sink**(finding C 修了 sink 1/2 = `materialize`+`gen_types`;`comptime_double_arith` 轮修了算术回读 = `interpNumericBinop`;本 sink 漏网)。
**状态:** Open(2026-05-29 立项;裁决 probe 实测 LOSSY 坐实)
**颗粒度:** 预估 标准改 —— DOUBLE_LIT S1 表示契约冲突需根因级设计,非照抄 `0x${hex}`(见 §为何独立)
**依赖:** `comptime_double_arith` 轮已落 `bitsToDouble` builtin(hex16→double)—— **本 issue 修复直接复用它**(底层先行,MNK §字段 10(d))
**创建:** 2026-05-29
**立项由:** `comptime_double_arith`(chained comptime double 算术精度)轮 `/simplify` altitude agent 复查 —— 发现同根因第三 sink;裁决 probe 实测推翻 D171 上一轮"class_comptime.ss:48 本就正确不改"误判

---

## 现象 / 裁决 probe(可观测,2026-05-29 实测)

`@methodOf` annotation handler 捕获外层 comptime double **算术绑定**,生成方法返回它 → 返回值丢精:

```ss
function WithRatio(cls: string) {
    const ratio = 10.0 / 3.0
    @methodOf(cls) function getRatio(): double { return ratio }
}
@WithRatio
class Box { v: int }
function main() {
    const b = new Box(v: 1)
    println(doubleBits(b.getRatio()))   // 400aaaa8eb463498  ← %g re-parse 有损值
    println(doubleBits(10.0 / 3.0))     // 400aaaaaaaaaaaab  ← 精确
    // b.getRatio() == 10.0/3.0 → false (LOSSY)
}
```

`getRatio()` 返回 `3.33333`(从 %g 字串 re-parse),bit pattern `400aaaa8eb463498` ≠ 精确 `400aaaaaaaaaaaab`。**进入数值消费(return 值参与后续算术/比较),非仅 metadata 显示** —— 这推翻 D171 §下一步上一轮判定「class_comptime.ss:48 annotation arg 走 human %g 十进制(metadata 显示,本就正确不改)」。

## 根因

`bootstrap/gen/class/class_comptime.ss:48` `rewriteIdentToLit` double 分支:

```ss
if (tk == "double") {
    nKind.set(nodeId + "", "DOUBLE_LIT")
    nSetS1(nodeId, tvD1.getString(pl + ""))   // ← 读 tvD1(%g,6 位有效数字,丢精)
    return 1
}
```

`foldComptimeIdentsInTree` 把生成方法 body 里捕获的外层 comptime double IDENT 折叠成 `DOUBLE_LIT`,S1 取自 tvD1(%g)。下游数值消费者全部吃到 rounded 串:
- `gen_decls.ss:191/213/259` → `global double <S1>` / `store double <S1>`(直接进 LLVM,丢精)
- `eval_expr.ss:36` + `interp_obj.ss:175` → `parseDouble(nGetS1())`(atof 十进制重解析,丢精)
- `class_annotation.ss:129` `annArgToSrc` → DOUBLE_LIT S1 当 **SS 源码文本** 流回 handler 合成

与 finding C / `comptime_double_arith` 同一类 lossy readback(tvD1=%g 跨读),只是发生在 **AST-literal 物化**(rewriteIdentToLit)而非物化常量 / 算术回读。

## 为何独立(不能本轮一起照抄 `0x${hex}` 修)

DOUBLE_LIT 的 S1 有**两类不兼容消费者**,构成**表示契约冲突**:
1. **LLVM IR 物化**(`gen_decls store double <S1>`):接受 `0x<16hex>` 精确 double 常量 ✓
2. **SS 源码 / atof re-parse**(`annArgToSrc` 流回源码文本 / `eval_expr.ss:36` `parseDouble`):**只认十进制** —— SS lexer 不 lex hex float,atof 不解析 hex ✗

单一字符串无法同时满足"LLVM 精确(hex)"+"SS 源码/atof(十进制)"。照抄前两 sink 的 `0x${tvStringOf}` 会让 re-parse 消费点崩/错。正确根因解需**设计 DOUBLE_LIT 精度契约**,候选方向:
- (a) DOUBLE_LIT 增 exact-bits slot(S1 留 %g 显示 / 新 slot 存 hex),消费者按需取
- (b) re-parse 消费点(`parseDouble`)改 `bitsToDouble` + `annArgToSrc` 路径统一精度表示
- (c) rewriteIdentToLit 对 double 不折叠成 DOUBLE_LIT,改保留精确值句柄机制

→ bug 修复类,需 `comptime_double_ident_fold.options.md`(≥3 候选 + 层次标 + 决策行 + 假设破裂入口 + §实证)过 `bug_options_linter`。

## 步骤

1. 走 CLAUDE.md §Bug 修复 Harness §轨1:产 `comptime_double_ident_fold.options.md` GATE OK 才 Execute
2. 选定 DOUBLE_LIT 精度契约方案(复用本轮 `bitsToDouble`)
3. RED→GREEN:上方 getRatio probe `doubleBits` bit-exact == 精确值;固化 `tests/phase5/d171_comptime_double_ident_fold.ss`
4. bootstrap 三阶段固定点 + 全测 0 regression + reflection_health + sunset linter GATE PASS

## 反向

不修 → comptime annotation handler(@methodOf/@Getter/@Setter)捕获外层 double 算术绑定时静默丢精进数值,与 D171 §第一性需求「comptime = 完整语言」对 double 忠实性相悖(同 finding C 根因家族未清的最后一面)。
