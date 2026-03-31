# D013: Standardize List Concatenation with listAppendStr (I005)

## Status
firm

## Resolves
I005 — AST child node lists as comma-separated strings. Specifically, standardizes all manual string-list concatenation sites to use helper functions.

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P3 (behavior-preserving refactoring)
- principles.md → P13 (extract only when justified — 17 sites justify the abstraction)

## Decision
Introduce `listAppendStr(listStr: string, item: string): string` alongside existing `listAppend(listStr: string, childId: int): string`. Convert all manual `if (x == "") { x = item } else { x = x + "," + item }` patterns to use these helpers.

**Two helpers, two types**: `listAppend` handles int items (AST node IDs for `nList`), `listAppendStr` handles string items (field names, method names, import names, path components, etc.). Both live in parser.ss and are accessible from all files via import merging.

**Coverage**: 17 total conversions across 7 files:
- parser.ss: 4 string sites (implList, names×2, typeArgs) — already had 15 int sites using `listAppend`
- gen_class.ss: 3 sites (fieldNames, methodNames, slots)
- gen_exprs.ss: 1 int site (providedArgs → `listAppend`), 1 string site (fullArgs)
- codegen.ss: 1 site (defaults)
- checker.ss: 4 sites (allFuncNameList, names×2, methodNames)
- gen_rc.ss: 1 site (localPtrVars)
- main.ss: 1 site (stack)

## Key Reasoning (3 sentences max)
The `if/else` concatenation pattern was duplicated 17 times across 7 files, making it a justified extraction per P13. Two type-specific helpers (int vs string) are necessary because SS has no generics. Using `+` concatenation in both helpers maintains consistent style and avoids template string overhead.

## Rejected Alternatives
- ✗ **Function overloading (`listAppend` for both signatures)**: SS supports overloading via mangled names, but using distinct names (`listAppend` vs `listAppendStr`) is clearer and avoids relying on type inference at call sites.
- ✗ **Single generic helper**: SS has no generics. Two type-specific functions with identical logic is the standard pattern.
- ✗ **Leave string sites unconverted**: Would leave 17 sites with duplicated logic. The pattern was error-prone (inconsistent use of `+` vs template strings, missing empty-string checks).

## Interfaces With Other Decisions
- D001 (god function split): Same principle of extracting repeated patterns into helpers.
- I005: This resolves the standardization aspect. The deeper structural issue (lists as comma-separated strings vs proper array type) remains deferred until SS supports arrays at the language level.

## Open Tensions
- `listAppendStr` lives in parser.ss but is used by codegen, checker, and gen_rc. If SS gains a utility module system, these helpers should move to a shared utils file.
- The underlying representation (comma-separated strings) is still suboptimal. True resolution requires language-level array support.

## Notes
Net change: +5 lines (1 new function), -17 lines (pattern elimination). All 56 tests pass, bootstrap 3-stage fixed-point verified. No behavioral change — pure P3 refactoring.
