# Round 165

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D088-comptime-zig-route.md (CRITICAL: Zig route decision, verification checklist, anti-patterns)
- docs/4-issues/1-open/ (check remaining open issues)
- lib/comptime.ss (current comptime library — all @derive handlers now use fields()+bracket)
- bootstrap/prelude.ss (overloaded _ss_hashContrib/_ss_jsonValue helpers)

## Last Round (max 3 sentences)
Fixed 5 pre-existing interp_* test failures by adding interpReset() and creating interp_stubs.ss for standalone compilation. Rewrote @derive(Hash) and @derive(ToJson) using fields()+bracket + overloaded runtime helpers (_ss_hashContrib, _ss_jsonValue), eliminating per-field string-based code generation. Key technique: function overload resolution during for-in unrolling automatically picks the correct type-specific variant at compile time.

## Task
**Continue @derive rewrites or advance D088 roadmap**

### D088 Phase Status
- **Phase 5** ✅ obj.fields() + obj[name] + compile-time for-in unrolling
- **Phase 6** ✅ interpreter class support
- **Phase 7** ✅ interpreter enum/try-catch/closures
- **Phase 8** ⬜ comptime parameters — `function repeat(@comptime n: int, s: string)` specialization
- **Phase 9** ⬜ types as comptime values — `comptime { return Pair(int, string) }`

### @derive rewrite status (all using fields()+bracket, no getTypeInfo)
- ✅ ToString — for-in + name + this[name]
- ✅ Equals — for-in + this[name] != other[name]
- ✅ Comparable — for-in + this[name] < other[name]
- ✅ Hash — for-in + _ss_hashContrib(this[name]) (overloaded)
- ✅ ToJson — for-in + _ss_jsonValue(this[name]) (overloaded)
- ❌ Copy — needs `new ClassName(field: this.field)` construction
- ❌ Default — needs `new ClassName(field: zero)` with type-specific zeros
- ❌ With — needs per-field `withXxx()` method generation

### Overload + unrolling pattern (new capability)
- `_ss_hashContrib(v: int/string/double)` in prelude.ss — overloaded type-specific hash
- `_ss_jsonValue(v: int/string/double)` in prelude.ss — overloaded type-specific JSON serialization
- During for-in unrolling: `this[name]` has known type → `resolveOverload` picks correct variant
- Pattern generalizable: any type-specific operation can use this overload dispatch

### Remaining @derive handlers (Copy/Default/With)
These need `new ClassName(field: value)` construction which requires field names as named arguments. Current for-in unrolling + bracket notation cannot construct objects. Options:
1. Keep using getTypeInfo for these (pragmatic, limited scope)
2. Add compile-time named argument resolution from comptime consts (extend Phase 5)
3. Defer to Phase 8/9

### Interpreter coverage
- ✅ Literals, variables, functions, closures, classes, inheritance
- ✅ if/while/do-while/for/for-in, break/continue/return
- ✅ throw/try/catch/finally, switch/case
- ✅ Arrays, Maps, string methods, higher-order methods
- ✅ @comptimeEmit, emit(), getTypeInfo, file I/O, shell
- ✅ interpReset() for standalone test use
- ❌ enum (ENUM_DECL in interpreter — enum values exist via compiler registry)

### Open Issues (by priority)
1. **I001 -- Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 -- String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 -- AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 -- Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 -- Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Project Status
- **Bootstrap**: 48 files, ~18700 LOC, 216 tests (216 passing, 0 failures).
- **Comptime**: D087 Phase 1-4 complete. D088 Phase 5-7 complete. ct* functions frozen.
- **@derive**: 5/8 handlers rewritten with fields()+bracket. Copy/Default/With still use getTypeInfo.
- **Next**: Copy/Default/With rewrites, Phase 8, or other improvements.

## Watch Out For
- **D088 anti-patterns**: No new ct* functions, no new @derive handlers with string concat, no @comptimeEmit enhancements, no new template placeholders.
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Phase 5 capabilities**: obj.fields() + obj[name] + for-in unrolling + overload dispatch.
- **Overload pattern**: _ss_hashContrib/_ss_jsonValue demonstrate type-dispatched helpers via function overloading. Reusable for any type-specific operation.
- **interp_stubs.ss**: Required for standalone interpreter tests (provides codegen global stubs).

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests for new features
2. Verify against D088 checklist and design principles
3. Run `/simplify` to review code quality before commit
4. Self-review for contradictions
5. Commit and push to remote
6. Generate next docs/5-handoff/next-prompt.md (include "Next Direction" summary)
7. List files created/modified + brief next direction
8. **Stop.**
