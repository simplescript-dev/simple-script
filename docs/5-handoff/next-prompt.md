# Round 63

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~13392 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
String utility module（D038）：新增 lib/string_utils.ss（220 LOC，16 个 StringUtil 静态方法）——trimStart/trimEnd/capitalize/reverse/isBlank/isDigit/isAlpha/isAlphaNumeric/padCenter/truncate/count/removePrefix/removeSuffix/equalsIgnoreCase/lines/words。纯 SS 实现，无编译器改动，遵循 D035 静态方法模式。全量测试 + bootstrap 固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done
Scope:
1. **Standard library expansion (continued)**:
   - **New modules**: Consider `datetime.ss` (timestamp formatting), `regex.ss` (basic pattern matching)
   - **json.ss remaining**: Unicode `\uXXXX` escape parsing (requires hex utils)
2. **Phase 4 remaining features**:
   - **String template tag functions** — Tagged templates (advanced, low priority)
3. **Phase 2 remaining** (diminishing returns):
   - Mutability inference — Fixed-point analysis marking function params as mutated/readonly
4. **文件大小状态**: gen_class.ss ~615 (approaching limit), gen_decls.ss ~576, parser.ss ~559, check_stmts.ss ~553, checker.ss ~531, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_calls.ss ~507. gen_class.ss may need a split if further features add to it.
5. **Standard library状态**: json.ss (512 LOC), sha256.ss (228 LOC), string_utils.ss (220 LOC), http.ss (151 LOC), path.ss (148 LOC), math.ss (115 LOC), base64.ss (63 LOC), fs.ss (60 LOC). Total ~1497 LOC in lib/, 8 modules.
6. **建议**: datetime module would add practical value (timestamp formatting/parsing). Or consider json.ss Unicode \uXXXX escape, or new language features like `for-of` for Map iteration, numeric separators (1_000_000). gen_class.ss at 615 lines may need splitting if more codegen features are added there.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **String utils (D038, Round 62)**:
  - **16 methods**: trimStart, trimEnd, capitalize, reverse, isBlank, isDigit, isAlpha, isAlphaNumeric, padCenter, truncate, count, removePrefix, removeSuffix, equalsIgnoreCase, lines, words.
  - **Pure SS**: No compiler changes. Uses static method pattern (`StringUtil.capitalize("hello")`).
  - **Character class checks**: isDigit (48-57), isAlpha (65-90, 97-122), isAlphaNumeric (both). Use `charCodeAt()` method.
  - **Whitespace set**: space, tab (\t), newline (\n), carriage return (\r) — consistent with prelude `_ss_trim`.
  - **lines()**: Handles `\r\n` by stripping trailing `\r` before splitting on `\n`.
  - **words()**: Splits by whitespace, skips consecutive whitespace (like Go's `strings.Fields`).
  - **count()**: Non-overlapping occurrences. `count("aaa", "aa")` → 1.
- **Math enhancements (D037, Round 61)**:
  - **New builtins**: `Math.tan(x)`, `Math.asin(x)`, `Math.acos(x)`, `Math.atan(x)`, `Math.atan2(y,x)`, `Math.exp(x)`, `Math.log10(x)`, `Math.log2(x)`, `Math.trunc(x)`, `Math.sign(x)`, `Math.hypot(x,y)`, `Math.cbrt(x)`, `Math.fmod(x,y)`.
  - **All return double**: Auto int→double conversion via `isMathClass` in `genStaticMethodCall()`.
  - **sign**: Custom LLVM IR (fcmp ogt/olt + select). **cbrt**: pow(x, 1/3). Others wrap libc.
  - **lib/math.ss (MathUtil)**: `clamp(v,lo,hi)`, `lerp(a,b,t)`, `inverseLerp(a,b,v)`, `mapRange(v,inMin,inMax,outMin,outMax)`, `toDegrees(rad)`, `toRadians(deg)`, `approxEqual(a,b,eps)`, `isEven(n)`, `isOdd(n)`, `gcd(a,b)`, `lcm(a,b)`, `isPowerOfTwo(n)`.
  - **Constants as methods**: `MathUtil.PI()`, `MathUtil.E()`, `MathUtil.TAU()`, `MathUtil.EPSILON()` — zero-arg methods since built-in class property access not supported.
  - **Known limitation**: `Math.PI` (property-style) not supported — would require member access dispatch for built-in classes.
- **JSON library (D036, Round 60)**:
  - **Getters**: `getDouble(key)` uses `parseDouble()`, `getBool(key)` reads stored int, `has(key)` checks field existence, `keys()` returns `Array<string>`.
  - **Direct access**: `asDouble()`, `asBool()` for array elements or direct node value access.
  - **Builders**: `put(key, double)`, `putBool(key, int)`, `putNull(key)`, `add(double)`, `addBool(int)`, `addNull()`. Bool uses separate method names to avoid signature clash with int.
  - **Escape**: `jnEscapeString()` in stringify handles `\`, `"`, `\n`, `\t`, `\r`. Parser handles `\r`, `\/`.
  - **Scientific notation**: `jpParseNumber()` handles `e`/`E` with optional `+`/`-`.
  - **Known limitation**: Unicode `\uXXXX` escape not yet supported.
- **Standard library pattern (D035, Round 59)**:
  - **Static method pattern**: `class Path()` + `function Path_join(...)` → user calls `Path.join(...)`. Same pattern as JSON, Math, StringUtil.
  - **Overloaded join**: `Path.join(a, b)`, `Path.join(a, b, c)`, `Path.join(a, b, c, d)` — different param counts → different mangled names.
  - **FS wraps builtins**: `FS.readFile()` wraps `readFile()`, `FS.readDir()` wraps `listDir()` + split into `Array<string>`.
  - **Import path**: `import { Path } from "@/lib/path"`, `import { FS } from "@/lib/fs"`, `import { StringUtil } from "@/lib/string_utils"`.
- **Tuple types (D034, Round 58)**:
  - **Syntax**: `[int, string]` in type position → `"Tuple<int,string>"` internal representation.
  - **Runtime**: Backed by arrays. Mixed-type literals use `ss_newArray` (tag=1, no element RC cleanup) to avoid segfault from cleanup treating int as ptr.
  - **Type inference**: INDEX_ACCESS on tuple variable with INT_LIT index → returns positional type via `tupleElemTypeAtIndex()`. Depth-aware `<>` parsing handles nested generics.
  - **Destructuring**: `genDestructureArray()` detects tuple type via `inferType(initId)` and assigns per-element types.
  - **Helpers**: `isTupleType(t)` and `tupleElemTypeAtIndex(tupleType, idx)` in gen_types.ss.
  - **Known limitations**: Only IDENT-based tuple expression supported for type inference (not chained calls). Class instance elements in tuple destructuring lack PIR RC tracking.
- **Phase 4 batch (D033, Round 57)**: String `.includes()`, `for-of` loops, `?.field`, spread in calls.
- **Array methods (Round 56)**: `find/findIndex/some/every` as prelude + genHigherOrderMethod. `includes` as genArrayMethod (indexOf-based).
- **Power operator (D032, Round 55)**: `**` and `**=`. `POWER`/`POWER_ASSIGN` tokens.
- **Multi-constraints (D031, Round 54)**: `<T extends A & B>` syntax.
- **Type constraints (D031, Round 53)**: `<T extends InterfaceName>`.
- **gen_calls.ss split (Round 52)**: Extracted gen_arrows.ss.
- **gen_class.ss split (Round 51)**: Extracted gen_iface.ss and gen_generic_class.ss.
- **Generic class inheritance (D030)**: Three forms — Case A/B/C. `splitParentType()` in gen_generic_class.ss.
- **resolveInheritance**: Recursive resolve-parent-first pattern (D030 bug fix). `resolvedInheritance` Map tracks processed classes.
- **Deferred struct + codegen globals**: `registrationPhase`, `deferredStructDefs`, `specClassNodeId`, `specClassTypeArgs`, `specClassGenerated`. All in gen_class.ss.
- **Destructuring**: Array uses `inferArrayElemType()`. Object uses `emitFieldLoad()` + `resolveObjClass()`.
- **Switch pattern matching (D029)**: `SWITCH_PAT` node S1=kind, S2=value.
- **Explicit type arguments (D028)**: Types in CALL.S2 and NEW_EXPR.S2. Known limitation: `>>` lexes as SHR.
- **Generic class (D027)**: Monomorphization at `new`. `preRegisterSpecializedClass()` in gen_generic_class.ss.
- **Generic function (D026)**: Monomorphization at call site. Mangled names: `@funcName_T_int`.
- **Interface (D025)**: Switch-based dispatch via TypeInfo class_id. Dispatch functions in gen_iface.ss.
- **Dual RC systems**: Old (ss_rc_retain/ss_rc_release) for strings/arrays/maps via libc. New (ss_retain/ss_release) for class instances + closures + interface-typed vars via mimalloc.
- **Closure implementation**: Tag-bit closures. CLOSURE_HDR_SLOTS = 3. All closure code in gen_arrows.ss.
- **PIR**: Map-based IR. All keys use `id + ""`. Pass 1 liveness → Pass 2 move → Pass 3 uniqueness → Pass 5 reuse.
- **Split structure**: parser.ss + parse_stmts.ss + parse_exprs.ss. lexer.ss + lex_ops.ss. checker.ss + check_stmts.ss + check_suggest.ss. gen_stmts.ss + gen_decls.ss + gen_assigns.ss. gen_exprs.ss + gen_calls.ss + gen_arrows.ss + gen_methods.ss + gen_builtins.ss. gen_class.ss + gen_iface.ss + gen_generic_class.ss + gen_type_ops.ss. gen_pir.ss + pir_lower.ss + pir_opt.ss. gen_runtime.ss + gen_rt_*.ss.
- **phase5 tests**: 57 tests.
- **35 bootstrap files**, ~13392 LOC.

## Decision Criteria
- Standard library now has 8 modules: json.ss (512), sha256.ss (228), string_utils.ss (220), http.ss (151), path.ss (148), math.ss (115), base64.ss (63), fs.ss (60). Total ~1497 LOC.
- StringUtil: 16 functions covering trimming (2), casing (1), validation (4), transformation (3), search (1), prefix/suffix (2), comparison (1), splitting (2).
- Math builtins: 25 total (12 original + 13 new). MathUtil stdlib: 16 functions.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- File sizes: gen_class.ss ~615 (largest), gen_decls.ss ~576, parser.ss ~559, check_stmts.ss ~553, checker.ss ~531.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- 35 bootstrap files total, ~13392 LOC, 57 phase5 tests.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
