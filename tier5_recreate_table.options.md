## Tier5 recreateTable 族形态巡检 — 方案对比与决策

延续 Tier1-4 测试 DRY 主线(commit `bb08cf3`/`a4f97d8`/`8d49763`/`deebc51`)。上一轮 Tier4
dropTable 抽 `dropAllTables(url, names: Array<string>)` 净 -36 LOC 9→0 GREEN;
Tier4 commit message 显式留「setupTable / clearAll / recreateTable 同形 fixture 留 Tier5 单独评估」。
本轮 Tier5 调研 recreateTable 族 9 文件可抽性,不连带做 setupTable/clearAll。

### 形态实测(9 文件,grep -A 12 '^function recreateTable')

| 文件 | 表名 | DROP 数 | CREATE 数 | seed 形态 | 分组 |
|------|------|--------|----------|----------|------|
| d134_mysql/integration_test.ss | users | 1 | 1 (InnoDB) | — | **G1** |
| d138_generated_keys/integration_test.ss | d138_generated_keys | 1 | 1 (AUTO_INCREMENT) | — | **G1** |
| d139_sql_exception/integration_test.ss | d139_sql_exception_test | 1 | 1 (NOT NULL) | — | **G1** |
| d157_parameter_metadata/integration_test.ss | integration_d157 | 1 | 1 (BIGINT UNSIGNED + BLOB) | — | **G1** |
| d136_prepared_statement/integration_test.ss | users_d136 | 1 | 1 | 2 静态 INSERT | **G2** |
| d155_resultset_metadata/integration_test.ss | integration_d155 | 1 | 1 (BIGINT UNSIGNED + DECIMAL) | 2 静态 INSERT(含 NULL) | **G2** |
| d146_server_cursor/integration_test.ss | d146_server_cursor_integration | 1 | 1 | `while(i<=ROW_COUNT=1000)` 循环 INSERT | **G3** |
| d147_updatable_cursor/integration_test.ss | integration_d147 | 1 | 1 (UNIQUE) | `while(i<=5)` 模板化 INSERT(4 列) | **G3** |
| d156_database_metadata/integration_test.ss | parent + child | 2(child 先) | 2(FK) | 2 INSERT(FK 顺序) | **G4** |

**分组语义差异**:
- **G1**(4 文件):纯 DROP + CREATE,helper 内核 = `tmpl.execute(DROP) + tmpl.execute(createSql)` 3 行
- **G2**(2 文件):G1 + 静态 seed Array,可在 G1 helper 上加 `seedSqls: Array<string>` 参数
- **G3**(2 文件):循环 INSERT,d146 1000 行物理不可 Array 展开 + d147 模板化 4 列字段插值
- **G4**(1 文件):FK 双表,DROP 顺序敏感(child→parent),CREATE 顺序敏感(parent→child)

### 候选方案(≥ 3)

#### 候选 A — 全抽,高度参数化(架构层 refactor)

```ss
function recreateTable(url: string, dropSqls: Array<string>,
                       createSqls: Array<string>, seedSqls: Array<string>): int
```

- **覆盖**:G1/G2/G4 自然(顺序通过 Array 索引保留),G3 d146 需调用方预先展开 1000 行 INSERT(物理不可)
- **G3 d147** while 循环模板化(`"INSERT ... VALUES (" + i + ", " + (i * 10) + ...)`) → 调用方仍需写循环再 push 到 seedSqls,helper 调用 vs inline 等价啰嗦
- **API 参数膨胀**:调用方构造 3 个 Array 比 inline `tmpl.execute(...)` 多
- **净 LOC**:G1 调用方 +2 行(空 [] × 2)、G2 调用方 +1 行、G3 d146 不适用、G3 d147 不适用、G4 +1 行;helper +15 行 → 估算 **+15-25 LOC(反向)**
- **层次定位**:架构层但 G3 物理不可达 → 假覆盖
- **长久 / 演化维度**:helper 4 参数等价"小 ORM"早期形态,业界演化对标 Spring JdbcTestUtils 提供分散 helper(`createTable` / `dropTables` / `countRowsInTable`)而非聚合 4-arg 入口 → A 与业界演化反向 N 年返工度高

#### 候选 B — G1 only 抽简单 helper(接口层 trap)

```ss
function recreateTableSimple(url: string, table: string, createSql: string): int {
    const tmpl = new JdbcTemplate(url)
    tmpl.execute(`DROP TABLE IF EXISTS ${table}`)
    tmpl.execute(createSql)
    return 0
}
```

- **覆盖**:G1 4 文件(d134/d138/d139/d157)
- **调用方形态**:`function recreateTable(): int { return recreateTableSimple(URL, "users", "CREATE TABLE users ...") }` — 5 行 → 2 行
- **净 LOC**:helper +6 + 4 文件 × -3 行 = **-6 LOC**
- **API 简单**:3 参数对齐 dropAllTables 风格
- **反身性问**:抽出后调用方仍传 createSql string(字面 CREATE TABLE SQL),消除的只是 `const tmpl = new JdbcTemplate(URL)` + `return 0` 2 行 × 4 = 8 行模板字面
- **隐患**:helper 内核仅 `tmpl.execute(DROP) + tmpl.execute(createSql)` 两行真逻辑 — sugar 而非 DRY,与 dropTable 抽出"DROP TABLE IF EXISTS X"模板化截然不同
- **长久 / 演化维度**:helper 内核 2 行的 indirection,N 年返工概率高(下游若想加 seed / FK 必扩 API → 演化方向不收敛)

#### 候选 C — G1+G2 扩展 helper(接口层 trap)

```ss
function recreateTableSimple(url: string, table: string,
                             createSql: string, seedSqls: Array<string>): int
```

- **覆盖**:G1 + G2 共 6 文件
- **G1 调用方**:`recreateTableSimple(URL, "users", "...", [])` — 末尾 `[]` 略啰嗦
- **G2 调用方**:`recreateTableSimple(URL, "users_d136", "...", ["INSERT...", "INSERT..."])`
- **净 LOC**:helper +10 + 6 文件 × -3 行(d136/d155 多省 1 行 INSERT 字面)= **-8 LOC**
- **API 多 1 参数**:Array<string> 空 [] 形态
- **反身性问**:同 B,seedSqls 字面 INSERT SQL 仍在调用方,helper 多包一层循环 — sugar 升级版
- **长久 / 演化维度**:G3 d147 循环 INSERT 模板插值无法套入 seedSqls(while 循环不能 Array 展开),G3/G4 仍 inline,API 仍非完整覆盖

#### 候选 D — 不抽,留 inline fixture(数据层零改)

- **覆盖**:无(9 文件 recreateTable 全留 inline)
- **净 LOC**:0
- **决策依据**(根因解决度判定):
  - **dropTable vs recreateTable 本质差异**:dropTable 是「DROP TABLE IF EXISTS X」字串模板化 + 表名是**唯一变量** → 真 DRY,9 文件 → 1 helper 高回报;recreateTable 是「DROP + CREATE TABLE X (...schema...)」schema **每文件独立异构** → helper 仅薄包 `const tmpl + execute` 模板代码,真正消除的"重复"是 3 行模板字面 × N
  - **schema 与测试语义紧绑**:d138 AUTO_INCREMENT 是 GeneratedKeys case 的关键、d155 BIGINT UNSIGNED + DECIMAL 是 ResultSetMetadata 验证靶子、d146 1000 行循环是 server cursor scope 标志、d156 FK 是 DatabaseMetadata 测试核心 — 抽到 helper 后 schema 字面跨文件传递,读测试需 cross-reference helper signature 反损可读性
  - **fixture 异构是设计本质而非工程债**:每个测试场景独立 schema 是 fixture-per-test 设计 idiom,业界对标 JUnit `@Sql` annotation / Spring `JdbcTestUtils.executeSqlScript` 都是 per-test fixture 不强行抽聚合 helper
- **缺点**:9 文件 × 3 行模板代码(const tmpl + DROP + return 0)~27 行字面级重复
- **长久 / 演化维度**:加新 JDBC 测试 copy-paste 3 行模板可接受成本,N 年返工度低 — fixture 异构 schema 永远存在,不是临时债务

### 决策行

**选 D — 不抽,留 inline fixture**。根因解决度评分:**Tier5 与 Tier4 本质差异 = dropTable 同构语义(表名是唯一变量)vs recreateTable 异构 schema(每文件独立 DDL)**;A 假覆盖(G3 物理不可达)、B/C 是 sugar 不是 DRY(helper 内核仅 2 行 indirection,createSql 字面仍在调用方),D 保留 inline 与测试 fixture-per-test 设计 idiom 自洽。

**不选 deeper layer(架构层 refactor 候选 A)的理由**:
- (a) 工程量:候选 A 物理不可达(G3 循环 INSERT 无法 Array 展开)
- (b) 业界演化对标:Spring JdbcTestUtils 是分散 helper 不是聚合 4-arg 入口
- (c) N 年返工度:候选 A 与 fixture-per-test 主流 idiom 反向,长期返工概率高

**不选 sugar helper(B/C)的理由**:
- (a) 反身性问:抽出后调用方 createSql 字面仍 inline,消除的仅 const tmpl + return 0 模板字面 — 是 sugar 不是真 DRY
- (b) 与 Tier4 dropTable 抽法本质不同:dropTable 抽是"DROP TABLE IF EXISTS X" 字串模板化,recreateTable 抽不到等价的字串模板化锚
- (c) 长久演化:helper 内核仅 2 行的 indirection 加抽象层无信息密度回报

### 反身性问答

**问**:不做 Tier5 抽出,Tier 主线第一性需求(测试 DRY)会被卡吗?
**答**:不被卡。Tier 主线第一性需求是「同构语义的字面重复消除」,recreateTable 异构 schema 不符合"同构"前提。Tier5 调研结论"不抽"恰好定义主线适用边界 — Tier 不是"凡测试模板必抽"而是"凡同构语义必抽,异构 schema 保留 inline"。

**问**:本轮"不抽"决策与上一轮"全抽 dropTable"决策矛盾吗?
**答**:不矛盾。两轮决策基于同一判据"同构 vs 异构":
- Tier4 dropTable:9 文件全 `DROP TABLE IF EXISTS X` 同构,X 是唯一变量 → 抽
- Tier5 recreateTable:9 文件 DDL 异构(schema / seed / 循环 / FK 各异)→ 不抽

### 下游 action(本轮不做,留下轮 issue)

- **Tier6 setupTable / clearAll 单独评估**:Tier4 commit message 同样留待,与 Tier5 同源调研
- **stringly-typed cleanup PR**:Tier4 commit message 留的 d134/d136/d138/d139/d146 无 `const TABLE` 仍裸字面量调 dropAllTables — 独立任务不在本轮 scope

### 结论

**Tier5 落定为"不抽,留 inline fixture"**,Plan 型 Decision Layer 调研产出归档本文件;**不进入 Execute 阶段**,9 文件 integration_test.ss 全保持 inline,`tests/jdbc/import/jdbc_test_helpers.ss` 不变。
