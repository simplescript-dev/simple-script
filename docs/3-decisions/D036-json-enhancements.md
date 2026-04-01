# D036: JSON Library Enhancements

**Status:** Accepted
**Depends-on:** D035 (stdlib pattern)

## Decision

Enhance `lib/json.ss` with:
1. **New getter methods**: `getDouble()`, `getBool()`, `has()`, `keys()`
2. **New direct access**: `asDouble()`, `asBool()`
3. **New builder methods**: `put(key, double)`, `putBool()`, `putNull()`, `add(double)`, `addBool()`, `addNull()`
4. **Escape handling in stringify**: `jnEscapeString()` escapes `\`, `"`, `\n`, `\t`, `\r`
5. **Parser fixes**: `\r` and `\/` escape handling, scientific notation (`e`/`E`/`+`/`-`)

## Reasoning

The original json.ss (392 LOC) only supported `getString()` and `getInt()` getters. Real-world JSON contains doubles, booleans, and nulls. The stringify function didn't escape special characters, producing invalid JSON output for strings containing newlines, tabs, quotes, or backslashes. The parser didn't handle scientific notation or `\r`/`\/` escape sequences.

## Interfaces

```
// Getters (on JsonNode)
getDouble(key: string): double     // returns parseDouble of stored number string
getBool(key: string): int          // returns 1/0 from stored bool value
has(key: string): int              // returns 1 if key exists, 0 otherwise
keys(): Array<string>              // returns all object keys

// Direct access (on JsonNode, for array elements)
asDouble(): double
asBool(): int

// Builders (on JsonNode, chainable)
put(key: string, value: double): JsonNode
putBool(key: string, value: int): JsonNode
putNull(key: string): JsonNode
add(value: double): JsonNode
addBool(value: int): JsonNode
addNull(): JsonNode
```

## Implementation Notes

- `getDouble` uses existing `parseDouble()` builtin (wraps `atof`)
- `getBool` is type-agnostic — reads numeric value regardless of node type ("bool" or "number")
- `keys()` parses the internal field list string (`"key1:id1,key2:id2,..."`) and returns `Array<string>`
- `putBool`/`addBool` use separate method names (not overloaded `put`/`add`) because bool is `int` in SS — would clash with `put(key, int)` signature
- `jnEscapeString()` handles: `\` → `\\`, `"` → `\"`, newline → `\n`, tab → `\t`, CR → `\r`
- Scientific notation: `jpParseNumber()` now consumes `e`/`E` followed by optional `+`/`-` and digits
- No compiler changes needed — pure SS library code
- json.ss: 392 → 514 LOC

## Rejected Alternatives

- **Separate `getNumber` returning string**: Less ergonomic than `getDouble`/`getInt` split
- **Bool overload on `put`**: Would require separate bool type; SS bool is i32
- **Unicode `\uXXXX` escape**: Deferred — requires hex parsing utilities not yet available
