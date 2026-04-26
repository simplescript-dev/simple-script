// MySQL handshake v10 + caching_sha2_password fast-path scramble — D135 Phase 1.
// Supersedes D134 Phase 3 mysql_native_password (MySQL 5.x era plugin); MySQL 8+
// default is caching_sha2_password and the 32-byte SHA-256 chained scramble is
// sent unconditionally in HandshakeResponse41 — single round-trip true fast-path,
// no AuthSwitchRequest detour. Server fast-path reply 0x01 0x03 fast_auth_success
// is followed by a normal OK packet on cache hit; 0x01 0x04
// perform_full_authentication (cache miss → RSA-OAEP) is rejected (out of scope).
// See D135 §A.1 / §A.2 / §A.3.
//
// API deviates from D134 §3 Phase 3 literal spec (`buildHandshakeResponse41 → string`):
// the response payload contains many embedded 0x00 bytes (capability flags with
// zero high bits, max-packet trailing zero, 23-byte filler, null-terminators) and
// ss_string_concat is strlen-based — a string-returning builder would silently
// truncate. sendHandshakeResponse41 stream-writes to fd directly, sharing the
// byte-by-byte tcpWriteBytes pattern wire.ss writePacket already uses for the
// 4-byte header. Decision recorded in D134 §A.3 / §附录 B Phase 3.
//
// Scramble representation: HandshakeV10.scrambleHex stores the 20-byte server
// nonce as 40 hex chars (ASCII, no embedded NULL) so the value survives string
// concat and feeds sha256flex's dataHex parameter for chained SHA-256.

import { byteToInt } from "@/lib/binary"
import { readPacket, writePacket, MysqlPacket } from "@/lib/com/mysql/wire"
import { Crypto } from "@/lib/crypto"
import { hexByte } from "@/lib/sha256"

const CLIENT_LONG_PASSWORD     = 1
const CLIENT_LONG_FLAG         = 4
const CLIENT_CONNECT_WITH_DB   = 8
const CLIENT_PROTOCOL_41       = 0x200
const CLIENT_TRANSACTIONS      = 0x2000
const CLIENT_SECURE_CONNECTION = 0x8000
const CLIENT_MULTI_RESULTS     = 0x20000
const CLIENT_PLUGIN_AUTH       = 0x80000

// caching_sha2_password auth response packet first/second byte (D135 §A.3)
const AUTH_OK                       = 0x00
const AUTH_MORE_DATA                = 0x01
const FAST_AUTH_SUCCESS             = 0x03
const PERFORM_FULL_AUTHENTICATION   = 0x04
const AUTH_SWITCH_REQUEST           = 0xFE
const ERR_PACKET                    = 0xFF
const CACHING_SHA2_REPLY_LEN        = 32

class HandshakeV10 {
    protoVer: int
    serverVer: string
    connId: int
    scrambleHex: string
    capabilityFlags: int
    charset: int
    statusFlags: int
    authPlugin: string
}

// Parses a handshake v10 packet payload. Layout (per MySQL Native Protocol):
//   1   protocol version (= 10)
//   N   server version (null-terminated string)
//   4   connection id (LE)
//   8   auth-plugin-data part 1 (scramble1)
//   1   filler (0x00)
//   2   capability flags lower (LE)
//   1   character set
//   2   status flags (LE)
//   2   capability flags upper (LE)
//   1   auth-plugin-data length
//   10  reserved (zeros)
//   N   auth-plugin-data part 2 (scramble2 + trailing NULL)
//   N   auth plugin name (null-terminated)
function parseHandshakeV10(payload: string): HandshakeV10 {
    const h = new HandshakeV10(0, "", 0, "", 0, 0, 0, "")
    h.protoVer = charCodeAt(payload, 0)

    let off = 1
    let svEnd = off
    while (charCodeAt(payload, svEnd) != 0) { svEnd = svEnd + 1 }
    let sv = ""
    let i = off
    while (i < svEnd) {
        sv = sv + fromCharCode(charCodeAt(payload, i))
        i = i + 1
    }
    h.serverVer = sv
    off = svEnd + 1

    h.connId = byteToInt(payload, off, 4)
    off = off + 4

    let scrHex = ""
    i = 0
    while (i < 8) {
        scrHex = scrHex + hexByte(charCodeAt(payload, off + i))
        i = i + 1
    }
    off = off + 8 + 1

    const capLow = byteToInt(payload, off, 2)
    off = off + 2
    h.charset = charCodeAt(payload, off)
    off = off + 1
    h.statusFlags = byteToInt(payload, off, 2)
    off = off + 2
    const capHigh = byteToInt(payload, off, 2)
    off = off + 2
    h.capabilityFlags = capLow | (capHigh << 16)

    const authDataLen = charCodeAt(payload, off)
    off = off + 1
    off = off + 10

    // scramble2 = max(12, authDataLen - 8) bytes data + 1-byte NULL terminator.
    let scramble2Bytes = 12
    if (authDataLen > 21) { scramble2Bytes = authDataLen - 8 - 1 }
    i = 0
    while (i < scramble2Bytes) {
        scrHex = scrHex + hexByte(charCodeAt(payload, off + i))
        i = i + 1
    }
    h.scrambleHex = scrHex
    off = off + scramble2Bytes + 1

    let apEnd = off
    while (charCodeAt(payload, apEnd) != 0) { apEnd = apEnd + 1 }
    let ap = ""
    i = off
    while (i < apEnd) {
        ap = ap + fromCharCode(charCodeAt(payload, i))
        i = i + 1
    }
    h.authPlugin = ap

    return h
}

// SHA256(pwd) XOR SHA256(SHA256(SHA256(pwd)) ‖ nonce). Returns 64 hex chars
// (32 bytes; caller decodes each pair back to a byte at write-time).
//
// Note: stage3 = SHA256(stage2 ‖ nonce) — stage2 in front, opposite of
// mysql_native_password's SHA1(nonce ‖ stage2). Source:
// MySQL auth/sha2_password_common.cc generate_auth_string_sha256().
//
// All SHA-256 calls go through sha256flex's dataHex parameter so the binary
// intermediates (stage1, stage2 — each 32 bytes that may contain 0x00) bypass
// strlen on byte buffers.
function cachingSha2Scramble(password: string, scrambleHex: string): string {
    const stage1Hex = Crypto.sha256(password)
    const stage2Hex = sha256flex("", stage1Hex, "", "", 0)
    const stage3Hex = sha256flex("", stage2Hex + scrambleHex, "", "", 0)
    let replyHex = ""
    let i = 0
    while (i < CACHING_SHA2_REPLY_LEN) {
        const b1 = cryptoHexDigit(stage1Hex.charAt(i * 2)) * 16 + cryptoHexDigit(stage1Hex.charAt(i * 2 + 1))
        const b3 = cryptoHexDigit(stage3Hex.charAt(i * 2)) * 16 + cryptoHexDigit(stage3Hex.charAt(i * 2 + 1))
        replyHex = replyHex + hexByte(b1 ^ b3)
        i = i + 1
    }
    return replyHex
}

// Stream-writes a HandshakeResponse41 packet to fd (seqId = 1; server's handshake
// arrived as seq 0). Layout:
//   4   capability flags (LE)
//   4   max packet size (LE; 0xFFFFFF = 16MB - 1)
//   1   character set
//   23  filler (zeros)
//   N   username (null-terminated)
//   1   length of auth-response (= 32 for caching_sha2_password)
//   32  auth-response (SHA-256 chained scramble bytes)
//   N   database (null-terminated, only if CLIENT_CONNECT_WITH_DB)
//   N   "caching_sha2_password" (null-terminated)
function sendHandshakeResponse41(fd: int, capFlags: int, charset: int, username: string, replyHex: string, database: string): int {
    const usernameLen = username.length()
    const databaseLen = database.length()
    const pluginName = "caching_sha2_password"
    const pluginLen = pluginName.length()
    let dbBlock = 0
    if (databaseLen > 0) { dbBlock = databaseLen + 1 }
    const payloadLen = 4 + 4 + 1 + 23 + usernameLen + 1 + 1 + CACHING_SHA2_REPLY_LEN + dbBlock + pluginLen + 1

    tcpWriteBytes(fd, fromCharCode(payloadLen & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode((payloadLen >>> 8) & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode((payloadLen >>> 16) & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode(1), 1)

    let i = 0
    while (i < 4) {
        tcpWriteBytes(fd, fromCharCode((capFlags >>> (i * 8)) & 0xFF), 1)
        i = i + 1
    }
    tcpWriteBytes(fd, fromCharCode(0xFF), 1)
    tcpWriteBytes(fd, fromCharCode(0xFF), 1)
    tcpWriteBytes(fd, fromCharCode(0xFF), 1)
    tcpWriteBytes(fd, fromCharCode(0), 1)
    tcpWriteBytes(fd, fromCharCode(charset & 0xFF), 1)

    i = 0
    while (i < 23) {
        tcpWriteBytes(fd, fromCharCode(0), 1)
        i = i + 1
    }
    if (usernameLen > 0) {
        tcpWriteBytes(fd, username, usernameLen)
    }
    tcpWriteBytes(fd, fromCharCode(0), 1)

    tcpWriteBytes(fd, fromCharCode(CACHING_SHA2_REPLY_LEN), 1)
    i = 0
    while (i < CACHING_SHA2_REPLY_LEN) {
        const b = cryptoHexDigit(replyHex.charAt(i * 2)) * 16 + cryptoHexDigit(replyHex.charAt(i * 2 + 1))
        tcpWriteBytes(fd, fromCharCode(b), 1)
        i = i + 1
    }

    if (databaseLen > 0) {
        tcpWriteBytes(fd, database, databaseLen)
        tcpWriteBytes(fd, fromCharCode(0), 1)
    }
    tcpWriteBytes(fd, pluginName, pluginLen)
    tcpWriteBytes(fd, fromCharCode(0), 1)

    return 4 + payloadLen
}

// Full mysqlConnect flow:
//   tcpConnect → readPacket(handshake) → parseHandshakeV10 →
//   cachingSha2Scramble → sendHandshakeResponse41 → readPacket(auth response)
// Auth response branching (D135 §A.3):
//   firstByte 0x00 → OK directly (rare)
//   firstByte 0x01 secondByte 0x03 → fast_auth_success → readPacket → expect OK
//   firstByte 0x01 secondByte 0x04 → perform_full_authentication → ERR (RSA-OAEP scope-out)
//   firstByte 0xFE → AuthSwitchRequest → ERR (caching_sha2 fast-path direct mode)
//   firstByte 0xFF → ERR packet (wrong password / user not found)
// Returns the authenticated socket fd, or -1 on any failure (caller must check).
// Driver-layer Connection state (autoCommit / closed) is owned by
// lib/com/mysql/jdbc.ss class MysqlConnection : Connection — handshake.ss owns
// only the auth protocol, not connection lifecycle.
// Diagnostics emitted via println.
function mysqlConnect(host: string, port: int, username: string, password: string, database: string): int {
    let errMsg = ""
    let fd = tcpConnect(host, port)
    if (fd < 0) { errMsg = "tcpConnect failed" }

    let h: HandshakeV10 = new HandshakeV10(0, "", 0, "", 0, 0, 0, "")
    if (errMsg == "") {
        const handshakePkt = readPacket(fd)
        if (handshakePkt.payloadLen <= 0) {
            errMsg = "handshake read failed"
        } else {
            h = parseHandshakeV10(handshakePkt.payload)
        }
    }

    if (errMsg == "") {
        const replyHex = cachingSha2Scramble(password, h.scrambleHex)
        let capFlags = CLIENT_LONG_PASSWORD | CLIENT_LONG_FLAG | CLIENT_PROTOCOL_41 | CLIENT_TRANSACTIONS | CLIENT_SECURE_CONNECTION | CLIENT_MULTI_RESULTS | CLIENT_PLUGIN_AUTH
        if (database.length() > 0) {
            capFlags = capFlags | CLIENT_CONNECT_WITH_DB
        }
        sendHandshakeResponse41(fd, capFlags, h.charset, username, replyHex, database)

        const authPkt = readPacket(fd)
        if (authPkt.payloadLen <= 0) {
            errMsg = "auth response read failed"
        } else {
            const firstByte = charCodeAt(authPkt.payload, 0)
            if (firstByte == AUTH_OK) {
                // OK packet directly — server accepted without AuthMoreData (rare but legal)
            } else if (firstByte == AUTH_MORE_DATA) {
                const secondByte = charCodeAt(authPkt.payload, 1)
                if (secondByte == FAST_AUTH_SUCCESS) {
                    // server cache hit; expect OK packet next
                    const okPkt = readPacket(fd)
                    if (okPkt.payloadLen <= 0) {
                        errMsg = "post-fast_auth_success OK read failed"
                    } else {
                        const okFirst = charCodeAt(okPkt.payload, 0)
                        if (okFirst == ERR_PACKET) { errMsg = "auth failed (ERR after fast_auth_success)" }
                        if (okFirst != AUTH_OK && okFirst != ERR_PACKET) { errMsg = "unexpected post-fast_auth_success byte" }
                    }
                } else if (secondByte == PERFORM_FULL_AUTHENTICATION) {
                    errMsg = "full auth not supported (server cache miss; RSA-OAEP scope-out)"
                } else {
                    errMsg = "unexpected AuthMoreData status byte"
                }
            } else if (firstByte == AUTH_SWITCH_REQUEST) {
                errMsg = "server requested AuthSwitch (caching_sha2 fast-path direct mode)"
            } else if (firstByte == ERR_PACKET) {
                errMsg = "auth failed (ERR packet)"
            } else {
                errMsg = "unexpected auth response first byte"
            }
        }
    }

    if (errMsg != "") {
        println("MySQL: " + errMsg)
        return -1
    }
    return fd
}
