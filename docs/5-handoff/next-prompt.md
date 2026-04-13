# Round 169

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D089-compiler-is-interpreter.md (CRITICAL: 统一架构设计，tagged int，迁移计划)
- bootstrap/codegen.ss (ctVal/isCt/payload/constVal/reg/materialize)
- bootstrap/gen_exprs.ss (genVal — Phase 1 literal cases + genExprOld fallback)

## Last Round (max 3 sentences)
Skipped Phase 0b (nextReg int conversion, 363 sites) — unnecessary since Phase 2+ can use `constVal(nextReg())` pattern at ~50 individual migration points instead. Implemented D089 Phase 1: genVal returns ctVal for INT_LIT, STRING_LIT, TRUE/FALSE_LIT, NULL_LIT; added materialize() to convert comptime values to IR constants. DOUBLE_LIT deferred (formatting round-trip risk). Bootstrap fixed-point + 218 tests pass.

## Task
**D089 Phase 2: Binary/Unary comptime propagation**

### What to do
1. Move BINARY handling from genExprOld to genVal:
   - Both operands ctVal → comptime result via interpBinaryOp (no IR emitted)
   - Either operand runtime → materialize both, emit IR as before, return constVal(nextReg())
2. Move UNARY handling from genExprOld to genVal:
   - Operand ctVal → comptime result via interpUnaryOp
   - Operand runtime → materialize, emit IR, return constVal(nextReg())
3. Move TERNARY handling from genExprOld to genVal:
   - Condition ctVal → only evaluate taken branch (compile-time branch elimination)
   - Condition runtime → emit IR as before

### Key functions needed
- `interpBinaryOp(op: string, lv: int, rv: int): int` — comptime binary evaluation
  - Check interp_eval.ss for existing binary evaluation logic to reuse
- `interpUnaryOp(op: string, v: int): int` — comptime unary evaluation

### Phase 2 验证
- Bootstrap 固定点通过
- `bin/ss test tests/` 全量通过（218 tests）
- **新测试**: 验证 `1 + 2` 在 comptime 块外也产出 comptime 值（可以用 `--emit-ir` 验证无 add 指令）
- 行为不变，但常量表达式现在是编译期求值

### Design notes
- genBinary/genIntBinary/genDoubleBinary 等 helper 函数目前在 gen_exprs.ss 中
- Phase 2 只迁移 genBinary 的 INT_LIT 分支（int 操作），不迁移 string concat、short-circuit、instanceof 等复杂 case
- 对于 short-circuit (&&/||), ternary, null-coalesce: comptime condition → 编译期选择分支
- String concat with comptime operands → 编译期拼接（interpBinaryOp 处理）

## Project Status
- **Bootstrap**: 48 files, ~18700 LOC, 218 tests (218 passing, 0 failures).
- **D089 Phase 0**: Complete. Tagged int infra + genVal/genExpr wrapper.
- **D089 Phase 1**: Complete. Literal comptime + materialize.
- **D089 Phase 2**: Binary/unary comptime propagation — pending.

## Watch Out For
- **genBinary 的复杂性**：有 string concat、short-circuit、instanceof、as、null-coalesce 等特殊 case。Phase 2 先只处理 int/bool 算术和比较，其他 case fallback 到 genExprOld。
- **interpBinaryOp 是否已存在**：interp_eval.ss 有 interpBinaryOp 或类似函数，优先复用。
- **DOUBLE_LIT 未走 ctVal**：Phase 2 的 double binary 操作暂不做 comptime 折叠。
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests verifying constant folding works
2. Run `bin/ss test tests/` — 218+ tests pass
3. Run `./build.sh bootstrap` — fixed-point verified
4. Run `/simplify` to review code quality before commit
5. Self-review for contradictions
6. Commit and push to remote
7. Generate next docs/5-handoff/next-prompt.md (include "Next Direction" summary)
8. List files created/modified + brief next direction
9. **Stop.**
