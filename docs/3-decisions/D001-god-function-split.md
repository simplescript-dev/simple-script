# D001: God Function Split (DI-1)

## Status
firm

## Resolves
DI-1 — 6 god functions (100-184 lines) split into 24 focused handlers.

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P6 (dispatcher only dispatches)

## Decision
Split 6 god functions across gen_exprs.ss, gen_stmts.ss, gen_class.ss into 24 handler functions. Dispatchers contain only if/kind → delegate. Each handler ≤ 50 lines. genBinary → 7 functions, genCall → 4, genClassDecl → 4, genMethodCall → 4, genExpr/genStmt → extracted per-case handlers.

## Key Reasoning
God functions made it impossible to modify one feature without risking others. Go/Rust compilers use one handler per variant. Flat if/else chosen over dispatch table (SS has no Map<string, fn>).

## Rejected Alternatives
- ✗ **Coarse grouping by type**: Produced 60-70 line functions still mixing concerns. P6 violated.
- ✗ **Map-based dispatch table**: SS lacks first-class function types in Map. Would require language feature first.
- ✗ **Multi-level dispatchers**: Added classification maintenance cost with no benefit. P7 violated.

## Notes
Completed 2026-03-30. Bootstrap fixed-point verified.
