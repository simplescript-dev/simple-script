# D031: Generic Type Constraints

**Status:** Implemented (multi-constraints added Round 54)
**Depends on:** D025 (interface dispatch), D026 (generic functions), D027 (generic classes), D028 (explicit type args)

## Decision

Generic type parameters can be constrained to require interface implementations using TypeScript-compatible `extends` syntax. Multiple constraints use `&` (intersection):

```simplescript
function best<T extends Rankable>(a: T, b: T): T { ... }
function show<T extends Printable & Scorable>(item: T): string { ... }
class Wrapper<T extends Printable & Scorable>(value: T) { ... }
```

Constraints are validated at specialization time (call site / `new` site). If the concrete type does not implement all required interfaces, compilation fails with a descriptive error.

## Syntax

```
<T extends InterfaceName>                // single constraint
<T extends A & B>                        // multi-constraint (intersection)
<T extends A & B & C>                    // three+ constraints
<T extends Rankable, U>                  // mixed: T constrained, U unconstrained
<A extends X & Y, B extends Z>          // multiple params, each with constraints
```

## Reasoning

1. **TypeScript compatibility (V1):** `extends` is the standard TS syntax. `&` for intersection constraints matches TS `<T extends A & B>`. The `EXTENDS` token was already in the lexer; `&` reuses the existing `BIT_AND` token.
2. **No parsing ambiguity:** Inside `<...>`, `BIT_AND` after a constraint identifier is unambiguously another constraint interface. `>` terminates the list.
3. **Monomorphization (zero runtime cost):** Constraints are purely compile-time validation. The monomorphized code is identical with or without constraints.
4. **Leverages existing infrastructure:** Constraint satisfaction is checked against the `ifaceImplementors` Map already populated by class registration.

## Rejected Alternatives

1. **Colon syntax `<T : Interface>`** — Used by Rust/Kotlin/Swift but not TypeScript. Rejected per V1 (TS-like syntax).
2. **Where clause `where T : Interface`** — More verbose, introduces new keyword. Deferred as potential future enhancement.
3. **Structural typing** — TS uses structural types but SS has nominal typing. Would require significant type system changes. Rejected for MVP.
4. **Comma-separated constraints `<T extends A, B>`** — Ambiguous with multiple type params. `&` is unambiguous (matches TS).

## Implementation

### Storage

Constraints stored as `&`-separated string in two Maps:

- `funcConstraintMap` — keyed by `"funcName.typeParam"` → `"A&B"` or `"A"` (single)
- `classConstraintMap` — keyed by `"className.typeParam"` → `"A&B"` or `"A"`

### Parser (parser.ss)

`parseTypeParamList()` reads type param identifiers inside `<...>`. After each identifier, checks for `EXTENDS`. If present, reads constraint interface name, then loops on `BIT_AND` to collect additional constraints, joining with `&`.

### Validation (gen_class.ss, gen_calls.ss, gen_generic_class.ss)

Shared `checkConstraint(concreteType, constraint, tp, ownerKind, ownerName)` in gen_class.ss:
1. Split constraint by `&`
2. For each interface, verify concrete type exists in `ifaceImplementors[interface]`
3. Error with descriptive message if any constraint not satisfied

### Error format

```
error: type 'Foo' does not satisfy constraint 'Scorable' for type parameter 'T' in function 'ranked'
error: type 'Plain' does not satisfy constraint 'Printable' for type parameter 'T' in class 'Box'
```

## Interfaces

| Function | File | Purpose |
|----------|------|---------|
| `funcConstraint(name, tp)` | parser.ss | Look up function type param constraint |
| `classConstraint(name, tp)` | parser.ss | Look up class type param constraint |
| `checkConstraint(type, constraint, tp, kind, name)` | gen_class.ss | Validate concrete type satisfies all constraints |

## Tensions

- **Primitive types cannot satisfy constraints:** `int`, `string`, etc. are not in `ifaceImplementors`. Constraints only work with user-defined classes. This is consistent with nominal typing but limits generic utility functions. Future: could add built-in type trait mapping.
