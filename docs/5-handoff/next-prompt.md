# Round 162

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~18700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D088-comptime-zig-route.md (CRITICAL: Zig route decision, verification checklist, anti-patterns)
- docs/4-issues/1-open/ (check remaining open issues)
- lib/comptime.ss (current comptime library — frozen, no new ct* functions per D088)

## Last Round (max 3 sentences)
Added comptime collection utilities (ctReplaceAll, ctMap, ctRange, ctLen, ctContains, ctZip) to lib/comptime.ss — these are frozen per D088, no further ct* additions. Created D088 decision document: SS walks the Zig route, with `obj.fields()` + `obj[name]` as the first-priority goal (structural field access). 215 tests (210 passing, 5 pre-existing interp_* failures), bootstrap fixed-point verified.

## Task
**Implement D088 Phase 5: `obj.fields()` + `obj[name]` + compile-time loop unrolling**

This is the #1 priority from D088. The first-principle need is: given an object, iterate its field names and values. Everything else (toString, toJson, equals, hash, copy) becomes a plain library function once this works.

### What to implement (3 things)

1. **`obj.fields()`** — Compiler built-in method for every class. Returns field name array (compile-time constant). Like TS `Object.keys(obj)`.

2. **`obj[name]` bracket notation** — When `name` is a compile-time constant string, `obj["x"]` resolves to `obj.x` field access at codegen (GEP instruction). Like TS `obj[key]`.

3. **Compile-time for-in unrolling** — When for-in's iteration target is a compile-time constant array, compiler unrolls the loop. Each iteration's loop variable becomes a constant.

### Verification test
```ss
class Point { x: int; y: int }

function describePoint(p: Point): string {
    let parts = ""
    for (name in p.fields()) {
        if (parts != "") { parts = parts + ", " }
        parts = parts + name + "=" + p[name]
    }
    return "Point(" + parts + ")"
}

function main() {
    const p = new Point(x: 10, y: 20)
    assertEqual(describePoint(p), "Point(x=10, y=20)")
}
```

**Pass criteria:** Compiles, runs correctly, and emitted LLVM IR contains no loop for the for-in (fully unrolled to per-field access).

### D088 verification checklist (MUST check before starting)
1. This task solves the first-principle need: structural field access ✅
2. No new ct* functions ✅
3. No new keywords (fields() is a method, obj[name] is existing index syntax, for-in is existing) ✅
4. User writes plain SS code, compiler absorbs complexity ✅

### Open Issues (by priority)
1. **I001 -- Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 -- String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 -- AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 -- Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 -- Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Project Status
- **Bootstrap**: 47 files, ~18700 LOC, 215 tests (210 passing, 5 pre-existing interp_* failures).
- **Comptime**: D087 Phase 1-4 complete. D088 accepted (Zig route). ct* functions frozen.
- **D088 Phase 5 is next**: obj.fields() + obj[name] + compile-time loop unrolling.

## Watch Out For
- **D088 anti-patterns**: No new ct* functions, no new @derive handlers with string concat, no @comptimeEmit enhancements, no new template placeholders.
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **obj.fields() is compile-time only**: Returns compile-time constant array. Not runtime reflection.
- **obj[name] requires constant name**: Only works when name is a compile-time constant string. Not runtime dynamic lookup.
- **for-in unrolling**: Compiler detects compile-time constant iteration target → unrolls. No `inline` keyword needed.

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
