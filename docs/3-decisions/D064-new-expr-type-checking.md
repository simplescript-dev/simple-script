---
id: D064
title: NEW_EXPR constructor argument type checking
status: implemented
depends-on: [D053, D054, D063]
---

## Decision
Add compile-time type checking for `new ClassName(...)` constructor arguments, covering both positional and named argument styles.

## Reasoning
I003 identified NEW_EXPR argument type matching as the last remaining type-check gap in Phase 3. Constructor args map directly to class fields, so field types (already stored in `checkerFieldTypes`) serve as the expected types. This completes the 7th type-check site in the checker.

## Implementation

### Data structures
- **`checkerGenericClasses`**: New Map tracking generic classes (`"ClassName" → "1"`). Set during CLASS_DECL registration when `classTypeParams(s) != ""`.
- **Existing**: `checkerClassFields` (ordered field names), `checkerFieldTypes` (field types), `checkerClassParents` (inheritance chain).

### Helper function
- **`lookupConsParamType(className, paramIndex)`** in checker.ss: Builds parent chain root→leaf, walks fields in order counting indices, returns field type for `paramIndex`. Returns `""` for generic class fields (skips type check) or out-of-range indices.

### Type checking sites
1. **Positional args** (check_stmts.ss, NEW_EXPR handler): Iterates args, calls `lookupConsParamType()` per index, checks via `isTypeCompatible()`. Skips spread args.
2. **Named args** (`checkNamedConstructorArgs`): After field-exists validation, walks parent chain to find field owner class, checks value type vs field type. Skips generic class-owned fields.

### Generic class handling
Generic classes (e.g., `Box<T>`) are tracked in `checkerGenericClasses`. Both positional and named arg type checks skip fields belonging to generic classes, preventing false positives when field types are type parameters like `T`.

### Inheritance
`lookupConsParamType` accumulates fields from root ancestor to leaf class (parent fields first), matching SS constructor parameter order. Named arg check walks parent chain to find field owner for correct type lookup.

## Rejected alternatives
- **Dedicated `classConsParamTypes` Map**: Would duplicate data already in `checkerFieldTypes`. Using existing field data avoids synchronization issues.

## Interfaces
- `lookupConsParamType(className: string, paramIndex: int): string` — public, used by check_stmts.ss
- `checkerGenericClasses` — global Map, set in checker.ss CLASS_DECL handler

## Tensions
- Type checking completeness vs false positives: conservative approach (skip when type unknown) trades missed errors for zero false positives.
