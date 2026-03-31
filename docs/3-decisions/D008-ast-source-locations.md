# D008: AST Source Location Tracking (I004 Phase 1)

## Status
firm

## Resolves
I004 Phase 1 — AST nodes have no source location; checker errors report no line numbers.

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P8 (catch errors at compile time, with useful messages)
- D007 (checker integrated into compile pipeline — errors now hit users on every build)

## Decision
Three-layer location tracking: (1) Lexer saves token start column in new `tkCols` Map alongside existing `tkLines`. (2) Parser adds `nLine`/`nCol` Maps; `newNode()` auto-captures current token's line/col. Key constructs (FUNC_DECL, CLASS_DECL, VAR_DECL, ASSIGN, CALL, IDENT, POSTFIX) override with explicit start position saved before parsing sub-parts. (3) Checker imports `nGetLine` and adds `at line N` to all 9 error sites.

## Key Reasoning (3 sentences max)
Auto-capture in `newNode()` gives correct lines for most nodes (IDENT, literals, operators) since they're created at or near the token. Constructs parsed "outside-in" (FUNC_DECL, CLASS_DECL, etc.) need explicit overrides because `newNode()` is called after sub-parts are parsed. This dual approach minimizes parser changes while giving accurate lines for all checker-reported errors.

## Rejected Alternatives
- ✗ **No auto-capture, explicit everywhere**: Requires modifying 30+ parsing functions. Too many mechanical changes for Phase 1.
- ✗ **Token position in AST (store tPos, resolve later)**: Would couple checker to lexer token Maps. AST should be self-contained.
- ✗ **Line-only, no column**: Column tracking costs 1 Map + 1 variable. No reason to skip it — needed for Phase 2 underline display.

## Interfaces With Other Decisions
- D007 (checker in pipeline): Checker errors are now user-facing on every `ss build`. Line numbers make them actionable.
- I004 Phase 2 (source context display): `nGetLine`/`nGetCol` provide the info needed to show source snippets with underlines.
- I004 Phase 3 (error collection): Node locations enable deferred error reporting without losing position info.

## Open Tensions
None currently.

## Notes
Changes: lexer.ss (+14 lines), parser.ss (+30 lines), checker.ss (+5 net). 9 checker error sites updated. Manual verification: undefined variable (line 3), const reassignment (line 3), wrong arg count (line 5), missing return (line 1) — all correct. Bootstrap 3-stage fixed-point verified. Completed 2026-03-30.
