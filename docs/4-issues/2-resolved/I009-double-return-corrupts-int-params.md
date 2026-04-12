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

## Root Cause

`resolveCallArgs()` in gen_calls.ss used a blanket `expectsDouble` flag based on the function's **return type**. When return type was `double`, ALL int arguments were promoted via `sitofp i32 → double`. This created a type mismatch: the `define` declared `i32` params but the `call` site passed `double` values. LLVM interpreted the double bit pattern as i32, producing garbage.

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

## Resolution

Added `funcParamTypes` registry (`"funcName:paramIndex" → SS type`) in gen_registry.ss. Replaced the blanket `expectsDouble` flag with per-parameter type lookup: only promote int→double when the callee's declared parameter type is `double`, not based on return type. Generic specializations register resolved param types before the call.

**Files changed:** gen_registry.ss, codegen.ss (registerFuncDeclNode), gen_calls.ss (resolveCallArgs, genGenericCall, genCall)
**Test:** tests/phase5/double_return.ss — 4 cases (single int, two ints, mixed string+int, double params with int literals)
**Verified:** 185/190 tests pass (5 pre-existing interp_* failures), bootstrap fixed-point verified.

## Impact

- `interpAsDouble` in interp.ss was the only affected function in the codebase
- Workaround applied in D087 Phase 1e, all tests pass
- Any future function with signature `(param: int): double` now works correctly
