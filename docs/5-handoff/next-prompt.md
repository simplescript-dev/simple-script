# Round 58

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~13282 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
Tuple types 实现：`[int, string]` 类型语法（parser 转为 `Tuple<int,string>` 内部表示），位置类型推断（INDEX_ACCESS 常量索引时返回位置类型），元组解构支持（genDestructureArray 按位置分配类型）。修复混合类型数组安全问题：同时含 ptr 和 scalar 元素的 array literal 使用 `ss_newArray` (tag=1) 避免 cleanup 将 int 当 pointer 释放导致 segfault。1 个新测试 + 全量测试通过，bootstrap 三阶段固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done, power operator done, array methods done, phase 4 features batch done, tuple types done
Scope:
1. **Phase 4 remaining features**:
   - **Numeric separators** — `1_000_000` already implemented in lexer (skip)
   - **String template tag functions** — Tagged templates (advanced, low priority)
2. **Standard library expansion**:
   - **json.ss** enhancements — Additional JSON utilities
   - **path.ss** — Path manipulation utilities
   - **fs.ss** — File system wrapper (higher-level API over existing runtime)
3. **Phase 2 remaining** (diminishing returns):
   - Mutability inference — Fixed-point analysis marking function params as mutated/readonly
4. **文件大小状态**: gen_class.ss ~615 (approaching limit), gen_decls.ss ~576, parser.ss ~559, check_stmts.ss ~553, parse_exprs.ss ~531, parse_stmts.ss ~519, checker.ss ~518, gen_calls.ss ~507. gen_class.ss may need a split if further features add to it.
5. **建议**: Consider standard library expansion (json/path/fs) or other language features. gen_class.ss at 615 lines may need splitting if more codegen features are added there. Phase 4 is essentially complete (tuples done, numeric separators done, tag functions deferred).

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports all Phase 1-4 features including: Perceus RC, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints, `**` operator, array methods, string `.includes()`, `for-of`, `?.field`, spread in calls, **tuple types `[T, U]`**. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
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
- **phase5 tests**: 51 tests.
- **35 bootstrap files**, ~13282 LOC.

## Decision Criteria
- Tuple types (D034, Round 58) completed: `[int, string]` syntax, positional type inference, tuple destructuring, mixed-type array safety.
- Phase 4 essentially complete: tuples done, numeric separators done, tag functions deferred (low priority).
- File sizes: gen_class.ss ~615 (largest, approaching limit), gen_decls.ss ~576, parser.ss ~559, check_stmts.ss ~553, parse_exprs.ss ~531, parse_stmts.ss ~519, checker.ss ~518, gen_calls.ss ~507.
- All existing features working: tuple types (D034), Phase 4 batch (D033), array methods, power operator (D032), multi-constraints (D031), type constraints, generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Known issue: `genOptionalMethodCall` has same double-evaluation pattern that was fixed in `genOptionalMemberAccess`. Low priority since method call object is typically an IDENT.
- 35 bootstrap files total, ~13282 LOC, 51 phase5 tests.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Commit and push to remote
5. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
6. List files created/modified
