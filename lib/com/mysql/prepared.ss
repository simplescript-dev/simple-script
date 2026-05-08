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
import { ColumnDef, parseColumnDef, MysqlResultSet, parseResultSetHeader, readUpdateResultPacket, okPacketAffectedRows, okPacketLastInsertId, GeneratedKeyResultSet, columnDefColType, columnDefName, columnDefOrgTable, columnDefFlags, isEofPacket, CURSOR_TYPE_READ_ONLY, CURSOR_TYPE_FOR_UPDATE, SERVER_STATUS_LAST_ROW_SENT, writeStmtFetchPacket, eofStatusFlags, NoopResultSetMetaData, MysqlResultSetMetaData, PRI_KEY_FLAG } from "@/lib/com/mysql/query"
import { PreparedStatement, ResultSet, ResultSetMetaData, ParameterMetaData, TYPE_FORWARD_ONLY, CONCUR_UPDATABLE, SQLException, SQLFeatureNotSupportedException, Timestamp, Date, Time, Blob, Clob, NClob, RowId, SQLXML, SqlArray, Ref } from "@/lib/java/sql"
import { BigDecimal } from "@/lib/java/math"
import { InputStream, Reader } from "@/lib/java/io"

// Reader.readN chunked drain — Reader 接口无 available()(D152 io.ss),
// 只能 chunked loop 读到 EOF(empty string)。8KiB 与 JDK BufferedReader
// 默认 buffer 一致。D151TestStub 同形(integration_test.ss:278-290)。
const READER_CHUNK_BYTES = 8192

function drainReader(r: Reader): string {
    let s = ""
    let cont = 1
    while (cont == 1) {
        const chunk = r.readN(READER_CHUNK_BYTES)
        if (chunk.length() == 0) {
            cont = 0
        } else {
            s = s + chunk
        }
    }
    return s
}

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

// D146 Phase 3 — fallback batch size for COM_STMT_FETCH when scrollable cursor
// opens without an explicit setFetchSize hint. MySQL Connector/J 8.0 uses 100;
// matches the conservative window for in-memory cache fallback.
const DEFAULT_CURSOR_FETCH_SIZE = 100

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
    return new MysqlPreparedStatement(fd, ok.statementId, ok.numParams, paramDefs, paramTypes, paramValues, paramDoubles, paramNullBits, columnDefs, 0, 0, 0, 0, 0)
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
//
// D146 Phase 3 — cursorFlag parameter explicit (caller passes CURSOR_TYPE_NO_CURSOR
// 0x00 for client streaming or CURSOR_TYPE_READ_ONLY 0x01 for server-side cursor;
// MySQL Native Protocol §6.5.1.2 flags byte bit 0). Server-side cursor opens
// when bit 0 is set + the server replies with col defs + EOF (CURSOR_EXISTS)
// without rows; subsequent COM_STMT_FETCH 0x1c packets stream rows in batches.
function sendComStmtExecute(fd: int, statementId: int, paramTypes: Array<int>, paramValues: Array<string>, paramDoubles: Array<double>, paramNullBits: Array<int>, cursorFlag: int): int {
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
    writeByteToFd(fd, cursorFlag)
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

// MysqlBinaryResultSet — binary protocol mirror of query.ss MysqlResultSet,
// extended with D146 server-side cursor + scrollable in-memory cache.
//
// D146 Phase 3 cursor protocol fields:
//   useCursor       0 = client streaming (server pushes full ResultSet, client
//                       drains row-by-row), 1 = server cursor (server holds
//                       ResultSet, client drives via COM_STMT_FETCH batches)
//   fetchSize       rows per COM_STMT_FETCH batch when useCursor=1; 0 falls
//                   back to DEFAULT_CURSOR_FETCH_SIZE inside fetchNextBatch
//   cursorExhausted 1 once an EOF with SERVER_STATUS_LAST_ROW_SENT 0x0080 is
//                   observed — server has freed its row buffer; further
//                   COM_STMT_FETCH yields empty EOF
//   statementId     server-allocated id for COM_STMT_FETCH packet payload
//
// D146 Phase 3 scrollable in-memory cache fields (MySQL 5.7+ has no server
// scrollable cursor — D146 §A.2 H5 fallback to MySQL Connector/J idiom):
//   rsType          TYPE_FORWARD_ONLY 1003 / TYPE_SCROLL_INSENSITIVE 1004 /
//                   TYPE_SCROLL_SENSITIVE 1005; FORWARD_ONLY drops the cache
//                   on every fetchNextBatch (bounded memory),  SCROLL_*
//                   accumulates every row for absolute / previous in-memory
//                   back-track
//   cachedRows      Array<Row> — batch buffer when forward-only cursor;
//                   full row history when scrollable
//   cachedIdx       1-based row position in cachedRows; 0 = not positioned
//
// D147 Phase 4 driver-side updatable cursor fields (MySQL 5.7+ has no server
// SQL-standard updatable cursor — D147 §A.2 H1 driver-side simulation,
// Connector/J 5.0+ pattern):
//   pendingUpdates  col → string-encoded value buffer; updateXxx writes here
//                   while not in insert mode, updateRow flushes via fresh
//                   PreparedStatement UPDATE + clears the Map
//   pendingInserts  buffer of insert-row Maps (each Map = col → val); the
//                   trailing Map is the in-progress insert row added by
//                   moveToInsertRow; insertRow flushes the trailing Map as
//                   `INSERT INTO ... VALUES (...)` and pops it
//   tableName       derived from colMetadata[0].orgTable in
//                   readQueryResultSetBinary (single-table SELECT only)
//   pkColumn        derived from colMetadata flags PRI_KEY_FLAG bit 1
//                   (single PK only — composite PK / no PK / multi-PK
//                   returns "" and triggers SQLFeatureNotSupportedException
//                   from updateRow / deleteRow at flush time)
//   inInsertMode    0 = normal (updateXxx → pendingUpdates), 1 = insert
//                   mode (updateXxx → trailing pendingInserts Map);
//                   moveToInsertRow / moveToCurrentRow toggle this
//   rowState        ROW_STATE_CLEAN / UPDATED / DELETED / INSERTED — set by
//                   updateRow / deleteRow / insertRow, read by rowUpdated /
//                   rowDeleted / rowInserted; reset to CLEAN on every next()
//                   so the JDBC §15.2.5 "current row" semantics holds

// rowState — D147 §核心原则 8 driver-side row-mutation tracking. JDBC
// §15.2.5 rowUpdated / rowDeleted / rowInserted reflect mutations to the
// *current row only*; advancing past via next() resets the tracker.
const ROW_STATE_CLEAN = 0
const ROW_STATE_UPDATED = 1
const ROW_STATE_DELETED = 2
const ROW_STATE_INSERTED = 3

class MysqlBinaryResultSet : ResultSet {
    fd: int
    colCount: int
    colMetadata: Array<ColumnDef>
    currentRow: Array<string>
    closed: int
    hasMoreRows: int
    useCursor: int
    fetchSize: int
    cursorExhausted: int
    statementId: int
    rsType: int
    cachedRows: Array<Array<string>>
    cachedIdx: int
    pendingUpdates: Map<string, string>
    pendingInserts: Array<Map<string, string>>
    tableName: string
    pkColumn: string
    inInsertMode: int
    rowState: int
    // ── D155 §Phase 3 — lazy MysqlResultSetMetaData cache ──────
    // Same idiom as MysqlResultSet (lib/com/mysql/query.ss) — binary
    // protocol shares the ColumnDef41 packet path with text protocol
    // (D155 §A.2 H6). Interface-typed field is safe — codegen routes
    // deep_clone through TypeInfo vtable (gen_type_ops.ss isInterfaceType).
    metaDataCache: ResultSetMetaData
    metaDataInited: int

    function next(): int {
        if (this.closed != 0) { return 0 }
        // D147 Phase 4 H7 — JDBC §15.2.5 rowUpdated / rowDeleted /
        // rowInserted reflect mutations to the *current row only*; advancing
        // to a new row resets the tracker. Reset on every next() call (even
        // when no row is found below) — Connector/J idiom.
        this.rowState = ROW_STATE_CLEAN
        if (this.cachedIdx < this.cachedRows.length()) {
            this.cachedIdx = this.cachedIdx + 1
            this.currentRow = this.cachedRows[this.cachedIdx - 1]
            return 1
        }
        if (this.useCursor == 1) {
            if (this.cursorExhausted != 0) { return 0 }
            return this.fetchNextBatch()
        }
        if (this.hasMoreRows == 0) { return 0 }
        return this.readOneStreamingRow()
    }

    // Sends COM_STMT_FETCH(statementId, fetchSize) and drains the response into
    // cachedRows. For forward-only cursor (rsType == TYPE_FORWARD_ONLY) the
    // cache is reset before refilling so memory stays bounded by fetchSize;
    // scrollable cursors accumulate indefinitely so absolute(N) / previous()
    // can hit the cache without a re-fetch (MySQL 5.7+ has no server
    // scrollable cursor — D146 §A.2 H5).
    private function fetchNextBatch(): int {
        let n = this.fetchSize
        if (n <= 0) { n = DEFAULT_CURSOR_FETCH_SIZE }
        writeStmtFetchPacket(this.fd, this.statementId, n)
        if (this.rsType == TYPE_FORWARD_ONLY) {
            let empty: Array<Array<string>> = []
            this.cachedRows = empty
            this.cachedIdx = 0
        }
        let added = 0
        let draining = 1
        while (draining == 1) {
            const pkt = readPacket(this.fd)
            if (pkt.payloadLen <= 0) {
                this.cursorExhausted = 1
                this.hasMoreRows = 0
                draining = 0
            } else if (isEofPacket(pkt.payload, pkt.payloadLen) == 1) {
                const flags = eofStatusFlags(pkt.payload, pkt.payloadLen)
                if ((flags & SERVER_STATUS_LAST_ROW_SENT) != 0) {
                    this.cursorExhausted = 1
                    this.hasMoreRows = 0
                }
                draining = 0
            } else {
                const row = parseBinaryRow(pkt.payload, pkt.payloadLen, this.colMetadata)
                this.cachedRows = this.cachedRows.push(row)
                added = added + 1
            }
        }
        if (added == 0) { return 0 }
        this.cachedIdx = this.cachedIdx + 1
        this.currentRow = this.cachedRows[this.cachedIdx - 1]
        return 1
    }

    // Reads a single binary row packet from the socket (client streaming path,
    // useCursor=0). Scrollable client streaming (rsType != TYPE_FORWARD_ONLY)
    // appends each row to cachedRows so absolute / previous can back-track
    // without re-issuing the query (MySQL Connector/J 5.7+ idiom).
    private function readOneStreamingRow(): int {
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
        if (this.rsType != TYPE_FORWARD_ONLY) {
            this.cachedRows = this.cachedRows.push(this.currentRow)
            this.cachedIdx = this.cachedRows.length()
        }
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

    // ── D146 Phase 3 — JDBC 4.3 §15 cursor / scrollable methods ────────────
    // setFetchSize / getFetchSize: hint to driver for COM_STMT_FETCH batch size.
    // absolute / first / last / previous: scrollable cursor multi-direction
    // positioning. Forward-only ResultSet (rsType == TYPE_FORWARD_ONLY) returns
    // 0 for absolute / first / last / previous per JDBC spec ("invalid cursor
    // movement on forward-only"); scrollable types drive the in-memory cache.
    //
    // D146 Phase 4 H4 dual-semantics note: cursor mode is decided at
    // executeQuery time from MysqlPreparedStatement.fetchSize (see
    // deriveCursorFlag at prepared.ss:788). Calling setFetchSize on the
    // ResultSet *after* it is open updates the per-batch row count for
    // subsequent COM_STMT_FETCH packets (useCursor=1) but cannot toggle
    // useCursor itself — that decision was already plumbed by
    // plumbCursorState. INTEGER_MIN_VALUE on this method has no effect on
    // useCursor; callers wanting client streaming must call
    // ps.setFetchSize(INTEGER_MIN_VALUE) before executeQuery fires.
    function setFetchSize(rows: int) { this.fetchSize = rows }
    function getFetchSize(): int { return this.fetchSize }

    function absolute(row: int): int {
        if (this.closed != 0) { return 0 }
        if (this.rsType == TYPE_FORWARD_ONLY) { return 0 }
        if (row <= 0) { return 0 }
        while (this.cachedRows.length() < row) {
            if (this.fillOneMore() == 0) { return 0 }
        }
        this.cachedIdx = row
        this.currentRow = this.cachedRows[row - 1]
        return 1
    }

    function first(): int { return this.absolute(1) }

    function last(): int {
        if (this.closed != 0) { return 0 }
        if (this.rsType == TYPE_FORWARD_ONLY) { return 0 }
        while (this.fillOneMore() == 1) {}
        const total = this.cachedRows.length()
        if (total == 0) { return 0 }
        this.cachedIdx = total
        this.currentRow = this.cachedRows[total - 1]
        return 1
    }

    function previous(): int {
        if (this.closed != 0) { return 0 }
        if (this.rsType == TYPE_FORWARD_ONLY) { return 0 }
        if (this.cachedIdx <= 1) {
            this.cachedIdx = 0
            return 0
        }
        this.cachedIdx = this.cachedIdx - 1
        this.currentRow = this.cachedRows[this.cachedIdx - 1]
        return 1
    }

    function getRow(): int { return this.cachedIdx }

    // ── D147 Phase 4 — JDBC §15.2.5 update methods (driver-side simulation) ──
    // updateXxx routes to writeCol — pendingUpdates buffer in normal mode,
    // trailing pendingInserts Map in insert mode. updateRow / deleteRow /
    // insertRow open a fresh PreparedStatement on the same fd (D147 §A.2 H3
    // — server-side cursor is request-response synchronous, so a parallel
    // prepare on the same fd does not break the parked cursor; D146 Phase 5
    // Case 4 already established this fd-reuse pattern). refreshRow re-runs
    // SELECT WHERE pkCol=? and mirrors the fields back into currentRow.
    // cancelRowUpdates is purely client-side (D147 §A.2 H4): in insert mode
    // it resets the trailing pendingInserts Map to a fresh empty Map (so the
    // user can keep building the insert row), in normal mode it drops the
    // pendingUpdates buffer. moveToInsertRow / moveToCurrentRow toggle
    // inInsertMode + push a fresh empty Map onto pendingInserts (D147 §A.2
    // H6). rowUpdated / rowDeleted / rowInserted read rowState which is set
    // by the mutators and reset to CLEAN on every next() advance (D147 §A.2
    // H7). Empty tableName / pkColumn (composite PK / no PK / multi-table)
    // surface as SQLFeatureNotSupportedException via D139 SQLException
    // translator — driver-side simulation degrades gracefully.

    private function writeCol(col: string, val: string) {
        if (this.inInsertMode == 1 && this.pendingInserts.length() > 0) {
            const idx = this.pendingInserts.length() - 1
            const buf = this.pendingInserts[idx]
            buf.set(col, val)
        } else {
            this.pendingUpdates.set(col, val)
        }
    }

    function updateInt(col: string, val: int) { this.writeCol(col, "" + val) }
    function updateString(col: string, val: string) { this.writeCol(col, val) }
    function updateLong(col: string, val: int) { this.writeCol(col, "" + val) }
    function updateBoolean(col: string, val: int) {
        let v = "0"
        if (val != 0) { v = "1" }
        this.writeCol(col, v)
    }
    function updateDouble(col: string, val: double) { this.writeCol(col, "" + val) }
    function updateNull(col: string) { this.writeCol(col, "") }

    // ── D151 Phase 4 — JDBC 4.3 §15.2.5 update setter type extension ──
    // D153 §F2 codegen 修复后(gen_iface.ss 空 impls dispatch fn emit
    // unreachable allow link),interface-typed val 的 toString / getBytes /
    // getSubString / readN dispatch 在 sibling 编译单元无 implementor 时
    // 也能 link 通过(运行时若 hit 则 LLVM unreachable trap)。各 setter
    // 按 JDBC 范式 stringify 后写入 pendingUpdates,与 D151TestStub pattern
    // 同形(tests/d151_*/integration_test.ss:257-274)。
    function updateBigDecimal(col: string, val: BigDecimal) { this.writeCol(col, val.toString()) }
    function updateTimestamp(col: string, val: Timestamp) { this.writeCol(col, val.toString()) }
    function updateDate(col: string, val: Date) { this.writeCol(col, val.toString()) }
    function updateTime(col: string, val: Time) { this.writeCol(col, val.toString()) }
    function updateBlob(col: string, val: Blob) { this.writeCol(col, val.getBytes(1, val.length())) }
    function updateClob(col: string, val: Clob) { this.writeCol(col, val.getSubString(1, val.length())) }
    function updateNClob(col: string, val: NClob) { this.writeCol(col, val.getSubString(1, val.length())) }
    function updateRowId(col: string, val: RowId) { this.writeCol(col, val.toString()) }
    function updateSQLXML(col: string, val: SQLXML) { this.writeCol(col, val.getString()) }
    function updateArray(col: string, val: SqlArray) { this.writeCol(col, val.getArray()) }
    function updateRef(col: string, val: Ref) { this.writeCol(col, val.getObject()) }
    function updateAsciiStream(col: string, val: InputStream) { this.writeCol(col, val.readN(val.available())) }
    function updateBinaryStream(col: string, val: InputStream) { this.writeCol(col, val.readN(val.available())) }
    function updateCharacterStream(col: string, val: Reader) { this.writeCol(col, drainReader(val)) }
    function updateNCharacterStream(col: string, val: Reader) { this.writeCol(col, drainReader(val)) }
    function updateBytes(col: string, val: string) { this.writeCol(col, val) }
    function updateObject(col: string, val: string) { this.writeCol(col, val) }
    function updateNString(col: string, val: string) { this.writeCol(col, val) }

    // Trims the trailing entry of pendingInserts. SS Array<T> has no pop()
    // and Array<T>[i] = X is rejected by codegen (ss_arraySet i64 third arg
    // — phase2_spike line 86 note); we rebuild the array minus the last
    // element and reassign.
    private function popLastInsertRow() {
        if (this.pendingInserts.length() <= 0) { return }
        let trimmed: Array<Map<string, string>> = []
        let i = 0
        const lastIdx = this.pendingInserts.length() - 1
        while (i < lastIdx) {
            trimmed = trimmed.push(this.pendingInserts[i])
            i = i + 1
        }
        this.pendingInserts = trimmed
    }

    function updateRow() {
        // No-op on empty dirty set — JDBC §15.2.5 makes updateRow without
        // preceding updateXxx idempotent (Connector/J also a no-op). Skip
        // both the SQL round-trip and the SQLFeatureNotSupportedException
        // gate so unmutated rows in updatable cursors stay free.
        if (this.pendingUpdates.size() <= 0) {
            this.rowState = ROW_STATE_UPDATED
            return
        }
        if (this.tableName == "" || this.pkColumn == "") {
            throw(new SQLFeatureNotSupportedException("updateRow requires single-table SELECT with single PK column", "0A000", 0))
        }
        let dirtyCols: Array<string> = []
        let dirtyVals: Array<string> = []
        const keys = this.pendingUpdates.keys()
        let i = 0
        while (i < keys.length()) {
            const k = keys[i]
            dirtyCols = dirtyCols.push(k)
            dirtyVals = dirtyVals.push(this.pendingUpdates.get(k))
            i = i + 1
        }
        const sql = buildUpdateRowSql(this.tableName, this.pkColumn, dirtyCols)
        const ps = doPrepare(this.fd, sql)
        let j = 0
        while (j < dirtyCols.length()) {
            ps.setString(j + 1, dirtyVals[j])
            j = j + 1
        }
        ps.setString(dirtyCols.length() + 1, this.currentRow[this.colIndex(this.pkColumn)])
        const affected = ps.executeUpdate()
        ps.close()
        if (affected != 1) {
            throw(new SQLException("updateRow affected " + affected + " rows (expected 1)", "01000", 0))
        }
        let cleared: Map<string, string> = new Map()
        this.pendingUpdates = cleared
        this.rowState = ROW_STATE_UPDATED
    }

    function deleteRow() {
        if (this.tableName == "" || this.pkColumn == "") {
            throw(new SQLFeatureNotSupportedException("deleteRow requires single-table SELECT with single PK column", "0A000", 0))
        }
        const sql = buildDeleteRowSql(this.tableName, this.pkColumn)
        const ps = doPrepare(this.fd, sql)
        ps.setString(1, this.currentRow[this.colIndex(this.pkColumn)])
        const affected = ps.executeUpdate()
        ps.close()
        if (affected != 1) {
            throw(new SQLException("deleteRow affected " + affected + " rows (expected 1)", "01000", 0))
        }
        this.rowState = ROW_STATE_DELETED
    }

    function insertRow() {
        if (this.tableName == "") {
            throw(new SQLFeatureNotSupportedException("insertRow requires single-table SELECT", "0A000", 0))
        }
        if (this.pendingInserts.length() <= 0) {
            throw(new SQLException("insertRow called without moveToInsertRow", "07000", 0))
        }
        const idx = this.pendingInserts.length() - 1
        const buf = this.pendingInserts[idx]
        if (buf.size() <= 0) {
            this.popLastInsertRow()
            throw(new SQLException("insertRow with no updateXxx — empty insert buffer", "07000", 0))
        }
        let cols: Array<string> = []
        let vals: Array<string> = []
        const keys = buf.keys()
        let i = 0
        while (i < keys.length()) {
            const k = keys[i]
            cols = cols.push(k)
            vals = vals.push(buf.get(k))
            i = i + 1
        }
        const sql = buildInsertRowSql(this.tableName, cols)
        const ps = doPrepare(this.fd, sql)
        let j = 0
        while (j < cols.length()) {
            ps.setString(j + 1, vals[j])
            j = j + 1
        }
        const affected = ps.executeUpdate()
        ps.close()
        this.popLastInsertRow()
        if (affected != 1) {
            throw(new SQLException("insertRow affected " + affected + " rows (expected 1)", "01000", 0))
        }
        this.rowState = ROW_STATE_INSERTED
    }

    function cancelRowUpdates() {
        if (this.inInsertMode == 1 && this.pendingInserts.length() > 0) {
            // Reset trailing insert-row buffer to a fresh empty Map; preserve
            // inInsertMode + pendingInserts.length() so subsequent updateXxx
            // continues to land on the trailing Map.
            let trimmed: Array<Map<string, string>> = []
            let i = 0
            const lastIdx = this.pendingInserts.length() - 1
            while (i < lastIdx) {
                trimmed = trimmed.push(this.pendingInserts[i])
                i = i + 1
            }
            let fresh: Map<string, string> = new Map()
            trimmed = trimmed.push(fresh)
            this.pendingInserts = trimmed
        } else {
            let cleared: Map<string, string> = new Map()
            this.pendingUpdates = cleared
        }
        this.rowState = ROW_STATE_CLEAN
    }

    function refreshRow() {
        if (this.tableName == "" || this.pkColumn == "") {
            throw(new SQLFeatureNotSupportedException("refreshRow requires single-table SELECT with single PK column", "0A000", 0))
        }
        let cols: Array<string> = []
        let i = 0
        while (i < this.colCount) {
            cols = cols.push(columnDefName(this.colMetadata[i]))
            i = i + 1
        }
        const sql = buildRefreshRowSql(this.tableName, this.pkColumn, cols)
        const ps = doPrepare(this.fd, sql)
        ps.setString(1, this.currentRow[this.colIndex(this.pkColumn)])
        const rs = ps.executeQuery()
        if (rs.next() == 1) {
            let refreshed: Array<string> = []
            let j = 0
            while (j < this.colCount) {
                refreshed = refreshed.push(rs.getString(columnDefName(this.colMetadata[j])))
                j = j + 1
            }
            this.currentRow = refreshed
        }
        rs.close()
        ps.close()
    }

    function moveToInsertRow() {
        this.inInsertMode = 1
        let fresh: Map<string, string> = new Map()
        this.pendingInserts = this.pendingInserts.push(fresh)
    }

    function moveToCurrentRow() {
        this.inInsertMode = 0
    }

    function rowUpdated(): int {
        if (this.rowState == ROW_STATE_UPDATED) { return 1 }
        return 0
    }

    function rowDeleted(): int {
        if (this.rowState == ROW_STATE_DELETED) { return 1 }
        return 0
    }

    function rowInserted(): int {
        if (this.rowState == ROW_STATE_INSERTED) { return 1 }
        return 0
    }

    // Pulls one more row into cachedRows without advancing currentRow / cachedIdx
    // for absolute / last to size up the cache without disturbing the public
    // cursor position before the final assignment. Returns 1 if a row was
    // appended, 0 if the underlying source is exhausted.
    private function fillOneMore(): int {
        if (this.useCursor == 1) {
            if (this.cursorExhausted != 0) { return 0 }
            const savedIdx = this.cachedIdx
            const savedRow = this.currentRow
            const r = this.fetchNextBatch()
            if (r == 0) {
                this.cachedIdx = savedIdx
                this.currentRow = savedRow
                return 0
            }
            this.cachedIdx = savedIdx
            this.currentRow = savedRow
            return 1
        }
        if (this.hasMoreRows == 0) { return 0 }
        const savedIdx = this.cachedIdx
        const savedRow = this.currentRow
        const r = this.readOneStreamingRow()
        if (r == 0) { return 0 }
        this.cachedIdx = savedIdx
        this.currentRow = savedRow
        return 1
    }

    // D155 Phase 3 — real metadata reflection. Binary protocol shares
    // the same ColumnDef41 packet path as text protocol (D155 §A.2 H6),
    // so a MysqlResultSetMetaData wrapping this.colMetadata reflects
    // every JDBC §15.4 column attribute. Lazy-cached on first call so
    // ORM reflection loops do not re-allocate (D155 simplify efficiency
    // agent Phase 2 prearranged issue).
    function getMetaData(): ResultSetMetaData {
        if (this.metaDataInited == 0) {
            this.metaDataCache = new MysqlResultSetMetaData(this.colMetadata)
            this.metaDataInited = 1
        }
        return this.metaDataCache
    }

    // close() — D146 Phase 3 dual-mode drain. Cursor protocol (useCursor=1) is
    // request-response synchronous (each COM_STMT_FETCH returns rows + EOF
    // before the next FETCH request); when next() returns to user without
    // exhausting the cursor, the server is parked waiting for the next FETCH
    // and the socket has no pending data. Closing the PreparedStatement (which
    // sends COM_STMT_CLOSE 0x19) releases the server-side statement + cursor
    // — so this close() does not drain in cursor mode (D139 finally chain
    // handles fd cleanup at Connection level).
    //
    // Client streaming (useCursor=0): server has flushed the entire ResultSet
    // to the socket; mid-iteration close must drain remaining row + EOF
    // packets so the next command on this fd sees a clean response.
    function close() {
        if (this.closed != 0) { return }
        if (this.useCursor == 1) {
            this.closed = 1
            return
        }
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
//
// D146 Phase 3 — cursor / scrollable fields default to non-cursor / forward-only;
// the executeQuery 3-arg overload (MysqlPreparedStatement.executeQuery(sql,
// type, conc)) sets useCursor / fetchSize / statementId / rsType after
// readQueryResultSetBinary returns, so the legacy 1-arg executeQuery and
// executeUpdate paths leave them at the safe streaming defaults.
function readQueryResultSetBinary(fd: int): MysqlBinaryResultSet {
    let cols: Array<ColumnDef> = []
    let row: Array<string> = []
    let cached: Array<Array<string>> = []
    let pu: Map<string, string> = new Map()
    let pi: Array<Map<string, string>> = []
    const rs = new MysqlBinaryResultSet(fd, 0, cols, row, 0, 0, 0, 0, 0, 0, TYPE_FORWARD_ONLY, cached, 0, pu, pi, "", "", 0, ROW_STATE_CLEAN, new NoopResultSetMetaData(), 0)
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
    // D147 Phase 4 — derive metadata for driver-side updatable cursor.
    // deriveTableName reads colMetadata[0].orgTable; derivePkColumn scans
    // for PRI_KEY_FLAG bit 1. Empty-string fallback (no PK / multi-PK / no
    // rows) is checked at flush time inside updateRow / deleteRow.
    rs.tableName = deriveTableName(cols)
    rs.pkColumn = derivePkColumn(cols)
    readPacket(fd)
    rs.hasMoreRows = 1
    return rs
}

// ── D147 Phase 3 — driver-side updatable cursor SQL templates + PK helpers ──
//
// MySQL has no SQL-standard updatable cursor (5.7+ docs explicit); the driver
// simulates JDBC §15.2.5 update / delete / insert / refresh by issuing a fresh
// PreparedStatement on the same Connection (Connector/J 5.0+ pattern). The
// builders below produce the parameterized SQL each operation needs:
//
//   updateRow   →  buildUpdateRowSql(table, pkCol, dirtyCols)
//   deleteRow   →  buildDeleteRowSql(table, pkCol)
//   insertRow   →  buildInsertRowSql(table, cols)
//   refreshRow  →  buildRefreshRowSql(table, pkCol, cols)
//
// Phase 4 wires these into MysqlBinaryResultSet alongside the pendingUpdates
// Map / pendingInserts Array fields. Phase 3 only lands the helpers + unit
// tests so the Phase 4 surface is small.
//
// These builders trust their inputs (table / column names already vetted by
// derivePkColumn / deriveTableName + Phase 4 caller). No SQL escaping happens
// here — MySQL identifier escape (backtick) belongs in the driver layer that
// owns identifier sanitization, not the SQL template.

// PRI_KEY_FLAG migrated to lib/com/mysql/query.ss (D155 Phase 3 — 13-bit
// MySQL flag集中协议常量). prepared.ss imports it through the existing
// query.ss import statement; derivePkColumn below dispatches against the
// imported constant. Original D147 §A.2 H2 PRI_KEY_FLAG semantics — bit
// 1 (0x0002) of the ColumnDefinition41 flags i16 LE — preserved verbatim.

// Builds `UPDATE <table> SET col1=?, col2=? WHERE <pkCol>=?` for the
// driver-side updateRow path. Empty dirtyCols produces the syntactically
// invalid `UPDATE <table> WHERE <pkCol>=?` — Phase 4 callers check
// `dirtyCols.length() > 0` before invoking, so an empty call is a caller
// bug that surfaces as a server-side syntax error (1064) routed through
// D139 SQLExceptionTranslator.
function buildUpdateRowSql(table: string, pkCol: string, dirtyCols: Array<string>): string {
    let sql = "UPDATE " + table
    const n = dirtyCols.length()
    if (n > 0) {
        sql = sql + " SET "
        let i = 0
        while (i < n) {
            if (i > 0) { sql = sql + ", " }
            sql = sql + dirtyCols[i] + "=?"
            i = i + 1
        }
    }
    sql = sql + " WHERE " + pkCol + "=?"
    return sql
}

// Builds `DELETE FROM <table> WHERE <pkCol>=?` for the driver-side deleteRow
// path. PK binding is the only WHERE — multi-row delete is out of scope
// (caller iterates rs.next() + rs.deleteRow() per row).
function buildDeleteRowSql(table: string, pkCol: string): string {
    return "DELETE FROM " + table + " WHERE " + pkCol + "=?"
}

// Builds `INSERT INTO <table>(col1, col2) VALUES (?, ?)` for the driver-side
// insertRow path. Placeholder count == cols.length() — the matched
// PreparedStatement.setXxx calls happen in Phase 4 from pendingInserts last
// element. Empty cols would emit `INSERT INTO <table>() VALUES ()` which the
// server rejects (1064) — Phase 4 callers gate on `cols.length() > 0`.
function buildInsertRowSql(table: string, cols: Array<string>): string {
    let sql = "INSERT INTO " + table + "("
    const n = cols.length()
    let i = 0
    while (i < n) {
        if (i > 0) { sql = sql + ", " }
        sql = sql + cols[i]
        i = i + 1
    }
    sql = sql + ") VALUES ("
    i = 0
    while (i < n) {
        if (i > 0) { sql = sql + ", " }
        sql = sql + "?"
        i = i + 1
    }
    sql = sql + ")"
    return sql
}

// Builds `SELECT col1, col2 FROM <table> WHERE <pkCol>=?` for the driver-side
// refreshRow path. Empty cols falls back to `SELECT *` so the driver gets at
// least the row image even if Phase 4 forgets to populate cols (defensive,
// matches Connector/J refreshRow fallback when no specific column list is
// available).
function buildRefreshRowSql(table: string, pkCol: string, cols: Array<string>): string {
    let sql = "SELECT "
    const n = cols.length()
    if (n == 0) {
        sql = sql + "*"
    } else {
        let i = 0
        while (i < n) {
            if (i > 0) { sql = sql + ", " }
            sql = sql + cols[i]
            i = i + 1
        }
    }
    sql = sql + " FROM " + table + " WHERE " + pkCol + "=?"
    return sql
}

// Discovers the PK column from a SELECT's column metadata by scanning each
// ColumnDef.flags for PRI_KEY_FLAG bit 1. Returns the first PK column's name
// when exactly one PK exists; returns "" for the no-PK / multi-PK / no-rows
// cases — Phase 4 callers translate "" into SQLFeatureNotSupportedException
// (SQLState 0A000) so updateRow / deleteRow / insertRow on a non-trivial
// schema fails through D139 SQLExceptionTranslator instead of generating
// a malformed WHERE clause. Multi-PK + multi-table-join schemas are covered
// by D147 §Followup F3 (composite key support).
function derivePkColumn(colMetadata: Array<ColumnDef>): string {
    const n = colMetadata.length()
    let pk = ""
    let count = 0
    let i = 0
    while (i < n) {
        const flags = columnDefFlags(colMetadata[i])
        if ((flags & PRI_KEY_FLAG) != 0) {
            if (count == 0) { pk = columnDefName(colMetadata[i]) }
            count = count + 1
        }
        i = i + 1
    }
    if (count == 1) { return pk }
    return ""
}

// Discovers the table name for the SELECT by reading the first column's
// org_table (the unaliased storage table — alias lives in the skipped `table`
// field of ColumnDefinition41). Single-table SELECT is the only supported
// shape; multi-table joins where columns come from different org_tables
// return the first column's table — Phase 4 callers trust the schema is
// single-table. Empty colMetadata returns "" (same trap as derivePkColumn).
// D147 §Followup F3 covers multi-table updatable-view scenarios.
function deriveTableName(colMetadata: Array<ColumnDef>): string {
    if (colMetadata.length() <= 0) { return "" }
    return columnDefOrgTable(colMetadata[0])
}

// NoopParameterMetaData — D157 §Phase 1 stateless stub (7 method 默认值).
// Phase 2 替换为 new MysqlParameterMetaData(paramDefs) 真实现.
class NoopParameterMetaData : ParameterMetaData {
    function getParameterCount(): int { return 0 }
    function getParameterType(idx: int): int { return 0 }
    function getParameterTypeName(idx: int): string { return "" }
    function getParameterClassName(idx: int): string { return "" }
    function getParameterMode(idx: int): int { return parameterModeUnknown }
    function isNullable(idx: int): int { return parameterNullableUnknown }
    function isSigned(idx: int): int { return 0 }
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
    // Last lastInsertId from the most recent executeUpdate; ERR path throws
    // SQLException via readUpdateResultPacket so a failed INSERT never writes
    // here. Default 0 mirrors MysqlStatement.lastInsertId.
    lastInsertId: int
    closed: int
    // D146 Phase 3 cursor hint state.
    //   fetchSize     — driver-specific extension (PreparedStatement interface
    //                   has no setFetchSize in JDBC 4.3 spec; setter below is
    //                   the MySQL driver entry point used by Phase 3 spike).
    //                   Plumbed into MysqlBinaryResultSet.fetchSize at
    //                   executeQuery time so COM_STMT_FETCH batches the right
    //                   row count.
    //   rsType        — set by MysqlConnection.prepareStatement(sql, type, conc)
    //                   so executeQuery() (0-arg) honors the cursor declaration
    //                   from prepareStatement.
    //   concurrency   — JDBC 4.3 ResultSet concurrency mode. Plumbed by
    //                   Connection.prepareStatement(sql, type, conc) via
    //                   setCursorMode below; read by deriveCursorFlag to
    //                   pick CURSOR_TYPE_FOR_UPDATE 0x02 (CONCUR_UPDATABLE
    //                   1008) vs CURSOR_TYPE_READ_ONLY 0x01 (CONCUR_READ_ONLY
    //                   1007). D147 §Phase 1.
    fetchSize: int
    rsType: int
    concurrency: int

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

    // D146 Phase 4 — Implements the PreparedStatement.setFetchSize SSoT
    // (lib/java/sql.ss:127-145 dual-semantics docs). The setter is a
    // plain field write; MySQL Connector/J's three-way fetchSize routing
    // (MIN_VALUE / N>=1 / 0) falls out of deriveCursorFlag's
    // `fetchSize > 0` predicate at the executeQuery dispatch site below.
    function setFetchSize(rows: int) { this.fetchSize = rows }

    // Cross-module cursor hint setter. Direct field writes from jdbc.ss
    // (`ps.rsType = type`) trigger an SS codegen forward-ref llc rejection
    // because the top-level access emits before the foreign struct's type
    // declaration; method dispatch sidesteps this because method bodies emit
    // after struct declarations. Same workaround shape as columnDefColType /
    // columnDefName at query.ss:271-277.
    function setCursorMode(type: int, concurrency: int) {
        this.rsType = type
        this.concurrency = concurrency
    }

    // Cursor flag derivation:
    //   concurrency == CONCUR_UPDATABLE         → 0x02 FOR_UPDATE (driver-
    //                                              side updatable cursor;
    //                                              server treats same as
    //                                              0x01, D147 §A.2 H1)
    //   type != TYPE_FORWARD_ONLY               → 0x01 server cursor +
    //                                              in-memory cache fallback
    //                                              (MySQL 5.7+ has no server
    //                                              scrollable cursor)
    //   type == TYPE_FORWARD_ONLY + fetchSize>0 → 0x01 forward-only cursor
    //   otherwise                               → 0x00 client streaming
    // Caller passes type=0 sentinel from the 0-arg executeQuery() to fall
    // back to this.rsType (set by Connection.prepareStatement(sql,type,conc)).
    // Public (driver-specific extension, not on PreparedStatement interface)
    // so phase1_packet_unit_test can verify dispatch directly.
    function deriveCursorFlag(type: int): int {
        if (this.concurrency == CONCUR_UPDATABLE) {
            return CURSOR_TYPE_FOR_UPDATE
        }
        let effective = type
        if (effective == 0) { effective = this.rsType }
        if (effective != 0 && effective != TYPE_FORWARD_ONLY) {
            return CURSOR_TYPE_READ_ONLY
        }
        if (this.fetchSize > 0) { return CURSOR_TYPE_READ_ONLY }
        return CURSOR_TYPE_NO_CURSOR
    }

    private function plumbCursorState(rs: MysqlBinaryResultSet, cursorFlag: int, type: int) {
        if (cursorFlag == CURSOR_TYPE_READ_ONLY) { rs.useCursor = 1 }
        rs.fetchSize = this.fetchSize
        rs.statementId = this.statementId
        if (type != 0) { rs.rsType = type }
    }

    function executeQuery(): ResultSet {
        const cursorFlag = this.deriveCursorFlag(0)
        sendComStmtExecute(this.fd, this.statementId, this.paramTypes, this.paramValues, this.paramDoubles, this.paramNullBits, cursorFlag)
        const rs = readQueryResultSetBinary(this.fd)
        this.plumbCursorState(rs, cursorFlag, this.rsType)
        return rs
    }

    // sql is informational — PreparedStatement is already bound at
    // prepareStatement time per JDBC 4.3 §A.4.2. The overload mirrors the
    // Statement.executeQuery(sql, type, conc) signature and returns the
    // concrete MysqlBinaryResultSet (this overload is not in the
    // PreparedStatement interface) so callers can inspect cursor / cache
    // fields directly.
    function executeQuery(sql: string, type: int, concurrency: int): MysqlBinaryResultSet {
        const cursorFlag = this.deriveCursorFlag(type)
        sendComStmtExecute(this.fd, this.statementId, this.paramTypes, this.paramValues, this.paramDoubles, this.paramNullBits, cursorFlag)
        const rs = readQueryResultSetBinary(this.fd)
        this.plumbCursorState(rs, cursorFlag, type)
        return rs
    }

    function executeUpdate(): int {
        sendComStmtExecute(this.fd, this.statementId, this.paramTypes, this.paramValues, this.paramDoubles, this.paramNullBits, CURSOR_TYPE_NO_CURSOR)
        const ok = readUpdateResultPacket(this.fd)
        this.lastInsertId = okPacketLastInsertId(ok)
        return okPacketAffectedRows(ok)
    }

    // D138 Phase 2 — JDBC 4.3 §PreparedStatement.getGeneratedKeys returns a
    // ResultSet over the auto-increment ids generated by the most recent
    // executeUpdate. Wraps lastInsertId as single-row, single-column
    // "GENERATED_KEY" — same shape as MysqlStatement.getGeneratedKeys.
    function getGeneratedKeys(): ResultSet {
        return new GeneratedKeyResultSet(this.lastInsertId, 0, new NoopResultSetMetaData(), 0)
    }

    function getLastInsertId(): int {
        return this.lastInsertId
    }

    // D157 §Phase 1 stub — Phase 2 替换为 new MysqlParameterMetaData(this.paramDefs).
    function getParameterMetaData(): ParameterMetaData {
        return new NoopParameterMetaData()
    }

    // Sends COM_STMT_CLOSE; server returns no packet, so no read. Idempotent.
    function close() {
        if (this.closed != 0) { return }
        sendComStmtClose(this.fd, this.statementId)
        this.closed = 1
    }
}
