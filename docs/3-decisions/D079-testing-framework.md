# D079: Testing Framework

**Status:** Done
**Depends on:** D073 (try/catch), arrow functions (closures)

## Decision

Add a built-in `test("name", callback)` function for Jest/Deno-style testing. `test()` is handled specially by the compiler (like `println`), wrapping each callback in try/catch with automatic pass/fail tracking and summary reporting.

## Syntax

```simplescript
import { assertEqual, assertTrue } from "@/lib/test"

function main() {
    test("addition works", (): void => {
        assertEqual(1 + 1, 2)
    })

    test("string equality", (): void => {
        assertEqual("hello", "hello")
    })
}
```

Output:
```
  PASS: addition works
  PASS: string equality

Tests: 2 passed, 0 failed, 2 total
```

## Implementation

### Compiler (gen_calls.ss)
- `genTestCall(argList)`: Recognized in `genCall()` when `callee == "test"`, generates inline:
  1. Increment `@ss_test_total`
  2. Push exception depth (setjmp pattern from genTryCatch)
  3. Call callback with closure/direct dispatch (tag bit check)
  4. On success: `emitExcDepthDec()`, increment `@ss_test_passed`, print "  PASS: name"
  5. On catch: `emitExcDepthDec()`, increment `@ss_test_failed`, print "  FAIL: name - error"

### Runtime (gen_runtime.ss)
- Globals: `@ss_test_total`, `@ss_test_passed`, `@ss_test_failed`
- String constants: `@.rt.str.test_pass`, `@.rt.str.test_fail`, `@.rt.str.test_sep`, `@.rt.str.test_summary1`, etc.
- `@ss_test_summary`: atexit handler — if `total > 0`, prints summary line, exits 1 if any failures

### Registry (gen_registry.ss, checker.ss)
- `funcRetTypes.set("test", "void")` — registered as void builtin
- Checker: added to `voidFns` list and `twoArgFns` list (exactly 2 args)

### Main setup (gen_decls.ss)
- `atexit(@ss_test_summary)` registered in main() alongside existing RC cleanup

### Assertion library (lib/test.ss)
- `assertEqual(actual, expected)` — overloaded for int, string, double
- `assertTrue(value)`, `assertFalse(value)`
- `assertNull(value)`, `assertNotNull(value)` — string type only
- All assertions throw on failure, caught by test() wrapper

## Design Rationale

- **`test` is not a keyword** — it's a function name, recognized specially in genCall() like println
- **No new syntax needed** — `test("name", () => { ... })` is standard Jest/Vitest/Bun syntax
- **Inline try/catch** — each test() call generates its own setjmp wrapper, avoiding need for a runtime function that calls arbitrary function pointers
- **atexit for summary** — prints results after main() returns, handles early exit correctly
- **Assertions use throw()** — leverages existing D073 exception system

## Rejected Alternatives
- **`test` keyword (Zig style)**: Requires new keyword, no TS/JS equivalent
- **Naming convention (Go style)**: No descriptive test names, fragile
- **Runtime function for test runner**: Would need function pointer calling logic in generated LLVM IR runtime function; inline approach is simpler

## Known Limitations
- `assertNull`/`assertNotNull` only accept string type (no generics for nullable class instances yet)
- `assertEqual` for double uses exact comparison (standard, but users need `assertAlmostEqual` for float math)
- Test framework globals/summary included in all binaries (consistent with existing runtime pattern)
