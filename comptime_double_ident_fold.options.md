# comptime_double_ident_fold — comptime double IDENT 折叠走 tvD1(%g)丢精（D171 finding C 第三物化 sink / I032）

```ss
// RED 裁决 probe（bin/ss run 实测 LOSSY，第一工具调用族内已跑）
function WithRatio(cls: string) {
    const ratio = 10.0 / 3.0
    @methodOf(cls) function getRatio(): double { return ratio }
}
@WithRatio class Box { v: int }
function main() {
    const b = new Box(v: 1)
    println(doubleBits(b.getRatio()))   // 400aaaa8eb463498  ← %g re-parse 有损（现状）
    println(doubleBits(10.0 / 3.0))     // 400aaaaaaaaaaaab  ← 精确
    println(b.getRatio() == 10.0 / 3.0) // 0 (false) ← LOSSY 进数值消费
}
```

# 根因：`bootstrap/gen/class/class_comptime.ss:46-49` `rewriteIdentToLit` double 分支
# `nSetS1(nodeId, tvD1.getString(pl + ""))` 读 tvD1=%g（6 位有效数字，丢精），折叠成 DOUBLE_LIT。
# 下游 3 消费点全部吃到 rounded S1 串（gen_decls store double / eval_expr:36+interp_obj:175 parseDouble / annArgToSrc 源码回流）。

---

## 候选方案对比

> **关键约束（spike 实证，见 §实证 c）**：DOUBLE_LIT 的 S1 是**跨 folded/parsed 共享契约字段**，有三类消费者，精确约束各不同：
> - **LLVM 物化**（`gen_decls store double`）：接受「带小数点的十进制」或「`0x<16hex>`」；**拒绝** `3`/`1e+20`（无点）、**拒绝** `-0x..`（负 hex）。
> - **atof re-parse**（`eval_expr.ss:36`/`interp_obj.ss:175` `parseDouble`）：十进制 + 指数皆可，整型 hex 不解析。
> - **annArgToSrc 源码回流**（`class_annotation.ss:129`，重 `tokenize`+`parse`）：只认 SS lexer 可 lex 的「纯 `数字.数字`」，**无指数 / 无 hex float**（`lexer.ss:399-406` 实测）。

| 候选 | 层次 | 方案 | 在哪层处理"假设破裂入口" |
|---|---|---|---|
| A | 数据层 patch | 照搬 finding C 前两 sink 的 `0x${interpAsStr}` hex 写入 S1 | **不可行（spike 证伪）**——S1 是共享契约，hex 同时喂给三类消费者：LLVM 负号路径 `global double -0x..` REJECT、atof 不解析整型 hex、annArgToSrc 经 SS lexer 不 lex hex float。换一个表示破坏另两类消费者。治标且引入新崩。 |
| B | 接口层 trap | DOUBLE_LIT 增 exact-bits slot(S2)；value 消费点按「S2 present → `bitsToDouble(S2)` / `0x${S2}`」分支；annArgToSrc 改 emit `bitsToDouble("hex")` 调用式源码 | **消除但污染多消费点契约**——把"优先读 bits"子不变量 spread 到 eval_expr:36 / interp_obj:175 / gen_decls(191/213/259) / annArgToSrc 共 5+ 站点；负号 hex 边界(`-0x` 非法)需额外翻符号位；annArgToSrc-as-call 依赖 comptime 能 eval builtin call。新增"S2 可选"语义=未来新增 double 消费点须记得 prefer-S2，否则 bug 复活（高 N 年返工度）。 |
| C | 架构层 refactor | 把 fold 写入 S1 的"丢精 %g"换成 **round-trip 全精度十进制**：新增 `doubleToStringExact` builtin(`%.17g`，复用本轮 `bitsToDouble` 取 exact double)，fold 写 `doubleToStringExact(bitsToDouble(interpAsStr(pl)))` + `.0` 点保证；display(tvD1 %g)**不动** | **精确消除 + 零消费点改动**——把 S1 表示契约从"折叠后可能丢精的十进制"收紧为"round-trip-exact 十进制"。`%.17g` 是 binary64 的 DBL_DECIMAL_DIG 往返保证（spike 证 `10.0/3.0`→`400aaaaaaaaaaaab` bit-exact），LLVM/atof/annArgToSrc **全部照旧读 S1 即正确**（无一处消费点改动）。单一统一契约，破裂入口不可复现。 |
| D | 语言层 | 扩 SS `lexer.ss` 支持指数 float literal(`1.5e10`)→ annArgToSrc 可用 `%.17g` 指数形式 | **跨域超 scope**——改 number lexing 影响全局，且非 I032 第一性需求；I032 §界定明限"只修 DOUBLE_LIT double 精度契约"。**为何不选**：scope break + 风险(全局 number lexing 回归) + 独立特性应独立立项。 |

**假设破裂入口**：`rewriteIdentToLit` double 分支 `nSetS1(nodeId, tvD1.getString(pl))`（`class_comptime.ss:48`）**假设 tvD1 的字符串能无损往返回 double**，但 tvD1 存的是 `${d}`=%g（6 位有效数字的显示用十进制，`newTvDouble` interp_value.ss:189）。该假设在"comptime double 值经 fold 物化进 DOUBLE_LIT S1"时**破裂**。候选 A 换 hex 表示把破裂转移成"另两类消费者崩"；候选 B 在每个消费接口加"prefer bits"分支消除破裂但 spread 子不变量；候选 C 在 fold 写入点直接把 S1 收紧为 round-trip-exact 十进制，**单点根除假设破裂**且全消费点免改。

**决策行**：**选 C 因**（根因解决度评分：纵向 (a) 架构层最深 + 横向 (d) 不依赖未落地候选 + 零消费点改动=最低 N 年返工度）它把 S1 表示契约本身收紧为"round-trip-exact 十进制"——这是**跨 folded/parsed 共享字段**唯一能让"折叠不丢精 + 全消费点 correct by construction"并存的层次。A 换表示破坏另两类共享消费者（数据层换错表示），B 把"prefer bits"子不变量 spread 到 5+ 接口（接口层多点 trap，未来新消费点漏读即复活 bug），均落在比"统一表示契约"浅的层。**不选 deeper layer(D 语言层 lexer)** 因 scope break（I032 §界定明限只修 double 精度契约）+ 全局 number lexing 回归风险 + 应独立立项。

**长久 / 演化(d)**：
- **底层依赖链**：候选 C 唯一新底座 = `doubleToStringExact`(`%.17g` 格式化)，**不依赖任何未落地的更基础候选**；其取 exact-double 这一步复用本轮已落 `bitsToDouble`(I032 §依赖明示"底层先行")。候选 B 同样不依赖未落地件，但其"S2 可选 slot"是新增表示维度，未来每个新 double 消费点都成新依赖点。
- **业界对标**：成熟编译器（Clang APFloat）对 float 字面同时保留「精确值」+「源码 spelling」，消费按需取；本质上 round-trip 文本表示（C）与 hex/bits 双轨（B）都属此族。但「单一 round-trip 十进制」是最少表示维度的收敛形态（一份数据满足全消费者），演化稳定。
- **N 年返工度**：C **最低**——S1 单一契约"round-trip decimal"，任何未来新增 DOUBLE_LIT 消费点无差别读 S1 即自动正确，bug 不可复活。B 较高——"prefer S2 bits else S1"必须被每个未来消费点记住。极端幅值（`|x|≥1e17`，`%.17g` 转指数）下 C 的 annArgToSrc 子路径受 SS lexer 无指数限制——但此类 double **经 SS 字面量物理不可达**（lexer 无指数 literal，line 399-406），仅算术可达且属 pre-existing lexer gap，非本修引入，且不影响裁决 probe 与全部现实可达幅值。

---

## §实证（MNK §字段 12）

### (a) 根因定位 grep 证据（命令 + 输出）

```
$ grep -n "tvD1.getString" bootstrap/gen/class/class_comptime.ss
48:        nSetS1(nodeId, tvD1.getString(pl + ""))   # ← fold double 分支读 %g（假设破裂入口）

$ grep -n "tvD1\|tvS1\|doubleBits" bootstrap/eval/interp_value.ss | sed -n '1,4p'
189:    tvD1.set(id + "", `${d}`)                # tvD1 = %g human 显示（6 位，丢精）
194:    tvS1.set(id + "", doubleBits(d))         # tvS1 = IEEE754 hex16 exact（interpAsStr 取此）

# 三消费点（全读 S1）
$ grep -n "store double \${nGetS1\|global double \${nGetS1\|parseDouble(nGetS1\|DOUBLE_LIT.*nGetS1" \
    bootstrap/gen/gen_decls.ss bootstrap/eval/eval_expr.ss bootstrap/eval/interp_obj.ss bootstrap/gen/class/class_annotation.ss
gen_decls.ss:191:  `${globalRef} = global double ${nGetS1(initId)}`   # LLVM 物化
eval_expr.ss:36:   parseDouble(nGetS1(astId))                        # comptime/runtime 回读
interp_obj.ss:175: parseDouble(nGetS1(nodeId))                       # annotation arg 回读
class_annotation.ss:129: return nGetS1(argId)                        # 源码回流
```

### (b) 最危险假设

**"`%.17g` 对 binary64 bit-exact 往返（过 atof + LLVM round-to-nearest），且对现实可达幅值产纯十进制（带小数点、无指数）"** —— 若不成立，候选 C 物化仍丢精 / LLVM 拒绝，整方案崩。

### (c) 最小 spike（第一次大规模 Execute 之前）

```
# spike-1: %.17g round-trip（python proxy for C snprintf + atof + LLVM round-to-nearest）
%g    (10.0/3.0) = "3.33333"             -> bits 400aaaa8eb463498  ← LOSSY（正是 bug 观测值）
%.17g (10.0/3.0) = "3.3333333333333335"  -> bits 400aaaaaaaaaaaab  ← EXACT（命中精确目标）
%.17g 对 3.0/0.1/2.5/-3.14/123456789.12 全部 roundtrip=True、带小数点（仅整数值 3.0→"3" 无点，由 fold `.0` guard 补）

# spike-2: llc-18 接受度（决定表示约束）
ACCEPT: global double 3.3333333333333335   （非精确十进制 → 自动 round-to-nearest 精确位）
ACCEPT: global double 0x400AAAAAAAAAAAAB / -3.14 / 3.0
REJECT: global double 3        （整型无小数点 → "integer constant must have integer type"）
REJECT: global double -0x400AAAAAAAAAAAAB （负 hex 非法）
REJECT: global double 1e+20    （指数尾数无小数点）
→ 证伪候选 A（hex 负号路径崩）；坐实候选 C（round-trip decimal + `.0` guard 全 ACCEPT）。

# spike-3: SS lexer 无指数（决定 annArgToSrc 约束 + 极端幅值边界归因）
lexer.ss:399-406 仅 lex `数字.数字`，无 'e'/'E' 指数分支 → 极端幅值 %.17g 指数形式非 SS-lexable；
但 SS 字面量本就无指数 literal，极端 double 物理不可达 SS 源码，pre-existing gap 非本修引入。

# spike-4: 新 builtin 2-stage bootstrap 可行性
bitsToDouble（17dd88a 单 commit 同时 reg+use 成功）先例 + `emitRuntimeConversions()`(gen_runtime.ss:21)
无条件发射 → 注册后 stage1 codegen 即发射 def，stage2 获得能力 → Stage A(仅注册) → Stage B(接入) 两步可达。
```

**结论**：候选 C 关键假设全部 spike 实证通过，可一次性正式实施。
