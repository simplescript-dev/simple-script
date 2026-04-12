# Round 149

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/4-issues/1-open/ (check remaining open issues)
- bootstrap/gen_class.ss:397-500 (emitClassComptimeMethods + genClassDecl derive processing)
- lib/comptime.ss (comptime standard library — ctJsonBody, ctGenMethodToJson, ctDeriveToJson etc.)
- tests/phase5/comptime_derive.ss (@derive test)

## Last Round (max 3 sentences)
Implemented @derive annotation: `@derive("ToJson,ToString")` on a class triggers comptime function `ctDeriveXxx(className)` which generates class methods automatically. Extracted `emitClassComptimeMethods` helper shared by class-level comptime and @derive. Added genAutoToJson skip when comptime/derive already provides toJson. 197/202 tests pass, bootstrap fixed-point verified.

## Task
**Continue comptime enhancement toward Zig-level**

1. **Check `docs/4-issues/1-open/`** for remaining open issues (priority: fix before new features)
2. If no actionable issues, continue comptime roadmap:
   - **Custom @derive handlers**: user-defined ctDeriveXxx functions beyond ToJson/ToString
   - **Comptime conditional compilation**: `comptime { if (TARGET == "linux") { ... } }`
   - **Comptime type generation**: generate entire class definitions at comptime
   - **@field(obj, "name")**: dynamic field access by comptime string
   - **Comptime assertions**: `comptimeAssert(cond, msg)` for library authors

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Comptime Capabilities (current)
- **comptime blocks**: AST interpreter executes at compile time
- **Inline comptime expressions**: `comptime { return expr }` — compile-time constant (int/double/string/bool)
- **Type-level comptime**: `comptime { }` in class body — FUNC_DECLs become class methods
- **@derive annotation**: `@derive("ToJson,ToString")` → calls `ctDeriveXxx(className)` → generates class methods. genAutoToJson skips when derive already provides toJson.
- **Cross-block persistence**: root scope survives across comptime blocks
- **Comptime libraries**: `import { } from "@/lib/comptime"` — shared helpers with ct* prefix
- **@comptimeEmit(ssSource)**: string mixin → compile
- **@typeInfo / getTypeInfo**: class/enum/interface reflection
- **compileError(msg)**: abort compilation with error
- **hasField/hasMethod**: compile-time structural checks
- **getAnnotatedClasses(ann)**: query classes with ANY annotation
- **emit(irString)**: inject raw LLVM IR
- **Shared helpers**: flushComptimeSS/flushComptimeIR + emitClassComptimeMethods

### Proven Comptime Patterns (test-verified)
- **@derive annotation**: `@derive("ToJson")` / `@derive("ToString")` / `@derive("ToJson,ToString")` (comptime_derive.ss)
- **Class-level comptime methods**: describe/fieldCount/fieldNames via getTypeInfo (comptime_class_methods.ss)
- **Inline comptime expression**: `const x = comptime { return 6 * 7 }` (comptime_inline_expr.ss)
- **Comptime library import**: lib/comptime.ss helpers across files (comptime_library.ss)
- **ORM SQL generation**: @Entity/@Id/@Column → CREATE TABLE + INSERT (comptime_orm.ss)
- **Enum serialization**: nameOf + fromString (comptime_enum_serializer.ss)
- **JSON serialization**: standalone serializeX(obj) (comptime_json_serializer.ss)

### Project Status
- **Bootstrap**: 47 files, ~18700 LOC, 202 tests (197 passing, 5 pre-existing interp_* failures).
- **Comptime system**: 11 comptime tests, @derive, inline expr, class methods, cross-block persistence, library.

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Auto-generated toJson skip**: genAutoToJson checks classMethods for "toJson" — skips if comptime/@derive already generated it.
- **@derive convention**: `@derive("Xxx")` calls `ctDeriveXxx(className)` in comptime root scope. User defines handlers in comptime blocks or lib/comptime.ss.
- **emitClassComptimeMethods**: Shared by class-level comptime and @derive. Tokenizes comptimeSS → registers FUNC_DECLs as class methods → generates.
- **ctJsonBody accessor pattern**: `ctJsonBody(className, "obj")` for standalone, `ctJsonBody(className, "this")` for methods.
- **Checker skips ARROW_FUNC**: @comptimeEmit-generated functions must be called inside arrow functions.
- **Comptime root scope**: interpExecComptime uses persistent root scope. BLOCK body executed directly in root scope.
- **Comptime library ct* prefix**: All lib/comptime.ss helpers prefixed with `ct`.
- **Annotation collection handler-agnostic**: ALL annotations collected. emitAnnotationInits skips without handlers.
- **FUNC_DECL I4 conflict**: I4 for annotations and isAbstract. Known issue.
- **COMPTIME_EXPR side effects in inferType**: Intentional — cache prevents double execution.
- **flushComptimeSS/flushComptimeIR**: Shared in codegen.ss. Class-level comptime uses emitClassComptimeMethods instead.
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
