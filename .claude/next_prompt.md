ultrathink D138 Phase 4 实施(测试覆盖 — 6 形态完整 — `tests/d138_generated_keys/integration_test.ss`)+ 本轮(Phase 3 Spring KeyHolder + 编译器扩接口擦除 + arrow flush fix)commit hash 回填 + Status 行收关 + next_prompt 指向 Phase 5(全 Phase 收关)— D135/D136/D137/D138 SQL 主线范式延续(不是 D141-D145 docs-heavy 衍生链)。

**用户对话锁(2026-04-28)**:
- SQL 主线 — D138 是 D137 §F8 generated keys 直接续接
- **最优最佳,不考虑成本,不 workaround,不节省** — 完整 JDBC 4.3 + Spring KeyHolder 标准
- Phase 3 Spring KeyHolder + 编译器扩接口擦除 + arrow flush fix 已落地(commit `<本轮回填>`)— Spring KeyHolder 全路径打通(getKey / getKeyAsLong / getKeys / getKeyList 4 method 全实现 + JdbcTemplate.update(sql, setter, keyHolder) 第 6 method 重载 + 编译器扩 pickClassMethodKey 接口擦除 + genFuncDecl arrow flush bug fix)
- Phase 4 节奏:本轮(Phase 4 测试覆盖 6 形态 + Phase 3 hash 回填同 commit)+ 下轮(Phase 5 全 Phase 收关)

§前置就绪(D138 Phase 3 commit `<本轮回填>` 已锁):
— D138 Phase 2 hash `1ee1173` 已落档(3 处 placeholder 含 line 3 Status / line 327 §Phase 收关锚 / line 369 Status 时间线)+ Phase 3 实施完成(lib/spring/jdbc.ss interface KeyHolder + class GeneratedKeyHolder + JdbcTemplate.update 第 6 method 重载;bootstrap/gen/gen_iface.ss + gen_methods.ss + gen_decls.ss 编译器扩);D138 §Phase 收关锚 §Phase 3 mark `[✓] Done at commit \`<Phase 3 commit>\``(留 placeholder)+ Status 时间线本轮新行落档(留 placeholder)
— spike `/tmp/test_d138_phase3.ss` GREEN(`rows=1` + `key=1` + `keyAsLong=1` + `listLen=1` + `keysSize=1` + `keysGen=1`)证明 Spring KeyHolder 完整 spec 路径(JdbcTemplate.update(sql, arrow setter, keyHolder) + keyHolder.getKey/getKeyAsLong/getKeys/getKeyList 全打通,arrow lambda + method call 路径同步打通)
— d_doc_index F1=0 PASS + reflection_health GATE PASS no regressions(F1 gen_decls.ss cur=726 bm=730 PROGRESS / gen_methods.ss cur=711 bm=730 PROGRESS / gen_iface.ss 247 行 远低于 600 上限)+ 全 tests/ 284/4 pre-existing baseline 不破

§关键 SSoT(信息源,本轮已实测确认):
— `lib/spring/jdbc.ss:18-49` interface KeyHolder + class GeneratedKeyHolder(Phase 3 已加 — 4 method:getKey/getKeyAsLong/getKeys/getKeyList + keyList: Array<Map<string,int>> 字段)
— `lib/spring/jdbc.ss:101-120` JdbcTemplate.update(sql, setter, keyHolder: KeyHolder) 第 6 method 重载(per-call Connection — Phase 3 已加)
— `lib/com/mysql/query.ss:329-365` GeneratedKeyResultSet(Phase 1 已落 — 单行单列 GENERATED_KEY)
— `lib/com/mysql/jdbc.ss:99-130` MysqlStatement.getGeneratedKeys / getLastInsertId(Phase 2 已落)
— `lib/com/mysql/prepared.ss:559-569` MysqlPreparedStatement.getGeneratedKeys / getLastInsertId(Phase 2 已落)
— `lib/java/sql.ss:31-44` const RETURN_GENERATED_KEYS=1 / NO_GENERATED_KEYS=2(Phase 2 已加)
— `tests/d134_mysql/integration_test.ss` + `docker-compose.yml`(集成测试参考模板 — testss-mysql @ 127.0.0.1:3307,DB testdb,user root pwd test)
— `tests/d136_prepared_statement/integration_test.ss`(prepared statement 集成测试模式 — `probe.isClosed() == 1` 时 println + return 0 fallback)

§任务清单(D138 Phase 3 commit hash 回填 + Phase 4 实施):

(1) **本轮 commit hash 回填**:
  - `git log --oneline | head -3` 找最新 D138 Phase 3 commit hash → Edit `docs/3-decisions/D138-mysql-generated-keys.md` 2 处 `<Phase 3 commit>` placeholder(line 3 Status / line 342 §Phase 收关锚 §Phase 3 / line 380 Status 时间线 Phase 3)→ 替换为实际 hash

(2) **Phase 4 实施 — 测试覆盖 6 形态完整**:

  **4a. 新建 `tests/d138_generated_keys/integration_test.ss`** — 完整 6 形态 case(D138 §核心目标):
  - **Case 1**:INSERT 单行 + `stmt.getLastInsertId()` 直取 — `MysqlStatement / executeUpdate(sql) + getLastInsertId() == 1`(MySQL docker 探活 fallback skip 同 d134/d136 模式 — `probe.isClosed() == 1` 时 println + return 0)
  - **Case 2**:INSERT 单行 + `stmt.getGeneratedKeys()` ResultSet 走 spec — `executeUpdate + rs = stmt.getGeneratedKeys() + rs.next() == 1 + rs.getInt("GENERATED_KEY") == 1 + rs.next() == 0(past end)+ rs.close()`
  - **Case 3**:INSERT 单行 + `JdbcTemplate.update(sql, setter, keyHolder)` Spring 标准(arrow setter 形式)+ `keyHolder.getKey() == 1` + `keyHolder.getKeyAsLong() == 1` + `keyHolder.getKeys().get("GENERATED_KEY") == 1` + `keyHolder.getKeyList().length() == 1`
  - **Case 4**:INSERT 多行 `VALUES (?,?),(?,?)` 通过 PreparedStatement.setString 多次后 executeUpdate + `getLastInsertId() == first_id`(MySQL 协议规定首 id;后续 id 走 SELECT WHERE id >= first AND id < first + affectedRows 业务侧自计算)+ affectedRows == N
  - **Case 5**:transaction 中 INSERT + commit 后 id 持久 — `setAutoCommit(0) + INSERT + getLastInsertId == X + commit() + 后续 SELECT WHERE id = X 验证 row 存在(用 queryForString)`
  - **Case 6**:INSERT 失败(ERR packet 触发 — INSERT INTO nonexistent_table 或 PRIMARY KEY 冲突)+ `getLastInsertId() == 0 防御`(D138 §A.2 H7)

  **4b. 测试结构**:
  - 沿 d134_mysql/integration_test.ss 6 case test() 调用模式
  - clearAll() helper:每 case 前 DROP/CREATE 测试表
  - URL: `jdbc:mysql://root:test@127.0.0.1:3307/testdb`
  - probe.isClosed() == 1 时 println + return 0(docker 离线 fallback)
  - 表名 `d138_generated_keys`(避免与 d134/d136 测试碰撞)

  **4c. 隐藏假设 H1-H8 实证**:
  - H1 lenenc int offset 推进:Case 4 多行 INSERT affectedRows = 3,验证 lengthEncodedIntSize 推进 OK
  - H2 last_insert_id i64 范围:Case 1 验证常规 i64 read OK(超 i32 边界值留 docker 配置定制 sub-D)
  - H3 multi-row INSERT 首 id:Case 4 直接验证
  - H4 prepareStatement(sql, akg) MySQL no-op:Case 3 RETURN_GENERATED_KEYS 与未传 akg 等价(已 Phase 2 spike 隐含验证 — 本 Phase 4 sanity)
  - H5 GeneratedKeyResultSet vs MysqlResultSet vtable dispatch:Case 2 ResultSet.next/getInt 走 vtable 路径(Phase 1 spike 已 sanity,本 Phase 4 重新验证)
  - H6 KeyHolder.getKeyList() Array<Map<string,int>> 嵌套泛型:Case 3 全 4 method 全 GREEN — H6 风险已 Phase 3 spike 实证消除
  - H7 ERR packet getLastInsertId 防御:Case 6 直接验证返 0
  - H8 全 tests/ baseline 不降:VCM 六验

  **4d. 不动**:Phase 1-3 lib/ + bootstrap/ 既有(Phase 4 仅 tests/ 新建 + D138 docs)

  **VCM 六验**:
  - bootstrap 三阶段固定点 PASS(stage2 == stage3 — Phase 4 仅 tests/ 新建,bootstrap 编译器不变)
  - tests/d138_generated_keys 6/0/6 全绿(主判据)
  - tests/d134_mysql 5/0/5 + d135_caching_sha2 1/0/1 + d136_prepared_statement 1/0/1 baseline 不破(Phase 3 lib + bootstrap 改 docker 在线时同 baseline + 离线时 skip)
  - tests/d141-d144 反推 baseline 全绿(5/6/6/8)
  - 全 tests/ 290/4(原 284/4 + Phase 4 新加 6 case 全绿 — 4 fail 全 pre-existing 与 Phase 3 baseline 一致)
  - reflection_health GATE PASS no regressions(本 Phase 不动 bootstrap)
  - d_doc_index GATE OK
  - 行为验证:tests/d138_generated_keys/integration_test.ss `bin/ss test` 6 case 全 GREEN

(3) **commit `feat(D138): Phase 4 — 测试覆盖 6 形态完整 + 本轮 docs commit hash 回填 <本轮 commit> — tests/d138_generated_keys/integration_test.ss 6 case(单行直取 stmt.getLastInsertId / ResultSet 走 spec stmt.getGeneratedKeys.next.getInt / Spring KeyHolder JdbcTemplate.update + keyHolder 4 method / multi-row VALUES 首 id / transaction COMMIT 持久 / ERR packet INSERT 失败防御 0)+ docker MySQL 探活 fallback skip + 隐藏假设 H1-H8 PASS — D138 §核心目标 6 判据全形态主判据 PASS — D135/D136/D137/D138 SQL 主线范式延续`**
  - 仅 stage `tests/d138_generated_keys/` + `docs/3-decisions/D138-*.md` + `.claude/next_prompt.md`

(4) **next_prompt 指向 Phase 5**:全 Phase 收关 — D138 主线 close — Phase 0-5 commit hash 全列 + 兑现成果 + Followup F1-F7 锚明确 + Status 行最终收关 + 不再续 Phase

§根因优先(CLAUDE.md §项目技术规则):
— Phase 4 测试覆盖 = §核心目标 6 判据全形态实证(消除 D138 §核心目标"业务 INSERT 后无法 ORM/Repository 层 save(entity).id 回填走 KeyHolder 标准"剩余路径未验证)
— 复用 Phase 1-3 lib + 编译器扩 — 单一信息源出口(D138 §核心原则 4)
— D135/D136/D137/D138 SQL 主线范式 — 每 Phase 独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环

§D135/D136/D137/D138 Phase 4 同形参考:
— D135 Phase 0 + Phase 1 同 commit 模式
— D136 Phase 0 commit `9326b9f` + Phase 1 commit `c854778` 同模式
— D137 Phase 0 commit `bafc25a` + Phase 1 commit `d2df1ba` 同模式
— D138 Phase 0 commit `d47a05d` + Phase 1 commit `182b3fb` + Phase 1.5 计划落档 commit `c90df15` + Phase 1.5 实施 commit `8793be0` + Phase 2 commit `1ee1173` + Phase 3 commit `<本轮回填>` + Phase 4 commit(下轮 测试覆盖 6 形态)+ Phase 5 commit(下下轮 全 Phase 收关)同模式
