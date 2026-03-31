---
id: I003
title: Semantic analysis incomplete — missing return path, type checking, inferType pre-pass
severity: high
related-decisions: [D003, D007, D012]
related-principles: [P8]
origin: design-improvements.md DI-4 Phase 2-4
---
## Description
Pipeline: `Lexer → Parser → Checker → Codegen`. checker.ss currently validates:
- ✅ Undefined variables/functions (incl. fn-pointer calls, forward refs)
- ✅ const reassignment (chain-based scope, D003)
- ✅ Function argument count — CALL nodes only (D003)
- ✅ Return path analysis — non-void functions must return on all paths (D007)
- ✅ Checker integrated into compile pipeline (`ss build` runs checker)

**Not checked** (silently produces wrong code or crashes):
- Function argument type matching
- Return type consistency
- Assignment type compatibility
- Field type mismatches
- METHOD_CALL / NEW_EXPR argument count (needs type inference)

## Impact
- Missing `return` in non-void function → LLVM returns garbage → silent wrong results
- Type mismatch in assignment → wrong LLVM operation → crash or wrong output
- Wrong argument types → codegen emits mismatched IR → LLVM verifier error or silent bug
- Errors only caught at runtime (or not at all) instead of compile time

## Best Practices
- **Go compiler**: `cmd/compile/internal/typecheck` — independent pass, two-scan forward declaration
- **Rust compiler**: `rustc_hir_typeck` — independent crate, constraint-based type inference
- **Zig compiler**: `Sema` — semantic analysis is the largest module

## Proposed Solution (phased)

### Phase 2: Return path analysis ✅ (D007)
Implemented. `blockAlwaysReturns`/`stmtAlwaysReturns` walk AST to verify all control paths return. Handles: if/else, try/catch, switch/default, throw, exit() as noreturn. Checker also integrated into `compile()` pipeline.

### Phase 3: Basic type checking (partially done)
- ✅ METHOD_CALL / NEW_EXPR: argument count checking (D012) — constructor params with inheritance accumulation, method params with parent chain walk, receiver resolution for `this`/typed vars/new expr, built-in Map/Math methods
- Assignment: RHS type compatible with LHS declared type
- Function call: argument types match parameter types
- Remaining METHOD_CALL receiver resolution (chain calls, function return types — needs inferType in checker)

### Phase 4: Migrate inferType to checker
Move `inferType()` from gen_exprs.ss to checker.ss as a pre-pass. Checker populates type info for all expressions. Codegen reads cached types instead of re-inferring. This enables I002 (structured types) to be addressed independently.

## Context
Files: checker.ss (current ~865 lines). D003 established the incremental approach — each phase is independently verifiable. D012 extended arg count checking to constructors (with inheritance) and methods (with parent chain). Receiver class resolution covers 3 static cases; full coverage requires Phase 4 (inferType migration).
