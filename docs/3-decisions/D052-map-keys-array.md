# D052: Map.keys() Returns Array<string>

**Status:** Accepted
**Depends-on:** D021 (Collection types)

## Decision

`Map.keys()` now returns `Array<string>` instead of a newline-separated string. Added `ss_mapKeysArray` runtime function that iterates hash buckets and builds a proper Array. All compiler source usages of `.keys().split("\n")` pattern migrated to direct `.keys()`.

## Reasoning

`ss_mapKeys` returned a newline-separated string — an internal implementation detail leaked to user code. Users calling `.keys()` expected `Array<string>` (matching JS/TS), but got a raw string. This caused:
- `.length()` returning string byte count instead of key count
- `k[i]` returning garbage (array indexing on a string)
- 20+ stdlib modules forced into ugly global-Map-with-composite-keys workaround

The limitation was documented as "Known limitation" for 20+ rounds instead of being fixed — violating P4 (Root cause first). Added P4a principle to prevent recurrence.

## Implementation

### Runtime (gen_rt_map.ss)
- Added `ss_mapKeysArray(ptr %map) → ptr` — iterates 64 hash buckets, strdup each key into `ss_newArrayPtr`
- Kept `ss_mapKeys` unchanged for backward compatibility (internal use)

### Codegen (gen_builtins.ss)
- `genMapMethod` for "keys" → `call ptr @ss_mapKeysArray`

### Type Registry (gen_registry.ss)
- `funcRetTypes.set("Map_keys", "Array<string>")` — class-level return type
- `methodRetTypes.set("keys", "Array<string>")` — fallback return type
- Note: `funcRetTypes` for class methods takes priority over `methodRetTypes` in `inferType`

### Compiler Source Migration
8 files updated: gen_rc.ss, gen_type_ops.ss (2), pir_opt.ss (2), gen_generic_class.ss, gen_iface.ss, gen_class.ss. Pattern: `someMap.keys().split("\n")` → `someMap.keys()`.

### Bootstrap Strategy
Two-phase approach required (self-bootstrapping compiler uses `.keys()` internally):
1. Phase A: Change codegen + runtime only, keep old source pattern. Build bridge seed manually.
2. Phase B: Update compiler source to new pattern. Full 3-stage bootstrap with bridge seed.

## Rejected Alternatives

- **Add `.keysArray()` method**: Ugly non-standard API. Users expect `.keys()` to work.
- **Single-step bootstrap**: Impossible — stage1 compiled by old seed has old `.keys()` behavior but new source expects Array. Chicken-and-egg.
- **Change ss_mapKeys in-place**: Would break stage2 during bootstrap (runtime returns Array but source does `.split("\n")`).

## Tensions

- C1 (self-bootstrapping) required the two-phase approach — can't change method semantics and source usage simultaneously
- P4a (new): Compiler limitation is a bug, not a boundary — this fix was delayed 20+ rounds
