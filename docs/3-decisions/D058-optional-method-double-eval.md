---
id: D058
title: Fix optional method call double evaluation
status: implemented
depends-on: [D033]
---

## Decision

Fix `genOptionalMethodCall` to avoid double evaluation of object expression in `obj?.method()`.

## Problem

`genOptionalMethodCall` evaluated the object expression twice:
1. `genExpr(objId)` for the null check
2. `genMethodCall(id)` internally called `genExpr(objId)` again

For expressions with side effects (e.g., `getBox()?.method()`), the function was called twice.

## Solution

Add `preObj: string = ""` default parameter to `genMethodCall`. When provided, skip `genExpr(objId)` and use the pre-evaluated value. `genOptionalMethodCall` passes its already-evaluated `objVal` via `genMethodCall(id, objVal)`.

Same pattern as `genOptionalMemberAccess` (D033), which avoids double evaluation by using `objVal` directly for field access.

## Changes

- `gen_methods.ss`: `genMethodCall(id: int)` → `genMethodCall(id: int, preObj: string = "")`
- `gen_methods.ss`: `genOptionalMethodCall` passes `objVal` to `genMethodCall`
- Static method check gated by `preObj == ""` (optional chain never targets static methods)

## Test

`tests/phase5/optional_method.ss`: Verifies single evaluation via call counter, null returns, and method args.
