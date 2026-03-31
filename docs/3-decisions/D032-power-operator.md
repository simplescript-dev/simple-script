# D032: Exponentiation Operator `**`

**Status:** Implemented
**Depends on:** None (builds on existing lexer/parser/runtime infrastructure)

## Decision

Complete the `**` exponentiation operator implementation. The lexer (`POWER` token) and parser (`parsePower` with right-associativity) already existed. This decision adds codegen support, `**=` compound assignment, and `**` inside template expressions.

```simplescript
const a = 2 ** 10        // 1024
const b = 2 ** 3 ** 2    // 512 (right-associative: 2 ** (3 ** 2))
const c = 4 ** 0.5       // 2.0 (double result when either operand is double)
let x = 3
x **= 4                  // 81
```

## Syntax

```
expr ** expr              // exponentiation (right-associative)
variable **= expr        // compound assignment
obj.field **= expr       // member compound assignment
```

## Reasoning

1. **TypeScript compatibility (V1):** `**` is standard ES2016+ / TypeScript. `**=` is standard ES2016+ compound assignment.
2. **No new keywords:** Pure operator addition, no syntax invention.
3. **Right-associative:** Matches JS/TS semantics: `2 ** 3 ** 2 === 2 ** 9 === 512`.
4. **Type semantics:** `int ** int → int`, `double ** any → double`, `any ** double → double`. Consistent with how other arithmetic operators handle int/double promotion.

## Implementation

| Component | File | Change |
|-----------|------|--------|
| Lexer: `**` token | lex_ops.ss | Already existed (`lexStar`) |
| Lexer: `**=` token | lex_ops.ss | Added `POWER_ASSIGN` in `lexStar` |
| Lexer: `**` in templates | lexer.ss | Changed template inner loop to call `lexStar()` |
| Parser: `parsePower()` | parse_exprs.ss | Already existed (right-recursive) |
| Parser: `**=` | parse_stmts.ss | Added `POWER_ASSIGN` to both compound assign checks |
| Codegen: `genBinary` Pow | gen_exprs.ss | Convert to double → `@ss_pow` → convert back if int |
| Codegen: `**=` assign | gen_assigns.ss | New `POWER_ASSIGN` branch in `genAssign` + `genMemberAssign` |
| Runtime: `@ss_pow` | gen_rt_io.ss | Already existed (wraps libc `pow`) |
| Type inference | gen_types.ss | No change needed (generic numeric path works) |

## Rejected Alternatives

- **Integer-only pow loop:** Could avoid double conversion for `int ** int`, but adds complexity for negligible benefit. The `pow()` path handles all cases correctly.
- **LLVM `llvm.powi` intrinsic:** Only handles `double ** i32`. Using `@ss_pow` (wrapping libc `pow`) is simpler and handles all cases uniformly.
