---
id: I003
title: Semantic analysis incomplete — missing return path, type checking, inferType pre-pass
severity: high
related-decisions: [D003]
related-principles: [P8]
origin: design-improvements.md DI-4 Phase 2-4
---
## Description
Pipeline: `Lexer → Parser → Checker → direct Codegen`. checker.ss currently validates:
- ✅ Undefined variables/functions
- ✅ const reassignment (chain-based scope, D003)
- ✅ Function argument count — CALL nodes only (D003)

**Not checked** (silently produces wrong code or crashes):
- Function argument type matching
- Return type consistency
- Assignment type compatibility
- Field type mismatches
- Whether all control paths return a value (non-void functions)
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

### Phase 2: Return path analysis
Every non-void function must have `return` on all control paths. Walk AST: if/else both branches must return, for/while body + fallthrough, try/catch both blocks.

### Phase 3: Basic type checking
- Assignment: RHS type compatible with LHS declared type
- Function call: argument types match parameter types
- METHOD_CALL / NEW_EXPR: argument count checking (requires resolving receiver class → needs class type info in checker)

### Phase 4: Migrate inferType to checker
Move `inferType()` from gen_exprs.ss to checker.ss as a pre-pass. Checker populates type info for all expressions. Codegen reads cached types instead of re-inferring. This enables I002 (structured types) to be addressed independently.

## Context
Files: checker.ss (current ~540 lines). D003 established the incremental approach — each phase is independently verifiable.
