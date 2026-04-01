# Round 65

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
JSON Unicode escape（D040）：为 json.ss 添加完整 `\uXXXX` Unicode 转义支持——解析端处理 4 位 hex + surrogate pair 合并 + UTF-8 编码（1–4 字节），序列化端将控制字符（0–31）输出为 `\b`/`\f`/`\u00XX`。同时补全了 JSON 规范缺失的 `\b`（backspace）和 `\f`（form feed）命名转义。json.ss 从 512 → 578 LOC，全量测试 + bootstrap 固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done
Scope:
1. **Standard library expansion (continued)**:
   - **New modules**: Consider `uuid.ss` (v4 UUID generation), `csv.ss` (CSV parsing), `regex.ss` (basic pattern matching)
2. **Phase 4 remaining features**:
   - **String template tag functions** — Tagged templates (advanced, low priority)
3. **Phase 2 remaining** (diminishing returns):
   - Mutability inference — Fixed-point analysis marking function params as mutated/readonly
4. **文件大小状态**: gen_class.ss ~615 (approaching limit), gen_decls.ss ~576, parser.ss ~559, check_stmts.ss ~553, checker.ss ~531, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_calls.ss ~507. gen_class.ss may need a split if further features add to it.
5. **Standard library状态**: json.ss (578 LOC), datetime.ss (258 LOC), sha256.ss (228 LOC), string_utils.ss (220 LOC), http.ss (151 LOC), path.ss (148 LOC), math.ss (115 LOC), base64.ss (63 LOC), fs.ss (60 LOC). Total ~1821 LOC in lib/, 9 modules.
6. **建议**: JSON spec string handling now complete. Consider new stdlib modules like uuid.ss or csv.ss, or new language features like numeric separators (1_000_000). gen_class.ss at 615 lines may need splitting if more codegen features are added there.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **JSON Unicode escape (D040, Round 64)**:
  - **Parse**: `\uXXXX` → 4 hex digits → code point → UTF-8 (1–4 bytes). Surrogate pairs `\uD800`–`\uDBFF` + `\uDC00`–`\uDFFF` combined into U+10000+ code points.
  - **Stringify**: byte 8 → `\b`, byte 12 → `\f`, other control chars (0–31) → `\u00XX`. Non-ASCII UTF-8 passed through.
  - **Helpers**: `jpHexDigit(ch)`, `jpHexChar(n)`, `jpCodePointToUtf8(cp)`, `jpReadHex4()`.
  - **Also added**: `\b` (backspace) and `\f` (form feed) named escapes per JSON spec.
  - **JSON spec string handling now complete**: all escape sequences per RFC 8259.
- **DateTime module (D039, Round 63)**:
  - **21 methods**: year, month, day, hour, minute, second, dayOfWeek, dayOfYear, isLeapYear, daysInMonth, of, ofDate, addSeconds, addMinutes, addHours, addDays, toISODate, toISOTime, toISO, parseISODate, parseISO, dayName, monthName, now, nowMs.
  - **Pure SS**: No compiler changes. Uses static method pattern (`DateTime.year(ts)`).
  - **Algorithm**: Howard Hinnant's civil_from_days (C++20 `<chrono>`). Epoch shift to 0000-03-01, era-based 400-year decomposition, pure integer arithmetic.
  - **Encoding trick**: `dtCivil()` returns `year*10000 + month*100 + day` as single int for multi-value return.
  - **Helper functions**: `dtPad2(n)`, `dtPad4(n)` for ISO formatting zero-padding. `dtCivil(days)`, `dtDaysFromCivil(y,m,d)` for calendar math.
  - **substring semantics**: SS `substring(offset, length)` — offset + length, NOT start + end.
  - **Known limitations**: i32 timestamps valid through 2038-01-19. UTC only, no timezone support.
- **String utils (D038, Round 62)**:
  - **16 methods**: trimStart, trimEnd, capitalize, reverse, isBlank, isDigit, isAlpha, isAlphaNumeric, padCenter, truncate, count, removePrefix, removeSuffix, equalsIgnoreCase, lines, words.
  - **Pure SS**: No compiler changes. Uses static method pattern (`StringUtil.capitalize("hello")`).
- **Math enhancements (D037, Round 61)**:
  - **New builtins**: `Math.tan(x)`, `Math.asin(x)`, `Math.acos(x)`, `Math.atan(x)`, `Math.atan2(y,x)`, `Math.exp(x)`, `Math.log10(x)`, `Math.log2(x)`, `Math.trunc(x)`, `Math.sign(x)`, `Math.hypot(x,y)`, `Math.cbrt(x)`, `Math.fmod(x,y)`.
  - **All return double**: Auto int→double conversion via `isMathClass` in `genStaticMethodCall()`.
  - **lib/math.ss (MathUtil)**: `clamp(v,lo,hi)`, `lerp(a,b,t)`, `inverseLerp(a,b,v)`, `mapRange(v,inMin,inMax,outMin,outMax)`, `toDegrees(rad)`, `toRadians(deg)`, `approxEqual(a,b,eps)`, `isEven(n)`, `isOdd(n)`, `gcd(a,b)`, `lcm(a,b)`, `isPowerOfTwo(n)`.
  - **Constants as methods**: `MathUtil.PI()`, `MathUtil.E()`, `MathUtil.TAU()`, `MathUtil.EPSILON()`.
- **JSON library (D036, Round 60)**:
  - **Getters**: `getDouble(key)`, `getBool(key)`, `has(key)`, `keys()`.
  - **Escape**: `jnEscapeString()` in stringify handles `\`, `"`, `\n`, `\t`, `\r`, `\b`, `\f`, control chars.
  - **Scientific notation**: `jpParseNumber()` handles `e`/`E` with optional `+`/`-`.
- **Standard library pattern (D035, Round 59)**:
  - **Static method pattern**: `class Path()` + `function Path_join(...)` → user calls `Path.join(...)`.
  - **Import path**: `import { DateTime } from "@/lib/datetime"`, `import { Path } from "@/lib/path"`, etc.
- **Tuple types (D034, Round 58)**:
  - **Syntax**: `[int, string]` in type position → `"Tuple<int,string>"` internal representation.
  - **Runtime**: Backed by arrays. Mixed-type literals use `ss_newArray` (tag=1).
- **Phase 4 batch (D033, Round 57)**: String `.includes()`, `for-of` loops, `?.field`, spread in calls.
- **Array methods (Round 56)**: `find/findIndex/some/every` as prelude + genHigherOrderMethod.
- **Power operator (D032, Round 55)**: `**` and `**=`.
- **Multi-constraints (D031, Round 54)**: `<T extends A & B>` syntax.
- **Type constraints (D031, Round 53)**: `<T extends InterfaceName>`.
- **gen_calls.ss split (Round 52)**: Extracted gen_arrows.ss.
- **gen_class.ss split (Round 51)**: Extracted gen_iface.ss and gen_generic_class.ss.
- **Generic class inheritance (D030)**: Three forms — Case A/B/C.
- **Dual RC systems**: Old (ss_rc_retain/ss_rc_release) for strings/arrays/maps via libc. New (ss_retain/ss_release) for class instances + closures + interface-typed vars via mimalloc.
- **Closure implementation**: Tag-bit closures. CLOSURE_HDR_SLOTS = 3. All closure code in gen_arrows.ss.
- **PIR**: Map-based IR. All keys use `id + ""`. Pass 1 liveness → Pass 2 move → Pass 3 uniqueness → Pass 5 reuse.
- **Split structure**: parser.ss + parse_stmts.ss + parse_exprs.ss. lexer.ss + lex_ops.ss. checker.ss + check_stmts.ss + check_suggest.ss. gen_stmts.ss + gen_decls.ss + gen_assigns.ss. gen_exprs.ss + gen_calls.ss + gen_arrows.ss + gen_methods.ss + gen_builtins.ss. gen_class.ss + gen_iface.ss + gen_generic_class.ss + gen_type_ops.ss. gen_pir.ss + pir_lower.ss + pir_opt.ss. gen_runtime.ss + gen_rt_*.ss.
- **phase5 tests**: 59 tests.
- **35 bootstrap files**, ~13392 LOC.

## Decision Criteria
- Standard library now has 9 modules: json.ss (578), datetime.ss (258), sha256.ss (228), string_utils.ss (220), http.ss (151), path.ss (148), math.ss (115), base64.ss (63), fs.ss (60). Total ~1821 LOC.
- JSON spec string handling now complete: all named escapes (\n, \t, \r, \\, \", \/, \b, \f) + Unicode \uXXXX + surrogate pairs.
- DateTime: 21 functions covering time extraction (6), date info (2), construction (2), arithmetic (4), formatting (3), parsing (2), names (2), current time (2).
- Math builtins: 25 total (12 original + 13 new). MathUtil stdlib: 16 functions.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- File sizes: gen_class.ss ~615 (largest), gen_decls.ss ~576, parser.ss ~559, check_stmts.ss ~553, checker.ss ~531.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- 35 bootstrap files total, ~13392 LOC, 59 phase5 tests.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
