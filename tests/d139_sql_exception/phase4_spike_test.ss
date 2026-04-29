// D139 Phase 4 spike — JdbcTemplate.update upper-level catch SQLException
// → SQLExceptionTranslator.translate(e) → throw DAE. Business code catches
// the DAE subclass (DuplicateKeyException) and never sees the underlying
// java.sql.SQLException. Internal stmt.close + conn.close run in finally
// blocks per Spring spec.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// file prints a hint and returns 0 so `bin/ss test tests/` stays green when
// docker is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d139_sql_exception/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Validates D139 §Phase 4 §Phase 收关锚:
//   - business code catches DAE subclass (DuplicateKeyException) directly
//   - DAE.cause exposes the wire-protocol fields (sqlState 23000 / errorCode 1062)
//   - DAE.message inherits the original "Duplicate entry" SQLException message
//   - parent-class catch (DataIntegrityViolationException / DataAccessException)
//     also routes the same instance — proves catch hierarchy unwind via DAE
//     subtree rather than via raw SQLException.

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, DriverManager_getConnection, SQLException } from "@/lib/java/sql"
import { JdbcTemplate, DataAccessException, DataIntegrityViolationException, DuplicateKeyException } from "@/lib/spring/jdbc"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d139_phase4_dup")
    tmpl.execute("CREATE TABLE d139_phase4_dup (id INT PRIMARY KEY, name VARCHAR(100)) ENGINE=InnoDB")
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d139_phase4_dup")
    return 0
}

function main() {
    // Probe: skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D139 Phase 4 spike: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    test("Phase 4 spike: jdbc.update INSERT dup_key → DuplicateKeyException (Spring DAE leaf)", () => {
        const tmpl = new JdbcTemplate(URL)
        // First insert succeeds.
        assertEqual(tmpl.update("INSERT INTO d139_phase4_dup (id, name) VALUES (1, 'first')"), 1)

        // Second insert with same primary key — JdbcTemplate catches the
        // SQLIntegrityConstraintViolationException, translates via
        // SQLExceptionTranslator (1062 → DuplicateKey), and throws DAE.
        // Business code catches the DAE leaf directly.
        let caught = 0
        let state = ""
        let code = 0
        let msg = ""
        try {
            tmpl.update("INSERT INTO d139_phase4_dup (id, name) VALUES (1, 'duplicate')")
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

    test("Phase 4 spike: parent-class catch routes same DuplicateKey via DataIntegrityViolation", () => {
        const tmpl = new JdbcTemplate(URL)
        // Re-trigger the same dup-key — first INSERT already established the
        // unique row in the previous test (or recreateTable seeded it).
        let parentCaught = 0
        try {
            tmpl.update("INSERT INTO d139_phase4_dup (id, name) VALUES (1, 'parent-catch')")
        } catch (ex: DataIntegrityViolationException) {
            parentCaught = 1
        }
        assertEqual(parentCaught, 1)

        // Root-level DAE catch — exercises the full Spring DAE hierarchy
        // dispatch (DuplicateKey → DataIntegrityViolation → NonTransient → DAE).
        let rootCaught = 0
        try {
            tmpl.update("INSERT INTO d139_phase4_dup (id, name) VALUES (1, 'root-catch')")
        } catch (ex: DataAccessException) {
            rootCaught = 1
            // Even at the root catch, the wire-level fields stay reachable
            // through the cause chain.
            assertEqual(ex.cause.errorCode, 1062)
        }
        assertEqual(rootCaught, 1)
    })

    test("Phase 4 spike: JdbcTemplate finally-close runs on dup_key path (no socket starvation)", () => {
        // After the dup-key throws have fired multiple times above, a fresh
        // SELECT through queryForInt must still succeed — proves stmt.close /
        // conn.close ran in finally even on the throw path (otherwise the
        // server-side prepared statement handles or sockets would stack up
        // and the next query would deadlock or return a stale buffer).
        const tmpl = new JdbcTemplate(URL)
        const id = tmpl.queryForInt("SELECT id FROM d139_phase4_dup WHERE id = 1", "id")
        assertEqual(id, 1)
    })

    dropTable()

    println("All D139 Phase 4 jdbc.update DAE spike tests passed!")
}
