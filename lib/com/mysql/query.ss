// MySQL COM_QUERY + ResultSet packet parsing — D134 Phase 4.
//
// API deviates from D134 §3 Phase 4 literal spec on EOF terminator:
// the spec assumes CLIENT_DEPRECATE_EOF set (MySQL 8 default behavior), but
// Phase 3 sendHandshakeResponse41 capFlags does NOT include 0x01000000 — so
// the server emits **legacy EOF** packets (0xFE header + payloadLen < 9)
// after column definitions and after the last row. Phase 4 honors what the
// server actually sends. Decision recorded in D134 §附录 B Phase 4.
//
// Parse / read split: parseResultSetHeader / parseColumnDef / parseRow take
// payload buffers so unit tests can drive them with bash-printf fixtures
// (no socket); read* wrappers add a readPacket(fd) on top for production use.

import { byteToInt, readLengthEncodedInt, lengthEncodedIntSize, readLengthEncodedString } from "@/lib/binary"
import { readPacket, writePacket, MysqlPacket } from "@/lib/com/mysql/wire"
import { ResultSet, ResultSetMetaData, columnNoNulls, columnNullable, columnNullableUnknown, JDBC_TYPE_BIT, JDBC_TYPE_TINYINT, JDBC_TYPE_BIGINT, JDBC_TYPE_LONGVARBINARY, JDBC_TYPE_VARBINARY, JDBC_TYPE_CHAR, JDBC_TYPE_DECIMAL, JDBC_TYPE_INTEGER, JDBC_TYPE_SMALLINT, JDBC_TYPE_FLOAT, JDBC_TYPE_DOUBLE, JDBC_TYPE_VARCHAR, JDBC_TYPE_DATE, JDBC_TYPE_TIME, JDBC_TYPE_TIMESTAMP, JDBC_TYPE_NULL, SQLException, SQLNonTransientConnectionException, SQLIntegrityConstraintViolationException, SQLSyntaxErrorException, SQLDataException, SQLFeatureNotSupportedException, SQLTransactionRollbackException, Timestamp, Date, Time, Blob, Clob, NClob, RowId, SQLXML, SqlArray, Ref } from "@/lib/java/sql"
import { BigDecimal } from "@/lib/java/math"
import { InputStream, Reader } from "@/lib/java/io"

const COM_QUERY = 0x03
const NULL_MARKER = 0xFB
const ERR_HEADER = 0xFF
const OK_HEADER = 0x00
const EOF_HEADER = 0xFE
const RESULT_SET_HEADER_OK = -2

// Column definition (text protocol). Full ColumnDefinition41 field set.
// D134 Phase 4 kept name + colType + columnLen + charset; D147 Phase 3
// promoted org_table + flags from "skip" to "keep" so the driver-side
// updatable cursor can reach the original table name for UPDATE / DELETE
// / INSERT WHERE pk=? clauses + the PRI_KEY_FLAG bit (D147 §A.2 H2).
// D155 Phase 1 promotes the remaining catalog / schema / table (alias)
// / org_name + decimals — JDBC 4.3 §15.4 ResultSetMetaData getCatalogName
// / getSchemaName / getTableName / getColumnTypeName / getPrecision /
// getScale / getColumnDisplaySize derive directly off these fields, so a
// faithful reflection of MySQL Native Protocol §6.6 ColumnDefinition41 is
// the prerequisite for the metadata interface (D155 §核心目标).
class ColumnDef {
    name: string
    colType: int
    columnLen: int
    charset: int
    orgTable: string
    flags: int
    catalog: string
    schema: string
    table: string
    orgName: string
    decimals: int
}

// Sends a COM_QUERY packet (cmd 0x03 + sql bytes) with seqId reset to 0.
// SQL strings are ASCII (SELECT / INSERT / CREATE / ...) so the cmd-byte +
// sql concat survives ss_string_concat strlen — payloadLen is sql.length()+1.
function sendQuery(fd: int, sql: string): int {
    const sqlLen = sql.length()
    const payload = fromCharCode(COM_QUERY) + sql
    return writePacket(fd, 0, payload, sqlLen + 1)
}

// Parses the first packet of a query response.
// Returns:
//   -2 (RESULT_SET_HEADER_OK)  if first byte = 0x00 (OK packet — no rows)
//   N > 0                      length-encoded column count (SELECT result)
//   0                          empty payload
// Throws SQLException subclass dispatched by SQLState class when first byte
// is 0xFF (ERR packet) — D139 §核心原则 3+4 (sentinel removed; protocol
// layer surfaces JDBC SQLException directly).
function parseResultSetHeader(payload: string, payloadLen: int): int {
    if (payloadLen <= 0) { return 0 }
    const first = charCodeAt(payload, 0)
    if (first == ERR_HEADER) {
        throw(dispatchSQLException(parseErrorPacket(payload, payloadLen)))
    }
    if (first == OK_HEADER) { return RESULT_SET_HEADER_OK }
    return readLengthEncodedInt(payload, 0)
}

function readResultSetHeader(fd: int): int {
    const pkt = readPacket(fd)
    return parseResultSetHeader(pkt.payload, pkt.payloadLen)
}

// OK packet — D138 §核心原则 3 完整 4 字段 parse (SESSION_TRACK info string
// 留 §Followup F1). OK packet layout (text protocol, CLIENT_PROTOCOL_41 set,
// no SESSION_TRACK):
//   1 byte:        header (0x00 — OK; 0xFE counts as OK only when payloadLen < 9
//                  AND CLIENT_DEPRECATE_EOF is set, not the case here)
//   lenenc int:    affected rows
//   lenenc int:    last_insert_id        ← D138 Phase 1 解 skip
//   2 byte LE:     status flags          ← D138 Phase 1 解 skip
//   2 byte LE:     warnings count        ← D138 Phase 1 解 skip
//   ... rest:      info string           (SESSION_TRACK — D138 §Followup F1)
class OkPacket {
    affectedRows: int
    lastInsertId: int
    statusFlags: int
    warnings: int
}

// Parses the OK packet payload into a full OkPacket. lenenc int variable size
// (1/3/4/9 bytes) requires lengthEncodedIntSize after each read to advance off
// — affected_rows / last_insert_id are both lenenc, so two reads + two size
// advances. statusFlags / warnings (2 byte LE each) read only when payload has
// the trailing 4 bytes; pre-4.1 servers without CLIENT_PROTOCOL_41 omit them
// (defensive). Returns zero-initialized OkPacket if header is not OK (caller
// already filtered ERR — defensive).
function parseOkPacket(payload: string, payloadLen: int): OkPacket {
    const ok = new OkPacket(0, 0, 0, 0)
    if (payloadLen < 2) { return ok }
    if (charCodeAt(payload, 0) != OK_HEADER) { return ok }
    let off = 1
    ok.affectedRows = readLengthEncodedInt(payload, off)
    off = off + lengthEncodedIntSize(payload, off)
    ok.lastInsertId = readLengthEncodedInt(payload, off)
    off = off + lengthEncodedIntSize(payload, off)
    if (payloadLen >= off + 4) {
        ok.statusFlags = byteToInt(payload, off, 2)
        ok.warnings = byteToInt(payload, off + 2, 2)
    }
    return ok
}

// ERR packet — D139 §核心原则 5 完整 ERR_Packet spec parse (MySQL Native
// Protocol §ERR_Packet). Layout:
//   1 byte:       header 0xFF
//   2 byte LE:    error_code
//   1 byte:       sql_state_marker '#' (0x23)  ← present when CLIENT_PROTOCOL_41
//   5 byte ASCII: sql_state                    ← present when marker present
//   ... rest:     error_message                (UTF-8 / ASCII text)
//
// Pre-4.1 servers (CLIENT_PROTOCOL_41 not set) omit marker + sql_state — this
// driver always negotiates 4.1+ in Phase 3 sendHandshakeResponse41 capFlags so
// marker is expected, but the parse is defensive: missing marker → sqlState
// defaults to "HY000" (JDBC 4.3 §13.4 SQLState class "HY" general fallback)
// and the entire rest after error_code becomes errorMessage.
//
// String concat strlen note: error_message in MySQL ERR packets is ASCII /
// UTF-8 text (e.g. "Duplicate entry '1' for key 'PRIMARY'") with no embedded
// 0x00 by spec. byteToInt over the 2-byte error_code is binary-safe (charCodeAt
// based — gen_rt_string.ss:117-122). Per-byte fromCharCode + concat in the
// rest loop tolerates any non-NULL byte.
class ErrorPacket {
    errorCode: int
    sqlState: string
    errorMessage: string
}

function parseErrorPacket(payload: string, payloadLen: int): ErrorPacket {
    const ep = new ErrorPacket(0, "HY000", "")
    if (payloadLen < 3) { return ep }
    if (charCodeAt(payload, 0) != ERR_HEADER) { return ep }
    ep.errorCode = byteToInt(payload, 1, 2)
    let off = 3
    if (payloadLen >= off + 6 && charCodeAt(payload, off) == 0x23) {
        let s = ""
        let i = 0
        while (i < 5) {
            s = s + fromCharCode(charCodeAt(payload, off + 1 + i))
            i = i + 1
        }
        ep.sqlState = s
        off = off + 6
    }
    let msg = ""
    let j = off
    while (j < payloadLen) {
        msg = msg + fromCharCode(charCodeAt(payload, j))
        j = j + 1
    }
    ep.errorMessage = msg
    return ep
}

// Reads the response packet into a full OkPacket — D138 §核心原则 4 single
// source of truth for affectedRows + lastInsertId. ERR header parses
// ErrorPacket and throws an SQLException subclass dispatched by SQLState
// class; short read / unrecognised first byte throw
// SQLNonTransientConnectionException (08000 wire-protocol failure) — D139
// §核心原则 3+4 (sentinel removed; thin wrapper retired).
function readUpdateResultPacket(fd: int): OkPacket {
    const pkt = readPacket(fd)
    if (pkt.payloadLen <= 0) {
        throw(new SQLNonTransientConnectionException("MySQL: short read on update response", "08000", 0))
    }
    const first = charCodeAt(pkt.payload, 0)
    if (first == OK_HEADER) {
        return parseOkPacket(pkt.payload, pkt.payloadLen)
    }
    if (first == ERR_HEADER) {
        throw(dispatchSQLException(parseErrorPacket(pkt.payload, pkt.payloadLen)))
    }
    throw(new SQLNonTransientConnectionException("MySQL: unrecognised header on update response", "08000", 0))
}

// SQLState class → SQLException subclass dispatch — JDBC 4.3 §13.4. Two-char
// prefix routing per MySQL Connector/J convention; HY / unknown classes fall
// back to the SQLException root so callers can still read sqlState/errorCode.
function sqlStateClass(s: string): string {
    if (s.length() < 2) { return "" }
    return s.substring(0, 2)
}

function dispatchSQLException(ep: ErrorPacket): SQLException {
    const cls = sqlStateClass(ep.sqlState)
    // 08 connection failure / 28 invalid auth both surface as
    // SQLNonTransientConnectionException per JDBC 4.3 §13.4.
    if (cls == "08") { return new SQLNonTransientConnectionException(ep.errorMessage, ep.sqlState, ep.errorCode) }
    if (cls == "28") { return new SQLNonTransientConnectionException(ep.errorMessage, ep.sqlState, ep.errorCode) }
    if (cls == "23") { return new SQLIntegrityConstraintViolationException(ep.errorMessage, ep.sqlState, ep.errorCode) }
    if (cls == "40") { return new SQLTransactionRollbackException(ep.errorMessage, ep.sqlState, ep.errorCode) }
    if (cls == "42") { return new SQLSyntaxErrorException(ep.errorMessage, ep.sqlState, ep.errorCode) }
    if (cls == "0A") { return new SQLFeatureNotSupportedException(ep.errorMessage, ep.sqlState, ep.errorCode) }
    if (cls == "22") { return new SQLDataException(ep.errorMessage, ep.sqlState, ep.errorCode) }
    return new SQLException(ep.errorMessage, ep.sqlState, ep.errorCode)
}

// Cross-module accessors — D138 Phase 2. lib/com/mysql/jdbc.ss + prepared.ss
// IR is concatenated before query.ss declares %OkPacket, so a direct GEP
// %OkPacket from those modules forward-references the type and llc rejects
// 'base element of getelementptr must be sized'. Routing field access through
// a function defined here keeps the GEP inside the module that owns the type
// — same constraint columnDefColType / columnDefName document for ColumnDef.
function okPacketAffectedRows(ok: OkPacket): int {
    return ok.affectedRows
}

function okPacketLastInsertId(ok: OkPacket): int {
    return ok.lastInsertId
}

// Skips one length-encoded string at `offset`, returns the new offset.
// NULL marker (0xFB) consumes 1 byte of header and zero data bytes.
function skipLengthEncodedString(payload: string, offset: int): int {
    const len = readLengthEncodedInt(payload, offset)
    const sz = lengthEncodedIntSize(payload, offset)
    if (len < 0) { return offset + sz }
    return offset + sz + len
}

// Parses a Column Definition (ColumnDefinition41) packet payload. Layout:
//   lenenc str: catalog       (KEEP — D155 Phase 1; JDBC §15.4 getCatalogName)
//   lenenc str: schema        (KEEP — D155 Phase 1; JDBC §15.4 getSchemaName)
//   lenenc str: table         (KEEP — D155 Phase 1; JDBC §15.4 getTableName
//                              alias used by the SELECT — distinct from
//                              org_table which carries the storage table)
//   lenenc str: org_table     (KEEP — D147 Phase 3 driver-side updatable cursor
//                              needs the original table name for UPDATE / DELETE
//                              / INSERT WHERE pk=? generation)
//   lenenc str: name          (KEEP — column alias used by getString)
//   lenenc str: org_name      (KEEP — D155 Phase 1; storage column name behind
//                              the SELECT alias, for reflective ORM mapping)
//   1 byte:    filler 0x0c    (constant length tag for the 12-byte metadata block)
//   2 byte LE: character set  (KEEP — D134 Phase 4)
//   4 byte LE: column length  (KEEP — JDBC §15.4 getColumnDisplaySize / getPrecision
//                              derives off this; surfaced as
//                              columnDefMaxColumnLength accessor)
//   1 byte:    column type    (KEEP)
//   2 byte LE: flags          (KEEP — D147 Phase 3 bit 1 = PRI_KEY_FLAG 0x0002
//                              identifies the primary-key column without a
//                              SHOW INDEX FROM table round-trip; D147 §A.2 H2)
//   1 byte:    decimals       (KEEP — D155 Phase 1; JDBC §15.4 getScale)
//   2 byte:    reserved 0x0000(skip — implicit; payload tail is ignored)
function parseColumnDef(payload: string): ColumnDef {
    const col = new ColumnDef("", 0, 0, 0, "", 0, "", "", "", "", 0)
    let off = 0
    col.catalog = readLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    col.schema = readLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    col.table = readLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    col.orgTable = readLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    col.name = readLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    col.orgName = readLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    off = off + 1
    col.charset = byteToInt(payload, off, 2)
    off = off + 2
    col.columnLen = byteToInt(payload, off, 4)
    off = off + 4
    col.colType = charCodeAt(payload, off)
    off = off + 1
    col.flags = byteToInt(payload, off, 2)
    off = off + 2
    col.decimals = charCodeAt(payload, off)
    return col
}

function readColumnDef(fd: int): ColumnDef {
    const pkt = readPacket(fd)
    return parseColumnDef(pkt.payload)
}

// Cross-module accessors. lib/com/mysql/prepared.ss needs columnDefs[i].colType
// + colMetadata[i].name for binary protocol decode; emitting GEP %ColumnDef from
// prepared.ss directly causes llc 'base element must be sized' since prepared.ss
// IR is concatenated before query.ss declares %ColumnDef. Routing the field
// access through a function defined here keeps the GEP inside the same module
// where the type is declared. D136 prepared.ss Phase 1 header note pinned this
// constraint; Phase 2 honors it. Compiler-side fix (IR type-decl emission
// ordering) is a follow-up beyond D136 scope.
function columnDefColType(col: ColumnDef): int {
    return col.colType
}

function columnDefName(col: ColumnDef): string {
    return col.name
}

// D147 Phase 3 — driver-side updatable cursor accessors. derivePkColumn /
// deriveTableName (lib/com/mysql/prepared.ss) walk Array<ColumnDef> and need
// orgTable + flags via the same indirect path columnDefName / columnDefColType
// document. Direct GEP %ColumnDef from prepared.ss forward-references the type
// (prepared.ss IR is concatenated before query.ss declares the struct), so the
// access has to live in this module.
function columnDefOrgTable(col: ColumnDef): string {
    return col.orgTable
}

function columnDefFlags(col: ColumnDef): int {
    return col.flags
}

// D155 Phase 1 — JDBC ResultSetMetaData ≥21 method 反射派生 accessor.
// Same indirect-access constraint columnDefName / columnDefColType /
// columnDefOrgTable / columnDefFlags document — prepared.ss IR + the
// future MysqlResultSetMetaData class IR are concatenated before query.ss
// declares %ColumnDef, so direct GEP forward-references the type and llc
// rejects 'base element of getelementptr must be sized'. Routing the GEP
// through a function defined here keeps the access inside the owning module.
//
// columnDefMaxColumnLength surfaces the JDBC §15.4 spec name (the field that
// drives ResultSetMetaData.getColumnDisplaySize / getPrecision) while the
// underlying ColumnDef field keeps its MySQL Native Protocol name `columnLen`
// (the wire-spec calls it `column_length`). Same protocol→API split D147
// Phase 3 codified for columnDefName / col.name — the storage layer keeps
// the protocol name, the cross-module accessor exposes the JDBC view.
function columnDefCatalog(col: ColumnDef): string {
    return col.catalog
}

function columnDefSchema(col: ColumnDef): string {
    return col.schema
}

function columnDefTable(col: ColumnDef): string {
    return col.table
}

function columnDefOrgName(col: ColumnDef): string {
    return col.orgName
}

function columnDefCharset(col: ColumnDef): int {
    return col.charset
}

function columnDefMaxColumnLength(col: ColumnDef): int {
    return col.columnLen
}

function columnDefDecimals(col: ColumnDef): int {
    return col.decimals
}

// ── D155 §Phase 3 — MySQL flag bits (集中协议常量) ──────────
// MySQL Native Protocol §6.6 column definition packet flags i16 LE
// (column.flags field of ColumnDefinition41). Each bit encodes a
// per-column attribute (NOT NULL / PRIMARY KEY / AUTO_INCREMENT / ...).
// MysqlResultSetMetaData.isNullable / isAutoIncrement / isSigned /
// isCaseSensitive derive directly from these bits without a SHOW INDEX
// / INFORMATION_SCHEMA round-trip. derivePkColumn (lib/com/mysql/
// prepared.ss D147 Phase 4) discovers the PK column the same way.
//
// Connector/J range bits 0x0001-0x8000 stable across MySQL 5.0 -> 8.0 +
// MariaDB (D155 §A.2 H2). PRI_KEY_FLAG was originally added in D147 Phase
// 3 (lib/com/mysql/prepared.ss); D155 Phase 3 collects all 13 bits in
// the protocol-layer module so prepared.ss can drop its duplicate
// definition and import from here.
const NOT_NULL_FLAG = 0x0001
const PRI_KEY_FLAG = 0x0002
const UNIQUE_KEY_FLAG = 0x0004
const MULTIPLE_KEY_FLAG = 0x0008
const BLOB_FLAG = 0x0010
const UNSIGNED_FLAG = 0x0020
const ZEROFILL_FLAG = 0x0040
const BINARY_FLAG = 0x0080
const ENUM_FLAG = 0x0100
const AUTO_INCREMENT_FLAG = 0x0200
const TIMESTAMP_FLAG = 0x0400
const SET_FLAG = 0x0800
const NUM_FLAG = 0x8000

// ── D155 §Phase 3 — MySQL colType byte → JDBC type mapping ──
// MySQL Native Protocol §11.6 column type field (ColumnDefinition41
// column_type, 1 byte). Maps each protocol byte to the JDBC §13.1
// java.sql.Types int code MysqlResultSetMetaData.getColumnType returns.
// Static if-cascade mapping table (D155 §核心原则 4) — no runtime
// case dispatch. Connector/J `MysqlType` byte→type table stable
// across MySQL 5.x -> 8.0 (D155 §A.2 H3 unique mapping).
//
// MYSQL_TYPE_xxx byte constants (Connector/J `MysqlDefs` source):
//   0x00 DECIMAL     0x01 TINY        0x02 SHORT      0x03 LONG
//   0x04 FLOAT       0x05 DOUBLE      0x06 NULL       0x07 TIMESTAMP
//   0x08 LONGLONG    0x09 INT24       0x0A DATE       0x0B TIME
//   0x0C DATETIME    0x0D YEAR        0x0F VARCHAR    0x10 BIT
//   0xF6 NEWDECIMAL  0xF7 ENUM        0xF8 SET
//   0xF9 TINY_BLOB   0xFA MEDIUM_BLOB 0xFB LONG_BLOB  0xFC BLOB
//   0xFD VAR_STRING  0xFE STRING      0xFF GEOMETRY
function mysqlTypeToJdbcType(mysqlType: int): int {
    if (mysqlType == 0x00) { return JDBC_TYPE_DECIMAL }
    if (mysqlType == 0x01) { return JDBC_TYPE_TINYINT }
    if (mysqlType == 0x02) { return JDBC_TYPE_SMALLINT }
    if (mysqlType == 0x03) { return JDBC_TYPE_INTEGER }
    if (mysqlType == 0x04) { return JDBC_TYPE_FLOAT }
    if (mysqlType == 0x05) { return JDBC_TYPE_DOUBLE }
    if (mysqlType == 0x06) { return JDBC_TYPE_NULL }
    if (mysqlType == 0x07) { return JDBC_TYPE_TIMESTAMP }
    if (mysqlType == 0x08) { return JDBC_TYPE_BIGINT }
    if (mysqlType == 0x09) { return JDBC_TYPE_INTEGER }
    if (mysqlType == 0x0A) { return JDBC_TYPE_DATE }
    if (mysqlType == 0x0B) { return JDBC_TYPE_TIME }
    if (mysqlType == 0x0C) { return JDBC_TYPE_TIMESTAMP }
    if (mysqlType == 0x0D) { return JDBC_TYPE_DATE }
    if (mysqlType == 0x0F) { return JDBC_TYPE_VARCHAR }
    if (mysqlType == 0x10) { return JDBC_TYPE_BIT }
    if (mysqlType == 0xF6) { return JDBC_TYPE_DECIMAL }
    if (mysqlType == 0xF7) { return JDBC_TYPE_CHAR }
    if (mysqlType == 0xF8) { return JDBC_TYPE_CHAR }
    if (mysqlType == 0xF9) { return JDBC_TYPE_LONGVARBINARY }
    if (mysqlType == 0xFA) { return JDBC_TYPE_LONGVARBINARY }
    if (mysqlType == 0xFB) { return JDBC_TYPE_LONGVARBINARY }
    if (mysqlType == 0xFC) { return JDBC_TYPE_LONGVARBINARY }
    if (mysqlType == 0xFD) { return JDBC_TYPE_VARCHAR }
    if (mysqlType == 0xFE) { return JDBC_TYPE_CHAR }
    if (mysqlType == 0xFF) { return JDBC_TYPE_VARBINARY }
    return JDBC_TYPE_VARCHAR
}

// SQL type name string returned by ResultSetMetaData.getColumnTypeName.
// Matches MySQL Connector/J `MysqlType.getName()` strings — these
// surface in DDL statements (e.g. "VARCHAR" / "DECIMAL"), so callers
// running `metadata.getColumnTypeName(c)` see the exact MySQL keyword
// they would write in CREATE TABLE.
function mysqlTypeName(mysqlType: int): string {
    if (mysqlType == 0x00) { return "DECIMAL" }
    if (mysqlType == 0x01) { return "TINYINT" }
    if (mysqlType == 0x02) { return "SMALLINT" }
    if (mysqlType == 0x03) { return "INT" }
    if (mysqlType == 0x04) { return "FLOAT" }
    if (mysqlType == 0x05) { return "DOUBLE" }
    if (mysqlType == 0x06) { return "NULL" }
    if (mysqlType == 0x07) { return "TIMESTAMP" }
    if (mysqlType == 0x08) { return "BIGINT" }
    if (mysqlType == 0x09) { return "MEDIUMINT" }
    if (mysqlType == 0x0A) { return "DATE" }
    if (mysqlType == 0x0B) { return "TIME" }
    if (mysqlType == 0x0C) { return "DATETIME" }
    if (mysqlType == 0x0D) { return "YEAR" }
    if (mysqlType == 0x0F) { return "VARCHAR" }
    if (mysqlType == 0x10) { return "BIT" }
    if (mysqlType == 0xF6) { return "DECIMAL" }
    if (mysqlType == 0xF7) { return "ENUM" }
    if (mysqlType == 0xF8) { return "SET" }
    if (mysqlType == 0xF9) { return "TINYBLOB" }
    if (mysqlType == 0xFA) { return "MEDIUMBLOB" }
    if (mysqlType == 0xFB) { return "LONGBLOB" }
    if (mysqlType == 0xFC) { return "BLOB" }
    if (mysqlType == 0xFD) { return "VARCHAR" }
    if (mysqlType == 0xFE) { return "CHAR" }
    if (mysqlType == 0xFF) { return "GEOMETRY" }
    return "UNKNOWN"
}

// Java class name returned by ResultSetMetaData.getColumnClassName.
// Matches MySQL Connector/J `MysqlType.getClassName()` Java FQN —
// reflection-based ORM (Hibernate `BeanPropertyRowMapper`) reads this
// to pick the field setter. SS lacks `java.lang.Long` / `BigDecimal`
// real classes, but the FQN string is preserved verbatim so a
// downstream JVM bridge (or SS reflection consumer) can dispatch
// against the same class names a JDK driver would publish.
function mysqlTypeToJavaClassName(mysqlType: int): string {
    if (mysqlType == 0x00) { return "java.math.BigDecimal" }
    if (mysqlType == 0x01) { return "java.lang.Integer" }
    if (mysqlType == 0x02) { return "java.lang.Integer" }
    if (mysqlType == 0x03) { return "java.lang.Integer" }
    if (mysqlType == 0x04) { return "java.lang.Float" }
    if (mysqlType == 0x05) { return "java.lang.Double" }
    if (mysqlType == 0x06) { return "java.lang.Object" }
    if (mysqlType == 0x07) { return "java.sql.Timestamp" }
    if (mysqlType == 0x08) { return "java.lang.Long" }
    if (mysqlType == 0x09) { return "java.lang.Integer" }
    if (mysqlType == 0x0A) { return "java.sql.Date" }
    if (mysqlType == 0x0B) { return "java.sql.Time" }
    if (mysqlType == 0x0C) { return "java.sql.Timestamp" }
    if (mysqlType == 0x0D) { return "java.sql.Date" }
    if (mysqlType == 0x0F) { return "java.lang.String" }
    if (mysqlType == 0x10) { return "java.lang.Boolean" }
    if (mysqlType == 0xF6) { return "java.math.BigDecimal" }
    if (mysqlType == 0xF7) { return "java.lang.String" }
    if (mysqlType == 0xF8) { return "java.lang.String" }
    if (mysqlType == 0xF9) { return "[B" }
    if (mysqlType == 0xFA) { return "[B" }
    if (mysqlType == 0xFB) { return "[B" }
    if (mysqlType == 0xFC) { return "[B" }
    if (mysqlType == 0xFD) { return "java.lang.String" }
    if (mysqlType == 0xFE) { return "java.lang.String" }
    if (mysqlType == 0xFF) { return "[B" }
    return "java.lang.Object"
}

// ResultSetMetaData.isCaseSensitive(col) — charset-aware. MySQL charset
// IDs 33 (utf8_general_ci) / 8 (latin1_swedish_ci) / 45 (utf8mb4_general_
// ci) are case-insensitive collations; everything else (incl. _bin / _cs
// variants) is case-sensitive. BLOB / GEOMETRY are always binary →
// always case-sensitive (case is a meaningless concept for raw bytes).
// Numeric / date / null types are case-irrelevant — return 0.
function mysqlTypeIsCaseSensitive(mysqlType: int, charset: int): int {
    if (mysqlType == 0xF9) { return 1 }
    if (mysqlType == 0xFA) { return 1 }
    if (mysqlType == 0xFB) { return 1 }
    if (mysqlType == 0xFC) { return 1 }
    if (mysqlType == 0xFF) { return 1 }
    if (mysqlType == 0xFD || mysqlType == 0xFE || mysqlType == 0x0F || mysqlType == 0xF7 || mysqlType == 0xF8) {
        if (charset == 33) { return 0 }
        if (charset == 8) { return 0 }
        if (charset == 45) { return 0 }
        return 1
    }
    return 0
}

// ── D155 §Phase 3 — MysqlResultSetMetaData real reflection ──
// Single-field class wrapping the Array<ColumnDef> the driver already
// parsed off the wire (parseColumnDef at construction time). All ≥21
// method dispatch derive their value from colMetadata[col-1] — no
// extra state, no INFORMATION_SCHEMA round-trip (D155 §A.2 H4 —
// Connector/J 5.1+ MysqlResultSetMetaData range model: column
// descriptor reflection only).
//
// `col` parameter is 1-based per JDBC §15.4 spec (col=1 is the first
// column; getColumnCount returns the count). Out-of-range col values
// (col < 1 or col > colMetadata.length()) are not validated here; the
// SS driver follows the JDBC contract that callers respect the
// 1..getColumnCount range. Real Connector/J throws SQLException on
// out-of-range — left to D155 §Followup F4 alongside Wrapper.unwrap.
class MysqlResultSetMetaData : ResultSetMetaData {
    colMetadata: Array<ColumnDef>

    function getColumnCount(): int {
        return this.colMetadata.length()
    }

    function getColumnName(col: int): string {
        return columnDefName(this.colMetadata[col - 1])
    }

    function getColumnLabel(col: int): string {
        return columnDefName(this.colMetadata[col - 1])
    }

    function getColumnType(col: int): int {
        return mysqlTypeToJdbcType(columnDefColType(this.colMetadata[col - 1]))
    }

    function getColumnTypeName(col: int): string {
        return mysqlTypeName(columnDefColType(this.colMetadata[col - 1]))
    }

    function getColumnDisplaySize(col: int): int {
        return columnDefMaxColumnLength(this.colMetadata[col - 1])
    }

    function getColumnClassName(col: int): string {
        return mysqlTypeToJavaClassName(columnDefColType(this.colMetadata[col - 1]))
    }

    function getCatalogName(col: int): string {
        return columnDefCatalog(this.colMetadata[col - 1])
    }

    function getSchemaName(col: int): string {
        return columnDefSchema(this.colMetadata[col - 1])
    }

    function getTableName(col: int): string {
        return columnDefTable(this.colMetadata[col - 1])
    }

    function isNullable(col: int): int {
        const f = columnDefFlags(this.colMetadata[col - 1])
        if ((f & NOT_NULL_FLAG) != 0) { return columnNoNulls }
        return columnNullable
    }

    function isAutoIncrement(col: int): int {
        const f = columnDefFlags(this.colMetadata[col - 1])
        if ((f & AUTO_INCREMENT_FLAG) != 0) { return 1 }
        return 0
    }

    function isCaseSensitive(col: int): int {
        const colDef = this.colMetadata[col - 1]
        return mysqlTypeIsCaseSensitive(columnDefColType(colDef), columnDefCharset(colDef))
    }

    function isCurrency(col: int): int { return 0 }

    function isDefinitelyWritable(col: int): int { return 1 }

    function isReadOnly(col: int): int { return 0 }

    function isSearchable(col: int): int { return 1 }

    function isSigned(col: int): int {
        const f = columnDefFlags(this.colMetadata[col - 1])
        if ((f & UNSIGNED_FLAG) != 0) { return 0 }
        return 1
    }

    function isWritable(col: int): int { return 1 }

    function getPrecision(col: int): int {
        return columnDefMaxColumnLength(this.colMetadata[col - 1])
    }

    function getScale(col: int): int {
        return columnDefDecimals(this.colMetadata[col - 1])
    }
}

// ── D155 §Phase 2 — NoopResultSetMetaData stub ──────────────
// Phase 2 stub class shared by 3 lib implementor (MysqlResultSet /
// MysqlBinaryResultSet / GeneratedKeyResultSet) — every method returns
// the JDBC ResultSetMetaData zero / empty value so callers obtain a
// non-null reference that walks the ≥21-method vtable cleanly. Phase 3
// replaces 3 implementor returns with `new MysqlResultSetMetaData(
// colMetadata)` real reflection (D155 §Phase 收关锚 §Phase 3 line
// 101-109); GeneratedKeyResultSet keeps a 1-col GENERATED_KEY BIGINT
// stub via H5 (synthetic ResultSet only ever exposes lastInsertId).
//
// The stub also serves as the test-side mock under
// tests/d155_resultset_metadata/phase2_spike_test.ss — instantiated
// directly to verify ≥21 method are reachable through the vtable
// without a live MySQL socket.
class NoopResultSetMetaData : ResultSetMetaData {
    function getColumnCount(): int { return 0 }
    function getColumnName(col: int): string { return "" }
    function getColumnLabel(col: int): string { return "" }
    function getColumnType(col: int): int { return 0 }
    function getColumnTypeName(col: int): string { return "" }
    function getColumnDisplaySize(col: int): int { return 0 }
    function getColumnClassName(col: int): string { return "" }
    function getCatalogName(col: int): string { return "" }
    function getSchemaName(col: int): string { return "" }
    function getTableName(col: int): string { return "" }
    function isNullable(col: int): int { return columnNullableUnknown }
    function isAutoIncrement(col: int): int { return 0 }
    function isCaseSensitive(col: int): int { return 0 }
    function isCurrency(col: int): int { return 0 }
    function isDefinitelyWritable(col: int): int { return 0 }
    function isReadOnly(col: int): int { return 1 }
    function isSearchable(col: int): int { return 0 }
    function isSigned(col: int): int { return 0 }
    function isWritable(col: int): int { return 0 }
    function getPrecision(col: int): int { return 0 }
    function getScale(col: int): int { return 0 }
}

// Legacy EOF marker: 0xFE header + payload length < 9 bytes.
// Distinguishes from a row whose first column happens to start with 0xFE
// length-encoded prefix (which would imply an 8-byte length following — a
// 2^32-byte column, far above any realistic max_allowed_packet).
function isEofPacket(payload: string, payloadLen: int): int {
    if (payloadLen <= 0) { return 0 }
    if (payloadLen >= 9) { return 0 }
    if (charCodeAt(payload, 0) != EOF_HEADER) { return 0 }
    return 1
}

// Parses one row (text protocol) from `payload`. Each column is either a
// length-encoded string or a single 0xFB byte (SQL NULL — represented as
// the empty string in SS, since lib/java/sql.ss ResultSet.getString returns
// string with no separate null sentinel).
function parseRow(payload: string, colCount: int): Array<string> {
    let row: Array<string> = []
    let off = 0
    let i = 0
    while (i < colCount) {
        const first = charCodeAt(payload, off)
        if (first == NULL_MARKER) {
            row = row.push("")
            off = off + 1
        } else {
            const len = readLengthEncodedInt(payload, off)
            const sz = lengthEncodedIntSize(payload, off)
            row = row.push(readLengthEncodedString(payload, off))
            off = off + sz + len
        }
        i = i + 1
    }
    return row
}

// MySQL ResultSet — implements lib/java/sql.ss D025 ResultSet interface.
// Streaming model: next() reads one row packet at a time; column metadata is
// loaded once at construction (by readQueryResultSet). close() drains any
// remaining packets so the socket stays in sync for the next query.
class MysqlResultSet : ResultSet {
    fd: int
    // SELECT path = column count; OK path = RESULT_SET_HEADER_OK (-2); ERR
    // path throws via parseResultSetHeader before the ResultSet is built.
    colCount: int
    colMetadata: Array<ColumnDef>
    currentRow: Array<string>
    closed: int
    hasMoreRows: int
    // ── D155 §Phase 3 — lazy MysqlResultSetMetaData cache ──────
    // metaDataCache holds a NoopResultSetMetaData sentinel until first
    // getMetaData() call replaces it with the real reflection wrapper.
    // metaDataInited flips 0 → 1 on the first call so subsequent calls
    // return the same instance — the JDBC §15.4 contract permits
    // ResultSetMetaData to outlive the ResultSet (D155 §A.2 H7), so a
    // per-ResultSet single instance is safe. Interface-typed field is
    // safe now that codegen routes deep_clone through the obj's
    // TypeInfo.deep_clone_fn slot (D018 vtable) — see
    // bootstrap/gen/gen_type_ops.ss isInterfaceType branch.
    metaDataCache: ResultSetMetaData
    metaDataInited: int

    function next(): int {
        if (this.closed != 0 || this.hasMoreRows == 0) { return 0 }
        const pkt = readPacket(this.fd)
        if (pkt.payloadLen <= 0) {
            this.hasMoreRows = 0
            return 0
        }
        if (isEofPacket(pkt.payload, pkt.payloadLen) == 1) {
            this.hasMoreRows = 0
            return 0
        }
        this.currentRow = parseRow(pkt.payload, this.colCount)
        return 1
    }

    private function colIndex(col: string): int {
        let i = 0
        while (i < this.colCount) {
            if (this.colMetadata[i].name == col) { return i }
            i = i + 1
        }
        return -1
    }

    function getString(col: string): string {
        const idx = this.colIndex(col)
        if (idx < 0) { return "" }
        return this.currentRow[idx]
    }

    function getInt(col: string): int {
        return parseInt(this.getString(col))
    }

    function getLong(col: string): int {
        return parseInt(this.getString(col))
    }

    function getDouble(col: string): double {
        return parseDouble(this.getString(col))
    }

    function getBoolean(col: string): int {
        const s = this.getString(col)
        if (s == "1") { return 1 }
        if (s == "true") { return 1 }
        return 0
    }

    // ── D146 Phase 2 stubs — JDBC §15 cursor / scrollable method declarations ───
    // MysqlResultSet wraps the COM_QUERY 0x03 text protocol, which has no
    // server-side cursor (Phase 4 H4 dual semantics live exclusively on
    // MysqlBinaryResultSet via MysqlPreparedStatement.setFetchSize). The
    // setFetchSize call here is informational only — text protocol always
    // streams the entire result set from the socket regardless of fetchSize,
    // so INTEGER_MIN_VALUE / N >= 1 / 0 produce identical wire flow.
    // absolute / first / last / previous / getRow stay forward-only no-ops
    // (callers needing scrollable use prepareStatement + scrollable type).
    function setFetchSize(rows: int) {}
    function getFetchSize(): int { return 0 }
    function absolute(row: int): int { return 0 }
    function first(): int { return 0 }
    function last(): int { return 0 }
    function previous(): int { return 0 }
    function getRow(): int { return 0 }

    // ── D147 Phase 2 stubs — JDBC §15.2.5 update method declarations ────
    // Text protocol (COM_QUERY 0x03) has no updatable cursor surface —
    // simulation lives on MysqlBinaryResultSet via PreparedStatement +
    // CONCUR_UPDATABLE 1008 (D147 §Phase 4). Stubs preserve D025 vtable
    // parity; state queries return 0 so misuse falls through cleanly.
    function updateRow() {}
    function deleteRow() {}
    function insertRow() {}
    function cancelRowUpdates() {}
    function refreshRow() {}
    function moveToInsertRow() {}
    function moveToCurrentRow() {}
    function rowUpdated(): int { return 0 }
    function rowDeleted(): int { return 0 }
    function rowInserted(): int { return 0 }
    function updateInt(col: string, val: int) {}
    function updateString(col: string, val: string) {}
    function updateLong(col: string, val: int) {}
    function updateBoolean(col: string, val: int) {}
    function updateDouble(col: string, val: double) {}
    function updateNull(col: string) {}
    // ── D151 Phase 4 — JDBC 4.3 §15.2.5 update setter type extension ──
    // Text protocol (COM_QUERY 0x03) has no updatable cursor surface;
    // simulation lives on MysqlBinaryResultSet (D147 §Phase 4). All 18
    // typed setters are no-ops here for D025 vtable parity.
    function updateBigDecimal(col: string, val: BigDecimal) {}
    function updateTimestamp(col: string, val: Timestamp) {}
    function updateDate(col: string, val: Date) {}
    function updateTime(col: string, val: Time) {}
    function updateBlob(col: string, val: Blob) {}
    function updateClob(col: string, val: Clob) {}
    function updateNClob(col: string, val: NClob) {}
    function updateRowId(col: string, val: RowId) {}
    function updateSQLXML(col: string, val: SQLXML) {}
    function updateArray(col: string, val: SqlArray) {}
    function updateRef(col: string, val: Ref) {}
    function updateAsciiStream(col: string, val: InputStream) {}
    function updateBinaryStream(col: string, val: InputStream) {}
    function updateCharacterStream(col: string, val: Reader) {}
    function updateNCharacterStream(col: string, val: Reader) {}
    function updateBytes(col: string, val: string) {}
    function updateObject(col: string, val: string) {}
    function updateNString(col: string, val: string) {}

    // D155 Phase 3 — real metadata reflection. text protocol shares
    // the same ColumnDef41 packet path as binary protocol (D155 §A.2 H6),
    // so a MysqlResultSetMetaData wrapping this.colMetadata reflects
    // every JDBC §15.4 column attribute callers ask for. Lazy-cached on
    // first call (metaDataInited 0 → 1) so subsequent ORM reflection
    // loops do not re-allocate.
    function getMetaData(): ResultSetMetaData {
        if (this.metaDataInited == 0) {
            this.metaDataCache = new MysqlResultSetMetaData(this.colMetadata)
            this.metaDataInited = 1
        }
        return this.metaDataCache
    }

    function close() {
        if (this.closed != 0) { return }
        while (this.hasMoreRows != 0) {
            const pkt = readPacket(this.fd)
            if (pkt.payloadLen <= 0) {
                this.hasMoreRows = 0
            } else {
                if (isEofPacket(pkt.payload, pkt.payloadLen) == 1) {
                    this.hasMoreRows = 0
                }
            }
        }
        this.closed = 1
    }
}

// Generated keys ResultSet — wraps a single OkPacket.lastInsertId as a
// single-row, single-column ResultSet conforming to JDBC 4.3 spec
// Statement.getGeneratedKeys() return contract. Column name "GENERATED_KEY"
// matches MySQL Connector/J standard (JDBC drivers publish the column under
// this exact name regardless of underlying schema). The owning Statement
// already drained the OK packet during executeUpdate, so this ResultSet holds
// no socket-side state — close() is a no-op.
//
// Cursor model: firstAccessed = 0 → next() advances to the synthetic row and
// returns 1; firstAccessed = 1 → next() returns 0 (past end). Mirrors the
// JDBC contract that getGeneratedKeys returns a pre-positioned ResultSet
// whose first next() call advances onto the single row.
class GeneratedKeyResultSet : ResultSet {
    key: int
    firstAccessed: int
    // ── D155 §Phase 3 — lazy synthetic 1-col metadata cache ─────
    // GeneratedKeyResultSet has no ColumnDef41 packet from the wire
    // (the synthetic ResultSet wraps OkPacket.lastInsertId, not a
    // SELECT response — D138 Phase 2). H5 specifies a hard-coded
    // single-column GENERATED_KEY BIGINT shape per JDBC §13.6.4 spec.
    // Same lazy cache + interface field idiom as MysqlResultSet.
    metaDataCache: ResultSetMetaData
    metaDataInited: int

    function next(): int {
        if (this.firstAccessed != 0) { return 0 }
        this.firstAccessed = 1
        return 1
    }

    function getString(col: string): string {
        if (col == "GENERATED_KEY") { return "" + this.key }
        return ""
    }

    function getInt(col: string): int {
        return parseInt(this.getString(col))
    }

    function getLong(col: string): int {
        return parseInt(this.getString(col))
    }

    function getDouble(col: string): double {
        return parseDouble(this.getString(col))
    }

    function getBoolean(col: string): int {
        const s = this.getString(col)
        if (s == "1") { return 1 }
        if (s == "true") { return 1 }
        return 0
    }

    // D146 Phase 2/4 — JDBC §15 cursor / scrollable methods. GeneratedKeyResultSet
    // is a synthetic single-row ResultSet (lastInsertId wrapper); the row is
    // already materialized at construction so neither setFetchSize batching
    // nor scrollable positioning has any effect. INTEGER_MIN_VALUE / N >= 1 /
    // 0 all produce the same single-row iteration.
    function setFetchSize(rows: int) {}
    function getFetchSize(): int { return 0 }
    function absolute(row: int): int { return 0 }
    function first(): int { return 0 }
    function last(): int { return 0 }
    function previous(): int { return 0 }
    function getRow(): int { return 0 }

    // D147 Phase 2 stubs — driver-internal synthetic ResultSet has no underlying
    // table / PK / row state to mutate, so all 16 JDBC §15.2.5 update methods
    // are permanent no-ops. The stubs exist purely for D025 vtable parity.
    function updateRow() {}
    function deleteRow() {}
    function insertRow() {}
    function cancelRowUpdates() {}
    function refreshRow() {}
    function moveToInsertRow() {}
    function moveToCurrentRow() {}
    function rowUpdated(): int { return 0 }
    function rowDeleted(): int { return 0 }
    function rowInserted(): int { return 0 }
    function updateInt(col: string, val: int) {}
    function updateString(col: string, val: string) {}
    function updateLong(col: string, val: int) {}
    function updateBoolean(col: string, val: int) {}
    function updateDouble(col: string, val: double) {}
    function updateNull(col: string) {}
    // ── D151 Phase 4 — synthetic single-row ResultSet has no underlying
    // table / PK / row state to mutate; all 18 typed setters stay no-op for
    // D025 vtable parity.
    function updateBigDecimal(col: string, val: BigDecimal) {}
    function updateTimestamp(col: string, val: Timestamp) {}
    function updateDate(col: string, val: Date) {}
    function updateTime(col: string, val: Time) {}
    function updateBlob(col: string, val: Blob) {}
    function updateClob(col: string, val: Clob) {}
    function updateNClob(col: string, val: NClob) {}
    function updateRowId(col: string, val: RowId) {}
    function updateSQLXML(col: string, val: SQLXML) {}
    function updateArray(col: string, val: SqlArray) {}
    function updateRef(col: string, val: Ref) {}
    function updateAsciiStream(col: string, val: InputStream) {}
    function updateBinaryStream(col: string, val: InputStream) {}
    function updateCharacterStream(col: string, val: Reader) {}
    function updateNCharacterStream(col: string, val: Reader) {}
    function updateBytes(col: string, val: string) {}
    function updateObject(col: string, val: string) {}
    function updateNString(col: string, val: string) {}

    // D155 Phase 3 — synthetic single-row ResultSet exposes lastInsertId
    // through a hard-coded 1-col GENERATED_KEY BIGINT shape (§A.2 H5
    // implementation). MySQL Connector/J publishes Statement.
    // getGeneratedKeys() ResultSet under the exact column name
    // "GENERATED_KEY" with java.sql.Types.BIGINT regardless of the
    // underlying schema — the AUTO_INCREMENT_FLAG + NOT_NULL_FLAG +
    // PRI_KEY_FLAG + UNSIGNED_FLAG bits encode the auto-generated
    // primary-key semantics (lastInsertId is unsigned BIGINT in MySQL).
    function getMetaData(): ResultSetMetaData {
        if (this.metaDataInited == 0) {
            let cd: Array<ColumnDef> = []
            const flags = AUTO_INCREMENT_FLAG | NOT_NULL_FLAG | PRI_KEY_FLAG | UNSIGNED_FLAG
            cd = cd.push(new ColumnDef("GENERATED_KEY", 0x08, 20, 63, "", flags, "", "", "", "", 0))
            this.metaDataCache = new MysqlResultSetMetaData(cd)
            this.metaDataInited = 1
        }
        return this.metaDataCache
    }

    function close() {
    }
}

// Reads a complete query response and returns a MysqlResultSet positioned
// before the first row (caller must call next() to advance). OK header
// (no result set) returns a closed ResultSet with colCount = -2
// (RESULT_SET_HEADER_OK). ERR header throws an SQLException subclass via
// readResultSetHeader → parseResultSetHeader (D139 §核心原则 3+4).
//
// Wire flow (legacy EOF mode):
//   1. result-set header packet (column count or OK / ERR)
//   2. N column definition packets
//   3. one EOF packet                       ← legacy mode only
//   4. row data packets (next() reads these)
//   5. one terminating EOF / OK packet      ← detected by next()
function readQueryResultSet(fd: int): MysqlResultSet {
    let cols: Array<ColumnDef> = []
    let row: Array<string> = []
    const rs = new MysqlResultSet(fd, 0, cols, row, 0, 0, new NoopResultSetMetaData(), 0)
    const header = readResultSetHeader(fd)
    if (header <= 0) {
        rs.colCount = header
        rs.closed = 1
        return rs
    }
    rs.colCount = header
    let i = 0
    while (i < header) {
        cols = cols.push(readColumnDef(fd))
        i = i + 1
    }
    rs.colMetadata = cols
    readPacket(fd)
    rs.hasMoreRows = 1
    return rs
}

// ── D146 Phase 1: server-side cursor protocol layer ─────────────
// Building blocks for COM_STMT_FETCH 0x1c + EOF status_flags double-flag
// detection. Higher-level wiring (MysqlBinaryResultSet useCursor field /
// JDBC ResultSet setFetchSize / Spring RowCallbackHandler) lives at
// Phase 2-4 — D146 §Phase 收关锚.

// MySQL Native Protocol §6.5 — COM_STMT_FETCH command byte. Sent on a
// previously-opened server cursor (COM_STMT_EXECUTE flags = 0x01) to fetch
// the next batch of binary-protocol rows.
const COM_STMT_FETCH = 0x1c

// MySQL Native Protocol §6.5 — COM_STMT_EXECUTE flags field bit 0.
// Setting this bit on COM_STMT_EXECUTE asks the server to keep the result
// set on its side and emit only column defs + EOF; subsequent
// COM_STMT_FETCH requests stream the rows N at a time. Without the bit
// (default CURSOR_TYPE_NO_CURSOR 0x00 in lib/com/mysql/prepared.ss) the
// server pre-buffers the full result set and floods all rows at once.
const CURSOR_TYPE_READ_ONLY = 0x01

// MySQL Native Protocol §6.5 — COM_STMT_EXECUTE flags field bit 1. Per
// MySQL 5.7+ docs the server treats this identically to bit 0 (READ_ONLY)
// — Updatable cursor is driver-side simulation (MySQL Connector/J 5.0+
// `UpdatableResultSet`). The flag is still emitted for protocol parity +
// future MySQL MERGE_ENABLE_UPDATABLE upgrade path. See D147 §A.2 H1.
const CURSOR_TYPE_FOR_UPDATE = 0x02

// MySQL Native Protocol §EOF_Packet status_flags (i16 LE at payload
// offset 3 in legacy mode). Bit 6 = SERVER_STATUS_CURSOR_EXISTS — server
// still holds rows for this cursor, another COM_STMT_FETCH will return
// more data.
const SERVER_STATUS_CURSOR_EXISTS = 0x0040

// Bit 7 = SERVER_STATUS_LAST_ROW_SENT — cursor exhausted, the server has
// released its row buffer; further COM_STMT_FETCH on this statement_id
// will yield an empty EOF (no rows).
const SERVER_STATUS_LAST_ROW_SENT = 0x0080

// Builds the COM_STMT_FETCH 9-byte payload. Returns Array<int> rather than
// string because the LE-encoded statement_id / num_rows often have
// embedded 0x00 high bytes (e.g. statement_id = 1 → bytes [0x01, 0x00,
// 0x00, 0x00]) and SS string concat with fromCharCode(0) truncates via
// ss_string_concat strlen — see lib/binary.ss header note + lib/com/mysql/
// wire.ss writePacket header construction comment. Caller writes the
// bytes byte-by-byte to the fd via writeStmtFetchPacket; unit tests
// inspect the array directly.
//
// Layout per MySQL Native Protocol §6.5.1.4:
//   1 byte  : 0x1c (COM_STMT_FETCH)
//   4 byte  : statement_id  u32 LE
//   4 byte  : num_rows      u32 LE
//   ────────
//   9 byte  : total payload
function buildStmtFetchPayload(statementId: int, numRows: int): Array<int> {
    // Single 9-element allocation; each push() in SS Array<int> reallocates.
    // Layout maps 1:1 to MySQL Native Protocol §6.5.1.4 field table above.
    return [
        COM_STMT_FETCH,
        statementId & 0xFF,
        (statementId >>> 8) & 0xFF,
        (statementId >>> 16) & 0xFF,
        (statementId >>> 24) & 0xFF,
        numRows & 0xFF,
        (numRows >>> 8) & 0xFF,
        (numRows >>> 16) & 0xFF,
        (numRows >>> 24) & 0xFF
    ]
}

// Sends a COM_STMT_FETCH packet — header (4 bytes) + payload (9 bytes) =
// 13 bytes total. Returns the byte count on success. Like sendComStmtClose
// / sendComStmtExecute in lib/com/mysql/prepared.ss this writes byte-by-
// byte via tcpWriteBytes(fd, fromCharCode(b), 1) — payload contains
// embedded 0x00 in the LE-encoded statement_id / num_rows high bytes,
// which would truncate via writePacket's payload string parameter.
//
// seqId is reset to 0 — every COM_STMT_FETCH is the start of a new
// command/response sequence pair (server replies seqId 1, 2, ... up to
// the terminating EOF).
function writeStmtFetchPacket(fd: int, statementId: int, numRows: int): int {
    const bytes = buildStmtFetchPayload(statementId, numRows)
    const payloadLen = bytes.length()
    tcpWriteBytes(fd, fromCharCode(payloadLen & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode((payloadLen >>> 8) & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode((payloadLen >>> 16) & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode(0), 1)
    let i = 0
    while (i < payloadLen) {
        tcpWriteBytes(fd, fromCharCode(bytes[i] & 0xFF), 1)
        i = i + 1
    }
    return 4 + payloadLen
}

// Extracts the status_flags field (i16 LE) from an EOF_Packet payload.
// Legacy EOF layout (CLIENT_DEPRECATE_EOF unset — see query.ss header):
//   1 byte  : 0xFE header
//   2 byte  : warnings    u16 LE
//   2 byte  : status_flags u16 LE  ← this function returns
// Total 5 bytes. Pre-4.1 servers without CLIENT_PROTOCOL_41 omit the
// status fields — defensive return 0 when payload is too short or the
// header byte is wrong (the caller already drained an EOF; mismatch
// implies wire corruption, not a state we can recover by guessing).
//
// Caller uses bit-AND with SERVER_STATUS_CURSOR_EXISTS (0x0040) /
// SERVER_STATUS_LAST_ROW_SENT (0x0080) to drive cursor lifecycle —
// CURSOR_EXISTS = more rows pending (issue another COM_STMT_FETCH);
// LAST_ROW_SENT = server released the cursor (no more rows).
function eofStatusFlags(payload: string, payloadLen: int): int {
    if (payloadLen < 5) { return 0 }
    if (charCodeAt(payload, 0) != EOF_HEADER) { return 0 }
    return byteToInt(payload, 3, 2)
}
