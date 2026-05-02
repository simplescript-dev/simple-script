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
    // ── D146 §Phase 2 Cursor / Scrollable methods ───────────────
    // setFetchSize / getFetchSize: hint to driver about row buffer
    // window. Phase 4 wires the dual semantics — client Integer.MIN_VALUE
    // (-2147483648) for client-side row streaming (MySQL Connector/J
    // standard idiom) vs server-side cursor N rows (Phase 3 protocol
    // path with COM_STMT_FETCH 0x1c).
    //
    // absolute / first / last / previous / getRow: scrollable cursor
    // multi-direction positioning. TYPE_FORWARD_ONLY default returns 0
    // for absolute / first / last / previous (not supported); Phase 3
    // wires in-memory cache for TYPE_SCROLL_INSENSITIVE (MySQL 5.7+ has
    // no server scrollable cursor — D146 §A.2 H5 fallback to Connector/J
    // in-memory cache idiom).
    //
    // Return convention (JDBC 4.3 §java.sql.ResultSet):
    //   absolute / first / last / previous → 1 = positioned on a row,
    //                                        0 = past beginning/end
    //   getRow → 1-based current row number, 0 = not positioned
    function setFetchSize(rows: int)
    function getFetchSize(): int
    function absolute(row: int): int
    function first(): int
    function last(): int
    function previous(): int
    function getRow(): int
    // ── D147 §Phase 2 Updatable Cursor methods ──────────────────
    // JDBC 4.3 §15.2.5 update surface, paired with CURSOR_TYPE_FOR_UPDATE
    // 0x02 (lib/com/mysql/query.ss) + CONCUR_UPDATABLE 1008. MySQL has no
    // SQL-standard updatable cursor (5.7+ docs); the driver simulates it
    // in MysqlBinaryResultSet (Phase 4) — updateXxx fills a pending dirty
    // Map, then updateRow / deleteRow / insertRow flush via a fresh
    // PreparedStatement on the same Connection (Connector/J 5.0+ pattern).
    // 6 core SQL setters; extended types (BigDecimal / Timestamp / Bytes)
    // left to D147 §Followup F1.
    function updateRow()
    function deleteRow()
    function insertRow()
    function cancelRowUpdates()
    function refreshRow()
    function moveToInsertRow()
    function moveToCurrentRow()
    function rowUpdated(): int
    function rowDeleted(): int
    function rowInserted(): int
    function updateInt(col: string, val: int)
    function updateString(col: string, val: string)
    function updateLong(col: string, val: int)
    function updateBoolean(col: string, val: int)
    function updateDouble(col: string, val: double)
    function updateNull(col: string)
    function close()
}

// ── JDBC 4.3 §15 ResultSet — D146 §Phase 2 Cursor / Concurrency constants ───
// Mirror java.sql.ResultSet.TYPE_FORWARD_ONLY / TYPE_SCROLL_INSENSITIVE /
// TYPE_SCROLL_SENSITIVE 3 cursor types + CONCUR_READ_ONLY 1 concurrency mode.
// Passed to Statement.executeQuery(sql, type, concurrency) and
// Connection.prepareStatement(sql, type, concurrency) to declare cursor
// behavior. Standard JDBC 4.3 §java.sql.ResultSet integer values 1003-1007.
//
// D146 Phase 2 wires the constants + interface methods; Phase 3 plumbs
// them through MysqlBinaryResultSet (cursor protocol upgrade + scrollable
// in-memory cache for TYPE_SCROLL_INSENSITIVE / TYPE_SCROLL_SENSITIVE,
// MySQL 5.7+ has no server scrollable cursor — D146 §A.2 H5).
// CONCUR_UPDATABLE (1008) is the JDBC 4.3 §java.sql.ResultSet.CONCUR_UPDATABLE
// integer value, paired with the MySQL CURSOR_TYPE_FOR_UPDATE 0x02 protocol
// flag (lib/com/mysql/query.ss). MySQL has no server-side updatable cursor
// (5.7+ docs explicit) — the driver simulates updatable behavior in
// MysqlBinaryResultSet. Connector/J 5.0+ `UpdatableResultSet` pattern. See
// D147 §核心目标 + §Phase 1.
const TYPE_FORWARD_ONLY = 1003
const TYPE_SCROLL_INSENSITIVE = 1004
const TYPE_SCROLL_SENSITIVE = 1005
const CONCUR_READ_ONLY = 1007
const CONCUR_UPDATABLE = 1008

// ── JDBC 4.3 §Statement constants — D138 §核心原则 6 ─────────
// Mirror java.sql.Statement.RETURN_GENERATED_KEYS / NO_GENERATED_KEYS. Passed
// to Connection.prepareStatement(sql, autoGeneratedKeys) to opt in / out of
// generated key retrieval. MySQL wire protocol returns lastInsertId for every
// INSERT regardless, so these constants are no-op for the MySQL driver — kept
// for JDBC spec parity (PostgreSQL / SQLite drivers reading the parameter).
const RETURN_GENERATED_KEYS = 1
const NO_GENERATED_KEYS = 2

// ── Statement ────────────────────────────────────────────────
// D138 Phase 2: getGeneratedKeys() returns a ResultSet over auto-increment ids
// produced by the most recent executeUpdate. getLastInsertId() is the SS
// shortcut around the ResultSet wrapping (single int, no row iteration). MySQL
// generates one id per INSERT (multi-row VALUES (...),(...),(...) reports the
// first id; subsequent ids are first + 1, first + 2, ... by protocol contract).

interface Statement {
    function executeQuery(sql: string): ResultSet
    // D146 Phase 2 — JDBC 4.3 §Statement.executeQuery(sql, type, concurrency).
    // type = TYPE_FORWARD_ONLY (default) | TYPE_SCROLL_INSENSITIVE |
    // TYPE_SCROLL_SENSITIVE; concurrency = CONCUR_READ_ONLY. MySQL Statement
    // (non-prepared) goes through COM_QUERY 0x03 which has no server-side
    // cursor support (MySQL 5.7+ docs explicit — server cursor protocol is
    // prepared-statement-only) — both type+concurrency parameters are
    // informational on this path. Server-side cursor lives on
    // PreparedStatement (Connection.prepareStatement(sql, type, concurrency)
    // — see Connection interface below).
    function executeQuery(sql: string, type: int, concurrency: int): ResultSet
    function executeUpdate(sql: string): int
    function execute(sql: string): int
    function getGeneratedKeys(): ResultSet
    function getLastInsertId(): int
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
    // D146 Phase 4 — JDBC 4.3 §16 Statement.setFetchSize lifted to
    // PreparedStatement (since SS PreparedStatement is a standalone
    // interface — D136 §A.5 retcon — it does not inherit Statement's
    // setFetchSize via extends). Spring `JdbcTemplate.query(sql, setter,
    // callback)` calls setter(ps) so the setter can invoke
    // ps.setFetchSize(...) before executeQuery fires; declaring it here
    // closes the abstraction gap that would otherwise force callers to
    // cast to a driver-specific class.
    //
    // Dual semantics on MySQL driver (Connector/J 5.0.6+ idiom):
    //   setFetchSize(N >= 1)             → server-side cursor
    //                                        (COM_STMT_FETCH N rows / batch,
    //                                         rs.useCursor=1)
    //   setFetchSize(INTEGER_MIN_VALUE)  → client-side row streaming
    //                                        (server flushes full ResultSet,
    //                                         client reads row-by-row,
    //                                         rs.useCursor=0)
    //   setFetchSize(0) / no call        → client streaming default
    function setFetchSize(rows: int)
    function executeQuery(): ResultSet
    function executeUpdate(): int
    function getGeneratedKeys(): ResultSet
    function getLastInsertId(): int
    function close()
}

// ── Connection ───────────────────────────────────────────────
// D138 Phase 2: prepareStatement is overloaded by arity. The 1-arg form is the
// legacy entry; the 2-arg form takes RETURN_GENERATED_KEYS / NO_GENERATED_KEYS
// to declare intent for generated-key retrieval (drivers that gate id
// retrieval read the flag; MySQL returns ids unconditionally so the flag is
// informational only).

interface Connection {
    function createStatement(): Statement
    function prepareStatement(sql: string): PreparedStatement
    function prepareStatement(sql: string, autoGeneratedKeys: int): PreparedStatement
    // D146 Phase 2 — JDBC 4.3 §Connection.prepareStatement(sql, type, concurrency).
    // type = TYPE_FORWARD_ONLY (no cursor) | TYPE_SCROLL_INSENSITIVE /
    // TYPE_SCROLL_SENSITIVE (in-memory cache fallback per D146 §A.2 H5);
    // concurrency = CONCUR_READ_ONLY (Updatable cursor + CONCUR_UPDATABLE
    // 1008 留 D147+). Phase 2 declares the interface; Phase 3 wires the
    // type+concurrency through MysqlPreparedStatement.executeQuery to
    // toggle the COM_STMT_EXECUTE flags byte CURSOR_TYPE_READ_ONLY 0x01.
    function prepareStatement(sql: string, type: int, concurrency: int): PreparedStatement
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

// ── SQLException Hierarchy — JDBC 4.3 §13.1 ──────────────────
// Mirrors java.sql.SQLException complete class tree:
//
//   SQLException (extends Error, adds sqlState + errorCode)
//   ├── SQLNonTransientException                 ← retry will not succeed
//   │   ├── SQLNonTransientConnectionException   SQLState class 08 / 28
//   │   ├── SQLIntegrityConstraintViolationException SQLState class 23
//   │   ├── SQLSyntaxErrorException              SQLState class 42
//   │   ├── SQLDataException                     SQLState class 22
//   │   └── SQLFeatureNotSupportedException      SQLState class 0A
//   ├── SQLTransientException                    ← retry may succeed
//   │   ├── SQLTransientConnectionException      SQLState class 08 (transient)
//   │   ├── SQLTransactionRollbackException      SQLState class 40
//   │   └── SQLTimeoutException                  query timeout
//   └── SQLRecoverableException                  ← reconnect may succeed
//
// Constructor positional args follow Error base class convention (prelude.ss
// `class Error { message: string }` + tests/phase5/error_class.ss):
//   new SQLNonTransientConnectionException(message, sqlState, errorCode)
// (3 args, all subclasses identical — extra fields declared on SQLException
// transit to descendants via SS class extends chain — D025 vtable + bootstrap
// classParents lookup, exercised by tests/phase5/typed_catch.ss Test 4).
//
// Empty-body subclasses are intentional — JDBC subclasses carry no extra
// state; type identity alone routes catch-clause dispatch via
// bootstrap/gen/stmts/stmts_exc.ss:99 genCatchClauses.

class SQLException extends Error {
    sqlState: string
    errorCode: int
}

class SQLNonTransientException extends SQLException {}
class SQLTransientException extends SQLException {}
class SQLRecoverableException extends SQLException {}

class SQLNonTransientConnectionException extends SQLNonTransientException {}
class SQLIntegrityConstraintViolationException extends SQLNonTransientException {}
class SQLSyntaxErrorException extends SQLNonTransientException {}
class SQLDataException extends SQLNonTransientException {}
class SQLFeatureNotSupportedException extends SQLNonTransientException {}

class SQLTransientConnectionException extends SQLTransientException {}
class SQLTransactionRollbackException extends SQLTransientException {}
class SQLTimeoutException extends SQLTransientException {}
