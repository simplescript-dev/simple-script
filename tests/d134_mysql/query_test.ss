// D134 Phase 4 — query packet parse + ResultSet unit tests.
// No socket — parseResultSetHeader / parseColumnDef / parseRow / isEofPacket
// take payload buffers directly. Live sendQuery + readQueryResultSet flow
// against real mysql:8 is exercised in Phase 6 docker e2e.
//
// ColumnDef / EOF fixtures with multiple 0x00 bytes go through bash-printf +
// readFile (Phase 3 parseHandshakeV10 path) — charCodeAt is binary-safe via
// direct GEP+load and bypasses ss_string_concat strlen truncation.

import { assertEqual, assertTrue } from "@/lib/test"
import { parseResultSetHeader, parseColumnDef, parseRow, isEofPacket, parseOkPacket, ColumnDef, MysqlResultSet, RESULT_SET_HEADER_OK } from "@/lib/com/mysql/query"
import { SQLException } from "@/lib/java/sql"

function main() {
    // parseResultSetHeader: ERR throws / OK / column count / empty payload
    test("parseResultSetHeader ERR (0xFF) throws SQLException", () => {
        let caught = 0
        try {
            parseResultSetHeader(fromCharCode(0xFF), 1)
        } catch (e: SQLException) {
            caught = 1
        }
        assertEqual(caught, 1)
    })

    test("parseResultSetHeader OK (0x00) returns -2", () => {
        assertEqual(parseResultSetHeader(fromCharCode(0x00), 1), RESULT_SET_HEADER_OK)
    })

    test("parseResultSetHeader column count 1", () => {
        assertEqual(parseResultSetHeader(fromCharCode(1), 1), 1)
    })

    test("parseResultSetHeader column count 5", () => {
        assertEqual(parseResultSetHeader(fromCharCode(5), 1), 5)
    })

    test("parseResultSetHeader empty payload returns 0", () => {
        assertEqual(parseResultSetHeader("", 0), 0)
    })

    // isEofPacket: legacy EOF marker (0xFE + payloadLen < 9)
    test("isEofPacket EOF marker fixture", () => {
        // 5-byte EOF: 0xFE + 4 bytes warnings/status. bash-printf so 0x00 survives.
        const cmd = "bash -c \"printf '\\xFE\\x00\\x00\\x02\\x00' > /tmp/d134_q_eof.bin\""
        system(cmd)
        const buf = readFile("/tmp/d134_q_eof.bin")
        assertEqual(isEofPacket(buf, 5), 1)
    })

    test("isEofPacket non-EOF wrong header", () => {
        assertEqual(isEofPacket(fromCharCode(0x01), 1), 0)
    })

    test("isEofPacket non-EOF long payload", () => {
        // 0xFE first byte but payloadLen >= 9 → not EOF (impractical row case).
        const cmd = "bash -c \"printf '\\xFE\\x01\\x01\\x01\\x01\\x01\\x01\\x01\\x01\\x01' > /tmp/d134_q_long.bin\""
        system(cmd)
        const buf = readFile("/tmp/d134_q_long.bin")
        assertEqual(isEofPacket(buf, 10), 0)
    })

    test("isEofPacket empty payload", () => {
        assertEqual(isEofPacket("", 0), 0)
    })

    // parseColumnDef minimal id INT 11 utf8mb3 fixture (MYSQL_TYPE_LONG = 3)
    test("parseColumnDef minimal id INT 11 utf8mb3", () => {
        const cmd = "bash -c \"printf '\\x00\\x00\\x01t\\x01t\\x02id\\x02id\\x0c\\x21\\x00\\x0b\\x00\\x00\\x00\\x03\\x03\\x00\\x00\\x00\\x00' > /tmp/d134_q_coldef.bin\""
        system(cmd)
        const buf = readFile("/tmp/d134_q_coldef.bin")
        const col = parseColumnDef(buf)
        assertEqual(col.name, "id")
        assertEqual(col.charset, 33)
        assertEqual(col.columnLen, 11)
        assertEqual(col.colType, 3)
    })

    // parseRow text protocol: length-encoded strings + NULL marker (0xFB)
    test("parseRow 2 cols Alice 42", () => {
        const buf = fromCharCode(5) + "Alice" + fromCharCode(2) + "42"
        const row = parseRow(buf, 2)
        assertEqual(row.length(), 2)
        assertEqual(row[0], "Alice")
        assertEqual(row[1], "42")
    })

    test("parseRow NULL column 0xFB", () => {
        const buf = fromCharCode(0xFB) + fromCharCode(1) + "x"
        const row = parseRow(buf, 2)
        assertEqual(row.length(), 2)
        assertEqual(row[0], "")
        assertEqual(row[1], "x")
    })

    test("parseRow 1-col empty string", () => {
        const buf = fromCharCode(0)
        const row = parseRow(buf, 1)
        assertEqual(row.length(), 1)
        assertEqual(row[0], "")
    })

    // ColumnDef positional constructor
    test("ColumnDef positional constructor", () => {
        const c = new ColumnDef("price", 5, 12, 33, "", 0, "", "", "", "", 0)
        assertEqual(c.name, "price")
        assertEqual(c.colType, 5)
        assertEqual(c.columnLen, 12)
        assertEqual(c.charset, 33)
    })

    // MysqlResultSet manual construction + colIndex + getString / getInt / getLong
    test("MysqlResultSet positional ctor + colIndex + getters", () => {
        let cols: Array<ColumnDef> = []
        cols = cols.push(new ColumnDef("id", 3, 11, 33, "", 0, "", "", "", "", 0))
        cols = cols.push(new ColumnDef("name", 253, 80, 33, "", 0, "", "", "", "", 0))
        let row: Array<string> = []
        row = row.push("42")
        row = row.push("Alice")
        const rs = new MysqlResultSet(-1, 2, cols, row, 0, 1)
        assertEqual(rs.fd, -1)
        assertEqual(rs.colCount, 2)
        assertEqual(rs.closed, 0)
        assertEqual(rs.hasMoreRows, 1)
        assertEqual(rs.getString("id"), "42")
        assertEqual(rs.getString("name"), "Alice")
        assertEqual(rs.getString("missing"), "")
        assertEqual(rs.getInt("id"), 42)
        assertEqual(rs.getLong("id"), 42)
    })

    test("MysqlResultSet getBoolean true variants", () => {
        let cols: Array<ColumnDef> = []
        cols = cols.push(new ColumnDef("flag", 1, 1, 63, "", 0, "", "", "", "", 0))
        let row1: Array<string> = []
        row1 = row1.push("1")
        const rs1 = new MysqlResultSet(-1, 1, cols, row1, 0, 1)
        assertEqual(rs1.getBoolean("flag"), 1)

        let row2: Array<string> = []
        row2 = row2.push("true")
        const rs2 = new MysqlResultSet(-1, 1, cols, row2, 0, 1)
        assertEqual(rs2.getBoolean("flag"), 1)

        let row3: Array<string> = []
        row3 = row3.push("0")
        const rs3 = new MysqlResultSet(-1, 1, cols, row3, 0, 1)
        assertEqual(rs3.getBoolean("flag"), 0)

        let row4: Array<string> = []
        row4 = row4.push("false")
        const rs4 = new MysqlResultSet(-1, 1, cols, row4, 0, 1)
        assertEqual(rs4.getBoolean("flag"), 0)
    })

    // ── parseOkPacket.affectedRows (Phase 5) ────────────────────────
    // OK packet payload layout: 0x00 + lenenc affectedRows + lenenc lastInsertId
    //                         + 2-byte status + 2-byte warnings + ...
    test("parseOkPacket zero rows", () => {
        // 0x00 header + 0x00 (lenenc 0) + 0x00 (lenenc 0) + status + warnings.
        const cmd = "bash -c \"printf '\\x00\\x00\\x00\\x02\\x00\\x00\\x00' > /tmp/d134_q_ok0.bin\""
        system(cmd)
        const buf = readFile("/tmp/d134_q_ok0.bin")
        assertEqual(parseOkPacket(buf, 7).affectedRows, 0)
    })

    test("parseOkPacket one row", () => {
        const cmd = "bash -c \"printf '\\x00\\x01\\x00\\x02\\x00\\x00\\x00' > /tmp/d134_q_ok1.bin\""
        system(cmd)
        const buf = readFile("/tmp/d134_q_ok1.bin")
        assertEqual(parseOkPacket(buf, 7).affectedRows, 1)
    })

    test("parseOkPacket large rows (lenenc 2-byte)", () => {
        // 0x00 + 0xFC 0x10 0x27 (lenenc 0xFC + LE 10000) + 0x00 + status + warn
        const cmd = "bash -c \"printf '\\x00\\xFC\\x10\\x27\\x00\\x02\\x00\\x00\\x00' > /tmp/d134_q_okN.bin\""
        system(cmd)
        const buf = readFile("/tmp/d134_q_okN.bin")
        assertEqual(parseOkPacket(buf, 9).affectedRows, 10000)
    })

    test("parseOkPacket non-OK header returns zero-init", () => {
        // 0xFF first byte → not OK → defensive zero-init OkPacket.
        assertEqual(parseOkPacket(fromCharCode(0xFF) + fromCharCode(0x05), 2).affectedRows, 0)
    })

    test("parseOkPacket empty payload returns zero-init", () => {
        assertEqual(parseOkPacket("", 0).affectedRows, 0)
    })

    println("All D134 Phase 4 query tests passed!")
}
