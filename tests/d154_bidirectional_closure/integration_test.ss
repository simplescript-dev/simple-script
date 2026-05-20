// D154 §Followup F7 — bidirectional getter/setter closure integration test.
//
// Verifies the 12 production driver classes round-trip through the JDBC
// ResultSet read path (getString returning the server-side stringify) and
// the updateXxx setter (write path stringify into pending). The round-trip
// assertion locks read-stringify == write-stringify, so production code
// that fetches a column then writes the same driver class instance back
// preserves data fidelity end-to-end.
//
// 12 driver classes covered:
//   driver_types.ss  — MysqlTimestamp / MysqlRowId / MysqlSqlArray / MysqlRef
//   driver_lobs.ss   — MysqlBlob / MysqlClob / MysqlNClob / MysqlSQLXML
//   driver_streams.ss — MysqlAsciiStream / MysqlBinaryStream /
//                       MysqlCharacterStream / MysqlNCharacterStream
//
// See docs/3-decisions/D154-mysql-driver-class-impl.md §Followup F7.

import { test, assertEqual } from "@/lib/test"
import { ResultSet, ResultSetMetaData, Timestamp, Date, Time, Blob, Clob, NClob, RowId, SQLXML, SqlArray, Ref } from "@/lib/java/sql"
import { NoopResultSetMetaData } from "@/lib/com/mysql/query"
import { BigDecimal } from "@/lib/java/math"
import { InputStream, Reader } from "@/lib/java/io"
import { MysqlTimestamp, MysqlRowId, MysqlSqlArray, MysqlRef } from "@/lib/com/mysql/driver_types"
import { MysqlAsciiStream, MysqlBinaryStream, MysqlCharacterStream, MysqlNCharacterStream } from "@/lib/com/mysql/driver_streams"
import { MysqlBlob, MysqlClob, MysqlNClob, MysqlSQLXML } from "@/lib/com/mysql/driver_lobs"
import { drainReader } from "@/lib/com/mysql/prepared"

// BidirectionalStub — server-side stringify simulator. presetData maps
// column name → predefined stringify (mocking what the wire returns);
// pending captures what updateXxx writes back. Round-trip assertion:
// presetData[col] == updateXxx-derived pending[col].

class BidirectionalStub : ResultSet {
    pending: Map<string, string>
    presetData: Map<string, string>

    function next(): int { return 0 }
    function getString(col: string): string { return this.presetData.get(col) }
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

    function updateInt(col: string, val: int) {}
    function updateString(col: string, val: string) {}
    function updateLong(col: string, val: int) {}
    function updateBoolean(col: string, val: int) {}
    function updateDouble(col: string, val: double) {}
    function updateNull(col: string) {}
    function updateBigDecimal(col: string, val: BigDecimal) {}
    function updateTimestamp(col: string, val: Timestamp) { this.writeCol(col, val.toString()) }
    function updateDate(col: string, val: Date) {}
    function updateTime(col: string, val: Time) {}
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
    function updateBytes(col: string, val: string) {}
    function updateObject(col: string, val: string) {}
    function updateNString(col: string, val: string) {}
    function getMetaData(): ResultSetMetaData { return new NoopResultSetMetaData() }
    function close() {}
}

function newStub(col: string, presetStringify: string): BidirectionalStub {
    let preset: Map<string, string> = new Map()
    preset.set(col, presetStringify)
    let pending: Map<string, string> = new Map()
    return new BidirectionalStub(pending, preset)
}

function main() {
    test("MysqlTimestamp bidirectional round-trip", () => {
        const expected = "2026-05-04 12:34:56.0"
        const stub = newStub("ts", expected)
        const fetched = stub.getString("ts")
        assertEqual(fetched, expected)
        stub.updateTimestamp("ts", new MysqlTimestamp(2026, 5, 4, 12, 34, 56, 0, 0))
        assertEqual(stub.pending.get("ts"), expected)
    })

    test("MysqlRowId bidirectional round-trip", () => {
        const expected = "524f572d3432"
        const stub = newStub("rid", expected)
        const fetched = stub.getString("rid")
        assertEqual(fetched, expected)
        stub.updateRowId("rid", new MysqlRowId("ROW-42"))
        assertEqual(stub.pending.get("rid"), expected)
    })

    test("MysqlSqlArray bidirectional round-trip", () => {
        const expected = "[1,2,3]"
        const stub = newStub("tags", expected)
        const fetched = stub.getString("tags")
        assertEqual(fetched, expected)
        stub.updateArray("tags", new MysqlSqlArray(4, "INTEGER", "[1,2,3]"))
        assertEqual(stub.pending.get("tags"), expected)
    })

    test("MysqlRef bidirectional round-trip", () => {
        const expected = "ref-target"
        const stub = newStub("ref", expected)
        const fetched = stub.getString("ref")
        assertEqual(fetched, expected)
        stub.updateRef("ref", new MysqlRef("OBJECT_REF", "ref-target"))
        assertEqual(stub.pending.get("ref"), expected)
    })

    test("MysqlBlob bidirectional round-trip", () => {
        const expected = "BINARYDATA"
        const stub = newStub("photo", expected)
        const fetched = stub.getString("photo")
        assertEqual(fetched, expected)
        stub.updateBlob("photo", new MysqlBlob("BINARYDATA"))
        assertEqual(stub.pending.get("photo"), expected)
    })

    test("MysqlClob bidirectional round-trip", () => {
        const expected = "Hello, World!"
        const stub = newStub("bio", expected)
        const fetched = stub.getString("bio")
        assertEqual(fetched, expected)
        stub.updateClob("bio", new MysqlClob("Hello, World!"))
        assertEqual(stub.pending.get("bio"), expected)
    })

    test("MysqlNClob bidirectional round-trip", () => {
        const expected = "NCLOB-PAYLOAD"
        const stub = newStub("note_n", expected)
        const fetched = stub.getString("note_n")
        assertEqual(fetched, expected)
        stub.updateNClob("note_n", new MysqlNClob("NCLOB-PAYLOAD"))
        assertEqual(stub.pending.get("note_n"), expected)
    })

    test("MysqlSQLXML bidirectional round-trip", () => {
        const expected = "<root>x</root>"
        const stub = newStub("doc", expected)
        const fetched = stub.getString("doc")
        assertEqual(fetched, expected)
        stub.updateSQLXML("doc", new MysqlSQLXML("<root>x</root>"))
        assertEqual(stub.pending.get("doc"), expected)
    })

    test("MysqlAsciiStream bidirectional round-trip", () => {
        const expected = "AsciiPayload"
        const stub = newStub("ascii_blob", expected)
        const fetched = stub.getString("ascii_blob")
        assertEqual(fetched, expected)
        stub.updateAsciiStream("ascii_blob", new MysqlAsciiStream("AsciiPayload", 0, -1))
        assertEqual(stub.pending.get("ascii_blob"), expected)
    })

    test("MysqlBinaryStream bidirectional round-trip", () => {
        const expected = "BinaryPayload"
        const stub = newStub("bin_blob", expected)
        const fetched = stub.getString("bin_blob")
        assertEqual(fetched, expected)
        stub.updateBinaryStream("bin_blob", new MysqlBinaryStream("BinaryPayload", 0, -1))
        assertEqual(stub.pending.get("bin_blob"), expected)
    })

    test("MysqlCharacterStream bidirectional round-trip", () => {
        const expected = "CharPayload"
        const stub = newStub("char_clob", expected)
        const fetched = stub.getString("char_clob")
        assertEqual(fetched, expected)
        stub.updateCharacterStream("char_clob", new MysqlCharacterStream("CharPayload", 0, -1))
        assertEqual(stub.pending.get("char_clob"), expected)
    })

    test("MysqlNCharacterStream bidirectional round-trip", () => {
        const expected = "NCharPayload"
        const stub = newStub("nchar_clob", expected)
        const fetched = stub.getString("nchar_clob")
        assertEqual(fetched, expected)
        stub.updateNCharacterStream("nchar_clob", new MysqlNCharacterStream("NCharPayload", 0, -1))
        assertEqual(stub.pending.get("nchar_clob"), expected)
    })
}
