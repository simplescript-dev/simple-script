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

import { Timestamp, RowId } from "@/lib/java/sql"

// ── MysqlTimestamp — implements java.sql.Timestamp ─────────────
// Driver-side wrapper for TIMESTAMP / DATETIME column values from the
// MySQL binary protocol row stream. JDBC 4.3 §13.2.1 / Connector/J
// `MysqlxDateTime` / Postgres JDBC `PgTimestamp` direct port. Driver
// pre-decodes wire bytes into 7 components + millis-since-epoch — both
// representations live in the class so cheap getters never recompute.
//
// before/after/compareTo follow JDBC spec: time-millis primary key,
// nanos tie-breaker (Timestamp.equals contract: same time AND same
// nanos). toString format is "YYYY-MM-DD HH:MM:SS.fffffffff" with
// trailing zero strip on the fractional part (minimum 1 digit).

class MysqlTimestamp : Timestamp {
    yearVal: int
    monthVal: int
    dayVal: int
    hoursVal: int
    minutesVal: int
    secondsVal: int
    nanosVal: int
    timeVal: int

    function getYear(): int { return this.yearVal }
    function getMonth(): int { return this.monthVal }
    function getDay(): int { return this.dayVal }
    function getHours(): int { return this.hoursVal }
    function getMinutes(): int { return this.minutesVal }
    function getSeconds(): int { return this.secondsVal }
    function getNanos(): int { return this.nanosVal }

    function setNanos(nanos: int) { this.nanosVal = nanos }
    function getTime(): int { return this.timeVal }
    function setTime(time: int) { this.timeVal = time }

    function before(other: Timestamp): int {
        const otherTime = other.getTime()
        if (this.timeVal < otherTime) { return 1 }
        if (this.timeVal > otherTime) { return 0 }
        if (this.nanosVal < other.getNanos()) { return 1 }
        return 0
    }

    function after(other: Timestamp): int {
        const otherTime = other.getTime()
        if (this.timeVal > otherTime) { return 1 }
        if (this.timeVal < otherTime) { return 0 }
        if (this.nanosVal > other.getNanos()) { return 1 }
        return 0
    }

    function equals(other: Timestamp): int {
        if (this.timeVal != other.getTime()) { return 0 }
        if (this.nanosVal != other.getNanos()) { return 0 }
        return 1
    }

    function compareTo(other: Timestamp): int {
        const otherTime = other.getTime()
        if (this.timeVal < otherTime) { return -1 }
        if (this.timeVal > otherTime) { return 1 }
        const otherNanos = other.getNanos()
        if (this.nanosVal < otherNanos) { return -1 }
        if (this.nanosVal > otherNanos) { return 1 }
        return 0
    }

    function toString(): string {
        let result = pad4(this.yearVal)
        result = `${result}-${pad2(this.monthVal)}-${pad2(this.dayVal)}`
        result = `${result} ${pad2(this.hoursVal)}:${pad2(this.minutesVal)}:${pad2(this.secondsVal)}`
        result = `${result}.${nanosFormat(this.nanosVal)}`
        return result
    }
}

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

// Zero-pad `n` to 2 digits (e.g., 5 → "05", 12 → "12"). Caller guarantees
// 0 ≤ n ≤ 99 (calendar fields: month/day/hours/minutes/seconds).
function pad2(n: int): string {
    if (n < 10) { return `0${n}` }
    return `${n}`
}

// Zero-pad `n` to 4 digits (year). Negative years (BC) not supported by
// this spike — driver only emits positive years from MySQL TIMESTAMP /
// DATETIME columns (1970-9999 range per MySQL spec).
function pad4(n: int): string {
    if (n < 10) { return `000${n}` }
    if (n < 100) { return `00${n}` }
    if (n < 1000) { return `0${n}` }
    return `${n}`
}

// Format nanoseconds for Timestamp.toString() — JDBC 4.3 §13.2.1 spec:
// fixed 9-digit field with trailing zeros stripped, minimum 1 digit.
//   0           → "0"
//   123000000   → "123"
//   123456789   → "123456789"
function nanosFormat(n: int): string {
    if (n == 0) { return "0" }
    let s = ""
    let val = n
    let i = 0
    while (i < 9) {
        s = `${val % 10}${s}`
        val = val / 10
        i = i + 1
    }
    let last = s.length() - 1
    while (last > 0 && s.charCodeAt(last) == 48) {
        last = last - 1
    }
    return s.substring(0, last + 1)
}
