# D134: JDBC MySQL wire protocol 纯 SS 实现

**Status:** Execute(Phase 0/1/1.5/2/3/4 收关,Phase 5-6 待起立)

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
   | `lib/sha256.ss` | 1-228 | SHA-2 风格参考(SHA-1 复用 `lib/crypto.ss` 不新建) |
   | `lib/crypto.ss` | 53 / 500 / 512 / 516 / 520 | `sha1flex` + `Crypto_sha1` + `Crypto_hmacSHA1` + `Crypto_hexToBytes` + `Crypto_bytesToHex`(Phase 2 调研锚定为 SHA-1 SSoT) |

### Stable Facts

| 项 | 值 |
|---|---|
| 当前 axiom 兑现度 | 50%(D133 接口契约 ✓ + driver 实现 ✗) |
| 当前 driver 数 | 0(`DriverManager` placeholder) |
| 当前 server 端 TCP 原语 | ✓(`ss_tcpListen/Accept/Read/Write/WriteBytes/Close`) |
| 当前 client 端 TCP 原语 | ✗(无 `ss_tcpConnect`,无精确字节读 `ss_tcpReadBytes`) |
| 当前 SHA-256 | ✓ `lib/sha256.ss` 228 行 |
| 当前 SHA-1 | ✓ `lib/crypto.ss:53` `sha1flex` + `:500` `Crypto_sha1`(Phase 2 调研发现既有,不新建 `lib/sha1.ss`) |
| 当前 RSA / ASN.1 / DER | ✗(本 D 范围外,永远不做) |
| 当前 lib/binary | ✓ `lib/binary.ss`(Phase 2 新建) |
| 当前 lib/com/mysql/wire | ✓ `lib/com/mysql/wire.ss`(Phase 2 新建,Phase 3 修 latent bug:`class MysqlPacket` field 语法 + positional ctor) |
| 当前 lib/com/mysql/handshake | ✓ `lib/com/mysql/handshake.ss`(Phase 3 新建:`class HandshakeV10` + `class MysqlConnection` + `parseHandshakeV10` + `mysqlNativePasswordScramble` + `sendHandshakeResponse41` + `mysqlConnect`) |
| 当前 lib/com/mysql/query | ✓ `lib/com/mysql/query.ss`(Phase 4 新建:`class ColumnDef` + `sendQuery` + `parse/readResultSetHeader` + `parse/readColumnDef` + `parseRow` + `isEofPacket` + `class MysqlResultSet : ResultSet` 实现 D025 7 method + `readQueryResultSet` 完整 query response read flow) |
| 当前 lib/net | ✗(本 D 不创建,client 原语放 bootstrap rt 层一致 server 端范式) |
| 自举状态 | 自举完成,固定点验证通过(commit 510c497,memory project_bootstrap_status) |
| 测试基线 | `bin/ss test tests/` 255/259(D133 §附录 B Phase 6 列锚 4 fail = pre-existing latent,与本 D 零关联;Phase 2 wire_test 17 + Phase 3 handshake_test 7 + Phase 4 query_test 16 sub-test 全绿) |

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

#### Phase 2: lib/binary.ss + lib/com/mysql/wire.ss(SHA-1 复用 lib/crypto.ss)

- **`lib/binary.ss`** (新):
  - `function byteToInt(buf: string, offset: int, len: int): int`(little-endian 1/2/3/4/8 byte int 解析,binary-safe — `charCodeAt` direct GEP+load 不走 strlen 边界检查)
  - `function intToBytes(n: int, len: int): string`(little-endian 反向 — **NULL byte limitation**:`ss_string_concat` strlen-based,任何 byte == 0 截断,Phase 3 用 byte-by-byte 写或扩 builtin)
  - `function readLengthEncodedInt(buf: string, offset: int): int`(MySQL length-encoded int 返值,NULL marker 0xFB → -1;另出 `lengthEncodedIntSize(buf, offset)` 返字节数 — SS 无 tuple)
  - `function readLengthEncodedString(buf: string, offset: int): string`(同 NULL byte limitation)
  - `function writeLengthEncodedInt(n: int): string`(同 NULL byte limitation)
- **SHA-1**:**复用 `lib/crypto.ss:500 Crypto_sha1` + `:53 sha1flex`(支持 dataHex/prefixHex 路径处理 binary intermediate),Phase 2 调研发现既有实现 + tests/phase5/stdlib_crypto.ss FIPS 180-4 全 vector 已覆盖,不新建 `lib/sha1.ss`**(承 CLAUDE.md §项目本质 复用原则 + §Root Cause 优先 防重复实现;Phase 3 mysql_native_password scramble 需 chained SHA-1 走 `sha1flex(data, "", "", prevHashHex, 0)` 路径)
- **`lib/com/mysql/wire.ss`** (新):
  - `class MysqlPacket { let payload: string; let payloadLen: int; let seqId: int }`(用户原 spec 单 string 返 payload,实施 deviate 为 class — 因 payload 可含 embedded 0x00,`payload.length()` 走 `ss_stringLength` strlen 不可信,需独立 `payloadLen` field 持真实长度;同时 `seqId` 也作 field 持承 D134 §3 Phase 2 注释 "seq 内部状态用 class 属性持有")
  - `function readPacket(fd: int): MysqlPacket`(读 4-byte header + payload buf,失败返 `payloadLen = -1` sentinel)
  - `function writePacket(fd: int, seqId: int, payload: string, payloadLen: int): int`(用户原 spec 3 args,实施 deviate 为 4 args — 显式 `payloadLen` 因 payload 可含 embedded 0x00 时 `length()` 不可信)
  - `function readExactBytes(fd: int, len: int): string`(内部 helper,`" ".repeat(len)` 预分配 len-byte 0x20 buf + `tcpReadBytes` 填充)
  - 注意:packet > 16MB 需分包(`payload_length == 0xFFFFFF` 触发续包),本 D Phase 范围处理 ≤ 16MB(MySQL 默认 max_allowed_packet 1MB,绝大多数 query 远小于)
- **RED**:`ls lib/binary.ss lib/com/mysql/wire.ss tests/d134_mysql/wire_test.ss 2>&1 \| grep -c "No such" = 3`(全不存在;原 4 个,删 lib/sha1.ss = 3)
- **GREEN**:三文件存在 + 单元测试 `tests/d134_mysql/wire_test.ss`(纯字节计算,不依赖网络;含 binary 边界 + Crypto.sha1 sanity)— `bin/ss test tests/d134_mysql/wire_test.ss` 全绿
- **Phase 1.5 patch 前置**:Phase 1 漏注册 `tcpWriteBytes` 在 `bootstrap/checker/checker.ss intFns + funcParamMin/Max + bootstrap/gen/gen_registry.ss funcRetTypes`,binary write 必需(payload < 256 时 header 中段 0x00 byte,strlen-based `tcpWrite` 截断)— Phase 2 起立前补齐,独立 commit + bootstrap 固定点验证(承 §Principles 8 spirit "Phase 1 自包含 bootstrap touch")

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
- **Phase 2 调研发现 `lib/crypto.ss:53 sha1flex + :500 Crypto_sha1` 已实现 + `tests/phase5/stdlib_crypto.ss` FIPS 180-4 全 vector 已覆盖,直接复用,不新建 `lib/sha1.ss`**(承 CLAUDE.md §项目本质 "应用层 stdlib 复用" + Root Cause "防重复"),工程量 = 0 LOC

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

### Phase 0: D 文档落盘 [✓] Done at commit `5a71af9` (2026-04-26)

- ✓ PSM 九问填表(响应正文 + §A.8)
- ✓ D134 文档骨架完成
- ✓ 改动:`docs/3-decisions/D134-jdbc-mysql-wire-protocol.md`(新)
- ✓ 用户审阅 OK,下轮起 Phase 1

### Phase 1: socket client 原语补齐 [✓] Done at commit `2bf24d2` (2026-04-26)

- ✓ bootstrap/gen/rt/gen_rt_system.ss:258-329 `ss_tcpConnect`(socket+getaddrinfo+connect+sin_port@2 htons patch + IPv4-only)+ `ss_tcpReadBytes`(read-loop alloca-counter 精确字节读)
- ✓ bootstrap/gen/gen_runtime.ss declare `@connect / @getaddrinfo / @freeaddrinfo`
- ✓ bootstrap/gen/gen_registry.ss `funcRetTypes.set("tcpConnect","int")` + `tcpReadBytes` + builtinMap names CSV
- ✓ bootstrap/checker/checker.ss `intFns + twoArgFns(tcpConnect)+ funcParamMin/Max(tcpReadBytes 3)`
- ✓ bootstrap 三阶段固定点 stage2 == stage3 byte-identical 通过(二次验证)+ bin/ss sync
- ✓ tests 252 pass / 4 fail = D133 §附录 B Phase 6 latent baseline 不降级
- /simplify 复核 3 agent 回执:MUST-FIX 1 项应用 + MEDIUM 1 项应用 + HIGH SKIP 1 项 + CONCERN SKIP 1 项

### Phase 1.5 patch: tcpWriteBytes checker 注册补漏 [✓] Done at commit `9678b3d` (2026-04-26)

- 调研 Phase 2 buf 设计 question 时发现 Phase 1 漏注册 `tcpWriteBytes`(`bootstrap/gen/rt/gen_rt_system.ss:240-246` ss_tcpWriteBytes IR 既有但 `checker.ss intFns + funcParamMin/Max` + `gen_registry.ss funcRetTypes` 全无 → SS 调 `tcpWriteBytes(...)` 报 "undefined function" 实测确认)
- ✓ bootstrap/checker/checker.ss:278 `intFns` 加 `tcpWriteBytes` + L322-323 加 `funcParamMin/Max.set("tcpWriteBytes", "3")`
- ✓ bootstrap/gen/gen_registry.ss:140 加 `funcRetTypes.set("tcpWriteBytes", "int")`
- ✓ bootstrap 三阶段固定点 stage2 == stage3 byte-identical + bin/ss sync
- ✓ 实测 `tcpWriteBytes(fd, fromCharCode(0), 1)` 写 1 byte 0x00 成功(strlen=0 但 explicit len=1 → binary-safe)
- 决策:作为 Phase 1 完整化补丁独立 commit(承 §Principles 8 spirit "Phase 1 自包含 bootstrap touch" + §Principles 7 "Phase 边界 = commit 边界")

### Phase 2: lib/binary.ss + lib/com/mysql/wire.ss [✓] Done at commit `(本轮第二 commit)`

**关键调研发现**(决策记录):

- **SHA-1 复用 `lib/crypto.ss`**:Phase 2 起立调研发现 `lib/crypto.ss:53 sha1flex + :500 Crypto_sha1` 已完整实现 + `tests/phase5/stdlib_crypto.ss` FIPS 180-4 全 vector 已覆盖 → **不新建 `lib/sha1.ss`**(承 CLAUDE.md §项目本质 复用原则);Phase 3 mysql_native_password chained SHA-1 走 `sha1flex(data, "", "", prevHashHex, 0)` 路径处理 binary intermediate(sha1flex 通过 dataHex/prefixHex 参数避免 strlen 问题)
- **`tcpReadBytes` buf 来源决策**:三方案评估 — ① `" ".repeat(len)` 产 len-byte 0x20 buf(`charCodeAt` direct GEP+load 不走 strlen,binary-safe) ② 加 `bufferAlloc` builtin(scope creep) ③ 多次 `tcpRead` 短读重试(strlen 截断 unsafe);**选 ①**,实测 `" ".repeat(8).length() = 8 + charCodeAt(buf, 7) = 32`,验证 0x20 padding + 直接 byte access 工作 — 0 LOC bootstrap 触
- **写侧 string concat NULL byte limitation**:`ss_string_concat`(`bootstrap/gen/rt/gen_rt_string.ss:14-26`)strlen-based,任何 byte == 0 截断后续 concat,`intToBytes / writeLengthEncodedInt` 返 string 受影响 — 注释明示限制,Phase 3 handshake response 构造时再决方案(setByteAt builtin / Array<int> byte-buffer / 其他);wire.ss `writePacket` 用 byte-by-byte `tcpWriteBytes(fd, fromCharCode(b), 1)` 写 4-byte header 避坑(N+4 syscalls 但功能正确,binary-safe combo)
- **API deviation from 用户原 spec**:`readPacket(fd) → MysqlPacket class`(原 spec `→ string`,因 payload 可含 embedded 0x00 时 `payload.length()` 走 strlen 不可信,需独立 `payloadLen + seqId` field 持真实状态)+ `writePacket(fd, seqId, payload, payloadLen) → int`(原 spec 3 args,实施 4 args 显式 payloadLen 同上理由)

**实施结果**:

- ✓ `lib/binary.ss`(110 LOC):byteToInt + intToBytes + readLengthEncodedInt + lengthEncodedIntSize + readLengthEncodedString + writeLengthEncodedInt(read 侧全 binary-safe + write 侧 NULL 限制注释)
- ✓ `lib/com/mysql/wire.ss`(80 LOC):class MysqlPacket + readPacket + writePacket + readExactBytes helper
- ✓ `tests/d134_mysql/wire_test.ss`(150 LOC):17 unit test 全绿(byteToInt 1/2/3/4-byte LE + offset + intToBytes 1/2-byte non-zero + readLengthEncodedInt < 0xFB / 0xFB NULL / 0xFC / 0xFD markers + lengthEncodedIntSize 全 marker + readLengthEncodedString 1-byte len + 0-byte + writeLengthEncodedInt 1-byte + 0xFA boundary + Crypto.sha1 FIPS 180-4 sanity)
- ✓ `bin/ss test tests/d134_mysql/wire_test.ss` 17 pass / 0 fail
- ✓ `bin/ss test tests/` 253 pass / 4 fail(D133 latent 4 fail 不降级 + 新增 wire_test +1 pass = 252+1 = 253,zero regression)
- ✓ `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical 通过(Phase 2 lib only,无意外 bootstrap 触)
- 不变量保留:D018 / D022 / D025 / D088 / D123 / D130-133 全不动,mimalloc C link axiom 例外保留,既有 Phase 1 socket client + ss_tcpRead/Write/Listen/Accept 原语全保留

### Phase 3: lib/com/mysql/handshake.ss [✓] Done at commit `cf9c3a7` (2026-04-26)

**关键调研发现**(决策记录):

- **SS class field 语法 vs Phase 2 spec mismatch(latent bug 修复)**:Phase 3 起立调研发现 SS class 不支持 inline default value `let X: T = default` 语法,正确语法为 `X: T`(zero-init);class 实例化必须 positional ctor `new ClassName(field1, field2, ...)`,空 ctor `new H` 或 `new H()` 都报错。Phase 2 `lib/com/mysql/wire.ss:15-19 class MysqlPacket { let payload: string = "" ... }` 实际 parse error,但因 `tests/d134_mysql/wire_test.ss` 仅 import lib/binary + lib/crypto(不 import wire),wire.ss 编译路径从未触发,latent bug 未暴露 — Phase 3 顺带修复(承 §Root Cause 优先 + scope 扩到 latent bug 必修;本轮一同 commit,**不**作 Phase 2.5 patch 隔离因 wire.ss 改动 = Phase 3 必要前置而非独立步骤)
- **mysqlNativePasswordScramble 算法验证**:4 reference vectors 通过 Python hashlib 离线计算 — vec1 `pwd='abc' salt=20×0x41 → eece5cb02aeaa29e61bdf883fb14761f4b4b10ef` / vec2 `pwd='secret' salt='ABCDEFGHIJKLMNOPQRST' → 28441590674285e7d03cae7af237504797f70e91` / vec3 `pwd='' salt=20×0x41 → 41843480c89095e82f397bbe33ac92c6b7b5c91f` / vec4 `pwd='password' salt='12345678901234567890' → 1957dce2724282e018f40d905824cb6361f88d41`,SS 实现 100% 对应
- **parseHandshakeV10 测试构造路径**:`system + bash -c + printf '\xHH'` + readFile 路径,charCodeAt direct GEP+load binary-safe(实测 readFile 对 NULL byte buffer:`length()` strlen 截断,但 charCodeAt 越界返实际 byte;parser 全部用 charCodeAt + offset 算术,binary-safe);**`sh` 内置 printf 不展开 `\xHH` 在单引号下,需 `bash -c` 调 GNU printf**(实测验证)
- **实施 deviation 1: sendHandshakeResponse41 stream-write fd**:原 spec `buildHandshakeResponse41 → string` 因响应 payload 含多 embedded 0x00 byte(capability flags 高位 zero / max-packet trailing zero / 23-byte filler / null-terminators)+ `ss_string_concat` strlen-based 会截断 — 三方案评估 ① `setByteAt` builtin(~15 LOC bootstrap + Phase 2.5 prep commit) ② `Array<int>` + bytesToString 转换(死循环) ③ N syscall stream-write 沿用 wire.ss writePacket header 范式(0 LOC bootstrap),**选 ③** 因 sendHandshakeResponse41 一次性调用(连接创建)+ ~58 byte syscall 性能可忽略 + 复用既有范式不引入新概念。决策锚 D134 §A.3
- **实施 deviation 2: HandshakeV10.scrambleHex 存 hex 形式**:原 spec `scramble: string`,实施改 `scrambleHex: string`(40 ASCII chars)— scramble 是 binary 20 bytes 含可能 NULL,string concat 不安全;hex 形式(0-9/a-f)全 ASCII 无 NULL,与 sha1flex dataHex 参数同源 + downstream chained SHA-1 直接 hex 路径处理 binary intermediate
- **测试 deviation: mysqlConnect / sendHandshakeResponse41 留 Phase 6**:unit test 无法构造 socket pair 路径(SS 无 fork / pipe / socketpair builtin),需 docker mysql:8 e2e 验证完整 connect + auth flow

**实施结果**:

- ✓ `lib/com/mysql/handshake.ss`(~245 LOC):
  - `class HandshakeV10 { protoVer, serverVer, connId, scrambleHex, capabilityFlags, charset, statusFlags, authPlugin }`(8 field positional ctor)
  - `class MysqlConnection { fd, autoCommit, closed }`(3 field positional ctor)
  - `function byteToHex2(b: int): string` — local helper,byte → 2 hex chars(ASCII no NULL)
  - `function parseHandshakeV10(payload: string): HandshakeV10` — 全 charCodeAt + offset 算术(binary-safe input)+ scramble1/2 拼成 scrambleHex 40 chars + cap low/high 拼成 32-bit
  - `function mysqlNativePasswordScramble(password: string, scrambleHex: string): string` — 走 sha1flex dataHex 路径处理 binary intermediate(stage1/2/3 全 hex)+ XOR + 返 reply hex 40 chars
  - `function sendHandshakeResponse41(fd, capFlags, charset, username, replyHex, database): int` — stream-write 4-byte header + payload byte-by-byte tcpWriteBytes,~58 syscall per connect
  - `function mysqlConnect(host, port, username, password, database): MysqlConnection` — 完整 flow tcpConnect → readPacket(handshake) → parseHandshakeV10 → mysqlNativePasswordScramble → sendHandshakeResponse41 → readPacket(OK/ERR/AuthSwitch) → 返 fd ≥ 0 / -1 sentinel
- ✓ `tests/d134_mysql/handshake_test.ss`(~85 LOC):7 unit test
  - 4 mysqlNativePasswordScramble reference vectors(Python hashlib 离线算 → SS 100% 对应)
  - 1 parseHandshakeV10 minimal MySQL 8 fixture(via `system+bash -c+printf '\xHH'+readFile`)
  - 2 class positional constructor 测试
- ✓ `lib/com/mysql/wire.ss` latent bug 修复:
  - L15-19 `class MysqlPacket` field 改 `payload: string / payloadLen: int / seqId: int`(去 `let X: T = default` 错误语法)
  - L37 `new MysqlPacket("", 0, 0)` positional ctor 显式
- ✓ `bin/ss test tests/d134_mysql/handshake_test.ss` 7 pass / 0 fail(本轮新增)
- ✓ `bin/ss test tests/d134_mysql/` 24 pass / 0 fail(wire 17 + handshake 7)
- ✓ `bin/ss test tests/` 254 pass / 4 fail(D133 latent 4 fail baseline 不降级 — spring_web_params / harness_task / d096_p4_l2_reactive / harness_bug 全 pre-existing,与本 D 零关联;新增 wire_test 17 + handshake_test 7 = +24 net pass:252+24=276 不对,let me重新数:基线 252+wire 17=269;现在 252-基线+18+7=net = ?。实测输出 254 pass / 258 total = D133 baseline 252/256 + handshake_test 1 file +7 sub-pass + 自动可能 + 既 wire 文件已计 → 实际 +2 file +2 pass(file-level),OK)
- ✓ `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical 通过(Phase 3 lib only,零 bootstrap 冲击)

**不变量保留**:D018 / D022 / D025 / D088 / D123 / D130-133 全不动;mimalloc C link axiom 例外保留;Phase 1/1.5 socket client 原语 + Phase 2 lib/binary + lib/crypto SHA-1 + wire packet API 全保留;handshake.ss 单向依赖 lib/binary + lib/com/mysql/wire + lib/crypto,无循环。

### Phase 4: lib/com/mysql/query.ss + ResultSet [✓] Done at commit `<PHASE4_HASH>`

**关键调研发现**:

- **DEPRECATE_EOF 决策 = legacy EOF 路径**:D134 §3 line 217 spec "本 D 假设 DEPRECATE_EOF 设置 = MySQL 8 default",但 Phase 3 sendHandshakeResponse41 capFlags 实际**未**设 `CLIENT_DEPRECATE_EOF`(0x01000000),server 发送 legacy EOF(0xFE 头 + payload < 9 byte)。Phase 4 与 Phase 3 实际 capFlags 对齐,按 legacy EOF 处理(`isEofPacket(payload, payloadLen): int { 0xFE 头 && < 9 byte → 1 }`)— **不强行回设 DEPRECATE_EOF**(scope 控制,Phase 5 集成时若需可加)。决策 deviation 锚 D134 §3 Phase 4 + 本节实施日志
- **ColumnDef 字段最小集 = 4 字段决策**(name / colType / columnLen / charset):D134 §3 line 216 描述 packet 含 catalog/schema/table/org_table/name/org_name/charset/column_length/column_type/flags 等(完整集),但 ColumnDef **class field** 由 driver 决定哪些 metadata 必要。MysqlResultSet `getString(col)` linear search 仅需 `name`,future 类型转换可能用 `colType / columnLen / charset` — catalog/schema/table/org_table/org_name 是 wire spec 字段但 driver 不读字段名仅 skip bytes,4 字段最小集减 ctor 复杂度 + 内存,符合 D134 §Principles 7(Phase 边界 = 必要最小集)
- **MysqlResultSet 6 字段决策**(fd / colCount / colMetadata / currentRow / closed / hasMoreRows):D134 §3 line 220 spec 4 字段 `fd / colMetadata / currentRow / closed`,实施扩 2 字段:① `colCount: int` 双语义 — SELECT 路径=列数(parseRow / colIndex 必需);OK/ERR 路径=哨兵 RESULT_SET_HEADER_OK/ERR(-2/-1,无 row 时 colMetadata=[] 信息无法靠 .length() 还原) ② `hasMoreRows: int` — 三态语义 (closed=0,hasMoreRows=1) 流式中 / (closed=0,hasMoreRows=0) EOF 已读未 close(防 next() 重复读 socket) / (closed=1,hasMoreRows=0) 已 close。删任一字段都丢信息。simplify quality agent M1+M2 SKIP(语义不冗余) + readability agent OK(`hasMoreRows` 动词起头符 d 项,`closed` SS 无 bool 是 idiom)
- **parse / read 双层 split**:`parseResultSetHeader(payload, payloadLen)` / `parseColumnDef(payload)` / `parseRow(payload, colCount)` 纯解析(payload 来自任何源,test 用 bash printf fixture);`readResultSetHeader(fd) / readColumnDef(fd)` 一行 wrapper 加 `readPacket(fd)` 走 socket。**D134 §A.4 测试性决策** — 单元测试可驱动 parse 部分(无需 socket pair / fork builtin),保留 socket 路径供 Phase 5/6 集成
- **`skipLengthEncodedString(payload, offset): int` helper 抽出**:`parseColumnDef` 6 次 skip(catalog/schema/table/org_table/org_name 各 1 次 + read 1 次 name)— 复用 `readLengthEncodedInt + lengthEncodedIntSize` 双调用 + offset 推进 + NULL marker(< 0)0 数据 byte 处理。属 query.ss domain-specific(NULL 路径语义),不推回 lib/binary(违反 SSoT 通用层不承载 mysql NULL 语义);simplify reuse agent SKIP(正是双原语正确组合)
- **multi-line import 是 SS 不支持的语法**(本轮调研发现):初版 query_test.ss 用 multi-line import {\n  parseResultSetHeader,\n  parseColumnDef,\n  ...\n} from "..." 编译报 "parse error at line 56: expected newline or '}', found COMMA"(line 56 是 import 展开后位置不是源文件位置)。Phase 3 handshake_test.ss line 10 与 Phase 2 wire_test.ss line 7 全用单行 import,实测确认 SS parser 仅支持单行 import 语法。query_test.ss 改回单行 import 即过。**latent SS parser 限制**(可记 sub-D follow-up 或 Phase 5+ 修复 — 不在本轮 scope)
- **测试 deviation: sendQuery / readQueryResultSet 留 Phase 6 docker e2e**:同 Phase 3 mysqlConnect 决策,SS 无 fork/pipe/socketpair builtin 单元测试无法构造 socket pair 路径,完整 query response read flow 需 docker mysql:8 e2e

**实施结果**:

- ✓ `lib/com/mysql/query.ss`(~257 LOC):
  - `class ColumnDef { name, colType, columnLen, charset }`(4 字段最小集 positional ctor)
  - 8 个文件级常量:`COM_QUERY=0x03 / NULL_MARKER=0xFB / ERR_HEADER=0xFF / OK_HEADER=0x00 / EOF_HEADER=0xFE / RESULT_SET_HEADER_ERR=-1 / RESULT_SET_HEADER_OK=-2`
  - `function sendQuery(fd: int, sql: string): int` — packet seq=0,payload=`fromCharCode(COM_QUERY)+sql`,sql 全 ASCII nonzero string concat 安全,直调 `writePacket(fd, 0, payload, sqlLen+1)`
  - `function parseResultSetHeader(payload, payloadLen): int` — ERR/OK/列计数三分枝
  - `function readResultSetHeader(fd: int): int` — readPacket(fd) wrapper
  - `function skipLengthEncodedString(payload, offset): int` — domain-specific helper(NULL marker 不消费数据 byte)
  - `function parseColumnDef(payload: string): ColumnDef` — 6 次 skip + 1 次 readLengthEncodedString name + 1 byte filler + charset(2 LE) + columnLen(4 LE) + colType(1)
  - `function readColumnDef(fd: int): ColumnDef` — wrapper
  - `function isEofPacket(payload, payloadLen): int` — legacy EOF 检测(0xFE 头 + payloadLen < 9)
  - `function parseRow(payload: string, colCount: int): Array<string>` — 每列 NULL marker(0xFB)→ "" 或 length-encoded string
  - `class MysqlResultSet : ResultSet` 实现 D025 interface 7 method:`next / getString / getInt / getLong / getDouble / getBoolean / close` + `private function colIndex(col: string): int`(simplify quality M3 落实,private 防 D025 接口外暴露)
  - `function readQueryResultSet(fd: int): MysqlResultSet` — 完整 query response read flow(header → N column def → legacy EOF discard → return rs with hasMoreRows=1)
- ✓ `tests/d134_mysql/query_test.ss`(~149 LOC):16 unit test
  - 5 parseResultSetHeader test(ERR/OK/列计数 1/列计数 5/empty)
  - 4 isEofPacket test(EOF marker fixture / 非 EOF 错误头 / 非 EOF 长 payload / empty)
  - 1 parseColumnDef minimal id INT 11 utf8mb3 fixture(via `system+bash -c+printf '\xHH'+readFile`,charCodeAt direct GEP+load binary-safe)
  - 3 parseRow test(2 列 Alice/42 / NULL 列 0xFB / 1 列 empty string len=0)
  - 1 ColumnDef positional ctor 契约
  - 2 MysqlResultSet 测试(positional ctor + getters / getBoolean true 变体 4 case)
- ✓ `bin/ss test tests/d134_mysql/query_test.ss` 16 pass / 0 fail(本轮新增)
- ✓ `bin/ss test tests/d134_mysql/` 3 pass / 0 fail(wire + handshake + query 三 file 全绿)
- ✓ `bin/ss test tests/` 255 pass / 4 fail / 259 total — D133 §附录 B Phase 6 latent 4 fail 基线不降级(spring_web_params / harness_task / d096_p4_l2_reactive / harness_bug 全 pre-existing,与 Phase 4 零关联;新增 query_test.ss 1 file pass = +1 vs Phase 3 baseline 254/4/258)
- ✓ `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical(Phase 4 lib only,零 bootstrap 冲击)
- ✓ /simplify 复核 4 agent 回执(reuse + quality + efficiency 并发 + readability 否决权):
  - **MUST-FIX 0** 项
  - **MEDIUM 落实 3 项**:① quality M3 `MysqlResultSet.colIndex` 加 `private function`(D068 + tests/phase5/private_field.ss 实证 SS 支持)+ 删 test `assertEqual(rs.colIndex(...), N)` 直测 3 行(封装意义 — 通过 `getString` 间接验证已留) ② quality M2 `next()` 双 if 合并为 `if (this.closed != 0 || this.hasMoreRows == 0) { return 0 }` ③ quality M1 `colCount` 字段加 WHY 注释(双语义钉)
  - **SKIP 锚**:① reuse 1 MEDIUM SKIP(`parseRow` else 分支 read+advance 不能用 skip 替 — skip 只 advance 不 read,改后反 +1 charCodeAt) + 3 LOW SKIP(`colIndex` linear / EOF 检测对偶 / fixture 抽 helper 全 scope 控) ② quality 5 LOW SKIP(`getBoolean` 三 if 链 vs ternary readability 等价 / test 字面量 const 反违 readability rubric a / column type byte single-use inline / `close()` SS 无 break+continue / WHAT-only 注释扫描 0 删除) ③ efficiency 5 SKIP(E1 Array.push O(N²) lib/Array 语义 scope 外 / E2 fused decodeLengthEncoded 1% 收益污染 SSoT API / E3 colIndex Map<string,int> 小 N linear 比 hash 快 / E4 closed/hasMoreRows int 非效率问题 / E5 fixture system call 总耗 < 500ms 微优化) ④ readability NULL_MARKER → COLUMN_NULL_MARKER 非阻断(Phase 5 binary protocol NULL bitmap 时 rename)

**不变量保留**:D018 / D022 / D025(interface dispatch — Phase 4 兑现 MysqlResultSet : ResultSet 7 method 实现)/ D068(private 修饰符 — Phase 4 应用)/ D088 / D123 / D130-133 全不动;mimalloc C link axiom 例外保留;Phase 1/1.5 socket client 原语 + Phase 2 lib/binary + lib/com/mysql/wire + Phase 3 lib/com/mysql/handshake + lib/crypto SHA-1 全保留;query.ss 单向依赖 lib/binary + lib/com/mysql/wire + lib/java/sql,无循环。Phase 5(lib/com/mysql/jdbc.ss class MysqlConnection : Connection + class MysqlStatement : Statement + lib/java/sql.ss DriverManager_getConnection url dispatch + lib/spring/{jdbc,data}.ss placeholder 替换)待起立。

### Phase 5: DriverManager dispatch + Connection/Statement + lib/spring 接入 [ ] Planned

- lib/com/mysql/jdbc.ss class MysqlConnection / MysqlStatement
- lib/java/sql.ss DriverManager_getConnection url 协议分派
- lib/spring/{jdbc,data}.ss placeholder body 替换

### Phase 6: 全测试 + RED → 0 + axiom 红线 [ ] Planned

- tests/d134_mysql/docker-compose.yml + integration_test.ss
- 三轨闭环 GREEN
- bootstrap 三阶段固定点最终确认

---
