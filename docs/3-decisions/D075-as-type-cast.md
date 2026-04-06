# D075: `as` Type Casting Operator

**Status**: Done
**Depends-on**: D074 (instanceof)

## Decision

Add TypeScript-style `as` operator for runtime-checked type casting: `expr as ClassName`.

**Syntax**: `expr as ClassName` (comparison precedence, same level as `instanceof`)
**Semantics**: Runtime-checked downcast via `ss_isinstance`. Returns same pointer if type matches. Throws error if cast fails (catchable via try/catch).

## Reasoning

With `instanceof` (D074) done, users can check types but can't access subclass-specific members. The `as` operator completes the "type-safe downcasting" pattern:

```ss
if (animal instanceof Dog) {
    let dog = animal as Dog
    dog.bark()  // access subclass method
}
```

- **TypeScript syntax**: `as` is a standard TS keyword
- **Java-style runtime check**: Unlike TS's compile-time-only assertion, SS checks at runtime via `ss_isinstance` (safe for native code)
- **No unsafe casts**: Failed cast throws, never returns wrong type

## Implementation

~20 lines across 6 files:

1. **lexer.ss**: `AS` keyword token
2. **parse_exprs.ss**: `parseComparison()` handles `AS` like `INSTANCEOF` — BINARY node S1="As"
3. **check_stmts.ss**: Validates right side is known class (merged with instanceof handler)
4. **checker.ss**: `checkerInferType(BINARY "As")` returns target class name
5. **gen_exprs.ss**: `genBinary("As")` — calls `ss_isinstance`, branches to throw on failure, returns same pointer on success
6. **gen_types.ss**: `inferType("As")` + `resolveObjClass(BINARY "As")` return target class name

### AST

BINARY node: S1="As", I1=expression, I2=IDENT(ClassName)

### Codegen

```llvm
%obj = <genExpr(left)>
%check = call i32 @ss_isinstance(ptr %obj, ptr @"ClassName")
%ok = icmp eq i32 %check, 1
br i1 %ok, label %cast.ok, label %cast.fail
cast.fail:
  call void @ss_throw(ptr @"type cast failed: expected ClassName")
  unreachable
cast.ok:
  ; use %obj with ClassName type tracking
```

## Rejected Alternatives

- **Implicit narrowing after instanceof**: More complex (requires flow-sensitive type tracking in codegen), can be added later as enhancement
- **`as?` safe cast (returns null)**: Kotlin syntax, deferred — users can use try/catch or instanceof + as pattern
- **Java-style `(Type) expr` syntax**: Not TypeScript syntax

## Interfaces

- **User syntax**: `expr as ClassName`
- **Error on failure**: `"type cast failed: expected ClassName"` (catchable via try/catch)
- **Type inference**: Result type is the target class name

## Tensions

- **New keyword**: `as` is a new keyword, but it's a standard TypeScript keyword and cannot be expressed with existing keywords
