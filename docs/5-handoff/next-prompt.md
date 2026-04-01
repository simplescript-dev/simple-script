# Round 75

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
Log 标准库模块（D050）：为 lib/ 添加结构化日志库——5 级日志（DEBUG/INFO/WARN/ERROR/FATAL）、级别过滤、ANSI 彩色输出（fromCharCode(27) 模式）、isEnabled 查询。log.ss 101 LOC，自包含无依赖，纯 SS 无编译器改动，全量测试 + bootstrap 固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done, log module done
Scope:
1. **Standard library expansion (continued)**:
   - **New modules**: Consider `ini.ss` (INI config parser), `argparse.ss` (CLI argument parsing), `random.ss` (random utilities beyond Math.randomInt)
   - **buffer.ss** deferred: SS strings are null-terminated, limiting byte buffer ops. Array<int> workaround possible but awkward.
   - **event.ss** deferred: Array<fn> not fully supported (inferArrayElemType doesn't handle fn type). Needs compiler enhancement first.
2. **Phase 4 remaining features**:
   - **String template tag functions** — Tagged templates (advanced, low priority)
3. **Phase 2 remaining** (diminishing returns):
   - Mutability inference — Fixed-point analysis marking function params as mutated/readonly
4. **文件大小状态**: gen_class.ss ~615 (approaching limit), gen_decls.ss ~579, parser.ss ~559, check_stmts.ss ~553, checker.ss ~532, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_runtime.ss ~507, gen_calls.ss ~507. gen_class.ss may need a split if further features add to it.
5. **Standard library状态**: json.ss (578 LOC), crypto.ss (526 LOC), url.ss (442 LOC), regex.ss (440 LOC), template.ss (348 LOC), csv.ss (286 LOC), datetime.ss (258 LOC), sha256.ss (228 LOC), string_utils.ss (220 LOC), sort.ss (212 LOC), color.ss (178 LOC), http.ss (151 LOC), path.ss (148 LOC), assert.ss (139 LOC), math.ss (115 LOC), uuid.ss (114 LOC), log.ss (101 LOC), base64.ss (63 LOC), fs.ss (60 LOC). Total ~4607 LOC in lib/, 19 modules.
6. **建议**: Standard library now covers 19 modules with broad coverage. Consider new language features like string template tag functions, or new stdlib modules like ini.ss (config parsing — pure string processing, no exotic types needed), argparse.ss (CLI argument parsing — very practical for SS programs), or random.ss (random utilities building on Math.randomInt). gen_class.ss at 615 lines may need splitting if more codegen features are added there. Also consider compiler enhancements: inferArrayElemType for fn type (would unblock event.ss), or native stderr support (would improve log.ss).
7. **Known compiler limitation**: `Map.keys()` is unreliable when called on a Map passed as a function parameter. Workaround: use parallel arrays or call `.keys()` before passing to function. Does not affect Maps created/used within the same scope.
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.
9. **Known compiler limitation**: Global `let` with negative int literals (e.g., `let x = -1`) doesn't work — parser treats `-1` as UNARY_MINUS(INT_LIT(1)), which falls into non-literal init path and gets typed as `ptr`. Workaround: initialize to 0 and set the real value inside functions.
10. **Known stdlib convention**: `arr.slice(start, end)` uses start+end index semantics (NOT offset+length like `substring`). `arr.slice(0, mid)` gets first mid elements; `arr.slice(mid, n)` gets elements from mid to end.
11. **Known compiler limitation**: `inferArrayElemType()` only recognizes `<string>`, `<int>`, `<double>`. Does NOT handle `<fn>`, returning empty string. This prevents type-safe Array<fn> usage, blocking event emitter patterns.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array push returns new array**: In SS, `arr.push(val)` returns a new array. The correct pattern is `arr = arr.push(val)`, NOT `arr.push(val)`. This is critical for any code that builds arrays dynamically. All stdlib modules follow this pattern.
- **Array methods use `.length()` not `.length`**: SS arrays use `.length()` method call syntax, not `.length` property access. Using `.length` without parentheses will compile but produce wrong results (loads ptr instead of calling ss_arrayLen).
- **Array slice uses (start, end) not (offset, length)**: `arr.slice(start, end)` uses start+end index semantics. This differs from `substring(offset, length)`. Example: `arr.slice(0, mid)` for first half, `arr.slice(mid, n)` for second half.
- **Log module (D050, Round 74)**:
  - **Architecture**: Pure SS, static method pattern, self-contained (no lib imports).
  - **5 severity levels**: DEBUG(0)=cyan, INFO(1)=green, WARN(2)=yellow, ERROR(3)=red, FATAL(4)=bright red.
  - **Level filtering**: `Log.setLevel(n)` suppresses messages below threshold. Default=INFO(1). Set to 5 for OFF.
  - **ANSI colors**: Uses `fromCharCode(27)` for ESC character (same pattern as color.ss). Togglable via `Log.enableColor(0/1)`.
  - **Output format**: Colored=`ESC[CODEm[LABEL]ESC[0m msg`, Plain=`[LABEL] msg`. Labels 5-char aligned.
  - **All stdout**: No stderr support (SS lacks native stderr). Users redirect at shell level.
  - **Log static methods (9)**: `debug`, `info`, `warn`, `error`, `fatal`, `log`, `setLevel`, `getLevel`, `enableColor`, `isEnabled`.
  - **Module globals (2)**: `logLevel` (default 1), `logColorOn` (default 1).
  - **Internal helper (1)**: `logOutput(level, label, colorCode, msg)`.
  - **Import**: `import { Log } from "@/lib/log"`.
- **Sort module (D049, Round 73)**:
  - **Architecture**: Pure SS, static method pattern. Three sorting algorithms + eight utility functions for `Array<int>`.
  - **Sort static methods (11)**: `quickSort`, `mergeSort`, `insertionSort`, `isSorted`, `binarySearch`, `unique`, `merge`, `shuffle`, `min`, `max`, `descending`.
  - **Import**: `import { Sort } from "@/lib/sort"`.
- **Regex module (D048, Round 72)**:
  - **Architecture**: Pure SS, static method pattern. Recursive backtracking engine.
  - **Regex static methods (8)**: `test`, `match`, `matchAll`, `matchIndex`, `replace`, `replaceAll`, `split`, `escape`.
  - **Import**: `import { Regex } from "@/lib/regex"`.
- **Crypto module (D047, Round 71)**:
  - **Flex hash design**: `sha1flex`/`sha256flex` read bytes from multiple sources on-the-fly.
  - **Crypto static methods (7)**: `sha1`, `sha256`, `hmacSHA256`, `hmacSHA1`, `hexToBytes`, `bytesToHex`, `timingSafeEqual`.
  - **Import**: `import { Crypto } from "@/lib/crypto"`.
- **Template module (D046, Round 70)**:
  - **Template static methods (5)**: `render`, `escape`, `unescape`, `variables`, `strip`.
  - **Import**: `import { Template } from "@/lib/template"`.
- **Color module (D045, Round 69)**:
  - **Color static methods (32)**: 6 modifiers + 8 FG + 8 bright FG + 8 BG + strip + reset.
  - **Import**: `import { Color } from "@/lib/color"`.
- **Assert module (D044, Round 68)**:
  - **Assert static methods (15)**: isTrue, isFalse, equal (int/string overload), notEqual, approxEqual, greaterThan, lessThan, greaterOrEqual, lessOrEqual, contains, startsWith, endsWith, fail.
  - **Import**: `import { Assert } from "@/lib/assert"`.
- **Math.randomInt (D043, Round 67)**:
  - **New builtin**: `Math.randomInt(max: int): int` — returns random integer in [0, max).
- **UUID module (D043, Round 67)**:
  - **UUID static methods (5)**: `v4()`, `isValid(str)`, `parse(str)`, `version(str)`, `nil()`.
  - **Import**: `import { UUID } from "@/lib/uuid"`.
- **URL module (D042, Round 66)**:
  - **URL static methods (7)**: `parse`, `format`, `resolve`, `parseQuery`, `encodeQuery`, `encodeComponent`, `decodeComponent`.
  - **Import**: `import { URL, UrlParts } from "@/lib/url"`.
- **CSV module (D041, Round 65)**:
  - **CSV static methods (5)**: `parse`, `parseDelimited`, `stringify`, `stringifyDelimited`, `create`.
  - **Import**: `import { CSV, CsvTable } from "@/lib/csv"`.
- **JSON Unicode escape (D040, Round 64)**:
  - **Parse**: `\uXXXX` → UTF-8. Surrogate pairs combined into U+10000+ code points.
- **DateTime module (D039, Round 63)**:
  - **21 methods** via `DateTime.year(ts)` static pattern.
  - **Import**: `import { DateTime } from "@/lib/datetime"`.
- **Standard library pattern (D035, Round 59)**:
  - **Static method pattern**: `class Path()` + `function Path_join(...)` → user calls `Path.join(...)`.
  - **Import path**: `import { Log } from "@/lib/log"`, `import { Sort } from "@/lib/sort"`, etc.
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
- **phase5 tests**: 69 tests.
- **35 bootstrap files**, ~13410 LOC.

## Decision Criteria
- Standard library now has 19 modules: json.ss (578), crypto.ss (526), url.ss (442), regex.ss (440), template.ss (348), csv.ss (286), datetime.ss (258), sha256.ss (228), string_utils.ss (220), sort.ss (212), color.ss (178), http.ss (151), path.ss (148), assert.ss (139), math.ss (115), uuid.ss (114), log.ss (101), base64.ss (63), fs.ss (60). Total ~4607 LOC.
- Log module: 9 static methods + 1 internal helper + 2 module globals. Self-contained, no lib imports.
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- File sizes: gen_class.ss ~615 (largest), gen_decls.ss ~579, parser.ss ~559, check_stmts.ss ~553, checker.ss ~532.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- Known limitation: `Map.keys()` unreliable on function-parameter Maps. Workaround: parallel arrays or caller-side `.keys()`.
- Known limitation: SS strings are null-terminated. `hexToBytes` cannot produce strings with 0x00 bytes. HMAC uses on-the-fly hex decoding to avoid this.
- Known limitation: Global `let` with negative int literals typed as `ptr` instead of `int`. Use 0 initializer + function-level assignment.
- Known convention: `arr.slice(start, end)` is start+end index semantics, NOT offset+length. Differs from `substring(offset, length)`.
- Known limitation: `inferArrayElemType()` only handles string/int/double, not fn. Blocks Array<fn> support.
- 35 bootstrap files total, ~13410 LOC, 69 phase5 tests.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
