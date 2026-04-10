# Round 131

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18600 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D087-comptime.md (comptime 完整设计 + 实现路径 + 设计细节)
- bootstrap/interp.ss (Phase 1a-1e 解释器核心)
- bootstrap/interp_builtins.ss (Phase 1e 内置类型方法)

## Last Round (max 3 sentences)
完成 D087 Phase 1e：解释器内置类型方法。实现 string 12 方法、Array 9 方法（含 map/filter/reduce/forEach 高阶函数）、Map 7 方法、new Map() 支持、arrow 函数求值、interpCallValue（高阶回调）、parseInt/parseDouble/toString 内置函数。发现并绕过编译器 bug I009（int 参数传给返回 double 的函数时被破坏）。28 新测试，185 总测试全过，bootstrap 固定点验证通过。

## Task
**D087 Phase 1f：与编译器集成**

将解释器连接到编译管道：
- **Parser**: 识别 `comptime` 关键字，解析 `comptime { ... }` 块为新 AST 节点 COMPTIME_BLOCK
- **Checker**: 验证 comptime 块（基础验证即可，完整限制后续添加）
- **Codegen**: 遇到 COMPTIME_BLOCK 时调用解释器执行，跳过 IR 生成
- **完成标准**: `comptime { let x = 1 + 2; println(x) }` 编译时输出 3，运行时无代码

注意：这一步合并了 D087 设计文档中的 Phase 1f 和 Phase 2a-2c，因为解释器已完备，集成可一步完成。

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.
6. **I009 — double return corrupts int params** [MEDIUM]: Functions with `(int): double` signature corrupt int param values. Workaround: use `parseDouble(interpAsStr(id))` instead of `interpAsDouble(id)`.

### Project Status
- **D087 Phase 1a-1e done**: 解释器 — 值表示 + 作用域 + 表达式 + 控制流 + 赋值 + 数组 + 函数 + 类 + 内置类型方法 + arrow + Map
- **D087 next**: Phase 1f/2a-2c (comptime integration) → Phase 3 (reflection) → Phase 4 (rewrite annotations)
- **RETURN flag fix**: `interpReturnFlag=1` 必须在 `interpEval(returnExpr)` 之后设置
- **D086 v2 done**: annotationMapping + handler dispatch
- **Spring Boot DI**: @Component/@Service/@Repository → springAnnotationHandler in lib
- **D085 done**: Package system
- **D082 Phase 1-4 done**: ref/watch, Thread, Channel<T>
- **Bootstrap**: 43 files, ~18600 LOC, 185 tests (all passing).

## Watch Out For
- **D087 是唯一真相**：每轮开头读 D087，不重新讨论选型
- **Phase 编号跟踪**：当前步骤写在 handoff Task 中
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **interp.ss 自举安全**: 解释器是普通 SS 代码，seed 能编译。解释器不使用 comptime 自身。
- **Lexer 多次调用已修复**: tokenize() 现在重置 token 数组。
- **FUNC_DECL I4 conflict**: I4 is used for both annotations and isAbstract. Known issue.
- **RETURN flag ordering**: interpReturnFlag must be set AFTER interpEval(returnExpr), not before.
- **interpCall 隔离**: 函数体执行前 save/restore break+continue flags。
- **interpMethodCall 隔离**: 方法体执行前 save/restore this+break+continue flags。
- **interpObjFields key 格式**: `"valId:fieldName"` — valId 是对象值 ID，不是 AST 节点 ID。
- **interpCollectFields 顺序**: 父类字段在前，子类字段在后。
- **interpFindMethod 优先级**: 子类方法优先（先查子类，再递归父类）。
- **关键字冲突**: `double` 是类型关键字，不能用作方法名/变量名。
- **I009 workaround**: 避免 `(int): double` 函数签名，用 `parseDouble(interpAsStr(id))` 代替 `interpAsDouble(id)`。
- **interp_builtins.ss forward refs**: 该文件通过 forward reference 调用 interp.ss 的函数（interpNewVal、interpAsStr 等）和 interpCallValue。registerAllDecls 确保安全。
- **Map 值存储**: interpMapEntries (`"valId:keyStr" → "valId"`) + interpMapKeyIds (`"valId" → "keyValId1,keyValId2,..."`). interpResetBuiltins() 清理。
- **Rejected features**: Range syntax, pattern matching type patterns, Result<T,E> + ? operator, FFI via dlopen, Kotlin/Scala syntax. Do not propose.
- **for-in 不支持 const/let 前缀**: `for (x in arr)` 可以，`for (const x in arr)` 不行。

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests for new features
2. Verify against axioms and principles
3. Run `/simplify` to review code quality before commit
4. Self-review for contradictions
5. Commit and push to remote
6. Generate next docs/5-handoff/next-prompt.md (include "Next Direction" summary)
7. List files created/modified + brief next direction
8. **Stop.**
