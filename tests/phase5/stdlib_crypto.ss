// Test: Crypto standard library module (D047)

import { Crypto } from "@/lib/crypto"

function main() {
    // ── SHA-1 test vectors (FIPS 180-4) ──────────────────────
    const sha1Empty = Crypto.sha1("")
    if (sha1Empty != "da39a3ee5e6b4b0d3255bfef95601890afd80709") { exit(1) }

    const sha1Abc = Crypto.sha1("abc")
    if (sha1Abc != "a9993e364706816aba3e25717850c26c9cd0d89d") { exit(2) }

    const sha1Long = Crypto.sha1("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
    if (sha1Long != "84983e441c3bd26ebaae4aa1f95129e5e54670f1") { exit(3) }

    // ── SHA-256 via Crypto (verify matches sha256.ss) ────────
    const sha256Empty = Crypto.sha256("")
    if (sha256Empty != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") { exit(4) }

    const sha256Abc = Crypto.sha256("abc")
    if (sha256Abc != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") { exit(5) }

    // ── HMAC-SHA256 (RFC 4231 Test Case 2) ───────────────────
    const hmac256 = Crypto.hmacSHA256("Jefe", "what do ya want for nothing?")
    if (hmac256 != "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843") { exit(6) }

    // ── HMAC-SHA1 (RFC 2202 Test Case 2) ─────────────────────
    const hmac1 = Crypto.hmacSHA1("Jefe", "what do ya want for nothing?")
    if (hmac1 != "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79") { exit(7) }

    // ── HMAC with empty message ──────────────────────────────
    const hmac256empty = Crypto.hmacSHA256("key", "")
    if (hmac256empty != "5d5d139563c95b5967b9bd9a8c9b233a9dedb45072794cd232dc1b74832607d0") { exit(8) }

    // ── hexToBytes / bytesToHex ──────────────────────────────
    const hex = "48656c6c6f"
    const bytes = Crypto.hexToBytes(hex)
    if (bytes != "Hello") { exit(9) }

    const backToHex = Crypto.bytesToHex("Hello")
    if (backToHex != "48656c6c6f") { exit(10) }

    const roundtrip = Crypto.bytesToHex(Crypto.hexToBytes("deadbeef"))
    if (roundtrip != "deadbeef") { exit(11) }

    // ── timingSafeEqual ──────────────────────────────────────
    if (Crypto.timingSafeEqual("abc", "abc") != 1) { exit(12) }
    if (Crypto.timingSafeEqual("abc", "abd") != 0) { exit(13) }
    if (Crypto.timingSafeEqual("abc", "abcd") != 0) { exit(14) }
    if (Crypto.timingSafeEqual("", "") != 1) { exit(15) }

    println("All crypto tests passed!")
}
