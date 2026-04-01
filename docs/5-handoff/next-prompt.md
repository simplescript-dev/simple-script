# Round 72

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~13410 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
Crypto 标准库模块（D047）：为 lib/ 添加加密工具库——SHA-1 哈希、SHA-256 哈希、HMAC-SHA256（RFC 4231）、HMAC-SHA1（RFC 2202）、hex 转换、constant-time 比较，共 7 个 Crypto 静态方法。核心设计：flex hash 函数（sha1flex/sha256flex）通过 on-the-fly hex 解码避免 null-terminated 字符串的 0x00 截断问题，确保 HMAC 始终正确。crypto.ss 525 LOC，纯 SS 无编译器改动，全量测试 + bootstrap 固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done
Scope:
1. **Standard library expansion (continued)**:
   - **New modules**: Consider `regex.ss` (basic pattern matching), `buffer.ss` (byte buffer operations), `event.ss` (event emitter pattern)
2. **Phase 4 remaining features**:
   - **String template tag functions** — Tagged templates (advanced, low priority)
3. **Phase 2 remaining** (diminishing returns):
   - Mutability inference — Fixed-point analysis marking function params as mutated/readonly
4. **文件大小状态**: gen_class.ss ~615 (approaching limit), gen_decls.ss ~579, parser.ss ~559, check_stmts.ss ~553, checker.ss ~532, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_runtime.ss ~507, gen_calls.ss ~507. gen_class.ss may need a split if further features add to it.
5. **Standard library状态**: json.ss (578 LOC), crypto.ss (525 LOC), url.ss (442 LOC), template.ss (348 LOC), csv.ss (286 LOC), datetime.ss (258 LOC), sha256.ss (228 LOC), string_utils.ss (220 LOC), color.ss (178 LOC), http.ss (151 LOC), path.ss (148 LOC), assert.ss (139 LOC), math.ss (115 LOC), uuid.ss (114 LOC), base64.ss (63 LOC), fs.ss (60 LOC). Total ~3853 LOC in lib/, 16 modules.
6. **建议**: Standard library now covers 16 modules with broad coverage including crypto. Consider new language features like string template tag functions, or new stdlib modules like regex.ss (basic pattern matching — character classes, *, +, ?), buffer.ss (byte-level operations), or event.ss (pub/sub event emitter). gen_class.ss at 615 lines may need splitting if more codegen features are added there.
7. **Known compiler limitation**: `Map.keys()` is unreliable when called on a Map passed as a function parameter. Workaround: use parallel arrays or call `.keys()` before passing to function. Does not affect Maps created/used within the same scope.
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array push returns new array**: In SS, `arr.push(val)` returns a new array. The correct pattern is `arr = arr.push(val)`, NOT `arr.push(val)`. This is critical for any code that builds arrays dynamically. All stdlib modules (string_utils.ss, csv.ss, template.ss) follow this pattern.
- **Crypto module (D047, Round 71)**:
  - **Architecture**: Pure SS, static method pattern. Imports sha256.ss for SHA-256 helpers (rotr, ch, maj, sigma0/1, gamma0/1, getKConst, hexByte, hexWord).
  - **Flex hash design**: `sha1flex(data, dataHex, prefix, prefixHex, prefixXor)` and `sha256flex(...)` read bytes from multiple sources on-the-fly. Avoids constructing byte strings with potential 0x00 bytes that would be truncated by strlen-based string operations.
  - **Standalone hash**: `sha256flex(data, "", "", "", 0)` — no prefix, reads all bytes from data string.
  - **HMAC inner**: `sha256flex(message, "", key, "", 54)` — first 64 bytes = key XOR 0x36 (padded to 64), rest = message.
  - **HMAC outer**: `sha256flex("", innerHex, key, "", 92)` — first 64 bytes = key XOR 0x5c, rest = inner hash decoded from hex on-the-fly.
  - **Long key handling**: If key > 64 bytes, hash key first → keyHex, pass as prefixHex parameter.
  - **Crypto static methods (7)**: `sha1(data)`, `sha256(data)`, `hmacSHA256(key, msg)`, `hmacSHA1(key, msg)`, `hexToBytes(hex)`, `bytesToHex(data)`, `timingSafeEqual(a, b)`.
  - **Internal helpers (9)**: `sha1Rotl`, `sha1GetF`, `sha1GetK`, `cryptoHexDigit`, `sha1flex`, `sha256flex`, `cryptoHmac256`, `cryptoHmac1`, `cryptoTimeSafe`. Plus `cryptoHexToBytes`, `cryptoBytesToHex` for user-facing hex conversion.
  - **Import**: `import { Crypto } from "@/lib/crypto"`.
- **Template module (D046, Round 70)**:
  - **Architecture**: Pure SS, static method pattern (like UUID, Assert, Color).
  - **Template syntax**: `{{key}}` variable substitution, `{{#key}}...{{/key}}` sections, `{{^key}}...{{/key}}` inverted sections, `{{! comment }}` comments, `\{{` escaped delimiters.
  - **Truthiness**: Key is truthy if exists in Map AND value is not `""`, `"false"`, or `"0"`.
  - **Nesting**: `tmplFindClose()` tracks `{{#key}}`/`{{^key}}` depth to find matching `{{/key}}`.
  - **Template static methods (5)**: `render(tmpl, vars)`, `escape(text)`, `unescape(text)`, `variables(tmpl)`, `strip(tmpl)`.
  - **Internal helpers (5)**: `tmplTrim`, `tmplSliceFrom`, `tmplIsTruthy`, `tmplSkipTag`, `tmplFindClose`.
  - **Import**: `import { Template } from "@/lib/template"`.
- **Color module (D045, Round 69)**:
  - **Architecture**: Pure SS, static method pattern (like UUID, Assert).
  - **Core helper**: `colorWrap(text, open, close)` wraps text with `ESC[{open}m...ESC[{close}m` using `fromCharCode(27)`.
  - **Color static methods (32)**: 6 modifiers (bold, dim, italic, underline, inverse, strikethrough) + 8 FG colors (black, red, green, yellow, blue, magenta, cyan, white) + 8 bright FG (gray, brightRed, brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan, brightWhite) + 8 BG colors (bgBlack, bgRed, bgGreen, bgYellow, bgBlue, bgMagenta, bgCyan, bgWhite) + strip + reset.
  - **Composition**: Via nesting — `Color.bold(Color.red("text"))`.
  - **strip()**: Scans for ESC[...m sequences and removes them.
  - **Import**: `import { Color } from "@/lib/color"`.
- **Assert module (D044, Round 68)**:
  - **Architecture**: Pure SS, static method pattern (like UUID, DateTime, Path).
  - **Assert static methods (15)**: `isTrue(value, msg)`, `isFalse(value, msg)`, `equal(int/string overload)`, `notEqual(int/string overload)`, `approxEqual(actual, expected, eps, msg)`, `greaterThan(actual, expected, msg)`, `lessThan(actual, expected, msg)`, `greaterOrEqual(actual, expected, msg)`, `lessOrEqual(actual, expected, msg)`, `contains(text, substr, msg)`, `startsWith(text, prefix, msg)`, `endsWith(text, suffix, msg)`, `fail(msg)`.
  - **Overloading**: `equal` and `notEqual` have int (`_i_i_s`) and string (`_s_s_s`) overloads.
  - **Failure behavior**: Prints `FAIL: <msg> — <detail>` then `exit(1)`. Matches existing test pattern.
  - **Import**: `import { Assert } from "@/lib/assert"`.
- **Math.randomInt (D043, Round 67)**:
  - **New builtin**: `Math.randomInt(max: int): int` — returns random integer in [0, max). Returns 0 if max <= 0.
  - **Runtime**: `ss_randomInt(i32 %max)` calls `rand() % max` with guard for max <= 0.
  - **Auto-seeding**: Every SS program calls `srand(time(0))` at startup in main() preamble.
  - **isMathClass exception**: `gen_methods.ss` skips int→double auto-conversion for `randomInt` arg.
- **UUID module (D043, Round 67)**:
  - **Architecture**: Pure SS, static method pattern (like DateTime, Path).
  - **UUID static methods (5)**: `v4()`, `isValid(str)`, `parse(str)`, `version(str)`, `nil()`.
  - **Import**: `import { UUID } from "@/lib/uuid"`.
- **URL module (D042, Round 66)**:
  - **Architecture**: Map-based storage (like json.ss/csv.ss): global `urlData` Map keyed by `"id.field"`.
  - **URL static methods (7)**: `parse(input)`, `format(parts)`, `resolve(base, ref)`, `parseQuery(qs)`, `encodeQuery(keys, values)`, `encodeComponent(str)`, `decodeComponent(str)`.
  - **UrlParts methods (11)**: `protocol()`, `username()`, `password()`, `hostname()`, `port()`, `pathname()`, `search()`, `hash()`, `host()`, `origin()`, `href()`.
  - **Import**: `import { URL, UrlParts } from "@/lib/url"`.
- **CSV module (D041, Round 65)**:
  - **Architecture**: Map-based storage (like json.ss): `csvCells` for cell data, `csvMeta` for dimensions.
  - **CSV static methods (5)**: `parse(input)`, `parseDelimited(input, delim)`, `stringify(table)`, `stringifyDelimited(table, delim)`, `create()`.
  - **CsvTable methods (8)**: `rowCount()`, `colCount()`, `get(row, col)`, `set(row, col, value)`, `getRow(row)`, `headers()`, `getByName(row, name)`, `addRow(values)`.
  - **Import**: `import { CSV, CsvTable } from "@/lib/csv"`.
- **JSON Unicode escape (D040, Round 64)**:
  - **Parse**: `\uXXXX` → 4 hex digits → code point → UTF-8 (1–4 bytes). Surrogate pairs `\uD800`–`\uDBFF` + `\uDC00`–`\uDFFF` combined into U+10000+ code points.
  - **Stringify**: byte 8 → `\b`, byte 12 → `\f`, other control chars (0–31) → `\u00XX`. Non-ASCII UTF-8 passed through.
- **DateTime module (D039, Round 63)**:
  - **21 methods**: year, month, day, hour, minute, second, dayOfWeek, dayOfYear, isLeapYear, daysInMonth, of, ofDate, addSeconds, addMinutes, addHours, addDays, toISODate, toISOTime, toISO, parseISODate, parseISO, dayName, monthName, now, nowMs.
  - **Pure SS**: No compiler changes. Uses static method pattern (`DateTime.year(ts)`).
  - **Algorithm**: Howard Hinnant's civil_from_days (C++20 `<chrono>`). Epoch shift to 0000-03-01, era-based 400-year decomposition, pure integer arithmetic.
  - **Encoding trick**: `dtCivil()` returns `year*10000 + month*100 + day` as single int for multi-value return.
  - **substring semantics**: SS `substring(offset, length)` — offset + length, NOT start + end.
  - **Known limitations**: i32 timestamps valid through 2038-01-19. UTC only, no timezone support.
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
- **phase5 tests**: 66 tests.
- **35 bootstrap files**, ~13410 LOC.

## Decision Criteria
- Standard library now has 16 modules: json.ss (578), crypto.ss (525), url.ss (442), template.ss (348), csv.ss (286), datetime.ss (258), sha256.ss (228), string_utils.ss (220), color.ss (178), http.ss (151), path.ss (148), assert.ss (139), math.ss (115), uuid.ss (114), base64.ss (63), fs.ss (60). Total ~3853 LOC.
- Crypto module: 7 static methods (sha1, sha256, hmacSHA256, hmacSHA1, hexToBytes, bytesToHex, timingSafeEqual) + flex hash design for null-byte safety.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- File sizes: gen_class.ss ~615 (largest), gen_decls.ss ~579, parser.ss ~559, check_stmts.ss ~553, checker.ss ~532.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- Known limitation: `Map.keys()` unreliable on function-parameter Maps. Workaround: parallel arrays or caller-side `.keys()`.
- Known limitation: SS strings are null-terminated. `hexToBytes` cannot produce strings with 0x00 bytes. HMAC uses on-the-fly hex decoding to avoid this.
- 35 bootstrap files total, ~13410 LOC, 66 phase5 tests.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
