# D157: ParameterMetaData PreparedStatement 参数侧 metadata

**Status:** [x] Phase 0 D 文档落档 at commit `<phase0-hash>` — D156 §Followup F1 起首脱胎,D135-D156 SQL 主线范式延续。走**完整 JDBC 4.3 §10.2 `interface ParameterMetaData` ≥7 method**(getParameterCount / getParameterType / getParameterTypeName / getParameterClassName / getParameterMode / isNullable / isSigned)+ **MysqlParameterMetaData class 真实现**(单字段 `paramMetadata: Array<ColumnDef>` + ≥7 method 反射派生 + 复用 D155 mysqlTypeToJdbcType / mysqlTypeName / mysqlTypeToJavaClassName / 13 bit flag 解析路径)+ **`PreparedStatement.getParameterMetaData(): ParameterMetaData` 接口加 + 1 implementor 真返**(MysqlPreparedStatement 真返,paramDefs 字段已 lib/com/mysql/prepared.ss:160 构造点存在,无需新协议解析)— 不接受次优 / workaround / 节省。

## 起首脱胎
- D156 §Followup F1(`docs/3-decisions/D156-database-metadata.md:148`)
- D135-D156 SQL 主线范式延续(Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设挑战)
- Depends on:D154(MySQL driver class 主线 close — Connection / Statement / PreparedStatement / ResultSet 全实现)+ D155(ResultSetMetaData 主线 close + ColumnDef41 完整反射 + JDBC Types mapping + interface 字段 deep_clone vtable 根因修)+ D156(DatabaseMetaData 主线 close + INFORMATION_SCHEMA per-call PS + supportsXxx 静态)— 本 D 续接列 metadata + schema metadata 拓展到参数级 metadata,getParameterType / getParameterTypeName / getParameterClassName 走 D155 mysqlTypeToJdbcType / mysqlTypeName / mysqlTypeToJavaClassName 复用路径

## 核心目标 (Goal)

落地后:
1. `lib/java/sql.ss interface ParameterMetaData` 存在,JDBC 4.3 §10.2 ≥7 method 全声明
2. `lib/java/sql.ss interface PreparedStatement` 加 `getParameterMetaData(): ParameterMetaData` method
3. `lib/com/mysql/prepared.ss class MysqlParameterMetaData : ParameterMetaData` 真实现(单字段 `paramMetadata: Array<ColumnDef>` + ≥7 method 反射派生)
4. JDBC Types SQL type code mapping 复用 D155 `mysqlTypeToJdbcType` / `mysqlTypeName` / `mysqlTypeToJavaClassName`(Phase 3 落地;ColumnDef41 已统一 parseColumnDef → Phase 2 参数侧反射派生 直复用)
5. ParameterMode 静态映射(JDBC §10.2 spec — `parameterModeIn = 1` / `parameterModeInOut = 2` / `parameterModeOut = 4` / `parameterModeUnknown = 0`;MySQL prepare statement 不支持 OUT/INOUT 参数,统一返 `parameterModeIn = 1`)
6. isNullable 静态映射(JDBC §10.2 spec — `parameterNullable = 1` / `parameterNoNulls = 0` / `parameterNullableUnknown = 2`;COM_STMT_PREPARE_OK ParameterDef NOT_NULL_FLAG 0 → `parameterNullable` / 1 → `parameterNoNulls` — 复用 D155 ColumnDef41 NOT_NULL_FLAG 解析,但 MySQL 5.7+/8.0 在 prepare 阶段不解析 SQL placeholder 上下文 → 一律返 `parameterNullableUnknown = 2`,wire 实测 H4)
7. isSigned 反射(D155 ColumnDef41 UNSIGNED_FLAG 反向 — bit 5 `0x0020` 0 → signed 1 / 1 → unsigned 0;复用 D155 isSigned 路径)
8. 1 implementor 真返:`MysqlPreparedStatement.getParameterMetaData()` 真返 `new MysqlParameterMetaData(paramDefs)`(`paramDefs` 字段已 lib/com/mysql/prepared.ss:160 构造点存在 — readParamDef 返 Array<ColumnDef> 在 prepare 时一次性 buffer ParameterDef block,无需新协议解析层落地 — 这是 D157 vs D155/D156 的关键 scope 减项)
9. NoopPreparedStatement / 测试 mock stub 同步加 vtable getParameterMetaData(D025 vtable 强制全 method,新增 PreparedStatement.getParameterMetaData() 后已有 stub 必同步)
10. integration_test.ss e2e ≥7 case docker probe-skip 全形态覆盖(getParameterCount / getParameterType per type / getParameterTypeName / getParameterClassName / getParameterMode 全 IN / isNullable 全 Unknown / isSigned 真值 + UNSIGNED 反射)
11. `./build.sh bootstrap` 三阶段固定点 stage2==stage3 + `bin/ss test tests/` baseline 全继承 + reflection_health_linter 全 14 指标无 regression + d_doc_index_linter F1 = 0 + next_prompt_ultrathink_linter PASS

**RED**(本 D 文档落档前实测):
- `ls docs/3-decisions/D157-parameter-metadata.md` = ENOENT(D157 不存在,起首必新建)
- `grep -c "interface ParameterMetaData" lib/java/sql.ss` 实测 = 0(interface 完全缺)
- `grep -rc "class MysqlParameterMetaData" lib/com/mysql/` 实测 = 0(class 不存在)
- `grep -cE "function getParameterMetaData\(\): ParameterMetaData" lib/java/sql.ss` 实测 = 0(PreparedStatement.getParameterMetaData() 接口缺)
- `grep -c "<phase4-hash>" docs/3-decisions/D156-database-metadata.md` 实测 = 6(D156 Phase 4 hash placeholder 占 6 行,包含 line 3 内 2 处 — Status header Phase 4 entry + 主线 close 锚)

## 核心原则 (Principles)

1. **走完整 JDBC 4.3 §10.2 ParameterMetaData spec ≥7 method**:不简化、不 stub 关键 method、不"够用就行"(用户对话锁不接次优 / workaround / 节省路径)
2. **ParameterDef = ColumnDef41 同结构直接复用**:MySQL Native Protocol §15.7.7 COM_STMT_PREPARE_OK 之 ParameterDef block 与 ColumnDef block 字段完全同构(catalog / schema / table / orgTable / name / orgName / charset / maxColumnLength / colType / flags / decimals)— readParamDef 已用 parseColumnDef 解析(lib/com/mysql/prepared.ss:169-179),paramDefs: Array<ColumnDef> 字段已 lib/com/mysql/prepared.ss:160 构造点存在,无需新协议解析层 — 这是 D157 vs D155/D156 的核心 scope 减项
3. **JDBC Types mapping 复用 D155**:getParameterType 走 mysqlTypeToJdbcType(colType byte → Types.INT/VARCHAR/DECIMAL/BIGINT/...) / getParameterTypeName 走 mysqlTypeName / getParameterClassName 走 mysqlTypeToJavaClassName / isSigned 走 UNSIGNED_FLAG bit 5 反向(D155 §Phase 3 Phase 收关锚已落地)
4. **ParameterMode 静态 IN-only**:MySQL 5.7+/8.0 prepare statement 不支持 OUT / INOUT 参数(stored procedure CALL 走 callable statement 路径,留独立 sub-D §F2)— ParameterMetaData.getParameterMode(int) 一律返 `parameterModeIn = 1`,与 Connector/J `MysqlParameterMetadata.getParameterMode` 范式一致
5. **isNullable 静态 Unknown**:JDBC §10.2 spec — MySQL 5.7+/8.0 在 COM_STMT_PREPARE 阶段**不**解析 SQL placeholder 上下文(? 占位符在 INSERT INTO t (col1, col2) VALUES (?, ?) 中无法在 prepare 时知道 col1/col2 NOT NULL 约束)— 统一返 `parameterNullableUnknown = 2`,与 Connector/J `MysqlParameterMetadata.isNullable` 范式一致(Connector/J `MysqlParameterMetadata.parameterTypes` field 不存 NULL 约束)
6. **D135-D156 SQL 主线范式延续**:Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设 + §A.3 废案 + §Followup
7. **不简化关键 method**(D147 Phase 5 7-shape integration_test 范式 + D154 §F7 12 driver class round-trip + D155 Phase 4 10 case docker probe-skip + D156 Phase 4 10 case docker probe-skip 范式延续)— integration_test e2e 必含 wire 端真值实证
8. **MysqlParameterMetaData 单字段 value snapshot 不持 PreparedStatement ref**:Class 仅持 paramMetadata: Array<ColumnDef>(从 paramDefs 字段拷贝引用 — Array<ColumnDef> retain Array snapshot,不持 MysqlPreparedStatement ref)— PreparedStatement close 后 ParameterMetaData 仍可访问(语义对齐 D155 ResultSetMetaData close 后 H7),且无 D156 §F6 RC cycle(MysqlConnection ↔ MysqlDatabaseMetaData 2-node Perceus cycle)风险 — Connector/J `MysqlParameterMetadata` 范式同款 value snapshot,SS 直接复用
9. **不引入新协议解析层**:lib/com/mysql/prepared.ss:163-179 readParamDef 已实现 num_params × ColumnDef41 packet 解析(parseColumnDef 直接复用,Array<ColumnDef> paramDefs 字段已 lib/com/mysql/prepared.ss:160 构造点存在),D157 vs D155/D156 关键 scope 减项 — D155 加 16 bit flag + JDBC Types mapping helper / D156 加 INFORMATION_SCHEMA per-call PS helper / D157 仅加 interface + class + 1-line getter 真返,无新协议层

## A.1 主候选评估(§MNK §M §字段 10)

| 候选 | 层次 | 含 | 不含 | 决策 |
|------|------|-----|------|------|
| **C1** | 数据层 patch | + 几个核心 method 子集(getParameterCount + getParameterType ≤ 3 method)+ 部分静态返值,无 interface ParameterMetaData / 无完整 7 method | 无 interface ParameterMetaData;无 PreparedStatement.getParameterMetaData() 接口加;Spring `JdbcTemplate.update` 反射参数类型推导 / Hibernate `BasicBinder` 参数类型适配 / MyBatis `TypeHandler` 自动选择 全断链 | **不选** — 用户对话锁不接次优 / workaround;ORM 参数类型推导反射全断链,后续每条 ORM 主线必回头补 |
| **C2** | **接口层 trap** | + 完整 `interface ParameterMetaData` ≥7 method + PreparedStatement.getParameterMetaData() 接口加 + MysqlParameterMetaData class 真实现 + 复用 D155 mysqlTypeToJdbcType / mysqlTypeName / mysqlTypeToJavaClassName + 1 implementor 真返 + integration_test e2e ≥7 case docker probe-skip | CallableStatement OUT/INOUT 参数留 §F2 / 高级 SQL 类型(SQLXML / ARRAY / STRUCT)getParameterClassName 留 §F3 / 多 driver(PG/Oracle)留 §F4 | **选** — 根因解决:JDBC §10.2 spec 100% + Spring `JdbcTemplate.update` 反射参数类型推导 + Hibernate `BasicBinder` 参数类型适配 + MyBatis `TypeHandler` 自动选择 全 idiom 复用 + ORM 反射 idiom 标准 + 业界演化对标(MySQL Connector/J 5.1+ ParameterMetadata.java 演化路径)+ N 年返工度低 + D135-D156 SQL 主线范式延续 |
| **C3** | 架构层 refactor | + ParameterMetaData 完整 + CallableStatement OUT/INOUT 参数 + 高级 SQL 类型(SQLXML / ARRAY / STRUCT / RowId)+ Wrapper.unwrap | spec 100%;ORM Spring + Hibernate + MyBatis + iBatis + JOOQ 全 idiom 完整 + CallableStatement 调存储过程 + Array/Struct 类型 ORM 适配 | **不选** — scope 远超 D157 单 sub-D(LOC > 2000;CallableStatement OUT/INOUT 涉 binary protocol parameter direction byte + RESULT_SET 多 ResultSet round-trip 独立 sub-D + Array/Struct/RowId 高级类型各独立 sub-D) |

**决策行**:**选 C2 接口层 trap**(用户对话锁 — 不接次优 / workaround / 节省)— 因 (a) 完整 JDBC 4.3 §10.2 ParameterMetaData ≥7 method + 复用 D155 ColumnDef41 范式(parseColumnDef 已用,paramDefs 字段已 lib/com/mysql/prepared.ss:160 构造点存在)消除 ORM 参数类型推导反射断链根因;(b) Spring `JdbcTemplate.update` 反射参数类型推导 / Hibernate `BasicBinder` 参数类型适配 / MyBatis `TypeHandler` 自动选择 标准 idiom 直接复用,无手写 ParameterDef 字面 workaround;(c) **底层依赖链最深**:协议层 D135-D147 已稳 → 列级 metadata D155 已稳 → schema 级 metadata D156 已稳 → 参数级 metadata D157 是协议参数侧最直接下游 idiom 缺口;不先 D155 ColumnDef41 直接做 D157 会破依赖链;(d) **业界演化对标**:MySQL Connector/J 5.1+ 演化路径 — 协议层 → ResultSetMetaData(列级)→ DatabaseMetaData(schema 级)→ ParameterMetaData(参数级)。SS 协议层 D135-D147 已稳 + 列级 metadata D155 + schema 级 D156 已稳,下一阶段必属参数级 metadata(同 Connector/J 5.1.x → 8.x 演化路径);(e) **N 年返工度**:不做 → ORM Spring `JdbcTemplate` / Hibernate `BasicBinder` / MyBatis `TypeHandler` / JOOQ `BindContext` 全断链,后续每条 ORM 主线必回头补,返工率极高;(f) D135-D156 SQL 主线范式延续(协议层完整反射 + JDBC 接口扩 + driver 实现 + 测试覆盖 + Phase 计划独立 commit)。**为何不选 C1**:用户对话锁不接次优 / workaround / 节省路径;ORM 参数类型推导反射全断链。**为何不选 C3**:scope 远超 D157 单 sub-D — CallableStatement OUT/INOUT / Array/Struct/RowId 各留 §Followup 独立 sub-D。

## A.2 隐藏假设挑战

| H | 假设 | 挑战 | 实证锚 |
|---|------|------|--------|
| H1 | COM_STMT_PREPARE_OK 含 ParameterDef block 是 server 默认返 | MySQL 5.7+/8.0 server 默认对 num_params > 0 的 PREPARE 返 num_params × ColumnDef41 packet + 1 trailing legacy EOF(MySQL Native Protocol §15.7.7 — server 不要求 client 设置任何 capability flag,默认行为)。lib/com/mysql/prepared.ss:163-179 readParamDef 已实现 — paramDefs 字段在 prepare 时一次性 buffer。ParameterDef 与 ColumnDef41 字段完全同构,parseColumnDef 直接复用 | Phase 1+2 unit 静态 — paramDefs 字段非空在 num_params > 0 prepare 后(stub-driven readParamDef return Array<ColumnDef> non-empty);Phase 3 integration_test docker probe-skip e2e — `INSERT INTO t VALUES (?, ?, ?)` 真 prepare 后 getParameterCount() = 3 + paramDefs[i] 真 colType / charset / flags 实测 PASS |
| H2 | binary vs text protocol ParameterMetaData 差异 | MySQL 5.7+/8.0 ParameterMetaData 仅适用于 PREPARE statement(binary protocol),text protocol Statement(executeQuery / executeUpdate)无 ParameterMetaData 概念(无 ? 占位符) — JDBC §10.2 spec 明确 ParameterMetaData 仅在 PreparedStatement 路径上有意义;Connector/J `Statement` 不实现 getParameterMetaData()(Statement 无 PreparedStatement 接口继承)— D157 接口加在 PreparedStatement 而非 Statement | Phase 1 接口加在 PreparedStatement(D157 lib/java/sql.ss:280 PreparedStatement 接口扩 1 method);Phase 2 MysqlPreparedStatement.getParameterMetaData() 实现单 implementor;不在 MysqlStatement 加,不在 Statement 接口加 — 静态接口边界实证 |
| H3 | 复用 D155 parseColumnDef 同结构风险点 | MySQL Native Protocol §15.7.7 ParameterDef 与 §6.6 ColumnDef41 字段完全同构,但**字段语义部分降级** — ParameterDef 的 catalog / schema / table / orgTable / name / orgName 字段在 server 端**全填空 string ""**(prepare 阶段无 SQL placeholder 上下文;server 不解析 INSERT INTO t (col1) VALUES (?) 的 col1 上下文绑定);只有 colType + flags + charset + decimals + maxColumnLength 在 server 端有 meaningful 值。**风险**:getParameterTypeName 走 colType byte → mysqlTypeName mapping 静态可靠;但若用户期望 getParameterClassName 反映 charset-aware 字符串类型(如 VARBINARY vs VARCHAR),charset 字段在 ParameterDef 中是否真有效?Connector/J `MysqlParameterMetadata.getParameterClassName(int)` 实现:对 colType IS_TEXT (VARCHAR/CHAR/TEXT) 的 charset 检查 → binary charset → "[B"(byte[])/ 否则 → "java.lang.String";D157 复用 D155 mysqlTypeToJavaClassName 已含 charset-aware 路径 | Phase 2 spike — paramDefs[i].colType + charset 反射,mysqlTypeToJavaClassName 走 D155 charset-aware 路径 spike GREEN(VARBINARY → "[B" / VARCHAR → "java.lang.String" 静态实证);Phase 3 docker e2e — `SELECT * FROM t WHERE binary_col = ? AND text_col = ?` 真 prepare 后 getParameterClassName(1) = "[B" + getParameterClassName(2) = "java.lang.String" 实测 PASS |
| H4 | ParameterMetaData 在 PreparedStatement close 后行为(disallowed) | JDBC 4.3 §10.2 spec — ParameterMetaData 持 paramDefs 字段(value-typed Array<ColumnDef> snapshot,不持 PreparedStatement ref),PreparedStatement close 后 ParameterMetaData 仍可访问(语义对齐 D155 ResultSetMetaData close 后行为 H7)。**风险**:MysqlParameterMetaData 单字段 paramMetadata: Array<ColumnDef> 是 prepare 时 readParamDef 返的 snapshot,deep_clone 拷贝路径继承 D155 §F5 codegen 修(interface 字段 deep_clone vtable);PreparedStatement close 后 paramDefs 字段仍可访问 | Phase 2 spike — MysqlPreparedStatement.close() 后 getParameterMetaData() 返 cached MysqlParameterMetaData(paramMetadata snapshot 不变);Phase 3 docker e2e Case 7 — close 后 getParameterCount + getParameterType per param 仍返真值 PASS |
| H5 | num_params = 0 时 getParameterMetaData() 返非 null 空 ParameterMetaData | MySQL 5.7+/8.0 server 对 num_params = 0 的 PREPARE 不发送任何 ParameterDef packet 也不发送 EOF(readParamDef line 171 直接 return [] short-circuit)— paramDefs 字段为 empty Array<ColumnDef>。**风险**:JDBC §10.2 spec — getParameterMetaData() 必返非 null,getParameterCount() = 0 合规。MysqlParameterMetaData 单字段 paramMetadata: Array<ColumnDef> 接受空 Array — 不 throw NPE | Phase 2 spike — readParamDef returns [] when num_params = 0 + new MysqlParameterMetaData([]) + getParameterCount() = 0 spike GREEN;Phase 3 docker e2e Case 6 — `SELECT 1` 无参数 prepare 后 getParameterCount() = 0 + 不 throw exception PASS |
| H6 | getParameterType idx 越界(idx < 1 或 idx > getParameterCount())throws SQLException | JDBC 4.3 §10.2 spec — getParameterType(int param) param 1-indexed,越界 throws SQLException("parameter index out of range")。SS 当前 D139 SQLException 主线在 §F1 子 D 落地中,D157 对越界一律 fall back SS Array bounds runtime fail(实际不 throw SQL-typed exception 而是 SS Array index out of bounds runtime trap)— 未来 D139 §F SQLException 全链覆盖时再升级。Connector/J `MysqlParameterMetadata.checkBounds(int)` 范式显式抛 SQLException,SS 当前选 SS Array bounds 是 acceptable workaround | Phase 3 integration_test 不强制 boundary throw 行为(D157 §A.2 H6 显式声明,推 D139 §F SQLException 全链覆盖时再做)|
| H7 | ParameterMetaData paramMetadata field 是 paramDefs 浅拷贝 vs 深拷贝 | D155 §F5 codegen interface 字段 deep_clone vtable 已落地 — interface 类型字段在 class deep_clone 时通过 typeInfo.deep_clone_fn vtable 派发到具体类型 deep_clone。本 D MysqlParameterMetaData 单字段 paramMetadata: Array<ColumnDef>(具体类型,非 interface),deep_clone 走 SS 内置 Array deep_clone 路径(逐元素 ColumnDef deep_clone)— 实测开销小因 ColumnDef 是 value-typed 短字段集合,deep_clone 在用户 explicit clone 路径触发,正常 getter 路径不深拷 | Phase 2 spike — paramMetadata 浅拷贝即可(prepare 时 paramDefs Array snapshot 直接传入构造,无修改路径不需深拷);Phase 3 integration_test 不强制 deepClone 路径覆盖(基础 getter 路径足够 — Array 元素读 only)|

## A.3 废案

- **C1 数据层 patch**(用户对话锁不接次优;ORM Spring `JdbcTemplate.update` / Hibernate `BasicBinder` / MyBatis `TypeHandler` / JOOQ `BindContext` 反射全断链)
- **C3 架构层 refactor + CallableStatement OUT/INOUT + Array/Struct/RowId 高级类型**(scope 远超 D157 单 sub-D — 各独立 sub-D 留 §Followup F1-F4)
- **简化 ParameterMetaData ≤3 method 子集**(用户对话锁不接节省;ORM 参数类型推导 idiom 必依赖完整 ≥7 method — getParameterType + getParameterClassName 至少同时存在)
- **Connector/J 5.1.x ParameterMetaDataImpl 兼容模式**(SS 项目无 5.1 vs 8.x 演化压力,直接 8.x ParameterDef 范式 — Connector/J 5.1.x 模式仅为兼容 MySQL 4.x SHOW 命令,5.7+/8.0 prepare protocol 主路径)
- **PostgreSQL pg_describe / Oracle OCI parameter binding 路径**(SQL standard;但 D157 范畴限 MySQL — PG / Oracle driver 暂时不兼容,2026-05-05 用户对话锁,详 memory `project_no_postgres_for_now.md`)
- **MysqlParameterMetaData 持 PreparedStatement ref**(违反 H4 + Connector/J 范式 — class 仅持 paramMetadata: Array<ColumnDef> snapshot,close 后仍可访问,无 RC cycle)— D156 §F6 RC cycle 根因(MysqlConnection ↔ MysqlDatabaseMetaData)在 D157 不复现,因 ParameterMetaData 持 value snapshot 不持 ref
- **CallableStatement OUT / INOUT 参数 mode 反射**(scope 远超 — MySQL prepare statement 不支持 OUT / INOUT;CallableStatement 走 stored procedure CALL 路径独立 sub-D §F2)
- **getPrecision / getScale ParameterMetaData 扩展(JDBC §10.2 完整 9 method)**(本 D 落 ≥7 — getPrecision / getScale 复用 D155 ColumnDef41 maxColumnLength + decimals 字段反射派生路径,可合本 D Phase 2 若实现轻量;否则独立 sub-D)
- **MysqlParameterMetaData lazy cache MysqlPreparedStatement 内**(本 D Phase 2 每次 getParameterMetaData() new MysqlParameterMetaData(paramDefs) 廉价 — paramDefs Array snapshot 共享 ref,无深拷贝;Phase 2 simplify Agent 3 评估若发现 cold-path 多次 getParameterMetaData() 调用造成 RC retain/release 频繁,再升级 lazy cache,否则 ship as-is)
- **MysqlPreparedStatement.paramMetadata 字段从 paramDefs 重命名分离**(本 D Phase 2 直接复用 paramDefs: Array<ColumnDef> 已存字段构造 MysqlParameterMetaData,无需新加 paramMetadata 字段 — 减少 lib/com/mysql/prepared.ss line count 增量 + 减少 vtable / 构造点改动)
- **MysqlPreparedStatement 持 MysqlParameterMetaData 字段 + lazy cache**(违反 D157 §核心原则 8 — class 仅持 paramDefs: Array<ColumnDef> snapshot 不持 MysqlParameterMetaData ref;若 lazy cache 即引入 MysqlPreparedStatement ↔ MysqlParameterMetaData 双向引用 RC retain,getParameterMetaData() 频繁路径优化在 simplify Agent 3 评估再升级,默认 ship as-is)
- **CallableStatement.getParameterMetaData() 独立路径**(scope 远超 — CallableStatement 接口未在 D154 落地,需独立 sub-D 同时落 CallableStatement 接口 + OUT/INOUT 参数 mode 反射 + RESULT_SET 多 ResultSet round-trip — 留 §F2 远期)
- **getParameterMode 走 server-side parameter direction byte 反射**(scope 远超 — MySQL 5.7+/8.0 binary protocol parameter direction byte 仅在 CallableStatement 路径上由 client 传给 server,COM_STMT_PREPARE_OK ParameterDef 无 mode 字段反射;getParameterMode 静态返 parameterModeIn = 1 是 Connector/J 范式,选静态)

## Phase commit hash 总览

| Phase | 内容 | Commit |
|-------|------|--------|
| 0 | D 文档落档(§核心目标 + §核心原则 + §A.1-A.3 + §Phase 收关锚 Phase 0-3 + §Followup F1-F4)+ D156 Phase 4 hash 回填 | `<phase0-hash>` |
| 1 | interface ParameterMetaData ≥7 method + PreparedStatement.getParameterMetaData() 接口加 + 1 implementor stub + class NoopParameterMetaData(无字段 stateless stub)+ ≥10 case spike GREEN | `<phase1-hash>` |
| 2 | MysqlParameterMetaData class 真实现(单字段 paramMetadata + ≥7 method 反射派生 + 复用 D155 mysqlTypeToJdbcType + mysqlTypeName + mysqlTypeToJavaClassName + isSigned UNSIGNED_FLAG)+ MysqlPreparedStatement.getParameterMetaData() 真返 + ≥12 case spike GREEN | `<phase2-hash>` |
| 3 | integration_test e2e ≥7 case docker probe-skip(H1-H5 wire 端全实证)+ absorb spike(删 phase1_spike + phase2_spike,可保留 ≤1 unit test)+ Phase 0-2 hash 回填 + D157 主线 close 锚 | `<phase3-hash>` |

## Phase 收关锚

### Phase 0: D 文档落档 [x] Done at commit `<phase0-hash>`

- 落地 `docs/3-decisions/D157-parameter-metadata.md`(本文件)— §核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H5 + §A.3 废案 + §Phase 收关锚 Phase 0-3 + §Followup F1-F4 + §Status 时间线
- 落地 `.claude/next_prompt.md`(下轮 D157 Phase 1 起首)
- D156 Phase 4 hash `72e5e0c` 回填 D156.md 5 处(Status header line 3 ×2[Phase 4 entry + 主线 close 锚] + §Phase commit hash 总览段表 Phase 4 行 + §Phase 收关锚 §Phase 4 mark Done at commit + §Phase 收关锚 §Phase 4 内 D156 主线 close 锚引用 + §Phase 收关锚 §Phase 4 元描述行 + Status 时间线 Phase 4 entry — 实际语义位 ≥5 处,严格按 D155 §Phase 4 close → D156 §Phase 0 跨 D 起首回填 6 处范式延续)
- bootstrap/ + lib/ + tools/ + tests/ diff = 0
- baseline:d_doc_index_linter F1 = 0(D147/D154/D155/D156 全实存)+ next_prompt_ultrathink_linter PASS(下轮含 ultrathink 关键字)+ 14 reflection 指标全继承 D156 主线 close baseline(本 Phase 不动 bootstrap/)

### Phase 1: interface ParameterMetaData ≥7 method + PreparedStatement.getParameterMetaData() 接口加 + 1 implementor stub + spike GREEN [ ] Pending at commit `<phase1-hash>`

- `lib/java/sql.ss` 加 `interface ParameterMetaData` ≥7 method(JDBC 4.3 §10.2 完整子集 — getParameterCount / getParameterType / getParameterTypeName / getParameterClassName / getParameterMode / isNullable / isSigned;Wrapper.unwrap / isWrapperFor 留 §F3)
- `lib/java/sql.ss interface PreparedStatement` 加 `getParameterMetaData(): ParameterMetaData`
- 静态返值 JDBC 常量(parameterModeIn = 1 / parameterModeInOut = 2 / parameterModeOut = 4 / parameterModeUnknown = 0 + parameterNullable = 1 / parameterNoNulls = 0 / parameterNullableUnknown = 2 — JDBC §10.2 spec 字面值)
- 1 implementor stub:`MysqlPreparedStatement.getParameterMetaData()` stub(prepared.ss,1-line body `return new NoopParameterMetaData()`)+ NoopParameterMetaData class(无字段 stateless stub,7 method 各返 stub 默认值:int → 0 / string → "")
- 全 lib/ + tests/ stub 同步加 vtable getParameterMetaData(D025 vtable 强制全 method,新增 PreparedStatement.getParameterMetaData() 后已有 stub 必同步 — d154/d155/d156 PreparedStatement 各 stub 加 1-line)
- `tests/d157_parameter_metadata/phase1_spike_test.ss` ≥10 case spike GREEN(NoopParameterMetaData 7 method dispatch / JDBC 7 常量值 / ParameterMetaData 接口变量 dispatch / parameterModeIn 默认值 / parameterNullableUnknown 默认值 / getParameterCount 默认 0)
- §A.2 H1 部分实证(本 Phase 接口层 — 1 lib implementor 全返 NoopParameterMetaData,Phase 2 替换 `new MysqlParameterMetaData(paramDefs)` 时共享 paramDefs 路径)
- VCM 六验全 PASS

### Phase 2: MysqlParameterMetaData class 真实现 + 复用 D155 mysqlTypeToJdbcType + spike GREEN [ ] Pending at commit `<phase2-hash>`

- `lib/com/mysql/prepared.ss` 加 `class MysqlParameterMetaData : ParameterMetaData`(单字段 `paramMetadata: Array<ColumnDef>`)
- ≥7 method 真实现:
  - `getParameterCount()` → `paramMetadata.length`
  - `getParameterType(idx)` → `mysqlTypeToJdbcType(paramMetadata[idx-1].colType)`(复用 D155 query.ss 已落地 helper)
  - `getParameterTypeName(idx)` → `mysqlTypeName(paramMetadata[idx-1].colType)`(复用 D155)
  - `getParameterClassName(idx)` → `mysqlTypeToJavaClassName(paramMetadata[idx-1].colType, paramMetadata[idx-1].charset)`(复用 D155 charset-aware 路径)
  - `getParameterMode(idx)` → 静态返 `parameterModeIn = 1`(MySQL prepare statement 不支持 OUT/INOUT)
  - `isNullable(idx)` → 静态返 `parameterNullableUnknown = 2`(prepare 阶段无 SQL placeholder 上下文,Connector/J 范式)
  - `isSigned(idx)` → `(paramMetadata[idx-1].flags & UNSIGNED_FLAG) == 0 ? 1 : 0`(D155 §Phase 3 13 bit flag 解析路径复用,UNSIGNED_FLAG = 0x0020 bit 5)
- 1 implementor 真返:`MysqlPreparedStatement.getParameterMetaData()` 替换 stub `return new MysqlParameterMetaData(paramDefs)`(prepared.ss;`paramDefs` 字段已 lib/com/mysql/prepared.ss:160 构造点存在,无需新协议解析层落地)+ NoopParameterMetaData 仍保留作 stub-driven test mock 锚
- `tests/d157_parameter_metadata/phase2_spike_test.ss` ≥12 case 纯本地全 GREEN(MysqlParameterMetaData class 字段 / getParameterCount 多 num_params 路径 / getParameterType per type ≥5 byte case + JDBC Types code mapping / getParameterTypeName ≥5 case / getParameterClassName charset-aware ≥3 case[VARCHAR / VARBINARY / INT] / getParameterMode 静态 / isNullable 静态 / isSigned 真值 + UNSIGNED 反射 ≥3 case + ParameterMetaData interface vtable dispatch + 空 paramDefs num_params=0 边界)
- §A.2 H1+H3+H4+H5 部分实证(class 真实现 + 1 implementor 真返侧落地,wire 端 docker 实证留 Phase 3)
- VCM 六验全 PASS

### Phase 3: integration_test e2e ≥7 case docker probe-skip + absorb spike + D157 主线 close [ ] Pending at commit `<phase3-hash>`

- `tests/d157_parameter_metadata/integration_test.ss` ≥7 case docker probe-skip e2e(Probe 失败 println + return 离线零阻塞;在线 docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait 后全 PASS;recreateTable + dropTable helper 用 `integration_d157` 表隔离 D134/D136/D138/D139/D146/D147/D151/D154/D155/D156 parallel batch — table 字段 id BIGINT UNSIGNED NOT NULL PK + name VARCHAR(64) + price DECIMAL(10,2) + qty INT + binary_col VARBINARY(64),seed 多类型 row 验 UNSIGNED + binary charset)
- ≥7 case 含:Case 1 num_params=3 INSERT prepare 后 getParameterCount() = 3 / Case 2 getParameterType per type 4 byte case(BIGINT UNSIGNED → Types.BIGINT / VARCHAR → Types.VARCHAR / DECIMAL → Types.DECIMAL / INT → Types.INTEGER) / Case 3 getParameterTypeName 4 case(per colType byte → "BIGINT UNSIGNED" / "VARCHAR" / "DECIMAL" / "INT") / Case 4 getParameterClassName charset-aware 双 case(VARCHAR text → "java.lang.String" + VARBINARY binary charset → "[B")(H3 实证) / Case 5 getParameterMode 全 IN(parameterModeIn = 1)/ Case 6 isNullable 全 Unknown(parameterNullableUnknown = 2,H5 实证)/ Case 7 isSigned 真值(BIGINT UNSIGNED → 0 + INT signed → 1,H3 UNSIGNED_FLAG bit 5 反射实证)+ 可选 Case 8 num_params=0 边界(`SELECT 1` 无参数 prepare,getParameterCount() = 0 不 throw,H5 实证)+ 可选 Case 9 close 后 ParameterMetaData snapshot 仍可访问(H4 实证)
- absorb 删 ≤2 文件:tests/d157_parameter_metadata/phase1_spike_test.ss(stub stage,被 phase2_spike + integration_test 全覆盖)+ tests/d157_parameter_metadata/phase2_spike_test.ss(pure-local reflection,被 integration_test wire 真值版本全覆盖);保留 lib 层 helper 不删
- **§A.2 H1-H5 全实证锚收关**:H1 wire COM_STMT_PREPARE_OK ParameterDef block 默认返 / H2 接口加在 PreparedStatement 静态边界 / H3 复用 parseColumnDef 同结构 charset-aware / H4 close 后 snapshot / H5 num_params=0 边界 + parameterNullableUnknown 静态
- D157 主线 close 锚:Status header `[x] Phase 0-3 + [x] D157 主线 close at commit \`<phase3-hash>\``
- VCM 六验全 PASS

## Followup

| F | 内容 | 范围 |
|---|------|------|
| F1 | TypeInfo Connection 级 SQL 类型反射 — getTypeInfo() 返 ResultSet 18 列 spec(TYPE_NAME, DATA_TYPE, PRECISION, LITERAL_PREFIX, LITERAL_SUFFIX, ...)| Connection 级所有 SQL 类型枚举(JDBC 4.3 §11.7)— 留独立 sub-D 或合 D156 §F2 |
| F2 | CallableStatement OUT / INOUT 参数 mode 反射 — getParameterMode 返 parameterModeOut = 4 / parameterModeInOut = 2 实际值 + binary protocol parameter direction byte | MySQL stored procedure CALL 路径(`{ CALL proc(?, ?, ?) }`),涉 binary protocol parameter direction byte + RESULT_SET 多 ResultSet round-trip — 留独立 sub-D |
| F3 | Wrapper.unwrap / isWrapperFor + getPrecision / getScale ParameterMetaData 扩展 | JDBC 4.3 §10.2 完整 ≥9 method,本 D 落 ≥7 — Wrapper interface 2 method + getPrecision/getScale 留独立 sub-D 或合 D154 §F4 类型类扩展(getPrecision / getScale 复用 D155 ColumnDef41 maxColumnLength + decimals 字段反射,可合 Phase 2 若实现轻量) |
| F4 | 多 driver 兼容(PostgreSQL pg_describe / Oracle OCI parameter binding 路径)| memory `project_no_postgres_for_now.md` 锁 PG 暂搁;Oracle 路径需 OCI driver class — 独立 sub-D 远期 |
| F5 | MysqlPreparedStatement ↔ MysqlParameterMetaData lazy cache(同 MysqlConnection ↔ MysqlDatabaseMetaData lazy cache 范式)| 性能优化 — Phase 2 每次 getParameterMetaData() new MysqlParameterMetaData(paramDefs)(廉价,paramDefs Array snapshot 共享)是否需 lazy cache 待 simplify Agent 3 评估;长期可能不需要 — 留独立 sub-D 或 simplify 内决断 |
| F6 | SQLException 全链覆盖(D139 §F sub-D)对 ParameterMetaData boundary throw 行为升级 | D157 §A.2 H6 — getParameterType idx 越界目前走 SS Array bounds runtime fail,未来 D139 §F SQLException 全链覆盖落地后,各 ParameterMetaData method 显式抛 SQLException("parameter index out of range") — 跨 D 联动,留 D139 §F 主导 |

## Status 时间线

- 2026-05-05 Phase 0 D 文档落档(commit `<phase0-hash>`)— **新建 docs/3-decisions/D157-parameter-metadata.md**(≥150 行 — §核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H5 + §A.3 废案 + §Phase 收关锚 Phase 0-3 + §Followup F1-F5 + §Status 时间线)+ **D156 Phase 4 hash `72e5e0c` 即时回填 D156.md 实际语义位 ≥5 处**(Status header line 3 ×2[Phase 4 entry + 主线 close 锚] + §Phase commit hash 总览段表 Phase 4 行 + §Phase 收关锚 §Phase 4 mark Done at commit + §Phase 收关锚 §Phase 4 内 D156 主线 close 锚引用 + §Phase 收关锚 §Phase 4 元描述行校准[原 "留 placeholder 待下轮回填" → "已由 D157 Phase 0 回填"]+ Status 时间线 Phase 4 entry — D147 §Phase 5 close → D154 §Phase 0 跨 D 起首回填范式延续 + D155 §Phase 4 close → D156 §Phase 0 跨 D 起首回填范式延续);**RED 实测**:ls D157 = ENOENT / grep -c "interface ParameterMetaData" lib/java/sql.ss = 0 / grep -rc "class MysqlParameterMetaData" lib/com/mysql/ = 0 / grep -cE "function getParameterMetaData\(\): ParameterMetaData" lib/java/sql.ss = 0 / grep -c "<phase4-hash>" docs/3-decisions/D156-database-metadata.md = 6(待回填);**GREEN**:D157.md 落档 ≥150 行 + D156 hash 回填全位 0 placeholder + .claude/next_prompt.md 含 ultrathink 关键字;**baseline**:bootstrap/ + lib/ + tools/ + tests/ diff = 0(本 Phase 纯 docs/ + .claude/next_prompt.md)+ d_doc_index_linter F1 = 0 PASS(D147/D154/D155/D156 全实存,加入 D157 实存)+ next_prompt_ultrathink_linter PASS(下轮含 ultrathink 关键字)+ 14 reflection 指标全继承 D156 主线 close baseline(本 Phase 不动 bootstrap/);**simplify 跳过**(纯文档改动,§After Done §1 例外);**等下轮 Phase 1 interface ParameterMetaData ≥7 method + PreparedStatement.getParameterMetaData() 接口加 + NoopParameterMetaData stub class + MysqlPreparedStatement.getParameterMetaData() 1-line stub + ≥10 case spike GREEN**
