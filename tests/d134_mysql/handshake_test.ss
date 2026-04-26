// D134 Phase 3 — handshake unit tests.
// mysqlNativePasswordScramble: 4 reference vectors computed via Python hashlib
//   SHA1(pwd) ⊕ SHA1(salt || SHA1(SHA1(pwd))).
// parseHandshakeV10: minimal MySQL 8 handshake fixture written via
//   bash -c "printf '\\x..'" (sh built-in printf doesn't expand \\x in single
//   quotes; bash does), readFile is binary-safe via charCodeAt direct GEP+load.
// mysqlConnect / sendHandshakeResponse41: real socket flow — Phase 6 docker e2e.

import { assertEqual, assertTrue } from "@/lib/test"
import { parseHandshakeV10, mysqlNativePasswordScramble, HandshakeV10, MysqlConnection } from "@/lib/com/mysql/handshake"

function main() {
    // ── mysqlNativePasswordScramble reference vectors ──────────────
    test("scramble vec1: pwd='abc' salt=20×0x41", () => {
        const salt = "4141414141414141414141414141414141414141"
        assertEqual(mysqlNativePasswordScramble("abc", salt),
                    "eece5cb02aeaa29e61bdf883fb14761f4b4b10ef")
    })

    test("scramble vec2: pwd='secret' salt='ABCDEFGHIJKLMNOPQRST'", () => {
        const salt = "4142434445464748494a4b4c4d4e4f5051525354"
        assertEqual(mysqlNativePasswordScramble("secret", salt),
                    "28441590674285e7d03cae7af237504797f70e91")
    })

    test("scramble vec3: empty pwd salt=20×0x41", () => {
        const salt = "4141414141414141414141414141414141414141"
        assertEqual(mysqlNativePasswordScramble("", salt),
                    "41843480c89095e82f397bbe33ac92c6b7b5c91f")
    })

    test("scramble vec4: pwd='password' salt='12345678901234567890'", () => {
        const salt = "3132333435363738393031323334353637383930"
        assertEqual(mysqlNativePasswordScramble("password", salt),
                    "1957dce2724282e018f40d905824cb6361f88d41")
    })

    // ── parseHandshakeV10 fixture ──────────────────────────────────
    // Layout (74 bytes): \x0a + '8.0.32' + \x00 + connId(LE 0x12345678) +
    //   8×'A' + filler + capLow(0x0001) + charset(0x21) + status(0x0002) +
    //   capHigh(0x0008) + authDataLen(0x15) + 10×\x00 + 12×'B' + \x00 +
    //   'mysql_native_password' + \x00.
    test("parseHandshakeV10 minimal MySQL 8 fixture", () => {
        const cmd = "bash -c \"printf '\\x0a8.0.32\\x00\\x78\\x56\\x34\\x12AAAAAAAA\\x00\\x01\\x00\\x21\\x02\\x00\\x08\\x00\\x15\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00BBBBBBBBBBBB\\x00mysql_native_password\\x00' > /tmp/d134_hs_fixture.bin\""
        system(cmd)
        const buf = readFile("/tmp/d134_hs_fixture.bin")
        const h = parseHandshakeV10(buf)
        assertEqual(h.protoVer, 10)
        assertEqual(h.serverVer, "8.0.32")
        assertEqual(h.connId, 0x12345678)
        assertEqual(h.scrambleHex, "4141414141414141424242424242424242424242")
        assertEqual(h.charset, 33)
        assertEqual(h.statusFlags, 2)
        // capLow 0x0001 + capHigh 0x0008 → 0x0001 | (0x0008 << 16) = 0x80001
        assertEqual(h.capabilityFlags, 1 | (8 << 16))
        assertEqual(h.authPlugin, "mysql_native_password")
    })

    // ── class default field values ─────────────────────────────────
    test("HandshakeV10 positional constructor", () => {
        const h = new HandshakeV10(10, "8.0.32", 12345, "abcd", 100, 33, 2, "mysql_native_password")
        assertEqual(h.protoVer, 10)
        assertEqual(h.serverVer, "8.0.32")
        assertEqual(h.connId, 12345)
        assertEqual(h.scrambleHex, "abcd")
        assertEqual(h.capabilityFlags, 100)
        assertEqual(h.charset, 33)
        assertEqual(h.statusFlags, 2)
        assertEqual(h.authPlugin, "mysql_native_password")
    })

    test("MysqlConnection positional constructor", () => {
        const c = new MysqlConnection(-1, 1, 0)
        assertEqual(c.fd, -1)
        assertEqual(c.autoCommit, 1)
        assertEqual(c.closed, 0)
    })

    println("All D134 Phase 3 handshake tests passed!")
}
