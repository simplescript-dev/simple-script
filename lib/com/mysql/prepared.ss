// MySQL Prepared Statement protocol (COM_STMT_PREPARE / EXECUTE / CLOSE) —
// D136.
//
// Wire flow (prepare):
//   1. client → server: COM_STMT_PREPARE (0x16) + sql payload (seqId 0)
//   2. server → client: COM_STMT_PREPARE_OK (0x00) + statement_id u32 LE
//      + num_columns u16 LE + num_params u16 LE + filler 0x00 + warning_count
//      u16 LE (12 bytes total payload)
//   3. server → client: num_params × ColumnDef41 packet + EOF (legacy)
//   4. server → client: num_columns × ColumnDef41 packet + EOF (legacy)
//
// Wire flow (execute):
//   1. client → server: COM_STMT_EXECUTE (0x17) + statement_id u32 LE
//      + flags u8 (0x00 CURSOR_TYPE_NO_CURSOR) + iteration_count u32 LE = 1
//      + NULL bitmap (numParams+7)/8 byte (bit i = param i+1 is NULL, +0 offset)
//      + new_params_bound_flag u8 (0x01 first-call sends type info)
//      + param_types numParams * 2 byte (type code u8 + unsigned flag u8)
//      + param values (NULL skipped; INT 4B u32 LE; LONGLONG 8B i64 LE;
//        DOUBLE 8B IEEE 754 LE; VAR_STRING length-encoded)
//   2. server → client: result-set packets — for SELECT this is column count
//      packet + N × ColumnDef41 + EOF + binary row packets + EOF; for
//      INSERT/UPDATE this is a single OK packet.
//
// Binary row format (server → client, post-execute SELECT path):
//   1B header 0x00 + (numColumns+7+2)/8 byte NULL bitmap (bits 0,1 reserved,
//   bit i+2 = column i is NULL, +2 offset distinguishes from execute request
//   +0 offset — D136 §A.4 R1) + binary values for non-NULL columns.
//
// API split: build* / parse* take payload buffers — unit-testable via charCodeAt.
// send* wrappers add fd-level write on top. Mirrors query.ss parse* / read* split.
//
// CLIENT_DEPRECATE_EOF is unset (handshake.ss capFlags), so the server emits
// legacy EOF packets after param defs / column defs / row stream — same as
// query.ss MysqlResultSet's text-protocol path.
//
// IEEE 754 cast — MYSQL_TYPE_DOUBLE encode/decode uses bootstrap builtins
// writeDoubleLE / readDoubleLE (D136 §A.6 + bootstrap/gen/rt/gen_rt_system.ss).
// SS user layer has no double<->bytes cast otherwise (ss_string_concat
// truncates at 0x00, lib/binary.ss header note), so the 5-subset DOUBLE branch
// would drop zero bytes in IEEE 754 without the builtin pair.

import { byteToInt, readLengthEncodedInt, lengthEncodedIntSize, readLengthEncodedString } from "@/lib/binary"
import { readPacket, writePacket, MysqlPacket } from "@/lib/com/mysql/wire"
import { ColumnDef, parseColumnDef, MysqlResultSet, parseResultSetHeader, readUpdateResultPacket, okPacketAffectedRows, okPacketLastInsertId, GeneratedKeyResultSet, columnDefColType, columnDefName, isEofPacket } from "@/lib/com/mysql/query"
import { PreparedStatement, ResultSet } from "@/lib/java/sql"

// Command bytes — MySQL Native Protocol §6.5
const COM_STMT_PREPARE = 0x16
const COM_STMT_EXECUTE = 0x17
const COM_STMT_CLOSE   = 0x19

// Binary value type codes — MySQL Native Protocol §A.6 (5-subset for Phase 2:
// INT / VARCHAR / DOUBLE / LONGLONG / NULL covers business-layer 80%+ of JDBC
// types; TIMESTAMP / DATE / JSON / DECIMAL / BLOB are sub-D follow-ups).
const MYSQL_TYPE_LONG       = 3
const MYSQL_TYPE_DOUBLE     = 5
const MYSQL_TYPE_NULL       = 6
const MYSQL_TYPE_LONGLONG   = 8
const MYSQL_TYPE_VAR_STRING = 253

const PREPARE_OK_HEADER      = 0x00
const PREPARE_OK_PAYLOAD_LEN = 12
const BINARY_ROW_HEADER      = 0x00
const EXECUTE_FIXED_PREFIX_LEN = 10  // 0x17 + statement_id 4B + flags 1B + iteration_count 4B
const NEW_PARAMS_BOUND_FLAG_FIRST = 0x01
const CURSOR_TYPE_NO_CURSOR  = 0x00
const EXECUTE_ITERATION_COUNT = 1

// COM_STMT_PREPARE_OK response — D136 §A.2.
class PrepareOk {
    statementId: int
    numColumns: int
    numParams: int
    warningCount: int
}

// Builds the COM_STMT_PREPARE request payload (without packet header) —
// unit-testable via charCodeAt. Format: 0x16 cmd byte + sql ASCII bytes.
// SQL strings contain no embedded 0x00, so ss_string_concat is safe.
function buildComStmtPreparePayload(sql: string): string {
    return fromCharCode(COM_STMT_PREPARE) + sql
}

// Sends a COM_STMT_PREPARE packet (cmd 0x16 + sql) with seqId reset to 0.
function sendComStmtPrepare(fd: int, sql: string): int {
    const payload = buildComStmtPreparePayload(sql)
    return writePacket(fd, 0, payload, sql.length() + 1)
}

// Parses COM_STMT_PREPARE_OK packet payload. Returns zero-initialized PrepareOk
// on short payload (< 12 bytes) or wrong header; caller detects via statementId
// == 0 (server-allocated ids start at 1) or all-zero numColumns/numParams.
function parsePrepareOk(payload: string, payloadLen: int): PrepareOk {
    const ok = new PrepareOk(0, 0, 0, 0)
    if (payloadLen < PREPARE_OK_PAYLOAD_LEN) { return ok }
    if (charCodeAt(payload, 0) != PREPARE_OK_HEADER) { return ok }
    ok.statementId = byteToInt(payload, 1, 4)
    ok.numColumns = byteToInt(payload, 5, 2)
    ok.numParams = byteToInt(payload, 7, 2)
    // payload[9] = filler 0x00 (skip)
    ok.warningCount = byteToInt(payload, 10, 2)
    return ok
}

function readPrepareOk(fd: int): PrepareOk {
    const pkt = readPacket(fd)
    return parsePrepareOk(pkt.payload, pkt.payloadLen)
}

// Drives the full prepare flow: sendComStmtPrepare → readPrepareOk →
// readParamDef → readColumnDefList → wrap in MysqlPreparedStatement.
// This is the single entry point used by jdbc.ss MysqlConnection.prepareStatement,
// so callers never touch PrepareOk fields directly (cross-module struct field
// access at codegen time can forward-reference %PrepareOk; keeping access inside
// prepared.ss avoids the issue). Phase 2 setXxx relies on the pre-sized
// paramTypes / paramValues / paramDoubles / paramNullBits arrays seeded here.
function doPrepare(fd: int, sql: string): MysqlPreparedStatement {
    sendComStmtPrepare(fd, sql)
    const ok = readPrepareOk(fd)
    const paramDefs = readParamDef(fd, ok.numParams)
    const columnDefs = readColumnDefList(fd, ok.numColumns)
    let paramTypes: Array<int> = []
    let paramValues: Array<string> = []
    let paramDoubles: Array<double> = []
    let paramNullBits: Array<int> = []
    let i = 0
    while (i < ok.numParams) {
        paramTypes = paramTypes.push(0)
        paramValues = paramValues.push("")
        paramDoubles = paramDoubles.push(0.0)
        paramNullBits = paramNullBits.push(0)
        i = i + 1
    }
    return new MysqlPreparedStatement(fd, ok.statementId, ok.numParams, paramDefs, paramTypes, paramValues, paramDoubles, paramNullBits, columnDefs, 0, 0)
}

// Reads numParams × ColumnDef41 packet + 1 trailing legacy EOF packet.
// Returns Array<ColumnDef> — Phase 2 binary value encoding inspects colType
// via a query.ss helper to keep ColumnDef field access inside that module
// (a cross-module GEP from prepared.ss into ColumnDef would forward-reference
// %ColumnDef and llc would reject the IR — circular import order quirk).
// numParams == 0 → returns [] and skips EOF (server omits).
function readParamDef(fd: int, numParams: int): Array<ColumnDef> {
    let cols: Array<ColumnDef> = []
    if (numParams <= 0) { return cols }
    let i = 0
    while (i < numParams) {
        cols = cols.push(parseColumnDef(readPacket(fd).payload))
        i = i + 1
    }
    readPacket(fd)
    return cols
}

// Reads numColumns × ColumnDef41 packet + 1 trailing legacy EOF packet.
// Returns Array<ColumnDef> for Phase 2 binary result set decode (colType
// + columnLen + charset + name all used by parseBinaryRow / getString).
// numColumns == 0 → returns [] and skips EOF (UPDATE / INSERT — no result set).
function readColumnDefList(fd: int, numColumns: int): Array<ColumnDef> {
    let cols: Array<ColumnDef> = []
    if (numColumns <= 0) { return cols }
    let i = 0
    while (i < numColumns) {
        cols = cols.push(parseColumnDef(readPacket(fd).payload))
        i = i + 1
    }
    readPacket(fd)
    return cols
}

// ── Phase 2 byte writers ────────────────────────────────────────
// Direct byte-by-byte fd writes — same pattern as wire.ss writePacket header
// and handshake.ss sendHandshakeResponse41. SS strings cannot carry embedded
// 0x00 across ss_string_concat (gen_rt_string.ss:14-26 strlen-based), and the
// EXECUTE payload is full of zeros (statement_id high bytes, iteration_count
// high bytes, NULL bitmap zero bits, type unsigned flags, integer high bytes,
// IEEE 754 mantissa tails) so per-byte syscalls are the only correct way.

function writeByteToFd(fd: int, b: int) {
    tcpWriteBytes(fd, fromCharCode(b & 0xFF), 1)
}

function writeIntLEToFd(fd: int, n: int, len: int) {
    let i = 0
    while (i < len) {
        writeByteToFd(fd, (n >>> (i * 8)) & 0xFF)
        i = i + 1
    }
}

// Writes the length-encoded prefix (1/3/4/9 byte) + the string body. Mirrors
// lib/binary.ss writeLengthEncodedInt sizing, but skips the intToBytes-style
// concatenation since intToBytes truncates at 0x00 — which kills the prefix
// for any length whose middle bytes happen to be zero (e.g. 256 → 0xFC 0x00 0x01
// would lose the 0x00 in a string-concat path).
function writeLengthEncodedStringToFd(fd: int, s: string) {
    const len = s.length()
    if (len < 0xFB) {
        writeByteToFd(fd, len)
    } else if (len < 65536) {
        writeByteToFd(fd, 0xFC)
        writeIntLEToFd(fd, len, 2)
    } else if (len < 16777216) {
        writeByteToFd(fd, 0xFD)
        writeIntLEToFd(fd, len, 3)
    } else {
        writeByteToFd(fd, 0xFE)
        writeIntLEToFd(fd, len, 8)
    }
    if (len > 0) {
        tcpWriteBytes(fd, s, len)
    }
}

// Returns the on-wire byte size of a single non-NULL binary value.
// MYSQL_TYPE_NULL bytes are tracked via the NULL bitmap, not value bytes.
function binaryValueSize(typeCode: int, val: string): int {
    if (typeCode == MYSQL_TYPE_LONG) { return 4 }
    if (typeCode == MYSQL_TYPE_LONGLONG) { return 8 }
    if (typeCode == MYSQL_TYPE_DOUBLE) { return 8 }
    if (typeCode == MYSQL_TYPE_VAR_STRING) {
        const len = val.length()
        if (len < 0xFB) { return 1 + len }
        if (len < 65536) { return 3 + len }
        if (len < 16777216) { return 4 + len }
        return 9 + len
    }
    return 0
}

// Writes a single non-NULL binary value to fd. dval is consulted only when
// typeCode == MYSQL_TYPE_DOUBLE — for INT/LONGLONG val carries a decimal-string
// representation (set via setInt/setLong), parsed back to int here for binary
// encoding. SS int is i32 (gen_rt_string.ss:7 ss_stringLength signature), so
// MYSQL_TYPE_LONGLONG writes the low 4 bytes verbatim and pads the high 4 with
// zeros — SS cannot represent values >= 2^31 user-side anyway, so this matches
// lib/binary.ss byteToInt's symmetric high-32-bit-truncation read behavior.
function writeBinaryValue(fd: int, typeCode: int, val: string, dval: double) {
    if (typeCode == MYSQL_TYPE_LONG) {
        writeIntLEToFd(fd, parseInt(val), 4)
    } else if (typeCode == MYSQL_TYPE_LONGLONG) {
        writeIntLEToFd(fd, parseInt(val), 4)
        writeIntLEToFd(fd, 0, 4)
    } else if (typeCode == MYSQL_TYPE_DOUBLE) {
        writeDoubleLE(fd, dval)
    } else if (typeCode == MYSQL_TYPE_VAR_STRING) {
        writeLengthEncodedStringToFd(fd, val)
    }
}

// Sends a COM_STMT_EXECUTE packet — D136 §A.3. Returns total bytes written
// (4-byte header + payload). Pre-computes payload length so the header's
// 3-byte LE length field is correct, then emits the entire packet byte-by-byte
// to avoid embedded-0x00 truncation in SS string concat. Field-list signature
// (vs taking a MysqlPreparedStatement) sidesteps the same `getelementptr base
// element must be sized` forward-ref that columnDefColType / columnDefName
// document — top-level functions are emitted before class structs are declared.
function sendComStmtExecute(fd: int, statementId: int, paramTypes: Array<int>, paramValues: Array<string>, paramDoubles: Array<double>, paramNullBits: Array<int>): int {
    const numParams = paramTypes.length()
    const bitmapLen = (numParams + 7) / 8
    let payloadLen = EXECUTE_FIXED_PREFIX_LEN + bitmapLen + 1 + numParams * 2
    let i = 0
    while (i < numParams) {
        if (paramNullBits[i] == 0) {
            payloadLen = payloadLen + binaryValueSize(paramTypes[i], paramValues[i])
        }
        i = i + 1
    }
    writeIntLEToFd(fd, payloadLen, 3)
    writeByteToFd(fd, 0)
    writeByteToFd(fd, COM_STMT_EXECUTE)
    writeIntLEToFd(fd, statementId, 4)
    writeByteToFd(fd, CURSOR_TYPE_NO_CURSOR)
    writeIntLEToFd(fd, EXECUTE_ITERATION_COUNT, 4)
    i = 0
    while (i < bitmapLen) {
        let bm = 0
        let j = 0
        while (j < 8) {
            const idx = i * 8 + j
            if (idx < numParams) {
                if (paramNullBits[idx] == 1) {
                    bm = bm | (1 << j)
                }
            }
            j = j + 1
        }
        writeByteToFd(fd, bm)
        i = i + 1
    }
    writeByteToFd(fd, NEW_PARAMS_BOUND_FLAG_FIRST)
    i = 0
    while (i < numParams) {
        writeByteToFd(fd, paramTypes[i] & 0xFF)
        writeByteToFd(fd, 0x00)
        i = i + 1
    }
    i = 0
    while (i < numParams) {
        if (paramNullBits[i] == 0) {
            writeBinaryValue(fd, paramTypes[i], paramValues[i], paramDoubles[i])
        }
        i = i + 1
    }
    return 4 + payloadLen
}

// ── Phase 2 COM_STMT_CLOSE ─────────────────────────────────────
// Sends a COM_STMT_CLOSE packet (5-byte payload: 0x19 + statement_id u32 LE).
// Server returns no packet — connection-side cleanup only. Returns total bytes
// written (4 header + 5 payload = 9).
function sendComStmtClose(fd: int, statementId: int): int {
    writeIntLEToFd(fd, 5, 3)
    writeByteToFd(fd, 0)
    writeByteToFd(fd, COM_STMT_CLOSE)
    writeIntLEToFd(fd, statementId, 4)
    return 9
}

// ── Phase 2 binary result set ─────────────────────────────────
// Parses a binary protocol row payload — D136 §A.4. NULL bitmap is +2 offset
// (bits 0,1 reserved, bit i+2 = column i is NULL) — a spec quirk that differs
// from the EXECUTE request's +0 offset (R1 risk anchor). Each non-NULL column
// is decoded by colType per the 5-subset (LONG / LONGLONG / DOUBLE / VAR_STRING).
// Unknown colType yields "" — defensive, since we only register columnDefs from
// the server's prepare response, but length-prefixed types we don't decode (e.g.
// TIMESTAMP) cannot be safely skipped without their length prefix logic.
function parseBinaryRow(payload: string, payloadLen: int, columnDefs: Array<ColumnDef>): Array<string> {
    let row: Array<string> = []
    const numColumns = columnDefs.length()
    if (payloadLen <= 0) { return row }
    let off = 1
    const bitmapLen = (numColumns + 7 + 2) / 8
    const bitmapStart = off
    off = off + bitmapLen
    let i = 0
    while (i < numColumns) {
        const bitIdx = i + 2
        const byteIdx = bitmapStart + bitIdx / 8
        const bitInByte = bitIdx & 7
        const nullByte = charCodeAt(payload, byteIdx)
        if ((nullByte & (1 << bitInByte)) != 0) {
            row = row.push("")
        } else {
            const colType = columnDefColType(columnDefs[i])
            if (colType == MYSQL_TYPE_LONG) {
                const n = byteToInt(payload, off, 4)
                row = row.push("" + n)
                off = off + 4
            } else if (colType == MYSQL_TYPE_LONGLONG) {
                const n = byteToInt(payload, off, 8)
                row = row.push("" + n)
                off = off + 8
            } else if (colType == MYSQL_TYPE_DOUBLE) {
                const d = readDoubleLE(payload, off)
                row = row.push("" + d)
                off = off + 8
            } else if (colType == MYSQL_TYPE_VAR_STRING) {
                const sz = lengthEncodedIntSize(payload, off)
                const len = readLengthEncodedInt(payload, off)
                row = row.push(readLengthEncodedString(payload, off))
                off = off + sz + len
            } else {
                row = row.push("")
            }
        }
        i = i + 1
    }
    return row
}

// MysqlBinaryResultSet — binary protocol mirror of query.ss MysqlResultSet:
// same fields, same close()-drain semantics, only next() differs (parseBinaryRow
// vs parseRow). Streaming model: next() reads one row packet at a time and
// decodes via columnDefs.
class MysqlBinaryResultSet : ResultSet {
    fd: int
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
        this.currentRow = parseBinaryRow(pkt.payload, pkt.payloadLen, this.colMetadata)
        return 1
    }

    private function colIndex(col: string): int {
        let i = 0
        while (i < this.colCount) {
            if (columnDefName(this.colMetadata[i]) == col) { return i }
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

// Reads a complete binary-protocol query response and returns a positioned
// MysqlBinaryResultSet. For OK / ERR responses (no result set), returns a
// closed ResultSet with colCount = -2 (RESULT_SET_HEADER_OK) / -1 so callers
// can distinguish update-vs-error. Mirrors query.ss readQueryResultSet flow.
function readQueryResultSetBinary(fd: int): MysqlBinaryResultSet {
    let cols: Array<ColumnDef> = []
    let row: Array<string> = []
    const rs = new MysqlBinaryResultSet(fd, 0, cols, row, 0, 0)
    const headerPkt = readPacket(fd)
    const header = parseResultSetHeader(headerPkt.payload, headerPkt.payloadLen)
    if (header <= 0) {
        rs.colCount = header
        rs.closed = 1
        return rs
    }
    rs.colCount = header
    let i = 0
    while (i < header) {
        cols = cols.push(parseColumnDef(readPacket(fd).payload))
        i = i + 1
    }
    rs.colMetadata = cols
    readPacket(fd)
    rs.hasMoreRows = 1
    return rs
}

// MysqlPreparedStatement — four parallel param-binding arrays indexed by
// idx-1 (JDBC idx is 1-based; SS array is 0-based):
//   - paramTypes: MYSQL_TYPE_xxx code
//   - paramValues: decimal string for INT / LONGLONG / VAR_STRING text
//   - paramDoubles: original double bits when paramTypes[i] == MYSQL_TYPE_DOUBLE.
//     SS has no Array<i64> for IEEE 754 raw bits, and decimal round-trip via
//     paramValues is not bit-identical for all doubles, so a parallel double
//     array is the only correct path until the compiler exposes a raw-bytes
//     Array primitive.
//   - paramNullBits: 1 = NULL (skip value bytes), 0 = bound
class MysqlPreparedStatement : PreparedStatement {
    fd: int
    statementId: int
    numParams: int
    paramDefs: Array<ColumnDef>
    paramTypes: Array<int>
    paramValues: Array<string>
    paramDoubles: Array<double>
    paramNullBits: Array<int>
    columnDefs: Array<ColumnDef>
    // D138 Phase 2 — lastInsertId from the most recent executeUpdate. Default 0;
    // ERR-path executeUpdate (readUpdateResultPacket sentinel affectedRows = -1)
    // does not write — D138 §A.2 H7 防御.
    lastInsertId: int
    closed: int

    // Single bind helper. `this.X[i] = v` is parser-rejected (test confirmed),
    // so we alias each parallel array into a local — Array values are reference
    // so the in-place index-assign reaches the field's backing data.
    private function bindParam(idx: int, typeCode: int, sval: string, dval: double, isNull: int) {
        const types = this.paramTypes
        const values = this.paramValues
        const doubles = this.paramDoubles
        const nullBits = this.paramNullBits
        const i = idx - 1
        types[i] = typeCode
        values[i] = sval
        doubles[i] = dval
        nullBits[i] = isNull
    }

    function setInt(idx: int, val: int) {
        this.bindParam(idx, MYSQL_TYPE_LONG, "" + val, 0.0, 0)
    }

    function setLong(idx: int, val: int) {
        this.bindParam(idx, MYSQL_TYPE_LONGLONG, "" + val, 0.0, 0)
    }

    function setString(idx: int, val: string) {
        this.bindParam(idx, MYSQL_TYPE_VAR_STRING, val, 0.0, 0)
    }

    function setDouble(idx: int, val: double) {
        this.bindParam(idx, MYSQL_TYPE_DOUBLE, "", val, 0)
    }

    // JDBC has no native BOOL; MySQL maps boolean → TINYINT(1). MYSQL_TYPE_LONG
    // is the standard binding (server widens TINY → LONG for bound params), so
    // setBoolean stores 0/1 as a 4-byte int alongside setInt's path.
    function setBoolean(idx: int, val: int) {
        let v = 0
        if (val != 0) { v = 1 }
        this.bindParam(idx, MYSQL_TYPE_LONG, "" + v, 0.0, 0)
    }

    function setNull(idx: int) {
        this.bindParam(idx, MYSQL_TYPE_NULL, "", 0.0, 1)
    }

    function executeQuery(): ResultSet {
        sendComStmtExecute(this.fd, this.statementId, this.paramTypes, this.paramValues, this.paramDoubles, this.paramNullBits)
        return readQueryResultSetBinary(this.fd)
    }

    function executeUpdate(): int {
        sendComStmtExecute(this.fd, this.statementId, this.paramTypes, this.paramValues, this.paramDoubles, this.paramNullBits)
        const ok = readUpdateResultPacket(this.fd)
        const rows = okPacketAffectedRows(ok)
        if (rows >= 0) { this.lastInsertId = okPacketLastInsertId(ok) }
        return rows
    }

    // D138 Phase 2 — JDBC 4.3 §PreparedStatement.getGeneratedKeys returns a
    // ResultSet over the auto-increment ids generated by the most recent
    // executeUpdate. Wraps lastInsertId as single-row, single-column
    // "GENERATED_KEY" — same shape as MysqlStatement.getGeneratedKeys.
    function getGeneratedKeys(): ResultSet {
        return new GeneratedKeyResultSet(this.lastInsertId, 0)
    }

    function getLastInsertId(): int {
        return this.lastInsertId
    }

    // Sends COM_STMT_CLOSE; server returns no packet, so no read. Idempotent.
    function close() {
        if (this.closed != 0) { return }
        sendComStmtClose(this.fd, this.statementId)
        this.closed = 1
    }
}
