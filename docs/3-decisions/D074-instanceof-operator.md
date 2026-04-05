# D074: instanceof Operator

**Status:** Accepted
**Date:** 2026-04-05

## Context

With D073's Java-style error handling (typed catch, Error class hierarchy), there's a need for runtime type checking in user code. TypeScript and Java both have the `instanceof` operator as a standard binary operator.

The runtime infrastructure already exists: `ss_isinstance(ptr, className)` was added in D073 for typed catch dispatch, walking the TypeInfo parent chain.

## Decision

Add `instanceof` as a binary operator at the comparison precedence level.

**Syntax:** `expr instanceof ClassName` → returns `int` (1=true, 0=false, same as SS booleans).

**Semantics:** Checks if the object's TypeInfo (or any ancestor TypeInfo in the parent chain) matches the target class name. Works with inheritance — `dog instanceof Animal` returns 1 if Dog extends Animal.

## Implementation

### Lexer (lexer.ss)
- New keyword: `instanceof` → `INSTANCEOF` token in `keywordKind()`

### Parser (parse_exprs.ss)
- Added `INSTANCEOF` to `parseComparison()` loop alongside `<`, `>`, `<=`, `>=`
- Creates `BINARY` node with `S1="Instanceof"`, `I1=left expr`, `I2=right expr (IDENT)`

### Checker (checker.ss)
- `checkerInferType()` returns `"int"` for `Instanceof` operator (boolean result)

### Type Inference (gen_types.ss)
- `inferType()` returns `"int"` for `Instanceof` operator

### Codegen (gen_exprs.ss)
- `genBinary()` handles `Instanceof`: evaluates left operand, gets class name from right IDENT node, calls `ss_isinstance(ptr obj, ptr className)` which returns i32

### Runtime
- No changes needed — `ss_isinstance` already exists from D073

## Tests

- `tests/phase5/instanceof_basic.ss` — direct type, inheritance, negative checks
- `tests/phase5/instanceof_error.ss` — Error class hierarchy, if-else branching

## Precedence

Same as comparison operators (`<`, `>`, `<=`, `>=`), matching Java/TypeScript behavior.
