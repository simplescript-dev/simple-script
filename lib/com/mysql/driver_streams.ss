// lib/com/mysql/driver_streams.ss — MySQL JDBC driver stream classes
//
// D154 §F7 sub-D Phase 4 — driver-side stream class implementations
// for JDBC LOB type access. Blob.getBinaryStream() / Clob.
// getCharacterStream() / SQLXML.getBinaryStream() / SQLXML.
// getCharacterStream() return these. JDBC 4.3 §13.2.2 / Connector/J
// `MysqlxBlob.getBinaryStream` / Postgres JDBC `PgBlob.getBinaryStream`
// direct port.
//
// 4 stream class:
//   MysqlAsciiStream / MysqlBinaryStream    : InputStream (byte stream)
//   MysqlCharacterStream / MysqlNCharacterStream : Reader (char stream)
//
// SS strings are byte-oriented (charCodeAt → 0..255). InputStream and
// Reader implementations share method bodies — semantic distinction
// (ascii-only vs binary, default vs national charset) lives in the
// driver wire-decoding layer, not in stream class behaviour. The
// 4 classes carry separate names per JDBC API contract so that future
// charset enforcement (e.g., AsciiStream rejecting bytes > 127 on
// write) can be added without renaming callers.
//
// Mark/reset bookmark facility: mark() records current pos; reset()
// rewinds. Calling reset() before mark() is a silent no-op (D136 §A.5:
// no IOException hierarchy on streams; convention is leave pos
// unchanged). markSupported() always returns 1.

import { InputStream, Reader } from "@/lib/java/io"

// ── MysqlAsciiStream — implements InputStream ──────────────────
// Wraps ASCII-decoded bytes from CHAR / VARCHAR with `ascii` charset.
// Driver-side handle for ResultSet.getAsciiStream / PreparedStatement.
// setAsciiStream.

class MysqlAsciiStream : InputStream {
    payload: string
    pos: int
    markPos: int

    function read(): int {
        if (this.pos >= this.payload.length()) { return -1 }
        const b = this.payload.charCodeAt(this.pos)
        this.pos = this.pos + 1
        return b
    }

    function readN(len: int): string {
        const remaining = this.payload.length() - this.pos
        if (remaining <= 0) { return "" }
        let take = len
        if (take > remaining) { take = remaining }
        const result = this.payload.substring(this.pos, take)
        this.pos = this.pos + take
        return result
    }

    function skip(n: int): int {
        const remaining = this.payload.length() - this.pos
        let actual = n
        if (actual > remaining) { actual = remaining }
        if (actual < 0) { actual = 0 }
        this.pos = this.pos + actual
        return actual
    }

    function available(): int {
        return this.payload.length() - this.pos
    }

    function close() {
        this.payload = ""
        this.pos = 0
    }

    function mark(readlimit: int) {
        this.markPos = this.pos
    }

    function reset() {
        if (this.markPos < 0) { return }
        this.pos = this.markPos
    }

    function markSupported(): int { return 1 }
}

// ── MysqlBinaryStream — implements InputStream ─────────────────
// Wraps raw bytes from BLOB / VARBINARY / BINARY columns. No charset
// enforcement — any byte 0..255 passes through. Method bodies identical
// to MysqlAsciiStream; class identity preserves JDBC API contract.

class MysqlBinaryStream : InputStream {
    payload: string
    pos: int
    markPos: int

    function read(): int {
        if (this.pos >= this.payload.length()) { return -1 }
        const b = this.payload.charCodeAt(this.pos)
        this.pos = this.pos + 1
        return b
    }

    function readN(len: int): string {
        const remaining = this.payload.length() - this.pos
        if (remaining <= 0) { return "" }
        let take = len
        if (take > remaining) { take = remaining }
        const result = this.payload.substring(this.pos, take)
        this.pos = this.pos + take
        return result
    }

    function skip(n: int): int {
        const remaining = this.payload.length() - this.pos
        let actual = n
        if (actual > remaining) { actual = remaining }
        if (actual < 0) { actual = 0 }
        this.pos = this.pos + actual
        return actual
    }

    function available(): int {
        return this.payload.length() - this.pos
    }

    function close() {
        this.payload = ""
        this.pos = 0
    }

    function mark(readlimit: int) {
        this.markPos = this.pos
    }

    function reset() {
        if (this.markPos < 0) { return }
        this.pos = this.markPos
    }

    function markSupported(): int { return 1 }
}

// ── MysqlCharacterStream — implements Reader ───────────────────
// Wraps UTF-8-decoded chars from CHAR / VARCHAR / TEXT columns
// (default character set). Driver-side handle for ResultSet.
// getCharacterStream / PreparedStatement.setCharacterStream.

class MysqlCharacterStream : Reader {
    payload: string
    pos: int
    markPos: int

    function read(): int {
        if (this.pos >= this.payload.length()) { return -1 }
        const c = this.payload.charCodeAt(this.pos)
        this.pos = this.pos + 1
        return c
    }

    function readN(len: int): string {
        const remaining = this.payload.length() - this.pos
        if (remaining <= 0) { return "" }
        let take = len
        if (take > remaining) { take = remaining }
        const result = this.payload.substring(this.pos, take)
        this.pos = this.pos + take
        return result
    }

    function skip(n: int): int {
        const remaining = this.payload.length() - this.pos
        let actual = n
        if (actual > remaining) { actual = remaining }
        if (actual < 0) { actual = 0 }
        this.pos = this.pos + actual
        return actual
    }

    function ready(): int {
        if (this.pos < this.payload.length()) { return 1 }
        return 0
    }

    function close() {
        this.payload = ""
        this.pos = 0
    }

    function mark(readlimit: int) {
        this.markPos = this.pos
    }

    function reset() {
        if (this.markPos < 0) { return }
        this.pos = this.markPos
    }

    function markSupported(): int { return 1 }
}

// ── MysqlNCharacterStream — implements Reader ──────────────────
// Wraps UTF-8-decoded chars from NCHAR / NVARCHAR / NTEXT columns
// (national character set). Method bodies identical to
// MysqlCharacterStream; class identity preserves JDBC API contract.

class MysqlNCharacterStream : Reader {
    payload: string
    pos: int
    markPos: int

    function read(): int {
        if (this.pos >= this.payload.length()) { return -1 }
        const c = this.payload.charCodeAt(this.pos)
        this.pos = this.pos + 1
        return c
    }

    function readN(len: int): string {
        const remaining = this.payload.length() - this.pos
        if (remaining <= 0) { return "" }
        let take = len
        if (take > remaining) { take = remaining }
        const result = this.payload.substring(this.pos, take)
        this.pos = this.pos + take
        return result
    }

    function skip(n: int): int {
        const remaining = this.payload.length() - this.pos
        let actual = n
        if (actual > remaining) { actual = remaining }
        if (actual < 0) { actual = 0 }
        this.pos = this.pos + actual
        return actual
    }

    function ready(): int {
        if (this.pos < this.payload.length()) { return 1 }
        return 0
    }

    function close() {
        this.payload = ""
        this.pos = 0
    }

    function mark(readlimit: int) {
        this.markPos = this.pos
    }

    function reset() {
        if (this.markPos < 0) { return }
        this.pos = this.markPos
    }

    function markSupported(): int { return 1 }
}
