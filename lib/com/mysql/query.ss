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
import { ResultSet, SQLException, SQLNonTransientConnectionException, SQLIntegrityConstraintViolationException, SQLSyntaxErrorException, SQLDataException, SQLFeatureNotSupportedException, SQLTransactionRollbackException } from "@/lib/java/sql"

const COM_QUERY = 0x03
const NULL_MARKER = 0xFB
const ERR_HEADER = 0xFF
const OK_HEADER = 0x00
const EOF_HEADER = 0xFE
const RESULT_SET_HEADER_OK = -2

// Column definition (text protocol). Minimal field set — driver-relevant
// metadata only. The wire packet also carries catalog / schema / table /
// org_table / org_name (skipped during parse) and flags / decimals / 2-byte
// reserved (skipped after the 0x0c filler).
class ColumnDef {
    name: string
    colType: int
    columnLen: int
    charset: int
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
//   lenenc str: catalog       (skip)
//   lenenc str: schema        (skip)
//   lenenc str: table         (skip — alias)
//   lenenc str: org_table     (skip)
//   lenenc str: name          (KEEP — column alias used by getString)
//   lenenc str: org_name      (skip)
//   1 byte:    filler 0x0c    (constant length tag for the 12-byte metadata block)
//   2 byte LE: character set
//   4 byte LE: column length
//   1 byte:    column type
//   2 byte LE: flags          (skip)
//   1 byte:    decimals       (skip)
//   2 byte:    reserved 0x0000(skip)
function parseColumnDef(payload: string): ColumnDef {
    const col = new ColumnDef("", 0, 0, 0)
    let off = 0
    off = skipLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    col.name = readLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    off = skipLengthEncodedString(payload, off)
    off = off + 1
    col.charset = byteToInt(payload, off, 2)
    off = off + 2
    col.columnLen = byteToInt(payload, off, 4)
    off = off + 4
    col.colType = charCodeAt(payload, off)
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
    const rs = new MysqlResultSet(fd, 0, cols, row, 0, 0)
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
