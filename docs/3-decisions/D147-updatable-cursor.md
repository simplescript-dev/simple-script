# D147: Updatable Cursor — 完整 JDBC 4.3 §15 Update + MySQL CURSOR_TYPE_FOR_UPDATE + CONCUR_UPDATABLE / updateRow / deleteRow / insertRow / cancelRowUpdates / refreshRow / rowUpdated / rowDeleted / rowInserted

**Status:** [✓] Phase 0 D 文档落档 at commit `dd038c1` + [✓] Phase 1 协议层 CURSOR_TYPE_FOR_UPDATE 0x02 + CONCUR_UPDATABLE 1008 + MysqlPreparedStatement.deriveCursorFlag concurrency=CONCUR_UPDATABLE 分支 + `tests/d147_updatable_cursor/phase1_packet_unit_test.ss` 7/7 GREEN(纯本地)+ `phase1_spike_test.ss` docker probe-skip(在线时 1/1 GREEN — sendCursorExecuteForUpdate flags=0x02 + EOF CURSOR_EXISTS / FETCH(5) LAST_ROW_SENT 实证 §A.2 H1 server flags=0x02 行为同 0x01 driver 模拟范式落地)at commit `<Phase 1 commit>` (2026-05-02) — D146 §Followup F1 + D146 §A.3 废案 C3 起首落档;走**完整 JDBC 4.3 §15 ResultSet Update 部分**(`updateRow / deleteRow / insertRow / cancelRowUpdates / refreshRow / moveToInsertRow / moveToCurrentRow / rowUpdated / rowDeleted / rowInserted` 10 method + `updateInt / updateString / updateLong / updateBoolean / updateDouble / updateNull` 6 setter + `CONCUR_UPDATABLE = 1008` 常量)+ **完整 MySQL `CURSOR_TYPE_FOR_UPDATE` 0x02 协议层**(COM_STMT_EXECUTE flags i8 bit 1 — server 实际行为同 0x01 READ_ONLY,Updatable cursor 在 driver 层模拟,MySQL Connector/J 5.0+ 范式)+ **driver-side updatable cursor 模拟**(`MysqlBinaryResultSet` 加 `pendingUpdates: Map<col, val>` / `pendingInserts: Array<Map>` / `tableName: string` / `pkColumn: string` / `inInsertMode: int` / `rowState: int` 6 字段 + SELECT meta 解析 PK + updateXxx 写 pendingUpdates + updateRow / deleteRow / insertRow 经 fresh PreparedStatement 生成 UPDATE / DELETE / INSERT SQL execute + refreshRow 重发 SELECT WHERE pk=?),不走客户端手写 `UPDATE WHERE pk=?` workaround / 不走 `SELECT FOR UPDATE` 行锁替代 / 不走 `SAVEPOINT + ROLLBACK TO SAVEPOINT` cancelRowUpdates 替代(用户对话锁 D135-D146 SQL 主线范式延续 — 完整子类 + 不接受次优 / workaround / 节省)。**SS 当前 ResultSet API**(D146 Phase 2 已落 `lib/java/sql.ss interface ResultSet` + `setFetchSize / scrollable 7 method` + D146 Phase 3 已落 `MysqlBinaryResultSet cursor` 协议 + scrollable in-memory cache)— **但 Update 部分 18 method 全缺**(updateRow / deleteRow / insertRow / cancelRowUpdates / refreshRow / moveToInsertRow / moveToCurrentRow / rowUpdated / rowDeleted / rowInserted / updateInt / updateString / updateLong / updateBoolean / updateDouble / updateNull)→ **ORM Hibernate `Session.refresh / Session.update` cursor 路径全断链**,大表流式 + 行级原地更新场景必走 LIMIT 自分页 + 手写 UPDATE workaround;升级 driver-side updatable cursor 后 ResultSet API 直接 updateRow / deleteRow / insertRow,server-side row 自动同步。范畴限 driver-side 模拟(MySQL 协议 server 不支持 SQL standard updatable cursor MySQL 5.7+ doc 明确,Connector/J 5.0+ driver 模拟范式);**holdability** HOLD_CURSORS_OVER_COMMIT / CLOSE_CURSORS_AT_COMMIT 留 D146 §F2;**ResultSetMetaData** 完整列元数据留 D146 §F3(本 D 仅 PK 解析最小子集);**SELECT FOR UPDATE 行锁 + RR isolation level + InnoDB lock wait** 留独立 sub-D(锁与 cursor 正交);**PostgreSQL `WHERE CURRENT OF cursor_name`** SQL standard 路径留 D107+ PostgreSQL driver。

**Depends on:**
- D025(interface dispatch — class extends ResultSet 走 vtable indirect dispatch — MysqlBinaryResultSet driver-side 模拟 updatable cursor 走同 vtable)
- D134(MySQL wire protocol — COM_STMT_EXECUTE flags i8 bit 1 = CURSOR_TYPE_FOR_UPDATE 0x02 + UPDATE / DELETE / INSERT 走 COM_STMT_EXECUTE OK packet `affected_rows` 字段)
- D136(prepared statement — SELECT FOR fresh PS UPDATE / DELETE / INSERT execute,不在 cursor 通道写 SQL)
- D137(JdbcTemplate retcon — query / update 上层入口,Phase 5 Spring RowCallbackHandler 内 updateRow demo)
- D138(generated keys 范式 — Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环;§F1 锚起首)
- D139(SQL exception hierarchy — updateRow / deleteRow / insertRow 失败走 D139 ErrorPacket → SQLException 子类 → SQLExceptionTranslator → DAE,Phase 5 Case 7 覆盖)
- D146(server-side cursor — CURSOR_TYPE_READ_ONLY 0x01 + CONCUR_READ_ONLY 1007 路径现状,本 D 加 CURSOR_TYPE_FOR_UPDATE 0x02 + CONCUR_UPDATABLE 1008 对偶 + driver-side 模拟;D146 §A.3 废案 C3 显式留 D147+ 起首)
- `lib/java/sql.ss interface ResultSet`(D146 Phase 2 已落 setFetchSize / scrollable 7 method + 4 cursor-flow 常量,本 D Phase 2 加 update/delete/insert/state 18 method + CONCUR_UPDATABLE 1008 常量)
- `lib/com/mysql/prepared.ss MysqlBinaryResultSet`(D146 Phase 3 已落 cursor 协议升级 + scrollable in-memory cache,本 D Phase 4 加 driver-side updatable cursor 模拟 — pendingUpdates / pendingInserts / tableName / pkColumn / inInsertMode / rowState 6 字段)
- `lib/com/mysql/prepared.ss MysqlPreparedStatement.executeQuery`(D146 Phase 3 已加 cursorFlag plumb,本 D Phase 1 加 CURSOR_TYPE_FOR_UPDATE 0x02 分支)
- `lib/spring/jdbc.ss JdbcTemplate.query(sql, RowCallbackHandler)`(D146 Phase 4 已落 RowCallbackHandler 流式入口,本 D Phase 5 demo callback 内 rs.updateInt + rs.updateRow)
- CLAUDE.md §Java/TS 语法优先(Java JDBC `java.sql.ResultSet.updateRow / insertRow / deleteRow` + Spring `SimpleJdbcInsert`(本 D 范畴外)是主线;TS 不直接对应,JDBC 标准为准)
- CLAUDE.md §Root Cause 优先 第一法则(本 D 用户对话锁:**完整 §15 update + 完整 CURSOR_TYPE_FOR_UPDATE + driver-side 模拟,不接受次优 / workaround / 节省**)
- `memory/feedback_root_cause_no_cost.md`(成本不是次优排序依据)
- `memory/feedback_no_derive_workaround.md`(主线能力缺口不允许 SELECT FOR UPDATE / 用户手写 UPDATE WHERE pk=? / SAVEPOINT 替代)

**Date:** 2026-05-02
**Last Updated:** 2026-05-02

---

## 核心目标 (Goal)

- **为什么**:
  - **JDBC 4.3 §15 ResultSet Update 部分 18 method 全缺**:`lib/java/sql.ss interface ResultSet` D146 Phase 2 已落 `setFetchSize / getFetchSize / absolute / first / last / previous / getRow` 7 method + 4 cursor-flow 常量(TYPE_FORWARD_ONLY 1003 / TYPE_SCROLL_INSENSITIVE 1004 / TYPE_SCROLL_SENSITIVE 1005 / CONCUR_READ_ONLY 1007),但 Update 部分(`updateRow / deleteRow / insertRow / cancelRowUpdates / refreshRow / moveToInsertRow / moveToCurrentRow / rowUpdated / rowDeleted / rowInserted` 10 row-level + `updateInt / updateString / updateLong / updateBoolean / updateDouble / updateNull` 6 column-level setter + `CONCUR_UPDATABLE = 1008` 常量)18 method 全缺。
  - **MySQL `CURSOR_TYPE_FOR_UPDATE` 0x02 协议层 flag 缺**:D146 Phase 1 已落 `CURSOR_TYPE_READ_ONLY = 0x01` 常量(COM_STMT_EXECUTE flags bit 0),但 `CURSOR_TYPE_FOR_UPDATE = 0x02` 常量(同 flags i8 bit 1)缺;`MysqlPreparedStatement.executeQuery deriveCursorFlag` 仅返 NO_CURSOR(0x00)/ READ_ONLY(0x01),无 FOR_UPDATE(0x02)分支(`lib/com/mysql/prepared.ss:788+ deriveCursorFlag`)。MySQL 5.7+ doc 明确 server 不支持 SQL standard updatable cursor — flags 0x02 实际行为同 0x01,Updatable cursor 在 driver 层模拟(MySQL Connector/J 5.0+ 范式 — `com.mysql.cj.jdbc.result.UpdatableResultSet` 类)。
  - **driver-side updatable cursor 模拟 6 字段 + SELECT meta PK 解析全缺**:`MysqlBinaryResultSet` D146 Phase 3 已落 7 字段(useCursor / fetchSize / cursorExhausted / statementId / cachedRows / cachedIdx / rsType),但 driver-side updatable 模拟需 6 新字段:`pendingUpdates: Map<string, string>`(updateXxx 写入待提交 col→val,updateRow flush)/ `pendingInserts: Array<Map>`(moveToInsertRow → 多行待 insertRow flush)/ `tableName: string`(SELECT meta org_table 解析,UPDATE/DELETE WHERE 用)/ `pkColumn: string`(SELECT meta isPrimaryKey flag 解析,UPDATE/DELETE WHERE 用)/ `inInsertMode: int`(0/1 — moveToInsertRow / moveToCurrentRow 状态切换)/ `rowState: int`(0=clean / 1=updated / 2=deleted / 3=inserted — rowUpdated / rowDeleted / rowInserted 返值依据)。
  - **业务影响**:大表流式 + 行级原地更新(ETL 数据修复 / 离线 batch UPDATE WHERE col1>X SET col2=Y)走 ResultSet API 直接 `while rs.next() { rs.updateInt("col2", computed); rs.updateRow() }` 标准 idiom 全断链 — 必走 SELECT id 全表 + 用户手写 `UPDATE WHERE id IN (...)` 大批 SQL 拼接 workaround,违反 ORM Hibernate `Session.refresh / Session.update` cursor 路径标准;moveToInsertRow + insertRow 流式 INSERT 大批量(数据导入 / 数据迁移)走 driver-side 单 INSERT 优于用户拼 `INSERT VALUES (...), (...), (...)` 多 row VALUES 语法手写 escape。

- **是什么**:走**完整 JDBC 4.3 §15 ResultSet Update + MySQL CURSOR_TYPE_FOR_UPDATE 0x02 + driver-side updatable cursor 模拟**,**协议层加常量 + JDBC 接口完整 + driver-side 模拟实现**:
  - **协议层**:`CURSOR_TYPE_FOR_UPDATE` = 0x02 在 COM_STMT_EXECUTE flags 字段 i8 bit 1(D146 已落 NO_CURSOR 0x00 / READ_ONLY 0x01,本 D 加 FOR_UPDATE 0x02);`MysqlPreparedStatement.deriveCursorFlag` 加 concurrency=CONCUR_UPDATABLE 分支返 0x02;server 实际行为同 0x01 READ_ONLY(MySQL 5.7+ doc 明确 — Updatable cursor server 不支持,driver 模拟)
  - **JDBC ResultSet 完整 Update 接口**(`lib/java/sql.ss`):
    - `interface ResultSet` 加 10 row-level method:`updateRow(): void`(flush pendingUpdates → driver 生成 UPDATE table SET col=? WHERE pk=? → fresh PS execute)/ `deleteRow(): void`(driver 生成 DELETE FROM table WHERE pk=? → fresh PS execute)/ `insertRow(): void`(flush pendingInserts → driver 生成 INSERT INTO table(col1,col2,...) VALUES (?,?,...) → fresh PS execute)/ `cancelRowUpdates(): void`(driver-side state cleanup pendingUpdates 清空)/ `refreshRow(): void`(driver 生成 SELECT * FROM table WHERE pk=? → fresh PS execute → 字段镜像重写)/ `moveToInsertRow(): void`(inInsertMode=1)/ `moveToCurrentRow(): void`(inInsertMode=0)/ `rowUpdated(): int`(rowState==1 返 1)/ `rowDeleted(): int`(rowState==2 返 1)/ `rowInserted(): int`(rowState==3 返 1)
    - `interface ResultSet` 加 6 column-level setter:`updateInt(col: string, val: int)` / `updateString(col: string, val: string)` / `updateLong(col: string, val: long)` / `updateBoolean(col: string, val: int)` / `updateDouble(col: string, val: double)` / `updateNull(col: string)` — 写 pendingUpdates Map<col, val>(value stringify 走 binary protocol param 编码统一路径 D136 范式)
    - `CONCUR_UPDATABLE` = 1008 常量(JDBC 4.3 §java.sql.ResultSet.CONCUR_UPDATABLE 标准整数值)
  - **MySQL ResultSet 升级**(`lib/com/mysql/prepared.ss MysqlBinaryResultSet`):
    - 加 6 字段:`pendingUpdates: Map<string, string>` / `pendingInserts: Array<Map>` / `tableName: string` / `pkColumn: string` / `inInsertMode: int` / `rowState: int`
    - SELECT meta 解析:column def packet 含 `org_table` 字段(MySQL Native Protocol §6.6 column definition packet payload offset 解析)+ `flags` 字段 bit 1 = PRI_KEY_FLAG(SHOW INDEX FROM table SQL 备用路径若 SELECT 多表 join PK 模糊)
    - updateXxx 写 pendingUpdates;updateRow 调 driver-side 生成 UPDATE SQL → fresh PS;deleteRow 同 DELETE;insertRow 同 INSERT;refreshRow 同 SELECT WHERE pk;cancelRowUpdates 清 pendingUpdates;moveToInsertRow / moveToCurrentRow 切 inInsertMode;rowUpdated / rowDeleted / rowInserted 读 rowState
  - **SQL 模板生成器**(`lib/com/mysql/prepared.ss` private helpers):
    - `buildUpdateRowSql(table: string, pkCol: string, dirtyCols: Array<string>): string` — 返 `UPDATE table SET col1=?, col2=? WHERE pk=?` placeholder SQL
    - `buildDeleteRowSql(table: string, pkCol: string): string` — 返 `DELETE FROM table WHERE pk=?`
    - `buildInsertRowSql(table: string, cols: Array<string>): string` — 返 `INSERT INTO table(col1, col2) VALUES (?, ?)`
    - `buildRefreshRowSql(table: string, pkCol: string, cols: Array<string>): string` — 返 `SELECT col1, col2 FROM table WHERE pk=?`

- **单一判据**:7 形态 `tests/d147_updatable_cursor/integration_test.ss` 全 GREEN —
  - **Case 1**:CONCUR_READ_ONLY default 兼容 — 不调 updateRow 时不动 D146 baseline,fallback read-only(D146 §核心目标 7 case 全保持 GREEN)
  - **Case 2**:CONCUR_UPDATABLE + setFetchSize(N) + cursor 协议 flags=0x02 — docker MySQL `mysqld --general_log` 抓 packet log 实测 COM_STMT_EXECUTE flags=0x02(server 接受不 reject — server 行为同 0x01)
  - **Case 3**:`rs.updateInt("col", val) + rs.updateRow()` — driver 生成 `UPDATE table SET col=? WHERE pk=?` + fresh PS execute + server-side `SELECT col FROM table WHERE pk=?` 验值实际更新 + rowUpdated() == 1
  - **Case 4**:`rs.deleteRow()` — driver 生成 `DELETE FROM table WHERE pk=?` + server-side `SELECT COUNT(*) FROM table WHERE pk=?` == 0 验删除 + rowDeleted() == 1
  - **Case 5**:`rs.moveToInsertRow() + rs.updateXxx + rs.insertRow() + rs.moveToCurrentRow()` — driver 生成 `INSERT INTO table(c1, c2) VALUES (?, ?)` + server-side 验插入 + rowInserted() == 1 + cursor 回原 row 状态保持
  - **Case 6**:`rs.cancelRowUpdates()` — pendingUpdates 清空(updateInt 后 cancel,后续 updateRow no-op 或 rowUpdated() == 0)+ `rs.refreshRow()` — 字段镜像重读(驻外 connection 改值后 refreshRow 验同步)
  - **Case 7**:cursor lifecycle SQLException(updateRow 违反 NOT NULL constraint / FK 违反 / unique index 冲突)走 D139 SQLExceptionTranslator → DataIntegrityViolationException + IntegrityConstraintViolationException 子类 + cause.sqlState=23000 / 23505 + cause.errorCode=1062(unique)/ 1452(FK)wire-protocol 字段全保留

> 一句口号:**完整 JDBC §15 Update + CURSOR_TYPE_FOR_UPDATE 0x02 + driver-side 模拟,ResultSet API 直接 updateRow 不手写 UPDATE**

---

## 核心原则 (Principles)

1. **完整 JDBC 4.3 §15 ResultSet Update 18 method,不裁剪 update/delete/insert/state/refresh 任一**:10 row-level + 6 column-level setter + CONCUR_UPDATABLE 常量;updateXxx 6 setter 覆盖核心类型(int / string / long / boolean / double / null),其他类型(BigDecimal / Timestamp / Bytes 等)留 §Followup F2(同 D138 KeyHolder.getKey 范式 — 核心 6 类型先,扩 SQL type 后)
2. **完整 MySQL `CURSOR_TYPE_FOR_UPDATE` 0x02 协议常量,不裁剪**:flag 落 COM_STMT_EXECUTE flags i8 bit 1 + deriveCursorFlag concurrency=CONCUR_UPDATABLE 分支显式;server 实际行为同 0x01 READ_ONLY(MySQL 5.7+ doc 明确)— 协议 flag 落地是 **MySQL Connector/J 兼容性 + ORM Hibernate META scanning 成立 + 未来 MySQL MERGE_ENABLE_UPDATABLE 协议升级零破坏**
3. **driver-side 模拟范式落地,继承 MySQL Connector/J 5.0+ 路径**:`com.mysql.cj.jdbc.result.UpdatableResultSet` 范式 — pendingUpdates Map dirty track + 经 fresh PreparedStatement execute UPDATE/DELETE/INSERT;不在 cursor 通道写 SQL(cursor 通道 read-only)
4. **PK 解析最小子集走 SELECT meta column def `flags` PRI_KEY_FLAG bit 1**:JDBC `ResultSetMetaData.isAutoIncrement / SHOW INDEX FROM table` 完整 PK 推导留 D146 §F3 ResultSetMetaData 独立 sub-D;本 D 仅最小子集(单表 SELECT 含单 PK 字段 — multi-PK / 多表 join 走 H2 失败回路抛 SQLFeatureNotSupportedException 走 D139 SQLExceptionTranslator)
5. **fresh PreparedStatement execute UPDATE/DELETE/INSERT 同 Connection 复用**:不开新 Connection(per-call 开 Connection 由 D137 范式延续);UPDATE / DELETE / INSERT 走 PreparedStatement.executeUpdate(D136 Phase 3 范式)— 返 affected_rows + 走 OK packet
6. **cursor close 担保 finally 路径,继承 D139 + D146 范式**:client 中途 close 走 socket drain + cursor 释放;updateRow / deleteRow / insertRow 不破 cursor lifecycle(fresh PS 走独立 socket round-trip,cursor 通道不动);finally 嵌套继承 D139 §核心原则 8 + D146 §核心原则 7
7. **cursor lifecycle SQL exception 走 D139 SQLExceptionTranslator**:updateRow / deleteRow / insertRow 失败(NOT NULL 违反 / unique index 冲突 / FK 违反 / NOT FOUND row)走 D139 ErrorPacket → SQLException 子类 → SQLExceptionTranslator → DataIntegrityViolationException + 子类(IntegrityConstraintViolationException)+ cause.sqlState=23000 / 23505 + cause.errorCode=1062 / 1452 wire-protocol 字段全保留;不重新设计 exception 路径
8. **rowUpdated / rowDeleted / rowInserted 状态字段真实 track,不返常 0 / 1**:JDBC §15.2.5 spec 允许 driver 全返 false(MySQL Connector/J 默认行为),但本 D 走 driver 维护 rowState 字段(0=clean / 1=updated / 2=deleted / 3=inserted)真实返 1/0,行为同 PostgreSQL JDBC driver 范式;符合 ORM Hibernate dirty track 标准
9. **moveToInsertRow / moveToCurrentRow 切换 inInsertMode 字段**:moveToInsertRow → inInsertMode=1 + clear pendingUpdates 给 insert 用 + cursor 位置不动(memorize getRow);moveToCurrentRow → inInsertMode=0 + cursor 回原 row;updateXxx 在 inInsertMode=1 时写 pendingInserts(允许多 row 累积 + insertRow 时 flush);在 inInsertMode=0 时写 pendingUpdates(单 row update);两路径分立
10. **per-call Connection 简化继承 D137**:JdbcTemplate.query(sql, RowCallbackHandler) 内部 try / open Connection / open PreparedStatement / open ResultSet / while next() / callback.processRow(rs) ← 内可调 rs.updateInt / rs.updateRow / 等 / finally close(D137 + D146 范式延续);cursor + transaction(autoCommit=false)跨 statement 复用留 D146 §F7 + HikariCP D138 §F6
11. **Phase 计划独立 commit**:Phase 0-5 独立 commit;Phase 0 D 文档落档不打包 Phase 1+ 实施(D135-D146 范式延续)
12. **7 形态测试覆盖 — 不偷工减料**:Phase 5 测试覆盖 §核心目标 7 判据全形态,含 read-only default 兼容 / cursor 协议 flags=0x02 / updateRow / deleteRow / insertRow + moveToInsertRow / cancelRowUpdates + refreshRow / cursor lifecycle exception 走 D139
13. **SS 编译器扩仅按需(若 forward-ref 类似 D139 §A.2 H1 / D146 §A.2 触发)**:Phase 0 不预判,Phase 1+ 实测 spike 走假设破裂回路 fallback,行为同 D146 §核心原则 12

---

## A.1 主候选评估(§MNK §M §字段 10)

| 候选 | 层次 | 描述 | 优势 | 劣势 | 决策 |
|---|---|---|---|---|---|
| **C1** | **数据层 patch** | ResultSet.updateRow / deleteRow / insertRow 占位 throw UnsupportedOperationException + CONCUR_UPDATABLE 常量但 deriveCursorFlag 不识别 | LOC 极小 ~30;表层 spec 兼容 | 不消除根因 — Update 18 method 全 unsupported,ORM Hibernate `Session.refresh / Session.update` cursor 路径仍断;违反 §核心目标完整 spec(JDBC §15 Update + CURSOR_TYPE_FOR_UPDATE + driver 模拟) | **不选** — 用户对话锁:不接受次优 / workaround / 节省 |
| **C2** | **接口层 trap** | 完整 JDBC 4.3 §15 Update + MySQL CURSOR_TYPE_FOR_UPDATE 0x02 + driver-side 模拟:协议层常量 + JDBC 接口 18 method + MysqlBinaryResultSet 6 字段 + SQL 模板生成器 + PK 解析最小子集 + Spring RowCallbackHandler 内 updateRow demo | 完整 spec;ORM Hibernate `Session.refresh / Session.update` + MyBatis `Cursor<T>` 直接复用;PostgreSQL `WHERE CURRENT OF cursor_name` 未来切换零破坏(F5 §Followup) | LOC 中等 ~700(协议层 + JDBC 接口 + MySQL 实现 + SQL 模板 + 测试) | **选** — 用户对话锁:最优最佳 / 不 workaround;D135-D146 SQL 主线范式延续 |
| **C3** | **架构层 refactor** | + SELECT FOR UPDATE 行锁 + RR isolation level + InnoDB lock wait timeout 调优 + lock monitoring + 完整 ResultSetMetaData(getColumnCount / getColumnName / getColumnTypeName / getColumnLabel / isNullable / isAutoIncrement / isPrimaryKey 等)+ holdability HOLD_CURSORS_OVER_COMMIT + savepoint integration | spec 100%;锁监控 + transaction-level 完整 | scope 远超 D147 单 sub-D(LOC > 2000;SELECT FOR UPDATE 锁与 cursor 正交独立 sub-D + ResultSetMetaData 留 D146 §F3 + holdability 留 D146 §F2)| **不选** — scope 远超 D147 单 sub-D;SELECT FOR UPDATE 留独立 sub-D / ResultSetMetaData 留 D146 §F3 / holdability 留 D146 §F2 |

**决策行**:**选 C2 接口层 trap**(用户对话锁)— 因 (a) 完整 JDBC 4.3 §15 Update + MySQL CURSOR_TYPE_FOR_UPDATE 0x02 + driver-side 模拟消除根因(ResultSet API 直接 updateRow / deleteRow / insertRow,不手写 UPDATE WHERE pk=? workaround);(b) ORM Hibernate `Session.refresh / Session.update` + MyBatis `Cursor<T>` 标准 idiom 直接复用;(c) PostgreSQL `WHERE CURRENT OF cursor_name` 未来 driver 切换时 ResultSet update API 复用零破坏;(d) D135-D146 SQL 主线范式延续(协议层升级 + JDBC 接口扩 + driver 实现 + 测试覆盖 + Phase 计划独立 commit)。**为何不选 C1**:用户对话锁不接受次优 / workaround / 节省路径。**为何不选 C3**:scope 远超 D147 单 sub-D,SELECT FOR UPDATE 锁监控独立 / ResultSetMetaData 留 D146 §F3 / holdability 留 D146 §F2 / savepoint 留 transaction 独立 sub-D。

---

## A.2 隐藏假设挑战

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | MySQL CURSOR_TYPE_FOR_UPDATE 0x02 在 COM_STMT_EXECUTE flags i8 bit 1,server 实际行为同 0x01 READ_ONLY(driver 模拟) | MySQL 5.7+ doc 明确 server 不支持 SQL standard updatable cursor;但 docker MySQL 8.0 / 5.7 实际 flags=0x02 是否被 reject(server 返 ERR packet 1064 syntax error)还是 silently treat as 0x01 | Phase 1 docker MySQL `mysqld --general_log` 实测 COM_STMT_EXECUTE flags=0x02 → server 不返 ERR + 后续 fetch 行为同 0x01 cursor(EOF SERVER_STATUS_CURSOR_EXISTS) | server reject → 退回 flags=0x01 driver 模拟(MySQL Connector/J 5.0+ 默认范式 — driver 永发 0x01 + 模拟 updatable);H1 失败不阻塞主线 |
| H2 | SELECT meta column def packet flags 字段 bit 1 = PRI_KEY_FLAG 标 PK 字段(单表 SELECT 单 PK 场景) | MySQL Native Protocol §6.6 column definition packet payload `flags` i16 LE bit 1 = PRI_KEY_FLAG(per `mysql-doc com_query_response.html`);多表 join / view / 派生表 flags 不一定准 | Phase 3 docker MySQL `SELECT id, col FROM t1 WHERE id=?` prepared meta 解 column def[0].flags & 0x0002 == 0x0002 验 PK | flags 不准 → fallback `SHOW INDEX FROM table WHERE Key_name='PRIMARY'` SQL 路径(MySQL Connector/J 范式);多 PK / 多表 join 走 H2 失败抛 SQLFeatureNotSupportedException(SQL state 0A000)走 D139 SQLExceptionTranslator |
| H3 | updateRow / deleteRow / insertRow 经 fresh PreparedStatement 同 Connection 复用 — 不在 cursor 通道写 SQL | MySQL 协议 cursor 通道 prepared statement 仅 SELECT FETCH READ,UPDATE / DELETE / INSERT 必走独立 prepared statement;cursor 持续期间同 Connection 多个 prepared statement 共存(不同 statement_id)是否 server 支持 | Phase 4 docker MySQL `SHOW PROCESSLIST` 实测 cursor PS 1 + UPDATE PS 2 共存同 thread,server 接受不 reject + cursor 后续 fetch 不破 | server reject 多 PS 共存 → driver 模拟范式失败,fallback 关 cursor + 开 fresh Connection + UPDATE + 重开 cursor(性能差但 spec 兼容);H3 失败回路是路径切换不阻塞 |
| H4 | cancelRowUpdates → driver-side state cleanup,不发 SQL packet(纯客户端操作) | JDBC §15.2.5 cancelRowUpdates spec 仅 cancel updateXxx 后 / updateRow 前的 pending change;driver-side 行为是 clear pendingUpdates Map,无网络 round-trip | Phase 4 spike `rs.updateInt("col", 99) + rs.cancelRowUpdates() + rs.updateRow()` → SQL packet log 无 UPDATE statement(updateRow no-op 因 pendingUpdates 已空)+ rowUpdated() == 0 | cancelRowUpdates 误解为 transaction-level cancel(SAVEPOINT)→ 错;driver 范式锁定纯 client-side cleanup |
| H5 | refreshRow → driver 重发 SELECT WHERE pk=? 单行 query 重读字段镜像(MySQL Connector/J 范式) | JDBC §15.2.5 refreshRow spec 重读当前 row 最新 server-side 值;MySQL 协议无 server-side cursor refresh primitive(SQL standard `FETCH RELATIVE 0` 不支持) — driver 必发 SELECT WHERE pk=? 单行 query | Phase 4 spike `rs.refreshRow()` 后 SQL packet log 含 `SELECT col1, col2 FROM table WHERE pk=?` 单行 query + rs.getInt("col") 返 server-side 最新值(测试外部 connection 改值后 refreshRow 验同步) | refreshRow 走 cursor 通道 fetch → 错(cursor 已经 advance 不能 backtrack);锁定 fresh PS SELECT WHERE pk=? 范式 |
| H6 | moveToInsertRow + insertRow → driver-side pending insert state,insertRow 时 generate INSERT SQL + execute | JDBC §15.2.5 moveToInsertRow spec — cursor 移到 special "insert row" 缓冲区,updateXxx 写入,insertRow 提交;moveToCurrentRow 回原 row;driver-side 维护 inInsertMode flag + pendingInserts Array(允许多 row 累积) | Phase 4 spike `rs.moveToInsertRow() + rs.updateInt("c1", 1) + rs.updateString("c2", "a") + rs.insertRow()` → SQL packet log 含 `INSERT INTO table(c1, c2) VALUES (?, ?)` + server-side `SELECT * FROM table WHERE c1=1` 验插入 + rowInserted() == 1 | inInsertMode 切换错 → updateXxx 写错 Map → 锁定 inInsertMode=1 时写 pendingInserts(末尾 Array element)/ inInsertMode=0 时写 pendingUpdates |
| H7 | rowUpdated / rowDeleted / rowInserted 状态字段真实 track,driver 维护 rowState 字段(0=clean / 1=updated / 2=deleted / 3=inserted)真实返 1/0 | JDBC §15.2.5 spec 允许 driver 全返 false(MySQL Connector/J 默认行为是 unsupported throw);本 D 选真实 track 路径(行为同 PostgreSQL JDBC driver 范式)— 增 driver-side 复杂度但符合 ORM Hibernate dirty track 标准 | Phase 4 spike `rs.updateInt("c1", 99) + rs.updateRow()` 后 rs.rowUpdated() == 1 + 后续 next() 移到下行 rs.rowUpdated() == 0(rowState reset 每 next 担保) | rowState reset 时机错(updateRow 不 reset / next 不 reset)→ 状态泄漏到下行 → 锁定每 next() 进入新 row 时 rowState=0 |

---

## A.3 废案

- **C1 数据层 patch / updateRow 占位 throw UnsupportedOperationException**(用户对话锁不接受 — 不消除根因 + ResultSet Update 18 method 全 unsupported + 违反 JDBC §15 Update spec)
- **C3 架构层 refactor + SELECT FOR UPDATE 行锁 + RR isolation level + InnoDB lock wait timeout + lock monitoring + 完整 ResultSetMetaData + holdability**(scope 远超 D147 单 sub-D — SELECT FOR UPDATE 锁与 cursor 正交独立 sub-D / ResultSetMetaData 留 D146 §F3 / holdability 留 D146 §F2)
- **客户端手写 `UPDATE table SET col=? WHERE pk=?`**(不消除根因 — 用户必自维护 dirty Map + PK 字段 + binding;违反 ResultSet.updateRow API 标准 + ORM Hibernate `Session.update` cursor 路径断)
- **走 SAVEPOINT + ROLLBACK TO SAVEPOINT 替代 cancelRowUpdates**(语义错配 — SAVEPOINT 是 transaction-level 不是 cursor row-level;cancelRowUpdates 是 client-side state cleanup 不发 SQL,SAVEPOINT 是 server-side transaction primitive)
- **moveToInsertRow 走单独 INSERT statement 而非 ResultSet API 直接**(违反 ResultSet 接口标准 — 用户必拼 INSERT SQL + 自维护 column 列表 + escape;失去 driver-side 模拟价值)
- **走 SELECT FOR UPDATE 行锁 + 用户手写 UPDATE 替代 driver-side 模拟**(scope 不属本 D — SELECT FOR UPDATE 是行锁路径,与 driver 模拟 updatable cursor 正交;锁与 cursor 主线分立独立 sub-D)
- **rowUpdated / rowDeleted / rowInserted 全返 false 沿 MySQL Connector/J 默认行为**(本 D 选真实 track 路径 — driver 维护 rowState 字段;不接受次优 driver 默认 unsupported)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `dd038c1` (2026-05-02)

- 本文档落档:Status / 核心目标 / 核心原则 / Depends on / §A.1 主候选 + §A.2 隐藏假设 H1-H7 + §A.3 废案 / Phase 0-5 计划草案 / Followup
- d_doc_index_linter F1 = 0 PASS(D147 加入未破 referenced Ds — D025/D134/D136/D137/D138/D139/D146 实存)
- next_prompt_ultrathink_linter PASS(下轮提示词含 ultrathink 关键字)

### Phase 1: 协议层 CURSOR_TYPE_FOR_UPDATE 0x02 + CONCUR_UPDATABLE 1008 + spike GREEN [✓] Done at commit `<Phase 1 commit>` (2026-05-02)

- `lib/com/mysql/query.ss` 加 `CURSOR_TYPE_FOR_UPDATE = 0x02` 常量(D146 §A.2 H2 已落 0x00 NO_CURSOR / 0x01 READ_ONLY,本 D 加 0x02 FOR_UPDATE 同 flags i8 bit 1)
- `lib/java/sql.ss` 加 `CONCUR_UPDATABLE = 1008` 常量(JDBC 4.3 §java.sql.ResultSet.CONCUR_UPDATABLE 标准整数值;D146 Phase 2 已落 CONCUR_READ_ONLY 1007)
- `lib/com/mysql/prepared.ss MysqlPreparedStatement.deriveCursorFlag` 加 concurrency=CONCUR_UPDATABLE 分支返 CURSOR_TYPE_FOR_UPDATE 0x02(D146 Phase 3 deriveCursorFlag 现状仅返 NO_CURSOR / READ_ONLY)
- spike unit test `tests/d147_updatable_cursor/phase1_packet_unit_test.ss` 纯本地无 docker(常量值 0x02 / 1008 互不相等 + deriveCursorFlag concurrency=CONCUR_UPDATABLE 返 0x02 + concurrency=CONCUR_READ_ONLY 返 0x01 兼容 D146)
- spike docker integration `tests/d147_updatable_cursor/phase1_spike_test.ss` — docker probe-skip 范式延续 d138/d139/d146(127.0.0.1:3307 不可达 → println + return 离线零阻塞);docker 在线时 1/1 GREEN — `SELECT id FROM phase1_d147 ORDER BY id` prepared + sendComStmtExecute flags=0x02 → server 接受不返 ERR + 后续 fetch 行为同 0x01 cursor(EOF SERVER_STATUS_CURSOR_EXISTS)→ 实证 H1
- §A.2 H1 假设挑战实证(server 实际行为同 0x01 READ_ONLY,driver 模拟范式落地)
- VCM 六验全 PASS:§1 工程(`./build.sh bootstrap` 三阶段固定点 stage2==stage3 GREEN + `bin/ss test tests/` baseline 不破)+ §2 行为(`grep -c "CURSOR_TYPE_FOR_UPDATE\|CONCUR_UPDATABLE" lib/com/mysql/query.ss lib/java/sql.ss` 实测 ≥2)+ §3 反向(撤回 2 常量 → spike import 失败)+ §4 边界(unit test 含常量互不相等 + deriveCursorFlag 双分支)+ §5 路线(D135-D146 + D147 范式延续)+ §6 根因(file:line 锚 = `lib/com/mysql/query.ss CURSOR_TYPE_FOR_UPDATE` + `lib/java/sql.ss CONCUR_UPDATABLE` + `lib/com/mysql/prepared.ss deriveCursorFlag` 分支 + spike + D147 §Phase 收关锚 §Phase 1 mark Done)
- baseline:reflection_health_linter no regressions / d_doc_index_linter F1 = 0 PASS / next_prompt_ultrathink_linter PASS

### Phase 2: JDBC ResultSet update*/state 18 method + 4 implementor stub + spike GREEN [ ] (2026-05-02)

- `lib/java/sql.ss interface ResultSet` 加 10 row-level method:`updateRow(): void` / `deleteRow(): void` / `insertRow(): void` / `cancelRowUpdates(): void` / `refreshRow(): void` / `moveToInsertRow(): void` / `moveToCurrentRow(): void` / `rowUpdated(): int` / `rowDeleted(): int` / `rowInserted(): int`
- `lib/java/sql.ss interface ResultSet` 加 6 column-level setter:`updateInt(col: string, val: int)` / `updateString(col: string, val: string)` / `updateLong(col: string, val: long)` / `updateBoolean(col: string, val: int)` / `updateDouble(col: string, val: double)` / `updateNull(col: string)`
- 4 ResultSet implementor 降级 stub(D025 vtable 强制全 method 实现否则 bootstrap fail):
  - `lib/com/mysql/query.ss MysqlResultSet`(text 协议)— 18 method no-op stub(text 协议无 cursor 路径,update 走 D139 throw SQLFeatureNotSupportedException 或 silently no-op + rowUpdated 永返 0)
  - `lib/com/mysql/query.ss GeneratedKeyResultSet`(synthetic 单 row)— 同 stub,driver-internal 类型 update 永 no-op
  - `lib/com/mysql/prepared.ss MysqlBinaryResultSet`(binary 协议)— Phase 4 真实现的占位 stub
  - `tests/d146_server_cursor/phase2_spike_test.ss NoopPreparedStatement / NoopResultSet`(D146 已建 mock)— 加 18 method stub(D025 vtable 强制 — 否则 phase2_spike_test bootstrap fail)
- spike `tests/d147_updatable_cursor/phase2_spike_test.ss` 纯本地无 docker mock NoopResultSet 18 method reachable + CONCUR_UPDATABLE 1008 常量 + Statement / Connection 接口 plumb concurrency 落 mock state
- §A.2 H1-H2 hidden assumption 部分实证(H1 Phase 1 已落 / H2 留 Phase 4 真 PK 解析)
- VCM 六验全 PASS:§1 工程(bootstrap 固定点 + baseline 不破)+ §2 行为(`grep -c "updateRow\|deleteRow\|insertRow\|moveToInsertRow\|cancelRowUpdates\|refreshRow\|rowUpdated\|rowDeleted\|rowInserted\|updateInt\|updateString\|updateLong\|updateBoolean\|updateDouble\|updateNull" lib/java/sql.ss` 实测 ≥16)+ §3 反向 + §4 边界 + §5 路线 + §6 根因
- baseline:reflection_health_linter no regressions / d_doc_index_linter F1 = 0 PASS

### Phase 3: SQL 模板生成器 + PK 解析最小子集 + unit test [ ] (2026-05-02)

- `lib/com/mysql/prepared.ss` 加 4 private helpers:
  - `buildUpdateRowSql(table: string, pkCol: string, dirtyCols: Array<string>): string` — 返 `UPDATE table SET col1=?, col2=? WHERE pk=?` placeholder SQL
  - `buildDeleteRowSql(table: string, pkCol: string): string` — 返 `DELETE FROM table WHERE pk=?`
  - `buildInsertRowSql(table: string, cols: Array<string>): string` — 返 `INSERT INTO table(col1, col2) VALUES (?, ?)`
  - `buildRefreshRowSql(table: string, pkCol: string, cols: Array<string>): string` — 返 `SELECT col1, col2 FROM table WHERE pk=?`
- `lib/com/mysql/query.ss` 加 column def packet `org_table` + `flags` 字段解析(MySQL Native Protocol §6.6 — 现 columnDefName / columnDefColType 范式延续 line 269-277 加 columnDefOrgTable / columnDefFlags)
- `lib/com/mysql/prepared.ss` 加 `derivePkColumn(colMetadata: Array<Map>): string` private helper — 扫 colMetadata flags & 0x0002(PRI_KEY_FLAG)bit 1 返第一个 PK 字段名;无 PK / 多 PK 返 ""(空串触发 H2 失败回路 SQLFeatureNotSupportedException)
- `lib/com/mysql/prepared.ss` 加 `deriveTableName(colMetadata: Array<Map>): string` private helper — 取 colMetadata[0].orgTable(单表 SELECT 范式)
- spike unit test `tests/d147_updatable_cursor/phase3_sql_template_unit_test.ss` 纯本地无 docker — 4 builder 字符串拼接覆盖(空 dirtyCols / 1 col / 多 col / 含 SQL 关键字 col 名 escape 边界 + buildInsertRowSql 多 col VALUES placeholder count + derivePkColumn 单 PK / 多 PK 返 "" / 无 PK 返 "" / deriveTableName 多 col 同 orgTable / 多表 join 不同 orgTable 返第一个)
- §A.2 H2 hidden assumption 实证(SELECT meta column def packet flags PRI_KEY_FLAG bit 1 解析,单表单 PK 场景)
- VCM 六验全 PASS:§1 工程 + §2 行为(`grep -c "buildUpdateRowSql\|buildDeleteRowSql\|buildInsertRowSql\|buildRefreshRowSql\|derivePkColumn\|deriveTableName" lib/com/mysql/prepared.ss` 实测 ≥6)+ §3 反向 + §4 边界 + §5 路线 + §6 根因
- baseline:reflection_health_linter no regressions / d_doc_index_linter F1 = 0 PASS

### Phase 4: MysqlBinaryResultSet driver-side updatable cursor 真实现 + spike GREEN [ ] (2026-05-02)

- `lib/com/mysql/prepared.ss MysqlBinaryResultSet` 加 6 字段(D146 Phase 3 已落 7 字段 useCursor / fetchSize / cursorExhausted / statementId / cachedRows / cachedIdx / rsType,本 D 加 6 字段共 13):`pendingUpdates: Map<string, string>` / `pendingInserts: Array<Map>` / `tableName: string` / `pkColumn: string` / `inInsertMode: int` / `rowState: int`(0=clean / 1=updated / 2=deleted / 3=inserted)
- `MysqlBinaryResultSet` 加 readQueryResultSetBinary 调用初始化 tableName + pkColumn(从 colMetadata 调 deriveTableName + derivePkColumn 设字段)
- `MysqlBinaryResultSet.updateInt / updateString / updateLong / updateBoolean / updateDouble / updateNull` 6 setter — 写 pendingUpdates(inInsertMode=0)或 pendingInserts(inInsertMode=1,追加到末尾 Array element)
- `MysqlBinaryResultSet.updateRow` — fresh PreparedStatement 走 buildUpdateRowSql + 经 fd 的 Connection 复用(MysqlPreparedStatement.executeUpdate D136 范式)+ 验 affected_rows == 1 否则 throw SQLException(NOT FOUND)+ rowState=1 + 清 pendingUpdates
- `MysqlBinaryResultSet.deleteRow` — fresh PreparedStatement 走 buildDeleteRowSql + 经 fd 复用 + 验 affected_rows == 1 + rowState=2
- `MysqlBinaryResultSet.insertRow` — fresh PreparedStatement 走 buildInsertRowSql + 经 fd 复用 pendingInserts.last() 字段 + 验 affected_rows == 1 + rowState=3 + 清 pendingInserts.last() / pop
- `MysqlBinaryResultSet.cancelRowUpdates` — 清 pendingUpdates Map(inInsertMode=0)或清 pendingInserts.last()(inInsertMode=1)+ rowState=0
- `MysqlBinaryResultSet.refreshRow` — fresh PreparedStatement 走 buildRefreshRowSql + 经 fd 复用 + 重读字段镜像 currentRow Array 字段
- `MysqlBinaryResultSet.moveToInsertRow` — inInsertMode=1 + pendingInserts.push(new Map())预留 insert row
- `MysqlBinaryResultSet.moveToCurrentRow` — inInsertMode=0
- `MysqlBinaryResultSet.rowUpdated` — 返 (rowState == 1) ? 1 : 0
- `MysqlBinaryResultSet.rowDeleted` — 返 (rowState == 2) ? 1 : 0
- `MysqlBinaryResultSet.rowInserted` — 返 (rowState == 3) ? 1 : 0
- `MysqlBinaryResultSet.next()` — 在 D146 三分支(cache forward / cursor refill / legacy streaming)前加 rowState=0 reset(每 next() 进入新 row 时 rowState 重置担保 H7)
- spike `tests/d147_updatable_cursor/phase4_spike_test.ss` 5 case docker probe-skip 范式延续 d138/d139/d146 — Case 1 updateRow + 验外部 SELECT 验值(H3 fresh PS 同 fd 复用 + cursor 不破)/ Case 2 deleteRow + 验外部 SELECT COUNT==0 / Case 3 moveToInsertRow + insertRow + 验外部 SELECT 找新 row(H6)/ Case 4 cancelRowUpdates 后 updateRow no-op + rowUpdated==0(H4)/ Case 5 refreshRow 后字段镜像同步外部 update(H5)
- §A.2 H3-H7 hidden assumption 全实证(H3 fresh PS 同 fd 复用 cursor 不破 / H4 cancelRowUpdates 纯 client-side / H5 refreshRow 走 fresh PS SELECT WHERE pk / H6 moveToInsertRow + insertRow / H7 rowState 真实 track + 每 next() reset)
- VCM 六验全 PASS:§1 工程 + §2 行为(`grep -c "pendingUpdates\|pendingInserts\|inInsertMode\|rowState\|tableName\|pkColumn" lib/com/mysql/prepared.ss` 实测 ≥18)+ §3 反向 + §4 边界(5 case 含 updateRow 单字段 / 多字段 / NOT FOUND throw / insertRow VALUES 多 col / cancelRowUpdates 后 updateRow no-op / refreshRow 与外部 update 竞争同步)+ §5 路线 + §6 根因
- baseline:reflection_health_linter no regressions / d_doc_index_linter F1 = 0 PASS

### Phase 5: 7 形态 integration_test.ss + Spring RowCallbackHandler 内 updateRow demo + absorb spike + 全 Phase 收关 + D147 主线 close [ ] (2026-05-02)

- `tests/d147_updatable_cursor/integration_test.ss` 7 case e2e 全形态覆盖 — Case 1 CONCUR_READ_ONLY default 兼容(D146 baseline 不破)/ Case 2 CONCUR_UPDATABLE + setFetchSize(N) cursor 协议 flags=0x02(packet log 实证)/ Case 3 updateRow + 外部 SELECT 验值 + rowUpdated==1 / Case 4 deleteRow + 外部 SELECT COUNT==0 + rowDeleted==1 / Case 5 moveToInsertRow + insertRow + 外部 SELECT 找新 row + rowInserted==1 / Case 6 cancelRowUpdates + refreshRow 双重(H4+H5)/ Case 7 cursor lifecycle SQLException(unique 冲突 / NOT NULL 违反)走 D139 SQLExceptionTranslator → DataIntegrityViolationException + 子类 catch hierarchy + cause.sqlState=23000 / 23505 + cause.errorCode=1062 / 1452 wire-protocol 字段全保留
- Spring RowCallbackHandler demo:Case 8(可选)JdbcTemplate.query(sql, RowCallbackHandler) 内 callback.processRow 内 rs.updateInt + rs.updateRow 走 driver-side 模拟 — 验 ORM Hibernate 流式更新 idiom 复用
- absorb 决策:删 Phase 1+3+4 spike(7 case 吸收覆盖)— 保留 phase1_packet_unit_test.ss(协议层常量值 byte-level)+ phase3_sql_template_unit_test.ss(SQL 模板拼接 byte-level)互补无重叠(D139 / D146 范式延续 — 协议层反查表 vs 业务层 catch chain split)
- §A.2 H1-H7 全实证锚 — 收关
- 全 Phase 0-5 commit hash 6 个总览(Phase 0 `dd038c1` / Phase 1 `<Phase 1 commit>` / Phase 2 `<Phase 2 commit>` / Phase 3 `<Phase 3 commit>` / Phase 4 `<Phase 4 commit>` / Phase 5 `<Phase 5 commit>` 本)
- D147 主线 close — 等用户分流下一 SQL 主线 sub-D(D138 §F4 NamedParameterJdbcTemplate / D138 §F6 HikariCP Connection Pool / D138 §F7 batchUpdate + BatchUpdateException / D146 §F2 holdability / D146 §F3 ResultSetMetaData)

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | updateXxx 6 setter 扩展类型(BigDecimal / Timestamp / Date / Time / Bytes / Float / Short / Byte) | 本 D 仅 6 核心类型(int / string / long / boolean / double / null);JDBC 4.3 §15.2.5 全 SQL type setter ≥18 method,扩展类型留独立 sub-D 或合入 D146 §F3 ResultSetMetaData |
| F2 | SELECT FOR UPDATE 行锁 + RR isolation level + InnoDB lock wait timeout | SQL standard `SELECT ... FOR UPDATE` 行锁与 cursor 正交独立 sub-D — RR isolation level + InnoDB Gap Lock + lock wait timeout 调优监控完整;本 D scope 限 driver-side 模拟 cursor,锁路径独立 |
| F3 | multi-PK / 多表 join updatable cursor | 本 D Phase 3 derivePkColumn 仅最小子集(单表 SELECT 单 PK)— multi-PK 复合主键 + 多表 join updatable view 走 SHOW INDEX / INFORMATION_SCHEMA.KEY_COLUMN_USAGE 完整 PK 推导 + multi-table updatable cursor 留独立 sub-D 或合入 D146 §F3 ResultSetMetaData |
| F4 | SQL standard `WHERE CURRENT OF cursor_name` named cursor + UPDATE/DELETE WHERE CURRENT OF | SQL standard SQL/PSM cursor name + `UPDATE table WHERE CURRENT OF cursor_name` 语法(MySQL 不支持 — 仅 stored procedure 内 DECLARE CURSOR);留独立 sub-D 或合入 D146 §F4 |
| F5 | PostgreSQL `WHERE CURRENT OF cursor_name` 切换路径 | D107+ PostgreSQL driver 起首时 PostgreSQL 原生支持 `UPDATE/DELETE WHERE CURRENT OF cursor_name` SQL standard 路径;与 MySQL driver-side 模拟范式不同,driver 适配独立 — 留 D107+ |
| F6 | savepoint integration cursor + transaction 跨 statement 复用(autoCommit=false) | cursor lifecycle 跨 setAutoCommit(false) → multiple updateRow → SAVEPOINT / ROLLBACK TO SAVEPOINT cancelRowUpdates 深度集成;D137 per-call Connection vs cursor 跨 statement 复用矛盾 — 留独立 sub-D 或合入 D146 §F7 + HikariCP D138 §F6 |
| F7 | server-side updatable cursor MySQL 8.0+ MERGE_ENABLE_UPDATABLE 协议升级 | MySQL 5.7- / 8.0 默认无 server-side SQL standard updatable cursor;未来 MySQL MERGE_ENABLE_UPDATABLE 标志若启用 → server-side updatable cursor 协议 + 删 driver-side 模拟 fallback — 留独立 sub-D |

---

## Status 时间线

- 2026-05-02 Phase 0 D 文档落档(commit `dd038c1`)— D146 §Followup F1 + D146 §A.3 废案 C3 起首落档,走完整 JDBC 4.3 §15 ResultSet Update + MySQL CURSOR_TYPE_FOR_UPDATE 0x02 + driver-side updatable cursor 模拟(MySQL Connector/J 5.0+ 范式延续);**§核心目标 7 判据**(Case 1 CONCUR_READ_ONLY default 兼容 / Case 2 CONCUR_UPDATABLE + cursor flags=0x02 / Case 3 updateRow / Case 4 deleteRow / Case 5 moveToInsertRow + insertRow / Case 6 cancelRowUpdates + refreshRow / Case 7 cursor lifecycle SQLException 走 D139 DataIntegrityViolationException);**§A.2 H1-H7 假设挑战**(H1 server flags=0x02 行为同 0x01 driver 模拟 / H2 SELECT meta column def flags PRI_KEY_FLAG / H3 fresh PS 同 fd 复用 cursor 不破 / H4 cancelRowUpdates 纯 client-side / H5 refreshRow 走 fresh PS SELECT WHERE pk / H6 moveToInsertRow + insertRow + inInsertMode 切换 / H7 rowState 真实 track + 每 next() reset);**§A.3 废案 7 条**(C1 数据层 patch / C3 架构层 + SELECT FOR UPDATE / 客户端手写 UPDATE / SAVEPOINT 替代 cancelRowUpdates / moveToInsertRow 走单独 INSERT / SELECT FOR UPDATE 替代 / rowUpdated 全返 false);**Phase 0-5 计划草案 6 phase**(Phase 1 协议层常量 + spike / Phase 2 JDBC 18 method + 4 implementor stub + spike mock / Phase 3 SQL 模板生成器 + PK 解析 + unit test / Phase 4 MysqlBinaryResultSet driver-side 真实现 + spike / Phase 5 7 形态 integration_test e2e + absorb spike + 全 Phase 收关);**Followup 7 条**(F1 updateXxx 扩展类型 / F2 SELECT FOR UPDATE 行锁独立 sub-D / F3 multi-PK 多表 join / F4 SQL standard WHERE CURRENT OF / F5 PostgreSQL 路径 / F6 savepoint cursor 跨 transaction / F7 MySQL 8.0+ server-side updatable);**baseline**:d_doc_index_linter F1 = 0 PASS(D147 加入未破 referenced Ds — D025/D134/D136/D137/D138/D139/D146 实存)+ next_prompt_ultrathink_linter PASS(下轮提示词含 ultrathink 关键字);Phase 0 hash 留 `dd038c1` placeholder 待下轮 Phase 1 commit 时回填 4 处(Status header line 3 + §Phase 收关锚 §Phase 0 mark Done at commit + Phase 5 §全 Phase 0-5 commit hash 总览 + 本 Status 时间线 Phase 0 entry);**等下轮 Phase 1 协议层 CURSOR_TYPE_FOR_UPDATE 0x02 + CONCUR_UPDATABLE 1008 常量 + deriveCursorFlag concurrency=CONCUR_UPDATABLE 分支 + spike unit test + docker spike(在线时验 server flags=0x02 接受不 reject + 后续 fetch 行为同 0x01)+ §A.2 H1 hidden assumption 实证 + Phase 0 hash 回填**
- 2026-05-02 Phase 1 协议层 CURSOR_TYPE_FOR_UPDATE 0x02 + CONCUR_UPDATABLE 1008 + deriveCursorFlag 分支(commit `<Phase 1 commit>`)— `lib/com/mysql/query.ss CURSOR_TYPE_FOR_UPDATE = 0x02` 常量(MySQL Native Protocol §6.5.1 COM_STMT_EXECUTE flags i8 bit 1 — 同 D146 §A.2 H2 已落 0x00 NO_CURSOR / 0x01 READ_ONLY 范式延续)+ `lib/java/sql.ss CONCUR_UPDATABLE = 1008` 常量(JDBC 4.3 §java.sql.ResultSet.CONCUR_UPDATABLE 标准整数值;D146 Phase 2 已落 CONCUR_READ_ONLY 1007)+ `lib/com/mysql/prepared.ss MysqlPreparedStatement.deriveCursorFlag` 加 concurrency=CONCUR_UPDATABLE 分支返 CURSOR_TYPE_FOR_UPDATE 0x02(优先于 D146 type+fetchSize 路径 — driver-side updatable cursor 独立于 server-cursor batching,即使 setFetchSize(100) flag 仍 0x02)+ deriveCursorFlag private → public 解锁 unit test 双语义验证(同 setFetchSize / setCursorMode driver-specific public method 范式)+ MysqlPreparedStatement concurrency 字段注释更新(D146 informational only → D147 plumbed by setCursorMode read by deriveCursorFlag)+ `tests/d147_updatable_cursor/phase1_packet_unit_test.ss` 7/7 GREEN(常量值 0x02 / 1008 + 常量互不相等 + deriveCursorFlag 6 case 双语义覆盖:CONCUR_UPDATABLE → 0x02 / CONCUR_READ_ONLY+fetchSize=0 → NO_CURSOR / CONCUR_READ_ONLY+fetchSize>0 → READ_ONLY / unknown 0 fall through 双子 case fetchSize=0 / fetchSize>0 / scrollable+UPDATABLE concurrency wins over type)+ `tests/d147_updatable_cursor/phase1_spike_test.ss` docker probe-skip 范式延续 d138/d139/d146-phase1(127.0.0.1:3307 不可达 → println + return 离线零阻塞)— 在线时 1/1 GREEN — sendCursorExecuteForUpdate 自定义 10 字节 0-param payload(同 D146 phase1_spike sendCursorExecuteZeroParam 范式但 flags=0x02)+ PREPARE SELECT id, val FROM phase1_d147 + EXECUTE flags=0x02 + drainExecuteResponse EOF CURSOR_EXISTS 必置 / LAST_ROW_SENT 必清 + FETCH(5) + drainFetchResponse 5 rows + EOF LAST_ROW_SENT 必置 / CURSOR_EXISTS 必清 + COM_STMT_CLOSE;**§A.2 H1 实证**(server flags=0x02 接受不返 ERR + 后续 fetch 行为同 0x01 — driver 模拟范式 MySQL Connector/J 5.0+ `UpdatableResultSet` 落地基础,server 实际行为 0x02 ≡ 0x01 MySQL 5.7+ doc 明确);**baseline**:./build.sh bootstrap 三阶段固定点 stage2==stage3 GREEN + bin/ss test tests/ baseline 净 +1 passed phase1_packet_unit_test 纯本地 / +1 fail phase1_spike_test docker 离线(同 D146 phase1_spike fallback skip 范式 — 用户口令明示本环境 docker daemon stuck testss-mysql 不可达)+ reflection_health_linter no regressions(本 Phase 不动 bootstrap/ → 14 指标全继承 Phase 0 baseline)+ d_doc_index_linter F1 = 0 PASS + next_prompt_ultrathink_linter PASS;Phase 1 hash 留 `<Phase 1 commit>` placeholder 待下轮 Phase 2 commit 时回填 4 处(Status header line 3 + §Phase 收关锚 §Phase 1 mark Done at commit + Phase 5 §全 Phase 0-5 commit hash 总览 Phase 1 行 + 本 Status 时间线 Phase 1 entry);**等下轮 Phase 2 JDBC ResultSet update*/state 18 method**(updateRow / deleteRow / insertRow / cancelRowUpdates / refreshRow / moveToInsertRow / moveToCurrentRow / rowUpdated / rowDeleted / rowInserted 10 row-level + updateInt / updateString / updateLong / updateBoolean / updateDouble / updateNull 6 column-level setter)+ 4 ResultSet implementor 降级 stub + spike mock GREEN + Phase 1 hash 回填
