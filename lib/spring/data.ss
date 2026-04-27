// spring-data-jpa:2025.1 — JpaRepository.
// CRUD over JDBC via JdbcTemplate. Each repository operates on a single table.
// D134 Phase 5: factory body — JpaRepositoryFactory_create wires a
// JdbcTemplate(url) into a JpaRepository(table, columns, jdbc, placeholders).
// D137 Phase 2: PreparedStatementSetter callback retcon — dynamic values
// (id / value / save row / setColumns binding) bound via setter; metadata
// (tableName / columns / column name) stay as template interpolation (MySQL
// forbids ? placeholders for table/column names — see §核心原则 4).
// See docs/3-decisions/D137-jdbctemplate-prepared-retcon.md §Phase 2

import { Connection, ResultSet, PreparedStatement, DriverManager } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"

// ── JpaRepository ────────────────────────────────────────────
// Usage:
//   const repo = JpaRepositoryFactory_create("jdbc:mysql://host:3306/db", "users", "id,name,age")
//   repo.execute("CREATE TABLE users (...)")
//   repo.findAll() → ResultSet
//   repo.findById(1) → ResultSet
//   repo.save((s) => { s.setInt(1, 1); s.setString(2, "Alice"); s.setInt(3, 30) })

class JpaRepository {
    tableName: string
    columns: string
    jdbc: JdbcTemplate
    placeholders: string


    function execute(sql: string): int {
        return this.jdbc.execute(sql)
    }

    function save(setter: fn(PreparedStatement):void): int {
        return this.jdbc.update(
            `INSERT INTO ${this.tableName} (${this.columns}) VALUES (${this.placeholders})`,
            setter
        )
    }

    function findAll(): ResultSet {
        return this.jdbc.queryForList(`SELECT ${this.columns} FROM ${this.tableName}`)
    }

    function findById(id: int): ResultSet {
        return this.jdbc.queryForList(
            `SELECT ${this.columns} FROM ${this.tableName} WHERE id = ?`,
            (stmt: PreparedStatement) => { stmt.setInt(1, id) }
        )
    }

    function findBy(column: string, value: string): ResultSet {
        return this.jdbc.queryForList(
            `SELECT ${this.columns} FROM ${this.tableName} WHERE ${column} = ?`,
            (stmt: PreparedStatement) => { stmt.setString(1, value) }
        )
    }

    function findByInt(column: string, value: int): ResultSet {
        return this.jdbc.queryForList(
            `SELECT ${this.columns} FROM ${this.tableName} WHERE ${column} = ?`,
            (stmt: PreparedStatement) => { stmt.setInt(1, value) }
        )
    }

    function existsById(id: int): int {
        return this.jdbc.queryForInt(
            `SELECT COUNT(*) as cnt FROM ${this.tableName} WHERE id = ?`,
            (stmt: PreparedStatement) => { stmt.setInt(1, id) },
            "cnt"
        ) > 0 ? 1 : 0
    }

    function count(): int {
        return this.jdbc.queryForInt(`SELECT COUNT(*) as cnt FROM ${this.tableName}`, "cnt")
    }

    function deleteById(id: int): int {
        return this.jdbc.update(
            `DELETE FROM ${this.tableName} WHERE id = ?`,
            (stmt: PreparedStatement) => { stmt.setInt(1, id) }
        )
    }

    function deleteAll(): int {
        return this.jdbc.update(`DELETE FROM ${this.tableName}`)
    }

    // setColumns is the full SET ... WHERE ... clause with ? placeholders;
    // setter binds every ? including the WHERE-side id. Mirrors Spring 7.0
    // JdbcTemplate.update(sql, setter) — no internal id fixup.
    function update(setColumns: string, setter: fn(PreparedStatement):void): int {
        return this.jdbc.update(`UPDATE ${this.tableName} SET ${setColumns}`, setter)
    }
}

// ── Factory (static method) ──────────────────────────────────

class JpaRepositoryFactory

// "id,name,age" → "?, ?, ?" for INSERT ... VALUES placeholder substitution.
function buildPlaceholders(columns: string): string {
    const parts = columns.split(",")
    let qs: Array<string> = []
    for (p in parts) { qs = qs.push("?") }
    return qs.join(", ")
}

function JpaRepositoryFactory_create(url: string, tableName: string, columns: string): JpaRepository {
    const jdbc = new JdbcTemplate(url)
    const placeholders = buildPlaceholders(columns)
    return new JpaRepository(tableName, columns, jdbc, placeholders)
}
