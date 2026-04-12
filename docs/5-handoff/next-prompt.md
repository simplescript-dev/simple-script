# Round 156

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/4-issues/1-open/ (check remaining open issues)
- lib/comptime.ss (all built-in derive handlers + helpers)
- tests/phase5/comptime_derive_custom.ss (custom derive test)

## Last Round (max 3 sentences)
Added @derive("Equals") built-in handler for field-by-field equality comparison. Demonstrated user-defined custom derive handlers (ctDeriveDebug) proving the derive system is extensible. 204/209 tests pass, bootstrap fixed-point verified.

## Task
**Continue comptime enhancement toward Zig-level**

1. **Check `docs/4-issues/1-open/`** for remaining open issues (priority: fix before new features)
2. If no actionable issues, continue comptime roadmap:
   - **Comptime comprehensive showcase**: combine all features in a real-world scenario (build info module, auto-registry, config-driven codegen)
   - **Comptime code validation**: compile-time structural checks — e.g., `fieldCount(cls)`, `fieldNames(cls)`, `implements(cls, iface)`, `isSubclassOf(child, parent)`
   - **Comptime Map operations**: generate runtime lookup tables from compile-time Maps
   - **Comptime array comprehension**: generate arrays/lists at compile time
   - **@derive new handlers**: consider Hash, Copy, or other common patterns

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Comptime Capabilities (current)
- **comptime blocks**: AST interpreter executes at compile time
- **Inline comptime expressions**: `comptime { return expr }` — compile-time constant
- **Type-level comptime**: `comptime { }` in class body — FUNC_DECLs become class methods
- **@derive annotation**: `@derive("ToJson,ToString,Equals")` → ctDeriveXxx(className) → generates methods
- **Custom derive handlers**: Users define `ctDeriveXxx(className)` in comptime blocks — fully extensible
- **Comptime type generation**: CLASS_DECL, ENUM_DECL, INTERFACE_DECL via @comptimeEmit
- **Comptime type discovery**: classNames(), enumNames() — all registered type names
- **Conditional compilation**: OS, ARCH, DEBUG, COMPILER_VERSION + comptimeAssert + getenv
- **Comptime file I/O**: readFile, writeFile, fileExists at compile time
- **Comptime shell execution**: system(cmd) → exit code, shellOutput(cmd) → stdout string
- **Cross-block persistence**: root scope survives across comptime blocks
- **Comptime libraries**: `import { } from "@/lib/comptime"` — shared helpers
- **@comptimeEmit(ssSource)**: string mixin → compile
- **@typeInfo / getTypeInfo**: class/enum/interface reflection
- **compileError / comptimeAssert**: compile-time error/assertion
- **hasField/hasMethod**: compile-time structural checks
- **getAnnotatedClasses(ann)**: annotation queries
- **emit(irString)**: inject raw LLVM IR

### Built-in @derive Handlers
- **ToJson**: generates `toJson(): string` — JSON serialization of all fields
- **ToString**: generates `toString(): string` — `ClassName(field1=val1, field2=val2)` format
- **Equals**: generates `equals(other: ClassName): int` — field-by-field comparison (0/1)

### Proven Comptime Patterns (test-verified)
- **Shell execution**: git hash, build timestamp, uname, conditional on kernel (comptime_shell.ss)
- **Type discovery**: classNames/enumNames → auto-describe + enum registry (comptime_discovery.ss)
- **Type generation**: enum/interface/class with polymorphic dispatch (comptime_type_gen.ss)
- **File embedding**: readFile → parse config → generate constants (comptime_file_embed.ss)
- **Conditional compilation**: OS/ARCH/DEBUG + comptimeAssert (comptime_conditional.ss)
- **Class generation**: Vector3/Pair/Greeting with RC (comptime_class_gen.ss)
- **@derive built-in**: ToJson/ToString/Equals (comptime_derive.ss, comptime_derive_custom.ss)
- **@derive user-defined**: ctDeriveDebug custom handler (comptime_derive_custom.ss)
- **Class-level comptime**: describe/fieldCount/fieldNames (comptime_class_methods.ss)
- **Inline comptime**: `const x = comptime { return 6 * 7 }` (comptime_inline_expr.ss)
- **Comptime library**: lib/comptime.ss helpers (comptime_library.ss)
- **ORM SQL**: @Entity/@Id/@Column (comptime_orm.ss)
- **Enum serialization**: nameOf + fromString (comptime_enum_serializer.ss)
- **JSON serialization**: standalone serializeX(obj) (comptime_json_serializer.ss)

### Project Status
- **Bootstrap**: 47 files, ~18700 LOC, 209 tests (204 passing, 5 pre-existing interp_* failures).
- **Comptime system**: 18 comptime tests, full type generation + discovery + shell execution + custom derives.

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **shellOutput temp file**: Uses /tmp/ss_comptime_exec.tmp — concurrent compilations could conflict.
- **COMPTIME_EXPR in genGlobalVar**: Emits typed globals directly.
- **emittedDispatchers guard**: emitIfaceDispatchFn is idempotent.
- **flushComptimeSS 5-pass**: Pass 0 VAR_DECL → Pass 1 type registration → Pass 2 FUNC_DECL → Pass 3 codegen → Pass 4 interface dispatchers.
- **enumDeclNodes for enum names**: Use enumDeclNodes.keys() not enumValues.keys().
- **classNames excludes Map**: Filtered from classNames() results.
- **Predefined constants**: OS, ARCH, DEBUG, COMPILER_VERSION. SS_TARGET_OS/SS_TARGET_ARCH override.
- **FUNC_DECL I4 conflict**: I4 for annotations and isAbstract. Known issue.
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
