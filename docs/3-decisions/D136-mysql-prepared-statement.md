# D136: MySQL Prepared Statement 协议集成(COM_STMT_PREPARE / EXECUTE / CLOSE)

**Status:** [✓] Phase 0 落盘(commit `<回填>`)+ [ ] Phase 1 接口扩 + COM_STMT_PREPARE / [ ] Phase 2 EXECUTE + binary result set + CLOSE / [ ] Phase 3 e2e + JdbcTemplate retcon scope 评估

**Depends on:**
- D134 全 Phase 收关锚(commit `e509be1`)— `lib/com/mysql/{wire,handshake,query,jdbc}.ss` driver 实施层 + `tests/d134_mysql/` integration test 框架
- D135 全 Phase 收关锚(commit `1c2e07b`)— caching_sha2_password fast-path 直发模式 + `tests/d135_caching_sha2/` e2e
- CLAUDE.md §项目本质 L7 axiom("应用层 stdlib 用纯 SS 模块实现,不引入应用层 C 库")
- CLAUDE.md §项目技术规则 §Root Cause 优先 L91-103("第一法则,无例外")
- CLAUDE.md §项目技术规则 §交互式单文档(用户对话授权 2026-04-27 "集成 mysql + 推荐 ③")
- D025 Interface Dispatch
- `memory/feedback_root_cause_no_cost.md` / `memory/feedback_no_derive_workaround.md`(成本不是选次优 / 不留 fallback dead code)
- `docs/3-MNK.md` §M PSM 九问 / §N VCM 六验 / §大改档位规则

**承 D134 §6 follow-up ③ Prepared Statement candidate** + **D135 §Principles 11 范围外明确清单兑现** — 用户对话指令 2026-04-27 "我当前的需求是集成 mysql 你觉得下一个应该是哪个" → Claude 推荐 ③ Prepared Statement(SQL 注入根因 + binary protocol 性能根因 + ⑥⑦ 依赖前置)→ 用户 OK → D136 = COM_STMT_PREPARE / EXECUTE / CLOSE 协议集成 + binary result set codec + lib/java/sql.ss `interface PreparedStatement` 接口扩

**Date:** 2026-04-27
**Last Updated:** 2026-04-27

---

## 第一性需求

CLAUDE.md §项目本质 axiom 兑现深化 — D134 落地 driver 文本协议(COM_QUERY 0x03 + 文本 ResultSet 解析),tests/d134_mysql/integration_test.ss + lib/spring/jdbc.ss + lib/spring/data.ss 全 SQL 字符串拼接(`INSERT INTO users VALUES (1, 'Alice', 30)` 字面量 + 单引号 escape 风险),用户写业务无 `?` 占位符 API → 必须自己拼字符串 → SQL 注入暴露面持续。

**Why ①(直接症状层)**:tests/d134_mysql/integration_test.ss:73 实测 `stmt.executeUpdate("INSERT INTO users VALUES (1, 'Alice', 30)")` — 用户值 `'Alice'` 单引号必须自己 escape,整型 `30` 必须自己 string concat,driver-agnostic 接口层 `interface Statement` 仅 `execute(sql)` 一签名,**无 `setInt/setString/setLong/setDouble/setBoolean` 参数化 API**;Spring 层 `JdbcTemplate.execute / update / queryForString / queryForInt` 同模式 → SQL 注入暴露面是 OWASP top 10 #3(2021),业务层任何动态值都走拼接,根因在接口层缺位 + 协议层未实现。

**Why ②(协议性能层)**:文本协议 COM_QUERY 每次 query server 重新 parse SQL → 无 statement cache → 重复执行的 query(分页 / batch insert / 同一查询不同参数)server-side parser 开销重复;text protocol 整数 / 浮点 / timestamp 全 string-encode(`30` → `"30"`)后 server string-parse 回 binary,client side 收 result set 又把 binary → string → SS int → string → SS int 反复 encode/decode → **二进制协议加速失**(`MYSQL_TYPE_LONG` u32 LE 直 decode + `MYSQL_TYPE_DOUBLE` 8-byte IEEE 754 直 cast 全失)。

**末层断言可观测否定证据**:
```bash
grep -rnE "PreparedStatement|COM_STMT_PREPARE|prepareStatement" lib/com/mysql/ lib/java/sql.ss | wc -l
# 当前 = 0(本轮 Plan 实测)→ 不做 → 任何参数化查询走字符串拼接 → SQL 注入风险 + binary protocol 性能加速全失
```

---

## 核心目标 (Goal)

- **为什么**:**OWASP top 10 #3 SQL 注入根因解决**(参数化绑定是唯一正确防御)+ **binary protocol 性能根因解决**(server-side parse 一次 cache + binary value 直 decode 免去 string round-trip)+ D025 接口规约 PreparedStatement 抽象补齐(driver-agnostic 接口 + driver-specific 实现 双轨)+ D134 §6 ③ sub-D candidate 兑现
- **是什么**:lib/java/sql.ss `interface PreparedStatement extends Statement`(setInt/setString/setLong/setDouble/setBoolean + 重载 executeQuery() / executeUpdate())+ `Connection.prepareStatement(sql)` + lib/com/mysql/prepared.ss(新)= COM_STMT_PREPARE / COM_STMT_EXECUTE / COM_STMT_CLOSE 协议实施 + binary result set codec(NULL bitmap + binary value decode)+ jdbc.ss `class MysqlPreparedStatement : PreparedStatement` + e2e integration test
- **单一判据**:三轨闭环(§第一性需求 末层 grep + wire-level vec test + e2e)+ `./build.sh bootstrap` 三阶段固定点(纯 lib 改,Phase 1-3 后跑确认零冲击)+ tests/d134_mysql/ + tests/d135_caching_sha2/ baseline 不降(plugin / statement 层对 connection / authentication 层透明)+ axiom 红线 grep / nm = 0 永久

> 口号:**Prepared Statement 走根因 — 接口层 + 协议层 + 实施层三层齐落,SQL 注入零风险 + binary protocol 性能加速**(承 §Root Cause + memory `feedback_no_derive_workaround` + D135 "走根因 + 删 dead code" 范式)

---

## 核心原则 (Principles)

1. **driver-agnostic 接口扩 lib/java/sql.ss** — 加 `interface PreparedStatement extends Statement`(setInt/setString/setLong/setDouble/setBoolean + 重载 executeQuery() / executeUpdate())+ `Connection.prepareStatement(sql)` 接口方法;不破坏既有 `interface Statement` / `interface ResultSet` / `interface Connection` 签名
2. **driver-specific 实施 lib/com/mysql/prepared.ss(新)** — 纯 SS COM_STMT_PREPARE / COM_STMT_EXECUTE / COM_STMT_CLOSE,复用 lib/com/mysql/wire.ss readPacket / writePacket(D134 Phase 2 packet 层)+ lib/binary byteToInt / readLengthEncodedInt / lengthEncodedIntSize / readLengthEncodedString(D134 Phase 4 binary helper)
3. **不留 text protocol fallback dead code** — 自用语境 MySQL 4.1+ 全支持 COM_STMT_*(2002 release),无兼容性顾虑;承 §Root Cause + memory `feedback_no_derive_workaround` + D135 §Principles 2 范式;text protocol(query.ss COM_QUERY)保留作"不带参数的 DDL / SELECT * FROM x" simple path,prepared 用于带 `?` 参数化路径,**两路径并存非 fallback** — query.ss 不删
4. **binary protocol 子集覆盖** — `MYSQL_TYPE_LONG = 3`(u32 LE)/ `MYSQL_TYPE_VAR_STRING = 253`(length-encoded string)/ `MYSQL_TYPE_DOUBLE = 5`(8-byte IEEE 754)/ `MYSQL_TYPE_LONGLONG = 8`(i64 LE,SS int 默认)/ `MYSQL_TYPE_NULL = 6`(无 value 字节,标 NULL bitmap)+ NULL bitmap 处理;**TIMESTAMP / DATE / TIME / JSON / DECIMAL / BLOB 等留 sub-D 评估**(scope 控,业务覆盖度优先 INT/VARCHAR/DOUBLE/LONGLONG/NULL 5 子集)
5. **不实现 multi-result statement / stored procedure call**(范围外,D134 §6 + D135 §Principles 11 + 本 D §界定)
6. **不实现 COM_STMT_RESET / COM_STMT_FETCH 流式 cursor / COM_STMT_SEND_LONG_DATA**(范围外,scope 控)
7. **不实现 batch execution(addBatch/executeBatch) / generated keys retrieval(getGeneratedKeys) / metadata API(getMetaData / getParameterMetaData)**(范围外,sub-D 处理)
8. **不实现 schema cache / 跨 connection statement cache / connection-state-aware statement_id reuse**(范围外,statement_id 仅在本 connection 内有效,close 后失效)
9. **JdbcTemplate retcon scope 评估留 Phase 3** — lib/spring/jdbc.ss `execute / update / queryForString / queryForInt / queryForList` 现全字符串拼接,改走 prepareStatement + setXxx 需评估 LOC + 签名破坏面;**LOC > 200 或破坏既有签名 → 留 D137 sub-follow-up**(scope 控不藏表面,本 D 仅落 driver-agnostic 接口 + MysqlPreparedStatement 实施 + e2e 验证 + JdbcTemplate 加 1 个 `update(sql, params)` 重载示范)
10. **复用 lib/com/mysql/wire.ss + lib/binary** — packet 层 + binary helper D134 Phase 2/4 全就绪,**禁重写**(承 D135 §Principles 6 复用范式)
11. **Phase 边界 = commit 边界** — 4 Phase 各自独立 commit,禁打包(承 D134 §Principles 7 + D135 §Principles 9)
12. **bootstrap 隔离** — 全 Phase 仅改 lib/ + tests/ + docs/,不动 bootstrap(packet 层 + binary 层 + socket 原语 D134 全就绪,无新内置原语需求)
13. **不变量保留**(承 D134 + D135):D018 / D022 / D025 / D068 / D088 / D123 / D130-135 全不动;mimalloc C link axiom 例外保留;D134 driver 拼装架构(`lib/com/mysql/{wire,query,jdbc,handshake,prepared}` + `lib/spring` + `lib/java/sql`)接口契约扩(加 PreparedStatement)不破现有 Statement / ResultSet / Connection

---

## 1. Context Management(上下文管理)

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D136)
2. CLAUDE.md §项目本质 + §项目技术规则 §Root Cause 优先 + §交互式单文档
3. docs/3-MNK.md §M PSM 九问 + §N VCM 六验 + §K 收敛循环 + §大改档位规则
4. docs/3-decisions/D134-jdbc-mysql-wire-protocol.md §Status §核心原则 §A.4(packet 协议)+ §A.5(driver dispatch)
5. docs/3-decisions/D135-mysql-caching-sha2-fast-path.md §Status(认证层范式参考)
6. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `lib/java/sql.ss` | 31-36 `interface Statement` | Phase 1 加 `interface PreparedStatement extends Statement` |
   | `lib/java/sql.ss` | 40-47 `interface Connection` | Phase 1 加 `prepareStatement(sql): PreparedStatement` 方法 |
   | `lib/com/mysql/wire.ss` | 27-45 `readPacket` | Phase 1+2 复用(packet 层就绪) |
   | `lib/com/mysql/wire.ss` | 53-62 `writePacket` | Phase 1+2 复用(packet 层就绪) |
   | `lib/com/mysql/query.ss` | 117-133 `parseColumnDef` | Phase 1 复用(prepared 响应包含 column def 序列) |
   | `lib/com/mysql/query.ss` | 145-150 `isEofPacket` | Phase 1+2 复用(legacy EOF 范式) |
   | `lib/com/mysql/query.ss` | 75-79 `parseOkPacketAffectedRows` | Phase 2 复用(executeUpdate OK packet 解析) |
   | `lib/binary` | (existing) `byteToInt / readLengthEncodedInt / lengthEncodedIntSize / readLengthEncodedString` | Phase 1+2 复用(D134 Phase 4 binary helper) |
   | `lib/com/mysql/jdbc.ss` | 30-70 `class MysqlConnection` | Phase 1 加 `prepareStatement(sql)` 方法 |
   | `lib/com/mysql/prepared.ss` | (新建) | Phase 1+2 实施 COM_STMT_* 协议 + binary value codec + `class MysqlPreparedStatement` |
   | `tests/d134_mysql/prepared_test.ss` | (新建) | Phase 1+2 wire-level vec test |
   | `tests/d136_prepared_statement/integration_test.ss` | (新建) | Phase 3 e2e |
   | `lib/spring/jdbc.ss` | (existing) `execute / update / queryForString / queryForInt` | Phase 3 retcon scope 评估(LOC > 200 留 D137) |

### Stable Facts

| 项 | 值 |
|---|---|
| D134 全 Phase 收关锚 | commit `e509be1`(2026-04-26)|
| D135 全 Phase 收关锚 | commit `1c2e07b`(2026-04-26)|
| 当前 lib/com/mysql/ 总 LOC | 782(handshake.ss 300 + jdbc.ss 134 + query.ss 286 + wire.ss 62)|
| 当前 lib/java/sql.ss 总 LOC | 62 |
| 当前 `interface Statement` 方法 | executeQuery(sql) / executeUpdate(sql) / execute(sql) / close(),**无 setXxx / 重载 executeQuery() executeUpdate()** |
| 当前 `interface Connection` 方法 | createStatement / setAutoCommit / commit / rollback / close / isClosed,**无 prepareStatement** |
| 当前 socket TCP 原语 | ✓ ss_tcpConnect / ss_tcpReadBytes / ss_tcpWriteBytes(D134 Phase 1 全就绪)|
| 当前 packet 层 | ✓ readPacket / writePacket / `class MysqlPacket`(D134 Phase 2 wire.ss)|
| 当前 binary helper | ✓ byteToInt / readLengthEncodedInt / lengthEncodedIntSize / readLengthEncodedString(lib/binary)|
| 当前 `class ColumnDef` | ✓ name / colType / columnLen / charset(D134 Phase 4 query.ss)|
| 当前 `class MysqlResultSet` | ✓ 文本协议(D134 Phase 4 query.ss)|
| 当前 caching_sha2 fast-path | ✓(D135 Phase 1 lib/com/mysql/handshake.ss)|
| 当前 PreparedStatement 接口 | ✗(本 D Phase 1 落)|
| 当前 COM_STMT_* | ✗(本 D Phase 1+2 落)|
| 当前 binary result set codec | ✗(本 D Phase 2 落)|
| 当前 `class MysqlBinaryResultSet` | ✗(本 D Phase 2 落,模仿 query.ss `MysqlResultSet`)|
| 测试基线(D135 §Status)| `bin/ss test tests/` 256 pass / 4 pre-existing fail / 260 total |
| docker-compose | tests/d134_mysql/docker-compose.yml(D135 Phase 2 retcon caching_sha2 默认接管)|
| 自举状态 | 自举完成,固定点验证通过(D135 commit `1c2e07b`)|

### 禁止的 Context 操作

- ❌ 不读 multi-result statement / stored procedure call 协议(范围外)
- ❌ 不读 COM_STMT_RESET / COM_STMT_FETCH 流式 cursor / COM_STMT_SEND_LONG_DATA(范围外)
- ❌ 不读 SCROLLABLE / UPDATABLE result set / batch execution / generated keys / metadata API(范围外)
- ❌ 不读 connection pool / statement cache 跨 connection 设计(范围外,D125+ HikariCP sub-D 处理)
- ❌ 不试图保留 text protocol fallback dead code(query.ss 留作 simple path,非 fallback)
- ❌ 不试图实现 TIMESTAMP / DATE / TIME / JSON / DECIMAL / BLOB binary value decode(范围外,scope 控 INT/VARCHAR/DOUBLE/LONGLONG/NULL 5 子集)

---

## 2. Tool System

### 必备工具(已在环境中)

| 类别 | 工具 | 用途 |
|---|---|---|
| Claude 内置 | Read / Edit / Write / Bash | 文件操作 |
| 项目专属 | `./build.sh bootstrap` | 三阶段固定点(本 D 纯 lib 改,Phase 1-3 后跑确认零冲击)|
| 项目专属 | `bin/ss test tests/` | 全测试集 |
| 项目专属 | `bin/ss test tests/d134_mysql/` | D134 既有 e2e(Phase 3 若 JdbcTemplate retcon 走 prepared 仍绿)|
| 项目专属 | `bin/ss test tests/d135_caching_sha2/` | D135 既有 e2e(认证层透明,本 D 不动)|
| 项目专属 | `bin/ss test tests/d136_prepared_statement/` | D136 新 e2e(Phase 3 加)|
| 项目专属 | `bin/ss test tests/d134_mysql/prepared_test.ss` | D136 wire-level vec test(Phase 1+2 加)|
| 项目专属 | `nm bin/ss \| grep -c -E "RSA_\|EVP_"` | axiom 红线扫描(永久 = 0)|
| 项目专属 | `docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait` | MySQL 8 实例(D135 caching_sha2 默认接管)|
| Python | `python3 -c "import struct; ..."` | binary value reference vec 离线算(MYSQL_TYPE_LONG u32 LE / MYSQL_TYPE_DOUBLE 8-byte IEEE 754 等)|
| Python | `mysql-connector-python` | wire-level vec test reference 实施(prepare + execute packet 字节级对比)|
| linter | `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate(F1 死指针 = 0)|
| linter | `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射,baseline 不动)|
| linter | `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ 任何新 C 库(libmysqlclient / libssl / libcrypto / libasn1 等)
- ❌ 任何新 build flag(本 D 不改 build.sh / bootstrap/main.ss link 段)
- ❌ 新内置 socket 原语(D134 Phase 1 已就绪)
- ❌ 新内置 binary helper(lib/binary 已就绪)
- ❌ 新 reflection / annotation / generic constraint 机制(本 D 纯协议层 + 接口扩,不触类型系统)

---

## 3. Execution Orchestration

### 总体节奏

- 4 Phase 各自独立 commit + Phase 1-3 各跑 bootstrap 三阶段固定点 + Phase 3 必跑 docker mysql 真 e2e
- 禁"边写 prepared.ss 边改 jdbc.ss 边改 spring/jdbc.ss"打包 commit
- Phase 0 = 本轮 Plan(D 文档骨架),Phase 1-3 = 下轮起逐 Phase Execute(承 D135 Phase 0 范式)

### Phase 详细

#### Phase 0: 本文档落盘(本轮 Plan)

- D136 文档骨架 + PSM 九问归档 + 4 Phase 序列 + 风险锚 R1-R5 + 三轨闭环
- 改动:`docs/3-decisions/D136-mysql-prepared-statement.md`(新)+ `.claude/next_prompt.md`(改 — Phase 1 起立)
- **不动代码**:`git diff --stat bootstrap/ lib/ tools/ tests/ = 0`
- **不动 D134 / D135 文件**:Phase 0 只落 D136 文档骨架,D134 §Status superseded 锚留 Phase 3 commit hash known 时回填(若 JdbcTemplate retcon 落 Phase 3)
- **验证**:用户审阅 OK 后下轮 Execute Phase 1

#### Phase 1: 接口扩 + COM_STMT_PREPARE 实施(纯 lib 改)

- **`lib/java/sql.ss`** 改 ~15 LOC:
  - 加 `interface PreparedStatement` extends `Statement` — 新方法 `setInt(idx, val)` / `setString(idx, val)` / `setLong(idx, val)` / `setDouble(idx, val)` / `setBoolean(idx, val)` / `setNull(idx)` + 重载 `executeQuery(): ResultSet` / `executeUpdate(): int`(无 sql 参数,sql 在 prepare 时 bound)
  - 加 `Connection.prepareStatement(sql: string): PreparedStatement` 接口方法
  - **签名约束**:idx 从 1 起(JDBC 4.3 范式),与 array 0-based 差 1
- **`lib/com/mysql/prepared.ss`**(新)~250 LOC:
  - 协议常量:`COM_STMT_PREPARE = 0x16` / `COM_STMT_EXECUTE = 0x17` / `COM_STMT_CLOSE = 0x19` / `MYSQL_TYPE_LONG = 3` / `MYSQL_TYPE_DOUBLE = 5` / `MYSQL_TYPE_LONGLONG = 8` / `MYSQL_TYPE_NULL = 6` / `MYSQL_TYPE_VAR_STRING = 253`
  - `class PrepareOk { statementId: int; numColumns: int; numParams: int; warningCount: int }`
  - `function sendComStmtPrepare(fd: int, sql: string): int` — 发 0x16 + sql payload(seqId 0)
  - `function parsePrepareOk(payload: string, payloadLen: int): PrepareOk` — 解 0x00 header(1 byte)+ statement_id u32 LE + num_columns u16 LE + num_params u16 LE + filler 0x00(1 byte)+ warning_count u16 LE
  - `function readPrepareOk(fd: int): PrepareOk` — readPacket + parsePrepareOk
  - `function readParamDef(fd: int, numParams: int): Array<int>` — 读 numParams 个 ColumnDef41 packet(复用 query.ss `parseColumnDef` 拿 colType)+ EOF packet
  - `function readColumnDefList(fd: int, numColumns: int): Array<ColumnDef>` — 读 numColumns 个 ColumnDef41 packet + EOF packet
  - `class MysqlPreparedStatement` 框架:fd / statementId / paramTypes: Array&lt;int&gt; / params: Array&lt;string&gt; / paramNullBits: Array&lt;int&gt; / columnDefs: Array&lt;ColumnDef&gt; / closed: int + setXxx 占位实施(写 paramTypes + params + paramNullBits)+ executeQuery / executeUpdate / close 占位(Phase 2 实施)
- **`lib/com/mysql/jdbc.ss`** 改 ~10 LOC:
  - `MysqlConnection.prepareStatement(sql: string): PreparedStatement` 加新方法 — 调用 sendComStmtPrepare(fd, sql) → readPrepareOk(fd) → readParamDef(fd, numParams) → readColumnDefList(fd, numColumns) → 返 `new MysqlPreparedStatement(fd, statementId, paramTypes, params, paramNullBits, columnDefs, 0)`
- **`tests/d134_mysql/prepared_test.ss`** 新建 ~150 LOC:
  - test 1: sendComStmtPrepare packet bytes — `SELECT id FROM users WHERE id = ?` reference vec(`printf '\x14\x00\x00\x00\x16SELECT id FROM users WHERE id = ?'` 字节级对比)
  - test 2: parsePrepareOk reference vec — `\x00\x01\x00\x00\x00\x01\x00\x01\x00\x00\x00\x00\x00` (statement_id=1, num_columns=1, num_params=1, filler 0x00, warning_count=0)
  - test 3: parsePrepareOk 多 column 多 param vec
  - test 4: parsePrepareOk warning_count > 0 vec
- **RED**:
  ```bash
  grep -rnE "COM_STMT_PREPARE|prepareStatement|PreparedStatement|sendComStmtPrepare" lib/com/mysql/ lib/java/sql.ss | wc -l = 0
  ```
- **GREEN**:改后 ≥ 5(接口 PreparedStatement + sendComStmtPrepare + parsePrepareOk + MysqlPreparedStatement + Connection.prepareStatement + 测试引用)+ `bin/ss test tests/d134_mysql/prepared_test.ss` 全绿(4 vec)+ `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical(纯 lib 不动 bootstrap)+ `bin/ss test tests/` 256+/260 不降

#### Phase 2: COM_STMT_EXECUTE + binary result set + COM_STMT_CLOSE 实施(纯 lib 改)

- **`lib/com/mysql/prepared.ss`** 加 ~350 LOC(若总 LOC 接近 600 上限则拆 binary_query.ss):
  - `function sendComStmtExecute(fd: int, statementId: int, paramTypes: Array<int>, params: Array<string>, paramNullBits: Array<int>): int`
    - 头:cmd 0x17(1 byte)+ statement_id u32 LE(4 byte)+ flags u8 0x00 = CURSOR_TYPE_NO_CURSOR(1 byte)+ iteration_count u32 LE = 1(4 byte)
    - NULL bitmap:`(numParams + 7) / 8` bytes,paramNullBits[i] == 1 则置 bit
    - new_params_bound_flag u8 = 1(首次发送 type 信息)
    - param_types:`numParams * 2` bytes,每 param 2 byte(type code u8 + unsigned flag u8 = 0x00)
    - param values:按 binary protocol encode 顺序写入(NULL 不发 value;INT/LONGLONG = u32/i64 LE;DOUBLE = 8 byte IEEE 754 LE;VARCHAR = length-encoded string)
  - `function parseBinaryRow(payload: string, payloadLen: int, columnDefs: Array<ColumnDef>): Array<string>`
    - skip header byte 0x00(1 byte)
    - NULL bitmap:`(numColumns + 7 + 2) / 8` bytes(注意 binary protocol +2 offset 是 spec 特殊,与 execute request +0 offset 不同)
    - 按 columnDefs 顺序 decode 各 binary value:NULL bit 置则空串("");否则按 colType 对应 binary decode(MYSQL_TYPE_LONG → 4 byte u32 LE → toString;MYSQL_TYPE_LONGLONG → 8 byte i64 LE → toString;MYSQL_TYPE_DOUBLE → 8 byte IEEE 754 → toString;MYSQL_TYPE_VAR_STRING → length-encoded string)
  - `class MysqlBinaryResultSet : ResultSet`(模仿 query.ss `MysqlResultSet` 文本范式):
    - fd / colCount / colMetadata / currentRow / closed / hasMoreRows
    - next() / getString / getInt / getLong / getDouble / getBoolean / close()
  - `function readQueryResultSetBinary(fd: int): MysqlBinaryResultSet` — 模仿 query.ss `readQueryResultSet` 文本范式
  - `function sendComStmtClose(fd: int, statementId: int): int` — 发 0x19 + statement_id u32 LE(no response,server 不回包)
  - `MysqlPreparedStatement.executeQuery(): ResultSet` 实施 — sendComStmtExecute → readQueryResultSetBinary
  - `MysqlPreparedStatement.executeUpdate(): int` 实施 — sendComStmtExecute → readUpdateResult(复用 query.ss)
  - `MysqlPreparedStatement.close()` 实施 — sendComStmtClose
  - setXxx 实施 — 按 idx-1 写 paramTypes / params / paramNullBits(idx 从 1 起)
- **`tests/d134_mysql/prepared_test.ss`** 加 ~200 LOC:
  - test 5: sendComStmtExecute packet bytes — INT/VARCHAR/DOUBLE/NULL 混合 4 param reference vec(Python `mysql-connector-python` 离线算)
  - test 6: parseBinaryRow reference vec — INT/VARCHAR/DOUBLE/NULL 混合 4 column 一行
  - test 7: NULL bitmap +2 offset 边界 vec(numColumns=14,bitmap 2 byte boundary)
  - test 8: binary VARCHAR length-encoded boundary(< 251 / 251-65535 / 65536-16M 三档)
- **RED**:
  ```bash
  grep -rnE "COM_STMT_EXECUTE|sendComStmtExecute|parseBinaryRow|MysqlBinaryResultSet|sendComStmtClose" lib/com/mysql/ | wc -l = 0
  ```
- **GREEN**:改后 ≥ 5 + `bin/ss test tests/d134_mysql/prepared_test.ss` 全绿(prepare + execute + close 共 8 vec)+ `./build.sh bootstrap` 三阶段固定点 + `bin/ss test tests/` 256+/260 不降

#### Phase 3: e2e + JdbcTemplate retcon scope 评估

- **`tests/d136_prepared_statement/integration_test.ss`** 新建 ~150 LOC(模仿 d134_mysql/integration_test.ss probe + test 范式 + d135_caching_sha2/integration_test.ss 注释结构):
  - probe 127.0.0.1:3307,docker unreachable skip(沿 D134 Phase 6 + D135 Phase 2 范式)
  - test 1: prepare + executeQuery 单 param SELECT — `SELECT id, name, age FROM users WHERE id = ?` + setInt(1, 1) → 验 id=1 / name="Alice" / age=30
  - test 2: prepare + executeUpdate 多 param INSERT — `INSERT INTO users VALUES (?, ?, ?)` + setInt(1, 100) / setString(2, "Trinity") / setInt(3, 35) → 验 affected rows = 1
  - test 3: prepare + executeQuery 多类型 + 多行 — `SELECT id, name, age FROM users` 不带 param + 多行 binary result set → 验 row count + 字段值
  - test 4: NULL 处理 — `INSERT INTO users VALUES (?, NULL, ?)` + setInt(1, 200) / setInt(3, 25) → 验 affected rows + SELECT 验 name = ""(SS 无 null sentinel)
  - test 5: prepare close 后 fd 仍可用 — close prepared 不关 connection,connection 上仍可继续 execute statement
- **JdbcTemplate retcon scope 评估**(Phase 3 决策点):
  - lib/spring/jdbc.ss `execute / update / queryForString / queryForInt / queryForList` 现全字符串拼接 — 评估改走 prepareStatement + setXxx 的 LOC + scope
  - **判据**:JdbcTemplate API 签名是否需要破坏?— `execute(sql, params...)` 重载 + 调用方 spring/data.ss 全部改 + tests/d134_mysql/integration_test.ss / tests/d135_caching_sha2/integration_test.ss 全部改
  - **若 retcon LOC > 200 或破坏既有签名 → 留 D137 sub-follow-up**(scope 控不藏表面);D136 Phase 3 仅落 e2e + JdbcTemplate 加 1 个 `update(sql, params)` 重载示范(不改既有 `update(sql)` 签名,重载叠加)
  - **若 retcon LOC ≤ 200 不破签名 → 落 D136 Phase 3**:JdbcTemplate 加 `execute(sql, params)` / `update(sql, params)` / `queryForInt(sql, params, col)` 重载,既有无 params 签名保留(走 query.ss 文本协议)
- **`docs/3-decisions/D134-jdbc-mysql-wire-protocol.md`** §Status retcon(Phase 3 commit hash known 时回填,若 JdbcTemplate retcon 走 prepared):
  - 加 superseded 锚 `**D136 superseded text protocol fallback for parameterized queries** at commit <D136 Phase 3 hash> (2026-04-27)`
  - 维持 d_doc_index_linter F1 死指针 = 0
- **`docs/3-decisions/D135-mysql-caching-sha2-fast-path.md`** **不需要 retcon**(D135 是认证层,与 statement 层无关)
- **GREEN**:`bin/ss test tests/d136_prepared_statement/` 全绿(5 case)+ `bin/ss test tests/d134_mysql/` 8 case 全绿(若 JdbcTemplate retcon)+ `bin/ss test tests/d135_caching_sha2/` 4 case 全绿 + 三轨 RED 闭环 + axiom 红线 grep / nm = 0 永久 + d_doc_index_linter F1 = 0

### 反模式

- ❌ 边写 prepared.ss 边改 jdbc.ss 边改 spring/jdbc.ss(打包 commit,违反 §Principles 11)
- ❌ 保留 text protocol fallback dead code(违反 §Principles 3 — text protocol 是 simple path 不是 fallback)
- ❌ 实现 multi-result statement / stored procedure(违反 §Principles 5)
- ❌ 实现 COM_STMT_RESET / COM_STMT_FETCH / COM_STMT_SEND_LONG_DATA(违反 §Principles 6)
- ❌ 实现 batch execution / generated keys / metadata API(违反 §Principles 7)
- ❌ 跨 connection statement cache(违反 §Principles 8)
- ❌ JdbcTemplate retcon LOC > 200 仍硬塞 Phase 3(违反 §Principles 9 scope 控)
- ❌ 重写 wire.ss / query.ss / binary helper(已就绪,违反 §Principles 10 复用原则)
- ❌ 触动 bootstrap(违反 §Principles 12 isolation)
- ❌ 破坏 D025 interface Statement / ResultSet / Connection 既有签名(违反 §Principles 13 不变量)
- ❌ TIMESTAMP / DATE / TIME / JSON / DECIMAL / BLOB binary value decode 实施(违反 §Principles 4 子集控)
- ❌ Phase 0 retcon D134 §Status(D134 retcon 留 Phase 3,因 JdbcTemplate retcon scope 评估在 Phase 3 决定)

---

## 4. State & Memory

### 编译时 state

| 变量 | 文件 | 角色 |
|---|---|---|
| 无新增编译时 state | — | Phase 1-3 纯 lib 改,bootstrap funcRetTypes 不动 |

### 运行时 state(driver 内部)

- `class MysqlPreparedStatement.fd: int / statementId: int / paramTypes: Array<int> / params: Array<string> / paramNullBits: Array<int> / columnDefs: Array<ColumnDef> / closed: int`
- `class MysqlBinaryResultSet.fd / colCount / colMetadata / currentRow / closed / hasMoreRows`(模仿 query.ss `MysqlResultSet` 范式)
- statement_id server-allocated u32,connection 内 unique,close 后失效
- params Array store as string(SS int → toString 走 setInt;SS double → toString 走 setDouble;binary value encode 在 sendComStmtExecute 时按 paramTypes 还原 binary)

### 中间产物

- Phase 1: 4 parsePrepareOk reference vec(printf-fixture-style + Python `mysql-connector-python` 抓 packet bytes)
- Phase 2: 4 vec(sendComStmtExecute INT/VARCHAR/DOUBLE/NULL + parseBinaryRow + NULL bitmap +2 offset 边界 + VARCHAR length-encoded boundary)
- Phase 3: docker mysql 真 e2e 5 case

### 会话间持久化

- git log — Phase 0/1/2/3 commit 边界 = 进度锚
- 本文档 — 唯一 D136 状态记录
- D134 §Status superseded 锚(Phase 3 commit hash known 时回填,若 JdbcTemplate retcon)— 跨轮引用一致性

### 禁止 state 操作

- ❌ 把跨 Phase 进度写到 .claude/next_prompt.md 累积
- ❌ amend 已 push commit
- ❌ 写 binary_protocol_log.md / prepared_protocol_analysis.md 类分析文件入仓
- ❌ 把 mysql credentials 硬编码进 tests/d136_prepared_statement/(用 docker-compose 环境变量传递,密码默认 `test` 沿 D134 范式)
- ❌ 跨 connection statement cache(违反 §Principles 8)

---

## 5. Evaluation & Observation

### 判据(每 Phase 完成必跑)

| # | 类型 | 命令 | 通过条件 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | Phase 1-3 后跑确认零冲击(纯 lib 改);stage2 == stage3 byte-identical |
| 2 | 测试 | `bin/ss test tests/` | 256+/260 不降(D135 baseline)|
| 3 | D134 e2e 兼容 | `bin/ss test tests/d134_mysql/` | Phase 3 若 JdbcTemplate retcon 走 prepared 仍 8 case 全绿 |
| 4 | D135 e2e 兼容 | `bin/ss test tests/d135_caching_sha2/` | 4 case 全绿(认证层透明,本 D 不动)|
| 5 | D136 wire-level vec | `bin/ss test tests/d134_mysql/prepared_test.ss` | Phase 1+2 加 + 全绿(8 vec)|
| 6 | D136 e2e | `bin/ss test tests/d136_prepared_statement/` | Phase 3 加 + 全绿(5 case)|
| 7 | RED 收敛 | `grep -rnE "COM_STMT_PREPARE\|COM_STMT_EXECUTE\|COM_STMT_CLOSE\|prepareStatement\|PreparedStatement" lib/com/mysql/ lib/java/sql.ss \| wc -l` | Phase 1 后 ≥ 3,Phase 2 后 ≥ 5 |
| 8 | axiom 红线 | `grep -rn "libmysqlclient\|libssl\|RSA_\|EVP_PKEY" bootstrap/ lib/ build.sh \| wc -l` + `nm bin/ss \| grep -c -E "RSA_\|EVP_"` | 永久 = 0 |
| 9 | D 治理 | `bin/ss run tools/d_doc_index_linter.ss` | F1 死指针 = 0(Phase 3 D134 §Status retcon superseded 锚维持引用)|
| 10 | 反射 baseline | `bin/ss run tools/reflection_health_linter.ss` | 不升(本 D 不触反射)|

### 回归信号(任一出现 = 立即停下)

- ⚠ Phase 1-3 后 stage2 ≠ stage3(纯 lib 改不该出现 bootstrap 字节差,若出现说明误改 bootstrap)
- ⚠ Phase 2 后 D134 e2e 任一红(prepared 实施破坏既有 application layer 透明性)
- ⚠ Phase 2 后 D135 e2e 任一红(认证层应不受 statement 层影响)
- ⚠ Phase 3 e2e test 1-5 任一红(prepare/execute/close 路径不通)
- ⚠ axiom 红线 grep / nm 命中(libssl / RSA_ 误链)
- ⚠ JdbcTemplate retcon LOC > 200(scope 爆,留 D137 sub-follow-up — Phase 3 决策点)
- ⚠ 反射 baseline 升(本 D 不触反射,若升说明误改)
- ⚠ Phase 3 D134 §Status retcon 后 d_doc_index_linter F1 BLOCK(死指针 — 修锚点引用)

---

## 6. Constraints & Recovery

### 硬约束

- **不允许 axiom 例外** — feedback_root_cause_no_cost,纯 SS 实现到底
- **不允许跨层** — TLS / RSA-OAEP / Pool / multi-result / stored procedure / batch / metadata 全留 sub-D 或永远不做
- **不允许打包 commit** — 4 Phase 各自独立 commit
- **不允许接口签名变** — D025 interface Statement / ResultSet / Connection 既有签名本 D 不动(只扩 PreparedStatement + Connection.prepareStatement)
- **不允许保留 text protocol fallback dead code** — query.ss 是 simple path 不是 fallback,prepared.ss 与 query.ss 并存非互替
- **不允许 binary value decode 超出 5 子集** — INT/VARCHAR/DOUBLE/LONGLONG/NULL 5 类型,TIMESTAMP/DATE/TIME/JSON/DECIMAL/BLOB 范围外

### 风险锚(R1-R5)

| # | 风险 | 触发场景 | 处置 |
|---|---|---|---|
| R1 | binary protocol NULL bitmap 边界错 | execute request NULL bitmap 是 +0 offset(`(numParams + 7) / 8` byte),binary result set NULL bitmap 是 **+2 offset**(`(numColumns + 7 + 2) / 8` byte)— 两路径计算不同,易混淆 | Phase 2 调研 + Python `mysql-connector-python` source code 反查 binary protocol spec + reference vec 锁定;test 7 专测 NULL bitmap +2 offset 边界(numColumns=14 触 2 byte boundary)|
| R2 | binary value type code 错配 | MYSQL_TYPE_LONG = 3(u32 LE)vs MYSQL_TYPE_LONGLONG = 8(i64 LE)vs MYSQL_TYPE_TINY = 1,SS int = i64 → MYSQL_TYPE_LONGLONG 最匹配但 driver 通常用 MYSQL_TYPE_LONG 兼容性 | Phase 2 决策:setInt 用 MYSQL_TYPE_LONG(server 自动 widen)/ setLong 用 MYSQL_TYPE_LONGLONG;reference vec 锁定 + e2e 验证 |
| R3 | VARCHAR length-encoded encoding 边界 | length < 251 一字节直发;251-65535 三字节 0xFC prefix + u16 LE;65536-16M 四字节 0xFD prefix + u24 LE — 复用 lib/binary lengthEncoded helper(D134 Phase 4)| Phase 2 复用 lib/binary;test 8 专测 三档 boundary(短 / 中 / 长 string)|
| R4 | prepared statement 数据库重启 cache miss | server 重启后 statement_id invalid → 再次 execute 触发 ER_UNKNOWN_STATEMENT_HANDLER ERR;driver 不重新 prepare(scope 控,留 D138 sub-follow-up handle)| Phase 0 §Principles 8 锚定;Phase 2-3 ERR packet 处理走 query.ss `parseResultSetHeader RESULT_SET_HEADER_ERR` 范式(MysqlBinaryResultSet.colCount = -1)|
| R5 | JdbcTemplate retcon scope 爆 | execute/update 签名要不要变(`execute(sql)` 单 / `execute(sql, params)` 重载?)+ tests/d134_mysql/integration_test.ss 8 case 全部要改 + tests/d135_caching_sha2/integration_test.ss 4 case 全部要改 + spring/data.ss 调用方全部要改 | Phase 3 LOC > 200 评估即留 D137 sub-follow-up;D136 Phase 3 仅落 e2e + JdbcTemplate 加 1 个 `update(sql, params)` 重载示范(不改既有 `update(sql)` 签名,重载叠加 — JDBC 标准范式) |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 parsePrepareOk vec 错 | MySQL `mysqlbinlog -v` 抓真实 packet bytes 对比 + Python `mysql-connector-python` packet log 反查 + MySQL 官方 doc `Protocol::COM_STMT_PREPARE_OK` 反向核对 byte layout |
| Phase 2 sendComStmtExecute packet bytes 错 | Python `mysql-connector-python` source code 反查 binary protocol value encode + `tcpdump -i lo -X port 3307` 抓 docker mysql 真实 packet |
| Phase 2 binary result set NULL bitmap +2 offset 边界错 | MySQL 官方 doc `Protocol::Binary Resultset Row` 反查 binary protocol result set spec(关键:binary result set NULL bitmap 是 +2 offset,与 execute request +0 offset 不同 — 历史 reserve 2 bit 给 prefix)|
| Phase 2 binary value type code 错配(setInt 触 MYSQL_TYPE_LONG vs LONGLONG)| reference vec 锁定 + Python `mysql-connector-python` setInt 实测 type code 对比 |
| Phase 3 e2e test 1-5 任一红 | packet log + tcpdump + 重新跑 wire-level vec test 锁定 prepare/execute boundary |
| Phase 3 JdbcTemplate retcon LOC > 200 | 立即停下不硬塞,留 D137 sub-follow-up;Phase 3 仅落 e2e + JdbcTemplate 1 个 `update(sql, params)` 重载示范 |
| Phase 3 D134 e2e 8 case 红 | git revert Phase 3 JdbcTemplate retcon,Phase 3 仅落 d136_prepared_statement/ e2e |
| Phase 3 D134 §Status retcon F1 死指针 BLOCK | 检查 D134 §A.4 / §A.5 等源码注释引用 — 若 D134 文件 § 段被 retcon 而引用未更新 → 修引用 |

### 回滚策略

- 任一 Phase 失败 → `git reset --soft HEAD^` 回上一 Phase
- Phase 0 落盘后允许下轮 Execute Phase 1 起立时 git stash + 重 plan(D 文档措辞调整)
- 跨 Phase 回滚需先和用户确认(Phase 边界 = 稳定锚点,承 D134 §6 §回滚策略 + D135 §回滚策略)

---

# 附录 A: 决策细节

## A.1 协议选型 — Prepared Statement vs 文本协议

候选:

| 候选 | 描述 | 优 | 劣 | 选/不选 |
|---|---|---|---|---|
| ① **Prepared Statement(COM_STMT_*)** | client 发 0x16 prepare → server 返 statement_id → client 发 0x17 execute(statement_id + binary params)→ server 返 binary result set → client 发 0x19 close | 参数化绑定 SQL 注入根因解决 / binary protocol 性能加速 / server-side parser cache / standard JDBC 范式 | 实施 LOC ≥ 1000 / NULL bitmap 边界复杂 / binary value encoding 多类型 | **✓ 选**(用户对话授权"集成 mysql + 推荐 ③")|
| ② Client-side SQL escape + 文本协议 | client 自己 escape `'` / `\` 等特殊字符,生成 SQL 字符串后走 COM_QUERY | 实施 LOC < 100 / 复用 query.ss 文本路径 | escape 漏一个字符就 SQL 注入(MySQL 0x00 / 0x1A / 0x22 / 0x27 / 0x5C / 0x5F / 0x25 / 0x60 等需 escape — 漏一个就漏)/ 无 binary protocol 性能加速 / 无 server-side parser cache / driver-agnostic 接口暴露不出 setXxx | ✗ 不选 |
| ③ Server-side function-based escape(`mysql_real_escape_string`)| client 调 server-side function escape | server-side function 实施 by libmysqlclient → 跨 axiom 红线 | libmysqlclient 应用层 client 库 → axiom 不允许 link;且仍是文本协议 | ✗ 不选 |
| ④ ORM-level parameterized + 文本拼接 | 业务层 ORM 拼 `?` placeholder → ORM 自己 escape | escape 仍依赖 ORM 实施 / driver 层无 prepared 支持 | 同 ② 漏 escape 风险 / ORM 责任移位非根因 | ✗ 不选 |

**选 ①**,理由:
- 用户对话授权(2026-04-27 "集成 mysql + 推荐 ③ Prepared Statement")
- SQL 注入根因解决(参数化绑定 = 唯一正确防御,OWASP top 10 #3 锚)
- binary protocol 性能根因解决
- standard JDBC 4.3 范式(driver-agnostic 接口 + driver-specific 实现 双轨)
- ⑥ multi-result / ⑦ stored procedure 依赖 ③ 前置(D134 §6 follow-up 顺序锚)

## A.2 COM_STMT_PREPARE 请求 + COM_STMT_PREPARE_OK 响应格式

### COM_STMT_PREPARE 请求(client → server)

```
+------+------+
| 0x16 | sql  |
+------+------+
  1B    NB   (no length prefix — payloadLen 由 packet header 控制)
```

### COM_STMT_PREPARE_OK 响应(server → client)

```
+------+----------------+----------------+----------------+--------+----------------+
| 0x00 | statement_id   | num_columns    | num_params     | filler | warning_count  |
+------+----------------+----------------+----------------+--------+----------------+
  1B   |    4B u32 LE   |   2B u16 LE    |   2B u16 LE    |  1B    |   2B u16 LE    |
       |                |                |                | 0x00   |                |
```

后接:
- `num_params` 个 `Protocol::ColumnDefinition41` packet(每个 packet 是一个 param 元数据 — 复用 query.ss `parseColumnDef`)
- 1 个 EOF packet(legacy mode,与 query.ss `isEofPacket` 范式一致)
- `num_columns` 个 `Protocol::ColumnDefinition41` packet
- 1 个 EOF packet

> **CLIENT_DEPRECATE_EOF 锚**:D134 sendHandshakeResponse41 capFlags 不含 0x01000000(承 D134 §A.4),故 server 走 legacy EOF — 与 query.ss `MysqlResultSet` 范式同。

## A.3 COM_STMT_EXECUTE 请求格式(NULL bitmap + binary param encoding)

```
+------+----------------+-------+----------------+--------------+--------------------+----------------+--------------+
| 0x17 | statement_id   | flags | iteration_count| NULL bitmap  | new_params_bound   | param_types    | param values |
+------+----------------+-------+----------------+--------------+--------------------+----------------+--------------+
  1B   |    4B u32 LE   |  1B   |   4B u32 LE   | (P+7)/8 byte |       1B          | 2*P byte       | binary encode|
       |                | 0x00  |     = 1       | bit 0 = NULL |     = 0x01        |type+unsigned   |              |
       |                |CURSOR_|               |              | (首次发送 type)   |  flag 各 1B    |              |
       |                | NONE  |               |              |                   |                |              |
```

**P = numParams**;**NULL bitmap**:`(P + 7) / 8` byte,bit i 标 param i+1 是否 NULL(注意 +0 offset,与 binary result set +2 offset 不同);**param_types**:每 param 2 byte(type code u8 + unsigned flag u8 = 0x00);**param values**:NULL 不发 value;INT/LONGLONG/DOUBLE 直发 binary;VARCHAR length-encoded string

### Binary value encoding 子集

| Type code | 名称 | 长度 | 编码 |
|---|---|---|---|
| 1 | MYSQL_TYPE_TINY | 1 byte | i8(本 D 不用)|
| 3 | MYSQL_TYPE_LONG | 4 byte | u32 LE(setInt)|
| 5 | MYSQL_TYPE_DOUBLE | 8 byte | IEEE 754 LE(setDouble)|
| 6 | MYSQL_TYPE_NULL | 0 byte | 不发(NULL bitmap 标)|
| 8 | MYSQL_TYPE_LONGLONG | 8 byte | i64 LE(setLong)|
| 12 | MYSQL_TYPE_DATETIME | 0/4/7/11 byte | length prefix + Y/M/D/h/m/s/μs(本 D 不用,sub-D 评估)|
| 253 | MYSQL_TYPE_VAR_STRING | 1+N byte | length-encoded string(setString)|

**setBoolean 决策**:setBoolean → setInt(0 / 1)+ MYSQL_TYPE_LONG(JDBC 标准范式,MySQL 无原生 BOOL,实际是 TINYINT(1))

## A.4 Binary Result Set 解析(NULL bitmap header +2 offset + binary value decode)

### Binary Resultset Row 格式

```
+------+--------------+-------------------+
| 0x00 | NULL bitmap  | binary values     |
+------+--------------+-------------------+
  1B   | (C+7+2)/8 B  | 按 columnDefs    |
       | bit 0,1 reserved|                |
       | bit 2 = col 1  |                |
```

**C = numColumns**;**NULL bitmap +2 offset** 是 binary protocol spec 历史 reserve(execute request +0 offset 不一致,易混淆 — R1 风险锚)。

### Binary value decode 子集(同 §A.3 编码反向)

按 columnDef.colType decode:
- MYSQL_TYPE_LONG → 4 byte u32 LE → toString
- MYSQL_TYPE_LONGLONG → 8 byte i64 LE → toString
- MYSQL_TYPE_DOUBLE → 8 byte IEEE 754 → toString
- MYSQL_TYPE_VAR_STRING → length-encoded string
- MYSQL_TYPE_NULL → 空串 ""(SS 无 null sentinel,沿 query.ss `parseRow` 范式)

## A.5 PreparedStatement 接口设计(JDBC 4.3 对标)

### `interface PreparedStatement extends Statement`

```ss
interface PreparedStatement extends Statement {
    function setInt(idx: int, val: int)
    function setLong(idx: int, val: int)
    function setString(idx: int, val: string)
    function setDouble(idx: int, val: double)
    function setBoolean(idx: int, val: int)
    function setNull(idx: int)
    function executeQuery(): ResultSet      // 重载,无 sql 参数
    function executeUpdate(): int           // 重载,无 sql 参数
}
```

**idx 从 1 起**(JDBC 4.3 范式),与 array 0-based 差 1。setXxx 内部 `paramTypes[idx-1] = MYSQL_TYPE_xxx; params[idx-1] = val.toString(); paramNullBits[idx-1] = 0`。

### `interface Connection.prepareStatement`

```ss
interface Connection {
    function createStatement(): Statement
    function prepareStatement(sql: string): PreparedStatement   // 新增
    function setAutoCommit(auto: int)
    function commit()
    function rollback()
    function close()
    function isClosed(): int
}
```

### 与既有 Statement 接口关系

`PreparedStatement extends Statement`(SS interface 继承范式),故 PreparedStatement 同时拥有 `executeQuery(sql)` / `executeUpdate(sql)` / `execute(sql)` 三签名 + 新增 `executeQuery() / executeUpdate()` 无参重载。**调用方**:

```ss
const stmt = conn.prepareStatement("SELECT id, name FROM users WHERE id = ?")
stmt.setInt(1, 42)
const rs = stmt.executeQuery()    // 用无参重载
while (rs.next() == 1) {
    println(rs.getString("name"))
}
rs.close()
stmt.close()
```

## A.6 与 D134 axiom 范式的对偶

D134 §A.7:
- TCP socket syscall = OS / libc 边界,axiom 例外允许
- libmysqlclient.so / libmariadb.so = 应用层 client 库,axiom 不允许 link
- mysql wire protocol 实现纯 SS = 应用层 stdlib

本 D 同范式延伸:
- COM_STMT_PREPARE / EXECUTE / CLOSE 协议 = 纯 SS 协议层(复用 wire.ss + binary helper)
- binary value encoding / decoding 子集 = 纯 SS(IEEE 754 cast 复用 SS 既有 `intBitsToFloat` / `floatBitsToInt` 内置 — 若不存在则 Phase 2 调研补)
- 永远不做 RSA-OAEP / TLS / libmysqlclient link = 跨 axiom 红线 + 工程量爆,自用语境免

## A.7 PSM 九问填表(Phase 0 — 对话正文已述,本节归档完整版)

| # | 字段 | 内容 |
|---|---|---|
| 1 | 总体 | D134 §6 follow-up ③ Prepared Statement candidate 起立 + D135 §Principles 11 范围外明确清单兑现;用户对话授权 2026-04-27 "集成 mysql + 推荐 ③";D025 接口契约现状 lib/java/sql.ss:31-36 仅有 `Statement.execute(sql)` 文本协议,无 `PreparedStatement` 接口 — D136 补齐 |
| 2 | 第一性需求 | 现 lib/com/mysql/jdbc.ss + spring/jdbc.ss + spring/data.ss 全 SQL 字符串拼接 → SQL 注入暴露面 + binary protocol 性能加速失;末层断言 `grep -rnE "PreparedStatement\|COM_STMT_PREPARE" lib/ = 0` 实测 |
| 3 | 核心目标 | 三轨闭环:① grep ≥ 5 ② wire-level vec 全绿 ③ e2e 全绿 + bootstrap 固定点 + axiom 红线 = 0 永久 |
| 4 | 规则 | CLAUDE.md §项目本质 L7 + §Root Cause 第一法则 L91 + §交互式单文档 L106 + D025 + D134 §A.4 packet + D134 §A.7 axiom + docs/3-MNK.md §M PSM 九问 |
| 5 | 界定 | 做:7 条(接口扩 / prepared.ss 新建 / binary result set / jdbc.ss MysqlPreparedStatement / wire-level vec test / e2e / JdbcTemplate retcon scope 评估);不做:11 条(multi-result / stored procedure / COM_STMT_RESET / COM_STMT_FETCH / COM_STMT_SEND_LONG_DATA / SCROLLABLE/UPDATABLE / batch / generated keys / metadata API / schema cache / 跨 connection statement cache / utf8mb4 / TLS / Pool)|
| 6 | 步骤 | 4 Phase: 0 D 文档骨架 / 1 接口扩 + COM_STMT_PREPARE / 2 EXECUTE + binary result set + CLOSE / 3 e2e + JdbcTemplate retcon scope 评估 |
| 7 | 对照实验 | 不做 → §第一性需求 卡:① 字符串拼接 SQL 注入暴露面持续 ② 重复 query 无 statement cache 性能差 ③ binary protocol 加速失 ✓ 卡 |
| 8 | Plan vs Execute + Layer | Phase 0 = Plan + Decision Layer(D 文档落盘);Phase 1-3 = Execute + Implementation Layer 留下轮起立;Layer 跨越判定 ✓ 不跨层 |
| 9 | 表面 vs 根 | 根:① OWASP SQL 注入根因解决 ② binary protocol 性能根因解决 ③ D025 接口规约 PreparedStatement 抽象补齐 — 接口层 + 协议层 + 实施层三层齐落,非接口包装表面 ④ JdbcTemplate retcon scope 评估留 Phase 3 — 不一刀切批量执行,符合 §Root Cause |
| 10 | bug 修复方案对比 | 不适用(新功能起立)|

---

# 附录 B: 实施日志

### Phase 0: D 文档落盘 [✓] Done at commit `<回填>` (2026-04-27)

- ✓ PSM 九问填表(响应正文 + §A.7)
- ✓ D136 文档骨架完成(此文件)
- ✓ 改动:`docs/3-decisions/D136-mysql-prepared-statement.md`(新)
- ✓ 用户对话授权:2026-04-27 "我当前的需求是集成 mysql 你觉得下一个应该是哪个" → Claude 推荐 ③ Prepared Statement → 用户 OK
- ✓ 不动 D134 / D135 文件(retcon 留 Phase 3 commit hash known 时回填,若 JdbcTemplate retcon)
- 用户审阅 OK 后下轮起 Phase 1

### Phase 1: 接口扩 + COM_STMT_PREPARE 实施 [ ] Planned

- [ ] `lib/java/sql.ss` 加 `interface PreparedStatement extends Statement` + `Connection.prepareStatement` 接口方法
- [ ] `lib/com/mysql/prepared.ss`(新)~250 LOC — 协议常量 + `class PrepareOk` + sendComStmtPrepare + parsePrepareOk + readPrepareOk + readParamDef + readColumnDefList + `class MysqlPreparedStatement` 框架
- [ ] `lib/com/mysql/jdbc.ss` 加 `MysqlConnection.prepareStatement` 方法
- [ ] `tests/d134_mysql/prepared_test.ss`(新)~150 LOC — 4 vec test(prepare packet bytes + parsePrepareOk reference vec)
- [ ] RED: `grep -rnE "COM_STMT_PREPARE\|prepareStatement\|PreparedStatement\|sendComStmtPrepare" lib/com/mysql/ lib/java/sql.ss \| wc -l = 0` 改前
- [ ] GREEN: ≥ 5 + `bin/ss test tests/d134_mysql/prepared_test.ss` 全绿 + `./build.sh bootstrap` 三阶段固定点 + `bin/ss test tests/` 256+/260 不降

### Phase 2: COM_STMT_EXECUTE + binary result set + COM_STMT_CLOSE 实施 [ ] Planned

- [ ] `lib/com/mysql/prepared.ss` 加 ~350 LOC — sendComStmtExecute + parseBinaryRow + `class MysqlBinaryResultSet : ResultSet` + readQueryResultSetBinary + sendComStmtClose + `MysqlPreparedStatement.executeQuery / executeUpdate / close / setXxx` 实施
- [ ] `tests/d134_mysql/prepared_test.ss` 加 ~200 LOC — 4 vec test(execute packet bytes + parseBinaryRow + NULL bitmap +2 offset 边界 + VARCHAR length-encoded boundary)
- [ ] RED: `grep -rnE "COM_STMT_EXECUTE\|sendComStmtExecute\|parseBinaryRow\|MysqlBinaryResultSet\|sendComStmtClose" lib/com/mysql/ \| wc -l = 0` 改前
- [ ] GREEN: ≥ 5 + 8 vec 全绿 + bootstrap + tests baseline 不降

### Phase 3: e2e + JdbcTemplate retcon scope 评估 [ ] Planned

- [ ] `tests/d136_prepared_statement/integration_test.ss`(新)~150 LOC — probe + 5 e2e(单 param SELECT / 多 param INSERT / 多类型多行 SELECT / NULL 处理 / close 后 connection 复用)
- [ ] **JdbcTemplate retcon scope 评估**:
  - LOC > 200 或破坏既有签名 → 留 D137 sub-follow-up,Phase 3 仅落 e2e + JdbcTemplate 加 1 个 `update(sql, params)` 重载示范
  - LOC ≤ 200 不破签名 → 落 D136 Phase 3:JdbcTemplate 加 `execute(sql, params)` / `update(sql, params)` / `queryForInt(sql, params, col)` 重载,既有签名保留
- [ ] D134 §Status retcon(若 JdbcTemplate retcon)— 加 `D136 superseded text protocol fallback for parameterized queries` 锚
- [ ] GREEN: e2e 5 case 全绿 + tests/d134_mysql/ 8 case + tests/d135_caching_sha2/ 4 case 全绿 + 三轨 RED 闭环 + axiom 红线 = 0 + d_doc_index_linter F1 = 0

---

## D136 全 Phase 收关锚(待 Phase 3 完成时回填)

axiom 兑现度由 D134 "文本协议字符串拼接 + SQL 注入暴露面" → D136 "prepared statement 参数化绑定 + binary protocol 加速 + SQL 注入零风险"。三轨闭环:
- ① `grep -rnE "COM_STMT_PREPARE|COM_STMT_EXECUTE|COM_STMT_CLOSE|prepareStatement|PreparedStatement" lib/com/mysql/ lib/java/sql.ss | wc -l ≥ 5` 待 Phase 1+2 锚
- ② tests/d134_mysql/prepared_test.ss 8 vec 全绿 待 Phase 1+2 锚
- ③ tests/d136_prepared_statement/ 5 case + tests/d134_mysql/ 8 case + tests/d135_caching_sha2/ 4 case 全绿 + bootstrap 三阶段固定点 + d_doc_index_linter F1 = 0 + axiom 红线 grep / nm = 0 永久 待 Phase 3 锚

---
