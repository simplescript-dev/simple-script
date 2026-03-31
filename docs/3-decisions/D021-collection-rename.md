# D021: Collection Type Rename and Set

## Status
firm

## Resolves
Array naming inconsistency and missing Set type. `Array` renamed to `List` for clarity. `Set` added as Phase 1 basic collection.

## Depends On
- axioms.md → V1 (TypeScript-like syntax — TS uses Array, but List is more universal)

## Decision
**Phase 1:**
- `Array<T>` → `List<T>` (rename, same underlying implementation)
- `Map<K, V>` — unchanged
- `Set<T>` — new type, internally `Map<T, bool>` wrapper

**Phase 2+:**
- `FixedList<T>` — immutable list (no add/remove/replace after construction)
- `FixedMap<K, V>` — immutable map
- `FixedSet<T>` — immutable set

`Fixed*` means collection structure is fixed. Element internal mutability depends on element's own field `const` declarations.

```
let items: List<Player> = [hero1, hero2]
items.push(hero3)          // OK
items[0].health -= 20      // OK (Player.health is mutable)
items[0].name = "Bob"      // ERROR (Player.name is const)
```

Set implementation (~30 lines, Map wrapper):
```
class Set<T> {
    _inner: Map<T, bool>
    function add(item: T)       { this._inner.set(item, true) }
    function has(item: T): bool { return this._inner.has(item) }
    function remove(item: T)    { this._inner.remove(item) }
    function size(): int        { return this._inner.size() }
}
```

## Key Reasoning (3 sentences max)
`List` is the more universal name for ordered mutable collections (Java, Python, Kotlin, Dart all use List). Set has near-zero implementation cost as a Map wrapper and completes the basic collection trio (List, Map, Set) for Phase 1. Fixed variants deferred because they need additional design (construction syntax, freeze semantics, compiler optimizations).

## Rejected Alternatives
- Keep `Array` name: Less clear semantics. "Array" suggests fixed-size in many languages (C, Java).
- Defer Set to Phase 2: Almost no implementation cost. Having List+Map+Set in Phase 1 covers most use cases.
- Implement FixedList in Phase 1: Needs design decisions (literal syntax vs `.freeze()`, conversion semantics). Not essential for initial release.

## Interfaces With Other Decisions
- D017 (field-level const): Collection element mutability governed by element's own const fields, not collection type.
- D018 (object layout): List/Set are heap objects with RC header + TypeInfo, same as any class.

## Open Tensions
- `Array` keyword may still appear in existing tests and bootstrap code. Migration requires renaming all references.
- Generic type parameters (`<T>`) are currently type annotations only — no compile-time type checking of element types.

## Notes
Runtime functions renamed: `ss_arrayNew` → `ss_listNew`, `ss_arrayPush` → `ss_listPush`, etc. Or keep internal names and only change user-facing type name. Decision confirmed 2026-03-31.
