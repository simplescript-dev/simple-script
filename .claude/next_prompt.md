ultrathink D138 SQL 主线已 close — Phase 5 全 Phase 收关 commit `<Phase 5 commit>`(2026-04-28)。**等用户指定下一方向**,本轮不自主推进新 sub-D。

§D138 close 锚(`docs/3-decisions/D138-mysql-generated-keys.md`):
- §Phase 收关锚 §Phase 5 mark Done — line 367(2026-04-28)
- 全 6 Phase commit hash:Phase 0 d47a05d / Phase 1 182b3fb / Phase 1.5 8793be0 / Phase 2 1ee1173 / Phase 3 8f8abb7 / Phase 4 fe45bdc / Phase 5 `<Phase 5 commit>`
- 兑现:JDBC 4.3 §Statement.getGeneratedKeys / getLastInsertId + 常量 RETURN_GENERATED_KEYS / NO_GENERATED_KEYS + §Connection.prepareStatement(sql, akg) 重载 + Spring KeyHolder 4 method + GeneratedKeyHolder impl + JdbcTemplate.update(sql, setter, keyHolder) 第 6 method 重载 + MySQL OkPacket 完整 4 字段 + GeneratedKeyResultSet 单行单列 + MysqlStatement / MysqlPreparedStatement lastInsertId + 编译器扩 4 处(Phase 1.5 interface method overload by arity / Phase 2 inferType arity-aware mangle / Phase 3 class method overload by interface erasure / Phase 3 genFuncDecl arrow flush bug fix)+ 测试覆盖 6 形态 GREEN

§下一方向候选(D138 §Followup 全 7 锚明确,等用户指定):

**SQL 主线 sub-D**(D135/D136/D137/D138 范式延续 — 每 Phase 独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环):
- F2 → D139+ **SQLException 完整生态**(SQLState + ErrorCode + getMessage,JDBC §SQLException spec — 当前 ERR packet 路径返 -1 / println 简化)
- F3 → D140+ **server-side cursor + scrollable ResultSet**(MySQL `useCursorFetch=true` + ResultSet TYPE_SCROLL_INSENSITIVE / TYPE_SCROLL_SENSITIVE,大表分页场景必需)
- F4 → NamedParameterJdbcTemplate `:name` 参数 + KeyHolder 整合(D137 §F1 + D138 Phase 3 KeyHolder 入口合并)
- F5 → RowMapper<T> 泛型 callback(**强依赖 SS 泛型 D026/D027** — 非 JDBC SQL 主线直推,看 SS 泛型路径状态)
- F6 → HikariCP Connection Pool(D137 §F6 — 连接池 lifecycle + acquire/release + max pool size + idle eviction + healthcheck)
- F7 → batchUpdate / addBatch / executeBatch + KeyHolder 整合(D137 §F7 + D138 Phase 3 KeyHolder 入口合并)
- F1 → OK packet `info string` 字段(SESSION_TRACK 路径 — MySQL 5.7+,本身较 niche,可合并入其他 sub-D)

**其他方向**(用户对话锁后启动):
- SS 泛型路径 D026/D027(若 F5 RowMapper<T> 优先级提升 — JDBC 主线必经之路)
- 反射 baseline 压回(D097 §reflection root cause metrics + `tools/reflection_health_linter.ss` F1 PROGRESS — D138 Phase 3 后 `gen_methods.ss=711` / `gen_decls.ss=726` / `gen_iface.ss=249` 残留 cur 低于 bv,可压回 baseline)
- D 文档治理(d_doc_index linter SOFT WARN 18 orphan — 业务 / Plan D 文档无 §-form 源码引用,不是 bug,治理可考虑)
- 编译器主线优化(其他 SQL 无关 path)

§本轮 Phase 5 commit hash 待 placeholder 回填:
- `docs/3-decisions/D138-mysql-generated-keys.md` 4 处 `<Phase 5 commit>` placeholder(line 3 Status / line 367 §Phase 收关锚 §Phase 5 / Phase 5 章节内全 Phase commit hash 总览 / Status 时间线 Phase 5 行)— 留下一 D 文档 Phase 0 commit 时回填,或下轮用户指定方向后 Phase 0 commit hash 出来时人工补

§根因优先(CLAUDE.md §项目技术规则):
- D138 主线 close,Followup F1-F7 全 file:line 锚定,下轮直接读 D138 §Followup table
- D135/D136/D137/D138 SQL 主线范式延续 — 每 Phase 独立 commit + Status 收关 + commit hash 回填 + next_prompt 自闭环

§硬约束(本轮不动):
- 不自主挑下一 sub-D — 用户对话锁(CLAUDE.md §交互式单文档:每轮等用户明确指定一个文档/方向)
- 不顺带跑 simplify / 反射压回等其他动作 — 等用户指定

**等用户指定下一方向 — D138 主线已 close,本轮不自主推进。**
