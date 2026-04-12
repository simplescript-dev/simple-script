# Round 140

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/4-issues/1-open/I009-double-return-corrupts-int-params.md (the bug to fix)
- bootstrap/gen_decls.ss (function declaration codegen — calling convention)
- bootstrap/gen_calls.ss (function call codegen — argument passing)
- bootstrap/gen_exprs.ss (inferType, expression codegen)

## Last Round (max 3 sentences)
D087 Phase 4d verified: spring_di.ss test passes end-to-end (DI injection, @PostConstruct, @GetMapping + @PathVariable parameter bridging). 184/189 tests pass (5 pre-existing interp_* failures), bootstrap fixed-point verified. D087 Phase 4 (comptime annotation rewrite) is complete.

## Task
**I009: Fix double return corrupts int parameters**

Functions with `(int): double` signature corrupt the int parameter values at the call site. The int value received by the callee is garbage. This is a codegen calling convention bug.

1. **Read the reproduction case** in I009 issue doc — understand the symptom
2. **Investigate codegen for (int): double functions**: compare LLVM IR generated for `(int): int`, `(int): string`, and `(int): double` signatures. The difference should reveal the calling convention bug
3. **Root cause**: likely LLVM IR parameter types or calling convention mismatch when return type is `double` (i32 params may be promoted or stack-misaligned)
4. **Fix in codegen**: correct the IR generation for functions returning double with int parameters
5. **Write a test**: `tests/phase5/double_return.ss` — function with `(int): double` signature, verify int param is received correctly
6. **Verify**: full test suite + bootstrap

### Investigation hints
- Compare the `define` signatures and `call` instructions for functions returning i32 vs double
- Check if function declaration uses `double` return type but call site uses `i32` or vice versa
- Check `genCallExpr` and `genFuncDecl` for return type handling
- The LLVM IR `call` instruction's return type must match the function's `define` return type exactly

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.
6. **I009 — double return corrupts int params** [MEDIUM]: Functions with `(int): double` signature corrupt int param values. Workaround: use `parseDouble(interpAsStr(id))` instead of `interpAsDouble(id)`.

### Project Status
- **D087 complete**: Phase 1-4 all done. comptime blocks, @typeInfo, @comptimeEmit, emit()/registerFunction()/getAnnotatedClasses()/getTypeInfo()/addStringConst() builtins, Spring Boot annotation pipeline fully in comptime
- **COMPTIME_BLOCK**: AST node, I1=body BLOCK, Codegen calls interpExecComptime(bodyId)
- **TYPEINFO_EXPR**: AST node, S1=className, interpEval calls interpBuildTypeInfo
- **COMPTIME_EMIT**: AST node, I1=expression, interpEval accumulates to comptimeSS
- **comptimeIR**: interp.ss global buffer, emit() appends IR strings, genStmt flushes to output
- **comptimeSS**: interp.ss global buffer, @comptimeEmit() appends SS source, genStmt tokenizes→parses→registers→genStmts
- **registerFuncDeclNode**: codegen.ss extracted function, registers FUNC_DECL retType/paramCount/overloads/generics/defaults
- **emit(irString)**: comptime builtin, appends LLVM IR to comptimeIR
- **registerFunction(name, retType, paramCount)**: comptime builtin, registers to funcRetTypes/funcParamCount
- **getAnnotatedClasses(annName)**: comptime builtin (D087 4a), queries annClassNodeIds/annClassAnnNames, returns array of unique class names
- **getTypeInfo(className)**: comptime builtin (D087 4a), calls interpBuildTypeInfo with string arg
- **addStringConst(str)**: comptime builtin (D087 4b), calls compiler's addStringConst, returns IR ref string
- **@comptimeEmit(ssSource)**: comptime expression, accumulates SS source for post-block compilation
- **gen_annotations.ss**: only collection + handler dispatch, no IR generation
- **D086 v2 done**: annotationMapping + handler dispatch
- **Spring Boot DI**: @Component/@Service/@Repository → springAnnotationHandler in lib
- **D085 done**: Package system
- **D082 Phase 1-4 done**: ref/watch, Thread, Channel<T>
- **Interpreter split**: interp.ss (core 303) + interp_eval.ss (237) + interp_calls.ss (393) + interp_exec.ss (210) + interp_reflect.ss (146) + interp_builtins.ss (321)
- **Bootstrap**: 47 files, ~18700 LOC, 189 tests (184 passing, 5 pre-existing interp_* failures).

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **interp.ss bootstrap safe**: interpreter is plain SS code, seed can compile. Interpreter doesn't use comptime itself.
- **Interpreter file split**: interp.ss imports interp_eval/calls/exec/reflect. Sub-files use forward references (no imports between them), same pattern as interp_builtins.ss.
- **Lexer multi-call fixed**: tokenize() now resets token array.
- **FUNC_DECL I4 conflict**: I4 is used for both annotations and isAbstract. Known issue.
- **RETURN flag ordering**: interpReturnFlag must be set AFTER interpEval(returnExpr), not before.
- **interpCall isolation**: save/restore break+continue flags before function body.
- **interpMethodCall isolation**: save/restore this+break+continue flags before method body.
- **interpObjFields key format**: `"valId:fieldName"` — valId is object value ID, not AST node ID.
- **interpCollectFields order**: parent fields first, child fields after.
- **interpFindMethod priority**: child methods first (check child, then recurse parent).
- **Keyword conflict**: `double` is a type keyword, cannot be used as method/variable name.
- **I009 workaround**: avoid `(int): double` function signature, use `parseDouble(interpAsStr(id))` instead of `interpAsDouble(id)`.
- **interp_builtins.ss forward refs**: uses forward references to interp.ss functions. registerAllDecls ensures safety.
- **Map value storage**: interpMapEntries (`"valId:keyStr" → "valId"`) + interpMapKeyIds (`"valId" → "keyValId1,keyValId2,..."`). interpResetBuiltins() cleans up.
- **comptime blocks independent**: interpExecComptime resets each time, blocks don't share state. @typeInfo queries compiler registry directly, not interpreter class system.
- **comptimeIR accumulates across blocks**: not cleared in interpReset, initialized in resetCodegen. genStmt flushes after each COMPTIME_BLOCK.
- **comptimeSS flushed per block**: cleared after tokenize→parse→genStmt in each COMPTIME_BLOCK handler. Also cleared in resetCodegen() defensively.
- **classNodeIds vs interpClasses**: classNodeIds is compiler's class registry (gen_class.ss), interpClasses is interpreter's (comptime-declared classes). Completely independent.
- **@typeInfo only in comptime**: TYPEINFO_EXPR parsed in parseAtom, checker skips comptime blocks.
- **@comptimeEmit two-pass**: first pass registers FUNC_DECL nodes, second pass calls genStmt — enables forward references between generated functions.
- **getAnnotatedClasses queries annClassNodeIds/annClassAnnNames**: these are populated during registerAllDecls (before codegen), so available when comptime blocks execute.
- **comptime factory vs gen_annotations.ss**: comptime-generated factories register in funcRetTypes via registerFunction(). gen_annotations.ss only dispatches handler calls, no IR generation.
- **collectBeans coverage**: boot.ss comptime must collectBeans for ALL annotations whose classes need factories (Component/Service/Repository/RestController/SpringBootApplication). Missing one causes undefined symbol at link time.
- **interpUpdateVar updates across scopes**: finds variable in parent scope and updates there, enabling closures in comptime blocks.
- **interpToStr doesn't handle array type**: returns "null" for arrays in template strings — values are correct, just display issue.
- **Rejected features**: Range syntax, pattern matching type patterns, Result<T,E> + ? operator, FFI via dlopen, Kotlin/Scala syntax. Do not propose.
- **for-in doesn't support const/let prefix**: `for (x in arr)` ok, `for (const x in arr)` not.

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
