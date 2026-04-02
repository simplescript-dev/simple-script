---
id: D063
title: Generic type parameter compatibility in checker
status: implemented
depends-on: [D053, D060]
---

## Decision

Add `currentTypeParams` global to checker that tracks the current function's type parameters (from FUNC_DECL S3). In `isTypeCompatible()`, if either the declared or actual type is a current type parameter (e.g. `T`), return compatible.

## Reasoning

D060 introduced return type checking, which correctly errors on `return "hello"` from `function f(): int`. But for generic functions like `function addOne<T>(x: T): T`, the checker infers `return x + 1` as type `int` while the declared return type is `T`. Since `T` is a type parameter (not a concrete type), the checker cannot verify compatibility at definition site — it can only be checked at call site after monomorphization. So type parameters must be treated as universally compatible.

## Implementation

- `checker.ss`: Add `currentTypeParams` global (comma-separated type param names)
- `checker.ss` `isTypeCompatible()`: Split `currentTypeParams` by comma, if declared or actual matches any → return 1
- `check_stmts.ss` FUNC_DECL handler: Save/restore `currentTypeParams` from `nGetS3(id)` (same pattern as `currentFuncRetType`)

## Impact

- Fixes `generic_multi_call.ss` test (was the only pre-existing test failure)
- All 6 type check sites (VAR_DECL, ASSIGN, MEMBER_ASSIGN, CALL, METHOD_CALL, RETURN) now correctly handle generic type parameters
- No false negatives: concrete type mismatches still caught; only type parameter names bypass the check

## Rejected Alternatives

- **Skip return type check entirely for generic functions**: Too broad — would miss real errors like returning a string from a function with return type `Array<T>`.
- **Single-letter uppercase heuristic**: Fragile — relies on naming convention rather than parser data.
