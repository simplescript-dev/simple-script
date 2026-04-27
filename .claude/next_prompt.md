ultrathink D137 Phase 4 实施 — e2e 闭环收关 + D136 §F1 D138 编号冲突注释 + D137 全 Phase 收关锚 + Status 终态。前置:Phase 3 已落地 commit `4a10e48`(tests/d134_mysql/integration_test.ss 11 处含动态值 SQL retcon 走 prepared+setter — test 2 CRUD 5 处 prepareStatement 直驱 + test 3/4 transaction commit/rollback 各 1 INSERT prepared 三 setter + test 7 JdbcTemplate 4 处走 Phase 1 callback 重载 + sel1/sel2 → selRow/selAge 语义命名 simplify 采纳 + Statement import 清理);Phase 0 commit `bafc25a` / Phase 1 commit `d2df1ba` / Phase 2 commit `4c28bc0` / Phase 3 commit `4a10e48` 已全部落锁。

**RED 凭据**(本轮已跑过):
- `bin/ss run tools/d_doc_index_linter.ss` 当前 F1 = 0 GATE OK(无死指针,9 referenced Ds all live)— Phase 4 维持
- D136 §F1 当前缺 D138 编号冲突注释(D136 §R4 line 362 写 "留 D138 sub-follow-up handle" cache miss + D136 §F1 line 386 写 "sub-D D138 cross-module struct GEP",D138 编号双指)— Phase 4 落实注释
- D137 §全 Phase 收关锚(line 473)当前为 "(待全 Phase 落地后回填,参 D135 line 487 范式)" — Phase 4 替换为终态总结
- 三轨 RED 已 Phase 3 GREEN(grep VALUES + WHERE id literal = 0 / prepareStatement 接管 = 8 / setter 注入 = 26)— Phase 4 维持

**改动清单**(D137 §Phase 4 §改动清单 + §核心原则 7-9):

1. **D136 §F1 D138 编号冲突注释**(D136-mysql-prepared-statement.md §F1 处加注释段):指出 D136 §R4 + §F1 双处引用 "D138" 但语义不同(§R4 = prepared statement cache miss handle / §F1 = cross-module struct GEP),D 治理后续轮处理(可能 D138 = cache miss / D140 = cross-module GEP),Phase 4 仅注释**不动编号**(承 D137 §F4 follow-up 锚)
2. **D137 §Status 加 Phase 4 reference**(D137 line 3):`+ [✓] Phase 4 收关 at commit <phase4-commit>` 拼接(本 commit hash 自指,docs commit message 含 hash,提交后 hash 回填留 sub-followup 由 git log 索引,避免 chicken-and-egg;Phase 0/1/2/3 同此模式 hash 提交后回填)
3. **D137 §Phase 4 收关锚**(D137 line 467 替换 [ ] Pending):落细 — D136 §F1 注释 commit + d_doc_index_linter F1 = 0 GATE OK + 三轨 RED 终态 GREEN(Phase 3 已实证)+ axiom 红线 grep 0 永久 + reflection baseline 维持 + tests/ 259/4/263 baseline 不降 + d134_mysql/d135/d136 全绿 baseline
4. **D137 §全 Phase 收关锚**(line 473):替换占位为终态总结 — 4 Phase commit hash 全列 + JdbcTemplate 5 method callback 重载落地 + JpaRepository 11 处 callback retcon 落地 + tests/d134_mysql 11 处含动态值 SQL retcon 落地 + Spring 层 SQL 注入根因解决 100% 传递业务层 + D136 ROI 拉满 + §F9 sub-D follow-up 锚明确(SS 编译器 lambda 参数类型推断 + interface dispatch 集成 bug)+ §F1-F8 follow-up 锚明确(NamedParameterJdbcTemplate / RowMapper / SqlParameterSource / D138 编号 / batchUpdate / generated keys / HikariCP D125+)

**GREEN 标准**(D137 §Phase 4 §GREEN):

- `bin/ss run tools/d_doc_index_linter.ss` F1 = 0(D137 + D136 引用维持一致 + D138 编号冲突仅注释不动编号,F1 死指针 = 0)
- `bin/ss run tools/reflection_health_linter.ss` baseline 不升(本 Phase 不触代码,仅文档)
- D137 §Status 行包含 4 Phase commit hash(0/1/2/3/4 五 phase 状态条)
- D137 §全 Phase 收关锚替换占位,不再为 "(待全 Phase 落地后回填)"
- D136 §F1 含 D138 编号冲突注释段(grep `D138.*编号` 命中)
- 三轨 RED 维持 Phase 3 GREEN 状态(grep VALUES + WHERE id literal = 0 维持)
- axiom 红线 grep / nm = 0 永久维持(D134 + D135 + D136 全继承)

严格按 D137 §核心原则 1-11 + docs/3-MNK.md §M PSM 九问 + §N VCM 六验执行:
- §核心原则 7 tests/d135_caching_sha2/ + tests/d136_prepared_statement/ 不动(Phase 4 仅文档)
- §核心原则 8 Phase 边界 = commit 边界(Phase 4 单 commit 收 — docs(D137) Phase 4 收关 + 全 Phase 终态 + D136 §F1 注释)
- §核心原则 9 bootstrap 隔离(Phase 4 仅 docs/3-decisions/ 改,不动 bootstrap / lib / tests)
- D 文档治理 gate(F1 死指针 = 0,新增 D136 §F1 注释段 grep `D138.*冲突|D138.*编号` 命中 sanity check)

**§After Done 三步必走**(收尾 gate):
1. /simplify N/A 文档型(承 Phase 0 §After Done 范式 — D137 line 426 simplify N/A)
2. commit(单 commit 范式 — Phase 4 终态收关型 — `docs(D137): Phase 4 收关 — D136 §F1 D138 编号冲突注释 + D137 §Status Phase 0+1+2+3+4 全 hash + §全 Phase 收关锚替换占位为终态 + §F9 sub-D follow-up 锚 + §F1-F8 follow-up 锚 — D135/D136/D140 范式延续`)
3. 写下轮 next_prompt 指向 D137 完结后的下一 D 文档(交互式单文档 axiom — 由用户对话指示下一路径,候选含:§F9 SS 编译器 lambda 参数类型推断 + interface dispatch 集成 bug 修编译器 / §F4 D138 编号冲突修正 D 治理 / §F1 NamedParameterJdbcTemplate / §F2 RowMapper 泛型(依赖 D026/D027)/ §F7 batchUpdate;**禁** Claude 自主挑路径 — 等用户对话指示)且必含 ultrathink 关键字 + 跑 `bin/ss run tools/next_prompt_ultrathink_linter.ss` GATE PASS
