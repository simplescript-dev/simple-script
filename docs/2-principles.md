# Principles

Derived from Axioms. Each traces to Constraints or Values. Can refine, not violate.

## Development Process

- **P1: Bootstrap guard.** Every change → `bin/ss test tests/` → `./build.sh bootstrap`. No exceptions. ← C1
- **P2: Test before modify.** Confirm all tests pass before touching code. ← C1
- **P3: Behavior-preserving refactoring.** Pure refactoring produces identical IR output. ← C1, V6
- **P4: Root cause first.** Fix from source, no workarounds or hacks. ← V3
- **P4a: Compiler limitation is a bug, not a boundary.** When a compiler limitation forces ugly patterns in stdlib or user code, fix the compiler first. Do NOT record it as "Known limitation" and work around it. If the same workaround appears twice, stop and fix the root cause. ← V3, C1
- **P5: Verify, don't assume.** Technical conclusions must be validated. If uncertain, say so. ← V3

## Architecture

- **P6: Dispatcher only dispatches.** No business logic in dispatch functions (genExpr, genStmt, genBinary). Each case → one-line delegation to handler. Handler ≤ 50 lines. ← V5, V6 (derived from DI-1 refactoring)
- **P7: Flat if/else over dispatch table.** SS has no Map<string, fn>. Go/Rust also use flat switch. No multi-level dispatchers. ← V5 (derived from DI-1)
- **P8: Study before designing.** Check Go/Rust/Zig/Swift compiler approach before implementing any feature. ← V3
- **P9: Complexity in compiler, not user code.** Users should never see implementation details of memory management, vtables, or other internals. ← C5, V2
- **P10: Forward-compatible refactoring.** Refactoring blocked by missing language features (struct, enum) is deferred, not hacked around. ← V6

## Code Style

- **P11: Template strings for readability.** Use `` `${var}` `` over `+` concatenation. ← V5
- **P12: No dead code.** Deprecated code is deleted, not commented out. ← V5
- **P13: Extract only when justified.** Three similar lines are better than a premature abstraction. ← V6

## Workflow

- **P14: Atomic task execution.** Sequential steps of the same task (analyze → verify → commit) execute in one go. Handoff splits only at genuinely independent task boundaries. ← V6
- **P15: Simplify after verify.** After implementation is manually verified correct, review changed code for reuse, quality, and efficiency (`/simplify`). Run tests + bootstrap again after simplification. ← V5, V6
- **P16: Record decisions immediately.** Every design discussion that produces a confirmed decision → create a D-numbered doc in `docs/3-decisions/` before moving on. One decision per doc. Include: status, depends-on, decision text, reasoning, rejected alternatives, interfaces, tensions. ← V3, V5
