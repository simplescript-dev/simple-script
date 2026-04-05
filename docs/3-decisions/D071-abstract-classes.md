# D071: Abstract Classes and Methods

**Status:** Done
**Depends-on:** D068 (access modifiers), D070 (static methods)

## Decision

Add `abstract` keyword for classes and methods, following TypeScript/Java semantics. Abstract classes cannot be instantiated. Abstract methods have no body and must be implemented by concrete subclasses.

## Syntax

```
abstract class Shape {
    name: string

    abstract function area(): double
    abstract function perimeter(): double

    function describe(): string {
        return this.name
    }
}

class Circle extends Shape {
    radius: double

    function area(): double {
        return 3.14159 * this.radius * this.radius
    }

    function perimeter(): double {
        return 2.0 * 3.14159 * this.radius
    }
}
```

Modifier order: `[private|protected] [abstract] function name(...)`. `abstract` and `static` are mutually exclusive. `private abstract` is invalid.

## Checker Rules

| Rule | Description | Error |
|------|-------------|-------|
| R1 | Cannot instantiate abstract class | `cannot create an instance of abstract class 'Shape'` |
| R2 | Non-abstract subclass must implement all inherited abstract methods | `class 'X' must implement abstract method 'Y' from 'Z'` |
| R3 | Abstract methods have no body | Handled by parser (skips body parsing) |
| R4 | Abstract method must be in abstract class | `abstract method 'X' can only be declared in an abstract class` |
| R5 | Private abstract is invalid | `'private' modifier cannot be used with 'abstract' modifier` |
| R6 | Static abstract is invalid | `'static' modifier cannot be used with 'abstract' modifier` |

## Implementation

### AST Encoding
- `CLASS_DECL.I1 = 1` for abstract class (I1 was unused)
- `FUNC_DECL.I4 = 1` for abstract method (overrides unused annotations slot)

### Parser
- `parsingAbstractMethod` global flag: when set, `parseFuncDecl()` skips body parsing
- Top-level: `abstract class ...` detected in `parseStmt()`
- Class body: `abstract function ...` detected after access modifiers, mutually exclusive with `static`

### Checker
- `abstractClasses` Map: `"ClassName" -> "1"`
- `abstractMethods` Map: `"ClassName.methodName" -> "1"`
- `classMethodNames` Map: `"ClassName" -> ",method1,method2,"` for R2 check
- `checkAbstractImpl()`: walks parent chain collecting abstract methods, verifies all implemented

### Codegen
- `abstractMethodsCG` Map: tracks abstract methods at codegen level
- `genClassMethod()`: early return for I4==1 (no body to generate)
- Vtable: abstract methods get `null` entry; concrete subclasses override with real implementations
- Abstract class still generates struct, constructor (for subclass use), TypeInfo, drop/clone

## Dispatch Model

SimpleScript has **vtable-based dispatch** for classes in inheritance hierarchies. Abstract methods get `null` vtable entries. Since abstract classes cannot be instantiated (R1), their vtable null entries are never accessed at runtime. Concrete subclasses always have non-null entries for all methods.

## Reasoning

- Completes the OOP model (extends + override + super + private + protected + static + abstract)
- Standard TypeScript/Java feature — no novel syntax
- Pure compile-time enforcement — no runtime overhead
- ~40 lines across 7 files (minimal change)

## Rejected Alternatives

- **Abstract fields**: Java doesn't have abstract fields; TS does but SS fields are constructor params. Deferred.
- **Virtual dispatch for calling abstract methods from parent concrete methods**: Would require generating bridge functions. Not needed — users call methods on concrete types.
