# Round 77

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~13450 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
Map.keys() 修复（D052）：Map.keys() 从返回换行分隔字符串改为返回 Array<string>。添加 ss_mapKeysArray 运行时函数，更新 codegen 和类型注册，迁移编译器源码 8 处 .keys().split("\n") 用法。两阶段 bootstrap（bridge seed → source update），固定点验证通过。新增 P4a 原则：编译器限制是 bug，不是边界条件。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done, stdlib path+fs done, json enhancements done, math enhancements done, string utils done, datetime done, json unicode escape done, csv module done, url module done, uuid module done, assert module done, color module done, template module done, crypto module done, regex module done, sort module done, log module done, ini module done, **Map.keys() fix done**
Scope:
**P17: 先修后加。Open issues 优先于新功能。每轮开始先读 `docs/4-issues/1-open/`。**

### Open Issues (按优先级)
1. **I003 — 语义分析不完整** [HIGH]: 类型不匹配时静默产出错误代码。Phase 4 需要将 inferType() 从 codegen 迁移到 checker 做预检。**不被语言能力阻塞，可以立即推进。**
2. **I001 — 全局可变状态爆炸** [BLOCKED]: 55+ 全局变量。需要 struct 支持才能彻底解决（P10）。短期可分组 + init 函数。
3. **I002 — 字符串类型系统** [BLOCKED]: 类型用 raw string 比较。需要 enum/struct。短期可统一解析函数。
4. **I005 — AST list 用字符串** [PARTIAL]: 已有 helper，性能问题待 proper array type。
5. **I006 — Runtime raw IR** [LOW]: 已大幅转换，剩 401 处 raw emitIR。
6. **I008 — Parser 优先级硬编码** [LOW]: 能用，递归下降是标准做法。
7. **I004 — 错误报告** [CLOSED]: 全部 4 阶段已完成，已移至 `2-closed/`。

### 次优先级
8. **Standard library cleanup**: csv.ss/ini.ss 可用 Map 字段简化（Map.keys() 已修复）。
9. **Standard library expansion**: argparse.ss, random.ss 等新模块。
10. **Phase 4 remaining**: Tagged templates（低优先级）。
11. **Phase 2 remaining**: Mutability inference（收益递减）。

### 项目状态
- **文件大小**: gen_class.ss ~615, gen_decls.ss ~579, parser.ss ~559, check_stmts.ss ~553, checker.ss ~532, parse_exprs.ss ~531, parse_stmts.ss ~519, gen_runtime.ss ~507, gen_calls.ss ~507.
- **Stdlib**: 20 modules, ~4862 LOC in lib/.
- **Bootstrap**: 35 files, ~13450 LOC, 71 phase5 tests.
8. **Known stdlib limitation**: SS strings are null-terminated (strlen-based length). `hexToBytes` cannot produce strings containing 0x00 bytes. HMAC functions handle this internally via on-the-fly hex decoding in flex hash functions.
9. **Known compiler limitation**: Global `let` with negative int literals (e.g., `let x = -1`) doesn't work — parser treats `-1` as UNARY_MINUS(INT_LIT(1)), which falls into non-literal init path and gets typed as `ptr`. Workaround: initialize to 0 and set the real value inside functions.
10. **Known stdlib convention**: `arr.slice(start, end)` uses start+end index semantics (NOT offset+length like `substring`). `arr.slice(0, mid)` gets first mid elements; `arr.slice(mid, n)` gets elements from mid to end.
11. **Known compiler limitation**: `inferArrayElemType()` only recognizes `<string>`, `<int>`, `<double>`. Does NOT handle `<fn>`, returning empty string. This prevents type-safe Array<fn> usage, blocking event emitter patterns.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, spread in calls, **tuple types `[T, U]`**, **Math builtins (13 new)**, **Math.randomInt(max)**, **Map.keys() → Array<string>**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array push returns new array**: In SS, `arr.push(val)` returns a new array. The correct pattern is `arr = arr.push(val)`, NOT `arr.push(val)`. This is critical for any code that builds arrays dynamically. All stdlib modules follow this pattern.
- **Array methods use `.length()` not `.length`**: SS arrays use `.length()` method call syntax, not `.length` property access. Using `.length` without parentheses will compile but produce wrong results (loads ptr instead of calling ss_arrayLen).
- **Array slice uses (start, end) not (offset, length)**: `arr.slice(start, end)` uses start+end index semantics. This differs from `substring(offset, length)`. Example: `arr.slice(0, mid)` for first half, `arr.slice(mid, n)` for second half.
- **P4a principle**: Compiler limitation is a bug, not a boundary. When a compiler limitation forces ugly patterns in stdlib or user code, fix the compiler first. Do NOT record it as "Known limitation" and work around it.
- **Map.keys() fix (D052, Round 76)**:
  - **Runtime**: `ss_mapKeysArray(ptr %map) → ptr` — iterates 64 hash buckets, strdup keys into Array<string>. Old `ss_mapKeys` (returns string) kept for backward compat.
  - **Codegen**: `genMapMethod` "keys" calls `ss_mapKeysArray`.
  - **Type registry**: `funcRetTypes.set("Map_keys", "Array<string>")` takes priority over `methodRetTypes`. Both updated.
  - **Bootstrap**: Two-phase approach needed for self-bootstrapping: bridge seed (codegen change only) → source update → full bootstrap.
  - **Compiler source**: 8 files migrated from `.keys().split("\n")` to `.keys()`.
  - **Import**: `m.keys()` returns `Array<string>` directly, no split needed.
- **Dual RC systems**: Old (ss_rc_retain/ss_rc_release) for strings/arrays/maps via libc. New (ss_retain/ss_release) for class instances + closures + interface-typed vars via mimalloc.
- **Closure implementation**: Tag-bit closures. CLOSURE_HDR_SLOTS = 3. All closure code in gen_arrows.ss.
- **PIR**: Map-based IR. All keys use `id + ""`. Pass 1 liveness → Pass 2 move → Pass 3 uniqueness → Pass 5 reuse.
- **Split structure**: parser.ss + parse_stmts.ss + parse_exprs.ss. lexer.ss + lex_ops.ss. checker.ss + check_stmts.ss + check_suggest.ss. gen_stmts.ss + gen_decls.ss + gen_assigns.ss. gen_exprs.ss + gen_calls.ss + gen_arrows.ss + gen_methods.ss + gen_builtins.ss. gen_class.ss + gen_iface.ss + gen_generic_class.ss + gen_type_ops.ss. gen_pir.ss + pir_lower.ss + pir_opt.ss. gen_runtime.ss + gen_rt_*.ss.
- **phase5 tests**: 71 tests.
- **35 bootstrap files**, ~13450 LOC.

## Decision Criteria
- Standard library now has 20 modules, ~4862 LOC.
- Map.keys() fixed: returns Array<string>, no longer a "Known limitation".
- Phase 4 essentially complete (tuples done, numeric separators done, tag functions deferred).
- File sizes: gen_class.ss ~615 (largest), gen_decls.ss ~579, parser.ss ~559, check_stmts.ss ~553, checker.ss ~532.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- Known limitation: SS strings are null-terminated. `hexToBytes` cannot produce strings with 0x00 bytes. HMAC uses on-the-fly hex decoding to avoid this.
- Known limitation: Global `let` with negative int literals typed as `ptr` instead of `int`. Use 0 initializer + function-level assignment.
- Known convention: `arr.slice(start, end)` is start+end index semantics, NOT offset+length. Differs from `substring(offset, length)`.
- Known limitation: `inferArrayElemType()` only handles string/int/double, not fn. Blocks Array<fn> support.
- 35 bootstrap files total, ~13450 LOC, 71 phase5 tests.

## When Done
**P18: 单上下文单任务。完成当前任务或上下文不足时，更新 handoff 并停止。**
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
7. **Stop.** Do NOT start the next task. External automation will clear + `/next`.
