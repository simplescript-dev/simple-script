---
id: I006
title: gen_runtime.ss 2000+ lines of raw LLVM IR strings
severity: medium
related-decisions: [D016]
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
Introduce IR builder helper functions that wrap `emitIR()` with structured parameters.

### Phase 1: Core helpers + proof of concept ✅ (D016)
15 helper functions added to codegen.ss: `irLabel`, `irAlloca`, `irLoad`, `irStore`, `irGEP`, `irICmp`, `irBr`, `irBrCond`, `irRet`, `irRetVoid`, `irAdd`, `irSub`, `irMul`, `irCall`, `irCallVoid`. Applied to `emitRuntimeProcess` and `emitRuntimeMath` (~52 emitIR calls converted). Convention: `dst` param auto-prefixed with `%`; value params are raw IR strings.

### Phase 2: Extend to remaining sections (in progress)
Phase 2a complete: emitRuntimeConversions, emitRuntimeFS converted (~130 emitIR calls → helpers). 5 new helpers added: irSext, irZext, irSelect, irSDiv, irOr. Also fixed 1 leftover sext in emitRuntimeProcess.

Phase 2b (continued): emitRuntimeHelpers, emitRuntimeIO converted (~121 emitIR calls → helpers). 1 new helper added: irTrunc. Then emitRuntimeExceptions, emitRuntimeStringOps converted (~167 emitIR calls → helpers). 1 new helper added: irPtrToInt. Then emitRuntimeArrayOps converted (~256 emitIR calls → helpers). 1 new helper added: irIntToPtr. Then emitRuntimeRC converted (~189 emitIR calls → helpers, 10 runtime functions: ss_rc_alloc, ss_rc_calloc, ss_rc_realloc, ss_rc_strdup, ss_rc_retain, ss_rc_release, ss_rc_release_no_children, ss_rc_destroy_map, ss_rc_destroy_array_ptrs, ss_rc_atexit_cleanup). No new helpers needed. 2 raw emitIR retained: multi-index GEP (dtor vtable lookup) and indirect call (dtor dispatch). Then emitRuntimeNet converted (~60 emitIR calls → helpers, 6 functions: ss_tcpListen, ss_tcpAccept, ss_tcpRead, ss_tcpWrite, ss_tcpWriteBytes, ss_tcpClose). Then emitRuntimeSQLite converted (~129 emitIR calls → helpers, 4 functions: ss_sqlite3_open, ss_sqlite3_close, ss_sqlite3_exec, ss_sqlite3_query). Then emitRuntimeMap converted (~222 emitIR calls → helpers, 10 functions: hash_str, find_entry, ss_mapNew, ss_mapSet, ss_mapGet, ss_mapGetString, ss_mapHas, ss_mapSize, ss_mapDelete, ss_mapKeys). 1 raw emitIR retained: urem instruction in hash_str (no helper exists, 1 occurrence — P13).

**Phase 2b complete.** Current state: 1337 helper calls, 401 raw emitIR calls remaining. Only unconverted section: emitRuntimeGlobals (module-level declarations — globals/constants, not function body instructions, cannot benefit from current helpers). Remaining raw emitIR are structural (define/closing braces/blank lines), IR comments, and special instructions without helpers (urem, multi-index GEP, indirect call, unreachable, fcmp/sitofp/fdiv, variadic snprintf, puts with discarded return).

### Scope limitation
Helpers are designed for gen_runtime.ss (hardcoded register names). gen_stmts.ss/gen_exprs.ss use `nextReg()` returning `"%N"` — incompatible convention. Unifying would require changing `nextReg()` return format.

## Context
Files: gen_runtime.ss (2019 lines), codegen.ss (helpers, ~414 lines). 23 helpers total. Phase 2b complete: all convertible sections done (10 of 11 sections; emitRuntimeGlobals is declarations-only). Also benefits gen_stmts.ss, gen_exprs.ss, gen_class.ss which have similar hand-written IR patterns, but requires convention unification first.
