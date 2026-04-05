# D069: Super Keyword for Parent Method Calls

**Status:** Done
**Depends on:** D068 (access modifiers), class inheritance (extends/override)

## Decision

Add `super` keyword to call parent class methods from overriding methods. `super.method(args)` bypasses vtable dispatch and calls the parent class's implementation directly.

## Syntax

```typescript
class Animal {
    name: string
    function speak(): string { return this.name }
}

class Dog extends Animal {
    override function speak(): string {
        return `${super.speak()} barks`  // calls Animal.speak()
    }
}
```

## Semantics

- `super.method(args)` — Call parent class's method implementation directly (static dispatch, no vtable)
- `super` can only be used inside class methods
- `super` requires the class to have a parent (`extends`)
- In multi-level inheritance, `super` always refers to the immediate parent (one level up)
- `super` accesses protected parent methods (allowed by D068 semantics)
- `super` cannot access private parent methods (blocked by D068 semantics)
- `super` is not supported as standalone expression or for field access — only `super.method()` form

## Implementation

~45 lines across 7 files:

### Lexer (lexer.ss)
- Added `"super"` → `"SUPER"` token in `keywordKind()`

### Parser (parse_exprs.ss)
- Added `SUPER` node creation in `parseAtom()` (same pattern as `THIS`)
- Postfix `.method()` handling in `parsePrimary()` naturally creates `METHOD_CALL` with `I1=SUPER`

### Checker (check_stmts.ss, checker.ss)
- `checkExpr(SUPER)`: Validates usage inside class method + class has parent
- `inferCheckerClass(SUPER)`: Returns parent class via `checkerClassParents`
- `checkerInferType(SUPER)`: Returns parent class name
- D068 access checks work unmodified: private → blocked, protected → allowed for subclass

### Codegen (gen_methods.ss, gen_exprs.ss, gen_types.ss, pir_lower.ss)
- `genExpr(SUPER)`: Same as `genThisExpr()` (loads `this` pointer — same object)
- `resolveObjClass(SUPER)`: Returns parent class via `classParents`
- `inferType(SUPER)`: Returns parent class name
- `genSuperMethodCall()`: New function — walks parent chain from parent to find method, builds args with `this`, always uses static dispatch `call @ParentClass_method()`
- `pirExtractRootVar(SUPER)`: Returns `"this"`

## Rejected Alternatives

1. **`super(args)` constructor delegation** — SS constructors are auto-generated from field declarations. No user-defined constructor body to delegate to.
2. **`super.field` field access** — Inherited fields are already accessible via `this.field`. No need for `super.field`.
3. **`super` as standalone expression** — No use case. Only `super.method()` form is needed.

## Tensions

- **C5 (no user-facing memory syntax)**: No tension — `super` is pure OOP, no memory management exposure.
- **"Don't add new keywords"**: `super` is standard Java/TS keyword, and no existing keyword can express "call parent method". Justified exception.
