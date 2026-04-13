# Round 167

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D089-compiler-is-interpreter.md (CRITICAL: 统一架构设计，tagged int，迁移计划)
- docs/3-decisions/D088-comptime-zig-route.md (Zig route context)
- bootstrap/codegen.ss (nextReg, emitIR, regCount — Phase 0 改造目标)
- bootstrap/gen_exprs.ss (genExpr — genVal 的基础)

## Last Round (max 3 sentences)
Implemented interpreter enum support (ENUM_DECL, variant access, values/names/valueOf methods). Then discussed the fundamental architecture gap: SS has "compiler + interpreter" (two implementations), not "compiler = interpreter" (one implementation). Designed D089: tagged int Value encoding (bit 30 = comptime flag), genVal replaces genExpr, Zig-style value-level comptime propagation, 7-phase migration plan.

## Task
**D089 Phase 0: 基础设施 — tagged int + 寄存器表 + genVal wrapper**

### What to do
1. Add tagged int operations to codegen.ss: `ctVal()`, `isCt()`, `payload()`, `r()`
2. Add register table: `regTable` array, modify `nextReg()` to return int and store name in table
3. Add `constVal(s: string): int` for non-register constants
4. Add `genVal(id: int): int` initial version: wraps old genExpr, returns `constVal(oldGenExpr(id))`
5. Rename current `genExpr` → `genExprOld`, add new `genExpr` wrapper: `return r(genVal(id))`
6. Update all callers: `nextReg()` returns int now, wrap with `r()` where used in emitIR

### Phase 0 验证
- Bootstrap 固定点通过（stage2 == stage3）
- `bin/ss test tests/` 全量通过（218 tests）
- 行为完全不变，纯重构

### D089 Core Principle
> **新增语言特性时改几处？1 处 → 在路线上。2 处 → 没改到位。**
> Phase 0 不改变这个数字，只搭基础设施。Phase 1-6 逐步统一。

### Migration Baseline (from research)
- genExpr 调用点: 111（97% 赋值到变量）
- nextReg 调用点: 363
- emitIR 调用点: 1,857
- 解释器待删除代码: 1,782 行

## Project Status
- **Bootstrap**: 48 files, ~18700 LOC, 218 tests (218 passing, 0 failures).
- **Comptime**: D087 Phase 1-4, D088 Phase 5-7 complete. Interpreter enum just added.
- **D089**: Phase 0 pending. Architecture designed, not yet implemented.

## Watch Out For
- **Phase 0 是纯重构**：行为不变，只搭基础设施。不要在这一步做 comptime 传播。
- **nextReg 改造是最大风险**：363 个调用点从 string 变 int。用 `r()` wrapper 机械替换。
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
