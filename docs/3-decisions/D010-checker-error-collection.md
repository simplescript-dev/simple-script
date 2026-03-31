# D010: Checker Error Collection Mode (I004 Phase 3)

## Status
firm

## Resolves
I004 Phase 3 — Checker exits on first error; users cannot see multiple errors in one compilation.

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P8 (study before designing — Go/Rust error collection as reference)
- principles.md → P9 (complexity in compiler, not user code — fewer compile cycles = better UX)
- D009 (checker error display — `checkerError` function provides formatting infrastructure)

## Decision
Streaming error collection: `checkerError()` prints each error as found (preserving D009 Rust-style format) but no longer calls `exit(1)`. A global `errorCount` tracks total errors. Errors beyond 20 are silently skipped to prevent cascade flooding. After `check()` Pass 2 completes, if `errorCount > 0`, a summary line is printed and `exit(1)` is called. The "expected PROGRAM node" check remains fatal (immediate exit) since the checker cannot continue without a valid root node.

## Key Reasoning (3 sentences max)
Go and Rust compilers both collect errors during semantic analysis and report them at the end — this is the industry standard approach. Since the SS checker walks a complete AST (not a token stream), error recovery is trivial: after recording an error, simply continue the tree walk. Streaming output (print-as-found) avoids buffering complexity while producing identical output to Rust's error display.

## Rejected Alternatives
- **Buffer all errors in string, print at end**: Requires building multi-line strings with `\n` handling. Streaming output (println as found) is simpler and produces the same result — Go and Rust both stream errors.
- **Error poisoning (mark undefined vars to suppress cascading)**: Useful but adds complexity. Phase 3 scope is collection, not deduplication. Can be added as a follow-up optimization.
- **No error limit**: Risk of 100+ cascading errors from a single root cause (e.g., missing import). 20-error cap follows Go's practice (Go caps at 10 per file).
- **Return error list from check()**: Callers currently ignore check()'s return value and rely on exit-on-error. Changing the API is unnecessary — check() still exits on errors, just after printing all of them.

## Interfaces With Other Decisions
- D009 (error display): `checkerError` format unchanged — still produces Rust-style source context with caret. Only the exit behavior changed.
- I004 Phase 4 (suggestions): Error collection enables showing "did you mean?" suggestions per error without the first error killing the process.
- I003 Phase 3 (type checking): When type checking is added, errors will naturally collect alongside existing checks.

## Open Tensions
- Undefined variable used N times produces N errors. Error poisoning (track reported-undefined names, skip re-reports) would reduce noise but is deferred to keep Phase 3 minimal.

## Notes
Output format (multiple errors):
```
error: function 'add' with return type 'int' does not return on all paths
 --> line 1:1
  |
1 | function add(a: int, b: int): int {
  | ^

error: cannot reassign const variable 'x'
 --> line 9:5
  |
9 |     x = 20
  |     ^

error: function 'add' expects 2 arguments, got 3
  --> line 10:5
   |
10 |     add(1, 2, 3)
   |     ^

aborting due to 3 errors
```
Changes: checker.ss (+12 net lines: 1 global, `checkerError` refactored, `check()` summary block). All 56 tests pass, bootstrap 3-stage fixed-point verified. Completed 2026-03-30.
