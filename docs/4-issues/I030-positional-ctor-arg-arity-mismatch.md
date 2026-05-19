# I030 — `genNewExpr` / `genGenericNewExpr` positional-partial 构造调用未补齐到构造函数 arity

**父决策:** 无(独立 root cause —— codegen miscompile)。关联 D149(partial named arg ctor + field default value)/ D150 —— 本 bug 是 D149「NEW_EXPR ctor 实参分支统一到 `genCtorArgsWithDefaults`」未完成的 **positional 路径同胞缺口**(D149 只并入 named + empty 两分支)。
**状态:** Resolved —— `genNewExpr` 位置分支 + `genGenericNewExpr` 实参循环并入既有 arity-安全 helper `genCtorArgsWithDefaults`,三分支(named / empty / positional)统一;回归测试 `tests/phase5/i030_positional_ctor_arg_arity.ss`(修复 + 测试 + .bugfix 本轮同 commit)
**颗粒度:** 立项 + 修复同轮(用户 next_prompt 授权);修复 = 2 个 codegen 函数的位置实参拼装并入 `genCtorArgsWithDefaults`,标准改档
**依赖:** 无。`genCtorArgsWithDefaults`(D149 已落地)是现成 arity-安全填充原语,修复不依赖未落地能力
**创建:** 2026-05-19
**立项由:** 上一轮 Plan 型段错误诊断(`bin/ss test` test_121 = `tests/phase5/harness_bug/main.ss` 确定性段错误);next_prompt 指定本轮立项修复

---

## 现象

`bin/ss test tests/` 中 test_121(`tests/phase5/harness_bug/main.ss`)单进程零并发下**每次**段错误(exit 139),并向 runner CWD(repo 根)抛 `core.<pid>` 污染工作树。

`harness_bug/main.ss` 编译成功(非编译期失败),运行时 `Bug_detected` 内一条间接 `call` 跳进非法地址 `0x200`(gdb backtrace 仅 3 帧 `?? ← Bug_detected ← main`,非栈溢出)。崩溃发生在 `bug2 = new Bug("no-callbacks")`(`main.ss:42`)那个**没注册任何回调**的对象的 `bug2.detected(3,3)` —— `if (this.detectedCb != 0) this.detectedCb()` 里 `detectedCb` 字段是垃圾值 `0x200` 而非 0。

## root cause

`genNewExpr`(`bootstrap/gen/class/class.ss:251`)拼构造调用实参分三支:named → `genNamedConstructorArgs` → `genCtorArgsWithDefaults`;empty → 直调 `genCtorArgsWithDefaults`;**positional(`argList != ""`)→ 自有 `for` 裸循环,只发射已提供位置实参,不补齐到构造函数全 arity**。`genCtorArgsWithDefaults`(`class_method.ss:138`)遍历类全部字段、缺字段补类型正确零值,恒产满 arity —— 分支 1/2 经它正确,分支 3(positional)不经它。

`Bug` 7 字段(`name` + 6 个可选),`new Bug("test-bug")` 经分支 3 → IR `call ptr @Bug_new(ptr @.str.98)` 仅 1 实参 vs `Bug_new` 7 形参。`main` 汇编只设 `%rdi`(name)→ `Bug_new` 从未初始化 `%r9` 读 `detectedCb` = 残留垃圾 `0x200` → 写进对象。`bug` 紧接 `onDetected(arrow)` 覆写 `detectedCb` 故无害;`bug2` 无 `onDetected` → 垃圾存活 → `detected()` 内 `!= 0` 守卫被骗过 → `call *0x200` → SIGSEGV。

`genGenericNewExpr`(`gen_generic_class.ss:238`)的实参循环同址同形(且无 empty-arg 分支 → `new Generic<T>()` 0 实参更严重)—— same_pattern 同胞实例。

归类:**codegen miscompile** —— 构造调用点实参数目不匹配。**非 array RC UAF**;闭包 / RC 机制本身正常,字段单纯从未初始化 ABI 寄存器读出垃圾。

## 修复(候选 C —— `i030_positional_ctor_arg_arity.options.md` `bug_options_linter` 6/6 GATE OK)

新增统一 helper `genCtorCallArgs`(`class_method.ss`)—— 单一 arity-安全的构造调用实参构建器:named 实参委托 `genNamedConstructorArgs`,positional 实参按「位置 i ↔ `classFields` 字段 i」映射后(同 empty 构造)经 `genCtorArgsWithDefaults` 把每个未提供字段补类型正确零值/默认值。`genNewExpr`(`class.ss`)与 `genGenericNewExpr`(`gen_generic_class.ss`)的实参拼装(原各自裸循环只发射已提供实参)统一塌缩为一行 `genCtorCallArgs` 调用 —— named/positional/empty 三分支 + 两 emitter 全收敛到唯一路径,`call @ClassName_new` 恒满构造函数声明 arity(`genGenericNewExpr` 缺失的 empty-arg 分支一并补齐;`mangledName` 由 `preRegisterSpecializedClass` 已注册进 `classFields`/`classFieldTypes`)。

候选层次:A 数据层(裸循环后硬编码补 `i64 0`)—— 不查默认值表达式 / LL 类型,`= 默认值` 字段错补、`ptr`/`double` 字段类型错;B 接口层(新 helper `genPositionalCtorArgs`)—— 与 `genCtorArgsWithDefaults` 近重复造双轨;**C 架构层(选)** —— 复用既有 helper,无双轨。详见 options.md §3/§4。

验证:`./build.sh bootstrap` 三阶段固定点 Stage2==Stage3;`bin/ss test` 332 passed / 3 failed(修复前 331/4,test_121 转 PASS,0 regression);IR `call @Bug_new` 由 1 实参 → 满 7 实参(`detectedCb`/`fixedCb` 补 `i64 0`);因果证据 `tools/bugfix_reports/2026-05-19-i030-positional-ctor-arg-arity.bugfix`,回归测试 `tests/phase5/i030_positional_ctor_arg_arity.ss`(positional-partial 非泛型 + 泛型双覆盖,pre-fix `git HEAD:bin/ss` exit 1 / fixed exit 0)。

## 反向

不修 → test_121 每次段错误 + `core.*` 持续污染工作树;且这是对**一整类**代码形态(任何带可选 / 默认字段的类的位置部分构造)的确定性误编译 —— 任何用户写出同形态代码,未提供的可选 `fn` 字段被调用 → 崩,未提供的可选指针字段被 RC release → 崩。下轮 Claude 读不到根因易复判为 flaky(I025/I026/I027 同类误诊史)。

## 关联观察

`preRegisterSpecializedClass`(`gen_generic_class.ss:67`)注册 specialized class 时填了 `classFields`/`classFieldTypes`/`classConstFields`,**未填 `classFieldDefaultIds`**。故 generic 类若带 `= 默认值表达式` 的字段,经 `genGenericNewExpr` → `genCtorArgsWithDefaults` 时未提供字段取**类型零值**而非默认表达式值。本修复使 generic 路径从「垃圾」改善为「类型零值」(段错误已根治);generic 类 field default-value expr 的完整支持是 generic 类注册的独立既有缺口,候选下游 issue。
