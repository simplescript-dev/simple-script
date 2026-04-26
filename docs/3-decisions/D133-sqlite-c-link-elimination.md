# D133: SQLite C 链路彻底剥离 + lib/java/sql driver-agnostic 重构

**Status:** Phase 1 Done at `lib/java/sql.ss:1-55` — Phase 2 待 Execute
**Depends on:**
- CLAUDE.md §项目本质 L7 axiom("应用层 stdlib 用纯 SS 模块实现,不引入应用层 C 库;只有底层基础设施(mimalloc 分配器)允许链接 C")
- CLAUDE.md §项目技术规则 §Root Cause 优先 L101-103("第一法则,无例外")
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优理由)
- `memory/feedback_no_derive_workaround.md`(承认 axiom 例外 = workaround)
- `docs/3-MNK.md` §M PSM 九问 / §N VCM 六验

**是 D134(JDBC MySQL wire protocol)的 hard prereq** — D134 必须等本 D 全 Phase GREEN 后才能起立

**Date:** 2026-04-26
**Last Updated:** 2026-04-26

---

## 第一性需求

CLAUDE.md §项目本质字面承诺:**"应用层 stdlib 用纯 SS 模块实现,不引入应用层 C 库"**。

但 lib/java/sql.ss 当前实现违反:
- `gen_runtime.ss:133-142` 有 10 行 `declare i32 @sqlite3_*` LLVM ABI declare
- `gen/rt/gen_rt_system.ss:319-end` 有 `emitRuntimeSQLite()` 实现 `ss_sqlite3_open/close/exec/query` thin wrapper 直调 SQLite C API
- `bootstrap/main.ss:611-617` 链接命令静态链入 `vendor/sqlite3.o`
- `lib/java/sql.ss:157` `Connection.close() { ss_sqlite3_close(this.dbHandle) }` 接口绑死 SQLite-shape

**axiom 文字 vs 实现物理状态机械可验证矛盾**(grep `sqlite3_` ≥ 10 处)。

**单一判据**(机械):
```bash
grep -rn "ss_sqlite3\|sqlite3_\|sqliteObj\|vendor/sqlite\|jdbc:sqlite" \
    bootstrap/ lib/ build.sh | wc -l
# 当前 = 46,目标 = 0

nm bin/ss | grep -c sqlite3_
# 当前 ≥ 10,目标 = 0(自举二进制无 SQLite 符号)
```

---

## 核心目标 (Goal)

- **为什么**:axiom 文字承诺 vs lib/ 实现物理矛盾持续。任何后续 wire-protocol 数据库 driver(MySQL/Postgres/Redis)若在 SQLite-shape 接口之上扩,Java 生态分层 L1 物理断裂(必须新建 `lib/db/mysql/Connection` 平行 `lib/java/sql.Connection`,产生**两条 JDBC 风路径**)
- **是什么**:删 SQLite C link 全栈(declare + define + registry + link line + vendor/sqlite3.o);重构 `lib/java/sql.ss` 把 `Connection`/`Statement`/`ResultSet`/`DriverManager` 抽成 driver-agnostic 接口,具体实现交给 driver(本 D 范围**不实现任何 driver**,留 D134 MySQL 接入)
- **单一判据**:`grep -rn "ss_sqlite3\|sqlite3_\|sqliteObj" bootstrap/ lib/ build.sh | wc -l = 0` + `nm bin/ss | grep -c sqlite3_ = 0` + `./build.sh bootstrap` 三阶段固定点 stage2==stage3 + `bin/ss test tests/` 全绿(已弃用 SQLite 的 tests / examples 在本 D Phase 5 列锚转 D134)

> 口号:**axiom 不是文字,是 grep 输出**。文字承诺与 grep 一致 = axiom 兑现;不一致 = axiom 持续违反。

---

## 核心原则 (Principles)

1. **根因优先,无例外** — feedback_root_cause_no_cost:不允许"SQLite 没 wire protocol 替代,允许 axiom 例外"绕路。axiom 字面 = 应用层 stdlib 不引入 C 库,SQLite 是应用层 C 库,违反 = 修
2. **接口与实现强分离** — `lib/java/sql.ss` 重构为纯接口(`Connection`/`Statement`/`ResultSet` 抽 interface 或 abstract class),具体实现归 driver(本 D 不出 driver,只出接口)
3. **dbHandle:string SQLite-shape 必删** — 当前 `Connection.dbHandle:string` 是 SQLite handle,不能让 MySQL driver 继承(MySQL 需要 socket fd + state machine,不是 string)
4. **string-based ResultSet 必删** — 当前 `ResultSet` 内部 `data:string` + `"col1\tcol2\nval1\tval2\n"` 编码是 SQLite-shape 序列化决策,driver-agnostic 接口要求 ResultSet 由 driver 自己实现行迭代
5. **本 D 不引入新 driver** — D134 MySQL wire protocol 是 follow-up,本 D 范围只做接口抽离 + C link 删除。Phase 5 验证后 lib/java/sql.ss 处于"接口齐全无实现"状态
6. **examples / tests 中 SQLite 用例不修复** — 让其编译失败暴露 dependent 路径,在本 D 附录 A.5 列锚清单,Phase 5 commit message 显式声明"等 D134 MySQL ready 后转用"
7. **Phase 边界 = commit 边界** — 6 个 Phase 各自独立 commit,禁打包

---

## 1. Context Management(上下文管理)

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D133)
2. `CLAUDE.md` §项目本质 + §项目技术规则 §Root Cause 优先
3. `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验 + §大改档位规则
4. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/gen/gen_runtime.ss` | 133-142 | SQLite ABI declare(全段删) |
   | `bootstrap/gen/rt/gen_rt_system.ss` | 319-end `emitRuntimeSQLite()` | SQLite C wrapper(全段删 + dispatcher 调用点删) |
   | `bootstrap/gen/gen_registry.ss` | 128-129 | `ss_sqlite3_*` funcRetTypes(删) |
   | `bootstrap/main.ss` | 611-617 | sqliteObj link 逻辑(删) |
   | `lib/java/sql.ss` | 1-216 全文 | driver-agnostic 接口重构(改) |
   | `lib/spring/jdbc.ss` | 1-49 | import lib/java/sql,内容不动(检查依赖) |
   | `lib/spring/data.ss` | 1-77 | import lib/java/sql,L11 SQLite-specific 注释删 |
   | `lib/spring/boot/jpa.ss` | 1-14 | `sqlite:./data.db` default url 改 placeholder |
   | `lib/com/zaxxer/hikari.ss` | 1-37 | import lib/java/sql,L17 SQLite 注释更新 |
   | `lib/jakarta/sql.ss` | 1-23 | DataSource 接口,import 检查 |
   | `docs/guide.md` | 1343,1356 | SQLite 用户文档段(暂撤) |

### Stable Facts

| 项 | 值 |
|---|---|
| 当前 axiom 状态 | 持续违反(grep 命中 = 46) |
| 自举状态 | 自举完成,固定点验证通过(memory project_bootstrap_status) |
| 测试基线 | `bin/ss test tests/` 全绿(commit 1797bee) |
| 入口命令 | `./build.sh bootstrap` 三阶段固定点 |

### 禁止的 Context 操作

- ❌ 不读 SQLite C 源码 / 文档(本 D 范围是删,不是理解 SQLite)
- ❌ 不读 MySQL wire protocol(D134 范围,跨层)

---

## 2. Tool System

### 必备工具(已在环境中)

| 类别 | 工具 | 用途 |
|---|---|---|
| Claude 内置 | Read / Edit / Write / Bash | 文件操作 |
| 项目专属 | `./build.sh bootstrap` | 三阶段固定点验证 |
| 项目专属 | `bin/ss test tests/` | 全测试集 |
| 项目专属 | `nm bin/ss \| grep -c sqlite3_` | 二进制符号扫描 |
| linter | `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate(死指针 / 孤立) |
| linter | `bin/ss run tools/reflection_health_linter.ss` | 反射根因 metrics(本 D 不触反射,baseline 不动) |

### 禁止引入

- ❌ 任何新 C 库(本 D 是删 C 链,不是加)
- ❌ 任何新 build flag

---

## 3. Execution Orchestration

### 总体节奏

- 6 Phase 各自独立 commit + bootstrap 固定点 + 全测试验证 = 硬约束
- 禁"边删边重构边加 driver"

### Phase 详细

#### Phase 0: 本文档落盘(本轮 Plan)

- 本 D 文档骨架 + PSM 九问 + 决策细节 + 实施日志骨架
- **验证**:用户审阅 D 文档措辞 OK 后下轮 Execute Phase 1

#### Phase 1: lib/java/sql.ss driver-agnostic 接口重构

- 改 `Connection` / `Statement` / `ResultSet` 为接口(interface or abstract,SS 当前 interface 形态见 D025)
- 删 `Connection.close() { ss_sqlite3_close(...) }` 直调
- 删 `dbHandle:string` SQLite-shape;改 `Connection` 接口持有 driver-specific state(留接口字段不绑实现)
- 改 `ResultSet`:删内部 `data:string` + `rsGetValue` 字符串切割实现,改成接口 `next()` / `getString(col)` / `getInt(col)` 等方法签名;具体实现归 driver
- `DriverManager_getConnection(url)` 改为 url 协议分派 stub(本 D 不实现任何分派 case,Phase 5 留 placeholder error message)
- **验证**:`./build.sh bootstrap` 编译过(可以编译失败的是后续 Phase 删 SQLite 实现后,本 Phase 仅改接口)+ 接口签名稳定

#### Phase 2: bootstrap SQLite declare/define/registry 删除

- 删 `gen/gen_runtime.ss:133-142` 10 行 `declare i32 @sqlite3_*`
- 删 `gen/rt/gen_rt_system.ss:319-end` `emitRuntimeSQLite()` 函数 + dispatcher 调用点(grep 找 emitRuntimeSQLite 调用)
- 删 `gen/gen_registry.ss:128-129` `ss_sqlite3_*` funcRetTypes
- **验证**:bootstrap 第一阶段编译过(可能 stage2/3 有问题,Phase 4 验证)

#### Phase 3: link line + vendor/sqlite3.o 删除

- 删 `bootstrap/main.ss:611-617` `sqliteObj` 块(`fileExists("vendor/sqlite3.o")` 检查 + 链接拼接)
- `rm vendor/sqlite3.o`(若存在)
- **验证**:`bin/ss build examples/web_demo.ss -o /tmp/wd && nm /tmp/wd | grep -c sqlite3_ = 0`

#### Phase 4: 三阶段固定点验证

- `./build.sh bootstrap` seed → stage1 → stage2 → stage3
- stage2 == stage3 byte-identical
- **验证**:固定点通过 = bootstrap 编译器不再依赖 SQLite

#### Phase 5: 依赖 lib + 文档更新 + 断裂清单

- `lib/spring/data.ss:11` 注释 `sqlite::memory:` 删
- `lib/spring/boot/jpa.ss:6` `sqlite:./data.db` default url 改 placeholder(or `unset` + Phase 6 全测验证)
- `lib/com/zaxxer/hikari.ss:17` 注释 "For SQLite" 更新
- `docs/guide.md:1343,1356` SQLite 用户文档段撤(留 "数据库支持等待 D134 MySQL 接入")
- grep 全仓库 `jdbc:sqlite\|sqlite::memory\|@/lib/java/sql` 用例 → 列断裂清单到本 D §附录 A.5
- **验证**:Phase 5 commit message 显式声明断裂清单 + "转 D134"

#### Phase 6: 全测试 + RED → 0

- `bin/ss test tests/` 全绿(已弃用 SQLite 的 tests 在 §附录 A.5 列锚 + 跳过 / 标记 D134-pending)
- RED 命令:`grep -rn "ss_sqlite3\|sqlite3_\|sqliteObj\|vendor/sqlite\|jdbc:sqlite" bootstrap/ lib/ build.sh | wc -l = 0`
- `nm bin/ss | grep -c sqlite3_ = 0`
- 三轨闭环 GREEN

### 反模式

- ❌ 边删 SQLite 边加 MySQL driver(跨层,违反 §字段 8;D134 工作)
- ❌ 跳过 Phase 4 固定点验证直接进 Phase 5(bootstrap 状态污染)
- ❌ 修复 examples / tests 中 SQLite 用例(本 D 范围外;Phase 5 列锚 + 转 D134)

---

## 4. State & Memory

### 编译时 state

| 变量 | 文件 | 角色 |
|---|---|---|
| `funcRetTypes` | `bootstrap/gen/gen_registry.ss:128-129` | `ss_sqlite3_*` 类型注册(删) |
| `sqliteObj` | `bootstrap/main.ss:612` | link path string(删) |
| `dbHandle` | `lib/java/sql.ss` Connection class | SQLite handle string(删 / 改 driver-specific) |

### 中间产物

- `vendor/sqlite3.o`(若存在,Phase 3 删)
- bootstrap stage1/2/3 二进制(Phase 4 固定点比对)

### 会话间持久化

- `git log` — Phase 1-6 commit 边界 = 进度锚
- 本文档 — 唯一 D133 状态记录
- `bin/ss test tests/` 测试集

### 禁止 state 操作

- ❌ 把跨 Phase 进度写到 .claude/next_prompt.md 累积
- ❌ amend 已 push commit
- ❌ 写 sqlite_removal_log.md / analysis.md 这类分析文件入仓

---

## 5. Evaluation & Observation

### 判据(每 Phase 完成必跑)

| # | 类型 | 命令 | 通过条件 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | 三阶段固定点 stage2==stage3 |
| 2 | 测试 | `bin/ss test tests/` | 全绿(SQLite-pending 测试在 §附录 A.5 列锚) |
| 3 | RED 收敛 | `grep -rn "ss_sqlite3\|sqlite3_\|sqliteObj\|vendor/sqlite\|jdbc:sqlite" bootstrap/ lib/ build.sh \| wc -l` | = 0 |
| 4 | 二进制扫 | `nm bin/ss \| grep -c sqlite3_` | = 0 |
| 5 | D 治理 | `bin/ss run tools/d_doc_index_linter.ss` | F1 死指针 = 0 |
| 6 | 反射 baseline | `bin/ss run tools/reflection_health_linter.ss` | 不升 |

### 回归信号(任一出现 = 立即停下)

- ⚠ stage2 ≠ stage3(固定点漂)
- ⚠ `bin/ss test tests/` 出现 SQLite 无关测试新红
- ⚠ `nm bin/ss | grep sqlite3_` 命中 ≥ 1(C 链路未删干净)

---

## 6. Constraints & Recovery

### 硬约束

- **不允许 axiom 例外** — feedback_root_cause_no_cost
- **不允许跨层** — 不在本 D 实现 MySQL driver(D134 工作)
- **不允许打包 commit** — 6 Phase 各自独立 commit

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 4 固定点 stage2 ≠ stage3 | `git reset --hard HEAD~N` 回 Phase 1,确认接口重构未引入 nondeterminism |
| Phase 6 RED grep ≥ 1 | grep 输出 → 看哪行漏删 → Edit 修 → 回 Phase 6 验证 |
| `bin/ss test tests/` SQLite 无关测试新红 | 检查 Phase 1 接口重构是否破其他 lib/ 路径(grep `import.*lib/java/sql`) |

### 回滚策略

- 任一 Phase 失败 → `git reset --soft HEAD^` 回上一 Phase
- 跨 Phase 回滚需先和用户确认(Phase 边界 = 稳定锚点)

---

# 附录 A: 决策细节

## A.1 SQLite C link 现状清单(grep 实测)

| 文件 | 行号 | 内容 |
|---|---|---|
| `bootstrap/gen/gen_registry.ss` | 128-129 | `funcRetTypes.set("ss_sqlite3_query","string")` / `..._open","string")` |
| `bootstrap/gen/gen_runtime.ss` | 133-142 | 10 行 `declare i32 @sqlite3_*` LLVM ABI |
| `bootstrap/gen/rt/gen_rt_system.ss` | 320-end(`emitRuntimeSQLite`) | `ss_sqlite3_*` thin wrapper define |
| `bootstrap/main.ss` | 611-617 | sqliteObj link line |
| `lib/java/sql.ss` | 全文 216 行 | SQLite-shape 接口 + ss_sqlite3_* 直调 |
| `lib/spring/data.ss` | 11 | 注释 `sqlite::memory:` |
| `lib/spring/boot/jpa.ss` | 6 | `let defaultDbUrl = "sqlite:./data.db"` |

## A.2 lib/java/sql.ss 接口重构后形态(Phase 1 目标)

```ss
// java.sql — JDBC 4.3 Core Interfaces (driver-agnostic)
// Drivers register implementations; this file holds **only** interfaces.

interface ResultSet {
    function next(): int
    function getString(col: string): string
    function getInt(col: string): int
    function getLong(col: string): int
    function getDouble(col: string): double
    function getBoolean(col: string): int
    function close()
}

interface Statement {
    function executeQuery(sql: string): ResultSet
    function executeUpdate(sql: string): int
    function execute(sql: string): int
    function close()
}

interface Connection {
    function createStatement(): Statement
    function setAutoCommit(auto: int)
    function commit()
    function rollback()
    function close()
    function isClosed(): int
}

class DriverManager
function DriverManager_getConnection(url: string): Connection {
    // Phase 1: 暂返 placeholder error,具体协议分派由 driver 注册
    println(`JDBC: no driver registered for url: ${url}`)
    exit(1)
}
```

注:SS interface 形态见 D025;Phase 1 实测后若 SS interface 不支持 inheritance / default method 则降级为 abstract class + 强制方法。

## A.3 ResultSet 重构 — 抛弃 string-based 内部存储

旧实现(SQLite-shape):
```ss
class ResultSet {
    data: string  // "col1\tcol2\nval1\tval2\n"
    columns: string
    rowCount: int
    currentRow: int
    function getString(col): string { return rsGetValue(this.data, ...) }
}
```

新接口(driver-agnostic):
```ss
interface ResultSet {
    function next(): int       // 移到下一行,有行返 1 无行返 0
    function getString(col: string): string
    // ... driver 自己实现行迭代,内部状态自由(socket buffer / pre-fetch / streaming)
}
```

driver 实现细节:
- D134 MySQL `class MysqlResultSet : ResultSet` 持有 socket fd + 预取 row buffer + col 元数据
- 若未来加 SQLite-pure-SS driver(数万 LOC,D???-future),`class SqliteResultSet : ResultSet` 持有 file handle + B-tree cursor

## A.4 link line 重构(main.ss:611-617 → 删 sqliteObj 段)

旧:
```ss
let sqliteObj = ""
if (fileExists("vendor/sqlite3.o") == 1) { sqliteObj = "vendor/sqlite3.o" }
if (fileExists("../vendor/sqlite3.o") == 1) { sqliteObj = "../vendor/sqlite3.o" }
// ...
if (system(`musl-gcc ${linkFlags} ${objFile} ${rtObj} ${mimallocObj} ${sqliteObj} -o ${outputFile} -lm`) != 0) {
```

新:
```ss
if (system(`musl-gcc ${linkFlags} ${objFile} ${rtObj} ${mimallocObj} -o ${outputFile} -lm`) != 0) {
```

## A.5 examples / tests / docs 断裂清单(Phase 5 列锚)

**待 Phase 1 启动后用 `grep -rn "@/lib/java/sql\|jdbc:sqlite\|sqlite::memory" tests/ examples/ docs/`** 实际产出,本附录 A.5 留位 Phase 5 commit message 引用。

预期断裂源:
- `lib/spring/boot/jpa.ss:6` default url 用 SQLite — 改 placeholder
- `lib/spring/data.ss:11` 注释 SQLite 例 — 改 MySQL placeholder 或撤
- `docs/guide.md:1343,1356` 用户文档 SQLite 例段 — 撤段并加 "见 D134 MySQL 接入" placeholder
- 其他 examples / tests **未知,Phase 5 grep 列锚**

转 D134 的处理:本 D 不修复,Phase 5 commit message 写"以下断裂等 D134 MySQL ready 后转用,本 D 范围内允许编译失败"。

## A.6 与 mimalloc C 链路的区别

mimalloc 是 axiom 例外(底层基础设施允许),SQLite 不是。区别:
- mimalloc = 内存分配器,SS 自身需要(对象布局 / RC 系统)— **基础设施**
- SQLite = 应用层数据库 client — **应用层 stdlib**(等同 HTTP/JSON 之类)

axiom 字面区分清晰,本 D 不挑战 axiom,只兑现 axiom。

---

# 附录 B: 实施日志

### Phase 0: D 文档落盘 [⏳]

- 本轮 PSM 九问填表
- D133 文档骨架完成
- 等用户审阅措辞 OK 后下轮起 Phase 1

### Phase 1: lib/java/sql.ss 接口重构 [✅ Done]

- 改动:`lib/java/sql.ss` 重写 216 行 → 55 行(driver-agnostic 接口契约)
- ResultSet / Statement / Connection 全部 `class` → `interface`,删 `data:string` / `dbHandle:string` / `currentRow:int` / `rowCount:int` / `columns:string` 等 SQLite-shape 字段
- 删 `ss_sqlite3_close` 直调(原 Connection.close() body)
- 删 `ss_sqlite3_open` / `ss_sqlite3_query` / `ss_sqlite3_exec` 直调(原 stmtExecuteQuery/stmtExecuteUpdate/DriverManager_getConnection body)
- 删 `rsGetValue` 字符串切割实现(48 行)+ `rsNext` (3 行) + `stmtExecuteQuery` (21 行) + `stmtExecuteUpdate` (3 行)
- `DriverManager_getConnection(url)` 改 placeholder `println + exit(1)`(check_return.ss:23 已注册 exit() 为 noreturn,无需 return 占位)
- **RED 验证**:`grep -nE "ss_sqlite3|dbHandle:\s*string|^class (Connection|Statement|ResultSet)" lib/java/sql.ss | wc -l` = 0(原 15)
- **GREEN 验证**:`./build.sh bootstrap` 三阶段固定点 stage2 == stage3 通过(超出 Phase 1 标准的 stage1 编译过 — 因 bootstrap 编译器自身不依赖 lib/java/sql,故接口改动对 bootstrap 路径零冲击)
- **依赖破裂确认**(R2 风险锚兑现,Phase 5 修复):
  - `lib/spring/jdbc.ss:4` import `rsNext, stmtExecuteQuery, stmtExecuteUpdate` 已破(三函数全删)
  - `lib/spring/data.ss:5` 同上 + `:75` `conn.dbHandle` 字段访问已破(Connection interface 无字段)
  - `lib/com/zaxxer/hikari.ss:24` `this.conn.close()` 接口方法调用 OK(无破)
  - `lib/jakarta/sql.ss` import `Connection, DriverManager` OK(无破)
  - 上述破裂 Phase 5 集中修复(转 placeholder / 暂撤,等 D134 ready)
- **不变量保留**:D018(对象布局)/ D022(clone 语义)/ D025(interface dispatch)/ D088 / D123 / D130-132 不动,mimalloc C link axiom 例外保留

### Phase 2: bootstrap SQLite declare/define/registry 删除 [待 Execute]

(待回填)

### Phase 3: link line + vendor/sqlite3.o 删除 [待 Execute]

(待回填)

### Phase 4: 三阶段固定点验证 [待 Execute]

(待回填)

### Phase 5: 依赖 lib + 文档更新 + 断裂清单 [待 Execute]

(待回填)

### Phase 6: 全测试 + RED → 0 [待 Execute]

(待回填)

---

## 反模式 / 正模式

### ❌ 反模式

- "SQLite 没 wire protocol 替代,允许 axiom 例外" — feedback_root_cause_no_cost 禁
- "边删 SQLite 边加 MySQL driver" — 跨层(D134 工作)
- "修复 examples / tests 中 SQLite 用例" — 本 D 范围外,Phase 5 列锚转 D134
- "打包 6 Phase 一次 commit" — 违反 §大改档位

### ✅ 正模式

- "axiom 不是文字是 grep 输出" — 三轨闭环 grep + nm + bootstrap 固定点
- "接口与实现强分离" — Phase 1 抽 interface,driver 留 D134
- "Phase 边界 = commit 边界" — 6 Phase 各自独立 + 各自验证

---

## 参考

- CLAUDE.md §项目本质 L7 axiom
- CLAUDE.md §项目技术规则 §Root Cause 优先 L101-103
- `memory/feedback_root_cause_no_cost.md`
- `memory/feedback_no_derive_workaround.md`
- `docs/3-MNK.md` §M PSM 九问 / §N VCM 六验
- D018(对象布局)/ D022(clone 语义)— 不变量保留
- D025(Interface Dispatch)— Phase 1 接口形态依据
- D134(JDBC MySQL wire protocol)— follow-up,等本 D 全 Phase GREEN 后起立
