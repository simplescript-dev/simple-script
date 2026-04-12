# Round 148

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/4-issues/1-open/ (check remaining open issues)
- bootstrap/gen_class.ss:422-467 (class-level comptime in genClassDecl)
- bootstrap/gen_types.ss:215-252 (COMPTIME_EXPR in inferType)
- bootstrap/codegen.ss:297-330 (flushComptimeSS/flushComptimeIR helpers)
- tests/phase5/comptime_class_methods.ss (class-level comptime tests)
- tests/phase5/comptime_inline_expr.ss (inline comptime expression tests)

## Last Round (max 3 sentences)
Implemented two comptime features: (1) inline comptime expressions `comptime { return expr }` in expression position — evaluated at compile time, cached as constant; (2) type-level comptime — `comptime { }` blocks inside class body, @comptimeEmit FUNC_DECLs auto-registered as class methods with `this` access. Extracted flushComptimeSS/flushComptimeIR shared helpers. 196/201 tests pass, bootstrap fixed-point verified.

## Task
**Continue comptime enhancement toward Zig-level**

1. **Check `docs/4-issues/1-open/`** for remaining open issues (priority: fix before new features)
2. If no actionable issues, continue comptime roadmap:
   - **Comptime map literals**: Map construction in interpreter for lookup tables
   - **@field(obj, "name")**: dynamic field access by comptime string
   - **Generic comptime serializer**: bridge comptime + generics for `@serialize<T>()`
   - **Comptime conditional compilation**: `comptime { if (TARGET == "linux") { ... } }`
   - **Comptime type generation**: generate entire class/struct definitions at comptime

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Comptime Capabilities (current)
- **comptime blocks**: AST interpreter executes at compile time
- **Inline comptime expressions**: `comptime { return expr }` in expression position — evaluated once, cached as compile-time constant (int/double/string/bool)
- **Type-level comptime**: `comptime { }` inside class body — @comptimeEmit FUNC_DECLs auto-registered as class methods (ClassName prefix, `this` access, funcRetTypes + classMethods)
- **Cross-block persistence**: root scope survives — functions/variables from earlier comptime blocks available in later ones
- **Comptime libraries**: `import { } from "@/lib/comptime"` imports shared comptime helpers
- **@comptimeEmit(ssSource)**: generate SS source → compile (string mixin)
- **@typeInfo / getTypeInfo**: class/enum/interface reflection
- **compileError(msg)**: abort compilation with error
- **hasField/hasMethod**: compile-time structural checks
- **getAnnotatedClasses(ann)**: query classes with ANY annotation
- **emit(irString)**: inject raw LLVM IR
- **registerFunction/addStringConst**: low-level codegen helpers
- **Interpreter builtins**: string methods, concat, arithmetic, arrays, maps
- **Shared helpers**: flushComptimeSS() + flushComptimeIR() in codegen.ss

### Proven Comptime Patterns (test-verified)
- **Class-level comptime methods**: describe/fieldCount/fieldNames generated via getTypeInfo in class body (comptime_class_methods.ss)
- **Inline comptime expression**: `const x = comptime { return 6 * 7 }` → int/string/arithmetic/loops (comptime_inline_expr.ss)
- **Comptime library import**: lib/comptime.ss helpers used across files (comptime_library.ss)
- **ORM SQL generation**: @Entity/@Id/@Column → CREATE TABLE + INSERT SQL (comptime_orm.ss)
- **Enum serialization**: nameOf + fromString for int/string/auto enums (comptime_enum_serializer.ss)
- **JSON serialization**: type-aware field iteration → serializeX(obj) (comptime_json_serializer.ss)
- **Class/enum/interface introspection**: full reflection test suite

### Project Status
- **Bootstrap**: 47 files, ~18700 LOC, 201 tests (196 passing, 5 pre-existing interp_* failures).
- **Comptime system**: 10 comptime tests, inline expressions, class-level methods, cross-block persistence, shared library.

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Checker skips ARROW_FUNC**: @comptimeEmit-generated functions must be called inside arrow functions.
- **Auto-generated toJson**: Compiler generates `ClassName_toJson` for all classes. Don't reuse this name.
- **Class-level comptime**: COMPTIME_BLOCK nodes stored in methods block alongside FUNC_DECL. Registration (registerClass) naturally skips them (only processes FUNC_DECL). Execution in genClassDecl after normal methods. Emitted FUNC_DECLs auto-registered as class methods with ClassName prefix.
- **Comptime root scope**: interpExecComptime uses persistent root scope (interpComptimeRootScope). BLOCK body statements executed directly in root scope, nested blocks still push/pop normally.
- **interpReset deleted**: Was dead code after persistence change. Global init (`let interpVT = new Map()` etc.) handles initial state.
- **Comptime library ct* prefix**: All lib/comptime.ss helpers prefixed with `ct` to avoid collisions with user code.
- **Annotation collection handler-agnostic**: ALL annotations collected. emitAnnotationInits skips without handlers.
- **Enum registration**: registerEnum in both registerAllDecls and genStmt. Double-call safe.
- **PARAM nList for field annotations**: I4 is isStatic for class fields.
- **hasMethod exact match**: `,methods,`.indexOf(`,name,`) pattern.
- **FUNC_DECL I4 conflict**: I4 for annotations and isAbstract. Known issue.
- **@comptimeEmit two-pass**: first pass registers FUNC_DECL, second calls genStmt.
- **double→string**: `0.0` displays as `"0"` (runtime behavior).
- **COMPTIME_EXPR side effects in inferType**: Intentional — inferType is the earliest point where type is needed; cache prevents double execution. See comment at gen_types.ss:215.
- **flushComptimeSS/flushComptimeIR**: Shared helpers in codegen.ss. Used by COMPTIME_BLOCK (gen_stmts.ss) and COMPTIME_EXPR (gen_types.ss). Class-level comptime does NOT use flushComptimeSS — different semantics (methods vs top-level).
- **Rejected features**: Range syntax, pattern matching type patterns, Result<T,E> + ? operator, FFI via dlopen, Kotlin/Scala syntax.

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
