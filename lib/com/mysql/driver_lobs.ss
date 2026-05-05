// lib/com/mysql/driver_lobs.ss — MySQL JDBC driver Large Object classes
//
// D154 §F7 sub-D Phase 5 — 4 LOB type class production impl,完整 12/12
// driver class 落地。Blob/Clob/NClob/SQLXML 的 getBinaryStream /
// getCharacterStream 返回真 stream class implementor (driver_streams.ss),
// 不再是 stub。
//
// JDBC 4.3 §13.2.2 / Connector/J `MysqlxBlob` / `MysqlxClob` / Postgres
// JDBC `PgBlob` / `PgSQLXML` 直翻。
//
// JDBC API 1-based position convention: getBytes(pos, len) / getSubString
// (pos, len) / setBytes(pos, ...) / setString(pos, ...) / position()
// 全部 1-based。truncate(len) 直接 0-based length cut。free() 清空 payload
// (driver-side resource — 无 server-side handle 需要 release on MySQL
// wire, MySQL LOB columns 是 inline content 不是 BLOB descriptor).

import { Blob, Clob, NClob, SQLXML } from "@/lib/java/sql"
import { InputStream, Reader } from "@/lib/java/io"
import { MysqlBinaryStream, MysqlCharacterStream, MysqlNCharacterStream } from "@/lib/com/mysql/driver_streams"

// ── MysqlBlob — implements java.sql.Blob ───────────────────────
// Wraps raw binary bytes from BLOB / VARBINARY / BINARY columns.
// getBinaryStream() returns MysqlBinaryStream (driver_streams.ss).

class MysqlBlob : Blob {
    payload: string

    function length(): int { return this.payload.length() }

    function getBytes(pos: int, len: int): string {
        const start = pos - 1
        if (start < 0) { return "" }
        if (start >= this.payload.length()) { return "" }
        const remaining = this.payload.length() - start
        let take = len
        if (take > remaining) { take = remaining }
        return this.payload.substring(start, take)
    }

    function setBytes(pos: int, bytes: string): int {
        const start = pos - 1
        if (start < 0) { return 0 }
        const before = this.payload.substring(0, start)
        const afterStart = start + bytes.length()
        let after = ""
        if (afterStart < this.payload.length()) {
            after = this.payload.substring(afterStart, this.payload.length() - afterStart)
        }
        this.payload = before + bytes + after
        return bytes.length()
    }

    function position(pattern: string, start: int): int {
        const startIdx = start - 1
        if (startIdx < 0) { return -1 }
        if (startIdx >= this.payload.length()) { return -1 }
        const slice = this.payload.substring(startIdx, this.payload.length() - startIdx)
        const idx = slice.indexOf(pattern)
        if (idx < 0) { return -1 }
        return idx + start
    }

    function truncate(len: int) {
        if (len < 0) { return }
        if (len >= this.payload.length()) { return }
        this.payload = this.payload.substring(0, len)
    }

    function getBinaryStream(): InputStream {
        return new MysqlBinaryStream(this.payload, 0, -1)
    }

    function free() { this.payload = "" }
}

// ── MysqlClob — implements java.sql.Clob ───────────────────────
// Wraps UTF-8 chars from TEXT / LONGTEXT / CLOB columns. Method bodies
// match MysqlBlob pattern (SS strings are byte/char-equivalent at this
// layer); getCharacterStream() returns MysqlCharacterStream.

class MysqlClob : Clob {
    payload: string

    function length(): int { return this.payload.length() }

    function getSubString(pos: int, len: int): string {
        const start = pos - 1
        if (start < 0) { return "" }
        if (start >= this.payload.length()) { return "" }
        const remaining = this.payload.length() - start
        let take = len
        if (take > remaining) { take = remaining }
        return this.payload.substring(start, take)
    }

    function setString(pos: int, str: string): int {
        const start = pos - 1
        if (start < 0) { return 0 }
        const before = this.payload.substring(0, start)
        const afterStart = start + str.length()
        let after = ""
        if (afterStart < this.payload.length()) {
            after = this.payload.substring(afterStart, this.payload.length() - afterStart)
        }
        this.payload = before + str + after
        return str.length()
    }

    function position(pattern: string, start: int): int {
        const startIdx = start - 1
        if (startIdx < 0) { return -1 }
        if (startIdx >= this.payload.length()) { return -1 }
        const slice = this.payload.substring(startIdx, this.payload.length() - startIdx)
        const idx = slice.indexOf(pattern)
        if (idx < 0) { return -1 }
        return idx + start
    }

    function truncate(len: int) {
        if (len < 0) { return }
        if (len >= this.payload.length()) { return }
        this.payload = this.payload.substring(0, len)
    }

    function getCharacterStream(): Reader {
        return new MysqlCharacterStream(this.payload, 0, -1)
    }

    function free() { this.payload = "" }
}

// ── MysqlNClob — implements java.sql.NClob ─────────────────────
// Wraps national-character chars from NCHAR / NVARCHAR / NCLOB columns.
// Identical semantics to MysqlClob; getCharacterStream() returns
// MysqlNCharacterStream to preserve national-charset class identity
// for downstream code that pattern-matches on stream class type.

class MysqlNClob : NClob {
    payload: string

    function length(): int { return this.payload.length() }

    function getSubString(pos: int, len: int): string {
        const start = pos - 1
        if (start < 0) { return "" }
        if (start >= this.payload.length()) { return "" }
        const remaining = this.payload.length() - start
        let take = len
        if (take > remaining) { take = remaining }
        return this.payload.substring(start, take)
    }

    function setString(pos: int, str: string): int {
        const start = pos - 1
        if (start < 0) { return 0 }
        const before = this.payload.substring(0, start)
        const afterStart = start + str.length()
        let after = ""
        if (afterStart < this.payload.length()) {
            after = this.payload.substring(afterStart, this.payload.length() - afterStart)
        }
        this.payload = before + str + after
        return str.length()
    }

    function position(pattern: string, start: int): int {
        const startIdx = start - 1
        if (startIdx < 0) { return -1 }
        if (startIdx >= this.payload.length()) { return -1 }
        const slice = this.payload.substring(startIdx, this.payload.length() - startIdx)
        const idx = slice.indexOf(pattern)
        if (idx < 0) { return -1 }
        return idx + start
    }

    function truncate(len: int) {
        if (len < 0) { return }
        if (len >= this.payload.length()) { return }
        this.payload = this.payload.substring(0, len)
    }

    function getCharacterStream(): Reader {
        return new MysqlNCharacterStream(this.payload, 0, -1)
    }

    function free() { this.payload = "" }
}

// ── MysqlSQLXML — implements java.sql.SQLXML ───────────────────
// Wraps XML / JSON column payload. Both binary stream (UTF-8 bytes) and
// character stream (UTF-8 chars) views are exposed — SS strings are
// byte/char-equivalent so both views read the same payload.

class MysqlSQLXML : SQLXML {
    payload: string

    function getString(): string { return this.payload }
    function setString(value: string) { this.payload = value }

    function getBinaryStream(): InputStream {
        return new MysqlBinaryStream(this.payload, 0, -1)
    }

    function getCharacterStream(): Reader {
        return new MysqlCharacterStream(this.payload, 0, -1)
    }

    function free() { this.payload = "" }
}
