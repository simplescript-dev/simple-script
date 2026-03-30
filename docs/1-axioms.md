# Axioms

Constraint vs Value conflict → Constraint wins. Value vs Value → escalate to human.

## Constraints (external, non-negotiable)

- **C1: Self-bootstrapping.** The compiler compiles itself. Every change must pass 3-stage fixed-point verification (stage2 == stage3 byte-identical).
- **C2: Zero C dependency.** No runtime.c. All runtime functions generated as LLVM IR by gen_runtime.ss.
- **C3: Static binary output.** Target: musl-gcc static linking via llc-18. Single binary, no shared libs.
- **C4: No GC.** No runtime garbage collection pauses. Deterministic memory management only (RC).
- **C5: No user-facing memory syntax.** No `weak`, `unowned`, or other memory management keywords. Complexity hidden in compiler. Users write code like Java/TS.
- **C6: Class fields immutable.** No `obj.field = value` syntax. Fields set only at construction. This is a language design constraint that simplifies RC (no field reassignment cycles).

## Values (designer's choices)

- **V1: TypeScript-like syntax.** Familiar to JS/TS developers: const/let, function, class/new/this/extends, arrow functions, template literals, try/catch.
- **V2: Transparent memory management.** Memory management should feel like Java/TS — users don't think about it. RC overhead acceptable if invisible.
- **V3: Best practices from mature compilers.** Every design decision references Go/Rust/Zig/Swift compiler implementations. No inventing novel approaches.
- **V4: Pure SS implementation.** No embedding third-party C libraries. All functionality implemented in pure SimpleScript.
- **V5: Readability over cleverness.** Template strings over concatenation. No reducing lines at cost of clarity. Single file ≤ 500 lines preferred.
- **V6: Minimal change principle.** One file, one function at a time. No big-bang refactoring. Incremental improvement.
