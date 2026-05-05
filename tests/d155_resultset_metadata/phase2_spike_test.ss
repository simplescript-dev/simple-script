// D155 Phase 2 spike — pure local, no docker dependency.
//
// Verifies the JDBC 4.3 §15.4 ResultSetMetaData interface declared in
// lib/java/sql.ss is reachable through the vtable of the Phase 2 stub
// class NoopResultSetMetaData (lib/com/mysql/query.ss). All ≥21 method
// dispatch + return their stub default values cleanly without a live
// MySQL socket.
//
// One Case (#7) instantiates GeneratedKeyResultSet and calls
// rs.getMetaData() through the ResultSet interface to confirm the
// implementor stub wiring lands on NoopResultSetMetaData (Phase 3 will
// replace this with MysqlResultSetMetaData real reflection per
// D155 §Phase 收关锚 §Phase 3 line 101-109).
//
// JDBC isNullable enum-as-int constants columnNoNulls / columnNullable /
// columnNullableUnknown (lib/java/sql.ss D155 Phase 2) are verified for
// stable JDBC 4.3 §15.4 spec values.
//
// See docs/3-decisions/D155-resultset-metadata.md §Phase 收关锚 §Phase 2.

import { assertEqual, assertTrue } from "@/lib/test"
import { ResultSet, ResultSetMetaData, columnNoNulls, columnNullable, columnNullableUnknown } from "@/lib/java/sql"
import { NoopResultSetMetaData, GeneratedKeyResultSet } from "@/lib/com/mysql/query"

function main() {
    const m = new NoopResultSetMetaData()

    // Case 1 — getColumnCount stub returns 0 (no columns)
    test("NoopResultSetMetaData.getColumnCount = 0 (D155 Phase 2)", () => {
        assertEqual(m.getColumnCount(), 0)
    })

    // Case 2 — 7 string-returning method default to "" via vtable
    test("NoopResultSetMetaData 7 string accessors stub = '' (D155 Phase 2)", () => {
        assertEqual(m.getColumnName(1), "")
        assertEqual(m.getColumnLabel(1), "")
        assertEqual(m.getColumnTypeName(1), "")
        assertEqual(m.getColumnClassName(1), "")
        assertEqual(m.getCatalogName(1), "")
        assertEqual(m.getSchemaName(1), "")
        assertEqual(m.getTableName(1), "")
    })

    // Case 3 — 4 int-returning size/precision/scale method default to 0
    test("NoopResultSetMetaData 4 int accessors stub = 0 (D155 Phase 2)", () => {
        assertEqual(m.getColumnType(1), 0)
        assertEqual(m.getColumnDisplaySize(1), 0)
        assertEqual(m.getPrecision(1), 0)
        assertEqual(m.getScale(1), 0)
    })

    // Case 4 — isNullable stub defaults to columnNullableUnknown (JDBC §15.4
    // safe value: stub cannot prove either NOT_NULL or nullable without
    // ColumnDef41 flags). Phase 3 wires real flag-bit derivation.
    test("NoopResultSetMetaData.isNullable = columnNullableUnknown (D155 Phase 2)", () => {
        assertEqual(m.isNullable(1), columnNullableUnknown)
    })

    // Case 5 — JDBC 4.3 §15.4 isNullable enum-as-int constants stable
    test("JDBC §15.4 columnNoNulls / Nullable / NullableUnknown constants (D155 Phase 2)", () => {
        assertEqual(columnNoNulls, 0)
        assertEqual(columnNullable, 1)
        assertEqual(columnNullableUnknown, 2)
    })

    // Case 6 — 8 isXxx boolean-like method default values (stub semantics:
    // metadata-less view => readonly + non-writable + not searchable +
    // unsigned + non-incrementing. Phase 3 derives from MySQL flag bits).
    test("NoopResultSetMetaData 8 isXxx stubs default values (D155 Phase 2)", () => {
        assertEqual(m.isAutoIncrement(1), 0)
        assertEqual(m.isCaseSensitive(1), 0)
        assertEqual(m.isCurrency(1), 0)
        assertEqual(m.isDefinitelyWritable(1), 0)
        assertEqual(m.isReadOnly(1), 1)
        assertEqual(m.isSearchable(1), 0)
        assertEqual(m.isSigned(1), 0)
        assertEqual(m.isWritable(1), 0)
    })

    // Case 7 — GeneratedKeyResultSet.getMetaData() implementor stub dispatches
    // to NoopResultSetMetaData (Phase 2 fallback). Phase 3 swaps this for
    // a hard-coded 1-col GENERATED_KEY BIGINT MysqlResultSetMetaData (§A.2 H5).
    test("GeneratedKeyResultSet.getMetaData stub dispatch (D155 Phase 2)", () => {
        const ks = new GeneratedKeyResultSet(42, 0)
        const md: ResultSetMetaData = ks.getMetaData()
        assertEqual(md.getColumnCount(), 0)
        assertEqual(md.isNullable(1), columnNullableUnknown)
    })

    // Case 8 — vtable dispatch through ResultSetMetaData interface variable
    // confirms NoopResultSetMetaData implements every declared method
    // (D025 vtable 强制全 method 否则 bootstrap fail — this case verifies
    // every ≥21 method survives the indirection layer).
    test("ResultSetMetaData interface vtable dispatch (D155 Phase 2)", () => {
        const md: ResultSetMetaData = new NoopResultSetMetaData()
        assertEqual(md.getColumnCount(), 0)
        assertEqual(md.getColumnName(1), "")
        assertEqual(md.getColumnLabel(1), "")
        assertEqual(md.getColumnType(1), 0)
        assertEqual(md.getColumnTypeName(1), "")
        assertEqual(md.getColumnDisplaySize(1), 0)
        assertEqual(md.getColumnClassName(1), "")
        assertEqual(md.getCatalogName(1), "")
        assertEqual(md.getSchemaName(1), "")
        assertEqual(md.getTableName(1), "")
        assertEqual(md.isNullable(1), columnNullableUnknown)
        assertEqual(md.isAutoIncrement(1), 0)
        assertEqual(md.isCaseSensitive(1), 0)
        assertEqual(md.isCurrency(1), 0)
        assertEqual(md.isDefinitelyWritable(1), 0)
        assertEqual(md.isReadOnly(1), 1)
        assertEqual(md.isSearchable(1), 0)
        assertEqual(md.isSigned(1), 0)
        assertEqual(md.isWritable(1), 0)
        assertEqual(md.getPrecision(1), 0)
        assertEqual(md.getScale(1), 0)
    })
}
