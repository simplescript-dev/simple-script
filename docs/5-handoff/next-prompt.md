# Round 171

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D089-compiler-is-interpreter.md (CRITICAL: 统一架构设计，tagged int，迁移计划)
- bootstrap/codegen.ss (ctVal/isCt/payload/constVal/reg/materialize/regTable)
- bootstrap/gen_exprs.ss (genVal — Phase 1-3 complete: literals + binary/unary + ternary/short-circuit/grouping)

## Last Round (max 3 sentences)
Implemented D089 Phase 3: genValTernary folds comptime ternary (dead branch elimination); genValShortCircuit folds comptime And/Or (short-circuit at compile time); GROUPING routes through genVal enabling `(1+2)*3` → `9`. Verified `1>0 ? 10:20` emits `store i32 10` (no branch IR). Bootstrap fixed-point + 220 tests pass (1 pre-existing failure in power_operator).

## Task
**D089 Phase 4: Comptime variables (ctVars scope)**

### What to do
1. Add `ctVars` Map to track comptime variable bindings:
   - `VAR_DECL` with comptime initializer → record in ctVars, still emit IR (constant folding, not elimination)
   - `IDENT` lookup → check ctVars first, return ctVal if found
   - `ASSIGN` to ctVars variable → update ctVars binding
2. Scope management:
   - `ctVars` needs scope push/pop aligned with existing variable scoping
   - Consider using existing `interpPushScope`/`interpPopScope` or a simpler stack

### Phase 4 验证
- Bootstrap 固定点通过
- `bin/ss test tests/` 全量通过（220 tests）
- **新测试**: `const x = 1 + 2; const y = x * 3; assertEqual(y, 9)` — comptime propagation through variables
- 行为不变，但 `const x = 1+2; const y = x*3` 现在全程 comptime（y = 9 直接 store）

### Design notes
- Phase 4 scope: only `const` variables with comptime initializers. `let` variables are mutable → always runtime
- ctVars key: `"funcName:varName"` (same pattern as varTypes/varAliases)
- Don't eliminate IR for const declarations — still emit store. Phase 4 just enables further folding downstream
- IDENT in genVal: check ctVars → if found, return ctVal; otherwise fall through to genExprOld (which loads from alloca)

## Project Status
- **Bootstrap**: 48 files, ~18700 LOC, 220 tests (219 passing, 1 pre-existing failure).
- **D089 Phase 0**: Complete. Tagged int infra + genVal/genExpr wrapper.
- **D089 Phase 1**: Complete. Literal comptime + materialize.
- **D089 Phase 2**: Complete. Binary/unary comptime constant folding.
- **D089 Phase 3**: Complete. Ternary/short-circuit/grouping comptime.
- **D089 Phase 4**: Comptime variables (ctVars) — pending.

## Watch Out For
- **Scope 管理复杂性**：ctVars 需要与现有 scope 对齐。函数调用、block 进出时 push/pop。考虑最简方案。
- **let vs const**：只有 const 可以 comptime（不可变）。let 变量始终 runtime，因为后续可能被赋值。
- **函数参数**：参数是 runtime 值（除非在 comptime 块内）。Phase 4 不处理参数 comptime。
- **DOUBLE_LIT 未走 ctVal**：Phase 4 仍不做 double comptime 折叠。
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests verifying comptime variable propagation
2. Run `bin/ss test tests/` — 220+ tests pass
3. Run `./build.sh bootstrap` — fixed-point verified
4. Run `/simplify` to review code quality before commit
5. Self-review for contradictions
6. Commit and push to remote
7. Generate next docs/5-handoff/next-prompt.md (include "Next Direction" summary)
8. List files created/modified + brief next direction
9. **Stop.**
