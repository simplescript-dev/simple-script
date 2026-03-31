# D011: Checker "Did You Mean?" Suggestions (I004 Phase 4)

## Status
firm

## Resolves
I004 Phase 4 — Checker errors for undefined names show no suggestions; users must guess the correct spelling.

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P8 (study before designing — Rust compiler suggestion mechanism as reference)
- principles.md → P9 (complexity in compiler, not user code — better errors = better UX)
- D009 (checker error display — `checkerError` format provides the `= help:` extension point)
- D010 (error collection — multiple suggestions shown in one compilation)

## Decision
Levenshtein edit distance with scope-aware candidate collection. Three new functions: `editDistance(a, b)` computes distance using a Map-based matrix (avoiding Array dependency), `collectVisibleNames()` walks the scope chain via `scopeVarNames` Map plus `allFuncNameList` to gather all accessible identifiers, and `findSuggestion(name)` selects the closest candidate within threshold `max(name.len, candidate.len) / 3` (minimum 1), following Rust's approach. `checkerError` gains an optional 4th parameter `suggestion: string = ""` and prints `= help: did you mean '...'?` when non-empty. All 4 undefined-name error sites (IDENT, CALL, ASSIGN, POSTFIX_INC/DEC) pass suggestions.

## Key Reasoning (3 sentences max)
Rust's edit-distance approach is the industry standard for compiler suggestion UX — simple, effective, and well-understood. Map-based matrix avoids dependency on Array index assignment semantics in the bootstrap compiler. Scope-aware collection ensures suggestions are always reachable identifiers, not arbitrary strings from other scopes.

## Rejected Alternatives
- ✗ **Array-based Levenshtein matrix**: Requires `Array<int>` index assignment (`arr[i] = val`), which is less battle-tested in the bootstrap compiler than Map. Map adds overhead but only runs on error paths.
- ✗ **Damerau-Levenshtein (transposition-aware)**: More complex to implement, marginal benefit. Rust uses standard Levenshtein. Transpositions in short names (4 chars) correctly stay above threshold.
- ✗ **Global flat name list (no scope awareness)**: Would suggest variables from unrelated scopes (e.g., a local in another function). Scope-chain walk ensures only accessible names appear.
- ✗ **Fuzzy substring matching**: Simpler but produces false positives (e.g., "count" matching "ount"). Edit distance is more precise.

## Interfaces With Other Decisions
- D009 (error display): The `= help:` line is a natural extension of the Rust-style error format. No format changes needed.
- D010 (error collection): Multiple errors each get independent suggestions. No interaction issues.
- I003 Phase 3 (type checking): When type checking adds new error types, they can reuse `findSuggestion` for similar "did you mean?" UX.

## Open Tensions
None currently.

## Notes
New infrastructure: `scopeVarNames` Map tracks variable names per scope ID, `allFuncNameList` accumulates function names (deduped via `funcNames.has()` check). Both initialized in `initChecker()`.

Output format:
```
error: undefined variable 'mesage'
 --> line 3:13
  |
3 |     println(mesage)
  |             ^
  = help: did you mean 'message'?
```

Threshold examples (Rust's `max(a.len, b.len) / 3`, min 1):
- 1-3 char names: max distance 1
- 4-6 char names: max distance 2
- 7-9 char names: max distance 3

Changes: checker.ss (+68 net lines: 2 globals, 3 functions, `checkerError` +1 param +3 lines, 4 error sites updated). All 56 tests pass, bootstrap 3-stage fixed-point verified.
