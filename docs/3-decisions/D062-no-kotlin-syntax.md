# D062: Syntax Reference Priority — Java/TS, Not Kotlin

**Status**: Active (permanent guideline)
**Depends-on**: None

## Decision

When designing SimpleScript syntax, prioritize borrowing from **Java** and **TypeScript/JavaScript**. Do NOT borrow from Kotlin or Scala syntax patterns.

## Reasoning

- SS targets TS/JS developers. Kotlin syntax (primary constructors, `val/var` in params, colon-based inheritance) is unfamiliar and creates confusion.
- `class Foo(x: int)` (Kotlin primary constructor) was adopted early but proven problematic — `extends Parent(fields)` is ambiguous.
- Java and TS are the two largest language communities. Syntax familiarity reduces learning curve.

## Concrete Rules

1. Class fields: in body (Java/TS), not in constructor params (Kotlin)
2. Inheritance: `extends Parent` (Java/TS), not `: Parent` (Kotlin)
3. Variable declarations: `const/let` (TS), not `val/var` (Kotlin)
4. No data class / sealed class / companion object syntax borrowing
5. When in doubt, check "how does TypeScript do this?" first, then Java
