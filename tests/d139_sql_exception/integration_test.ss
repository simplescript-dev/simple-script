// D139 Phase 5 — 7-shape integration test (D139 主线 close).
//
// Covers all 7 forms of D139 §核心目标 single criterion in one main file.
// Subsumes Phase 2 spike (Case 2 dup_key + lower-level SQLException) and
// Phase 4 spike (Case 6 4-layer DAE catch fallthrough + Case 2 jdbc.update
// translate path); the legacy spikes are removed in this Phase. Phase 3
// translator_spike_test.ss is kept — it exercises SQLExceptionTranslator's
// 12 reverse-lookup paths in pure local mode (no docker dependency) and
// is complementary, not redundant, to this end-to-end suite.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// file prints a hint and returns 0 so `bin/ss test tests/` stays green
// when docker is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d139_sql_exception/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Uses table `d139_sql_exception_test` to isolate from D134 (`users`) /
// D136 (`users_d136`) / D138 (`d138_generated_keys`) under
// `bin/ss test tests/` parallel batch.
//
// Validates D139 §核心目标 single criterion (7 cases):
//   Case 1 — wrong-password URL                → CannotGetJdbcConnectionException + cause.sqlState 28xxx + cause.errorCode 1045
//   Case 2 — INSERT dup_key                    → DuplicateKeyException             + cause.sqlState 23000 + cause.errorCode 1062
//   Case 3 — INSERT non-existent table         → BadSqlGrammarException            + cause.sqlState 42S02 + cause.errorCode 1146
//   Case 4 — NOT NULL violation                → DataIntegrityViolationException   + cause.sqlState 23000 + cause.errorCode 1048
//   Case 5 — catch SQLException 3-field        → message + sqlState + errorCode all reachable on the raw java.sql layer
//   Case 6 — 5-layer catch hierarchy           → DuplicateKey → DataIntegrityViolation → NonTransientDAE → DAE → Error all match the same instance
//   Case 7 — wrong-user URL handshake          → CannotGetJdbcConnectionException + cause.sqlState 28000 + cause.errorCode 1045
//
// SS arrow-function closure capture rebinds outer-scope catch `e`
// (D139 §Followup F10) — every inner catch in this file uses `ex`, never
// `e`, to avoid reusing the outer probe-catch name.

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, PreparedStatement, DriverManager_getConnection, SQLException } from "@/lib/java/sql"
import { JdbcTemplate, DataAccessException, NonTransientDataAccessException, DataIntegrityViolationException, BadSqlGrammarException, CannotGetJdbcConnectionException, DuplicateKeyException } from "@/lib/spring/jdbc"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const URL_WRONG_PWD = "jdbc:mysql://root:wrongpass@127.0.0.1:3307/testdb"
const URL_WRONG_USER = "jdbc:mysql://wronguser:wrongpass@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d139_sql_exception_test")
    tmpl.execute("CREATE TABLE d139_sql_exception_test (id INT PRIMARY KEY, name VARCHAR(100) NOT NULL) ENGINE=InnoDB")
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d139_sql_exception_test")
    return 0
}

function main() {
    // Probe: skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D139 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    // ── Case 1: wrong-password URL → CannotGetJdbcConnectionException ───────
    test("Case 1: wrong-password URL → CannotGetJdbcConnectionException + sqlState 28xxx + errorCode 1045", () => {
        const tmpl = new JdbcTemplate(URL_WRONG_PWD)
        let caught = 0
        let state = ""
        let code = 0
        try {
            tmpl.execute("SELECT 1")
        } catch (ex: CannotGetJdbcConnectionException) {
            caught = 1
            state = ex.cause.sqlState
            code = ex.cause.errorCode
        }
        assertEqual(caught, 1)
        assertEqual(code, 1045)
        // MySQL "Access denied" → sqlState class 28 (5-char "28000").
        assertEqual(state.length(), 5)
        assertEqual(state.substring(0, 2), "28")
    })

    // ── Case 2: INSERT dup_key → DuplicateKeyException ──────────────────────
    test("Case 2: INSERT dup_key → DuplicateKeyException + sqlState 23000 + errorCode 1062", () => {
        const tmpl = new JdbcTemplate(URL)
        // Seed row id=1 (idempotent for parallel re-runs).
        tmpl.update("INSERT IGNORE INTO d139_sql_exception_test (id, name) VALUES (1, 'first')")

        let caught = 0
        let state = ""
        let code = 0
        let msg = ""
        try {
            tmpl.update("INSERT INTO d139_sql_exception_test (id, name) VALUES (1, 'duplicate')")
        } catch (ex: DuplicateKeyException) {
            caught = 1
            state = ex.cause.sqlState
            code = ex.cause.errorCode
            msg = ex.message
        }
        assertEqual(caught, 1)
        assertEqual(state, "23000")
        assertEqual(code, 1062)
        assertTrue(msg.length() > 0)
    })

    // ── Case 3: INSERT non-existent table → BadSqlGrammarException ──────────
    test("Case 3: INSERT non-existent table → BadSqlGrammarException + sqlState 42S02 + errorCode 1146", () => {
        const tmpl = new JdbcTemplate(URL)
        let caught = 0
        let state = ""
        let code = 0
        try {
            tmpl.update("INSERT INTO d139_does_not_exist (id) VALUES (1)")
        } catch (ex: BadSqlGrammarException) {
            caught = 1
            state = ex.cause.sqlState
            code = ex.cause.errorCode
        }
        assertEqual(caught, 1)
        assertEqual(state, "42S02")
        assertEqual(code, 1146)
    })

    // ── Case 4: NOT NULL violation → DataIntegrityViolationException ────────
    test("Case 4: NOT NULL violation → DataIntegrityViolationException + sqlState 23000 + errorCode 1048", () => {
        const tmpl = new JdbcTemplate(URL)
        let caught = 0
        let state = ""
        let code = 0
        try {
            // `name` column is VARCHAR(100) NOT NULL; raw SQL NULL literal
            // triggers MySQL errorCode 1048 ("Column 'name' cannot be null").
            tmpl.update("INSERT INTO d139_sql_exception_test (id, name) VALUES (2, NULL)")
        } catch (ex: DataIntegrityViolationException) {
            caught = 1
            state = ex.cause.sqlState
            code = ex.cause.errorCode
        }
        assertEqual(caught, 1)
        assertEqual(state, "23000")
        assertEqual(code, 1048)
    })

    // ── Case 5: catch SQLException 3-field on raw java.sql layer ────────────
    test("Case 5: catch SQLException 3-field (message + sqlState + errorCode) on raw java.sql layer", () => {
        // Bypass JdbcTemplate to reach the java.sql layer directly — the
        // SQLException subclass thrown by the protocol layer (here
        // SQLIntegrityConstraintViolationException via dispatchSQLException
        // 23xxx fallback) carries all three wire fields.
        const conn = DriverManager_getConnection(URL)
        const ins = conn.prepareStatement("INSERT INTO d139_sql_exception_test (id, name) VALUES (?, ?)")
        ins.setInt(1, 1)
        ins.setString(2, "raw-sql-layer")

        let caught = 0
        let msg = ""
        let state = ""
        let code = 0
        try {
            ins.executeUpdate()
        } catch (ex: SQLException) {
            caught = 1
            msg = ex.message
            state = ex.sqlState
            code = ex.errorCode
        }
        ins.close()
        conn.close()

        assertEqual(caught, 1)
        assertTrue(msg.length() > 0)
        assertEqual(state, "23000")
        assertEqual(code, 1062)
    })

    // ── Case 6: 5-layer catch hierarchy ─────────────────────────────────────
    test("Case 6: 5-layer catch hierarchy (DuplicateKey → DataIntegrityViolation → NonTransientDAE → DAE → Error)", () => {
        const tmpl = new JdbcTemplate(URL)

        // 6a — leaf: DuplicateKeyException catches the exact subtype.
        let leafCaught = 0
        try {
            tmpl.update("INSERT INTO d139_sql_exception_test (id, name) VALUES (1, 'leaf')")
        } catch (ex: DuplicateKeyException) {
            leafCaught = 1
        }
        assertEqual(leafCaught, 1)

        // 6b — mid: DataIntegrityViolationException (parent) catches the same subtype.
        let midCaught = 0
        try {
            tmpl.update("INSERT INTO d139_sql_exception_test (id, name) VALUES (1, 'mid')")
        } catch (ex: DataIntegrityViolationException) {
            midCaught = 1
        }
        assertEqual(midCaught, 1)

        // 6c — grandparent: NonTransientDataAccessException catches the same subtype.
        let grandCaught = 0
        try {
            tmpl.update("INSERT INTO d139_sql_exception_test (id, name) VALUES (1, 'grand')")
        } catch (ex: NonTransientDataAccessException) {
            grandCaught = 1
        }
        assertEqual(grandCaught, 1)

        // 6d — DAE root: DataAccessException + cause fields still reachable.
        let rootCaught = 0
        try {
            tmpl.update("INSERT INTO d139_sql_exception_test (id, name) VALUES (1, 'root')")
        } catch (ex: DataAccessException) {
            rootCaught = 1
            assertEqual(ex.cause.errorCode, 1062)
            assertEqual(ex.cause.sqlState, "23000")
        }
        assertEqual(rootCaught, 1)

        // 6e — Error top: SS prelude `class Error` catches DAE (DAE extends Error).
        let errorCaught = 0
        try {
            tmpl.update("INSERT INTO d139_sql_exception_test (id, name) VALUES (1, 'error-top')")
        } catch (ex: Error) {
            errorCaught = 1
        }
        assertEqual(errorCaught, 1)
    })

    // ── Case 7: wrong-user URL handshake → CannotGetJdbcConnectionException ─
    test("Case 7: wrong-user URL handshake → CannotGetJdbcConnectionException + sqlState 28000 + errorCode 1045", () => {
        const tmpl = new JdbcTemplate(URL_WRONG_USER)
        let caught = 0
        let state = ""
        let code = 0
        try {
            tmpl.execute("SELECT 1")
        } catch (ex: CannotGetJdbcConnectionException) {
            caught = 1
            state = ex.cause.sqlState
            code = ex.cause.errorCode
        }
        assertEqual(caught, 1)
        assertEqual(code, 1045)
        assertEqual(state, "28000")
    })

    dropTable()

    println("All D139 7-shape integration tests passed!")
}
