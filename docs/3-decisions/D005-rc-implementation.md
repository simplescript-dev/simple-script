# D005: Reference Counting Memory Management

## Status
firm

## Resolves
design-issues.md #6 — No memory release mechanism (every malloc leaked).

## Depends On
- axioms.md → C4 (no GC)
- axioms.md → C5 (no user-facing memory syntax)
- axioms.md → C6 (class fields immutable)
- axioms.md → V2 (transparent memory management)

## Decision
Compile-time inserted reference counting (ARC), inspired by Swift ARC + Lobster compile-time ownership. 9 phases:

- **Phase 0-1**: RC runtime (ss_rc_alloc/retain/release), negative-offset header [rc:i64][tag:i32][magic:i32]
- **Phase 2**: Function exit releases local ptr vars (localPtrVars tracking)
- **Phase 3**: Expression temporaries released (template literals, concat chains)
- **Phase 4**: Assignment releases old value before storing new
- **Phase 5**: genExprAsString conversion temps (lastExprStringOwned flag)
- **Phase 6**: Container destructors (Map: release keys/values, Array<ptr>: release elements, Class: dtor table)
- **Phase 7**: Map val_type flag, class field destructors via global dtor table
- **Phase 8**: Block scope RC (blockPtrVarStack, pushBlockScope/popBlockScope)
- **Phase 9**: Compile-time cyclic ownership detection + ownership transfer fixes (D006)

### Phase 9 Design: Compile-time Cyclic Ownership Detection

**Constraints leveraged:**
- C6 (immutable fields) → direct field cycles (A↔B) create chicken-and-egg deadlock, cannot instantiate
- Therefore, cycles can ONLY form through container mutation (array.push, map.set)
- The problem reduces to: detect class types whose container fields can reach back to themselves

**Algorithm** (gen_rc.ss `detectCyclicOwnership()`):
1. After all classes registered and inheritance resolved, iterate all user classes
2. For each container field (Array<X>, Map<K,X>), extract element type X
3. If X is a user class, BFS through X's type graph via `canReachClass(X, thisClass)`
4. If reachable → mark field as non-owning in `nonOwningFields` Map

**Non-owning container behavior:**

| Operation | Normal container | Non-owning container |
|-----------|-----------------|---------------------|
| push(value) | retain value | skip retain |
| destroy | release each element | `ss_rc_release_no_children` (free container, skip elements) |
| Semantics | container owns elements | container borrows elements |

**Integration points:**
- gen_exprs.ss:884-889 — detects push to non-owning field, sets `pushNonOwning` flag
- gen_exprs.ss:682 — conditional retain: skip when `pushNonOwning == 1`
- gen_class.ss:367 — conditional release: `ss_rc_release_no_children` for non-owning fields

**atexit cleanup (Layer 3):** Stub registered via `@atexit(@ss_rc_atexit_cleanup)` in main(). Currently empty. Available as future safety net for residual leaked objects, but not strictly needed — compile-time analysis covers all container-mediated cycles, and C6 prevents direct field cycles.

## Key Reasoning
RC provides deterministic deallocation without GC pauses. Magic guard (0x534F5353) allows safe retain/release on non-RC pointers (string constants). Tag-based destructor dispatch enables container-specific cleanup. Compile-time cycle detection avoids runtime overhead — zero cost when no cycles exist, and when cycles are detected, the non-owning semantics match the logical ownership pattern (e.g., a tree doesn't "own" its parent; an EventBus doesn't "own" its listeners).

## Rejected Alternatives
- ✗ **`weak` keyword (Swift-style)**: Violates C5 — adds user-facing memory syntax. Users must understand strong vs weak references.
- ✗ **Runtime cycle collector (trial-deletion)**: Violates C4 — introduces GC-like runtime pauses.
- ✗ **Tracing GC**: Violates C4 — stop-the-world pauses unacceptable.
- ✗ **Arena/region-based allocation**: Poor fit for long-lived objects and complex ownership graphs.

## Interfaces With Other Decisions
- D004 (RC centralization): RC helpers centralized in gen_rc.ss — cycle detection functions live here
- D006 (ownership transfer): Bug fixes prerequisite for Phase 9 — push retain must exist before non-owning conditional can skip it

## Known Limitations
- **L1: Non-owning dangling references.** If an element's last owning reference is released while the element is still in a non-owning container, the container holds a dangling pointer. Acceptable for typical patterns (observer unregisters before destruction; tree children outlive parent references). C6 (immutable fields) significantly limits the danger surface. Matches Lobster's accepted trade-off.
- **L2: No interface/trait-based cycle detection.** `canReachClass()` traverses concrete class types in containers. If a future interface system adds polymorphic containers (e.g., `Array<Listener>` where multiple classes implement `Listener`), the cycle detection would need to check all implementing classes. Currently not an issue — SS has no interfaces.

## Notes
All 9 phases passed 3-stage bootstrap fixed-point. Phase 9 implementation: gen_rc.ss (268 LOC, 12 functions + 7 global vars).
