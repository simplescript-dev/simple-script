# Round 133

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D087-comptime.md (comptime 完整设计 + 实现路径 + 设计细节)
- bootstrap/interp.ss (解释器核心 + interpBuildTypeInfo + interpExecComptime)
- bootstrap/interp_builtins.ss (内置类型方法)

## Last Round (max 3 sentences)
完成 D087 Phase 3a：`@typeInfo(T)` 编译期反射。Parser 识别 `@typeInfo(ClassName)` 为 TYPEINFO_EXPR 节点，解释器查询编译器的 classFields/classFieldTypes/classMethods/funcRetTypes 注册表构建 ClassInfo 对象（含 fields 数组带 name/type、methods 数组带 name/returnType/params、annotations 空数组）。`classNodeIds` Map 存储 CLASS_DECL AST ID 用于提取方法参数信息。182 测试通过，bootstrap 固定点验证通过。

## Task
**D087 Phase 3b：comptime 代码生成**

实现 comptime 块向编译输出注入声明的能力：
- comptime 块可调用编译器 API 注入函数声明、全局变量到后续编译阶段
- 完成标准：comptime 生成的函数在运行时可调用
- 这是 Phase 4（用 comptime 重写注解处理）的核心依赖

设计思路：comptime 块目前只做 println 调试输出，结果不传递到编译管道。需要一个机制让 comptime 块的结果（如生成的函数声明）注入到后续 codegen。参考 D 语言 mixin 或 Zig comptime 的代码注入方式。

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
- **D087 next**: Phase 3b (comptime 代码生成) → Phase 3c (comptime string→code) → Phase 4 (rewrite annotations)
- **COMPTIME_BLOCK**: AST 节点，I1=body BLOCK，Codegen 调用 interpExecComptime(bodyId)
- **TYPEINFO_EXPR**: AST 节点，S1=className，interpEval 调用 interpBuildTypeInfo
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
- **Bootstrap**: 43 files, ~18700 LOC, 187 tests (182 passing, 5 pre-existing interp_* failures).

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
