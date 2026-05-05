// D147 Phase 3 unit test — pure local, no docker dependency. Verifies the
// driver-side updatable cursor SQL templates + PK / table discovery helpers
// added to prepared.ss + the column def packet's org_table / flags fields
// added to query.ss:
//   1. buildUpdateRowSql / buildDeleteRowSql / buildInsertRowSql /
//      buildRefreshRowSql produce the exact placeholder SQL Phase 4's
//      MysqlBinaryResultSet.updateRow / deleteRow / insertRow / refreshRow
//      will hand to a fresh PreparedStatement.
//   2. derivePkColumn walks the SELECT's column metadata for PRI_KEY_FLAG
//      (bit 1 = 0x0002) and returns "" on the multi-PK / no-PK trap edges
//      — Phase 4 translates "" into SQLFeatureNotSupportedException.
//   3. deriveTableName takes the first column's org_table (single-table
//      SELECT — multi-table joins return the first column's table per
//      D147 §Followup F3).
//   4. ColumnDef.orgTable + .flags round-trip through the cross-module
//      accessors columnDefOrgTable / columnDefFlags so prepared.ss can
//      walk Array<ColumnDef> without forward-referencing %ColumnDef from
//      query.ss (same indirect-access constraint columnDefName /
//      columnDefColType document).
//
// §A.2 H2 hidden assumption — SELECT meta column def packet flags
// PRI_KEY_FLAG bit 1 marks the PK column — is exercised here for the
// single-table single-PK shape; the on-wire round-trip lands in Phase 4
// docker integration.
//
// See docs/3-decisions/D147-updatable-cursor.md §Phase 收关锚 §Phase 3.

import { assertEqual, assertTrue } from "@/lib/test"
import { ColumnDef, columnDefOrgTable, columnDefFlags } from "@/lib/com/mysql/query"
import { buildUpdateRowSql, buildDeleteRowSql, buildInsertRowSql, buildRefreshRowSql, derivePkColumn, deriveTableName, PRI_KEY_FLAG } from "@/lib/com/mysql/prepared"

// PK column constructor — name + flags PRI_KEY_FLAG bit set.
function pkCol(name: string, orgTable: string): ColumnDef {
    return new ColumnDef(name, 3, 11, 33, orgTable, PRI_KEY_FLAG, "", "", "", "", 0)
}

// Plain (non-PK) column constructor — flags = 0.
function plainCol(name: string, orgTable: string): ColumnDef {
    return new ColumnDef(name, 3, 11, 33, orgTable, 0, "", "", "", "", 0)
}

function main() {
    test("PRI_KEY_FLAG is the MySQL Native Protocol bit 1 (0x0002)", () => {
        assertEqual(PRI_KEY_FLAG, 0x0002)
        // bit 1 distinct from bit 0 (NOT_NULL_FLAG 0x0001) — basic sanity.
        assertEqual(PRI_KEY_FLAG & 0x0001, 0)
    })

    test("buildUpdateRowSql single dirty column → SET col=? WHERE pk=?", () => {
        const sql = buildUpdateRowSql("users", "id", ["name"])
        assertEqual(sql, "UPDATE users SET name=? WHERE id=?")
    })

    test("buildUpdateRowSql multi dirty columns → comma-separated SET clause", () => {
        const sql = buildUpdateRowSql("users", "id", ["name", "email", "age"])
        assertEqual(sql, "UPDATE users SET name=?, email=?, age=? WHERE id=?")
    })

    test("buildUpdateRowSql empty dirty cols → invalid SQL trap (Phase 4 callers gate)", () => {
        // Empty dirtyCols produces `UPDATE users WHERE id=?` — syntactically
        // invalid; Phase 4 callers gate on `dirtyCols.length() > 0` so this
        // surface only fires from a misuse, and the server's 1064 syntax
        // error routes through D139 SQLExceptionTranslator. We still pin
        // the literal output so the trap is visible.
        const sql = buildUpdateRowSql("users", "id", [])
        assertEqual(sql, "UPDATE users WHERE id=?")
    })

    test("buildUpdateRowSql trusts caller — column names pass through verbatim", () => {
        // No identifier escaping — Phase 4 caller is responsible. Pinning
        // the verbatim behavior so a future "auto-quote" change can't sneak
        // in without breaking this test.
        const sql = buildUpdateRowSql("orders", "order_id", ["customer_id", "total_amount"])
        assertEqual(sql, "UPDATE orders SET customer_id=?, total_amount=? WHERE order_id=?")
    })

    test("buildDeleteRowSql → DELETE FROM table WHERE pk=?", () => {
        assertEqual(buildDeleteRowSql("users", "id"), "DELETE FROM users WHERE id=?")
        assertEqual(buildDeleteRowSql("audit_log", "log_id"), "DELETE FROM audit_log WHERE log_id=?")
    })

    test("buildInsertRowSql placeholder count == cols.length()", () => {
        // Single column.
        assertEqual(buildInsertRowSql("users", ["name"]), "INSERT INTO users(name) VALUES (?)")
        // Two columns.
        assertEqual(buildInsertRowSql("users", ["name", "email"]), "INSERT INTO users(name, email) VALUES (?, ?)")
        // Five columns — explicit comma + placeholder count check.
        const sql = buildInsertRowSql("users", ["a", "b", "c", "d", "e"])
        assertEqual(sql, "INSERT INTO users(a, b, c, d, e) VALUES (?, ?, ?, ?, ?)")
    })

    test("buildRefreshRowSql column list comma-separated SELECT", () => {
        const sql = buildRefreshRowSql("users", "id", ["name", "email"])
        assertEqual(sql, "SELECT name, email FROM users WHERE id=?")
    })

    test("buildRefreshRowSql empty cols → SELECT * fallback", () => {
        // Defensive fallback when Phase 4 hasn't populated cols — caller
        // still gets a complete row image. Pinning the fallback so the
        // trap is documented in test form.
        const sql = buildRefreshRowSql("users", "id", [])
        assertEqual(sql, "SELECT * FROM users WHERE id=?")
    })

    test("derivePkColumn single PK → returns column name", () => {
        let cols: Array<ColumnDef> = []
        cols = cols.push(pkCol("id", "users"))
        cols = cols.push(plainCol("name", "users"))
        cols = cols.push(plainCol("email", "users"))
        assertEqual(derivePkColumn(cols), "id")
    })

    test("derivePkColumn multi-PK → returns \"\" (composite key trap)", () => {
        // Composite primary key (e.g. (user_id, role_id)) — D147 §Followup F3
        // ships composite key support; Phase 3 returns "" so Phase 4 can
        // raise SQLFeatureNotSupportedException through D139 dispatch.
        let cols: Array<ColumnDef> = []
        cols = cols.push(pkCol("user_id", "user_roles"))
        cols = cols.push(pkCol("role_id", "user_roles"))
        cols = cols.push(plainCol("granted_at", "user_roles"))
        assertEqual(derivePkColumn(cols), "")
    })

    test("derivePkColumn no PK → returns \"\" (heap table trap)", () => {
        let cols: Array<ColumnDef> = []
        cols = cols.push(plainCol("a", "events"))
        cols = cols.push(plainCol("b", "events"))
        assertEqual(derivePkColumn(cols), "")
    })

    test("deriveTableName takes first column's org_table (single-table SELECT)", () => {
        let cols: Array<ColumnDef> = []
        cols = cols.push(pkCol("id", "users"))
        cols = cols.push(plainCol("name", "users"))
        cols = cols.push(plainCol("email", "users"))
        assertEqual(deriveTableName(cols), "users")
    })

    test("deriveTableName multi-table join → first column's table (D147 §Followup F3)", () => {
        // Joins where columns come from different org_tables fall back to
        // the first column's table — Phase 4 callers trust the schema is
        // single-table. Pinning the behavior so a future "throw on mismatch"
        // refactor lands as an explicit test diff.
        let cols: Array<ColumnDef> = []
        cols = cols.push(pkCol("user_id", "users"))
        cols = cols.push(plainCol("order_id", "orders"))
        assertEqual(deriveTableName(cols), "users")
    })

    test("deriveTableName empty colMetadata → returns \"\"", () => {
        let cols: Array<ColumnDef> = []
        assertEqual(deriveTableName(cols), "")
    })

    test("columnDefOrgTable + columnDefFlags accessors round-trip ColumnDef state", () => {
        // Verifies the cross-module accessor pair lives on query.ss (same
        // forward-ref workaround columnDefName / columnDefColType document).
        const c = pkCol("id", "users")
        assertEqual(columnDefOrgTable(c), "users")
        assertEqual(columnDefFlags(c), PRI_KEY_FLAG)
        assertTrue((columnDefFlags(c) & PRI_KEY_FLAG) != 0)

        const p = plainCol("name", "users")
        assertEqual(columnDefOrgTable(p), "users")
        assertEqual(columnDefFlags(p), 0)
        assertEqual(columnDefFlags(p) & PRI_KEY_FLAG, 0)
    })
}
