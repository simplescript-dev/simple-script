# D070: Static Methods

**Status:** Done
**Depends on:** D068 (access modifiers), class system

## Decision

Add `static` keyword for class methods. Static methods belong to the class itself, not instances. They have no `this` parameter and are called via `ClassName.method()`.

## Syntax

```typescript
class MathUtils {
    static function max(a: int, b: int): int {
        if (a > b) { return a }
        return b
    }

    static function create(): MathUtils {
        return new MathUtils()
    }
}

let m = MathUtils.max(10, 20)
let obj = MathUtils.create()
```

## Semantics

- `static function name(...)` — Declares a static method (no `this` parameter)
- Static methods called via `ClassName.method(args)`, not on instances
- `this` and `super` are compile-time errors inside static methods
- Combinable with access modifiers: `private static function ...`, `protected static function ...`
- Order: `[access] [static] function name(...)`
- Static methods can create instances (`new ClassName(...)`) and call other static methods

## Implementation

- **Lexer**: `static` keyword → `STATIC` token
- **Parser**: Detect `STATIC` after access modifiers in class body, mark `I2=1` on FUNC_DECL node
- **Checker**: `staticMethods` Map (`"ClassName.methodName" → "1"`). `currentStaticMethod` flag tracks context. THIS/SUPER nodes error when flag is set.
- **Codegen**: `genClassMethod()` skips `this` parameter and `this` alloca when `nGetI2(id)==1`. `genMethodCall()` existing `ClassName.method()` detection (line 296) routes to `genStaticMethodCall()` which already omits `this`.

## AST

- FUNC_DECL: I2=1 if static (orthogonal to I3 access level)

## Rejected Alternatives

- **Static fields**: Deferred. Would need global variable semantics per class. Static methods are the common use case.
- **Calling static methods on instances** (`obj.staticMethod()`): Rejected per TS semantics. Static methods are class-level only.
- **`static` as field modifier**: Deferred. Fields need different storage (globals vs struct offsets).
