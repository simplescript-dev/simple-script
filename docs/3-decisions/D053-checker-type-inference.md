# D053: Checker Type Inference and Basic Type Checking

**Status:** Accepted
**Depends-on:** D003 (Checker scope), D007 (Return path), D012 (Arg count)

## Decision

Add `checkerInferType()` to the checker for compile-time type inference, and use it for basic type checking at four sites: variable declarations (VAR_DECL), variable assignments (ASSIGN), field assignments (MEMBER_ASSIGN), and function call arguments (CALL).

## Reasoning

I003 identifies that the checker silently passes type mismatches to codegen, producing wrong LLVM IR or runtime crashes. The codegen has `inferType()` (gen_types.ss) but the checker ran without any type awareness. Adding type inference to the checker catches mismatches at compile time with clear error messages.

This is I003 Phase 3 progress — building the foundation for full type checking without a complete `inferType` migration (Phase 4).

## Implementation

### `checkerInferType(nodeId)` — checker.ss
Returns SS type string for expressions using only checker-available state:
- Literals: INT_LIT→"int", DOUBLE_LIT→"double", STRING_LIT/TEMPLATE_LIT→"string", TRUE_LIT/FALSE_LIT→"int"
- IDENT: `lookupVar()` (returns "" for "auto" to skip check; checks `lookupFunc` only if var not found)
- NEW_EXPR: class name from S1
- CALL: return type from `funcNames` (skips "builtin" marker)
- MEMBER_ACCESS: delegates to `inferCheckerClass` + `checkerFieldTypes`
- BINARY: comparison ops→"int", Add with string→"string", double promotion
- Returns "" for unknown types (METHOD_CALL, INDEX_ACCESS, etc.) — type check skipped

### `isTypeCompatible(declared, actual)` — checker.ss
- Empty/"auto" types always compatible (unknown = skip)
- Exact match, int→double widening, bool↔int equivalence
- Interface declared type accepts any actual type (can't verify impl at call site)
- Class inheritance: walks `checkerClassParents` chain
- Generic base type match: `Array<int>` compat with `Array<string>` (imprecise but no false positives)
- Array/List/Tuple cross-compatibility

### Parameter type storage — checker.ss first pass
- `funcParamTypes` map: `"funcName:paramIndex"` → type string
- Only stored for first definition (overloads detected via `funcNames.has()` before `defineFunc()`)
- Generic functions (S3 non-empty) excluded — type params like "T" are not concrete types
- `funcOverloaded` map prevents type checking at call sites for overloaded functions

### Type check sites — check_stmts.ss
1. **VAR_DECL**: explicit type annotation vs initializer type
2. **ASSIGN**: variable type vs RHS (simple `=` only, compound assignments skipped)
3. **MEMBER_ASSIGN**: field type vs assigned value (simple `=` only)
4. **CALL**: argument types vs declared parameter types (non-overloaded, non-generic, no spread)

## Rejected Alternatives

- **Full inferType migration**: Moving codegen's `inferType()` to checker requires resolving all codegen-specific state (`getVarType`, `funcRetTypes`, `classFields`). Too large for one round.
- **Builtin parameter type checking**: Builtins would need manual type registration. Deferred — no false positives from skipping.
- **METHOD_CALL type checking**: Requires method return type tracking + receiver resolution. Deferred.

## Tensions

- **Precision vs safety**: `isTypeCompatible` is deliberately loose (e.g., `Array<int>` matches `Array<string>`). This avoids false positives at the cost of missing some errors. Tighter checking requires full generic type argument tracking.
- **Interface compatibility**: Any type accepted for interface-declared parameters. Full verification needs an "implements" relationship registry accessible at call sites.
