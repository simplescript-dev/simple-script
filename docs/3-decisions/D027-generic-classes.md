# D027: Generic Classes via Monomorphization

## Status: Accepted

## Context

D026 implemented generic functions via monomorphization. Generic classes are the natural extension: `class Box<T>(value: T)` with methods, specialized at `new Box(42)` to produce `Box_i` with all concrete types.

Key difference from generic functions: classes need **pre-registration in multiple Maps** (classFields, classFieldTypes, classMethods, classIds, funcRetTypes, classConstFields) before `genClassDecl` can emit correct IR.

## Decision

**Monomorphization**, reusing the D026 infrastructure. Each unique instantiation (`new Box(42)`, `new Box("hello")`) generates a fully specialized class (`Box_i`, `Box_s`) with concrete field types, methods, and RC functions.

## Implementation

### Storage
- `classTypeParamsMap` (parser.ss): Global Map keyed by CLASS_DECL node ID → comma-separated type params. Separate Map needed because CLASS_DECL S1-S3 slots are all taken (S1=name, S2=parent, S3=implList).
- `genericClassNodes` Map: class name → AST node ID (for re-traversal during specialization)
- `specializedClasses` Map: mangled name → `"1"` (prevents duplicate generation)
- `specClassName`: active mangled name during specialization (analogous to `specFuncName`)

### Specialization flow
1. `genNewExpr()` detects generic class via `genericClassNodes.has(className)`
2. `genGenericNewExpr()` infers type subs from constructor args
3. Builds mangled name: `Box_i`, `Pair_i_s` (using `typeSig()`)
4. `preRegisterSpecializedClass()` populates all codegen Maps with concrete types + emits struct definition to module header
5. State-save/buffer/flush pattern: save 12+ codegen vars → set `genericTypeSubs` + `specClassName` → call `genClassDecl()` → buffer IR to `genericSpecDefs` → restore state
6. Emit constructor call: `call ptr @Box_i_new(args...)`

### Pre-registration (critical timing)
`preRegisterSpecializedClass()` must run BEFORE any `ssTypeToLLVM()` call on the mangled name. Called from two sites:
- `inferGenericClassName()` in gen_types.ss (early, during type inference)
- `genGenericNewExpr()` in gen_class.ss (during codegen)
Guard `if (classFields.has(mangledName) == 1) { return }` prevents double registration.

### Struct definition placement
Struct type definitions (`%Box_i = type { ... }`) emitted during pre-registration to:
- `strConsts` (in-memory mode) — prepended to module output
- `.str` file (file-output mode) — appended to string constants file

This ensures types are defined before any `getelementptr` references in function bodies.

### Method type resolution
`genClassMethod()` calls `resolveTypeParam()` on return types and parameter types, using the active `genericTypeSubs` Map during specialization.

### Type inference
`inferGenericClassName()` in gen_types.ss infers the mangled class name from constructor args, enabling `resolveObjClass()` and `inferType()` to return the specialized class name (e.g., `Box_i` instead of `Box`).

## Files Changed
- `parser.ss` — `classTypeParamsMap` + `classTypeParams()` accessor + parse `<T, U>` in `parseClassDecl()`
- `codegen.ss` — global state + registration skip + emit skip + import
- `gen_class.ss` — `registerClass` skip + `genClassDecl` name override + `genClassMethod` type resolution + `genGenericNewExpr` + `preRegisterSpecializedClass`
- `gen_types.ss` — `inferGenericClassName` + `resolveObjClass`/`inferType` NEW_EXPR handling
- `gen_decls.ss` — `setObjClass` uses mangled name for generic NEW_EXPR
- `checker.ss` — lenient constructor arity (0-99) for generic classes

## Not Covered (Future Work)
- Explicit type args: `new Box<int>(42)`
- Generic class inheritance: `class X<T> extends Y`
- Type constraints: `<T: Comparable>`
- Generic interfaces
