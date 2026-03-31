# D024: Perceus REUSE Optimization

## Status
Accepted

## Context
PIR Passes 1-3 (Liveness, Move, Uniqueness) implement basic Perceus reference counting: automatic drop insertion, move optimization, and direct-drop for provably unique variables. The next step is the core Perceus innovation: **memory reuse**. When a unique variable is dropped and the next statement allocates a new object of the same type, we reuse the memory (skip mi_free + mi_calloc).

Reference: Reinking et al., "Perceus: Garbage Free Reference Counting with Reuse" (MSR-TR-2020-42).

## Decision
Implement same-type static REUSE as PIR Pass 5:

1. **Detection**: `pirReusePass` scans PIR instructions. When an ALLOC follows a statement whose scheduled drop has a same-type unique variable, record the drop-alloc pair.
2. **Drop-side**: `pirEmitScheduled` calls `ss_drop_fields_ClassName(ptr)` instead of `ss_drop_ClassName(ptr)` — releases ref-type fields but keeps memory.
3. **Alloc-side**: `genNewExpr` calls `ClassName_new_reuse(ptr, args)` — writes rc, TypeInfo, vtable, fields into existing memory.
4. **Communication**: Drop stores the LLVM register in `pirReuseReg[allocVar]`. `genVarDecl` reads it and sets `pirPendingReuseReg`/`pirPendingReuseClass` for `genNewExpr`.

### Constraints
- Same-type only (same struct size guaranteed)
- Static uniqueness only (from Pass 3, no runtime `is_unique` check)
- Consecutive statements only (drop at stmt A, alloc at stmt B where B immediately follows A)

### Per-class generated functions
- `ss_drop_fields_ClassName`: calls `emitFieldReleaseLoop` (release ref-type fields), no dealloc
- `ClassName_new_reuse(ptr, args)`: same as `ClassName_new` but uses pre-allocated pointer via shared `emitClassCtorBody`
- `ss_drop_ClassName` now calls `ss_drop_fields_ClassName` then `ss_dealloc` (eliminates code duplication)

### Bug fix: Constructor arg uniqueness
Pass 3 (Uniqueness Analysis) had a pre-existing bug: variables passed as constructor args get retained internally (rc bumped from 1→2), but PIR only sees USE markers. Fix: mark variables as non-unique if they appear as USE at the same AST statement as an ALLOC of a different variable.

## Alternatives Considered
- **Runtime uniqueness check**: `if (rc == 1) reuse else alloc`. More general but adds runtime overhead per allocation. Deferred for future work.
- **Size-class reuse**: Reuse across different types with same allocation size. More complex, requires size tracking. Deferred.
- **Non-consecutive reuse**: Track reuse tokens across multiple statements. Requires register liveness tracking beyond current PIR scope. Deferred.

## Consequences
- Memory reuse for common patterns: `const p1 = new Point(1,2); ...; const p2 = new Point(3,4)` skips both mi_free and mi_calloc for p2
- Generated IR grows by two functions per class (drop_fields + new_reuse), but LLVM can eliminate unused ones
- gen_pir.ss grew to 626 lines (1.25x limit) due to accumulated PIR state and query functions — candidate for split if more passes added
