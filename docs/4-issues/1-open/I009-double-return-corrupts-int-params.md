# I009: Functions returning double corrupt int parameters

**Severity:** MEDIUM
**Discovered:** D087 Phase 1e (interpreter double comparison)
**Workaround:** Avoid `(int): double` function signatures; use `(int): string` + `parseDouble()` instead

## Problem

When a function has return type `double` and takes `int` parameters, the int parameter values are corrupted at the call site. The int value received by the callee is garbage (e.g., passing 1 produces 5526601).

## Reproduction

```simplescript
function getId(id: int): double {
    println(`id=${id}`)        // prints garbage, not 1
    return parseDouble("5")
}
function main() {
    let r = getId(1)           // id receives corrupted value
}
```

Functions with `(int): int` or `(int): string` signatures work correctly. The bug is specific to the `(int): double` return type combination.

## Root Cause (suspected)

Likely a calling convention issue in codegen — the LLVM IR generated for functions returning `double` may be using incorrect register allocation or stack layout for i32 parameters.

## Workaround

Replace `interpAsDouble(id)` pattern:
```
// BAD: (int): double signature
function interpAsDouble(id: int): double {
    return parseDouble(interpVD.getString(`${id}`))
}

// GOOD: split into (int): string + parseDouble
parseDouble(interpAsStr(id))
```

## Impact

- `interpAsDouble` in interp.ss was the only affected function in the codebase
- Workaround applied in D087 Phase 1e, all tests pass
- Any future function with signature `(param: int): double` would hit this bug
