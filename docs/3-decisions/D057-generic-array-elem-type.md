---
id: D057
status: implemented
depends-on: []
---
# D057: Generic Array Element Type Inference

## Decision
Replace hardcoded `inferArrayElemType()` type checks (`<string>`, `<int>`, `<double>`) with generic type parameter extraction from the type annotation string. Also fix all codegen call sites to properly handle ptr-typed array elements (class instances, interfaces, etc.).

## Reasoning
`inferArrayElemType()` only recognized three specific type parameters. `Array<fn>`, `Array<ClassName>`, and other generic array types returned empty string, causing:
- for-in loops to fall back to i64 (wrong LLVM type for ptr-typed elements)
- INDEX_ACCESS to skip necessary inttoptr conversion
- Destructuring to store i64 into ptr allocas

Per P4a: compiler limitation is a bug, not a boundary.

## Implementation
1. **gen_types.ss**: Extract type parameter generically via `indexOf("<")` + `substring()` instead of three `contains()` checks
2. **gen_exprs.ss**: Add `ssTypeToLLVM(idxElem) == "ptr"` branch for inttoptr in INDEX_ACCESS
3. **gen_stmts.ss**: Add `double` (bitcast) and `ptr` (inttoptr) branches in for-in element conversion
4. **gen_decls.ss**: Add `ptr` branch with inttoptr + trackPtrVar + emitRetainForType in destructuring

## Rejected Alternatives
- Adding `<fn>` as a fourth hardcoded check: doesn't solve the general problem for class types
- Extracting a shared `emitConvertI64ToType()` helper: P13 says three similar lines are better than premature abstraction; contexts differ (return vs store, RC management varies)

## Tensions
- for-in loop does NOT retain ptr elements (array alive during iteration); destructuring DOES (variable outlives expression). This asymmetry is correct and matches existing string handling.
