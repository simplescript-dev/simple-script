ultrathink D145 Phase 1 — RED 复现 + 信息源探查 — Map literal 节点 slot 占用探查(D143 已用 nSetS2 className,Phase 1 决策 nSetS3 valueType 扩 vs 单 nSetS2 复合)+ 8+ dispatch site 全 grep + funcParamTypes Map<K,V> 时序 §A.2 H1 同模式实证 + eval pre-eval 时序 §A.2 H10 cross-D 反思继承(D143/D144 教训)+ Phase 2 入口全锁 — D135/D136/D137/D140/D141/D142/D143/D144 范式延续(D144 Phase 1 commit `17a1573` 同模式)。

§前置就绪(D144 Phase 5 commit `15c4c9a` 已锁 + D145 Phase 0 commit `<本轮回填>` 已锁):
— D145 §Phase 0 章节 [✓] Done at commit `<本轮回填>` (2026-04-28)— D142 §Followup F5 + D143 §Followup F2 + D144 §Followup F1 同位三合 sub-D 起首落档 + Phase 0-5 计划草案 + §A.1 三主候选 + §A.1.1 三实施路径 + §A.2 H1-H13 隐藏假设挑战 + §A.3 废案 + Followup F1-F6 同位映射 D144 §F2-F7
— VCM 六验全 PASS(§1 豁免 `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + tests/d144 8/0/8 + tests/d143 6/0/6 + tests/d142 6/0/6 + tests/d141 5/0/5 + reflection_health GATE PASS 11 metric baseline 不变 + d_doc_index F1=0 11 referenced Ds all live + F2 soft warn 17 含 D145 不阻)
— D144 主线 close + 5 Phase commit hash 全锚(Phase 0 `02415c9` / Phase 1 `17a1573` / Phase 2 `71af131` / Phase 3 `959a2de` / Phase 4 `9af130c` / Phase 5 `15c4c9a`)+ Followup F1-F7 入下游 sub-D 启动队列(F1 Map literal contextual typing → D145 入口)
— D145 主战场锁定:checker `check_exprs.ss:OBJ_LITERAL case` callee 类型分叉判定(`Map<K,V>` → Map literal 反推 K + V;`class<X>` → 走 D143 既有 className 反推) + codegen 阶段反推回填 keyType + valueType slot + eval pre-eval 时序前移 + helper 三函数(`isMapType` / `extractMapKVTypes` / `inferMapLiteralKVTypes`)+ codegen 路径分叉(`Map<K,V>` 走 ss_newMap + ss_mapSet * N;`class<X>` 走 D143 既有 class ctor)

§任务清单(D145 Phase 1 实施 — RED 复现 + 信息源探查 + Phase 2 入口全锁,D144 Phase 1 commit `17a1573` 同模式):

(1) **D145 Phase 0 commit hash 回填**(本轮 hash 回填轮先做):
  - `git log --oneline | head -3` 找最新 D145 Phase 0 commit hash → Edit `docs/3-decisions/D145-map-literal-contextual-typing.md` 3 处 `<placeholder>`(grep 实测 3 处定位精确):
    - line 3 Status 行(`Phase 0 — D 文档落档 [✓] Done at commit \`<placeholder>\``)→ Phase 0 hash
    - §Phase 收关锚 §Phase 0 章节标题(`### Phase 0: D 文档落档 [✓] Done at commit \`<placeholder>\``)→ Phase 0 hash
    - Status 时间线起首行(`2026-04-28 Phase 0 D 文档落档(commit \`<placeholder>\`)`)→ Phase 0 hash

(2) **RED 复现 spike**(`/tmp/spike_map_lit_red.ss` Phase 1 写入):
  - 写 7+ 形态 spike(单 K-V / 多 K-V / 嵌套 Map / Map<K,Array<V>> / Map<K,User> 类型化值 / Map<K,V?> nullable values / 显式 new Map() + .set 与反推同行)
  - `bin/ss build /tmp/spike_map_lit_red.ss --emit-ir 2>&1 | head -30` 看 IR 层 RED 铁证(callee `Map<K,V>` + OBJ_LITERAL 反推到 D143 className 路径走 `<unknown>_new(...)` ctor 失败 / silent miscompile / checker 硬错)
  - `bin/ss run /tmp/spike_map_lit_red.ss 2>&1 | head -10` 看 run 时 LLC error / segfault / silent miscompile 铁证

(3) **§A.2 H1 同模式实证**(funcParamTypes Map<K,V> 时序 — D141/D142/D143/D144 H1 同模式继承):
  - grep `bootstrap/gen/codegen.ss:110-112` 普通函数 funcParamTypes 注册路径
  - grep `bootstrap/gen/gen_registry.ss:56-57` class method funcParamTypes 注册路径
  - grep `bootstrap/gen/codegen.ss:326` registerAllDecls 时序确认在 emitGlobalsAndCode 之前
  - 实证 funcParamTypes Map<K,V> 字符串 codegen 阶段已满载 + Map<K,V> 嵌套泛型(`Map<string,Array<int>>` / `Map<int,Map<string,User>>` 等)正确注册

(4) **§A.2 H10 cross-D 反思继承**(eval pre-eval 时序 — D143/D144 H10 教训 `feedback_h10_cross_d_verify.md`):
  - **不能仅 grep 字面 handler `evalObjLiteral`**(handler 触发时 callee context 已丢)
  - 必须 grep `bootstrap/eval/method_call.ss:36-70` outer call site pre-eval — D141/D142/D143/D144 反推前移落锚行确认
  - 必须 grep `bootstrap/eval/call.ss:18-43` outer call site pre-eval — D141/D142/D143/D144 反推前移落锚行
  - 必须 grep `bootstrap/eval/new_expr.ss:24-41` outer call site pre-eval — D143 NAMED_ARG OBJ_LITERAL 反推 + D144 落点
  - **D145 同点追加** `inferMapLiteralKVTypes(argId, callee, idx)` 第 5 行 — D141/D142/D143/D144 G1 4 落点 + D145 同位扩到第 5 行

(5) **OBJ_LITERAL 节点 slot 占用探查**(D143 已用 nSetS2 className,Phase 1 决策双 slot vs 复合 slot):
  - `bootstrap/parse/parse_exprs.ss:521-522`(D143 探查锚)`newNode("OBJ_LITERAL")` + `nSetList(id, fields)` — i1/i2/i3/i4 + s1/s3 全空闲(s2 D143 已用 className)
  - **决策 A**:nSetS2 复合存 `Map<K,V>` 字符串 + nGetS2 startsWith("Map<") 判定走 Map literal vs `class<X>` 判定走 D143 既有(单 slot 复用,语义靠 prefix 区分)
  - **决策 B**:nSetS2 keep className(D143 不破)+ nSetS3 存 valueType + nSetS1 加 marker "MAP" 区分(双 slot + marker)
  - **决策 C**:nSetS2 复合 + nSetS3 加 marker — 实测 grep + Phase 2 实施成本评估后定案(根因优先 + LOC 最少 + D143 path 不破)

(6) **OBJ_LITERAL kind dispatch site 全 grep**(D143 已落基础,D145 加 callee 类型分叉判定后扩):
  - parser(`bootstrap/parse/parse_exprs.ss` OBJ_LITERAL 节点构造)
  - checker case(`bootstrap/checker/check_exprs.ss:285` D143 已落 untyped 放行入口)
  - checker inferType(`bootstrap/checker/check_types.ss` OBJ_LITERAL inferType case)
  - genVal dispatch(`bootstrap/gen/exprs/exprs.ss` OBJ_LITERAL case)
  - codegen inferType(`bootstrap/gen/gen_types.ss:544-551` D143 落点)
  - codegen emit(`bootstrap/gen/exprs/` 或 `bootstrap/gen/class/` D143 落点 — `class_method.ss:genNamedConstructorArgs` 嵌套反推)
  - eval dispatch(`bootstrap/eval/eval_expr.ss` OBJ_LITERAL case)
  - eval handler(`bootstrap/eval/object_literal.ss` 或 `bootstrap/eval/expr_obj.ss` 待 grep 实测)
  - PIR(`bootstrap/pir/pir_lower.ss` OBJ_LITERAL use 分析 — 仅递归收集 use 不破反推链路)

(7) **Phase 2 入口全锁**(D145 §1 必读清单 line 号精确化):
  - `bootstrap/checker/check_exprs.ss:285` 改:加 callee 类型分叉判定(`isMapType(calleeType)` → Map literal 反推 K + V;else 走 D143 既有 className 反推)
  - `bootstrap/checker/check_types.ss` OBJ_LITERAL inferType case 改:优先读 nGetS2/S3(Map<K,V> 形态)fallback `class<ClassName>`(D143)fallback "auto"
  - `bootstrap/gen/gen_types.ss` 加 helper 3 函数:`isMapType` / `extractMapKVTypes` / `inferMapLiteralKVTypes`(对偶 D141 isFnType + D142 isArrayType + D143 isClassType + D144 isNullableType)
  - `bootstrap/gen/gen_calls.ss:284` + `bootstrap/gen/methods/gen_methods.ss:206` args 循环加 inferMapLiteralKVTypes(D141/D142/D143/D144 G1 4 落点同位扩)
  - `bootstrap/eval/method_call.ss:64` + `bootstrap/eval/call.ss:36` + `bootstrap/eval/new_expr.ss:24` outer call site pre-eval 追加 inferMapLiteralKVTypes 第 5 行(D141/D142/D143/D144 H10 cross-D 反思继承)
  - `bootstrap/gen/gen_runtime.ss` 或 `bootstrap/gen/rt/gen_rt_*.ss` D052 ss_newMap + ss_mapSet 入口探查(待 Phase 1 grep 精确文件)— Phase 2 codegen emit 直接调,无重写

(8) **VCM 六验**(本轮 docs-only — D145 Phase 0 commit hash 回填 + Phase 1 RED + 信息源探查 — Phase 1 主战场是 docs + spike 文件,§1 豁免依然成立):
  - `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 → §1 豁免锚成立
  - `bin/ss test tests/d144_ternary_inference/` 8/0/8 不破
  - `bin/ss test tests/d143_object_literal_inference/` 6/0/6 不破
  - `bin/ss test tests/d142_array_literal_inference/` 6/0/6 不破
  - `bin/ss test tests/d141_lambda_inference/` 5/0/5 不破
  - `bin/ss run tools/reflection_health_linter.ss` GATE PASS no regressions
  - `bin/ss run tools/d_doc_index_linter.ss` PASS:11 referenced Ds all live(F1=0;F2 soft warn 17 含 D145 不阻 — D145 当前是新 D 文档无 §-form 引用同 D135/D144 等同位)

(9) **commit `feat(D145): Phase 1 — RED 复现 + 信息源探查 — Map literal 节点 slot 占用探查 + 8+ dispatch site 全 grep + funcParamTypes Map<K,V> 时序 §A.2 H1 同模式实证 + eval pre-eval 时序 §A.2 H10 cross-D 反思继承(D143/D144 教训)+ Phase 2 入口全锁 — D135/D136/D137/D140/D141/D142/D143/D144 范式延续(D144 Phase 1 commit \`17a1573\` 同模式)`**(D144 Phase 1 commit `17a1573` 同模式锚)
  - D145 Phase 0 commit hash 回填(3 处 placeholder 精确替换)
  - D145 §1 必读清单 + §A.2 H1/H10 实证记录入档
  - D145 §Phase 收关锚 §Phase 1 章节落档(spike 形态 + RED 铁证 + 信息源探查 PASS + Phase 2 入口全锁)
  - D145 Status 时间线增 Phase 1 行
  - 仅 stage `docs/3-decisions/D145-*.md` + `.claude/next_prompt.md` 两文件,**不**用 `git add -A` 防混入工作树遗留删除

(10) **next_prompt 指向 D145 Phase 1 commit hash 回填轮**(同 D144 Phase 1 commit `17a1573` 后 commit `ef2d2dd` hash 回填轮模式):
  `docs(D145): Phase 1 commit hash 回填 <Phase 1 hash> + Status 行收关(Phase 1 完结)+ next_prompt 指向 Phase 2(codegen 阶段反推实施 + G1 D141/D142/D143/D144 同模式复刻 — checker check_exprs.ss callee 类型分叉判定 + check_types.ss + gen_types.ss helper 3 函数 + gen_calls/gen_methods args 循环 + eval pre-eval 三处前移 + codegen Map literal emit 路径分叉)— D135/D136/D137/D140/D141/D142/D143/D144 范式延续`

§根因优先(CLAUDE.md §项目技术规则):
— **根因解决度 + 第一性需求覆盖度**第一,LOC / 工程量 / bootstrap 轮数不是次优排序依据
— D145 主战场是 callee 类型分叉判定 + Map literal K + V 双类型反推 + codegen 路径分叉(`Map<K,V>` → ss_newMap + ss_mapSet * N;`class<X>` → 走 D143 既有 class ctor)— 不接受次优 / workaround / 临时绕道
— Phase 1 信息源探查 RED + Phase 2 入口锁是 D145 Phase 2+ 启动的 hard prereq(D135-D144 范式继承)
— H10 cross-D 反思继承(`feedback_h10_cross_d_verify.md` D143 教训 + D144 PASS 实证)— 不能仅 grep `evalObjLiteral` 字面 handler,必须 outer call site `genVal(argId)` 通用 pre-eval 才是反推时序关键
— `feedback_no_option_menu.md` 红线:Phase 1 决策 A/B/C(节点 slot 占用)实测 grep + Phase 2 实施成本后**直接定案**,不列选项菜单等用户审

§D135/D136/D137/D140/D141/D142/D143/D144 Phase 1 commit 同形参考:
— D141 Phase 1 commit(待查)
— D142 Phase 1 commit `eb26644`
— D143 Phase 1 commit `f089738`
— D144 Phase 1 commit `17a1573`(7 形态 spike + IR RED + funcParamTypes 时序 H1 + eval pre-eval H10 cross-D 反思 + 节点 slot + 8 dispatch site 全 grep + Phase 2 入口全锁 — D145 直接同模式继承)
— D145 Phase 1 commit `<下轮 commit>`(本轮 next_prompt 指向)
