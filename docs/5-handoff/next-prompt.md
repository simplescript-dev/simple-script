# Round 166

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D088-comptime-zig-route.md (CRITICAL: Zig route = 解释器覆盖完整语言，验证清单，反模式)
- docs/4-issues/1-open/ (check remaining open issues)
- bootstrap/interp.ss + interp_eval.ss + interp_exec.ss (interpreter — 补缺口的主战场)

## Last Round (max 3 sentences)
Implemented bracket WRITE, zero-arg constructor, rewrote @derive(Copy/Default). Then corrected the Zig route understanding: Phase 8/9 (comptime parameters, types as values) are Zig syntax features SS doesn't need — SS already has generics. The real Zig route is "interpreter = full language": close interpreter gaps so any SS code runs in `comptime {}`.

## Task
**Close interpreter gaps — make `comptime {}` support more SS syntax**

### Zig Route Core Principle
> **编译器即解释器，解释器 = 完整语言。**
> 每轮验证：**这轮完成后，有新的 SS 语法能在 `comptime {}` 里跑了吗？**
> 是 → 在路线上。不是 → 偏了。

### Interpreter Gap List (by priority)
| Gap | Compiler counterpart | Impact |
|-----|---------------------|--------|
| ENUM_DECL | registerEnum in gen_stmts.ss | Can't define/use enums in comptime |
| destructuring array | genDestructureArray | `let [a, b] = arr` won't work |
| destructuring object | genDestructureObject | `let {x, y} = obj` won't work |
| spread | SPREAD_ELEM | `...arr` won't work |
| super | SUPER in gen_exprs.ss | `super.method()` won't work |
| bitwise compound assign | &= |= ^= <<= >>= | Won't work in comptime |

### Interpreter Current Coverage
- ✅ Literals, variables, functions, closures, classes, inheritance
- ✅ if/while/do-while/for/for-in, break/continue/return
- ✅ throw/try/catch/finally, switch/case
- ✅ Arrays, Maps, string methods, higher-order methods
- ✅ @comptimeEmit, emit(), getTypeInfo, file I/O, shell
- ✅ interpReset() for standalone test use
- ❌ enum, destructuring, spread, super, bitwise compound assign

### Phase 5 Capabilities (completed, stable)
- obj.fields() + obj[name] READ/WRITE + compile-time for-in unrolling + overload dispatch
- @derive 7/8 rewritten with fields()+bracket (With stays with getTypeInfo — inherently per-field)
- _ss_hashContrib / _ss_jsonValue / _ss_zero overloaded runtime helpers

### Open Issues (by priority)
1. **I001 -- Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 -- String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 -- AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 -- Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 -- Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Project Status
- **Bootstrap**: 48 files, ~18700 LOC, 217 tests (217 passing, 0 failures).
- **Comptime**: D087 Phase 1-4 complete. D088 Phase 5-7 complete. ct* functions frozen.
- **Zig route**: Interpreter ~80% complete. Gaps: enum, destructuring, spread, super.

## Watch Out For
- **D088 验证**: 每轮必过——有新的 SS 语法能在 comptime {} 里跑了吗？不是→偏了。
- **不打磨便捷层**: @derive 已够用（7/8），不再花时间优化。
- **不抄 Zig 语法**: 不做 @comptime 参数、不做 types as values，除非出现真实驱动场景。
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **interp_stubs.ss**: Required for standalone interpreter tests (provides codegen global stubs).

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests: SS code using the new feature inside `comptime {}`, proving it works
2. Verify against D088 checklist: "有新语法能在 comptime 里跑了吗？"
3. Run `/simplify` to review code quality before commit
4. Self-review for contradictions
5. Commit and push to remote
6. Generate next docs/5-handoff/next-prompt.md (include "Next Direction" summary)
7. List files created/modified + brief next direction
8. **Stop.**
