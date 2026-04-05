# Round 103

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~14852 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- docs/spec-status.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
D073 Java-style error handling enhancement — 4 phases: (1) `finally` block, (2) built-in `Error` class in prelude, (3) `throw` supports class instances with auto message extraction for backward-compatible string catch, (4) typed catch `catch (e: IOError)` with multi-catch + `ss_isinstance` runtime walking TypeInfo parent chain. TypeInfo extended with parent TypeInfo pointer for inheritance chain checking. ~200 lines across 9 files, 100 phase5 tests all passing + bootstrap fixed-point verified.

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done, log module done, ini module done, Map.keys() fix done, checker type inference done (D053), METHOD_CALL type checking done (D054), this.field assign fix done (D055), global negative literal fix done (D056), generic array element type inference done (D057), optional method call double-eval fix done (D058), builtin method type inference done (D059), return type checking done (D060), class body fields complete (D061 all phases), generic type param compat done (D063), NEW_EXPR type checking done (D064), INDEX_ACCESS type inference + INDEX_ASSIGN type checking + builtin function return types done (D065), inferType migration analysis done — I003 closed (D066), argparse stdlib module done, null safety complete (D067 all 3 phases), **access modifiers complete — private + protected keywords (D068 Phase 1+2)**, **super keyword complete (D069)**, **static methods complete (D070)**, **abstract classes/methods complete (D071)**, **Java-style error handling complete (D073 — finally + Error class + throw objects + typed catch)**
Scope:
**P17: Fix before add. Open issues take priority over new features. Check `docs/4-issues/1-open/` each round.**

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Next Priority (语言改进优先，stdlib 延后)
6. **Module-level export**: Access modifiers Phase 3 — `export` keyword for module visibility (needs module system maturity)
7. **Standard library expansion**: 延后，语言核心完善后再做
8. **Phase 4 remaining**: Tagged templates (low priority).

### Project Status
- **D073 complete**: Java-style error handling. `finally` block (always runs after try/catch). Built-in `Error` class in prelude. `throw(new Error("msg"))` / `throw(new IOError(...))` with auto message extraction. Typed catch `catch (e: IOError) { e.path }` with multi-catch support. `ss_isinstance` runtime walks TypeInfo parent chain. TypeInfo extended with parent TypeInfo ptr.
- **D072 rejected**: Result<T,E> + ? operator — Rust syntax, doesn't fit TS/Java design principle.
- **D071 complete**: `abstract` keyword for classes and methods.
- **D070 complete**: `static` keyword for class methods.
- **D069 complete**: `super` keyword for calling parent class methods.
- **D068 complete (Phase 1+2)**: `private` and `protected` keywords for class fields and methods.
- **File sizes**: checker.ss ~1187 (largest), check_stmts.ss ~828, parser.ss ~653, gen_class.ss ~626.
- **Stdlib**: 21 modules, ~5217 LOC in lib/.
- **Bootstrap**: 35 files, ~14852 LOC, 100 phase5 tests (all passing).
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.
9. **Known stdlib convention**: `arr.slice(start, end)` uses start+end index semantics (NOT offset+length like `substring`). `arr.slice(0, mid)` gets first mid elements; `arr.slice(mid, n)` gets elements from mid to end.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, `?.method()` (no double-eval), spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**, **Map.keys() → Array<string>**, **basic type checking (D053)**, **METHOD_CALL type checking (D054)**, **this.field = value in methods (D055)**, **global negative literal init (D056)**, **generic array element type inference (D057)**, **optional method call fix (D058)**, **builtin method type inference (D059)**, **return type checking (D060)**, **class body fields (D061 complete, old syntax removed)**, **generic type param compat (D063)**, **NEW_EXPR type checking (D064)**, **INDEX_ACCESS type inference + INDEX_ASSIGN checking + builtin return types (D065)**, **null safety complete: T? types, checker enforcement, smart narrowing, ?. returns T?, ?? returns T (D067)**, **private + protected keywords for class fields/methods (D068 Phase 1+2)**, **super keyword for parent method calls (D069)**, **static methods for classes (D070)**, **abstract classes/methods (D071)**, **Java-style error handling: finally + Error class + throw objects + typed catch (D073)**. Compiler source CAN now use these features.
- **All open issues BLOCKED or LOW**: I001/I002/I005 need struct/enum support. I006/I008 are LOW priority. Language improvements are the primary work stream; stdlib expansion is deferred.
- **Rejected features**: Range syntax (`0..10`), pattern matching type patterns + guard — TS/JS 无对应语法。Result<T,E> + ? operator — Rust 语法。不要提议这些特性。
- **Priority**: 语言核心改进优先于 stdlib 模块扩展。All access modifiers (private + protected) complete. Module-level export deferred until module system matures.
- **Error handling (D073)**: `try { } catch (e: Type) { } finally { }`. Multiple typed catch clauses supported. Untyped `catch(e)` gives string (backward compatible). Typed `catch(e: IOError)` gives Error object. `throw("string")` works (backward compat). `throw(new Error("msg"))` extracts message for untyped catch. TypeInfo now has parent_typeinfo ptr (field index 6). `ss_isinstance(obj, targetName)` walks TypeInfo chain. `@ss_exc_is_obj` and `@ss_exc_obj` globals track thrown object. CATCH_CLAUSE AST node: S1=var name, S2=type, I1=body.
- **Class body fields (D061 complete)**: All code uses `class Foo { fields }` syntax. Old `class Foo(fields)` syntax removed from parser. Detection: `const` → field; `private`/`protected` → field or method; `IDENT` + `:` or `?` → field; `function`/`@` → method. Body fields create PARAM nodes in CLASS_DECL.List.
- **Access modifiers (D068 complete)**: `private` and `protected` modifiers for class fields and methods. AST: I3=0 public, I3=1 private, I3=2 protected on PARAM (field) and FUNC_DECL (method) nodes. Checker: `privateFields`/`privateMethods` + `protectedFields`/`protectedMethods` Maps keyed by `"ClassName.memberName"`. `lookupPrivateOwner()` and `lookupProtectedOwner()` walk parent chain. `isSubclassOf(child, ancestor)` walks parent chain for protected inheritance check. 4 enforcement sites: MEMBER_ACCESS, MEMBER_ASSIGN, METHOD_CALL, DESTRUCTURE_OBJECT. Private: same-class only (TS semantics). Protected: same-class + subclasses.
- **Super keyword (D069 complete)**: `super.method(args)` calls parent class method directly. Lexer: SUPER token. Parser: SUPER node in parseAtom(), postfix `.method()` creates METHOD_CALL with I1=SUPER. Checker: validates inside class method + has parent. Codegen: `genSuperMethodCall()` walks parent chain from parent class, always static dispatch (no vtable). `genExpr(SUPER)` = `genThisExpr()` (same object pointer). `resolveObjClass(SUPER)` returns parent class. D068 checks work unmodified (private blocked, protected allowed).
- **Static methods (D070 complete)**: `static function method()` in class body. Lexer: STATIC token. Parser: detects STATIC after access modifiers, sets I2=1 on FUNC_DECL. Checker: `staticMethods` Map, `currentStaticMethod` flag — rejects `this`/`super` in static methods. Codegen: `genClassMethod()` skips `this` parameter when I2=1. Call dispatch: `genMethodCall()` existing static detection (line 296) routes to `genStaticMethodCall()` which omits `this`. Modifier order: `[private|protected] static function name(...)`.
- **Abstract classes/methods (D071 complete)**: `abstract class` cannot be instantiated. `abstract function` has no body. AST: CLASS_DECL.I1=1 (abstract class), FUNC_DECL.I4=1 (abstract method). Parser: `parsingAbstractMethod` flag skips body in `parseFuncDecl()`. Checker: `abstractClasses`/`abstractMethods`/`classMethodNames` Maps. 6 rules: R1 no instantiate, R2 must implement, R3 no body (parser), R4 only in abstract class, R5 no private abstract, R6 no static abstract. `checkAbstractImpl()` walks parent chain. Codegen: `abstractMethodsCG` Map, `genClassMethod()` skips I4==1. Vtable: null entries for abstract methods; concrete subclasses override. Modifier order: `[private|protected] abstract function name(...)`.
- **inferType architecture (D066)**: `inferType()` (gen_types.ss) returns LLVM-level types for instruction selection. `checkerInferType()` (checker.ss) returns source-level types for compile-time error detection. Two separate functions by design — do not attempt to unify.
- **8 type check sites in checker**: VAR_DECL (D053), ASSIGN (D053), MEMBER_ASSIGN (D053), CALL args (D053), METHOD_CALL args (D054), RETURN (D060), NEW_EXPR args (D064), INDEX_ASSIGN (D065).
- **Null safety complete (D067)**: Phase 1: `T?` parsed by `maybeNullable()`. Checker: `isNullableType(t)`, `stripNullable(t)`, `makeNullable(t)`, `isPrimitiveNullable(t)`. `isTypeCompatible` enforces null→T ERROR, null→T? OK, T?→T ERROR, T→T? OK. Codegen: `stripNullableCG(t)` strips `?` from registries. Phase 2: Smart narrowing via `narrowedTypes` Map — 5 patterns (if-then/else/early-exit, reversed operand). Phase 3: `checkerInferType` checks `nGetI3` optional flag on MEMBER_ACCESS/METHOD_CALL, returns `makeNullable(type)` for `?.`. `??` (NullCoalesce) correctly returns `stripNullable(leftType)`.
- **Builtin function return types in checker (D065)**: All builtin functions now registered with actual return types (string/int/double/void). `checkerInferType(CALL)` resolves return types for both user functions and builtins.
- **Builtin method types in checker (D059)**: string/Array/Map/Set/Math methods have return types. String methods also have param types.
- **this.field = value works** in class methods (D055). No more `let self = this` workaround needed.
- **Optional method call fixed (D058)**: No more double evaluation of object expression in `obj?.method()`.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array push returns new array**: In SS, `arr.push(val)` returns a new array. The correct pattern is `arr = arr.push(val)`, NOT `arr.push(val)`. This is critical for any code that builds arrays dynamically. All stdlib modules follow this pattern.
- **Array methods use `.length()` not `.length`**: SS arrays use `.length()` method call syntax, not `.length` property access. Using `.length` without parentheses will compile but produce wrong results (loads ptr instead of calling ss_arrayLen).
- **Array slice uses (start, end) not (offset, length)**: `arr.slice(start, end)` uses start+end index semantics. This differs from `substring(offset, length)`. Example: `arr.slice(0, mid)` for first half, `arr.slice(mid, n)` for second half.
- **P4a principle**: Compiler limitation is a bug, not a boundary. When a compiler limitation forces ugly patterns in stdlib or user code, fix the compiler first. Do NOT record it as "Known limitation" and work around it.
- **Generic type param compat (D063)**: `currentTypeParams` tracks current function's type parameters. `isTypeCompatible()` returns 1 if either side is a type param. Save/restore in FUNC_DECL handler.
- **NEW_EXPR type checking (D064)**: `lookupConsParamType(className, paramIndex)` walks parent chain root→leaf. `checkerGenericClasses` Map tracks generic classes — their fields skipped in type checking.
- **INDEX_ACCESS type inference (D065)**: `extractElemType(t)` extracts type parameter from generic types (e.g., `Array<string>` → `string`). INDEX_ASSIGN checks value type vs element type.
- **Generic array element type (D057)**: `inferArrayElemType()` extracts type parameter generically. Codegen handles ptr-typed elements correctly (inttoptr i64 to ptr).
- **Dual RC systems**: Old (ss_rc_retain/ss_rc_release) for strings/arrays/maps via libc. New (ss_retain/ss_release) for class instances + closures + interface-typed vars via mimalloc.
- **Closure implementation**: Tag-bit closures. CLOSURE_HDR_SLOTS = 3. All closure code in gen_arrows.ss.
- **PIR**: Map-based IR. All keys use `id + ""`. Pass 1 liveness → Pass 2 move → Pass 3 uniqueness → Pass 5 reuse.
- **Split structure**: parser.ss + parse_stmts.ss + parse_exprs.ss. lexer.ss + lex_ops.ss. checker.ss + check_stmts.ss + check_suggest.ss. gen_stmts.ss + gen_decls.ss + gen_assigns.ss. gen_exprs.ss + gen_calls.ss + gen_arrows.ss + gen_methods.ss + gen_builtins.ss. gen_class.ss + gen_iface.ss + gen_generic_class.ss + gen_type_ops.ss. gen_pir.ss + pir_lower.ss + pir_opt.ss. gen_runtime.ss + gen_rt_*.ss.
- **phase5 tests**: 100 tests (all passing).
- **35 bootstrap files**, ~14852 LOC.

## Decision Criteria
- Standard library now has 21 modules, ~5217 LOC.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- D061 class body fields fully complete (all 3 phases). Old syntax removed.
- I003 fully resolved (D066): Phase 3 has 8 type check sites + builtin types. Phase 4 inferType migration analyzed and closed — two-function architecture is correct by design.
- **D067 null safety fully complete** (all 3 phases): T? types, checker enforcement, smart narrowing, operator type propagation.
- **D068 access modifiers fully complete** (Phase 1+2): `private` keyword (class-only), `protected` keyword (class + subclasses). 4 enforcement sites. `isSubclassOf()` for inheritance checking.
- **D069 super keyword complete**: `super.method(args)` for parent method calls. Static dispatch, works with D068 access checks.
- **D070 static methods complete**: `static function method()` for class-level methods. No `this`/`super`. Combinable with access modifiers.
- **D071 abstract classes/methods complete**: `abstract class` + `abstract function`. 6 checker rules. Vtable null entries. Completes OOP model.
- **D073 Java-style error handling complete**: `finally` block. Built-in `Error` class. `throw` class instances. Typed catch with multi-catch + inheritance matching. Backward compatible with string throw/catch.
- All remaining open issues are BLOCKED (I001/I002/I005 need struct/enum) or LOW (I006/I008).
- **OOP model fully complete**: extends + override + super + private + protected + static + abstract.
- **Error handling improved**: finally + Error class + typed catch (Java-style).
- **Next: review open issues or consider next language improvement.** Critical path: package manager (spec 07), testing framework (spec 17), or other language improvements.
- File sizes: checker.ss ~1187 (largest), check_stmts.ss ~828, parser.ss ~653, gen_class.ss ~626.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known limitation: SS strings are null-terminated. `hexToBytes` cannot produce strings with 0x00 bytes. HMAC uses on-the-fly hex decoding to avoid this.
- Known convention: `arr.slice(start, end)` is start+end index semantics, NOT offset+length. Differs from `substring(offset, length)`.
- 35 bootstrap files total, ~14852 LOC, 100 phase5 tests (all passing).
- **argparse.ss module** (347 LOC): ArgParse.create() factory, ArgParser with option/flag/parse/parseArray/help, ArgResult with getString/getInt/getBool/has/positionals. Supports --key=value, -k value, --, positional args.

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
7. **Stop.** Do NOT start the next task. External automation will clear + `/next`.
