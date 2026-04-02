// spring-jdbc:7.0 — JdbcTemplate (SimpleScript Implementation)
// Simplified JdbcTemplate for common SQL operations.

import { Connection, ResultSet, rsNext, stmtExecuteQuery, stmtExecuteUpdate } from "@/lib/java/sql"

// ── JdbcTemplate ─────────────────────────────────────────────

class JdbcTemplate {
    dbHandle: string

    function execute(sql: string): int {
        return stmtExecuteUpdate(this.dbHandle, sql)
    }

    function update(sql: string): int {
        return stmtExecuteUpdate(this.dbHandle, sql)
    }

    function queryForList(sql: string): ResultSet {
        return stmtExecuteQuery(this.dbHandle, sql)
    }

    function queryForString(sql: string, column: string): string {
        const rs = stmtExecuteQuery(this.dbHandle, sql)
        if (rs.next() == 1) { return rs.getString(column) }
        return ""
    }

    function queryForInt(sql: string, column: string): int {
        const rs = stmtExecuteQuery(this.dbHandle, sql)
        if (rs.next() == 1) { return rs.getInt(column) }
        return 0
    }
}

// ── Transaction helper ───────────────────────────────────────

function withTransaction(db: string, fn: fn): int {
    stmtExecuteUpdate(db, "BEGIN")
    try {
        fn()
        stmtExecuteUpdate(db, "COMMIT")
        return 0
    } catch (e) {
        stmtExecuteUpdate(db, "ROLLBACK")
        println(`transaction rolled back: ${e}`)
        return 1
    }
}
