# D137: JdbcTemplate Prepared Retcon — PreparedStatementSetter Callback Routing

**Status:** [✓] Phase 0 落盘 at commit `bafc25a` + [✓] Phase 1 实施落地 at commit `d2df1ba` + [✓] Phase 2 实施落地 at commit `4c28bc0` + [✓] Phase 3 实施落地 at commit `4a10e48` + [✓] Phase 4 e2e 闭环收关 at commit `8e1c5de`(D137 完结)

**Depends on:**
- D136 全 Phase 收关锚(commit `b7cb6d5`)— `interface PreparedStatement` + `lib/com/mysql/prepared.ss` MysqlPreparedStatement 实施 + `MysqlConnection.prepareStatement()` driver 拼装 + `tests/d136_prepared_statement/` e2e 已就绪
- D134 全 Phase 收关锚(commit `e509be1`)— `lib/spring/jdbc.ss` Phase 5 落地范式(per-call Connection lifecycle)+ `tests/d134_mysql/` integration test 框架
- D135 全 Phase 收关锚(commit `1c2e07b`)— 认证层不在本 D 范围(只读 `tests/d135_caching_sha2/` 4 case 不 retcon 论证)
- D025 Interface Dispatch — `interface PreparedStatement` driver-agnostic 接口
- CLAUDE.md §项目本质 axiom("应用层 stdlib 用纯 SS")
- CLAUDE.md §项目技术规则 §Root Cause 优先 L91-103("第一法则,无例外")
- CLAUDE.md §项目技术规则 §交互式单文档(用户对话授权 2026-04-27 "1" → 锁选 D137 → "A" → 锁选候选 A callback)
- CLAUDE.md §项目技术规则 §Java/TS 语法优先(Spring JdbcTemplate 主线 callback 是参考标杆)
- `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验(Plan 型 §④ 替换「替代方案对比 + 隐藏假设挑战」)+ §大改档位规则
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优的理由)
- `memory/feedback_no_derive_workaround.md`(不留 fallback dead code)
- `memory/feedback_no_option_menu.md`(三候选论证 + 决策行,非选项菜单)

**承 D136 §核心原则 9 + §R5 + §Phase 3 §决策点 defer 锚** —「JdbcTemplate retcon scope 评估留 Phase 3,LOC > 200 或破坏既有签名 → 留 D137 sub-follow-up」+ 用户对话指令 2026-04-27 "1" → "A" → D137 = JdbcTemplate Spring 层 prepared retcon 决策档,候选 A `PreparedStatementSetter callback 重载` 路径。

**Date:** 2026-04-27
**Last Updated:** 2026-04-27

---

## 第一性需求

D136 兑现协议层 + driver-agnostic 接口层 + MysqlPreparedStatement 实施层三层根因解决 SQL 注入 + binary protocol 加速,**Spring 层未接管** —— `lib/spring/jdbc.ss` 5 method(execute / update / queryForList / queryForString / queryForInt)全字符串拼接,`lib/spring/data.ss` 11 处 JpaRepository CRUD 调用全模板字符串(`\`UPDATE ${tableName} SET ${setClauses} WHERE id = ${id}\``),业务层 90%+ 走 ORM Spring,**整个 stack 未受 D136 收益**。

**Why ①(直接症状层)**:`lib/spring/jdbc.ss:22-67` 5 method 实测全 `stmt.execute(sql)` / `stmt.executeQuery(sql)` 文本协议;`lib/spring/data.ss:30/34/38/42/46/50/54/58/62/66` 11 处 JdbcTemplate 调用,`save / findAll / findById / findByColumn / findByColumnInt / existsById / count / deleteById / deleteAll / update` 全部模板字符串拼接动态值(`${id}` / `${value}` / `${setClauses}` / `${vals}`);Spring 层无 prepared 接管 → 业务层若用 JpaRepository 写 CRUD,**SQL 注入暴露面 100% 持续**(D136 driver 层投入对业务层零产出),违反 D136 §第一性需求 axiom 兑现深化承诺。

**Why ②(架构成本层)**:Spring data.ss 是 ORM 抽象层,业务代码绝大多数走 `repo.save(...)` / `repo.findById(...)` / `repo.deleteById(...)` 等高层 API,**永不直接调** lib/com/mysql/jdbc.ss MysqlPreparedStatement;若 Spring 层不接管 prepared,D136 三层根因解决相当于"协议层就绪 + driver 层就绪 + 业务层无法用",ROI 剧降至 10%(仅 tests/d136_prepared_statement/ 5 case 直 driver 测试受益,业务路径全失);D136 §第一性需求 末层"OWASP top 10 #3 SQL 注入"防御**未能传递到业务层**。

**末层断言可观测否定证据**:
```bash
grep -c "prepareStatement" lib/spring/jdbc.ss
# 当前 = 0(本轮 Plan 实测)→ 不做 → JdbcTemplate 完全无 prepared 路径接管,
#   spring/data.ss 11 处 JpaRepository CRUD 全部走文本协议字符串拼接,
#   D136 投入对业务层零产出,SQL 注入根因解决路线在 Spring 层断
```

---

## 核心目标 (Goal)

- **为什么**:**OWASP top 10 #3 SQL 注入根因解决传递到业务层**(D136 协议 / driver / 接口三层就绪 + Spring 层接管 → 业务层 100% 受益)+ **D136 ROI 拉满**(JpaRepository CRUD 全走 prepared,业务路径 binary protocol 加速生效)+ **Spring JdbcTemplate API 主线对齐**(Spring 7.0 真 API 子集 callback 范式)+ D136 §核心原则 9 defer 锚兑现
- **是什么**:`lib/spring/jdbc.ss` 加 5 重载(`execute(sql, setter: fn)` / `update(sql, setter: fn)` / `queryForList(sql, setter: fn)` / `queryForString(sql, setter: fn, column: string)` / `queryForInt(sql, setter: fn, column: string)`)+ `lib/spring/data.ss` 11 处 JpaRepository CRUD 全 retcon 走 callback + `tests/d134_mysql/integration_test.ss` 8 case 含动态值的 retcon 走 callback + 旧 5 method 签名保留(DDL `CREATE TABLE` / `DROP TABLE` / `SET autocommit` 走旧路径)
- **单一判据**:三轨闭环(§第一性需求 末层 grep > 0 + spring/data.ss 11 处全 ?化 + tests/d134_mysql 8 case 全绿)+ `./build.sh bootstrap` 三阶段固定点(纯 lib 改,Phase 1-4 后跑确认零冲击)+ tests/d134_mysql/ 8 case + tests/d135_caching_sha2/ 4 case + tests/d136_prepared_statement/ 5 case 全绿 baseline 不降 + axiom 红线 grep / nm = 0 永久维持(D134 + D135 + D136 全继承)+ d_doc_index_linter F1 = 0

> 口号:**Spring 层接管 prepared — JpaRepository CRUD 全走 callback,SQL 注入根因解决传递到业务层,D136 ROI 拉满**(承 §Root Cause + memory `feedback_no_derive_workaround` + D136 "三层齐落" 范式延续到 Spring 层)

---

## 核心原则 (Principles)

1. **PreparedStatementSetter callback 主线** — Spring JdbcTemplate 真 API 子集(callback fn 接 PreparedStatement,1-based index 内部 setter.setInt(1, x) / setter.setString(2, y));5 method 各加 1 个 `(..., setter: fn, ...)` 重载;**不引入** NamedParameterJdbcTemplate `:name` 命名参数 / RowMapper 泛型 / SqlParameterSource Map-based 三 sub-D 候选(F1-F3,范围外)
2. **既有 5 method 签名零破坏** — 旧 `execute(sql)` / `update(sql)` / `queryForList(sql)` / `queryForString(sql, column)` / `queryForInt(sql, column)` 保留,服务 DDL(`CREATE TABLE` / `DROP TABLE` / `SET autocommit`)+ 无参数 SELECT 路径;tests/d135_caching_sha2/ 4 处 `adminStmt.execute("DROP USER ...")` / `adminStmt.execute("CREATE USER ...")` / `adminStmt.execute("GRANT ALL ...")` 是 DDL + 用户 const 字符串(不接 user input),**不在 SQL 注入面,不 retcon**
3. **不留 string concat fallback dead code** — spring/data.ss 11 处 JpaRepository CRUD 全 retcon 走 callback,**禁留**"旧的字符串拼接路径供 fallback";tests/d134_mysql/integration_test.ss 8 case 含动态值的全部 retcon;DDL / 用户 const 路径走旧签名是**双轨并存非 fallback**(职责分离:DDL = 旧,参数化 = 新)
4. **元数据 vs 动态值 grep 分类** — spring/data.ss 11 处中,`${this.tableName}` / `${this.columns}` / `${column}`(列名)/ `${cols}`(列名列表)是**元数据**(用户 const,不接 user input,不 ?化);`${id}` / `${value}` / `${setClauses}` / `${vals}` 等是**动态值**(?化 + setter);Phase 2 grep 逐条标分类,严防"全 ?化"误把元数据也 ?化(MySQL 不允许 prepared statement ? 占位列名 / 表名)
5. **JdbcTemplate per-call Connection lifecycle 不变** — D134 §Phase 5 范式保留(每次重载方法开 + 关 Connection,无 pool);queryForList 重载仍**故意不**关 Connection(streaming socket 共享 ResultSet,caller 必须 rs.close 才能下次 query)— D134 §Phase 5 caveat 同模式,sub-D HikariCP D125+ 解决
6. **Spring data.ss 11 处全迁** — 用户写 JpaRepository 100% 受益(SQL 注入根因解决传递)+ binary protocol 加速生效;**禁手动跳过**任何一处(全迁完整性是 D137 §核心目标 单一判据的硬约束)
7. **tests retcon 范围明示** — tests/d134_mysql/ 8 case 全部含动态值(`INSERT INTO users VALUES (1, 'Alice', 30)` 等)→ retcon 走 callback;tests/d135_caching_sha2/ 4 case adminStmt DDL → 不动;tests/d136_prepared_statement/ 5 case 已直接走 prepared driver 接口 → 不动
8. **Phase 边界 = commit 边界** — 5 Phase 各自独立 commit,禁打包(承 D134 §Principles 7 + D135 §Principles 9 + D136 §Principles 11)
9. **bootstrap 隔离** — 全 Phase 仅改 lib/ + tests/ + docs/,**不动** bootstrap;PreparedStatement 接口 + MysqlPreparedStatement 实施 + binary protocol IEEE 754 cast pair 等基础设施 D136 全就绪;SS fn 类型多语句 lambda 是既有能力(D134 `withTransaction(db, fn)` 已实证)
10. **不实现 NamedParameterJdbcTemplate / RowMapper 泛型 / SqlParameterSource / batchUpdate / queryForObject + class mapping**(范围外,F1-F3 sub-D follow-up;依赖 SS 泛型 D026/D027 落地的 RowMapper 不能本轮做)
11. **不变量保留**(承 D136):D018 / D022 / D025 / D068 / D088 / D123 / D130-136 全不动;mimalloc C link axiom 例外保留;D134 driver 拼装架构 + D136 prepared 接口契约不破

---

## 1. Context Management(上下文管理)

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D137)
2. CLAUDE.md §项目本质 + §项目技术规则 §Root Cause 优先 + §交互式单文档 + §Java/TS 语法优先
3. docs/3-MNK.md §M PSM 九问 + §N VCM 六验(Plan 型 §④ 替换)+ §K 收敛循环 + §大改档位规则
4. docs/3-decisions/D136-mysql-prepared-statement.md §Status §核心原则 9 §Phase 3 §R5 §Followup F1-F3(defer 锚 + 后续 sub-D 锚)
5. docs/3-decisions/D134-jdbc-mysql-wire-protocol.md §Phase 5(JdbcTemplate per-call Connection lifecycle 范式)
6. docs/3-decisions/D025-interface-dispatch.md(PreparedStatement 接口契约)
7. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `lib/spring/jdbc.ss` | 22-67 | 既有 5 method(execute / update / queryForList / queryForString / queryForInt)— Phase 1 加 5 重载 |
   | `lib/spring/data.ss` | 30/34/38/42/46/50/54/58/62/66 | JpaRepository 11 处 jdbc 调用 — Phase 2 全 retcon |
   | `lib/java/sql.ss` | 51-61 | `interface PreparedStatement`(setInt/setString/setLong/setDouble/setBoolean/setNull + executeQuery/executeUpdate/close)— D136 已就绪 |
   | `lib/com/mysql/jdbc.ss` | 46-48 | `MysqlConnection.prepareStatement(sql)` — D136 已就绪 |
   | `lib/com/mysql/prepared.ss` | 全文 | MysqlPreparedStatement 实施 — D136 已就绪 |
   | `tests/d134_mysql/integration_test.ss` | 8 case | Phase 3 全 retcon(动态值路径)|
   | `tests/d135_caching_sha2/integration_test.ss` | 4 处 adminStmt | **不动**(DDL + const 字符串,§核心原则 7) |
   | `tests/d136_prepared_statement/integration_test.ss` | 5 case | **不动**(已直接走 prepared 接口) |

### Stable Facts

| 项 | 值 |
|---|---|
| spring/jdbc.ss 当前 method 数 | 5(execute / update / queryForList / queryForString / queryForInt) |
| spring/data.ss 当前 jdbc 调用密度 | 11 处全模板字符串拼接 |
| tests/d134_mysql/ 含动态值 case 数 | 8(test 6 / 7 / 8 等含 INSERT/SELECT WHERE id = 20 等)|
| PreparedStatement 接口已就绪 | lib/java/sql.ss:51-61(D136 §核心原则 1 落锚) |
| MysqlPreparedStatement 实施已就绪 | lib/com/mysql/prepared.ss(D136 §Phase 1-2) |
| Connection.prepareStatement 已就绪 | lib/com/mysql/jdbc.ss:46-48(D136 §Phase 1) |
| SS fn 多语句 lambda 实证 | D134 `withTransaction(db: string, fn: fn)` 已用,Phase 1 早期 spike 仍要复测 callback 内 setter.setInt + setter.setString 多语句 |
| Spring 7.0 JdbcTemplate 真 API | callback 风格(PreparedStatementSetter / RowMapper / ResultSetExtractor 三大 callback)— D137 仅子集 PreparedStatementSetter |
| 反射 baseline | tools/reflection_health_linter.ss(本 D 不触反射) |
| d_doc_index_linter F1 | 0(GATE OK)+ D137 加入后 orphan +1(soft warn 不阻 commit) |

### 禁止的 Context 操作

- ❌ 引入 NamedParameterJdbcTemplate `:name` 风格(F1 sub-D follow-up)
- ❌ 引入 RowMapper 泛型 callback(F2 sub-D,依赖 SS 泛型 D026/D027 落地)
- ❌ 引入 SqlParameterSource Map-based(F3 sub-D)
- ❌ 引入 batchUpdate / addBatch(范围外)
- ❌ 引入 generated keys retrieval / metadata API(D136 §核心原则 7 范围外)
- ❌ 改既有 5 method 签名(候选 B 废案,违反 §核心原则 2)
- ❌ 引入 builder fluent chain(候选 C 废案,Spring 文化分裂)
- ❌ tests/d135_caching_sha2/ 4 处 adminStmt DDL retcon(§核心原则 7)
- ❌ tests/d136_prepared_statement/ retcon(已直接走 prepared 接口)

---

## 2. Tool System

### 必备工具(已在环境中)

| 工具 | 用途 |
|---|---|
| `./build.sh bootstrap` | 三阶段固定点(每 Phase 后跑) |
| `bin/ss test tests/` | 全测 |
| `bin/ss test tests/d134_mysql/` | D134 e2e(8 case,Phase 3 后跑) |
| `bin/ss test tests/d135_caching_sha2/` | D135 e2e(4 case,Phase 1-4 baseline 不降) |
| `bin/ss test tests/d136_prepared_statement/` | D136 e2e(5 case,Phase 1-4 baseline 不降) |
| `docker compose up -d mysql8` | MySQL fixture |
| `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate(F1 死指针 = 0)|
| `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射,baseline 不动)|
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ vendor/jdbc / vendor/spring(纯 SS 实现 axiom)
- ❌ libssl / RSA_(D136 axiom 红线继承)
- ❌ Spring AOP / Spring DI / Spring Bean(范围外,Spring 7.0 子集仅 JdbcTemplate)

---

## 3. Execution Orchestration

### 总体节奏

5 Phase:
- Phase 0: 本文档落盘(本轮 Plan)
- Phase 1: lib/spring/jdbc.ss 5 method callback 重载实施(纯 lib 改)
- Phase 2: lib/spring/data.ss 11 处 JpaRepository CRUD retcon
- Phase 3: tests/d134_mysql/integration_test.ss 8 case 含动态值 retcon
- Phase 4: e2e 闭环 + D136 §F1 D138 编号冲突注释 + Status 收关

### Phase 详细

#### Phase 0: 本文档落盘(本轮 Plan)

- 本文档 落 Status `[ ]` → `[✓]` 当前 commit hash 回填
- 不动代码 / 测试
- d_doc_index_linter F1 = 0 验证(D137 加入后 referenced Ds 待 D138/D139 母决策落锚时引用)
- §After Done(simplify N/A 文档型 / commit / 下一步提示词)

#### Phase 1: lib/spring/jdbc.ss 5 method callback 重载实施(纯 lib 改)

- 加 5 重载:
  - `execute(sql: string, setter: fn): int` → prepareStatement + setter(stmt) + executeUpdate + close
  - `update(sql: string, setter: fn): int` → 同上
  - `queryForList(sql: string, setter: fn): ResultSet` → executeQuery,Connection 故意不关(streaming)
  - `queryForString(sql: string, setter: fn, column: string): string` → 复用 queryForList 重载 + getString
  - `queryForInt(sql: string, setter: fn, column: string): int` → 复用 queryForList 重载 + getInt
- 既有 5 method 保留(DDL / 无参数 SELECT 路径)
- LOC 估 ~60(jdbc.ss 5 重载 + 1 import 加 PreparedStatement)
- **GREEN**:
  - `./build.sh bootstrap` 三阶段固定点
  - `bin/ss test tests/d134_mysql/` 8 case 全绿(旧签名仍可用,Phase 3 才 retcon 调用方)
  - `bin/ss test tests/d135_caching_sha2/` 4 case 全绿(adminStmt DDL 走旧签名)
  - `bin/ss test tests/d136_prepared_statement/` 5 case 全绿(直走 driver 接口,与 Spring 层无关)
  - `grep -c "prepareStatement" lib/spring/jdbc.ss > 0` 当前 GREEN(Phase 1 落地)
- **早期 spike**:Phase 1 第一步实测 SS fn 多语句 lambda 体 — 写一个最小 callback `(s) => { s.setInt(1, 1); s.setString(2, "X"); s.setInt(3, 30) }` 编译 + 运行验证 GREEN(H1 假设挑战);失败回单语句 lambda 路径 + 用户分多次调 setter 范式

#### Phase 2: lib/spring/data.ss 11 处 JpaRepository CRUD retcon

- 11 处分类(§核心原则 4 元数据 vs 动态值):

  | line | method | 元数据(保留拼接) | 动态值(?化 + setter) |
  |---|---|---|---|
  | 26 | execute(sql) | (caller 传完整 SQL) | (无,DDL 路径用户自己控) |
  | 30 | save(values) | tableName + cols | values(待重设计为 setter callback)|
  | 34 | findAll() | columns + tableName | (无)|
  | 38 | findById(id) | columns + tableName | id(?化 + setInt)|
  | 42 | findByColumn(column, value: string) | columns + tableName + column | value(?化 + setString)|
  | 46 | findByColumnInt(column, value: int) | columns + tableName + column | value(?化 + setInt)|
  | 50 | existsById(id) | tableName | id(?化 + setInt)|
  | 54 | count() | tableName | (无)|
  | 58 | deleteById(id) | tableName | id(?化 + setInt)|
  | 62 | deleteAll() | tableName | (无)|
  | 66 | update(id, setClauses) | tableName | id + setClauses(待重设计为 setter callback,setClauses 内嵌动态值需挑出)|

- save / update 两 method 签名重设计(原签名 `save(values: string)` 把动态值预序列化字符串 — 反 prepared 主线;新签名 `save(setter: fn)` 接 callback,values 由 setter 内 setXxx 注入);其余 method 沿用 id / value 单参数,内部生成 callback
- 新增 JpaRepository 字段 `placeholders: string`(constructor 初始化为按 columns 数生成的 "?, ?, ?" 串),供 save/update INSERT/UPDATE 占位使用
- LOC 估 ~80(11 处全 retcon + JpaRepository 字段 + constructor 改)
- **GREEN**:
  - `./build.sh bootstrap` 三阶段固定点
  - `bin/ss test tests/` 全绿(包含 JpaRepository 调用测试,如 tests/d133_sqlite/)
  - `grep -cE '\$\{(id|value|setClauses|vals)\}' lib/spring/data.ss = 0`(所有动态值已 ?化)
  - 元数据拼接保留:`grep -cE '\$\{(this\.tableName|this\.columns|column|cols)\}' lib/spring/data.ss > 0`

#### Phase 3: tests/d134_mysql/integration_test.ss 8 case 含动态值 retcon

- 8 case 分类:
  - DDL `CREATE TABLE` / `DROP TABLE` / `DELETE FROM users`(无 WHERE)→ 旧签名保留(用户 const 字符串)
  - `INSERT INTO users VALUES (?, ?, ?)` + setter 路径 → 新签名
  - `SELECT ... WHERE id = ?` / `SELECT name FROM users WHERE id = ?` → 新签名
  - `DELETE FROM users WHERE id = ?` → 新签名
- LOC 估 ~50(8 case retcon)
- **GREEN**:
  - `bin/ss test tests/d134_mysql/` 8 case 全绿
  - `bin/ss test tests/d135_caching_sha2/` 4 case 全绿(不动)
  - `bin/ss test tests/d136_prepared_statement/` 5 case 全绿(不动)

#### Phase 4: e2e 闭环 + D136 §F1 D138 编号冲突注释 + Status 收关

- D137 §Status 全 `[✓]` 回填 commit hash
- D136 §F1 注释附加(指出 D138 编号双指 cache miss vs cross-module struct GEP,留 D 治理后续修正)
- d_doc_index_linter F1 = 0
- **GREEN**:
  - 三轨 RED 闭环(`grep -c "prepareStatement" lib/spring/jdbc.ss > 0` + `grep -cE '\$\{(id|value|setClauses|vals)\}' lib/spring/data.ss = 0` + tests/d134_mysql 8 case 全绿)
  - axiom 红线 grep / nm = 0 永久(D134 + D135 + D136 全继承)
  - d_doc_index_linter F1 = 0

### 反模式

- ❌ 边写 jdbc.ss 边改 data.ss 边改 tests(打包 commit,违反 §核心原则 8)
- ❌ 全 retcon 既有 5 method 签名(候选 B 废案,违反 §核心原则 2)
- ❌ 引入 builder fluent chain(候选 C 废案,违反 §核心原则 1 Spring 主线)
- ❌ 引入 NamedParameterJdbcTemplate / RowMapper / SqlParameterSource(F1-F3 范围外,违反 §核心原则 10)
- ❌ tests/d135_caching_sha2/ 4 处 adminStmt DDL retcon(违反 §核心原则 7)
- ❌ tests/d136_prepared_statement/ retcon(已直接走 prepared 接口,无需 Spring 层)
- ❌ 把元数据(tableName / columns / column 名)?化(MySQL 不允许 prepared statement ? 占位元数据,违反 §核心原则 4)
- ❌ Phase 2 跳过任意一处 spring/data.ss 11 处(违反 §核心原则 6 全迁完整性)
- ❌ 改既有 5 method 签名(候选 B 废案 + 违反 §核心原则 2)

---

## 4. State & Memory

### 编译时 state

- (PreparedStatement 接口已 D136 就绪,不需 bootstrap 改;SS fn 多语句 lambda 是 D134 既有能力)

### 运行时 state(driver 内部)

- statement_id per-prepare(PreparedStatement 内部,用户透明,D136 §Phase 1 落锚)
- per-call Connection lifecycle 不变(D134 §Phase 5 范式保留:每次重载方法开 + 关 Connection,无 pool;queryForList 故意不关供 streaming)
- JpaRepository 新增 placeholders 字段(constructor 初始化,只读)

### 中间产物

- 三候选评估矩阵(本 D §A.1)
- 隐藏假设挑战表(本 D §A.2,Plan 型 §④ 替换配套)
- spring/data.ss 11 处元数据 vs 动态值分类表(本 D §Phase 2 表格)

### 会话间持久化

- D137 §Phase 进度(clear 后续 Plan 锚,Status 行单一事实源)
- D136 §F1 注释附加 commit hash(Phase 4 回填)

### 禁止 state 操作

- ❌ 引入 ThreadLocal Connection(Spring JDBC 4.0+ 真有,本 D 范围外)
- ❌ 引入 schema cache / 跨 connection statement cache(D136 §核心原则 8 范围外继承)
- ❌ JpaRepository 字段无关引入(只加 placeholders,其他不动)

---

## 5. Evaluation & Observation

### 判据(每 Phase 完成必跑)

| # | 判据 | 命令 | 期望 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | 三阶段固定点 GREEN |
| 2 | spring/jdbc.ss prepared 接管 | `grep -c "prepareStatement" lib/spring/jdbc.ss` | Phase 1 后 > 0,Phase 2-4 维持 |
| 3 | spring/data.ss SQL 注入清零 | `grep -cE '\$\{(id\|value\|setClauses\|vals)\}' lib/spring/data.ss` | Phase 2 后 = 0 |
| 4 | spring/data.ss 元数据保留 | `grep -cE '\$\{(this\.tableName\|this\.columns\|column\|cols)\}' lib/spring/data.ss` | Phase 2 后 > 0(元数据合法拼接) |
| 5 | tests/d134_mysql 全绿 | `bin/ss test tests/d134_mysql/` | Phase 3 后 8 case 全绿 |
| 6 | tests/d135_caching_sha2 baseline | `bin/ss test tests/d135_caching_sha2/` | Phase 1-4 全程 4 case 全绿 |
| 7 | tests/d136_prepared_statement baseline | `bin/ss test tests/d136_prepared_statement/` | Phase 1-4 全程 5 case 全绿 |
| 8 | axiom 红线 | `grep -rn "libmysqlclient\|libssl\|RSA_\|EVP_PKEY" bootstrap/ lib/ build.sh \| wc -l` + `nm bin/ss \| grep -c -E "RSA_\|EVP_"` | 永久 = 0 |
| 9 | D 治理 | `bin/ss run tools/d_doc_index_linter.ss` | F1 死指针 = 0(D137 加入 orphan soft warn 不阻) |
| 10 | 反射 baseline | `bin/ss run tools/reflection_health_linter.ss` | 不升(本 D 不触反射) |

### 回归信号(任一出现 = 立即停下)

- ⚠ Phase 1 后 tests/d136_prepared_statement 5 case 任一红(driver 层被误改 — git revert)
- ⚠ Phase 2 后 spring/data.ss 元数据(tableName / columns / column)误 ?化(MySQL ER_PARSE_ERROR — 回 §核心原则 4)
- ⚠ Phase 3 后 tests/d134_mysql 8 case 任一红(callback 内 setter 调用错位 / 1-based vs 0-based 错)
- ⚠ tests/d135_caching_sha2 baseline 降(误改 adminStmt DDL — git revert)
- ⚠ axiom 红线 grep / nm 命中(libssl / RSA_ 误链)
- ⚠ d_doc_index_linter F1 BLOCK(死指针 — 修锚点引用)
- ⚠ 反射 baseline 升(本 D 不触反射,若升说明误改)
- ⚠ 既有 5 method 签名变(候选 B 废案路径 — 违反 §核心原则 2)
- ⚠ JpaRepository 引入字段超 placeholders(违反 §State 禁止 state 操作)

---

## 6. Constraints & Recovery

### 硬约束

- 不破既有 5 method 签名(§核心原则 2)
- 不动 bootstrap(§核心原则 9)
- 不动 D025 接口(§核心原则 11 不变量保留)
- 不引入 NamedParameterJdbcTemplate / RowMapper / SqlParameterSource / batchUpdate / generated keys / metadata API(§核心原则 10)
- 不动 tests/d135_caching_sha2/ + tests/d136_prepared_statement/(§核心原则 7)

### 风险锚(R1-R5)

| # | 风险 | 描述 | mitigation |
|---|---|---|---|
| R1 | SS fn 多语句 lambda 兼容性 | callback `(s) => { s.setInt(1, x); s.setString(2, y) }` 多语句 lambda 体是否正常 — D134 `withTransaction(db, fn)` 已实证 fn 类型,但需复测 callback 内 setter 多语句 | Phase 1 早期 spike 实测;失败回单语句 lambda + 用户分多次调 setter 范式(罕见,SS 已支持 block lambda)|
| R2 | PreparedStatement.close 重入 / Connection 双关 | 重载方法内部 stmt.close() + conn.close() 顺序;若 stmt.close 内部已释放 fd 资源,conn.close 重复释放致 use-after-free | Phase 1 显式顺序 stmt.close 先 + conn.close 后;lib/com/mysql/prepared.ss D136 已实现 close 仅发 COM_STMT_CLOSE 不关 fd(fd 由 Connection 拥有) |
| R3 | queryForList streaming socket 与 prepared cursor 兼容 | D136 prepared 是非流式(readBinaryResultSet 一次性读完),与 query.ss queryForList streaming 不同;queryForList 重载是否需要 ResultSet 兼容包装 | Phase 1 调研:实测 MysqlBinaryResultSet 是否支持 next() 流式接口(D025 ResultSet 接口契约);若不兼容,queryForList(sql, setter) 重载先实施"读完再返"语义,sub-D 评估 streaming 兼容 |
| R4 | spring/data.ss 元数据 vs 动态值分类完整性 | findByColumn 的 `${column}` 是元数据(用户 const 列名),不是 user-input value,误 ?化致 MySQL ER_PARSE_ERROR | Phase 2 grep 逐条标(元数据 / 动态值 二分);Phase 2 后判据 §3-4 grep 互补(动态值 = 0 + 元数据 > 0)交叉验证 |
| R5 | save / update 签名重设计致调用方破坏 | save 原签名 `save(values: string)` 把动态值预序列化字符串,新签名 `save(setter: fn)` 接 callback — 调用方必须改 | Phase 2 同 commit 内改 JpaRepository + 所有 save/update 调用方(tests/d133_sqlite/ / 业务层若有);grep 全调用方实测;**JpaRepository.save/update 签名破坏是 §核心原则 2 的局部例外**(JpaRepository 层不是 JdbcTemplate 5 method,§核心原则 2 仅约束 JdbcTemplate 不破签名,JpaRepository 重设计是 §核心目标 单一判据的硬性要求 — 元数据 vs 动态值正确分离需要 callback 接口) |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 build 失败 | git revert;调 fn 类型签名 + 检查 import PreparedStatement |
| Phase 1 SS fn 多语句 lambda 实测失败 | 单语句 lambda 路径 + sub-D 评估 SS lambda block 增强 |
| Phase 2 spring/data.ss 11 处任一红 | 回退该 method 单独 fix;grep 元数据 vs 动态值分类重做 |
| Phase 2 元数据误 ?化致 MySQL ER_PARSE_ERROR | git revert;回 §核心原则 4 重新分类 |
| Phase 3 tests/d134_mysql 8 case 任一红 | tcpdump 锁定 packet diff;检查 callback 内 setter 1-based index |
| Phase 3 tests/d135_caching_sha2 / tests/d136_prepared_statement baseline 降 | git revert(违反 §核心原则 7) |
| Phase 4 d_doc_index_linter F1 BLOCK | 修引用(D136 §F1 注释附加 commit hash 错位等) |

### 回滚策略

- 任一 Phase 失败 → `git reset --soft HEAD^` 回上一 Phase
- Phase 2 重设计 save/update 签名失败 → 回 callback 单独重载叠加(JpaRepository.save 旧 + JpaRepository.save_callback 新),保 §核心原则 2 字面字号(但本质上 callback 主线无法绕,接受局部破坏 R5)

---

## A.1 三候选评估矩阵(Plan 型 §④ 替换:替代方案对比)

| 维度 | 候选 A(callback 重载)★ 选 | 候选 B(全 retcon 签名) | 候选 C(builder 抽口) |
|---|---|---|---|
| 接口风格 | Spring 真 API 子集 PreparedStatementSetter | 重新设计 5 method 签名 | builder fluent chain(非 Spring) |
| LOC 估 | jdbc 60 + data 80 + tests 50 = **~190**(< 200 上限内,贴近边界) | jdbc 80 + data 90 + tests 80 + executeRaw 30 = **~280**(超 D136 §核心原则 9 上限) | jdbc 30 + data 60 + tests 30 = **~120**(最少) |
| 签名破坏 | **零**(重载叠加;JpaRepository.save/update 局部破坏是动态值 ?化的硬性要求,接受 R5)| **重**(JdbcTemplate 5 method + JpaRepository 11 处 + DDL 需新 executeRaw method + tests 24+ 处) | **零** |
| Spring 文化对齐 | **高**(JdbcTemplate 真 API callback) | 中(Spring 不强迫 callback,但破坏面爆) | 低(Spring 是 callback 不是 builder) |
| 类型安全 | 高(每 setXxx 强类) | 高 | 高 |
| spring/data.ss 11 处迁移 | 自然迁移(Phase 2 一次性) | 强制迁移(jdbc 签名变 → data 必须改) | 自愿迁移(易遗漏,长期维护成本累积) |
| DDL 路径处理 | 旧签名保留(无变动)| 需新 executeRaw method | 旧签名保留 |
| 根因解决度(SQL 注入根因 + Spring 层接管) | ★★★ | ★★★(但破坏面爆致实施风险) | ★(Spring 文化分裂 + 11 处不自动迁) |
| 第一性需求覆盖度(Spring 层接管业务路径) | 100%(spring/data.ss 11 处全迁) | 100%(强制迁) | 30-50%(自愿迁,易遗漏) |

**决策**:**选候选 A**

**理由**:
- **根因解决度 ≥ B**(同样 ★★★ Spring 主线,但 B 破坏面爆致实施风险跨 D 文档,违反 §交互式单文档 隔离精神)
- **第一性需求覆盖度 ≥ C**(100% vs 30-50%,C 自愿迁移性导致 spring/data.ss 11 处易遗漏,D136 ROI 拉满目标失)
- Spring JdbcTemplate 真 API 主线对齐(CLAUDE.md §Java/TS 语法优先)
- 零签名破坏(JpaRepository 局部破坏是动态值 ?化的硬性要求,§R5 接受)
- LOC < 200(D136 §核心原则 9 上限内)

**为何不选 B**:
- 签名破坏面跨 D134/D135/D136 测试 + spring/data.ss + DDL 需新 executeRaw method,跨 D 文档影响多,违反 §交互式单文档 隔离精神
- LOC ~280 超 D136 §核心原则 9 上限
- 实施风险高(24+ 处调用方强制改,任一处 callback 形成 / 元数据分类错位致 cascade 失败)
- **关键反驳**:候选 B 的"强制迁移"看似比 A 的"自然迁移"更彻底,但实施风险代价 vs 收益完全不成比例 — 与候选 A 同等覆盖度(100%)但 1.5x LOC + 跨 D 文档破坏面;按 CLAUDE.md §Root Cause"根因解决度 + 第一性需求覆盖度"排,A = B 同 ★★★,但 A 实施风险显著低 → 选 A

**为何不选 C**:
- Spring 文化分裂(callback vs builder 二选一,Spring 用户认知错位,违反 CLAUDE.md §Java/TS 语法优先)
- spring/data.ss 11 处不会自动迁移,需用户手工每处改写,长期累积维护成本反高
- 第一性需求覆盖度仅 30-50%(自愿迁移性 + 易遗漏)→ D136 ROI 拉满目标失
- **关键反驳**:候选 C 的"零签名破坏 + LOC 最少"看似最经济,但 CLAUDE.md §Root Cause 第一法则明示**禁按 LOC 最少 / 最快上线 排序**;C 第一性需求覆盖度低是质量缺陷,不是经济性优势

**废案**:
- E5(全 string Array<string> 序列化路径)— 类型信息丢失,反 binary protocol 加速 + 反 D136 §核心目标 binary 子集覆盖
- E6(N-ary type combination 静态重载族)— update_i / update_s / update_ii / update_si 等爆炸,JdbcTemplate 5 method × N-ary × type combo = 不可维护

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套)

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | SS fn 类型支持多语句 lambda body | 实施层失败 — callback 内多 setter 调用必须可以 | Phase 1 早期 spike 实测 `(s) => { s.setInt(1, 1); s.setString(2, "X"); s.setInt(3, 30) }` 编译 + 运行 GREEN | 单语句 lambda 路径 + sub-D 评估 SS lambda block 增强 |
| H2 | PreparedStatement.close 不重复 release Connection | 重复 close 致 fd leak / double-free | grep lib/com/mysql/prepared.ss 已实现 close 语义(D136 §Phase 2)+ Phase 1 重载方法内部 stmt.close 先 + conn.close 后顺序固定 | Phase 1 单元 test;失败 → fix prepared.ss close 语义 |
| H3 | queryForList 重载(streaming)与 prepared cursor(non-streaming)兼容 | D136 prepared 是非流式(readBinaryResultSet 一次性),与 query.ss queryForList streaming 不同;queryForList 重载可能需要 ResultSet 兼容包装 | Phase 1 调研:实测 MysqlBinaryResultSet 是否支持 next() 流式接口(D025 ResultSet 接口契约) | 若不兼容,queryForList(sql, setter) 重载先实施"读完再返"语义(MysqlBinaryResultSet 已就绪,D025 ResultSet next() 接口仅遍历缓存),sub-D 评估 streaming 兼容 |
| H4 | spring/data.ss 11 处 SQL 都能 ?化(无动态列名 / 动态表名 / 动态 SET clause) | findByColumn `WHERE ${column} = ?` 中 ${column} 是元数据(用户传 const),不需 ?化(MySQL 不允许 prepared statement ? 占位元数据);update setClauses 动态拼接是更复杂场景 | Phase 2 grep 逐条标分类(元数据 / 动态值);update 的 setClauses 重设计为多次 setter 调用 | 任一处分类错(元数据误 ?化)→ MySQL ER_PARSE_ERROR;判据 §3-4 grep 互补交叉验证 |
| H5 | tests/d135_caching_sha2/ 4 处 adminStmt.execute(DROP/CREATE/GRANT USER)不需 retcon | 这些是 DDL,用户 const 字符串(不接 user input),不在 SQL 注入面 | Phase 3 不动 d135 测试(§核心原则 7);adminStmt 走 MysqlStatement 文本协议 | 若误改 → tests/d135_caching_sha2 4 case 红,git revert |
| H6 | per-call Connection lifecycle(D134 §Phase 5)不变 | 重载方法每次开 + 关 Connection — Spring 真 API 也是这样除非 ThreadLocal | Phase 1 jdbc.ss code review 确认重载方法均 conn = DriverManager_getConnection + conn.close 配对 | 失败 → 回 D134 §Phase 5 范式 |
| H7 | SS fn 类型可作为 callback setter 传递 + capture outer scope 变量 | callback 必须能 capture `id`, `value` 等外层变量;D134 `withTransaction(db, fn)` 已实证 closure | Phase 1 早期 spike 实测 `(s) => { s.setInt(1, id) }` capture 外层 id 编译 + 运行 GREEN | 失败 → sub-D 评估 closure 增强 |

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | NamedParameterJdbcTemplate `:name` 命名参数 | sub-D 评估 — 命名参数风格 `WHERE id = :userId` 替代 `?` 占位,可读性提升;依赖 SS Map<string, value> 参数源(类似 SqlParameterSource);本 D 范围外 |
| F2 | RowMapper 泛型 callback | sub-D 评估 — `queryForObject(sql, RowMapper<T>, args)` 返自定义类;**强依赖 SS 泛型(D026 generic functions / D027 generic classes)落地**;本 D 范围外 |
| F3 | SqlParameterSource(Map<string, value>)Map-based parameter binding | sub-D 评估 — Map 参数源替代 callback;依赖 NamedParameterJdbcTemplate(F1);本 D 范围外 |
| F4 | D136 §F1 D138 编号冲突 | D136 §R4(line 362)写"留 D138 sub-follow-up handle" cache miss + D136 §F1(line 386)写"sub-D D138 cross-module struct GEP",D138 编号双指(cache miss vs cross-module struct GEP),需 D 治理后续修正(可能 D138 = cache miss / D140 = cross-module GEP);本 D Phase 4 仅在 D136 §F1 加注释指出冲突,**不动**编号(D 治理后续轮处理) |
| F5 | tests/d135_caching_sha2/ 4 处 adminStmt.execute DDL | DDL + 用户 const 字符串(不接 user input),不在 SQL 注入面,本 D 不 retcon;若未来 d135 测试新增动态值路径(罕见,d135 范围是 caching_sha2 认证不是 SQL 业务),再按 D137 范式 retcon |
| F6 | HikariCP D125+ Connection Pool | JdbcTemplate per-call Connection lifecycle 是 Phase 5 spec 接受的"无 pool 简化"(D134 §Phase 5 caveat 继承);queryForList 故意不关 Connection 的 leak 仍由 HikariCP D125+ 解决 |
| F7 | batchUpdate / addBatch / executeBatch | sub-D 评估 — 批量执行 API,依赖 prepared statement cache(D138 cache miss handle);本 D 范围外 |
| F8 | generated keys retrieval(getGeneratedKeys)| sub-D 评估 — INSERT 后取 auto-increment id,依赖 MySQL OK packet last_insert_id 字段(D134 已 parse);本 D 范围外 |
| F9 | SS lambda 参数类型推断 + interface dispatch 集成 bug | **Phase 2 实测发现**:`(s) => s.setInt(...)` 无类型注解时 SS interface method dispatch 走错路径(setInt 不写入 MysqlPreparedStatement.paramTypes/paramValues,prepared statement INSERT 全 result=-1);最小隔离 spike `/tmp/spike_lambda_typed.ss` 实证:加 `(s: PreparedStatement) => ...` 后 result=1,无类型注解 result=-1。**workaround**(本 D 已落):`lib/spring/data.ss` 6 处 lambda + `tests/d134_mysql` 2 处 lambda 全显式标 `(s: PreparedStatement) =>`,通过 Java 8+ explicit lambda type 风格规避(memory `feedback_no_derive_workaround` 不视作 fallback dead code — 类型注解是更类型安全的正向写法)。**真根因 sub-D follow-up**(编号待 D 治理后续轮处理,F4 D138 编号冲突独立):修 SS 编译器 lambda 参数类型推断 — 在 lambda 表达式作为 fn 调用实参时,从 fn 接收方的方法 body 内 setter(stmt) 调用上下文反推 lambda 参数类型 = 实际传入参数的静态类型(MysqlPreparedStatement 实现的 PreparedStatement 接口),从而 lambda body 内 `s.setInt(...)` method dispatch 通过 vtable 正确分派。本 D 范围外(§核心原则 9 bootstrap 隔离硬约束)|

---

## Phase 收关锚

### Phase 0: D 文档落盘 [✓] Done at commit `bafc25a` (2026-04-27)

- 本文档 Status [✓] Phase 0 落盘 at commit `bafc25a`
- d_doc_index_linter F1 = 0 验证 PASS(D137 加入未破 referenced Ds)
- next_prompt_ultrathink_linter PASS 3/3

### Phase 1: lib/spring/jdbc.ss 5 method callback 重载 [✓] Done at commit `d2df1ba` (2026-04-27)

- jdbc.ss +52/-1: execute(sql, setter) line 32 / update(sql, setter) line 51 / queryForList(sql, setter) line 73 / queryForString(sql, setter, column) line 90 / queryForInt(sql, setter, column) line 110
- import { PreparedStatement } from @/lib/java/sql 加(line 15)
- 既有 5 method 签名零破坏(§核心原则 2 持守)
- execute/update(sql, setter):prepareStatement + setter(stmt) + executeUpdate + stmt.close 先 + conn.close 后(R2 顺序)
- queryForList(sql, setter):故意不关 Connection(streaming,与旧 queryForList(sql) 同模式,sub-D HikariCP D125+ 解决,§核心原则 5)
- queryForString/queryForInt(sql, setter, column):复用 this.queryForList(sql, setter)(DRY,与旧无 setter 重载同模式)
- spike GREEN(/tmp/spike_lambda_multi.ss → 三 setter capture id=42/name=Alice → §A.2 H1+H7 双 PASS)
- VCM 六验:bootstrap 三阶段固定点 + tests/ 259/4/263 baseline 不降 + d134_mysql/5 + d135_caching_sha2/1 + d136_prepared_statement/1 全绿 + d_doc_index_linter GATE OK + reflection_health_linter GATE PASS no regressions
- prepareStatement count = 3(execute/update/queryForList 重载内主路径直接调,queryForString/queryForInt 复用 queryForList(sql, setter))→ 满足 §5 §Evaluation 第 2 判据 `> 0` SSoT
- simplify 采纳: 注释 #1 单行化(删 setInt/setString 例子,保 D 引用 + WHY); 拒绝: 无

### Phase 2: lib/spring/data.ss 11 处 JpaRepository CRUD retcon [✓] Done at commit `4c28bc0` (2026-04-27)

- data.ss +35/-0(77→112 行):11 处分类落地(§核心原则 4 元数据 vs 动态值)
  - **改 7 处 callback retcon**(动态值 ?化 + setter):save line 33 / findById line 44 / findBy line 51 / findByInt line 58 / existsById line 65 / deleteById line 77 / update line 91
  - **保留 4 处 metadata-only**(无动态值,§核心原则 4 合法路径):execute line 29 / findAll line 40 / count line 73 / deleteAll line 84
- **JpaRepository 字段扩**:`placeholders: string`(line 26)— constructor 4 参数位置(tableName / columns / jdbc / placeholders)
- **Factory 内部计算 placeholders**:`buildPlaceholders(columns: string)` line 101-106 通过 columns.split(",") + Array<string>.join(", ") 派生 "?, ?, ?";JpaRepositoryFactory_create line 108-112 调用注入到 4 参 constructor
- **save 签名重设计**(R5 局部破坏 §核心原则 2):`save(cols: string, vals: string)` → `save(setter: fn)` — 内部用 `this.columns + this.placeholders` 元数据派生 SQL `INSERT INTO ${this.tableName} (${this.columns}) VALUES (${this.placeholders})`
- **update 签名重设计**(R5 局部破坏 §核心原则 2):`update(id: int, setClauses: string)` → `update(setColumns: string, setter: fn)` — caller 写完整 "name=?, age=? WHERE id=?",setter 绑全部 ?(避免嵌套 lambda 复杂性,update 当前 0 调用方 grep 验证破坏面=0)
- **tests/d134_mysql/integration_test.ss line 145-160 retcon**:test 7 JpaRepository save callback 改 `(s: PreparedStatement) => { s.setInt(1, 30); s.setString(2, "Neo"); s.setInt(3, 32) }` 风格;import 加 PreparedStatement
- **三轨 RED 全 GREEN**:
  - `grep -cE '\$\{(id\|value\|setClauses\|vals)\}' lib/spring/data.ss` = 0(动态值 100% ?化)
  - `grep -cE '\$\{(this\.tableName\|this\.columns\|column\|cols)\}' lib/spring/data.ss` = 10(元数据合法保留 §核心原则 4)
  - `grep -c "prepareStatement\|setInt\|setString" lib/spring/data.ss` = 6(setter 调用就位)
- **VCM 六验**:bootstrap 三阶段固定点 + tests/ 259/4/263 baseline 不降 + d134_mysql 5/5 全绿 + d_doc_index_linter GATE OK + reflection_health_linter GATE PASS no regressions
- **F9 root cause 发现**(本 Phase 实施过程中暴露):lambda `(s) => s.setInt(...)` 无类型注解时 SS interface method dispatch 走错路径(setInt 静默不写入 paramTypes,executeUpdate 返 -1);最小隔离 spike `/tmp/spike_lambda_typed.ss` 实证 typed lambda result=1 / untyped lambda result=-1;**根 vs 表面分层**(PSM §字段 9 回写):
  - **根**(本 Phase 兑现):11 处 callback retcon = SQL 注入根因解决传递业务层(§第一性需求 末层 ✓);消除双轨制 = 文本协议(`stmt.execute(sql)`)vs prepared 协议(`stmt.setX + executeUpdate`)架构分立(D136 §A.5 + D137 §核心原则 1)
  - **表面 patch**:lambda 参数显式类型注解(JpaRepository 6 处 + tests 2 处)= 数据层 patch 规避 SS 编译器 lambda 类型推断 bug;**升根路径** = §F9 锚 sub-D 修编译器 lambda 参数类型推断 + interface dispatch 集成
- simplify 采纳: buildPlaceholders 用 Array<string>.join(", ") 替代 first==1 标志位手卷拼接(reuse agent: 14→5 行,符合 lib/regex.ss:393/439 join 范式);拒绝: lambda 参数显式注解 6 处 helper 抽取(quality agent: §F9 workaround 抽 helper 隐藏类型注解致 F9 修后难 grep 回收 + 单语句 callback 抽间接致可读性净亏)+ placeholders 字段缓存(efficiency agent: constructor 单算每次 save 复用,Spring SimpleJdbcInsert 同范式)+ update 2 参 vs 3 参(quality agent: §6.R5 Spring API 一一映射,setColumns 含 WHERE 是文档化决策)

### Phase 3: tests/d134_mysql/integration_test.ss 11 处含动态值 SQL retcon [✓] Done at commit `4a10e48` (2026-04-27)

- integration_test.ss +57/-19:11 处 callback retcon(§核心原则 1 + 6 全迁完整性)
  - **test 2 CRUD 5 处 prepareStatement 直驱**(line 74/81/92/98/106):INSERT(insStmt 三 setter)+ SELECT id,name,age(selRowStmt setInt)+ UPDATE(updStmt 双 setInt)+ SELECT age(selAgeStmt setInt)+ DELETE(delStmt setInt);每 stmt close 先 + conn.close 后(R2 顺序);ResultSet rs/rs2 close 在对应 stmt close 前
  - **test 3 transaction commit 1 处 INSERT prepared**(line 120):pstmt 三 setter(int + string + int)在 setAutoCommit(0) 后,executeUpdate + close,然后 conn.commit + conn.close
  - **test 4 transaction rollback 1 处 INSERT prepared**(line 137):同 test 3 但 conn.rollback,确认 binary protocol 在 rollback 路径正确(数据未持久化)
  - **test 7 JdbcTemplate 4 处走 Phase 1 callback 重载**(line 169/174/176/178):tmpl.update(sql, setter) + tmpl.queryForString(sql, setter, column) + tmpl.queryForInt(sql, setter, column) + tmpl.execute(sql, setter);全部 lambda 显式 `(s: PreparedStatement) =>`(§F9 持续应用)
- **Statement import 清理**:test 2 全 prepared 后 Statement type 不再使用,line 17 import 删除(reuse agent 隐含建议;Phase 2 留 Statement import 是 test 2 当时仍走 createStatement,Phase 3 retcon 后变成 dead import)
- **simplify 1 处采纳**:sel1Stmt/sel2Stmt 流水号命名 → selRowStmt/selAgeStmt 语义命名(quality agent:`memory/feedback_human_readable_code.md` 可读性 rubric b — "禁数字尾缀流水号气味";rename 反映 SQL 实际语义 — "SELECT id,name,age 全行" vs "SELECT age 单列");**拒绝**:全统一为 `pstmt`(原 quality 主建议:JS 同 scope `const` 重声明语义 SS 复刻不确定 + test 2 五 stmt 同 lambda scope 共存,语义命名比 `pstmt` 反复更清晰);其余 reuse / efficiency agent 均 0 finding(test 2 raw driver 路径是测试本意,JdbcTemplate 复用违反职责分离 + 5 round-trip 是 prepared 协议测试本意 + 资源关闭顺序 / round-trip 数 / 内存泄漏均无可优化)
- **三轨 RED 全 GREEN**:
  - `grep -cE "VALUES \([0-9]+, '" tests/d134_mysql/integration_test.ss` = 0(4 处 INSERT 字面量全 ?化)
  - `grep -cE "WHERE id = [0-9]" tests/d134_mysql/integration_test.ss` = 0(7 处 WHERE id literal 全 ?化)
  - `grep -c "prepareStatement" tests/d134_mysql/integration_test.ss` = 8(7 处直接 conn.prepareStatement + 1 处注释引用,test 2 五 stmt + test 3/4 各一)
  - `grep -cE "\.setInt|\.setString" tests/d134_mysql/integration_test.ss` = 26(setter 注入就位)
- **VCM 六验**:bootstrap 三阶段固定点 + tests/ 259/4/263 baseline 不降(与 Phase 1+2 完全一致 0 回归)+ d134_mysql 5/5 全绿 + d135_caching_sha2 1/1 baseline 不降 + d136_prepared_statement 1/1 baseline 不降 + axiom 红线 grep 0 + nm 0(永久维持)+ d_doc_index_linter F1 = 0 GATE OK + reflection_health_linter GATE PASS no regressions
- **§F9 workaround 持续**:test 7 4 处 lambda 显式 `(s: PreparedStatement)` 注解(承 Phase 2 6 处 + Phase 3 4 处 = 10 处累计);**真根因 sub-D follow-up** 编号待 D 治理后续轮处理(§F9 锚:修 SS 编译器 lambda 参数类型推断 + interface dispatch 集成 bug)
- **R3 streaming 兼容验证**:test 7 line 174/176 走 tmpl.queryForString/Int(sql, setter, column) 内部复用 queryForList(sql, setter)(jdbc.ss line 90-98 / 110-118),实证 D136 prepared 非流式 ResultSet 与 streaming socket 接口契约兼容(GREEN — H3 假设挑战 PASS)

### Phase 4: e2e 闭环 + D136 §F1 D138 编号冲突注释 + Status 收关 [✓] Done at commit `8e1c5de` (2026-04-27)

- **D136 §F1 注释段落附加**(D136-mysql-prepared-statement.md line 387 后):指出 §R4(line 362)+ §F1(line 386)双处引用 "D138" 但语义不同(§R4 = cache miss handle / §F1 = cross-module struct GEP),Phase 4 仅注释**不动编号**(承 D137 §F4 follow-up 锚 + D 治理后续轮处理候选编号方案);grep `D138.*编号|D138.*冲突` 命中 = 1 sanity check
- **D137 §Status 全 5 Phase 全 [✓]**:Phase 0 `bafc25a` + Phase 1 `d2df1ba` + Phase 2 `4c28bc0` + Phase 3 `4a10e48` + Phase 4 `8e1c5de`(本 commit hash 自指,docs commit message 含 hash,提交后 `git log` 索引 — Phase 0/1/2/3 同此模式 hash 提交后回填,避免 chicken-and-egg)
- **D137 §Phase 4 收关锚替换占位**(本段):落细 — D136 §F1 注释 commit + d_doc_index_linter F1 = 0 GATE OK + 三轨 RED 终态 GREEN(Phase 3 已实证维持)+ axiom 红线 grep 0 永久 + reflection baseline 维持 + tests/ 259/4/263 baseline 不降 + d134_mysql/d135/d136 全绿 baseline
- **D137 §全 Phase 收关锚替换占位**(line 487-489):4 Phase commit hash 全列 + JdbcTemplate 5 method callback 重载 + JpaRepository 11 处 callback retcon + tests/d134_mysql 11 处含动态值 SQL retcon + Spring 层 SQL 注入根因解决 100% 传递业务层 + D136 ROI 拉满 + §F9 + §F1-F8 follow-up 锚明确
- **三轨 RED 终态 GREEN 维持**(Phase 3 已落,Phase 4 不触代码,验证不动):
  - `grep -cE "VALUES \([0-9]+, '" tests/d134_mysql/integration_test.ss` = 0(4 处 INSERT 字面量全 ?化,Phase 3 已 GREEN)
  - `grep -cE "WHERE id = [0-9]" tests/d134_mysql/integration_test.ss` = 0(7 处 WHERE id literal 全 ?化,Phase 3 已 GREEN)
  - `grep -c "prepareStatement" tests/d134_mysql/integration_test.ss` = 8(test 2 五 stmt + test 3/4 各一 + 注释引用,Phase 3 已 GREEN)
  - `grep -c "prepareStatement" lib/spring/jdbc.ss` = 3(execute/update/queryForList 重载主路径,Phase 1 已 GREEN)
- **VCM 六验**(文档型 Phase,§4 无代码改 / §6 工程量极小):
  - ① bootstrap 三阶段固定点 — 仅 docs/ 改不动 bootstrap,自动维持(承 D135 line 487 / D136 line 614 文档型 Phase 范式)
  - ② tests/ 259/4/263 baseline 不降 — 仅 docs/ 改不动 tests
  - ③ d134_mysql 5/5 + d135_caching_sha2 1/1 + d136_prepared_statement 1/1 全绿维持
  - ④ axiom 红线 `grep -rn "libmysqlclient\|libssl\|RSA_\|EVP_PKEY" bootstrap/ lib/ build.sh | wc -l` = 0 + `nm bin/ss | grep -c -E "RSA_\|EVP_"` = 0 永久(D134 + D135 + D136 全继承)
  - ⑤ d_doc_index_linter F1 死指针 = 0 GATE OK(D136 §F1 注释段引用 D138 仍是字面 "D138",编号冲突注释指出待 D 治理修正,**不**新增死指针)
  - ⑥ reflection_health_linter GATE PASS no regressions(本 D 不触反射,baseline 不动)
- **simplify**:N/A 文档型(承 Phase 0 §After Done 范式 — D137 line 426 simplify N/A)
- **§F9 root cause sub-D 锚维持**:SS 编译器 lambda 参数类型推断 + interface dispatch 集成 bug — Phase 4 不修(§核心原则 9 bootstrap 隔离硬约束),sub-D 编号待 D 治理后续轮处理(F9 锚见 Followup 表 line 418 + 待 D 治理与 F4 D138 编号冲突一并处理)

---

## D137 全 Phase 收关锚

**Date:** 2026-04-27 (单日 5 Phase 闭环 — 范式延续 D135 line 487 / D136 line 614)

### 4 Phase commit hash 全锚

| Phase | Commit | 内容摘要 |
|---|---|---|
| Phase 0 | `bafc25a` | D 文档落盘(三候选评估 + §A.2 隐藏假设 H1-H7 + 11 Principles + Followup F1-F9 锚)|
| Phase 1 | `d2df1ba` | lib/spring/jdbc.ss 5 method callback 重载实施(jdbc.ss +52/-1: execute/update/queryForList/queryForString/queryForInt 5 重载 + import PreparedStatement)+ 既有 5 method 签名零破坏(§核心原则 2)+ R2 stmt.close 先 + conn.close 后 + R3 streaming 验证(queryForString/Int 复用 queryForList(sql, setter))|
| Phase 2 | `4c28bc0` | lib/spring/data.ss 11 处 JpaRepository CRUD retcon(7 改 callback retcon + 4 保留 metadata-only)+ JpaRepository 字段扩 placeholders + buildPlaceholders helper(Array<string>.join 复用 simplify 采纳)+ save/update 签名重设计(R5 局部破坏)+ tests/d134_mysql/integration_test.ss test 7 同 commit retcon + **§F9 root cause 发现**(SS lambda 类型推断 + interface dispatch 集成 bug)|
| Phase 3 | `4a10e48` | tests/d134_mysql/integration_test.ss 11 处含动态值 SQL retcon(test 2 CRUD 5 处 prepareStatement 直驱 + test 3/4 transaction commit/rollback 各 1 INSERT prepared + test 7 JdbcTemplate 4 处走 Phase 1 callback 重载)+ Statement import 清理(reuse agent)+ sel1/sel2 → selRow/selAge 语义命名(quality agent simplify 采纳)+ §F9 lambda 参数显式 (s: PreparedStatement) 注解持续 |
| Phase 4 | `8e1c5de` | e2e 闭环收关 + D136 §F1 D138 编号冲突注释 + D137 §Status 全 [✓] + §Phase 4 收关锚替换占位 + §全 Phase 收关锚替换占位为终态总结 |

### 兑现成果(§核心目标 单一判据)

- **OWASP top 10 #3 SQL 注入根因解决 100% 传递业务层** ✓ — D136 协议 / driver / 接口三层就绪 + Spring 层 JdbcTemplate 5 method callback 重载接管 + JpaRepository 11 处 CRUD 全走 prepared,业务路径 100% 受益(用户写 `repo.save(...)` / `repo.findById(...)` / `repo.update(...)` 全走 ?化 + setter 注入)
- **D136 ROI 拉满** ✓ — driver 层 binary protocol 加速传递到业务路径(JpaRepository CRUD 全 prepared)+ tests/d134_mysql 11 处含动态值 SQL 全 retcon(VALUES/WHERE id literal = 0 + prepareStatement = 8 + setter 注入 = 26)
- **Spring JdbcTemplate API 主线对齐** ✓ — Spring 7.0 真 API callback 风格(PreparedStatementSetter)+ 既有 5 method 签名零破坏(DDL `CREATE TABLE` / `DROP TABLE` / `SET autocommit` 走旧路径)
- **D136 §核心原则 9 defer 锚兑现** ✓ — Phase 3 LOC 评估 ~190 < 200 上限内 + 候选 A 路径走 callback 重载叠加(零签名破坏除 R5 JpaRepository 局部例外)
- **三轨 RED 终态 GREEN** ✓ — §第一性需求 末层 grep 命中 + spring/data.ss 动态值 ?化 100% + tests/d134_mysql 11 处含动态值 SQL retcon 100%
- **axiom 红线** ✓ — libmysqlclient / libssl / RSA_ / EVP_PKEY grep / nm = 0 永久(D134 + D135 + D136 全继承)
- **测试 baseline** ✓ — tests/ 259/4/263 全 Phase 不降 + d134_mysql 5/5 + d135_caching_sha2 1/1 + d136_prepared_statement 1/1 全绿维持
- **D 治理 gate** ✓ — d_doc_index_linter F1 死指针 = 0(D136 §F1 D138 编号冲突注释指出但不动编号,F1 持守)
- **反射 baseline** ✓ — reflection_health_linter GATE PASS no regressions(本 D 不触反射)
- **bootstrap 隔离** ✓ — 全 5 Phase 仅改 lib/ + tests/ + docs/,不动 bootstrap(§核心原则 9 硬约束)

### Followup 锚明确(留 sub-D 后续轮)

| # | 锚 | 状态 | 触发条件 |
|---|---|---|---|
| F1 | NamedParameterJdbcTemplate `:name` 命名参数 | sub-D 待评估 | 业务层需可读性提升时 |
| F2 | RowMapper 泛型 callback | sub-D 待评估 | **强依赖 SS 泛型(D026/D027)落地**,不在本轮范围 |
| F3 | SqlParameterSource(Map<string, value>) | sub-D 待评估 | 依赖 F1 NamedParameterJdbcTemplate |
| F4 | D136 §F1 D138 编号冲突 | **本 Phase 4 已加注释** | D 治理后续轮选定 D138 真归属 + 另一引用 retcon 新编号 |
| F5 | tests/d135_caching_sha2/ 4 处 adminStmt DDL | 不 retcon | DDL + 用户 const,不在 SQL 注入面 |
| F6 | HikariCP D125+ Connection Pool | sub-D 待评估 | per-call Connection lifecycle 简化的 leak 长期解决 |
| F7 | batchUpdate / addBatch / executeBatch | sub-D 待评估 | 依赖 D138(cache miss handle 取 §R4 候选)|
| F8 | generated keys retrieval | sub-D 待评估 | INSERT 后取 auto-increment id |
| F9 | SS lambda 参数类型推断 + interface dispatch 集成 bug | **Phase 2 实证发现** | 修 SS 编译器 — lambda 表达式作 fn 实参时,从 fn 接收方方法 body 内 setter(stmt) 调用上下文反推 lambda 参数类型;workaround 已落(10 处 lambda 显式 `(s: PreparedStatement)` 注解,Phase 2 6 处 + Phase 3 4 处);sub-D 编号待 D 治理后续轮 |

### 范式延续(D135/D136 → D137 → 后续)

- 5 Phase 边界 = commit 边界(D134 §Principles 7 + D135 §Principles 9 + D136 §Principles 11 + D137 §Principles 8 一脉相承)
- §M PSM 九问 + §N VCM 六验(`docs/3-MNK.md` 单一事实源)
- 文档型 Phase simplify N/A 范式(D137 Phase 0 line 426 + Phase 4 line 481+ 同模式)
- §核心原则 9 bootstrap 隔离硬约束(D135/D136/D137 三 D 文档继承)
- D 治理 gate F1 死指针 = 0 永久(d_doc_index_linter SSoT)
- §Followup 锚明确(F1-F9)+ 候选 sub-D 编号待 D 治理后续轮(F4 D138 编号冲突 + F9 SS 编译器 lambda 类型推断)
