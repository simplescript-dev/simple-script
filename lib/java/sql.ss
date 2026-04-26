// java.sql — JDBC 4.3 Core Interfaces (driver-agnostic)
// Mirrors: java.sql.Connection, Statement, ResultSet, DriverManager
//
// This file declares the JDBC abstraction (interfaces) and dispatches
// DriverManager_getConnection by URL scheme. Concrete drivers
// (e.g. MySQL wire protocol, future SQLite-pure-SS / PostgreSQL) provide
// implementations under lib/com/<vendor>/jdbc.ss.
//
// D133: SQLite C link removed — interfaces hold no driver-specific shape.
// D134: MySQL wire-protocol driver registered (jdbc:mysql://). The cycle
// jdbc.ss ↔ sql.ss is handled by bootstrap/main.ss resolveInner visited set.
// See docs/3-decisions/D133-sqlite-c-link-elimination.md
// See docs/3-decisions/D134-jdbc-mysql-wire-protocol.md §A.5

// ── ResultSet ────────────────────────────────────────────────
// Driver controls internal row storage (socket buffer / pre-fetch /
// streaming cursor). Callers iterate via next() and column getters.

interface ResultSet {
    function next(): int
    function getString(col: string): string
    function getInt(col: string): int
    function getLong(col: string): int
    function getDouble(col: string): double
    function getBoolean(col: string): int
    function close()
}

// ── Statement ────────────────────────────────────────────────

interface Statement {
    function executeQuery(sql: string): ResultSet
    function executeUpdate(sql: string): int
    function execute(sql: string): int
    function close()
}

// ── Connection ───────────────────────────────────────────────

interface Connection {
    function createStatement(): Statement
    function setAutoCommit(auto: int)
    function commit()
    function rollback()
    function close()
    function isClosed(): int
}

// ── DriverManager ────────────────────────────────────────────
// D134 §A.5: hardcoded scheme dispatch. Future drivers add an else-if branch.

import { getMysqlConnection } from "@/lib/com/mysql/jdbc"

class DriverManager

function DriverManager_getConnection(url: string): Connection {
    if (url.startsWith("jdbc:mysql://") == 1) {
        return getMysqlConnection(url)
    }
    println(`JDBC: no driver registered for url: ${url}`)
    exit(1)
}
