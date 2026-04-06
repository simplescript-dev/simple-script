# D076: Enum String Values

**Status**: Implemented
**Depends-on**: Existing enum support (integer enums)

## Decision

Support string values in enums, following TypeScript's string enum semantics:

```typescript
enum Direction {
    Up = "up",
    Down = "down",
    Left = "left",
    Right = "right"
}
```

String enums require every variant to have an explicit string value (no auto-increment). Mixing string and integer values in the same enum is a compile error.

## Reasoning

- TypeScript has string enums — direct correspondence (V1)
- No new keywords needed — extends existing `enum` keyword
- Useful for JSON serialization, API methods, status codes
- Clean integration with existing switch/case

## Design

### Syntax

```typescript
// Integer enum (existing, unchanged)
enum Color { Red, Green, Blue }
enum Color { Red = 1, Green = 2, Blue = 3 }

// String enum (new)
enum HttpMethod { Get = "GET", Post = "POST", Put = "PUT", Delete = "DELETE" }

// Mixed — compile error
enum Bad { A = "hello", B = 42 }  // error: cannot mix string and integer values
```

### AST

- **ENUM_VARIANT**: S1=name, I1=intValue (int enums), S2=stringValue (string enums)
- **ENUM_DECL**: S1=name, List=variants, I1=isStringEnum (0=int, 1=string)

### Type Semantics

- `Direction.Up` has type `string` (not a special enum type)
- `Color.Red` has type `int` (unchanged)
- String enum values interoperate with string comparison (`==`, `!=`, `switch`)
- Variables assigned from string enums are typed `string`

### Codegen

- String enum access: `genMemberAccess()` returns `addStringConst(value)` (ptr to string constant)
- Integer enum access: returns integer literal directly (unchanged)
- Switch/case: automatically uses `ss_string_eq` when subject is string type

### Checker

- Validates consistency: if any variant has a string value, all must have string values
- Error: `enum 'X' cannot mix string and integer values` (points to offending variant)

## Implementation

~25 lines across 6 files:
- **parser.ss**: Accept STRING token in `parseEnumDecl()`, track `isStringEnum`
- **checker.ss**: Validate string enum consistency
- **codegen.ss**: Add `enumTypes` global Map
- **gen_stmts.ss**: `registerEnum()` tracks string vs int enum type
- **gen_class.ss**: `genMemberAccess()` returns string constant for string enums
- **gen_types.ss**: `inferType()` returns "string" for string enum member access

## Rejected Alternatives

- **Mixed string/int enums**: TypeScript doesn't recommend this, adds complexity for little value
- **Auto-increment for string enums**: No meaningful auto-increment for strings
- **Separate enum type (not string)**: Would require a new type system concept; TypeScript treats string enums as strings

## Interfaces

- `enumValues` Map: stores `"EnumName.VariantName" → value` (string for both int and string enums)
- `enumTypes` Map: stores `"EnumName" → "string"` or `"EnumName" → "int"`
