// MySQL wire protocol binary primitives — D134 §A.4
// Little-endian byte/int conversions + MySQL length-encoded int/string.
//
// Read side (string buf input via charCodeAt) is binary-safe:
//   ss_charCodeAt does direct GEP+load, no strlen bounds-check (gen_rt_string.ss:117-122),
//   so embedded 0x00 bytes in the buffer are read correctly past any leading NULL.
//
// Write side (string return) has a fundamental limitation: ss_string_concat is
// strlen-based (gen_rt_string.ss:14-26), so concatenating fromCharCode(0) into a
// result truncates the result at the first 0x00 byte. Callers building binary
// payloads with embedded NULLs must either:
//   (a) write byte-by-byte via tcpWriteBytes(fd, fromCharCode(b), 1) — N+4 syscalls
//       (used by lib/com/mysql/wire.ss writePacket for header construction)
//   (b) Phase 3 may need a setByteAt builtin or Array<int> byte-buffer pattern
//       for handshake response construction (D134 §3 Phase 3 prep)

// ── Little-endian byte ↔ int ─────────────────────────────────────

// Reads `len` bytes (1..8) at `buf[offset..offset+len]` as little-endian unsigned int.
// Result is 32-bit (SS int); for 8-byte values, top 32 bits silently truncated.
function byteToInt(buf: string, offset: int, len: int): int {
    let result = 0
    let i = 0
    while (i < len) {
        const b = charCodeAt(buf, offset + i)
        result = result | (b << (i * 8))
        i = i + 1
    }
    return result
}

// LE encode `n` to a `len`-byte string. LIMITATION: any byte == 0 in the encoding
// truncates the returned string via ss_string_concat strlen — see file header.
// Useful only for values where all `len` low bytes are nonzero (rare).
function intToBytes(n: int, len: int): string {
    let result = ""
    let i = 0
    while (i < len) {
        const b = (n >>> (i * 8)) & 255
        result = result + fromCharCode(b)
        i = i + 1
    }
    return result
}

// ── MySQL length-encoded integer ─────────────────────────────────
// Encoding rules (MySQL Native Protocol):
//   first byte < 0xFB → value is the byte itself (1 byte total)
//   first byte = 0xFB → NULL marker (column value only; size = 1)
//   first byte = 0xFC → next 2 bytes LE = value (3 bytes total)
//   first byte = 0xFD → next 3 bytes LE = value (4 bytes total)
//   first byte = 0xFE → next 8 bytes LE = value (9 bytes total)

// Returns the encoded value, or -1 for NULL marker (0xFB).
// 0xFF (ERR packet header) is unreachable in length-encoded position per MySQL
// spec — fall through to -1 sentinel for caller-detectable corruption.
function readLengthEncodedInt(buf: string, offset: int): int {
    const first = charCodeAt(buf, offset)
    if (first < 0xFB) { return first }
    if (first == 0xFB) { return -1 }
    if (first == 0xFC) { return byteToInt(buf, offset + 1, 2) }
    if (first == 0xFD) { return byteToInt(buf, offset + 1, 3) }
    if (first == 0xFE) { return byteToInt(buf, offset + 1, 8) }
    return -1
}

// Returns total bytes consumed by the length-encoded int at `buf[offset]`.
// Caller must call this separately to advance offset (SS has no tuple return).
function lengthEncodedIntSize(buf: string, offset: int): int {
    const first = charCodeAt(buf, offset)
    if (first < 0xFB) { return 1 }
    if (first == 0xFB) { return 1 }
    if (first == 0xFC) { return 3 }
    if (first == 0xFD) { return 4 }
    if (first == 0xFE) { return 9 }
    return 1
}

// Reads length-encoded string at `buf[offset]`. Same string-concat NULL limitation
// as intToBytes — returned string truncates at first embedded 0x00. Use
// charCodeAt(buf, offset + size + i) directly when the payload may contain NULLs.
function readLengthEncodedString(buf: string, offset: int): string {
    const len = readLengthEncodedInt(buf, offset)
    if (len <= 0) { return "" }
    const size = lengthEncodedIntSize(buf, offset)
    let result = ""
    let i = 0
    while (i < len) {
        result = result + fromCharCode(charCodeAt(buf, offset + size + i))
        i = i + 1
    }
    return result
}

// LE encode `n` to length-encoded form. Same NULL limitation as intToBytes.
function writeLengthEncodedInt(n: int): string {
    if (n < 0xFB) {
        return fromCharCode(n)
    }
    if (n < 65536) {
        return fromCharCode(0xFC) + intToBytes(n, 2)
    }
    if (n < 16777216) {
        return fromCharCode(0xFD) + intToBytes(n, 3)
    }
    return fromCharCode(0xFE) + intToBytes(n, 8)
}
