# D007: Return Path Analysis + Checker Pipeline Integration

## Status
firm

## Resolves
I003 Phase 2 — Non-void functions with missing return produce LLVM garbage values silently.

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P8 (catch errors at compile time)
- D003 (checker infrastructure: scope chain, param count)

## Decision
Added return path analysis to checker.ss: `blockAlwaysReturns`/`stmtAlwaysReturns` recursively walk AST to verify non-void functions return on all control paths. Handles IF+ELSE, TRY+CATCH, SWITCH+DEFAULT, THROW, and exit() as noreturn. Also integrated checker into `compile()` pipeline so it runs on every `ss build`, not just `ss check`.

## Key Reasoning (3 sentences max)
Missing return in non-void functions was the highest-impact correctness bug — silent garbage values with no compile-time warning. Integration into compile pipeline was necessary because a checker that only runs on explicit `ss check` doesn't protect users. Required fixing 4 checker limitations (forward refs, fn-pointers, builtins sync, Math namespace) exposed by running on prelude + full codebase.

## Rejected Alternatives
- ✗ **Keep checker as separate `ss check` only**: Users must explicitly run it — most won't. Bugs slip through to runtime. Violates P8.
- ✗ **Treat `exit()` like any other call (not noreturn)**: Would require dummy `return` after every `exit(1)` in the codebase. Impractical — `exit()` is used extensively in error paths throughout the bootstrap compiler.
- ✗ **Analyze loops (while/for) as always-returning**: Loop body may not execute (condition false on first check). Would produce false negatives.

## Interfaces With Other Decisions
- D003 (checker param count): Shares the checker infrastructure. Forward reference fix (Pass 1 registering global vars/classes/enums) benefits both param checking and return path analysis.
- I003 Phase 3-4 (future): Return path analysis is prerequisite for type checking — establishes that the checker can handle full codebase analysis including prelude.

## Open Tensions
None currently.

## Notes
Checker grew from ~540 to 621 lines. 6 manual test scenarios verified: if/else, fallback return, void func, missing else, try/catch, exit()-as-noreturn. Bootstrap 3-stage fixed-point verified. Completed 2026-03-30.
