ultrathink D134 Phase 5 起立 — lib/com/mysql/jdbc.ss(class MysqlConnection : Connection + class MysqlStatement : Statement)+ lib/java/sql.ss DriverManager_getConnection url dispatch + lib/spring/{jdbc,data}.ss placeholder body 替换

承本轮 commit GREEN:`32098ac` Phase 4 lib/com/mysql/query.ss + tests/d134_mysql/query_test.ss 落盘 — class ColumnDef 4 字段最小集 + 8 文件级常量 + sendQuery + parse/read 双层 split(parseResultSetHeader / parseColumnDef / parseRow / isEofPacket / readResultSetHeader / readColumnDef / readQueryResultSet)+ class MysqlResultSet : ResultSet 实现 D025 7 method + private function colIndex(simplify quality M3) — 16 unit test 全绿(packet parse only)+ bootstrap 三阶段固定点 stage2==stage3 byte-identical(Phase 4 lib only,零 bootstrap 冲击)+ tests 255 pass / 4 fail / 259 total = D133 latent baseline 不降级 + D134 §Status Phase 0/1/1.5/2/3/4 收关 / §Stable Facts 加 lib/com/mysql/query 状态行 / §附录 B Phase 4 [✓] 全回填(实施日志 6 段调研 + 8 段实施结果)。本轮 Layer = **Execute / Implementation Layer**,起 D134 §3 §Phase 5 多文件落盘。

**Why 起 Phase 5**:D134 §Stable Facts 锚 Phase 5 lib/com/mysql/jdbc.ss ✗(不存在);Phase 6 docker e2e + integration_test 必调 `DriverManager_getConnection("jdbc:mysql://...")` 拿 `Connection`,无 Phase 5 → Phase 6 阻塞;`lib/spring/{jdbc,data}.ss` 当前 placeholder body(D133 phase1 锁,exit(1)/println JDBC: no driver registered)— 无 Phase 5 → spring 接入永久空契约 → axiom 兑现停 75%(Phase 0/1/1.5/2/3/4 ✓ + driver 拼装 / spring 接入 ✗)。**axiom 紧约束**:CLAUDE.md §项目本质 L7 + D134 §Principles 1,4 — 纯 SS 不 link libssl / 任何 C crypto / mysqlclient。

**Phase 5 范围**(承 D134 §3 §Phase 5 line 223-238):

1. **`lib/com/mysql/jdbc.ss`**(新建,~250-400 LOC):
   - `class MysqlConnection : Connection`:fd / autoCommit / closed 实现 D025 Connection 6 method:
     - `createStatement(): Statement` — 返 `new MysqlStatement(this.fd)`
     - `setAutoCommit(auto: int)` — `sendQuery(this.fd, "SET autocommit=" + (auto == 1 ? "1" : "0"))` + readQueryResultSet 消费 OK packet
     - `commit()` — sendQuery(fd, "COMMIT") + readQueryResultSet
     - `rollback()` — sendQuery(fd, "ROLLBACK") + readQueryResultSet
     - `close()` — writePacket(fd, 0, fromCharCode(0x01) + "", 1) COM_QUIT(0x01) + tcpClose(fd) + closed = 1
     - `isClosed(): int` — return this.closed
   - `class MysqlStatement : Statement`:fd 实现 D025 Statement 4 method:
     - `executeQuery(sql: string): ResultSet` — sendQuery(fd, sql) + readQueryResultSet(fd) → MysqlResultSet(实现 ResultSet interface)
     - `executeUpdate(sql: string): int` — sendQuery(fd, sql) + readResultSetHeader(fd) → 若 -2 OK 解析 affected rows count 返(OK packet 第二 length-encoded int = affected rows;但 readResultSetHeader 当前仅返 -2 sentinel,需扩 `parseOkPacketAffectedRows(payload): int` helper);若 -1 ERR 返 -1
     - `execute(sql: string): int` — 通用,等同 executeUpdate 路径(简化:返 affected rows / 0 / -1)
     - `close()` — no-op(SS Statement 不拥有 socket fd,Connection 拥有)
   - `function getMysqlConnection(url: string): MysqlConnection` — URL parser:
     - input format: `jdbc:mysql://[user[:pwd]@]host[:port]/[db][?param=val&...]`
     - 解析 host / port(default 3306)/ user(default "root")/ pwd(default "")/ db(default "")
     - 调 `mysqlConnect(host, port, user, pwd, db)` 返 raw `MysqlConnection` — **NAMESPACE COLLISION 风险**:handshake.ss 已有 `class MysqlConnection { fd, autoCommit, closed }`(Phase 3 simple struct,**未** implement Connection interface),Phase 5 jdbc.ss 必须新建一个**同名** `class MysqlConnection : Connection` 实现 D025 interface — SS 是否允许同名 class?如不允许,**根因决策**:① 重命名 handshake.ss `class MysqlConnection` → `RawMysqlConnection`(handshake.ss 改 1 处 class def + parseHandshakeV10 / mysqlConnect 返 RawMysqlConnection 改名 → handshake_test.ss 同步改 1 处 ctor 测) ② handshake.ss 直接用 `int` 返(mysqlConnect 返 fd:int,失败 -1)— jdbc.ss class MysqlConnection 自己持 fd 不依赖 handshake struct;**优先选 ② Root Cause**(handshake.ss 拆掉 class struct 责任,driver 层接口由 jdbc.ss 单独承载) 
2. **`lib/java/sql.ss`** 改:
   - `import { getMysqlConnection } from "@/lib/com/mysql/jdbc"` — 单向依赖,jdbc.ss 也 import { Connection, Statement, ResultSet } from "@/lib/java/sql" 接口定义 ← **是否循环 import?**SS resolveImports 是 inline 展开,需要查实际 import 顺序。D134 §A.5 line 480 acknowledge 这是 OK 的(sql.ss imports getMysqlConnection,jdbc.ss imports interface),如果实测 SS resolver 报循环 → ultrathink 决策:把 ResultSet/Statement/Connection interface 抽到 sql.ss 之前的 minimal interface file(scope 扩大,慎)/或 jdbc.ss 不 import sql.ss 而 inline 重复 interface 声明(SS 是否要求 implements 时本地 interface 可见?需查 tests/phase5/interface_basic.ss 范式)
   - `DriverManager_getConnection(url): Connection` body 替换:`if (startsWith(url, "jdbc:mysql://")) { return getMysqlConnection(url) }`(SS startsWith 是否内置?需查 — lib/spring/boot/application.ss 等是否用过)
3. **`lib/spring/jdbc.ss`** 改:`JdbcTemplate.execute / queryForList / queryForString / queryForInt / queryForBoolean` 5 method body + `withTransaction` body 替换 placeholder → 真实 driver 调用:`DriverManager_getConnection(url)` + `conn.createStatement().executeXXX(sql)` + `ResultSet.getXXX()` + `conn.close()`
4. **`lib/spring/data.ss`** 改:`JpaRepositoryFactory_create` body 替换为真实 `new JdbcTemplate(...) + new JpaRepository(...)` 拼装

**调研步骤**(写代码前 ultrathink):

1. Read lib/java/sql.ss:15-54(D025 ResultSet/Statement/Connection 全签名 + DriverManager_getConnection 当前 body)
2. Read lib/com/mysql/handshake.ss:40-44 + 215-258(class MysqlConnection 当前结构 + mysqlConnect 完整 flow)
3. Read lib/com/mysql/query.ss(本轮 Phase 4 落盘:sendQuery / readResultSetHeader / readQueryResultSet / class MysqlResultSet : ResultSet)
4. Read lib/spring/jdbc.ss(JdbcTemplate / withTransaction 当前 placeholder body)
5. Read lib/spring/data.ss(JpaRepositoryFactory_create 当前 placeholder body)
6. Read tests/phase5/interface_basic.ss + interface_multi.ss(SS interface 实现 + 跨文件 import 范式)
7. ultrathink **NAMESPACE COLLISION**:handshake.ss class MysqlConnection 与 Phase 5 jdbc.ss class MysqlConnection : Connection 同名冲突 — 三候选(① handshake.ss → RawMysqlConnection rename / ② handshake.ss 拆 class 改 mysqlConnect 返 fd:int / ③ jdbc.ss 用 MysqlJdbcConnection 别名)— 按**根因解决度**排序而非 LOC 最小,优先 ② 单一职责(handshake 层不持 connection state,driver 层 jdbc.ss 独立承载)
8. ultrathink **CIRCULAR IMPORT**:lib/java/sql.ss import jdbc.ss + jdbc.ss import sql.ss interface 是否 SS resolveImports 报循环 — 需 RED 实测,若循环则:① 引 lib/jdbc/driver_registry.ss 中间层(scope 扩) / ② sql.ss 不 import jdbc.ss 而硬编码 url scheme dispatch 用 import-once 全局函数 / ③ jdbc.ss 内联 interface(SS 是否允许同 interface 多文件声明 — 需查 D025 实现)
9. ultrathink **OK packet affected rows 解析**:executeUpdate 必需,readResultSetHeader 当前仅返 -2 sentinel,需扩 `parseOkPacketAffectedRows(payload): int` helper(MySQL OK packet layout: header 0x00 + length-encoded affected rows + length-encoded last_insert_id + 2-byte status + 2-byte warnings + ...);scope:加到 query.ss 作为 OK packet 解析配套(对偶 ERR packet 当前未解析 error code/SQLSTATE)
10. ultrathink **COM_QUIT close 路径**:writePacket(fd, 0, fromCharCode(0x01), 1) — 0x01 是 nonzero 单 byte payload,string concat 安全,直调 wire.writePacket;后调 tcpClose(fd) — 注意 D134 §A.4 没 explicit close packet seq 重置规则,COM_QUIT 是单包请求服务器关闭无响应
11. ultrathink **JdbcTemplate.queryForList → Array<Map<string,string>>**:每行用 Map<string,string>(列名 → 列值字符串),整体 Array<Map>;**queryForString / queryForInt / queryForBoolean** 假设 1 行 1 列结果,直接 ResultSet.next() 第一行 getString/getInt/getBoolean(注意:SS Map<string,string> 默认值如何?lib/spring/boot/application.ss line 153 用 Map<string,int> seen set 范式)
12. RED 命令实测:`ls lib/com/mysql/jdbc.ss = No such` ✓ + `grep "no driver registered" lib/java/sql.ss = 1 命中`(替换前)/ `grep "import.*jdbc" lib/java/sql.ss = 0 命中`
13. Write lib/com/mysql/jdbc.ss + 改 lib/java/sql.ss + lib/spring/jdbc.ss + lib/spring/data.ss + (可能)lib/com/mysql/handshake.ss(若选根因方案 ②)+ tests/d134_mysql/handshake_test.ss(同步改 ctor 测)
14. Read lib/spring/jdbc.ss / data.ss 当前 placeholder body 之前 — 不 deviate spec(D134 §3 line 236-237)
15. `bin/ss test tests/` 全绿 + Phase 5 触 spring/ 测试可能需 mock url(因 docker 未启) — 若 lib/spring/jdbc.ss body 替换后 spring/ 测试需真 MySQL,sub-D follow-up 决定 mock 还是 .skip
16. `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical(Phase 5 lib only 零 bootstrap 冲击;若选根因方案 ② 触 handshake.ss class 拆,bootstrap 仍零冲击因 lib/ 不入 bootstrap)
17. /simplify 复核 4 agent → 1-3 commit 隔离(Phase 5 大改可能拆:handshake namespace fix → jdbc.ss + sql.ss → spring 接入,各 commit 独立验证)→ 写下轮 next_prompt(Phase 6 docker e2e + RED → 0 + axiom 红线最终验证)+ ultrathink linter pass → stop

**RED**(Phase 5 起立前实测):
```bash
ls lib/com/mysql/jdbc.ss 2>&1 | grep -c "No such"   # 期望 = 1(Phase 5 起立前)
grep "no driver registered" lib/java/sql.ss          # 期望 = 1 命中(替换前)
grep "import.*jdbc" lib/java/sql.ss                  # 期望 = 0 命中(替换前)
```

**GREEN**(Phase 5 收敛):
- lib/com/mysql/jdbc.ss 存在 + 含 `class MysqlConnection : Connection` + `class MysqlStatement : Statement` + `function getMysqlConnection`
- lib/java/sql.ss `DriverManager_getConnection` body 替换为 url dispatch(`startsWith(url, "jdbc:mysql://")` → `getMysqlConnection(url)`)+ no driver registered 兜底(其他 url scheme)
- lib/spring/jdbc.ss + data.ss placeholder body 全替换(grep "no driver registered\|exit(1)" lib/spring/{jdbc,data}.ss 应 = 0 命中)
- `bin/ss test tests/d134_mysql/` Phase 4 三 file(wire / handshake / query)不降级
- `bin/ss test tests/` Phase 5 触 spring/ 测试若需真 MySQL,可能 4 latent fail → 5+;**Phase 5 GREEN 判据**:`bin/ss test tests/d134_mysql/` + `bin/ss build lib/com/mysql/jdbc.ss / lib/spring/jdbc.ss / lib/spring/data.ss` 编译过(类型契约对得上)+ 无新 bootstrap 冲击
- `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical

**MNK §M PSM 九问填表**(下轮第一次工具调用之前必须落):
- 字段 1 总体:服务 D134 §3 Phase 5 Execute 实施 — 实测 §Status `Execute(Phase 0/1/1.5/2/3/4 收关)` ✓ + Phase 5 §3 Execution Orchestration §Phase 5 起立锚 D134 §3 §Phase 5 line 223-238 + §A.5 driver 注册机制 = 硬编码 dispatch
- 字段 2 第一性需求:无 lib/com/mysql/jdbc → DriverManager_getConnection 永久 placeholder → spring/jdbc.ss spring/data.ss 永久空契约 → axiom 兑现停 75%(Phase 0/1/1.5/2/3/4 ✓ + driver 拼装 / spring 接入 ✗)
- 字段 3 核心目标:`ls lib/com/mysql/jdbc.ss = exists` + `grep "no driver registered" lib/java/sql.ss = 0`(替换后) + `grep "no driver registered\|exit(1)" lib/spring/{jdbc,data}.ss = 0` + `bin/ss build lib/com/mysql/jdbc.ss` 编译过 + bootstrap 固定点
- 字段 4 规则:CLAUDE.md §项目本质 L7(纯 SS) + D134 §Principles 1,4(axiom 红线)+ §Principles 5(mysql_native_password 锁,Phase 5 不触 caching_sha2)+ §Principles 7(Phase 边界 = commit 边界)+ docs/3-MNK.md §M PSM 九问 + §大改档位
- 字段 5 界定:**做** — lib/com/mysql/jdbc.ss(新)+ class MysqlConnection : Connection + class MysqlStatement : Statement + getMysqlConnection url parser + lib/java/sql.ss DriverManager dispatch 替换 + lib/spring/{jdbc,data}.ss placeholder body 替换;**不做** — Phase 6 docker / integration_test(Phase 6 拼装)+ Prepared Statement / TLS / Pool / utf8mb4 切换(本 D 范围外明确禁)+ caching_sha2_password full auth(Phase 3 锁定 mysql_native_password,sub-D follow-up)+ readResultSetHeader / readColumnDef / parseRow API 改动(Phase 4 锁定)
- 字段 6 步骤:见上调研步骤 1-17
- 字段 7 对照实验:不做 → spring/jdbc.ss spring/data.ss 永久 placeholder → axiom 兑现 75% 永卡
- 字段 8 Plan vs Execute + Layer:**Execute / Implementation Layer**(D134 §Phase 5);本轮 Layer 引用上层 D134 §3 = 同 Layer 不跨层
- 字段 9 表面 vs 根:**根**(三轨证):① jdbc.ss 物理空缺 → 补齐结构性根因;② class MysqlConnection : Connection 走 D025 interface 实现是 axiom 兑现的"实物到底"路径(对偶 D133 §核心目标"axiom 不是文字,是 grep 输出");③ NAMESPACE COLLISION 选**根因方案 ②**(handshake.ss 拆 class 改 mysqlConnect 返 fd:int)而非 LOC 最小方案 ①(重命名)or workaround ③(别名)
- 字段 10 bug 修复:不适用(新功能起立)

**档位**:**大改**(LOC ~600-900:jdbc.ss ~300 + sql.ss 改 ~10 + spring/jdbc.ss 改 ~150 + spring/data.ss 改 ~80 + handshake.ss 重构 ~30 + handshake_test.ss 同步 ~10;新建 1 文件 + 改 5 文件,Phase 5 lib only 零 bootstrap 触)

**不变量保留**:D018(对象布局)/ D022(clone)/ D025(interface dispatch — Phase 5 兑现 MysqlConnection : Connection + MysqlStatement : Statement + Phase 4 已兑现 MysqlResultSet : ResultSet)/ D068(private)/ D088 / D123 / D130-133 全不动;mimalloc C link axiom 例外保留;Phase 1/1.5 socket client 原语 + Phase 2 lib/binary + lib/com/mysql/wire + Phase 3 mysql_native_password scramble + Phase 4 query.ss 全保留;jdbc.ss 单向依赖 lib/java/sql + lib/com/mysql/handshake + lib/com/mysql/query,无循环(待 RED 实测 sql.ss ↔ jdbc.ss 循环风险)

**git stale state 处理**(承 D133/D134 范式):仅 stage 本轮真实改动:`git add lib/com/mysql/jdbc.ss lib/java/sql.ss lib/spring/jdbc.ss lib/spring/data.ss .claude/next_prompt.md docs/3-decisions/D134-jdbc-mysql-wire-protocol.md`(若选根因方案 ② 加 lib/com/mysql/handshake.ss + tests/d134_mysql/handshake_test.ss;若 Phase 5 触 bootstrap 则 bin/ss 也加 — 实际 Phase 5 lib only 零 bootstrap 触)。其他 stale 不动(违反 §交互式单文档)。

**收尾**:Phase 5 GREEN(jdbc.ss + sql.ss + spring/jdbc.ss + spring/data.ss + grep 全部 placeholder = 0 + bootstrap 固定点零冲击) → /simplify → 1-3 commit 隔离(Phase 5 大改可拆:① handshake namespace fix(若根因方案 ②) → ② jdbc.ss + sql.ss dispatch → ③ spring 接入,各 commit 独立验证) → 写下轮 next_prompt(Phase 6 docker e2e + tests/d134_mysql/docker-compose.yml + integration_test.ss + RED → 0 验证 axiom 红线 grep 0 命中)→ stop

**Layer**:Execute / Implementation Layer。本轮在 D134 §3 §Phase 5 范围内不跨层。

下轮 Execute / Implementation 流程,**ultrathink** 模式下深度调研 lib/java/sql.ss D025 Connection/Statement 全签名 + lib/com/mysql/handshake.ss class MysqlConnection 当前结构 + lib/com/mysql/query.ss readResultSetHeader API + lib/spring/{jdbc,data}.ss placeholder body 决策:① NAMESPACE COLLISION 三候选(根因方案 ② handshake.ss 拆 class 改 mysqlConnect 返 fd:int 优先) + ② CIRCULAR IMPORT sql.ss ↔ jdbc.ss 实测验证 + ③ OK packet affected rows 解析 helper 加 query.ss 还是 jdbc.ss + ④ JdbcTemplate.queryForList → Array<Map<string,string>> 范式 + 写 5 文件 + bin/ss test tests/d134_mysql/ + spring/ 不降级 + bootstrap 固定点 + commit。
