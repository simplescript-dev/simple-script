---
id: D055
title: Support this.field = value in class methods
status: implemented
depends-on: [D017]
date: 2026-04-01
---

## Decision

Route `THIS` token through `parseAssignOrExpr()` in `parseStmt()`, enabling `this.field = value` assignment syntax inside class methods.

## Reasoning

Previously, `parseStmt()` only entered the assignment-detection path for `IDENT` tokens. When a statement started with `this`, it fell through to the generic expression path which created an `EXPR_STMT` — ignoring any assignment operator that followed. This forced users to write `let self = this; self.field = value` as a workaround.

Per P4a (compiler limitation is a bug, not a boundary), this should be fixed rather than documented as a known limitation.

## Implementation

One-line change in `parse_stmts.ss`:

```
// Before
if (k == "IDENT") { return parseAssignOrExpr() }

// After
if (k == "IDENT" || k == "THIS") { return parseAssignOrExpr() }
```

When `THIS` enters `parseAssignOrExpr()`:
- Early fast-paths (LBRACKET, ASSIGN, compound assign, ++/--) check `nextTok` — for `this.field` the next token is DOT, so all skip
- Falls through to the general expression path (line 498): `parseExpr()` produces `MEMBER_ACCESS(THIS, "field")`
- Assignment operator detection creates `MEMBER_ASSIGN` node correctly
- All downstream stages (checker, PIR, codegen) already handle THIS in MEMBER_ASSIGN

## Rejected Alternatives

1. **Duplicate member-assign detection in fallback path**: Would duplicate the logic from `parseAssignOrExpr()`. Unnecessary since routing THIS there works cleanly.
2. **Rewrite parseAssignOrExpr to accept any expression start**: Over-engineering for this specific case.

## Supported Patterns

- `this.field = value` (simple assignment)
- `this.field += value` (compound assignment: +=, -=, *=, /=, %=, **=)
- `this.a.b = value` (nested field assignment)

## Test

`tests/phase5/this_field_assign.ss` — Counter class (increment/decrement/reset/rename) + Player class (takeDamage/heal/setWeapon/upgradeWeapon with nested field).
