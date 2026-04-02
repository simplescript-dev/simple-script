# Round 92

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
D065 完成：为 checker 添加 INDEX_ACCESS 类型推断（`extractElemType()` 从 Array<T> 提取元素类型）、INDEX_ASSIGN 类型检查（第 8 个检查点）、以及所有内置函数实际返回类型注册（取代 "builtin" 占位符）。现在 `let x: int = readFile("f")` 和 `arr[0] = "hello"` (对 Array<int>) 等类型错误都能在编译期捕获。83 tests 全部通过，bootstrap 固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done, log module done, ini module done, Map.keys() fix done, checker type inference done (D053), METHOD_CALL type checking done (D054), this.field assign fix done (D055), global negative literal fix done (D056), generic array element type inference done (D057), optional method call double-eval fix done (D058), builtin method type inference done (D059), return type checking done (D060), class body fields complete (D061 all phases), generic type param compat done (D063), NEW_EXPR type checking done (D064), **INDEX_ACCESS type inference + INDEX_ASSIGN type checking + builtin function return types done (D065)**
Scope:
**P17: 先修后加。Open issues 优先于新功能。每轮开始先读 `docs/4-issues/1-open/`。**

### Open Issues (按优先级)
1. **I003 — 语义分析不完整** [MEDIUM]: Phase 3 完成。8 个类型检查点 + builtin 方法返回/参数类型注册（D059）+ 泛型类型参数兼容（D063）+ NEW_EXPR 参数类型检查（D064）+ INDEX_ACCESS/INDEX_ASSIGN 类型检查 + builtin 函数返回类型（D065）。剩余：Phase 4 inferType 迁移。
2. **I001 — 全局可变状态爆炸** [BLOCKED]: 55+ 全局变量。需要 struct 支持。
3. **I002 — 字符串类型系统** [BLOCKED]: 类型用 raw string 比较。需要 enum/struct。
4. **I005 — AST list 用字符串** [PARTIAL]: 已有 helper，性能问题待 proper array type。
5. **I006 — Runtime raw IR** [LOW]: 已大幅转换，剩 401 处 raw emitIR。
6. **I008 — Parser 优先级硬编码** [LOW]: 能用，递归下降是标准做法。

### 次优先级
7. **Standard library expansion**: argparse.ss, random.ss 等新模块。
8. **Phase 4 remaining**: Tagged templates（低优先级）。

### 项目状态
- **文件大小**: checker.ss ~929, check_stmts.ss ~680, gen_class.ss ~613, parser.ss ~599, gen_decls.ss ~593, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_runtime.ss ~507, gen_calls.ss ~507.
- **Stdlib**: 20 modules, ~4862 LOC in lib/.
- **Bootstrap**: 35 files, ~14046 LOC, 83 phase5 tests (all passing).
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.
9. **Known stdlib convention**: `arr.slice(start, end)` uses start+end index semantics (NOT offset+length like `substring`). `arr.slice(0, mid)` gets first mid elements; `arr.slice(mid, n)` gets elements from mid to end.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, `?.method()` (no double-eval), spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**, **Map.keys() → Array<string>**, **basic type checking (D053)**, **METHOD_CALL type checking (D054)**, **this.field = value in methods (D055)**, **global negative literal init (D056)**, **generic array element type inference (D057)**, **optional method call fix (D058)**, **builtin method type inference (D059)**, **return type checking (D060)**, **class body fields (D061 complete, old syntax removed)**, **generic type param compat (D063)**, **NEW_EXPR type checking (D064)**, **INDEX_ACCESS type inference + INDEX_ASSIGN checking + builtin return types (D065)**. Compiler source CAN now use these features.
- **Class body fields (D061 complete)**: All code uses `class Foo { fields }` syntax. Old `class Foo(fields)` syntax removed from parser. Detection: `const` → field; `IDENT` + `:` or `?` → field; `function`/`@` → method. Body fields create PARAM nodes in CLASS_DECL.List.
- **INDEX_ACCESS type inference (D065)**: `extractElemType(t)` extracts type parameter from generic types (e.g., `Array<string>` → `string`). INDEX_ACCESS case in `checkerInferType` returns element type for Array/List/Tuple. INDEX_ASSIGN checks value type vs element type (8th type check site). All builtins registered with actual return types in `funcNames` (no more "builtin" placeholder).
- **NEW_EXPR type checking (D064)**: `lookupConsParamType(className, paramIndex)` walks parent chain root→leaf, returns field type at paramIndex. `checkerGenericClasses` Map tracks generic classes — their fields are skipped in type checking to prevent false positives. Both positional and named args checked. 8 type check sites total.
- **Generic type param compat (D063)**: `currentTypeParams` tracks current function's type params (from FUNC_DECL S3). `isTypeCompatible()` returns 1 if either side is a type param. Save/restore in FUNC_DECL handler (same pattern as `currentFuncRetType`).
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array push returns new array**: In SS, `arr.push(val)` returns a new array. The correct pattern is `arr = arr.push(val)`, NOT `arr.push(val)`. This is critical for any code that builds arrays dynamically. All stdlib modules follow this pattern.
- **Array methods use `.length()` not `.length`**: SS arrays use `.length()` method call syntax, not `.length` property access. Using `.length` without parentheses will compile but produce wrong results (loads ptr instead of calling ss_arrayLen).
- **Array slice uses (start, end) not (offset, length)**: `arr.slice(start, end)` uses start+end index semantics. This differs from `substring(offset, length)`. Example: `arr.slice(0, mid)` for first half, `arr.slice(mid, n)` for second half.
- **P4a principle**: Compiler limitation is a bug, not a boundary. When a compiler limitation forces ugly patterns in stdlib or user code, fix the compiler first. Do NOT record it as "Known limitation" and work around it.
- **Checker type inference (D053, Round 77)**:
  - **checkerInferType()**: Returns SS type string for expressions using checker state only. Returns "" for unknown (type check skipped). Handles literals, IDENT, CALL, NEW_EXPR, BINARY, MEMBER_ACCESS, METHOD_CALL, INDEX_ACCESS, TERNARY, UNARY, etc.
  - **isTypeCompatible()**: Checks type compatibility. Supports: exact match, int→double widening, bool↔int, interface accept-all, class inheritance chain, generic base type match (Array/List/Tuple cross-compat), **generic type parameters (D063)**.
  - **funcParamTypes**: Stores parameter types for non-overloaded, non-generic user functions. Key: `"funcName:paramIndex"` → type. funcOverloaded marks functions with multiple definitions.
  - **IDENT type inference**: When var exists with "auto" type, returns "" (not "fn"). Only checks lookupFunc when var is truly not found. This prevents false positives when a local variable shadows a function name.
  - **Generic functions**: Excluded from param type storage (S3 non-empty = has type params). Prevents "expected T, got int" false positives.
- **METHOD_CALL type checking (D054, Round 78)**:
  - **methodParamTypes**: `"ClassName.methodName:paramIndex"` → type. Stored for non-generic classes only.
  - **methodRetTypes**: `"ClassName.methodName"` → return type. Enables METHOD_CALL inference in `checkerInferType`/`inferCheckerClass`.
  - **lookupMethodParamType/lookupMethodRetType**: Walk `checkerClassParents` chain for inherited methods.
  - **Chain call inference**: `a.getB().method()` resolves via `inferCheckerClass(METHOD_CALL)` → receiver class → `lookupMethodRetType`.
  - **Receiver resolution**: `inferCheckerClass` handles THIS, IDENT, NEW_EXPR, MEMBER_ACCESS, CALL, METHOD_CALL, STRING_LIT, ARRAY_LIT.
- **Builtin method type inference (D059, Round 84)**:
  - **Pseudo-classes**: "string" and "Array" registered in `classConsMin` for method dispatch.
  - **resolveCheckerClass()**: Normalizes generic types for method dispatch (Array<int> → Array). Used in `inferCheckerClass` at IDENT/MEMBER_ACCESS/CALL/METHOD_CALL return points.
  - **~60 builtin methods**: Return types registered for string (17), Array (15), Map (6), Set (5), Math (26). String param types also registered.
  - **Literal inference**: STRING_LIT→"string", ARRAY_LIT→"Array" in `inferCheckerClass`. Enables `"hello".split(",")` type checking.
  - **Simplified receiver resolution**: check_stmts.ss uses `inferCheckerClass(objId)` + namespace fallback (4 lines replaces 20+).
- **Return type checking (D060, Round 85)**:
  - **currentFuncRetType**: Global variable tracking enclosing function's declared return type. Save/restored per FUNC_DECL (supports nested functions + class methods).
  - **Conservative check**: Only errors when return type annotation exists, is non-void, return has a value, value type is inferable, and types are incompatible.
  - **8 type check sites total**: VAR_DECL, ASSIGN, MEMBER_ASSIGN, CALL args, METHOD_CALL args, RETURN, NEW_EXPR args, INDEX_ASSIGN.
- **Generic type param compat (D063, Round 89)**:
  - **currentTypeParams**: Global variable tracking current function's type parameters (from FUNC_DECL S3, comma-separated).
  - **isTypeCompatible()**: If either declared or actual matches a current type param → return 1 (compatible).
  - **Save/restore**: In FUNC_DECL handler, same save/restore pattern as `currentFuncRetType`.
  - **Scope**: Applies to all 8 type check sites, not just RETURN.
- **NEW_EXPR type checking (D064, Round 90)**:
  - **lookupConsParamType(className, paramIndex)**: Builds parent chain root→leaf, walks fields in order, returns type at index. Returns "" for generic class fields.
  - **checkerGenericClasses**: Map tracking generic classes (set during CLASS_DECL when `classTypeParams(s) != ""`).
  - **Positional args**: Iterate args, lookup expected type by index, infer actual via `checkerInferType`, check with `isTypeCompatible`.
  - **Named args**: In `checkNamedConstructorArgs`, after field-exists check, walk parent chain to find field owner, check value type vs field type. Skip generic class-owned fields.
- **INDEX_ACCESS type inference + INDEX_ASSIGN type checking (D065, Round 91)**:
  - **extractElemType(t)**: Extracts type parameter from generic types. `"Array<string>"` → `"string"`, `"List<int>"` → `"int"`. Handles nested generics.
  - **INDEX_ACCESS in checkerInferType**: Infers element type from Array<T>/List<T>/Tuple<T> via `extractElemType`. Returns "" for plain Array or unknown.
  - **INDEX_ASSIGN checking**: Looks up array variable type, extracts element type, checks value compatibility. 8th type check site.
  - **Builtin function return types**: All builtins now registered with actual return types (string/int/double/void/Map/Set) instead of "builtin". Enables `checkerInferType(CALL)` to resolve builtin return types.
- **Generic array element type (D057, Round 82)**:
  - **inferArrayElemType()**: Now extracts type parameter generically via `indexOf("<")` + `substring()`. Handles `Array<fn>`, `Array<ClassName>`, any `Array<T>`.
  - **Codegen call sites**: INDEX_ACCESS, for-in, destructuring all handle ptr-typed elements correctly (inttoptr i64 to ptr).
  - **for-in double**: Now explicitly bitcasts i64 to double (was falling through to raw i64 store).
  - **Destructuring ptr**: Does trackPtrVar + emitRetainForType (variable outlives expression). for-in does NOT retain (array alive during loop).
- **Optional method call fix (D058, Round 83)**:
  - **genMethodCall(id, preObj="")**: Added default parameter `preObj`. When non-empty, skips `genExpr(objId)` and uses pre-evaluated value.
  - **genOptionalMethodCall**: Passes already-evaluated `objVal` to `genMethodCall(id, objVal)`, avoiding double evaluation of object expression.
  - Same pattern as `genOptionalMemberAccess` (D033).
- **Map.keys() fix (D052, Round 76)**: `ss_mapKeysArray` returns Array<string>. Both `funcRetTypes` and `methodRetTypes` updated. Compiler source migrated from `.keys().split("\n")` to `.keys()`.
- **Dual RC systems**: Old (ss_rc_retain/ss_rc_release) for strings/arrays/maps via libc. New (ss_retain/ss_release) for class instances + closures + interface-typed vars via mimalloc.
- **Closure implementation**: Tag-bit closures. CLOSURE_HDR_SLOTS = 3. All closure code in gen_arrows.ss.
- **PIR**: Map-based IR. All keys use `id + ""`. Pass 1 liveness → Pass 2 move → Pass 3 uniqueness → Pass 5 reuse.
- **Split structure**: parser.ss + parse_stmts.ss + parse_exprs.ss. lexer.ss + lex_ops.ss. checker.ss + check_stmts.ss + check_suggest.ss. gen_stmts.ss + gen_decls.ss + gen_assigns.ss. gen_exprs.ss + gen_calls.ss + gen_arrows.ss + gen_methods.ss + gen_builtins.ss. gen_class.ss + gen_iface.ss + gen_generic_class.ss + gen_type_ops.ss. gen_pir.ss + pir_lower.ss + pir_opt.ss. gen_runtime.ss + gen_rt_*.ss.
- **phase5 tests**: 83 tests (all passing).
- **35 bootstrap files**, ~14046 LOC.

## Decision Criteria
- Standard library now has 20 modules, ~4862 LOC.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- D061 class body fields fully complete (all 3 phases). Old syntax removed.
- D065 INDEX_ACCESS type inference + INDEX_ASSIGN checking + builtin return types done. Phase 3 type checking now has 8 check sites + builtin method types + builtin function return types + generic type param compat + NEW_EXPR args + INDEX_ACCESS/INDEX_ASSIGN.
- I003 Phase 3 fully complete. Phase 4 remainder: full inferType migration to checker (large refactor: 50+ call sites across 9 files, type vocabulary mismatch between checker source-level types and codegen LLVM-level types).
- File sizes: checker.ss ~929 (largest), check_stmts.ss ~680, gen_class.ss ~613, parser.ss ~599, gen_decls.ss ~593.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known limitation: SS strings are null-terminated. `hexToBytes` cannot produce strings with 0x00 bytes. HMAC uses on-the-fly hex decoding to avoid this.
- Known convention: `arr.slice(start, end)` is start+end index semantics, NOT offset+length. Differs from `substring(offset, length)`.
- **8 type check sites in checker**: VAR_DECL (D053), ASSIGN (D053), MEMBER_ASSIGN (D053), CALL args (D053), METHOD_CALL args (D054), RETURN (D060), NEW_EXPR args (D064), INDEX_ASSIGN (D065).
- **Builtin function return types in checker (D065)**: All builtin functions now registered with actual return types (string/int/double/void). `checkerInferType(CALL)` resolves return types for both user functions and builtins.
- **Builtin method types in checker (D059)**: string/Array/Map/Set/Math methods have return types. String methods also have param types.
- **this.field = value works** in class methods (D055). No more `let self = this` workaround needed.
- **Optional method call fixed (D058)**: No more double evaluation of object expression in `obj?.method()`.
- 35 bootstrap files total, ~14046 LOC, 83 phase5 tests (all passing).

## When Done
**P18: 单上下文单任务。完成当前任务或上下文不足时，更新 handoff 并停止。**
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
7. **Stop.** Do NOT start the next task. External automation will clear + `/next`.
