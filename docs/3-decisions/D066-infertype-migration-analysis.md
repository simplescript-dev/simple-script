# D066: inferType Migration Analysis — Phase 4 Closure

**Status**: Accepted
**Depends-on**: D053, D054, D059, D060, D063, D064, D065
**Related**: I003

## Decision

Close I003 Phase 4 ("Migrate inferType to checker"). The codegen `inferType()` and checker `checkerInferType()` serve fundamentally different purposes and cannot be unified. Phase 3 (8 type check sites + builtin type registration) is the practical completion point for compile-time semantic analysis.

## Analysis

### Two Functions, Two Purposes

| Aspect | `inferType()` (gen_types.ss) | `checkerInferType()` (checker.ss) |
|--------|------|------|
| **Purpose** | LLVM IR generation — select correct instructions | Compile-time type checking — catch user errors |
| **Returns for unknown** | `"int"` (safe LLVM default → `i32`) | `""` (unknown → skip type check) |
| **NULL_LIT** | `"ptr"` (LLVM pointer type) | `""` (type unknown) |
| **ARRAY_LIT** | `"ptr"` (LLVM pointer type) | `"Array"` (source type) |
| **LLVM-specific types** | `"i64"`, `"ptr"` | Never returns these |
| **Generic classes** | Mangled name (`"Box_i"`) via `inferGenericClassName` | Plain name (`"Box"`) |
| **Data stores** | `varTypes`, `funcRetTypes`, `objClasses`, `classFields` | `varNames`, `funcNames`, `checkerFieldTypes` |
| **Runs during** | Code generation phase | Type checking phase |

### Call Site Analysis (63 total)

- **13 internal** (recursive/infrastructure within inferType itself)
- **43 cannot be replaced** — depend on LLVM-level types:
  - `"i64"` detection for truncation/casting (13 sites across gen_assigns, gen_exprs, gen_builtins, gen_methods, gen_stmts)
  - `"int"` default for LLVM alloca/instruction selection (nearly all sites)
  - `"ptr"` for NULL_LIT/ARRAY_LIT handling (3 sites)
  - Generic monomorphization via `inferGenericRetType`/`inferGenericClassName` (4 sites)
  - Codegen-specific registries (`funcRetTypes` with mangled names, `objClasses`)
- **7 potentially replaceable** — simple `"string"` vs non-string checks on literals, but unsafe due to different scope/registry state between phases

### Why Migration Fails

1. **Type vocabulary mismatch**: Codegen needs `"i64"` (for fn pointers stored as i64), `"ptr"` (for null/arrays). Checker correctly never returns LLVM types — mixing them violates separation of concerns.

2. **Default value semantics**: `inferType` returns `"int"` for unknowns → `ssTypeToLLVM("int")` → `"i32"` (safe LLVM default). `checkerInferType` returns `""` for unknowns → type check skipped (correct checker behavior). Changing either default breaks its respective system.

3. **Different data lifetimes**: Checker state is populated during check phase and discarded. Codegen state is populated during registration/generation. Bridging would require persisting checker state or running checker inline during codegen.

4. **Generic inference**: Codegen's `inferGenericRetType()` and `inferGenericClassName()` use monomorphization state that only exists during code generation. Checker has no equivalent — nor should it, since generic monomorphization is a codegen concern.

## What Phase 3 Achieved

The original goal of I003 was to catch type errors at compile time. Phase 3 delivers this with 8 type check sites covering all major assignment/call patterns:

1. VAR_DECL — annotation vs initializer (D053)
2. ASSIGN — variable type vs RHS (D053)
3. MEMBER_ASSIGN — field type vs value (D053)
4. CALL args — parameter types vs argument types (D053)
5. METHOD_CALL args — method parameter types vs argument types (D054)
6. RETURN — return value vs declared return type (D060)
7. NEW_EXPR args — constructor field types vs argument types (D064)
8. INDEX_ASSIGN — element type vs assigned value (D065)

Plus: ~60 builtin method return/param types (D059), generic type param compatibility (D063), builtin function return types (D065).

## Rejected Alternatives

### A: Full migration with LLVM type extension
Extend `checkerInferType` to return `"i64"`, `"ptr"`, handle generic monomorphization. **Rejected**: conflates semantic checking with code generation, violates separation of concerns.

### B: Cached type map bridge
Checker stores per-node types in a Map, codegen reads them and converts to LLVM types. **Rejected**: adds complexity (new global Map, ~50 conversion call sites), checker would still need codegen's registries for full coverage, net code increase with marginal benefit.

### C: Gradual replacement (7 safe sites only)
Replace only the 7 potentially-safe call sites. **Rejected**: high risk for low benefit — different scope state could cause subtle bugs, and 7 of 50 sites doesn't justify the coupling.

## Resolution

- I003 Phase 3 is the practical completion point
- `inferType` remains in codegen as an LLVM-level type selection function
- `checkerInferType` remains in checker as a source-level type inference function
- Future type checking improvements (new check sites, more builtin types) extend `checkerInferType` independently
- I003 Phase 4 is closed — the two-function architecture is correct by design
