# D017: Field-Level const (C6 Abolishment)

## Status
firm

## Resolves
C6 axiom removal — fields are no longer universally immutable. Enables mutable object fields with opt-in immutability.

## Depends On
- axioms.md → C5 (no user-facing memory syntax — complexity hidden in compiler)
- spec/71-perceus-rc.md (Perceus RC handles mutable field semantics)

## Decision
Abolish C6 ("Class fields immutable"). Replace with field-level `const` modifier:

- **No modifier** → mutable field, assignable after construction: `health: int`
- **`const` modifier** → immutable field, set only at construction: `const name: string`

Compiler rejects any post-construction assignment to `const` fields at compile time, regardless of context (direct access, function parameter, nested access).

Field assignment syntax: `obj.field = value`, including nested `a.b.c = value` (recursive GEP chain). Compound assignment supported: `obj.field += value`.

Two independent layers of immutability:
- **Binding layer** (let/const): controls whether variable can be rebound to another object
- **Field layer** (const modifier): controls whether individual field values can change

```
const hero = new Player("Alice", 100)
hero.health -= 25    // OK: mutable field
hero.name = "Bob"    // ERROR: const field
hero = new Player()  // ERROR: const binding
```

Named parameter construction supported: `new Player(name: "Alice", health: 100)`.

## Key Reasoning (3 sentences max)
C6 was a simplification constraint that prevented the language from expressing common mutation patterns (game state, context passing, configuration). Field-level const gives users fine-grained control while keeping the mental model simple — same as Kotlin/Swift property modifiers. Perceus RC analysis handles the memory safety implications that C6 was designed to avoid.

## Rejected Alternatives
- Keep C6 (all fields immutable): Blocks too many real-world use cases. Forces users into functional patterns for simple state updates.
- Mutable by annotation (`mut` keyword): Adds a new keyword. Default-mutable with `const` opt-in is more familiar to TS/Java developers (V1).
- Deep immutability (const field makes nested objects immutable too): Overcomplicates the model. Each level controls its own fields independently.

## Interfaces With Other Decisions
- D018 (object layout): Mutable fields stored identically to const fields in struct — enforcement is compile-time only.
- D019 (Perceus IR): FIELD_SET instruction handles RC implications of field reassignment (rc_dec old value, rc_inc new value for ref-type fields).
- D022 (clone semantics): deepClone can optimize const fields (rc_inc instead of recursive copy).
- I003 (semantic analysis): Checker needs new pass for const field validation.

## Open Tensions
- Nested const field checking requires class field metadata at compile time. Checker must have access to field const status across class boundaries.
- Parser must distinguish `const name: string` (field declaration with const) from `const x = 10` (variable binding). Context determines interpretation.

## Notes
C6 abolished 2026-03-31. Axioms.md updated. All existing tests unaffected (they don't use field assignment, which was previously forbidden).
