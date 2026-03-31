# D019: Perceus IR Intermediate Layer

## Status
firm

## Resolves
No intermediate representation between AST and LLVM IR — RC operations are ad-hoc, inline, and difficult to optimize. Perceus analysis requires a dedicated IR layer.

## Depends On
- axioms.md → C4 (deterministic RC, no GC)
- D018 (object layout — PIR needs to know struct layout for FIELD_SET/GET)
- principles.md → V3 (best practices — Koka/Perceus paper defines this IR)

## Decision
Introduce Perceus IR (PIR) between AST and LLVM IR:

```
AST → PIR Lowering → PIR Optimization (5 passes) → LLVM IR Codegen
```

PIR uses Map-based node system (same as AST, bootstrap-compatible):

| Field | Usage |
|-------|-------|
| `pirKind` | Instruction type string |
| `pirStr1/2/3` | Operand names (variables, types, fields) |
| `pirInt1` | Node ID operand |
| `pirList` | Argument list (comma-separated node IDs) |

**Instruction set (12 instructions):**

| Instruction | Semantics |
|-------------|-----------|
| RC_INC | ss_retain |
| RC_DEC | ss_release (drop if rc→0) |
| RC_IS_UNIQUE | ss_is_unique |
| ALLOC | ss_alloc + init rc=1 + fill TypeInfo |
| MOVE | ownership transfer, no RC ops |
| DEEP_CLONE | recursive clone via TypeInfo |
| SHALLOW_CLONE | shallow copy + rc_inc ref fields |
| DROP | call ss_drop_XXX + ss_dealloc |
| REUSE | reuse old memory for new (skip dealloc+alloc) |
| FIELD_SET | set field (old val rc_dec + new val rc_inc for ref types) |
| FIELD_GET | read field |
| CALL | function call (args tagged mutated/readonly) |

**5 optimization passes (Phase 1: Pass 1 only; Phase 2-3: all passes):**

1. **Liveness Analysis**: Mark last-use, insert RC_DEC after last use
2. **Move Analysis**: Eliminate redundant RC_INC+RC_DEC pairs → MOVE
3. **Uniqueness Analysis**: Statically prove rc==1 → skip RC_IS_UNIQUE check
4. **Drop Order Optimization**: Reorder field releases for REUSE hit rate
5. **Reuse Analysis**: DROP+ALLOC (same size) → REUSE

Each function compiles to a node ID list (PIR instruction sequence). Passes traverse and transform this list.

## Key Reasoning (3 sentences max)
Perceus paper defines this exact IR layer — RC operations must be explicit and analyzable before LLVM IR generation. Map-based nodes avoid the chicken-and-egg problem (compiler can't use enum-with-data it hasn't implemented yet). Passes are simple pattern matches on pirKind strings, implementable with current SS capabilities.

## Rejected Alternatives
- No IR, inline RC in LLVM codegen (current approach): Cannot optimize RC operations. Every retain/release is ad-hoc.
- Use LLVM passes for RC optimization: Violates the principle that semantic correctness must be ensured before LLVM IR. LLVM doesn't understand RC semantics.
- Use enum-with-data for PIR: Requires language features not yet implemented. Map-based approach works now.

## Interfaces With Other Decisions
- D018 (object layout): ALLOC and FIELD_SET/GET need struct layout knowledge.
- D020 (runtime functions): Each PIR instruction maps to specific runtime calls.
- D022 (clone): DEEP_CLONE/SHALLOW_CLONE map to TypeInfo clone function pointers.

## Open Tensions
- Map-based PIR is verbose and type-unsafe. After enum-with-data is implemented (Phase 4+), PIR should be rewritten for clarity.
- Phase 2 implements Passes 2-3 (Move Analysis, Uniqueness Analysis). Passes 4-5 are Phase 3.
- CALL instruction needs mutated/readonly tags per argument, but Phase 1 treats all object params as mutated (conservative).

## Notes
PIR is internal to the compiler — not user-visible. Implementation files: `gen_pir.ss` (core: state + accessors + analysis entry + schedule emission + REUSE queries, 342 lines), `pir_lower.ss` (AST→PIR lowering + expression scanning, 279 lines), `pir_opt.ss` (optimization passes 1-3 + 5, 277 lines), modified gen_stmts.ss and codegen.ss for PIR→LLVM integration. Decision confirmed 2026-03-31.

**Phase 1b implementation (Round 24–25):** PIR subset (8 of 12 instructions: ALLOC, RC_INC, RC_DEC, FIELD_SET, FIELD_GET, USE, CALL, MOVE). Pass 1 (Liveness) only. Opt-in per function — functions without class operations skip PIR entirely. Schedule-based integration: PIR analysis runs before codegen, produces a schedule Map (astStmtId → vars to RC_DEC), genBlock checks schedule after each genStmt. PIR-managed vars use new RC system (ss_retain/ss_release), non-PIR vars continue using old system (ss_rc_retain/ss_rc_release).

**Phase 2 implementation (Round 28):** Pass 2 (Move Analysis). Detects RC_INC(src=A, dst=B) where A's RC_DEC is scheduled at the same AST statement (A's last use IS the RC_INC). Eliminates the retain+release pair: genVarDecl skips ss_retain, source marked as released (ownership transferred to destination). Chained moves supported (a→b→c). Implementation: `pirMoveAnalysis()` in pir_opt.ss (45 lines), `pirMoveStmts` Map + `pirIsMoveStmt()` query in gen_pir.ss, single-line guard in genVarDecl.

**Phase 2 implementation (Round 37):** Pass 3 (Uniqueness Analysis). Statically proves rc==1 at release time for ALLOC-created variables that never had RC_INC (no shared references) or RC_DEC (no reassignment). For provably unique vars, replaces `ss_release(obj)` (null check → rc-- → zero-check → TypeInfo lookup → indirect call) with direct `ss_drop_ClassName(obj)`. Saves 5 runtime operations per release. Applied only in pirEmitScheduled (liveness-based releases); pirEmitReturnCleanup always uses ss_release because unreleased vars at function exit may include retained return values (rc>1). Also fixed: pirCollectUsesRec now handles TEMPLATE_LIT, INDEX_ACCESS, and NAMED_ARG AST nodes. Implementation: `pirUniquenessPass()` in pir_opt.ss (44 lines), `pirUniqueAtRelease` Map + `pirIsUniqueAtRelease()` query in gen_pir.ss.
