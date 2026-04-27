ultrathink D141 Phase 3 完结 commit `40aa152`(测试覆盖 + 隐藏假设挑战 5 测试用例 + Phase 2 兑现漏点根因修 4 处)+ Status 收关 + 11 file 改 +187/-31 LOC + bootstrap 三阶段固定点 stage2==stage3 + tests/ 264/4/268 baseline 不降(259+5/4/263+5)+ tests/d141_lambda_inference/ 5/0/5 全绿(untyped_single + untyped_multi + explicit_override + interface_dispatch + non_structured_callee)+ d136_prepared_statement 1/0/1 不破 + reflection_health_linter GATE PASS(扩容申报 D141#扩容申报-Phase3 — gen_calls.ss 699→718 / gen_types.ss 847→873)+ d_doc_index_linter F1=0;关键发现 Phase 2 兑现漏点 4 处只在 Phase 3 测试 end-to-end 暴露(顶层 fn callee + non-overloaded class method + non-void retType 三边界 Phase 2 method call overloaded callee skip 类型检查走 GREEN 未触发)— 按 §Root Cause 优先 第一法则当轮根因修不延期(`feedback_root_cause_no_cost.md`),根因修 4 处合并入 Phase 3 commit:isTypeCompatible fn 双向兼容(`bootstrap/checker/check_types.ss` ~5 行)+ indirect call retType 反推从 `getVarType(callee)` 取 `fn(T):R` 提取 R 而非硬编码 i64 + closure/direct/phi merge 三段适配 void/non-void 双路径(`bootstrap/gen/gen_calls.ss:512-565` ~19 行)+ CALL inferType for fn-typed callee 返结构化 R 而非 "i64"(`bootstrap/gen/gen_types.ss:354` ~8 行)+ ARROW_FUNC retT 同步反推 inferArrowFuncParams 末尾从 callee `fn(...):R` 提取 R 回填(`bootstrap/gen/gen_types.ss` ~8 行)+ extractFnRetType helper(`bootstrap/gen/gen_types.ss` ~8 行)。

Phase 4 起首 — workaround cleanup(D137 §F9 既有 11 处显式注解全删):

(a) RED 凭据 — `grep -rn ": PreparedStatement) =>" lib/spring/ tests/d134_mysql/ 2>&1 | wc -l` = 11(`lib/spring/data.ss` 5 处 `(stmt: PreparedStatement) =>` + `tests/d134_mysql/integration_test.ss` 6 处 `(s: PreparedStatement) =>` 显式注解 D137 Phase 2-3 落锚 workaround,D141 反推机制实施后应可全删走 untyped lambda 反推路径)。

(b) Phase 4 实施步骤(单 commit 大改档,D135/D136/D137/D140 范式延续):
  - **lib/spring/data.ss 5 处 cleanup**(line 47/54/61/68/80):删 `(stmt: PreparedStatement)` 形参注解保留 lambda body 不变,改 `(stmt: PreparedStatement) => { stmt.setInt(1, id) }` → `(stmt) => { stmt.setInt(1, id) }`(callee `setter: fn(PreparedStatement):void` 已 Phase 2.3 升级结构化签名,反推机制回填 PARAM s2 = "PreparedStatement" 走 vtable indirect dispatch GREEN)
  - **tests/d134_mysql/integration_test.ss 6 处 cleanup**(line 169/175/177/179/190/195):同模式删 `(s: PreparedStatement)` → `(s)`,callee `tmpl.update / tmpl.queryForString / tmpl.queryForInt / repo.save` 反推路径自然走通(注 D141 §H6 显式优先级 > 推断 验证已 PASS 在 Phase 3 explicit_override.ss,Phase 4 删注解后仍 GREEN 因为 lambda body method dispatch 走 setVarType + vtable 链路 H10 不变,只是 PARAM s2 来源从用户显式 → 反推回填)
  - **bootstrap 不动**(D141 主线已落 Phase 3 commit `40aa152`,Phase 4 仅 lib/tests cleanup 删用户态 workaround 注解)
  - **simplify 检查 cleanup 后 lib/spring/data.ss 可读性**(陌生人秒懂判据 — 删形参类型注解后 setter callback 仍单 expr lambda body,符合 `feedback_human_readable_code.md` a-e 5 rubric;callee 类型签名已结构化 `fn(PreparedStatement):void` 代替 `fn` 单字符串,信息源单点足够 IDE 类型推断)

(c) GREEN 凭据 — 三轨 RED 全 GREEN:
  - `grep -c "(s: PreparedStatement)" lib/spring/data.ss tests/d134_mysql/integration_test.ss` = 0(workaround 全删,注:`(stmt: PreparedStatement)` lib/data.ss 5 处也属同类 grep `: PreparedStatement) =>` ≥ 11)
  - `grep -c "(s) =>" lib/spring/data.ss tests/d134_mysql/integration_test.ss` ≥ 6(untyped lambda 接管 tests/d134_mysql 6 处)+ `grep -c "(stmt) =>" lib/spring/data.ss` ≥ 5(untyped lambda 接管 lib/data.ss 5 处)
  - `bin/ss test tests/d136_prepared_statement` 1/0/1 全绿(d136 driver 路径不破)+ d134_mysql 测试需 docker compose 启动验(可选 docker 不可用 skip — `bin/ss test tests/d134_mysql/` 需 docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait;若 docker 不可用,d134_mysql 测试自动 probe skip 仍 GREEN)
  - bootstrap 三阶段固定点 stage2==stage3 + tests/ 264/4/268 baseline 不降(Phase 4 cleanup 不增不减测试,基数不变)
  - `bin/ss run tools/reflection_health_linter.ss` GATE PASS(Phase 4 不动 bootstrap,F1 不变;lib/tests/ 不计 reflection scope)
  - `bin/ss run tools/d_doc_index_linter.ss` PASS:F1=0 不破

(d) D141 文档收尾 — §Phase 4 [✓ 完结] commit `<hash>` + 兑现成果(11 处 workaround 全删 + d136_prepared_statement / d134_mysql probe skip 不破 + tests/ baseline 不降)+ §Status 时间线增 Phase 4 行 + next_prompt 指向 Phase 5 全 Phase 收关(§全 Phase 收关锚 4 Phase commit hash 全列 + 兑现成果总结 C2 接口层 trap + workaround 11 处全删 + 隐藏假设 H1-H8 全 PASS + bootstrap 隔离破例 D137 §核心原则 9 接受 + axiom 红线 grep / nm = 0 永久 + d_doc_index_linter F1=0 永久 + reflection_health_linter GATE PASS + §Followup 锚明确 — F1 array literal contextual typing / F2 object literal contextual typing 等);D 文档治理:Phase 4 改 D141 §Phase 4 + §Status 段 不删/合并/重命名 D 文档,d_doc_index_linter F1=0 不破。

— D135/D136/D137/D140 范式延续(Phase 计划独立 commit 大改档 + Status 收关 + commit hash 回填 + next_prompt 指向下一 Phase 入口)。
