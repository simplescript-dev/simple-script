# Round 94

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~14046 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- docs/spec-status.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
新增 stdlib 模块 `argparse.ss`（347 LOC）——命令行参数解析库，支持 options（`--key value`、`--key=value`）、flags（`-v`）、positionals、`--` 停止解析、help 文本生成、`parseArray()` 用于测试。API: `ArgParse.create()` 工厂 → `ArgParser` 实例方法（`.option()/.flag()/.parse()/.help()`）→ `ArgResult` 查询（`.getString()/.getInt()/.getBool()/.has()/.positionals()`）。84 个 phase5 测试全部通过 + bootstrap 固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done, log module done, ini module done, Map.keys() fix done, checker type inference done (D053), METHOD_CALL type checking done (D054), this.field assign fix done (D055), global negative literal fix done (D056), generic array element type inference done (D057), optional method call double-eval fix done (D058), builtin method type inference done (D059), return type checking done (D060), class body fields complete (D061 all phases), generic type param compat done (D063), NEW_EXPR type checking done (D064), INDEX_ACCESS type inference + INDEX_ASSIGN type checking + builtin function return types done (D065), inferType migration analysis done — I003 closed (D066), **argparse stdlib module done**
Scope:
**P17: Fix before add. Open issues take priority over new features. Check `docs/4-issues/1-open/` each round.**

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Next Priority
6. **Standard library expansion**: random.ss, toml.ss, etc.
7. **Phase 4 remaining**: Tagged templates (low priority).

### Project Status
- **I003 resolved (D066)**: Phase 3 complete (8 type check sites), Phase 4 inferType migration analyzed and closed.
- **File sizes**: checker.ss ~929, check_stmts.ss ~680, gen_class.ss ~613, parser.ss ~599, gen_decls.ss ~593, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_runtime.ss ~507, gen_calls.ss ~507.
- **Stdlib**: 21 modules, ~5217 LOC in lib/.
- **Bootstrap**: 35 files, ~14046 LOC, 84 phase5 tests (all passing).
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.
9. **Known stdlib convention**: `arr.slice(start, end)` uses start+end index semantics (NOT offset+length like `substring`). `arr.slice(0, mid)` gets first mid elements; `arr.slice(mid, n)` gets elements from mid to end.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, `?.method()` (no double-eval), spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**, **Map.keys() → Array<string>**, **basic type checking (D053)**, **METHOD_CALL type checking (D054)**, **this.field = value in methods (D055)**, **global negative literal init (D056)**, **generic array element type inference (D057)**, **optional method call fix (D058)**, **builtin method type inference (D059)**, **return type checking (D060)**, **class body fields (D061 complete, old syntax removed)**, **generic type param compat (D063)**, **NEW_EXPR type checking (D064)**, **INDEX_ACCESS type inference + INDEX_ASSIGN checking + builtin return types (D065)**. Compiler source CAN now use these features.
- **All open issues BLOCKED or LOW**: I001/I002/I005 need struct/enum support. I006/I008 are LOW priority. New features and stdlib expansion are now the primary work stream.
- **Class body fields (D061 complete)**: All code uses `class Foo { fields }` syntax. Old `class Foo(fields)` syntax removed from parser. Detection: `const` → field; `IDENT` + `:` or `?` → field; `function`/`@` → method. Body fields create PARAM nodes in CLASS_DECL.List.
- **inferType architecture (D066)**: `inferType()` (gen_types.ss) returns LLVM-level types for instruction selection. `checkerInferType()` (checker.ss) returns source-level types for compile-time error detection. Two separate functions by design — do not attempt to unify.
- **8 type check sites in checker**: VAR_DECL (D053), ASSIGN (D053), MEMBER_ASSIGN (D053), CALL args (D053), METHOD_CALL args (D054), RETURN (D060), NEW_EXPR args (D064), INDEX_ASSIGN (D065).
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
- **phase5 tests**: 84 tests (all passing).
- **35 bootstrap files**, ~14046 LOC.

## Decision Criteria
- Standard library now has 21 modules, ~5217 LOC.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- D061 class body fields fully complete (all 3 phases). Old syntax removed.
- I003 fully resolved (D066): Phase 3 has 8 type check sites + builtin types. Phase 4 inferType migration analyzed and closed — two-function architecture is correct by design.
- All remaining open issues are BLOCKED (I001/I002/I005 need struct/enum) or LOW (I006/I008).
- **Primary work stream is now stdlib expansion and new language features.**
- File sizes: checker.ss ~929 (largest), check_stmts.ss ~680, gen_class.ss ~613, parser.ss ~599, gen_decls.ss ~593.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known limitation: SS strings are null-terminated. `hexToBytes` cannot produce strings with 0x00 bytes. HMAC uses on-the-fly hex decoding to avoid this.
- Known convention: `arr.slice(start, end)` is start+end index semantics, NOT offset+length. Differs from `substring(offset, length)`.
- 35 bootstrap files total, ~14046 LOC, 84 phase5 tests (all passing).
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
