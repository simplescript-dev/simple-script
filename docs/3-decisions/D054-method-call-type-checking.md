# D054: METHOD_CALL Argument Type Checking

**Status:** Accepted
**Depends-on:** D053 (Checker type inference), D012 (Arg count)

## Decision

Extend the checker to type-check METHOD_CALL arguments against declared parameter types, and enable method return type inference for chain call resolution.

## Reasoning

D053 added type checking for CALL arguments but skipped METHOD_CALL (needed method param/return type tracking). This completes I003 Phase 3 by covering the remaining type check site.

## Implementation

### Method type storage — checker.ss first pass

- `methodParamTypes` map: `"ClassName.methodName:paramIndex"` → type string
- `methodRetTypes` map: `"ClassName.methodName"` → return type string
- Populated during CLASS_DECL first pass for non-generic classes (classTypeParams == "")
- Generic classes excluded (type params like "T" are not concrete types)

### Parent chain lookup — checker.ss

- `lookupMethodParamType(className, methodName, paramIndex)`: walks `checkerClassParents` chain to find inherited method param types
- `lookupMethodRetType(className, methodName)`: walks parent chain for method return types

### METHOD_CALL type inference — checker.ss

- `checkerInferType(METHOD_CALL)`: resolves receiver class via `inferCheckerClass`, looks up method return type via `lookupMethodRetType`. Returns "" for unknown (type check skipped).
- `inferCheckerClass(METHOD_CALL)`: same logic, enables chain call resolution (e.g., `a.getB().getC()` resolves B's type, then C's)

### METHOD_CALL argument type checking — check_stmts.ss

After existing receiver resolution and arg count check:
- Skip if receiver class unknown, or spread args present
- For each positional argument, look up expected param type via `lookupMethodParamType`
- Compare against actual type from `checkerInferType`
- Report error if `isTypeCompatible` returns false

## Coverage

| Site | Status |
|------|--------|
| `obj.method(wrongType)` | Checked (when receiver class resolved) |
| `this.method(wrongType)` | Checked (currentCheckerClass) |
| `new Foo().method(wrongType)` | Checked (class from NEW_EXPR) |
| `a.getB().method(wrongType)` | Checked (chain via METHOD_CALL inference) |
| Inherited methods | Checked (parent chain walk) |
| Generic class methods | Skipped (no false positives) |
| Builtin methods (Map/Array) | Skipped (no param types registered) |

## Rejected Alternatives

- **Register builtin method param types**: Map.set, Array.push etc. would need manual type registration for each method. Deferred — no false positives from skipping.
- **Full receiver resolution via inferCheckerClass**: Could replace the 3-case IDENT/THIS/NEW_EXPR check with a single `inferCheckerClass` call. Deferred — current resolution is sufficient and well-tested.

## Tensions

- **Receiver resolution gap**: Variables with generic type annotations (e.g., `let box: Box<int>`) don't resolve receiver class because `classConsMin.has("Box<int>")` is 0. Same pre-existing limitation as arg count checking.
