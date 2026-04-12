# Round 146

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/4-issues/1-open/ (check remaining open issues)
- tests/phase5/comptime_enum_serializer.ss (enum nameOf/fromString generator)
- tests/phase5/comptime_json_serializer.ss (JSON serializer generator)
- tests/phase5/comptime_orm.ss (ORM SQL generator)

## Last Round (max 3 sentences)
Added two comptime serializer demos with zero compiler changes: enum nameOf/fromString (int/string/auto-increment) and JSON serializer (type-aware field iteration). Both prove comptime system is powerful enough for real metaprogramming. 193/198 tests pass, bootstrap fixed-point verified.

## Task
**Continue comptime enhancement toward Zig-level**

1. **Check `docs/4-issues/1-open/`** for remaining open issues (priority: fix before new features)
2. If no actionable issues, continue comptime roadmap:
   - **Inline comptime expressions**: `comptime { val }` usable as expression, not just statement block
   - **Type-level comptime**: comptime inside class body to generate methods/fields
   - **Comptime map literals**: Map construction in interpreter for lookup tables
   - **@field(obj, "name")**: dynamic field access by comptime string (for interpreter-level introspection)
   - **Generic comptime serializer**: single `genToJson<T>()` that works for any class (needs comptime + generics bridge)

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Comptime Capabilities (current)
- **comptime blocks**: AST interpreter executes at compile time
- **@comptimeEmit(ssSource)**: generate SS source → compile (string mixin, D-language level)
- **@typeInfo / getTypeInfo**: class/enum/interface reflection
- **Class reflection**: fields (name, type, annotations), methods (name, returnType, params, annotations), class annotations
- **Interface reflection**: InterfaceInfo {name, kind="interface", methods [{name, returnType, params}]}
- **Enum reflection**: EnumInfo {name, kind="enum", isString, variants [{name, value}]}
- **Field-level annotations**: @Id, @Column("name"), @NotNull on class fields
- **compileError(msg)**: abort compilation with error message from comptime
- **hasField(class, field)**: compile-time check if class has field
- **hasMethod(class, method)**: compile-time check if class has method (exact match)
- **getAnnotatedClasses(ann)**: query classes with ANY annotation (handler-agnostic)
- **emit(irString)**: inject raw LLVM IR
- **registerFunction(name, ret, count)**: register function signature
- **addStringConst(str)**: add string constant, returns IR ref
- **Comptime user-defined functions**: function declarations inside comptime blocks work
- **Interpreter builtins**: string methods (length/trim/split/indexOf/substring/replace/startsWith/endsWith/charAt/includes), string concat (+), int/double/bool arithmetic, arrays, maps

### Proven Comptime Patterns (test-verified)
- **ORM SQL generation**: @Entity/@Id/@Column → CREATE TABLE + INSERT SQL (comptime_orm.ss)
- **Enum serialization**: nameOf(value→name) + fromString(name→value) for int/string/auto enums (comptime_enum_serializer.ss)
- **JSON serialization**: type-aware field iteration → serializeClassName(obj) (comptime_json_serializer.ss)
- **Class introspection**: hasField/hasMethod/compileError guards (comptime_introspect.ss)
- **Field annotations**: @Id/@Column/@NotNull on class fields (comptime_field_annotations.ss)
- **Enum reflection**: int/string/auto-increment variant iteration (comptime_enum_reflect.ss)
- **Interface reflection**: method/param/returnType iteration (comptime_iface_reflect.ss)

### Project Status
- **Bootstrap**: 47 files, ~18700 LOC, 198 tests (193 passing, 5 pre-existing interp_* failures).
- **Comptime system mature**: 7 comptime tests covering reflection, introspection, ORM, serialization — all working.
- **Annotation collection**: handler-agnostic since R144, getAnnotatedClasses works for any annotation.

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Checker skips ARROW_FUNC**: @comptimeEmit-generated functions must be called inside arrow functions.
- **Auto-generated toJson**: Compiler auto-generates `ClassName_toJson` for all classes. Don't use this name in comptime-generated functions.
- **Annotation collection is handler-agnostic**: ALL class/method annotations collected. emitAnnotationInits skips those without handlers.
- **Enum registration**: registerEnum called in both registerAllDecls and genStmt. Double-call safe.
- **PARAM nList for field annotations**: PARAM I4 is isStatic for class fields.
- **hasMethod exact match**: `,methods,`.indexOf(`,name,`) pattern.
- **Interface reflection sources**: ifaceMethodsCG/Rets/Pars registries.
- **FUNC_DECL I4 conflict**: I4 used for both annotations and isAbstract. Known issue.
- **RETURN flag ordering**: interpReturnFlag set AFTER interpEval(returnExpr).
- **interpCall isolation**: save/restore break+continue flags.
- **@comptimeEmit two-pass**: first pass registers FUNC_DECL, second calls genStmt.
- **comptimeSS flushed per block**: cleared after tokenize→parse→genStmt.
- **double→string**: `0.0` displays as `"0"` (runtime snprintf behavior). Tests should expect this.
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
