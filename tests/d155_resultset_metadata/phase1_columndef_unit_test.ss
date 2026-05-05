// D155 Phase 1 unit test — pure local, no docker dependency.
//
// Verifies parseColumnDef byte-level pass-through over the full
// MySQL Native Protocol §6.6 ColumnDefinition41 wire layout — D155
// Phase 1 promoted catalog / schema / table (alias) / org_name / decimals
// from "skip" to "keep" so JDBC §15.4 ResultSetMetaData ≥21 method has
// the full reflection source. The 7 cross-module accessors round-trip
// the same fields so the future MysqlResultSetMetaData (Phase 3) can walk
// Array<ColumnDef> without forward-referencing %ColumnDef from query.ss
// (same indirect-access constraint columnDefName / columnDefColType /
// columnDefOrgTable / columnDefFlags document).
//
// §A.2 H1 hidden assumption (ColumnDef41 binary vs text protocol same
// packet structure) is exercised here for the byte-level layer; the
// on-wire double-protocol round-trip lands in Phase 4 docker integration.
//
// See docs/3-decisions/D155-resultset-metadata.md §Phase 收关锚 §Phase 1.

import { assertEqual, assertTrue } from "@/lib/test"
import { ColumnDef, parseColumnDef, columnDefName, columnDefColType, columnDefOrgTable, columnDefFlags, columnDefCatalog, columnDefSchema, columnDefTable, columnDefOrgName, columnDefCharset, columnDefMaxColumnLength, columnDefDecimals } from "@/lib/com/mysql/query"

function main() {
    // Reusable fixture (id INT NOT NULL PRIMARY KEY, charset utf8mb4_bin = 63):
    //   catalog="def" / schema="test" / table="users" / org_table="users"
    //   name="id" / org_name="id"
    //   filler 0x0c / charset 63 / column_length 11 / column_type 0x03
    //   flags 0x4003 (NOT_NULL_FLAG 0x0001 | PRI_KEY_FLAG 0x0002 | NUM_FLAG 0x4000)
    //   decimals 0 / reserved 0x0000
    // Total 40 bytes — bash-printf so embedded 0x00 survives ss_string_concat.
    const cmd = "bash -c \"printf '\\x03def\\x04test\\x05users\\x05users\\x02id\\x02id\\x0c\\x3f\\x00\\x0b\\x00\\x00\\x00\\x03\\x03\\x40\\x00\\x00\\x00' > /tmp/d155_p1_coldef.bin\""
    system(cmd)
    const buf = readFile("/tmp/d155_p1_coldef.bin")
    const col = parseColumnDef(buf)

    // ── 11 字段 byte-level pass-through ──────────────────────────
    test("parseColumnDef catalog pass-through (D155 Phase 1)", () => {
        assertEqual(col.catalog, "def")
    })

    test("parseColumnDef schema pass-through (D155 Phase 1)", () => {
        assertEqual(col.schema, "test")
    })

    test("parseColumnDef table (alias) pass-through (D155 Phase 1)", () => {
        assertEqual(col.table, "users")
    })

    test("parseColumnDef org_table pass-through (D147 Phase 3 baseline)", () => {
        assertEqual(col.orgTable, "users")
    })

    test("parseColumnDef name pass-through (D134 Phase 4 baseline)", () => {
        assertEqual(col.name, "id")
    })

    test("parseColumnDef org_name pass-through (D155 Phase 1)", () => {
        assertEqual(col.orgName, "id")
    })

    test("parseColumnDef charset pass-through (utf8mb4_bin = 63)", () => {
        assertEqual(col.charset, 63)
    })

    test("parseColumnDef columnLen pass-through (max display width 11)", () => {
        assertEqual(col.columnLen, 11)
    })

    test("parseColumnDef colType pass-through (MYSQL_TYPE_LONG = 3)", () => {
        assertEqual(col.colType, 3)
    })

    test("parseColumnDef flags pass-through (NOT_NULL | PRI_KEY | NUM = 0x4003)", () => {
        assertEqual(col.flags, 0x4003)
    })

    test("parseColumnDef decimals pass-through (D155 Phase 1)", () => {
        assertEqual(col.decimals, 0)
    })

    // ── 7 D155 Phase 1 cross-module accessor round-trip ──────────
    test("columnDefCatalog accessor round-trip", () => {
        assertEqual(columnDefCatalog(col), "def")
    })

    test("columnDefSchema accessor round-trip", () => {
        assertEqual(columnDefSchema(col), "test")
    })

    test("columnDefTable accessor round-trip (alias)", () => {
        assertEqual(columnDefTable(col), "users")
    })

    test("columnDefOrgName accessor round-trip", () => {
        assertEqual(columnDefOrgName(col), "id")
    })

    test("columnDefCharset accessor round-trip", () => {
        assertEqual(columnDefCharset(col), 63)
    })

    test("columnDefMaxColumnLength accessor — JDBC view of column_length", () => {
        // Protocol→API alias layer: accessor uses JDBC §15.4 spec name
        // (getColumnDisplaySize / getPrecision derive off this), the
        // underlying ColumnDef field keeps the wire-protocol name (columnLen).
        assertEqual(columnDefMaxColumnLength(col), 11)
    })

    test("columnDefDecimals accessor round-trip", () => {
        assertEqual(columnDefDecimals(col), 0)
    })

    // ── 4 baseline accessors still functional ────────────────────
    test("columnDefOrgTable accessor still functional (D147 Phase 3 baseline)", () => {
        assertEqual(columnDefOrgTable(col), "users")
    })

    test("columnDefFlags accessor still functional (D147 Phase 3 baseline)", () => {
        assertEqual(columnDefFlags(col), 0x4003)
    })

    test("columnDefName accessor still functional (D134 Phase 4 baseline)", () => {
        assertEqual(columnDefName(col), "id")
    })

    test("columnDefColType accessor still functional (D134 Phase 4 baseline)", () => {
        assertEqual(columnDefColType(col), 3)
    })

    // ── 11-arg positional constructor + per-field readback ───────
    test("ColumnDef positional constructor — full 11-arg", () => {
        const c = new ColumnDef("price", 5, 12, 33, "products", 0x0001, "def", "shop", "items", "amount", 2)
        assertEqual(c.name, "price")
        assertEqual(c.colType, 5)
        assertEqual(c.columnLen, 12)
        assertEqual(c.charset, 33)
        assertEqual(c.orgTable, "products")
        assertEqual(c.flags, 0x0001)
        assertEqual(c.catalog, "def")
        assertEqual(c.schema, "shop")
        assertEqual(c.table, "items")
        assertEqual(c.orgName, "amount")
        assertEqual(c.decimals, 2)
    })
}
