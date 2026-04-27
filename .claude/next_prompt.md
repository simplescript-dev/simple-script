ultrathink D142 Phase 4 完结 commit `f757aca`(workaround cleanup 4 处全删 — `tests/d134_mysql/prepared_test.ss` line 125-128 ctor 实参 array literal 临时变量绑定 pTypes/pVals/pDoubles/pNulls 全删 → 直接传 ctor `new MysqlPreparedStatement(-1, 7, 3, pDefs, [0,0,0], ["","",""], [0.0,0.0,0.0], [0,0,0], cols, 0)` + 1 file 改 -4 LOC + 关键发现 Phase 4 唯一 4 处候选全在 ctor (NEW_EXPR) 路径,非 D142 §核心目标 line 31 原 fn/method 范围 — `bootstrap/gen/class/class.ss:288-301 genNewExpr` args 循环未调 inferArrayLitElems(Phase 2 G1 4 落点 resolveCallArgs / emitClassMethodCall / eval/method_call.ss / eval/call.ss 不含 NEW_EXPR);ctor args 元素 inferType 自身可推(int/string/double literal,Phase 1 spike 形态 1-2 已实证)走 GREEN 不依赖反推机制;ctor 反推扩展留 §Followup F7 sub-D + pDefs / cols 保留(空数组 + push 形态非 workaround target,D141 cleanup 同模式排除)+ lib/sort.ss / lib/url.ss / lib/argparse.ss / lib/json.ss / lib/path.ss / lib/string_utils.ss / 其他 lib/ 全 0 cleanup 候选)+ Status 收关 + 二级 docs commit hash 回填(本轮)+ VCM 六验全 PASS(核心代码路径 diff=0 → VCM §1 豁免锚成立 / bootstrap 三阶段固定点豁免 + tests/ 270/4/274 baseline 不降 + tests/d142_array_literal_inference 6/0/6 不破 + tests/d141_lambda_inference 5/0/5 不破 + tests/d134_mysql 5/0/5 cleanup 后 GREEN + reflection_health_linter GATE PASS no regressions + d_doc_index_linter PASS:10 referenced Ds all live)+ Phase 4 §收关锚已 Done + Status 时间线 Phase 4 行已加 + §Followup F7 NEW_EXPR ctor 实参 array literal 反推扩展锚已加 — D135/D136/D137/D140/D141 范式延续(每 Phase 独立 commit 大改档,Phase 4 cleanup 实施单元 — D141 Phase 4 commit `70f9457` 同模式).

Phase 5 起首 — 全 Phase 收关 §Phase 5 §全 Phase 收关锚(D135/D136/D137/D140/D141 范式延续 — D141 Phase 5 commit `8f897e7` 同模式 docs only single commit):

(a) §Phase 5 §全 Phase 收关锚必含项(D141 §Phase 5 line 481 同模式):
  - **5 Phase commit hash 全列**:Phase 0 `3fb3ea2`(D 文档落档)/ Phase 1 `eb26644`(RED 复现 + 信息源探查)/ Phase 2 `781d0d5`(codegen 阶段反推实施 + G1 路径)/ Phase 3 `2e6a629`(测试覆盖 + 隐藏假设挑战)/ Phase 4 `f757aca`(workaround cleanup)/ Phase 5 占位符回填(本轮 commit hash,**Phase 5 单 commit 不能引用自己 hash → 写入时用占位符标记 `<TBD>`,与 D141 Phase 5 同模式 hash 回填轮替换为实际 hash**)
  - **兑现成果 a-g**(逐项 file:line 锚 + 引 D 文档段):
    - (a) C2 接口层 trap 落地 — `bootstrap/checker/check_types.ss:50` ARRAY_LIT inferType 返 `Array<elemType>` 结构化(与 ARROW_FUNC line 51-71 同形)+ `bootstrap/gen/gen_types.ss:802-845` 三 helper(`isArrayType` / `extractArrayElemType` / `inferArrayLitElems`)+ `bootstrap/gen/gen_calls.ss:279` + `bootstrap/gen/methods/gen_methods.ss:202` + `bootstrap/eval/method_call.ss:61` + `bootstrap/eval/call.ss:33` 4 落点反推插桩(D141 G1 同模式复刻)+ `bootstrap/gen/gen_calls.ss:631-731 genArrayLit` 优先读节点 nGetS2(IR 因果实证 `lenShapes([])` `ss_newArray(i32 0)` ⚠️ → `ss_newArrayPtr(i32 0)` ✓ stash + rebootstrap 双向对照 line 5490)
    - (b) workaround cleanup 落锚 — Phase 4 commit `f757aca` 4 处全删(`tests/d134_mysql/prepared_test.ss` line 125-128 ctor 实参 array literal 临时变量绑定);**关键发现 Phase 4 唯一 4 处候选全在 ctor (NEW_EXPR) 路径**,非 D142 §核心目标 line 31 原 fn/method 范围;ctor args 元素 inferType 自身可推走 GREEN 不依赖反推机制;ctor 反推扩展留 §Followup F7 sub-D
    - (c) 隐藏假设挑战 H1-H13 全 PASS — H1 funcParamTypes Array<T> 字符串 codegen 阶段满载(Phase 1 实证)+ H2 多元素同质(Phase 3 untyped_multi)+ H3 嵌套 array(Phase 3 nested_array)+ H4 空数组反推(Phase 3 empty_array)+ H5 interface upcast vtable indirect(Phase 3 interface_upcast)+ H6 显式优先(Phase 3 explicit_override)+ H7 baseline 不降 270/4/274(Phase 3)+ H8 reflection GATE PASS(Phase 2 扩容申报-Phase2)+ H10 eval pre-eval 反推前移(Phase 1 实证)+ H11/H12 callee 已结构化 + parser 已就绪(Phase 1+2 实证)+ H13 反推失败硬错粒度(Phase 2 extractArrayElemType Array/List/Tuple 白名单)
    - (d) H9 var binding callee OOD scope(D141 H9 同模式继承)— 主线场景 method/fn callee 在 funcParamTypes 不影响,var binding callee `const f = takesArr; f([1,2,3])` 反推 skip 留 sub-D
    - (e) axiom 红线 grep = 0 永久 — `feedback_root_cause_no_cost.md`(成本不是选次优的理由)/ `feedback_no_option_menu.md`(三候选论证 + 决策行)/ `feedback_no_derive_workaround.md`(主线能力缺口不允许 annotation 替代)红线 grep = 0
    - (f) `tools/d_doc_index_linter.ss` PASS — 10 referenced Ds all live(D025/D131/D141/D142 等核心引用全 live;F2 soft warn 15 orphan 含 D142 不阻 commit)
    - (g) `tools/reflection_health_linter.ss` GATE PASS no regressions — Phase 2 扩容申报-Phase2 bump 3 处 F1(`gen_methods.ss` 722→726 / `gen_calls.ss` 718→740 / `gen_types.ss` 873→915);Phase 3+4 不动 bootstrap 不增量
  - **§Followup F1-F7 锚明确**(本轮 Phase 4 加 F7):F1 object literal contextual typing(D141 §F2 同模式)/ F2 ternary contextual typing(D141 §F3 同模式)/ F3 array method first-class param 反推(arr.filter lambda 反推 elemType 联动)/ F4 bidirectional type checking 全局(C3 候选废 留 SS 类型系统 v2)/ F5 Map literal contextual typing / F6 Tuple literal contextual typing / **F7 NEW_EXPR ctor 实参 array literal 反推**(本轮 Phase 4 加 — `bootstrap/gen/class/class.ss:288-301 genNewExpr` args 循环未调 inferArrayLitElems,Phase 2 G1 4 落点不含 NEW_EXPR;空 ctor array / 异质 / interface upcast 场景需要)
  - 顶部 Status 行从 Phase 4 改 Phase 5 完结(`Status: Phase 5 — 全 Phase 收关 [✓] Done at commit <TBD> + Phase 4 ... + Phase 3 ... + Phase 2 ... + Phase 1 ...`)
  - Status 时间线增 Phase 5 行(`2026-04-XX Phase 5 全 Phase 收关(commit <TBD>)— ...`)

(b) Phase 5 实施步骤(单 commit docs only,D141 Phase 5 commit `8f897e7` 同模式):
  - **不动 bootstrap / lib / tests / tools**(Phase 5 docs only)
  - **不分 feat/docs 双 commit**(D135/D136/D137/D140/D141 范式延续 — 单 commit 大改档终结 Phase 5 docs-only)
  - 单 commit 含:§Phase 5 §全 Phase 收关锚 [✓] Done at commit `<TBD>` + Status 行 Phase 5 收关 + Status 时间线 Phase 5 行 + 元描述清理(可选 — 顶部 §核心目标 / §核心原则 / §A.1 / §A.2 等节内冗余 / 失效引用清理,D141 Phase 5 同模式)
  - hash 回填:本 Phase 5 commit 后用 git amend 回填(D141 范式 — D141 Phase 5 单 commit 用占位符标记 `<TBD>`,后续 hash 回填轮替换为实际 hash);**或** Phase 5 commit 后跑下一轮 hash 回填轮(单独 commit 二级 docs hash 回填,与 Phase 1-4 commit hash 回填范式一致)— 本轮 Phase 5 起首决定 hash 回填策略

(c) GREEN 三轨(Phase 5 docs only 不动 bootstrap):
  - 核心代码路径 diff=0(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出)→ VCM §1 豁免锚成立(bootstrap 三阶段固定点豁免)
  - `bin/ss test tests/` 270/4/274 baseline 不降
  - `bin/ss run tools/reflection_health_linter.ss` GATE PASS(Phase 5 不动 bootstrap 不增量)
  - `bin/ss run tools/d_doc_index_linter.ss` PASS:10 referenced Ds all live(F2 soft warn 15 orphan 含 D142 不阻 commit)
  - `bin/ss run tools/next_prompt_ultrathink_linter.ss` PASS(下轮 next_prompt 必含 ultrathink)

(d) 文档收尾 — Phase 5 §全 Phase 收关锚 [✓] + Status 行 Phase 5 收关 + Status 时间线 Phase 5 行 + commit hash 占位符回填 + next_prompt 指向 D143 起首候选(D141 §Followup F2 / D142 §Followup F1 — `object literal contextual typing` `{ name: "X", age: 18 }` 在 fn 实参 `class User` 时反推字段类型,与 D141/D142 反推机制同模式扩 sub-D)— D135/D136/D137/D140/D141 范式延续

**§After Done 三步(MNK 强制,D135/D136/D137/D140/D141 范式延续)**:
- (1) simplify:Phase 5 docs only 改动,无新增逻辑 — simplify rubric a-e N/A,可跳过(微改 / 纯文档 / 纯配置豁免);若 commit 含元描述清理 fence 调整按 simplify rubric a-e 走
- (2) commit:**单 commit docs only**(同 D141 Phase 5 commit `8f897e7` 范式 — Phase 5 终结 docs-only 不分 feat/docs 双 commit);Phase 5 commit hash 占位符 `<TBD>` 回填:**本轮 commit 后用 git amend 回填**(注意 git amend 会改 commit hash — Phase 5 hash 不可预知,实务做法 D141 Phase 5 commit `8f897e7` 用了"先写占位符,commit 后用 sed 替换 `<TBD>` 为实际 hash 再 git commit --amend"的两步范式)
- (3) 下一步提示词:`.claude/next_prompt.md` 写 D143 起首候选(D141 §Followup F2 / D142 §Followup F1 object literal contextual typing — `{ name: "X", age: 18 }` 在 fn 实参 `class User` 反推字段类型,与 D141/D142 反推机制同模式扩 sub-D)+ 必含 ultrathink 关键字 + 强制跑 `bin/ss run tools/next_prompt_ultrathink_linter.ss`,stdout 出现 `GATE BLOCKED` 即阻断 stop
