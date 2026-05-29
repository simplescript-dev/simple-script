# comptime_double_arith — chained comptime double 算术精度丢失

**bug**:comptime 块内 double **中间值跨操作回读**丢精——`comptime { let t = 10.0/3.0; return t * 3.0 }` 物化成 `9.99999` 而非 `10.0`。

**RED(已实测)**:
```bash
bin/ss run /tmp/d171_chain.ss   # let t=10.0/3.0; return t*3.0
# 现状: chain result = 9.99999   (应 10)
```

**根因链**:`interpNumericBinop`(`bootstrap/eval/interp_op.ss:81-88`)的 double 分支回读中间值走
`parseDouble(interpToStr(lp))`，而 `interpToStr`(`interp_op.ss:37`)对 double 读 `tvD1`(`%g` 十进制，
默认 6 位有效数字）。链式算术 `t = 10.0/3.0` 把 t 存为 tvD1=`"3.33333"`，回读 `parseDouble("3.33333")=3.33333`，
`× 3.0 = 9.99999`。finding C 已让**物化路径**(`materialize()` / `gen_types.ss:294`)走 tvS1 IEEE754
exact-bits，但**算术回读路径**仍误读 tvD1 这条"给人看的十进制显示列"。

**这是双轨误用**:double 有两份存档——tvS1(IEEE754 exact-bits，finding C 加)+ tvD1(`%g` human 显示)。
算术回读误用了 human 显示列。

---

## 候选方案对比

| 候选 | 层次 | 方案 | 在哪层处理"假设破裂入口" |
|---|---|---|---|
| A | 数据层 patch | 提高 tvD1 的 `%g` 精度(`newTvDouble` 存 `${d}` 改用 `%.17g`) | **不消除**——回读仍经十进制中间表示(tvD1)。`%.17g` 是 double 最短可往返十进制位数，但 SS `${d}` 走默认 `%g`；即便提精度，double→decimal→double 往返在边界值仍非保证 bit-exact，且**改变 human 显示**(println 全变长串)。治标。 |
| B | 接口层 trap | `interpToStr` 对 double 改读 tvS1 hex(所有 double→string 走 exact bits） | **消除但污染显示**——`interpToStr` 是 human 显示主路径(println/模板插值最终经此）。改读 hex 后 `println(3.14)` 显示 `0x40091eb851eb851f`，破坏 finding C 注释明示的"tvD1=`%g` 仅作 human 显示"语义。trap 落在错误的接口层。 |
| C | 架构层 refactor | 新增 `bitsToDouble` 反向 builtin(hex16→`strtoull`→i64→`bitcast` double，镜像 `ss_doubleBits` 逆），`interpNumericBinop` double 回读分支从 tvS1 exact-bits 重建 double；human 显示路径(`interpToStr`→tvD1 `%g`)**不动** | **精确消除**——在 value 表示层把"算术回读=IEEE754 精确位"与"human 显示=十进制"两条路径彻底分离，对称 finding C 的物化路径。 |

**假设破裂入口**:`interpNumericBinop` double 分支 `parseDouble(interpToStr(lp))`(`interp_op.ss:83`)在
"中间 double 值跨操作回读"时**假设破裂**——它假设 `interpToStr` 返回的字符串能无损往返回 double，但
`interpToStr` 读的是 tvD1=`%g`(6 位有效数字的显示用十进制)。候选 A 不消除该假设破裂(仍读十进制列，
仅提精度)；候选 B 消除但把破裂转移到显示接口(污染 println)；候选 C 在 `interpNumericBinop` 局部把回读
切到 tvS1 exact-bits，精确消除假设破裂且不触显示接口。

**决策行**:**选 C 因** 它在 value 表示层把"算术回读"与"human 显示"两条路径分离——算术专走 tvS1
IEEE754 exact-bits（与 finding C 物化路径对称闭环：物化已走 exact-bits，本轮补齐回读），显示专走 tvD1 `%g`；
IEEE754 bit-exact 是 double 算术的唯一忠实语义。A 仍经十进制中间表示治标、B 污染显示接口，均落在错误的层
（根因解决度：C > A > B）。

**ladder（最根?）**:C 之上更深 = interpreter double 全程 native double 存储（不经 tv string 槽往返）=
D098 §Phase C step 2 value-storage 迁移，但 trigger「深比较成瓶颈」**unmet**（D171 §决策判 correctly
deferred，`interpValEquals` 已 O(1)）。当前 tv string-slot 存储架构下，exact-bits hex 往返是 double 算术忠实
的**最深可达层**（`interp_op.ss:80` 注释：`int→string→parseDouble` 是 SS bootstrap tv 无 native double 存储
既有模式）。已穷尽当前架构层。

**长久/演化(d)**:候选 C 不依赖任何未落地的更基础候选——finding C 已落地 tvS1 exact-bits 存储(底层依赖
已就绪)，本轮只补"回读"这一对称半。业界对标:Zig comptime 用 `InternPool.Key.Float`(bit-pattern）存
comptime float，算术也走 bit-exact 不经十进制——候选 C 与之同构。N 年返工度低：未来 value-storage 迁 native
double(Phase C)时，`bitsToDouble` 回读点是隔离的单一 callsite，无痛替换。

---

## §实证(MNK §字段 12)

### (a) 根因定位 grep 证据(命令 + 输出)

```
$ grep -n "tvD1.getString\|parseDouble(interpToStr" bootstrap/eval/interp_op.ss
37:    if (k == "double") { return tvD1.getString(id + "") }          # interpToStr double 读 tvD1 %g
83:        const ld = lt == "double" ? parseDouble(interpToStr(lp)) ... # 回读点(假设破裂入口)

$ grep -n "tvS1.set" bootstrap/eval/interp_value.ss
194:    tvS1.set(id + "", doubleBits(d))                               # finding C: exact-bits 入 tvS1

$ grep -rn "strtoull" bootstrap/gen/
(空)                                                                   # strtoull 未声明,需新 declare

$ grep -rn "interpNumericBinop" bootstrap/
interp_op.ss:81(def) / pow_binary.ss:19 / eval_expr.ss:163            # 仅 2 callsite,改 helper 一处全覆盖

$ grep -rn "bitsToDouble\|hexToDouble" bootstrap/
(空)                                                                   # 反向 builtin 不存在,需新增
```

### (b) 最危险假设

`ss_bitsToDouble`(hex16→`strtoull(buf,null,16)`→i64→`bitcast double`)与已有 `ss_doubleBits`
(`bitcast double→i64`→`snprintf "%016llx"`)**完全互逆** —— 单 op exact-bits 不退化。若往返非互逆，整方案崩。

### (c) 最小 spike(第一次大规模 Execute 之前）

1. 新增 `ss_bitsToDouble` IR(`gen_rt_string.ss`，紧跟 `ss_doubleBits`)+ `declare i64 @strtoull`(`gen_runtime.ss`）
2. 改 `interp_op.ss:83-84` double 回读 `parseDouble(interpToStr(x))` → `bitsToDouble(interpAsStr(x))`
3. 最小注册(`gen_registry.ss` funcRetTypes+names）
4. `./build.sh bootstrap` stage1 + probe:
   - `comptime { return 10.0/3.0 }`（**单 op**，finding C 已正确，验证回读**不退化**仍精确）
   - `comptime { let t=10.0/3.0; return t*3.0 }`（**chained**，验证修复 → 10）
5. spike GREEN（单 op 仍精确 + chained=10）→ 全量(补 checker 注册 + 回归测试 + 三阶段固定点 + 全测）；
   spike 崩（往返非互逆 / 单 op 退化）→ 回方案层，禁全量 Execute。
