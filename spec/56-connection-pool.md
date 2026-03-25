# 56 - Connection Pool & Database (连接池与数据库)

## 设计理念

> 数据库连接池是标准库内置功能。自动管理连接生命周期，防止泄漏。

## 配置

```yaml
# application.yml
database:
  driver: postgres
  url: "postgres://localhost:5432/mydb"
  username: myuser
  password: mypass
  pool:
    min: 5
    max: 20
    idleTimeout: 300000        # 空闲 5 分钟回收
    maxLifetime: 1800000       # 连接最长存活 30 分钟
    connectionTimeout: 5000    # 获取连接超时 5 秒
```

## 基本使用

```simplescript
import { Database } from "dev/db"

// 连接 (自动创建连接池)
const db = Database.connect("postgres://localhost/mydb")

// 查询
const users = db.query<User>("SELECT * FROM users WHERE age > $1", 18)

// 单条查询
const user = db.queryOne<User>("SELECT * FROM users WHERE id = $1", 1)

// 执行 (INSERT/UPDATE/DELETE)
const affected = db.execute("UPDATE users SET active = $1 WHERE id = $2", true, 1)

// 插入并返回
const newUser = db.insert<User>("INSERT INTO users (name, age) VALUES ($1, $2) RETURNING *", "Alice", 30)
```

## 事务

```simplescript
// 手动事务
const result = db.transaction((tx) => {
    tx.execute("UPDATE accounts SET balance = balance - $1 WHERE id = $2", 100, fromId)
    tx.execute("UPDATE accounts SET balance = balance + $1 WHERE id = $2", 100, toId)
    return Result.Ok(())
    // 正常返回 → commit
    // 返回 Err 或 panic → rollback
})

// 注解事务 (推荐)
import { Transactional } from "dev/db/tx"

@Service
class TransferService(db: Database) {

    @Transactional
    function transfer(fromId: long, toId: long, amount: double): Result<void, Error> {
        db.execute("UPDATE accounts SET balance = balance - $1 WHERE id = $2", amount, fromId)?
        db.execute("UPDATE accounts SET balance = balance + $1 WHERE id = $2", amount, toId)?
        return Result.Ok(())
    }
}
```

## 多数据源

```yaml
# application.yml
databases:
  primary:
    driver: postgres
    url: "postgres://primary-host/mydb"
  readonly:
    driver: postgres
    url: "postgres://readonly-host/mydb"
  analytics:
    driver: sqlite
    url: "file:analytics.db"
```

```simplescript
import { Database, DataSource } from "dev/db"

@Service
class ReportService(
    @DataSource("primary") db: Database,
    @DataSource("readonly") readDb: Database,
    @DataSource("analytics") analyticsDb: Database
) {
    function getReport(): Report {
        const users = readDb.query<User>("SELECT * FROM users")
        analyticsDb.execute("INSERT INTO reports ...")
        return generateReport(users)
    }
}
```

## 连接池监控

```simplescript
import { Database } from "dev/db"

const stats = db.poolStats()
println(`active: ${stats.activeConnections}`)
println(`idle: ${stats.idleConnections}`)
println(`total: ${stats.totalConnections}`)
println(`waiting: ${stats.waitingThreads}`)
```

## 支持的数据库

```
postgres    PostgreSQL 12+
mysql       MySQL 8.0+ / MariaDB 10.5+
sqlite      SQLite 3.35+
```
