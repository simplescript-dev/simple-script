---
id: I004
title: Error reporting — no column, no source context, single-error exit
severity: medium
related-decisions: []
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

### Phase 1: AST nodes record line/col
Parser stores line/col when creating each AST node. Requires adding `nLine`/`nCol` Maps or extending existing node storage. Minimal codegen impact — information just stored, not yet used.

### Phase 2: Unified error reporting function
`reportError(msg, line, col)` — displays source line with `^^^` underline pointing to error location. All error sites migrated to use this function.

### Phase 3: Error collection mode
Don't `exit(1)` on first error. Collect errors in a list. Report all at end. Requires careful recovery logic in parser and checker (skip to next statement on error).

### Phase 4: "Did you mean?" suggestions
Compute edit distance between undefined identifier and known symbols. Suggest closest match. Useful for typos in function/variable names.

## Context
Files: parser.ss (parse errors), checker.ss (semantic errors), gen_exprs.ss/gen_stmts.ss (codegen errors).
