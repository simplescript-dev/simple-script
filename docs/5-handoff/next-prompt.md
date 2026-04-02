# Round 85

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~13878 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
I003 Phase 3 继续推进：添加 RETURN 语句类型检查（D060），验证返回值类型与函数声明返回类型的兼容性。使用 `currentFuncRetType` 全局变量跟踪当前函数返回类型，支持嵌套函数和类方法。保守策略——仅在可推断类型且不兼容时报错。Bootstrap 固定点验证通过，80 tests 全部通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done, log module done, ini module done, Map.keys() fix done, checker type inference done (D053), METHOD_CALL type checking done (D054), this.field assign fix done (D055), global negative literal fix done (D056), generic array element type inference done (D057), optional method call double-eval fix done (D058), builtin method type inference done (D059), **return type checking done (D060)**
Scope:
**下一步：D061 class body fields 迁移（方案B）。这是语法重构最高优先级。**
**P17: 先修后加。Open issues 优先于新功能。每轮开始先读 `docs/4-issues/1-open/`。**

### Syntax Refactor (最高优先级)
1. **D061 — Class fields in body**: 将 `class Foo(x: int)` Kotlin 风格迁移为 `class Foo { x: int }` TS/Java 风格。涉及 parser、checker、codegen、全部 bootstrap/stdlib/tests。需要分阶段执行（先支持新语法、再迁移代码、最后移除旧语法）。详见 `docs/3-decisions/D061-class-body-fields.md`。
2. **D062 — 语法借鉴原则**: Java/TS 优先，不借鉴 Kotlin/Scala。已写入 CLAUDE.md。

### Open Issues (按优先级)
1. **I003 — 语义分析不完整** [MEDIUM]: Phase 3 大部分完成。6 个类型检查点（VAR_DECL, ASSIGN, MEMBER_ASSIGN, CALL args, METHOD_CALL args, RETURN）+ builtin 方法返回/参数类型注册（D059）。剩余：NEW_EXPR argument type checking（构造函数参数类型验证），Phase 4 inferType 迁移。**已降级为 MEDIUM，按需推进。**
2. **I001 — 全局可变状态爆炸** [BLOCKED]: 55+ 全局变量。需要 struct 支持才能彻底解决（P10）。短期可分组 + init 函数。
3. **I002 — 字符串类型系统** [BLOCKED]: 类型用 raw string 比较。需要 enum/struct。短期可统一解析函数。
4. **I005 — AST list 用字符串** [PARTIAL]: 已有 helper，性能问题待 proper array type。
5. **I006 — Runtime raw IR** [LOW]: 已大幅转换，剩 401 处 raw emitIR。
6. **I008 — Parser 优先级硬编码** [LOW]: 能用，递归下降是标准做法。

### 次优先级
7. **Standard library cleanup**: csv.ss/ini.ss 已检查，无需修改（用 count metadata 模式，不依赖 Map.keys()）。
8. **Standard library expansion**: argparse.ss, random.ss 等新模块。
9. **Phase 4 remaining**: Tagged templates（低优先级）。
10. **Phase 2 remaining**: Mutability inference（收益递减）。

### 项目状态
- **文件大小**: checker.ss ~854, check_stmts.ss ~627, gen_class.ss ~613, gen_decls.ss ~593, parser.ss ~559, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_runtime.ss ~507, gen_calls.ss ~507.
- **Stdlib**: 20 modules, ~4862 LOC in lib/.
- **Bootstrap**: 35 files, ~13878 LOC, 80 phase5 tests.
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.
9. **Known stdlib convention**: `arr.slice(start, end)` uses start+end index semantics (NOT offset+length like `substring`). `arr.slice(0, mid)` gets first mid elements; `arr.slice(mid, n)` gets elements from mid to end.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, `?.method()` (no double-eval), spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**, **Map.keys() → Array<string>**, **basic type checking (D053)**, **METHOD_CALL type checking (D054)**, **this.field = value in methods (D055)**, **global negative literal init (D056)**, **generic array element type inference (D057)**, **optional method call fix (D058)**, **builtin method type inference (D059)**, **return type checking (D060)**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array push returns new array**: In SS, `arr.push(val)` returns a new array. The correct pattern is `arr = arr.push(val)`, NOT `arr.push(val)`. This is critical for any code that builds arrays dynamically. All stdlib modules follow this pattern.
- **Array methods use `.length()` not `.length`**: SS arrays use `.length()` method call syntax, not `.length` property access. Using `.length` without parentheses will compile but produce wrong results (loads ptr instead of calling ss_arrayLen).
- **Array slice uses (start, end) not (offset, length)**: `arr.slice(start, end)` uses start+end index semantics. This differs from `substring(offset, length)`. Example: `arr.slice(0, mid)` for first half, `arr.slice(mid, n)` for second half.
- **P4a principle**: Compiler limitation is a bug, not a boundary. When a compiler limitation forces ugly patterns in stdlib or user code, fix the compiler first. Do NOT record it as "Known limitation" and work around it.
- **Checker type inference (D053, Round 77)**:
  - **checkerInferType()**: Returns SS type string for expressions using checker state only. Returns "" for unknown (type check skipped). Handles literals, IDENT, CALL, NEW_EXPR, BINARY, MEMBER_ACCESS, METHOD_CALL, TERNARY, UNARY, etc.
  - **isTypeCompatible()**: Checks type compatibility. Supports: exact match, int→double widening, bool↔int, interface accept-all, class inheritance chain, generic base type match (Array/List/Tuple cross-compat).
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
  - **6 type check sites total**: VAR_DECL, ASSIGN, MEMBER_ASSIGN, CALL args, METHOD_CALL args, RETURN.
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
- **phase5 tests**: 80 tests.
- **35 bootstrap files**, ~13878 LOC.

## Decision Criteria
- Standard library now has 20 modules, ~4862 LOC.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- I003 Phase 3 mostly complete: type inference + 6 type check sites + builtin method types (D059). Phase 4 remainder: full inferType migration to checker. Also: NEW_EXPR argument type checking.
- File sizes: checker.ss ~854 (largest), check_stmts.ss ~627, gen_class.ss ~613, gen_decls.ss ~593.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known limitation: SS strings are null-terminated. `hexToBytes` cannot produce strings with 0x00 bytes. HMAC uses on-the-fly hex decoding to avoid this.
- Known convention: `arr.slice(start, end)` is start+end index semantics, NOT offset+length. Differs from `substring(offset, length)`.
- **6 type check sites in checker**: VAR_DECL (D053), ASSIGN (D053), MEMBER_ASSIGN (D053), CALL args (D053), METHOD_CALL args (D054), RETURN (D060).
- **Builtin method types in checker (D059)**: string/Array/Map/Set/Math methods have return types. String methods also have param types.
- **this.field = value works** in class methods (D055). No more `let self = this` workaround needed.
- **Optional method call fixed (D058)**: No more double evaluation of object expression in `obj?.method()`.
- 35 bootstrap files total, ~13878 LOC, 80 phase5 tests.

## When Done
**P18: 单上下文单任务。完成当前任务或上下文不足时，更新 handoff 并停止。**
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
7. **Stop.** Do NOT start the next task. External automation will clear + `/next`.
