---
id: I003
title: Semantic analysis incomplete — missing return path, type checking, inferType pre-pass
severity: high
related-decisions: [D003, D007, D012, D053, D054, D060, D063, D064, D065]
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
- ~~Function argument type matching~~ ✅ (D053, D054)
- ~~Return type consistency~~ ✅ (D060)
- ~~Assignment type compatibility~~ ✅ (D053)
- ~~Field type mismatches~~ ✅ (D053)
- ~~METHOD_CALL / NEW_EXPR argument count~~ ✅ (D012)
- ~~NEW_EXPR argument type matching~~ ✅ (D064)

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
- ✅ Type inference in checker: `checkerInferType()` — literals, IDENT, CALL, NEW_EXPR, BINARY, MEMBER_ACCESS, etc. (D053)
- ✅ VAR_DECL type checking: annotation vs initializer type (D053)
- ✅ ASSIGN type checking: variable type vs RHS for simple assignment (D053)
- ✅ MEMBER_ASSIGN type checking: field type vs assigned value (D053)
- ✅ CALL argument type checking: parameter types vs argument types for non-overloaded, non-generic functions (D053)
- ✅ METHOD_CALL argument type checking: method parameter types vs argument types, parent chain walk for inherited methods (D054)
- ✅ METHOD_CALL return type inference: `checkerInferType` + `inferCheckerClass` handle METHOD_CALL via `methodRetTypes`, enabling chain call type resolution (D054)
- ✅ RETURN type checking: return value type vs declared function return type (D060)
- ✅ Generic type parameter compatibility: `isTypeCompatible()` recognizes type params like `T` via `currentTypeParams` tracking (D063)
- ✅ NEW_EXPR argument type checking: positional + named args vs field types, inheritance chain walk, generic class skip (D064)
- ✅ INDEX_ACCESS type inference + INDEX_ASSIGN type checking + builtin function return types (D065)
- Remaining: full inferType migration to checker (Phase 4)

### Phase 4: Migrate inferType to checker
Move `inferType()` from gen_exprs.ss to checker.ss as a pre-pass. Checker populates type info for all expressions. Codegen reads cached types instead of re-inferring. This enables I002 (structured types) to be addressed independently.

## Context
Files: checker.ss (~910 lines), check_stmts.ss (~680 lines). D003 established the incremental approach — each phase is independently verifiable. D012 extended arg count checking to constructors (with inheritance) and methods (with parent chain). D053 added `checkerInferType()` for compile-time type inference and basic type checking at 4 sites (VAR_DECL, ASSIGN, MEMBER_ASSIGN, CALL). D054 completed Phase 3 by adding METHOD_CALL argument type checking with method param/return type storage, parent chain walk, and chain call resolution via `inferCheckerClass`/`checkerInferType` METHOD_CALL support. D060 added RETURN type checking (6th type check site). D063 added generic type parameter compatibility — `isTypeCompatible()` recognizes type params via `currentTypeParams` tracking, fixing false positives on generic functions. D064 added NEW_EXPR argument type checking for both positional and named constructor args, with inheritance chain walk and generic class skip. D065 added INDEX_ACCESS type inference (element type from Array<T>/List<T>), INDEX_ASSIGN type checking (8th check site), and registered actual return types for all built-in functions.
