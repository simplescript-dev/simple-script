---
id: D007
title: Return path analysis + checker integration into compile pipeline
date: 2026-03-30
status: firm
related-issues: [I003]
---
## Decision
Added return path analysis to checker.ss (I003 Phase 2) and integrated checker into the `compile()` pipeline so it runs on every `ss build`.

## Key Design Choices

### Return path analysis
- `blockAlwaysReturns(blockId)` / `stmtAlwaysReturns(id)` — recursive AST walk
- Handles: RETURN, THROW, IF+ELSE (both branches), TRY+CATCH (both blocks), SWITCH+DEFAULT (all cases + default), exit() as noreturn
- FOR/WHILE/DO_WHILE never guarantee return (loop may not execute)
- Only checked for functions with non-empty, non-void return type annotation

### Checker integration into compile pipeline
- Added `check(root)` call in `compile()` function (main.ss)
- Previously checker only ran via `ss check` command, not during `ss build`
- Required several fixes to handle prelude + full codebase checking:
  - **Forward references**: Pass 1 now registers global VAR_DECL, CLASS_DECL, ENUM_DECL (not just FUNC_DECL)
  - **Function pointer calls**: CALL check now allows callee to be a variable (e.g., `callback: fn`)
  - **Variadic println/print**: param count set to 0-99 (genPrintCall concatenates args)
  - **Built-in namespaces**: Math registered as known identifier
  - **Builtins sync**: checker builtins list expanded to match codegen funcRetTypes

## Verification
- All tests pass + bootstrap fixed-point verified
- 6 manual test scenarios: if/else, fallback return, void func, missing else, try/catch, exit()-as-noreturn
