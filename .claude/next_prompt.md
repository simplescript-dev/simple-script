ultrathink D137 已完结(commit `8e1c5de` Phase 4 收关 + 全 5 Phase 闭环 — Phase 0 `bafc25a` + Phase 1 `d2df1ba` + Phase 2 `4c28bc0` + Phase 3 `4a10e48` + Phase 4 `8e1c5de`)。**下一路径请用户对话指示,Claude 不预设候选挑选** — 严格走 CLAUDE.md §交互式单文档 axiom + memory `feedback_interactive_one_doc.md`(每轮由用户指定一个文档,逐个问题交互式处理,不自动批量推进)。

**D137 兑现成果**(单一判据已 GREEN,见 D137 §全 Phase 收关锚 line 487+):
- OWASP top 10 #3 SQL 注入根因解决 100% 传递业务层 ✓(Spring 层接管 + JpaRepository 11 处 callback retcon)
- D136 ROI 拉满 ✓(driver 层 binary protocol 加速传递业务路径)
- Spring JdbcTemplate API 主线对齐 ✓(callback 风格 + 既有 5 method 签名零破坏)
- 三轨 RED 终态 GREEN ✓(VALUES literal=0 + WHERE id literal=0 + tests prepareStatement=8 + jdbc.ss prepareStatement=3)
- axiom 红线 grep / nm = 0 永久 ✓(D134/D135/D136 全继承)
- d_doc_index_linter F1 死指针 = 0 ✓
- reflection_health_linter GATE PASS no regressions ✓
- bootstrap 隔离 ✓(全 5 Phase 仅改 lib/ + tests/ + docs/)

**D137 §Followup 候选**(优先级建议供参考,仍由用户对话锁定 — Claude 禁自主挑):

| # | 锚 | 类型 | 触发条件 | 根因解决度 / 第一性需求覆盖度 |
|---|---|---|---|---|
| F9 | **SS 编译器 lambda 参数类型推断 + interface dispatch 集成 bug** | bootstrap 改 / 升根路径 | Phase 2 实证发现,workaround 已落 10 处显式 `(s: PreparedStatement)` 注解;修 = 在 lambda 表达式作 fn 实参时,从 fn 接收方方法 body 内 setter(stmt) 调用上下文反推 lambda 参数类型 = 实际传入参数静态类型(MysqlPreparedStatement 实现的 PreparedStatement 接口),从而 lambda body 内 `s.setInt(...)` method dispatch 通过 vtable 正确分派 | ★★★ 编译器 bug 直接修(`feedback_root_cause_no_cost.md` "编译器限制是 bug 不是边界条件")+ 全项目 lambda 类型推断收益 |
| F4 | **D136 §F1 D138 编号冲突修正(D 治理)** | docs 治理 / 编号 retcon | D136 §R4(line 362)+ §F1(line 386)双指 D138,本 Phase 4 已加注释指出,D 治理需选定真 D138 归属(候选:R4 cache miss handle 优先 / F1 cross-module struct GEP)+ 另一引用 retcon 新编号(如 D141+);跑 d_doc_index_linter F1 = 0 验证 + bootstrap 不动 | ★★ 文档治理质量(已注释指出冲突,正式修复需 D 文档治理轮)|
| F1 | NamedParameterJdbcTemplate `:name` 命名参数 | 新 sub-D | 业务层可读性提升;依赖 SS Map<string, value> 参数源(类似 SqlParameterSource F3) | ★★ 可读性增强 |
| F7 | batchUpdate / addBatch / executeBatch | 新 sub-D | 批量执行 API,依赖 prepared statement cache(D138 cache miss handle 取 §R4 候选 — 与 F4 编号冲突修复路径耦合)| ★★ 性能 + 批处理路径 |
| F2 | RowMapper 泛型 callback | 新 sub-D | **强依赖 SS 泛型(D026/D027)落地** — D026/D027 未实施前不能本轮做 | ★ 依赖未就位 |

**指示格式建议**(用户回话):
- "F9" → 开 sub-D Plan: 修 SS 编译器 lambda 参数类型推断 + interface dispatch 集成(bootstrap 改,大档位)
- "F4" → 开 D 治理轮: 选定真 D138 归属 + 另一引用 retcon 新编号
- "F1" / "F7" → 开新 sub-D Plan(F1 不依赖 SS 泛型,F7 依赖 F4 D138 编号修复后的 cache 锚)
- "其他" → 用户提具体路径(可能是无关 D 文档或新探索方向)

**收尾闸门**(本轮 next_prompt 自身合规):
- next_prompt_ultrathink_linter PASS — `ultrathink` 关键字命中(本文第 1 行)
- 交互式单文档持守 — 不预设挑选,等用户对话指示

ultrathink
