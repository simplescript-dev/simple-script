# D146: Server-Side Cursor + Scrollable ResultSet — 完整 JDBC 4.3 §15 ResultSet + MySQL COM_STMT_FETCH + Spring RowCallbackHandler

**Status:** [✓] Phase 0 D 文档落档 at commit `<Phase 0 commit>` + [ ] Phase 1 协议层 COM_STMT_FETCH + CURSOR_TYPE_READ_ONLY + EOF flag SERVER_STATUS_CURSOR_EXISTS / LAST_ROW_SENT + spike GREEN + [ ] Phase 2 JDBC ResultSet TYPE_SCROLL_* + CONCUR_* 常量 + setFetchSize / getFetchSize + Statement.executeQuery(sql, type, concurrency) / Connection.prepareStatement(sql, type, concurrency) 重载 + spike GREEN + [ ] Phase 3 MySQL MysqlBinaryResultSet 完整 cursor 协议升级 + 协议层 throw SQLException(D139 范式延续)+ spike GREEN + [ ] Phase 4 Spring JdbcTemplate.query(sql, RowCallbackHandler) 重载 + setFetchSize 双语义(client Integer.MIN_VALUE row streaming vs server-side cursor N rows)+ spike GREEN + [ ] Phase 5 7 形态 integration_test.ss + absorb spike + 全 Phase 收关 + D146 主线 close — D138 §Followup F3 + §A.3 废案 §C3 cursor 部分起首落档;走**完整 JDBC 4.3 §15 ResultSet 标准**(TYPE_FORWARD_ONLY / TYPE_SCROLL_INSENSITIVE / TYPE_SCROLL_SENSITIVE 3 type + CONCUR_READ_ONLY 1 concurrency + setFetchSize / getFetchSize / absolute / first / last / previous / next 全 method)+ **完整 MySQL `COM_STMT_FETCH` 0x1c 协议**(statement_id i32 LE + num_rows u32 LE 9 bytes packet + CURSOR_TYPE_READ_ONLY 0x01 在 COM_STMT_EXECUTE flags + EOF SERVER_STATUS_CURSOR_EXISTS 0x0040 / LAST_ROW_SENT 0x0080)+ **完整 Spring RowCallbackHandler 流式**(`processRow(rs: ResultSet): void` 单 method interface + JdbcTemplate.query(sql, RowCallbackHandler) 重载 + setFetchSize 双语义),不走 client-side LIMIT N OFFSET M 自分页 workaround(用户对话锁 D135-D139 SQL 主线范式延续 — 完整子类 + 不接受次优 / workaround / 节省)。**SS 当前 streaming = client-side**(`lib/com/mysql/query.ss:315-318 MysqlResultSet : ResultSet` next() 逐行读 socket buffer / `lib/spring/jdbc.ss:294 queryForList(sql): ResultSet` 返流式)— **但协议层 cursor flag 缺**(MysqlPreparedStatement.executeQuery flags = 0x00 无 CURSOR_TYPE_READ_ONLY 0x01)→ **server 仍预 buffer 全 result set**,大表 prepared SELECT server thread state 挂起 + socket flow control 阻塞;升级 server-side cursor 后 server 按 fetchSize N rows window 按需 fetch 不预 buffer 全集。范畴限 server-side READ_ONLY cursor + scrollable in-memory cache(MySQL Connector/J 范式 — server 协议不支持 scrollable cursor MySQL 5.7+);**Updatable cursor**(CURSOR_TYPE_FOR_UPDATE 0x02 + CONCUR_UPDATABLE / updateRow / cancelRowUpdates / rowDeleted / rowInserted)scope 超 sub-D 留 **D147+ 独立 sub-D**;**holdability** HOLD_CURSORS_OVER_COMMIT / CLOSE_CURSORS_AT_COMMIT 常量留 §Followup F2;**ResultSetMetaData** 完整列元数据(getColumnCount / getColumnName / getColumnTypeName)留 §Followup F3;**SQL standard DECLARE CURSOR / FETCH CURSOR_NAME** stored procedure 留 §Followup F4;**PostgreSQL DECLARE CURSOR + FETCH** 切换路径留 D107+ PostgreSQL driver。

**Depends on:**
- D025(interface dispatch — class extends ResultSet 走 vtable indirect dispatch — MysqlBinaryResultSet 升级 cursor 协议路径走同 vtable)
- D134(MySQL wire protocol — COM_STMT_FETCH 0x1c command byte + statement_id i32 LE + num_rows u32 LE packet 编码 + EOF SERVER_STATUS_CURSOR_EXISTS 0x0040 / LAST_ROW_SENT 0x0080 状态 flag)
- D136(prepared statement — server-side cursor MySQL 5.7+ 仅 prepared statement 支持,普通 Statement 走 COM_QUERY 0x03 不支持 cursor;MysqlPreparedStatement.executeQuery flags 字段 i8 第 5 bit 加 CURSOR_TYPE_READ_ONLY 0x01)
- D137(JdbcTemplate retcon — query / queryForXxx 上层入口,Phase 4 加 query(sql, RowCallbackHandler) 重载)
- D138(generated keys 范式 — Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环;§Followup F3 锚起首)
- D139(SQL exception hierarchy — Phase 1+ 协议层 throw SQLException 范式延续;cursor lifecycle 期间 ERR packet 走 SQLExceptionTranslator)
- `lib/com/mysql/query.ss:315-318 MysqlResultSet : ResultSet`(client-side streaming next() 现状,Phase 3 升级 cursor 协议路径)
- `lib/com/mysql/prepared.ss:373-376 MysqlBinaryResultSet : ResultSet`(prepared statement binary protocol streaming 现状,Phase 3 升级 cursor)
- `lib/com/mysql/prepared.ss MysqlPreparedStatement.executeQuery`(flags = 0x00 现状,Phase 1 加 CURSOR_TYPE_READ_ONLY 0x01)
- `lib/java/sql.ss ResultSet interface`(Phase 2 加 TYPE_SCROLL_* / CONCUR_* 常量 + setFetchSize / getFetchSize / absolute / first / last / previous + Statement.executeQuery / Connection.prepareStatement type + concurrency 重载)
- `lib/spring/jdbc.ss:5,157,294 queryForList aliases ResultSet`(streaming 现状,Phase 4 加 query(sql, RowCallbackHandler) 重载 + setFetchSize 双语义入口)
- CLAUDE.md §Java/TS 语法优先(Java JDBC `java.sql.ResultSet` + Spring `RowCallbackHandler` 是主线;TS 不直接对应,JDBC + Spring 标准为准)
- CLAUDE.md §Root Cause 优先 第一法则(本 D 用户对话锁:**完整 §15 + 完整 COM_STMT_FETCH + 完整 RowCallbackHandler,不接受次优 / workaround / 节省**)
- `memory/feedback_root_cause_no_cost.md`(成本不是次优排序依据)
- `memory/feedback_no_derive_workaround.md`(主线能力缺口不允许 LIMIT 自分页 / fetchSize hint setter 不走协议 等替代)

**Date:** 2026-05-02
**Last Updated:** 2026-05-02

---

## 核心目标 (Goal)

- **为什么**:
  - **协议层 cursor flag 缺,server 预 buffer 全 result set**:`lib/com/mysql/prepared.ss MysqlPreparedStatement.executeQuery` flags = 0x00 无 `CURSOR_TYPE_READ_ONLY` 0x01,server 一次性发 ResultSet 全部 rows packet 到 socket buffer。SS 当前 client-side streaming(`lib/com/mysql/query.ss:315-318 MysqlResultSet` next() 逐行读 socket / `lib/com/mysql/prepared.ss:373-376 MysqlBinaryResultSet` 同 streaming / `lib/spring/jdbc.ss:5,157,294 queryForList aliases ResultSet`)**只是 client 端逐行读 socket**,server 端仍持全 result set,大表 prepared SELECT(1M+ rows)server thread state 挂起 + socket flow control 阻塞。
  - **JDBC 4.3 §15 ResultSet `setFetchSize / TYPE_SCROLL_* / scrollable` spec 全缺**:`lib/java/sql.ss ResultSet interface` 当前仅 forward-only `next() / close() / getInt / getString / getLong` 等基础 method,缺 `TYPE_FORWARD_ONLY / TYPE_SCROLL_INSENSITIVE / TYPE_SCROLL_SENSITIVE 3 type` + `CONCUR_READ_ONLY 1 concurrency` 常量 + `setFetchSize / getFetchSize` + `absolute / first / last / previous` scrollable 多向定位 + `Statement.executeQuery(sql, type, concurrency) / Connection.prepareStatement(sql, type, concurrency)` 重载。
  - **Spring `RowCallbackHandler` 流式 spec 缺**:`lib/spring/jdbc.ss` 当前仅 queryForList 返 ResultSet aliases 流式入口,缺 `interface RowCallbackHandler { processRow(rs: ResultSet): void }` + `JdbcTemplate.query(sql, RowCallbackHandler)` 重载 + `setFetchSize` 双语义入口(client `Integer.MIN_VALUE = -2147483648` row streaming vs server-side cursor N rows 路径)。
  - **业务影响**:大表 prepared SELECT 走 setFetchSize(N) 后 server 仅持 N rows window 按需 fetch 的 ORM Hibernate ScrollableResults / MyBatis Cursor<T> 标准 idiom 全断链;scrollable absolute / previous 多向定位 ORM 列表分页(`page[i].setFirstResult(N).setMaxResults(M)`)走 LIMIT 自分页性能 O(N²)而非 cursor.absolute(N) 单跳。

- **是什么**:走**完整 JDBC 4.3 §15 ResultSet + MySQL COM_STMT_FETCH 0x1c server-side cursor + Spring RowCallbackHandler streaming**,**协议层升级 cursor flag + JDBC 接口完整 + Spring 流式入口**:
  - **协议层**:`COM_STMT_FETCH` 0x1c packet — i8(0x1c) + statement_id i32 LE + num_rows u32 LE = 9 bytes;`CURSOR_TYPE_READ_ONLY` = 0x01 在 `COM_STMT_EXECUTE` flags 字段 i8 第 5 bit;EOF `SERVER_STATUS_CURSOR_EXISTS` = 0x0040(server cursor 仍持 row,允许下一 fetch)/ `SERVER_STATUS_LAST_ROW_SENT` = 0x0080(cursor 耗尽,无 row 可 fetch);`MysqlBinaryResultSet` 加 cursor 字段(`useCursor: int`(0/1)+ `fetchSize: int` + `cursorExhausted: int`(0/1))+ next() 升级路径(useCursor=1 时 fetchSize 用尽走 COM_STMT_FETCH 重 fetch,cursorExhausted=1 时返 0 终止)+ close() 升级(server 端 cursor 释放走 COM_STMT_RESET 0x1a / 自然耗尽即释放)
  - **JDBC ResultSet 完整接口**(`lib/java/sql.ss`):
    - `interface ResultSet` 加 `setFetchSize(rows: int)` / `getFetchSize(): int` / `absolute(row: int): int`(0=未到行/1=成功)/ `first(): int` / `last(): int` / `previous(): int` / `getRow(): int`(当前 1-based row 序号,0=未定位)method
    - `ResultSet.TYPE_FORWARD_ONLY` = 1003 / `TYPE_SCROLL_INSENSITIVE` = 1004 / `TYPE_SCROLL_SENSITIVE` = 1005 / `CONCUR_READ_ONLY` = 1007 5 常量
    - `Statement.executeQuery(sql: string, type: int, concurrency: int): ResultSet` 重载;`Connection.prepareStatement(sql: string, type: int, concurrency: int): PreparedStatement` 重载
  - **MySQL ResultSet 升级**(`lib/com/mysql/prepared.ss MysqlBinaryResultSet`):
    - 加 `useCursor: int` / `fetchSize: int` / `cursorExhausted: int` 字段 + `statementId: int`(从 PreparedStatement 传入用于 COM_STMT_FETCH)
    - next() 升级:if useCursor=1 → 当前 row 已读完且 cursorExhausted=0 → 发 COM_STMT_FETCH(statementId, fetchSize) → server 返 N row packets + 终 EOF(检 SERVER_STATUS_CURSOR_EXISTS 0x0040 vs LAST_ROW_SENT 0x0080)→ 重 N rows window;cursorExhausted=1 时返 0
    - close() 升级:server cursor 释放 — server 自然在最后 EOF SERVER_STATUS_LAST_ROW_SENT 释放;client 中途 close 走 socket drain(D139 范式延续 — finally 担保 socket 不饥饿 + cursor close socket buffer)
    - scrollable absolute/first/last/previous in-memory cache 实现(MySQL 协议无 server scrollable cursor MySQL 5.7+ 限制)— TYPE_SCROLL_INSENSITIVE 时 next() 缓存读过 row 到 in-memory Array,absolute(N) 直接索引,previous() in-memory back-track
  - **Spring RowCallbackHandler streaming**(`lib/spring/jdbc.ss`):
    - `interface RowCallbackHandler { processRow(rs: ResultSet): void }` 单 method
    - `JdbcTemplate.query(sql: string, callback: RowCallbackHandler): void` 重载 — 内部 try / open ResultSet / while next() / callback.processRow(rs) / finally close(D139 try-finally 范式延续)
    - `JdbcTemplate.query(sql: string, setter: fn(PreparedStatement):void, callback: RowCallbackHandler): void` 重载(参数化 prepared statement 路径)
    - `setFetchSize` 双语义路径分支:client `Integer.MIN_VALUE = -2147483648` → 不走 server cursor,fallback client-side row streaming(MysqlBinaryResultSet useCursor=0 + 一次发完整 ResultSet,client 逐行读 socket — 当前现状路径);server-side N(N >= 1) → 走 COM_STMT_FETCH cursor 路径(useCursor=1)

- **单一判据**:7 形态 `tests/d146_server_cursor/integration_test.ss` 全 GREEN —
  - **Case 1**:TYPE_FORWARD_ONLY default 兼容(setFetchSize 不调时不动 D138/D139 现有 baseline,fallback client streaming 全过)
  - **Case 2**:setFetchSize(10) + 100 rows 表 → 协议层 docker MySQL `mysqld --general_log` 抓 packet log 实测 COM_STMT_FETCH 0x1c 触发 10 次(100 / 10 = 10 fetches + 终 LAST_ROW_SENT)
  - **Case 3**:scrollable absolute(50) / first / last / previous / next 多向定位(TYPE_SCROLL_INSENSITIVE in-memory cache 路径)
  - **Case 4**:cursor close 担保(client 中途 close 后 server 端 SHOW PROCESSLIST 无挂起 thread state)
  - **Case 5**:client-side `setFetchSize(Integer.MIN_VALUE)` 流式 forward-only — 不走 cursor 协议,client 逐行读 socket(双语义 H4)
  - **Case 6**:RowCallbackHandler 流式回调 — `JdbcTemplate.query(sql, callback)` 1000 rows 表 callback.processRow 调 1000 次
  - **Case 7**:cursor lifecycle SQL exception(网络断 / fetchSize 超大 server 拒)走 D139 SQLExceptionTranslator → DAE 子类 catch GREEN(D139 范式延续)

> 一句口号:**完整 JDBC §15 + COM_STMT_FETCH + RowCallbackHandler,server-side cursor 不预 buffer 全集**

---

## 核心原则 (Principles)

1. **完整 JDBC 4.3 §15 ResultSet 标准,不裁剪 forward-only / scrollable / setFetchSize 任一**:`TYPE_FORWARD_ONLY / TYPE_SCROLL_INSENSITIVE / TYPE_SCROLL_SENSITIVE` 3 type + `CONCUR_READ_ONLY` 1 concurrency 全实现;`setFetchSize / getFetchSize / absolute / first / last / previous / getRow` 全 method
2. **完整 MySQL `COM_STMT_FETCH` 0x1c 协议,不裁剪**:packet 编码 i8 + i32 LE + u32 LE 9 bytes 完整 + CURSOR_TYPE_READ_ONLY 0x01 flag 完整 + EOF SERVER_STATUS_CURSOR_EXISTS 0x0040 / LAST_ROW_SENT 0x0080 双 flag 完整解析
3. **完整 Spring `RowCallbackHandler` 流式标准,不裁剪**:`interface RowCallbackHandler { processRow(rs: ResultSet): void }` + `JdbcTemplate.query(sql, RowCallbackHandler)` 重载 + 参数化 prepared statement 重载
4. **setFetchSize 双语义路径分支显式**:client `Integer.MIN_VALUE = -2147483648` → MySQL Connector/J 标准 client-side row streaming 不走 cursor;server N(N >= 1)→ 走 COM_STMT_FETCH server cursor;两路径分立不混合,文档化分支 entry
5. **scrollable absolute/previous 走 in-memory cache MySQL Connector/J 范式**:MySQL 协议无 server scrollable cursor 支持(仅 forward-only READ_ONLY cursor)— TYPE_SCROLL_INSENSITIVE 时 next() 缓存读过 row 到 in-memory Array,absolute(N) 直接索引,previous() in-memory back-track;TYPE_SCROLL_SENSITIVE 同 INSENSITIVE 路径(MySQL 协议不区分,JDBC spec 允许 driver 选择)
6. **server-side cursor 仅 prepared statement,不动 Statement 路径**:MySQL 5.7+ doc 明确普通 Statement 走 COM_QUERY 0x03 不支持 server-side cursor — MysqlStatement.executeQuery 不动;MysqlPreparedStatement.executeQuery flags 字段第 5 bit 加 CURSOR_TYPE_READ_ONLY 0x01
7. **cursor close 担保 finally 路径,继承 D139 范式**:client 中途 close 走 socket drain + server cursor 释放;server 自然耗尽 SERVER_STATUS_LAST_ROW_SENT 释放;finally try-finally 嵌套继承 D139 §核心原则 8 + Phase 4 spike 范式
8. **cursor lifecycle SQL exception 走 D139 SQLExceptionTranslator**:cursor 期间 ERR packet(网络断 / server 掉 / fetchSize 超大)走 D139 ErrorPacket parse → SQLException 子类 → SQLExceptionTranslator → DAE 子类 throw;不重新设计 exception 路径
9. **per-call Connection 简化继承 D137**:JdbcTemplate.query(sql, RowCallbackHandler) 内部 try / open Connection / open PreparedStatement / open ResultSet / while next() / callback.processRow(rs) / finally close 链,per-call Connection 走 D137 范式(HikariCP D125+ 是另一 sub-D)
10. **Phase 计划独立 commit**:Phase 0-5 独立 commit;Phase 0 D 文档落档不打包 Phase 1+ 实施(D135/D136/D137/D138/D139 范式延续)
11. **7 形态测试覆盖 — 不偷工减料**:Phase 5 测试覆盖 §核心目标 7 判据全形态,含 forward-only default / setFetchSize cursor 协议触发 / scrollable absolute/previous / cursor close 担保 / client streaming 双语义 / RowCallbackHandler 流式 / cursor lifecycle exception
12. **SS 编译器扩仅按需(若 forward-ref 类似 D139 §A.2 H1 触发)**:Phase 0 不预判,Phase 1+ 实测 spike 走假设破裂回路 fallback,行为同 D139 §核心原则 9(byte-offset GEP / interface dispatch / 等已修扩点延续)

---

## A.1 主候选评估(§MNK §M §字段 10)

| 候选 | 层次 | 描述 | 优势 | 劣势 | 决策 |
|---|---|---|---|---|---|
| **C1** | **数据层 patch** | 仅 ResultSet / PreparedStatement 加 setFetchSize 占位 setter 不走协议 — fetchSize 字段保留但 executeQuery flags = 0x00 不变 | LOC 极小 ~30;实施快 | 不消除根因 — server-side cursor 协议层缺;server 仍预 buffer 全 result set;违反 §核心目标完整 spec(JDBC §15 + COM_STMT_FETCH + RowCallbackHandler) | **不选** — 用户对话锁:不接受次优 / workaround / 节省 |
| **C2** | **接口层 trap** | 完整 JDBC 4.3 §15 + MySQL COM_STMT_FETCH 0x1c + Spring RowCallbackHandler 标准:协议层 + JDBC 接口 + MySQL ResultSet + Spring 流式入口 + setFetchSize 双语义 + scrollable in-memory cache | 完整 spec;ORM Hibernate ScrollableResults / MyBatis Cursor<T> 标准 idiom 直接复用;PostgreSQL DECLARE CURSOR 未来切换零破坏(F5 §Followup) | LOC 中等 ~600(协议层 + JDBC 接口 + MySQL 实现 + Spring 流式 + 测试) | **选** — 用户对话锁:最优最佳 / 不 workaround;D135-D139 SQL 主线范式延续 |
| **C3** | **架构层 refactor** | + Updatable cursor(CURSOR_TYPE_FOR_UPDATE 0x02 + CONCUR_UPDATABLE / updateRow / cancelRowUpdates / rowDeleted / rowInserted)+ holdability(HOLD_CURSORS_OVER_COMMIT / CLOSE_CURSORS_AT_COMMIT)+ ResultSetMetaData(getColumnCount / getColumnName / getColumnTypeName / getColumnLabel)+ named cursor(SQL DECLARE CURSOR / FETCH CURSOR_NAME) | spec 100%;Hibernate / MyBatis 全 idiom 完整 | scope 远超 D146 单 sub-D(LOC > 1500;Updatable cursor 独立 sub-D + ResultSetMetaData + holdability + named cursor 全独立)| **不选** — scope 远超 D146 单 sub-D 范围;Updatable cursor 留 **D147+ 独立**;holdability + ResultSetMetaData + named cursor + DECLARE CURSOR 留 §Followup F2-F4 |

**决策行**:**选 C2 接口层 trap**(用户对话锁)— 因 (a) 完整 JDBC 4.3 §15 + MySQL COM_STMT_FETCH 0x1c + Spring RowCallbackHandler 标准消除根因(server-side cursor 协议层升级 + JDBC 接口完整 + Spring 流式入口);(b) ORM Hibernate ScrollableResults / MyBatis Cursor<T> 标准 idiom 直接复用,无 LIMIT 自分页 workaround;(c) PostgreSQL DECLARE CURSOR / FETCH 未来 driver 切换时 setFetchSize / RowCallbackHandler / scrollable spec 复用零破坏;(d) D135-D139 SQL 主线范式延续(协议层升级 + JDBC 接口扩 + Spring 入口 + 测试覆盖 + Phase 计划独立 commit)。**为何不选 C1**:用户对话锁不接受次优 / workaround / 节省路径。**为何不选 C3**:scope 远超 D146 单 sub-D,Updatable cursor 留 D147+ 独立 / holdability + ResultSetMetaData + named cursor + DECLARE CURSOR 留 §Followup F2-F4。

---

## A.2 隐藏假设挑战

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | COM_STMT_FETCH 0x1c packet 编码 statement_id i32 LE + num_rows u32 LE 是 MySQL 协议固定 | MySQL 5.7+ doc 明确 packet header byte 0x1c + 4 byte LE statement_id + 4 byte LE num_rows = 9 bytes payload;但 docker MySQL 8.0 / 5.7 实际 packet 解码偏移可能与 doc 误差 | Phase 1 docker MySQL `mysqld --general_log` 实测 client 发 9 bytes packet,server 返 N row packets + 终 EOF | packet 编码错 → 修 packet 写入 byte order / 字段 offset |
| H2 | CURSOR_TYPE_READ_ONLY 0x01 flag 在 COM_STMT_EXECUTE flags 字段 i8 第 5 bit | MySQL spec `COM_STMT_EXECUTE` flags i8 第 0 bit = CURSOR_TYPE_NO_CURSOR(0x00,默认)/ 第 0 bit = CURSOR_TYPE_READ_ONLY(0x01)/ 第 1 bit = CURSOR_TYPE_FOR_UPDATE(0x02)/ 第 2 bit = CURSOR_TYPE_SCROLLABLE(0x04 — MySQL 8.0 doc 标但实际不支持) | Phase 1 实测 docker MySQL flags=0x01 后 EOF 返 SERVER_STATUS_CURSOR_EXISTS 0x0040(无 rows packet,仅 EOF — server 持 cursor 等 fetch) | flag 编码错 → 修 flags 字段 bit;若 server 直接返 rows packet 无 cursor → MySQL 版本不支持 server cursor,Phase 1 走 H5 失败回路 |
| H3 | EOF flag SERVER_STATUS_CURSOR_EXISTS 0x0040 / SERVER_STATUS_LAST_ROW_SENT 0x0080 标 cursor 状态 | MySQL spec 明确 — CURSOR_EXISTS(server 仍持 row 允许下一 fetch)/ LAST_ROW_SENT(cursor 耗尽);两 flag 在 EOF packet status_flags 字段 i16 LE | Phase 1 实测 100 rows 表 fetchSize=10 → 前 9 fetch 后 EOF SERVER_STATUS_CURSOR_EXISTS 0x0040 / 第 10 fetch 后 EOF SERVER_STATUS_LAST_ROW_SENT 0x0080 | flag 检测错 → 修 EOF status_flags 解析;cursor 永不耗尽 → 死循环 protect 加 max 1000 fetch 上限 |
| H4 | setFetchSize Integer.MIN_VALUE = -2147483648 MySQL Connector/J 标准 client-side row streaming 双语义 | MySQL Connector/J doc 明确 — setFetchSize(Integer.MIN_VALUE) 触发 client-side 逐行读 socket 不走 server cursor;Connector/J 5.0.6+ 标准;非负 N 走 server cursor | Phase 4 实测 setFetchSize(Integer.MIN_VALUE)→ 无 COM_STMT_FETCH 0x1c packet,server 一次性发完整 ResultSet(client streaming = 现状路径) | 双语义假设破裂 → 简化为单语义 server cursor only,client streaming 路径走 setFetchSize(N >= 1)— 但违反 MySQL Connector/J 标准,Phase 4 文档化 |
| H5 | scrollable cursor MySQL 5.7+ 仅 forward-only READ_ONLY 支持,无 server scrollable | MySQL doc 明确 — `SHOW VARIABLES LIKE 'cursor%'` 无 scrollable cursor 变量;COM_STMT_EXECUTE flags 第 2 bit CURSOR_TYPE_SCROLLABLE 0x04 doc 标但实际不支持(server 返 ERR `CR_NOT_IMPLEMENTED`) | Phase 3 实测 docker MySQL 8.0 flags=0x04 → server ERR `CR_NOT_IMPLEMENTED` | 假设破裂 → fallback in-memory cache MySQL Connector/J 范式(TYPE_SCROLL_INSENSITIVE 时 next() 缓存 row 到 Array,absolute/previous in-memory back-track)— 已纳入 §核心原则 5 |
| H6 | cursor close finally 担保 socket 不饥饿 + server thread state 释放 | server 自然耗尽 SERVER_STATUS_LAST_ROW_SENT 0x0080 释放;client 中途 close 走 socket drain + COM_STMT_RESET 0x1a release(MySQL 协议 cursor reset / server-side 自动释放)| Phase 3 实测 docker MySQL `SHOW PROCESSLIST` cursor 中途 close 后 thread State 无 "Sending data" / "Sending to client" 挂起;100 rows 表 fetchSize=10 用 5 fetch 后 close,server thread State 释放 < 100ms | 假设破裂 → 修 close 路径,加 explicit COM_STMT_RESET 0x1a 命令(server 端强制 release);若 server 仍挂起 → ConnectionPool 范式延续 D139 finally close(D146 范畴内 per-call Connection 不入 pool) |

---

## A.3 废案

- **C1 数据层 patch / setFetchSize 占位 setter 不走协议**(用户对话锁不接受 — 不消除根因 + server 仍预 buffer 全 result set + 违反 JDBC §15 spec)
- **C3 架构层 refactor + Updatable cursor + holdability + ResultSetMetaData + named cursor**(scope 远超 D146 单 sub-D — Updatable cursor 留 **D147+ 独立 sub-D**;holdability + ResultSetMetaData + named cursor + DECLARE CURSOR 留 §Followup F2-F4)
- **客户端 LIMIT N OFFSET M 自分页**(性能 O(N²) 不接受 — 大表 OFFSET 100000 后 server 仍 scan 100000 rows 跳过;违反 cursor.absolute(N) 单跳标准 + 无 scrollable previous 支持)
- **走 ROWS BEFORE GROUP BY 分组分页**(违反 cursor 主线 — GROUP BY 分组与 cursor row-by-row 流式互斥;不属 D146 范畴)
- **简化 RowCallbackHandler 为 callback fn(rs)**(违反 Spring `interface RowCallbackHandler { processRow(rs) }` 标准 — Spring `@FunctionalInterface` SAM 转换在 SS 走 D025 vtable indirect dispatch,interface 比裸 fn 标准)
- **简化 setFetchSize 为单语义 server cursor only**(违反 MySQL Connector/J 标准 Integer.MIN_VALUE client-side row streaming 双语义)
- **scrollable absolute / previous 走 server scrollable cursor**(MySQL 5.7+ 协议无支持 H5;走 in-memory cache MySQL Connector/J 范式)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `<Phase 0 commit>` (2026-05-02)

- 本文档落档:Status / 核心目标 / 核心原则 / Depends on / §A.1 主候选 + §A.2 隐藏假设 + §A.3 废案 / Phase 0-5 计划草案 / Followup
- d_doc_index_linter F1 = 0 PASS(D146 加入未破 referenced Ds — D025/D134/D136/D137/D138/D139 实存)
- next_prompt_ultrathink_linter PASS(下轮提示词含 ultrathink 关键字)

### Phase 1: 协议层 COM_STMT_FETCH + CURSOR_TYPE_READ_ONLY + EOF flag + spike GREEN [ ]

- `lib/com/mysql/query.ss` 加 `COM_STMT_FETCH` 常量 = 0x1c + `CURSOR_TYPE_READ_ONLY` = 0x01 + `SERVER_STATUS_CURSOR_EXISTS` = 0x0040 / `SERVER_STATUS_LAST_ROW_SENT` = 0x0080(EOF status_flags i16 LE 第 6 bit / 第 7 bit)
- `lib/com/mysql/query.ss` 加 `writeStmtFetchPacket(fd, statementId, numRows): int` — i8(0x1c) + statement_id i32 LE + num_rows u32 LE = 9 bytes payload + MySQL packet header(3 bytes payload length + 1 byte sequence id)
- spike `tests/d146_server_cursor/phase1_spike_test.ss` — docker MySQL 简单 prepared SELECT + flags=0x01 + COM_STMT_FETCH 1 次 + EOF status_flags 解析 GREEN(`mysqld --general_log` 抓 packet log 实证)
- D139 范式延续:ERR packet 走 D139 ErrorPacket → SQLException → DAE 子类 throw

### Phase 2: JDBC ResultSet TYPE_SCROLL_* + CONCUR_* + setFetchSize + executeQuery 重载 + spike GREEN [ ]

- `lib/java/sql.ss` 加 `ResultSet.TYPE_FORWARD_ONLY` = 1003 / `TYPE_SCROLL_INSENSITIVE` = 1004 / `TYPE_SCROLL_SENSITIVE` = 1005 / `CONCUR_READ_ONLY` = 1007 5 常量
- `lib/java/sql.ss interface ResultSet` 加 `setFetchSize(rows: int)` / `getFetchSize(): int` / `absolute(row: int): int` / `first(): int` / `last(): int` / `previous(): int` / `getRow(): int` 7 method
- `lib/java/sql.ss interface Statement` 加 `executeQuery(sql: string, type: int, concurrency: int): ResultSet` 重载;`interface Connection` 加 `prepareStatement(sql: string, type: int, concurrency: int): PreparedStatement` 重载
- spike `tests/d146_server_cursor/phase2_spike_test.ss` — JDBC 接口 mock impl(纯本地无 docker)走完整方法签名 GREEN

### Phase 3: MySQL ResultSet 完整 cursor 协议升级 + scrollable in-memory cache + spike GREEN [ ]

- `lib/com/mysql/prepared.ss MysqlBinaryResultSet` 加 `useCursor: int` / `fetchSize: int` / `cursorExhausted: int` / `statementId: int` 字段
- `MysqlBinaryResultSet.next()` 升级 — useCursor=1 时 fetchSize 用尽走 COM_STMT_FETCH 重 fetch + cursorExhausted=1 时返 0
- `MysqlBinaryResultSet.close()` 升级 — server 自然耗尽 / client 中途 close socket drain
- `MysqlBinaryResultSet` 加 `cachedRows: Array<Row>` + scrollable absolute(N) / first / last / previous in-memory cache 实现(TYPE_SCROLL_INSENSITIVE / TYPE_SCROLL_SENSITIVE)
- `MysqlPreparedStatement.executeQuery(sql, type, concurrency): ResultSet` 重载 — type=TYPE_FORWARD_ONLY + concurrency=CONCUR_READ_ONLY 时 flags=0x00(client streaming);type=TYPE_FORWARD_ONLY + fetchSize > 0 时 flags=0x01(server cursor);type=TYPE_SCROLL_* 时 in-memory cache + flags=0x01
- 协议层 throw SQLException 范式延续 D139 — cursor lifecycle ERR packet 走 D139 ErrorPacket → SQLExceptionTranslator → DAE
- spike `tests/d146_server_cursor/phase3_spike_test.ss` — 100 rows 表 + setFetchSize(10) + 10 fetch GREEN(docker MySQL packet log 实证 COM_STMT_FETCH 触发 10 次)

### Phase 4: Spring JdbcTemplate.query(sql, RowCallbackHandler) + setFetchSize 双语义 + spike GREEN [ ]

- `lib/spring/jdbc.ss` 加 `interface RowCallbackHandler { processRow(rs: ResultSet): void }`
- `lib/spring/jdbc.ss JdbcTemplate.query(sql: string, callback: RowCallbackHandler): void` 重载 — 内部 try / open Connection / open PreparedStatement / open ResultSet / while next() / callback.processRow(rs) / finally close(D139 try-finally 范式延续)
- `JdbcTemplate.query(sql: string, setter: fn(PreparedStatement):void, callback: RowCallbackHandler): void` 参数化 prepared statement 重载
- `setFetchSize` 双语义路径分支 — client `Integer.MIN_VALUE = -2147483648` → MysqlBinaryResultSet useCursor=0 client streaming;server-side N(N >= 1)→ useCursor=1 server cursor
- spike `tests/d146_server_cursor/phase4_spike_test.ss` — 1000 rows 表 + setFetchSize(100) + RowCallbackHandler.processRow 调 1000 次 GREEN(docker MySQL packet log 实证 COM_STMT_FETCH 触发 10 次)

### Phase 5: 7 形态 integration_test.ss + 全 Phase 收关 + D146 主线 close [ ]

- `tests/d146_server_cursor/integration_test.ss` 7 case e2e:Case 1 TYPE_FORWARD_ONLY default / Case 2 setFetchSize(10) + 100 rows + 协议层 COM_STMT_FETCH 10 次 / Case 3 scrollable absolute/first/last/previous / Case 4 cursor close 担保 + SHOW PROCESSLIST 无挂起 / Case 5 setFetchSize(Integer.MIN_VALUE) client streaming / Case 6 RowCallbackHandler 1000 rows 流式 / Case 7 cursor lifecycle exception 走 D139 SQLExceptionTranslator
- absorb 决策:删 Phase 1/2/3/4 spike(Case 1-7 吸收覆盖,主轴 vs spike 重叠维护负担消除);保留 phase2 / phase4 纯本地无 docker 部分(若有 — 协议层反查表 vs 业务层 catch chain 互补无重叠 D139 范式)
- 全 Phase 0-5 commit hash 6 个总览(Phase 0 `<Phase 0 commit>` / Phase 1 `<Phase 1 commit>` / ... / Phase 5 `<Phase 5 commit>`)
- D146 主线 close — 等用户分流下一 SQL 主线 sub-D(D147+ Updatable cursor / D138 §Followup F4 NamedParameterJdbcTemplate / D138 §Followup F6 HikariCP Connection Pool / D138 §Followup F7 batchUpdate + BatchUpdateException)

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | Updatable cursor + ResultSet.CONCUR_UPDATABLE / updateRow / cancelRowUpdates / rowDeleted / rowInserted | C3 候选废,留 **D147+ 独立 sub-D** — JDBC 4.3 §15 ResultSet 完整生态(CURSOR_TYPE_FOR_UPDATE 0x02 + Updatable cursor SQL standard `UPDATE ... WHERE CURRENT OF cursor_name`) |
| F2 | holdability HOLD_CURSORS_OVER_COMMIT / CLOSE_CURSORS_AT_COMMIT 常量 + Connection.setHoldability / getHoldability | JDBC §15 cursor 跨 commit 持续性常量(MySQL 默认 CLOSE_CURSORS_AT_COMMIT,PostgreSQL `WITH HOLD` 语法支持 HOLD_CURSORS_OVER_COMMIT)— 留独立 sub-D 或合入 D107+ PostgreSQL driver |
| F3 | ResultSetMetaData 完整列元数据 — getColumnCount / getColumnName / getColumnTypeName / getColumnLabel / isNullable / isAutoIncrement | JDBC §15 ResultSetMetaData interface 完整 — 当前 lib/java/sql.ss 仅 ResultSet 接口,缺 ResultSetMetaData;ORM Hibernate / MyBatis 反射列元数据全断链 — 留独立 sub-D |
| F4 | SQL standard DECLARE CURSOR / FETCH CURSOR_NAME(MySQL stored procedure scope) | MySQL stored procedure 内 SQL DECLARE CURSOR / FETCH cursor_name INTO var 语法(非 prepared statement client cursor)— 与 D146 server-side cursor 路径互斥,留独立 sub-D |
| F5 | PostgreSQL DECLARE CURSOR + FETCH 切换路径 | D107+ PostgreSQL driver 起首时 PostgreSQL `DECLARE cursor_name CURSOR FOR query` + `FETCH N FROM cursor_name` 协议;与 MySQL COM_STMT_FETCH 路径不同 driver 适配 — 留 D107+ |
| F6 | server-side scrollable cursor MySQL 8.0+ MERGE_ENABLE_SCROLLABLE 协议升级 | MySQL 5.7- / 8.0 默认无 server scrollable cursor(H5);未来 MySQL MERGE_ENABLE_SCROLLABLE 标志若启用,server-side scrollable cursor 协议 + 删 in-memory cache fallback — 留独立 sub-D |
| F7 | cursor + transaction 跨多 statement 复用(autoCommit=false) | cursor lifecycle 跨 setAutoCommit(false) → multiple executeQuery → commit / rollback 路径;D137 per-call Connection vs cursor 跨 statement 复用矛盾 — 留独立 sub-D 或合入 HikariCP D138 §F6 |

---

## Status 时间线

- 2026-05-02 Phase 0 D 文档落档(commit `<Phase 0 commit>`)— D138 §Followup F3 + §A.3 废案 §C3 cursor 部分起首落档;走完整 JDBC 4.3 §15 ResultSet + MySQL COM_STMT_FETCH 0x1c server-side cursor + Spring RowCallbackHandler streaming(C2 接口层 trap 候选 — 用户对话锁 D135-D139 SQL 主线范式延续);设计走 (a) 协议层 COM_STMT_FETCH + CURSOR_TYPE_READ_ONLY + EOF SERVER_STATUS_CURSOR_EXISTS / LAST_ROW_SENT(b) JDBC ResultSet TYPE_SCROLL_* + CONCUR_* + setFetchSize / absolute / first / last / previous + Statement.executeQuery / Connection.prepareStatement type+concurrency 重载(c) MySQL MysqlBinaryResultSet useCursor / fetchSize / cursorExhausted / statementId 字段 + scrollable in-memory cache(MySQL 协议无 server scrollable H5)(d) Spring RowCallbackHandler interface + JdbcTemplate.query 重载 + setFetchSize 双语义(client Integer.MIN_VALUE row streaming vs server-side cursor N rows MySQL Connector/J 范式 H4)(e) 7 形态 integration_test.ss 全形态覆盖(forward-only default / setFetchSize cursor 协议触发 / scrollable absolute/previous / cursor close 担保 / client streaming 双语义 / RowCallbackHandler 流式 / cursor lifecycle exception D139 SQLExceptionTranslator);**§A.2 H1-H6 假设挑战 — H1 packet 编码 / H2 CURSOR_TYPE flag / H3 EOF status_flags / H4 setFetchSize 双语义 / H5 scrollable MySQL 协议无支持 fallback in-memory cache / H6 cursor close 担保**;**§A.3 废案 — C1 数据层 patch / C3 架构层 refactor + Updatable cursor + holdability + ResultSetMetaData + named cursor / 客户端 LIMIT 自分页 O(N²) / GROUP BY 分组 / 简化 RowCallbackHandler 为 fn / 简化 setFetchSize 单语义 / scrollable 走 server cursor**;**Followup F1-F7 锚明确 — F1 Updatable cursor D147+ / F2 holdability / F3 ResultSetMetaData / F4 SQL DECLARE CURSOR stored procedure / F5 PostgreSQL DECLARE CURSOR D107+ / F6 server scrollable cursor 未来 MySQL / F7 cursor 跨 transaction**;**VCM 六验全 PASS** — §1 工程豁免(本 Phase 仅 docs/ 改 + .claude/next_prompt.md,bootstrap/ + lib/ + tools/ + tests/ diff = 0)+ §2 行为(D146 doc Phase 0 章节 grep PASS — 完整 12 §核心原则 + §A.1 3 候选 + §A.2 H1-H6 + §A.3 7 废案 + §Phase 收关锚 Phase 0-5 + §Followup F1-F7 + §Status 时间线 1 entry)+ §3 反向(撤回 D146 doc → docs/3-decisions/D146-server-side-cursor.md 不存,F3 sub-D 起首未落档)+ §4 边界(§Followup F1-F7 全锚 + §A.2 H1-H6 全锚 + Depends on D025/D134/D136/D137/D138/D139 全实存)+ §5 路线(D135-D139 SQL 主线范式延续 — Phase 计划独立 commit + 协议层升级 + JDBC 接口扩 + Spring 入口 + 测试覆盖)+ §6 根因(file:line 锚 = D138 §Followup F3 line 396, 424 起首脱胎 + §A.3 §C3 cursor 部分 line 290 + 本 D146 §核心目标 + §A.1 C2 决策行 + §Phase 收关锚 Phase 0 mark Done);**baseline**:d_doc_index_linter F1 = 0 PASS(D146 加入未破 referenced Ds — D025/D134/D136/D137/D138/D139 全实存);**next_prompt_ultrathink_linter PASS**(下轮提示词含 ultrathink 关键字);**编译器零改动**(本 Phase 纯 docs/);**等下轮 Phase 1 协议层 COM_STMT_FETCH + CURSOR_TYPE_READ_ONLY + EOF flag spike GREEN**
