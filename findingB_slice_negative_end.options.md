# findingB_slice_negative_end — 方案对比表

> bug:runtime `Array.slice(start, end)` 对**负 start / 负 end** 不归一(`end<0 → len+end` / `start<0 → len+start`),
> 偏离 comptime interp(oracle 正确)+ JS slice 语义。属 D171 §收口验收「行为级穷举 parity 零偏离」finding B 闭环。
>
> RED:`printf 'function main(){let a=[10,20,30,40];println(a.slice(1,-1).join("-"))}'>/tmp/sb.ss && bin/ss run /tmp/sb.ss`
> → **空行**(comptime/JS oracle = `20-30`);`slice(-3,-1)` 出越界垃圾 `[4-4]`、`slice(-10,2)` 读未初始化内存。

## 现象与根因分层

| # | 表现 | 当前 runtime | comptime oracle |
|---|---|---|---|
| 1 | `slice(1,-1)` 负 end | `[]`(空) | `20-30` |
| 2 | `slice(-3,-1)` 双负 | `[4-4]`(越界垃圾) | `20-30` |
| 3 | `slice(-10,2)` 越界负 start | 读未初始化内存 | `10-20`(start clamp 0) |
| 4 | `slice(-2)` / `slice(1)` 单参 | **编译错误**(checker 强制 2 参) | `30-40` / `20-30-40` |

根因双层:**(L1) runtime `ss_arraySlice` 不归一负索引** —— `gen_rt_array.ss:262-268` 仅做 `e>len` 上界 clamp,
缺 `s<0→len+s` / `e<0→len+e` 归一 + `s` 下界 clamp(致负 start 直接进 GEP → 越界);
**(L2) codegen + checker 不支持单参 slice** —— `gen_builtins.ss:161-166` 无脑读 `slArgs[1]`,`checker.ss:246` 强制 `(2,2)`。

## 候选方案对比

**A**(**数据层 patch** — 调用方 codegen 时补归一)
- 做法:`gen_builtins.ss` slice case 里,若 end 是负**字面量**,codegen emit `len + end` 计算后再传 `ss_arraySlice`。
- **假设破裂入口**:`genExpr` 在方法体内 emit length-load + 加法,需静态知道 array runtime 长度 → 必须 emit `ss_arrayLen` 调用拼接,绕过 runtime 函数边界。
- 在哪层绕过破裂:数据层(只在一个调用点补算),**不消除**根因 —— 破裂入口仍在 runtime 函数。
- **为何不选**:(a) 只覆盖负**字面量**,变量负 end(`slice(1, x)` x 运行期才知 <0)无法静态判,仍漏;(b) 调用方补归一 = workaround,违反 CLAUDE.md §Root Cause「单一真相源」+「禁调用方补 strdup/copy 类 workaround」;(c) `ss_arraySlice` 另有解构 rest 调用点(`gen_decls.ss:399`),不共享 → **同 workaround 第二次出现**,CLAUDE.md 明令停下修根因。
- 长久/演化:N 年返工度**高** —— 变量负索引迟早要补,届时返工到接口层。

**B**(**接口层 trap** — runtime `ss_arraySlice` 内归一 + codegen 单参缺省)✅ 选定
- 做法:在 `ss_arraySlice` LLVM IR 内对 start/end 做 `neg→len+neg` 归一 + clamp(start 下界 0 防 GEP 越界 / end 上界 len),**语义对齐 comptime `ctArrayMethod` slice**(`exprs_ct_builtin.ss:156-159`)。配套:codegen 单参传 sentinel `2147483647`(复用解构既有 sentinel),checker 放宽 `(2,2)→(1,2)`。
- **假设破裂入口**:`ss_arraySlice` 被 method call(`gen_builtins.ss:165`)+ 解构 rest(`gen_decls.ss:399` 传 sentinel `2147483647` + 非负 idx)两处调用 —— 归一**必须对 sentinel / 非负 idx 无副作用**,否则解构 rest 破裂。
- 在哪层消除破裂:**接口层**(runtime 函数边界统一拦截负索引)—— 论证 sentinel `2147483647` 为正不触发 neg 归一、clamp 到 len(同现状);解构 idx≥0 → `s_c=idx` 不变。所有调用点 + 变量负索引(runtime 动态判)自动受益。
- 长久/演化:**底层依赖链**无(不依赖未落地能力);**业界对标** V8/SpiderMonkey 的 runtime slice 亦在函数内归一负索引;**N 年返工度低** —— 函数边界归一是成熟语言标准做法。

**C**(**架构层 refactor** — 抽 comptime+runtime 共享的统一归一函数)
- 做法:把负索引归一抽成跨 comptime interp / codegen 共享的单一 `normalizeSliceRange`。
- **假设破裂入口**:comptime 是 SS 解释器对 tagged value(`interpArrayGet/Push`)操作、runtime 是生成的 LLVM IR(i64 寄存器 + `memcpy`),两执行模型在不同相位 —— 假设"两边可共享同一份**字面**归一代码"在 codegen 相位破裂(解释期值 ≠ 生成期 IR)。
- 在哪层绕过破裂:架构层尝试共享,但**物理不可达** —— 只能共享"语义契约"(归一规则文字)而非可执行代码。
- **为何不选**:(a) comptime/runtime 执行模型物理隔离,字面代码共享不可达,强行抽象只增间接层;(b) 业界 V8/SpiderMonkey comptime 折叠与 runtime slice 亦两套实现 + 契约锁一致;(c) 真"单一真相源"在**语义层(parity 测试锁两边一致)**,不在代码层 —— 候选 B 已含 parity 测试。

### 决策行

**选 B 因 根因解决度最高(接口层 trap > 候选 A 数据层 patch;候选 C 架构层共享物理不可达,降级回 B)** —— 负索引归一是 slice 语义的**内在属性**,放在 runtime 函数边界 = 真单一真相源,自动覆盖所有调用点 + 变量负索引,与 comptime interp 的归一语义对称(两执行上下文各在自己的 slice 实现内归一),零调用方 workaround。不选 A(数据层)因只覆盖字面量 + 调用方 workaround 违反 §Root Cause + 同 workaround 第二次出现;不选 C(架构层)因 comptime/runtime 执行模型物理隔离、字面代码共享不可达,语义一致由 parity 测试锁(B 已含)。

**ladder 追问(是最根的根因解决吗?)**:接口层 trap 能否上推架构层?**no(已穷尽)** —— 候选 C 论证物理隔离不可达;再上推一层(slice 负索引做成语言级 IR pass)即出 slice builtin 的本编译器 scope(slice 非用户可重载语义)。证据:业界编译器 comptime 折叠 + runtime slice 均两套实现 + 契约锁,候选 B 与之对标。

## §实证(MNK §字段 12)

### 根因定位 grep 证据

```
$ grep -n 'irICmp\|irSelect\|irSub' bootstrap/gen/rt/gen_rt_array.ss   # 改前 262-268
262: irSext("s", "i32", "%start", "i64")
263: irSext("e", "i32", "%end_idx", "i64")
264: irICmp("e2", "sgt", "i64", "%e", "%len")      # 仅 e>len 上界 clamp
265: irSelect("end", "e2", "i64", "%len", "%e")
266: irSub("nlen", "i64", "%end", "%s")            # 用未归一的 %s → 负 start 进 GEP 越界
# 缺 s<0→len+s / e<0→len+e 归一 + s 下界 clamp ← L1 根因坐实
```

```
$ sed -n '153,159p' bootstrap/gen/exprs/exprs_ct_builtin.ss   # comptime oracle 已正确
153: if (method == "slice") {
156:     if (start < 0) { start = len + start }   # ← comptime 正确归一(本轮 runtime 对齐目标)
157:     if (end < 0) { end = len + end }
158:     if (start < 0) { start = 0 }             # ← start 下界 clamp
159:     if (end > len) { end = len }
```

```
$ grep -rn 'ss_arraySlice' bootstrap/   # 仅 2 调用点(归一须对两者安全)
gen_decls.ss:399  ... @ss_arraySlice(... i32 ${idx}, i32 2147483647)   # 解构 rest:非负 idx + sentinel
gen_builtins.ss:165 ... @ss_arraySlice(... i32 ${slStart}, i32 ${slEnd})  # method call
```

### 最危险假设的最小 spike 结果

**最危险假设**:runtime 归一破坏解构 rest 调用点(传 sentinel `2147483647`)或引入新 OOB。

最小 spike = 仅改 `gen_rt_array.ss`(1 文件,加负归一 + GEP 用 clamped `%s_c`),bootstrap + 实切验证:

```
$ ./build.sh bootstrap            → Fixed point verified! Stage 2 = Stage 3  (BOOTSTRAP_EXIT=0)
$ slice(1,-1)  → [20-30]   ✓ (oracle 20-30)
$ slice(-3,-1) → [20-30]   ✓ (原越界垃圾 [4-4])
$ slice(-10,2) → [10-20]   ✓ (原读未初始化内存)
$ slice(0,-100)→ []        ✓ (oracle 空)
$ slice(0,2)   → [10-20]   ✓ (正索引无回归)
$ 解构 const [x,...rest]=[10,20,30,40,50] → x=10 rest=[20-30-40-50]  ✓ (最危险假设证伪失败=假设成立,sentinel 路径未受影响)
$ bin/ss test tests/  → 344 passed, 3 failed, 347 total  (3 pre-existing: d096_p4_l2_reactive / harness_task / spring_web_params,持平)
```

**spike 通过** → 最危险假设成立(归一对 sentinel/非负 idx 无副作用),候选 B 可行性确认,全量实施(+ codegen 单参 + checker 1-2 + 回归测试)。
