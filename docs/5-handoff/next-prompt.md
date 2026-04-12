# Round 134

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D087-comptime.md (comptime 完整设计 + 实现路径 + 设计细节)
- bootstrap/interp.ss (解释器核心 + emit/registerFunction builtins + interpBuildTypeInfo)
- bootstrap/interp_builtins.ss (内置类型方法)

## Last Round (max 3 sentences)
完成 D087 Phase 3b：comptime 代码生成。解释器新增 `emit(irString)` 将 LLVM IR 追加到 `comptimeIR` 缓冲区，`registerFunction(name, retType, paramCount)` 向编译器 funcRetTypes/funcParamCount 注册函数签名。genStmt 在 COMPTIME_BLOCK 执行后 flush comptimeIR 到 IR 输出。183 测试通过（+1 comptime_emit），bootstrap 固定点验证通过。

## Task
**D087 Phase 3c：comptime 字符串→代码（@comptimeEmit）**

实现类 D 语言 mixin 的能力——comptime 块将 SimpleScript 源码字符串编译并注入到输出：
- `@comptimeEmit(ssSourceString)` 在 comptime 块内可用，解析并编译 SS 源码字符串
- 完成标准：comptime 可根据 @typeInfo 反射结果动态生成 SS 级别的函数，不需要手写 LLVM IR
- 这比 Phase 3b 的 `emit()` 更高层，用户写 SS 代码而非 IR

设计思路：`@comptimeEmit(str)` 调用 tokenize+parse 生成 AST 节点，然后将这些 AST 节点注入到当前编译单元的根节点。需要重新 registerAllDecls 处理新注入的声明，然后在 codegen 中处理它们。或者直接在 comptime 执行点对新 AST 调用 genStmt/genFuncDeclStmt。

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.
6. **I009 — double return corrupts int params** [MEDIUM]: Functions with `(int): double` signature corrupt int param values. Workaround: use `parseDouble(interpAsStr(id))` instead of `interpAsDouble(id)`.

### Project Status
- **D087 Phase 1a-1f done**: 解释器 + comptime 块集成到编译管道
- **D087 Phase 3a done**: @typeInfo(T) 编译期反射
- **D087 Phase 3b done**: comptime 代码生成 (emit + registerFunction)
- **D087 next**: Phase 3c (comptime string→code @comptimeEmit) → Phase 4 (rewrite annotations)
- **COMPTIME_BLOCK**: AST 节点，I1=body BLOCK，Codegen 调用 interpExecComptime(bodyId)
- **TYPEINFO_EXPR**: AST 节点，S1=className，interpEval 调用 interpBuildTypeInfo
- **comptimeIR**: interp.ss 全局缓冲区，emit() 追加 IR 字符串，genStmt flush 到输出
- **emit(irString)**: comptime 内置函数，追加 LLVM IR 到 comptimeIR
- **registerFunction(name, retType, paramCount)**: comptime 内置函数，注册函数到 funcRetTypes/funcParamCount
- **interpBuildTypeInfo**: 查询 classFields/classFieldTypes/classMethods/funcRetTypes/classNodeIds 构建 ClassInfo 对象
- **interpBuildMethodParams**: 从 CLASS_DECL AST 提取方法参数信息
- **classNodeIds**: gen_class.ss 中的 Map，"ClassName" → CLASS_DECL AST node ID
- **interpExecComptime**: interpReset() + interpExec(bodyId)，每个 comptime 块独立状态
- **Checker skip**: comptime 块不做深检查，解释器自己处理错误
- **RETURN flag fix**: `interpReturnFlag=1` 必须在 `interpEval(returnExpr)` 之后设置
- **D086 v2 done**: annotationMapping + handler dispatch
- **Spring Boot DI**: @Component/@Service/@Repository → springAnnotationHandler in lib
- **D085 done**: Package system
- **D082 Phase 1-4 done**: ref/watch, Thread, Channel<T>
- **Bootstrap**: 43 files, ~18700 LOC, 188 tests (183 passing, 5 pre-existing interp_* failures).

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
- **comptime 块独立**: interpExecComptime 每次 reset，块间不共享状态。@typeInfo 直接查编译器注册表，不走解释器类系统。
- **comptimeIR 跨块累积**: comptimeIR 不在 interpReset 中清理，在 resetCodegen 中初始化。genStmt 在每个 COMPTIME_BLOCK 后 flush。
- **classNodeIds vs interpClasses**: classNodeIds 是编译器的类注册表（gen_class.ss），interpClasses 是解释器的类注册表（comptime 块内声明的类）。两者完全独立。
- **@typeInfo 只在 comptime 中有效**: TYPEINFO_EXPR 在 parseAtom 解析，checker 跳过 comptime 块所以不检查。
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
