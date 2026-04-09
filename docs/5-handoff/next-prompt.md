# Round 116

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~16000 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D082-concurrency-model.md
- bootstrap/gen_rt_thread.ss
- bootstrap/gen_arrows.ss (irBuf/strOutFile save/restore fix)

## Last Round (max 3 sentences)
Implemented D082 Phase 2: `Thread.start(fn)` + `.join()` with M:N thread pool scheduler. Runtime generates 6 functions (schedInit/Enqueue/Dequeue/workerLoop/threadStart/threadJoin) with N worker pthreads, tag-bit closure dispatch, per-VThread mutex/condvar for join synchronization. Fixed a pre-existing nested arrow bug (irBuf/strOutFile not saved/restored in genArrowFunc). 172 tests passing, fixed-point verified, seed updated.

## Task
Phase: D082 concurrency — Phase 2 (Thread.start/join) complete. **Next: D082 Phase 3 — Thread closure capture analysis.**

Capture rules from D082:
- Value types (int/double/bool): copy — already works (passed by value)
- string: shared — already works (immutable, ptr copy)
- `Ref<T>`: shared — already works (ptr copy, thread-safe internals)
- Other objects: auto deep clone — **NOT YET IMPLEMENTED**
- let variables: compile error — **NOT YET IMPLEMENTED**

Implementation scope for Phase 3:
1. **Checker**: When arrow function is argument to Thread.start, validate captured variables:
   - Reject `let` variables (compile error: "let variables cannot be captured by thread closures")
   - Warn/error on mutable objects (non-Ref, non-string, non-value-type)
2. **Codegen**: In genArrowFunc, when generating a thread closure:
   - Auto deep-clone captured class instances (call `ss_deep_clone_ClassName`)
   - Share Ref<T> captures (just copy ptr, no clone)
3. **Type tracking**: Need a way to mark an arrow as "thread closure" so codegen can apply different capture semantics

Alternative: skip Phase 3 capture analysis, move to **Channel<T>** for thread communication, or **computed()** reactive primitive.

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Project Status
- **D082 Phase 1 done**: `ref()` + `watch()` — gen_rt_ref.ss
- **D082 Phase 2 done**: `Thread.start(fn)` + `.join()` — gen_rt_thread.ss, thread pool M:N scheduler
- **Nested arrow bug fixed**: genArrowFunc now saves/restores irBuf + strOutFile (was losing outer arrow IR on nested arrow compilation)
- **Bootstrap**: 37 files, ~16200 LOC, 172 tests (all passing).
- **Bootstrap perf**: Three-stage bootstrap ~27s.

## Watch Out For
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **Bootstrap pattern for new builtins**: Don't add builtin calls to prelude.ss — seed won't know them. Use genCall special case instead (like ref, watch, exec, test, println, Thread.start).
- **Nested arrows now work**: irBuf/strOutFile save/restore fixed in gen_arrows.ss. Test with nested scenarios.
- **Thread.start double return**: i64 storage means double return values from thread callbacks don't work (double returns in xmm0, not rax). Document or fix if needed.
- **No capture analysis yet**: Thread closures capture by value copy (same as regular closures). Objects are shared (ptr copy), not cloned. let variables are not rejected.
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
