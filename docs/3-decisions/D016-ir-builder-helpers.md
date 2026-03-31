# D016: IR Builder Helpers for gen_runtime.ss

## Status
firm

## Resolves
I006 — gen_runtime.ss 2000+ lines of raw LLVM IR strings (Phase 1: core helpers + proof of concept)

## Depends On
- axioms.md → C1 (bootstrap must pass)
- principles.md → P3 (behavior-preserving refactoring)
- principles.md → V3 (best practices — LLVM IRBuilder pattern)

## Decision
Add 15 IR builder helper functions to codegen.ss, grouped after `emitIR`/`nextReg`/`nextLabel`. Each wraps a single `emitIR()` call with structured parameters. Apply to `emitRuntimeProcess` and `emitRuntimeMath` as proof of concept.

**Helpers** (Phase 1): `irLabel`, `irAlloca`, `irLoad`, `irStore`, `irGEP`, `irICmp`, `irBr`, `irBrCond`, `irRet`, `irRetVoid`, `irAdd`, `irSub`, `irMul`, `irCall`, `irCallVoid`. Extended in Phase 2: `irSext`, `irZext`, `irSelect`, `irSDiv`, `irOr`, `irTrunc`, `irPtrToInt`, `irIntToPtr`.

**Parameter convention**:
- `dst` (destination register): name only, auto-prefixed with `%` by helper
- Label names (in `irBr`, `irBrCond`): name only, auto-prefixed with `%`
- `cond` (in `irBrCond`): register name, auto-prefixed with `%` (always i1 register)
- Value/operand params: raw IR values — caller includes `%` for registers, `@` for globals, bare for literals/null
- `func` (in `irCall`/`irCallVoid`): function name, auto-prefixed with `@`

**Placement**: codegen.ss after `nextLabel()`, before `addStringConst()`. Keeps all IR-emitting primitives grouped.

## Key Reasoning (3 sentences max)
LLVM's IRBuilder pattern (V3) separates instruction construction from string formatting. Placing helpers in codegen.ss avoids new file/import and keeps codegen.ss at ~370 lines (under V5). Incremental application (2 of 14 sections) validates the pattern before committing to full conversion.

## Rejected Alternatives
- **New file ir_builder.ss**: Would require import changes and adds a file for ~50 lines. codegen.ss has room (320→370 lines, under V5 500-line limit).
- **Unify with nextReg() convention**: gen_stmts/gen_exprs use `nextReg()` returning `"%N"` (with `%`). Making helpers compatible would require changing `nextReg()` return format across ~350 call sites — disproportionate scope for a maintainability improvement.
- **Convert all 14 sections at once**: Violates V6 (minimal change). 1700+ emitIR call conversions in one round is high-risk for bootstrap verification.
- **Add align parameter to irLoad/irStore**: gen_runtime.ss never uses align on load/store. Adding unused parameters would be YAGNI.

## Interfaces With Other Decisions
- I006: Phase 1 complete, Phase 2a complete, Phase 2b complete (10 of 10 convertible sections done). emitRuntimeGlobals has only module-level declarations — cannot benefit from helpers.
- I001: Helpers added to codegen.ss (+92 lines total), keeping it at ~414 lines — no new extraction needed.

## Open Tensions
- gen_stmts.ss/gen_exprs.ss cannot use these helpers due to `nextReg()` convention mismatch. This limits helpers to gen_runtime.ss and similar hand-written IR contexts.
- `irCall`/`irCallVoid` hardcode `@` prefix — cannot handle indirect calls through function pointers. emitRuntimeRC has 1 indirect call (`call void %dfn(ptr %p)` for dtor dispatch) retained as raw emitIR.
- `irCall` works for variadic calls (e.g. snprintf) by passing the full signature as retTy: `irCall("written", "i32 (ptr, i64, ptr, ...)", "snprintf", ...)`. Not ideal but functional — only 1 occurrence.
- emitRuntimeMath has 3 functions (ss_min, ss_max, ss_random) with mixed helper/raw emitIR due to missing irFCmp/irSIToFP/irFDiv helpers. Will be addressed when those helpers are added.
- `call i32 @puts(ptr %_1)` in emitRuntimeExceptions uses raw emitIR — returns i32 but result discarded, neither irCall (requires dst) nor irCallVoid (uses void) fits. Rare pattern (1 occurrence), not worth a dedicated helper per P13.

## Notes
Phase 1: codegen.ss +50 lines (15 helpers), 52 emitIR calls converted. Phase 2a: codegen.ss +20 lines (5 new helpers: irSext, irZext, irSelect, irSDiv, irOr), ~130 additional emitIR calls converted in emitRuntimeConversions + emitRuntimeFS + emitRuntimeProcess sext fix. Phase 2b (partial): codegen.ss +8 lines (2 new helpers: irTrunc, irPtrToInt), ~288 additional emitIR calls converted in emitRuntimeHelpers + emitRuntimeIO + emitRuntimeExceptions + emitRuntimeStringOps. Phase 2b (continued): codegen.ss +4 lines (1 new helper: irIntToPtr), ~256 additional emitIR calls converted in emitRuntimeArrayOps (15 runtime functions). Phase 2b (continued): no new helpers needed, ~189 additional emitIR calls converted in emitRuntimeRC (10 runtime functions). 2 raw emitIR retained: multi-index GEP and indirect call for dtor dispatch. Phase 2b (final): no new helpers needed, ~414 additional emitIR calls converted in emitRuntimeNet (6 functions), emitRuntimeSQLite (4 functions), emitRuntimeMap (10 functions). 1 raw emitIR retained: urem in hash_str (P13). Total: 23 helpers, 1337 helper calls, 401 raw emitIR remaining (structural + unconvertible). All 56 tests pass, bootstrap 3-stage fixed-point verified. No behavioral change — pure P3 refactoring.
