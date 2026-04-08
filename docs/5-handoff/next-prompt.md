# Round 111

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~15530 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- docs/spec-status.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md
- docs/3-decisions/D081-file-watcher.md

## Last Round (max 3 sentences)
D080 exec() process output capture — `exec("cmd")` returns `ExecResult { stdout, exitCode }` via popen. Handled as genCall special case (like test/println) to avoid bootstrap chicken-and-egg with prelude calling seed-unknown builtins. Runtime `ss_popen_read` in gen_rt_io.ss, ExecResult class in prelude.ss, 108 tests all passing + bootstrap fixed-point verified.

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done, log module done, ini module done, Map.keys() fix done, checker type inference done (D053), METHOD_CALL type checking done (D054), this.field assign fix done (D055), global negative literal fix done (D056), generic array element type inference done (D057), optional method call double-eval fix done (D058), builtin method type inference done (D059), return type checking done (D060), class body fields complete (D061 all phases), generic type param compat (D063), NEW_EXPR type checking done (D064), INDEX_ACCESS type inference + INDEX_ASSIGN type checking + builtin function return types done (D065), inferType migration analysis done — I003 closed (D066), argparse stdlib module done, null safety complete (D067 all 3 phases), **access modifiers complete — private + protected keywords (D068 Phase 1+2)**, **super keyword complete (D069)**, **static methods complete (D070)**, **abstract classes/methods complete (D071)**, **Java-style error handling complete (D073 — finally + Error class + throw objects + typed catch)**, **instanceof operator complete (D074)**, **as type casting complete (D075)**, **enum string values complete (D076)**, **enum iteration methods complete (D077)**, **static fields complete (D078)**, **testing framework complete (D079)**, **exec process capture complete (D080)**
Scope:
**Implement D081: File Watcher (inotify).** This is P1 for van-cli dev server hot reload.

Implementation steps:
1. Read D081 decision doc for full design
2. Add inotify libc declarations in gen_runtime.ss (inotify_init, inotify_add_watch, read, poll, close)
3. Add runtime functions in gen_rt_system.ss (ss_inotify_init, ss_inotify_add_watch, ss_inotify_poll, ss_inotify_close)
4. Register builtins in gen_registry.ss and checker.ss
5. Create lib/watcher.ss with FileWatcher class
6. Write test: tests/phase5/watcher_basic.ss
7. Verify: `bin/ss test tests/` + `./build.sh bootstrap`

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Upcoming (after D081)
- **Module-level export**: Access modifiers Phase 3 — `export` keyword for module visibility
- **Standard library expansion**: deferred, language core first

### Project Status
- **D080 complete**: exec() process capture. `exec("cmd")` → ExecResult { stdout, exitCode }. genCall special case + ss_popen_read runtime.
- **D081 designed**: File watcher. inotify runtime + FileWatcher stdlib class.
- **D079 complete**: Testing framework. `test("name", () => { ... })` Jest-style.
- **D078 complete**: Static fields. `[private|protected] static [const] fieldName: Type [= value]`.
- **File sizes**: checker.ss ~1221 (largest), check_stmts.ss ~937, gen_class.ss ~714, parser.ss ~688, gen_calls.ss ~660.
- **Stdlib**: 22 modules, ~5270 LOC in lib/.
- **Bootstrap**: 35 files, ~15530 LOC, 108 phase5 tests (all passing).

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` now supports exec() (D080). Compiler source CAN use exec().
- **All open issues BLOCKED or LOW**: I001/I002/I005 need struct/enum support. I006/I008 are LOW priority.
- **Rejected features**: Range syntax (`0..10`), pattern matching type patterns + guard — TS/JS no equivalent. Result<T,E> + ? operator — Rust syntax. FFI via dlopen — musl static incompatible. Do not propose these features.
- **exec() implementation (D080)**: genCall special case in gen_calls.ss. `genExecCall(argList)` calls `@ss_popen_read(cmd)` → stdout, loads `@ss_last_exit_code` → code, calls `@ExecResult_new(stdout, code)`. ExecResult class defined in prelude.ss. Runtime `ss_popen_read` in gen_rt_io.ss: popen + fread loop + pclose + WEXITSTATUS. Dynamic buffer (4096 initial, doubles on fill). Exit code stored in `@ss_last_exit_code` global.
- **Bootstrap pattern for new builtins**: Don't add builtin calls to prelude.ss — seed won't know them. Use genCall special case instead (like exec, test, println).
- **phase5 tests**: 108 tests (all passing).
- **35 bootstrap files**, ~15530 LOC.

## Decision Criteria
- Standard library now has 22 modules, ~5270 LOC.
- **exec() complete (D080)**: van-cli can now call van-core via subprocess.
- **Next: implement D081 (file watcher).** inotify-based for van dev hot reload.
- 35 bootstrap files total, ~15530 LOC, 108 phase5 tests (all passing).

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
7. **Stop.** Do NOT start the next task. External automation will clear + `/next`.
