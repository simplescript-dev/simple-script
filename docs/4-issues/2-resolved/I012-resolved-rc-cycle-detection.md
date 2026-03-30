---
id: I012
title: "Resolved: RC Phase 9 cyclic reference detection + pre-existing RC bugs"
severity: critical
resolved-by: D005 (Phase 9 firm), D006 (ownership transfer fixes)
origin: I007 (design-issues.md #6 Phase 9+, phase9-cycle-detection.md)
---

## Resolution Summary

### Layer 1: Pre-existing Bug Fixes (D006)

**Bug 1: array.push() retain** ✅
- gen_exprs.ss:681-684 — `ss_rc_retain()` called for ptr elements on push
- Conditional on `pushNonOwning` flag (Phase 9 non-owning containers skip)

**Bug 2: Constructor ptr retain** ✅
- gen_class.ss:289-291 — `ss_rc_retain()` called for ptr-type parameters before storing in class fields
- Prevents dangling pointer + double-free on destruction

**Why tests didn't catch it**: All tests used string constants (magic guard protects non-RC pointers). Only dynamic strings/objects trigger the bug.

### Layer 2: Compile-time Cyclic Ownership Detection (D005 Phase 9)

**Implementation**: gen_rc.ss — 4 functions (268 LOC total file)
- `detectCyclicOwnership()` — scans all classes for container fields that create type graph cycles
- `canReachClass()` — BFS through class field type graph
- `extractContainerElemType()` — parses `Array<X>`, `Map<K,X>` annotations
- `findFieldOwner()` — walks inheritance chain for field type lookup

**Key insight**: C6 (immutable fields) reduces the problem to container-only cycles. Direct field cycles are impossible (chicken-and-egg deadlock at construction).

**Non-owning semantics**: Cycle-path container fields skip retain on push, use `ss_rc_release_no_children` on destroy.

### Layer 3: atexit Cleanup

Stub registered (`@ss_rc_atexit_cleanup`). Currently empty — not strictly needed because compile-time analysis covers all container-mediated cycles. Available as future safety net.

### Known Limitations (accepted)
- L1: Non-owning containers may hold dangling pointers if element freed while still referenced. Acceptable for typical patterns (C6 limits danger surface). Matches Lobster's approach.
- L2: No interface-based cycle detection (SS has no interfaces yet).

## Verification
- `bin/ss test tests/` — all pass
- `tests/phase4/rc_cycle.ss` — self-referential Node/Parent classes
- `tests/phase4/rc_class_dtor.ss` — ptr field constructor/destructor
- `./build.sh bootstrap` — 3-stage fixed-point verified
