# D084: Object Literal Syntax

**Status:** Done
**Depends on:** class system (existing)

## Background

Configuration file scenarios (e.g., `van.config.ss`) need concise object creation syntax. Previously only `new ClassName(named: args)` was available.

## Decision

### Object Literal: Type Annotation + `{ key: value }` Constructor Sugar

When a variable declaration has a type annotation, `= { k: v, ... }` is equivalent to `= new ClassName(k: v, ...)`.

```simplescript
class VanConfig {
    plugins: Array<fn>
    debug: bool
}

// These two are equivalent
const config: VanConfig = { plugins: [vanTailwindCSS()], debug: true }
const config = new VanConfig(plugins: [vanTailwindCSS()], debug: true)
```

Works with both `const` and `let`:

```simplescript
const x: Config = { ... }
let x: Config = { ... }
```

**Core rule: type context required.** `let x = { ... }` without annotation is a compile error.

## Implementation

Parser creates `OBJ_LITERAL` node (List = NAMED_ARG nodes). Checker and codegen rewrite it to `NEW_EXPR` (S1 = class name from type annotation). All existing constructor validation and code generation is reused — zero new codegen functions, zero new runtime functions.

| File | Change |
|------|--------|
| `parse_exprs.ss` | `parseAtom()`: LBRACE → `OBJ_LITERAL` with NAMED_ARG list |
| `check_stmts.ss` | VAR_DECL: rewrite OBJ_LITERAL → NEW_EXPR; checkExpr: error if no type context |
| `gen_decls.ss` | `genVarDecl()`: same rewrite (covers arrow function scope) |

Note: Checker skips arrow function bodies, so the codegen-level rewrite is needed to cover all scopes.

## Rejected Alternatives

### `{ k: v }` → Map instance
Values must be uniform type, no `.key` access, no compile-time field checking.

### `{ k: v }` → Anonymous class (compiler-generated type)
Requires structural type system for cross-function passing — fundamental change to SS's nominal type system. Cost far exceeds benefit.

### `export` keyword
Evaluated and deferred. Current import system is full-file inlining (`{ name }` in import is not filtered). `export` has no effect without symbol-level module resolution. Will revisit when module system is upgraded.

### `export default`
JS legacy from CommonJS → ESM migration. Not needed.

### Omitting `=` (`const config: VanConfig { ... }`)
Inconsistent with existing assignment syntax. Keeping `=` is clearer.
