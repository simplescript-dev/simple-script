# D020: Runtime Function Redesign

## Status
firm

## Resolves
Runtime function naming and semantics redesign — from tag-based RC dispatch to TypeInfo-based generic dispatch, with new naming convention.

## Depends On
- axioms.md → C2 (no handwritten runtime, allow third-party allocator)
- axioms.md → V4 (core logic in SS, low-level infra allows C libs)
- D018 (object layout — ss_release reads TypeInfo for drop dispatch)

## Decision
**Naming convention:** All runtime functions use `ss_` prefix with shortest verb. No sub-categories (`rc_`, `rt_`).

| Function | Old Name | Signature | Purpose |
|----------|----------|-----------|---------|
| `ss_retain` | `ss_rc_retain` | `void (%RcHeader*)` | rc + 1 |
| `ss_release` | `ss_rc_release` | `void (%RcHeader*)` | rc - 1; if 0, drop via TypeInfo |
| `ss_is_unique` | (new) | `i1 (%RcHeader*)` | return rc == 1 |
| `ss_alloc` | `ss_rc_alloc` | `i8* (i64)` | allocate via mimalloc, rc = 1 |
| `ss_dealloc` | (new) | `void (i8*)` | free via mimalloc |
| `ss_shallow_copy` | (new) | `i8* (i8*, i64)` | byte copy, new rc = 1 |

**Per-class functions (compiler-generated):**
| Function | Purpose |
|----------|---------|
| `ss_drop_ClassName` | rc_dec all ref-type fields, then ss_dealloc |
| `ss_deep_clone_ClassName` | recursive deep clone |
| `ss_shallow_clone_ClassName` | shallow copy + rc_inc ref fields |

**Allocator:** Phase 1 introduces mimalloc:
- `ss_alloc` → `mi_calloc(1, size)`
- `ss_dealloc` → `mi_free(ptr)`
- Integration: compile `mimalloc/src/static.c`, link statically (+50-100KB)
- Required for Perceus REUSE optimization (LIFO free-list guarantee)

**ss_release is generic** — no tag system, no switch statement:
```
ss_release(obj):
    obj.rc -= 1
    if obj.rc == 0:
        drop_fn = obj.type_info.drop
        drop_fn(obj)
```

## Key Reasoning (3 sentences max)
Unified `ss_` prefix is simpler than `ss_rc_` + `ss_rt_` sub-categories — all functions are runtime, no need to sub-categorize. TypeInfo-based drop dispatch replaces the tag system (0=string, 1=array, 2=map, 3=class, etc.) which doesn't scale. mimalloc's LIFO free-list is essential for Perceus REUSE optimization — musl malloc doesn't guarantee this.

## Rejected Alternatives
- Keep `ss_rc_` prefix: Inconsistent with other runtime functions. `ss_` is sufficient namespace isolation.
- Keep tag-based dispatch: Requires maintaining a tag registry and switch statement. Every new class category needs a new tag.
- Use musl malloc: No LIFO guarantee. Perceus REUSE optimization would be ineffective.
- `rc_inc`/`rc_dec`/`rt_alloc` naming: Two different prefixes for the same system. Unnecessary complexity.

## Interfaces With Other Decisions
- D018 (object layout): ss_alloc must initialize both rc=1 and TypeInfo pointer.
- D019 (Perceus IR): Each PIR instruction maps to specific ss_* functions.
- D022 (clone): ss_shallow_copy used by shallowClone; deepClone calls per-class ss_deep_clone_*.

## Open Tensions
- mimalloc conflicts with original C2/V4 axioms (now modified). If mimalloc proves problematic for some targets, need a fallback to libc malloc.
- Per-class drop/clone functions increase binary size linearly with number of classes. Acceptable for typical programs (<100 classes).

## Notes
Old functions deprecated: ss_rc_alloc, ss_rc_retain, ss_rc_release, ss_rc_release_no_children, ss_rc_realloc, ss_rc_strdup, ss_rc_calloc. Decision confirmed 2026-03-31.
