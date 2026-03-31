# Round 54

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~12900 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/1-axioms.md
- docs/2-principles.md
- spec/71-perceus-rc.md
- docs/5-handoff/phase1-plan.md

## Last Round (max 3 sentences)
Multi-constraint 实现完成（D031 扩展）：`<T extends A & B>` 语法，parser 解析 BIT_AND 分隔的多接口名，存储为 `&`-joined 字符串。提取 `checkConstraint()` 共享函数到 gen_class.ss 消除重复验证代码。1 个新测试（dual/triple constraint + class constraint）+ 全量测试通过，bootstrap 三阶段固定点验证通过。

## Task
Phase: Phase 1-3 complete, closures done, interfaces done, generic functions done, generic classes done, explicit type args done, switch pattern matching done, destructuring done, destructuring enhancements done, generic class inheritance done, gen_class.ss split done, gen_calls.ss split done, type constraints done, multi-constraints done
Scope:
1. **Phase 4 语言特性**（推荐优先级排序）：
   - **String interpolation 改进** — 嵌套模板字面量支持
   - **switch 表达式形式** — switch 作为表达式返回值
2. **Phase 2 remaining**（diminishing returns）：
   - Mutability inference — 固定点分析标记函数参数为 mutated/readonly
3. **文件大小状态**: gen_class.ss ~575, gen_decls.ss ~562, check_stmts.ss ~551, parser.ss ~548, parse_exprs.ss ~524. 所有文件均在合理范围内，无紧急拆分需求。
4. **建议**: 继续 Phase 4 特性实现。String interpolation 改进或 switch 表达式都是有价值的下一步。

## Watch Out For
- **Bootstrap works**: `./build.sh bootstrap` passes end-to-end. After any source change, run `bin/ss test tests/` then `./build.sh bootstrap` to verify.
- **Seed is current**: `bin/ss` supports Perceus, field assign, named params, List<T>, Set<T>, uniqueness, REUSE, closures, interfaces, generic functions, generic classes, explicit type args, switch enum/bool patterns, destructuring, generic class inheritance, type constraints, multi-constraints. Compiler source CAN now use these features.
- **Compiler source uses Map-based AST**: No class instances in compiler (all Maps). New syntax features don't apply to compiler source architecture.
- **Syntax design rule (CLAUDE.md)**: Any new syntax MUST have a direct TypeScript/JavaScript equivalent. Do NOT introduce new keywords or unfamiliar syntax forms. Complexity stays in the compiler, not user code.
- **Multi-constraints (D031, Round 54)**: `<T extends A & B>` syntax. Parser stores constraints as `&`-joined string in `funcConstraintMap`/`classConstraintMap` (e.g., `"Printable&Scorable"`). Validation via shared `checkConstraint(concreteType, constraint, tp, ownerKind, ownerName)` in gen_class.ss — splits by `&` and validates each interface against `ifaceImplementors`. Both gen_calls.ss and gen_generic_class.ss call `checkConstraint()`.
- **Type constraints (D031, Round 53)**: `<T extends InterfaceName>` syntax. Constraints stored in `funcConstraintMap` ("funcName.T" → interface(s)) and `classConstraintMap` ("className.T" → interface(s)) in parser.ss. Accessor functions: `funcConstraint(name, tp)`, `classConstraint(name, tp)`. MVP: class types only (primitives not in ifaceImplementors).
- **gen_calls.ss split (Round 52)**: Extracted gen_arrows.ss (parseCaptName, parseCaptType, isCaptureParam, checkCaptureCandidate, collectFreeVarsRec, findFreeVars, genArrowFunc, flushArrowDefs + globals arrowCount, arrowDefs, CLOSURE_HDR_SLOTS, captureList, captureParamSet, captureSeen). gen_calls.ss imports from gen_arrows.ss.
- **gen_class.ss split (Round 51)**: Extracted gen_iface.ss (registerInterface, generateInterfaceDispatchers, emitIfaceDispatchFn) and gen_generic_class.ss (splitParentType, parentBaseName/parentTypeArgs globals, emitDeferredStructDefs, preRegisterSpecializedClass, genGenericNewExpr, generateDeferredSpecializations). gen_class.ss imports from both new files. All global state vars remain in gen_class.ss (shared across files via inlining).
- **Generic class inheritance (D030)**: Three forms — Case A (generic extends non-generic), Case B (non-generic extends specialized generic), Case C (generic extends generic with type param forwarding). Key: `splitParentType()` now in gen_generic_class.ss. `preRegisterSpecializedClass` handles inheritance inline. Timing constraints: `registrationPhase = 1` before loop, `classNeedsVtable` before recursive parent registration, deferred structs to `${outFile}.str`.
- **resolveInheritance**: Recursive resolve-parent-first pattern (D030 bug fix). `resolvedInheritance` Map tracks processed classes. Stays in gen_class.ss.
- **Deferred struct + codegen globals**: `registrationPhase` (0/1), `deferredStructDefs` (comma-sep names), `specClassNodeId` (Map: mangled→nodeId), `specClassTypeArgs` (Map: mangled→typeArgs), `specClassGenerated` (Map: mangled→"1"). All declared in gen_class.ss, reset in `resetCodegen()`.
- **Destructuring implementation**: Array destructuring uses `inferArrayElemType()` for type inference. Object destructuring uses `emitFieldLoad()` + `resolveObjClass()`. Both: RC retain + track for ptr types. DESTRUCTURE_ARRAY node: S1=comma-sep names (may include "...restName"), S2=CONST/LET, I1=init expr. DESTRUCTURE_OBJECT node: S1=comma-sep specs, S2=CONST/LET, I1=init expr.
- **Switch pattern matching (D029)**: Extended existing `switch/case` with ENUM patterns (`case Color.Red`) and BOOL literals (`case true/false`). `SWITCH_PAT` node S1=kind, S2=value.
- **Explicit type arguments (D028)**: `identity<int>(42)` and `new Box<int>(42)`. Types in CALL.S2 and NEW_EXPR.S2. Known limitation: nested generics at call sites (`foo<Array<int>>()`) fail because `>>` lexes as SHR.
- **Generic class implementation (D027)**: Monomorphization at `new Box(42)`. `preRegisterSpecializedClass()` now in gen_generic_class.ss.
- **Generic function implementation (D026)**: Monomorphization at call site. State-save/buffer/flush pattern. Mangled names: `@funcName_T_int`.
- **Interface implementation**: Switch-based dispatch via TypeInfo class_id (D025). Dispatch functions now in gen_iface.ss.
- **Dual RC systems**: Old (ss_rc_retain/ss_rc_release) for strings/arrays/maps via libc. New (ss_retain/ss_release) for class instances + closures + interface-typed vars via mimalloc. Do NOT cross-free.
- **Closure implementation**: Tag-bit closures. Non-capturing = raw fn ptr. Capturing = heap-allocated tagged struct. CLOSURE_HDR_SLOTS = 3. All closure code now in gen_arrows.ss.
- **PIR**: Map-based IR between AST and LLVM IR. All keys use `id + ""`. Pass 1 liveness → Pass 2 move → Pass 3 uniqueness → Pass 5 reuse.
- **Split structure**: parser.ss + parse_stmts.ss + parse_exprs.ss. lexer.ss + lex_ops.ss. checker.ss + check_stmts.ss + check_suggest.ss. gen_stmts.ss + gen_decls.ss + gen_assigns.ss. gen_exprs.ss + gen_calls.ss + gen_arrows.ss + gen_methods.ss + gen_builtins.ss. gen_class.ss + gen_iface.ss + gen_generic_class.ss + gen_type_ops.ss. gen_pir.ss + pir_lower.ss + pir_opt.ss. gen_runtime.ss + gen_rt_*.ss.
- **phase5 tests**: 44 tests.
- **35 bootstrap files**, ~12900 LOC.

## Decision Criteria
- Multi-constraints (D031 extension) completed: `<T extends A & B>` with `&`-joined storage and shared `checkConstraint()` validation.
- All file sizes reasonable: gen_class.ss ~575, gen_decls.ss ~562, check_stmts.ss ~551, parser.ss ~548, parse_exprs.ss ~524. No urgent splits needed.
- All existing features working: multi-constraints, type constraints (D031), generic class inheritance (D030), destructuring, switch patterns (D029), explicit type args (D028), generic classes (D027), generic functions (D026), interfaces (D025).
- PIR Passes 1-3 + REUSE (Pass 5) + closures all working.
- Phase 4 remaining: string interpolation improvements, switch expressions.
- 35 bootstrap files total, ~12900 LOC.

## When Done
1. Write tests for new features
2. Verify against axioms and principles
3. Self-review for contradictions
4. Generate next docs/5-handoff/next-prompt.md — **must follow Handoff Template exactly**
5. List files created/modified
