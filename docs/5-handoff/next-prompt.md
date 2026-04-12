# Round 159

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/4-issues/1-open/ (check remaining open issues)
- lib/comptime.ss (all built-in derive handlers + string utilities + lookup generators)
- tests/phase5/comptime_string_utils.ss (string utilities + lookup + @derive(Default) test)

## Last Round (max 3 sentences)
Added comptime string utilities (ctJoin/ctRepeat/ctIndent/ctWrap), lookup table generation (ctGenLookup/ctGenReverseLookup), and @derive("Default") generating `empty()` zero-value factory. All functions are pure library additions to lib/comptime.ss, no compiler changes needed. 213 tests (208 passing, 5 pre-existing interp_* failures), bootstrap fixed-point verified.

## Task
**Continue comptime enhancement toward Zig-level**

1. **Check `docs/4-issues/1-open/`** for remaining open issues (priority: fix before new features)
2. If no actionable issues, continue comptime roadmap:
   - **Comptime Map operations**: build Maps at compile time, emit runtime lookup structures
   - **Comptime array comprehension**: generate arrays/lists at compile time
   - **@derive new handlers**: consider Hash, Comparable, or other common patterns
   - **Comptime loop unrolling**: generate repetitive code from comptime loops (e.g., N fields -> N accessors)
   - **Comptime code templates**: parameterized multi-line code generation patterns
   - **Comptime import/plugin**: load external .ss files as comptime plugins

### Open Issues (by priority)
1. **I001 -- Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 -- String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 -- AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 -- Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 -- Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Comptime Capabilities (current)
- **comptime blocks**: AST interpreter executes at compile time
- **Inline comptime expressions**: `comptime { return expr }` -- compile-time constant
- **Type-level comptime**: `comptime { }` in class body -- FUNC_DECLs become class methods
- **@derive annotation**: `@derive("ToJson,ToString,Equals,Copy,With,Default")` -> ctDeriveXxx(className) -> generates methods
- **Custom derive handlers**: Users define `ctDeriveXxx(className)` in comptime blocks -- fully extensible
- **Comptime type generation**: CLASS_DECL, ENUM_DECL, INTERFACE_DECL via @comptimeEmit
- **Comptime type discovery**: classNames(), enumNames() -- all registered type names
- **Conditional compilation**: OS, ARCH, DEBUG, COMPILER_VERSION + comptimeAssert + getenv
- **Comptime file I/O**: readFile, writeFile, fileExists at compile time
- **Comptime shell execution**: system(cmd) -> exit code, shellOutput(cmd) -> stdout string
- **Structural validation**: fieldCount(cls), fieldNames(cls), hasInterface(cls, iface), isSubclassOf(child, parent)
- **Validation helpers**: ctAssertHasField, ctAssertHasMethod, ctAssertImplements, ctAssertExtends (lib/comptime.ss)
- **String utilities**: ctJoin, ctRepeat, ctIndent, ctWrap (lib/comptime.ss)
- **Lookup table generation**: ctGenLookup, ctGenReverseLookup (lib/comptime.ss)
- **Cross-block persistence**: root scope survives across comptime blocks
- **Comptime libraries**: `import { } from "@/lib/comptime"` -- shared helpers
- **@comptimeEmit(ssSource)**: string mixin -> compile
- **@typeInfo / getTypeInfo**: class/enum/interface reflection
- **compileError / comptimeAssert**: compile-time error/assertion
- **hasField/hasMethod**: compile-time structural checks
- **getAnnotatedClasses(ann)**: annotation queries
- **emit(irString)**: inject raw LLVM IR

### Built-in @derive Handlers
- **ToJson**: generates `toJson(): string` -- JSON serialization of all fields
- **ToString**: generates `toString(): string` -- `ClassName(field1=val1, field2=val2)` format
- **Equals**: generates `equals(other: ClassName): int` -- field-by-field comparison (0/1)
- **Copy**: generates `copy(): ClassName` -- returns new instance with same field values
- **With**: generates `withFieldName(value): ClassName` -- per-field wither (immutable builder)
- **Default**: generates `empty(): ClassName` -- zero-value factory (0/0.0/"" per type)

### Proven Comptime Patterns (test-verified)
- **String utilities + lookup tables**: ctJoin/ctRepeat/ctIndent/ctWrap + ctGenLookup/ctGenReverseLookup (comptime_string_utils.ss)
- **Structural validation**: fieldCount/fieldNames/hasInterface/isSubclassOf + ctAssert helpers (comptime_validation.ss)
- **Comprehensive showcase**: 7 features combined in one scenario (comptime_showcase.ss)
- **Shell execution**: git hash, build timestamp, uname, conditional on kernel (comptime_shell.ss)
- **Type discovery**: classNames/enumNames -> auto-describe + enum registry (comptime_discovery.ss)
- **Type generation**: enum/interface/class with polymorphic dispatch (comptime_type_gen.ss)
- **File embedding**: readFile -> parse config -> generate constants (comptime_file_embed.ss)
- **Conditional compilation**: OS/ARCH/DEBUG + comptimeAssert (comptime_conditional.ss)
- **Class generation**: Vector3/Pair/Greeting with RC (comptime_class_gen.ss)
- **@derive built-in**: ToJson/ToString/Equals (comptime_derive.ss, comptime_derive_custom.ss)
- **@derive Copy/With**: immutable copy + per-field withers (comptime_derive_with.ss)
- **@derive Default**: zero-value factory (comptime_string_utils.ss)
- **@derive user-defined**: ctDeriveDebug/ctDeriveSchema custom handlers (comptime_derive_custom.ss, comptime_showcase.ss)
- **Class-level comptime**: describe/fieldCount/fieldNames (comptime_class_methods.ss)
- **Inline comptime**: `const x = comptime { return 6 * 7 }` (comptime_inline_expr.ss)
- **Comptime library**: lib/comptime.ss helpers (comptime_library.ss)
- **ORM SQL**: @Entity/@Id/@Column (comptime_orm.ss)
- **Enum serialization**: nameOf + fromString (comptime_enum_serializer.ss)
- **JSON serialization**: standalone serializeX(obj) (comptime_json_serializer.ss)

### Project Status
- **Bootstrap**: 47 files, ~18700 LOC, 213 tests (208 passing, 5 pre-existing interp_* failures).
- **Comptime system**: 21 comptime tests, full type generation + discovery + shell execution + custom derives + structural validation + string utilities + lookup tables.

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **shellOutput trailing newline**: Always `.trim()` shell output before embedding in generated code strings.
- **COMPTIME_EXPR in genGlobalVar**: Emits typed globals directly.
- **emittedDispatchers guard**: emitIfaceDispatchFn is idempotent.
- **flushComptimeSS 5-pass**: Pass 0 VAR_DECL -> Pass 1 type registration -> Pass 2 FUNC_DECL -> Pass 3 codegen -> Pass 4 interface dispatchers.
- **enumDeclNodes for enum names**: Use enumDeclNodes.keys() not enumValues.keys().
- **classNames excludes Map**: Filtered from classNames() results.
- **Predefined constants**: OS, ARCH, DEBUG, COMPILER_VERSION. SS_TARGET_OS/SS_TARGET_ARCH override.
- **`implements` is keyword**: Comptime interface check uses `hasInterface()`, not `implements()`.
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
