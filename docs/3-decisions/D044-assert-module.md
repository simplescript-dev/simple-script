# D044: Assert Module — Lightweight Test Assertions

**Status:** Accepted
**Depends on:** D035 (stdlib pattern)

## Decision

Add `lib/assert.ss` — a lightweight test assertion library using the static method pattern. Provides type-specific assertion methods with overloaded `equal`/`notEqual` for int and string. Pure SS, no compiler changes.

## Reasoning

Every test file in `tests/phase5/` re-defines local `assert()`, `assertEq()`, `assertInt()` helpers. Centralizing these into a stdlib module:
- Eliminates boilerplate (~10-15 lines per test file)
- Provides consistent failure messages with actual/expected values
- Adds comparison and string-matching assertions not commonly hand-written
- Follows the established stdlib pattern (static methods on empty class)

## API (15 methods)

| Method | Signature | Description |
|--------|-----------|-------------|
| `isTrue` | `(value: int, msg: string)` | Assert value != 0 |
| `isFalse` | `(value: int, msg: string)` | Assert value == 0 |
| `equal` | `(actual: int, expected: int, msg: string)` | Int equality |
| `equal` | `(actual: string, expected: string, msg: string)` | String equality |
| `notEqual` | `(actual: int, expected: int, msg: string)` | Int not-equal |
| `notEqual` | `(actual: string, expected: string, msg: string)` | String not-equal |
| `approxEqual` | `(actual: double, expected: double, eps: double, msg: string)` | Float equality within epsilon |
| `greaterThan` | `(actual: int, expected: int, msg: string)` | Assert actual > expected |
| `lessThan` | `(actual: int, expected: int, msg: string)` | Assert actual < expected |
| `greaterOrEqual` | `(actual: int, expected: int, msg: string)` | Assert actual >= expected |
| `lessOrEqual` | `(actual: int, expected: int, msg: string)` | Assert actual <= expected |
| `contains` | `(text: string, substr: string, msg: string)` | Assert string contains substring |
| `startsWith` | `(text: string, prefix: string, msg: string)` | Assert string starts with prefix |
| `endsWith` | `(text: string, suffix: string, msg: string)` | Assert string ends with suffix |
| `fail` | `(msg: string)` | Unconditional failure |

## Design Choices

- **Overloaded `equal`/`notEqual`**: Uses SS function overloading (`_i_i_s` / `_s_s_s` mangling) for type-safe equality. No `any` type needed.
- **`exit(1)` on failure**: Matches existing test pattern. No try/catch overhead.
- **Descriptive output**: Failure prints `FAIL: <msg>` + detail line with actual/expected values.
- **Pass counter**: Internal `assertPassCount` tracks successful assertions. `Assert.summary()` not included — tests print their own success message.
- **No `throws` assertion**: Would require calling a generic `fn` — SS doesn't have a void-returning zero-arg function type convention. Deferred.

## Rejected Alternatives

- **Exception-based**: Using `throw` instead of `exit(1)`. Rejected: doesn't match existing test pattern, adds try/catch complexity.
- **Generic equality**: Single `equal(a: any, b: any)`. Rejected: SS has no `any` type; overloading is the correct approach.
- **Test runner framework**: Full xUnit-style with setup/teardown. Rejected: over-engineered for current needs.

## Interfaces

- **Import**: `import { Assert } from "@/lib/assert"`
- **Usage**: `Assert.equal(42, 42, "answer")`, `Assert.contains("hello world", "world", "greeting")`
- **Failure output**: `FAIL: <msg>\n  expected <expected>, got <actual>`

## Tensions

- None. Pure library addition, no compiler changes, no existing code affected.
