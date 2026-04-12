# Round 145

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/4-issues/1-open/ (check remaining open issues)
- bootstrap/interp_reflect.ss (full reflection: class/enum/interface)
- bootstrap/gen_annotations.ss (annotation collection now handler-agnostic)
- tests/phase5/comptime_orm.ss (ORM PoC — demonstrates full comptime pipeline)

## Last Round (max 3 sentences)
Added interface reflection to getTypeInfo (InterfaceInfo with methods/params/returnTypes). Built ORM proof-of-concept: @Entity/@Id/@Column comptime-driven SQL generation using helper functions + getTypeInfo + getAnnotatedClasses. Fixed annotation collection to be handler-agnostic so getAnnotatedClasses works for any annotation. 191/196 tests pass, bootstrap fixed-point verified.

## Task
**Continue comptime enhancement toward Zig-level**

1. **Check `docs/4-issues/1-open/`** for remaining open issues (priority: fix before new features)
2. If no actionable issues, continue comptime roadmap:
   - **Comptime-driven enum serializer**: use enum reflection to auto-generate toString/fromString
   - **@field(obj, "name")**: compile-time field access by string name (useful for comptime object introspection)
   - **Comptime map literals**: allow Map construction in interpreter for building lookup tables
   - **Inline comptime expressions**: `comptime { val }` as expression (not just block), like Zig's `comptime val`
   - **Type-level comptime**: `comptime { @comptimeEmit(...) }` inside class body for generated methods

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Comptime Capabilities (current)
- **comptime blocks**: AST interpreter executes at compile time
- **@comptimeEmit(ssSource)**: generate SS source → compile (string mixin, D-language level)
- **@typeInfo / getTypeInfo**: class reflection — fields (name, type, annotations), methods (name, returnType, params, annotations), class annotations
- **Interface reflection**: getTypeInfo returns InterfaceInfo {name, kind="interface", methods [{name, returnType, params, annotations}]}
- **Enum reflection**: getTypeInfo returns EnumInfo {name, kind="enum", isString, variants [{name, value}]}
- **Field-level annotations**: @Id, @Column("name"), @NotNull on class fields, stored in PARAM nList as ANNOTATION_LIST node
- **compileError(msg)**: abort compilation with error message from comptime
- **hasField(class, field)**: compile-time check if class has field (returns 0/1)
- **hasMethod(class, method)**: compile-time check if class has method (returns 0/1, exact match)
- **getAnnotatedClasses(ann)**: query classes with ANY annotation (handler-agnostic since R144)
- **emit(irString)**: inject raw LLVM IR
- **registerFunction(name, ret, count)**: register function signature
- **addStringConst(str)**: add string constant, returns IR ref
- **Comptime user-defined functions**: function declarations inside comptime blocks work (ORM PoC proven)
- **Interpreter string methods**: length, trim, toUpper/Lower, split, indexOf, substring, replace, startsWith, endsWith, charAt, includes
- **Interpreter string concat**: `+` operator on strings works in comptime

### Project Status
- **ORM PoC complete**: comptime_orm.ss — @Entity/@Id/@Column driven SQL generation. Proves: getTypeInfo + field annotations + getAnnotatedClasses + comptime helper functions + @comptimeEmit all working together.
- **Annotation collection fix**: collectClassAnnotations/collectMethodAnnotations now collect ALL annotations. annHandlerMap gate moved to emitAnnotationInits(). getAnnotatedClasses() works for any annotation.
- **Interface reflection**: getTypeInfo returns InterfaceInfo from ifaceMethodsCG/Rets/Pars registries.
- **D087 complete**: Phase 1-4 all done. comptime blocks, @typeInfo, @comptimeEmit, Spring Boot annotation pipeline
- **I009 fixed**: funcParamTypes registry, per-parameter int→double promotion
- **Interpreter split**: interp.ss (core) + interp_eval.ss + interp_calls.ss + interp_exec.ss + interp_reflect.ss + interp_builtins.ss
- **Bootstrap**: 47 files, ~18700 LOC, 196 tests (191 passing, 5 pre-existing interp_* failures).

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Checker skips ARROW_FUNC**: @comptimeEmit-generated functions called from main() must be inside arrow functions (e.g., test(() => { ... })) to avoid checker "undefined function" errors.
- **Annotation collection is handler-agnostic**: collectClassAnnotations no longer checks annHandlerMap. ALL class/method annotations are collected. emitAnnotationInits skips annotations without handlers.
- **Enum registration**: registerEnum called in both registerAllDecls (for comptime access) and genStmt (for codegen). Double-call is safe.
- **PARAM nList for field annotations**: PARAM I4 is isStatic for class fields, so field annotations use nList to store ANNOTATION_LIST node ID.
- **isFieldPatternAt(pos)**: shared helper for field detection.
- **hasMethod exact match**: uses `,methods,`.indexOf(`,name,`) pattern.
- **Interface reflection data sources**: ifaceMethodsCG (name→methods), ifaceMethodRets (name.method→returnType), ifaceMethodPars (name.method→"paramName:paramType,...").
- **Interface vs class detection**: `ifaceMethodsCG.has(name) && !classFields.has(name)`.
- **Interpreter file split**: interp.ss imports interp_eval/calls/exec/reflect. Sub-files use forward references.
- **FUNC_DECL I4 conflict**: I4 is used for both annotations and isAbstract. Known issue.
- **RETURN flag ordering**: interpReturnFlag must be set AFTER interpEval(returnExpr), not before.
- **interpCall isolation**: save/restore break+continue flags before function body.
- **funcParamTypes**: registered in registerFuncDeclNode (base + mangled name) and genGenericCall.
- **@comptimeEmit two-pass**: first pass registers FUNC_DECL nodes, second pass calls genStmt.
- **comptimeSS flushed per block**: cleared after tokenize→parse→genStmt in each COMPTIME_BLOCK handler.
- **Rejected features**: Range syntax, pattern matching type patterns, Result<T,E> + ? operator, FFI via dlopen, Kotlin/Scala syntax. Do not propose.

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
