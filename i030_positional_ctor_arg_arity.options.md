# I030 — positional-partial 构造调用未补齐到构造函数 arity — 修复方案对比(MNK §轨 1)

**bug**: `genNewExpr`(`bootstrap/gen/class/class.ss:251`)的位置实参分支(改前 `:306-318`)与 `genGenericNewExpr`(`bootstrap/gen/gen_generic_class.ss:238`)的实参循环(改前 `:336-350`)拼构造函数调用实参时,只发射「显式提供的位置实参」,不补齐到构造函数声明的全字段 arity。带可选(`?`)/默认值字段的类被位置部分构造(`new Bug("test-bug")` —— 7 字段只给 1)时,生成的 `call @ClassName_new(...)` 实参数少于 `ClassName_new` 声明的形参数;被调函数从未初始化 ABI 寄存器/栈槽读取缺失实参,对象未提供字段被垃圾初始化。可选 `fn` 字段的垃圾值骗过 `!= 0` 守卫、`call` 进垃圾地址 → SIGSEGV(test_121 = `tests/phase5/harness_bug/main.ss` 确定性段错误)。

**父约束**: 独立 root cause(I030)。关联 D149(partial named arg ctor + field default value)/ D150 —— D149 主线只把 NEW_EXPR ctor 的 **named + empty** 两路径并入统一填充 helper `genCtorArgsWithDefaults`(`class_method.ss:135` 注释明列「Used by both partial named arg path 和 全 default 空 ctor path」),**positional 路径从未并入**。本 bug 是该「三分支统一」未完成的位置路径同胞缺口。业界对标:TS / Dart / Kotlin 的构造默认值机制是单一参数填充路径,不分 named / positional 两套。

**结论**: **选 C —— positional 分支并入既有 `genCtorArgsWithDefaults`**(见 §4 决策行)。

---

## 1. 根因机理(坐实)

`genNewExpr` 拼 `${args}` 分三支:`hasNamed` → `genNamedConstructorArgs` → `genCtorArgsWithDefaults`;`argList == ""` → 直调 `genCtorArgsWithDefaults`;**`argList != ""`(位置实参)→ 自有 `for (p in parts)` 裸循环**,只对每个已提供实参发射 `${llType} ${val}`,无补齐。`genCtorArgsWithDefaults`(`class_method.ss:138`)遍历类**全部字段**,缺字段查默认值表达式 / 退类型正确零值(`ptr null` / `i64 0`),恒产满 arity 实参表 —— 分支 1/2 经它正确,分支 3 不经它。

`Bug`(`lib/harness/bug.ss`)7 字段(`name` + `importance? urgency? round? certainty? detectedCb? fixedCb?` 六可选),`Bug_new` 定义 7 形参且无条件 `store i64 %detectedCb.arg`(`detectedCb` 偏移 `0x28`)。`new Bug("test-bug")` 经分支 3 → IR `call ptr @Bug_new(ptr @.str.98)` 仅 1 实参;`main` 汇编只设 `%rdi` → `Bug_new` 从未初始化 `%r9` 读出 `detectedCb` = `0x200`。`bug` 因紧接 `onDetected(arrow)` 覆写 `detectedCb` 故无害;`bug2 = new Bug("no-callbacks")` 无 `onDetected` → `bug2.detected(3,3)` 内 `if (this.detectedCb != 0) this.detectedCb()` → `call *0x200` → SIGSEGV。`genGenericNewExpr` 同址同形(且无 `argList == ""` 分支 → `new Generic<T>()` 0 实参更严重)。

## 2. 假设破裂入口

位置实参分支(`class.ss` 改前 `:306-318`)隐含未校验**假设**:「位置实参个数 == 构造函数形参个数」(用户总提供全部字段)。**假设破裂**:类带可选 / 默认值字段时位置构造允许只给前缀 —— checker `check_exprs.ss:254` `checkArgCount` 以 `[min,max]` 放行 `argCount < 字段数`(未提供尾部是可选 / 默认字段时合法)。`for (p in parts)` 只迭代「已提供实参」、`emitIR(call @X_new(${args}))` 直接发射 → 实参表长度 = 已提供数 ≠ 构造函数 arity。该假设在「位置部分构造」下必然破裂;`genGenericNewExpr` 同址同假设破裂入口。

## 3. 候选方案对比

| 候选 | 层次 | 改动 | 评估 |
|---|---|---|---|
| A | 数据层 patch | 位置裸循环后按 `字段数 − 已发数` 手动 append `, i64 0` 补足 arity | codegen 拼 `${args}` 这步不持有字段「默认值表达式 id」与「LL 类型」。硬编码 `i64 0`:有 `= 默认值` 的字段(`count: int = 5`)被错补 `0`、`ptr` / `double` 字段补 `i64 0` 触 LLVM 类型不匹配。只补「数目」不补「正确值 / 类型」,假设破裂处仅打补丁 —— 表面解 |
| B | 接口层 trap | 位置分支调新写 helper `genPositionalCtorArgs` 内部遍历字段补齐 | 消除 arity 缺口,但新 helper 与既有 `genCtorArgsWithDefaults` 逻辑近重复(都「遍历字段 → 缺则默认 / 零」)→ 双轨:positional 走 B-helper、named / empty 走旧 helper,改默认值语义须同步两处。半根(消症状留双轨),违 D149 §C3「统一 helper」初衷 |
| C | 架构层 refactor | 位置实参按「位置 i ↔ `classFields` 字段 i」映射进 `namedVals` / `namedLLTypes`,直调既有 `genCtorArgsWithDefaults`;`genGenericNewExpr` 同步并入(`mangledName` 由 `preRegisterSpecializedClass` 已注册进 `classFields` / `classFieldTypes`)| `genNewExpr` named 分支(`genNamedConstructorArgs`)+ empty 分支早已调 `genCtorArgsWithDefaults`;C 让 positional 并入 → 三分支收敛到唯一 arity-安全填充路径。无新增 helper、无双轨。根因解决度最高 |

## 4. 决策行

**选 C 因** 它把位置分支并入既有唯一填充 helper `genCtorArgsWithDefaults` —— named / empty 两分支早经它,C 补齐 positional 是 D149/D150「三分支统一」未完成的最后一格收口:无新增代码路径、无双轨,未来新增「字段默认值」语义只改 helper 一处。**不选 A** 因数据层硬编码零字面不查字段默认值表达式与 LL 类型 → `= 默认值` 字段被错补、`ptr` / `double` 字段类型错,假设(「未提供字段都补 `i64 0`」)再次破裂。**不选次优 B** 因新 helper 与 `genCtorArgsWithDefaults` 近重复造双轨,改默认值语义要同步两处,违 D149「统一 helper」;C 复用既有 helper 比 B 上推一格。排序依据为根因解决度(三分支是否真正收敛到单一路径),非 LOC / 工程量。

## 5. 长久评估

`genCtorArgsWithDefaults` 是 D149 已落地的 arity-安全填充原语,C **不依赖任何未落地能力**(底层依赖链闭合)。**业界对标**:TS / Dart / Kotlin 的构造默认值机制都是单一参数填充路径(编译器对 named / positional 实参先归一化为「字段 → 值」映射,再统一填默认)—— 不存在「positional 一套、named 一套」的双机制,C 对齐此终局范式。**N 年返工度 ≈ 0**:三分支并轨后,「字段默认值 / 可选字段」语义演进只改 `genCtorArgsWithDefaults` 单点;B 的双轨会在每次默认值语义演进时返工同步。**scope 边界**:generic 类经 `genGenericNewExpr` 并入后,未提供字段取**类型正确零值**(段错误根治);`preRegisterSpecializedClass` 未捕获 `classFieldDefaultIds` → generic 类带 `= 默认值表达式` 的字段取零值而非默认表达式值 —— 这是 generic 类注册的独立既有缺口(本修复使其从「垃圾」改善为「零值」,严格变好),完整修复属 generic 注册的独立 followup,非本段错误根因。

## 6. §实证(MNK §字段 12)

**根因定位 grep 证据**:

```
$ grep -n 'Used by both\|function genCtorArgsWithDefaults' bootstrap/gen/class/class_method.ss
135:// Used by both partial named arg path (genNamedConstructorArgs) and 全 default 空 ctor path.
138:function genCtorArgsWithDefaults(className: string, namedVals: Map, namedLLTypes: Map): string
   → helper 注释只列 named + empty 两路径,positional 从未并入

$ grep -n 'call ptr @.*_new(' /tmp/t121ir.ll   （改前 emit-ir）
6123:  %5  = call ptr @Bug_new(ptr @.str.98)    ← 1 实参 vs Bug_new 7 形参
6205:  %44 = call ptr @Bug_new(ptr @.str.111)   ← 1 实参 vs 7 形参

$ git grep -n 'first == 1' bootstrap/gen/gen_generic_class.ss   （改前)
   genGenericNewExpr 的位置裸循环与 class.ss 分支 3 同形 —— same_pattern 实例
```

**最危险假设最小 spike** —— 候选 C 最危险假设「位置 i ↔ `classFields` 字段 i ↔ 构造形参 i 三者对齐」:`class_register.ss:314` `emitClassConstructor` 的 `ctorParams` 与 `genCtorArgsWithDefaults` **同迭代** `classFields.getString(name).split(",")` → 对齐成立;`check_exprs.ss:254` `checkArgCount` 保证 `argCount ≤ max ≤ 字段数` → 位置 → 字段映射不越界。spike = 应用 C 修复(新增统一 helper `genCtorCallArgs` 于 `class_method.ss`,`genNewExpr` / `genGenericNewExpr` 两 emitter 实参拼装塌缩为一行调用)+ bootstrap + 全测试切:

- `./build.sh bootstrap` 三阶段固定点 Stage 2 == Stage 3 ✓(`class.ss` 修复后 + `gen_generic_class.ss` 修复后各验一次)
- `bin/ss test tests/` → **332 passed / 3 failed**(修复前 331 / 4 → `harness_bug`(test_121)转 PASS,**0 regression**;余 3 fail 为 d096 / spring 编译错 + harness_task 缺 `.harness/` 目录,均与本 bug 无关)
- RED→GREEN:`harness_bug/main.ss` exit 139 → 0;IR `call @Bug_new` 由 1 实参 → `(ptr @.str.98, i32 0, i32 0, i32 0, i32 0, i64 0, i64 0)` 满 7 实参,`detectedCb`/`fixedCb` 补 `i64 0`(null fn)
- 回归测试 `tests/phase5/i030_positional_ctor_arg_arity.ss`:pre-fix 编译器(`git show HEAD:bin/ss`)exit 1、fixed 编译器 exit 0
