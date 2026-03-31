# D012: Checker Method/Constructor Argument Count (I003 Phase 3 Partial)

## Status
firm

## Resolves
I003 Phase 3 (partial) — METHOD_CALL and NEW_EXPR argument count checking. Function call arg count was already checked (D003); this extends coverage to class constructors and method calls.

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P8 (study before designing — Go/Rust compiler approach)
- principles.md → P9 (complexity in compiler, not user code — better errors)
- D003 (checker param count — established min/max pattern for function calls)
- D009 (checker error display — `checkerError` format reused)
- D010 (error collection — multiple errors shown)

## Decision
Register class constructor and method parameter counts during checker Pass 1. Check argument counts at NEW_EXPR and METHOD_CALL sites with receiver class resolution.

**Constructor params**: Each CLASS_DECL's PARAM list stores own fields. `totalConstructorParams()` walks the `checkerClassParents` chain to sum own + inherited field counts, matching codegen's `resolveInheritance()` behavior.

**Method param lookup**: `lookupMethodParams(className, methodName)` walks the parent chain (like codegen's method resolution) to find the method's min/max param counts. Handles method inheritance.

**Receiver class resolution** (3 cases, zero false positives):
1. `this.method()` — `currentCheckerClass` set when entering CLASS_DECL method bodies
2. `variable.method()` — `lookupVar` returns type annotation or inferred class name (from NEW_EXPR initializer)
3. `new ClassName().method()` — class name from NEW_EXPR S1

**Built-in registration**: Map (7 methods) and Math (12 methods) registered in `initChecker()` with known param counts. `checkArgCount(label, name, argCount, min, max, line, col)` unified helper for all 3 check sites (CALL, NEW_EXPR, METHOD_CALL).

## Key Reasoning (3 sentences max)
Extending D003's function arg count checking to constructors and methods catches a class of bugs that previously compiled silently but crashed at runtime. Receiver class resolution limited to statically-determinable cases (this, typed vars, new expr) ensures zero false positives without requiring full type inference. Inheritance-aware param accumulation for constructors and method lookup mirrors codegen behavior.

## Rejected Alternatives
- ✗ **Full type inference in checker**: Would require moving `inferType`/`resolveObjClass` from codegen to checker — that's I003 Phase 4, blocked by I002. Current approach handles the most common cases without it.
- ✗ **Built-in method checking by method name only (type-agnostic)**: Would cause false positives when user classes shadow built-in method names (e.g., a class with a custom `length(n)` method). Only check when receiver class is known.
- ✗ **Precomputing inherited constructor params**: Requires topological sort of class hierarchy or careful ordering. Just-in-time `totalConstructorParams()` chain walk is simpler and equally fast for typical 2-3 level hierarchies.
- ✗ **Unified classConsMin/methodParamMin Maps**: Constructor params must not walk parent chain (each class stores own params), while method params must walk. Separate Maps keep the semantics clear.

## Interfaces With Other Decisions
- D003 (function param count): `checkArgCount` helper now shared across CALL, NEW_EXPR, and METHOD_CALL.
- D009 (error display): Same Rust-style format with `-->` and `^` caret.
- D010 (error collection): Multiple constructor/method errors collected in one compilation.
- I003 Phase 4 (inferType migration): When inferType moves to checker, receiver resolution can cover all METHOD_CALL cases, not just the 3 statically-determinable ones.

## Open Tensions
- Receiver resolution limited to 3 cases. Chain calls like `getObj().method()` unchecked until Phase 4.
- `classConsMin.has()` used as proxy for "is known class" — works but semantic mismatch. A dedicated `knownClasses` Map would be cleaner.

## Notes
New infrastructure: `classConsMin`/`classConsMax` Maps for constructor params, `methodParamMin`/`methodParamMax` for method params, `checkerClassParents` for inheritance chain, `currentCheckerClass` for `this` resolution. Helper functions: `countParamRange`, `totalConstructorParams`, `lookupMethodParams`, `registerMethodParams`, `checkArgCount`.

Output format (same as D003/D009):
```
error: constructor 'Dog' expects 2 arguments, got 1
 --> line 8:29
  |
8 |     const d = new Dog("Rex")
  |                             ^
```

Changes: checker.ss (+95 net lines: 6 globals, 5 functions, 3 check sites in checkExpr, Pass 1 class registration, VAR_DECL type inference). All 56 tests pass, bootstrap 3-stage fixed-point verified.
