// SimpleScript Crypto Library — SHA-1, SHA-256, HMAC, hex utilities
//
// Usage:
//   import { Crypto } from "@/lib/crypto"
//
//   Crypto.sha1("abc")                          // SHA-1 hash (hex)
//   Crypto.sha256("abc")                        // SHA-256 hash (hex)
//   Crypto.hmacSHA256("key", "message")         // HMAC-SHA256 (hex)
//   Crypto.hmacSHA1("key", "message")           // HMAC-SHA1 (hex)
//   Crypto.hexToBytes("48656c6c6f")             // hex to byte string
//   Crypto.bytesToHex("Hello")                  // byte string to hex
//   Crypto.timingSafeEqual(a, b)                // constant-time compare

import { hexByte, hexWord } from "@/lib/sha256"

class Crypto {}

// ── SHA-1 helpers ────────────────────────────────────────────

function sha1Rotl(x: int, n: int): int {
    return (x << n) | (x >>> (32 - n))
}

function sha1GetF(round: int, b: int, c: int, d: int): int {
    if (round < 20) { return (b & c) | ((~b) & d) }
    if (round < 40) { return b ^ c ^ d }
    if (round < 60) { return (b & c) | (b & d) | (c & d) }
    return b ^ c ^ d
}

function sha1GetK(round: int): int {
    if (round < 20) { return 1518500249 }
    if (round < 40) { return 1859775393 }
    if (round < 60) { return -1894007588 }
    return -899497514
}

// ── Hex decode helper ────────────────────────────────────────

function cryptoHexDigit(c: string): int {
    if (c >= "0" && c <= "9") { return c.charCodeAt(0) - 48 }
    if (c >= "a" && c <= "f") { return c.charCodeAt(0) - 87 }
    if (c >= "A" && c <= "F") { return c.charCodeAt(0) - 55 }
    return 0
}

// ── SHA-1 flex hash ──────────────────────────────────────────
// Standalone:  sha1flex(data, "", "", "", 0)
// HMAC inner:  sha1flex(message, "", key, "", 0x36)
// HMAC outer:  sha1flex("", innerHex, key, "", 0x5c)
// Long-key:    sha1flex(msg, "", "", keyHashHex, padByte)

function sha1flex(data: string, dataHex: string, prefix: string, prefixHex: string, prefixXor: int): string {
    let h0 = 1732584193
    let h1 = -271733879
    let h2 = -1732584194
    let h3 = 271733878
    let h4 = -1009589776

    const prefixStrLen = prefix.length()
    const prefixHexLen = prefixHex.length()
    let prefixLen = prefixStrLen
    if (prefixHexLen > 0) { prefixLen = prefixHexLen / 2 }
    let padPrefixLen = 0
    if (prefixLen > 0 || prefixXor > 0) { padPrefixLen = 64 }

    const dataHexLen = dataHex.length()
    let msgLen = data.length()
    if (dataHexLen > 0) { msgLen = dataHexLen / 2 }

    const dataLen = padPrefixLen + msgLen
    const bitLen = dataLen * 8

    let padLen = dataLen + 1
    while (padLen % 64 != 56) { padLen = padLen + 1 }
    padLen = padLen + 8

    let blockStart = 0
    while (blockStart < padLen) {
        let w0 = 0
        let w1 = 0
        let w2 = 0
        let w3 = 0
        let w4 = 0
        let w5 = 0
        let w6 = 0
        let w7 = 0
        let w8 = 0
        let w9 = 0
        let w10 = 0
        let w11 = 0
        let w12 = 0
        let w13 = 0
        let w14 = 0
        let w15 = 0

        let wi = 0
        while (wi < 16) {
            let word = 0
            let bi = 0
            while (bi < 4) {
                const byteIdx = blockStart + wi * 4 + bi
                let byteVal = 0
                if (byteIdx < padPrefixLen) {
                    let kb = 0
                    if (byteIdx < prefixLen) {
                        if (prefixHexLen > 0) {
                            const hoff = byteIdx * 2
                            kb = cryptoHexDigit(prefixHex.charAt(hoff)) * 16 + cryptoHexDigit(prefixHex.charAt(hoff + 1))
                        } else {
                            kb = prefix.charCodeAt(byteIdx)
                        }
                    }
                    byteVal = (kb ^ prefixXor) & 255
                } else if (byteIdx < dataLen) {
                    const moff = byteIdx - padPrefixLen
                    if (dataHexLen > 0) {
                        const hoff = moff * 2
                        byteVal = cryptoHexDigit(dataHex.charAt(hoff)) * 16 + cryptoHexDigit(dataHex.charAt(hoff + 1))
                    } else {
                        byteVal = data.charCodeAt(moff)
                    }
                } else if (byteIdx == dataLen) {
                    byteVal = 128
                } else if (byteIdx >= padLen - 4) {
                    const lbp = byteIdx - (padLen - 4)
                    if (lbp == 0) { byteVal = (bitLen >>> 24) & 255 }
                    if (lbp == 1) { byteVal = (bitLen >>> 16) & 255 }
                    if (lbp == 2) { byteVal = (bitLen >>> 8) & 255 }
                    if (lbp == 3) { byteVal = bitLen & 255 }
                }
                word = (word << 8) | byteVal
                bi = bi + 1
            }
            if (wi == 0) { w0 = word }
            if (wi == 1) { w1 = word }
            if (wi == 2) { w2 = word }
            if (wi == 3) { w3 = word }
            if (wi == 4) { w4 = word }
            if (wi == 5) { w5 = word }
            if (wi == 6) { w6 = word }
            if (wi == 7) { w7 = word }
            if (wi == 8) { w8 = word }
            if (wi == 9) { w9 = word }
            if (wi == 10) { w10 = word }
            if (wi == 11) { w11 = word }
            if (wi == 12) { w12 = word }
            if (wi == 13) { w13 = word }
            if (wi == 14) { w14 = word }
            if (wi == 15) { w15 = word }
            wi = wi + 1
        }

        let a = h0
        let b = h1
        let c = h2
        let d = h3
        let e = h4

        // First 16 rounds use w0..w15 directly
        let round = 0
        while (round < 16) {
            let wVal = 0
            if (round == 0) { wVal = w0 }
            if (round == 1) { wVal = w1 }
            if (round == 2) { wVal = w2 }
            if (round == 3) { wVal = w3 }
            if (round == 4) { wVal = w4 }
            if (round == 5) { wVal = w5 }
            if (round == 6) { wVal = w6 }
            if (round == 7) { wVal = w7 }
            if (round == 8) { wVal = w8 }
            if (round == 9) { wVal = w9 }
            if (round == 10) { wVal = w10 }
            if (round == 11) { wVal = w11 }
            if (round == 12) { wVal = w12 }
            if (round == 13) { wVal = w13 }
            if (round == 14) { wVal = w14 }
            if (round == 15) { wVal = w15 }

            const f = sha1GetF(round, b, c, d)
            const k = sha1GetK(round)
            const temp = sha1Rotl(a, 5) + f + e + k + wVal
            e = d
            d = c
            c = sha1Rotl(b, 30)
            b = a
            a = temp
            round = round + 1
        }

        // Rounds 16-79: expand and compress
        while (round < 80) {
            const new_w = sha1Rotl(w13 ^ w8 ^ w2 ^ w0, 1)
            w0 = w1
            w1 = w2
            w2 = w3
            w3 = w4
            w4 = w5
            w5 = w6
            w6 = w7
            w7 = w8
            w8 = w9
            w9 = w10
            w10 = w11
            w11 = w12
            w12 = w13
            w13 = w14
            w14 = w15
            w15 = new_w

            const f = sha1GetF(round, b, c, d)
            const k = sha1GetK(round)
            const temp = sha1Rotl(a, 5) + f + e + k + new_w
            e = d
            d = c
            c = sha1Rotl(b, 30)
            b = a
            a = temp
            round = round + 1
        }

        h0 = h0 + a
        h1 = h1 + b
        h2 = h2 + c
        h3 = h3 + d
        h4 = h4 + e

        blockStart = blockStart + 64
    }

    return hexWord(h0) + hexWord(h1) + hexWord(h2) + hexWord(h3) + hexWord(h4)
}

// ── SHA-256 flex hash ────────────────────────────────────────
// Same flex interface as sha1flex but for SHA-256.
// Uses rotr/ch/maj/sigma0/sigma1/gamma0/gamma1/getKConst from sha256.ss.

function sha256flex(data: string, dataHex: string, prefix: string, prefixHex: string, prefixXor: int): string {
    let h0 = 1779033703
    let h1 = -1150833019
    let h2 = 1013904242
    let h3 = -1521486534
    let h4 = 1359893119
    let h5 = -1694144372
    let h6 = 528734635
    let h7 = 1541459225

    const prefixStrLen = prefix.length()
    const prefixHexLen = prefixHex.length()
    let prefixLen = prefixStrLen
    if (prefixHexLen > 0) { prefixLen = prefixHexLen / 2 }
    let padPrefixLen = 0
    if (prefixLen > 0 || prefixXor > 0) { padPrefixLen = 64 }

    const dataHexLen = dataHex.length()
    let msgLen = data.length()
    if (dataHexLen > 0) { msgLen = dataHexLen / 2 }

    const dataLen = padPrefixLen + msgLen
    const bitLen = dataLen * 8

    let padLen = dataLen + 1
    while (padLen % 64 != 56) { padLen = padLen + 1 }
    padLen = padLen + 8

    let blockStart = 0
    while (blockStart < padLen) {
        let w0 = 0
        let w1 = 0
        let w2 = 0
        let w3 = 0
        let w4 = 0
        let w5 = 0
        let w6 = 0
        let w7 = 0
        let w8 = 0
        let w9 = 0
        let w10 = 0
        let w11 = 0
        let w12 = 0
        let w13 = 0
        let w14 = 0
        let w15 = 0

        let wi = 0
        while (wi < 16) {
            let word = 0
            let bi = 0
            while (bi < 4) {
                const byteIdx = blockStart + wi * 4 + bi
                let byteVal = 0
                if (byteIdx < padPrefixLen) {
                    let kb = 0
                    if (byteIdx < prefixLen) {
                        if (prefixHexLen > 0) {
                            const hoff = byteIdx * 2
                            kb = cryptoHexDigit(prefixHex.charAt(hoff)) * 16 + cryptoHexDigit(prefixHex.charAt(hoff + 1))
                        } else {
                            kb = prefix.charCodeAt(byteIdx)
                        }
                    }
                    byteVal = (kb ^ prefixXor) & 255
                } else if (byteIdx < dataLen) {
                    const moff = byteIdx - padPrefixLen
                    if (dataHexLen > 0) {
                        const hoff = moff * 2
                        byteVal = cryptoHexDigit(dataHex.charAt(hoff)) * 16 + cryptoHexDigit(dataHex.charAt(hoff + 1))
                    } else {
                        byteVal = data.charCodeAt(moff)
                    }
                } else if (byteIdx == dataLen) {
                    byteVal = 128
                } else if (byteIdx >= padLen - 4) {
                    const lbp = byteIdx - (padLen - 4)
                    if (lbp == 0) { byteVal = (bitLen >>> 24) & 255 }
                    if (lbp == 1) { byteVal = (bitLen >>> 16) & 255 }
                    if (lbp == 2) { byteVal = (bitLen >>> 8) & 255 }
                    if (lbp == 3) { byteVal = bitLen & 255 }
                }
                word = (word << 8) | byteVal
                bi = bi + 1
            }
            if (wi == 0) { w0 = word }
            if (wi == 1) { w1 = word }
            if (wi == 2) { w2 = word }
            if (wi == 3) { w3 = word }
            if (wi == 4) { w4 = word }
            if (wi == 5) { w5 = word }
            if (wi == 6) { w6 = word }
            if (wi == 7) { w7 = word }
            if (wi == 8) { w8 = word }
            if (wi == 9) { w9 = word }
            if (wi == 10) { w10 = word }
            if (wi == 11) { w11 = word }
            if (wi == 12) { w12 = word }
            if (wi == 13) { w13 = word }
            if (wi == 14) { w14 = word }
            if (wi == 15) { w15 = word }
            wi = wi + 1
        }

        let a = h0
        let b = h1
        let c = h2
        let d = h3
        let e = h4
        let f = h5
        let g = h6
        let h = h7

        // First 16 rounds
        let round = 0
        while (round < 16) {
            let wVal = 0
            if (round == 0) { wVal = w0 }
            if (round == 1) { wVal = w1 }
            if (round == 2) { wVal = w2 }
            if (round == 3) { wVal = w3 }
            if (round == 4) { wVal = w4 }
            if (round == 5) { wVal = w5 }
            if (round == 6) { wVal = w6 }
            if (round == 7) { wVal = w7 }
            if (round == 8) { wVal = w8 }
            if (round == 9) { wVal = w9 }
            if (round == 10) { wVal = w10 }
            if (round == 11) { wVal = w11 }
            if (round == 12) { wVal = w12 }
            if (round == 13) { wVal = w13 }
            if (round == 14) { wVal = w14 }
            if (round == 15) { wVal = w15 }

            const t1 = h + sigma1(e) + ch(e, f, g) + getKConst(round) + wVal
            const t2 = sigma0(a) + maj(a, b, c)
            h = g
            g = f
            f = e
            e = d + t1
            d = c
            c = b
            b = a
            a = t1 + t2
            round = round + 1
        }

        // Rounds 16-63: expand and compress
        while (round < 64) {
            const new_w = gamma1(w14) + w9 + gamma0(w1) + w0
            w0 = w1
            w1 = w2
            w2 = w3
            w3 = w4
            w4 = w5
            w5 = w6
            w6 = w7
            w7 = w8
            w8 = w9
            w9 = w10
            w10 = w11
            w11 = w12
            w12 = w13
            w13 = w14
            w14 = w15
            w15 = new_w

            const t1 = h + sigma1(e) + ch(e, f, g) + getKConst(round) + new_w
            const t2 = sigma0(a) + maj(a, b, c)
            h = g
            g = f
            f = e
            e = d + t1
            d = c
            c = b
            b = a
            a = t1 + t2
            round = round + 1
        }

        h0 = h0 + a
        h1 = h1 + b
        h2 = h2 + c
        h3 = h3 + d
        h4 = h4 + e
        h5 = h5 + f
        h6 = h6 + g
        h7 = h7 + h

        blockStart = blockStart + 64
    }

    return hexWord(h0) + hexWord(h1) + hexWord(h2) + hexWord(h3) + hexWord(h4) + hexWord(h5) + hexWord(h6) + hexWord(h7)
}

// ── Hex conversion utilities ─────────────────────────────────

function cryptoHexToBytes(hex: string): string {
    let result = ""
    let i = 0
    const len = hex.length()
    while (i < len) {
        const hi = cryptoHexDigit(hex.charAt(i))
        const lo = cryptoHexDigit(hex.charAt(i + 1))
        result = result + fromCharCode(hi * 16 + lo)
        i = i + 2
    }
    return result
}

function cryptoBytesToHex(data: string): string {
    let result = ""
    let i = 0
    const len = data.length()
    while (i < len) {
        result = result + hexByte(data.charCodeAt(i))
        i = i + 1
    }
    return result
}

// ── HMAC ─────────────────────────────────────────────────────

function cryptoHmac256(key: string, message: string): string {
    let keyStr = key
    let keyHex = ""
    if (key.length() > 64) {
        keyHex = sha256flex(key, "", "", "", 0)
        keyStr = ""
    }
    const innerHex = sha256flex(message, "", keyStr, keyHex, 54)
    return sha256flex("", innerHex, keyStr, keyHex, 92)
}

function cryptoHmac1(key: string, message: string): string {
    let keyStr = key
    let keyHex = ""
    if (key.length() > 64) {
        keyHex = sha1flex(key, "", "", "", 0)
        keyStr = ""
    }
    const innerHex = sha1flex(message, "", keyStr, keyHex, 54)
    return sha1flex("", innerHex, keyStr, keyHex, 92)
}

// ── Timing-safe comparison ───────────────────────────────────

function cryptoTimeSafe(a: string, b: string): int {
    if (a.length() != b.length()) { return 0 }
    let diff = 0
    let i = 0
    while (i < a.length()) {
        diff = diff | (a.charCodeAt(i) ^ b.charCodeAt(i))
        i = i + 1
    }
    if (diff == 0) { return 1 }
    return 0
}

// ── Crypto static methods ────────────────────────────────────

function Crypto_sha1(data: string): string {
    return sha1flex(data, "", "", "", 0)
}

function Crypto_sha256(data: string): string {
    return sha256flex(data, "", "", "", 0)
}

function Crypto_hmacSHA256(key: string, message: string): string {
    return cryptoHmac256(key, message)
}

function Crypto_hmacSHA1(key: string, message: string): string {
    return cryptoHmac1(key, message)
}

function Crypto_hexToBytes(hex: string): string {
    return cryptoHexToBytes(hex)
}

function Crypto_bytesToHex(data: string): string {
    return cryptoBytesToHex(data)
}

function Crypto_timingSafeEqual(a: string, b: string): int {
    return cryptoTimeSafe(a, b)
}
