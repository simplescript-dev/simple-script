# D134: JDBC MySQL wire protocol 纯 SS 实现

**Status:** Plan(Phase 0 — D 文档落盘,等用户审阅措辞 OK 后下轮起 Phase 1)

**Depends on:**
- D133 全 Phase 收关锚(commit 510c497)— `lib/java/sql.ss` driver-agnostic interface + `lib/spring/{jdbc,data}.ss` placeholder body
- CLAUDE.md §项目本质 L7 axiom("应用层 stdlib 用纯 SS 模块实现,不引入应用层 C 库")
- CLAUDE.md §项目技术规则 §Root Cause 优先 L101-103("第一法则,无例外")
- D025 Interface Dispatch(`lib/java/sql.ss` interface 形态依赖)
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优理由)
- `memory/feedback_no_derive_workaround.md`(承认 axiom 例外 = workaround)
- `docs/3-MNK.md` §M PSM 九问 / §N VCM 六验

**承 D133 §6 §58 follow-up 锚** — D133 §核心原则 5 显式声明"本 D 不引入新 driver — D134 MySQL wire protocol 是 follow-up,本 D 范围只做接口抽离 + C link 删除"。本 D 接续兑现实现层。

**Date:** 2026-04-26
**Last Updated:** 2026-04-26

---

## 第一性需求

CLAUDE.md §项目本质字面承诺:**"应用层 stdlib 用纯 SS 模块实现,不引入应用层 C 库"**。

D133 兑现接口层(`lib/java/sql.ss` = driver-agnostic interface),但实现层处"接口齐全无实现"裸契约状态:

- `lib/java/sql.ss:51-54` `DriverManager_getConnection` body = `println("JDBC: no driver registered ..."); exit(1)`
- `lib/spring/jdbc.ss:13-36` `JdbcTemplate.execute/update/queryForList/queryForString/queryForInt` 5 method body 全 placeholder + exit(1)
- `lib/spring/jdbc.ss:41-44` `withTransaction` body placeholder
- `lib/spring/data.ss:73-76` `JpaRepositoryFactory_create` body placeholder

任何用户调用 JDBC 路径(`bin/ss run examples/web_demo.ss` 含数据库逻辑) = 立即 `exit(1)`。

**单一判据**(机械,承 D133 §核心目标"axiom 不是文字,是 grep 输出"口号):

```bash
# 实施层 driver 替换判据(本 D Phase 6 GREEN 收敛)
grep -rn "no driver registered" lib/java/sql.ss lib/spring/jdbc.ss lib/spring/data.ss | wc -l
# 当前 ≥ 8,目标 = 0(driver 全替换 placeholder body)

# axiom 边界永久红线(本 D 范围内 + 永久维持)
grep -rn "libmysqlclient\|libmariadb\|ss_mysql_c_\|@mysql_real_\|@mariadb_" bootstrap/ lib/ build.sh | wc -l
nm bin/ss | grep -c -E "mysql_real|mariadb_"
# 永久 = 0(纯 SS 实现,不允许 C 客户端库 link)

# 集成测试 e2e
bin/ss test tests/d134_mysql/
# 目标 = 全绿(对真 MySQL 实例,docker-compose mysql:8)
```

---

## 核心目标 (Goal)

- **为什么**:D133 axiom 兑现停在"接口空契约",`lib/spring/{jdbc,data}.ss` + `lib/com/zaxxer/hikari.ss` + `lib/jakarta/{sql,persistence}.ss` 整套 Java 生态全栈空跑。axiom 完整兑现 = 接口契约 + **至少一个具体 driver 的纯 SS 实现**;无 driver = 接口契约形式正确实物 0,axiom 兑现度 = 50%
- **是什么**:在 `lib/com/mysql/{wire,handshake,query,jdbc}.ss` 实现 MySQL Native Protocol over TCP 纯 SS driver — Handshake v10 + mysql_native_password 认证 + COM_QUERY + ResultSet packet 解析 — 实现 `lib/java/sql.ss` 的 `Connection`/`Statement`/`ResultSet` interface 契约;`DriverManager_getConnection` 加 url 协议分派 `jdbc:mysql://` → `getMysqlConnection`;`lib/spring/{jdbc,data}.ss` placeholder body 替换为真实 driver 调用
- **单一判据**:三轨闭环(§第一性需求 中三个 grep / nm / test 命令)+ `./build.sh bootstrap` 三阶段固定点 stage2 == stage3(Phase 1 改 bootstrap 后必跑)

> 口号:**接口契约不是 axiom,实现到底才是 axiom 兑现**(对偶 D133 §核心目标"axiom 不是文字,是 grep 输出")。

---

## 核心原则 (Principles)

1. **纯 SS 实现 axiom 不破** — feedback_root_cause_no_cost:不允许 link `libmysqlclient.so` / `libmariadb.so` / `libssl.so` 等任何 C client 库,即使 caching_sha2_password full auth path 复杂(留 sub-D follow-up)。axiom 红线 grep / nm 永久 = 0
2. **接口契约不动** — `lib/java/sql.ss` interface(D133 Phase 1 锁定)签名本 D 不改,只加 driver 实现 + DriverManager dispatch 逻辑
3. **socket client 原语补齐** — `bootstrap/gen/rt/gen_rt_system.ss:175-255` `emitRuntimeNet()` 当前只有 server 端原语(`tcpListen`/`Accept`/`Read`/`Write`/`WriteBytes`/`Close`),缺 client 端 `tcpConnect` + 精确字节读 `tcpReadBytes`(binary protocol 必须读满,现有 `tcpRead` 是字符串单次 read 可能短读)。Phase 1 补齐 + bootstrap 三阶段固定点验证
4. **packet 解析纯 SS** — 新建 `lib/binary.ss`(字节序 little-endian 解析 + length-encoded integer/string)+ 新建 `lib/sha1.ss`(对照 `lib/sha256.ss:1-228` 风格,SHA-1 是 mysql_native_password 必需),不引入任何 C 库
5. **认证选型保守** — Phase 3 优先 `mysql_native_password`(MySQL 5.x default + 8 兼容,SHA-1 单 round XOR);`caching_sha2_password` fast-path(SHA-256 同结构,4-6 LOC 可加)留 sub-D 决定要不要做;`caching_sha2_password` full auth path 需 RSA-OAEP + ASN.1 + DER 解析(≥ 1000 LOC)**永远不做**(本 D 范围明确禁止)
6. **driver 路径分层**(Java 生态既定):
   - `lib/java/` = JDBC 接口契约层(j2ee 抽象,driver-agnostic)
   - `lib/com/<vendor>/` = vendor 实现层(对照 `com.mysql.cj.jdbc` Java namespace + `lib/com/zaxxer/hikari.ss` 现有分层范式)
   - 未来扩 SQLite-pure-SS / Postgres driver:`lib/com/sqlite/jdbc.ss` / `lib/com/postgresql/jdbc.ss` 自然扩
7. **Phase 边界 = commit 边界** — 6 Phase 各自独立 commit,禁打包(承 D133 §Principles 7)
8. **bootstrap 隔离** — 仅 Phase 1 改 `bootstrap/gen/rt/gen_rt_system.ss` + `bootstrap/gen/gen_registry.ss` 加 socket client 原语,其他 Phase(2-6)仅改 `lib/`。Phase 1 后 bootstrap 路径不再触
9. **driver 注册 = 硬编码 dispatch** — SS 无 module-load hook(import 是纯包含无副作用),全局 driver registry Map 自注册不可行;改 `lib/java/sql.ss` 加 import `lib/com/mysql/jdbc` 单向依赖 + `DriverManager_getConnection` 内 if `startsWith("jdbc:mysql://")` 硬编码分派。未来 driver 数 ≥ 3 时再设计 SPI(本 D 范围外)
10. **本 D 范围外明确清单**:TLS、Connection Pool(已 placeholder 在 `lib/com/zaxxer/hikari.ss`,sub-D 处理)、Prepared Statement(`COM_STMT_PREPARE/EXECUTE/CLOSE`)、ORM、`caching_sha2_password` full auth(RSA-OAEP)、utf8mb4 / latin1 字符集切换(本 D 假设 utf8 / utf8mb3)、multi-result statement、stored procedure call、`COM_BINLOG_DUMP` 等 replication 协议
11. **不变量保留**(承 D133):D018(对象布局)/ D022(clone 语义)/ D025(interface dispatch)/ D088 / D123 / D130-133 全不动;mimalloc C link axiom 例外保留

---

## 1. Context Management(上下文管理)

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D134)
2. `CLAUDE.md` §项目本质 + §项目技术规则 §Root Cause 优先
3. `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验 + §K 收敛循环 + §大改档位规则
4. `docs/3-decisions/D133-sqlite-c-link-elimination.md` §Status §核心原则(对偶 axiom 兑现路径)+ §A.6 axiom 边界(mimalloc 例外 / SQLite 应用层)
5. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/gen/rt/gen_rt_system.ss` | 175-255 `emitRuntimeNet()` | server 端 TCP 原语(Phase 1 加 `ss_tcpConnect` + `ss_tcpReadBytes`) |
   | `bootstrap/gen/gen_registry.ss` | (Phase 1 加) | `funcRetTypes.set("ss_tcpConnect","int")` 等注册 |
   | `lib/java/sql.ss` | 49-54 | `DriverManager_getConnection` placeholder(Phase 5 加 url dispatch + import lib/com/mysql/jdbc) |
   | `lib/spring/jdbc.ss` | 13-36, 41-44 | `JdbcTemplate.*` + `withTransaction` placeholder body(Phase 5 替换) |
   | `lib/spring/data.ss` | 73-76 | `JpaRepositoryFactory_create` placeholder body(Phase 5 替换) |
   | `lib/com/zaxxer/hikari.ss` | 全文 | vendor 命名空间约定参考(`lib/com/<vendor>/<module>.ss`) |
   | `lib/sha256.ss` | 1-228 | Phase 2 `lib/sha1.ss` 实现风格参考 |

### Stable Facts

| 项 | 值 |
|---|---|
| 当前 axiom 兑现度 | 50%(D133 接口契约 ✓ + driver 实现 ✗) |
| 当前 driver 数 | 0(`DriverManager` placeholder) |
| 当前 server 端 TCP 原语 | ✓(`ss_tcpListen/Accept/Read/Write/WriteBytes/Close`) |
| 当前 client 端 TCP 原语 | ✗(无 `ss_tcpConnect`,无精确字节读 `ss_tcpReadBytes`) |
| 当前 SHA-256 | ✓ `lib/sha256.ss` 228 行 |
| 当前 SHA-1 | ✗(Phase 2 新建 `lib/sha1.ss`) |
| 当前 RSA / ASN.1 / DER | ✗(本 D 范围外,永远不做) |
| 当前 lib/binary | ✗(Phase 2 新建) |
| 当前 lib/net | ✗(本 D 不创建,client 原语放 bootstrap rt 层一致 server 端范式) |
| 自举状态 | 自举完成,固定点验证通过(commit 510c497,memory project_bootstrap_status) |
| 测试基线 | `bin/ss test tests/` 252/256(D133 §附录 B Phase 6 列锚 4 fail = pre-existing latent,与本 D 零关联) |

### 禁止的 Context 操作

- ❌ 不读 `libmysqlclient` C 源码(本 D 是纯 SS,不是 ABI 绑定)
- ❌ 不读 RSA-OAEP / ASN.1 / PKCS 协议规范(范围外)
- ❌ 不读 TLS / SSL 协议(范围外)
- ❌ 不读 MySQL replication / binlog 协议(范围外)
- ❌ 不读 Prepared Statement(`COM_STMT_*`)协议(范围外)

---

## 2. Tool System

### 必备工具(已在环境中)

| 类别 | 工具 | 用途 |
|---|---|---|
| Claude 内置 | Read / Edit / Write / Bash | 文件操作 |
| 项目专属 | `./build.sh bootstrap` | 三阶段固定点验证(Phase 1 必跑;Phase 2-5 lib 改不动 bootstrap 时建议跑确认零冲击) |
| 项目专属 | `bin/ss test tests/` | 全测试集 |
| 项目专属 | `bin/ss test tests/d134_mysql/` | D134 集成测试(Phase 6 加,docker mysql 依赖) |
| 项目专属 | `nm bin/ss \| grep -c -E "mysql_real\|mariadb_"` | 二进制符号扫描(永久 = 0 axiom 红线) |
| 项目专属 | `docker-compose -f tests/d134_mysql/docker-compose.yml up -d` | 真 MySQL 8 实例(Phase 6) |
| linter | `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate(F1 死指针 = 0) |
| linter | `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射,baseline 不动) |
| linter | `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ 任何新 C 库(`libmysqlclient` / `libmariadb` / `libssl` / `libcrypto` 等)
- ❌ 任何新 build flag(本 D 不改 build.sh / `bootstrap/main.ss` link 段)
- ❌ 任何 mysql server-side / wire protocol 调试器作 build dep(`strace` / `tcpdump` 仅诊断,不入仓)

---

## 3. Execution Orchestration

### 总体节奏

- 6 Phase 各自独立 commit + Phase 1 必跑 bootstrap 固定点 + Phase 6 必跑全测试
- 禁"边补 socket client 原语 边写 handshake 边接 driver 注册"打包

### Phase 详细

#### Phase 0: 本文档落盘(本轮 Plan)

- D134 文档骨架 + PSM 九问 + 6 Phase 序列 + 风险锚 ≥ 7 + 三轨闭环
- 改动:`docs/3-decisions/D134-jdbc-mysql-wire-protocol.md`(新)+ `.claude/next_prompt.md`(改,Phase 1 起立)
- **不动代码**:`git diff --stat bootstrap/ lib/ tools/ = 0`
- **验证**:用户审阅 D 文档措辞 OK 后下轮 Execute Phase 1

#### Phase 1: socket client 原语补齐(bootstrap 改)

- `bootstrap/gen/rt/gen_rt_system.ss` `emitRuntimeNet()` 加:
  - `ss_tcpConnect(host: ptr, port: i32) -> i32`:`socket(AF_INET, SOCK_STREAM, 0)` → `getaddrinfo` (or `gethostbyname`) → `connect(fd, &sockaddr, 16)` → fd / -1
  - `ss_tcpReadBytes(fd: i32, buf: ptr, len: i32) -> i32`:read-loop 直到读满 len 字节或 EOF;返实际读字节数(< len 表示 EOF)
- `bootstrap/gen/gen_registry.ss`:`funcRetTypes.set("ss_tcpConnect","int")` + `funcRetTypes.set("ss_tcpReadBytes","int")`
- **RED**:`grep -nE "ss_tcpConnect|ss_tcpReadBytes" bootstrap/gen/rt/gen_rt_system.ss bootstrap/gen/gen_registry.ss \| wc -l = 0`(改前)
- **GREEN**:RED 改后 ≥ 4 + `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical
- **D025 不变量**:不引入新 IR emit pattern,完全对照 `ss_tcpListen` / `ss_tcpRead` 既有 syscall wrapper 范式

#### Phase 2: lib/binary.ss + lib/sha1.ss + lib/com/mysql/wire.ss

- **`lib/binary.ss`** (新):
  - `function byteToInt(buf: string, offset: int, len: int): int`(little-endian 1/2/3/4/8 byte int 解析)
  - `function intToBytes(n: int, len: int): string`(little-endian 反向)
  - `function readLengthEncodedInt(buf: string, offset: int): int`(MySQL length-encoded int,返值;另出 `lengthEncodedIntSize(buf, offset)` 返字节数 — SS 无 tuple)
  - `function readLengthEncodedString(buf: string, offset: int): string`
  - `function writeLengthEncodedInt(n: int): string`
- **`lib/sha1.ss`** (新):SHA-1 hash 实现,对照 `lib/sha256.ss:1-228` 风格,80 round + 5 个 32-bit state(H0-H4),输出 20-byte hash
- **`lib/com/mysql/wire.ss`** (新):
  - `function readPacket(fd: int): string`(返 payload — 读 3-byte length + 1-byte seq + payload;seq 内部状态用全局 / class 属性 持有)
  - `function writePacket(fd: int, seqId: int, payload: string): int`
  - 注意:packet > 16MB 需分包(`payload_length == 0xFFFFFF` 触发续包),本 D Phase 范围处理 ≤ 16MB(MySQL 默认 max_allowed_packet 1MB,绝大多数 query 远小于)
- **RED**:`ls lib/binary.ss lib/sha1.ss lib/com/mysql/wire.ss = 0`(全不存在)
- **GREEN**:三文件存在 + 单元测试 `tests/d134_mysql/wire_test.ss`(纯字节计算,不依赖网络)— `bin/ss test tests/d134_mysql/wire_test.ss` 全绿

#### Phase 3: lib/com/mysql/handshake.ss(handshake v10 + mysql_native_password)

- **`class HandshakeV10`**:`protoVer:int / serverVer:string / connId:int / scramble:string / capabilityFlags:int / charset:int / statusFlags:int / authPlugin:string`
- **`function parseHandshakeV10(payload: string): HandshakeV10`**:从 server initial packet 解析
- **`function buildHandshakeResponse41(...): string`**:capability flags(`CLIENT_PROTOCOL_41 | CLIENT_PLUGIN_AUTH | CLIENT_SECURE_CONNECTION` 等)+ max_packet(16MB)+ charset(utf8 = 33)+ username(null-term)+ auth_response(length-encoded)+ db(null-term, 可选)+ plugin(null-term)
- **`function mysqlNativePasswordScramble(password: string, scramble: string): string`**:SHA1(pwd) XOR SHA1(scramble + SHA1(SHA1(pwd))) — 20-byte 输出
- **`function mysqlConnect(host: string, port: int, username: string, password: string, database: string): MysqlConnection`**:完整 connect flow — `ss_tcpConnect` → `readPacket(handshake)` → `parseHandshakeV10` → `mysqlNativePasswordScramble` → `buildHandshakeResponse41` → `writePacket(seq=1)` → `readPacket(OK or ERR or AuthSwitchRequest)` → 校验 OK 返 MysqlConnection
- **GREEN**:`tests/d134_mysql/handshake_test.ss` 对真 MySQL 8 实例(docker-compose mysql:8 + `default_authentication_plugin=mysql_native_password`)测连接成功

#### Phase 4: lib/com/mysql/query.ss(COM_QUERY + ResultSet)

- **`function sendQuery(fd: int, sql: string): int`**:packet seq 重置 = 0,写 `[COM_QUERY=0x03][sql payload]`
- **`function readQueryResponse(fd: int): MysqlResultSet`**:
  - 第一个 packet:`payload[0] == 0xFF` → ERR(throw / return null)/ `0x00` → OK 包(更新 / 删除等无 row)/ 其他 → 列计数(length-encoded int)
  - 列定义 packets(数 = 列计数,每个含 catalog / schema / table / org_table / name / org_name / charset / column_length / column_type / flags 等)
  - (5.7.5+ DEPRECATE_EOF flag 设置时跳 EOF 用 OK with 0xFE 头;本 D 假设 DEPRECATE_EOF 设置 = MySQL 8 default)
  - row data packets(text protocol — 每列 length-encoded string,NULL = 0xFB)
  - EOF / OK 终止
- **`class MysqlResultSet : ResultSet`**:持 `socket fd : int / colMetadata : list[ColumnDef] / currentRow : list[string] / closed : int`,实现 `next()` / `getString` / `getInt` / `getLong` / `getDouble` / `getBoolean` / `close`
- **GREEN**:`tests/d134_mysql/query_test.ss` 对真 MySQL 实例 SELECT 实测全绿

#### Phase 5: DriverManager url dispatch + Connection/Statement 实现 + lib/spring 接入

- **`lib/com/mysql/jdbc.ss`** (新):
  - `class MysqlConnection : Connection`:持 `fd:int / autoCommit:int / closed:int`,实现 `createStatement / setAutoCommit / commit / rollback / close / isClosed`
    - `commit()` = `sendQuery(fd, "COMMIT")` + `readQueryResponse`
    - `rollback()` = `sendQuery(fd, "ROLLBACK")` + ...
    - `setAutoCommit(0)` = `sendQuery(fd, "SET autocommit=0")` ...
    - `close()` = `writePacket(fd, 0, [COM_QUIT=0x01])` + `ss_tcpClose(fd)`
  - `class MysqlStatement : Statement`:持 `fd:int`,实现 `executeQuery / executeUpdate / execute / close`
  - `function getMysqlConnection(url: string): MysqlConnection`(协议入口 — 解析 `jdbc:mysql://user:pwd@host:port/db?param=val` URL)
- **`lib/java/sql.ss`** 改:
  - import `{ getMysqlConnection } from "@/lib/com/mysql/jdbc"`(单向依赖,防循环)
  - `DriverManager_getConnection(url)` body 改:`if (startsWith(url, "jdbc:mysql://")) return getMysqlConnection(url) else println / exit(1)`
- **`lib/spring/jdbc.ss`** 改:`JdbcTemplate.*` 5 method body + `withTransaction` body 替换为真实 driver 调用(`DriverManager_getConnection` + `Statement.executeQuery / executeUpdate` + `ResultSet`)
- **`lib/spring/data.ss`** 改:`JpaRepositoryFactory_create` body 替换为真实 `new JdbcTemplate { url: url } + new JpaRepository {...}`
- **GREEN**:`tests/d134_mysql/spring_jdbc_test.ss`(`JdbcTemplate.execute / queryForList / queryForString / queryForInt` 实测对真 MySQL 实例)+ `bin/ss test tests/` 全绿(`spring/data` 等 transitive 测试不再 placeholder + exit(1))

#### Phase 6: 全测试 + RED → 0 + 最终 axiom 验证

- **`tests/d134_mysql/docker-compose.yml`**(新):`mysql:8` 容器 + `MYSQL_ROOT_PASSWORD=test` + `default_authentication_plugin=mysql_native_password` + 端口 mapping
- **`tests/d134_mysql/integration_test.ss`**(新):完整 e2e — `CREATE TABLE / INSERT / SELECT / UPDATE / DELETE / TRANSACTION` 全场景
- **RED 收敛**:
  - `grep -rn "no driver registered" lib/java/sql.ss lib/spring/{jdbc,data}.ss = 0`(driver 全替换)
  - `grep -rn "libmysqlclient\|libmariadb\|ss_mysql_c_\|@mysql_real_\|@mariadb_" bootstrap/ lib/ build.sh = 0`(永久 axiom 红线)
  - `nm bin/ss | grep -c -E "mysql_real|mariadb_" = 0`(driver IR 不污染 bootstrap)
- **GREEN**:三轨闭环 + `bin/ss test tests/` 全绿 + `./build.sh bootstrap` 三阶段固定点 stage2 == stage3(从 Phase 1 后未触 bootstrap,Phase 6 commit 时再次确认零冲击)

### 反模式

- ❌ 边补 socket client 原语 边写 handshake 边接 driver 注册(打包,违反 §Principles 7)
- ❌ 跳过 Phase 1 直接 Phase 2(`lib/com/mysql/wire.ss` 调 `ss_tcpConnect` 不存在 → 编译错)
- ❌ 实现 `caching_sha2_password` full auth(跨层,sub-D follow-up;§Principles 5)
- ❌ link `libmysqlclient.so` / `libmariadb.so`(违反 axiom L7;§Principles 1)
- ❌ Phase 5 driver 注册用全局副作用(SS 无 module-load hook,改用硬编码 dispatch;§Principles 9)
- ❌ Phase 6 不起 docker-compose 仅靠 unit mock 宣告 GREEN(集成测试形态见 §A.6,unit + integration 两层皆需)
- ❌ 在 lib/com/mysql 内引入 SQLite-shape 字段(承 D133 §核心原则 3:driver-specific state 各自管理)

---

## 4. State & Memory

### 编译时 state

| 变量 | 文件 | 角色 |
|---|---|---|
| `funcRetTypes` | `bootstrap/gen/gen_registry.ss` | Phase 1 加 `ss_tcpConnect` / `ss_tcpReadBytes` 返回类型 |
| `MysqlConnection` / `MysqlStatement` / `MysqlResultSet` | `lib/com/mysql/jdbc.ss` | Phase 5 实现接口 |
| `MYSQL_SCRAMBLE_LEN` | `lib/com/mysql/handshake.ss` | constant 20 bytes |
| `CLIENT_PROTOCOL_41` 等 capability flag | `lib/com/mysql/handshake.ss` | constant set |

### 运行时 state(driver 内部)

- socket fd:int(MysqlConnection 持有)
- packet sequence id:int(每 query 重置 = 0)
- column metadata:list[ColumnDef](MysqlResultSet 持有)
- current row buffer:list[string](MysqlResultSet 持有,next() 触发解析下一行)
- autoCommit:int(MysqlConnection 持有)

### 中间产物

- `tests/d134_mysql/docker-compose.yml`(Phase 6 新)
- bootstrap stage1/2/3 二进制(Phase 1 必跑固定点)

### 会话间持久化

- `git log` — Phase 1-6 commit 边界 = 进度锚
- 本文档 — 唯一 D134 状态记录
- `bin/ss test tests/d134_mysql/`(Phase 6 ready 后)

### 禁止 state 操作

- ❌ 把跨 Phase 进度写到 `.claude/next_prompt.md` 累积
- ❌ amend 已 push commit
- ❌ 写 `mysql_protocol_log.md` / `wire_analysis.md` 之类分析文件入仓
- ❌ 把 mysql credentials 硬编码进 `tests/d134_mysql/`(用 docker-compose 环境变量传递)

---

## 5. Evaluation & Observation

### 判据(每 Phase 完成必跑)

| # | 类型 | 命令 | 通过条件 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | Phase 1 三阶段固定点 stage2 == stage3 byte-identical;Phase 2-5 建议跑确认零冲击;Phase 6 commit 时最终确认 |
| 2 | 测试 | `bin/ss test tests/` | Phase 5 后 252+/256 不降(D133 已知 4 fail latent 与本 D 零关联);Phase 6 加 `tests/d134_mysql/` 后全绿 |
| 3 | 集成测试 | `bin/ss test tests/d134_mysql/` | Phase 6 docker-compose mysql:8 起测 + 全绿 |
| 4 | RED 收敛 | `grep -rn "no driver registered" lib/java/sql.ss lib/spring/{jdbc,data}.ss \| wc -l` | Phase 6 = 0 |
| 5 | axiom 红线 | `grep -rn "libmysqlclient\|libmariadb\|ss_mysql_c_\|@mysql_real_\|@mariadb_" bootstrap/ lib/ build.sh \| wc -l` + `nm bin/ss \| grep -c -E "mysql_real\|mariadb_"` | 永久 = 0(本 D 全 Phase + 后续维持) |
| 6 | D 治理 | `bin/ss run tools/d_doc_index_linter.ss` | F1 死指针 = 0 |
| 7 | 反射 baseline | `bin/ss run tools/reflection_health_linter.ss` | 不升(本 D 不触反射) |

### 回归信号(任一出现 = 立即停下)

- ⚠ Phase 1 后 `stage2 ≠ stage3`(`ss_tcpConnect` IR emit 引入 nondeterminism)
- ⚠ Phase 任一阶段 `nm bin/ss | grep mysql_real` 命中 ≥ 1(driver IR 漏入 bootstrap → driver 实现 build flow 错误污染编译器)
- ⚠ Phase 5 `lib/java/sql.ss` import `lib/com/mysql/jdbc` 后出现循环依赖(driver 反向 import `lib/java/sql` 是允许的,但 `lib/java/sql` 必须不依赖具体 driver 内部状态)
- ⚠ Phase 6 `bin/ss test tests/` 出现 D133 4 fail latent 之外的新红(transitive bug)

---

## 6. Constraints & Recovery

### 硬约束

- **不允许 axiom 例外** — feedback_root_cause_no_cost,纯 SS 实现到底
- **不允许跨层** — TLS / Pool / Prepared Statement / ORM / `caching_sha2_password` full auth 全留 sub-D
- **不允许打包 commit** — 6 Phase 各自独立 commit(承 D133 §Principles 7)
- **不允许接口签名变** — `lib/java/sql.ss` interface (D133 Phase 1 锁) 本 D 不动

### 风险锚(R1-R8)

| # | 风险 | 触发场景 | 处置 |
|---|---|---|---|
| R1 | socket client 原语缺失 | Phase 2 `lib/com/mysql/wire.ss` 调 `ss_tcpConnect` 不存在 → 编译错 | Phase 1 先补 + bootstrap 固定点验证;Phase 2 起方可调用 |
| R2 | `caching_sha2_password` 加密复杂度 | MySQL 8 默认 auth plugin = `caching_sha2_password`,full auth 需 RSA-OAEP(本 D 范围外) | Phase 3 优先 `mysql_native_password`;Phase 6 docker-compose 配置 `default_authentication_plugin=mysql_native_password` 强制使用;`caching_sha2_password` fast-path 留 sub-D |
| R3 | 字节序与 length-encoded int 解析 | MySQL 协议 little-endian + 4 段长度编码,SS 现无 binary parsing 能力 | Phase 2 `lib/binary.ss` 集中实现 + 单元测试 100% 覆盖 |
| R4 | 集成测试基础设施 | docker-compose mysql 起测 vs unit mock packets 选型 | Phase 6 两层皆做(unit 测 packet 解析 + docker 测 e2e),docker-compose.yml 可选(CI 不必跑) |
| R5 | `lib/spring/{jdbc,data}.ss` placeholder body 替换语义 | `JdbcTemplate.url:string` field 直接传给 `DriverManager_getConnection`,user / password 等 url 内嵌 | Phase 5 用 standard JDBC URL format `jdbc:mysql://user:pwd@host:port/db?charset=utf8` 解析 |
| R6 | bootstrap 路径污染 | Phase 1 改 `bootstrap/gen/rt/gen_rt_system.ss` 加 `ss_tcpConnect` IR emit,可能影响其他既有 net 测试 | Phase 1 后必跑 bootstrap 三阶段固定点 + `bin/ss test tests/` 全绿确认 |
| R7 | driver 注册循环依赖 | `lib/java/sql.ss` import `lib/com/mysql/jdbc`,而 `lib/com/mysql/jdbc` import `lib/java/sql` 取 interface | 单向依赖:`lib/com/mysql/jdbc` → `lib/java/sql`(实现接口)+ `lib/java/sql` → `lib/com/mysql/jdbc`(取 `getMysqlConnection`)— 单文件 import 不构成循环(SS 模块系统 import 是 inline 不是 cyclic graph),Phase 5 实测验证 |
| R8 | Phase 4 ResultSet 内存累积 | text protocol 全部 row 一次性读完 vs 流式读取 — 大表 SELECT * 内存爆 | Phase 4 ResultSet 用流式:`next()` 触发读下一行(不预读),仅当前 row 在内存;`close()` 必须读完剩余 packet(防止 socket 状态 corrupt) |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 固定点 stage2 ≠ stage3 | `git reset --hard HEAD^`,排查 `ss_tcpConnect` IR emit nondeterminism(`getaddrinfo` 返回值 order 等) |
| Phase 3 `mysql_native_password` scramble 错(MySQL 拒绝 auth) | 对 MySQL 实例日志 `general_log` 比对 SHA-1 中间产物 + `tcpdump` 抓包对照 hex dump |
| Phase 4 ResultSet `next()` 解析失败 | column metadata 与 row 字段数对不上 → 检查 EOF / DEPRECATE_EOF flag 处理(MySQL 5.7.5+ vs 8) |
| Phase 5 driver 注册编译循环依赖 | 改硬编码 dispatch + 单向 import 防循环(承 §Principles 9) |
| Phase 6 集成测试 docker mysql 不可用 | 降级 unit test mock packets(写死 handshake bytes 序列 + 写死 query response packet 序列) |

### 回滚策略

- 任一 Phase 失败 → `git reset --soft HEAD^` 回上一 Phase
- 跨 Phase 回滚需先和用户确认(Phase 边界 = 稳定锚点)

---

# 附录 A: 决策细节

## A.1 driver 路径选型

候选:

| 候选 | 路径 | 优 | 劣 |
|---|---|---|---|
| ① 平铺 | `lib/java/sql_mysql.ss` | 接口 + 实现一文件邻接,易找 | 接口 / 实现混层,违反 Java 生态既定分层 |
| ② vendor 分层 | `lib/com/mysql/jdbc.ss` | 对照 `com.mysql.cj.jdbc` Java namespace + `lib/com/zaxxer/hikari.ss` 现有分层范式;未来扩 `lib/com/postgresql/` / `lib/com/sqlite/` 自然 | 接口 / 实现分文件,需双向 import |

**选 ② vendor 分层(`lib/com/mysql/`)**,理由:

- `lib/java/` 是接口契约层(j2ee 抽象,driver-agnostic)— 接口归 java,实现归 vendor 是 Java 生态既定分层范式,SS 已采纳(`lib/com/zaxxer/hikari.ss` connection pool 实现也归 com.zaxxer vendor namespace)
- 未来扩 SQLite-pure-SS / Postgres driver:`lib/com/sqlite/jdbc.ss` / `lib/com/postgresql/jdbc.ss` 自然扩展,无需重命名
- 对 `com.mysql.cj.jdbc.MysqlConnection` / `MysqlStatement` / `MysqlResultSet` Java 库实际结构 1:1 对照
- 内部细分:`lib/com/mysql/wire.ss`(packet)+ `handshake.ss`(auth)+ `query.ss`(COM_QUERY + ResultSet)+ `jdbc.ss`(Connection/Statement)— 模块边界清晰

## A.2 认证选型:`mysql_native_password` vs `caching_sha2_password`

| 项 | `mysql_native_password` | `caching_sha2_password` fast-path | `caching_sha2_password` full auth |
|---|---|---|---|
| MySQL 5.x default | ✓ | (5.6 起选项) | (5.6 起选项) |
| MySQL 8 default | (兼容 fallback) | ✓ | ✓ |
| Hash | SHA-1 | SHA-256 | SHA-256 + RSA-OAEP |
| 协议复杂度 | 简单(单 round XOR + scramble) | 简单(同 SHA-1 路径结构,SHA-256 替) | 复杂(RSA-OAEP + ASN.1 + DER + PEM cert 解析) |
| SS 现状依赖 | SHA-1(Phase 2 加) | SHA-256(`lib/sha256.ss` ✓) | RSA + ASN.1 + DER(全无,≥ 1000 LOC) |
| 本 D 选型 | ✓(Phase 3 实现) | sub-D follow-up(可选) | **永远不做**(超 axiom 范围 + 工程量爆) |

**Phase 3 选 `mysql_native_password` 优先**,理由:

- 协议简单:`SHA1(pwd) XOR SHA1(scramble + SHA1(SHA1(pwd)))` — 20-byte 输出,单 round 计算
- MySQL 8 用户 CREATE 时显式 `IDENTIFIED WITH mysql_native_password BY 'password'` 即可强制使用;Phase 6 docker-compose `default_authentication_plugin=mysql_native_password` 全局配置无兼容问题
- `lib/sha256.ss:1-228` 已有,SHA-1 实现直接对照风格写 `lib/sha1.ss`,工程量 ≈ 200 LOC

`caching_sha2_password` fast-path 留 sub-D 理由:

- fast-path 协议:`SHA-256(pwd) XOR SHA-256(scramble + SHA-256(SHA-256(pwd)))` — 与 SHA-1 路径完全同构,SHA-256 已存在,4-6 LOC 即可加
- full auth path 跨 axiom 风险:RSA-OAEP 加密 password 上行 — 单独 sub-D 处理 RSA + ASN.1 + DER 解析,**工程量爆 ≥ 1000 LOC + 数学复杂度高**

`caching_sha2_password` full auth 永远不做的理由(对照 §Principles 5):

- RSA-OAEP 实现需大数运算 + ASN.1 BER/DER 解析 + PKCS#1 padding,纯 SS 实现 ≥ 1000 LOC 且数学复杂度高
- TLS 替代路径同样跨 axiom(`libssl.so` 链接违反)— 纯 SS TLS 工程量 > 5000 LOC
- 用户绕开方案:MySQL CREATE USER 时强制用 `mysql_native_password` 即可

## A.3 socket client 原语补齐细节

`bootstrap/gen/rt/gen_rt_system.ss:175-255` `emitRuntimeNet()` 现有(server 端):

- `ss_tcpListen` (port → fd):`socket(AF_INET, SOCK_STREAM, 0)` + `setsockopt(SO_REUSEADDR)` + `bind` + `listen(128)`
- `ss_tcpAccept` (fd → client_fd):`accept(fd, NULL, NULL)`
- `ss_tcpRead` (fd, maxlen → ptr string):单次 `read` 最多 maxlen,**返字符串**(0-terminated)
- `ss_tcpWrite` / `ss_tcpWriteBytes` / `ss_tcpClose`

缺(client 端):

- **`ss_tcpConnect(host: ptr, port: i32) → i32`**:
  - 流程:`socket(AF_INET, SOCK_STREAM, 0)` → `getaddrinfo(host, NULL, &hints, &res)` → `connect(fd, res->ai_addr, res->ai_addrlen)` → 成功返 fd,失败返 -1
  - 实现细节:用 musl libc `getaddrinfo`(类比 `ss_tcpListen` 用 `socket+bind+listen` 直 syscall);hints 设 `AF_INET + SOCK_STREAM`
  - 错误处理:`getaddrinfo` 失败 / `connect` 失败 → close fd + return -1
- **`ss_tcpReadBytes(fd: i32, buf: ptr, len: i32) → i32`**:
  - 现有 `ss_tcpRead` 单次 read 返 ptr 字符串(可能短读 + 字符串 0-terminated 不适合 binary protocol)
  - **必须 read-loop**:`while (read_so_far < len) { n = read(fd, buf + read_so_far, len - read_so_far); if (n <= 0) break; read_so_far += n; }` 返 read_so_far
  - binary protocol 必须读满(packet 长度由前 4 bytes 决定后,后续必须精确读 payload_length 字节)

注意:`ss_tcpConnect` 的 host 参数是 `ptr` SS string,IPv6 / hostname 解析依赖 musl libc `getaddrinfo`;Phase 1 范围内不引入 IPv6-only / DNS over HTTPS 等高级网络栈。

## A.4 packet 解析细节

### MySQL 协议包结构

```
+---------------+---------------+---------------+---------------+
| payload_len[0]| payload_len[1]| payload_len[2]|  sequence_id  |
+---------------+---------------+---------------+---------------+
|                          payload[...]                         |
+---------------------------------------------------------------+
                       (little-endian)
```

- payload_length:3-byte little-endian unsigned int(max 16,777,215 = 16MB - 1)
- sequence_id:1-byte(每 query 重置 = 0,server / client 交替递增)
- payload:payload_length bytes

> payload_length == 0xFFFFFF 触发**续包**:下一个 packet 的 sequence_id 递增,payload 拼接;直到 payload_length < 0xFFFFFF 终止。本 D Phase 范围处理 ≤ 16MB(MySQL 默认 max_allowed_packet 1MB,绝大多数 query 远小)— 续包逻辑入 sub-D。

### length-encoded integer

| 第一 byte | 含义 |
|---|---|
| `< 0xFB` | 直接 1-byte unsigned int |
| `0xFB` | NULL(列值用) |
| `0xFC` | 后续 2-byte little-endian |
| `0xFD` | 后续 3-byte little-endian |
| `0xFE` | 后续 8-byte little-endian |

### length-encoded string

= length-encoded int(长度)+ 同长度 raw bytes

## A.5 driver 注册机制 — 硬编码 dispatch

候选:

- ① 全局 driver registry Map(`url scheme → factory function`)+ driver import 时自注册
- ② `lib/java/sql.ss` 硬编码 `if startsWith` dispatch + 单向 import driver

**选 ② 硬编码 dispatch**,理由:

- SS 无 module-load hook(import 是纯包含 inline,无副作用)— 自注册需 `init_driver()` 函数显式调用,但 `lib/java/sql.ss` 不知道有哪些 driver,没法主动 init
- driver 数量目前 1 个(本 D 只 mysql),未来 2-3 个,硬编码可读性高
- `lib/java/sql.ss` → import `lib/com/mysql/jdbc` 单向依赖,无循环
- 未来加 driver(SQLite-pure-SS / Postgres):`lib/java/sql.ss` `DriverManager_getConnection` 加 `else if branch` 即可

```ss
// lib/java/sql.ss (Phase 5 后)
import { Connection, Statement, ResultSet } from "@/lib/java/sql"  // 接口本文件定义
import { getMysqlConnection } from "@/lib/com/mysql/jdbc"

interface ResultSet { ... }  // D133 Phase 1 锁
interface Statement { ... }
interface Connection { ... }

class DriverManager

function DriverManager_getConnection(url: string): Connection {
    if (startsWith(url, "jdbc:mysql://")) {
        return getMysqlConnection(url)
    }
    // 未来:if (startsWith(url, "jdbc:postgresql://")) return getPostgresConnection(url)
    println(`JDBC: no driver registered for url: ${url}`)
    exit(1)
}
```

driver 数 ≥ 3 时再设计 SPI(本 D 范围外):全局 registry Map + driver import 时调用 `DriverManager_register("jdbc:mysql://", getMysqlConnection)` — 但需 SS 加 module-load hook 或全局变量初始化机制,sub-D 处理。

## A.6 集成测试形态(Phase 6)

候选:

- ① docker-compose mysql 起测(真 MySQL e2e)
- ② unit test mock packets(写死 handshake bytes 序列)

**Phase 6 推荐两层皆做**:

- **unit test**(`tests/d134_mysql/wire_test.ss` / `binary_test.ss` / `sha1_test.ss` / `handshake_scramble_test.ss`):测 packet 解析 / scramble 计算正确性,**不依赖外部 mysql**,纯字节计算 + assertEqual
- **集成测试**(`tests/d134_mysql/integration_test.ss`):真 MySQL 实例 e2e,`tests/d134_mysql/docker-compose.yml` 起 mysql:8 容器

CI 路径:

- 默认 `bin/ss test tests/` 跳过 `tests/d134_mysql/integration_test.ss`(docker 不一定可用)— 可用 `.skip` 或 `import condition`(sub-D 决定)
- 显式 `bin/ss test tests/d134_mysql/` 跑全集(用户需先启 docker:`docker-compose -f tests/d134_mysql/docker-compose.yml up -d`)

## A.7 与 D133 axiom 范式的对偶

D133 §A.6 区分:

- mimalloc = 内存分配器,**基础设施**,axiom 例外保留(C link 允许)
- SQLite = 应用层数据库 client,**应用层 stdlib**,axiom 不允许 C link

本 D 同范式:

- TCP socket syscall(`connect` / `read` / `write` / `getaddrinfo`)= **OS / libc 边界**,axiom 例外允许(底层基础设施,SS 自身需要)
- `libmysqlclient.so` / `libmariadb.so` = **应用层数据库 client 库**,axiom 不允许 link
- mysql wire protocol 实现纯 SS = **应用层 stdlib**,与 `lib/http.ss` / `lib/json.ss` 同等地位

## A.8 PSM 九问填表(Phase 0)

(本 D 头部已述,本节为完整 PSM 九问对照 D133 范式记录)

| # | 字段 | 内容 |
|---|---|---|
| 1 | 总体 | 服务 CLAUDE.md §项目本质 axiom 兑现 — D133 §Status 全 Phase 收关 ✓ + lib/java/sql.ss 接口 driver-agnostic ✓ + lib/spring/{jdbc,data}.ss placeholder body ✓ — axiom 处"接口齐全无实现"裸契约状态,需 driver 落地 |
| 2 | 第一性需求 | "axiom 不是文字,是 grep 输出"(承 D133 口号);Why 链 ① 无 driver = lib/spring + lib/com/zaxxer + lib/jakarta 全栈 placeholder 空转;Why 链 ② 不做 → 用户 JDBC 路径 100% exit(1) |
| 3 | 核心目标 | 三轨闭环:① grep no-driver = 0 ② grep libmysqlclient + nm mysql = 0 ③ docker mysql e2e 全绿 |
| 4 | 规则 | CLAUDE.md §项目本质 L7 + §Root Cause + docs/3-MNK.md §M PSM 九问 |
| 5 | 界定 | 做:driver 实现 + DriverManager dispatch + lib/spring 接入 + socket client 原语;不做:TLS / Pool / PreparedStatement / ORM / caching_sha2 full auth / utf8mb4 切换 |
| 6 | 步骤 | 6 Phase 序列(§Phase 详细) |
| 7 | 对照实验 | 不做 → spring 栈永久空跑 / axiom 兑现停在"接口空契约" / Java 生态承诺持续断裂 ✓ 卡 |
| 8 | Plan vs Execute + Layer | 本轮 Phase 0 = Plan / Decision Layer(D 文档独立审查窗口);后续 Phase 1-6 = Execute / Implementation Layer |
| 9 | 表面 vs 根 | 根:driver 实现是接口契约的"实物到底"(对偶 D133 §A.6 axiom 边界);非 workaround / annotation / 旁路 |
| 10 | bug 修复方案对比 | 不适用(新功能起立,非 bug 修复) |

---

# 附录 B: 实施日志

### Phase 0: D 文档落盘 [⏳ 进行中]

- 本轮 PSM 九问填表(响应正文 + §A.8)
- D134 文档骨架完成(本文件)
- 改动:`docs/3-decisions/D134-jdbc-mysql-wire-protocol.md`(新)+ `.claude/next_prompt.md`(改 — Phase 1 起立 + ultrathink)
- 不动代码:`git diff --stat bootstrap/ lib/ tools/ = 0`
- 等用户审阅措辞 OK 后下轮起 Phase 1

### Phase 1: socket client 原语补齐 [ ] Planned

- bootstrap/gen/rt/gen_rt_system.ss `emitRuntimeNet()` 加 `ss_tcpConnect` + `ss_tcpReadBytes`
- bootstrap/gen/gen_registry.ss 加 funcRetTypes 注册
- bootstrap 三阶段固定点验证

### Phase 2: lib/binary.ss + lib/sha1.ss + lib/com/mysql/wire.ss [ ] Planned

- 字节序 + length-encoded int 解析
- SHA-1 hash(对照 lib/sha256.ss 风格)
- packet read/write 原语

### Phase 3: lib/com/mysql/handshake.ss [ ] Planned

- handshake v10 解析
- mysql_native_password scramble
- mysqlConnect flow

### Phase 4: lib/com/mysql/query.ss + ResultSet [ ] Planned

- COM_QUERY 发包
- column / row packet 解析
- class MysqlResultSet : ResultSet

### Phase 5: DriverManager dispatch + Connection/Statement + lib/spring 接入 [ ] Planned

- lib/com/mysql/jdbc.ss class MysqlConnection / MysqlStatement
- lib/java/sql.ss DriverManager_getConnection url 协议分派
- lib/spring/{jdbc,data}.ss placeholder body 替换

### Phase 6: 全测试 + RED → 0 + axiom 红线 [ ] Planned

- tests/d134_mysql/docker-compose.yml + integration_test.ss
- 三轨闭环 GREEN
- bootstrap 三阶段固定点最终确认

---
