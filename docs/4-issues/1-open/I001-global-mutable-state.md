---
id: I001
title: Global mutable state explosion — 55+ global lets
severity: high
related-decisions: [D004]
related-principles: [P10]
origin: design-improvements.md DI-2
---
## Description
codegen.ss has 30+ global let variables, gen_exprs.ss 10+, gen_stmts.ss 10+, parser.ss 9 AST Maps. All functions directly read/write global state.

`resetCodegen()` has already missed variable resets (design-issues #13, fixed by resetting guard flags and adding 20+ missing vars).

## Impact
- Changing one global variable's structure requires grepping all files for usage
- Cannot test any function in isolation
- Parallel compilation impossible
- New features risk depending on stale state
- Every new global variable must be manually added to `resetCodegen()` — easy to forget

## Best Practices
- **Go compiler**: `ssagen.state` struct encapsulates all codegen state
- **Rust compiler**: `TyCtxt` context object threaded through entire compilation
- **Zig compiler**: `Compilation` struct holds all state

## Proposed Solution
> ⚠️ **Blocked**: SS has no `struct` — global Map is the only state aggregation mechanism.
>
> **Short-term**: Group related global variables into Map objects (e.g., `rcState`, `codegenCtx`) to reduce bare global count. D004 already did this for RC state (7 globals → gen_rc.ss with initRcState()).
>
> **Long-term**: After SS supports `struct`, upgrade Map groups to struct instances.

## Context
Files: codegen.ss (30+), gen_exprs.ss (10+), gen_stmts.ss (10+), parser.ss (9 AST Maps).
