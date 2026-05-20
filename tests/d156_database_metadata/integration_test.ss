// D156 Phase 4 — wire-end e2e integration test (docker probe-skip).
//
// Verifies the MysqlDatabaseMetaData class real INFORMATION_SCHEMA
// reflection (lib/com/mysql/jdbc.ss D156 §Phase 3) on an actual MySQL
// 8.0 docker instance — every JDBC §11 schema metadata path returns
// spec-aligned rows + columns end-to-end. Subsumes phase2_spike_test.ss
// (12 case stub stage) + phase3_spike_test.ss (16 case pure-local
// reflection stage) — both removed in this Phase per D156 §Phase 4
// absorb decision. phase1_info_schema_unit_test.ss is kept because the
// 8 offline static-literal cases run without docker and the byte-level
// helper round-trip cases are protocol-layer (complementary, not
// redundant, to this schema-level e2e — same split as D147 / D155
// 范式).
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the
// test prints a hint and returns 0 so `bin/ss test tests/` stays green
// when docker is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d156_database_metadata/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Uses tables `integration_d156_parent` + `integration_d156_child` —
// InnoDB ER (child FK references parent.id; parent holds PK + UNIQUE
// INDEX on email) — to isolate from D134 (`users`) / D136 / D138 /
// D139 / D146 / D147 (`integration_d147`) / D151 / D154 / D155
// (`integration_d155`) under `bin/ss test tests/` parallel batch.
//
// Validates D156 §核心目标 §9 + §A.2 H1-H8 wire-end 实证 (10 cases):
//   Case 1 — getCatalogs() ≥1 row + contains testdb (H2 wire)
//   Case 2 — getSchemas() empty (single-tier MySQL H2 wire)
//   Case 3 — getTables() returns parent + child rows (H7 wire)
//   Case 4 — getColumns() col rows + RSMD spec col 1 = TABLE_CAT
//            (H4 + H7 wire — D155 path reuse)
//   Case 5 — getPrimaryKeys() PK + KEY_SEQ + PK_NAME (H8 wire)
//   Case 6 — getImportedKeys(child) + getExportedKeys(parent) FK
//            two-way (H8 wire)
//   Case 7 — getIndexInfo() ≥2 INDEX (PRIMARY + UNIQUE) (H8 wire)
//   Case 8 — ≥5 supportsXxx static cross MySQL 8.0 (H3 wire)
//   Case 9 — getDriver* + getDatabaseProductVersion(SELECT VERSION())
//            + getURL + getUserName (H6 wire — driver static + DB id)
//   Case 10 — getTables() RSMD getColumnCount ≥ 10 + col 1 = TABLE_CAT
//             (H4 wire — D155 path full reuse)
//
// See docs/3-decisions/D156-database-metadata.md §Phase 收关锚 §Phase 4.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { Connection, ResultSet, DatabaseMetaData, DriverManager_getConnection, SQLException, TYPE_FORWARD_ONLY, TYPE_SCROLL_INSENSITIVE, TYPE_SCROLL_SENSITIVE, TRANSACTION_REPEATABLE_READ, TRANSACTION_NONE } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"
import { dropAllTables } from "@/tests/jdbc/import/jdbc_test_helpers"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const SCHEMA = "testdb"
const PARENT = "integration_d156_parent"
const CHILD = "integration_d156_child"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    // Drop child first — InnoDB FK refuses parent drop while child references.
    tmpl.execute("DROP TABLE IF EXISTS integration_d156_child")
    tmpl.execute("DROP TABLE IF EXISTS integration_d156_parent")
    tmpl.execute("CREATE TABLE integration_d156_parent (id INT NOT NULL PRIMARY KEY, email VARCHAR(64) NOT NULL UNIQUE, name VARCHAR(64)) ENGINE=InnoDB")
    tmpl.execute("CREATE TABLE integration_d156_child (id INT NOT NULL PRIMARY KEY, parent_id INT NOT NULL, note VARCHAR(64), CONSTRAINT fk_d156_child_parent FOREIGN KEY (parent_id) REFERENCES integration_d156_parent(id)) ENGINE=InnoDB")
    tmpl.execute("INSERT INTO integration_d156_parent (id, email, name) VALUES (1, 'p1@d156.test', 'parent1')")
    tmpl.execute("INSERT INTO integration_d156_child (id, parent_id, note) VALUES (10, 1, 'child10')")
    return 0
}

function main() {
    // Probe — skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D156 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    // ── Case 1 — getCatalogs() ≥1 row + testdb present (H2 wire) ──
    test("Case 1 — getCatalogs() ≥1 row + contains testdb (H2 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        const rs = md.getCatalogs()
        let n = 0
        let foundTestdb = 0
        while (rs.next() == 1) {
            const name = rs.getString("TABLE_CAT")
            if (name == SCHEMA) { foundTestdb = 1 }
            n = n + 1
        }
        assertTrue(n >= 1)
        assertEqual(foundTestdb, 1)
        rs.close()
        conn.close()
    })

    // ── Case 2 — getSchemas() empty (single-tier MySQL H2) ──
    test("Case 2 — getSchemas() empty ResultSet (single-tier MySQL H2 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        const rs = md.getSchemas()
        assertEqual(rs.next(), 0)
        rs.close()
        conn.close()
    })

    // ── Case 3 — getTables() parent + child (H7 wire) ──
    test("Case 3 — getTables(catalog,'%','integration_d156_%','') returns parent + child (H7 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        const rs = md.getTables(SCHEMA, "%", "integration_d156_%", "")
        let foundParent = 0
        let foundChild = 0
        while (rs.next() == 1) {
            const name = rs.getString("TABLE_NAME")
            if (name == PARENT) { foundParent = 1 }
            if (name == CHILD) { foundChild = 1 }
        }
        assertEqual(foundParent, 1)
        assertEqual(foundChild, 1)
        rs.close()
        conn.close()
    })

    // ── Case 4 — getColumns + RSMD col 1 (H4 + H7 wire — D155 path reuse) ──
    test("Case 4 — getColumns(...) col rows + RSMD spec col 1 = TABLE_CAT (H4 + H7 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        const rs = md.getColumns(SCHEMA, "%", PARENT, "%")
        // Verify D155 ResultSetMetaData path before consuming rows. JDBC §11
        // getColumns spec returns 24 cols; getColumnName(1) = TABLE_CAT.
        const rsmd = rs.getMetaData()
        assertTrue(rsmd.getColumnCount() >= 10)
        assertEqual(rsmd.getColumnName(1), "TABLE_CAT")
        // Verify all 3 parent cols (id, email, name) reflect.
        let foundId = 0
        let foundEmail = 0
        let foundName = 0
        while (rs.next() == 1) {
            const col = rs.getString("COLUMN_NAME")
            if (col == "id") { foundId = 1 }
            if (col == "email") { foundEmail = 1 }
            if (col == "name") { foundName = 1 }
        }
        assertEqual(foundId, 1)
        assertEqual(foundEmail, 1)
        assertEqual(foundName, 1)
        rs.close()
        conn.close()
    })

    // ── Case 5 — getPrimaryKeys + KEY_SEQ + PK_NAME (H8 wire) ──
    test("Case 5 — getPrimaryKeys(catalog,'',parent) PK col + KEY_SEQ 1 + PK_NAME (H8 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        const rs = md.getPrimaryKeys(SCHEMA, "", PARENT)
        let foundPk = 0
        let keySeq = 0
        let pkName = ""
        while (rs.next() == 1) {
            const col = rs.getString("COLUMN_NAME")
            if (col == "id") {
                foundPk = 1
                keySeq = rs.getInt("KEY_SEQ")
                pkName = rs.getString("PK_NAME")
            }
        }
        assertEqual(foundPk, 1)
        assertEqual(keySeq, 1)
        // MySQL InnoDB always names the primary key constraint "PRIMARY".
        assertEqual(pkName, "PRIMARY")
        rs.close()
        conn.close()
    })

    // ── Case 6 — getImportedKeys(child) + getExportedKeys(parent) FK two-way (H8 wire) ──
    test("Case 6 — getImportedKeys(child) + getExportedKeys(parent) FK two-way (H8 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()

        // child.parent_id → parent.id incoming reference observed from child side.
        const rsImp = md.getImportedKeys(SCHEMA, "", CHILD)
        let foundImp = 0
        while (rsImp.next() == 1) {
            const fkTab = rsImp.getString("FKTABLE_NAME")
            const pkTab = rsImp.getString("PKTABLE_NAME")
            const fkCol = rsImp.getString("FKCOLUMN_NAME")
            if (fkTab == CHILD && pkTab == PARENT && fkCol == "parent_id") {
                foundImp = 1
            }
        }
        assertEqual(foundImp, 1)
        rsImp.close()

        // Same FK observed from parent side (outgoing).
        const rsExp = md.getExportedKeys(SCHEMA, "", PARENT)
        let foundExp = 0
        while (rsExp.next() == 1) {
            const fkTab = rsExp.getString("FKTABLE_NAME")
            const pkTab = rsExp.getString("PKTABLE_NAME")
            if (fkTab == CHILD && pkTab == PARENT) { foundExp = 1 }
        }
        assertEqual(foundExp, 1)
        rsExp.close()
        conn.close()
    })

    // ── Case 7 — getIndexInfo + ≥2 INDEX (PRIMARY + UNIQUE) (H8 wire) ──
    test("Case 7 — getIndexInfo(parent,0,1) ≥2 INDEX (PRIMARY + UNIQUE on email) (H8 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        const rs = md.getIndexInfo(SCHEMA, "", PARENT, 0, 1)
        let foundPrimary = 0
        let foundUniqueEmail = 0
        while (rs.next() == 1) {
            const idxName = rs.getString("INDEX_NAME")
            const colName = rs.getString("COLUMN_NAME")
            if (idxName == "PRIMARY") { foundPrimary = 1 }
            if (colName == "email") { foundUniqueEmail = 1 }
        }
        assertEqual(foundPrimary, 1)
        assertEqual(foundUniqueEmail, 1)
        rs.close()
        conn.close()
    })

    // ── Case 8 — ≥5 supportsXxx static cross MySQL 8.0 (H3 wire) ──
    test("Case 8 — supportsTransactions + BatchUpdates + IsolationLevel + ResultSetType (H3 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        assertEqual(md.supportsTransactions(), 1)
        assertEqual(md.supportsBatchUpdates(), 1)
        assertEqual(md.supportsTransactionIsolationLevel(TRANSACTION_REPEATABLE_READ), 1)
        assertEqual(md.supportsTransactionIsolationLevel(TRANSACTION_NONE), 0)
        assertEqual(md.supportsResultSetType(TYPE_FORWARD_ONLY), 1)
        assertEqual(md.supportsResultSetType(TYPE_SCROLL_INSENSITIVE), 1)
        assertEqual(md.supportsResultSetType(TYPE_SCROLL_SENSITIVE), 0)
        conn.close()
    })

    // ── Case 9 — driver static + DB identity (H6 wire) ──
    test("Case 9 — getDriverName + Version + getDatabaseProductVersion + getURL + getUserName (H6 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        assertEqual(md.getDriverName(), "MySQL Connector/SS")
        assertEqual(md.getDriverVersion(), "1.0")
        // SELECT VERSION() round-trip → MySQL 8.0.x — verify non-empty.
        const version = md.getDatabaseProductVersion()
        assertTrue(version.length() > 0)
        assertEqual(md.getURL(), URL)
        assertEqual(md.getUserName(), "root")
        conn.close()
    })

    // ── Case 10 — getTables RSMD col count + col 1 (H4 wire D155 path full reuse) ──
    test("Case 10 — getTables() RSMD getColumnCount ≥ 10 + col 1 = TABLE_CAT (H4 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const md = conn.getMetaData()
        const rs = md.getTables(SCHEMA, "%", "integration_d156_%", "")
        // JDBC §11 getTables spec returns 10 cols; first col TABLE_CAT.
        const rsmd = rs.getMetaData()
        assertTrue(rsmd.getColumnCount() >= 10)
        assertEqual(rsmd.getColumnName(1), "TABLE_CAT")
        rs.close()
        conn.close()
    })

    dropAllTables(URL, [CHILD, PARENT])
    println("All D156 10-shape integration tests passed!")
}
