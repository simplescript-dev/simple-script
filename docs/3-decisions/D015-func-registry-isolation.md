# D015: Isolate Function Registry State into gen_registry.ss

## Status
firm

## Resolves
I001 — Global mutable state explosion (short-term: function registry grouping)

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P3 (behavior-preserving refactoring)
- D004 (RC centralization — established the pattern)
- D014 (class state isolation — same pattern, prior step)

## Decision
Move 9 function/method registry global variables from codegen.ss to gen_registry.ss, co-located with their init and lookup functions. Introduce `initFuncRegistry()` as the unified init function. Extract `trackOverload(name)` to eliminate duplicated overload registration logic in codegen.ss and gen_class.ss. Initialize `overloadCount` directly as Map in `initFuncRegistry()` instead of lazy initialization scattered across files.

**Moved globals**: `funcRetTypes`, `funcRetReady`, `funcDefaults`, `funcParamCount`, `methodRetTypes`, `overloadCount`, `overloadReady`, `builtinMap`, `builtinMapReady`.

**Moved functions**: `initFuncRetTypes()`, `initBuiltinMap()`, `runtimeName()`.

**New functions**: `initFuncRegistry()` (unified init), `trackOverload(name)` (deduplicated from codegen.ss + gen_class.ss).

## Key Reasoning (3 sentences max)
Follows the D004/D014 pattern (state group → dedicated file with init function). Function registry is the second-largest cohesive group (9 globals) and its init function `initFuncRetTypes()` was the largest function in codegen.ss (~100 lines). Extracting `trackOverload()` eliminates duplicated 7-line blocks in codegen.ss and gen_class.ss that directly manipulated registry state.

## Rejected Alternatives
- **Keep in codegen.ss, only reorganize sections**: codegen.ss was near V5 limit (485 lines) and the registry init dominated the file. Extracting reduces codegen.ss to 320 lines.
- **Move to gen_exprs.ss (second-largest consumer)**: gen_exprs.ss is already 1495 lines (3x V5 threshold). Adding more code there would worsen the violation.
- **Create accessor functions for all registry reads**: SS has no module visibility control. Adding getters/setters for every `funcRetTypes.has()` call (94 references across 5 files) would add boilerplate without enforcement. `trackOverload()` was extracted because it had duplicated *logic*, not just reads.

## Interfaces With Other Decisions
- D004 (RC centralization): Same pattern — dedicated file + init function for state group.
- D014 (class state isolation): Same pattern, immediately prior step in I001 progression.
- I001: This resolves the function registry subset. Remaining groups: IR output state (irBuf, strConsts, strCount, irOutFile, strOutFile), SSA counters (regCount, labelCount, varCounter), variable tracking (varTypes, varAliases, globalAliases), control flow (breakLabel, continueLabel, currentFunc, terminated), and misc (enumValues, annotatedRoutes).

## Open Tensions
- codegen.ss still has ~15 globals. Further grouping possible but diminishing returns — file is now 320 lines, well under V5 threshold.
- `runtimeName()` has a redundant branch structure (both paths check builtinMap identically). Pre-existing logic, not introduced by this change.
- `builtinMapReady` is intentionally not reset in `initFuncRegistry()` since builtinMap is static data — asymmetric but correct.

## Notes
Net change: codegen.ss -165 lines, gen_class.ss -7 lines, gen_registry.ss +182 lines (new). All 56 tests pass, bootstrap 3-stage fixed-point verified. No behavioral change — pure P3 refactoring.
