# D155: ResultSetMetaData 完整列元数据

**Status:** [ ] Phase 0 D 文档落档 at commit `<phase0-hash>` — D146 §Followup F3 + §A.3 废案 §C3 ResultSetMetaData 部分起首脱胎,D135-D154 SQL 主线范式延续。走**完整 JDBC 4.3 §15.4 `interface ResultSetMetaData` ≥21 method**(getColumnCount / getColumnName / getColumnLabel / getColumnType / getColumnTypeName / getColumnDisplaySize / getColumnClassName / getCatalogName / getSchemaName / getTableName / isNullable / isAutoIncrement / isCaseSensitive / isCurrency / isDefinitelyWritable / isReadOnly / isSearchable / isSigned / isWritable / getPrecision / getScale)+ **完整 MySQL Native Protocol §6.6 ColumnDefinition41 packet 字段反射**(catalog / schema / table / orgTable / name / orgName / charset / maxColumnLength / colType / flags / decimals)+ **MysqlResultSetMetaData class 真实现**(单字段 `colMetadata: Array<ColumnDef>` + ≥21 method 反射派生 + 16 bit MySQL flag 解析 + JDBC `Types` SQL type code mapping)+ **`ResultSet.getMetaData(): ResultSetMetaData` 接口加 + 4 implementor 真返/stub**(MysqlBinaryResultSet binary protocol / MysqlResultSet text protocol / GeneratedKeyResultSet synthetic / NoopResultSet test mock)— 不接受次优 / workaround / 节省。

## 起首脱胎
- D146 §Followup F3(`docs/3-decisions/D146-server-side-cursor.md:207`)+ §A.3 废案 §C3 ResultSetMetaData 部分(line 110)
- D135-D154 SQL 主线范式延续(Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设挑战)
- Depends on:D146(server-side cursor 主线 close)+ D147(§Phase 3 ColumnDef 已扩 orgTable + flags 字段 — 本 D 续接扩展)+ D154(MySQL driver class 主线 close)

## 核心目标 (Goal)

落地后:
1. `lib/java/sql.ss interface ResultSetMetaData` 存在,JDBC 4.3 §15.4 ≥21 method 全声明
2. `lib/java/sql.ss interface ResultSet` 加 `getMetaData(): ResultSetMetaData` method
3. `lib/com/mysql/query.ss ColumnDef` 完整 ColumnDef41 字段(catalog / schema / table / orgTable / name / orgName / charset / maxColumnLength / colType / flags / decimals)
4. `parseColumnDef` 完整解析所有 ColumnDef41 段
5. 7 cross-module accessor helper(columnDefCatalog / Schema / Table / OrgName / Charset / MaxColumnLength / Decimals)
6. `MysqlResultSetMetaData` class 单字段 colMetadata + ≥21 method 反射派生
7. 13 bit MySQL flag 常量(NOT_NULL_FLAG 0x0001 / PRI_KEY_FLAG 0x0002 / UNIQUE_KEY_FLAG 0x0004 / MULTIPLE_KEY_FLAG 0x0008 / BLOB_FLAG 0x0010 / UNSIGNED_FLAG 0x0020 / ZEROFILL_FLAG 0x0040 / BINARY_FLAG 0x0080 / ENUM_FLAG 0x0100 / AUTO_INCREMENT_FLAG 0x0200 / TIMESTAMP_FLAG 0x0400 / SET_FLAG 0x0800 / NUM_FLAG 0x8000)
8. JDBC Types SQL type code mapping function `mysqlTypeToJdbcType(byte): int`(≥20 mapping case)
9. 4 implementor:MysqlBinaryResultSet.getMetaData() 真返 / MysqlResultSet.getMetaData() text protocol 真返 / GeneratedKeyResultSet.getMetaData() synthetic 1 col stub / NoopResultSet.getMetaData() test mock
10. integration_test.ss e2e ≥10 case docker probe-skip 全形态覆盖
11. `./build.sh bootstrap` 三阶段固定点 stage2==stage3 + `bin/ss test tests/` baseline 全继承 + reflection_health_linter 全 14 指标无 regression + d_doc_index_linter F1 = 0 + next_prompt_ultrathink_linter PASS

**RED**(本 D 文档落档前实测):
- `grep -c "interface ResultSetMetaData" lib/java/sql.ss` = 0(interface 完全缺,起首必新建)
- `grep "col\.charset\|col\.maxColumnLength\|col\.decimals" lib/com/mysql/query.ss` = 0(ColumnDef41 字段缺)
- `grep "MysqlResultSetMetaData" lib/com/mysql/` 跨模块全 = 0(class 不存在)

## 核心原则 (Principles)

1. **走完整 JDBC 4.3 §15.4 ResultSetMetaData spec ≥21 method**:不简化、不 stub 关键 method、不"够用就行"(用户对话锁不接次优 / workaround / 节省)
2. **ColumnDef41 字段反射式实现**:MysqlResultSetMetaData ≥21 method 全部从 `colMetadata[col-1]` 派生,不维护额外状态(MySQL Connector/J 5.1+ MysqlResultSetMetaData 范式)
3. **16 bit MySQL flag 完整解析**:isNullable / isAutoIncrement / isSigned 等从 `flags & MASK` 派生,不依赖 INFORMATION_SCHEMA 二次查询(Connector/J `MysqlDefs` 范式)
4. **JDBC Types mapping 表静态查找**:MySQL colType byte → java.sql.Types int 走静态 mapping 函数,不走运行时 case dispatch(D154 driver class type 范式延续)
5. **4 implementor 完整覆盖**:MysqlBinaryResultSet binary protocol / MysqlResultSet text protocol / GeneratedKeyResultSet synthetic 1 col / NoopResultSet test mock — 不留 stub 关键路径
6. **D135-D154 SQL 主线范式延续**:Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设 + §A.3 废案 + §Followup
7. **per-call Connection 简化继承 D137**:JdbcTemplate.query(sql, ResultSetExtractor) 内部 try / open Connection / open PS / open RS / rs.getMetaData() / extractor.extractData(rs) / finally close(D137 + D146 + D147 范式延续)

## A.1 主候选评估(§MNK §M §字段 10)

| 候选 | 层次 | 含 | 不含 | 决策 |
|------|------|-----|------|------|
| **C1** | 数据层 patch | + ColumnDef 部分字段(charset / maxColumnLength / decimals)+ private getColumnNameAt(idx) helper | 无 interface ResultSetMetaData;无 ResultSet.getMetaData() 接口加;ORM 反射列名映射断链 | **不选** — 用户对话锁不接次优 / workaround;ORM Hibernate `BeanPropertyRowMapper` / MyBatis `ResultMap` 反射列映射全断链 |
| **C2** | **接口层 trap** | + 完整 `interface ResultSetMetaData` ≥21 method + ResultSet.getMetaData() 接口加 + ColumnDef41 完整解析 + MysqlResultSetMetaData class 真实现 + 13 bit flag + JDBC Types mapping + 4 implementor 真返 | DatabaseMetaData(getCatalogs / getSchemas / getTables / getColumns)留 §F1 / ParameterMetaData 留 §F2 / TypeInfo 留 §F3 / Wrapper unwrap+isWrapperFor 留 §F4 | **选** — 根因解决:JDBC §15.4 spec 100% + Hibernate/MyBatis/Spring `BeanPropertyRowMapper` 反射列映射标准 idiom 全复用 + D147 §F3 multi-PK / F5 KeyHolder 等下游依赖 prerequisite + 业界演化对标(MySQL Connector/J 5.1+ / Oracle JDBC 演化路径)+ N 年返工度低 |
| **C3** | 架构层 refactor | + DatabaseMetaData(getCatalogs / getSchemas / getTables / getColumns / getPrimaryKeys / getForeignKeys / getIndexInfo)+ ParameterMetaData(getParameterCount / getParameterType / getParameterTypeName / getParameterMode)+ TypeInfo(getTypeInfo Connection 级 SQL 类型反射)+ RowId / SQLXML / Array / Struct 高级类型 metadata | spec 100%;ORM Hibernate `Dialect` / `MetadataSources` / Spring JPA 自动 schema 验证 + Flyway 迁移全 idiom 完整 | **不选** — scope 远超 D155 单 sub-D(LOC > 2500;DatabaseMetaData INFORMATION_SCHEMA 完整查询独立 sub-D + ParameterMetaData COM_STMT_PREPARE_OK packet 解析独立 sub-D + TypeInfo / RowId / SQLXML / Array / Struct 各独立 sub-D)|

**决策行**:**选 C2 接口层 trap**(用户对话锁 — 不接次优 / workaround / 节省)— 因 (a) 完整 JDBC 4.3 §15.4 ResultSetMetaData ≥21 method + ColumnDef41 完整反射 + MysqlResultSetMetaData class 消除 ORM 反射列映射断链根因;(b) Hibernate `BeanPropertyRowMapper` / MyBatis `ResultMap` 自动列映射 / Spring `JdbcTemplate.queryForList` 反射列名映射 标准 idiom 直接复用,无手写列字面 workaround;(c) **底层依赖链最深**:D147 §F3 multi-PK 复合主键 SHOW INDEX / INFORMATION_SCHEMA 推导依赖 ResultSetMetaData / D138 §F1 KeyHolder 主键列识别依赖 column metadata / 未来 ORM 全部依赖,先底层后上层;(d) **业界演化对标**:MySQL Connector/J 5.1+ / Oracle JDBC 演化路径全在协议稳后立刻补 metadata reflection,SS 协议层 D135-D147 + 类型类 D154 已稳,下一阶段必属 metadata;(e) **N 年返工度**:不做 → ORM / KeyHolder / multi-PK / TypeHandler / 任何反射式数据访问全断链,后续每条主线必回头补,返工率极高;(f) D135-D154 SQL 主线范式延续(协议层完整反射 + JDBC 接口扩 + driver 实现 + 测试覆盖 + Phase 计划独立 commit)。**为何不选 C1**:用户对话锁不接次优 / workaround / 节省路径。**为何不选 C3**:scope 远超 D155 单 sub-D — DatabaseMetaData / ParameterMetaData / TypeInfo / RowId / SQLXML / Array / Struct 各留 §Followup 独立 sub-D。

## A.2 隐藏假设挑战

| H | 假设 | 挑战 | 实证锚 |
|---|------|------|--------|
| H1 | ColumnDef41 字段在 binary protocol vs text protocol 一致 | MySQL Native Protocol §6.6 ColumnDefinition41 — binary vs text 同一 packet 结构(spec 明确)+ Connector/J 5.1+ ColumnDefinition source 验证 | Phase 1 unit test parseColumnDef 跨 binary / text 双协议同 packet 范式 PASS |
| H2 | 13 bit MySQL flag bit 位语义跨 MySQL 5.7 / 8.0 稳定 | Connector/J 5.1+ `MysqlDefs` flag 常量自 MySQL 5.0 至 8.0 不变 + MariaDB 兼容 | Phase 3 unit test 13 flag bit 单独 case 验证 + 真 docker MySQL 8.0 PASS |
| H3 | MySQL colType byte → java.sql.Types int mapping 唯一 | MySQL 8.0 colType ≥20 唯一 byte(0x00 DECIMAL ... 0xFF GEOMETRY)+ JDBC Types ≥20 int(java.sql.Types const)mapping 1:1 或 N:1(如 VAR_STRING/STRING 都映 VARCHAR=12)+ Connector/J `MysqlType` 范式 | Phase 3 unit test mapping 表全 byte 验证 |
| H4 | MysqlResultSetMetaData 不维护额外状态,全部 ColumnDef[col-1] 派生 | MySQL Connector/J 5.1+ MysqlResultSetMetaData 实现验证 — class 仅持 ColumnDef[] ref + ≥21 method 反射派生,无额外字段 | Phase 3 class 字段数 = 1(colMetadata: Array<ColumnDef>)实证 |
| H5 | GeneratedKeyResultSet synthetic 单 row 单 col metadata 派生 | 自动生成主键 ResultSet 仅 1 col(GENERATED_KEY BIGINT),metadata 可硬编码 stub(JDBC §13.6.4 spec) | Phase 3 GeneratedKeyResultSet.getMetaData() 返硬编码 1 col stub PASS |
| H6 | MysqlResultSet text protocol getMetaData() 与 binary protocol 行为一致 | text protocol 也走 ColumnDef41 packet(MySQL Native Protocol §10.6 COM_QUERY ResultSet)+ Connector/J `ResultSetImpl` text/binary 共享 metadata 路径 | Phase 4 integration_test text protocol getMetaData() 路径覆盖 |
| H7 | ResultSetMetaData 在 cursor close 后行为(allowed?) | JDBC 4.3 §15.4 spec — metadata 可在 ResultSet close 后访问(独立生命周期);实现走 colMetadata Array<ColumnDef> ref 持有,close 不释放 | Phase 4 integration_test close 后 getMetaData() PASS |

## A.3 废案

- **C1 数据层 patch**(用户对话锁不接次优;ORM 反射列名映射断链)
- **C3 架构层 refactor + DatabaseMetaData + ParameterMetaData + TypeInfo + RowId / SQLXML / Array / Struct 高级类型**(scope 远超 D155 单 sub-D — 各独立 sub-D 留 §Followup F1-F4)
- **简化 ResultSetMetaData 到 ≤10 method 子集**(用户对话锁不接节省;ORM 反射 idiom 必依赖完整 ≥21 method)
- **MysqlResultSetMetaData 维护额外状态**(违反 H4 — Connector/J 范式纯 ColumnDef[] 派生)
- **PostgreSQL DECLARE COLUMN ... 元数据反射路径**(SQL standard;但 D155 范畴限 MySQL — PG driver 暂时不兼容,2026-05-05 用户对话锁,详 memory `project_no_postgres_for_now.md`)

## Phase 收关锚

### Phase 0: D 文档落档 [ ] Pending(本 commit)

- 落地 `docs/3-decisions/D155-resultset-metadata.md`(本文件)— §核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H7 + §A.3 废案 + §Phase 收关锚 Phase 0-4 + §Followup F1-F4 + §Status 时间线
- 落地 `.claude/next_prompt.md`(下轮 Phase 1 起首)
- bootstrap/ + lib/ + tools/ + tests/ diff = 0
- baseline:d_doc_index_linter F1 = 0(D146/D147/D154 全实存)+ next_prompt_ultrathink_linter PASS(下轮含 ultrathink 关键字)

### Phase 1: ColumnDef41 完整字段解析升级 + 7 accessor helper + unit test [ ] Pending

- `lib/com/mysql/query.ss ColumnDef` 加 7 字段:`catalog: string` / `schema: string` / `table: string` / `orgName: string` / `charset: int` / `maxColumnLength: int` / `decimals: int`(D147 Phase 3 已加 `orgTable: string` + `flags: int`,本 Phase 续扩 7 字段,合计 ColumnDef ≥11 字段完整 ColumnDef41 覆盖)
- `parseColumnDef` 改全部 skipLengthEncodedString → readLengthEncodedString:`catalog`(原 skip 第 1 段)/ `schema`(原 skip 第 2 段)/ `table`(原 skip 第 3 段)/ `orgName`(原 skip 第 6 段);加 fixed-length 段 `charset = byteToInt(payload, off, 2)` / `maxColumnLength = byteToInt(payload, off, 4)` / `decimals = byteToInt(payload, off, 1)`(MySQL Native Protocol §6.6 ColumnDefinition41 — fixed-length 段在 colType + flags 之后)
- 7 cross-module accessor helper:`columnDefCatalog` / `columnDefSchema` / `columnDefTable` / `columnDefOrgName` / `columnDefCharset` / `columnDefMaxColumnLength` / `columnDefDecimals`(同 D147 Phase 3 columnDefOrgTable / columnDefFlags 范式)
- `tests/d155_resultset_metadata/phase1_columndef_unit_test.ss` ≥10 case byte-level pass-through 实证(catalog="def" / schema="test" / table="users" / orgTable="users" / name="id" / orgName="id" / charset=63 / maxColumnLength=11 / colType=0x03 / flags=0x4003 / decimals=0)+ 7 accessor round-trip
- baseline:`./build.sh bootstrap` stage2==stage3 + `bin/ss test tests/` 净 +10 passed

### Phase 2: interface ResultSetMetaData ≥21 method + ResultSet.getMetaData() 接口加 + JDBC 常量 + 4 implementor stub + spike GREEN [ ] Pending

- `lib/java/sql.ss` 加 `interface ResultSetMetaData` ≥21 method:`getColumnCount(): int` / `getColumnName(int col): string` / `getColumnLabel(int col): string` / `getColumnType(int col): int` / `getColumnTypeName(int col): string` / `getColumnDisplaySize(int col): int` / `getColumnClassName(int col): string` / `getCatalogName(int col): string` / `getSchemaName(int col): string` / `getTableName(int col): string` / `isNullable(int col): int` / `isAutoIncrement(int col): boolean` / `isCaseSensitive(int col): boolean` / `isCurrency(int col): boolean` / `isDefinitelyWritable(int col): boolean` / `isReadOnly(int col): boolean` / `isSearchable(int col): boolean` / `isSigned(int col): boolean` / `isWritable(int col): boolean` / `getPrecision(int col): int` / `getScale(int col): int`(JDBC 4.3 §15.4 完整子集 ≥21 method;Wrapper unwrap / isWrapperFor 留 §Followup F4)
- `lib/java/sql.ss interface ResultSet` 加 `getMetaData(): ResultSetMetaData`
- JDBC 常量:`columnNoNulls = 0` / `columnNullable = 1` / `columnNullableUnknown = 2`
- 4 implementor stub:MysqlBinaryResultSet / MysqlResultSet / GeneratedKeyResultSet / NoopResultSet(返 NoopResultSetMetaData stub class)
- `tests/d155_resultset_metadata/phase2_spike_test.ss` ≥6 case 纯本地 mock NoopResultSetMetaData ≥21 method reachable
- baseline:./build.sh bootstrap stage2==stage3 + bin/ss test tests/ 净 +6 passed

### Phase 3: MysqlResultSetMetaData class 真实现 + 13 bit flag + JDBC Types mapping + 4 implementor 真返 + spike GREEN [ ] Pending

- `lib/com/mysql/query.ss` 加 `class MysqlResultSetMetaData : ResultSetMetaData`(单字段 `colMetadata: Array<ColumnDef>`)
- ≥21 method 真实现:`getColumnCount` 返 `colMetadata.length()`;`getColumnName(col)` 返 `columnDefName(colMetadata[col-1])`;`getColumnLabel(col)` 返 `columnDefName(colMetadata[col-1])`(SQL alias 即 name);`getColumnType(col)` 返 `mysqlTypeToJdbcType(columnDefColType(colMetadata[col-1]))`;`getColumnTypeName(col)` 返 `mysqlTypeName(columnDefColType(colMetadata[col-1]))`;`getColumnDisplaySize(col)` 返 `columnDefMaxColumnLength(colMetadata[col-1])`;`getColumnClassName(col)` 返 `mysqlTypeToJavaClassName(columnDefColType(colMetadata[col-1]))`;`getCatalogName / SchemaName / TableName(col)` 返 `columnDefCatalog/Schema/Table`;`isNullable(col)` 返 `(columnDefFlags(colMetadata[col-1]) & NOT_NULL_FLAG) ? columnNoNulls : columnNullable`;`isAutoIncrement(col)` 返 `(columnDefFlags(colMetadata[col-1]) & AUTO_INCREMENT_FLAG) != 0`;`isCaseSensitive(col)` 返 `mysqlTypeIsCaseSensitive(columnDefColType(colMetadata[col-1]))`(charset != 33 ci);`isCurrency` 返 `0`(MySQL 无 currency type);`isDefinitelyWritable` 返 `1`;`isReadOnly` 返 `0`;`isSearchable` 返 `1`;`isSigned(col)` 返 `(columnDefFlags(colMetadata[col-1]) & UNSIGNED_FLAG) == 0`;`isWritable` 返 `1`;`getPrecision(col)` 返 `columnDefMaxColumnLength(colMetadata[col-1])`;`getScale(col)` 返 `columnDefDecimals(colMetadata[col-1])`
- 13 bit MySQL flag 常量:`NOT_NULL_FLAG = 0x0001` / `PRI_KEY_FLAG = 0x0002` / `UNIQUE_KEY_FLAG = 0x0004` / `MULTIPLE_KEY_FLAG = 0x0008` / `BLOB_FLAG = 0x0010` / `UNSIGNED_FLAG = 0x0020` / `ZEROFILL_FLAG = 0x0040` / `BINARY_FLAG = 0x0080` / `ENUM_FLAG = 0x0100` / `AUTO_INCREMENT_FLAG = 0x0200` / `TIMESTAMP_FLAG = 0x0400` / `SET_FLAG = 0x0800` / `NUM_FLAG = 0x8000`(D147 已加 PRI_KEY_FLAG,本 Phase 续扩 12 常量)
- JDBC Types mapping function `mysqlTypeToJdbcType(byte): int`:0x00→DECIMAL=3 / 0x01→TINYINT=-6 / 0x02→SMALLINT=5 / 0x03→INTEGER=4 / 0x04→FLOAT=6 / 0x05→DOUBLE=8 / 0x07→TIMESTAMP=93 / 0x08→BIGINT=-5 / 0x0A→DATE=91 / 0x0B→TIME=92 / 0x0C→TIMESTAMP=93(DATETIME) / 0xF6→DECIMAL=3(NEWDECIMAL) / 0xFB→LONGVARBINARY=-4(LONG_BLOB) / 0xFC→LONGVARBINARY=-4(BLOB) / 0xFD→VARCHAR=12(VAR_STRING) / 0xFE→CHAR=1(STRING) ≥20 mapping
- 4 implementor 真返:`MysqlBinaryResultSet.getMetaData()` 返 `new MysqlResultSetMetaData(this.colMetadata)` / `MysqlResultSet.getMetaData()` 返 `new MysqlResultSetMetaData(this.colMetadata)`(text protocol 共享 ColumnDef41 解析路径,H6 实证)/ `GeneratedKeyResultSet.getMetaData()` 返硬编码 1 col GENERATED_KEY BIGINT stub(H5 实证)/ `NoopResultSet.getMetaData()` 返 `new NoopResultSetMetaData()`(test mock)
- `tests/d155_resultset_metadata/phase3_spike_test.ss` ≥10 case docker probe-skip 范式(127.0.0.1:3307 不可达 → println + return 离线零阻塞,在线时全 PASS)
- baseline:./build.sh bootstrap stage2==stage3 + bin/ss test tests/ 净 +10 passed

### Phase 4: integration_test e2e ≥10 case + absorb spike + 全 Phase 收关 + D155 主线 close [ ] Pending

- `tests/d155_resultset_metadata/integration_test.ss` ≥10 case docker probe-skip e2e 全形态:Case 1 `getColumnCount()` / Case 2 `getColumnName/Label/Type/TypeName/DisplaySize/ClassName` / Case 3 `getCatalogName/SchemaName/TableName` / Case 4 `isNullable` 三态(NOT_NULL_FLAG / Nullable)/ Case 5 `isAutoIncrement` AUTO_INCREMENT_FLAG / Case 6 `isSigned` UNSIGNED_FLAG / Case 7 `getPrecision` + `getScale` DECIMAL(10,2)/ Case 8 ResultSet close 后 getMetaData() 仍可访问(H7 实证)/ Case 9 GeneratedKeyResultSet.getMetaData() synthetic stub(H5 实证)/ Case 10 text protocol MysqlResultSet.getMetaData() 与 binary protocol 同字段(H6 实证)
- absorb 决策:删 phase2_spike + phase3_spike 由 integration_test 覆盖;保留 phase1_columndef_unit_test 纯本地 byte-level
- §A.2 H1-H7 全实证锚收关
- 全 Phase 0-4 commit hash 总览
- D155 主线 close 锚 + Status 时间线 close entry
- baseline:./build.sh bootstrap stage2==stage3 + bin/ss test tests/ 净 +10 passed - 2 spike

## Followup

| F | 内容 | 范围 |
|---|------|------|
| F1 | DatabaseMetaData 完整 schema introspection — getCatalogs / getSchemas / getTables / getColumns / getPrimaryKeys / getForeignKeys / getIndexInfo / getProcedures / getProcedureColumns ≥30 method | INFORMATION_SCHEMA 完整查询;Hibernate `Dialect` / Spring JPA 自动 schema 验证 / Flyway 迁移依赖;留独立 sub-D |
| F2 | ParameterMetaData PreparedStatement 参数侧 metadata — getParameterCount / getParameterType / getParameterTypeName / getParameterMode / getParameterClassName / isNullable / isSigned | COM_STMT_PREPARE_OK packet ParameterDef 解析(同 ColumnDef41 范式);Spring `JdbcTemplate.update` 反射参数类型推导依赖;留独立 sub-D |
| F3 | TypeInfo Connection 级 SQL 类型反射 — getTypeInfo() | Connection 级所有 SQL 类型枚举(JDBC 4.3 §11.7);留独立 sub-D 或合入 §F1 DatabaseMetaData |
| F4 | Wrapper.unwrap / isWrapperFor + RowId / SQLXML / Array / Struct ResultSetMetaData 高级类型 method | JDBC 4.3 §15.4 ≥24 完整 method 已落 ≥21,Wrapper interface 2 method + RowIdLifetime 1 method 留独立 sub-D 或合入 D154 §F4 类型类扩展 |

## Status 时间线

- 2026-05-05 Phase 0 D 文档落档(commit `<phase0-hash>`)— D146 §Followup F3 + §A.3 废案 §C3 ResultSetMetaData 部分起首脱胎,D135-D154 SQL 主线范式延续(C2 接口层 trap 候选 — 用户对话锁不接次优 / workaround / 节省路径);设计走 (a) ColumnDef41 完整字段解析升级(D147 Phase 3 已加 orgTable + flags,本 D 续扩 catalog/schema/table/orgName/charset/maxColumnLength/decimals)(b) interface ResultSetMetaData ≥21 method + ResultSet.getMetaData() 接口加 + JDBC 常量 columnNoNulls/Nullable/NullableUnknown(c) MysqlResultSetMetaData class 真实现(单字段 colMetadata + ≥21 method 反射派生 + 13 bit MySQL flag 解析 + JDBC Types mapping ≥20 case)(d) 4 implementor 真返/stub(MysqlBinaryResultSet binary protocol / MysqlResultSet text protocol H6 共享 / GeneratedKeyResultSet synthetic 1 col H5 / NoopResultSet test mock)(e) ≥10 case integration_test e2e 全形态;**§A.2 H1-H7 假设挑战 — H1 ColumnDef41 binary/text 协议一致 / H2 13 bit flag 跨 MySQL 5.7+/8.0 稳定 / H3 colType byte → JDBC Types 唯一 mapping / H4 MysqlResultSetMetaData 单字段不维护额外状态 / H5 GeneratedKeyResultSet synthetic stub / H6 text/binary protocol metadata 共享 / H7 ResultSet close 后 metadata 仍可访问**;**§A.3 废案 — C1 数据层 patch / C3 架构层 refactor + DatabaseMetaData + ParameterMetaData + TypeInfo + RowId/SQLXML/Array/Struct / 简化 ≤10 method 子集 / MysqlResultSetMetaData 维护额外状态 / PostgreSQL 路径 (PG 暂不兼容 — memory project_no_postgres_for_now.md)**;**Followup F1-F4 锚明确 — F1 DatabaseMetaData 独立 sub-D / F2 ParameterMetaData 独立 sub-D / F3 TypeInfo / F4 Wrapper / RowId / SQLXML 高级类型**;**VCM 六验全 PASS** — §1 工程豁免(本 Phase 仅 docs/ + .claude/next_prompt.md,bootstrap/ + lib/ + tools/ + tests/ diff = 0)+ §2 行为(D155 doc Phase 0 章节 grep PASS)+ §3 反向(撤回 D155 → docs/3-decisions/D155-resultset-metadata.md 不存,F3 sub-D 起首未落档)+ §4 边界(§Followup F1-F4 全锚 + §A.2 H1-H7 全锚 + Depends on D146/D147/D154 全实存)+ §5 路线(D135-D154 SQL 主线范式延续)+ §6 根因(file:line 锚 = D146 §Followup F3 line 207 起首脱胎 + §A.3 §C3 line 110 + 本 D155 §核心目标 + §A.1 C2 决策行 + §Phase 收关锚 Phase 0 mark Pending);**baseline**:d_doc_index_linter F1 = 0 PASS(D155 加入未破 referenced Ds — D146/D147/D154 全实存);**next_prompt_ultrathink_linter PASS**(下轮提示词含 ultrathink 关键字);**编译器零改动**(本 Phase 纯 docs/);**等下轮 Phase 1 ColumnDef41 完整字段解析升级 + 7 accessor helper + unit test**
