# Round 170

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D089-compiler-is-interpreter.md (CRITICAL: 统一架构设计，tagged int，迁移计划)
- bootstrap/codegen.ss (ctVal/isCt/payload/constVal/reg/materialize/regTable)
- bootstrap/gen_exprs.ss (genVal — Phase 1 literals + Phase 2 binary/unary + genExprOld fallback)

## Last Round (max 3 sentences)
Implemented D089 Phase 2: genValBinary folds int/bool binary ops at compile time via interpIntOp; genValUnary folds Neg/Not/BitNot. Short-circuit/instanceof/as/string/double ops fall back to genExprOld. Verified `1 + 2` emits `store i32 3` (no add instruction). Bootstrap fixed-point + 219 tests pass.

## Task
**D089 Phase 3: TERNARY comptime propagation**

### What to do
1. Move TERNARY handling from genExprOld to genVal:
   - Condition ctVal → only evaluate taken branch (compile-time branch elimination)
   - Condition runtime → emit IR as before (materialize condition, emit branch/phi)
2. Consider NULL_COALESCE comptime handling in genValBinary:
   - If left operand ctVal and non-null → return left (no IR)
   - If left operand ctVal and null → evaluate right
   - Otherwise fall back to genExprOld

### Phase 3 验证
- Bootstrap 固定点通过
- `bin/ss test tests/` 全量通过（219+ tests）
- **新测试**: 验证 `true ? 1 : 2` 和 `false ? 1 : 2` 产出 comptime 值
- 行为不变，但常量三元表达式现在是编译期求值

### Design notes
- genTernary 在 gen_exprs.ss 中，处理 condition→then/else 分支 + phi 节点
- Phase 3 只处理 condition 是 comptime 的 case，operands 可以是 comptime 或 runtime
- Short-circuit (And/Or) 也可以考虑 comptime：`true || expr` → `true` 不求值 expr

## Project Status
- **Bootstrap**: 48 files, ~18700 LOC, 219 tests (219 passing, 0 failures).
- **D089 Phase 0**: Complete. Tagged int infra + genVal/genExpr wrapper.
- **D089 Phase 1**: Complete. Literal comptime + materialize.
- **D089 Phase 2**: Complete. Binary/unary comptime constant folding.
- **D089 Phase 3**: TERNARY/null-coalesce comptime — pending.

## Watch Out For
- **genTernary 的 label/phi 结构**：ternary 用 label + phi 实现，comptime 时直接返回分支值，不生成 phi。
- **Short-circuit And/Or**：目前 fallback 到 genExprOld。可以在 Phase 3 加 comptime 处理（true && x → x, false || x → x）。
- **DOUBLE_LIT 未走 ctVal**：Phase 3 仍不做 double comptime 折叠。
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests verifying ternary/null-coalesce comptime folding
2. Run `bin/ss test tests/` — 219+ tests pass
3. Run `./build.sh bootstrap` — fixed-point verified
4. Run `/simplify` to review code quality before commit
5. Self-review for contradictions
6. Commit and push to remote
7. Generate next docs/5-handoff/next-prompt.md (include "Next Direction" summary)
8. List files created/modified + brief next direction
9. **Stop.**
