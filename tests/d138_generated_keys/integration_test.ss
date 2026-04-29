// D138 Phase 4 — MySQL Generated Keys + JDBC + Spring KeyHolder e2e integration tests.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test file
// prints a hint and returns 0 so `bin/ss test tests/` stays green when docker
// is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d138_generated_keys/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Uses table `d138_generated_keys` to isolate from D134 (`users`) and D136
// (`users_d136`) under `bin/ss test tests/` parallel batch.
//
// See docs/3-decisions/D138-mysql-generated-keys.md §Phase 4 (§核心目标 6 判据)

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, ResultSet, PreparedStatement, DriverManager_getConnection, RETURN_GENERATED_KEYS, SQLException, SQLSyntaxErrorException } from "@/lib/java/sql"
import { JdbcTemplate, GeneratedKeyHolder } from "@/lib/spring/jdbc"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d138_generated_keys")
    tmpl.execute("CREATE TABLE d138_generated_keys (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), age INT) ENGINE=InnoDB")
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d138_generated_keys")
    return 0
}

function main() {
    // Probe: skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D138 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    // ── Direct path ──────────────────────────────────────────────
    test("case 1: INSERT + getLastInsertId direct path", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.prepareStatement("INSERT INTO d138_generated_keys (name, age) VALUES (?, ?)")
        stmt.setString(1, "Alice")
        stmt.setInt(2, 30)
        assertEqual(stmt.executeUpdate(), 1)
        const id = stmt.getLastInsertId()
        assertTrue(id > 0)
        stmt.close()
        conn.close()
    })

    // ── ResultSet (JDBC 4.3 spec, 2-arg prepareStatement) ────────
    test("case 2: INSERT + getGeneratedKeys ResultSet (JDBC 4.3 spec)", () => {
        const conn = DriverManager_getConnection(URL)
        // 2-arg prepareStatement(sql, RETURN_GENERATED_KEYS) is the JDBC 4.3
        // §Connection entry that opts in to generated-key retrieval. MySQL
        // returns lastInsertId unconditionally so the flag is informational
        // here, but the spec requires this path exist for portable drivers.
        const stmt = conn.prepareStatement("INSERT INTO d138_generated_keys (name, age) VALUES (?, ?)", RETURN_GENERATED_KEYS)
        stmt.setString(1, "Bob")
        stmt.setInt(2, 25)
        assertEqual(stmt.executeUpdate(), 1)
        const rs = stmt.getGeneratedKeys()
        assertEqual(rs.next(), 1)
        const key = rs.getInt("GENERATED_KEY")
        assertTrue(key > 0)
        // Past-end semantics: a second next() returns 0.
        assertEqual(rs.next(), 0)
        rs.close()
        stmt.close()
        conn.close()
    })

    // ── Spring KeyHolder ─────────────────────────────────────────
    test("case 3: JdbcTemplate.update(sql, setter, keyHolder) Spring path", () => {
        const tpl = new JdbcTemplate(URL)
        let arr: Array<Map<string, int>> = []
        let holder = new GeneratedKeyHolder(arr)
        const r = tpl.update("INSERT INTO d138_generated_keys (name, age) VALUES (?, ?)",
            (s) => { s.setString(1, "Trinity"); s.setInt(2, 35) }, holder)
        assertEqual(r, 1)
        const k = holder.getKey()
        assertTrue(k > 0)
        assertEqual(holder.getKeyAsLong(), k)
        assertEqual(holder.getKeyList().length(), 1)
        assertEqual(holder.getKeys().get("GENERATED_KEY"), k)
    })

    // ── Multi-row VALUES ─────────────────────────────────────────
    test("case 4: multi-row VALUES INSERT — getLastInsertId returns first id", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.prepareStatement("INSERT INTO d138_generated_keys (name, age) VALUES (?, ?), (?, ?), (?, ?)")
        stmt.setString(1, "Neo")
        stmt.setInt(2, 32)
        stmt.setString(3, "Morpheus")
        stmt.setInt(4, 45)
        stmt.setString(5, "Smith")
        stmt.setInt(6, 28)
        assertEqual(stmt.executeUpdate(), 3)
        const firstId = stmt.getLastInsertId()
        assertTrue(firstId > 0)
        stmt.close()
        conn.close()

        // MySQL protocol: LAST_INSERT_ID() returns the id of the FIRST row in
        // the batch; subsequent rows have ids first+1, first+2 (innodb_autoinc
        // _lock_mode=1 default). Verify by name lookup.
        const tpl = new JdbcTemplate(URL)
        assertEqual(tpl.queryForInt("SELECT id FROM d138_generated_keys WHERE name = ?",
            (s) => { s.setString(1, "Neo") }, "id"), firstId)
    })

    // ── Transaction commit ───────────────────────────────────────
    test("case 5: transaction INSERT + commit — id persists", () => {
        const conn = DriverManager_getConnection(URL)
        conn.setAutoCommit(0)
        const stmt = conn.prepareStatement("INSERT INTO d138_generated_keys (name, age) VALUES (?, ?)")
        stmt.setString(1, "Cypher")
        stmt.setInt(2, 40)
        assertEqual(stmt.executeUpdate(), 1)
        const id = stmt.getLastInsertId()
        assertTrue(id > 0)
        stmt.close()
        conn.commit()
        conn.close()

        // Fresh Connection sees the committed row — proves the id captured
        // pre-commit refers to the row that survived the commit.
        const tpl = new JdbcTemplate(URL)
        assertEqual(tpl.queryForString("SELECT name FROM d138_generated_keys WHERE id = ?",
            (s) => { s.setInt(1, id) }, "name"), "Cypher")
    })

    // ── ERR packet defensive ─────────────────────────────────────
    test("case 6: INSERT failure (ERR packet) — throws SQLSyntaxErrorException", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        // ERR packet path: target a non-existent table. D139 Phase 2 升级:
        // readUpdateResultPacket throws SQLSyntaxErrorException(table not exist
        // → SQLState 42S02 → dispatchSQLException class "42"). lastInsertId is
        // never written so it stays at the default 0.
        let caught = 0
        try {
            stmt.executeUpdate("INSERT INTO d138_does_not_exist (col) VALUES (1)")
        } catch (e: SQLSyntaxErrorException) {
            caught = 1
        }
        assertEqual(caught, 1)
        assertEqual(stmt.getLastInsertId(), 0)
        stmt.close()
        conn.close()
    })

    dropTable()

    println("All D138 Phase 4 generated keys integration tests passed!")
}
