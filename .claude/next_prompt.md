ultrathink D138 Phase 3 实施(Spring KeyHolder 完整 — `lib/spring/jdbc.ss` 加 `interface KeyHolder` + `class GeneratedKeyHolder : KeyHolder` + `JdbcTemplate.update(sql, setter, keyHolder)` 重载)+ 本轮(Phase 2 lib + 编译器 inferType arity-aware fix)commit hash 回填 + Status 行收关 + next_prompt 指向 Phase 4(测试覆盖 6 形态)— D135/D136/D137/D138 SQL 主线范式延续(不是 D141-D145 docs-heavy 衍生链)。

**用户对话锁(2026-04-28)**:
- SQL 主线 — D138 是 D137 §F8 generated keys 直接续接
- **最优最佳,不考虑成本,不 workaround,不节省** — 完整 JDBC 4.3 + Spring KeyHolder 标准
- Phase 2 lib + 编译器扩延展已落地(commit `<本轮回填>`)— 完整 JDBC 4.3 spec 打通(Statement/PreparedStatement.getGeneratedKeys/getLastInsertId + Connection.prepareStatement(sql, akg) 重载 + RETURN_GENERATED_KEYS / NO_GENERATED_KEYS 常量 + MySQL OkPacket helper + inferType arity-aware mangle fix)
- Phase 3 节奏:本轮(Phase 3 Spring KeyHolder + Phase 2 hash 回填同 commit)+ 下轮(Phase 4 测试覆盖 6 形态)+ Phase 5 全 Phase 收关

§前置就绪(D138 Phase 2 commit `<本轮回填>` 已锁):
— D138 Phase 1.5 hash `8793be0` 已落档(3 处 placeholder)+ Phase 2 实施完成(lib/java/sql.ss interface 扩 + lib/com/mysql/jdbc.ss + prepared.ss + query.ss helper + bootstrap/gen/gen_types.ss inferType arity-aware fix);D138 §Phase 收关锚 §Phase 2 mark `[✓] Done at commit \`<Phase 2 commit>\``(留 placeholder)+ Status 时间线本轮新行落档(留 placeholder)
— spike /tmp/test_d138_phase2.ss GREEN(`rows=1` + `id=1` + `gen_key=1`)证明 JDBC 4.3 完整 spec 路径(prepareStatement(sql, RETURN_GENERATED_KEYS) + setString + executeUpdate + getLastInsertId + getGeneratedKeys + ResultSet.next() + getInt("GENERATED_KEY") + close)全打通,可承载 Phase 3 Spring KeyHolder 重载的下游消费
— d_doc_index F1=0 PASS + reflection_health GATE PASS no regressions(F1 gen_types.ss cur=1050 边界 DRIFT)+ 全 tests/ 284/4 pre-existing baseline 不破

§关键 SSoT(信息源,本轮已实测确认):
— `lib/java/sql.ss:31-44` const RETURN_GENERATED_KEYS=1 / NO_GENERATED_KEYS=2(Phase 2 已加)
— `lib/java/sql.ss:46-58` interface Statement(executeQuery / executeUpdate / execute / getGeneratedKeys / getLastInsertId / close — Phase 2 已扩)
— `lib/java/sql.ss:62-74` interface PreparedStatement(setXxx + executeQuery / executeUpdate / getGeneratedKeys / getLastInsertId / close — Phase 2 已扩)
— `lib/java/sql.ss:84-95` interface Connection(createStatement / prepareStatement(sql) / prepareStatement(sql, akg) / setAutoCommit / commit / rollback / close / isClosed — Phase 2 已扩;Phase 1.5 编译器扩支持 arity-aware mangle)
— `lib/com/mysql/jdbc.ss:97-141` MysqlStatement / MysqlConnection 完整实现(Phase 2 已落)
— `lib/com/mysql/prepared.ss:486-590` MysqlPreparedStatement 完整实现(Phase 2 已落)
— `lib/com/mysql/query.ss:139-152` okPacketAffectedRows / okPacketLastInsertId helper(Phase 2 已加)+ `query.ss:329-365` GeneratedKeyResultSet(Phase 1 已落)
— `lib/spring/jdbc.ss` 当前文件(Phase 3 入口)— 检查 JdbcTemplate.update 5 method 重载(`update(sql)` / `update(sql, setter)` 等)实存,Phase 3 加第 6 method 重载 `update(sql, setter, keyHolder: KeyHolder): int`

§任务清单(D138 Phase 2 commit hash 回填 + Phase 3 实施):

(1) **本轮 commit hash 回填**:
  - `git log --oneline | head -3` 找最新 D138 Phase 2 commit hash → Edit `docs/3-decisions/D138-mysql-generated-keys.md` 2 处 `<Phase 2 commit>` placeholder(line ~327 §Phase 收关锚 §Phase 2 / line ~356 Status 时间线本轮新行)→ 替换为实际 hash

(2) **Phase 3 实施 — Spring KeyHolder 完整**:

  **3a. 扩 `lib/spring/jdbc.ss`**:
  - 加 `interface KeyHolder { getKey(): int; getKeyAsLong(): int; getKeys(): Map<string,int>; getKeyList(): Array<Map<string,int>> }` 完整 4 method(D138 §核心原则 2 — Spring 标准 4 method 全实现 + multi-row + multi-column 扩展位)
  - 加 `class GeneratedKeyHolder : KeyHolder` impl:`keyList: Array<Map<string,int>>` 字段(为 multi-row + multi-column generated keys 留扩展位,SS 当前限 int 类型);构造期默认 keyList 空 Array;`addKey(key: int)` 内部 method 由 JdbcTemplate.update 后填充 keyList(单 row 单 column GENERATED_KEY 路径);`getKey(): int` 返 keyList[0].getString("GENERATED_KEY") 解析 int(单 row 单 column 标准路径);`getKeyAsLong(): int` 同 getKey(SS int 是 i64);`getKeys(): Map<string,int>` 返 keyList[0](单 row 多 column 路径);`getKeyList(): Array<Map<string,int>>` 返完整 keyList(multi-row 路径)
  - 加 `JdbcTemplate.update(sql: string, setter: fn(PreparedStatement):void, keyHolder: KeyHolder): int` 重载(per-call Connection 同 D137 — `prepareStatement(sql, RETURN_GENERATED_KEYS)` → setter → executeUpdate → getGeneratedKeys → fill keyHolder.keyList → close;依赖 Phase 1.5 编译器扩 + Phase 2 lib 完整 spec)
  - 不动 D137 既有 5 method 重载本体(向后兼容,加重载不改既有)/ 不动 D025 dispatch 契约本体 / 不动 D133/D134 driver dispatch 路径 / 不动 D138 Phase 1/2 lib 已落

  **3b. SS 限制可能触发的边界 case**:
  - **vtable indirect dispatch 检查**:`KeyHolder.getKeyList()` 返 `Array<Map<string,int>>` 嵌套泛型 — D138 §A.2 H6 风险锚("SS Array<Map<K,V>> 嵌套泛型当前 D025 vtable 是否完整")— Phase 3 实测 spike `keyHolder.getKeyList()[0].getString("GENERATED_KEY")` 路径,若 dispatch 错位 → simplify 简化 keyList → keys: Map<string,int> 单 row 限制(Phase 3 §A.2 H6 失败回路)
  - **JdbcTemplate.update 既有 5 method 重载与新加重载 paramSig 是否冲突**:已存 `update(sql)` arity 1 / `update(sql, setter)` arity 2 / 等;新加 `update(sql, setter, keyHolder)` arity 3 — Phase 1.5 编译器扩支持 arity-aware mangle,arity 3 与 arity 1/2 不冲突,paramSig 自动分流(class method 同公约)

  **3c. 不动**:Phase 1 query.ss 路径 / Phase 2 lib 已落(jdbc.ss + prepared.ss + sql.ss + query.ss helper)/ Phase 4 测试覆盖 6 形态(留下轮)

  **VCM 六验**:
  - bootstrap 三阶段固定点 PASS(stage2 == stage3 — Phase 3 lib 层改触发 build cache 但 bootstrap 编译器本体不变;若 Phase 3 触碰编译器 fix 需独立 simplify 削回 F1 budget)
  - tests/d134_mysql 5/0/5 + d135_caching_sha2 1/0/1 + d136_prepared_statement 1/0/1 baseline 不破(Phase 3 lib 层不动既有)
  - tests/d141-d144 反推 baseline 不破(5/6/6/8 全绿)
  - 全 tests/ baseline 不降(284/4 fail 全 pre-existing — git stash 反证 Phase 3 改前后同 baseline)
  - reflection_health GATE PASS no regressions
  - d_doc_index GATE OK
  - 行为验证:spike `JdbcTemplate.update("INSERT INTO ...", setter, keyHolder)` + `keyHolder.getKey()` 路径 GREEN(docker MySQL 探活若失败 → tests/d138 沿 d134/d136 模式 `probe.isClosed() == 1` 时 println + return 0)

(3) **commit `feat(D138): Phase 3 — Spring KeyHolder 完整 + 本轮 docs commit hash 回填 <本轮 commit> — lib/spring/jdbc.ss 加 interface KeyHolder(getKey/getKeyAsLong/getKeys/getKeyList 4 method)+ class GeneratedKeyHolder : KeyHolder impl(keyList: Array<Map<string,int>> 字段为 multi-row + multi-column 扩展位)+ JdbcTemplate.update(sql, setter, keyHolder) 重载(per-call Connection 同 D137 — prepareStatement(sql, RETURN_GENERATED_KEYS) → setter → executeUpdate → getGeneratedKeys → fill keyHolder.keyList → close)— D138 §核心目标 Spring KeyHolder 标准 ORM/Repository 层 save(entity).id 回填路径 — D135/D136/D137/D138 SQL 主线范式延续`**
  - 仅 stage `lib/spring/jdbc.ss` + `docs/3-decisions/D138-*.md` + `.claude/next_prompt.md`

(4) **next_prompt 指向 Phase 4**:测试覆盖 — 6 形态完整 — `tests/d138_generated_keys/integration_test.ss`(6 case:单行直取 stmt.getLastInsertId / ResultSet 走 spec stmt.getGeneratedKeys.next.getInt / Spring KeyHolder JdbcTemplate.update + keyHolder.getKey / multi-row VALUES 首 id / transaction COMMIT 后持久 / ERR packet INSERT 失败防御 0)+ docker MySQL 探活 fallback skip + 隐藏假设 H1-H8 PASS

§根因优先(CLAUDE.md §项目技术规则):
— Phase 3 lib 层完整 Spring KeyHolder 标准落地 = 根因解(消除 D138 §核心目标"业务 INSERT 后无法 ORM/Repository 层 save(entity).id 回填走 KeyHolder 标准")
— 复用 Phase 2 已落的 prepareStatement(sql, akg) 重载 + getGeneratedKeys / getLastInsertId — 单一信息源出口(D138 §核心原则 4)+ Phase 1 GeneratedKeyResultSet 已落
— D135/D136/D137/D138 SQL 主线范式 — 每 Phase 独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环

§D135/D136/D137/D138 Phase 3 同形参考:
— D135 Phase 0 + Phase 1 同 commit 模式
— D136 Phase 0 commit `9326b9f` + Phase 1 commit `c854778` 同模式
— D137 Phase 0 commit `bafc25a` + Phase 1 commit `d2df1ba` 同模式
— D138 Phase 0 commit `d47a05d` + Phase 1 commit `182b3fb` + Phase 1.5 计划落档 commit `c90df15` + Phase 1.5 实施 commit `8793be0` + Phase 2 commit `<本轮回填>` + Phase 3 commit(下轮 Spring KeyHolder)+ Phase 4 commit(下下轮 测试覆盖 6 形态)同模式
