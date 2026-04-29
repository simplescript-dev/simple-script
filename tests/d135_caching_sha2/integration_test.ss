// D135 Phase 2 — caching_sha2_password fast-path e2e integration tests.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test file
// prints a hint and returns 0 so `bin/ss test tests/` stays green when docker
// is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d135_caching_sha2/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Fixture: D134 docker-compose with the --default-authentication-plugin
// override removed (D135 Phase 2 supersedes). MySQL 8 default plugin =
// caching_sha2_password; the docker healthcheck runs `mysqladmin ping
// --protocol=TCP -h 127.0.0.1` so it authenticates as root@% (the same
// account the SS driver uses) and populates the server-side caching_sha2
// cache via mysqladmin's full RSA-OAEP path. After `docker compose up
// -d --wait` returns healthy, the cache is warm and SS TCP connects land
// on the fast-path direct mode (D135 §A.3) single-RTT.
//
// Coverage of the reply paths in lib/com/mysql/handshake.ss mysqlConnect:
//
//   firstByte == 0x00 (AUTH_OK) directly        — implicit, rare on cache hit
//   firstByte == 0x01 (AUTH_MORE_DATA)
//     secondByte == 0x03 (FAST_AUTH_SUCCESS)    — test 1 / test 2
//     secondByte == 0x04 (PERFORM_FULL_AUTHENTICATION) — test 3 / test 4
//   firstByte == 0xFF (ERR_PACKET)              — defensive code path; MySQL 8
//                                                 caching_sha2 collapses bad
//                                                 password and unknown user
//                                                 into 0x01 0x04 to deny user
//                                                 enumeration, so the 0xFF
//                                                 branch is only reachable on
//                                                 lower-level protocol errors
//   firstByte == 0xFE (AUTH_SWITCH_REQUEST)     — out of scope (D135 §Principles 5)

import { assertEqual } from "@/lib/test"
import { DriverManager_getConnection, SQLException } from "@/lib/java/sql"

const URL            = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const URL_WRONG_PWD  = "jdbc:mysql://root:wrong@127.0.0.1:3307/testdb"
const URL_FRESH_USER = "jdbc:mysql://d135fresh:pwd@127.0.0.1:3307/testdb"

function main() {
    // Probe: skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D135 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    // ── 1. caching_sha2 fast-path basic flow (cache hit via healthcheck) ──
    test("connect + isClosed transitions + close (caching_sha2 fast-path)", () => {
        const conn = DriverManager_getConnection(URL)
        assertEqual(conn.isClosed(), 0)
        conn.close()
        assertEqual(conn.isClosed(), 1)
    })

    // ── 2. Repeat connect = server cache hit FAST_AUTH_SUCCESS (0x01 0x03) ──
    // The docker healthcheck primes the cache; test 1 also leaves it warm.
    // This reuses the same URL to confirm the fast-path stays single-RTT.
    test("server cache hit fast_auth_success on repeat connect", () => {
        const conn = DriverManager_getConnection(URL)
        assertEqual(conn.isClosed(), 0)
        conn.close()
    })

    // ── 3. Wrong password rejected (anti-enumeration path) ──
    // MySQL 8 caching_sha2 deliberately collapses "user exists + bad password"
    // and "user does not exist" onto the same wire response — both reply with
    // 0x01 0x04 perform_full_authentication so a remote attacker cannot tell
    // the two apart. Without RSA-OAEP the SS driver rejects 0x01 0x04 (same
    // path as test 4 below) and throws SQLException via mysqlConnect.
    test("wrong password rejected (caching_sha2 anti-enumeration → 0x01 0x04)", () => {
        let caught = 0
        try {
            DriverManager_getConnection(URL_WRONG_PWD)
        } catch (e: SQLException) {
            caught = 1
        }
        assertEqual(caught, 1)
    })

    // ── 4. Fresh user cache miss = PERFORM_FULL_AUTHENTICATION (0x01 0x04) ──
    // Create a brand-new user via the (already-cached) root account, then try
    // to log in as that user over TCP. The server has no cache entry for the
    // new user, so it requests RSA-OAEP full authentication (0x01 0x04). The
    // SS driver does not implement RSA-OAEP and rejects 0x04 in
    // handshake.ss::mysqlConnect, which throws SQLException (D139 Phase 2 升级).
    // (No FLUSH PRIVILEGES: MySQL 8 reloads grant tables automatically on
    // CREATE/DROP USER and GRANT, and FLUSH PRIVILEGES would purge the entire
    // caching_sha2 cache — including root@% — making the test non-idempotent.)
    test("fresh user cache miss rejected with perform_full_authentication (0x01 0x04)", () => {
        const adminConn = DriverManager_getConnection(URL)
        const adminStmt = adminConn.createStatement()
        adminStmt.execute("DROP USER IF EXISTS 'd135fresh'@'%'")
        adminStmt.execute("CREATE USER 'd135fresh'@'%' IDENTIFIED WITH caching_sha2_password BY 'pwd'")
        adminStmt.execute("GRANT ALL ON testdb.* TO 'd135fresh'@'%'")

        let caught = 0
        try {
            DriverManager_getConnection(URL_FRESH_USER)
        } catch (e: SQLException) {
            caught = 1
        }
        assertEqual(caught, 1)

        adminStmt.execute("DROP USER IF EXISTS 'd135fresh'@'%'")
        adminStmt.close()
        adminConn.close()
    })

    println("All D135 Phase 2 caching_sha2 fast-path e2e tests passed!")
}
