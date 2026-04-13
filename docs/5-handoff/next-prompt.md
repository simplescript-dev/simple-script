# Round 163

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D088-comptime-zig-route.md (CRITICAL: Zig route decision, verification checklist, anti-patterns)
- docs/4-issues/1-open/ (check remaining open issues)
- lib/comptime.ss (current comptime library — frozen ct* functions, @derive uses fields()+bracket)

## Last Round (max 3 sentences)
Implemented D088 Phase 5: `obj.fields()` + `obj[name]` bracket notation + compile-time for-in unrolling. Rewrote @derive(ToString/Equals/Comparable) to use fields()+bracket notation instead of getTypeInfo + manual string concatenation — validates Phase 5 in real use. 216 tests (211 passing, 5 pre-existing interp_* failures), bootstrap fixed-point verified.

## Task
**Continue D088: rewrite remaining @derive handlers and/or advance to Phase 6**

### What was done in Phase 5
- `obj.fields()` — compiler built-in, returns field name array (compile-time constant for for-in, runtime Array<string> standalone)
- `obj[name]` — bracket notation on class instances, resolves to GEP field access when name is compile-time constant string
- Compile-time for-in unrolling — when iterating obj.fields(), compiler unrolls loop (zero runtime overhead)
- @derive(ToString/Equals/Comparable) already rewritten to use fields()+bracket

### Remaining @derive handlers (cannot use fields()+bracket directly)
These need type-specific logic per field and cannot simply loop with `this[name]`:
- **Hash**: `h * 31 + this.x` (int) vs `h * 31 + this.name.length()` (string)
- **ToJson**: strings need quotes, ints don't
- **Copy/Default/With**: need `new ClassName(field: value)` construction, can't build named args dynamically

### D088 Phase 6: interpreter support for class
**Goal:** comptime blocks can define class, instantiate objects, access fields, call methods.
- interp.ss support CLASS_DECL → register class
- interp.ss support NEW_EXPR → create object value
- interp.ss support MEMBER_ACCESS / MEMBER_ASSIGN → field read/write
- interp.ss support METHOD_CALL on object → method call
- Verification: `comptime { class Foo { x: int }; const f = new Foo(x: 42); return f.x }` → 42

### D088 verification checklist (MUST check before starting)
1. This task solves the first-principle need: structural field access ✅ (Phase 5 done)
2. No new ct* functions ✅
3. No new keywords ✅
4. User writes plain SS code, compiler absorbs complexity ✅

### Open Issues (by priority)
1. **I001 -- Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 -- String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 -- AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 -- Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 -- Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Project Status
- **Bootstrap**: 47 files, ~18700 LOC, 216 tests (211 passing, 5 pre-existing interp_* failures).
- **Comptime**: D087 Phase 1-4 complete. D088 Phase 5 complete. ct* functions frozen.
- **D088 Phase 5 done**: obj.fields() + obj[name] + compile-time for-in unrolling.
- **Next direction**: Phase 6 (interpreter class support) or continue rewriting remaining @derive handlers.

## Watch Out For
- **D088 anti-patterns**: No new ct* functions, no new @derive handlers with string concat, no @comptimeEmit enhancements, no new template placeholders.
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **obj.fields() is compile-time only**: Returns compile-time constant array. Not runtime reflection.
- **obj[name] requires constant name**: Only works when name is a compile-time constant string. Not runtime dynamic lookup.
- **for-in unrolling**: Compiler detects compile-time constant iteration target → unrolls. No `inline` keyword needed.
- **@derive rewrite status**: ToString/Equals/Comparable done. Hash/ToJson/Copy/Default/With still use old string concat approach (need type-specific logic).

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
