# D002: Unified Built-in Method Signature Registry (DI-5)

## Status
firm

## Resolves
DI-5 — 8 hardcoded string lists for built-in method return types.

## Depends On
- axioms.md → C1 (bootstrap)

## Decision
Register all 35 built-in functions in `funcRetTypes` and 32 built-in methods in `methodRetTypes` (single init function). `callReturnType()` reduced from 19 to 4 lines. Adding a new method requires one line in one place.

## Key Reasoning
Scattered hardcoded lists caused silent bugs when a method was added in one list but missed in another. Single registry eliminates this class of bugs entirely.

## Rejected Alternatives
- ✗ **Keep lists but add comments**: Still error-prone. Human discipline doesn't scale.

## Notes
Completed 2026-03-30. Bootstrap fixed-point verified.
