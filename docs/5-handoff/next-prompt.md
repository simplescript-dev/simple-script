# Next Task

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~8800 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Context
RC implementation complete (D005 Phases 0-9, all firm). Ownership transfer bugs fixed (D006). All tests pass + bootstrap fixed-point verified. Working directory has uncommitted changes ready for commit.

### Uncommitted Changes Summary
- `bootstrap/gen_rc.ss` (NEW) — RC state + block scope + cycle detection (268 LOC)
- `bootstrap/gen_class.ss` (MOD) — constructor retain, resolveInheritance(), vtable, dtor tags
- `bootstrap/gen_runtime.ss` (MOD) — ss_rc_release_no_children, atexit stub, RC runtime funcs
- `bootstrap/gen_stmts.ss` (MOD) — atexit registration, block scope RC integration
- `bootstrap/codegen.ss` (MOD) — integration (resolveInheritance, buildClassVtables, assignClassDtorTags, detectCyclicOwnership)
- `bootstrap/lexer.ss`, `parser.ss`, `main.ss` (MOD) — various improvements
- `tests/phase4/` (NEW) — rc_cycle.ss, rc_class_dtor.ss, rc_block_scope.ss, rc_destruct.ss, vtable.ss
- `bin/ss` (MOD) — compiled binary
- `docs/` — D005 updated, D006 new, I007→I012 resolved, axioms/principles/decisions created

## Task
1. **Commit** all uncommitted changes (tests pass, bootstrap verified)
2. **Pick next priority** from open issues: I001 (global mutable state), I002 (string-based type system), I003 (semantic analysis incomplete), I004 (weak error reporting), I005 (AST list as string), I006 (runtime raw IR), I008 (parser no precedence table)
3. **Analyze + implement + verify** the chosen issue in one go (no artificial round splits)

## Decision Criteria for Next Priority
- Impact on correctness > impact on maintainability > impact on developer experience
- Issues that block future features rank higher
- Issues with existing partial implementations rank higher

## Watch Out For
- C1: Every change must pass test + bootstrap
- P1: Test before modify
- V6: Minimal change — one issue at a time
