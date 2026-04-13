# Round 168

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D089-compiler-is-interpreter.md (CRITICAL: 统一架构设计，tagged int，迁移计划)
- bootstrap/codegen.ss (ctVal/isCt/payload/constVal/reg — Phase 0 已完成)
- bootstrap/gen_exprs.ss (genExprOld/genVal/genExpr wrapper — Phase 0 已完成)

## Last Round (max 3 sentences)
Implemented D089 Phase 0: tagged int infrastructure (ctVal, isCt, payload, constVal, reg) in codegen.ss, genVal/genExpr wrapper in gen_exprs.ss, regTable reset at all 11 function boundaries. genExpr is now `reg(genVal(id))` → `constVal(genExprOld(id))` round-trip, 111 callers unchanged. nextReg int conversion (363 call sites) deferred to next step per "一次只改一层" principle.

## Task
**D089 Phase 0b: nextReg 返回 int + reg() 包装**

### What to do
1. Change `nextReg(): string` → `nextReg(): int` in codegen.ss
   - Store `%N` string in regTable, return index (same as constVal pattern)
2. Find all 363 `nextReg()` call sites across 15 files
3. At each call site, wrap usages in template strings with `reg()`:
   - Pattern: `${varName}` → `${reg(varName)}` where varName holds nextReg result
   - Also wrap usages passed as function arguments expecting string
4. Do NOT change any genExpr callers (those already go through wrapper)

### Phase 0b 验证
- Bootstrap 固定点通过（stage2 == stage3）
- `bin/ss test tests/` 全量通过（218 tests）
- 行为完全不变，纯机械替换

### Risk Mitigation
- 363 call sites × ~3 usages each ≈ 1000+ template edits
- Work file-by-file, test after each major file
- Most common pattern: `const r = nextReg(); emitIR(\`  ${r} = ...\`)` → `emitIR(\`  ${reg(r)} = ...\`)`
- Watch for: nextReg results passed to helper functions (irLoad, irStore, etc.) — those need reg() at the call site OR inside the helper
- Watch for: nextReg results returned from functions — return type changes from string to int

### Alternative approach (safer)
If 363 sites is too risky for one round, split by file:
- Round 1: gen_exprs.ss (50 calls) + gen_builtins.ss (50 calls) — most self-contained
- Round 2: gen_calls.ss (56 calls) + gen_methods.ss (45 calls)
- Round 3: gen_stmts.ss (38 calls) + gen_assigns.ss (38 calls) + gen_decls.ss (13 calls)
- Round 4: gen_class.ss (15 calls) + gen_arrows.ss (14 calls) + gen_type_ops.ss (29 calls) + remaining

## Project Status
- **Bootstrap**: 48 files, ~18700 LOC, 218 tests (218 passing, 0 failures).
- **D089 Phase 0**: Complete. Tagged int infra + genVal/genExpr wrapper in place.
- **D089 Phase 0b**: nextReg int conversion pending (363 call sites).
- **D089 Phase 1**: Literal comptime (INT_LIT → ctVal) — after Phase 0b.

## Watch Out For
- **Phase 0b 是纯机械替换**：行为不变，只改 nextReg 返回类型 + 包装调用点。
- **irLoad/irStore/irAlloca 等 helper 函数**：它们接受 string 参数。如果 nextReg 结果传给这些 helper，需要在调用点用 reg() 包装。
- **函数返回类型**：genThisExpr, genIdent 等返回 nextReg 结果的函数，返回类型从 string 不变（它们已通过 genExprOld 被 constVal 包装）。
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests verifying behavior unchanged
2. Run `bin/ss test tests/` — 218 tests pass
3. Run `./build.sh bootstrap` — fixed-point verified
4. Run `/simplify` to review code quality before commit
5. Self-review for contradictions
6. Commit and push to remote
7. Generate next docs/5-handoff/next-prompt.md (include "Next Direction" summary)
8. List files created/modified + brief next direction
9. **Stop.**
