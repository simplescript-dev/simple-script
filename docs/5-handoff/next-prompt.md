# Round 57

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~13204 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
Phase 4 特性批量实现：string `.includes()` (通过 genArrayMethod dispatch)、`for-of` 循环 (FOR_OF 节点 + genForIn 复用)、optional field chaining `obj?.field` (genOptionalMemberAccess 直接字段加载避免双重求值)、spread in calls `foo(...args)` (resolveCallArgs 提取数组元素 + checker 跳过 spread 参数计数检查)。4 个新测试 + 全量测试通过，bootstrap 三阶段固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done
Scope:
1. **Phase 4 remaining features**:
   - **Numeric separators** — `1_000_000` already implemented in lexer (skip)
   - **Tuple types** — Fixed-length typed arrays `[int, string]` (new)
   - **String template tag functions** — Tagged templates (advanced, low priority)
2. **Standard library expansion**:
   - **json.ss** enhancements — Additional JSON utilities
   - **path.ss** — Path manipulation utilities
   - **fs.ss** — File system wrapper (higher-level API over existing runtime)
3. **Phase 2 remaining** (diminishing returns):
   - Mutability inference — Fixed-point analysis marking function params as mutated/readonly
4. **文件大小状态**: gen_class.ss ~615 (approaching limit), gen_decls.ss ~562, check_stmts.ss ~553, parser.ss ~548, parse_exprs.ss ~531, parse_stmts.ss ~519, checker.ss ~518, gen_calls.ss ~506. gen_class.ss may need a split if further features add to it.
5. **建议**: Consider standard library expansion (json/path/fs) or other language features. gen_class.ss at 615 lines may need splitting if more codegen features are added there.

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods (find/findIndex/some/every/includes), string `.includes()`, `for-of`, `?.field`, spread in calls. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Phase 4 batch (D033, Round 57)**: Four features implemented together:
  - **String `.includes()`**: Dispatched through `genArrayMethod` (NOT genStringMethod — genArrayMethod handles both array and string cases via type branching). Return type already registered as "includes" → "int".
  - **`for-of` loops**: `FOR_OF` AST node, same layout as `FOR_IN` (S1=item, I1=iterable, I2=body). `of` is a contextual keyword (IDENT value check, not a reserved keyword). Supports bare `for (x of arr)`, `for (const x of arr)`, `for (let x of arr)`. All codegen/checker/PIR handlers check `|| kind == "FOR_OF"` alongside `FOR_IN`. Reuses `genForIn()`.
  - **Optional field chaining `?.field`**: Parser already stored `nGetI3(id, isOptional)` on MEMBER_ACCESS nodes. `genOptionalMemberAccess()` in gen_class.ss: evaluates obj once, null check, direct field load via `resolveObjClass` + `emitFieldLoad` (no double evaluation). Default: `""` for ptr, `0` for int/double.
  - **Spread in function calls**: `SPREAD_ELEM` nodes in `parseArgs()`. `resolveCallArgs()` extracts elements via `ss_arrayGet` for remaining param slots. Type conversion: i64→ptr (inttoptr), i64→i32 (trunc), i64→double (bitcast). Checker `hasSpreadArg()` skips arg count validation. Spread must be last arg (positional, not interleaved).
- **Array methods (Round 56)**: `find/findIndex/some/every` as prelude + genHigherOrderMethod. `includes` as genArrayMethod (indexOf-based). Return types in methodRetTypes.
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
- **phase5 tests**: 50 tests.
- **35 bootstrap files**, ~13204 LOC.

## Decision Criteria
- Phase 4 batch (Round 57) completed: string includes, for-of, optional field chaining, spread in calls.
- File sizes: gen_class.ss ~615 (largest, approaching limit), gen_decls.ss ~562, check_stmts.ss ~553, parser.ss ~548, parse_exprs.ss ~531, parse_stmts.ss ~519, checker.ss ~518, gen_calls.ss ~506. gen_class.ss may need a split soon.
- All existing features working: Phase 4 batch, array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Phase 4 largely complete: numeric separators (already done), string includes (done), for-of (done), optional chaining (done), spread (done).
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- 35 bootstrap files total, ~13204 LOC, 50 phase5 tests.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
