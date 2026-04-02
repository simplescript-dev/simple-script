# D061: Class Fields in Body (TS-style)

**Status**: Planned
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

## Tensions

- Massive migration: every class in ~13878 LOC codebase.
- Bootstrap complexity: seed compiler uses old syntax, new compiler must compile itself with new syntax.
- Need careful phased approach: support both syntaxes temporarily during bootstrap transition.
