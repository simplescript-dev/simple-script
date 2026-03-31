# D009: Checker Error Source Context Display (I004 Phase 2)

## Status
firm

## Resolves
I004 Phase 2 — Checker errors show no source context; users cannot see the offending code line.

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P8 (study before designing — Rust compiler error format as reference)
- principles.md → P9 (complexity in compiler, not user code — better errors = better UX)
- D008 (AST source locations — provides line/col for all checker-reported nodes)

## Decision
Three-layer error display infrastructure: (1) Lexer exports `getSourceLine(rawLine)` which scans the `src` global to extract a specific line by 1-based line number. (2) Parser exports `getLineOffset()` to expose the prelude line offset, enabling adjusted→raw line conversion. (3) Checker implements `checkerError(msg, line, col)` which formats Rust-style error output with source line and `^` caret underline. All 9 checker error sites migrated to use `checkerError`. Graceful fallback: line <= 0 prints message only; empty source line prints `at line N` only.

## Key Reasoning (3 sentences max)
Rust's error format (message + location + source snippet + caret) is the industry standard for compiler error UX. The `src` global in lexer persists through the full compile pipeline, so no extra storage needed. Keeping `checkerError` in checker.ss avoids circular imports while cleanly centralizing all checker error formatting.

## Rejected Alternatives
- ✗ **Pre-split source lines into Map at tokenize time**: Wastes memory for the common case (no errors). Since we exit on first error, on-demand line extraction is sufficient.
- ✗ **Shared error module imported by parser + checker**: Creates new file for a function only checker uses today. Parser/lexer migration is Phase 3 scope — extract then, not now (P13).
- ✗ **Go-style `file:line:col: message` (no source snippet)**: Misses the primary UX improvement. The source line + caret is what makes errors actionable without opening the file.

## Interfaces With Other Decisions
- D008 (AST locations): `nGetLine`/`nGetCol` provide the location data that `checkerError` displays. Without D008, this decision has no input.
- I004 Phase 3 (error collection): `checkerError` currently calls `exit(1)`. Phase 3 must refactor it to collect errors instead of exiting. The format function can be extracted from the exit logic.
- I004 Phase 4 (suggestions): The `checkerError` output format has a natural extension point — add a "help:" line below the caret, like Rust's `help: did you mean ...?`.

## Open Tensions
None currently.

## Notes
Output format:
```
error: undefined variable 'x'
 --> line 3:9
  |
3 | let y = x + 1
  |         ^
```
Changes: lexer.ss (+15 lines), parser.ss (+4 lines), checker.ss (+28 net, 9 error sites migrated). Manual verification: undefined variable, const reassignment, arg count mismatch, missing return path — all display correct source context with accurate caret position. Bootstrap 3-stage fixed-point verified. Completed 2026-03-30.
