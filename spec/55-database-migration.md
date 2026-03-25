# 55 - Database Migration (数据库迁移)

## 设计理念

> 数据库 schema 版本化管理。来自 Flyway/Liquibase 的思路，但用 SimpleScript 代码而非 SQL/XML。

## 安装

```bash
ym add yummy/db-migrate
```

## 定义迁移

```simplescript
import { Migration, CreateTable, AddColumn, DropColumn, AddIndex } from "yummy/db-migrate"

// 每个迁移类有版本号和 up/down 方法
class V001_CreateUsers : Migration {
    override const version = "001"
    override const description = "create users table"

    override function up(db: MigrationDb) {
        db.createTable("users", (t) => {
            t.id()                                    // bigint 自增主键
            t.string("name", length: 100)
            t.string("email", length: 200, unique: true)
            t.integer("age")
            t.boolean("active", default: true)
            t.timestamps()                            // created_at, updated_at
        })
    }

    override function down(db: MigrationDb) {
        db.dropTable("users")
    }
}

class V002_CreateOrders : Migration {
    override const version = "002"
    override const description = "create orders table"

    override function up(db: MigrationDb) {
        db.createTable("orders", (t) => {
            t.id()
            t.bigint("user_id")
            t.decimal("amount", precision: 10, scale: 2)
            t.string("status", length: 20, default: "pending")
            t.timestamps()
            t.foreignKey("user_id", references: "users", column: "id")
        })

        db.addIndex("orders", "user_id")
    }

    override function down(db: MigrationDb) {
        db.dropTable("orders")
    }
}

class V003_AddUserPhone : Migration {
    override const version = "003"
    override const description = "add phone column to users"

    override function up(db: MigrationDb) {
        db.addColumn("users", "phone", "string", length: 20, nullable: true)
        db.addIndex("users", "phone", unique: true)
    }

    override function down(db: MigrationDb) {
        db.dropIndex("users", "phone")
        db.dropColumn("users", "phone")
    }
}
```

## 运行迁移

```bash
# 执行所有未执行的迁移
ym run migrate up

# 回滚上一次迁移
ym run migrate down

# 回滚到指定版本
ym run migrate down --to 001

# 查看迁移状态
ym run migrate status

# 输出:
# Version  Description          Status     Applied At
# 001      create users table   Applied    2026-03-20 10:00:00
# 002      create orders table  Applied    2026-03-21 14:30:00
# 003      add phone to users   Pending    -
```

## 生成 SQL (不执行)

```bash
# 只生成 SQL，不执行 (DBA 审核用)
ym run migrate preview

# 输出:
# -- Migration V003: add phone column to users
# ALTER TABLE users ADD COLUMN phone VARCHAR(20);
# CREATE UNIQUE INDEX idx_users_phone ON users(phone);
```

## 原生 SQL 迁移

```simplescript
// 复杂迁移可以直接写 SQL
class V004_ComplexMigration : Migration {
    override const version = "004"
    override const description = "complex data migration"

    override function up(db: MigrationDb) {
        db.executeSql(`
            INSERT INTO user_profiles (user_id, display_name)
            SELECT id, name FROM users
            WHERE NOT EXISTS (
                SELECT 1 FROM user_profiles WHERE user_profiles.user_id = users.id
            )
        `)
    }

    override function down(db: MigrationDb) {
        db.executeSql("DELETE FROM user_profiles")
    }
}
```

## 种子数据

```simplescript
import { Seed } from "yummy/db-migrate"

class UserSeed : Seed {
    override function run(db: MigrationDb) {
        db.insert("users", Map.of(
            ["name", "admin"],
            ["email", "admin@example.com"],
            ["age", 0],
            ["active", true]
        ))
    }
}
```

```bash
# 执行种子数据
ym run migrate seed
```
