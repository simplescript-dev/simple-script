# D067: Null Safety Design — Kotlin/Dart Style, No Escape Hatch

**Status**: Phase 3 Implemented (Complete)
**Depends-on**: D053 (type checking), D033 (`?.` `??` operators), D058 (optional method fix)
**Related**: I002 (string-based type system), spec/43

## Decision

SimpleScript adopts **Kotlin/Dart style null safety**: default non-null types, `T?` for nullable, smart narrowing via control flow analysis, **no `!` escape hatch**.

## Background & Motivation

### The Problem

SimpleScript compiles to native binary via LLVM IR. A null pointer dereference = **segfault** — no stack trace, no error message, process dies. This is categorically worse than TypeScript (V8 throws `TypeError`) or Kotlin (JVM throws `NullPointerException` with stack trace).

Current state: `null` is a keyword, compiles to LLVM `null` (pointer). Any `ptr`-typed variable can be null. The compiler performs **zero** nullability checking. This is a crash waiting to happen.

### Design Space Explored

| Approach | Languages | Null exists? | Escape hatch | Safety |
|----------|-----------|-------------|--------------|--------|
| `T?` + `!` assertion | TypeScript, Kotlin | Yes | `!` / `!!` | Medium |
| `Optional<T>` wrapper | Java 8+ | Yes (two systems) | `.get()` | Low |
| `Option<T>` enum + match | Rust, OCaml | **No null** | `.unwrap()` | High |
| `T?` + no escape | **This proposal** | Yes (controlled) | **None** | High |

### Rejected Alternatives

**Rust-style `Option<T>` + pattern matching**: Requires enum value types + pattern matching infra that SS doesn't have. Foreign syntax style — SS follows TS/Java conventions (D062). Rejected.

**TypeScript-style with `!` assertion**: `!` is widely abused in production TS code (reason `no-non-null-assertion` lint exists). For native binary output where null = segfault, escape hatches are too dangerous. Rejected.

**Java-style `Optional<T>`**: Two parallel null systems (raw null + Optional wrapper). Universally considered a half-measure. Rejected.

**C#-style warnings-only**: Not enforced at compile time, just warnings. Adoption data shows low effectiveness. Rejected.

## Design

### Core Rules

1. **Default non-null**: `let x: string = "hello"` — cannot assign null
2. **Nullable with `?`**: `let x: string? = null` — explicitly opted in
3. **No direct use of `T?` as `T`**: must narrow first
4. **No `!` operator**: no way to bypass the type system
5. **Smart narrowing**: `if (x != null)` automatically narrows `x` from `T?` to `T`

### Syntax (all TS/Java compatible)

```simplescript
// 1. Non-null by default
let name: string = "Alice"
name = null                        // COMPILE ERROR: cannot assign null to non-null type 'string'

// 2. Nullable types
let nick: string? = null           // OK
let nick: string? = "Bob"         // OK

// 3. Safe access (already implemented — D033)
let len = nick?.length             // type: int? (propagates nullability)

// 4. Null coalescing (already implemented)
let display = nick ?? "anonymous"  // type: string (unwrapped via default)

// 5. Smart narrowing — the ONLY way to "unwrap"
if (nick != null) {
    println(nick.length)           // OK: nick is string here, not string?
}

// 6. Narrowing in else branch
if (nick == null) {
    return                         // early return
}
println(nick.length)               // OK: nick narrowed to string after null-guard

// 7. Function signatures
function find(id: int): User? {
    if (id <= 0) { return null }
    return new User(id)
}

function greet(user: User) {       // non-null param
    println(user.name)
}

// 8. Calling with nullable
let u = find(1)                    // type: User?
greet(u)                           // COMPILE ERROR: User? not assignable to User
if (u != null) {
    greet(u)                       // OK: narrowed to User
}

// 9. Class fields
class Profile {
    name: string                   // non-null, must be set in constructor
    bio: string? = null            // nullable with default
}

// 10. Null coalescing for unwrap
let u = find(1) ?? new User(0)    // type: User (unwrapped)
greet(u)                          // OK
```

### What Already Works

| Feature | Status | Decision |
|---------|--------|----------|
| `null` keyword & literal | ✅ | lexer/parser/codegen |
| `?.` optional field access | ✅ | D033 |
| `?.` optional method call | ✅ | D033 + D058 (no double-eval) |
| `??` null coalescing | ✅ | D033 |
| `T?` type annotation parsing | ✅ | D067 Phase 1 |
| Compile-time null checking | ✅ | D067 Phase 1 |
| Smart narrowing | ✅ | D067 Phase 2 |
| `?.` returns `T?` type | ✅ | D067 Phase 3 |
| `??` returns `T` type | ✅ | D067 Phase 3 |

### What Needs Implementation

#### Phase 1: Checker-level null awareness

1. **`checkerInferType` returns nullable info**: When a type is `string?`, return `"string?"` (with `?` suffix). `NULL_LIT` returns `"null"` instead of `""`.

2. **Assignment checking**: In existing 8 type check sites (D053-D065), add null compatibility:
   - `null` assignable to `T?`, not to `T`
   - `T?` assignable to `T?`, not to `T`
   - `T` assignable to both `T` and `T?`

3. **Function param/return checking**: Existing CALL/RETURN check sites enforce nullability.

#### Phase 2: Smart narrowing

4. **Null guard tracking**: After `if (x != null)` in the then-branch, narrow `x` from `T?` to `T`. After `if (x == null) { return }`, narrow in subsequent code.

5. **Scope-based narrowing**: Narrowing only applies within the guarded scope. Re-assignment resets narrowing.

#### Phase 3: Operator propagation

6. **`?.` returns `T?`**: `obj?.field` where field is `T` returns `T?`.
7. **`??` returns `T`**: `expr ?? default` where expr is `T?` returns `T` (unwrapped).

### Type Compatibility Matrix

| Source → Target | `T` | `T?` |
|----------------|-----|------|
| `T` value | ✅ | ✅ |
| `T?` value | ❌ (must narrow) | ✅ |
| `null` literal | ❌ | ✅ |

### Interaction with I002 (String-based Type System)

Current type system uses raw strings. Nullable types add a `?` suffix: `"string?"`, `"User?"`, `"Array<int>?"`. This is a minimal extension:
- `isNullable(type)`: check if type ends with `?`
- `baseType(type)`: strip trailing `?`
- `makeNullable(type)`: append `?`

Not ideal (I002 proposes structured types), but workable within current constraints. When I002 is resolved, nullable becomes a proper flag on the type structure.

### Codegen Implications

- `null` remains LLVM `null` pointer
- Non-null types: no codegen change (compiler trusts checker)
- Nullable types: no special codegen — all ptr values can be null at LLVM level
- Safety is enforced **entirely at compile time** by the checker
- Existing `?.` and `??` codegen unchanged

## Research References

| Language | Approach | Verdict |
|----------|----------|---------|
| **Kotlin** | `T?` + `!!` + smart cast | Best-in-class. `!!` is only weakness. |
| **Dart** | `T?` + flow analysis + `late` | Sound null safety since 3.0. `late` is escape hatch. |
| **Swift** | `T?` + `if let` + `guard let` + `!` | Strict but verbose. `!` (force unwrap) is escape hatch. |
| **C#** | `T?` + warnings | Not enforced. Low adoption. |
| **TypeScript** | `strictNullChecks` + `!` + `any` | Too many escape hatches. |

SS takes the strictest position: Kotlin's smart narrowing + Dart's soundness, minus ALL escape hatches.

## Migration Impact

### Compiler source (bootstrap/)

The compiler uses Map-based AST (no class instances except via `new Map()` etc.). Global variables initialized to `ptr null` will need `?` annotations or restructuring. This is a bootstrap concern — can be handled incrementally.

### Existing user code

- Code that never uses `null` → no change needed
- Code using `null` without `?` annotations → compile errors (intentional — surfaces bugs)
- `?.` and `??` usage → already correct, no change
