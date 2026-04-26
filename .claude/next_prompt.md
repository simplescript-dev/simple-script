ultrathink D134 全 Phase 收关 — 等用户对话指定下一任务

承上轮 commit:`e509be1` Phase 6 tests/d134_mysql/{docker-compose.yml + integration_test.ss} + lib/com/mysql/wire.ss readPacket 0x00 strlen-equality bug 根因修 — D134 §3 §Phase 6 终轮闭环全绿:8 个 e2e 测试覆盖 connect/CRUD/transaction/JdbcTemplate/JpaRepository / RED 三轨闭环 GREEN(driver 替换 grep / axiom 红线 grep + nm / 集成测试 e2e)/ bootstrap 三阶段固定点 stage2 == stage3 byte-identical / D134 §Status 全 Phase 收关 / §Stable Facts axiom 兑现度 100% / §附录 B Phase 6 [✓] Done at commit `e509be1` 全回填(关键调研 7 段 + 实施结果 8 段)+ /simplify 3 agent 全 PASS(0 MUST-FIX / 0 MEDIUM / 0 LOW)。

**D134 状态**:✓ 全 Phase 收关(Phase 0/1/1.5/2/3/4/5/6 全绿;axiom 兑现度 100%)
- Phase 0 调研锚定 → Phase 1 socket client 原语(tcpConnect / tcpReadBytes)→ Phase 1.5 lib/crypto sha1flex 复用 → Phase 2 lib/binary + lib/com/mysql/wire → Phase 3 lib/com/mysql/handshake(mysql_native_password scramble + parseHandshakeV10 + sendHandshakeResponse41 + mysqlConnect)→ Phase 4 lib/com/mysql/query(sendQuery + readResultSetHeader + class MysqlResultSet : ResultSet 7 method 实现)→ Phase 5 lib/com/mysql/jdbc(class MysqlConnection : Connection 6 method + class MysqlStatement : Statement 4 method + getMysqlConnection url dispatch)+ lib/spring/{jdbc,data}.ss placeholder 替换 → Phase 6 docker e2e + 三轨 RED 闭环最终验证

**axiom 兑现**:CLAUDE.md §项目本质 L7 "应用层 stdlib 用纯 SS 模块实现,不引入应用层 C 库" — JDBC MySQL driver 纯 SS 实现,axiom 红线 grep / nm = 0(永久维持)。"axiom 不是文字,是 grep 输出" 口号兑现(承 D133 §核心目标范式)。

**测试基线**:
- `bin/ss test tests/d134_mysql/` 4 file pass / 0 fail / 29 sub-test 全绿(Phase 2 wire 17 + Phase 3 handshake 7 + Phase 4 query 16 + Phase 5 query +5 + Phase 6 integration 8 = 53 累积 sub-test 全绿)
- `bin/ss test tests/` 256 pass / 4 fail / 260 total(D133 §附录 B Phase 6 latent 4 fail 不降级,与本 D 零关联;Phase 6 +1 file pass = integration_test.ss 通过)
- `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical(Phase 6 lib/com/mysql/wire.ss readPacket 修 + 新 tests/ 文件,bootstrap 沿用 wire.ss 但 readPacket bug 修不影响 compiler self-bootstrap 任何路径)

**§6 follow-up 候选**(由用户决定起立顺序,§交互式单文档 锚不自主挑):

| # | 候选 | 范围 | 价值 | 复杂度 |
|---|---|---|---|---|
| ① | `caching_sha2_password` fast-path sub-D | MySQL 8 默认 plugin,SHA-256 fast-path(RSA-OAEP full auth 范围外) | 现代 MySQL 默认配置直接连不需 docker mysql_native_password 切换 | 中(新 plugin 路径 + 测试) |
| ② | Connection pool sub-D D125+(HikariCP) | spring/jdbc.ss per-call lifecycle → 连接池 + 复用;JdbcTemplate streaming queryForList Connection leak 兜底 | 性能 + 资源管理 | 高(pool 状态机 + 并发) |
| ③ | Prepared Statement(`COM_STMT_*`)sub-D | parameterized query + SQL injection 防御 + binary protocol | 安全(D134 §3 line 343 spec 接受当前简化 string 拼接,prepared statement 是安全升级) | 中-高(binary protocol + null bitmap) |
| ④ | TLS / SSL `CLIENT_SSL` sub-D | 加密 connection(scope 外,sub-D 接续) | 生产环境必需 | 高(TLS handshake + 证书) |
| ⑤ | 多 driver 扩展(SQLite-pure-SS / PostgreSQL)D135+ | lib/com/sqlite/jdbc.ss / lib/com/postgresql/jdbc.ss | 验 D134 §A.5 hardcoded scheme dispatch 扩展性 | 中-高(各 driver 协议) |
| ⑥ | 全新 D 文档方向 | 其他 axiom 兑现路径 / 编译器优化 / 语言特性等 | 用户主导 | — |
| ⑦ | docs/4-issues/ 整理 | §6 follow-up 候选写入 docs/4-issues/I0NN.md sub-issue 挂载点(承 memory project_no_issues_dir.md "D 文档子问题挂载点") | 跟进路径机械化 | 低 |

**Layer**:Plan / Discovery Layer(等用户对话指定方向后跳到 Execute / Implementation Layer)

**下轮 Claude 行动**:本 prompt 由 terman claude-next preset 30s 窗口注入后,Claude 读取本文件 → 看到"D134 全 Phase 收关 + 等用户指定下一任务"→ Claude **只输出 D134 全 Phase 收关报告摘要(3-5 行)+ 列 §6 follow-up 候选 ①-⑦ + 让用户对话指定具体任务方向**,**不自主挑下一 sub-D / 不批量推进 / 不批量扫 docs/3-decisions/ 找未完成决策**(CLAUDE.md §交互式单文档 锚)。Claude 不主动开始 Execute,等用户对话明确指定方向后再起立(可能是 Plan 也可能是 Execute,取决于用户指令的层级)。

**可选 cleanup 提示(由用户决定)**:
- `docker compose -f tests/d134_mysql/docker-compose.yml down -v` 拆 testss-mysql 容器(本轮 Phase 6 调试 + 测试 leftover,本机 testss-mysql:8.0 + d134_mysql_default network 占用 ~ 100MB 内存 + 3307 端口);若用户下轮跑 sub-D ① caching_sha2 / sub-D ③ prepared statement 集成测试可保留容器复用。

**ultrathink 关键字嵌入**:本 next_prompt 含 "ultrathink" 关键字(本行)以满足 `bin/ss run tools/next_prompt_ultrathink_linter.ss` C3 判据;C1(文件存在)+ C2(非空)+ C3(含 ultrathink)三轨 GATE OK。
