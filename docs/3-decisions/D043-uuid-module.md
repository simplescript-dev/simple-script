# D043: UUID Module

**Status**: Accepted
**Depends-on**: D037 (Math enhancements), D035 (stdlib pattern)

## Decision

Add `lib/uuid.ss` — a UUID v4 generation and validation library following the standard library static method pattern. Also add `Math.randomInt(max: int): int` builtin and auto-seed `srand(time(0))` at program startup.

## Reasoning

UUID v4 is a widely-needed primitive for unique identifier generation. The module requires:
1. **Random integer generation**: `Math.random()` returns `double`, but SS has no `double→int` conversion method. Adding `Math.randomInt(max)` fills this gap cleanly — it calls `rand() % max` internally, avoiding the type conversion problem entirely.
2. **PRNG seeding**: `rand()` was unseeded, producing deterministic sequences. Auto-seeding with `srand(time(0))` in every program's `main()` startup ensures randomness by default.

## Rejected Alternatives

- **`toInt()` method on doubles**: Would require adding a new method dispatch path in the codegen. `Math.randomInt` is more targeted and sufficient.
- **`/dev/urandom` read**: SS's `readFile` reads text, not raw bytes. Would need new binary I/O runtime support — too heavy for this use case.
- **UUID v1 (timestamp-based)**: More complex, requires MAC address or node ID. v4 (random) is simpler and more commonly used.
- **External library**: Axiom V4 mandates core logic in pure SS.

## Interfaces

### Compiler Changes (3 files)
- `gen_runtime.ss`: Declare `@srand(i32)` in libc declarations
- `gen_decls.ss`: Call `srand(time(0))` in `main()` preamble (auto-seed)
- `gen_rt_io.ss`: Add `ss_randomInt(i32 %max) → i32` runtime function (`rand() % max`)
- `gen_registry.ss`: Register `Math_randomInt` → returns `int`, maps to `ss_randomInt`
- `gen_methods.ss`: Skip `int→double` auto-conversion for `randomInt` (isMathClass exception)

### Library API (lib/uuid.ss)

| Method | Signature | Description |
|--------|-----------|-------------|
| `UUID.v4()` | `(): string` | Generate random UUID v4 |
| `UUID.isValid(str)` | `(str: string): int` | Validate 8-4-4-4-12 hex format |
| `UUID.parse(str)` | `(str: string): string` | Normalize to lowercase, `""` if invalid |
| `UUID.version(str)` | `(str: string): int` | Extract version digit, 0 if invalid |
| `UUID.nil()` | `(): string` | Return nil UUID (all zeros) |

### Import
```
import { UUID } from "@/lib/uuid"
```

## Tensions

- **`Math.randomInt` not in JS/TS**: JS has no separate int type, so `Math.randomInt` has no JS equivalent. Justified because SS's `int`/`double` type split creates a practical need that doesn't exist in JS. The alternative (no double→int conversion at all) would make many numeric operations impossible.
- **`srand` auto-seeding is global side effect**: Every SS program now calls `srand(time(0))` at startup. This is standard C practice and matches user expectations for `Math.random()`. The slight startup cost (one `time()` syscall) is negligible.
- **`rand() % max` modulo bias**: For small `max` values (like 16 for hex digits), modulo bias is negligible (RAND_MAX=2^31-1). Not worth the complexity of bias-free rejection sampling for this use case.
