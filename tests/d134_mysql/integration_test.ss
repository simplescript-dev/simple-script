// D134 Phase 6 — JDBC MySQL e2e integration tests.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test file
// prints a hint and exits 0 so `bin/ss test tests/` stays green when docker is
// unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d134_mysql/integration_test.ss
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// D135 Phase 2 supersedes: the fixture now uses MySQL 8 default plugin
// `caching_sha2_password` (the `--default-authentication-plugin` override is
// gone). The SS driver speaks the fast-path direct mode end-to-end; the
// authentication plugin is transparent to this Connection / Statement /
// ResultSet layer so all 8 sub-tests below remain unchanged.

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, ResultSet, PreparedStatement, DriverManager_getConnection, SQLException } from "@/lib/java/sql"
import { JdbcTemplate, withTransaction } from "@/lib/spring/jdbc"
import { JpaRepository, JpaRepositoryFactory_create } from "@/lib/spring/data"
import { dropAllTables } from "@/tests/jdbc/import/jdbc_test_helpers"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS users")
    tmpl.execute("CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100), age INT) ENGINE=InnoDB")
    return 0
}

function clearAll(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DELETE FROM users")
    return 0
}

function countAll(): int {
    const tmpl = new JdbcTemplate(URL)
    return tmpl.queryForInt("SELECT COUNT(*) AS cnt FROM users", "cnt")
}

function main() {
    // Probe: skip the file (exit 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D134 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    // ── 1. Connection lifecycle ─────────────────────────────────────
    test("connect + isClosed transitions + close", () => {
        const conn = DriverManager_getConnection(URL)
        assertEqual(conn.isClosed(), 0)
        conn.close()
        assertEqual(conn.isClosed(), 1)
    })

    // ── 2. CRUD via PreparedStatement ───────────────────────────────
    // D137 Phase 3: every literal value retcons to ?-bound prepareStatement
    // + setter + executeUpdate/executeQuery (§核心原则 1).
    test("CRUD: INSERT / SELECT / UPDATE / DELETE", () => {
        clearAll()
        const conn = DriverManager_getConnection(URL)

        const insStmt = conn.prepareStatement("INSERT INTO users VALUES (?, ?, ?)")
        insStmt.setInt(1, 1)
        insStmt.setString(2, "Alice")
        insStmt.setInt(3, 30)
        assertEqual(insStmt.executeUpdate(), 1)
        insStmt.close()

        const selRowStmt = conn.prepareStatement("SELECT id, name, age FROM users WHERE id = ?")
        selRowStmt.setInt(1, 1)
        const rs = selRowStmt.executeQuery()
        assertEqual(rs.next(), 1)
        assertEqual(rs.getInt("id"), 1)
        assertEqual(rs.getString("name"), "Alice")
        assertEqual(rs.getInt("age"), 30)
        assertEqual(rs.next(), 0)
        rs.close()
        selRowStmt.close()

        const updStmt = conn.prepareStatement("UPDATE users SET age = ? WHERE id = ?")
        updStmt.setInt(1, 31)
        updStmt.setInt(2, 1)
        assertEqual(updStmt.executeUpdate(), 1)
        updStmt.close()

        const selAgeStmt = conn.prepareStatement("SELECT age FROM users WHERE id = ?")
        selAgeStmt.setInt(1, 1)
        const rs2 = selAgeStmt.executeQuery()
        assertEqual(rs2.next(), 1)
        assertEqual(rs2.getInt("age"), 31)
        rs2.close()
        selAgeStmt.close()

        const delStmt = conn.prepareStatement("DELETE FROM users WHERE id = ?")
        delStmt.setInt(1, 1)
        assertEqual(delStmt.executeUpdate(), 1)
        delStmt.close()

        conn.close()
    })

    // ── 3. Transaction commit on a single connection ───────────────
    // D137 Phase 3: prepared INSERT under autocommit=0, three setters.
    test("transaction commit (single conn)", () => {
        clearAll()
        const conn = DriverManager_getConnection(URL)
        conn.setAutoCommit(0)
        const pstmt = conn.prepareStatement("INSERT INTO users VALUES (?, ?, ?)")
        pstmt.setInt(1, 10)
        pstmt.setString(2, "Bob")
        pstmt.setInt(3, 25)
        pstmt.executeUpdate()
        pstmt.close()
        conn.commit()
        conn.close()
        assertEqual(countAll(), 1)
    })

    // ── 4. Transaction rollback on a single connection ─────────────
    // D137 Phase 3: prepared INSERT before rollback, three setters.
    test("transaction rollback (single conn)", () => {
        clearAll()
        const conn = DriverManager_getConnection(URL)
        conn.setAutoCommit(0)
        const pstmt = conn.prepareStatement("INSERT INTO users VALUES (?, ?, ?)")
        pstmt.setInt(1, 11)
        pstmt.setString(2, "Eve")
        pstmt.setInt(3, 28)
        pstmt.executeUpdate()
        pstmt.close()
        conn.rollback()
        conn.close()
        assertEqual(countAll(), 0)
    })

    // ── 5. withTransaction smoke ───────────────────────────────────
    // fn has no args/closure for sharing the outer connection (D134 Phase 5
    // simplification); the actual commit/rollback effect is verified by 3+4.
    test("withTransaction commit path returns 0", () => {
        clearAll()
        const r = withTransaction(URL, () => { return 0 })
        assertEqual(r, 0)
    })
    test("withTransaction rollback path returns -1", () => {
        clearAll()
        const r = withTransaction(URL, () => { return -1 })
        assertEqual(r, -1)
    })

    // ── 6. JdbcTemplate execute / update / queryForString / queryForInt ──
    // D137 Phase 3: every JdbcTemplate call retcons to its (sql, setter, ...)
    // callback overload (D137 §Phase 1 — d2df1ba).
    test("JdbcTemplate execute + update + queryForString/Int", () => {
        clearAll()
        const tmpl = new JdbcTemplate(URL)
        assertEqual(tmpl.update("INSERT INTO users VALUES (?, ?, ?)", (s) => {
            s.setInt(1, 20)
            s.setString(2, "Trinity")
            s.setInt(3, 35)
        }), 1)
        assertEqual(tmpl.queryForString("SELECT name FROM users WHERE id = ?",
            (s) => { s.setInt(1, 20) }, "name"), "Trinity")
        assertEqual(tmpl.queryForInt("SELECT age FROM users WHERE id = ?",
            (s) => { s.setInt(1, 20) }, "age"), 35)
        assertEqual(tmpl.execute("DELETE FROM users WHERE id = ?",
            (s) => { s.setInt(1, 20) }), 1)
        assertEqual(countAll(), 0)
    })

    // ── 7. JpaRepository save / count / deleteAll ──────────────────
    // D137 Phase 2: save retcon to PreparedStatementSetter callback.
    test("JpaRepository save + count + deleteAll", () => {
        clearAll()
        const repo = JpaRepositoryFactory_create(URL, "users", "id,name,age")
        assertEqual(repo.save((s) => {
            s.setInt(1, 30)
            s.setString(2, "Neo")
            s.setInt(3, 32)
        }), 1)
        assertEqual(repo.save((s) => {
            s.setInt(1, 31)
            s.setString(2, "Morpheus")
            s.setInt(3, 45)
        }), 1)
        assertEqual(repo.count(), 2)
        repo.deleteAll()
        assertEqual(repo.count(), 0)
    })

    dropAllTables(URL, ["users"])

    println("All D134 Phase 6 integration tests passed!")
}
