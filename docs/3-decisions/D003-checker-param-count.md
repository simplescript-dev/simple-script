# D003: Checker Function Parameter Count Validation (DI-4 Phase 1)

## Status
firm

## Resolves
DI-4 Phase 1 — No function argument count checking at compile time.

## Depends On
- axioms.md → C1 (bootstrap)
- D001 (clean checker structure enables incremental additions)

## Decision
Dual Map approach: `funcParamMin` + `funcParamMax` track [min, max] argument range per function. Overloaded functions use union interval [min(all_min), max(all_max)] (lenient — avoids false positives). 24 built-in functions registered by arity group. CALL nodes checked; METHOD_CALL/NEW_EXPR deferred to Phase 3+.

## Key Reasoning
Dual Map handles default parameters and overloads naturally. Union interval is conservative — may miss some errors but never produces false positives, which matters for a self-bootstrapping compiler.

## Rejected Alternatives
- ✗ **Single paramCount Map**: Cannot handle default/optional parameters. Rejected.
- ✗ **Full overload resolution**: Requires type inference in checker (Phase 3+ territory). Too early.
- ✗ **Check METHOD_CALL/NEW_EXPR too**: Requires class type inference not available in checker. Deferred.

## Interfaces With Other Decisions
- DI-4 Phase 2-4: This is step 1 of a 4-phase plan. Phase 2 = return path analysis, Phase 3 = type checking.

## Notes
Also fixed: chain-based scope (replacing broken scopeDepth), enabled const reassignment detection, added TRY/THROW node traversal. Completed 2026-03-30.
