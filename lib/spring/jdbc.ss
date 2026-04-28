// spring-jdbc:7.0 — JdbcTemplate. D134 Phase 5: real driver wiring.
//
// JdbcTemplate dispatches every call through DriverManager_getConnection(url).
// Per-call Connection lifecycle is managed at this layer (open + close around
// each method); ResultSet returned by queryForList aliases the underlying
// socket — caller must call ResultSet.close() before the next query on the
// same JdbcTemplate or the socket buffer will desync.
//
// withTransaction wraps fn() with setAutoCommit(0) + commit/rollback gating
// on fn's int return (0 = success → commit; nonzero = error → rollback).
//
// See docs/3-decisions/D133-sqlite-c-link-elimination.md
// See docs/3-decisions/D134-jdbc-mysql-wire-protocol.md §3 §Phase 5
// See docs/3-decisions/D138-mysql-generated-keys.md §Phase 3 (KeyHolder)

import { Connection, ResultSet, PreparedStatement, DriverManager_getConnection, RETURN_GENERATED_KEYS } from "@/lib/java/sql"

// ── KeyHolder ────────────────────────────────────────────────
// D138 Phase 3 — Spring KeyHolder standard. JdbcTemplate.update(sql, setter,
// keyHolder) populates keyHolder.getKeyList() with one Map<string,int> per
// generated row (column name "GENERATED_KEY" — MySQL Connector/J convention).
// getKey / getKeyAsLong return the single int from the first row (most common
// path for AUTO_INCREMENT INSERT). getKeys returns the first row Map for the
// rare multi-column generated-keys case (kept as Spring spec parity even
// though MySQL only generates one column today).
//
// Mirrors org.springframework.jdbc.support.KeyHolder. SS Map<string,int>
// constrains values to int (the only generated-key shape MySQL emits) — Spring's
// Map<String,Object> is not modelable until SS gains a top-type.

interface KeyHolder {
    function getKey(): int
    function getKeyAsLong(): int
    function getKeys(): Map<string, int>
    function getKeyList(): Array<Map<string, int>>
}

class GeneratedKeyHolder : KeyHolder {
    keyList: Array<Map<string, int>>

    function getKey(): int {
        if (this.keyList.length() == 0) { return 0 }
        return this.keyList[0].get("GENERATED_KEY")
    }

    function getKeyAsLong(): int {
        return this.getKey()
    }

    function getKeys(): Map<string, int> {
        if (this.keyList.length() == 0) { return new Map() }
        return this.keyList[0]
    }

    function getKeyList(): Array<Map<string, int>> {
        return this.keyList
    }
}

// ── JdbcTemplate ─────────────────────────────────────────────

class JdbcTemplate {
    url: string

    function execute(sql: string): int {
        const conn = DriverManager_getConnection(this.url)
        const stmt = conn.createStatement()
        const r = stmt.execute(sql)
        stmt.close()
        conn.close()
        return r
    }

    // D137 Phase 1: PreparedStatementSetter callback — setter binds positional params before executeUpdate fires.
    function execute(sql: string, setter: fn(PreparedStatement):void): int {
        const conn = DriverManager_getConnection(this.url)
        const stmt = conn.prepareStatement(sql)
        setter(stmt)
        const r = stmt.executeUpdate()
        stmt.close()
        conn.close()
        return r
    }

    function update(sql: string): int {
        const conn = DriverManager_getConnection(this.url)
        const stmt = conn.createStatement()
        const r = stmt.executeUpdate(sql)
        stmt.close()
        conn.close()
        return r
    }

    function update(sql: string, setter: fn(PreparedStatement):void): int {
        const conn = DriverManager_getConnection(this.url)
        const stmt = conn.prepareStatement(sql)
        setter(stmt)
        const r = stmt.executeUpdate()
        stmt.close()
        conn.close()
        return r
    }

    // D138 Phase 3 — Spring KeyHolder INSERT path. Per-call Connection
    // (HikariCP D125+ sub-D for pooling).
    function update(sql: string, setter: fn(PreparedStatement):void, keyHolder: KeyHolder): int {
        const conn = DriverManager_getConnection(this.url)
        const stmt = conn.prepareStatement(sql, RETURN_GENERATED_KEYS)
        setter(stmt)
        const r = stmt.executeUpdate()
        const list = keyHolder.getKeyList()
        const rs = stmt.getGeneratedKeys()
        while (rs.next() == 1) {
            let row: Map<string, int> = new Map()
            row.set("GENERATED_KEY", rs.getInt("GENERATED_KEY"))
            list.push(row)
        }
        rs.close()
        stmt.close()
        conn.close()
        return r
    }

    // ResultSet streams rows from the underlying socket — caller must call
    // rs.close() before issuing another query on the same url, and the
    // Connection leaks until then. Sub-D (HikariCP D125+) introduces pooling.
    function queryForList(sql: string): ResultSet {
        const conn = DriverManager_getConnection(this.url)
        const stmt = conn.createStatement()
        return stmt.executeQuery(sql)
    }

    // Same streaming semantics as queryForList(sql) — the Connection leaks
    // until rs.close(); PreparedStatement.close() releases the server-side
    // statement handle but the fd is owned by the caller via the leaked conn.
    function queryForList(sql: string, setter: fn(PreparedStatement):void): ResultSet {
        const conn = DriverManager_getConnection(this.url)
        const stmt = conn.prepareStatement(sql)
        setter(stmt)
        return stmt.executeQuery()
    }

    function queryForString(sql: string, column: string): string {
        const rs = this.queryForList(sql)
        let v = ""
        if (rs.next() == 1) {
            v = rs.getString(column)
        }
        rs.close()
        return v
    }

    function queryForString(sql: string, setter: fn(PreparedStatement):void, column: string): string {
        const rs = this.queryForList(sql, setter)
        let v = ""
        if (rs.next() == 1) {
            v = rs.getString(column)
        }
        rs.close()
        return v
    }

    function queryForInt(sql: string, column: string): int {
        const rs = this.queryForList(sql)
        let v = 0
        if (rs.next() == 1) {
            v = rs.getInt(column)
        }
        rs.close()
        return v
    }

    function queryForInt(sql: string, setter: fn(PreparedStatement):void, column: string): int {
        const rs = this.queryForList(sql, setter)
        let v = 0
        if (rs.next() == 1) {
            v = rs.getInt(column)
        }
        rs.close()
        return v
    }
}

// ── Transaction helper ───────────────────────────────────────
// Opens a Connection, disables autocommit, runs fn(), and commits if fn returns
// 0 / rolls back otherwise. Returns fn's return value.

function withTransaction(db: string, fn: fn): int {
    const conn = DriverManager_getConnection(db)
    conn.setAutoCommit(0)
    const r = fn()
    if (r == 0) {
        conn.commit()
    } else {
        conn.rollback()
    }
    conn.close()
    return r
}
