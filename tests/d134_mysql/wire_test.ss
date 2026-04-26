// D134 Phase 2 — lib/binary unit tests + lib/crypto SHA-1 reuse sanity check.
// No network — tests pure byte-calculation paths only. Wire packet read/write
// (lib/com/mysql/wire.ss) requires a real MySQL socket and is exercised in
// Phase 3 handshake_test.ss against docker-compose mysql:8.

import { assertEqual, assertTrue } from "@/lib/test"
import { byteToInt, intToBytes, readLengthEncodedInt, lengthEncodedIntSize, readLengthEncodedString, writeLengthEncodedInt } from "@/lib/binary"
import { Crypto } from "@/lib/crypto"

function main() {
    // ── byteToInt: little-endian decode ──────────────────────────
    test("byteToInt 1-byte ASCII", () => {
        assertEqual(byteToInt("ABC", 0, 1), 65)
        assertEqual(byteToInt("ABC", 1, 1), 66)
        assertEqual(byteToInt("ABC", 2, 1), 67)
    })

    test("byteToInt 2-byte LE", () => {
        // "AB" = [0x41, 0x42] LE → 0x4241 = 16961
        assertEqual(byteToInt("AB", 0, 2), 16961)
    })

    test("byteToInt 3-byte LE no-zero", () => {
        // [0xCD, 0xAB, 0x12] → 0x12ABCD = 1223629
        const buf = fromCharCode(0xCD) + fromCharCode(0xAB) + fromCharCode(0x12)
        assertEqual(byteToInt(buf, 0, 3), 1223629)
    })

    test("byteToInt 4-byte LE no-zero", () => {
        // [0x78, 0x56, 0x34, 0x12] → 0x12345678 = 305419896
        const buf = fromCharCode(0x78) + fromCharCode(0x56) + fromCharCode(0x34) + fromCharCode(0x12)
        assertEqual(byteToInt(buf, 0, 4), 305419896)
    })

    test("byteToInt with offset", () => {
        // "XABYZ" — read 2 bytes at offset 1 → "AB" = 16961
        assertEqual(byteToInt("XABYZ", 1, 2), 16961)
    })

    // ── intToBytes: 1-byte (no NULL truncation) ──────────────────
    test("intToBytes 1-byte non-zero", () => {
        // intToBytes(65, 1) → "A" (length 1)
        const r = intToBytes(65, 1)
        assertEqual(r.length(), 1)
        assertEqual(charCodeAt(r, 0), 65)
    })

    test("intToBytes 2-byte no-zero", () => {
        // intToBytes(0xABCD, 2) → "\xCD\xAB" — both bytes non-zero
        const r = intToBytes(0xABCD, 2)
        assertEqual(r.length(), 2)
        assertEqual(charCodeAt(r, 0), 0xCD)
        assertEqual(charCodeAt(r, 1), 0xAB)
    })

    // ── readLengthEncodedInt: < 0xFB single byte ─────────────────
    test("readLengthEncodedInt 1-byte values", () => {
        assertEqual(readLengthEncodedInt(fromCharCode(5), 0), 5)
        assertEqual(readLengthEncodedInt(fromCharCode(0xFA), 0), 0xFA)
        assertEqual(readLengthEncodedInt(fromCharCode(100), 0), 100)
    })

    // ── readLengthEncodedInt: 0xFB NULL marker ───────────────────
    test("readLengthEncodedInt NULL marker (0xFB) returns -1", () => {
        assertEqual(readLengthEncodedInt(fromCharCode(0xFB), 0), -1)
    })

    // ── readLengthEncodedInt: 0xFC marker + 2-byte LE ────────────
    test("readLengthEncodedInt 0xFC marker + 2-byte LE", () => {
        // [0xFC, 0xCD, 0xAB] → 0xABCD = 43981 (data bytes nonzero so concat survives)
        const buf = fromCharCode(0xFC) + fromCharCode(0xCD) + fromCharCode(0xAB)
        assertEqual(readLengthEncodedInt(buf, 0), 43981)
    })

    // ── readLengthEncodedInt: 0xFD marker + 3-byte LE ────────────
    test("readLengthEncodedInt 0xFD marker + 3-byte LE", () => {
        // [0xFD, 0xCD, 0xAB, 0x12] → 0x12ABCD = 1223629
        const buf = fromCharCode(0xFD) + fromCharCode(0xCD) + fromCharCode(0xAB) + fromCharCode(0x12)
        assertEqual(readLengthEncodedInt(buf, 0), 1223629)
    })

    // ── lengthEncodedIntSize ─────────────────────────────────────
    test("lengthEncodedIntSize per marker", () => {
        assertEqual(lengthEncodedIntSize(fromCharCode(5), 0), 1)
        assertEqual(lengthEncodedIntSize(fromCharCode(0xFA), 0), 1)
        assertEqual(lengthEncodedIntSize(fromCharCode(0xFB), 0), 1)
        // For 0xFC/FD/FE, content bytes don't affect size — but size lookup
        // only reads first byte so suffix can be empty.
        assertEqual(lengthEncodedIntSize(fromCharCode(0xFC), 0), 3)
        assertEqual(lengthEncodedIntSize(fromCharCode(0xFD), 0), 4)
        assertEqual(lengthEncodedIntSize(fromCharCode(0xFE), 0), 9)
    })

    // ── readLengthEncodedString: 1-byte length prefix + ASCII ────
    test("readLengthEncodedString 1-byte len + ASCII", () => {
        // [0x03, 'a', 'b', 'c'] → "abc"
        const buf = fromCharCode(3) + "abc"
        assertEqual(readLengthEncodedString(buf, 0), "abc")
    })

    test("readLengthEncodedString empty (len = 0)", () => {
        // [0x00, ...] — length 0 → empty string
        assertEqual(readLengthEncodedString(fromCharCode(0), 0), "")
    })

    // ── writeLengthEncodedInt: 1-byte values (no NULL issue) ─────
    test("writeLengthEncodedInt 1-byte values", () => {
        // 0x05 < 0xFB → single byte 0x05
        const r = writeLengthEncodedInt(5)
        assertEqual(r.length(), 1)
        assertEqual(charCodeAt(r, 0), 5)
    })

    test("writeLengthEncodedInt 0xFA boundary", () => {
        // 0xFA < 0xFB → single byte 0xFA
        const r = writeLengthEncodedInt(0xFA)
        assertEqual(r.length(), 1)
        assertEqual(charCodeAt(r, 0), 0xFA)
    })

    // ── Crypto.sha1 reuse sanity (FIPS 180-4 vectors already covered
    //     by tests/phase5/stdlib_crypto.ss; this asserts D134 Phase 2 has
    //     SHA-1 dependency wired through lib/crypto, not lib/sha1) ──────
    test("Crypto.sha1 FIPS 180-4 vectors reachable", () => {
        assertEqual(Crypto.sha1(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        assertEqual(Crypto.sha1("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
    })

    println("All D134 Phase 2 binary + crypto tests passed!")
}
