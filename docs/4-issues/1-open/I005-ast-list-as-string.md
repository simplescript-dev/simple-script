---
id: I005
title: AST child node lists as comma-separated strings
severity: medium
related-decisions: [D013]
related-principles: [P11, P3, P13]
origin: design-improvements.md DI-8
---
## Description
`nList` Map stores child node IDs as comma-separated strings: `"12,45,89"`. Traversal requires `split(",")` + parseInt loop.

Two helpers standardize list concatenation:
- ✅ `listAppend(listStr, childId: int)` — for AST node ID lists (parser.ss, 15 sites)
- ✅ `listAppendStr(listStr, item: string)` — for string lists (D013, 17 sites across 7 files)

**Remaining structural issue**: The underlying comma-separated string representation is suboptimal. True resolution requires language-level array/list support, which is deferred.

## Impact
- ~~Error-prone manual concatenation~~ (resolved by D013)
- ~~Code verbosity~~ (resolved by D013)
- Performance overhead from repeated string split/parse on every AST traversal (structural, deferred)

## Proposed Solution
~~Standardize all manual list concatenation sites to use helpers.~~ ✅ Done (D013).

Remaining: Replace comma-separated string representation with proper array type when SS supports it.

## Context
Files: parser.ss (listAppend + listAppendStr definitions), used by gen_class.ss, gen_exprs.ss, codegen.ss, checker.ss, gen_rc.ss, main.ss.
