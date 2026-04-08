# Round 109

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~15513 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- docs/spec-status.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
D079 testing framework — `test("name", () => { ... })` Jest/Deno-style built-in function. Compiler recognizes `test()` in genCall(), generates inline try/catch wrapper with closure/direct dispatch, automatic pass/fail counting, atexit summary. lib/test.ss provides assertEqual/assertTrue/assertFalse assertions that throw on failure. ~130 lines in gen_calls.ss + ~45 lines gen_runtime.ss, 1 new phase5 test, 107 total phase5 tests all passing + bootstrap fixed-point verified.

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done, log module done, ini module done, Map.keys() fix done, checker type inference done (D053), METHOD_CALL type checking done (D054), this.field assign fix done (D055), global negative literal fix done (D056), generic array element type inference done (D057), optional method call double-eval fix done (D058), builtin method type inference done (D059), return type checking done (D060), class body fields complete (D061 all phases), generic type param compat done (D063), NEW_EXPR type checking done (D064), INDEX_ACCESS type inference + INDEX_ASSIGN type checking + builtin function return types done (D065), inferType migration analysis done — I003 closed (D066), argparse stdlib module done, null safety complete (D067 all 3 phases), **access modifiers complete — private + protected keywords (D068 Phase 1+2)**, **super keyword complete (D069)**, **static methods complete (D070)**, **abstract classes/methods complete (D071)**, **Java-style error handling complete (D073 — finally + Error class + throw objects + typed catch)**, **instanceof operator complete (D074)**, **as type casting complete (D075)**, **enum string values complete (D076)**, **enum iteration methods complete (D077)**, **static fields complete (D078)**, **testing framework complete (D079)**
Scope:
**P17: Fix before add. Open issues take priority over new features. Check `docs/4-issues/1-open/` each round.**

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Next Priority (language improvements first, stdlib deferred)
6. **Module-level export**: Access modifiers Phase 3 — `export` keyword for module visibility (needs module system maturity)
7. **Standard library expansion**: deferred, language core first
8. **Phase 4 remaining**: Tagged templates (low priority).

### Project Status
- **D079 complete**: Testing framework. `test("name", () => { ... })` Jest-style. Compiler-recognized builtin in genCall(), inline setjmp/try-catch + closure/direct dispatch. `@ss_test_total/passed/failed` globals. `@ss_test_summary` atexit prints results, exits 1 on failure. `emitExcDepthDec()` reused from gen_stmts.ss. lib/test.ss: `assertEqual(int|string|double)`, `assertTrue`, `assertFalse`, `assertNull`, `assertNotNull`.
- **D078 complete**: Static fields. `[private|protected] static [const] fieldName: Type [= value]`. Access via `ClassName.field`. Static fields are global variables.
- **D077 complete**: Enum iteration methods. `Color.values()` and `Color.names()`.
- **D076 complete**: Enum string values. `enum Direction { Up = "up" }`.
- **D075 complete**: `as` type casting. `expr as ClassName` at comparison precedence.
- **D074 complete**: `instanceof` operator. `obj instanceof ClassName` at comparison precedence.
- **D073 complete**: Java-style error handling. `finally` block. Built-in `Error` class. Typed catch.
- **D072 rejected**: Result<T,E> + ? operator — Rust syntax.
- **D071 complete**: `abstract` keyword for classes and methods.
- **D070 complete**: `static` keyword for class methods.
- **D069 complete**: `super` keyword for calling parent class methods.
- **D068 complete (Phase 1+2)**: `private` and `protected` keywords for class fields and methods.
- **File sizes**: checker.ss ~1221 (largest), check_stmts.ss ~937, gen_class.ss ~714, parser.ss ~688, gen_calls.ss ~639.
- **Stdlib**: 22 modules, ~5270 LOC in lib/.
- **Bootstrap**: 35 files, ~15513 LOC, 107 phase5 tests (all passing).
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.
9. **Known stdlib convention**: `arr.slice(start, end)` uses start+end index semantics (NOT offset+length like `substring`). `arr.slice(0, mid)` gets first mid elements; `arr.slice(mid, n)` gets elements from mid to end.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, `?.method()` (no double-eval), spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**, **Map.keys() → Array<string>**, **basic type checking (D053)**, **METHOD_CALL type checking (D054)**, **this.field = value in methods (D055)**, **global negative literal init (D056)**, **generic array element type inference (D057)**, **optional method call fix (D058)**, **builtin method type inference (D059)**, **return type checking (D060)**, **class body fields (D061 complete, old syntax removed)**, **generic type param compat (D063)**, **NEW_EXPR type checking (D064)**, **INDEX_ACCESS type inference + INDEX_ASSIGN checking + builtin return types (D065)**, **null safety complete: T? types, checker enforcement, smart narrowing, ?. returns T?, ?? returns T (D067)**, **private + protected keywords for class fields/methods (D068 Phase 1+2)**, **super keyword for parent method calls (D069)**, **static methods for classes (D070)**, **abstract classes/methods (D071)**, **Java-style error handling: finally + Error class + throw objects + typed catch (D073)**, **instanceof operator (D074)**, **as type casting (D075)**, **enum string values (D076)**, **enum iteration methods: values()/names() (D077)**, **static fields: class-level state via global variables (D078)**, **testing framework: test() + assertions (D079)**. Compiler source CAN now use these features.
- **All open issues BLOCKED or LOW**: I001/I002/I005 need struct/enum support. I006/I008 are LOW priority. Language improvements are the primary work stream; stdlib expansion is deferred.
- **Rejected features**: Range syntax (`0..10`), pattern matching type patterns + guard — TS/JS no equivalent. Result<T,E> + ? operator — Rust syntax. Do not propose these features.
- **Priority**: Language core improvements over stdlib module expansion. All access modifiers (private + protected) complete. Module-level export deferred until module system matures.
- **Testing framework (D079)**: `test("name", callback)` recognized in genCall() like println. Generates inline try/catch (setjmp/longjmp) + closure/direct fn_ptr dispatch. Callback signature: `(): void`. Pass: inc @ss_test_passed, print "  PASS: name". Fail: inc @ss_test_failed, print "  FAIL: name - error". Summary via atexit @ss_test_summary (checks total>0, prints counts, exit(1) on failures). Assertions in lib/test.ss use throw() on failure. assertNull/assertNotNull string-only (no generic nullable support yet).
- **Error handling (D073)**: `try { } catch (e: Type) { } finally { }`. Multiple typed catch clauses supported. Untyped `catch(e)` gives string (backward compatible). Typed `catch(e: IOError)` gives Error object. `throw("string")` works (backward compat). `throw(new Error("msg"))` extracts message for untyped catch. TypeInfo now has parent_typeinfo ptr (field index 6). `ss_isinstance(obj, targetName)` walks TypeInfo chain. `@ss_exc_is_obj` and `@ss_exc_obj` globals track thrown object. CATCH_CLAUSE AST node: S1=var name, S2=type, I1=body.
- **instanceof (D074)**: `expr instanceof ClassName` at comparison precedence. BINARY node S1="Instanceof". Codegen: genExpr(left) → addStringConst(rightName) → call ss_isinstance. Returns i32 (1/0). Works with inheritance (TypeInfo parent chain walk).
- **as type casting (D075)**: `expr as ClassName` at comparison precedence. BINARY node S1="As". Codegen: genExpr(left) → ss_isinstance check → branch: fail throws "type cast failed: expected ClassName", ok returns same pointer. `inferType` and `resolveObjClass` return target class name. Enables downcast pattern: `if (x instanceof Dog) { let d = x as Dog; d.bark() }`.
- **Enum string values (D076)**: `enum Direction { Up = "up" }`. ENUM_VARIANT S2=stringValue. ENUM_DECL I1=1 for string enum. `enumTypes` Map: "EnumName" → "1" (Set semantics, only string enums stored). `genMemberAccess()` returns `addStringConst(value)` for string enums. `inferType()` returns "string" for string enum access. Mixed int+string is compile error. Switch/case works via `subjectType == "string"` path.
- **Enum iteration (D077)**: `Color.values()` and `Color.names()`. `enumDeclNodes` Map: "EnumName" → AST node ID. `genEnumValues`/`genEnumNames` walk AST to generate array IR. Dispatch in `genMethodCall()` before static method check. `inferType()` returns "ptr" for both methods.
- **Static fields (D078)**: `[private|protected] static [const] fieldName: Type [= value]`. PARAM.I4=1 for static flag. Parser: `isBodyFieldStart()` detects STATIC before field tokens (not STATIC FUNCTION). Checker: `staticFields` Map, `instanceParamList` for constructor param counting (excludes static). `ClassName.field` access validated; `instance.staticField` rejected. Codegen: `staticFieldGlobals`/`staticFieldTypes` Maps. `registerStaticField()` emits `@ClassName_fieldName = global ...`. Literal inits (int/double/bool/string/negated) emitted directly; others queued in `sfPendingInits`/`sfInitExprs` for `emitStaticFieldInits()` called at main() start. `genMemberAccess()` loads from global. `genStaticFieldAssign()` handles ASSIGN, compound (+=/-=/*=//=/%%=), and POWER_ASSIGN. `inferType()`/`resolveObjClass()`/`checkerInferType()` resolve static field types.
- **Class body fields (D061 complete)**: All code uses `class Foo { fields }` syntax. Old `class Foo(fields)` syntax removed from parser.
- **Access modifiers (D068 complete)**: `private` and `protected` modifiers for class fields and methods. AST: I3=0 public, I3=1 private, I3=2 protected on PARAM (field) and FUNC_DECL (method) nodes. Checker: `privateFields`/`privateMethods` + `protectedFields`/`protectedMethods` Maps keyed by `"ClassName.memberName"`. `lookupPrivateOwner()` and `lookupProtectedOwner()` walk parent chain. `isSubclassOf(child, ancestor)` walks parent chain for protected inheritance check. 4 enforcement sites: MEMBER_ACCESS, MEMBER_ASSIGN, METHOD_CALL, DESTRUCTURE_OBJECT.
- **Super keyword (D069 complete)**: `super.method(args)` calls parent class method directly. Always static dispatch.
- **Static methods (D070 complete)**: `static function method()` in class body. Modifier order: `[private|protected] static function name(...)`.
- **Abstract classes/methods (D071 complete)**: `abstract class` cannot be instantiated. `abstract function` has no body. 6 checker rules.
- **inferType architecture (D066)**: `inferType()` (gen_types.ss) returns LLVM-level types. `checkerInferType()` (checker.ss) returns source-level types. Two separate functions by design.
- **8 type check sites in checker**: VAR_DECL, ASSIGN, MEMBER_ASSIGN, CALL args, METHOD_CALL args, RETURN, NEW_EXPR args, INDEX_ASSIGN.
- **Null safety complete (D067)**: T? types, checker enforcement, smart narrowing, ?. returns T?, ?? returns T.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps).
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms.
- **Array push returns new array**: `arr = arr.push(val)`, NOT `arr.push(val)`.
- **Array methods use `.length()` not `.length`**: Method call syntax required.
- **Array slice uses (start, end) not (offset, length)**.
- **P4a principle**: Compiler limitation is a bug, not a boundary.
- **Dual RC systems**: Old (ss_rc_retain/ss_rc_release) for strings/arrays/maps via libc. New (ss_retain/ss_release) for class instances + closures via mimalloc.
- **Closure implementation**: Tag-bit closures. CLOSURE_HDR_SLOTS = 3. All closure code in gen_arrows.ss.
- **PIR**: Map-based IR. All keys use `id + ""`. Pass 1 liveness → Pass 2 move → Pass 3 uniqueness → Pass 5 reuse.
- **phase5 tests**: 107 tests (all passing).
- **35 bootstrap files**, ~15513 LOC.

## Decision Criteria
- Standard library now has 22 modules, ~5270 LOC.
- Phase 4 essentially complete.
- **OOP model fully complete**: extends + override + super + private + protected + static methods + static fields + abstract + instanceof + as.
- **Error handling complete**: finally + Error class + typed catch (Java-style).
- **Enum fully featured**: int values, string values, values()/names() iteration.
- **Testing framework complete (D079)**: `test()` + assertions. First toolchain feature beyond build/test runner.
- All remaining open issues are BLOCKED (I001/I002/I005) or LOW (I006/I008).
- **Next: review open issues or consider next language/toolchain improvement.** Options: package manager (spec 07), module export (spec 11/42), more numeric types (spec 01/40), or other language improvements.
- File sizes: checker.ss ~1221 (largest), check_stmts.ss ~937, gen_class.ss ~714, parser.ss ~688, gen_calls.ss ~639.
- 35 bootstrap files total, ~15513 LOC, 107 phase5 tests (all passing).
- **argparse.ss module** (347 LOC): ArgParse.create() factory, ArgParser with option/flag/parse/parseArray/help, ArgResult with getString/getInt/getBool/has/positionals.

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
7. **Stop.** Do NOT start the next task. External automation will clear + `/next`.
