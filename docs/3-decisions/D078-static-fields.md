# D078: Static Fields

**Status:** Done
**Depends on:** D070 (static methods), D068 (access modifiers)

## Decision

Add static field declarations to classes. Syntax: `[private|protected] static [const] fieldName: Type [= value]`. Access via `ClassName.field`, not instance.

## Syntax

```simplescript
class Counter {
    static count: int = 0
    static const MAX: int = 1000
    private static total: int = 0

    static function getTotal(): int {
        return Counter.total
    }
}

Counter.count += 1
let c = Counter.count
```

## Implementation

### Parser (parser.ss)
- `isBodyFieldStart()`: Detects `STATIC [CONST] IDENT COLON/QUESTION` and `PRIVATE/PROTECTED STATIC ...`
- `parseBodyField()`: Handles `static` keyword after access modifiers, stores PARAM.I4=1

### AST
- PARAM node: I4=1 indicates static field (I4 was unused on PARAM nodes)
- Modifier order: `[private|protected] static [const] fieldName: Type`

### Checker (checker.ss, check_stmts.ss)
- `staticFields` Map: `"ClassName.fieldName" -> "1"`
- Static fields excluded from constructor param counting (`instanceParamList`)
- MEMBER_ACCESS: `ClassName.field` validated as static; `instance.staticField` rejected
- MEMBER_ASSIGN: Same validation + const check + type check
- Access modifiers (private/protected) enforced on static fields

### Codegen (gen_class.ss, gen_assigns.ss, gen_types.ss)
- Static fields emitted as global variables: `@ClassName_fieldName = global <type> <value>`
- Literal initializers (int, double, bool, string, negated) emitted directly
- Non-literal initializers queued and emitted in `emitStaticFieldInits()` at start of main()
- `genMemberAccess()`: Detects `staticFieldGlobals` key, loads from global
- `genStaticFieldAssign()`: Handles ASSIGN, compound (+=/-=/*=//=/%%=), and POWER_ASSIGN
- `inferType()` and `resolveObjClass()`: Check `staticFieldTypes` for type inference
- `checkerInferType()`: Resolves static field types for class-name-based access

### State Maps
- `staticFieldGlobals`: `"ClassName.fieldName" -> "@ClassName_fieldName"`
- `staticFieldTypes`: `"ClassName.fieldName" -> SS type`
- `sfPendingInits` + `sfInitExprs`: Deferred runtime init for non-literal defaults

## Checker Rules
1. `ClassName.field` only for static fields; non-static field via class name is error
2. `instance.staticField` is error (TypeScript semantics)
3. `static const` fields reject all assignments
4. Private/protected enforcement on static fields
5. Type checking on static field assignments

## Rejected Alternatives
- **Merge static fields into classFieldTypes**: Would confuse instance vs static field semantics in struct layout and constructor generation
- **Static field access via instance**: TypeScript rejects this; following TS semantics

## Tensions
- Static fields add more global state to the compiler — consistent with existing `staticMethods` pattern
- `genStaticFieldAssign` has compound assignment logic similar to `genMemberAssign` — per P13, direct code is preferred over premature abstraction since the storage targets differ (global vs GEP)
