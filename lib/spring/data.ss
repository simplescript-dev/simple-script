// spring-data-jpa:2025.1 — JpaRepository (SimpleScript Implementation)
// Compile-time CRUD over SQLite via JdbcTemplate.
// Each repository operates on a single table.

import { Connection, ResultSet, rsNext, stmtExecuteQuery, stmtExecuteUpdate, DriverManager } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"

// ── JpaRepository ────────────────────────────────────────────
// Usage:
//   const repo = JpaRepository.create("sqlite::memory:", "users", "id,name,age")
//   repo.execute("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER)")
//   repo.save("name,age", "'Alice',30")
//   repo.findAll() → ResultSet
//   repo.findById(1) → ResultSet
//   repo.deleteById(1)
//   repo.count() → int

class JpaRepository(tableName: string, columns: string, jdbc: JdbcTemplate) {

    function execute(sql: string): int {
        return this.jdbc.execute(sql)
    }

    function save(cols: string, vals: string): int {
        return this.jdbc.update(`INSERT INTO ${this.tableName} (${cols}) VALUES (${vals})`)
    }

    function findAll(): ResultSet {
        return this.jdbc.queryForList(`SELECT ${this.columns} FROM ${this.tableName}`)
    }

    function findById(id: int): ResultSet {
        return this.jdbc.queryForList(`SELECT ${this.columns} FROM ${this.tableName} WHERE id = ${id}`)
    }

    function findBy(column: string, value: string): ResultSet {
        return this.jdbc.queryForList(`SELECT ${this.columns} FROM ${this.tableName} WHERE ${column} = '${value}'`)
    }

    function findByInt(column: string, value: int): ResultSet {
        return this.jdbc.queryForList(`SELECT ${this.columns} FROM ${this.tableName} WHERE ${column} = ${value}`)
    }

    function existsById(id: int): int {
        return this.jdbc.queryForInt(`SELECT COUNT(*) as cnt FROM ${this.tableName} WHERE id = ${id}`, "cnt") > 0 ? 1 : 0
    }

    function count(): int {
        return this.jdbc.queryForInt(`SELECT COUNT(*) as cnt FROM ${this.tableName}`, "cnt")
    }

    function deleteById(id: int): int {
        return this.jdbc.update(`DELETE FROM ${this.tableName} WHERE id = ${id}`)
    }

    function deleteAll(): int {
        return this.jdbc.update(`DELETE FROM ${this.tableName}`)
    }

    function update(id: int, setClauses: string): int {
        return this.jdbc.update(`UPDATE ${this.tableName} SET ${setClauses} WHERE id = ${id}`)
    }
}

// ── Factory (static method) ──────────────────────────────────

class JpaRepositoryFactory

function JpaRepositoryFactory_create(url: string, tableName: string, columns: string): JpaRepository {
    const conn = DriverManager.getConnection(url)
    const jdbc = new JdbcTemplate(conn.dbHandle)
    return new JpaRepository(tableName, columns, jdbc)
}
