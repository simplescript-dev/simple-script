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
import { ResultSet } from "@/lib/java/sql"

const COM_QUERY = 0x03
const NULL_MARKER = 0xFB
const ERR_HEADER = 0xFF
const OK_HEADER = 0x00
const EOF_HEADER = 0xFE
const RESULT_SET_HEADER_ERR = -1
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
//   -1 (RESULT_SET_HEADER_ERR) if first byte = 0xFF (ERR packet)
//   -2 (RESULT_SET_HEADER_OK)  if first byte = 0x00 (OK packet — no rows)
//   N > 0                      length-encoded column count (SELECT result)
//   0                          empty payload / unrecognised
function parseResultSetHeader(payload: string, payloadLen: int): int {
    if (payloadLen <= 0) { return 0 }
    const first = charCodeAt(payload, 0)
    if (first == ERR_HEADER) { return RESULT_SET_HEADER_ERR }
    if (first == OK_HEADER) { return RESULT_SET_HEADER_OK }
    return readLengthEncodedInt(payload, 0)
}

function readResultSetHeader(fd: int): int {
    const pkt = readPacket(fd)
    return parseResultSetHeader(pkt.payload, pkt.payloadLen)
}

// Parses the affected rows count from an OK packet payload. OK packet layout
// (text protocol, CLIENT_PROTOCOL_41 set, no SESSION_TRACK):
//   1 byte:        header (0x00 — OK; 0xFE counts as OK only when payloadLen < 9
//                  AND CLIENT_DEPRECATE_EOF is set, not the case here)
//   lenenc int:    affected rows           ← KEEP
//   lenenc int:    last_insert_id          (skip)
//   2 byte LE:     status flags            (skip)
//   2 byte LE:     warnings count          (skip)
//   ... rest:      info string             (skip)
// Returns 0 if header is not OK (caller already filtered ERR — defensive).
function parseOkPacketAffectedRows(payload: string, payloadLen: int): int {
    if (payloadLen < 2) { return 0 }
    if (charCodeAt(payload, 0) != OK_HEADER) { return 0 }
    return readLengthEncodedInt(payload, 1)
}

// Reads the response to an INSERT / UPDATE / DELETE / DDL command.
// Returns:
//   N >= 0  affected rows (OK packet)
//   -1      error (ERR packet, short read, or unrecognised first byte)
function readUpdateResult(fd: int): int {
    const pkt = readPacket(fd)
    if (pkt.payloadLen <= 0) { return -1 }
    const first = charCodeAt(pkt.payload, 0)
    if (first == ERR_HEADER) { return -1 }
    if (first == OK_HEADER) { return parseOkPacketAffectedRows(pkt.payload, pkt.payloadLen) }
    return -1
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
    // SELECT path = column count; OK / ERR path = sentinel RESULT_SET_HEADER_OK / _ERR.
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

// Reads a complete query response and returns a MysqlResultSet positioned
// before the first row (caller must call next() to advance). For OK / ERR
// responses (no result set), returns a closed ResultSet with colCount set
// to RESULT_SET_HEADER_OK (-2) / RESULT_SET_HEADER_ERR (-1) so the caller
// can distinguish update-vs-error.
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
