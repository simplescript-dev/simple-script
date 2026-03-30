---
id: I010
title: "Resolved P1 bugs — high risk (silent wrong code)"
severity: high
resolved-by: direct fixes + D005 (RC phases 0-8)
origin: design-issues.md #6-12
---

### #6: Memory leaks — no release mechanism 🔧 Phase 0-8 complete
- Every malloc leaked. No GC, no RC.
- Fixed in 8 phases (D005): RC runtime, local var release, expression temps, assignment old-value release, container destructors, class field destructors, block scope RC. Phase 9 (cycle detection) still open → I007.

### #7: Inheritance had no vtable — polymorphism was fake ✅
- Methods statically bound. `let a: Animal = new Dog(...)` always called `Animal_speak`.
- Fixed: vtable for inheritance hierarchies only. `classNeedsVtable`/`classVtableSlots`/`classVtableImpl` globals. Struct first field = vtable ptr. `emitClassMethodCall` uses indirect dispatch for vtable classes. Bootstrap unaffected (no inheritance in compiler).

### #8: `getFieldIndex` returned object register on missing field ✅
- Field not found → returned -1 → `emitFieldLoad` returned object pointer as field value. No error.
- Fixed: exit(1) on missing field.

### #9: Parent class registration order dependency ✅
- Child class registered before parent → parent fields silently skipped → wrong GEP offsets.
- Extra fix: `Map.keys()` returns `\n`-separated, but code used `split(",")` → inheritance completely broken.
- Fixed: `split("\n")`, two-pass registration.

### #10: Parser operator precedence asymmetry ✅
- `parseAdditive` left called `parseShift`, right called `parseMultiplicative`. Left/right at different precedence.
- Fixed: both sides call `parseShift` (next lower level).

### #11: `addStringConst` bytes vs chars ❌ False positive
- `length()` already calls `strlen` which returns byte count. No fix needed.

### #12: Struct size always `fieldCount * 8` ✅
- All fields allocated 8 bytes regardless of LLVM type. i32 fields wasted 2x memory.
- Fixed: calculated from struct type declaration.
