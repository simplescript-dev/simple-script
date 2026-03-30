---
id: I006
title: gen_runtime.ss 2000+ lines of raw LLVM IR strings
severity: medium
related-decisions: []
related-principles: [P5, P11]
origin: design-improvements.md DI-10
---
## Description
gen_runtime.ss contains 2000+ lines of hand-written LLVM IR as string literals via `emitIR()`. No abstraction layer — every alloca, load, store, GEP, icmp, br is a raw string. Example:

```ss
emitIR("  %ptr = getelementptr i8, ptr %base, i64 16")
emitIR("  %val = load i64, ptr %ptr, align 8")
emitIR("  %cmp = icmp eq i64 %val, 0")
emitIR("  br i1 %cmp, label %then, label %else")
```

One character error (wrong register name, missing %, wrong type) produces invalid IR with no compile-time feedback — only discovered when `llc` fails.

## Impact
- Adding/modifying runtime functions is slow and error-prone
- Common patterns (load-from-offset, null-check-branch, loop-with-counter) reimplemented from scratch each time
- Difficult to audit for correctness — must mentally parse IR strings
- Modifying one runtime function requires reading tens of emitIR lines

## Proposed Solution
Introduce IR builder helper functions:
- `emitAlloca(name, type)` → `%name = alloca type, align 8`
- `emitLoad(dst, type, ptr)` → `%dst = load type, ptr %ptr, align 8`
- `emitStore(type, val, ptr)` → `store type val, ptr %ptr, align 8`
- `emitGEP(dst, baseType, base, offset)` → `%dst = getelementptr ...`
- `emitICmp(dst, op, type, a, b)` → `%dst = icmp op type a, b`
- `emitBr(cond, thenLabel, elseLabel)` → `br i1 %cond, ...`

These wrap the string formatting and validate basic structure. Lower priority than other issues — gen_runtime.ss works, it's just painful to maintain.

## Context
Files: gen_runtime.ss (2019 lines). Also benefits gen_stmts.ss, gen_exprs.ss, gen_class.ss which have similar hand-written IR patterns.
