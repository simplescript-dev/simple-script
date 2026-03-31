# D028: Explicit Type Arguments at Call Sites

## Status: Accepted

## Context

D026 (generic functions) and D027 (generic classes) implement monomorphization, but type parameters are only inferred from argument types. This creates limitations when inference is ambiguous or when the user wants to be explicit about types. Adding `identity<int>(42)` and `new Box<int>(42)` completes the generics system.

## Decision

**TypeScript-style lookahead disambiguation** for function calls, **unambiguous parsing** for `new` expressions.

### Parser: Disambiguation Strategy

The core challenge: `foo<bar>(baz)` could be a generic call or a comparison chain `(foo < bar) > (baz)`.

Solution: `isGenericCallSite()` lookahead function (same pattern as `isArrowFunc()`):
1. Scan tokens from current position without modifying `tPos`
2. Valid tokens inside `<>`: IDENT, INT_TYPE, DOUBLE_TYPE, STRING_TYPE, BOOL_TYPE, VOID_TYPE, COMMA, LT, GT
3. If balanced `<>` closes and next token is LPAREN → generic call
4. Otherwise → comparison operator

For `new ClassName<Type>(...)`: no disambiguation needed — `<` after class name in `new` context can only be type args.

### Storage

Explicit type args stored in **S2 field** of CALL and NEW_EXPR nodes (previously unused):
- S2 = comma-separated type strings, e.g., `"int,string"`
- Empty S2 = inference mode (backward compatible)

### Codegen

`genGenericCall()` and `genGenericNewExpr()` check S2 before falling back to argument inference. `inferGenericRetType()` and `inferGenericClassName()` accept an `explicitTypes` parameter.

## Known Limitations

- **Nested generics at call sites**: `foo<Array<int>>(...)` fails because `>>` lexes as SHR token. Workaround: use inference.
- **False positive**: `a<b>(c)` where `a` and `b` are variables is parsed as generic call. Very rare; TypeScript has same behavior.

## Files Changed

- `parse_exprs.ss` — `isGenericCallSite()`, `parseTypeArgList()`, modified `parseAtom()` IDENT and NEW cases
- `gen_types.ss` — `inferGenericRetType()` and `inferGenericClassName()` accept explicit types, 4 call sites updated
- `gen_calls.ss` — `genGenericCall()` checks S2 before inference
- `gen_class.ss` — `genGenericNewExpr()` checks S2 before inference
- `gen_decls.ss` — Updated `inferGenericClassName` call site
- `parser.ss` — Added `listGet()` utility (used to simplify type-param zip pattern)

## Rejected Alternatives

- **Rust turbofish `::<T>`**: Simplest parser change but alien to TypeScript-style syntax
- **Go square brackets `[T]`**: Zero ambiguity but major syntax departure
- **Full speculative parsing with backtrack**: Overkill; SimpleScript parser is forward-only
