---
id: I004
title: Error reporting — no column, no source context, single-error exit
severity: medium
related-decisions: [D008, D009, D010, D011]
related-principles: [P9]
origin: design-improvements.md DI-6
---
## Description
Current error format:
```
parse error at line 42: expected ")"
```
Then immediately `exit(1)` — first error kills compilation.

Missing:
- No column number
- No source code context (doesn't show the offending line)
- Single-error exit — cannot collect multiple errors
- No "did you mean ...?" suggestions
- No error codes (users can't search for help)

## Impact
- Users fix one error at a time in a compile→fix→recompile loop
- Complex errors without source context are hard to understand
- No error codes means no searchable documentation
- Poor developer experience compared to modern compilers

## Best Practices
- **Rust**: Colored errors + source snippets + `^^^` underlines + fix suggestions
- **Elm**: Friendly full-paragraph error descriptions
- **Go**: Concise but precise `file:line:col: error` format

## Proposed Solution (phased)

### Phase 1: AST nodes record line/col ✅ (D008)
Implemented. Lexer stores token start column in `tkCols` Map. Parser stores line/col per AST node via `nLine`/`nCol` Maps — auto-captured in `newNode()`, with explicit overrides in key parsing functions (FUNC_DECL, CLASS_DECL, VAR_DECL, ASSIGN, CALL, IDENT, POSTFIX). Checker errors now include `at line N` in all 9 error sites.

### Phase 2: Unified error reporting function ✅ (D009)
Implemented. `checkerError(msg, line, col)` in checker.ss displays Rust-style error output: error message, `-->` location, source line with `^` caret underline. Three-layer infrastructure: lexer `getSourceLine(rawLine)` extracts source text, parser `getLineOffset()` exposes prelude offset, checker `checkerError()` formats and displays. All 9 checker error sites migrated. Graceful fallback when line/col unavailable.

### Phase 3: Error collection mode ✅ (D010)
Implemented. `checkerError()` no longer calls `exit(1)` — prints each error as found (streaming output, preserving D009 Rust-style format), increments global `errorCount`. Errors beyond 20 are silently skipped (cascade prevention, following Go's practice). After `check()` Pass 2 completes, summary line printed and `exit(1)` called if any errors found. AST-walking checker needs no recovery logic — tree walk continues naturally after recording an error.

### Phase 4: "Did you mean?" suggestions ✅ (D011)
Implemented. Levenshtein edit distance with scope-aware candidate collection. `editDistance(a, b)` uses Map-based matrix, `collectVisibleNames()` walks scope chain + function name list, `findSuggestion(name)` selects closest match within threshold `max(a.len, b.len) / 3` (min 1, following Rust). `checkerError` gains optional `suggestion` param, prints `= help: did you mean '...'?`. All 4 undefined-name error sites (IDENT, CALL, ASSIGN, POSTFIX) pass suggestions.

## Context
Files: lexer.ss (token columns, getSourceLine), parser.ss (AST line/col, parse errors, getLineOffset), checker.ss (checkerError + semantic errors with source context + error collection + suggestions), gen_exprs.ss/gen_stmts.ss (codegen errors). Phase 1 (D008) established location tracking. Phase 2 (D009) added source context display for checker errors. Phase 3 (D010) enabled multi-error collection. Phase 4 (D011) added "did you mean?" suggestions.
