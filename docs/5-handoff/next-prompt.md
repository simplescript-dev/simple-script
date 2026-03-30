# Next Task

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~8800 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Context
I003 Phase 2 (return path analysis) complete + checker integrated into compile pipeline (D007). All tests pass + bootstrap fixed-point verified.

### Recent Changes (D007)
- checker.ss: `blockAlwaysReturns`/`stmtAlwaysReturns` + Pass 1 registers global vars/classes/enums
- main.ss: `check(root)` added to `compile()` — checker runs on every `ss build`
- checker.ss: builtins list synced with codegen, fn-pointer calls allowed, Math namespace registered

## Task
1. **Pick next priority** from open issues: I001 (global mutable state), I002 (string-based type system), I003 Phase 3-4 (type checking, inferType migration), I004 (weak error reporting), I005 (AST list as string), I006 (runtime raw IR), I008 (parser no precedence table)
2. **Analyze + implement + verify** the chosen issue in one go

## Decision Criteria for Next Priority
- Impact on correctness > impact on maintainability > impact on developer experience
- Issues that block future features rank higher
- Issues with existing partial implementations rank higher

## Watch Out For
- C1: Every change must pass test + bootstrap
- P1: Test before modify
- V6: Minimal change — one issue at a time
