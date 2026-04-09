# D083: Enum.valueOf() — Reverse Name-to-Value Lookup

**Status:** Done
**Depends on:** D077 (enum iteration methods)

## Decision

Add `EnumName.valueOf(name: string)` static method for all enums. Returns the enum value corresponding to the variant name. Throws on invalid name.

## Syntax

```simplescript
enum Color { Red = 0, Green = 1, Blue = 2 }
enum Direction { Up = "up", Down = "down" }

Color.valueOf("Red")        // 0
Color.valueOf("Blue")       // 2
Direction.valueOf("Up")     // "up"
Color.valueOf("Purple")     // throws: "invalid enum name for Color: Purple"
```

## Return Type

- **Int enum** (`Color`): returns `int`
- **String enum** (`Direction`): returns `string`

## Implementation

### Codegen (gen_methods.ss)

`genEnumValueOf(eName, argList)` generates a strcmp chain at the call site:

```
strcmp(arg, "Red") == 0  → store 0, br done
strcmp(arg, "Green") == 0 → store 1, br done
strcmp(arg, "Blue") == 0  → store 2, br done
else → ss_throw("invalid enum name for Color: " + arg)
```

Uses alloca + phi-style load pattern (same as switch codegen).

### Type Inference (gen_types.ss)

`inferType` for METHOD_CALL: when `valueOf` is called on an enum IDENT, returns `"int"` for int enums, `"string"` for string enums (via `enumTypes` map check).

### Dispatch (gen_methods.ss)

Added to the existing enum method dispatch block in `genMethodCall()`, alongside `values` and `names`.

### Checker

No changes — follows the same pattern as `values()` and `names()` (no explicit checker validation for enum static methods).

## Rejected Alternatives

- **Runtime hash map lookup**: Would require a global Map per enum, initialized at startup. The strcmp chain is simpler and fast enough for typical enum sizes (< 20 variants).
- **Returning -1 or null on failure**: Java's `valueOf()` throws `IllegalArgumentException`. Throwing is more consistent with the language's error handling model.
