# i034_comparison_logical_bool.options.md — runtime comparison/logical→bool 推断残留致显示 parity 偏离 方案对比

> Bug: runtime `comparison`(Eq/Ne/Lt/Gt/Le/Ge)+ `logical`(And/Or)BINOP 经 `gen_types.ss:376-378` `inferType(BINARY)` 折叠成 `"int"` 类型字符串。后果:`let b=<比较/逻辑>` 经 `setVarType` 传播 `int`;`[1<2,3>4]` 经 `inferArrayElemType` 首元素 `inferType`→`int`→`gen_methods.ss:542` dispatch `_ss_joinInt`;`${b}`/拼接/join 三显示 sink 经 `inferType` 拿不到 `"bool"` → 落 `ss_int_to_string` 出 "1"/"0"。
> RED:`let b=1<2; \`${b}\`` → "1";`let c=true&&false; \`${c}\`` → "0";`[1<2,3>4].join("-")` → "1-0"。偏离 comptime oracle `interpNewBool`(`interp_op.ss:50-55` 比较 + short-circuit 逻辑)→ "true"/"false" + JS `String(1<2)="true"`。
> 来源:D171 §收口验收 I033(行 166)/ finding B(行 167)/ comptime-bool-return(行 168)末条显式列残余 backlog「I034 comparison→bool runtime 推断残留」。**是 I033 runtime 字面量折叠(`gen_types.ss:278` 已修 "bool")+ comptime-bool-return(`gen_types.ss:324` 已修 "bool")的镜像同根第三站点**(gen 层 bool→int 折叠族;I033 修字面量站点、comptime-bool-return 修 comptime-return 站点、本轮修 comparison/logical BINOP 站点)。

## 根因(单一概念根 = gen 层把 comparison/logical/instanceof BINOP 产出折叠成 int,丢失显示/分派所需类型;第三折叠站点)

- **站点 A(类型推断折叠 — 根)**:`gen_types.ss:376-378` `inferType(BINARY)` 对 `op==Eq/Ne/Lt/Gt/Le/Ge/And/Or/Instanceof` 一律 `return "int"`。后果:`let b=1<2` 经 `setVarType` 传播 `int`;`[1<2,3>4]` 经 `inferArrayElemType` 首元素 `inferType`→`int` → dispatch `_ss_joinInt`(非 `_ss_joinBool`);`genExprAsString`(`exprs_str_conv.ss:5` `inferType`)拿到 `int`→`ss_int_to_string`。**三 sink 永远拿不到 `"bool"` 类型**。comptime 侧 `interp_op.ss:50-55` 比较 / short-circuit 逻辑均返 `interpNewBool`(oracle 已正确)。
- **假设破裂入口(算术 fallthrough — 必须同闭合)**:`gen_types.ss:379-383` 通用算术/位运算分支 `return binLt`。原假设「comparison 结果类型只喂显示 sink」**破裂**于 `(a<b)+1` 等把 comparison 结果喂算术:站点 A 改 `"bool"` 后,`inferType(Add)` 经 line 379 `binLt=inferType(a<b)="bool"` → `return binLt="bool"` → `${(a<b)+1}` 误显 "true"(实测 comptime oracle `(1<2)+1`=2)。**这是改站点 A 会引入的新 parity 破裂**,必须在同一接口层归一(JS `bool→number` 强制,算术/位运算 bool 操作数结果是 int)。**同时闭合 I033 遗留同类漏**:`let x=true+1` 现已误显 "true"(I033 把 `true`→"bool" 后算术 fallthrough 同漏,实测 `boollit=true`)。
- **显示侧 + join + Not-unary 已就绪(I033/findingA/UNARY 遗产,不动)**:`genExprAsString` bool 分支(`exprs_str_conv.ss:35`→`ss_bool_to_string`)+ `ss_joinBool`(`gen_methods.ss:544` dispatch)+ `inferType(UNARY)`(`gen_types.ss:586` 委派操作数类型,`!(a<b)` 自动得 bool)**全现成**;站点 A 让类型回归 bool 后三 sink + Not-unary 自动复用,零新 runtime IR/函数。
- **bool@IR=i32 是正确低层表示**(`ssTypeToLLVM:750` bool→i32;mangling `i`;`exprs_binary.ss` 各 cmp/短路/instanceof 出口 `zext i1→i32` 字节一致),**不动** —— 折叠点仅在类型推断字符串(站点 A),非物理表示。

## 方案对比表

| 候选 | 层次 | 做法 | 假设破裂入口 | 在哪层消除/绕过 | 长久/演化(底层依赖链 + 业界对标 + N年返工度) |
|---|---|---|---|---|---|
| A | **数据层 patch** | 每个显示 sink(模板 codegen / 拼接 / join 变体)各自检测 BINARY comparison/logical 节点并内联三元 `?"true":"false"`;不动 inferType | **假设破裂入口** = "每个显示 sink 独立 stringify 比较结果";A 在每个调用点**各自打补丁**,模板与 join 各写一份 → 极易漂移不一致(`${a<b}`="true" vs 某 sink 漏改="1") | 仅在各调用点**绕过**,无单一真相源,治标 | 依赖链无新增但**重复** `ss_bool_to_string` 既有逻辑(I033 已建);业界对标:per-sink stringify 是 ad-hoc;N年返工度**高**(新增比较显示 sink 又补一份) |
| B | **接口层 trap(仅显示侧 — workaround)** | 仅在 `genExprAsString` 对 BINARY comparison/logical 节点补特判走 `ss_bool_to_string`;不动 inferType | **假设破裂入口** = "bool 值到 genExprAsString 时 vType 已是 `bool`";**破裂**:站点 A(line 377)把 comparison BINOP→`int` → `let b=a<b` 经 `setVarType` 已是 int / `genExprAsString` line 5 `inferType` 拿到 `int`,bool 分支不可达;且对 join(`inferArrayElemType`→`inferType`→int→`ss_joinInt`)**inert** | 仅在显示侧**绕过**单一 sink,var 传播 / join inert;**且是 I033 + comptime-bool-return 站点 A 教训的镜像违反**(显示侧 workaround,勿补特判) | 依赖链:依赖站点 A 已修(未落地)→ **不满足**;业界对标:缺类型源头;N年返工度高(只修 1/3 sink) |
| C | **接口层根因(inferType 单站点 + 算术 fallthrough 闭合,选定)** | **站点 A**:`gen_types.ss:377` comparison/logical/instanceof BINOP `return "int"` → `return "bool"`(值物化 IR 不变,各 cmp 出口仍 `zext i1→i32`)**+ 假设破裂闭合**:`gen_types.ss:383` 算术/位运算 fallthrough `return binLt` 前加 `if (binLt=="bool") return "int"`(JS bool→number 强制) | **假设破裂入口** = "gen 层把 comparison/logical 折叠成 int"(与 I033 `TRUE_LIT`/comptime-bool-return 折叠**同族第三站点**)+ "comparison 结果类型只喂显示"(`(a<b)+1` 喂算术 fallthrough);C 在**类型推断单站点**消除折叠,bool 类型经 `inferType` 流过 var 传播 + 数组 dispatch + 显示全链 + Not-unary,**并在同接口层归一算术 bool→int** | 在**接口层**消除两处假设破裂:`inferType` 给出 bool(三 sink 复用 `genExprAsString` bool 分支 I033 + `ss_joinBool`);算术 fallthrough 归一 int(parity comptime `(1<2)+1`=2)→ 单一真相源 | 依赖链:`ss_bool_to_string`+`ss_joinBool`+`genExprAsString` bool 分支 + `inferType(UNARY)` 委派 **全现成**(I033/findingA 已落地),无未落地依赖;业界对标:materialization 类型保真 + 单态化 dispatch 是终态;N年返工度**低**(bool@IR=i32 不动,未来真 bool 一等类型亦扩展 C 而非推翻;**与 I033/comptime-bool-return 站点 A 同根同模板,三站点对称闭合**;附带闭合 I033-latent `true+1` 漏 + `!(a<b)` Not-unary parity) |
| D | **架构层 refactor** | bool 升 IR 一等类型 `i1`(非 i32),全链 zext/trunc + checker/codegen/mangling 重写 | **假设破裂入口** = "bool 与 int 在 IR 同为 i32";D 改物理表示 i1 | 在**架构层**重建 bool 物理表示,理论最纯 | 依赖链:牵动 mangling(`i`→新符号)→ **ABI break** + 全量 zext/trunc;业界对标:LLVM 前端 bool 多以 i8/i32 存储避免 i1 对齐坑;N年返工度:**过度工程**(i32 表示本就正确,显示偏离不需改物理层),低收益高破坏 |

## 决策行

**选 C(接口层根因 inferType 单站点 + 算术 fallthrough 闭合)因** RED 根因 = gen 层把 comparison/logical/instanceof BINOP 产出折叠成 int(`gen_types.ss:377`)致三显示 sink 经 `inferType` 拿不到 bool 类型,**与 I033 字面量折叠(line 278)+ comptime-bool-return 折叠(line 324)同族同根第三站点**。C 在类型推断单站点消除折叠(line 377 返 "bool"),bool 类型完整流过 var 传播 / 数组 join dispatch / 显示全链 / Not-unary,三 sink(模板/拼接/join)复用 `genExprAsString` 既有 bool 分支(I033 遗产)+ `ss_joinBool` 单一真相源,零新 runtime IR/函数;**并在同接口层归一算术 fallthrough bool→int**(line 383)闭合「comparison 结果喂算术」假设破裂(否则 `(a<b)+1` 误显 "true",且顺带修 I033-latent `true+1` 漏)。**对齐 I033/comptime-bool-return 站点 A 模板**(推断返 "bool" 让 bool 类型流过全链,禁显示侧补特判)。

**instanceof 纳入根因闭合(同 line 376 sibling)**:`instanceof` 同 `gen_types.ss:376` 同 return、同 gen 层 bool 折叠根、JS `String(x instanceof Y)`="true"/"false"、IR 出口同 i32(`exprs_binary.ss:201-216` zext)、bootstrap 不以 operator 使用(`grep instanceof bootstrap/` 仅 eval import,零风险)、tests 全在 `if(x instanceof Y)` 条件态(真值 type-agnostic,不断言显示);**排除它反需额外拆 line 376 条件且留 sibling 偏离** → 纳入。注:comptime 不支持 instanceof(`error: [comptime] operator 'Instanceof' not supported`),parity 基准为 JS 语义(无 comptime==runtime 项)。

**为何不选 A(更浅数据层)**:per-sink 内联三元重复 `ss_bool_to_string` 既有逻辑、各写一份易漂移不一致,违反单一真相源——非根因。

**为何不选 B(仅显示侧 — workaround)**:B 假设"bool 值到 genExprAsString 时类型=bool",但站点 A 折叠在前 → var 传播 / join 路径 bool 不可达,仅修 1/3 sink;且 B 在显示侧补特判 = **I033 + comptime-bool-return 站点 A 教训的镜像违反**。B 是 C 的子集,缺类型源头站点 A。

**为何不选 D(更深架构层)**:bool@IR=i32(`ssTypeToLLVM:750`)是正确低层表示,显示偏离不需改物理层;D 改 i1 触发 mangling ABI break + 全量 zext/trunc,过度工程,业界(LLVM 前端)亦避 i1 存储。C 的 i32 不动即终态。

## §实证(MNK §字段 12)

### 根因定位 grep 证据(命令 + 输出)

```
$ sed -n '376,383p' bootstrap/gen/gen_types.ss
        if (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge" || op == "And" || op == "Or" || op == "Instanceof") {
            return "int"                                            # 站点 A:comparison/logical/instanceof 折叠 int
        }
        const binLt = inferType(nGetI1(id))
        const binRt = inferType(nGetI2(id))
        if (binLt == "double" || binRt == "double") { return "double" }
        if (binLt == "i64") { return "int" }
        return binLt                                                # 假设破裂入口:算术 fallthrough 漏 binLt="bool"
$ sed -n '278p;324p' bootstrap/gen/gen_types.ss
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "bool" }   # I033 字面量站点(同族,已修)
            if (ceType == "bool") { ... return "bool" }                # comptime-bool-return 站点(同族,已修)
$ sed -n '50,55p' bootstrap/eval/interp_op.ss
    if (op == "Eq") { return interpNewBool(a == b ? 1 : 0) }   # comptime oracle:比较返 bool tv → "true"/"false"
    ... (Ne/Lt/Gt/Le/Ge 同) ;  short-circuit And/Or 亦返 interpNewBool
$ sed -n '35,37p' bootstrap/gen/exprs/exprs_str_conv.ss
    if (vType == "bool") { ... call ptr @ss_bool_to_string(i32 ${val}) }   # 显示分支现成(I033 遗产)
$ grep -n 'ss_joinBool' bootstrap/gen/methods/gen_methods.ss
544:        else if (elemType == "bool") { jfn = "ss_joinBool" }   # join dispatch 现成(findingA 遗产)
$ sed -n '586p' bootstrap/gen/gen_types.ss
    if (kind == "UNARY") { return inferType(nGetI1(id)) }   # Not-unary 委派操作数 → !(a<b) 自动得 bool
$ grep -rn 'instanceof' bootstrap/   # 仅 eval import,bootstrap 不以 operator 使用 → 纳 instanceof 零风险
bootstrap/eval/eval_expr.ss:12:import { evalInstanceofOrAs } from "./instanceof_as"
```

**关键假断言核对(候选 B 破裂证明)**:候选 B「仅 genExprAsString 补特判」对 inferred var / join **inert**。`genExprAsString`(`exprs_str_conv.ss:5`)`const vType = inferType(id)`——对 `let b=a<b` 的 IDENT 节点 `vType=getVarType(b)`,而 `b` 经 `setVarType` 存的是站点 A 推断的 `"int"`(line 377);`[1<2,3>4].join` 经 `inferArrayElemType`→首元素 `inferType`→int→`ss_joinInt`。故必须修类型源头站点 A(返 "bool")让 var/join 经 `inferType` 拿到 bool,B 单显示侧不足。**与 I033/comptime-bool-return §字段12「站点 A 必修」实证同构**。

### RED 逐路径最小变量隔离(已跑 — 当前 bin/ss = I033+comptime-bool-return 已修、I034 未修)

```
inferred  `let b=1<2; ${b}`         → "lt=1"      ❌ RED 主(站点 A 折叠 int)
logical   `let c=true&&false; ${c}` → "and=0"     ❌ (短路同折)
logical   `(1>2)||(3<4)`            → "or=1"      ❌
eq/ne     `3==3` / `5!=6`           → "1" / "1"   ❌
join      `[1<2,3>4].join("-")`     → "1-0"       ❌ (站点 A → ss_joinInt)
not-unary `!(a<b)` (a=5,b=3)        → "not=1"     ❌ (委派站点 A int)
instanceof`a instanceof Animal`     → "inst=1"    ❌ (line 376 int;JS 期望 true)
comptime  `[1<2,3>4].join("-")`     → "true-false" ✅ oracle(interpNewBool)
── 假设破裂入口实测(改站点 A 会引入的新 parity 破裂)──
arith-var `let x=(a<b)+1; ${x}` (a=5,b=3) → "arithvar=1"  现 int;改站点A 无 fallthrough 闭合 → "true"(破裂)
arith-lit `let x=true+1; ${x}`      → "boollit=true"  ❌ I033-latent 同类漏(算术 fallthrough)
comptime  `(1<2)+1`                 → "ct_arith=2"  ✅ oracle = int 2(故算术结果必 int,不可 bool)
── 范围外(pre-existing 独立根因,不混入)──
global    `let g=1<2`(module 顶层)  → llc error `store ptr 1`(全局非字面量 int/bool 物化为 ptr null,
                                       与 inferType 显示无关 = 另根因;currently 非编译,无 passing test 依赖)
```

### 最危险假设 + 最小 spike(选定候选 C)

- **最危险假设 1**:改 comparison/logical/instanceof BINOP→"bool"(站点 A)不破坏 bootstrap 固定点(编译器自身海量比较/逻辑现 typed "bool")、不致大面积回归(bool@IR=i32 同 mangling`i` → 仅 display/dispatch 变,无 ABI/alloca/算术/condition 变;`if`/`while`/三元条件走真值 `icmp ne i32 0` type-agnostic,实测 grep `inferType== "int"` 消费点 in gen/stmts+gen/exprs = 空)。
- **最危险假设 2**:算术 fallthrough 闭合 `if(binLt=="bool")return "int"` 充分覆盖所有 bool-喂-算术 路径,不误伤合法 bool 流(fallthrough 仅 As/comparison/逻辑/instanceof/Add-string return 之后到达 → 处理 Add(非string)/Sub/Mul/Div/Mod/Bit*,bool 操作数恒应 coerce int;binLt 是唯一 bool 漏点,binRt=="bool" 而 binLt 非 bool 已 return 非-bool binLt)。
- **最小 spike(2 处编辑,1 文件 gen_types.ss ≈ 11 LOC < §字段12 大规模阈值 = 实现本身)**:站点 A line 377 `"int"`→`"bool"` + line 383 前加算术归一 → `./build.sh bootstrap` 三阶段固定点 + 全测 + 行为矩阵 GREEN。spike 实测(Execute 后回填):
  - **bootstrap 三阶段固定点**:PASS(Stage 2 = Stage 3,bin/ss 更新,29s)。
  - **行为矩阵全 GREEN**:`lt=true`/`and=false`/`or=true`/`eq=true`/`ne=true`(comparison+logical 6 运算符)、`join=true-false`(数组 join sink)、`not=true`(`!(a<b)` Not-unary 委派)、`inst=true`(instanceof);假设破裂闭合 `arithvar=1`(`(a<b)+1` 归 int 非 "true")、`boollit=2`(`true+1` 归 int,I033-latent 闭合);`if`/`while`/三元条件不变。
  - **comptime==runtime parity**:`lt rt=false ct=false` / `and rt=true ct=true` / `not rt=true ct=true` / `join rt=false-true ct=false-true` 逐一比对零偏离。
  - **全测**:347 passed / 3 failed / 350 total = 346 baseline + 1 新测(`i034_comparison_logical_bool.ss`),3 pre-existing(`d096_p4_l2_reactive`/`harness_task/main`/`spring_web_params`)不变,**0 新回归**。VCM §3:stash `gen_types.ss` + rebuild → RED test exit 1 ↔ 恢复 exit 0。
  - **范围外验证**:global 顶层 `let g=1<2` 仍 llc `store ptr 1` error(与修复前**字节一致**,pre-existing 独立根因未触及,无 regression)。
  - **net delta**:net_new_ifs=0(simplify 采纳合并:算术 fallthrough 既有 `if(binLt=="i64")` guard 并入 bool → `if(binLt=="i64"||binLt=="bool")`,非新增 if;line 377 同行修改)、net_new_fns=0、same_pattern_count=0(comparison/logical/instanceof 折叠唯一站点 gen_types.ss:377 已修;显示/join/Not-unary 全复用 I033/findingA 遗产,无第二处残留)。
  - **reflection/sunset gate**:reflection_health GATE PASS(gen_types 927≤1050,DRIFT 软)+ sunset GATE OK 无新 marker。
