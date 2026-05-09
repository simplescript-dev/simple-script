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
    // ── D151 Phase 4 — JDBC 4.3 §15.2.5 update setter type extension ──
    // 18 method signatures completing the JDBC §15.2.5 update API. Type
    // classes resolved by D152 (lib/java/{math,sql,io}.ss):
    //   BigDecimal      — D152 Phase 2 (lib/java/math.ss)
    //   Timestamp / Date / Time / Blob / Clob / NClob / RowId / SQLXML /
    //   SqlArray / Ref  — D152 Phase 3 (this file's type class section)
    //   InputStream / Reader — D152 Phase 4 (lib/java/io.ss)
    // updateBytes / updateObject / updateNString take SS string — JDBC
    // byte[] / Object / NString collapse onto string in this driver
    // (Object generics-on-interface tracked in D152 §Followup).
    function updateBigDecimal(col: string, val: BigDecimal)
    function updateTimestamp(col: string, val: Timestamp)
    function updateDate(col: string, val: Date)
    function updateTime(col: string, val: Time)
    function updateBlob(col: string, val: Blob)
    function updateClob(col: string, val: Clob)
    function updateNClob(col: string, val: NClob)
    function updateRowId(col: string, val: RowId)
    function updateSQLXML(col: string, val: SQLXML)
    function updateArray(col: string, val: SqlArray)
    function updateRef(col: string, val: Ref)
    function updateAsciiStream(col: string, val: InputStream)
    function updateBinaryStream(col: string, val: InputStream)
    function updateCharacterStream(col: string, val: Reader)
    function updateNCharacterStream(col: string, val: Reader)
    function updateBytes(col: string, val: string)
    function updateObject(col: string, val: string)
    function updateNString(col: string, val: string)
    // ── D155 Phase 2 — JDBC 4.3 §15.4 column metadata reflection ────────
    // ResultSetMetaData supplies column count + per-column name / type /
    // nullability / signedness / precision / scale used by ORM-style
    // reflection mappers (Hibernate `BeanPropertyRowMapper`, MyBatis
    // `ResultMap`, Spring `JdbcTemplate.queryForList`). The driver routes
    // the call through ColumnDef41 packet metadata (lib/com/mysql/query.ss
    // ColumnDef, D155 Phase 1 完整字段). Phase 2 stubs return a
    // NoopResultSetMetaData fallback; Phase 3 wires MysqlResultSetMetaData
    // reflection + 13-bit MySQL flag + JDBC Types mapping.
    function getMetaData(): ResultSetMetaData
    function close()
}

// ── ResultSetMetaData — D155 §Phase 2 / JDBC 4.3 §15.4 ───────
// Column metadata reflection for ResultSet. ≥21 method covers Hibernate
// `BeanPropertyRowMapper` / MyBatis `ResultMap` / Spring
// `JdbcTemplate.queryForList` reflection-based column mapping idioms.
// MySQL Native Protocol §6.6 ColumnDefinition41 packet supplies the
// underlying column descriptors via lib/com/mysql/query.ss ColumnDef
// (D147 Phase 3 + D155 Phase 1 累积 11 字段).
//
// Phase 2 (this Phase) declares the interface + 3 implementor stubs that
// return a NoopResultSetMetaData fallback. Phase 3 wires the real
// MysqlResultSetMetaData reflection + 13-bit MySQL flag + JDBC Types
// mapping; Phase 4 covers integration_test e2e.
//
// JDBC 4.3 §15.4 covers ≥24 method including Wrapper.unwrap /
// isWrapperFor + RowIdLifetime — those 3 留 §Followup F4. Boolean
// returns use SS int (0 / 1) per the same convention as
// ResultSet.getBoolean / rowUpdated / rowDeleted (interface boolean
// type unification 留 D154 §Followup outside D155 scope).
//
// isNullable(col) returns columnNoNulls = 0 / columnNullable = 1 /
// columnNullableUnknown = 2 (JDBC 4.3 §15.4 enum-as-int constants;
// declared below the interface block).

interface ResultSetMetaData {
    function getColumnCount(): int
    function getColumnName(col: int): string
    function getColumnLabel(col: int): string
    function getColumnType(col: int): int
    function getColumnTypeName(col: int): string
    function getColumnDisplaySize(col: int): int
    function getColumnClassName(col: int): string
    function getCatalogName(col: int): string
    function getSchemaName(col: int): string
    function getTableName(col: int): string
    function isNullable(col: int): int
    function isAutoIncrement(col: int): int
    function isCaseSensitive(col: int): int
    function isCurrency(col: int): int
    function isDefinitelyWritable(col: int): int
    function isReadOnly(col: int): int
    function isSearchable(col: int): int
    function isSigned(col: int): int
    function isWritable(col: int): int
    function getPrecision(col: int): int
    function getScale(col: int): int
}

// JDBC 4.3 §15.4 ResultSetMetaData.isNullable(int) return values.
const columnNoNulls = 0
const columnNullable = 1
const columnNullableUnknown = 2

// ── JDBC 4.3 §13.1 / java.sql.Types — D155 Phase 3 SQL type code mapping ─────
// java.sql.Types int constants used by ResultSetMetaData.getColumnType /
// PreparedStatement.setObject(idx, val, sqlType) / CallableStatement.
// registerOutParameter. Values match the JDK java.sql.Types literal
// (e.g. Types.VARCHAR = 12) so the wire-side mysqlTypeToJdbcType
// mapping (lib/com/mysql/query.ss) hits the same int code an upstream
// JDBC consumer (Hibernate / MyBatis / Spring) would dispatch on.
//
// Naming carries a JDBC_TYPE_ prefix because the bare names (BIT / TINYINT
// / VARCHAR / ...) overlap with potential reserved-word territory + the
// MySQL `mysqlType` byte constants (0x00 DECIMAL ... 0xFF GEOMETRY) that
// the query.ss mapping table dispatches on. The prefix keeps the JDBC view
// distinct from the protocol-byte view.
//
// Subset coverage = the ≥13 codes the MySQL driver actually returns
// (JDBC §13.1 lists ≥30 — ARRAY / STRUCT / REF / DATALINK / SQLXML left
// to D155 §Followup F4 + driver-side D152 type class extension).
const JDBC_TYPE_BIT = -7
const JDBC_TYPE_TINYINT = -6
const JDBC_TYPE_BIGINT = -5
const JDBC_TYPE_LONGVARBINARY = -4
const JDBC_TYPE_VARBINARY = -3
const JDBC_TYPE_BINARY = -2
const JDBC_TYPE_CHAR = 1
const JDBC_TYPE_NUMERIC = 2
const JDBC_TYPE_DECIMAL = 3
const JDBC_TYPE_INTEGER = 4
const JDBC_TYPE_SMALLINT = 5
const JDBC_TYPE_FLOAT = 6
const JDBC_TYPE_REAL = 7
const JDBC_TYPE_DOUBLE = 8
const JDBC_TYPE_VARCHAR = 12
const JDBC_TYPE_DATE = 91
const JDBC_TYPE_TIME = 92
const JDBC_TYPE_TIMESTAMP = 93
const JDBC_TYPE_LONGVARCHAR = -1
const JDBC_TYPE_NULL = 0
const JDBC_TYPE_BLOB = 2004
const JDBC_TYPE_CLOB = 2005

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
    // D157 §Phase 1 — JDBC 4.3 §10.2 parameter-level metadata reflection
    // for ORM idioms (Spring JdbcTemplate.update setter pre-eval, Hibernate
    // BasicBinder, MyBatis TypeHandler). Phase 2 wires MysqlParameterMetaData.
    function getParameterMetaData(): ParameterMetaData
    function close()
}

// ── CallableStatement — D160 §Phase 1 / JDBC 4.3 §13.x ──────────
// `extends PreparedStatement` (D161 §Phase 2 walk parent merge auto
// inherits the 13 PreparedStatement methods — setXxx for INOUT, the
// execute path, generated keys, parameter metadata, close). Adds 21
// own methods for stored-procedure OUT/INOUT parameters:
//   registerOutParameter ×2 arity overloads (with / without scale)
//   17 typed OUT getters (getString / getBoolean / getByte / getShort
//     / getInt / getLong / getFloat / getDouble / getBigDecimal /
//     getBytes / getDate / getTime / getTimestamp / getObject ×2 /
//     getNString / getCharacterStream / getNCharacterStream)
//   wasNull
// Advanced SQL-type OUT getters (Blob / Clob / NClob / RowId / SQLXML
// / Array / Ref / URL) 留 D160 §Followup F3.
//
// MySQL stored-procedure OUT path: the wire protocol returns OUT
// values in a trailing ResultSet (MySQL Native Protocol §15.7.4
// SERVER_MORE_RESULTS_EXISTS bit 8). Phase 2 wires
// MysqlCallableStatement to drain to that trailing ResultSet and
// reflect getXxx through it. Phase 1 (this file) lands the interface
// + Connection.prepareCall + jdbc.ss stub returning
// NoopCallableStatement.
interface CallableStatement extends PreparedStatement {
    function registerOutParameter(idx: int, sqlType: int)
    function registerOutParameter(idx: int, sqlType: int, scale: int)
    function wasNull(): int
    function getString(idx: int): string
    function getBoolean(idx: int): int
    function getByte(idx: int): int
    function getShort(idx: int): int
    function getInt(idx: int): int
    function getLong(idx: int): int
    function getFloat(idx: int): double
    function getDouble(idx: int): double
    function getBigDecimal(idx: int): BigDecimal
    function getBytes(idx: int): string
    function getDate(idx: int): Date
    function getTime(idx: int): Time
    function getTimestamp(idx: int): Timestamp
    function getObject(idx: int): string
    function getObject(idx: int, classType: string): string
    function getNString(idx: int): string
    function getCharacterStream(idx: int): Reader
    function getNCharacterStream(idx: int): Reader
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
    // D160 §Phase 1 — JDBC 4.3 §11 Connection.prepareCall(sql) for stored-
    // procedure CALL syntax. Single-arity in Phase 1; type+concurrency
    // overloads (for scrollable OUT cursors) 留 D160 §Followup.
    function prepareCall(sql: string): CallableStatement
    function setAutoCommit(auto: int)
    function commit()
    function rollback()
    function close()
    function isClosed(): int
    // ── D156 §Phase 2 — JDBC 4.3 §11 schema-level metadata reflection ─────
    // DatabaseMetaData supplies driver / database / schema / catalog / table /
    // column / key / index reflection used by ORM idioms (Hibernate `Dialect`
    // schema discovery, Spring JPA auto-validation, Flyway / Liquibase
    // migration, MyBatis Generator). The driver routes the call through
    // INFORMATION_SCHEMA per-call PreparedStatement (D156 Phase 1 helper) +
    // supportsXxx capability matrix + driver-static literals. Phase 2 stubs
    // return a NoopDatabaseMetaData fallback (lib/com/mysql/jdbc.ss); Phase 3
    // wires MysqlDatabaseMetaData reflection + 13 supportsXxx + lazy cache
    // getDatabaseProductVersion (D156 §A.2 H1-H8 wire-end e2e Phase 4).
    function getMetaData(): DatabaseMetaData
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

// ── JDBC 4.3 Type Class Foundation — D152 §Phase 3 ───────────
// JDK java.sql.* type class direct mapping (interface form). Driver-side
// concrete implementations live under lib/com/<vendor>/*.ss; user code
// dispatches through these interfaces.
//
// D152 §核心目标: ≥10 type class interfaces underlie D151 setter ≥18
// method (JDBC §15.2.5 updateXxx) signatures — without these, the setter
// API would have to fall back to ptr / null-stub workarounds (violates
// D151 §核心原则 1 完整不裁剪).
//
// Stream methods (Blob.getBinaryStream / Clob.getCharacterStream /
// NClob.getCharacterStream / SQLXML.getBinaryStream / SQLXML.
// getCharacterStream) return java.io.InputStream / java.io.Reader.
// Added in D152 §Phase 4 once lib/java/io.ss landed (this Phase).
//
// Naming: java.sql.Array → SqlArray. SS Array<T> is the built-in generic
// array type — declaring `interface Array` would shadow the keyword.
// The Sql- prefix matches the convention used by JPA driver bindings.
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 3 / §Phase 4.

import { InputStream, Reader } from "@/lib/java/io"

// ── Timestamp — JDBC 4.3 §13.2.1 / java.sql.Timestamp ────────
// Date + time + nanosecond precision. JDBC convention:
//   getMonth() returns 1-12 (NOT 0-11 like java.util.Date)
//   getNanos() returns 0-999999999 (sub-millisecond precision the
//                                    millis-only getTime() cannot represent)
// JDBC `Timestamp extends java.util.Date implements Comparable<Timestamp>`
// — SS interfaces lack extends/implements syntax (D136 §A.5), so the
// inherited getTime/setTime + Comparable.compareTo are restated here.

interface Timestamp {
    function getYear(): int
    function getMonth(): int
    function getDay(): int
    function getHours(): int
    function getMinutes(): int
    function getSeconds(): int
    function getNanos(): int
    function setNanos(nanos: int)
    function getTime(): int
    function setTime(time: int)
    function before(other: Timestamp): int
    function after(other: Timestamp): int
    function equals(other: Timestamp): int
    function compareTo(other: Timestamp): int
    function toString(): string
}

// ── Date — JDBC 4.3 §13.2.1 / java.sql.Date ──────────────────
// Date-only column type. toString() returns "YYYY-MM-DD" per JDBC spec.
// Same extends/implements restating as Timestamp (D136 §A.5).

interface Date {
    function getYear(): int
    function getMonth(): int
    function getDay(): int
    function getTime(): int
    function setTime(time: int)
    function before(other: Date): int
    function after(other: Date): int
    function equals(other: Date): int
    function compareTo(other: Date): int
    function toString(): string
}

// ── Time — JDBC 4.3 §13.2.1 / java.sql.Time ──────────────────
// Time-only column type. toString() returns "HH:MM:SS" per JDBC spec.

interface Time {
    function getHours(): int
    function getMinutes(): int
    function getSeconds(): int
    function getTime(): int
    function setTime(time: int)
    function before(other: Time): int
    function after(other: Time): int
    function equals(other: Time): int
    function compareTo(other: Time): int
    function toString(): string
}

// ── Blob — JDBC 4.3 §13.2.2 / java.sql.Blob ──────────────────
// Binary Large Object handle. Position is 1-based (JDBC convention).
//   length()                      — total bytes
//   getBytes(pos, len)            — read window
//   setBytes(pos, bytes)          — write at pos, returns count written
//   position(pattern, start)      — pattern search, -1 if not found
//   truncate(len)                 — shrink Blob to len bytes
//   free()                        — release driver resources
// getBinaryStream() returns InputStream — added in D152 §Phase 4.

interface Blob {
    function length(): int
    function getBytes(pos: int, len: int): string
    function setBytes(pos: int, bytes: string): int
    function position(pattern: string, start: int): int
    function truncate(len: int)
    function getBinaryStream(): InputStream
    function free()
}

// ── Clob — JDBC 4.3 §13.2.2 / java.sql.Clob ──────────────────
// Character Large Object handle. setString returns chars written.
// getCharacterStream() returns Reader — added in D152 §Phase 4.

interface Clob {
    function length(): int
    function getSubString(pos: int, len: int): string
    function setString(pos: int, str: string): int
    function position(pattern: string, start: int): int
    function truncate(len: int)
    function getCharacterStream(): Reader
    function free()
}

// ── NClob — JDBC 4.3 §13.2.2 / java.sql.NClob ────────────────
// National-character Clob (NCHAR / NVARCHAR / NCLOB columns). Inherits
// Clob's 7 methods via `extends Clob`; driver impls (MysqlNClob) are
// also Clob implementors so `let c: Clob = new MysqlNClob(...)` upcast
// dispatches correctly through the parent vtable.

interface NClob extends Clob {
}

// ── RowId — JDBC 4.3 §13.2.3 / java.sql.RowId ────────────────
// Driver-opaque row identifier (DB2 ROWID, Oracle ROWID, MySQL row hash).
// Used by Statement.getRowId / setRowId for cursor row addressing —
// alternative to PK-based positioning when PK is composite or absent.

interface RowId {
    function getBytes(): string
    function toString(): string
    function equals(other: RowId): int
    function hashCode(): int
}

// ── SQLXML — JDBC 4.3 §13.2.4 / java.sql.SQLXML ──────────────
// XML column handle (SQL/XML standard, MySQL JSON column, PostgreSQL xml,
// SQL Server XML, Oracle XMLType). getBinaryStream / getCharacterStream
// return InputStream / Reader — added in D152 §Phase 4.

interface SQLXML {
    function getString(): string
    function setString(value: string)
    function getBinaryStream(): InputStream
    function getCharacterStream(): Reader
    function free()
}

// ── SqlArray — JDBC 4.3 §13.2.5 / java.sql.Array ─────────────
// SQL ARRAY column handle (PostgreSQL TEXT[] / INT[], standard SQL ARRAY
// type). Renamed from JDBC `Array` to `SqlArray` because SS Array<T> is
// the built-in generic — declaring `interface Array` would shadow the
// keyword.
//
// getBaseType() returns the JDBC Types int constant of the element type
// (e.g. Types.INTEGER = 4, Types.VARCHAR = 12); getBaseTypeName()
// returns the SQL type name ("INTEGER", "VARCHAR").
//
// getArray() returns a driver-serialized representation. JDBC spec
// returns Object[]; SS interface return types must be concrete and
// generics-on-interface is not yet supported (D152 §Followup tracks
// generics-on-interface sub-D).

interface SqlArray {
    function getBaseType(): int
    function getBaseTypeName(): string
    function getArray(): string
    function free()
}

// ── Ref — JDBC 4.3 §13.2.6 / java.sql.Ref ────────────────────
// SQL REF column (SQL standard REF type, Oracle REF). Pointer to a row
// in a typed table. getObject returns the referenced object as a
// driver-serialized string (same generics-on-interface limitation as
// SqlArray, D152 §Followup).

interface Ref {
    function getBaseTypeName(): string
    function getObject(): string
    function setObject(value: string)
}

// ── DatabaseMetaData — D156 §Phase 2 / JDBC 4.3 §11 ──────────
// Schema-level metadata for Hibernate Dialect / Spring JPA / Flyway /
// MyBatis Generator. ResultSet-returning methods route through D156 Phase 1
// INFORMATION_SCHEMA helper; the ResultSet walks the D155 ResultSetMetaData
// reflection path (no separate column-metadata layer).
// catalog vs schema (§A.2 H2): MySQL single-tier — getCatalogs = SHOW
// DATABASES, getSchemas empty; PG double-tier reverse留 §Followup F3.
// Wrapper / RowIdLifetime / getMaxXxx / 40+ supportsXxx 留 §Followup F4.
interface DatabaseMetaData {
    function getCatalogs(): ResultSet
    function getSchemas(): ResultSet
    function getSchemas(catalog: string, schemaPattern: string): ResultSet
    function getTables(catalog: string, schemaPattern: string, tableNamePattern: string, types: string): ResultSet
    function getColumns(catalog: string, schemaPattern: string, tableNamePattern: string, columnNamePattern: string): ResultSet
    function getPrimaryKeys(catalog: string, schema: string, table: string): ResultSet
    function getImportedKeys(catalog: string, schema: string, table: string): ResultSet
    function getExportedKeys(catalog: string, schema: string, table: string): ResultSet
    function getCrossReference(parentCatalog: string, parentSchema: string, parentTable: string, foreignCatalog: string, foreignSchema: string, foreignTable: string): ResultSet
    function getIndexInfo(catalog: string, schema: string, table: string, unique: int, approximate: int): ResultSet
    function getProcedures(catalog: string, schemaPattern: string, procedureNamePattern: string): ResultSet
    function getProcedureColumns(catalog: string, schemaPattern: string, procedureNamePattern: string, columnNamePattern: string): ResultSet
    function getFunctions(catalog: string, schemaPattern: string, functionNamePattern: string): ResultSet
    function getFunctionColumns(catalog: string, schemaPattern: string, functionNamePattern: string, columnNamePattern: string): ResultSet
    function getDriverName(): string
    function getDriverVersion(): string
    function getDriverMajorVersion(): int
    function getDriverMinorVersion(): int
    function getDatabaseProductName(): string
    function getDatabaseProductVersion(): string
    function getURL(): string
    function getUserName(): string
    function getJDBCMajorVersion(): int
    function getJDBCMinorVersion(): int
    function getCatalogTerm(): string
    function getSchemaTerm(): string
    function getProcedureTerm(): string
    function getCatalogSeparator(): string
    function supportsTransactions(): int
    function supportsBatchUpdates(): int
    function supportsTransactionIsolationLevel(level: int): int
    function supportsResultSetType(type: int): int
    function supportsResultSetConcurrency(type: int, concurrency: int): int
}

// ── JDBC 4.3 §11 / java.sql.Connection — D156 §Phase 2 constants ─────
// Standard JDBC integer literals. TRANSACTION_REPEATABLE_READ = 4 (not 3
// — JDK gap). Connection.setTransactionIsolation 留 D156 §Followup F4.
const JDBC_MAJOR_VERSION = 4
const JDBC_MINOR_VERSION = 3
const TRANSACTION_NONE = 0
const TRANSACTION_READ_UNCOMMITTED = 1
const TRANSACTION_READ_COMMITTED = 2
const TRANSACTION_REPEATABLE_READ = 4
const TRANSACTION_SERIALIZABLE = 8

// ── ParameterMetaData — D157 §Phase 1 / JDBC 4.3 §10.2 ──────────
// Parameter-level metadata for ORM reflection. ParameterDef = ColumnDef41
// 同结构 (MySQL Native Protocol §15.7.7), readParamDef 已用 parseColumnDef
// (lib/com/mysql/prepared.ss:169-179). Wrapper.unwrap / getPrecision /
// getScale 留 §Followup F3.
interface ParameterMetaData {
    function getParameterCount(): int
    function getParameterType(idx: int): int
    function getParameterTypeName(idx: int): string
    function getParameterClassName(idx: int): string
    function getParameterMode(idx: int): int
    function isNullable(idx: int): int
    function isSigned(idx: int): int
}

// ── JDBC 4.3 §10.2 / java.sql.ParameterMetaData — D157 §Phase 1 constants ─
// Static literals. parameterModeOut = 4 (not 3 — spec gap). MySQL prepare
// returns parameterModeIn only; CallableStatement OUT/INOUT 留 §F2.
const parameterModeIn = 1
const parameterModeInOut = 2
const parameterModeOut = 4
const parameterModeUnknown = 0
const parameterNullable = 1
const parameterNoNulls = 0
const parameterNullableUnknown = 2
