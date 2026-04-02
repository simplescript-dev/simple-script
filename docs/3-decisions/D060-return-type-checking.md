# D060: RETURN Statement Type Checking

**Status**: Implemented
**Depends-on**: D053, D054, D059

## Decision

Add type checking for RETURN statements: verify that the return value's inferred type is compatible with the enclosing function's declared return type.

## Reasoning

The checker already validates types at VAR_DECL, ASSIGN, MEMBER_ASSIGN, CALL args, and METHOD_CALL args (D053/D054). RETURN was the last major unchecked site where type mismatches could silently produce wrong code or crash at runtime.

## Implementation

- **`currentFuncRetType`** global variable tracks the enclosing function's declared return type.
- **FUNC_DECL handler** saves/restores `currentFuncRetType` around body checking (supports nested functions and class methods).
- **RETURN handler** calls `checkerInferType(valId)` and `isTypeCompatible()` to validate the return value type.
- **Conservative**: Skips check when return type annotation is "" (unspecified) or "void", or when the return value type cannot be inferred (returns "").

## Cases Caught

- `return "hello"` in function declared `: int` → error
- `return new Enemy(...)` in function declared `: Player` → error (unrelated classes)
- `return this.intField` in method declared `: string` → error

## Cases Allowed

- `return 10` in function declared `: double` → OK (int→double widening)
- `return new Dog(...)` in function declared `: Animal` → OK (inheritance)
- `return someCall()` where type unknown → skipped (conservative)

## Rejected Alternatives

- **Full inferType pre-pass (I003 Phase 4)**: Would be more complete but is a much larger refactoring. The per-site checking approach is incremental and catches the most common errors.
- **Checking bare `return` in non-void functions**: Already covered by return path analysis. Adding value-presence checking would be redundant.

## Interfaces

- `currentFuncRetType: string` — new global, save/restored per FUNC_DECL
- No new public functions — uses existing `checkerInferType()` and `isTypeCompatible()`

## Tensions

- Some return type mismatches won't be caught when `checkerInferType` returns "" (e.g., builtin function calls). This is by design — false negatives are preferable to false positives in a bootstrapping compiler.
