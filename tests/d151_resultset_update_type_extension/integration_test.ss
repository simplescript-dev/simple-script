// D151 Phase 4 — JDBC 4.3 §15.2.5 update setter type extension integration test.
//
// Verifies the 18 typed setters dispatch through the ResultSet vtable into a
// driver-side stringify-into-pending-Map simulator. Stub classes implement
// the type class interfaces (Timestamp / Date / Time / Blob / Clob / NClob /
// RowId / SQLXML / SqlArray / Ref / InputStream / Reader) with predictable
// payloads, then D151TestStub : ResultSet records each updateXxx call so the
// test asserts the stringified column value matches the JDBC contract that
// MysqlBinaryResultSet (lib/com/mysql/prepared.ss) implements over the wire.
//
// See docs/3-decisions/D151-resultset-update-type-extension.md §Phase 4.

import { assertEqual } from "@/lib/test"
import { ResultSet, Timestamp, Date, Time, Blob, Clob, NClob, RowId, SQLXML, SqlArray, Ref } from "@/lib/java/sql"
import { BigDecimal } from "@/lib/java/math"
import { InputStream, Reader } from "@/lib/java/io"
import { MysqlTimestamp, MysqlRowId, MysqlSqlArray, MysqlRef } from "@/lib/com/mysql/driver_types"
import { MysqlBinaryStream, MysqlCharacterStream, MysqlNCharacterStream } from "@/lib/com/mysql/driver_streams"
import { MysqlBlob, MysqlClob, MysqlNClob, MysqlSQLXML } from "@/lib/com/mysql/driver_lobs"

// Matches JDK java.io.Reader default buffer size — chunked drain in
// drainReader() loops until readN returns "" (EOF).
const READER_CHUNK_BYTES = 8192

// D154 §F7 sub-D: production driver class implementations replace the
// 12 D154-scoped stub classes. Stream stubs (MemoryInputStream / Reader,
// EmptyInputStream / Reader) → MysqlBinaryStream / MysqlCharacterStream /
// MysqlNCharacterStream (lib/com/mysql/driver_streams.ss). Type stubs
// (StubTimestamp / StubBlob / StubClob / StubNClob / StubRowId /
// StubSQLXML / StubSqlArray / StubRef) → Mysql* (lib/com/mysql/
// driver_types.ss + driver_lobs.ss). StubDate / StubTime stay because
// D154 scope excludes Date/Time (no MysqlDate / MysqlTime — D154 §核心
// 目标 names 8 type class explicitly).

class StubDate : Date {
    iso: string
    function getYear(): int { return 0 }
    function getMonth(): int { return 0 }
    function getDay(): int { return 0 }
    function getTime(): int { return 0 }
    function setTime(time: int) {}
    function before(other: Date): int { return 0 }
    function after(other: Date): int { return 0 }
    function equals(other: Date): int { return 0 }
    function compareTo(other: Date): int { return 0 }
    function toString(): string { return this.iso }
}

class StubTime : Time {
    iso: string
    function getHours(): int { return 0 }
    function getMinutes(): int { return 0 }
    function getSeconds(): int { return 0 }
    function getTime(): int { return 0 }
    function setTime(time: int) {}
    function before(other: Time): int { return 0 }
    function after(other: Time): int { return 0 }
    function equals(other: Time): int { return 0 }
    function compareTo(other: Time): int { return 0 }
    function toString(): string { return this.iso }
}

// ── ResultSet stub: driver-side stringify simulator ─────────────────
// Records each updateXxx call into a pending Map mirroring the
// MysqlBinaryResultSet.writeCol pendingUpdates buffer (D147 §H8 pattern).

class D151TestStub : ResultSet {
    pending: Map<string, string>

    function next(): int { return 0 }
    function getString(col: string): string { return "" }
    function getInt(col: string): int { return 0 }
    function getLong(col: string): int { return 0 }
    function getDouble(col: string): double { return 0.0 }
    function getBoolean(col: string): int { return 0 }
    function setFetchSize(rows: int) {}
    function getFetchSize(): int { return 0 }
    function absolute(row: int): int { return 0 }
    function first(): int { return 0 }
    function last(): int { return 0 }
    function previous(): int { return 0 }
    function getRow(): int { return 0 }
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
    private function writeCol(col: string, val: string) { this.pending.set(col, val) }

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
    function close() {}
}

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

function newStub(): D151TestStub {
    let m: Map<string, string> = new Map()
    return new D151TestStub(m)
}

function main() {
    test("updateBigDecimal stringifies via toString preserving scale", () => {
        const rs = newStub()
        rs.updateBigDecimal("price", new BigDecimal(1999, 2))
        assertEqual(rs.pending.get("price"), "19.99")
    })

    test("updateTimestamp stringifies via toString JDBC literal form", () => {
        const rs = newStub()
        rs.updateTimestamp("created_at", new MysqlTimestamp(2026, 5, 4, 12, 34, 56, 0, 0))
        assertEqual(rs.pending.get("created_at"), "2026-05-04 12:34:56.0")
    })

    test("updateDate stringifies via toString YYYY-MM-DD", () => {
        const rs = newStub()
        rs.updateDate("birth", new StubDate("1990-01-15"))
        assertEqual(rs.pending.get("birth"), "1990-01-15")
    })

    test("updateTime stringifies via toString HH:MM:SS", () => {
        const rs = newStub()
        rs.updateTime("clock_in", new StubTime("09:30:00"))
        assertEqual(rs.pending.get("clock_in"), "09:30:00")
    })

    test("updateBlob writes 1-based getBytes drained payload", () => {
        const rs = newStub()
        rs.updateBlob("photo", new MysqlBlob("BINARYDATA"))
        assertEqual(rs.pending.get("photo"), "BINARYDATA")
    })

    test("updateClob writes 1-based getSubString drained body", () => {
        const rs = newStub()
        rs.updateClob("bio", new MysqlClob("Hello, World!"))
        assertEqual(rs.pending.get("bio"), "Hello, World!")
    })

    test("updateNClob writes via getSubString same shape as Clob", () => {
        const rs = newStub()
        rs.updateNClob("note_n", new MysqlNClob("NCLOB-PAYLOAD"))
        assertEqual(rs.pending.get("note_n"), "NCLOB-PAYLOAD")
    })

    test("updateRowId stringifies via toString opaque identifier", () => {
        const rs = newStub()
        rs.updateRowId("rid", new MysqlRowId("ROW-42"))
        // MysqlRowId.toString hex-encodes per JDBC convention; "ROW-42" → 0x52,0x4F,0x57,0x2D,0x34,0x32 = "524f572d3432"
        assertEqual(rs.pending.get("rid"), "524f572d3432")
    })

    test("updateSQLXML writes via getString XML literal", () => {
        const rs = newStub()
        rs.updateSQLXML("doc", new MysqlSQLXML("<root>x</root>"))
        assertEqual(rs.pending.get("doc"), "<root>x</root>")
    })

    test("updateArray writes via getArray driver-serialized form", () => {
        const rs = newStub()
        rs.updateArray("tags", new MysqlSqlArray(4, "INTEGER", "[1,2,3]"))
        assertEqual(rs.pending.get("tags"), "[1,2,3]")
    })

    test("updateRef writes via getObject driver-serialized form", () => {
        const rs = newStub()
        rs.updateRef("ref", new MysqlRef("OBJECT_REF", "ref-target"))
        assertEqual(rs.pending.get("ref"), "ref-target")
    })

    test("updateAsciiStream drains via readN(available())", () => {
        const rs = newStub()
        rs.updateAsciiStream("ascii_blob", new MysqlBinaryStream("AsciiPayload", 0, -1))
        assertEqual(rs.pending.get("ascii_blob"), "AsciiPayload")
    })

    test("updateBinaryStream drains via readN(available())", () => {
        const rs = newStub()
        rs.updateBinaryStream("bin_blob", new MysqlBinaryStream("BinaryPayload", 0, -1))
        assertEqual(rs.pending.get("bin_blob"), "BinaryPayload")
    })

    test("updateCharacterStream drains via 8KiB-chunk loop until EOF", () => {
        const rs = newStub()
        rs.updateCharacterStream("char_clob", new MysqlCharacterStream("CharPayload", 0, -1))
        assertEqual(rs.pending.get("char_clob"), "CharPayload")
    })

    test("updateNCharacterStream drains via same 8KiB loop as Reader path", () => {
        const rs = newStub()
        rs.updateNCharacterStream("nchar_clob", new MysqlNCharacterStream("NCharPayload", 0, -1))
        assertEqual(rs.pending.get("nchar_clob"), "NCharPayload")
    })

    test("updateBytes writes string directly (JDBC byte[] equivalent)", () => {
        const rs = newStub()
        rs.updateBytes("raw", "RAWBYTES")
        assertEqual(rs.pending.get("raw"), "RAWBYTES")
    })

    test("updateObject writes string-serialized form", () => {
        const rs = newStub()
        rs.updateObject("any", "OBJECTPAYLOAD")
        assertEqual(rs.pending.get("any"), "OBJECTPAYLOAD")
    })

    test("updateNString writes string for NVARCHAR / NCLOB columns", () => {
        const rs = newStub()
        rs.updateNString("nval", "NSTRING")
        assertEqual(rs.pending.get("nval"), "NSTRING")
    })
}
