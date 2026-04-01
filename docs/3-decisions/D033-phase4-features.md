# D033: Phase 4 Language Features Batch

**Status:** Accepted
**Depends-on:** D032 (power operator), D025 (interfaces)

## Decision

Implement four Phase 4 language features in a single batch:

1. **String `.includes()`** — Works through existing `genArrayMethod` dispatch (which handles both array and string `includes` via `ss_indexOf`). No changes to `genStringMethod`.

2. **`for-of` loops** — `for (const x of arr)`, `for (let x of arr)`, `for (x of arr)`. New AST node `FOR_OF` with same slot layout as `FOR_IN` (S1=itemName, I1=iterable, I2=body). Codegen reuses `genForIn()`. `of` is a contextual keyword (parsed as IDENT, matched by value).

3. **Optional field chaining** — `obj?.field`. Parser already stores `nGetI3(id, isOptional)` on `MEMBER_ACCESS` nodes. Added `genOptionalMemberAccess()` in gen_class.ss: null check → branch → direct field load (no double evaluation of object expression).

4. **Spread in function calls** — `foo(...args)`, `foo(a, ...rest)`. Parser: `SPREAD_ELEM` nodes in `parseArgs()`. Codegen: `resolveCallArgs()` extracts array elements via `ss_arrayGet` for remaining parameter slots. Checker: skips arg count validation when spread present.

## Reasoning

- All four features have direct TS/JS equivalents (V1)
- String `.includes()` is TS standard, `.contains()` is non-standard — both now work
- `for-of` is the standard JS/TS iteration syntax; `for-in` is the SS legacy form
- Optional chaining completes the `?.` implementation (method calls already existed)
- Spread in calls completes the spread operator (array literals already existed)

## Rejected Alternatives

- **String includes via genStringMethod**: Conflicted with array `includes` dispatch. `genArrayMethod` already handles both array and string cases via type-based branching.
- **`of` as reserved keyword**: Would break code using `of` as variable name. Contextual matching is standard (matches JS/TS behavior).
- **genOptionalMemberAccess via genMemberAccess delegation**: Would cause double evaluation of object expression. Direct field load avoids this.

## Interfaces

- AST: `FOR_OF` node (S1=itemName, I1=iterable, I2=body)
- AST: `SPREAD_ELEM` in function call arg lists (I1=array expression)
- Codegen: `genOptionalMemberAccess()` in gen_class.ss
- Checker: `hasSpreadArg()` in checker.ss
