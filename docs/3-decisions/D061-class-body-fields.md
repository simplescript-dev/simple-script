# D061: Class Fields in Body (TS-style)

**Status**: Complete (all phases done)
**Depends-on**: None

## Decision

Migrate class field declarations from constructor-param style to class body style:

```
// Before (Kotlin-style)
class Point(x: int, y: int)
class Point3D extends Point(z: int)

// After (TS/Java-style)
class Point {
    x: int
    y: int
}

class Point3D extends Point {
    z: int
}
```

Constructor is auto-generated from body field declarations. Field order determines constructor parameter order.

## Reasoning

- `class Foo(fields)` is Kotlin primary-constructor syntax, not TS/Java.
- `extends Point(z: int)` is ambiguous — `(z: int)` looks like arguments to `Point`.
- TS and Java declare fields in the class body. SS should follow the same convention.
- Principle: prioritize Java/TS syntax over Kotlin/Scala syntax.

## Scope

Breaking change. All class declarations across bootstrap (~35 files), stdlib (~20 modules), and tests (~80 files) must be migrated.

### Parser Changes
- Class body recognizes field declarations: `name: type`, `const name: type`, `name: type = defaultValue`
- Distinguish field declarations from method declarations in class body
- `class Foo(fields)` syntax deprecated/removed
- `extends Parent` no longer followed by `(fields)`

### Codegen Changes
- Field list extracted from body declarations instead of constructor param list
- Constructor auto-generated from body fields (same behavior, different source)
- `const` field handling moves from PARAM S3 to field declaration syntax

### Migration
- All `class Foo(field1: type1, field2: type2)` → `class Foo { field1: type1; field2: type2 }`
- All `class Bar extends Foo(field3: type3)` → `class Bar extends Foo { field3: type3 }`
- Bootstrap must be migrated atomically (seed compiler frozen at old syntax)

## Rejected Alternatives

- **Hybrid (body for subclass, parens for base)**: Inconsistent — two styles for same concept.
- **Keep Kotlin-style**: User rejected. Not aligned with TS/Java conventions.
- **`class Point3D(z: int) extends Point`**: Still Kotlin-style, just reordered.

## Implementation Phases

### Phase A — Parser dual-syntax support (DONE, Round 86)
- Added `isBodyFieldStart()` and `parseBodyField()` in parser.ss
- Modified `parseClassDecl()` body parsing to detect fields vs methods
- Detection: `const` → field; `IDENT` + `:` or `?` → field; `function`/`@` → method
- Body fields create identical PARAM nodes as old `(fields)` syntax
- Bootstrap fixed-point verified; 81 tests pass
- Seed compiler updated to support both syntaxes

### Phase B — Code migration (DONE, Round 87)
- Migrated 85 class declarations across 83 files (lib/, tests/, examples/)
- Bootstrap files have no class declarations (Map-based AST architecture)
- Python migration script `migrate_class_syntax.py` handled bulk conversion
- Bootstrap fixed-point verified; 81 tests pass

### Phase C — Remove old syntax (DONE, Round 88)
- Removed `(fields)` parsing from `parseClassDecl()` (5 lines deleted)
- Deleted migration script `migrate_class_syntax.py`
- Bootstrap fixed-point verified; 81 tests pass

## Tensions

- Massive migration: every class in ~13878 LOC codebase.
- Bootstrap complexity: seed compiler uses old syntax, new compiler must compile itself with new syntax.
- Phase A resolved by supporting both syntaxes; seed now handles both.
