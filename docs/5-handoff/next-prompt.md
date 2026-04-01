# Round 66

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
CSV 标准库模块（D041）：为 lib/ 添加 RFC 4180 兼容的 CSV 解析/序列化库——5 个 CSV 静态方法（parse, parseDelimited, stringify, stringifyDelimited, create）+ 8 个 CsvTable 方法（rowCount, colCount, get, set, getRow, headers, getByName, addRow）。解析器为字符级状态机，支持引号字段、转义引号（`""`）、字段内换行、CRLF 规范化、自定义分隔符（TSV 等）。csv.ss 286 LOC，全量测试 + bootstrap 固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done
Scope:
1. **Standard library expansion (continued)**:
   - **New modules**: Consider `uuid.ss` (v4 UUID generation), `regex.ss` (basic pattern matching), `url.ss` (URL parsing)
2. **Phase 4 remaining features**:
   - **String template tag functions** — Tagged templates (advanced, low priority)
3. **Phase 2 remaining** (diminishing returns):
   - Mutability inference — Fixed-point analysis marking function params as mutated/readonly
4. **文件大小状态**: gen_class.ss ~615 (approaching limit), gen_decls.ss ~576, parser.ss ~559, check_stmts.ss ~553, checker.ss ~531, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_calls.ss ~507. gen_class.ss may need a split if further features add to it.
5. **Standard library状态**: json.ss (578 LOC), csv.ss (286 LOC), datetime.ss (258 LOC), sha256.ss (228 LOC), string_utils.ss (220 LOC), http.ss (151 LOC), path.ss (148 LOC), math.ss (115 LOC), base64.ss (63 LOC), fs.ss (60 LOC). Total ~2107 LOC in lib/, 10 modules.
6. **建议**: CSV module now complete. Consider new stdlib modules like uuid.ss (v4 UUID, needs Math.random), url.ss (URL parsing), or new language features like numeric separators (1_000_000). gen_class.ss at 615 lines may need splitting if more codegen features are added there.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array push returns new array**: In SS, `arr.push(val)` returns a new array. The correct pattern is `arr = arr.push(val)`, NOT `arr.push(val)`. This is critical for any code that builds arrays dynamically. All stdlib modules (string_utils.ss, csv.ss) follow this pattern.
- **CSV module (D041, Round 65)**:
  - **Architecture**: Map-based storage (like json.ss): `csvCells` for cell data, `csvMeta` for dimensions.
  - **CSV static methods (5)**: `parse(input)`, `parseDelimited(input, delim)`, `stringify(table)`, `stringifyDelimited(table, delim)`, `create()`.
  - **CsvTable methods (8)**: `rowCount()`, `colCount()`, `get(row, col)`, `set(row, col, value)`, `getRow(row)`, `headers()`, `getByName(row, name)`, `addRow(values)`.
  - **Parser**: Character-level state machine. Handles quoted fields (`"..."`), escaped quotes (`""`), newlines in quoted fields, CRLF normalization, empty fields.
  - **Stringify**: Auto-quotes fields containing delimiter/quote/newline. Escaped quotes per RFC 4180.
  - **Import**: `import { CSV, CsvTable } from "@/lib/csv"`.
- **JSON Unicode escape (D040, Round 64)**:
  - **Parse**: `\uXXXX` → 4 hex digits → code point → UTF-8 (1–4 bytes). Surrogate pairs `\uD800`–`\uDBFF` + `\uDC00`–`\uDFFF` combined into U+10000+ code points.
  - **Stringify**: byte 8 → `\b`, byte 12 → `\f`, other control chars (0–31) → `\u00XX`. Non-ASCII UTF-8 passed through.
  - **JSON spec string handling now complete**: all escape sequences per RFC 8259.
- **DateTime module (D039, Round 63)**:
  - **21 methods**: year, month, day, hour, minute, second, dayOfWeek, dayOfYear, isLeapYear, daysInMonth, of, ofDate, addSeconds, addMinutes, addHours, addDays, toISODate, toISOTime, toISO, parseISODate, parseISO, dayName, monthName, now, nowMs.
  - **Pure SS**: No compiler changes. Uses static method pattern (`DateTime.year(ts)`).
  - **Algorithm**: Howard Hinnant's civil_from_days (C++20 `<chrono>`). Epoch shift to 0000-03-01, era-based 400-year decomposition, pure integer arithmetic.
  - **Encoding trick**: `dtCivil()` returns `year*10000 + month*100 + day` as single int for multi-value return.
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
- **phase5 tests**: 60 tests.
- **35 bootstrap files**, ~13392 LOC.

## Decision Criteria
- Standard library now has 10 modules: json.ss (578), csv.ss (286), datetime.ss (258), sha256.ss (228), string_utils.ss (220), http.ss (151), path.ss (148), math.ss (115), base64.ss (63), fs.ss (60). Total ~2107 LOC.
- CSV module: 5 static methods + 8 CsvTable methods = 13 methods. RFC 4180 compliant.
- JSON spec string handling complete: all named escapes + Unicode \uXXXX + surrogate pairs.
- DateTime: 21 functions. Math builtins: 25 total + 16 MathUtil. String utils: 16 methods.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- File sizes: gen_class.ss ~615 (largest), gen_decls.ss ~576, parser.ss ~559, check_stmts.ss ~553, checker.ss ~531.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- 35 bootstrap files total, ~13392 LOC, 60 phase5 tests.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
