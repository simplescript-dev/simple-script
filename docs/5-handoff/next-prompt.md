# Round 55

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~12976 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
`**` 指数运算符完成（D032）：lexer/parser 已有基础，补齐 genBinary Pow codegen + `**=` 复合赋值（lexer POWER_ASSIGN + parser + genAssign/genMemberAssign）+ 模板内 `**` 支持。1 个新测试（int/double/右结合/复合赋值/模板内）+ 全量测试通过，bootstrap 三阶段固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done
Scope:
1. **Phase 4 语言特性**（推荐优先级排序）：
   - **Spread operator** — `...arr` in function calls and array literals (partial: array spread exists, function call spread missing)
   - **String methods** — `.startsWith()`, `.endsWith()`, `.includes()`, `.repeat()`, `.padStart()`, `.padEnd()`
   - **Array methods** — `.find()`, `.findIndex()`, `.some()`, `.every()`, `.includes()`
   - **Numeric separators** — `1_000_000` in integer/hex/binary literals (lexer-only change)
2. **Phase 2 remaining**（diminishing returns）：
   - Mutability inference — 固定点分析标记函数参数为 mutated/readonly
3. **文件大小状态**: gen_class.ss ~575, gen_decls.ss ~562, check_stmts.ss ~551, parser.ss ~548, parse_exprs.ss ~524. gen_assigns.ss ~226, gen_exprs.ss ~412. 所有文件均在合理范围内，无紧急拆分需求。
4. **建议**: 继续 Phase 4 特性实现。String/Array 方法补齐是高频需求，Spread in calls 和 numeric separators 是标准 TS/JS 特性。

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports Perceus, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Power operator (D032, Round 55)**: `**` exponentiation and `**=` compound assignment. Lexer: `POWER` token already existed, added `POWER_ASSIGN` in `lexStar()`. Parser: `parsePower()` already existed (right-associative). Codegen: `genBinary` Pow case converts to double → `@ss_pow` → converts back if both int. `genAssign`/`genMemberAssign` have separate `POWER_ASSIGN` branches (follows existing compound assignment pattern). Template inner loop now calls `lexStar()` for `*`.
- **Multi-constraints (D031, Round 54)**: `<T extends A & B>` syntax. Parser stores constraints as `&`-joined string in `funcConstraintMap`/`classConstraintMap`. Validation via shared `checkConstraint()` in gen_class.ss.
- **Type constraints (D031, Round 53)**: `<T extends InterfaceName>` syntax. Constraints stored in `funcConstraintMap`/`classConstraintMap` in parser.ss. MVP: class types only.
- **gen_calls.ss split (Round 52)**: Extracted gen_arrows.ss. gen_calls.ss imports from gen_arrows.ss.
- **gen_class.ss split (Round 51)**: Extracted gen_iface.ss and gen_generic_class.ss. gen_class.ss imports from both.
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
- **phase5 tests**: 45 tests.
- **35 bootstrap files**, ~12976 LOC.

## Decision Criteria
- Power operator (D032) completed: `**` codegen + `**=` compound assignment + template support.
- All file sizes reasonable: gen_class.ss ~575, gen_decls.ss ~562, check_stmts.ss ~551, parser.ss ~548, parse_exprs.ss ~524. No urgent splits needed.
- All existing features working: power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Nested template literals verified working (no code change needed).
- Phase 4 remaining: spread in calls, string/array method additions, numeric separators.
- 35 bootstrap files total, ~12976 LOC.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
