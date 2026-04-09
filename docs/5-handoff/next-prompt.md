# Round 117

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~16200 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D082-concurrency-model.md
- bootstrap/check_stmts.ss (checkThreadClosureCaptures / checkThreadCapturesRec at end of file)
- bootstrap/gen_arrows.ss (thisIsThreadClosure deep-clone logic)
- bootstrap/gen_methods.ss (genThreadStart sets isThreadClosure flag)

## Last Round (max 3 sentences)
Implemented D082 Phase 3: Thread closure capture analysis. Checker rejects `let` variable captures in Thread.start closures with clear error messages. Codegen auto deep-clones captured class instances for thread isolation (Ref<T>/string/value-types shared as-is). 173 tests passing, fixed-point verified, seed updated.

## Task
Phase: D082 concurrency — Phase 3 (capture analysis) complete. **Next: choose one of these directions:**

1. **D082 Phase 4 — Channel<T>** for thread communication (BlockingQueue-style):
   - `const ch = new Channel<int>()`
   - `ch.send(42)` / `const val = ch.receive()`
   - Bounded or unbounded queue, mutex+condvar based
   - Enables producer-consumer patterns between threads

2. **D082 Phase 4 — computed()** reactive primitive:
   - `const isHigh = computed(() => count.value > 100)`
   - Auto-derive values from refs, lazy recalculation
   - Sugar over watch + ref

3. **Fix open issues** (recommended if any blockers found):
   - Review `docs/4-issues/1-open/` before adding new features

4. **New feature** outside D082 — evaluate other spec items in `spec/`.

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Project Status
- **D082 Phase 1 done**: `ref()` + `watch()` — gen_rt_ref.ss
- **D082 Phase 2 done**: `Thread.start(fn)` + `.join()` — gen_rt_thread.ss, M:N thread pool
- **D082 Phase 3 done**: Thread closure capture analysis — checker rejects `let` captures, codegen deep-clones class instances
- **Bootstrap**: 37 files, ~16200 LOC, 173 tests (all passing).
- **Bootstrap perf**: Three-stage bootstrap ~27s.

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Bootstrap pattern for new builtins**: Don't add builtin calls to prelude.ss — seed won't know them. Use genCall special case instead.
- **Nested arrows**: irBuf/strOutFile save/restore fixed in gen_arrows.ss. isThreadClosure also correctly saved/reset for nested arrows.
- **Thread.start double return**: i64 storage means double return values from thread callbacks don't work (double returns in xmm0, not rax).
- **Array/Map thread capture**: Not yet auto-cloned (no deep clone for container types). Users should use Ref<T> for shared mutable containers.
- **Checker captures are approximate**: Shadowed variables inside arrow body may cause false positives (rare, acceptable).
- **Rejected features**: Range syntax, pattern matching type patterns, Result<T,E> + ? operator, FFI via dlopen. Do not propose.
- **No new keywords**: Thread.start is a static method call, not a keyword.

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md
6. List files created/modified
7. **Stop.**
