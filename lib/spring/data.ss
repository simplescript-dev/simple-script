// spring-data-jpa:2025.1 — JpaRepository (D133 Phase 5 placeholder)
// CRUD over JDBC via JdbcTemplate. Each repository operates on a single table.
// D133: SQLite C link removed; factory delegates to placeholder JdbcTemplate
// until D134 (JDBC MySQL wire protocol) lands a concrete driver.
// See docs/3-decisions/D133-sqlite-c-link-elimination.md

import { Connection, ResultSet, DriverManager } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"

// ── JpaRepository ────────────────────────────────────────────
// Usage (D134 ready 后接入):
//   const repo = JpaRepositoryFactory.create("jdbc:mysql://host:3306/db", "users", "id,name,age")
//   repo.execute("CREATE TABLE users (...)")
//   repo.findAll() → ResultSet
//   repo.findById(1) → ResultSet
// 当前(D133 Phase 5):JdbcTemplate placeholder,任何 CRUD 调用 println + exit(1)

class JpaRepository {
    tableName: string
    columns: string
    jdbc: JdbcTemplate


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
    println(`JpaRepositoryFactory.create: no driver registered (D133), see D134 — url: ${url}`)
    exit(1)
}
