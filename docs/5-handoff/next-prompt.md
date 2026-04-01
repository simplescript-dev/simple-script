# Round 56

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~13069 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
Array 高阶方法补齐：`find`, `findIndex`, `some`, `every`（prelude + genHigherOrderMethod dispatch）+ `includes`（genArrayMethod，基于 indexOf）。5 个方法均在 prelude.ss 中纯 SS 实现，gen_builtins.ss 添加 codegen dispatch，gen_registry.ss 注册返回类型，gen_types.ss 为 find 添加 inferArrayElemType 推导。1 个新测试（18 case）+ 全量测试通过，bootstrap 三阶段固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done
Scope:
1. **Phase 4 语言特性**（推荐优先级排序）：
   - **Spread operator** — `...arr` in function calls and array literals (partial: array spread exists, function call spread missing)
   - **Numeric separators** — `1_000_000` already implemented in lexer (skip)
   - **String `.includes()`** — alias for existing `.contains()` method
   - **for-of loops** — `for (const item of iterable)` syntax (TS alignment)
   - **Optional chaining** — `obj?.field` (partial: `?.method()` exists, `?.field` missing)
2. **Phase 2 remaining**（diminishing returns）：
   - Mutability inference — 固定点分析标记函数参数为 mutated/readonly
3. **文件大小状态**: gen_class.ss ~575, gen_decls.ss ~562, check_stmts.ss ~551, parser.ss ~548, parse_exprs.ss ~524, gen_types.ss ~411. 所有文件均在合理范围内，无紧急拆分需求。
4. **建议**: 继续 Phase 4 特性实现。Spread in calls 是标准 TS/JS 特性。String `.includes()` 是简单 alias。

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports Perceus, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array higher-order methods (find/findIndex/some/every/includes). Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Array methods (Round 56)**: `find/findIndex/some/every` implemented as prelude functions (_ss_find etc.) + genHigherOrderMethod dispatch. `includes` implemented inline via indexOf in genArrayMethod. Return types registered in methodRetTypes. `find` has special inferType case using inferArrayElemType for element type inference. All follow the existing higher-order pattern (callback as i64 fn ptr).
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
- **phase5 tests**: 46 tests.
- **35 bootstrap files**, ~13069 LOC.

## Decision Criteria
- Array methods (Round 56) completed: find/findIndex/some/every/includes all working.
- All file sizes reasonable: gen_class.ss ~575, gen_decls.ss ~562, check_stmts.ss ~551, parser.ss ~548, parse_exprs.ss ~524. No urgent splits needed.
- All existing features working: array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Phase 4 remaining: spread in calls, string .includes(), for-of, optional field chaining.
- 35 bootstrap files total, ~13069 LOC.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
