ultrathink D134 Phase 6 起立 — tests/d134_mysql/docker-compose.yml + integration_test.ss + RED 三轨闭环(driver 替换 grep / axiom 红线 grep + nm / 集成测试)+ axiom 红线最终验证 + D134 §Status 全 Phase 收关

承本轮 commit GREEN:`4529596` Phase 5 lib/com/mysql/jdbc.ss + class MysqlConnection : Connection + class MysqlStatement : Statement + getMysqlConnection url dispatch + lib/spring/{jdbc,data}.ss placeholder body 替换 — D025 interface 兑现(7+6+4 method 三 class 全实现) + D134 §A.5 hardcoded scheme dispatch + NAMESPACE COLLISION 根因方案 ②(handshake.ss 拆 class 改 mysqlConnect 返 fd:int 单一职责 SoC)+ CIRCULAR IMPORT 实测 visited set 处理(bootstrap/main.ss resolveInner:186-187)+ JDBC URL 双 scheme strip `jdbc:` 前缀 + URL_parse 复用 lib/url.ss SSoT(simplify reuse F1)+ /simplify 4 项应用(MUST-FIX 2:URL_parse + autoCommit short-circuit;MEDIUM 2:errMsg 4→1 出口 + port p > 0 防御)+ tests 255 pass / 4 fail / 259 total = D133 latent baseline 不降级 + bootstrap 三阶段固定点 stage2 == stage3 byte-identical + D134 §Status Phase 0/1/1.5/2/3/4/5 收关 / §Stable Facts axiom 兑现度 50% → 75% / lib/com/mysql/jdbc 状态行新加 / §附录 B Phase 5 [✓] Done at commit `4529596` 全回填(关键调研 6 段 + 实施结果 12 段)。本轮 Layer = **Execute / Implementation Layer**,起 D134 §3 §Phase 6 终轮闭环(全测试 + RED → 0 + axiom 红线最终验证)。

**Why 起 Phase 6**:D134 §Status 锚 Phase 6 = 终轮(三轨 GREEN + axiom 红线最终验证 + bootstrap 固定点最终确认)。当前 axiom 兑现度 75% 卡在"driver 拼装 + spring 接入 ✓ + docker e2e + RED 收敛 + axiom 红线最终验证 ✗" — 缺 ① 集成测试覆盖 mysqlConnect 真 socket flow / sendQuery 真 packet write / readQueryResultSet 真 server-side EOF / executeUpdate 真 OK packet affected rows;② RED 三轨 grep + nm 红线最终验证;③ D 文档 §Status 改"✓ 全 Phase 收关"。**axiom 紧约束**:CLAUDE.md §项目本质 L7 + D134 §Principles 1,4(永久红线 0 命中维持)+ §Principles 8(Phase 1 后 bootstrap 不再触,Phase 6 commit 时再次确认零冲击)。

**Phase 6 范围**(承 D134 §3 §Phase 6 line 241-249):

1. **`tests/d134_mysql/docker-compose.yml`**(新建,~20 LOC,可选):
   - `version: '3.8'` + service `mysql` image `mysql:8` + `MYSQL_ROOT_PASSWORD=test` + `MYSQL_DATABASE=testdb` + `default_authentication_plugin=mysql_native_password` 全局配置(因 Phase 3 锁定 mysql_native_password,docker mysql:8 默认 caching_sha2 必须切回)+ ports `3306:3306`
   - 依赖外部:host 上需 `docker` + `docker-compose` 可用,WSL2 环境通常 docker daemon 通过 Windows Docker Desktop 暴露。**RED 实测先**:`docker --version 2>&1 | head -1` 命中 → 轨 1;否则 → 轨 2 mock packets

2. **`tests/d134_mysql/integration_test.ss`**(新建,~250-400 LOC,**双轨**):
   
   **轨 1**(docker 可用):完整 e2e CRUD:
   - `function testConnectAndPing()`:`DriverManager_getConnection("jdbc:mysql://root:test@127.0.0.1:3306/testdb")` + `conn.isClosed() == 0` + `conn.close()` + 后 `conn.isClosed() == 1`
   - `function testCreateTable()`:`stmt.execute("CREATE TABLE IF NOT EXISTS users (id INT PRIMARY KEY, name VARCHAR(100), age INT)")` 期 affected rows >= 0(DDL OK packet)
   - `function testInsert()`:`stmt.executeUpdate("INSERT INTO users VALUES (1, 'Alice', 30)")` 期返 1(affected rows)
   - `function testSelect()`:`stmt.executeQuery("SELECT id, name, age FROM users WHERE id = 1")` → `rs.next() == 1` + `rs.getInt("id") == 1` + `rs.getString("name") == "Alice"` + `rs.getInt("age") == 30` + `rs.close()`
   - `function testUpdate()`:`stmt.executeUpdate("UPDATE users SET age = 31 WHERE id = 1")` 期返 1
   - `function testDelete()`:`stmt.executeUpdate("DELETE FROM users WHERE id = 1")` 期返 1
   - `function testTransaction()`:`withTransaction("jdbc:mysql://...", () => { ... return 0 })` + 验证 commit / rollback 路径(insert 后 r=1 触发 rollback,二次查询应找不到)
   - `function testJdbcTemplate()`:`new JdbcTemplate("jdbc:mysql://...")` + `.execute("DELETE FROM users")` + `.update("INSERT ...")` + `.queryForString("SELECT name FROM users WHERE id = 1", "name") == "Alice"` + `.queryForInt("SELECT age FROM users WHERE id = 1", "age") == 30`
   - `function testJpaRepository()`:`JpaRepositoryFactory_create("jdbc:mysql://...", "users", "id,name,age")` + `.save("id,name,age", "2,'Bob',25")` + `.findById(2)` + `.deleteById(2)` + `.count()` + `.deleteAll()`
   
   **轨 2**(docker 不可用,mock packets):
   - 用 `bash -c "printf '\\xHH...'" + readFile + parseHandshakeV10/parseRow/parseOkPacketAffectedRows/isEofPacket` 各 helper 单元路径再覆盖一次,补足 Phase 4 测试已覆盖外的边界(eg `readUpdateResult` 短读路径 / EOF marker for SELECT 0 行 / multi-row SELECT)
   - **scope**:轨 2 不是 e2e,只是补单元测试,Phase 6 标"e2e 待 docker"(D134 §6 line 355 spec 接受 — "降级 unit test mock packets")

3. **RED 三轨闭环最终验证**(Phase 6 GREEN 收敛):
   - 轨 ① driver 替换 grep:`grep -rn "no driver registered" lib/spring/{jdbc,data}.ss | wc -l` = 0(spring/jdbc spring/data placeholder 全替换 — 已达成 ✓);`grep -rn "no driver registered" lib/java/sql.ss | wc -l` = 1(sql.ss line 60 fallback 兜底 — 这是 D134 §A.5 line 495 spec 留的"其他 url scheme 报错"路径,**不归为 placeholder**,不应消)
   - 轨 ② axiom 红线永久 grep:`grep -rn "libmysqlclient\|libmariadb\|ss_mysql_c_\|@mysql_real_\|@mariadb_" bootstrap/ lib/ build.sh | wc -l` = 0(已 ✓)
   - 轨 ③ axiom 红线 nm:`nm bin/ss | grep -c -E "mysql_real|mariadb_"` = 0(已 ✓)
   - 轨 ④ 集成测试 e2e(轨 1 / 轨 2 二选一):
     - 轨 1:`bin/ss test tests/d134_mysql/integration_test.ss` 全绿
     - 轨 2:`bin/ss test tests/d134_mysql/` 全 4 file pass(wire/handshake/query/integration_unit)

4. **D134 §Status 改 "✓ 全 Phase 收关"**:axiom 兑现度 75% → 100%(driver 拼装 + spring 接入 + docker e2e + RED 收敛 + axiom 红线最终验证全 ✓)

5. **bootstrap 三阶段固定点最终确认**:`./build.sh bootstrap` stage2 == stage3 byte-identical(Phase 6 lib only / tests only,零 bootstrap 冲击)

**调研步骤**(写代码前 ultrathink):

1. RED 实测 docker 可用性:`docker --version 2>&1 | head -1` + `docker-compose --version 2>&1 | head -1`(WSL2 通常通过 Windows Docker Desktop 暴露 — 探测一下)
2. Read tests/phase5/spring_data_jpa.ss 之类已有 spring 测试,看 JdbcTemplate / JpaRepository 测试范式
3. Read tests/d134_mysql/{wire_test.ss, handshake_test.ss, query_test.ss} 看 bash-printf fixture + readFile + parse* helper 测试范式
4. ultrathink **轨 1 vs 轨 2 决策**:docker 可用 → 轨 1 完整 e2e CRUD(全栈验证 mysqlConnect handshake + COM_QUERY + ResultSet + transaction + JdbcTemplate + JpaRepository);docker 不可用 → 轨 2 单元 mock packets(只补 Phase 4 没覆盖的边界)— 优先轨 1,docker 可用是关键探测
5. ultrathink **MySQL 8 docker mysql_native_password 切换**:MySQL 8 default `caching_sha2_password`,Phase 3 锁定 mysql_native_password,docker-compose.yml 必须 `command: --default-authentication-plugin=mysql_native_password` 全局切回
6. ultrathink **integration_test.ss 测试隔离**:每个 test 独立 conn / DROP TABLE 后重建 / 不依赖前一个 test 副作用 — `setUp` / `tearDown` 范式
7. ultrathink **withTransaction fn 类型 closure 限制**:SS fn 类型无显式签名(line `function withTransaction(db: string, fn: fn): int`),integration_test 调用 withTransaction 时 fn 闭包可见性 — 看 lib/reactive.ss:14 `fn()` 范式
8. ultrathink **JpaRepository.save 字符串模板 SQL 注入风险**:轨 1 测试用 `repo.save("id,name,age", "2,'Bob',25")` — 这是 D134 §Phase 5 spec 接受的简化(prepared statement sub-D),不是 Phase 6 阻塞
9. ultrathink **测试启动 docker 容器路径**:integration_test.ss 第一个 test 触发前需保证 mysql 容器 running + accepting connections — 候选 ① test fixture `system("docker-compose up -d mysql && sleep 5")` 入 main() 头 / ② 假设 docker 已 running by user(`docker-compose up -d` 手动) / ③ test 启动循环 ping 直到 ready;**优先 ① fixture in-process** + 收尾 `tearDown` `system("docker-compose down")`
10. ultrathink **Phase 6 测试 latent fail 影响**:integration_test.ss 是新 test file,通过 = +1 pass(255 → 256);失败 = +1 fail(255 → 254 + 5 = 259/259 latent + integration);D134 §3 line 309 spec "Phase 6 加 tests/d134_mysql/ 后全绿"
11. RED 命令实测:`ls tests/d134_mysql/integration_test.ss = No such` ✓ + `ls tests/d134_mysql/docker-compose.yml = No such` ✓(Phase 6 起立前)
12. Write tests/d134_mysql/docker-compose.yml + tests/d134_mysql/integration_test.ss + 改 docs/3-decisions/D134-jdbc-mysql-wire-protocol.md(§Status / §Stable Facts axiom 兑现度 100% / §附录 B Phase 6 [✓] 全回填)
13. `bin/ss test tests/d134_mysql/` 全绿(若轨 1 docker 可用) + Phase 4/5 不降级 + 整体 bin/ss test tests/ 255+/259 不降级
14. `./build.sh bootstrap` 三阶段固定点最终确认 stage2 == stage3 byte-identical
15. /simplify 复核 3 agent → 1 commit Phase 6(test 起立 + D 文档收关)→ 写下轮 next_prompt(D134 全 Phase 收关后:② sub-D follow-up clean-up / 或下一个 D 文档起立 / 或 next_prompt 写"D134 已收关,等用户指定下一个任务")+ ultrathink linter pass → stop

**RED**(Phase 6 起立前实测):
```bash
ls tests/d134_mysql/integration_test.ss 2>&1 | grep -c "No such"   # 期望 = 1(Phase 6 起立前)
ls tests/d134_mysql/docker-compose.yml 2>&1 | grep -c "No such"     # 期望 = 1
docker --version 2>&1 | head -1                                       # 探测轨 1 vs 轨 2
grep -rn "no driver registered" lib/spring/jdbc.ss lib/spring/data.ss # 期望 = 0(已 ✓)
grep -rn "libmysqlclient\|libmariadb\|ss_mysql_c_\|@mysql_real_\|@mariadb_" bootstrap/ lib/ build.sh | wc -l  # 期望 = 0(永久 ✓)
nm bin/ss | grep -c -E "mysql_real|mariadb_"                          # 期望 = 0(永久 ✓)
```

**GREEN**(Phase 6 收敛):
- tests/d134_mysql/{docker-compose.yml, integration_test.ss} 存在
- `bin/ss test tests/d134_mysql/` 全绿(轨 1 e2e 或轨 2 mock packets)
- `bin/ss test tests/` Phase 5 baseline 不降级或 +1 pass(integration_test.ss 通过)
- 三轨 RED 收敛闭环(driver 替换 grep / axiom 红线 grep + nm / 集成测试 全 ✓)
- D134 §Status 改 "✓ 全 Phase 收关"
- `./build.sh bootstrap` stage2 == stage3 byte-identical 最终确认

**MNK §M PSM 九问填表**(下轮第一次工具调用之前必须落):
- 字段 1 总体:服务 D134 §3 Phase 6 Execute 实施 — 实测 §Status `Execute(Phase 0/1/1.5/2/3/4/5 收关)` ✓ + Phase 6 §3 Execution Orchestration §Phase 6 line 241-249 锚 + §A.6 集成测试形态(双轨 docker e2e + unit mock)
- 字段 2 第一性需求:axiom 兑现度 75% 卡 driver 拼装 + spring 接入 ✓ + docker e2e + RED 三轨 + axiom 红线最终验证 ✗ → Phase 6 100% 兑现
- 字段 3 核心目标:`ls tests/d134_mysql/integration_test.ss = exists` + `bin/ss test tests/d134_mysql/` 全绿 + 三轨 RED 收敛闭环 + bootstrap 固定点 + D134 §Status 全 Phase 收关
- 字段 4 规则:CLAUDE.md §项目本质 L7(纯 SS) + D134 §Principles 1,4(axiom 红线永久维持)+ §Principles 5(mysql_native_password 锁,docker-compose 全局切回)+ §Principles 7(Phase 边界 = commit 边界)+ §Principles 8(Phase 1 后 bootstrap 不再触,Phase 6 commit 时再次确认零冲击)+ docs/3-MNK.md §M PSM 九问 + §大改档位
- 字段 5 界定:**做** — tests/d134_mysql/{docker-compose.yml, integration_test.ss}(新)+ 轨 1 e2e 8 test(connect / DDL / insert / select / update / delete / transaction / spring) 或 轨 2 unit mock packets + RED 三轨闭环验证 + D134 §Status 全 Phase 收关 + bootstrap 固定点最终确认;**不做** — TLS / Pool / Prepared Statement / caching_sha2 full auth / utf8mb4 切换(本 D 范围外明确禁)
- 字段 6 步骤:见上调研步骤 1-15
- 字段 7 对照实验:不做 → axiom 兑现度 75% 永卡(驱动逻辑层有,实物 e2e 验证无)→ axiom 兑现 = 文字不是 grep + test 输出,违反 D134 §核心目标"接口契约不是 axiom,实现到底才是 axiom 兑现"口号
- 字段 8 Plan vs Execute + Layer:**Execute / Implementation Layer**(D134 §Phase 6);本轮 Layer 引用上层 D134 §3 = 同 Layer 不跨层
- 字段 9 表面 vs 根:**根**(三轨证):① integration_test.ss 物理空缺 → 补齐结构性根因;② 三轨 RED 闭环验证是 axiom 兑现的"实物到底"路径(对偶 D133 §核心目标"axiom 不是文字,是 grep 输出");③ docker-compose 全局 default-authentication-plugin=mysql_native_password 切换是 Phase 3 mysql_native_password 锁定的 docker 适配根因(MySQL 8 default caching_sha2 不切回则 handshake 失败)
- 字段 10 bug 修复:不适用(测试起立 + 收关)

**档位**:**大改**(LOC ~300-450:integration_test.ss ~300 + docker-compose.yml ~20 + D134 改动 ~50;新建 2 文件 + 改 1 D 文档,Phase 6 lib only / tests only 零 bootstrap 触)

**不变量保留**:D018 / D022 / D025(Phase 4/5 已兑现 7+6+4 method 三 class)/ D068 / D088 / D123 / D130-133 全不动;mimalloc C link axiom 例外保留;Phase 1/1.5 socket client 原语 + Phase 2 lib/binary + lib/com/mysql/wire + Phase 3 mysql_native_password scramble + Phase 4 query.ss + Phase 5 jdbc.ss 全保留

**git stale state 处理**(承 D133/D134 范式):仅 stage 本轮真实改动:`git add tests/d134_mysql/docker-compose.yml tests/d134_mysql/integration_test.ss docs/3-decisions/D134-jdbc-mysql-wire-protocol.md .claude/next_prompt.md`。其他 stale 不动(违反 §交互式单文档)。

**收尾**:Phase 6 GREEN(integration_test.ss 全绿 + 三轨 RED 闭环 + bootstrap 固定点零冲击 + D134 §Status 全 Phase 收关)→ /simplify → 1 commit Phase 6 收尾 → 写下轮 next_prompt(D134 全 Phase 收关后:② sub-D follow-up 候选 — caching_sha2_password fast-path / connection pool HikariCP / prepared statement / TLS / 或等用户指定下一任务)→ stop

**Layer**:Execute / Implementation Layer。本轮在 D134 §3 §Phase 6 范围内不跨层。

下轮 Execute / Implementation 流程,**ultrathink** 模式下深度调研:① docker 可用性探测(WSL2 docker desktop 路径)+ ② docker-compose mysql:8 + mysql_native_password 全局切换 spec + ③ integration_test.ss 8 test fixture setUp/tearDown + 测试隔离 + ④ withTransaction fn 闭包范式 + ⑤ JpaRepositoryFactory_create + JdbcTemplate 真 driver 验证 + ⑥ 三轨 RED 闭环最终验证 + ⑦ axiom 兑现度 75% → 100% 收关 + 写 2 文件 + 改 D134 + bin/ss test tests/d134_mysql/ + 整体 tests 套不降级 + bootstrap 固定点 + commit。
