# Round 132

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18600 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D087-comptime.md (comptime 完整设计 + 实现路径 + 设计细节)
- bootstrap/interp.ss (Phase 1a-1e 解释器核心 + interpExecComptime)
- bootstrap/interp_builtins.ss (Phase 1e 内置类型方法)

## Last Round (max 3 sentences)
完成 D087 Phase 1f：comptime 块与编译器集成。Lexer 识别 `comptime` 关键字，Parser 解析 `comptime { ... }` 为 COMPTIME_BLOCK AST 节点，Checker 跳过深检查（预注册不覆盖 comptime 局部函数），Codegen 调用 `interpExecComptime()` 执行解释器后跳过 IR 生成。验证通过：编译期输出算术/字符串/循环/递归/数组结果，运行时无 comptime 代码，186 测试全过，bootstrap 固定点通过。

## Task
**D087 Phase 3a：编译期反射 @typeInfo(T)**

实现 `@typeInfo(T)` 内置函数，在 comptime 块中返回 ClassInfo 对象：
- fields 数组（每个元素有 name、type 属性）
- methods 数组（每个元素有 name、params、returnType 属性）
- annotations 数组（如有）
- 完成标准：`comptime { const info = @typeInfo(MyClass); println(info.fields.length()) }` 输出字段数

注意：Phase 2（comptime 函数参数、I/O 限制）可以按需实现，但 Phase 3a 的反射是 Phase 4（用 comptime 重写注解处理）的前置依赖。如果 @typeInfo 需要 comptime 块能看到外层声明（类定义），需要先解决 comptime 块与编译上下文的连接。

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.
6. **I009 — double return corrupts int params** [MEDIUM]: Functions with `(int): double` signature corrupt int param values. Workaround: use `parseDouble(interpAsStr(id))` instead of `interpAsDouble(id)`.

### Project Status
- **D087 Phase 1a-1f done**: 解释器 + comptime 块集成到编译管道
- **D087 next**: Phase 3a (@typeInfo 反射) → Phase 4 (rewrite annotations)
- **COMPTIME_BLOCK**: AST 节点，I1=body BLOCK，Codegen 调用 interpExecComptime(bodyId)
- **interpExecComptime**: interpReset() + interpExec(bodyId)，每个 comptime 块独立状态
- **Checker skip**: comptime 块不做深检查，解释器自己处理错误
- **RETURN flag fix**: `interpReturnFlag=1` 必须在 `interpEval(returnExpr)` 之后设置
- **D086 v2 done**: annotationMapping + handler dispatch
- **Spring Boot DI**: @Component/@Service/@Repository → springAnnotationHandler in lib
- **D085 done**: Package system
- **D082 Phase 1-4 done**: ref/watch, Thread, Channel<T>
- **Bootstrap**: 43 files, ~18600 LOC, 186 tests (all passing).

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
- **comptime 块独立**: interpExecComptime 每次 reset，块间不共享状态。Phase 3+ 可能需要让 comptime 看到编译上下文。
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
