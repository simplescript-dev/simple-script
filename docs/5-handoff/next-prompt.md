# Round 74

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
Sort 标准库模块（D049）：为 lib/ 添加排序算法和工具库——3 种排序算法（quickSort, mergeSort, insertionSort）+ 8 个工具函数（isSorted, binarySearch, unique, merge, shuffle, min, max, descending），面向 Array<int>。纯功能式实现（所有算法返回新数组），内部 helper sortMergeTwo + sortInsert。sort.ss 212 LOC，纯 SS 无编译器改动，全量测试 + bootstrap 固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done
Scope:
1. **Standard library expansion (continued)**:
   - **New modules**: Consider `buffer.ss` (byte buffer operations), `event.ss` (event emitter pattern)
2. **Phase 4 remaining features**:
   - **String template tag functions** — Tagged templates (advanced, low priority)
3. **Phase 2 remaining** (diminishing returns):
   - Mutability inference — Fixed-point analysis marking function params as mutated/readonly
4. **文件大小状态**: gen_class.ss ~615 (approaching limit), gen_decls.ss ~579, parser.ss ~559, check_stmts.ss ~553, checker.ss ~532, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_runtime.ss ~507, gen_calls.ss ~507. gen_class.ss may need a split if further features add to it.
5. **Standard library状态**: json.ss (578 LOC), crypto.ss (526 LOC), url.ss (442 LOC), regex.ss (440 LOC), template.ss (348 LOC), csv.ss (286 LOC), datetime.ss (258 LOC), sha256.ss (228 LOC), string_utils.ss (220 LOC), sort.ss (212 LOC), color.ss (178 LOC), http.ss (151 LOC), path.ss (148 LOC), assert.ss (139 LOC), math.ss (115 LOC), uuid.ss (114 LOC), base64.ss (63 LOC), fs.ss (60 LOC). Total ~4506 LOC in lib/, 18 modules.
6. **建议**: Standard library now covers 18 modules with broad coverage including sort. Consider new language features like string template tag functions, or new stdlib modules like buffer.ss (byte-level operations — but note null-terminated string limitation) or event.ss (pub/sub event emitter — requires storing/calling function pointers from arrays). gen_class.ss at 615 lines may need splitting if more codegen features are added there.
7. **Known compiler limitation**: `Map.keys()` is unreliable when called on a Map passed as a function parameter. Workaround: use parallel arrays or call `.keys()` before passing to function. Does not affect Maps created/used within the same scope.
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.
9. **Known compiler limitation**: Global `let` with negative int literals (e.g., `let x = -1`) doesn't work — parser treats `-1` as UNARY_MINUS(INT_LIT(1)), which falls into non-literal init path and gets typed as `ptr`. Workaround: initialize to 0 and set the real value inside functions.
10. **Known stdlib convention**: `arr.slice(start, end)` uses start+end index semantics (NOT offset+length like `substring`). `arr.slice(0, mid)` gets first mid elements; `arr.slice(mid, n)` gets elements from mid to end.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array push returns new array**: In SS, `arr.push(val)` returns a new array. The correct pattern is `arr = arr.push(val)`, NOT `arr.push(val)`. This is critical for any code that builds arrays dynamically. All stdlib modules (string_utils.ss, csv.ss, template.ss, regex.ss, sort.ss) follow this pattern.
- **Array methods use `.length()` not `.length`**: SS arrays use `.length()` method call syntax, not `.length` property access. Using `.length` without parentheses will compile but produce wrong results (loads ptr instead of calling ss_arrayLen).
- **Array slice uses (start, end) not (offset, length)**: `arr.slice(start, end)` uses start+end index semantics. This differs from `substring(offset, length)`. Example: `arr.slice(0, mid)` for first half, `arr.slice(mid, n)` for second half.
- **Sort module (D049, Round 73)**:
  - **Architecture**: Pure SS, static method pattern. Three sorting algorithms + eight utility functions for `Array<int>`.
  - **Sorting algorithms**: `quickSort` (3-way partition, recursive), `mergeSort` (recursive split + merge, stable), `insertionSort` (functional insert-into-sorted-position).
  - **All algorithms functional**: Return new sorted arrays (no in-place mutation). QuickSort partitions into less/equal/greater arrays and concatenates. MergeSort uses `sortMergeTwo` internal helper. InsertionSort uses `sortInsert` internal helper.
  - **Sorted-array utilities**: `isSorted(arr)` returns 1/0, `binarySearch(arr, target)` returns index or -1, `unique(arr)` removes adjacent duplicates (input must be sorted), `merge(a, b)` merges two sorted arrays.
  - **General utilities**: `shuffle(arr)` selection-based Fisher-Yates using `Math.randomInt`, `min(arr)`/`max(arr)` linear scan, `descending(arr)` quickSort + reverse.
  - **Internal helpers (2)**: `sortMergeTwo(a, b)` two-pointer merge, `sortInsert(arr, val)` insert into sorted position.
  - **Sort static methods (11)**: `quickSort`, `mergeSort`, `insertionSort`, `isSorted`, `binarySearch`, `unique`, `merge`, `shuffle`, `min`, `max`, `descending`.
  - **Import**: `import { Sort } from "@/lib/sort"`.
- **Regex module (D048, Round 72)**:
  - **Architecture**: Pure SS, static method pattern. Recursive backtracking engine operating directly on the pattern string — no compilation step.
  - **Core engine**: `rxMatchAt(pat, pi, pEnd, text, ti, tLen)` — match `pat[pi:pEnd)` at `text[ti:]`, returns end position or -1. `rxMatchOne` matches one atom. `rxFindMatch` scans positions, sets `rxStart`/`rxEnd` globals.
  - **Pattern navigation**: `rxAtomEnd` determines atom boundaries. `rxFindAlt` finds top-level `|`. `rxFindGroupEnd`/`rxFindClassEnd` handle nesting.
  - **Quantifier handling**: Greedy — collect positions in `Array<int>`, backtrack from most to least. `rxNot(v)` helper for negated shorthand classes. Zero-progress check prevents infinite loops.
  - **Globals**: `rxStart`/`rxEnd` (int, initialized to 0, not -1 — see known compiler limitation).
  - **Regex static methods (8)**: `test(pattern, text)`, `match(pattern, text)`, `matchAll(pattern, text)`, `matchIndex(pattern, text)`, `replace(pattern, text, repl)`, `replaceAll(pattern, text, repl)`, `split(pattern, text)`, `escape(text)`.
  - **Internal helpers (17)**: `rxIsDigit`, `rxIsAlpha`, `rxIsWord`, `rxIsSpace`, `rxNot`, `rxIsSpecial`, `rxFindClassEnd`, `rxFindGroupEnd`, `rxAtomEnd`, `rxFindAlt`, `rxMatchClassInner`, `rxMatchClass`, `rxMatchEscape`, `rxMatchOne`, `rxMatchAt`, `rxFindMatch`.
  - **Supported patterns**: `.` `*` `+` `?` `^` `$` `[abc]` `[a-z]` `[^abc]` `\d` `\w` `\s` `\D` `\W` `\S` `(...)` `|` `\\`.
  - **Import**: `import { Regex } from "@/lib/regex"`.
- **Crypto module (D047, Round 71)**:
  - **Architecture**: Pure SS, static method pattern. Imports sha256.ss for SHA-256 helpers (rotr, ch, maj, sigma0/1, gamma0/1, getKConst, hexByte, hexWord).
  - **Flex hash design**: `sha1flex(data, dataHex, prefix, prefixHex, prefixXor)` and `sha256flex(...)` read bytes from multiple sources on-the-fly. Avoids constructing byte strings with potential 0x00 bytes that would be truncated by strlen-based string operations.
  - **Crypto static methods (7)**: `sha1(data)`, `sha256(data)`, `hmacSHA256(key, msg)`, `hmacSHA1(key, msg)`, `hexToBytes(hex)`, `bytesToHex(data)`, `timingSafeEqual(a, b)`.
  - **Import**: `import { Crypto } from "@/lib/crypto"`.
- **Template module (D046, Round 70)**:
  - **Architecture**: Pure SS, static method pattern (like UUID, Assert, Color).
  - **Template syntax**: `{{key}}` variable substitution, `{{#key}}...{{/key}}` sections, `{{^key}}...{{/key}}` inverted sections, `{{! comment }}` comments, `\{{` escaped delimiters.
  - **Template static methods (5)**: `render(tmpl, vars)`, `escape(text)`, `unescape(text)`, `variables(tmpl)`, `strip(tmpl)`.
  - **Import**: `import { Template } from "@/lib/template"`.
- **Color module (D045, Round 69)**:
  - **Color static methods (32)**: 6 modifiers + 8 FG + 8 bright FG + 8 BG + strip + reset.
  - **Import**: `import { Color } from "@/lib/color"`.
- **Assert module (D044, Round 68)**:
  - **Assert static methods (15)**: isTrue, isFalse, equal (int/string overload), notEqual (int/string overload), approxEqual, greaterThan, lessThan, greaterOrEqual, lessOrEqual, contains, startsWith, endsWith, fail.
  - **Import**: `import { Assert } from "@/lib/assert"`.
- **Math.randomInt (D043, Round 67)**:
  - **New builtin**: `Math.randomInt(max: int): int` — returns random integer in [0, max). Returns 0 if max <= 0.
- **UUID module (D043, Round 67)**:
  - **UUID static methods (5)**: `v4()`, `isValid(str)`, `parse(str)`, `version(str)`, `nil()`.
  - **Import**: `import { UUID } from "@/lib/uuid"`.
- **URL module (D042, Round 66)**:
  - **URL static methods (7)**: `parse(input)`, `format(parts)`, `resolve(base, ref)`, `parseQuery(qs)`, `encodeQuery(keys, values)`, `encodeComponent(str)`, `decodeComponent(str)`.
  - **Import**: `import { URL, UrlParts } from "@/lib/url"`.
- **CSV module (D041, Round 65)**:
  - **CSV static methods (5)**: `parse(input)`, `parseDelimited(input, delim)`, `stringify(table)`, `stringifyDelimited(table, delim)`, `create()`.
  - **Import**: `import { CSV, CsvTable } from "@/lib/csv"`.
- **JSON Unicode escape (D040, Round 64)**:
  - **Parse**: `\uXXXX` → UTF-8. Surrogate pairs combined into U+10000+ code points.
- **DateTime module (D039, Round 63)**:
  - **21 methods** via `DateTime.year(ts)` static pattern. Howard Hinnant's algorithm.
  - **Import**: `import { DateTime } from "@/lib/datetime"`.
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
- **phase5 tests**: 68 tests.
- **35 bootstrap files**, ~13410 LOC.

## Decision Criteria
- Standard library now has 18 modules: json.ss (578), crypto.ss (526), url.ss (442), regex.ss (440), template.ss (348), csv.ss (286), datetime.ss (258), sha256.ss (228), string_utils.ss (220), sort.ss (212), color.ss (178), http.ss (151), path.ss (148), assert.ss (139), math.ss (115), uuid.ss (114), base64.ss (63), fs.ss (60). Total ~4506 LOC.
- Sort module: 11 static methods (quickSort, mergeSort, insertionSort, isSorted, binarySearch, unique, merge, shuffle, min, max, descending) + 2 internal helpers. All functional style (return new arrays).
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- File sizes: gen_class.ss ~615 (largest), gen_decls.ss ~579, parser.ss ~559, check_stmts.ss ~553, checker.ss ~532.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- Known limitation: `Map.keys()` unreliable on function-parameter Maps. Workaround: parallel arrays or caller-side `.keys()`.
- Known limitation: SS strings are null-terminated. `hexToBytes` cannot produce strings with 0x00 bytes. HMAC uses on-the-fly hex decoding to avoid this.
- Known limitation: Global `let` with negative int literals typed as `ptr` instead of `int`. Use 0 initializer + function-level assignment.
- Known convention: `arr.slice(start, end)` is start+end index semantics, NOT offset+length. Differs from `substring(offset, length)`.
- 35 bootstrap files total, ~13410 LOC, 68 phase5 tests.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
