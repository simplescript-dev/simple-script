# D004: RC Logic Centralization

## Status
firm

## Resolves
DI-7 — RC code scattered across gen_exprs.ss (~200 lines), gen_stmts.ss (~150 lines), gen_class.ss (~100 lines).

## Depends On
- axioms.md → C1 (bootstrap)
- principles.md → P6 (single responsibility)

## Decision
Created `gen_rc.ss` (268 lines) centralizing: 7 RC global variables, 8 scope/release helper functions, mapValueIsPtr, 4 cyclic ownership detection functions, plus new `trackPtrVar()` and `initRcState()`. Import order: codegen → gen_rc → gen_stmts → gen_exprs → gen_class → gen_runtime.

Not moved (reverse dependencies): `isOwnedExpr` (needs inferType from gen_exprs), `genNestedBlock` (needs genBlock from gen_stmts), inline retain/release calls (tightly coupled to business logic).

## Key Reasoning
Changing RC strategy required modifying 3 files and 20+ functions. Centralization means RC changes only touch gen_rc.ss. Inline RC stays because extracting it would create circular imports or artificial indirection.

## Rejected Alternatives
- **Move everything including inline RC**: Creates circular dependencies (gen_rc ↔ gen_exprs). Violated module ordering.
- **Independent RC pass**: Requires SSA-level intermediate representation. Not feasible without major language features.

## Interfaces With Other Decisions
- D005 (RC implementation): gen_rc.ss is the home for future RC enhancements.
- DI-4 Phase 4 (inferType migration): If inferType moves to checker, isOwnedExpr could also move to gen_rc.ss.

## Open Tensions
None currently.

## Notes
gen_stmts.ss 1082→945 lines, gen_class.ss 733→635 lines. Completed 2026-03-30.
