# D029: Pattern Matching via Switch Extension

## Status: Accepted

## Context

Current `switch` only supports integer and string literal patterns. Enum values must be matched by raw integer (`case 0` instead of `case Color.Red`). Phase 4 needs pattern matching to improve enum ergonomics.

## Decision

**Extend existing `switch/case` syntax** with new pattern types. No new keywords, no new syntax forms.

### Syntax

```simplescript
// Enum patterns (core value: replace raw integers)
switch (color) {
    case Color.Red -> println("red")
    case Color.Green -> println("green")
    default -> println("other")
}

// Bool literal patterns
switch (flag) {
    case true -> println("yes")
    case false -> println("no")
}

// Existing literal patterns (unchanged)
switch (x) {
    case 0 -> println("zero")
    case "hello" -> println("hi")
    default -> println("other")
}
```

### Pattern Types

| Pattern | Syntax | Resolution | Codegen |
|---------|--------|------------|---------|
| INT literal | `case 42` | existing | `icmp eq i32` |
| STRING literal | `case "hi"` | existing | `@ss_string_eq` |
| BOOL literal | `case true` | new | `icmp eq i32` |
| ENUM member | `case Color.Red` | compile-time via `enumValues` → int | `icmp eq i32` |
| IDENT (var ref) | `case someConst` | existing | load + compare |

### Parser Changes

Extend pattern parsing within existing `parseSwitch()`:

- `case INT` → INT literal (existing)
- `case STRING` → STRING literal (existing)
- `case TRUE/FALSE` → BOOL literal (new)
- `case IDENT DOT IDENT` → ENUM pattern (new: `Color.Red`)
- `case IDENT` → variable reference (existing)

AST: `SWITCH_PAT` node S1 stores pattern kind (`"INT"`, `"STRING"`, `"BOOL"`, `"ENUM"`, `"IDENT"`), S2 stores value.

## Design Principles

- **No new keywords**: `switch`, `case`, `default` all pre-existing
- **No new syntax forms**: every pattern uses existing token sequences
- **TS/JS alignment**: all patterns have direct TypeScript equivalents
- **Backward compatible**: existing switch/case code unchanged
- **Reuses infrastructure**: `enumValues` Map for compile-time enum resolution

## Rejected Alternatives

- **New `match` keyword**: Unnecessary language complexity. `switch` can express all needed patterns.
- **Type binding pattern (`case dog: Dog`)**: Introduces non-TypeScript syntax.
- **Wildcard (`case _`)**: `_` is a valid variable name in TS/JS, not a wildcard. Use existing `default ->` instead.
- **Exhaustiveness checking**: Deferred. Would require tracking all enum variants. Current behavior: no match → falls through silently (same as switch without default).
- **Destructuring patterns**: `case Dog(name, age)` deferred to separate feature.
- **Guard clauses**: `case x if x > 0` deferred. Can be emulated with nested if inside case body.
