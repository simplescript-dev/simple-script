// MySQL Prepared Statement protocol (COM_STMT_PREPARE / EXECUTE / CLOSE) —
// D136 Phase 1.
//
// Phase 1 lands COM_STMT_PREPARE request + COM_STMT_PREPARE_OK response parse +
// param def list read + column def list read + class MysqlPreparedStatement
// framework. setXxx / executeQuery / executeUpdate / close are intentional
// no-op stubs in Phase 1 (no e2e callers yet); Phase 2 swaps in real binary
// protocol (sendComStmtExecute / parseBinaryRow / sendComStmtClose + setXxx
// real value encoding). Phase 3 lands e2e + JdbcTemplate retcon scope.
//
// Wire flow (Phase 1 — prepare only):
//   1. client → server: COM_STMT_PREPARE (0x16) + sql payload (seqId 0)
//   2. server → client: COM_STMT_PREPARE_OK (0x00) + statement_id u32 LE
//      + num_columns u16 LE + num_params u16 LE + filler 0x00 + warning_count
//      u16 LE (12 bytes total payload)
//   3. server → client: num_params × ColumnDef41 packet + EOF (legacy)
//   4. server → client: num_columns × ColumnDef41 packet + EOF (legacy)
//
// API split: build* returns raw payload bytes (without packet header) — unit-
// testable via charCodeAt. send* wrappers add a writePacket(fd, seqId, payload,
// len) on top for production use. Mirrors query.ss parse* / read* split.
//
// CLIENT_DEPRECATE_EOF is unset (see handshake.ss capFlags), so the server
// emits legacy EOF packets after param defs and after column defs — same as
// query.ss MysqlResultSet's text-protocol path.

import { byteToInt } from "@/lib/binary"
import { readPacket, writePacket, MysqlPacket } from "@/lib/com/mysql/wire"
import { ColumnDef, parseColumnDef, MysqlResultSet } from "@/lib/com/mysql/query"
import { PreparedStatement, ResultSet } from "@/lib/java/sql"

// Command bytes — MySQL Native Protocol §6.5
const COM_STMT_PREPARE = 0x16
const COM_STMT_EXECUTE = 0x17
const COM_STMT_CLOSE   = 0x19

// Binary value type codes — MySQL Native Protocol §A.6 (subset for Phase 1+2:
// INT / VARCHAR / DOUBLE / LONGLONG / NULL covers business-layer 80%+ of
// JDBC types; TIMESTAMP / DATE / JSON / DECIMAL / BLOB are sub-D follow-ups).
const MYSQL_TYPE_LONG       = 3
const MYSQL_TYPE_DOUBLE     = 5
const MYSQL_TYPE_NULL       = 6
const MYSQL_TYPE_LONGLONG   = 8
const MYSQL_TYPE_VAR_STRING = 253

const PREPARE_OK_HEADER      = 0x00
const PREPARE_OK_PAYLOAD_LEN = 12

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
// prepared.ss avoids the issue). Phase 2 setXxx will rely on the pre-sized
// paramValues / paramNullBits / paramTypes arrays seeded here.
function doPrepare(fd: int, sql: string): MysqlPreparedStatement {
    sendComStmtPrepare(fd, sql)
    const ok = readPrepareOk(fd)
    const paramDefs = readParamDef(fd, ok.numParams)
    const columnDefs = readColumnDefList(fd, ok.numColumns)
    let paramTypes: Array<int> = []
    let paramValues: Array<string> = []
    let paramNullBits: Array<int> = []
    let i = 0
    while (i < ok.numParams) {
        paramTypes = paramTypes.push(0)
        paramValues = paramValues.push("")
        paramNullBits = paramNullBits.push(0)
        i = i + 1
    }
    return new MysqlPreparedStatement(fd, ok.statementId, ok.numParams, paramDefs, paramTypes, paramValues, paramNullBits, columnDefs, 0)
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

// MysqlPreparedStatement — D136 Phase 1 framework.
//
// Field layout: fd (owned by Connection, borrowed here) + statementId
// (server-allocated u32, unique within the connection) + numParams +
// paramDefs (server-returned ColumnDef41 metadata for each param,
// inspected via query.ss helpers in Phase 2) + three parallel arrays
// paramTypes / paramValues / paramNullBits indexed by idx-1 (JDBC idx
// is 1-based; SS array is 0-based) + columnDefs (server-returned
// ColumnDef41 metadata for the result set, used by executeQuery's
// binary row decoder in Phase 2) + closed flag.
//
// Phase 1 instances are usable for protocol skeleton checks (statementId
// roundtrip / param + column count) but cannot execute — setXxx are
// no-ops, executeQuery returns a closed MysqlResultSet (next() == 0
// immediately), executeUpdate returns -1 sentinel, close flips closed=1
// without a server CLOSE packet. Phase 2 swaps each method body in.
class MysqlPreparedStatement : PreparedStatement {
    fd: int
    statementId: int
    numParams: int
    paramDefs: Array<ColumnDef>
    paramTypes: Array<int>
    paramValues: Array<string>
    paramNullBits: Array<int>
    columnDefs: Array<ColumnDef>
    closed: int

    function setInt(idx: int, val: int) {
        // Phase 2: paramTypes[idx-1] = MYSQL_TYPE_LONG; paramValues[idx-1] = encode(val); paramNullBits[idx-1] = 0
    }

    function setLong(idx: int, val: int) {
        // Phase 2: paramTypes[idx-1] = MYSQL_TYPE_LONGLONG; paramValues[idx-1] = encode(val); paramNullBits[idx-1] = 0
    }

    function setString(idx: int, val: string) {
        // Phase 2: paramTypes[idx-1] = MYSQL_TYPE_VAR_STRING; paramValues[idx-1] = val; paramNullBits[idx-1] = 0
    }

    function setDouble(idx: int, val: double) {
        // Phase 2: paramTypes[idx-1] = MYSQL_TYPE_DOUBLE; paramValues[idx-1] = encode(val); paramNullBits[idx-1] = 0
    }

    function setBoolean(idx: int, val: int) {
        // Phase 2: paramTypes[idx-1] = MYSQL_TYPE_LONG; paramValues[idx-1] = encode(val ? 1 : 0); paramNullBits[idx-1] = 0
    }

    function setNull(idx: int) {
        // Phase 2: paramTypes[idx-1] = MYSQL_TYPE_NULL; paramNullBits[idx-1] = 1
    }

    function executeQuery(): ResultSet {
        // Phase 2: sendComStmtExecute(fd, statementId, paramTypes, paramValues, paramNullBits) + readQueryResultSetBinary(fd).
        // Phase 1 stub — return closed MysqlResultSet so callers' next() short-circuits without panicking.
        let cols: Array<ColumnDef> = []
        let row: Array<string> = []
        return new MysqlResultSet(this.fd, -1, cols, row, 1, 0)
    }

    function executeUpdate(): int {
        // Phase 2: sendComStmtExecute + readUpdateResult.
        return -1
    }

    function close() {
        // Phase 2: sendComStmtClose(this.fd, this.statementId) — server returns no packet.
        if (this.closed != 0) { return }
        this.closed = 1
    }
}
