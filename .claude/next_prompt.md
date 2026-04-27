ultrathink D143 Phase 3 起首 — 测试覆盖 + 隐藏假设挑战(D135/D136/D137/D140/D141/D142 范式延续 — D141 Phase 3 commit `<待查>` + D142 Phase 3 commit `<待查>` 同模式)。

**前置已就绪(Phase 2 commit 待回填实证)**:
- §A.2 H1 PASS:funcParamTypes class 名 codegen 阶段满载(Phase 1 实证已锁)
- §A.2 H10 OOD 实证错估修正:Phase 2 三处 pre-eval 前移 inferObjLiteralFields(`eval/call.ss:36 + eval/method_call.ss:64 + eval/new_expr.ss:24`)+ class_method.ss:genNamedConstructorArgs 嵌套 H3 反推 — D141/D142 H10 完全同形
- spike `/tmp/spike_d143_phase2.ss` GREEN 主线(`takesUser({ name: "Y", age: 18 })` → `Y:18` + `takesProfile({ user: { name: "Z", age: 20 }, addr: "Earth" })` → `Z@Earth`)— H1/H2/H3 主线 PASS
- gen_types.ss helper 三函数 ready:`isClassType` / `extractClassName` / `inferObjLiteralFromType` + `inferObjLiteralFields`
- D084 rewrite 同模式 inline ready(三步原子:nSetS2 + nKind→NEW_EXPR + nSetS1 → 走 NEW_EXPR genNamedConstructorArgs 路径)

**Phase 3 实施清单(D141/D142 Phase 3 同模式)**:
1. **`tests/d143_object_literal_inference/` 新建 6+ 测试**:
   - `single_field.ss` — H1 单字段反推(class 仅 1 字段时 `takesUser({ name: "X" })`)
   - `multi_field.ss` — H2 多字段同质反推(`takesUser({ name: "X", age: 18 })` 完整字段)
   - `nested.ss` — H3 嵌套 OBJ_LITERAL(`takesProfile({ user: {...}, addr: "..." })`)
   - `mixed_field.ss` — H5 字段类型混合(string + int + Array)
   - `explicit_override.ss` — H6 显式注解优先(`let u: User = {...}; takesUser(u)` D084 既有路径不破)
   - `interface_upcast_skip.ss` — H5b interface upcast OOD scope(object literal 不能 implements interface,显式 NEW_EXPR + vtable indirect dispatch 跳过反推)
   - `partial_field_strict.ss` — H4 部分字段 mismatch 决策(严格模式硬错 vs 默认值模式 — 当前实测 ctor arity error,Phase 3 决策行)
   - `mismatch_硬错.ss` — H13 反推失败硬错粒度(`{ name: 18, age: "X" }` 倒置类型 / callee 不在 funcParamTypes 走 skip)
2. **§A.2 隐藏假设全 PASS 实证**:H1/H2/H3/H5/H6/H7/H8 全 PASS;H4 决策行(严格 vs 默认值)落档;H5b OOD scope 标 + H9/H11/H12/H13 OOD/弱化标
3. **Followup F4 NEW_EXPR ctor 实参 OBJ_LITERAL 反推**(若 H3 nested + H4 strict 测试发现 NEW_EXPR ctor args 内 OBJ_LITERAL 反推路径需扩,Phase 3 顺手补 — D142 §Followup F7 同模式)
4. **VCM 六验全跑**:① bootstrap 三阶段固定点 ② tests/ 270/4/274+6 baseline ③ reflection_health_linter GATE PASS ④ §A.2 H1-H8 全 PASS + H4 决策行 ⑤ d_doc_index_linter F1=0 ⑥ next_prompt_ultrathink_linter PASS
5. **§MNK §字段 9 自证 grep**:Phase 2 修正 §A.2 H10 实证错估 — 检查 D141/D142 H10 实证表述是否同模式准确;若 D141/D142 H10 实证也仅 grep 字面 handler 漏判 → 反思补加 cross-D 实证 SSoT(memory 落档反复跨 D 验证模式)
6. **§MNK 大改档 commit 独立** — Phase 3 单独 commit `feat(D143): Phase 3 — 测试覆盖 + 隐藏假设挑战 + Followup F4 评估`,§After Done 三步(simplify → commit → 下一步 next_prompt 指向 Phase 4 cleanup)

**Phase 3 反推 spike 形态扩展**(对照 RED→GREEN 实测):
- 显式 vs 反推:`let u: User = {...}; takesUser(u)`(显式 D084)vs `takesUser({...})`(反推 D143)— 两路径 IR 应等价 `call ptr @User_new(...)`
- 嵌套深度 ≥ 2:`{ user: { profile: { name: "X" } } }` 三层嵌套反推 — 验证递归回填链路完整
- 字段顺序无关:用户写 `{ age: 18, name: "X" }`(倒序)与 `{ name: "X", age: 18 }`(正序)IR 等价(genNamedConstructorArgs 按 classFields 顺序拼)
- spread 反推 OOD scope:`{ ...base, name: "X" }` Phase 3 不实施(D143 §Followup F7 同模式 sub-D)

**Status 行收关(Phase 3 完结)** + 下一步 next_prompt 指向 Phase 4 cleanup:grep + 删现存 fn 实参 OBJ_LITERAL 临时变量绑定 workaround(若有 `let u: User = {...}; takesFn(u)` 形态)— D135/D136/D137/D140/D141/D142 范式延续。
