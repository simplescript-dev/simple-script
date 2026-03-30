---
id: I008
title: Parser has no operator precedence table — hardcoded in recursion nesting
severity: low
related-decisions: []
related-principles: []
origin: design-improvements.md DI-9
---
## Description
Operator precedence is hardcoded in recursive descent function nesting:
```
parseTernary → parseNullCoalesce → parseOr → parseAnd → parseBitOr →
parseBitXor → parseBitAnd → parseEquality → parseComparison →
parseShift → parseAdditive → parseMultiplicative → parseUnary → parsePostfix
```

Adding a new precedence level requires inserting a new function in the chain and updating the caller. A previous bug (design-issues #10) had left/right operands parsed at different precedence levels.

## Impact
- Adding new operators requires careful function chain surgery
- Precedence bugs are easy to introduce and hard to spot
- 14 functions just for precedence layering

## Proposed Solution
Introduce Pratt parser or precedence table. But current approach works correctly (bug #10 was fixed). Low priority — recursive descent with explicit layers is standard practice.

## Context
Files: parser.ss (~1277 lines). Go and many production parsers also use recursive descent without precedence tables.
