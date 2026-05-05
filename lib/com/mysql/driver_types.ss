// lib/com/mysql/driver_types.ss — MySQL JDBC driver type implementation classes
//
// D154 §F7 sub-D production driver class impl — landing point for the
// driver-side concrete implementations of lib/java/sql.ss type interfaces.
// JDBC 4.3 §13.2 driver impl pattern direct port (MySQL Connector/J 8.x
// `com.mysql.cj.jdbc.Mysqlx*` family) — every SQL type interface gets a
// vendor-specific production class wrapping wire-protocol payload from
// the MySQL row stream.
//
// Phase 1 spike: MysqlRowId (smallest interface in the 12-class surface,
// 4 methods). Subsequent phases land MysqlTimestamp/MysqlBlob/MysqlClob/
// MysqlNClob/MysqlSQLXML/MysqlSqlArray/MysqlRef + 4 stream classes
// (AsciiStream/BinaryStream/CharacterStream/NCharacterStream).

import { RowId } from "@/lib/java/sql"

// ── MysqlRowId — implements java.sql.RowId ─────────────────────
// Driver-opaque row identifier. JDBC 4.3 §13.2.3 contract: RowId bytes
// are vendor-defined — MySQL uses the row hash from the binary protocol
// row stream. equals() compares byte-for-byte; toString() hex-encodes
// for readability (Connector/J convention); hashCode() uses the standard
// Java polynomial hash so the value is suitable as a Map key.

class MysqlRowId : RowId {
    rowBytes: string

    function getBytes(): string {
        return this.rowBytes
    }

    function toString(): string {
        let result = ""
        let i = 0
        let n = this.rowBytes.length()
        while (i < n) {
            const c = this.rowBytes.charCodeAt(i)
            const hi = (c >> 4) & 0xF
            const lo = c & 0xF
            result = result + hexChar(hi) + hexChar(lo)
            i = i + 1
        }
        return result
    }

    function equals(other: RowId): int {
        const otherBytes = other.getBytes()
        if (this.rowBytes.length() != otherBytes.length()) { return 0 }
        if (this.rowBytes == otherBytes) { return 1 }
        return 0
    }

    function hashCode(): int {
        let h = 0
        let i = 0
        const n = this.rowBytes.length()
        while (i < n) {
            h = 31 * h + this.rowBytes.charCodeAt(i)
            i = i + 1
        }
        return h
    }
}

function hexChar(n: int): string {
    if (n < 10) {
        return fromCharCode(48 + n)
    }
    return fromCharCode(87 + n)
}
