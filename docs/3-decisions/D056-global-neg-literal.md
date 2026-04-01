---
id: D056
title: Fix global variable initialization with negative literals
status: implemented
depends-on: []
---

## Decision

Add constant-folding for negative numeric literals (`-INT_LIT`, `-DOUBLE_LIT`) in `genGlobalVar()`, so that `let x = -1` and `let y = -3.14` at global scope correctly produce `global i32 -1` and `global double -3.14` in LLVM IR.

## Reasoning

The parser treats `-1` as `UNARY(Neg, INT_LIT(1))`, which is correct. But `genGlobalVar` only recognized top-level `INT_LIT` / `DOUBLE_LIT` / `STRING_LIT` / `TRUE_LIT` / `FALSE_LIT` for compile-time constant initialization. Any other expression (including `UNARY`) fell into the runtime-init path, which:

1. Declared the global as `global ptr null` (wrong type)
2. Queued it for runtime initialization in `emitGlobalInits()`
3. `emitGlobalInits()` hardcoded `store ptr` regardless of actual type
4. Even though `inferType()` correctly returned `"int"`, the guard `realType != "int"` explicitly prevented type correction

This forced the workaround: initialize to 0, then assign the real value inside a function.

## Fix

Two new cases in `genGlobalVar()` before the else branch:
- `UNARY + Neg + INT_LIT` → `global i32 -N, align 4`, type = "int"
- `UNARY + Neg + DOUBLE_LIT` → `global double -N, align 8`, type = "double"

One-line pattern: constant-fold the negation at compile time, matching the existing literal handling pattern.

## Rejected Alternatives

- **Fix the else branch to handle int-typed expressions generically**: Would require also fixing `emitGlobalInits()` to emit type-correct stores. More invasive, and global variables with complex int expressions (function calls returning int) would still need runtime init anyway.

## Tensions

- P4a (compiler limitation is a bug): This was exactly the pattern P4a warns about — a compiler limitation forcing ugly workarounds.
