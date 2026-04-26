// D135 Phase 1 — handshake unit tests (supersedes D134 Phase 3 mysql_native vec).
// cachingSha2Scramble: 4 reference vectors computed via Python hashlib SHA-256
//   SHA256(pwd) ⊕ SHA256(SHA256(SHA256(pwd)) ‖ nonce) — note stage2‖nonce order,
//   opposite of mysql_native_password's nonce‖stage2; source MySQL
//   auth/sha2_password_common.cc generate_auth_string_sha256().
// parseHandshakeV10: minimal MySQL 8 handshake fixture written via
//   bash -c "printf '\\x..'" (sh built-in printf doesn't expand \\x in single
//   quotes; bash does), readFile is binary-safe via charCodeAt direct GEP+load.
// mysqlConnect / sendHandshakeResponse41: real socket flow — D135 Phase 2 docker e2e.

import { assertEqual, assertTrue } from "@/lib/test"
import { parseHandshakeV10, cachingSha2Scramble, HandshakeV10 } from "@/lib/com/mysql/handshake"

function main() {
    // ── cachingSha2Scramble reference vectors (Python hashlib SHA-256) ──
    test("scramble vec1: pwd='abc' salt=20×0x41", () => {
        const salt = "4141414141414141414141414141414141414141"
        assertEqual(cachingSha2Scramble("abc", salt),
                    "b3f41d870fa64cd50479c36da01d084c315fbacbc281f1a705ccfc7180483d4f")
    })

    test("scramble vec2: pwd='secret' salt='ABCDEFGHIJKLMNOPQRST'", () => {
        const salt = "4142434445464748494a4b4c4d4e4f5051525354"
        assertEqual(cachingSha2Scramble("secret", salt),
                    "d721e183c1f036a196c1389201b8d53f38064a16f1d0923683ab886763152d75")
    })

    test("scramble vec3: empty pwd salt=20×0x41", () => {
        const salt = "4141414141414141414141414141414141414141"
        assertEqual(cachingSha2Scramble("", salt),
                    "4a930e890070fdf49902f47194ef86b83038845d01c87f774c314a9b51d033d6")
    })

    test("scramble vec4: pwd='password' salt='12345678901234567890'", () => {
        const salt = "3132333435363738393031323334353637383930"
        assertEqual(cachingSha2Scramble("password", salt),
                    "718d80fb92b693f7ee1fcad95bfe7a2be1f332ac2c3ec6cdc85893b65b240650")
    })

    // ── parseHandshakeV10 fixture ──────────────────────────────────
    // Layout (74 bytes): \x0a + '8.0.32' + \x00 + connId(LE 0x12345678) +
    //   8×'A' + filler + capLow(0x0001) + charset(0x21) + status(0x0002) +
    //   capHigh(0x0008) + authDataLen(0x15) + 10×\x00 + 12×'B' + \x00 +
    //   'caching_sha2_password' + \x00.
    test("parseHandshakeV10 minimal MySQL 8 fixture", () => {
        const cmd = "bash -c \"printf '\\x0a8.0.32\\x00\\x78\\x56\\x34\\x12AAAAAAAA\\x00\\x01\\x00\\x21\\x02\\x00\\x08\\x00\\x15\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00BBBBBBBBBBBB\\x00caching_sha2_password\\x00' > /tmp/d135_hs_fixture.bin\""
        system(cmd)
        const buf = readFile("/tmp/d135_hs_fixture.bin")
        const h = parseHandshakeV10(buf)
        assertEqual(h.protoVer, 10)
        assertEqual(h.serverVer, "8.0.32")
        assertEqual(h.connId, 0x12345678)
        assertEqual(h.scrambleHex, "4141414141414141424242424242424242424242")
        assertEqual(h.charset, 33)
        assertEqual(h.statusFlags, 2)
        // capLow 0x0001 + capHigh 0x0008 → 0x0001 | (0x0008 << 16) = 0x80001
        assertEqual(h.capabilityFlags, 1 | (8 << 16))
        assertEqual(h.authPlugin, "caching_sha2_password")
    })

    // ── class default field values ─────────────────────────────────
    test("HandshakeV10 positional constructor", () => {
        const h = new HandshakeV10(10, "8.0.32", 12345, "abcd", 100, 33, 2, "caching_sha2_password")
        assertEqual(h.protoVer, 10)
        assertEqual(h.serverVer, "8.0.32")
        assertEqual(h.connId, 12345)
        assertEqual(h.scrambleHex, "abcd")
        assertEqual(h.capabilityFlags, 100)
        assertEqual(h.charset, 33)
        assertEqual(h.statusFlags, 2)
        assertEqual(h.authPlugin, "caching_sha2_password")
    })

    println("All D135 Phase 1 handshake tests passed!")
}
