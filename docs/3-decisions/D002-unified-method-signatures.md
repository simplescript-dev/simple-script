# D002: Unified Built-in Method Signature Registry

## Status
firm

## Resolves
DI-5 — 8 hardcoded string lists for built-in method return types.

## Depends On
- axioms.md → C1 (bootstrap)

## Decision
Register all 35 built-in functions in `funcRetTypes` and 32 built-in methods in `methodRetTypes` (single init function). `callReturnType()` reduced from 19 to 4 lines. Adding a new method requires one line in one place.

## Key Reasoning (3 sentences max)
Scattered hardcoded lists caused silent bugs when a method was added in one list but missed in another. Single registry eliminates this class of bugs entirely.

## Rejected Alternatives
- Keep lists but add comments: Still error-prone. Human discipline doesn't scale.

## Interfaces With Other Decisions
- D007 — checker builtins list must stay synced with codegen funcRetTypes.

## Open Tensions
None currently.

## Notes
Completed 2026-03-30. Bootstrap fixed-point verified.
