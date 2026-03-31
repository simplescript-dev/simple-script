# D026: Generic Functions via Monomorphization

## Status: Accepted

## Context

SimpleScript Phase 4 needs generic functions (`function identity<T>(x: T): T`). The parser already parsed `<T, U>` syntax but discarded type parameters.

Two approaches considered:
1. **Type erasure** — erase type info, pass everything as i64
2. **Monomorphization** — generate specialized code per concrete type

## Decision

**Monomorphization**. Generic function bodies contain operations (`>`, `+`, `==`) that compile to different LLVM IR per type (e.g., `icmp sgt i32` vs `call @ss_strcmp`). Type erasure would require boxing/unboxing at every operation inside the body.

## Implementation

### Storage
- FUNC_DECL S3 slot stores comma-separated type params (e.g., `"T"` or `"T,U"`)
- `genericFuncNodes` Map: function name → AST node ID (for re-traversal during specialization)
- `specializedFuncs` Map: mangled name → `"1"` (prevents duplicate generation)
- `genericTypeSubs` Map: active substitution table (`"T"→"int"`) during specialization

### Call-site specialization
Reuses the arrow function state-save/buffer/flush pattern:
1. Infer concrete types from arguments (`inferType` on each actual arg)
2. Build mangled name (e.g., `identity_i` for `identity<int>`)
3. Save codegen state → set `genericTypeSubs` + `specFuncName` → emit `genFuncDecl` into buffer
4. Restore state → buffer flushed via `flushGenericSpecDefs()`

### Type substitution
`resolveTypeParam(t)` checks `genericTypeSubs` Map. Called by:
- `ssTypeToLLVM()` — converts resolved type to LLVM type
- `typeSig()` — generates mangled signature character
- `emitParamAllocas()` — resolves param types during specialization
- `genFuncDecl()` — resolves return type

### Type inference
`inferGenericRetType(callee, argList)` matches declared param types to actual arg types to resolve the return type for `inferType()`.

## Files Changed
- `parser.ss` — store type params in S3
- `codegen.ss` — global state + registration + skip generic bodies
- `gen_types.ss` — resolveTypeParam + inferGenericRetType + ssTypeToLLVM/typeSig substitution
- `gen_decls.ss` — skip generic in genFuncDeclStmt + name override + param resolve + flush
- `gen_calls.ss` — genGenericCall (core monomorphization)

## Not Covered (Future Work)
- Generic classes: `class Box<T>(value: T)`
- Explicit type args: `identity<int>(42)`
- Type constraints: `<T: Comparable>`
