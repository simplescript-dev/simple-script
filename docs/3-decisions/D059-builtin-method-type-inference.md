---
id: D059
status: implemented
depends-on: [D053, D054]
date: 2026-04-02
---

# D059: Builtin Method Type Inference in Checker

## Decision

Register return types and parameter types for all built-in methods (string, Array, Map, Set, Math) in the checker's `methodRetTypes` / `methodParamTypes`, enabling compile-time type inference for chain calls and type checking for built-in method arguments.

## Context

D053 added `checkerInferType()` and D054 added METHOD_CALL type checking, but only for user-defined class methods. Built-in methods (string, Array, Map, Set, Math) had parameter count validation but no return type or parameter type information in the checker. This meant:

- Chain calls like `str.split(",").join("-")` couldn't be type-checked (checker didn't know `split` returns Array)
- Assignment type checking failed for built-in method results
- `inferCheckerClass` couldn't resolve receiver class for chained built-in calls

## Changes

### 1. Pseudo-class registration
Register `"string"` and `"Array"` as pseudo-classes in `classConsMin`, alongside existing `Map`, `Set`, `Math`. This allows the checker's method dispatch to work for these types.

### 2. Method return types
Registered return types for ~60 built-in methods across 5 types:
- **string**: charAt→string, indexOf→int, split→Array<string>, trim→string, etc.
- **Array**: push→Array, includes→int, join→string, filter→Array, etc.
- **Map**: getString→string, has→int, keys→Array<string>, etc.
- **Set**: has→int, size→int, values→string
- **Math**: all trig/math→double, randomInt→int

### 3. String method parameter types
Registered parameter types for all string methods (e.g., charAt expects int, indexOf expects string, replace expects string+string).

### 4. `resolveCheckerClass` helper
Extracted repeated base-type fallback logic (4 occurrences) into a single `resolveCheckerClass()` function. Normalizes generic types for method dispatch (`Array<int>` → `Array`).

### 5. Simplified receiver resolution
Replaced 20+ line manual receiver dispatch in `check_stmts.ss` with `inferCheckerClass(objId)` + namespace fallback. Now also covers MEMBER_ACCESS and CALL receivers (previously missing).

### 6. Literal type inference
Added STRING_LIT/TEMPLATE_LIT → `"string"` and ARRAY_LIT → `"Array"` to `inferCheckerClass`, enabling type checking for literal chain calls like `"hello".split(",")`.

## Rejected Alternatives

- **Batch registration via split+loop for all methods**: Used for Math (25 methods, same return type) but not for others where methods have varying signatures. Per P13, explicit registration is clearer.
- **Full inferType migration (I003 Phase 4)**: Deferred. This change adds specific value (builtin method types) without the full migration scope.

## Tensions

- checker.ss grew to ~852 lines (from ~730) due to registration code. Acceptable as initialization-only code that runs once per compilation.
