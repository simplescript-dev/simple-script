# i033_runtime_bool_display.options.md — runtime bool→string 显示 "1"/"0" 偏离 parity 方案对比

> Bug: runtime bool 经 `genExprAsString` 落 `ss_int_to_string` → "1"/"0"(模板插值 / `+` 拼接 / 数组 `.join` / `println`),偏离 comptime oracle `interpToStr`→"true"/"false"(interp_op.ss:35)+ JS `String(true)="true"`。
> RED:`let b=true; \`${b}\`` → "1";`[true,false].join("-")` → "1-0";comptime 同式 → "true-false"(oracle 反转)。
> 来源:D171 §下一步 finding A 收口验收衍生 issue `docs/4-issues/I033-*.md`。

## 根因(单一概念根 = gen 层把 bool 折叠成 int,丢失显示/分派所需类型;两个折叠站点)

- **站点 A(类型推断折叠 — inferred/join 路径)**:`gen_types.ss:274` `inferType(TRUE_LIT/FALSE_LIT)` 返 `"int"`(非 `"bool"`)。后果:`let b=true` 经 `gen_decls.ss` `setVarType(name, initType)` 传播为 `int`;`[true,false]` 经 `inferArrayElemType` 首元素 `inferType`→`int` → `gen_methods.ss:542` dispatch `_ss_joinInt`(非 `_ss_joinBool`)。**显示路径永远拿不到 `"bool"` 类型**。
- **站点 B(显示分支缺失 — 全 sink)**:`genExprAsString`(exprs_str_conv.ss)分派 string/double/i64/ptr,**无 bool 分支** → 任何 `vType=="bool"` 值落最后 `ss_int_to_string`(行 42)。即便站点 A 修好让类型=bool,无此分支仍出 "1"/"0"。
- **bool@IR=i32 是正确低层表示**(`gen_types.ss:742` bool→i32,mangling `i`),**不动** —— 折叠点仅在类型推断字符串(A)+ 显示分支(B),非物理表示。

## 方案对比表

| 候选 | 层次 | 做法 | 假设破裂入口 | 在哪层消除/绕过 | 长久/演化(底层依赖链 + 业界对标 + N年返工度) |
|---|---|---|---|---|---|
| A | **数据层 patch** | 每个 sink 各自内联三元:`_ss_joinBool` 内 `arr[i]?"true":"false"` + genExprAsString 内同样三元;不引 `ss_bool_to_string` | **假设破裂入口** = "每个显示 sink 独立 stringify bool";A 在每个调用点**各自打补丁**,join 与模板插值各写一份 → 极易漂移不一致(`${b}`="true" vs 某 sink 漏改="1") | 仅在各调用点**绕过**,无单一真相源,治标 | 依赖链无新增但**重复** `ss_bool_to_string` 既有逻辑(gen_rt_string.ss:308);业界对标:per-sink stringify 是 ad-hoc;N年返工度**高**(新增 bool 显示 sink 又要补一份) |
| B | **接口层 trap** | 仅 `genExprAsString` 补 `if(vType=="bool")`→`ss_bool_to_string`(= I033 issue-doc 推荐方向) | **假设破裂入口** = "bool 值到达 genExprAsString 时 vType 已是 `bool`";**实测此假设破裂**:站点 A(line 274)把 `TRUE_LIT`→`int` → `let b=true`/`[true,false]` 经 genExprAsString 时 vType=`int`,**bool 分支不可达** | 仅消除 **annotated `let b:bool`** 路径(getVarType="bool");对 RED a(inferred var)/ RED b(数组 join 走 `_ss_joinInt`)**inert** | 依赖链:依赖站点 A 已修(未落地)→ **不满足**;业界对标:显示单一真相源方向对,但缺类型源头;N年返工度高(只修 1/3 RED) |
| C | **接口层根因(双站点,选定)** | **站点 A**:`gen_types.ss:274` `TRUE_LIT/FALSE_LIT`→`"bool"`(literal 推断回归 bool,流过 var 传播 + 数组元素 dispatch→`_ss_joinBool`)**+ 站点 B**:`genExprAsString` 补 bool 分支→`ss_bool_to_string`(显示单一真相源) | **假设破裂入口** = "gen 层把 bool 折叠成 int";C **从源头同时堵两个折叠站点**(推断站点 A + 显示站点 B),bool 类型完整流过 inferred var / 数组 dispatch / 显示全链 → bool 分支可达 | 在 **接口层**双站点消除折叠假设破裂:literal 推断给出 bool(A)、显示分支消费 bool(B),join 经 `_ss_joinBool` 内 `result+arr[i]` 复用同一 genExprAsString bool 分支 → 三 sink 单一真相源 | 依赖链:`ss_bool_to_string` + `_ss_joinBool` + dispatch **全现成**,无未落地依赖;业界对标:literal 类型保真 + 单态化 dispatch 是终态;N年返工度**低**(bool@IR=i32 不动,未来真 bool 一等类型亦扩展 C 而非推翻) |
| D | **架构层 refactor** | bool 升 IR 一等类型 `i1`(非 i32),全链 zext/trunc + checker/codegen/mangling 重写 | **假设破裂入口** = "bool 与 int 在 IR 同为 i32";D 改物理表示 i1 | 在**架构层**重建 bool 物理表示,理论最纯 | 依赖链:牵动 mangling(`i`→新符号)→ **ABI break** + 全量 zext/trunc;业界对标:LLVM 前端 bool 多以 i8/i32 存储避免 i1 对齐坑;N年返工度:**过度工程**(i32 表示本就正确,显示偏离不需改物理层),低收益高破坏 |

## 决策行

**选 C(接口层根因双站点)因** I033 RED 根因 = gen 层 bool→int 折叠致显示路径拿不到 bool 类型,**单站点修不全**:issue-doc 推荐的 B(仅 genExprAsString)对 inferred var(RED a)与数组 join(RED b,走 `_ss_joinInt`)**inert**(实测假设破裂 — 见 §实证)。C 在两个折叠站点同时消除(line 274 literal 推断回归 bool + genExprAsString 显示分支),bool 类型完整流过全链,三 sink(模板/拼接/join)复用同一 genExprAsString bool 分支单一真相源,零新 runtime IR、零新函数。

**为何不选 A(更浅数据层)**:per-sink 内联三元重复 `ss_bool_to_string` 既有逻辑、各写一份易漂移不一致,违反单一真相源——非根因。

**为何不选 B(issue-doc 推荐但不足)**:B 假设"bool 值到 genExprAsString 时类型=bool",但站点 A(line 274)折叠在前 → inferred/join 路径 bool 分支不可达,仅修 1/3 RED(annotated)。B 是 C 的子集,缺类型源头站点 A。**已自决策修正 issue-doc 推荐方向**(报告≠请示)。

**为何不选 D(更深架构层)**:bool@IR=i32(line 742)是正确低层表示,显示偏离不需改物理层;D 改 i1 触发 mangling ABI break + 全量 zext/trunc,过度工程,业界(LLVM 前端)亦避 i1 存储。C 的 i32 不动即终态。

## §实证(MNK §字段 12)

### 根因定位 grep 证据(命令 + 输出)

```
$ grep -n 'TRUE_LIT' bootstrap/gen/gen_types.ss
274:    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }   # 站点 A:bool 折叠 int
$ grep -n 'ss_int_to_string\|ss_bool_to_string\|vType == "bool"' bootstrap/gen/exprs/exprs_str_conv.ss
42:    ... call ptr @ss_int_to_string(i32 ${val})   # 站点 B:无 bool 分支,fallback 落此 → "1"/"0"
$ grep -n 'ss_joinBool\|ss_joinInt\|inferArrayElemType' bootstrap/gen/methods/gen_methods.ss
539: const elemType = inferArrayElemType(objId)   # [true,false] 首元素 inferType=int(站点A)→ ss_joinInt
542: if (elemType == "int") { jfn = "ss_joinInt" }
544: else if (elemType == "bool") { jfn = "ss_joinBool" }   # dispatch 正确但 elemType 被站点A 误判 int
$ grep -n 'define ptr @ss_bool_to_string' bootstrap/gen/rt/gen_rt_string.ss
308:(已 define;ne i32 0 → @.rt.str.true/.false)   # 现成,无需新 runtime IR
```

**关键假断言核对(issue-doc 推荐 B 的破裂证明)**:issue-doc §候选"genExprAsString 补 bool 分支 ... 惠及 join"= **假断言**。`_ss_joinBool` 是 pure SS prelude(prelude.ss:295,body `result+arr[i]`)无独立 runtime IR(`grep 'define.*ss_joinBool'` = 空);但 `[true,false]` 因站点 A 折叠 → dispatch `_ss_joinInt`(`arr[i]:int`)→ genExprAsString **int** 分支,bool 分支不可达。故 B 单站点对 join inert,必须配站点 A。

### RED 逐路径最小变量隔离(已跑)

```
literal  `${true}`                  → "true"   (TMPL_FRAG 常量折叠,本就对,非 RED)
inferred `let b=true; ${b}`         → "1"      ❌ RED a(站点 A 折叠 int + 站点 B 无分支)
annotated`let b:bool=true; ${b}`    → "1"      ❌ (站点 B 无分支;getVarType 已 bool)
bare     `let b:bool=false; println(b)` → "1"  ❌
join     `[true,false].join("-")`   → "1-0"    ❌ RED b(站点 A → ss_joinInt)
concat   `"v="+false`               → "v=0"    ❌
comptime `comptime{[true,false].join("-")}` → "true-false"  ✅ oracle(interpToStr)
```

### 最危险假设 + 最小 spike(选定候选 C)

- **最危险假设**:改 `TRUE_LIT/FALSE_LIT`→"bool"(站点 A)不破坏 bootstrap 固定点、不致 bool→int 折叠依赖处大面积回归(自洽前提:bool@IR=i32 同 mangling`i` → 仅 display/dispatch 变,无 ABI/alloca/算术变)。
- **最小 spike 实测(2 文件 ~5 LOC = 实现本身,< 字段12 大规模阈值)**:
  - **bootstrap 三阶段固定点 PASS**(Stage2==Stage3;编译器自身大量 `true`/`false` 字面量现 typed "bool" 不破 codegen → 验证 bool@i32 自洽)。
  - **行为矩阵全 GREEN**:inferred `${b}` "1"→"true"、annotated→"true"、bare→"false"、join "1-0"→"true-false"、concat "v=0"→"v=false"、多片段 `${b1}-${b2}`→"true-false";literal `${true}` 保持 "true";comptime oracle "true-false" 不变 → **runtime/comptime parity 兑现**。
  - **全测**:344 passed / 3 failed / 347 total。3 failed = pre-existing(`d096_p4_l2_reactive` reactive 符号解析 / `harness_task/main` harness env IR / `spring_web_params` dispatcherServlet checker),经 `git stash`(站点A+B)+ rebuild 基线复跑确认三者 baseline 即 fail、`findingA` baseline pass(exit 0),**本轮 0 新回归**;新增 `i033_runtime_bool_display.ss` regression + 修正 `findingA` 旧 "1-0" 断言 → 344=343 baseline pass + 1 新测。
  - **net delta**:net_new_ifs=1(genExprAsString bool 分支;line 274 为修改非新增)、net_new_fns=0、same_pattern_count=0(单一真相源,无第二处 workaround)。
