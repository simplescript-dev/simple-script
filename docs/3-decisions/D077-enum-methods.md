# D077: Enum Iteration Methods

**Status**: Implemented
**Depends on**: D076 (enum string values)

## Decision

Add `EnumName.values()` and `EnumName.names()` static methods for all enums. These are compile-time generated arrays — no runtime dispatch needed.

```ss
enum Color { Red = 0, Green = 1, Blue = 2 }
enum Direction { Up = "up", Down = "down" }

Color.values()      // [0, 1, 2]        (Array<int>)
Color.names()       // ["Red", "Green", "Blue"]  (Array<string>)
Direction.values()  // ["up", "down"]    (Array<string>)
Direction.names()   // ["Up", "Down"]    (Array<string>)
```

## Reasoning

- **Java equivalent**: `Color.values()` returns all enum constants. Standard pattern across Java, Kotlin, Swift (`CaseIterable`).
- **TypeScript equivalent**: `Object.keys(Enum)` / `Object.values(Enum)`.
- **No new keywords**: Uses existing method call syntax on enum names.
- **Compile-time resolution**: Arrays are constructed inline at each call site — no runtime enum registry needed.

## Rejected Alternatives

- **`Color.valueOf("Red")`** (reverse lookup): Deferred — more complex (needs string→value mapping), can be added later.
- **Global constant array caching**: Each `.values()` call generates a fresh array. Could optimize to a global const array per enum later.

## Implementation

### Files Changed

1. **codegen.ss**: Add `enumVariantNames` global Map ("|"-separated variant name list per enum).
2. **gen_stmts.ss**: `registerEnum()` populates `enumVariantNames` alongside `enumValues`.
3. **gen_methods.ss**: `genEnumArray(eName, useNames)` generates array construction IR. Dispatch added at top of `genMethodCall()` before static method check.
4. **gen_types.ss**: `inferType()` returns "ptr" for enum `.values()`/`.names()` calls.

### Codegen Flow

1. `registerEnum()` stores `"Color" → "Red|Green|Blue"` in `enumVariantNames`
2. When `Color.values()` is encountered in `genMethodCall()`:
   - Detect: `enumReady == 1 && objKind == "IDENT" && enumVariantNames.has(objName)`
   - Call `genEnumArray(eName, 0)` for values, `genEnumArray(eName, 1)` for names
3. `genEnumArray()` emits:
   - `ss_newArray(count)` for int enums, `ss_newArrayPtr(count)` for string enums/names
   - Loop: `ss_arraySet` for each variant value or name

### Checker

No checker changes needed. Enum registered as type "enum" by checker, METHOD_CALL on unknown receiver class skips all validation. Codegen handles dispatch.

## Interfaces

- `enumVariantNames` Map: `"EnumName" → "Var1|Var2|Var3"` ("|"-separated variant names, insertion order preserved)
- `genEnumArray(eName, useNames)`: useNames=1 for names, useNames=0 for values
