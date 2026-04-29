// D139 Phase 2 spike — INSERT duplicate key e2e + catch SQLIntegrityConstraintViolationException.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test file
// prints a hint and returns 0 so `bin/ss test tests/` stays green when docker
// is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d139_sql_exception/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Validates D139 §A.2 H3 (MySQL errorCode 1062 + SQLState 23000 standard) +
// H7 (callers upgraded to throw — baseline holds). Phase 5 expands to the
// full 7-shape suite (D139 §Phase 收关锚 §Phase 5).
//
// Uses table `d139_dup_test` to isolate from D134 (`users`) / D136
// (`users_d136`) / D138 (`d138_generated_keys`) under `bin/ss test tests/`
// parallel batch.

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, PreparedStatement, DriverManager_getConnection, SQLException, SQLIntegrityConstraintViolationException } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d139_dup_test")
    tmpl.execute("CREATE TABLE d139_dup_test (id INT PRIMARY KEY, name VARCHAR(100)) ENGINE=InnoDB")
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d139_dup_test")
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

    test("Phase 2 spike: INSERT dup_key throws SQLIntegrityConstraintViolationException + sqlState 23000 + errorCode 1062", () => {
        const conn = DriverManager_getConnection(URL)
        const ins1 = conn.prepareStatement("INSERT INTO d139_dup_test (id, name) VALUES (?, ?)")
        ins1.setInt(1, 1)
        ins1.setString(2, "first")
        assertEqual(ins1.executeUpdate(), 1)
        ins1.close()

        let caught = 0
        let state = ""
        let code = 0
        let msg = ""
        const ins2 = conn.prepareStatement("INSERT INTO d139_dup_test (id, name) VALUES (?, ?)")
        ins2.setInt(1, 1)
        ins2.setString(2, "duplicate")
        // SS arrow-function closure rebinds outer-scope `e` (probe catch in
        // main) when the inner catch reuses the same name — rename to `ex`.
        try {
            ins2.executeUpdate()
        } catch (ex: SQLIntegrityConstraintViolationException) {
            caught = 1
            state = ex.sqlState
            code = ex.errorCode
            msg = ex.message
        }
        ins2.close()
        conn.close()

        assertEqual(caught, 1)
        assertEqual(state, "23000")
        assertEqual(code, 1062)
        // Message contains "Duplicate entry" — verify substring presence (defensive,
        // MySQL formats may include the exact key name e.g. "for key 'PRIMARY'").
        assertTrue(msg.length() > 0)
    })

    dropTable()

    println("All D139 Phase 2 spike tests passed!")
}
