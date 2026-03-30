---
id: I005
title: AST child node lists as comma-separated strings
severity: medium
related-decisions: []
related-principles: [P11]
origin: design-improvements.md DI-8
---
## Description
`nList` Map stores child node IDs as comma-separated strings: `"12,45,89"`. Traversal requires `split(",")` + parseInt loop. Parser manually concatenates with `+` in 50+ locations.

Example pattern repeated everywhere:
```ss
if (list == "") { list = `${id}` }
else { list = `${list},${id}` }
```

`listAppend()` helper exists but is not used in all locations.

## Impact
- Performance overhead from repeated string split/parse on every AST traversal
- Error-prone manual concatenation (off-by-one, empty-string edge cases)
- Code verbosity — every list manipulation is 3-4 lines instead of 1

## Proposed Solution
Standardize all 50+ manual list concatenation sites to use `listAppend()`. Pure mechanical refactoring — no behavior change. Can be done incrementally per file.

## Context
Files: parser.ss (50+ sites), gen_stmts.ss, gen_exprs.ss, gen_class.ss, checker.ss.
