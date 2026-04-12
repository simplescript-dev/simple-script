# Round 139

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D087-comptime.md (comptime full design + implementation path + details)
- bootstrap/interp.ss (interpreter core — value storage, scope, class infra, reset)
- lib/spring/boot.ss (comptime factory + wrapper generation block)

## Last Round (max 3 sentences)
Split interp.ss (1272 lines) into 5 files by responsibility: interp.ss core (303), interp_eval.ss (237), interp_calls.ss (393), interp_exec.ss (210), interp_reflect.ss (146). Fixed a latent bug: added collectBeans("SpringBootApplication") in boot.ss — the removed gen_annotations.ss fallback had been masking the missing factory generation for @SpringBootApplication classes. 184 tests passing, bootstrap fixed-point verified.

## Task
**D087 Phase 4d: Verify full comptime pipeline — end-to-end annotation test**

The comptime annotation pipeline is now complete: comptime blocks generate ALL factory + wrapper IR, gen_annotations.ss only dispatches handler calls. Verify the full pipeline works end-to-end:

1. **Review the existing spring_di test** (`tests/phase5/spring_di.ss`): check it covers DI injection, @PostConstruct, and route handler wrappers
2. **Add coverage for method wrappers**: if the test doesn't exercise @GetMapping/@PostMapping with @PathVariable parameter bridging, add a test case that verifies wrapper generation works correctly
3. **Verify no regressions**: run full test suite + bootstrap
4. **If all passes, D087 Phase 4 is complete**: update handoff to mark Phase 4 done and identify next direction

Design consideration:
- The test should verify that comptime-generated factories create singletons (same instance returned)
- The test should verify that comptime-generated wrappers correctly bridge parameters
- Keep tests self-contained (no actual HTTP server needed — test the DI/factory machinery directly)

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.
6. **I009 — double return corrupts int params** [MEDIUM]: Functions with `(int): double` signature corrupt int param values. Workaround: use `parseDouble(interpAsStr(id))` instead of `interpAsDouble(id)`.

### Project Status
- **D087 Phase 1a-1f done**: interpreter + comptime block integration
- **D087 Phase 3a done**: @typeInfo(T) compile-time reflection
- **D087 Phase 3b done**: comptime code generation (emit + registerFunction)
- **D087 Phase 3c done**: @comptimeEmit — SS source string → compiled code
- **D087 Phase 4a done**: comptime factory generation for @Component beans
- **D087 Phase 4b done**: comptime method wrapper generation for annotated beans
- **D087 Phase 4c done**: cleaned gen_annotations.ss — removed dead factory/wrapper codegen (-48%)
- **D087 next**: Phase 4d (verify full pipeline) → Phase 4 complete
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
- **interpBuildAnnotationArray(annListId)**: helper, parses ANNOTATION_LIST → array of {name, args}
- **interpBuildTypeInfo**: queries classFields/classFieldTypes/classMethods/funcRetTypes/classNodeIds; returns methods with annotations + params with annotation field
- **classNodeIds**: gen_class.ss Map, "ClassName" → CLASS_DECL AST node ID
- **interpExecComptime**: interpReset() + interpExec(bodyId), each comptime block independent
- **Checker skip**: comptime blocks not deeply checked, interpreter handles errors
- **RETURN flag fix**: `interpReturnFlag=1` must be set AFTER `interpEval(returnExpr)`
- **D086 v2 done**: annotationMapping + handler dispatch
- **Spring Boot DI**: @Component/@Service/@Repository → springAnnotationHandler in lib
- **Phase 4a factories**: comptime block in boot.ss uses getAnnotatedClasses + getTypeInfo + emit() + registerFunction() to generate @__ann_factory_ClassName singleton factories
- **Phase 4b wrappers**: same comptime block generates @__ann_wrapper_ClassName_methodName with parameter bridging (HttpServletRequest/Response/PathVariable). addStringConst builtin for IR string refs
- **Phase 4c cleanup**: gen_annotations.ss reduced to collection + handler dispatch only. emitFactory/emitMethodWrapper/annClassSet deleted. No fallback IR generation
- **D085 done**: Package system
- **D082 Phase 1-4 done**: ref/watch, Thread, Channel<T>
- **Interpreter split**: interp.ss (core 303) + interp_eval.ss (237) + interp_calls.ss (393) + interp_exec.ss (210) + interp_reflect.ss (146) + interp_builtins.ss (321)
- **Bootstrap**: 47 files, ~18700 LOC, 189 tests (184 passing, 5 pre-existing interp_* failures).

## Watch Out For
- **D087 is the single source of truth**: read D087 at start, don't re-discuss selection
- **Phase numbering**: current step in handoff Task
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
