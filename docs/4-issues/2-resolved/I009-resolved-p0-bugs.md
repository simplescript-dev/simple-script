---
id: I009
title: "Resolved P0 bugs — fatal (wrong output or crash)"
severity: critical
resolved-by: direct fixes (no architectural decision needed)
origin: design-issues.md #1-5
---

### #1: Checker scope lookup used wrong key ✅
- `defineVar` used `scopeId` (monotonic), `lookupVar` used `scopeDepth` (rewinds). Nested >2 scopes broke lookup.
- Fixed in D003: chain-based scope (`scopeParent` Map), const reassignment detection enabled.

### #2: `ss_i64_to_string` guessed type by numeric magnitude ✅
- `> 1048576` heuristic — large ints treated as pointers (segfault), small addresses treated as ints (garbage).
- Fixed: `inferArrayElemType()` from type annotations, `inferType(INDEX_ACCESS)` returns actual element type, `ss_i64_to_string` always formats as i64. 3-stage bootstrap passed.

### #3: Multiple fixed buffers without bounds checking ✅
- 6 locations (arrayToString, mapKeys, listDir, sqlite3Query, mkdirp, readLine) with 256-65536 byte fixed buffers.
- Fixed: `ss_rt_ensure_cap` helper (check-and-double), all 6 converted to dynamic growth.

### #4: Condition expressions assumed i32 type ✅
- `genIf/genFor/genWhile/genDoWhile` all emitted `icmp ne i32`. Broke on ptr/i64 conditions.
- Fixed: `emitCondToI1()` dispatches by `inferType` result — ptr uses `icmp ne ptr null`, i64 uses `icmp ne i64 0`, double uses `fcmp one`.

### #5: `genOptionalMethodCall` null check via string length ✅
- `?.` checked null by calling `ss_stringLength`. Class instances (non-string ptr) never detected as null.
- Fixed: `icmp eq ptr %obj, null` for true null pointer check.
