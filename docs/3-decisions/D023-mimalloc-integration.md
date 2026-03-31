# D023: mimalloc Integration

## Status
firm

## Resolves
Class instance allocation needs a LIFO free-list allocator for Perceus REUSE optimization. musl libc's malloc doesn't guarantee LIFO behavior.

## Depends On
- axioms.md → C2 (third-party C allocators allowed for low-level infrastructure)
- axioms.md → V4 (low-level infra may use C libraries)
- D020 (runtime redesign — ss_alloc/ss_dealloc backed by mimalloc)

## Decision
Integrate mimalloc v2.2.2 as the class instance allocator:

- **Vendored source**: `vendor/mimalloc/` (src/ + include/ + LICENSE)
- **Compilation**: `musl-gcc -c -O2 -DMI_OVERRIDE=0 -DMI_LIBC_MUSL=1 -I vendor/mimalloc/include -o vendor/mimalloc.o vendor/mimalloc/src/static.c`
- **Linking**: `vendor/mimalloc.o` added to musl-gcc link step (same pattern as sqlite3.o)
- **Runtime functions**: `ss_alloc` → `mi_calloc(1, size)`, `ss_dealloc` → `mi_free(ptr)`
- **Coexistence**: MI_OVERRIDE=0 prevents symbol conflicts with musl's malloc. Old RC system (strings/arrays/maps) continues using libc calloc/free. Two allocator pools coexist safely.

**Key flags:**
- `-DMI_OVERRIDE=0`: Do NOT replace musl's malloc/free. Only expose `mi_*` prefixed functions.
- `-DMI_LIBC_MUSL=1`: Enable musl-compatible TLS strategy.

**Binary size impact:** +58KB (within expected 50-100KB range).

## Key Reasoning (3 sentences max)
mimalloc's LIFO free-list behavior is essential for Perceus REUSE optimization — when an object is freed and a same-size object is immediately allocated, mimalloc returns the same memory address, enabling the compiler to skip dealloc+alloc entirely. MI_OVERRIDE=0 avoids all symbol conflicts with musl's malloc, allowing clean coexistence of two allocation pools (libc for strings/arrays/maps, mimalloc for class instances). v2.2.2 is the latest stable release with confirmed musl compatibility on x86_64.

## Rejected Alternatives
- MI_OVERRIDE=1 (replace musl malloc): Symbol conflicts with musl's non-weak malloc definitions. Multiple definition errors at link time.
- Use libc malloc for everything: No LIFO guarantee. Perceus REUSE optimization ineffective.
- Custom allocator in pure SS: Violates V3 (best practices) — mimalloc is battle-tested infrastructure.

## Interfaces With Other Decisions
- D018 (object layout): ss_alloc allocates objects with rc at offset 0, TypeInfo at offset 1.
- D019 (Perceus IR): REUSE instruction (Phase 3) depends on LIFO free-list behavior.
- D020 (runtime redesign): ss_alloc/ss_dealloc are the user-facing wrappers around mi_calloc/mi_free.

## Open Tensions
- Two allocator pools (libc + mimalloc) increase memory fragmentation slightly. Acceptable for typical programs.
- If mimalloc proves problematic on non-x86_64 targets, need a fallback build flag to use libc calloc/free.

## Notes
build.sh auto-compiles vendor/mimalloc.o if not present. Decision confirmed 2026-03-31.

**Bugs exposed by integration:**
1. `pirStmtHasClassOp` missed CALL/METHOD_CALL returning class types — fixed to use inferType.
2. `genReturn` used `ss_rc_retain` (old RC) for class instance return values — old RC's magic check silently fails on mi_calloc'd memory. Fixed to use `emitRetainForType` which dispatches correctly by type.
