// Test: CSV standard library module (D041)

import { CSV, CsvTable } from "@/lib/csv"

import { assertEq, assertInt } from "./import/asserts"

function main() {
    // ── Basic parsing ────────────────────────────────────────
    const t1 = CSV.parse("name,age,city\nAlice,30,NYC\nBob,25,LA")
    assertInt(t1.rowCount(), 3, "basic rowCount")
    assertInt(t1.colCount(), 3, "basic colCount")
    assertEq(t1.get(0, 0), "name", "header 0")
    assertEq(t1.get(0, 1), "age", "header 1")
    assertEq(t1.get(0, 2), "city", "header 2")
    assertEq(t1.get(1, 0), "Alice", "row 1 col 0")
    assertEq(t1.get(1, 1), "30", "row 1 col 1")
    assertEq(t1.get(1, 2), "NYC", "row 1 col 2")
    assertEq(t1.get(2, 0), "Bob", "row 2 col 0")
    assertEq(t1.get(2, 1), "25", "row 2 col 1")
    assertEq(t1.get(2, 2), "LA", "row 2 col 2")

    // ── Headers and getByName ────────────────────────────────
    const hdrs = t1.headers()
    assertInt(hdrs.length(), 3, "headers length")
    assertEq(hdrs[0], "name", "headers[0]")
    assertEq(hdrs[1], "age", "headers[1]")
    assertEq(hdrs[2], "city", "headers[2]")
    assertEq(t1.getByName(1, "name"), "Alice", "getByName Alice")
    assertEq(t1.getByName(2, "city"), "LA", "getByName LA")
    assertEq(t1.getByName(1, "missing"), "", "getByName missing")

    // ── Quoted fields ────────────────────────────────────────
    const t2 = CSV.parse("a,\"b,c\",d\n1,\"2\n3\",4")
    assertInt(t2.rowCount(), 2, "quoted rowCount")
    assertInt(t2.colCount(), 3, "quoted colCount")
    assertEq(t2.get(0, 0), "a", "quoted field a")
    assertEq(t2.get(0, 1), "b,c", "quoted comma in field")
    assertEq(t2.get(0, 2), "d", "quoted field d")
    assertEq(t2.get(1, 1), "2\n3", "quoted newline in field")

    // ── Escaped quotes ───────────────────────────────────────
    const t3 = CSV.parse("a,\"say \"\"hi\"\"\",c")
    assertEq(t3.get(0, 1), "say \"hi\"", "escaped quotes")

    // ── Empty fields ─────────────────────────────────────────
    const t4 = CSV.parse("a,,c\n,,")
    assertInt(t4.rowCount(), 2, "empty rowCount")
    assertInt(t4.colCount(), 3, "empty colCount")
    assertEq(t4.get(0, 0), "a", "empty field a")
    assertEq(t4.get(0, 1), "", "empty field middle")
    assertEq(t4.get(0, 2), "c", "empty field c")
    assertEq(t4.get(1, 0), "", "empty row all empty 0")
    assertEq(t4.get(1, 1), "", "empty row all empty 1")
    assertEq(t4.get(1, 2), "", "empty row all empty 2")

    // ── Trailing newline ─────────────────────────────────────
    const t5 = CSV.parse("a,b\nc,d\n")
    assertInt(t5.rowCount(), 2, "trailing newline rowCount")
    assertEq(t5.get(0, 0), "a", "trailing nl row 0")
    assertEq(t5.get(1, 0), "c", "trailing nl row 1")

    // ── CRLF handling ────────────────────────────────────────
    const t6 = CSV.parse("a,b\r\nc,d\r\n")
    assertInt(t6.rowCount(), 2, "crlf rowCount")
    assertEq(t6.get(0, 0), "a", "crlf row 0 col 0")
    assertEq(t6.get(1, 0), "c", "crlf row 1 col 0")
    assertEq(t6.get(1, 1), "d", "crlf row 1 col 1")

    // ── Custom delimiter (TSV) ───────────────────────────────
    const t7 = CSV.parseDelimited("name\tage\nAlice\t30", "\t")
    assertInt(t7.rowCount(), 2, "tsv rowCount")
    assertEq(t7.get(0, 0), "name", "tsv header 0")
    assertEq(t7.get(0, 1), "age", "tsv header 1")
    assertEq(t7.get(1, 0), "Alice", "tsv data 0")
    assertEq(t7.get(1, 1), "30", "tsv data 1")

    // ── Empty input ──────────────────────────────────────────
    const t8 = CSV.parse("")
    assertInt(t8.rowCount(), 0, "empty input rowCount")
    assertInt(t8.colCount(), 0, "empty input colCount")

    // ── Single column ────────────────────────────────────────
    const t9 = CSV.parse("a\nb\nc")
    assertInt(t9.rowCount(), 3, "single col rowCount")
    assertInt(t9.colCount(), 1, "single col colCount")
    assertEq(t9.get(0, 0), "a", "single col 0")
    assertEq(t9.get(1, 0), "b", "single col 1")
    assertEq(t9.get(2, 0), "c", "single col 2")

    // ── Stringify basic ──────────────────────────────────────
    const t10 = CSV.parse("name,age\nAlice,30\n")
    const out1 = CSV.stringify(t10)
    assertEq(out1, "name,age\nAlice,30\n", "stringify basic")

    // ── Stringify with quoting ───────────────────────────────
    const t11 = CSV.parse("a,\"b,c\",d\n")
    const out2 = CSV.stringify(t11)
    assertEq(out2, "a,\"b,c\",d\n", "stringify quoted")

    // ── Round-trip ───────────────────────────────────────────
    const original = "x,\"y\"\"z\",w\n1,\"2,3\",4\n"
    const roundTrip = CSV.stringify(CSV.parse(original))
    assertEq(roundTrip, original, "round-trip")

    // ── Create + addRow ──────────────────────────────────────
    const t12 = CSV.create()
    assertInt(t12.rowCount(), 0, "create empty rowCount")
    assertInt(t12.colCount(), 0, "create empty colCount")
    let r1: Array<string> = ["name", "score"]
    let r2: Array<string> = ["Alice", "100"]
    let r3: Array<string> = ["Bob", "85"]
    t12.addRow(r1)
    t12.addRow(r2)
    t12.addRow(r3)
    assertInt(t12.rowCount(), 3, "addRow rowCount")
    assertInt(t12.colCount(), 2, "addRow colCount")
    assertEq(t12.get(0, 0), "name", "addRow header")
    assertEq(t12.get(1, 0), "Alice", "addRow data")
    assertEq(t12.get(2, 1), "85", "addRow data 2")
    assertEq(CSV.stringify(t12), "name,score\nAlice,100\nBob,85\n", "addRow stringify")

    // ── set method ───────────────────────────────────────────
    t12.set(1, 1, "95")
    assertEq(t12.get(1, 1), "95", "set method")

    // ── getRow ───────────────────────────────────────────────
    const row = t12.getRow(2)
    assertInt(row.length(), 2, "getRow length")
    assertEq(row[0], "Bob", "getRow[0]")
    assertEq(row[1], "85", "getRow[1]")

    // ── TSV stringify ────────────────────────────────────────
    const t13 = CSV.create()
    let tr1: Array<string> = ["a", "b"]
    let tr2: Array<string> = ["1", "2"]
    t13.addRow(tr1)
    t13.addRow(tr2)
    assertEq(CSV.stringifyDelimited(t13, "\t"), "a\tb\n1\t2\n", "tsv stringify")

    // ── getByName with header ────────────────────────────────
    const t14 = CSV.parse("id,name,email\n1,Alice,a@b.c\n2,Bob,b@c.d")
    assertEq(t14.getByName(1, "id"), "1", "getByName id")
    assertEq(t14.getByName(1, "email"), "a@b.c", "getByName email")
    assertEq(t14.getByName(2, "name"), "Bob", "getByName row 2")

    // ── Quoted empty field ───────────────────────────────────
    const t15 = CSV.parse("a,\"\",c")
    assertEq(t15.get(0, 1), "", "quoted empty field")

    println("All CSV tests passed!")
}
