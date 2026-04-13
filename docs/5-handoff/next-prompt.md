# Round 166

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D088-comptime-zig-route.md (CRITICAL: Zig route decision, verification checklist, anti-patterns)
- docs/4-issues/1-open/ (check remaining open issues)
- lib/comptime.ss (current comptime library — 7/8 @derive handlers use fields()+bracket)
- bootstrap/prelude.ss (overloaded helpers: _ss_hashContrib, _ss_jsonValue, _ss_zero)

## Last Round (max 3 sentences)
Implemented bracket WRITE (`obj[name] = value`) in genIndexAssign with compile-time field name detection and RC-safe GEP+store, mirroring existing bracket READ. Fixed zero-arg constructor (`new ClassName()`) to pass zero values for all fields. Rewrote @derive(Copy) and @derive(Default) using fields()+bracket+overload pattern, eliminating getTypeInfo — 7/8 handlers now use D088 pattern.

## Task
**Continue D088 roadmap or advance remaining items**

### D088 Phase Status
- **Phase 5** ✅ obj.fields() + obj[name] READ + obj[name] WRITE + compile-time for-in unrolling
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
- ✅ Copy — for-in + result[name] = this[name] (bracket write)
- ✅ Default — for-in + result[name] = _ss_zero(result[name]) (overloaded)
- ❌ With — per-field `withXxx()` method generation (inherently per-field, stays with getTypeInfo)

### Overload + unrolling pattern (proven capability)
- `_ss_hashContrib(v: int/string/double)` — overloaded type-specific hash
- `_ss_jsonValue(v: int/string/double)` — overloaded type-specific JSON
- `_ss_zero(v: int/string/double)` — overloaded type-specific zero values
- During for-in unrolling: `this[name]` has known type → `resolveOverload` picks correct variant
- Pattern generalizable: any type-specific operation can use this overload dispatch

### New capabilities added this round
- **Bracket WRITE**: `obj[name] = value` in genIndexAssign — compile-time field name (STRING_LIT or comptimeConst IDENT) + class detection (getObjClass + getVarType fallback) → GEP+store with RC handling
- **Zero-arg constructor**: `new ClassName()` with no args now fills zero values for all fields (int→0, double→0.0, ptr→null)
- **_ss_zero overloads**: type-dispatched zero values for @derive(Default) pattern

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
- **Bootstrap**: 48 files, ~18700 LOC, 217 tests (217 passing, 0 failures).
- **Comptime**: D087 Phase 1-4 complete. D088 Phase 5-7 complete. ct* functions frozen.
- **@derive**: 7/8 handlers rewritten with fields()+bracket. Only With still uses getTypeInfo.
- **Next**: Phase 8 (comptime parameters), or other improvements.

## Watch Out For
- **D088 anti-patterns**: No new ct* functions, no new @derive handlers with string concat, no @comptimeEmit enhancements, no new template placeholders.
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Phase 5 capabilities**: obj.fields() + obj[name] READ/WRITE + for-in unrolling + overload dispatch.
- **Overload pattern**: _ss_hashContrib/_ss_jsonValue/_ss_zero demonstrate type-dispatched helpers via function overloading. Reusable for any type-specific operation.
- **interp_stubs.ss**: Required for standalone interpreter tests (provides codegen global stubs).
- **Zero-arg constructor**: `new ClassName()` with no args now works correctly (fills zeros). Used by @derive(Copy/Default).
- **Bracket write class resolution**: Uses getObjClass + getVarType fallback (INDEX_ASSIGN S1 is string varName, not expression node, so can't use resolveObjClass directly).

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
