# comptime_bool_return_fold.options.md — comptime-scalar bool-return 折叠 int 致显示 parity 偏离 方案对比

> Bug: `comptime { return true }` 经 `gen_types.ss:324` `inferType(COMPTIME_EXPR)` 把 `interpType=="bool"` 的返回值折叠成 `"int"` 类型字符串(literal 存 `tvIntOf`=1/0)。后果:`${b}` 模板插值 / `"v="+b` 拼接 / `[b1,b2].join` 三显示 sink 经 `inferType` 拿到 `"int"` → 落 `ss_int_to_string` 出 "1"/"0"。
> RED:`let b=comptime{return true}; \`${b}\`` → "1";`comptime{return 1<2}` → "1";偏离 comptime oracle `interpToStr`(interp_op.ss:50-55 比较/逻辑亦返 `interpNewBool`)→ "true"/"false" + JS `String(true)="true"`。
> 来源:D171 §收口验收 I033(docs/3-decisions/D171 行 166)显式列残余 backlog「comptime-scalar bool-return 折叠(gen_types.ss:318)」。**是 I033 runtime 字面量折叠的镜像同根**(gen 层 bool→int 折叠族;I033 修字面量站点 line 278,本轮修 comptime-return 站点 line 324)。

## 根因(单一概念根 = gen 层把 bool 折叠成 int 丢失显示/分派所需类型;comptime-return 站点)

- **站点 A(类型推断折叠 — 根)**:`gen_types.ss:323-327` `inferType(COMPTIME_EXPR)` 对 `ceType=="bool"` 分支 `set "int"` + `return "int"`。后果:`let b=comptime{return true}` 经 `setVarType` 传播 `int`;`[b1,b2]` 经 `inferArrayElemType` 首元素 `inferType`→`int`→`gen_methods.ss:544` dispatch `_ss_joinInt`(非 `_ss_joinBool`);`genExprAsString`(exprs_str_conv.ss:5 `inferType`)拿到 `int`→`ss_int_to_string`。**三 sink 永远拿不到 `"bool"` 类型**。
- **站点 B(消费侧补全 — 防 regression)**:`gen_decls.ss:255-276` 全局变量物化路径有 int/double/string/type/array case,**无 bool case**。站点 A 改 `"bool"` 后,全局 `let g=comptime{return true}` 会从现在的 `global i32 1` 退化落 `else`(line 272)→ `global ptr null` + 误入 runtime init queue(bool@IR 是 i32 非 ptr)→ **新 regression**。须补 bool case → `global i32 ${ceLit}`。
- **显示侧已就绪(I033 遗产,不动)**:`genExprAsString` bool 分支(exprs_str_conv.ss:35→`ss_bool_to_string`)+ `ss_joinBool`(gen_methods.ss:544 dispatch)**全现成**;站点 A 让类型回归 bool 后,三 sink 自动复用,零新 runtime IR/函数。
- **bool@IR=i32 是正确低层表示**(`gen_types.ss:746` bool→i32,mangling `i` line 847),**不动** —— 折叠点仅在类型推断字符串(A),非物理表示。值物化亦不变(`eval_expr.ss:102` bool 走 `constVal` 同 int)。

## 方案对比表

| 候选 | 层次 | 做法 | 假设破裂入口 | 在哪层消除/绕过 | 长久/演化(底层依赖链 + 业界对标 + N年返工度) |
|---|---|---|---|---|---|
| A | **数据层 patch** | 每个显示 sink(模板 codegen / 拼接 / join 变体)各自检测 COMPTIME_EXPR bool-return 并内联三元 `?"true":"false"`;不动 inferType | **假设破裂入口** = "每个显示 sink 独立 stringify comptime bool";A 在每个调用点**各自打补丁**,模板与 join 各写一份 → 极易漂移不一致(`${b}`="true" vs 某 sink 漏改="1") | 仅在各调用点**绕过**,无单一真相源,治标 | 依赖链无新增但**重复** `ss_bool_to_string` 既有逻辑(I033 已建);业界对标:per-sink stringify 是 ad-hoc;N年返工度**高**(新增 comptime 显示 sink 又补一份) |
| B | **接口层 trap(仅显示侧 — workaround)** | 仅在 `genExprAsString` 对 COMPTIME_EXPR 节点补特判:若 bool-return comptime 直接走 `ss_bool_to_string`;不动 inferType | **假设破裂入口** = "bool 值到 genExprAsString 时 vType 已是 `bool`";**破裂**:站点 A(line 324)把 COMPTIME_EXPR bool→int → `genExprAsString` line 5 `inferType` 拿到 `int`,bool 分支不可达;且对 join(走 `inferArrayElemType`→`inferType`→int→`ss_joinInt`)**inert** | 仅在显示侧**绕过**单一 sink,join/var 传播 inert;**且是 I033 站点 A 教训的镜像违反**(显示侧 workaround,勿补特判) | 依赖链:依赖站点 A 已修(未落地)→ **不满足**;业界对标:缺类型源头;N年返工度高(只修 1/3 sink) |
| C | **接口层根因(inferType 单站点 + 消费侧补全,选定)** | **站点 A**:`gen_types.ss:324` COMPTIME_EXPR `ceType=="bool"` → `set "bool"` + `return "bool"`(literal 仍 `tvIntOf`=1/0 不变)**+ 站点 B**:`gen_decls.ss` 全局路径补 bool case → `global i32 ${ceLit}` 防 regression | **假设破裂入口** = "gen 层把 comptime bool-return 折叠成 int"(与 I033 `TRUE_LIT/FALSE_LIT` 字面量折叠**同族**);C 在**类型推断单站点**消除折叠,bool 类型经 `inferType` 流过 var 传播 + 数组 dispatch + 显示全链 + 全局物化 | 在**接口层**消除折叠假设破裂:`inferType` 给出 bool,三 sink 复用 `genExprAsString` 既有 bool 分支(I033)+ `ss_joinBool`,全局物化补 i32 case → 单一真相源 | 依赖链:`ss_bool_to_string`+`ss_joinBool`+`genExprAsString` bool 分支 **全现成**(I033 已落地),无未落地依赖;业界对标:materialization 类型保真 + 单态化 dispatch 是终态;N年返工度**低**(bool@IR=i32 不动,未来真 bool 一等类型亦扩展 C 而非推翻;**与 I033 站点 A 同根同模板,对称闭合**) |
| D | **架构层 refactor** | bool 升 IR 一等类型 `i1`(非 i32),全链 zext/trunc + checker/codegen/mangling 重写 | **假设破裂入口** = "bool 与 int 在 IR 同为 i32";D 改物理表示 i1 | 在**架构层**重建 bool 物理表示,理论最纯 | 依赖链:牵动 mangling(`i`→新符号)→ **ABI break** + 全量 zext/trunc;业界对标:LLVM 前端 bool 多以 i8/i32 存储避免 i1 对齐坑;N年返工度:**过度工程**(i32 表示本就正确,显示偏离不需改物理层),低收益高破坏 |

## 决策行

**选 C(接口层根因 inferType 单站点 + 消费侧补全)因** RED 根因 = gen 层把 comptime bool-return 折叠成 int(`gen_types.ss:324`)致三显示 sink 经 `inferType` 拿不到 bool 类型,**与 I033 字面量折叠(line 278,已修 "bool")同族同根**。C 在类型推断单站点消除折叠(line 324 返 "bool",literal 不变),bool 类型完整流过 var 传播 / 数组 join dispatch / 显示全链,三 sink(模板/拼接/join)复用 `genExprAsString` 既有 bool 分支(I033 遗产)+ `ss_joinBool` 单一真相源,零新 runtime IR/函数;站点 B 补全局物化 bool case 防 regression。**对齐 I033 站点 A 模板**(推断返 "bool" 让 bool 类型流过全链,禁显示侧补特判)。

**为何不选 A(更浅数据层)**:per-sink 内联三元重复 `ss_bool_to_string` 既有逻辑、各写一份易漂移不一致,违反单一真相源——非根因。

**为何不选 B(仅显示侧 — workaround)**:B 假设"bool 值到 genExprAsString 时类型=bool",但站点 A 折叠在前 → var/join 路径 bool 不可达,仅修 1/3 sink;且 B 在显示侧补特判 = **I033 站点 A 教训的镜像违反**(I033 §字段12 实证修正过"仅 genExprAsString inert")。B 是 C 的子集,缺类型源头站点 A。

**为何不选 D(更深架构层)**:bool@IR=i32(line 746)是正确低层表示,显示偏离不需改物理层;D 改 i1 触发 mangling ABI break + 全量 zext/trunc,过度工程,业界(LLVM 前端)亦避 i1 存储。C 的 i32 不动即终态。

## §实证(MNK §字段 12)

### 根因定位 grep 证据(命令 + 输出)

```
$ sed -n '323,327p' bootstrap/gen/gen_types.ss
            if (ceType == "bool") {
                comptimeExprType.set(ceKey, "int")          # 站点 A:comptime bool-return 折叠 int
                comptimeExprLiteral.set(ceKey, `${tvIntOf(ceRetVal)}`)
                return "int"
            }
$ sed -n '278p' bootstrap/gen/gen_types.ss
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "bool" }   # I033 字面量站点(同族,已修 "bool")
$ sed -n '35,38p' bootstrap/gen/exprs/exprs_str_conv.ss
    if (vType == "bool") {                                              # 显示分支现成(I033 遗产)
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_bool_to_string(i32 ${val})`)
$ grep -n 'ss_joinBool' bootstrap/gen/methods/gen_methods.ss
544:        else if (elemType == "bool") { jfn = "ss_joinBool" }        # join dispatch 现成
$ sed -n '255,276p' bootstrap/gen/gen_decls.ss   # 全局物化:int/double/string/type/array,无 bool case → 站点 B 补
$ grep -n 'interpNewBool' bootstrap/eval/interp_op.ss | head -2
50:    if (op == "Eq") { return interpNewBool(...) }                    # 比较/逻辑 comptime 返 bool tv → 站点 A 自动覆盖
$ sed -n '102p' bootstrap/eval/eval_expr.ss
        return 0 - constVal(comptimeExprLiteral.getString(ceK)) - 1    # 值物化:bool 走 constVal 同 int(literal 1/0 不变)
```

**关键假断言核对(候选 B 破裂证明)**:候选 B「仅 genExprAsString 补特判」对 comptime bool-return **inert**。`genExprAsString`(exprs_str_conv.ss:5)`const vType = inferType(id)`——对 COMPTIME_EXPR 节点 `inferType` 返站点 A 缓存的 `"int"`(line 324),bool 分支(line 35)不可达;`[b1,b2].join` 经 `inferArrayElemType`→首元素 `inferType`→int→`ss_joinInt`,亦绕过。故必须修类型源头站点 A(返 "bool")让三 sink 经 `inferType` 拿到 bool,B 单显示侧不足。**与 I033 §字段12「双站点」实证同构**——I033 站点 A 修字面量推断,本轮站点 A 修 comptime-return 推断,显示站点 B(genExprAsString bool 分支)I033 已建复用。

### RED 逐路径最小变量隔离(已跑)

```
literal   `${true}`                          → "true"   (TMPL_FRAG 常量折叠,本就对,非 RED)
comptime  `let b=comptime{return true}; ${b}`→ "1"      ❌ RED 主(站点 A 折叠 int)
comptime  `comptime{return 1<2}`             → "1"      ❌ RED 比较(interpNewBool → 站点 A 折 int)
global    `let g=comptime{return true}; ${g}`→ "1"      ❌ RED 全局(现走 int case 输出 "1",改后须站点 B 防 ptr null regression)
comptime-oracle `comptime{ if(true){return "T"} }`      ✅ interpToStr bool="true"(oracle 方向)
```

### 最危险假设 + 最小 spike(选定候选 C)

- **最危险假设**:改 `inferType(COMPTIME_EXPR)` bool→"bool"(站点 A)不破坏 bootstrap 固定点、不致 bool→int 折叠依赖处大面积回归(自洽前提:bool@IR=i32 同 mangling `i`,值物化 `eval_expr.ss:102` 经 `constVal` 与 int 字节一致 → 仅 display/dispatch/全局物化类型字符串变,无 ABI/alloca/算术变;站点 B 补全局物化 i32 case 闭合唯一退化点)。
- **最小 spike(预期验证,VCM §N 兑现实测)**:
  - **bootstrap 三阶段固定点 PASS**(Stage2==Stage3;编译器自身大量 comptime 块,bool@i32 自洽不破 codegen)。
  - **行为矩阵全 GREEN**:comptime function-local `${b}` "1"→"true"、global "1"→"true"(站点 B)、comparison `1<2` "1"→"true"、logical `&&`/`||`、concat `"v="+comptime{...}`、join `[b1,b2].join` "1-0"→"true-false"、多片段 `${b1}-${b2}`;comptime==runtime parity(`comptime{return true}` 显示 == runtime `let r=true` 显示)。
  - **全测**:baseline 345 持平(3 pre-existing 不变:d096_p4_l2_reactive / harness_task/main / spring_web_params),+1 新测 `comptime_bool_return_fold.ss` → 346;VCM §3 stash(站点A+B)+ rebuild → RED test exit≠0 因果验证。
  - **net delta**:net_new_ifs=1(gen_decls 全局 bool case;站点 A line 324 为修改既有 if 非新增)、net_new_fns=0、same_pattern_count=0(单一真相源,无第二处 workaround)。
  - **reflection/sunset/bugfix gate**:改动域 gen_types.ss(bm=1050 充裕)+ gen_decls.ss(745→≤749 ≤ bm=750)非反射白名单 → GATE PASS 预期;无新过渡件 → sunset OK。
