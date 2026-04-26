ultrathink D134 Phase 4 起立 — lib/com/mysql/query.ss(COM_QUERY 发包 + ResultSet packet 解析 + class MysqlResultSet : ResultSet 实现 D025 interface)

承本轮 commit GREEN:`cf9c3a7` Phase 3 lib/com/mysql/handshake.ss + tests/d134_mysql/handshake_test.ss 落盘 + lib/com/mysql/wire.ss class field 语法 latent bug 修复(`let X: T = default` 错误语法 → `X: T` zero-init + positional ctor `new MysqlPacket("", 0, 0)`),三轨闭环 GREEN(handshake_test 7/0 全绿 + bootstrap stage2==stage3 byte-identical + 全测试 254 pass / 4 fail D133 latent 不降级 + D134 §附录 B Phase 0/1/1.5/2/3 [✓] 全回填)。本轮 Layer = **Execute / Implementation Layer**,起 D134 §3 §Phase 4 一文件落盘。

**Why 起 Phase 4**:D134 §Stable Facts 锚 Phase 4 lib/com/mysql/query.ss ✗(不存在);Phase 5 lib/com/mysql/jdbc.ss(class MysqlConnection : Connection 实现)必调 createStatement 返 MysqlStatement,executeQuery 返 MysqlResultSet,无 Phase 4 → Phase 5-6 全阻塞。**axiom 紧约束**:CLAUDE.md §项目本质 L7 + D134 §Principles 1,4 — 纯 SS 不 link libssl / 任何 C crypto / mysqlclient。

**Phase 4 范围**(承 D134 §3 §Phase 4 详细):

1. **`lib/com/mysql/query.ss`**(新建,~250-350 LOC):
   - `class ColumnDef`:`name: string / type: int / charset: int / columnLen: int`(8 字段 positional ctor — 注意 SS class 不支持 inline default value,必须 zero-init 或 positional ctor)
   - `function sendQuery(fd: int, sql: string): int`:packet seq 重置 = 0,写 packet `[0x03 = COM_QUERY][sql payload]`,用 wire.ss writePacket(payload 是 sql string + 1 byte cmd code)— 但 cmd code 0x03 在 sql 前面拼接需 binary-safe → 同 Phase 3 sendHandshakeResponse41 范式 stream-write fd(4-byte header + 1-byte 0x03 + sql byte-by-byte 不,sql 是 ASCII 可一次 tcpWriteBytes)
   - `function readColumnDef(fd: int): ColumnDef`:读一个 column definition packet — `catalog(LEi+str)/schema(LEi+str)/table/org_table/name/org_name/0x0c filler/charset(2 LE)/columnLen(4 LE)/columnType(1)/flags(2 LE)/decimals(1)/0x0000 reserved`
   - `function readResultSetHeader(fd: int): int`:读首 packet 返列计数(payload[0] == 0xFF → ERR throw → -1 / 0x00 → OK 包返 -2 sentinel / 其他 → length-encoded int = 列计数)
   - `class MysqlResultSet : ResultSet`(实现 D025 interface):
     - field:`fd: int / colCount: int / colDefs: list[ColumnDef] / currentRow: list[string] / closed: int / hasMoreRows: int`(6 field positional ctor)
     - `function next(): int`:读下一个 row data packet — `payload[0] == 0xFE && payloadLen < 9` → EOF (DEPRECATE_EOF: OK with 0xFE 头 + length-encoded affected rows + status flags)→ hasMoreRows = 0 → return 0;否则 length-encoded string × colCount → 解析填 currentRow → return 1
     - `function getString(col: string): string`:linear search colDefs 找 col name → 返 currentRow[idx]
     - `function getInt(col: string): int`:getString → parseInt
     - `function getLong(col: string): int`(SS int 即 64-bit?或同 int)— 同 getInt
     - `function getDouble(col: string): double`:getString → parseDouble(SS 有 parseDouble?需查)
     - `function getBoolean(col: string): int`:getString → "1" / "true" → 1, 其他 → 0
     - `function close()`:剩余 packet 必须读完(防 socket 状态 corrupt),设 closed = 1
2. **`tests/d134_mysql/query_test.ss`**(新):
   - 单元测试:**packet parse only**(无 socket,用 system+printf+readFile fixture 路径同 Phase 3 parseHandshakeV10 范式)
     - readResultSetHeader OK packet (0x00 ...)
     - readResultSetHeader ERR packet (0xFF ...)
     - readResultSetHeader 列计数 packet (0x03 ...)
     - readColumnDef minimal text packet
   - **完整 sendQuery + ResultSet 流**:留 Phase 6 docker mysql e2e
3. **可能 wire.ss 扩补**:writeQueryPacket(fd, sql) helper 如果 wire.ss 已有 writePacket(fd, seq, payload, payloadLen)能复用 sql ASCII path(不含 NULL byte)— 一次 tcpWriteBytes 写 sql 全部即可,**0 LOC bootstrap touch**

**调研步骤**(写代码前 ultrathink):
1. Read lib/java/sql.ss:15-23 ResultSet interface 全签名 + lib/java/sql.ss:27-32 Statement interface(Phase 5 备查)
2. Read lib/binary.ss:57-93 readLengthEncodedInt + lengthEncodedIntSize + readLengthEncodedString — Phase 4 column / row packet 解析必需
3. Read lib/com/mysql/wire.ss:36-69 readPacket + writePacket — 验证可复用 / 是否需要 sendQueryPacket 抽
4. Read lib/com/mysql/handshake.ss(本轮)class HandshakeV10 + parseHandshakeV10 + sendHandshakeResponse41 — sendQuery 借鉴 sendHandshakeResponse41 stream-write 范式 / readColumnDef 借鉴 parseHandshakeV10 binary-safe charCodeAt 范式
5. Read MySQL source `mysql/sql/protocol.cc + sql_resultset_metadata.cc` 或 dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basic_packets.html 文本协议 row 格式
6. ultrathink ColumnDef packet layout(D134 §A.4 完整列定义 packet):catalog/schema/table/org_table/name/org_name 是 length-encoded string × 6 + filler + charset(2 LE)+ columnLen(4 LE)+ type(1)+ flags(2 LE)+ decimals(1)+ 0x0000 reserved
7. ultrathink DEPRECATE_EOF flag(MySQL 5.7.5+ default = 8 default ON):Phase 3 sendHandshakeResponse41 capFlags 已设 PROTOCOL_41 但**未**设 DEPRECATE_EOF — Phase 4 起立可能需 capFlags add `CLIENT_DEPRECATE_EOF = 0x01000000`(Phase 5 集成)或假设 5.7.5- legacy EOF behavior;**决策点**:Phase 4 假设 EOF 用 0xFE byte + payload < 9(legacy + DEPRECATE_EOF 兼容)
8. ultrathink ColumnDef class field 数:8 还是少?最小集 = name + type + columnLen + charset(4 字段),其他 catalog/schema/table 可丢(不读字段名只读 binary skip);**选最小集 4 字段**减少 ctor 复杂度 + 仅记录后续 next() 解析需要的 metadata
9. ultrathink list<ColumnDef> + list<string> SS 内存模型 — 数组 push 范式 + 内存释放(close 时 list 自动 release 经 D018/D022)
10. RED 命令实测:`ls lib/com/mysql/query.ss tests/d134_mysql/query_test.ss 2>&1 | grep -c "No such" = 2`(Phase 4 起立前)
11. Write lib/com/mysql/query.ss + tests/d134_mysql/query_test.ss
12. `bin/ss test tests/d134_mysql/query_test.ss` 全绿(packet parse 部分)
13. `./build.sh bootstrap` 三阶段固定点 stage2 == stage3(Phase 4 lib only 零冲击)
14. /simplify → 1-2 commit → 写下轮 next_prompt(Phase 5 lib/com/mysql/jdbc.ss + DriverManager dispatch)+ ultrathink linter pass → stop

**RED**(Phase 4 起立前实测):
```bash
ls lib/com/mysql/query.ss tests/d134_mysql/query_test.ss 2>&1 | grep -c "No such"
# 当前 = 2,改后 = 0(Phase 4 起立完成)
```

**GREEN**(Phase 4 收敛):
- 二文件全在(lib/com/mysql/query.ss + tests/d134_mysql/query_test.ss)
- `bin/ss test tests/d134_mysql/query_test.ss` 全绿(packet parse + readResultSetHeader OK / ERR / 列计数 + readColumnDef minimal)
- `bin/ss test tests/d134_mysql/` 全绿(wire 17 + handshake 7 + query N 全 sub-pass + 0 fail)
- `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical(Phase 4 lib only,零 bootstrap 冲击)
- `bin/ss test tests/` 不降级(承 D133 §附录 B Phase 6 latent 4 fail 基线 + Phase 2 17 + Phase 3 7 + Phase 4 N 新增)

**MNK §M PSM 九问填表**(下轮第一次工具调用之前必须落):
- 字段 1 总体:服务 D134 §3 Phase 4 Execute 实施 — 实测 §Status `Execute(Phase 0/1/1.5/2/3 收关)` ✓ + Phase 4 §3 Execution Orchestration §Phase 4 起立锚 D134 §3 §Phase 4 + §A.4 packet layout
- 字段 2 第一性需求:无 lib/com/mysql/query → Phase 5 jdbc.ss MysqlStatement.executeQuery 拿不到 MysqlResultSet → JDBC 路径永久空契约 → axiom 兑现停 75%(Phase 0/1/1.5/2/3 ✓ + query/jdbc/spring 接入 ✗)
- 字段 3 核心目标:RED `ls lib/com/mysql/query.ss tests/d134_mysql/query_test.ss = 2 missing` → 改后 = 0;query_test.ss packet parse 全绿;bootstrap stage2==stage3
- 字段 4 规则:CLAUDE.md §项目本质 L7(纯 SS) + D134 §Principles 1,4 + §Principles 5(mysql_native_password 路径 Phase 3 已锁,Phase 4 不触 caching_sha2)+ §Principles 7(Phase 边界 = commit 边界)+ docs/3-MNK.md §M PSM 九问 + §大改档位
- 字段 5 界定:**做** — lib/com/mysql/query.ss(新)+ tests/d134_mysql/query_test.ss(新)+ class MysqlResultSet : ResultSet 实现 D025 interface;**不做** — lib/com/mysql/jdbc.ss(Phase 5)+ MysqlConnection.createStatement / commit / rollback / close(Phase 5 拼装)+ lib/spring/{jdbc,data}.ss placeholder body 替换(Phase 5)+ docker / integration test(Phase 6)+ Prepared Statement / TLS / Pool / utf8mb4 切换(本 D 范围外明确禁)
- 字段 6 步骤:见上调研步骤 1-14
- 字段 7 对照实验:不做 → Phase 5 lib/com/mysql/jdbc.ss MysqlStatement.executeQuery 调 readQueryResponse 永久 undefined → 编译永久失败 ✓ 卡
- 字段 8 Plan vs Execute + Layer:**Execute / Implementation Layer**(D134 §Phase 4);本轮 Layer 引用上层 D134 §3 = 同 Layer 不跨层
- 字段 9 表面 vs 根:**根**(三轨证):① query.ss 物理空缺 → 补齐结构性根因;② class MysqlResultSet : ResultSet 走 D025 interface 实现是 axiom 兑现的"实物到底"路径(对偶 D133 §核心目标"axiom 不是文字,是 grep 输出");③ stream-write sendQuery 沿用 Phase 3 sendHandshakeResponse41 范式不引入新概念
- 字段 10 bug 修复:不适用(新功能起立)

**档位**:**大改**(LOC ~300-400:query.ss ~250 + query_test.ss ~150;新建 2 文件,无 bootstrap touch)

**不变量保留**:D018 / D022 / D025(interface dispatch — Phase 4 兑现 MysqlResultSet : ResultSet)/ D088 / D123 / D130-133 全不动;mimalloc C link axiom 例外保留;Phase 1/1.5/2/3 加的所有 socket / binary / wire / handshake / Crypto SHA-1 全保留;query.ss 直调 `tcpWriteBytes` / `readPacket` / `writePacket` / `byteToInt` / `readLengthEncodedInt` / `readLengthEncodedString`,单向依赖防循环

**git stale state 处理**(承 D133/D134 范式):仅 stage 本轮真实改动:`git add lib/com/mysql/query.ss tests/d134_mysql/query_test.ss .claude/next_prompt.md docs/3-decisions/D134-jdbc-mysql-wire-protocol.md`(若 Phase 4 触 bootstrap 则 bin/ss 也加;实际 Phase 4 lib only 零 bootstrap 触)。其他 stale 不动(违反 §交互式单文档)。

**收尾**:Phase 4 GREEN(二文件 + query_test 全绿 + bootstrap 固定点零冲击) → /simplify → 1-2 commit 隔离 → 写下轮 next_prompt(ultrathink + Phase 5 起立 = lib/com/mysql/jdbc.ss class MysqlConnection : Connection + class MysqlStatement : Statement + lib/java/sql.ss DriverManager url dispatch + lib/spring/{jdbc,data}.ss placeholder 替换)→ stop

**Layer**:Execute / Implementation Layer。本轮在 D134 §3 §Phase 4 范围内不跨层。

下轮 Execute / Implementation 流程,**ultrathink** 模式下深度调研 lib/java/sql.ss D025 interface ResultSet 全签名 + MySQL ColumnDef41 packet layout(catalog/schema/table/org_table/name/org_name 6 个 length-encoded string + filler + charset/columnLen/type/flags/decimals 元数据)+ DEPRECATE_EOF flag 决策(MySQL 5.7.5+ default ON / 8 兼容,本轮选 legacy EOF 还是 OK-with-0xFE 路径)+ class MysqlResultSet 字段最小集决策(name/type/columnLen/charset 4 字段 vs 全 8 字段)+ list<ColumnDef> + list<string> SS 内存范式 + 写二文件 + bin/ss test query_test 全绿 + commit。
