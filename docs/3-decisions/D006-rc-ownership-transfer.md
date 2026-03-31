# D006: RC Ownership Transfer Fixes

## Status
firm

## Resolves
I007 Layer 1 — pre-existing RC bugs (array.push retain, constructor retain).

## Depends On
- axioms.md → C1 (bootstrap guard)
- axioms.md → C5 (no user-facing memory syntax)
- axioms.md → V2 (transparent memory management)
- D005 Phases 0-8 (RC infrastructure)

## Decision
Two missing `ss_rc_retain` calls are added in codegen, fixing ownership transfer at container insertion and object construction.

### Bug 1: `array.push()` missing retain for ptr elements

**Root cause**: `genArrayMethod("push")` stored the element pointer into the array without incrementing its refcount. The array held a raw copy; when the caller's scope released the original, the array was left with a dangling pointer.

**Fix** (gen_exprs.ss:681-684): Call `ss_rc_retain(ptr)` before storing the element as i64 in the array. The retain is conditional on `pushNonOwning` (Phase 9 non-owning containers skip retain by design).

**Comparison**: `map.set()` (gen_exprs.ss:731-732) already retained unconditionally — this aligns array.push to the same pattern.

### Bug 2: Class constructor missing retain for borrowed ptr params

**Root cause**: `emitClassConstructor()` stored ptr-type parameters directly into class fields without retaining. When the caller's function exit released the parameter, the class field became dangling. Subsequent destruction triggered double-free.

**Fix** (gen_class.ss:289-291): For each field where `ssTypeToLLVM(fieldType) == "ptr"`, call `ss_rc_retain(ptr %field.arg)` before the store instruction.

### Why tests didn't catch it
All existing tests used string constants (`"Alice"`), which carry the magic guard (0x534F5353). The retain/release functions detect non-RC pointers via the magic check and skip operations. Only dynamically created strings (from concatenation, template literals) and class instances are RC-managed. The bugs are only triggered by dynamic strings/objects stored in arrays or passed to constructors.

## Key Reasoning
Both bugs share the same pattern: **ownership transfer without retain**. When a reference is stored in a new location (container element, class field), the storage location becomes a new owner and must increment the refcount. The fix follows the standard ARC rule used by Swift and Nim: every store of a ptr into a persistent location must be paired with a retain.

## Rejected Alternatives
None — these are straightforward correctness fixes with no design alternatives.

## Interfaces With Other Decisions
- D005 Phase 9: Bug 1 fix is prerequisite for non-owning container semantics (the `pushNonOwning` conditional retain only makes sense when retain exists in the first place)
- D004 (RC centralization): Both fixes use the centralized `emitIR` pattern for retain calls

## Open Tensions
None currently.

## Notes
Verification:
1. `bin/ss test tests/` — all existing tests pass
2. `tests/phase4/rc_class_dtor.ss` — exercises ptr field retention in constructors
3. `tests/phase4/rc_destruct.ss` — exercises container element retention
4. `./build.sh bootstrap` — 3-stage fixed-point verified
