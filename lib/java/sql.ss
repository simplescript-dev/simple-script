// java.sql — JDBC 4.3 Core Interfaces (driver-agnostic)
// Mirrors: java.sql.Connection, Statement, ResultSet, DriverManager
//
// This file declares **only** the JDBC abstraction. Concrete drivers
// (e.g. MySQL wire protocol, future SQLite-pure-SS) provide implementations
// and register themselves with DriverManager.
//
// D133: SQLite C link removed — interfaces hold no driver-specific shape.
// See docs/3-decisions/D133-sqlite-c-link-elimination.md

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
// D133 Phase 1: no driver registered. Placeholder error until D134
// (JDBC MySQL wire protocol) lands a concrete driver.

class DriverManager

function DriverManager_getConnection(url: string): Connection {
    println(`JDBC: no driver registered for url: ${url}`)
    exit(1)
}
