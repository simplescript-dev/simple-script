// spring-jdbc:7.0 — JdbcTemplate (D133 Phase 5 placeholder)
// D133: SQLite C link removed; JdbcTemplate now placeholder until D134
// (JDBC MySQL wire protocol) lands a concrete driver.
// See docs/3-decisions/D133-sqlite-c-link-elimination.md

import { ResultSet } from "@/lib/java/sql"

// ── JdbcTemplate ─────────────────────────────────────────────

class JdbcTemplate {
    url: string

    function execute(sql: string): int {
        println(`JdbcTemplate.execute: no driver registered (D133), see D134 — sql: ${sql}`)
        exit(1)
    }

    function update(sql: string): int {
        println(`JdbcTemplate.update: no driver registered (D133), see D134 — sql: ${sql}`)
        exit(1)
    }

    function queryForList(sql: string): ResultSet {
        println(`JdbcTemplate.queryForList: no driver registered (D133), see D134 — sql: ${sql}`)
        exit(1)
    }

    function queryForString(sql: string, column: string): string {
        println(`JdbcTemplate.queryForString: no driver registered (D133), see D134 — sql: ${sql}`)
        exit(1)
    }

    function queryForInt(sql: string, column: string): int {
        println(`JdbcTemplate.queryForInt: no driver registered (D133), see D134 — sql: ${sql}`)
        exit(1)
    }
}

// ── Transaction helper ───────────────────────────────────────

function withTransaction(db: string, fn: fn): int {
    println(`withTransaction: no driver registered (D133), see D134`)
    exit(1)
}
