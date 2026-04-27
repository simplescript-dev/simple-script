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

// ── PreparedStatement ────────────────────────────────────────
// JDBC 4.3 PreparedStatement (driver-agnostic). Bound to a parameterized SQL
// at Connection.prepareStatement(sql) time; setXxx(idx, val) binds positional
// params (idx from 1, JDBC convention). executeQuery() / executeUpdate() use
// the bound sql + bound params via the binary protocol.
//
// D136 §A.5 retcon: standalone interface (not `extends Statement`). SS parser
// has no interface-extends syntax (parseInterfaceDecl) and no method overload
// support, so the JDBC spec historical `PreparedStatement extends Statement`
// shape is unimplementable here — and per JDBC 4.3 §A.4.2, calling
// Statement.execute(String) on a PreparedStatement throws SQLException anyway.
// Standalone interface matches the spec's effective semantics.

interface PreparedStatement {
    function setInt(idx: int, val: int)
    function setLong(idx: int, val: int)
    function setString(idx: int, val: string)
    function setDouble(idx: int, val: double)
    function setBoolean(idx: int, val: int)
    function setNull(idx: int)
    function executeQuery(): ResultSet
    function executeUpdate(): int
    function close()
}

// ── Connection ───────────────────────────────────────────────

interface Connection {
    function createStatement(): Statement
    function prepareStatement(sql: string): PreparedStatement
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
