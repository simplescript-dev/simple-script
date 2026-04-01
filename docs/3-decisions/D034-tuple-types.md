# D034: Tuple Types

**Status:** Accepted
**Depends-on:** D033 (Phase 4 features)

## Decision

Add tuple types as fixed-length typed arrays with TypeScript-like syntax `[type, type, ...]`.

## Syntax

```typescript
// Type annotation
let t: [int, string] = [42, "hello"]

// Indexed access with positional type inference
const n: int = t[0]      // inferred as int
const s: string = t[1]   // inferred as string

// Function return type
function getPair(): [string, int] {
    return ["hello", 42]
}

// Destructuring with per-element types
const [a, b] = getPair()  // a: string, b: int
```

## Internal Representation

- Type string: `Tuple<int,string>` (same format as generic types)
- Runtime: backed by arrays (same `ss_arrayGet`/`ss_arraySet`)
- Parser converts `[int, string]` → `"Tuple<int,string>"` in type position

## Key Design Choices

### Mixed-type array safety
Arrays with both ptr and scalar elements use `ss_newArray` (tag=1, no element-level RC cleanup) instead of `ss_newArrayPtr` (tag=5). This prevents segfaults from the cleanup code interpreting integer elements as pointers.

### Positional type inference
`inferType()` for INDEX_ACCESS checks if the array variable has a Tuple type and the index is a constant INT_LIT. If so, returns the positional element type. Dynamic indices fall back to i64.

### Depth-aware type parsing
`tupleElemTypeAtIndex()` counts `<>` nesting depth when splitting types by comma, correctly handling nested generics like `Tuple<int,Array<string>>`.

## Rejected Alternatives

- **`Tuple<int, string>` as user syntax** — Not TypeScript equivalent. TS uses `[number, string]`.
- **Separate runtime type for tuples** — Unnecessary complexity. Array backing is sufficient since type information is compile-time only.

## Interfaces

| File | Change |
|------|--------|
| parser.ss | `parseTypeAnn()` + LBRACKET case |
| gen_types.ss | `isTupleType()`, `tupleElemTypeAtIndex()`, `inferType()` INDEX_ACCESS |
| gen_exprs.ss | `genIndexAccess()` tuple element type casting |
| gen_decls.ss | `genDestructureArray()` per-element types |
| gen_calls.ss | `genArrayLit()` mixed-type safety |

## Known Limitations

- Positional type inference only works when the tuple expression is a simple IDENT (not chained calls like `f()[0]`)
- Class instance elements in tuple destructuring lack PIR RC tracking
- No tuple-specific length validation at compile time
