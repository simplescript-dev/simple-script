---
id: I001
title: Global mutable state explosion — 55+ global lets
severity: high
related-decisions: [D004, D014, D015]
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
> **Short-term**: Group related global variables into dedicated files with init functions. D004 did this for RC state (7 globals → gen_rc.ss with `initRcState()`). D014 did this for class state (11 globals → gen_class.ss with `initClassState()`). D015 did this for function registry (9 globals → gen_registry.ss with `initFuncRegistry()`). Remaining: IR output state (irBuf, strConsts, strCount, irOutFile, strOutFile), SSA counters (regCount, labelCount, varCounter), variable tracking (varTypes, varAliases, globalAliases), control flow (breakLabel, continueLabel, currentFunc, terminated), and misc (enumValues, annotatedRoutes) — ~15 globals in codegen.ss (320 lines, under V5 threshold).
>
> **Long-term**: After SS supports `struct`, upgrade Map groups to struct instances.

## Context
Files: codegen.ss (30+), gen_exprs.ss (10+), gen_stmts.ss (10+), parser.ss (9 AST Maps).
