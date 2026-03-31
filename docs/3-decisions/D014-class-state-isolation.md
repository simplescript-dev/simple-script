# D014: Isolate Class State into gen_class.ss

## Status
firm

## Resolves
I001 — Global mutable state explosion (short-term: class state grouping)

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P3 (behavior-preserving refactoring)
- D004 (RC centralization — established the pattern)

## Decision
Move 11 class-related global variables from codegen.ss to gen_class.ss, co-located with their primary consumers (63 of 127 references). Introduce `initClassState()` to initialize all class Maps and register built-in classes (Map, Math). Extract class Map creation from `initFuncRetTypes()` so each init function has a single responsibility. `resetCodegen()` and `main()` call `initClassState()` before `initFuncRetTypes()`.

**Moved globals**: `classFields`, `classFieldTypes`, `classMethods`, `objClasses`, `classParents`, `classNeedsVtable`, `classVtableSlots`, `classVtableImpl`, `classDtorTags`, `dtorNextTag`, `currentClassName`.

## Key Reasoning (3 sentences max)
Follows the D004 pattern (RC state → gen_rc.ss with `initRcState()`), proven to reduce missed-reset bugs. Class state is the largest natural group (11 globals, 127 references) and gen_class.ss is the primary consumer (63 refs). Separating class init from function registry init makes each function single-responsibility.

## Rejected Alternatives
- ✗ **Map-of-Maps grouping**: SS Maps can't hold Maps as values. Would require string-encoding all state, adding complexity without benefit.
- ✗ **Move all codegen globals at once**: Violates V6 (minimal change). Class state is the largest, most cohesive group — do it first.
- ✗ **Keep globals in codegen.ss, only extract init functions**: Globals would remain separated from their init functions, defeating the co-location benefit of D004's pattern.

## Interfaces With Other Decisions
- D004 (RC centralization): Same pattern — dedicated file + init function for state group.
- I001: This resolves the class-state subset. Remaining groups (IR output, SSA counters, variable tracking, function registry) can follow the same pattern incrementally.

## Open Tensions
- gen_class.ss is now ~665 lines (exceeds V5 ≤500 preference). A future split may be needed.
- codegen.ss still has ~20 globals. Further grouping possible for function registry and IR output state.

## Notes
Net change: codegen.ss -15 lines, gen_class.ss +30 lines. All 56 tests pass, bootstrap 3-stage fixed-point verified. No behavioral change — pure P3 refactoring.
