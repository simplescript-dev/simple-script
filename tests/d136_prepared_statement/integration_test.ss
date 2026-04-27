// D136 Phase 3 — MySQL Prepared Statement protocol e2e integration tests.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test file
// prints a hint and exits 0 so `bin/ss test tests/` stays green when docker is
// unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d136_prepared_statement/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Coverage of the binary protocol path in lib/com/mysql/prepared.ss:
//
//   sendComStmtPrepare → readPrepareOk → readParamDef + readColumnDefList
//                                  ↓
//                  MysqlPreparedStatement(setInt/setString/setNull)
//                                  ↓
//                          sendComStmtExecute
//                              ↓        ↓
//                  readQueryResultSetBinary  readUpdateResult
//                  (parseBinaryRow stream)   (OK packet)
//                                  ↓
//                          sendComStmtClose
//
//   Test 1: setInt(1, 1) single-param SELECT (Alice row)
//   Test 2: setInt + setString + setInt INSERT (multi-param)
//   Test 3: no-param SELECT * ORDER BY id (multi-row binary result set,
//           covers parseBinaryRow streaming + multiple types in same row)
//   Test 4: setNull + setInt NULL handling (NULL bitmap +0/+2 offset
//           paths — execute request +0, binary row +2)
//   Test 5: stmt.close() + new prepareStatement on same Connection
//           (statement_id lifecycle vs Connection fd lifecycle)
//
// JdbcTemplate retcon is deferred to D137 sub-follow-up — see
// docs/3-decisions/D136-mysql-prepared-statement.md §附录 B Phase 3.

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, PreparedStatement, ResultSet, DriverManager_getConnection } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS users_d136")
    tmpl.execute("CREATE TABLE users_d136 (id INT PRIMARY KEY, name VARCHAR(100), age INT) ENGINE=InnoDB")
    tmpl.update("INSERT INTO users_d136 VALUES (1, 'Alice', 30)")
    tmpl.update("INSERT INTO users_d136 VALUES (2, 'Bob', 25)")
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS users_d136")
    return 0
}

function main() {
    // Probe: skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    const probe = DriverManager_getConnection(URL)
    if (probe.isClosed() == 1) {
        println("D136 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }
    probe.close()

    recreateTable()

    // ── 1. Single-param SELECT ──────────────────────────────────────
    test("prepareStatement + setInt + executeQuery (single param SELECT)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.prepareStatement("SELECT id, name, age FROM users_d136 WHERE id = ?")
        stmt.setInt(1, 1)
        const rs = stmt.executeQuery()
        assertEqual(rs.next(), 1)
        assertEqual(rs.getInt("id"), 1)
        assertEqual(rs.getString("name"), "Alice")
        assertEqual(rs.getInt("age"), 30)
        assertEqual(rs.next(), 0)
        rs.close()
        stmt.close()
        conn.close()
    })

    // ── 2. Multi-param INSERT ──────────────────────────────────────
    test("prepareStatement + setInt+setString+setInt + executeUpdate (multi-param INSERT)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.prepareStatement("INSERT INTO users_d136 VALUES (?, ?, ?)")
        stmt.setInt(1, 100)
        stmt.setString(2, "Trinity")
        stmt.setInt(3, 35)
        assertEqual(stmt.executeUpdate(), 1)
        stmt.close()
        conn.close()

        // Cross-check via second prepareStatement
        const verify = DriverManager_getConnection(URL)
        const sel = verify.prepareStatement("SELECT name, age FROM users_d136 WHERE id = ?")
        sel.setInt(1, 100)
        const rs = sel.executeQuery()
        assertEqual(rs.next(), 1)
        assertEqual(rs.getString("name"), "Trinity")
        assertEqual(rs.getInt("age"), 35)
        rs.close()
        sel.close()
        verify.close()
    })

    // ── 3. Multi-row no-param SELECT (binary result set streaming) ──
    test("prepareStatement + executeQuery no-param (multi-row + multi-type)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.prepareStatement("SELECT id, name, age FROM users_d136 ORDER BY id")
        const rs = stmt.executeQuery()
        let rowCount = 0
        let aliceFound = 0
        let bobFound = 0
        let trinityFound = 0
        while (rs.next() == 1) {
            rowCount = rowCount + 1
            const id = rs.getInt("id")
            if (id == 1) {
                assertEqual(rs.getString("name"), "Alice")
                assertEqual(rs.getInt("age"), 30)
                aliceFound = 1
            }
            if (id == 2) {
                assertEqual(rs.getString("name"), "Bob")
                assertEqual(rs.getInt("age"), 25)
                bobFound = 1
            }
            if (id == 100) {
                assertEqual(rs.getString("name"), "Trinity")
                assertEqual(rs.getInt("age"), 35)
                trinityFound = 1
            }
        }
        assertEqual(aliceFound, 1)
        assertEqual(bobFound, 1)
        assertEqual(trinityFound, 1)
        assertTrue(rowCount >= 3)
        rs.close()
        stmt.close()
        conn.close()
    })

    // ── 4. NULL handling (setNull execute-request +0 + binary row +2) ──
    test("prepareStatement + setNull + executeUpdate (NULL bitmap dual offset)", () => {
        const conn = DriverManager_getConnection(URL)
        const ins = conn.prepareStatement("INSERT INTO users_d136 VALUES (?, ?, ?)")
        ins.setInt(1, 200)
        ins.setNull(2)
        ins.setInt(3, 28)
        assertEqual(ins.executeUpdate(), 1)
        ins.close()

        const sel = conn.prepareStatement("SELECT id, name, age FROM users_d136 WHERE id = ?")
        sel.setInt(1, 200)
        const rs = sel.executeQuery()
        assertEqual(rs.next(), 1)
        assertEqual(rs.getInt("id"), 200)
        // SS has no null sentinel — NULL columns surface as "" via parseBinaryRow.
        assertEqual(rs.getString("name"), "")
        assertEqual(rs.getInt("age"), 28)
        rs.close()
        sel.close()
        conn.close()
    })

    // ── 5. close + Connection reuse (statement_id lifecycle) ──
    test("prepareStatement close + Connection reuse (separate statement_ids)", () => {
        const conn = DriverManager_getConnection(URL)

        const stmt1 = conn.prepareStatement("SELECT name FROM users_d136 WHERE id = ?")
        stmt1.setInt(1, 1)
        const rs1 = stmt1.executeQuery()
        assertEqual(rs1.next(), 1)
        assertEqual(rs1.getString("name"), "Alice")
        rs1.close()
        stmt1.close()

        // Same Connection, second prepareStatement allocates a new statement_id;
        // closing stmt1 must not invalidate the Connection fd.
        const stmt2 = conn.prepareStatement("SELECT age FROM users_d136 WHERE id = ?")
        stmt2.setInt(1, 2)
        const rs2 = stmt2.executeQuery()
        assertEqual(rs2.next(), 1)
        assertEqual(rs2.getInt("age"), 25)
        rs2.close()
        stmt2.close()

        assertEqual(conn.isClosed(), 0)
        conn.close()
    })

    dropTable()

    println("All D136 Phase 3 prepared statement integration tests passed!")
}
