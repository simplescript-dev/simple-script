# Round 164

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D088-comptime-zig-route.md (CRITICAL: Zig route decision, verification checklist, anti-patterns)
- docs/4-issues/1-open/ (check remaining open issues)
- lib/comptime.ss (current comptime library — frozen ct* functions, @derive uses fields()+bracket)

## Last Round (max 3 sentences)
Confirmed D088 Phase 6 (interpreter class support) was already implemented — class/new/field/method all work in comptime. Implemented Phase 7 gaps: throw/try/catch/finally and switch/case in interpreter (closures already worked). Rewrote @derive(ToString/Equals/Comparable) to use Phase 5's fields()+bracket notation. 216 tests (211 passing, 5 pre-existing interp_* failures), bootstrap fixed-point verified.

## Task
**Continue D088 roadmap: Phase 8 (comptime parameters) or address remaining gaps**

### D088 Phase Status
- **Phase 5** ✅ obj.fields() + obj[name] + compile-time for-in unrolling
- **Phase 6** ✅ interpreter class support (was already implemented)
- **Phase 7** ✅ interpreter enum/try-catch/closures (try/catch/finally + switch added, closures already worked)
- **Phase 8** ⬜ comptime parameters — `function repeat(@comptime n: int, s: string)` specialization
- **Phase 9** ⬜ types as comptime values — `comptime { return Pair(int, string) }`

### @derive rewrite status
- ✅ ToString, Equals, Comparable — use fields()+bracket (no getTypeInfo)
- ❌ Hash — needs type-specific logic (int: `h*31+val`, string: `h*31+val.length()`)
- ❌ ToJson — needs type-specific logic (strings need quotes)
- ❌ Copy, Default, With — need `new ClassName(field: value)` construction

### Interpreter coverage (after this round)
- ✅ Literals, variables, functions, closures, classes, inheritance
- ✅ if/while/do-while/for/for-in, break/continue/return
- ✅ throw/try/catch/finally, switch/case
- ✅ Arrays, Maps, string methods, higher-order methods
- ✅ @comptimeEmit, emit(), getTypeInfo, file I/O, shell
- ❌ enum (ENUM_DECL in interpreter — enum values exist via compiler registry)

### Open Issues (by priority)
1. **I001 -- Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 -- String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 -- AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 -- Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 -- Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Project Status
- **Bootstrap**: 47 files, ~18700 LOC, 216 tests (211 passing, 5 pre-existing interp_* failures).
- **Comptime**: D087 Phase 1-4 complete. D088 Phase 5-7 complete. ct* functions frozen.
- **Next**: Phase 8 (comptime parameters) or other improvements.

## Watch Out For
- **D088 anti-patterns**: No new ct* functions, no new @derive handlers with string concat, no @comptimeEmit enhancements, no new template placeholders.
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Phase 5 capabilities**: obj.fields() (compile-time constant array), obj[name] (constant string → GEP), for-in unrolling (zero overhead).
- **Interpreter throw**: interpThrowFlag + interpThrowVal, propagates through interpShouldStop. TRY catches and clears. Finally preserves throw state.

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
