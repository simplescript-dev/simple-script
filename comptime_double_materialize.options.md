# Bug 方案对比表:comptime double-return 物化破损 (D171 finding C)

## 现象 (RED)
`bin/ss run` on `let x = comptime { return 3.5 + 1.25 }` →
`llc-18: error: expected value token` @ `store double , ptr %x.79`(空值 literal)。

## 根因双层
- **L1 跨读(致 llc 崩)**:`gen_types.ss:294` COMPTIME_EXPR double 分支用 `interpAsStr(ceRetVal)` 读 **tvS1**(string 槽,double tv 恒空)→ `""` → `store double ,`。与 D169 §POC 失败 N1(-3.14 global init regression,`eval_expr.ss:50` 注释)是**同一 tvS1/tvD1 跨读 bug 的两面**。
- **L2 有损存储(致静默丢精)**:`newTvDouble`(interp_value.ss:188)只存 `tvD1 = ${d}`,而 `${d}` 走 `ss_double_to_string`=`%g`(实测:`10.0/3.0`→`3.33333`、`0.1+0.2`→`0.3`)。**单纯换 interpToStr 读 tvD1 → 把 llc 崩换成非精确 double 静默丢精**(比崩更糟,违「无静默误编译」)。

## 候选方案

| 候选 | 方案 | 层次 (纵向) | 假设破裂入口 | 长久/演化 (横向, field 10d) | 判定 |
|---|---|---|---|---|---|
| **A** | gen_types.ss:294 `interpAsStr`→`interpToStr`(读 tvD1 %g) | **数据层 patch** | 假设 tvD1 含足够精确十进制 → **破裂**:tvD1=%g(6 位有效)→ `10.0/3.0` 物化成 3.33333 静默丢精 | 任一非 %g-exact double 出现即返工;**短期权宜** | ❌ REJECT:llc 崩换静默误编译(更糟),正是 eval_expr.ss:50 + D169 POC N1 警告的陷阱 |
| **B** | **newTvDouble +tvS1=`doubleBits(d)`(exact 16-hex 槽);gen_types.ss:294 + materialize():36 物化为 `0x${tvS1}`** | **数据层(补 exact-bits 存储)+ 接口层(物化读 exact slot)** | (a) interpAsStr(double) 现读空 tvS1 → 本方案填充之;(b) **最危险**:`0x<16hex>` 是否在 LLVM global+local+inline double 常量精确往返?→ spike 验 | 底层依赖链:仅依赖 doubleBits(已落)+ tvS1(已落),**无未落地 prereq**;业界对标:LLVM APFloat / Zig InternPool.Key.Float 存 **exact bits** 是 float 常量 canonical 做法;N 年返工度 **低**——是候选 C 的基础,纯扩展无返工 | ✅ **CHOOSE** |
| **C** | tvD1 改存 canonical bits;加 `ss_hexToDouble` runtime fn;重写 interpToStr(bits→%g 显示)+ 算术回读(interp_op.ss:83 bits→double)+ 全物化 | **架构层 refactor** | 需新 builtin ss_hexToDouble;interpToStr/算术/所有 reader 改造;多点 | 这是「全 comptime double 精确(含 chained 算术)」的最终根，但**依赖候选 B 的 exact-bits 基础先落地**(field 10d:基础层先于上层) | ❌ REJECT 本轮:混入 **chained 算术精度**这一 DISTINCT 既有根因(interp_op.ss:77-80 文档化的 tv-无-native-double 模型,非本 RED),over-scope finding C 成解释器 double 存储大改 + 新 builtin。backlog「exact comptime double 算术」 |

## 决策行
**选 候选 B 因** 它在 finding C 的 RED 路径(COMPTIME_EXPR 物化)上做到**精确物化的根因解决**:数据层补 exact-bits 存储消除 N1 跨读根因(tvS1 不再恒空),接口层物化读 exact slot 消除 %g 静默丢精;`doubleBits` 已存零新基础设施(根因解决度最高:同时灭 L1 跨读 + L2 丢精两层)。**不选 候选 A**(数据层)因其只换崩为静默误编译(更浅且更糟)。**不选 候选 C**(架构层)因其(field 10d 底层依赖链)依赖候选 B 的 exact-bits 基础先落地,且混入 chained 算术精度这一独立既有根因——候选 B 是候选 C 的**基础非短期权宜,零返工**。

## field 11 ladder(是最根的根因吗?)
对 **finding C = 物化层**:候选 B 已是最深可达——exact bits 是 double 的精确表示,不可能更精确(证据:LLVM/Zig 以 exact float bits 作常量 canonical 表示)。再上推一格(候选 C 全算术精确)即**离开物化 scope 进入解释器算术 scope**(另一根因,backlog)。故候选 B 锁定为 finding C 最根。

## 落点(改 3 处,leave 2 处)
- ✏️ `interp_value.ss:188` newTvDouble:+`tvS1.set(id+"", doubleBits(d))`(exact bits 入 string 槽,tvD1=%g 保留作 human 显示/算术回读)
- ✏️ `gen_types.ss:294`:`comptimeExprLiteral.set(ceKey, `0x${interpAsStr(ceRetVal)}`)`
- ✏️ `interp_value.ss:35-39` materialize() double 分支:`return `0x${tvStringOf(interpValId)}``(统一 reg() 路径,inline operand 安全无 parseDouble 重解析)
- 🚫 LEAVE `class_comptime.ss:48`:annotation arg 折叠需 **human 十进制**(class_annotation.ss:129 `nGetS1` as-is 作 metadata),%g 在此**正确**,不改
- 🚫 LEAVE `interp_op.ss:83` 算术回读:chained comptime double 精度是**独立既有根因**(候选 C scope),backlog

## §实证 (MNK §字段 12)

### (a) 事实断言核对 — 继承蓝图逐条重核
1. **RED 实证**(`bin/ss run` probe `let x = comptime { return 3.5 + 1.25 }`):
   ```
   llc-18: error: expected value token
     store double , ptr %x.79, align 8   ← 空 literal,坐实 L1
   ```
2. **L2 有损 grep+probe 实证**:`grep '@.rt.fmt.g' bootstrap/gen/gen_runtime.ss` → `c"%g\00"`(ss_double_to_string 用 %g);runtime probe `10.0/3.0`→`3.33333`、`0.1+0.2`→`0.3`(6 位有效,坐实「单纯 interpToStr 静默丢精」)。
3. **L1 槽错 grep 实证**:`gen_types.ss:294` = `interpAsStr(ceRetVal)`;`interpAsStr`→`tvStringOf`→`tvS1.getString`(interp_value.ss:154/134);double tv 仅 newTvDouble 写 `tvD1`(interp_value.ss:188)未写 tvS1 → tvS1 恒空。
4. **POC N1 同源实证**:`grep "POC.*N1\|跨读 tvS1" docs/3-decisions/D169*.md` + eval_expr.ss:50 注释 → -3.14 global init regression 同为 interpAsStr 跨读 tvS1 → 0.0。本方案填充 tvS1 即根除 N1 同源 bug。
5. **零新基础设施 grep 实证**:`grep "doubleBits" bootstrap` → ss_doubleBits 已存(gen_rt_string.ss:339,`%016llx` 16-hex);`grep "newTvDouble" bootstrap` → 唯一 caller interpNewDouble(且已算 doubleBits 作 InternPool key,line 195)→ 本方案自包含。
6. **无 parseDouble 重解析风险 grep 实证**:comptimeExprLiteral 消费侧(eval_expr.ss:102 constVal inline / gen_decls.ss:259 global / 540 local)直接发 `double <lit>`,**不建 DOUBLE_LIT 节点**;hex 不经 parseDouble。class_comptime:48 建 DOUBLE_LIT 故 LEAVE 不动(annotation 走 human 十进制)。

### (b) 最危险假设
`0x<16hex>`(doubleBits 输出加 `0x` 前缀)是否被 LLVM `llc-18` 在 **global / local store / inline operand** 三处 double 常量精确接受并 bit-exact 往返?(task 已验 `0x400C000000000000`=3.5 单点;本轮 spike 全路径实切)

### (c) 最小 spike(全量 Execute 前)
先改 2 处 RED-critical(newTvDouble +tvS1 bits;gen_types.ss:294 `0x${interpAsStr}`)→ `./build.sh bootstrap` 三阶段固定点 → 试切:
- 局部 `let x = comptime { return 3.5+1.25 }` + 全局 `let g = comptime{return 2.5*4.0}` → 编译过 + 运行 exit 0(L1 灭)
- 精度往返 `comptime{return 10.0/3.0}`、`comptime{return 0.1+0.2}` → 物化值 bit-exact(对照 `let r=10.0/3.0` runtime 同值;L2 灭)
- spike GREEN 才追加第 3 处 materialize() + 全测;spike 崩 → 回方案层,禁全量。

