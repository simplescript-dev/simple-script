# D139: SQL Exception Hierarchy — 完整 JDBC SQLException + Spring DataAccessException Tree

**Status:** [✓] Phase 0 D 文档落档 at commit `68a8184` + [✓] Phase 1 协议层 ErrorPacket + JDBC SQLException 完整 12 类 hierarchy + spike 跨 module 3 层继承 GREEN at commit `04821ce` + [✓] Phase 2 协议层全 throw + 删 sentinel + 调用方升级 + spike INSERT dup_key catch SQLIntegrityConstraintViolationException GREEN at commit `dd0ef4a` + [✓] Phase 3 Spring DAE 完整 14 子类树 + SQLExceptionTranslator 反查表 + spike 12/12 GREEN(MySQL errorCode 8 主映射 + SQLState 5 char fallback + 默认 fallback + 4 层 catch hierarchy)at commit `be394f5` + [✓] Phase 4 JdbcTemplate 11 method 上层 try / catch (e: SQLException) → translator.translate(e) → throw DAE + 嵌套 try-finally 担保 stmt+conn close + queryForList 流式异常路径 leak-on-failure 注释 + spike `jdbc.update INSERT dup_key catch DuplicateKeyException` 3/3 GREEN(业务侧 catch DAE 子类不见底层 SQLException + 父类 catch DataIntegrity / DAE 同实例 + finally-close 担保 socket 不饥饿)at commit `<Phase 4 commit>` (2026-04-29) — D138 §Followup F2 + §A.3 废案 §C3 SQLException 部分 起首落档;走**完整 JDBC 4.3 §13 SQLException Hierarchy**(`SQLException` + 3 主子类 + 6+ 中间层 = ~10 类)+ **完整 Spring `org.springframework.dao` DataAccessException Tree**(15+ 主子类)+ **SQLExceptionTranslator** 标准 + **协议层全 throw**(删 `RESULT_SET_HEADER_ERR = -1` sentinel + `readUpdateResult(fd): int` thin wrapper + `errMsg + println("MySQL: ...")` 路径)+ **调用方全升级**(commit / rollback / setAutoCommit / executeUpdate / executeQuery + tests/d134/d135/d136/d138 同步 try/catch),不走 SS sentinel workaround(用户对话锁 1b + 2b + 3a + 4:**完整子类 + 删 sentinel + 全升级 throw**)。**SS 已支持完整 typed try/catch/throw class extends**(`bootstrap/lexer/lexer.ss:454-456` + `bootstrap/parse/parse_stmts.ss:59 parseTryCatch / 96 parseThrow` + `bootstrap/checker/check_stmts.ss:425 TRY / 455 THROW` + `bootstrap/gen/stmts/stmts_exc.ss:23 genTryCatch / 172 genThrow` + `tests/phase5/typed_catch.ss` 6 case + `throw_error.ss` 4 case baseline GREEN 实证)。Phase 2 §A.2 H1 实测在 spring/data → spring/jdbc → java/sql → mysql/jdbc → mysql/query 链式 import 时具体子类 `%SQLException` GEP forward-ref(LLVM `base element of getelementptr must be sized`)— 走 H1 失败回路 fallback,`bootstrap/gen/stmts/stmts_exc.ss:172-205 genThrow` 1 处扩(byte-offset GEP `getelementptr i8, ptr %obj, i64 ${idx*8}` 替具体类型 GEP,类型无关 layout 直接 i8 byte offset bypass forward-ref;getFieldIndex 仍正确计 offset,语义不变),协议 / JDBC / Spring 三层纯 lib/ 落地不动其余编译器。

**Depends on:**
- D025(interface dispatch — class extends Error 继承 hierarchy 走 vtable indirect dispatch)
- D134(MySQL wire protocol — 0xFF ERR_PACKET header 已识别但未解析 errorCode / sqlState / errorMessage 字段)
- D135(caching_sha2 fast-path — handshake.ss errMsg + println sentinel 路径覆盖完整)
- D136(prepared statement — MysqlPreparedStatement.executeUpdate ERR sentinel 调用方,Phase 2 升级 throw)
- D137(JdbcTemplate retcon — update/query/queryForXxx 上层入口,Phase 4 加 try/catch SQLExceptionTranslator)
- D138(MySQL generated keys — readUpdateResultPacket sentinel `OkPacket{-1,0,0,0}` 调用方,Phase 2 升级 throw;§Followup F2 锚 起首)
- `bootstrap/lexer/lexer.ss:454-456`(TRY / CATCH / THROW keywords)
- `bootstrap/parse/parse_stmts.ss:59 parseTryCatch + 96 parseThrow`(SS try/catch/throw 完整 parser)
- `bootstrap/checker/check_stmts.ss:425 TRY case + 455 THROW case`(typed catch 类型检查)
- `bootstrap/gen/stmts/stmts_exc.ss:23 genTryCatch + 99 genCatchClauses + 172 genThrow`(完整 codegen)
- `tests/phase5/typed_catch.ss`(SS typed try/catch/throw class extends + finally 6 case 实证)
- `tests/phase5/throw_error.ss`(SS throw class instance + catch 提取 message 4 case 实证)
- `lib/com/mysql/query.ss:20 ERR_HEADER + 23 RESULT_SET_HEADER_ERR + 55 + 105-137`(协议层 sentinel 路径,Phase 2 删)
- `lib/com/mysql/handshake.ss:42 ERR_PACKET + 238-300 mysqlConnect errMsg path`(handshake sentinel 路径,Phase 2 删)
- `lib/com/mysql/prepared.ss:497`(MysqlPreparedStatement ERR-path executeUpdate sentinel,Phase 2 升级)
- `lib/com/mysql/jdbc.ss:96`(MysqlStatement ERR-path executeUpdate sentinel,Phase 2 升级)
- `lib/java/sql.ss`(JDBC interface 已存,Phase 1 加 SQLException 子类 hierarchy + 协议层全 throw 后 throws 注释)
- `lib/spring/jdbc.ss`(Spring JdbcTemplate.update / query / queryForXxx 上层入口,Phase 3 加 DAE 树 + Phase 4 加 try/catch translate)
- CLAUDE.md §Java/TS 语法优先(Java JDBC `java.sql.SQLException` + Spring `org.springframework.dao.DataAccessException` 是主线;TS 不直接对应,JDBC + Spring 标准为准)
- CLAUDE.md §Root Cause 优先 第一法则(本 D 用户对话锁 C3:**完整子类 + 删 sentinel + 全升级 throw,不接受次优 / workaround / 节省**)
- `memory/feedback_root_cause_no_cost.md`(成本不是次优排序依据)
- `memory/feedback_no_derive_workaround.md`(主线能力缺口不允许 sentinel / errMsg / println 替代)

**Date:** 2026-04-29
**Last Updated:** 2026-04-29

---

## 核心目标 (Goal)

- **为什么**:
  - **MySQL ERR packet 信息丢失**:`lib/com/mysql/query.ss:55` first byte == 0xFF (ERR_HEADER) → 直接返 `RESULT_SET_HEADER_ERR = -1` sentinel,error_code / sql_state / error_message 3 字段全 skip;`lib/com/mysql/query.ss:118-126` `readUpdateResultPacket` ERR / short read / 未知 header 全 collapse 到 `OkPacket{-1, 0, 0, 0}` sentinel;`lib/com/mysql/handshake.ss:238-300` `mysqlConnect` 走 `errMsg = "..."` + `println("MySQL: " + errMsg)` + `return -1`(全部 ERR 信息丢失到 stdout 不可程序处理)。
  - **JDBC `throw SQLException` spec 不实现**:JDBC 4.3 §13 SQLException Hierarchy 完整 ~10 类(`SQLException` + 3 主子类 NonTransient/Transient/Recoverable + 6+ 中间层 NonTransientConnection/IntegrityConstraintViolation/SyntaxError/Data/FeatureNotSupported/Timeout/TransactionRollback)全缺。`lib/java/sql.ss:64` 注释 "Statement.execute(String) on a PreparedStatement throws SQLException anyway" 是占位锚但未实现。
  - **Spring DAE 树缺失**:Spring `org.springframework.dao` 完整 DataAccessException 15+ 子类(DAE / TransientDAE / NonTransientDAE / DataIntegrityViolation / DuplicateKey / BadSqlGrammar / CannotGetJdbcConnection / DataAccessResourceFailure / DataRetrievalFailure / EmptyResultDataAccess / IncorrectResultSize / ConcurrencyFailure / DeadlockLoserDataAccess / TransientDataAccessResource)全缺。ORM/Repository 层 `try { repo.save(user) } catch (e: DuplicateKeyException) {...}` idiomatic 路径断链。
  - **业务影响**:INSERT 撞 UNIQUE 索引时业务只能 `affectedRows == -1` 反推,无法区分 dup vs syntax vs FK violation vs NOT NULL violation;ORM 层 catch DAE 反查 DAE 子类失败;handshake 失败(wrong password / user not found / network)全 collapse 到 fd = -1 不可区分。

- **是什么**:走**完整 JDBC 4.3 §13 SQLException Hierarchy + Spring DataAccessException Tree + SQLExceptionTranslator**,**删 sentinel + 全升级 throw**:
  - **协议层**:`class ErrorPacket { errorCode: int, sqlState: string, errorMessage: string }` + `parseErrorPacket(payload, payloadLen): ErrorPacket`(MySQL ERR_Packet spec — 0xFF header + 2 byte LE error_code + sql_state_marker `#`(0x23)+ 5 char sql_state + rest error_message)
  - **JDBC SQLException 完整子类**(`lib/java/sql.ss`):
    - `class SQLException extends Error { sqlState: string, errorCode: int }`(JDBC `java.sql.SQLException`)
    - 3 主子类:`SQLNonTransientException` / `SQLTransientException` / `SQLRecoverableException`
    - 6+ 中间层:`SQLNonTransientConnectionException` / `SQLIntegrityConstraintViolationException` / `SQLSyntaxErrorException` / `SQLDataException` / `SQLFeatureNotSupportedException` / `SQLTimeoutException` / `SQLTransactionRollbackException` / `SQLTransientConnectionException`
  - **Spring DAE 完整 15+ 子类**(`lib/spring/jdbc.ss`):
    - 顶层:`class DataAccessException extends Error`
    - 中间:`TransientDataAccessException` / `NonTransientDataAccessException`
    - NonTransient 子树:`DataIntegrityViolationException` / `BadSqlGrammarException` / `CannotGetJdbcConnectionException` / `DataAccessResourceFailureException` / `DataRetrievalFailureException`
    - DataIntegrity 子树:`DuplicateKeyException`
    - DataRetrieval 子树:`EmptyResultDataAccessException` / `IncorrectResultSizeDataAccessException`
    - Transient 子树:`TransientDataAccessResourceException` / `ConcurrencyFailureException`
    - Concurrency 子树:`DeadlockLoserDataAccessException`
  - **SQLExceptionTranslator**:`class SQLExceptionTranslator { translate(sqlException): DataAccessException }`(Spring `org.springframework.jdbc.support.SQLExceptionTranslator` 简化版)— 按 SQLState 前 2 char + MySQL errorCode 反查 → DAE 子类 dispatch
  - **协议层全 throw**:`readUpdateResultPacket / readResultSetHeader / parseResultSetHeader / parseOkPacketAffectedRows / mysqlConnect` 全 throw SQLException 子类(SQLState class 反查 → 具体子类);**删除** `RESULT_SET_HEADER_ERR = -1` 常量 + `readUpdateResult(fd): int` thin wrapper + `errMsg + println("MySQL: ...")` 路径
  - **调用方升级**:`MysqlConnection.commit / rollback / setAutoCommit` + `MysqlStatement.executeUpdate / executeQuery / getGeneratedKeys` + `MysqlPreparedStatement.executeUpdate / executeQuery / getGeneratedKeys` 全升级 throw;`tests/d134_mysql/*.ss` + `tests/d135_caching_sha2/*.ss` + `tests/d136_prepared_statement/*.ss` + `tests/d138_generated_keys/*.ss` 调用方更新 try/catch path
  - **JdbcTemplate 上层 catch / translate**:`JdbcTemplate.update / query / queryForXxx / queryForObject` 等全 method 上层 try / catch SQLException → SQLExceptionTranslator.translate → throw DAE(Spring 标准)

- **单一判据**:7 形态 `tests/d139_sql_exception/integration_test.ss` 全 GREEN — (1) connection 失败(wrong password)→ catch CannotGetJdbcConnectionException + sqlState 28xxx + errorCode 1045 / (2) INSERT duplicate key(MySQL errorCode 1062 / SQLState 23000)→ catch DuplicateKeyException / (3) INSERT non-existent table → catch BadSqlGrammarException(SQLState 42S02)/ (4) INSERT NOT NULL violation → catch DataIntegrityViolationException(SQLState 23000 / errorCode 1048)/ (5) catch SQLException 取 sqlState + errorCode 双字段 / (6) try / catch chain — 业务侧 try → catch DuplicateKeyException(具体)→ catch DataAccessException(fallthrough)/ (7) handshake 失败(ERR packet wrong user)→ catch SQLNonTransientConnectionException + sqlState 28000 + errorCode 1045

> 一句口号:**完整 JDBC + Spring DAE 树,删 sentinel,全升级 throw**

---

## 核心原则 (Principles)

1. **完整 JDBC 4.3 §13 SQLException Hierarchy,不裁剪**:`SQLException` + 3 主子类(NonTransient / Transient / Recoverable)+ 6+ 中间层(NonTransientConnection / IntegrityConstraintViolation / SyntaxError / Data / FeatureNotSupported / Timeout / TransactionRollback / TransientConnection)~10 类全实现
2. **完整 Spring `org.springframework.dao` DAE Tree,不裁剪**:15+ 子类(DAE / TransientDAE / NonTransientDAE / DataIntegrityViolation / DuplicateKey / BadSqlGrammar / CannotGetJdbcConnection / DataAccessResourceFailure / DataRetrievalFailure / EmptyResultDataAccess / IncorrectResultSize / ConcurrencyFailure / DeadlockLoserDataAccess / TransientDataAccessResource)全实现
3. **删 sentinel 路径,不留向后兼容**:`RESULT_SET_HEADER_ERR = -1` 常量 + `readUpdateResult(fd): int` thin wrapper + `errMsg + println("MySQL: ...")` 路径全删 — D138 §核心原则 5 thin wrapper 退役;sentinel 与 throw 共存违反 JDBC `throw SQLException` spec
4. **全升级 throw,不留 sentinel 调用方**:协议层 + JDBC 层 + Spring 层全升级 throw;commit / rollback / setAutoCommit / executeUpdate / executeQuery / getGeneratedKeys 等内部调用方 + tests/d134/d135/d136/d138 调用方全更新 try/catch
5. **ErrorPacket 协议层完整 parse,无 skip**:`errorCode / sqlState / errorMessage` 3 字段全保留 — MySQL ERR_Packet spec(0xFF + 2 byte LE error_code + `#` marker + 5 char sql_state + rest error_message)
6. **SQLException 子类 dispatch by SQLState class**(JDBC 4.3 §13.4 SQLState 前 2 char):`08` connection / `23` integrity constraint / `40` transaction rollback / `42` syntax/access / `0A` feature not supported / `22` data exception / `HY` general(MySQL Connector/J 标准 fallback)
7. **Spring DAE 子类 dispatch by SQLState + errorCode**(SQLExceptionTranslator 反查表)— MySQL errorCode 1062 → DuplicateKey / SQLState 23xxx → DataIntegrityViolation / SQLState 42xxx → BadSqlGrammar / SQLState 08xxx → CannotGetJdbcConnection / SQLState 40xxx → DeadlockLoserDataAccess / 其他 → DataAccessResourceFailure(默认 fallback)
8. **JdbcTemplate 上层 catch SQLException → SQLExceptionTranslator → throw DAE**:`update / query / queryForXxx / queryForObject` 全 method 上层 try / catch SQLException → SQLExceptionTranslator.translate → throw DAE(Spring 标准)
9. **SS typed try/catch/throw class extends 完整支持**:`bootstrap/lexer/lexer.ss:454-456` TRY/CATCH/THROW keywords + `bootstrap/parse/parse_stmts.ss:59 parseTryCatch / 96 parseThrow` 完整 parser + `bootstrap/checker/check_stmts.ss:425 TRY / 455 THROW` typed catch 类型检查 + `bootstrap/gen/stmts/stmts_exc.ss:23 genTryCatch / 172 genThrow` codegen + `tests/phase5/typed_catch.ss` 6 case + `throw_error.ss` 4 case + `error_class.ss` 实证 GREEN。**Phase 2 §A.2 H1 实测假设破裂回路**:具体子类 `%SQLException` GEP 在跨 module 链式 import 时 forward-ref(spring/data → spring/jdbc → java/sql → mysql/jdbc → mysql/query),走 H1 失败回路 fallback —— `bootstrap/gen/stmts/stmts_exc.ss:172-205 genThrow` 1 处扩(byte-offset GEP `getelementptr i8, ptr %obj, i64 ${idx*8}` 替具体类型 GEP,类型无关 layout 直接 i8 byte offset bypass forward-ref);除此 1 处外协议 / JDBC / Spring 三层纯 lib/ 落地不动其余编译器
10. **per-call Connection 简化继承 D137**:JdbcTemplate.update / query 等内部 try / catch / SQLExceptionTranslator / re-throw DAE,per-call Connection 走 D137 范式(HikariCP D125+ 是另一 sub-D)
11. **7 形态测试覆盖 — 不偷工减料**:Phase 5 测试覆盖 §核心目标 7 判据全形态,含 connection 失败 / dup key / table 不存在 / NOT NULL / sqlState+errorCode 双字段 / try-catch-chain 多层 fallthrough / handshake 失败
12. **Phase 计划独立 commit**:Phase 0-5 独立 commit;Phase 0 D 文档落档不打包 Phase 1+ 实施(D135/D136/D137/D138 范式)
13. **VCM 六验全跑**:bootstrap 三阶段固定点(本 D 不改编译器但 lib/ 改触发 build cache)+ tests/d134_mysql / d135_caching_sha2 / d136_prepared_statement / d138_generated_keys baseline 不破(调用方升级后)+ tests/d141-d144 反推机制 baseline 不破 + reflection_health GATE PASS + d_doc_index PASS

---

## 1. Context Management

### 必读清单(按顺序)

1. 本文档(D139)
2. CLAUDE.md §Java/TS 语法优先 + §Root Cause 优先 第一法则 + §交互式单文档
3. 依赖 D 文档:
   - D134 §3(MySQL wire protocol + ERR packet skip 现状)
   - D135 §A.3(handshake.ss errMsg + println 路径完整覆盖)
   - D136 §A.5(prepared statement ERR sentinel)
   - D137 §3(JdbcTemplate setter callback + per-call Connection)
   - D138 §核心原则 4(单一信息源 readUpdateResultPacket)+ §核心原则 5(thin wrapper 向后兼容 — 本 D 退役)+ §Followup F2(本 D 起首锚)
4. SS try/catch/throw 实现(读源码确认能力):
   - `bootstrap/lexer/lexer.ss:454-456`
   - `bootstrap/parse/parse_stmts.ss:59-104`(parseTryCatch + parseThrow)
   - `bootstrap/checker/check_stmts.ss:425-458`(TRY + THROW case)
   - `bootstrap/gen/stmts/stmts_exc.ss:23-200+`(genTryCatch + genCatchClauses + genThrow)
   - `tests/phase5/typed_catch.ss`(6 case 实证)
   - `tests/phase5/throw_error.ss`(4 case 实证)
5. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `lib/com/mysql/query.ss` | **20-23** | `ERR_HEADER = 0xFF` + `RESULT_SET_HEADER_ERR = -1`(Phase 2 删 sentinel 常量,统一 wire.ss 共享 0xFF)|
   | `lib/com/mysql/query.ss` | **52-58** | `parseResultSetHeader` ERR 路径返 -1 sentinel(Phase 2 改 throw)|
   | `lib/com/mysql/query.ss` | **89-103** | `parseOkPacket` 返 `OkPacket{0,0,0,0}` 当 header != OK_HEADER(Phase 1 加 `parseErrorPacket` 配套)|
   | `lib/com/mysql/query.ss` | **118-126** | `readUpdateResultPacket` ERR / short read sentinel `OkPacket{-1,0,0,0}`(Phase 2 改 throw)|
   | `lib/com/mysql/query.ss` | **128-137** | `readUpdateResult(fd): int` thin wrapper(Phase 2 删)|
   | `lib/com/mysql/handshake.ss` | **42** | `ERR_PACKET = 0xFF`(Phase 1 统一 wire.ss 共享 0xFF)|
   | `lib/com/mysql/handshake.ss` | **238-300** | `mysqlConnect` errMsg + println sentinel 路径(Phase 2 改 throw SQLException)|
   | `lib/com/mysql/jdbc.ss` | **35-105** | MysqlConnection / MysqlStatement(Phase 2 commit/rollback/setAutoCommit/executeUpdate/executeQuery/getGeneratedKeys 升级 throw)|
   | `lib/com/mysql/prepared.ss` | **493-580** | MysqlPreparedStatement(Phase 2 executeUpdate/executeQuery/getGeneratedKeys 升级 throw)|
   | `lib/java/sql.ss` | **(新加)** | Phase 1 加 `class SQLException extends Error` + 3 主子类 + 6+ 中间层 |
   | `lib/spring/jdbc.ss` | **(新加)** | Phase 3 加 `class DataAccessException extends Error` 完整 15+ 子类树 + `class SQLExceptionTranslator` 反查表 |
   | `lib/spring/jdbc.ss` | **51-122** | JdbcTemplate.update / query / queryForXxx 6 method baseline(Phase 4 上层 try / catch / translate)|
   | `tests/phase5/typed_catch.ss` | **3-89** | SS typed catch + 继承 hierarchy 实证(本 D Phase 1 spike 参考)|
   | `tests/phase5/throw_error.ss` | **1-49** | SS throw class instance 实证(本 D Phase 1 spike 参考)|
   | `tests/d134_mysql/` | (升级)| Phase 2 调用方更新 try/catch(commit/rollback/executeUpdate 等 ERR sentinel 调用方升级)|
   | `tests/d135_caching_sha2/` | (升级)| Phase 2 调用方更新 try/catch |
   | `tests/d136_prepared_statement/` | (升级)| Phase 2 调用方更新 try/catch |
   | `tests/d138_generated_keys/` | (升级)| Phase 2 调用方更新 try/catch(Case 6 ERR packet 防御从 affectedRows == -1 改 catch SQLException)|
   | `tests/d139_sql_exception/` | **(新建)** | Phase 5 — 7 形态 integration_test.ss |

### Context 不变量

| 不变量 | 状态 |
|---|---|
| MySQL ERR_Packet 协议字段 | D134 已识别 0xFF header 但 errorCode / sqlState / errorMessage 全 skip — Phase 1 解 |
| readLengthEncodedInt + lengthEncodedIntSize | `lib/binary` 已落,Phase 1 直接消费(query.ss:14 import)|
| OkPacket / ErrorPacket 设计模式 | D138 已落 OkPacket(query.ss:75),Phase 1 ErrorPacket 直接同模式扩 |
| MysqlResultSet : ResultSet 实现 | D134 已落,本 D 不动(SQLException throw 路径不影响 ResultSet 接口契约)|
| MysqlStatement / MysqlPreparedStatement.executeUpdate | D138 已落 readUpdateResultPacket(jdbc.ss:91-94 / prepared.ss:547-550)— Phase 2 改抛 SQLException 替换 sentinel `affectedRows == -1` 守卫 |
| D137 setter callback 5 method 重载 | 已落(D137),本 D Phase 4 在此基础上加 try/catch translate;不动 setter 签名 |
| D138 KeyHolder + GeneratedKeyResultSet | 已落(D138),本 D 不动(Phase 4 jdbcTemplate.update(sql, setter, keyHolder) 加 try/catch translate 上层包装,不动 KeyHolder 契约)|
| SS typed try/catch/throw class extends | 已落(lexer/parser/checker/codegen 全支持),`tests/phase5/typed_catch.ss` + `throw_error.ss` baseline GREEN — Phase 1 spike 直接复用 |
| `class Error { message: string }` 基类 | SS prelude 已落(lib/test.ss + tests/phase5 实证)— Phase 1 SQLException + DAE 直接 extends Error |
| 反射 baseline | `tools/reflection_health_linter.ss` + `tools/linter_baseline.txt`(本 D 不触反射 — 应用层 stdlib 纯 SS,不动 bootstrap)|

### 禁止的 Context 操作

- ❌ SS 简化 SQLException 单 class 不分子类(用户对话锁 1b 完整子类 hierarchy)
- ❌ 简化 Spring DAE 单 class 不分子类(用户对话锁 2b 完整 15+ 子类)
- ❌ 保留 `RESULT_SET_HEADER_ERR = -1` sentinel 与 throw 共存(用户对话锁 3a 全删)
- ❌ 保留 `readUpdateResult(fd): int` thin wrapper 向后兼容(用户对话锁 3a + 4 全升级 throw)
- ❌ 保留 `errMsg + println("MySQL: ...")` 路径(用户对话锁 4 全升级 throw)
- ❌ 修编译器(本 D 应用层 stdlib 纯 SS — SS 已支持 typed try/catch/throw class extends,§核心原则 9)
- ❌ 修 D025 interface dispatch / D134 wire protocol / D136 prepared statement / D137 JdbcTemplate / D138 generated keys 本体

---

## 2. Tools

| 工具 | 用途 |
|---|---|
| `./build.sh bootstrap` | 三阶段固定点(本 D lib/ 改触发 build cache,需验证)|
| `bin/ss test tests/d139_sql_exception/` | Phase 5 主判据 7 形态 |
| `bin/ss test tests/d138_generated_keys/` | D138 baseline(调用方升级后)不破 |
| `bin/ss test tests/d137_jdbctemplate_prepared/` | D137 baseline(JdbcTemplate.update / query 上层 catch / translate 后)不破 |
| `bin/ss test tests/d136_prepared_statement/` | D136 baseline(MysqlPreparedStatement.executeUpdate 升级 throw 后)不破 |
| `bin/ss test tests/d135_caching_sha2/` | D135 baseline(handshake mysqlConnect 升级 throw 后)不破 |
| `bin/ss test tests/d134_mysql/` | D134 baseline(commit/rollback/setAutoCommit/executeUpdate 升级 throw 后)不破 |
| `bin/ss test tests/d141-d144_*_inference/` | 反推机制 baseline 不破 |
| `bin/ss test tests/phase5/typed_catch.ss tests/phase5/throw_error.ss` | SS typed try/catch baseline 实证(Phase 1 spike 前置)|
| `bin/ss test tests/` | 全测 baseline 不降 |
| `docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait` | MySQL 集成测试探活前置 |
| `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate |
| `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline |
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt ultrathink 收尾 gate |

---

## 3. Orchestration

| Phase | 目标 | 关键产出 | 验证 |
|-------|------|----------|------|
| **Phase 0** | D 文档落档(本 Phase) | `docs/3-decisions/D139-sql-exception-hierarchy.md` | d_doc_index F1=0 + ultrathink_linter PASS |
| **Phase 1** | 协议层 ErrorPacket + JDBC SQLException 主子类 + spike | `class ErrorPacket { errorCode, sqlState, errorMessage }`(query.ss)+ `parseErrorPacket(payload, payloadLen): ErrorPacket`(query.ss)+ `class SQLException extends Error { sqlState, errorCode }` + 3 主子类 + 6+ 中间层 ~10 类(sql.ss)+ `/tmp/test_d139_phase1.ss` spike(throw class instance 跨 module + catch 继承 hierarchy)| spike RED→GREEN(throw new SQLException(...) + catch (e: SQLNonTransientException))+ bootstrap 三阶段固定点 + d134/d135/d136/d138 baseline 不破 + tests/phase5/typed_catch + throw_error 不破 |
| **Phase 2** | 协议层全 throw + 删 sentinel + 调用方升级 | `query.ss`:`parseResultSetHeader / parseOkPacketAffectedRows / readUpdateResultPacket / readResultSetHeader` 全 throw SQLException + 删 `RESULT_SET_HEADER_ERR` 常量 + 删 `readUpdateResult(fd): int` thin wrapper + 删 `parseOkPacketAffectedRows` thin wrapper(D138 §核心原则 5 退役);`handshake.ss`:`mysqlConnect` 全 throw SQLException + 删 errMsg + println 路径;`jdbc.ss`:MysqlConnection.commit / rollback / setAutoCommit + MysqlStatement.executeUpdate / executeQuery / getGeneratedKeys 全升级 throw;`prepared.ss`:MysqlPreparedStatement 同位升级;SQLState class 反查 → SQLException 子类 dispatch(`08` → SQLNonTransientConnection / `23` → IntegrityConstraintViolation / `40` → TransactionRollback / `42` → SyntaxError / `0A` → FeatureNotSupported / `22` → DataException / `HY` → SQLException 默认);tests/d134/d135/d136/d138 调用方更新 try/catch | spike `INSERT INTO ... VALUES (1,'A')` 撞 unique 索引 catch SQLIntegrityConstraintViolationException + sqlState 23000 + errorCode 1062 GREEN + tests/d134-d138 baseline 升级后不降 |
| **Phase 3** | Spring DAE 完整树 + SQLExceptionTranslator | `lib/spring/jdbc.ss` 加 15+ DAE 子类(顶层 DAE / TransientDAE / NonTransientDAE / DataIntegrityViolation / DuplicateKey / BadSqlGrammar / CannotGetJdbcConnection / DataAccessResourceFailure / DataRetrievalFailure / EmptyResultDataAccess / IncorrectResultSize / ConcurrencyFailure / DeadlockLoserDataAccess / TransientDataAccessResource)+ `class SQLExceptionTranslator { translate(sqlException): DataAccessException }` 反查表(SQLState 前 2 char + MySQL errorCode → DAE 子类) | spike `translator.translate(new SQLIntegrityConstraintViolationException("...", "23000", 1062))` 返 DuplicateKeyException GREEN;Spring DAE 树继承 hierarchy 实证(`catch (e: DataIntegrityViolationException) → catch (e: DataAccessException)` fallthrough)|
| **Phase 4** | JdbcTemplate 上层 catch / translate | `lib/spring/jdbc.ss` JdbcTemplate.update / query / queryForXxx / queryForObject(D137 5 method + D138 第 6 method)全 method 上层 try / catch SQLException → SQLExceptionTranslator.translate → throw DAE — Spring 标准 | spike `try { jdbc.update("INSERT INTO ... dup_key VALUES (1)") } catch (e: DuplicateKeyException) {...}` GREEN |
| **Phase 5** | 测试覆盖 7 形态 + 全 Phase 收关 | `tests/d139_sql_exception/integration_test.ss`(7 case:connection 失败 / dup key / table 不存在 / NOT NULL violation / sqlState+errorCode 双字段 / try-catch-chain 多层 fallthrough / handshake wrong user)+ 全 Phase commit hash 全列 + 兑现成果 + Followup F1+ 锚明确 + d_doc_index PASS + reflection_health PASS | 7/0/7 全绿 + 隐藏假设 H1-H? PASS + D139 主线 close |

### Phase 间依赖

- Phase 0 → 1:D 文档落档锁后 Phase 1 起首
- Phase 1 → 2:`ErrorPacket` + `SQLException` 子类 hierarchy 就位 + spike 跨 module throw class instance + catch 继承 GREEN + d134-d138 baseline 不破才启 Phase 2
- Phase 2 → 3:协议层全 throw + 删 sentinel + 调用方升级 + tests/d134-d138 调用方升级 try/catch 全绿才启 Phase 3
- Phase 3 → 4:Spring DAE 完整树 + SQLExceptionTranslator 反查表落地 + spike DAE 子类 dispatch 全 GREEN 才启 Phase 4
- Phase 4 → 5:JdbcTemplate 上层 catch / translate 全 method 落地 + spike 业务侧 catch DAE GREEN 才启 Phase 5
- Phase 5 收关:7 形态全绿 + 全 Phase commit hash 回填 + Followup 锚明确

### 反模式

- ❌ 把 Phase 1 SQLException 退化为单 class 不分子类(完整 ~10 子类)
- ❌ Phase 2 保留 `RESULT_SET_HEADER_ERR = -1` 与 throw 共存(违反 §核心原则 3 删 sentinel)
- ❌ Phase 2 保留 `readUpdateResult(fd): int` thin wrapper 向后兼容(D138 §核心原则 5 退役)
- ❌ Phase 3 简化 DAE 单 class 不分 15+ 子类(用户对话锁 2b 完整版)
- ❌ Phase 4 跳过 SQLExceptionTranslator 直接 throw SQLException(违反 Spring 标准)
- ❌ Phase 5 跳过 7 形态走轻量 3 形态(违反 §核心原则 11 不偷工减料)
- ❌ 起 D140+(本 D 仅 SQL exception;cursor / NamedParameterJdbcTemplate 等 D138 §Followup F3+ 留独立 sub-D)

---

## 4. State

### 编译时 state

- `class ErrorPacket` — Phase 1 加(query.ss)
- `class SQLException extends Error` + ~10 子类 — Phase 1 加(sql.ss)
- 删 `const RESULT_SET_HEADER_ERR = -1` — Phase 2 删(query.ss:23)
- 删 `function readUpdateResult(fd: int): int` — Phase 2 删(query.ss:135-137)
- 删 `function parseOkPacketAffectedRows(payload, payloadLen): int` — Phase 2 删(query.ss:108-110)
- `class DataAccessException extends Error` + 15+ 子类 — Phase 3 加(spring/jdbc.ss)
- `class SQLExceptionTranslator` — Phase 3 加(spring/jdbc.ss)

### 运行时 state

- ErrorPacket 内部:`errorCode: int / sqlState: string / errorMessage: string`
- SQLException 内部(继承 Error):`message: string` + 本 D 加 `sqlState: string / errorCode: int`
- DAE 内部(继承 Error):`message: string`(Spring DAE 内部不存 SQLState/errorCode,在 SQLException cause 里)— 本 D 简化:DAE 加 `cause: SQLException`(Spring `getCause()` 标准)
- SQLExceptionTranslator 内部:无 state(纯函数 translate)
- JdbcTemplate 调用方 try / catch state:per-call,不跨 method

### 禁止 state 操作

- ❌ 把 ErrorPacket 字段存全局 Map(class 字段已足够)
- ❌ 在 SQLException 之外另起 wrapper class(直接 extends Error 简洁)
- ❌ DAE 内部 store SQLState 重复(走 cause: SQLException 链获取)
- ❌ SQLExceptionTranslator 缓存反查结果(纯函数无副作用)

---

## 5. Evaluation

### 单一判据(必须 GREEN)

```bash
# Phase 5 主判据(完整 7 形态)
bin/ss test tests/d139_sql_exception/

# 7 形态:
# 1. connection 失败(wrong password)→ catch CannotGetJdbcConnectionException + sqlState 28xxx + errorCode 1045
# 2. INSERT duplicate key(MySQL errorCode 1062 / SQLState 23000)→ catch DuplicateKeyException
# 3. INSERT non-existent table → catch BadSqlGrammarException(SQLState 42S02)
# 4. INSERT NOT NULL violation → catch DataIntegrityViolationException(SQLState 23000 / errorCode 1048)
# 5. catch SQLException 取 sqlState + errorCode 双字段
# 6. try / catch chain — 业务侧 try → catch DuplicateKeyException(具体)→ catch DataAccessException(fallthrough)
# 7. handshake 失败(ERR packet wrong user)→ catch SQLNonTransientConnectionException + sqlState 28000 + errorCode 1045
```

### Phase 关键验证

- bootstrap 三阶段固定点 PASS(stage2 == stage3)— 本 D 不改 bootstrap,但 lib/ 改触发 build cache
- spike Phase 1 `parseErrorPacket` 4 字段 returnable 验证(payload bytes → ErrorPacket)
- spike Phase 1 `throw new SQLNonTransientException(...)` 跨 module + `catch (e: SQLException)` 继承 hierarchy GREEN
- spike Phase 2 `INSERT INTO ... dup_key VALUES (1)` MySQL docker 集成 catch SQLIntegrityConstraintViolationException + sqlState 23000 + errorCode 1062 GREEN
- spike Phase 3 `SQLExceptionTranslator.translate(sqlException)` 反查 DAE 子类 GREEN
- spike Phase 4 `try { jdbc.update("INSERT ... dup_key") } catch (e: DuplicateKeyException) {...}` Spring 标准 GREEN
- tests/d134_mysql / d135_caching_sha2 / d136_prepared_statement / d137_jdbctemplate_prepared / d138_generated_keys 全 baseline 不破(调用方升级后)
- tests/d141-d144 反推机制 baseline 不破
- tests/phase5/typed_catch.ss + throw_error.ss baseline 不破(SS try/catch 机制本 D 不改)
- reflection_health GATE PASS no regressions
- d_doc_index PASS

### 隐藏假设挑战(本 D §A.2)

见 §A.2(H1-H? 完整覆盖)

---

## 6. Constraints

### 硬约束

- **完整 JDBC 4.3 §13 + Spring DAE 完整树**(用户对话锁 1b + 2b:不裁剪 / 不简化 / 不 workaround)
- **删 sentinel + 全升级 throw**(用户对话锁 3a + 4:不留向后兼容)
- 不动 D025 interface dispatch 契约
- 不动 D134 wire protocol 本体(packet read 路径 readPacket / writePacket 不破)
- 不动 D136 prepared statement 本体(executeUpdate 调用方升级,本体 doPrepare / sendStmtExecute 不重写)
- 不动 D137 JdbcTemplate 5 method baseline(向后兼容,加 try/catch translate 不改既有签名)
- 不动 D138 KeyHolder + GeneratedKeyResultSet + RETURN_GENERATED_KEYS 常量(向后兼容,Phase 4 jdbcTemplate.update(sql, setter, keyHolder) 上层包装 try/catch translate)
- 不修编译器(SS 已支持 typed try/catch/throw class extends — §核心原则 9)
- bootstrap 不动 — 实际预估 ~700-900 LOC delta(协议层 ErrorPacket + JDBC SQLException ~10 类 + Spring DAE 15+ 类 + SQLExceptionTranslator + 协议层 throw + JdbcTemplate try/catch + tests)

### 软约束

- 优先编译期硬错(SQLException 子类 hierarchy 通过 SS 继承机制保 catch 静态分派优先)
- SQLState class 反查表覆盖 MySQL Connector/J 标准 6+ class(`08` / `23` / `40` / `42` / `0A` / `22` + `HY` 默认)— 其他 SQLState 默认 fallback 到 `SQLException`(不是子类)
- DAE 反查表覆盖 MySQL errorCode 5+ 主类(1062 / 1048 / 1452 / 1146 / 1054 等 + 默认 fallback 到 `DataAccessResourceFailureException`)
- DAE 内部不存 sqlState / errorCode 重复字段(走 `cause: SQLException` 链获取)— Spring `getRootCause()` 标准
- handshake 失败现 errMsg 字符串列表保留为 SQLException.message(不丢用户调试信息),sqlState + errorCode 按 MySQL ERR_Packet 解析填充

### 风险锚(R1-R6)

| # | 风险 | 描述 | mitigation |
|---|---|---|---|
| R1 | SS throw class instance 跨 module vtable indirect dispatch | `lib/com/mysql/query.ss` throw `new SQLNonTransientException(...)` + `lib/spring/jdbc.ss` catch `(e: SQLException)` 跨 module class hierarchy 是否走 D025 vtable 正确 | Phase 1 spike `/tmp/test_d139_phase1.ss` 实测 cross-module throw + typed catch hierarchy;若 dispatch 错位 → 走 D025 vtable 同模式 fallback;若仍错位 → 标 §Followup nested cross-module exception 限制 |
| R2 | catch (e: ParentClass) 是否能 catch 子类实例(继承 hierarchy) | `tests/phase5/typed_catch.ss` Test 4 已实证 `catch (e: Error)` 能 catch IOError 子类;但 ~10 层深的 SQLException 子类(SQLException → SQLNonTransientException → SQLNonTransientConnectionException)是否完整支持 | Phase 1 spike 三层继承 + Phase 3 验证 Spring DAE 5+ 层继承(DAE → NonTransientDAE → DataIntegrityViolation → DuplicateKey)|
| R3 | tests/d134-d138 调用方升级 throw 后 baseline 大量改动 | 升级 throw 后 commit / rollback / setAutoCommit / executeUpdate / executeQuery 等内部 sentinel 调用方 + tests/d134/d135/d136/d138 调用方都需 try/catch 包裹,可能涉及 ~30+ 处调用方升级 | Phase 2 列调用方清单 + 批量更新 try/catch + 全测 baseline 升级后不降验证;若回归 → Phase 2 拆 commit(协议层 throw + 调用方升级各独立 commit)|
| R4 | Spring SQLExceptionTranslator 反查表 MySQL 特异性 | Spring 标准 SQLExceptionTranslator 默认按 SQLState 反查;但 MySQL 部分 errorCode(1062 dup / 1048 NOT NULL / 1452 FK)需细分;Spring 完整版有 SQLErrorCodes XML 配置但 SS 不支持 XML | Phase 3 内置 MySQL Connector/J errorCode 反查表(简化 XML 为 SS function)+ Spring SQLState fallback;Phase 5 测试覆盖 errorCode 主类 |
| R5 | JdbcTemplate 上层 try / catch 嵌套 throw DAE stack unwind | JdbcTemplate.update 内部 try / catch SQLException → translate → throw DAE,业务侧 try / catch DAE 是双层 try/catch;SS try/catch 实现是否正常 unwind | Phase 4 spike 双层 try/catch + Phase 5 Case 6 try-catch-chain 多层 fallthrough 测试覆盖 |
| R6 | docker MySQL 探活失败时 SQLException 测试可跳 | Phase 5 测试需 docker MySQL 在线产生真实 ERR packet(dup key / table 不存在等);docker 不在线时跳过 | tests/d139 沿 d134/d136/d138 模式 — `probe.isClosed() == 1` 时 println + return 0,集成测试不阻 `bin/ss test tests/` |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 spike 跨 module throw class instance llc 错(`@SQLException_*` 未定义)| 走 D138 §A.2 H4 类比 — 检查 codegen interface dispatcher / class method symbol mangle 是否对齐 + Phase 1 加单元测试覆盖 |
| Phase 1 catch 继承 hierarchy 不工作(catch (e: SQLException) 不 catch SQLNonTransientException)| 检查 `bootstrap/gen/stmts/stmts_exc.ss:99 genCatchClauses` typed catch 是否走 instanceof 链;若错位 → §Followup 编译器扩(本 D 范围尽力避免)|
| Phase 2 删 sentinel 后 D134-D138 测试大量回归 | Phase 2 拆 commit:协议层 throw 独立 commit + 调用方升级 + tests 升级独立 commit + 回滚单 phase 不影响其他 |
| Phase 3 DAE 子类 hierarchy 5+ 层深 dispatch 错位 | 同 R2 — Phase 3 spike 5 层继承(DAE → NonTransientDAE → DataIntegrityViolation → DuplicateKey)|
| Phase 4 双层 try/catch 嵌套 unwind 错(SQLException 透传业务侧未 translate)| 检查 `genTryCatch` finally 路径 + Phase 4 加单元测试 |
| Phase 5 docker 探活失败 | tests/d139 沿 d134/d136/d138 模式 — fallback skip println + return 0 |
| reflection_health GATE BLOCK | 走 §MNK §反射路径根因 gate B 路径(扩容申报)— 本 D 不动 bootstrap,理论上不触反射 |

### 回滚策略

- Phase 1+ 失败 → `git reset --soft HEAD^`
- Phase 0 文档已落,Phase 1+ 实施 commit 边界严格(D135-D138 范式延续)
- Phase 2 拆 commit:协议层 throw 独立 + 调用方升级 + tests 升级各独立 commit(降低回滚单元粒度)
- 失败回退不影响 D134-D138(本 D 是新增能力,既有路径需要调用方升级 try/catch — 部分回退需配套回退 tests/ 调用方)

---

## A.1 主候选评估(§MNK §M §字段 10)

| 候选 | 层次 | 描述 | 优势 | 劣势 | 决策 |
|---|---|---|---|---|---|
| **C1** | **数据层 patch** | `class ErrorPacket { errorCode, sqlState, errorMessage }` sentinel 路径,加 `Statement.getLastException(): ErrorPacket` getter,**不动 throw / catch**,业务侧主动 query 检查 | LOC 极小 ~80;实施快;不破 D134-D138 既有 sentinel 调用方 | 不消除根因 — JDBC `throw SQLException` spec 仍缺;Spring `try { repo.save(user) } catch (e: DuplicateKeyException)` idiomatic 路径仍断链;违反 §核心目标完整 spec | **不选** — 用户对话锁:不接受次优 / workaround |
| **C2** | **接口层 trap** | `class SQLException extends Error` + 3 主子类(NonTransient/Transient/Recoverable)+ Spring DAE 7 主子类(DAE / TransientDAE / NonTransientDAE / DataIntegrityViolation / DuplicateKey / BadSqlGrammar / CannotGetJdbcConnection)+ SQLExceptionTranslator 简化版 + JdbcTemplate try/catch | 主线 idiomatic 路径打通;Spring 标准 catch DAE 子类正常;LOC 中等 ~400 | JDBC 4.3 §13 完整 ~10 子类 + Spring DAE 完整 15+ 子类不全 — 中间层 NonTransientConnection / SyntaxError / Data / FeatureNotSupported / Timeout / EmptyResultDataAccess / IncorrectResultSize / ConcurrencyFailure / DeadlockLoserDataAccess 缺,业务侧无法 catch 中间层做粒度处理 | **不选** — 用户对话锁不接受简化 |
| **C3** | **架构层 refactor** | **完整 JDBC 4.3 §13 SQLException Hierarchy ~10 类**(SQLException + 3 主 + 6+ 中间)+ **完整 Spring DAE Tree 15+ 子类**(DAE 全树包括 EmptyResultDataAccess / IncorrectResultSize / DataRetrievalFailure / ConcurrencyFailure / DeadlockLoserDataAccess / TransientDataAccessResource)+ **SQLExceptionTranslator** 完整反查表(SQLState 6+ class + MySQL errorCode 5+ 主类)+ **JdbcTemplate 全 method 上层 try/catch translate** + **删 sentinel + 全升级 throw**(`RESULT_SET_HEADER_ERR` 删 + `readUpdateResult` thin wrapper 删 + `errMsg + println` 删 + commit/rollback/setAutoCommit/executeUpdate/executeQuery 全升级 + tests/d134-d138 调用方升级)| spec 最完整;ORM 层完整路径(`catch (e: DuplicateKeyException) → fallthrough catch (e: DataIntegrityViolationException) → fallthrough catch (e: DataAccessException)`);PostgreSQL/SQLite 未来切换 driver 时 SQLState class 反查表零破坏;无 sentinel 法则 | LOC 大 ~700-900(协议层 + JDBC ~10 类 + Spring 15+ 类 + SQLExceptionTranslator + 协议层 throw + JdbcTemplate try/catch + tests/d134-d138 调用方升级 + tests/d139 7 形态);scope 6 Phase | **选** — 用户对话锁 1b + 2b + 3a + 4 完整 + 删 sentinel + 全升级 throw |

**决策行**:**选 C3 架构层 refactor**(用户对话锁 1b 完整 JDBC SQLException + 2b 完整 Spring DAE + 3a 删 sentinel + 4 全升级 throw)— 因 (a) 完整 JDBC 4.3 §13 + Spring DAE 标准消除根因(无 sentinel + 全 throw + ORM idiomatic 路径);(b) ~10 SQLException 子类 + 15+ DAE 子类完整继承 hierarchy 为业务侧粒度 catch 留扩展位;(c) PostgreSQL/SQLite 未来切换 driver 时 SQLState class 反查表 + Spring SQLExceptionTranslator 零破坏;(d) `RESULT_SET_HEADER_ERR = -1` + `readUpdateResult thin wrapper` + `errMsg + println` 路径全删 — 无 sentinel/throw 共存的根因不一致;(e) commit/rollback/setAutoCommit/executeUpdate/executeQuery + tests/d134-d138 调用方全升级 throw,JDBC spec 一致;(f) SS 已支持完整 typed try/catch/throw class extends — 不需要编译器扩(纯应用层 stdlib 落地)。**为何不选 C1**:用户对话锁不接受 sentinel workaround / 节省路径。**为何不选 C2**:用户对话锁不接受简化 — JDBC 4.3 §13 完整 10 类 + Spring 15+ 类是 spec 标准,简化为 3+7 子类业务侧无法 catch 中间层做粒度处理。

---

## A.2 隐藏假设挑战

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | SS throw class instance 跨 module + catch 继承 hierarchy 完整支持 | `bootstrap/gen/stmts/stmts_exc.ss` codegen 是否支持(a) lib/com/mysql throw `new SQLException(...)` + lib/spring/jdbc catch `(e: SQLException)` 跨 module + (b) 5+ 层继承(DAE → NonTransientDAE → DataIntegrityViolation → DuplicateKey)— `tests/phase5/typed_catch.ss` 仅实证 2 层(IOError extends Error)| Phase 1 spike `/tmp/test_d139_phase1.ss` 实测 5 层继承 + 跨 module throw / catch + 父类 catch 子类实例 | dispatch 错位 → 走 D025 vtable 同模式 fallback;若仍错位 → 编译器扩 §Followup |
| H2 | MySQL ERR_Packet spec offset 固定 | ERR_Packet 协议固定:0xFF (1) + error_code u16le (2) + sql_state_marker `#` (1) + sql_state ASCII (5) + error_message rest;旧 MySQL 4.0 server 不带 sql_state_marker(防御 backward compat)| Phase 1 实测 docker MySQL 8 + 5.7 + 4.0(若有)+ ERR_Packet 多形态 | 老 server 无 marker → defensive,sqlState 默认 "HY000" + errorMessage 包含整 rest |
| H3 | MySQL errorCode 1062 = duplicate key + SQLState 23000 标准 | MySQL Connector/J 标准映射:1062 → SQLState 23000(integrity violation) → DuplicateKeyException;1048 → 23000 NOT NULL → DataIntegrityViolation;1452 → 23000 FK → DataIntegrityViolation;1146 → 42S02 table not exist → BadSqlGrammar;1054 → 42S22 column unknown → BadSqlGrammar | Phase 5 测试 5 主类 errorCode 全形态 + Spring SQLExceptionTranslator 反查 GREEN | errorCode 不匹配 → 默认 fallback DataAccessResourceFailureException + §Followup 加映射 |
| H4 | SQLState 5 char ASCII 标准(JDBC 4.3 §13.4)| SQLState 标准 5 char(2 char class + 3 char subclass);MySQL 标准遵循,但部分老 errorCode 用 4 char SQLState 或 "HY..." MySQL 内部 | Phase 1 parseErrorPacket 严格 5 char;若不足 5 char defensive padding `"HY000"` | 老 server 4 char → defensive,记 §Followup |
| H5 | SQLException.message + sqlState + errorCode 三字段提取 | catch (e: SQLException) 后 e.message + e.sqlState + e.errorCode 是否都可访问;Error 基类只定义 message,本 D extend SQLException 加 sqlState + errorCode 两字段是否 SS class extends 支持 | Phase 1 spike 实测 catch (e: SQLException) e.message(继承 Error)+ e.sqlState(本 class 加)+ e.errorCode(本 class 加)| 字段不可访问 → 编译器扩 §Followup;若可访问但 message 串不流 → constructor 显式调 super(message)|
| H6 | catch (e: SubClass) 嵌套 throw 不会双层叠加 stack | JdbcTemplate.update 内部 try / catch SQLException → translate → throw DAE,业务侧 try / catch DAE,双层 try / catch SS 实现是否正常 unwind(不会 throw 后 stack 残留)| Phase 4 spike 双层 try/catch 实测 + Phase 5 Case 6 try-catch-chain 多层覆盖 | unwind 错位 → bootstrap codegen 检查 finally 路径 + 编译器扩 §Followup |
| H7 | tests/d134-d138 调用方升级 throw 后 baseline 不降 | 调用方升级 ~30+ 处:commit / rollback / setAutoCommit / executeUpdate / executeQuery / getGeneratedKeys + tests/d134/d135/d136/d138 各 ~5-10 调用方;升级量大,baseline 风险高 | Phase 2 拆 commit(协议层 throw + 调用方升级各独立 commit)+ 全测 baseline 升级后逐 commit 验证 | 任何 test 红 → 回 Phase 2 修 thin wrapper / catch 路径 |
| H8 | Spring SQLExceptionTranslator 反查表完整性 | MySQL Connector/J 5+ 主类 + Spring 完整 SQLErrorCodes XML 反查 — SS 简化为 SS function 表是否覆盖足够 | Phase 3 内置 MySQL 6+ errorCode 主映射 + Phase 5 测试覆盖;不足 → 默认 fallback DataAccessResourceFailureException + §Followup F? 加映射 | 反查不全 → §Followup 加映射,不阻 Phase 5 收关 |
| H9 | Connection.commit / rollback / setAutoCommit 内部 ERR sentinel 调用方升级 throw 后 D134 transaction 测试是否兼容 | tests/d134_mysql/transaction_test.ss(若存)+ d138 Case 5 transaction 持久 调用 commit() — sentinel 改 throw 后 try/catch 包裹 | Phase 2 调用方升级 + Phase 5 Case 5 transaction 重测 GREEN | transaction 路径回归 → Phase 2 拆 commit + 单 commit 修 |
| H10 | docker MySQL 探活失败时 fallback skip 路径升级 throw 后兼容 | tests/d134/d135/d136/d138 既有 fallback `if (probe.isClosed() == 1) { println("..."); return 0 }` — Phase 5 tests/d139 沿用,不动既有 fallback 模式 | Phase 5 沿用 d134-d138 fallback skip 模式 | 若新模式需 try/catch fallback → §Followup 提取 helper |

---

## A.3 废案

- **C1 数据层 sentinel patch / `class ErrorPacket` getter**(用户对话锁 3a + 4 不接受 — 不消除根因 + JDBC `throw SQLException` spec 仍缺)
- **C2 接口层 trap 简化**(3 主 SQLException + 7 主 DAE — 用户对话锁 1b + 2b 不接受简化,完整 ~10 + 15+ 子类)
- **保留 `RESULT_SET_HEADER_ERR = -1` 与 throw 共存**(违反 §核心原则 3 删 sentinel)
- **保留 `readUpdateResult(fd): int` thin wrapper 向后兼容**(D138 §核心原则 5 退役;C3 全删)
- **保留 `errMsg + println("MySQL: ...")` 路径**(违反 §核心原则 4 全升级 throw)
- **DAE 内部存 sqlState / errorCode 重复字段**(走 `cause: SQLException` 链 — Spring `getRootCause()` 标准)
- **修编译器加 throw / catch 新功能**(SS 已完整支持 typed try/catch/throw class extends — `tests/phase5/` 实证 GREEN)
- **cursor server-side scrollable ResultSet**(D138 §A.3 锚 留 D146+ 独立 sub-D — 本 D 仅 SQLException + DAE)
- **NamedParameterJdbcTemplate `:name` 参数**(D138 §Followup F4 留独立 sub-D — 本 D 不混入)
- **HikariCP Connection Pool**(D137 §F6 留 D125+ 独立 sub-D — 本 D 不混入)
- **batchUpdate / addBatch / executeBatch**(D138 §Followup F7 留独立 sub-D — 本 D 不混入)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `68a8184` (2026-04-29)

- 本文档落档:Status / 核心目标 / 核心原则 / Context / Tools / Orchestration / State / Evaluation / Constraints / §A.1 主候选 + §A.2 隐藏假设 H1-H10 + §A.3 废案 / Phase 0-5 计划草案 / Followup
- d_doc_index_linter F1 = 0 PASS(D139 加入未破 referenced Ds — D025/D134/D135/D136/D137/D138 实存)
- next_prompt_ultrathink_linter PASS

### Phase 1: 协议层 ErrorPacket + JDBC SQLException 主子类 + spike [✓] Done at commit `04821ce`

- `lib/com/mysql/query.ss` 加 `class ErrorPacket { errorCode: int, sqlState: string, errorMessage: string }`(D139 §核心原则 5 — 完整 ERR_Packet spec)— 兑现 file:line `lib/com/mysql/query.ss:131-135`
- `lib/com/mysql/query.ss` 加 `parseErrorPacket(payload, payloadLen): ErrorPacket` — 0xFF header + 2 byte LE error_code + sql_state_marker `#`(0x23,旧 server 防御 backward compat)+ 5 char sql_state(default "HY000")+ rest error_message — 兑现 file:line `lib/com/mysql/query.ss:137-161`
- `lib/java/sql.ss` 加 JDBC SQLException 完整子类 hierarchy(12 类:1 顶层 + 3 主 + 8 中间)— 兑现 file:line `lib/java/sql.ss:114-159`:
  - `class SQLException extends Error { sqlState: string, errorCode: int }`(JDBC `java.sql.SQLException` 顶层 — sql.ss:141-144)
  - 3 主子类:`SQLNonTransientException` / `SQLTransientException` / `SQLRecoverableException`(sql.ss:146-148)
  - 5 NonTransient 中间层:`SQLNonTransientConnectionException` / `SQLIntegrityConstraintViolationException` / `SQLSyntaxErrorException` / `SQLDataException` / `SQLFeatureNotSupportedException`(sql.ss:150-154)
  - 3 Transient 中间层:`SQLTransientConnectionException` / `SQLTransactionRollbackException` / `SQLTimeoutException`(sql.ss:156-158)
- spike `/tmp/test_d139_phase1.ss`:cross-module throw `new SQLNonTransientConnectionException(...)` + catch 3 层继承(`SQLNonTransientConnectionException → SQLNonTransientException → SQLException` 父类 catch 子类实例)+ Test 4 父类 catch 子类延伸到 Error 基类 4 层 + Test 5 catch fallthrough(具体 leaf 优先 / 父类兜底)+ Test 7-8 sibling subtree(NonTransient vs Transient)+ 三字段提取(e.message 继承 Error / e.sqlState / e.errorCode)8/8 PASS — D139 §A.2 H1 (跨 module 多层继承)+ H5(三字段提取)实证 GREEN
- VCM 验证:bootstrap 三阶段固定点 PASS + tests/phase5/typed_catch + throw_error + error_class baseline GREEN(SS try/catch 不动)+ tests/d134_mysql 5/0/5 + d135_caching_sha2 1/0/1 + d136_prepared_statement 1/0/1 + d138_generated_keys 1/0/1 baseline 不破 + tests/d141-d144 反推 baseline 全绿(5/6/6/8)+ tests/phase5 全 dir 194/0/4(4 fail 全 pre-existing 与不带本 Phase 改动的 stash 状态一致)+ reflection_health GATE PASS no regressions(本 Phase 不动 bootstrap)+ d_doc_index GATE OK(11 referenced Ds all live)

### Phase 2: 协议层全 throw + 删 sentinel + 调用方升级 [✓] Done at commit `dd0ef4a`

- `lib/com/mysql/query.ss` 删 sentinel:`const RESULT_SET_HEADER_ERR = -1`(原 line 23 删)+ `function readUpdateResult(fd: int): int` thin wrapper(原 line 186-188 删)+ `function parseOkPacketAffectedRows(payload, payloadLen): int` thin wrapper(原 line 108-110 删)— D138 §核心原则 5 退役兑现
- `lib/com/mysql/query.ss:52-65 parseResultSetHeader / readResultSetHeader` ERR path → `throw(dispatchSQLException(parseErrorPacket(...)))`,OK 仍 RESULT_SET_HEADER_OK,empty payload 仍 0
- `lib/com/mysql/query.ss:163-178 readUpdateResultPacket` ERR / short read / unrecognised header → 全 throw(ERR 走 dispatchSQLException 反查 / short read + unrecognised → SQLNonTransientConnectionException sqlState 08000)
- `lib/com/mysql/query.ss:180-204` 加 `sqlStateClass(s) + dispatchSQLException(ep): SQLException` SQLState 前 2 char 反查 dispatch:`08`/`28` → SQLNonTransientConnectionException、`23` → SQLIntegrityConstraintViolationException、`40` → SQLTransactionRollbackException、`42` → SQLSyntaxErrorException、`0A` → SQLFeatureNotSupportedException、`22` → SQLDataException、其他 → SQLException 顶层 fallback
- `lib/com/mysql/handshake.ss:240-301 mysqlConnect` 删 errMsg + `println("MySQL: ...")` + `return -1` 路径(共 16 处 errMsg 赋值 + 1 处 println + 1 处 return -1 全删),全 throw SQLNonTransientConnectionException(sqlState 08001 wire failure)+ ERR packet path → dispatchSQLException(parseErrorPacket(...)) 反查具体子类(28xxx invalid auth → SQLNonTransientConnectionException);imports 加 `parseErrorPacket / dispatchSQLException` from query.ss + `SQLException / SQLNonTransientConnectionException` from sql.ss
- `lib/com/mysql/jdbc.ss:23` import 删 `readUpdateResult`,保留 `readUpdateResultPacket`;`MysqlConnection.commit / rollback / setAutoCommit` 改调 `readUpdateResultPacket` 透传 throw(返 OkPacket discarded);`MysqlStatement.executeQuery / executeUpdate / execute` 删 `if (rows >= 0)` 守卫(D138 §A.2 H7 sentinel 守卫退役)+ executeUpdate / execute 直接调 readUpdateResultPacket → okPacketAffectedRows / okPacketLastInsertId 透传;`getMysqlConnection:148-167` 删 `if (fd < 0) { closed = 1 }` sentinel 守卫,直接 `return new MysqlConnection(fd, 1, 0)`(connection 失败已透传 mysqlConnect throw)
- `lib/com/mysql/prepared.ss:551-555 MysqlPreparedStatement.executeUpdate` 删 D138 §A.2 H7 sentinel 守卫 + 透传 throw;executeQuery 不变(透传 readQueryResultSetBinary → parseResultSetHeader throw)
- **§A.2 H1 实测破裂 + 编译器 1 处扩**:Phase 2 `bin/ss build tests/d134_mysql/integration_test.ss` 实测 spring/data → spring/jdbc → java/sql → mysql/jdbc → mysql/query 链式 import 触发 `getelementptr %SQLException, ptr ..., i32 0, i32 3` LLVM `base element of getelementptr must be sized` forward-ref(SQLException type decl 在 sql.ss IR 段,query.ss throw site 在前);走 H1 失败回路 fallback —— `bootstrap/gen/stmts/stmts_exc.ss:183-205 genThrow` 改 byte-offset GEP(`getelementptr i8, ptr %obj, i64 ${idx*8}` + `load ptr`)替具体 `%${exprType}` GEP,类型无关 layout 直接 i8 byte offset bypass forward-ref;getFieldIndex(exprType, "message") 仍计算正确 offset,语义不变;Phase 1 spike `/tmp/test_d139_phase1.ss` 8/8 + tests/phase5/typed_catch.ss + throw_error.ss + error_class.ss 全 PASS 实证 byte-offset GEP 与具体类型 GEP 等价
- `tests/d134_mysql/integration_test.ss` + `tests/d134_mysql/query_test.ss` + `tests/d135_caching_sha2/integration_test.ss` + `tests/d136_prepared_statement/integration_test.ss` + `tests/d138_generated_keys/integration_test.ss` 调用方升级 try/catch:
  - probe 路径 `if (probe.isClosed() == 1) { skip }` → `try { probe... } catch (e: SQLException) { skip }`(d134/d135/d136/d138 沿用 fallback skip 模式,docker 离线时 0 阻 `bin/ss test tests/`)
  - d134 query_test.ss `parseResultSetHeader ERR (0xFF) returns -1` test → `try { ... } catch (e: SQLException) { caught = 1 }`;`parseOkPacketAffectedRows(...)` → `parseOkPacket(...).affectedRows`(thin wrapper 退役)
  - d135 wrong pwd / fresh user `assertEqual(conn.isClosed(), 1)` → `try { DriverManager_getConnection(...) } catch (e: SQLException) { caught = 1 }`(2 case)
  - d138 Case 6 `assertEqual(r, -1)` → `try { stmt.executeUpdate(...) } catch (e: SQLSyntaxErrorException) { caught = 1 }`(table not exist → SQLState 42S02 → 类 42 → SQLSyntaxErrorException)
- `tests/d139_sql_exception/integration_test.ss` Phase 2 spike 新建:`INSERT INTO d139_dup_test (id, name) VALUES (1, 'first')` + 再次 INSERT 同 id → `catch (e: SQLIntegrityConstraintViolationException)` + `e.sqlState == "23000"` + `e.errorCode == 1062` 实证 — D139 §A.2 H3 (MySQL errorCode 1062 + SQLState 23000 标准) 实测路径(docker 离线 fallback skip 沿 d134/d136/d138 模式);Phase 5 7 形态完整版扩展同 dir
- VCM 六验全 PASS:bootstrap 三阶段固定点(stmts_exc.ss byte-offset GEP fix 后 stage2 == stage3)+ tests/d134-d139 5/0/5(d134_mysql / d135_caching_sha2 / d136_prepared_statement / d138_generated_keys / d139_sql_exception 各 1 file)+ tests/d141-d144 5/0/5 反推 baseline 不破 + tests/phase5 194/0/4(4 fail 全 pre-existing 与 Phase 1 baseline 一致)+ reflection_health GATE PASS no regressions(N3 569530/565400 软警 AUTO-DRIFT 1% 内不阻)+ d_doc_index GATE OK 12 referenced Ds all live

### Phase 3: Spring DAE 完整树 + SQLExceptionTranslator [✓] Done at commit `be394f5`

- `lib/spring/jdbc.ss` 加 Spring DAE 完整树 14 子类(1 顶层 + 2 中间 + 5 NonTransient 子 + 1 DataIntegrity 子 + 2 DataRetrieval 子 + 2 Transient 子 + 1 Concurrency 子)— 兑现 file:line `lib/spring/jdbc.ss:60-108`:
  - 顶层:`class DataAccessException extends Error { cause: SQLException }`(jdbc.ss:87-89 — Spring `org.springframework.dao.DataAccessException`,加 `cause: SQLException` 字段透传 wire-protocol sqlState/errorCode 到业务侧 `e.cause.sqlState`)
  - 中间:`NonTransientDataAccessException` / `TransientDataAccessException`(jdbc.ss:91-92,均 extends DataAccessException 空 body)
  - NonTransient 子树:`DataIntegrityViolationException` / `BadSqlGrammarException` / `CannotGetJdbcConnectionException` / `DataAccessResourceFailureException` / `DataRetrievalFailureException`(jdbc.ss:94-98,均 extends NonTransientDataAccessException)
  - DataIntegrity 子树:`DuplicateKeyException extends DataIntegrityViolationException`(jdbc.ss:100)
  - DataRetrieval 子树:`EmptyResultDataAccessException` / `IncorrectResultSizeDataAccessException`(jdbc.ss:102-103,均 extends DataRetrievalFailureException)
  - Transient 子树:`TransientDataAccessResourceException` / `ConcurrencyFailureException`(jdbc.ss:105-106,均 extends TransientDataAccessException)
  - Concurrency 子树:`DeadlockLoserDataAccessException extends ConcurrencyFailureException`(jdbc.ss:108)
- `lib/spring/jdbc.ss` 加 `class SQLExceptionTranslator { translate(ex: SQLException): DataAccessException }` — 兑现 file:line `lib/spring/jdbc.ss:117-145`(简化 Spring `org.springframework.jdbc.support.SQLErrorCodeSQLExceptionTranslator`)反查表:
  - **MySQL errorCode 主映射**(优先于 SQLState,jdbc.ss:125-132):
    - 1062 → DuplicateKeyException(:125)
    - 1048 → DataIntegrityViolationException(NOT NULL,:126)
    - 1452 → DataIntegrityViolationException(FK,:127)
    - 1146 → BadSqlGrammarException(table not exist,:128)
    - 1054 → BadSqlGrammarException(column unknown,:129)
    - 1213 → DeadlockLoserDataAccessException(:130)
    - 1205 → ConcurrencyFailureException(lock wait timeout,:131)
    - 1045 → CannotGetJdbcConnectionException(invalid auth,:132)
  - **SQLState 前 2 char fallback**(jdbc.ss:135-141):
    - `08` → CannotGetJdbcConnectionException(connection failure,:137)
    - `28` → CannotGetJdbcConnectionException(invalid auth,:138)
    - `23` → DataIntegrityViolationException(integrity,:139)
    - `40` → DeadlockLoserDataAccessException(rollback,:140)
    - `42` → BadSqlGrammarException(syntax,:141)
  - **默认 fallback**:`DataAccessResourceFailureException`(jdbc.ss:143)
- spike `tests/d139_sql_exception/translator_spike_test.ss` 12/12 GREEN(纯本地无 docker 依赖):Test 1 1062 → DuplicateKey + cause 三字段透传 / Test 2 1048 → DataIntegrityViolation / Test 3 1146 → BadSqlGrammar / Test 4 1213 → DeadlockLoser / Test 5 1045 → CannotGetJdbcConnection / Test 6 SQLState 28xxx (errorCode 0) → CannotGetJdbcConnection fallback / Test 7 SQLState 23xxx (errorCode 0) → DataIntegrityViolation fallback / Test 8 unknown errorCode + sqlState (HY000/9999) → DataAccessResourceFailure default / Test 9-11 DuplicateKey 实例被 DataIntegrityViolation 父 / NonTransientDataAccess 祖父 / DataAccessException 根 catch (4 层 catch hierarchy 实证)+ Test 12 Deadlock 实例被 Concurrency 父 / Transient 祖父 catch — D139 §A.2 H1 跨 module DAE class hierarchy + H6 multi-level fallthrough catch unwind 实证 GREEN
- VCM 六验全 PASS:bootstrap 三阶段固定点(本 Phase 不动 bootstrap,只动 lib/ + tests/)+ tests/d134_mysql + d135_caching_sha2 + d136_prepared_statement + d138_generated_keys + d139_sql_exception 5/0/5(d139 dir 含 Phase 2 integration_test.ss + Phase 3 translator_spike_test.ss 各 1 file)+ tests/d141-d144 inference 5/0/5(各 dir 名 d141_lambda_inference / d142_array_literal_inference / d143_object_literal_inference / d144_ternary_inference)反推 baseline 不破 + tests/phase5 194/0/4(4 fail 全 pre-existing 与 Phase 2 baseline 一致)+ reflection_health GATE PASS no regressions(M2/M3a/M4/M5/M7b/N2/N3 AUTO-DRIFT 1% 内软警告不阻)+ d_doc_index GATE OK 12 referenced Ds all live

### Phase 4: JdbcTemplate 上层 catch / translate [✓] Done at commit `<Phase 4 commit>`

- `lib/spring/jdbc.ss` JdbcTemplate 11 method(execute×2 / update×3 / queryForList×2 / queryForString×2 / queryForInt×2)全 method 上层 try / catch (e: SQLException) → `new SQLExceptionTranslator().translate(e)` → `throw DAE` — Spring 标准 — 兑现 file:line `lib/spring/jdbc.ss:166-394`(execute :166-186 / execute(setter) :188-209 / update :210-229 / update(setter) :231-252 / update(setter,kh) :255-289 / queryForList :294-303 / queryForList(setter) :308-318 / queryForString :320-336 / queryForString(setter) :338-354 / queryForInt :356-372 / queryForInt(setter) :374-390)
- 内部 per-call Connection 路径(D137/D138):嵌套 try-finally `{ const conn = ...; try { const stmt = ...; try { ... } finally { stmt.close() } } finally { conn.close() } }` 包外层 try-catch 兑现"内部 close 在 finally"(throw 路径 stmt.close + conn.close 仍跑,顺序 inner finally → middle finally → outer catch — `tests/phase5/finally_basic.ss` test4 "TFC" 链 + `/tmp/test_d139_phase4_throw_path.ss` Phase 4 spike 实证);catch (e: SQLException) 路径 → `translator.translate(e)` → `throw(...)` DAE 子类
- queryForList × 2 是流式异常路径:返回 ResultSet alias socket(D137 锁 caller 持有 fd → caller rs.close()),无法 finally close stmt/conn → 仅包 try-catch translate(失败路径 stmt+conn leak — D137 简单 per-call 模型,HikariCP D125+ pool reclaim 收尾,注释标 jdbc.ss:289-292)
- queryForString / queryForInt 上层 try { rs = this.queryForList(...); inner try { rs.next + getXxx } finally { rs.close } } catch (SQLException) translate — 内层 finally 担保 rs.close(success + throw 双路径)
- D137 5 setter method 签名零破(execute/update/queryForList/queryForString/queryForInt 含重载 11 method 完整,与 jdbc.ss:151 baseline 同形)+ D138 KeyHolder 第 6 method update(sql,setter,kh) 契约零破(getKeyList push GENERATED_KEY 路径在 outer try 内,rs.close finally 担保)
- spike `tests/d139_sql_exception/phase4_spike_test.ss` 3/3 GREEN(docker 在线时实测,离线 fallback skip 沿 d134/d136/d138/Phase 2 模式):Test 1 jdbc.update INSERT dup_key 触发 1062 → SQLIntegrityConstraintViolationException → SQLExceptionTranslator → throw DuplicateKeyException;业务侧 catch (ex: DuplicateKeyException) + ex.cause.sqlState == "23000" + ex.cause.errorCode == 1062 + ex.message.length() > 0 — D139 §核心目标 第 2 判据 + §A.2 H1 跨 module DAE class hierarchy 实证;Test 2 父类 catch DataIntegrityViolationException + 根类 catch DataAccessException 同实例 → 4 层 hierarchy(DuplicateKey → DataIntegrityViolation → NonTransientDAE → DAE)兑现 + ex.cause.errorCode == 1062 在根类 catch 仍可达;Test 3 dup_key throw 多次后 jdbc.queryForInt(SELECT id) 仍 GREEN — finally-close 担保 socket 不饥饿(否则 prepared statement handle / fd 累积 server-side desync)
- 编译器零改动(本 Phase 纯 lib/ + tests/);SS try / catch / finally / nested try-finally + outer try-catch + return inside try + throw → inner finally → outer catch hierarchy 全实证可用(`/tmp/test_d139_phase4_finally_return.ss` "TF1F2" 嵌套 finally + `/tmp/test_d139_phase4_throw_path.ss` "TFC:boom" throw 链 + `/tmp/test_d139_phase4_returnpath.ss` D007 return-path 接受 try-return + catch-throw 模式)
- VCM 六验全 PASS:bootstrap 三阶段固定点(本 Phase lib/ + tests/ 改触 build cache,stage2 == stage3)+ tests/d134_mysql 5/0/5 + d135_caching_sha2 1/0/1 + d136_prepared_statement 1/0/1 + d138_generated_keys 1/0/1 + d139_sql_exception 3/0/3(Phase 2 integration_test + Phase 3 translator_spike_test + Phase 4 phase4_spike_test 各 1 file)+ tests/d141-d144 inference 25/0/25(d141 5 + d142 6 + d143 6 + d144 8)反推 baseline 不破 + tests/phase5 194/0/4(4 fail 全 pre-existing 与 Phase 1/2/3 baseline 一致 — spring_web_params + harness_task/main + d096_p4_l2_reactive + harness_bug/main)+ reflection_health GATE PASS no regressions(M2/M3a/M4/M5/M7b/N2/N3 AUTO-DRIFT 1% 内软警告不阻 + F1 PROGRESS bootstrap/gen/methods/gen_methods.ss 730→728→711 + bootstrap/gen/gen_decls.ss 730→730→726)+ d_doc_index GATE OK 12 referenced Ds all live;**本 Phase 仅 wrap 不重写**(JdbcTemplate 11 method 业务逻辑 prepareStatement / setter / executeUpdate / getGeneratedKeys / executeQuery 路径全保留,仅外层加 try-catch + 内层加 try-finally — D137 per-call Connection 契约 + D138 KeyHolder 契约 + ResultSet 透传 caller 契约全零破)

### Phase 5: 测试覆盖 7 形态 + 全 Phase 收关 [ ] Pending at commit `<Phase 5 commit>` — D139 主线 close

- 新建 `tests/d139_sql_exception/integration_test.ss`(D139 §核心目标 7 判据全形态实证)+ docker MySQL 探活 fallback skip(d134/d136/d138 模式 — `probe.isClosed() == 1` 时 println + return,`bin/ss test tests/` 离线零阻塞)
- **Case 1**(connection 失败):wrong password URL → catch CannotGetJdbcConnectionException + sqlState 28xxx + errorCode 1045 — D139 §核心目标 第 1 判据
- **Case 2**(INSERT duplicate key):`INSERT INTO d139_test (id, name) VALUES (1, 'first')` + 再次 INSERT 同 id → catch DuplicateKeyException + sqlState 23000 + errorCode 1062 — D139 §核心目标 第 2 判据 + §A.2 H3 实证
- **Case 3**(table 不存在):`INSERT INTO d139_does_not_exist VALUES (1)` → catch BadSqlGrammarException + sqlState 42S02 + errorCode 1146 — D139 §核心目标 第 3 判据
- **Case 4**(NOT NULL violation):INSERT 漏 NOT NULL column → catch DataIntegrityViolationException + sqlState 23000 + errorCode 1048 — D139 §核心目标 第 4 判据
- **Case 5**(SQLException 字段):catch (e: SQLException) 后 `e.message != ""` + `e.sqlState != ""` + `e.errorCode > 0` 三字段 — D139 §核心目标 第 5 判据 + §A.2 H5 实证
- **Case 6**(try/catch chain):业务侧 try → catch DuplicateKeyException(具体)→ catch DataIntegrityViolationException(中间)→ catch DataAccessException(顶层 fallthrough)5 层继承 — D139 §核心目标 第 6 判据 + §A.2 H2 + H6 实证
- **Case 7**(handshake 失败 wrong user):`jdbc:mysql://wronguser:wrongpass@127.0.0.1:3307/testdb` → catch SQLNonTransientConnectionException + sqlState 28000 + errorCode 1045(MySQL "Access denied" 标准)— D139 §核心目标 第 7 判据 + §A.2 H1 跨 module throw 实证
- 表名 `d139_sql_exception_test`(隔离 D134 users / D136 users_d136 / D138 d138_generated_keys 并行批量);URL `jdbc:mysql://root:test@127.0.0.1:3307/testdb`(沿 D134 docker fixture)
- **§Phase 收关锚 §Phase 5 mark Done**:全 Phase commit hash 总览(Phase 0-5 6 个 hash)+ 兑现成果汇总 file:line 锚 + Followup F1+ 锚明确 + Status 时间线 Phase 5 行落档
- **VCM 六验全 PASS**:§1 工程豁免 + §2 行为(D139 doc Phase 5 收关章节 grep PASS)+ §3 反向(撤回 Phase 5 收关章节 → §Phase 收关锚 §Phase 5 仍 `[ ]` 占位符)+ §4 边界(Followup 全锚 + 兑现成果 file:line 全核对)+ §5 路线(D135-D138 + D139 SQL 主线范式延续)+ §6 根因(file:line 锚 = D139 §Phase 收关锚 §Phase 5 mark Done + 全 Phase commit hash 总览)
- baseline 不破:tests/d134-d138 + d141-d144 + 全 tests/ baseline 不降;reflection_health GATE PASS no regressions;d_doc_index GATE OK
- D135-D139 SQL 主线范式延续(每 Phase 独立 commit + Status 收关 + commit hash 回填 + next_prompt 自闭环)— **D139 主线 close,后续等用户指定下一 SQL 主线 sub-D**(D138 §Followup F3-F7:F3 cursor / F4 NamedParameterJdbcTemplate / F5 RowMapper<T> 依赖泛型 / F6 HikariCP / F7 batchUpdate / F1 SESSION_TRACK)

---

## Followup

| # | 项 | 说明 |
|---|---|---|
| F1 | SQLState 完整 ASCII class 反查表(JDBC 4.3 §13.4 + ANSI/ISO SQL:2016 Annex C) | 本 D Phase 2 + 3 已覆盖 6+ 主 class(`08` / `23` / `40` / `42` / `0A` / `22` / `28` / `HY`),完整 ~25 主 class 含 `01` warning / `02` no_data / `07` dynamic_sql_error / `09` triggered_action_exception / `2A` syntax_error_or_access_rule_violation_in_direct_sql / `2B` dependent_privilege_descriptors / `2C` invalid_character_set / `2D` invalid_transaction_termination / `2E` invalid_connection / `2F` sql_routine_exception / `33` invalid_sql_descriptor / `34` invalid_cursor_name / `35` invalid_condition_number / `36` cursor_sensitivity_exception / `37` syntax_error_or_access_rule_violation_in_dynamic_sql / `38` external_routine_exception / `39` external_routine_invocation_exception / `3B` savepoint_exception / `3C` ambiguous_cursor_name / `3D` invalid_catalog_name / `3F` invalid_schema_name / `44` with_check_option_violation / `HZ` rda_warning — 留 §Followup 完整版|
| F2 | MySQL errorCode 完整反查表(MySQL Connector/J ~150+ errorCode) | 本 D Phase 3 已覆盖 8 主映射(1062 / 1048 / 1452 / 1146 / 1054 / 1213 / 1205 / 1045),Spring 完整 SQLErrorCodes XML ~150+ MySQL errorCode 留 §Followup 扩 — D146+ 独立 sub-D 或合并 PostgreSQL/SQLite errorCode 路径 |
| F3 | server-side cursor + scrollable ResultSet | D138 §Followup F3 锚同位 — 留 D146+ 独立 sub-D(MySQL `useCursorFetch=true` + ResultSet TYPE_SCROLL_INSENSITIVE / TYPE_SCROLL_SENSITIVE)|
| F4 | NamedParameterJdbcTemplate `:name` 参数 + KeyHolder + SQLException 整合 | D138 §Followup F4 锚同位 — 留独立 sub-D(本 D 落地 SQLException 后,F4 自动获益 try/catch translate 路径)|
| F5 | RowMapper<T> 泛型 callback + SQLException 整合 | D138 §Followup F5 锚同位 — **强依赖 SS 泛型 D026/D027** — 留独立 sub-D |
| F6 | HikariCP Connection Pool + SQLRecoverableException 整合 | D138 §Followup F6 锚同位 — 留独立 sub-D(连接池失效场景 throw SQLRecoverableException 触发自动重连)|
| F7 | batchUpdate / addBatch / executeBatch + BatchUpdateException(JDBC `java.sql.BatchUpdateException` 子类)整合 | D138 §Followup F7 锚同位 — 留独立 sub-D(批量 INSERT 部分失败 throw BatchUpdateException + getUpdateCounts() 部分成功 / 失败索引)|
| F8 | OK packet `info string` 字段 SESSION_TRACK 路径 | D138 §Followup F1 锚同位 — niche,可合并入其他 sub-D |
| F9 | DAE 内部 `getRootCause(): SQLException` Spring 标准 method | 本 D Phase 3 DAE.cause 已就位,getRootCause() 取 cause 链根 helper 留 §Followup(Spring 5+ 标准 — 业务侧少用)|
| F10 | SS arrow-function closure capture rebinds outer-scope catch `e` | Phase 2 spike `tests/d139_sql_exception/integration_test.ss` 实测:`main()` 外层 probe `catch (e: SQLException)` 与内层 arrow `() => { ... catch (e: SQLIntegrityConstraintViolationException) { e.sqlState } }` 同名 `e` 触发 SS closure free-var 检测误把 inner catch e 视作 outer e capture,导致 IR `Instruction does not dominate all uses!`(arrow body 引用 outer e.710 alloca,but outer alloca 仅在 catch.body branch 而非 arrow 入口前 dominate);本 Phase workaround 内层重命名 `e → ex`,留 §Followup 修 bootstrap closure capture(arrow function free-var 检测应排除 inner catch declared 同名 var)|

---

## Status 时间线

- 2026-04-29 Phase 0 D 文档落档(commit `68a8184`)— D138 §Followup F2 + §A.3 废案 §C3 SQLException 部分 起首落档;C3 完整 JDBC 4.3 §13 + Spring DAE 完整 + 删 sentinel + 全升级 throw 决策(用户对话锁 1b + 2b + 3a + 4:**最优最佳 / 完整子类 / 删 sentinel / 全升级 throw**);§A.1 三主候选 + §A.2 H1-H10 隐藏假设挑战 + §A.3 废案 + Phase 0-5 计划草案 + Followup F1-F9;D135-D138 SQL 主线范式延续(每 Phase 独立 commit + Status 收关 + commit hash 回填 + next_prompt 自闭环);**元层校准锚**:用户回 SQL 主线后 D139 是 D138 §Followup F2 直接续接,sub-D 范畴 SQLException + DAE(cursor 留 D146+)
- 2026-04-29 Phase 1 协议层 ErrorPacket + JDBC SQLException 完整 12 类 hierarchy + spike 跨 module 3 层继承 GREEN(commit `04821ce`)— `lib/com/mysql/query.ss` 加 `class ErrorPacket { errorCode, sqlState, errorMessage }`(:131-135)+ `parseErrorPacket(payload, payloadLen)`(:137-161,0xFF + 2 byte LE error_code + 0x23 marker + 5 char sql_state(默认 "HY000")+ rest error_message,旧 server 无 marker defensive `HY000` fallback);`lib/java/sql.ss` 加 SQLException 完整 hierarchy(:114-159 — 1 顶层 + 3 主子类 NonTransient/Transient/Recoverable + 5 NonTransient 中间层 + 3 Transient 中间层 = 12 类,空 body extends 透传 SQLException 三字段);spike `/tmp/test_d139_phase1.ss` 8/8 PASS(Test 1-4 1/2/3/4 层父类 catch 子类 + Test 5-6 catch fallthrough 优先级 + Test 7-8 sibling subtree NonTransient vs Transient + 三字段 e.message + e.sqlState + e.errorCode 全实证 — H1 跨 module + H5 三字段实证 GREEN);VCM 六验全 PASS — bootstrap 固定点 + phase5 try/catch 三测 + d134-d138 + d141-d144 + 反射 + d_doc_index 全绿;**本 Phase 仅 add 不 mutate**(留 sentinel / errMsg+println / commit/rollback 调用方 至 Phase 2 升级 throw — D139 §核心原则 4 全升级)
- 2026-04-29 Phase 3 Spring DAE 完整 14 子类树 + SQLExceptionTranslator 反查表 + spike 12/12 GREEN(commit `be394f5`)— `lib/spring/jdbc.ss` 加 Spring DAE 完整树 14 子类(:60-108 — DAE 顶层 :87-89 加 `cause: SQLException` 字段 / NonTransientDAE+TransientDAE 中间 :91-92 / NonTransient 子树 5 类 :94-98 / DuplicateKey :100 / DataRetrieval 子树 EmptyResult+IncorrectResultSize :102-103 / Transient 子树 TransientResource+Concurrency :105-106 / DeadlockLoser :108)+ `class SQLExceptionTranslator` 反查表(:117-145 — MySQL errorCode 8 主映射 :125-132 优先 / SQLState 前 2 char 5 fallback :137-141 / 默认 DataAccessResourceFailure :143);spike `tests/d139_sql_exception/translator_spike_test.ss` 12/12 GREEN 纯本地无 docker(Test 1-8 8 路径反查 dispatch 全形态 + Test 9-12 4 层 catch hierarchy 父类 / 祖父 / 根 catch DuplicateKey + Concurrency / Transient catch Deadlock 实证 — §A.2 H1 跨 module DAE class hierarchy + H6 multi-level fallthrough 实证);VCM 六验全 PASS — bootstrap 三阶段固定点(本 Phase 不动 bootstrap)+ d134-d139 5/0/5 + d141-d144 5/0/5 + phase5 194/0/4(与 Phase 2 baseline 一致)+ reflection_health GATE PASS no regressions + d_doc_index GATE OK 12 referenced Ds all live;**本 Phase 仅 add 不 mutate**(留 JdbcTemplate 上层 try/catch translate 至 Phase 4 — Spring 业务侧 catch DAE 不见底层 SQLException 的标准路径)
- 2026-04-29 Phase 2 协议层全 throw + 删 sentinel + 调用方升级 + spike INSERT dup_key catch SQLIntegrityConstraintViolationException + 编译器 1 处扩(commit `dd0ef4a`)— `lib/com/mysql/query.ss` 删 RESULT_SET_HEADER_ERR + readUpdateResult + parseOkPacketAffectedRows 三处 sentinel(D138 §核心原则 5 退役兑现)+ parseResultSetHeader / readUpdateResultPacket 走 throw + 加 sqlStateClass / dispatchSQLException 反查表(:180-204);`lib/com/mysql/handshake.ss` mysqlConnect 删 16 处 errMsg + println + return -1 路径,全 throw SQLNonTransientConnectionException(sqlState 08001) + ERR packet 反查 dispatchSQLException;`lib/com/mysql/jdbc.ss` MysqlConnection.commit/rollback/setAutoCommit + MysqlStatement.executeQuery/executeUpdate/execute 升级 throw(删 sentinel 守卫)+ getMysqlConnection 删 fd<0 → closed=1 sentinel;`lib/com/mysql/prepared.ss` MysqlPreparedStatement.executeUpdate 删 D138 §A.2 H7 sentinel 守卫;**§A.2 H1 实测破裂回路触发**:链式 import 时具体 `%SQLException` GEP forward-ref(spring/data → spring/jdbc → java/sql → mysql/jdbc → mysql/query),走 H1 失败回路 fallback —— `bootstrap/gen/stmts/stmts_exc.ss:183-205 genThrow` 改 byte-offset GEP(类型无关 i8 byte offset bypass forward-ref,getFieldIndex 仍计 offset 语义不变);tests/d134_mysql/integration_test.ss + query_test.ss + d135 + d136 + d138 调用方 try/catch 升级(probe 路径 + d135 wrong pwd / fresh user + d138 Case 6 ERR-path 防御 → catch SQLSyntaxErrorException);tests/d139_sql_exception/integration_test.ss Phase 2 spike 新建(INSERT dup_key catch SQLIntegrityConstraintViolationException + sqlState 23000 + errorCode 1062 — H3 实测路径,docker 离线 fallback skip);VCM 六验全 PASS — bootstrap 固定点(stmts_exc.ss fix 后 stage2 == stage3)+ d134-d139 5/0/5 + d141-d144 5/0/5 + phase5 194/0/4(与 Phase 1 baseline 一致)+ reflection_health GATE PASS no regressions + d_doc_index GATE OK
- 2026-04-29 Phase 4 JdbcTemplate 11 method 上层 try / catch (e: SQLException) → translator.translate(e) → throw DAE + 嵌套 try-finally 担保 stmt+conn close + queryForList 流式异常 leak-on-failure + spike `jdbc.update INSERT dup_key catch DuplicateKeyException` 3/3 GREEN(commit `<Phase 4 commit>`)— `lib/spring/jdbc.ss` JdbcTemplate 11 method(execute×2 / update×3 / queryForList×2 / queryForString×2 / queryForInt×2)全 wrap 外层 try-catch translate + 内层嵌套 try-finally close stmt+conn(execute :166-186 / execute(setter) :188-209 / update :210-229 / update(setter) :231-252 / update(setter,kh) :255-289 / queryForList :294-303 / queryForList(setter) :308-318 / queryForString :320-336 / queryForString(setter) :338-354 / queryForInt :356-372 / queryForInt(setter) :374-390);queryForList × 2 为流式异常路径(返回 ResultSet alias socket,caller 持 fd,失败路径 leak — D137 简单 per-call 模型 / HikariCP D125+ pool reclaim 收尾);D137 5 setter method 签名零破 + D138 KeyHolder 第 6 method 契约零破 + ResultSet 透传 caller 契约零破;spike `tests/d139_sql_exception/phase4_spike_test.ss` 3/3 GREEN(docker 在线时实测,离线 fallback skip 沿 d134/d136/d138/Phase 2 模式)— Test 1 业务侧 catch DuplicateKeyException + ex.cause.sqlState "23000" + ex.cause.errorCode 1062 + ex.message "Duplicate entry";Test 2 父类 catch DataIntegrityViolation / 根类 catch DataAccessException 同实例 4 层 hierarchy 兑现;Test 3 dup_key throw 多次后 jdbc.queryForInt(SELECT id) 仍 GREEN — finally-close 担保 socket 不饥饿;**SS try / catch / finally 嵌套实证**:`tests/phase5/finally_basic.ss` test4 "TFC" 链 + `/tmp/test_d139_phase4_finally_return.ss` "TF1F2" 嵌套 finally + `/tmp/test_d139_phase4_throw_path.ss` "TFC:boom" throw 链 + `/tmp/test_d139_phase4_returnpath.ss` D007 return-path 接受 try-return + catch-throw 模式;VCM 六验全 PASS — bootstrap 三阶段固定点(本 Phase lib/ + tests/ 改触 build cache,stage2 == stage3)+ d134_mysql 5/0/5 + d135 1/0/1 + d136 1/0/1 + d138 1/0/1 + d139 3/0/3(Phase 2+3+4 spike 各 1)+ d141-d144 inference 25/0/25(d141 5+d142 6+d143 6+d144 8)+ phase5 194/0/4(4 fail pre-existing 与 Phase 1/2/3 baseline 一致)+ reflection_health GATE PASS no regressions(M2/M3a/M4/M5/M7b/N2/N3 AUTO-DRIFT 1% 软警 + F1 PROGRESS bootstrap/gen/methods/gen_methods.ss 730→728→711)+ d_doc_index GATE OK 12 referenced Ds all live;**本 Phase 仅 wrap 不重写**(JdbcTemplate 11 method 业务逻辑 prepareStatement / setter / executeUpdate / getGeneratedKeys / executeQuery 路径全保留,仅外层加 try-catch + 内层加 try-finally — D137/D138 契约 + ResultSet 透传契约全零破)— Phase 5 7 形态完整测试覆盖留续作主线 close
