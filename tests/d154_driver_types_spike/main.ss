// D154 Phase 1-2 spike — MysqlRowId + MysqlTimestamp production driver
// class verification.
//
// Replaces the d152 *_test.ss stub-class dispatch pattern with real
// production driver classes. Each test instantiates the production class
// (lib/com/mysql/driver_types.ss) and verifies interface methods
// dispatch correctly. Last test of each block exercises the interface
// type binding (e.g., `const ts: Timestamp = new MysqlTimestamp(...)`)
// to confirm interface-level vtable resolution.

import { assertEqual } from "@/lib/test"
import { Timestamp, RowId, SqlArray, Ref } from "@/lib/java/sql"
import { InputStream, Reader } from "@/lib/java/io"
import { MysqlRowId, MysqlTimestamp, MysqlSqlArray, MysqlRef } from "@/lib/com/mysql/driver_types"
import { MysqlAsciiStream, MysqlBinaryStream, MysqlCharacterStream, MysqlNCharacterStream } from "@/lib/com/mysql/driver_streams"

function main() {
    test("MysqlRowId getBytes returns stored bytes", () => {
        const rid = new MysqlRowId("rowidbytes")
        assertEqual(rid.getBytes(), "rowidbytes")
    })

    test("MysqlRowId equals same bytes returns 1", () => {
        const rid1 = new MysqlRowId("abc")
        const rid2 = new MysqlRowId("abc")
        assertEqual(rid1.equals(rid2), 1)
    })

    test("MysqlRowId equals different bytes returns 0", () => {
        const rid1 = new MysqlRowId("abc")
        const rid2 = new MysqlRowId("xyz")
        assertEqual(rid1.equals(rid2), 0)
    })

    test("MysqlRowId equals different lengths returns 0", () => {
        const rid1 = new MysqlRowId("abc")
        const rid2 = new MysqlRowId("abcd")
        assertEqual(rid1.equals(rid2), 0)
    })

    test("MysqlRowId toString hex-encodes single byte", () => {
        // ASCII 'A' = 0x41
        const rid = new MysqlRowId("A")
        assertEqual(rid.toString(), "41")
    })

    test("MysqlRowId toString hex-encodes multi-byte", () => {
        // ASCII 'A' = 0x41, 'B' = 0x42, 'C' = 0x43
        const rid = new MysqlRowId("ABC")
        assertEqual(rid.toString(), "414243")
    })

    test("MysqlRowId hashCode deterministic for same bytes", () => {
        const rid1 = new MysqlRowId("hello")
        const rid2 = new MysqlRowId("hello")
        assertEqual(rid1.hashCode(), rid2.hashCode())
    })

    test("MysqlRowId hashCode differs for different bytes", () => {
        const rid1 = new MysqlRowId("hello")
        const rid2 = new MysqlRowId("world")
        // Polynomial hash: with 5-char inputs starting from different
        // first char, hashes must diverge — assert inequality.
        if (rid1.hashCode() == rid2.hashCode()) {
            throw("hashCode collision on 'hello' vs 'world' — unexpected")
        }
    })

    test("MysqlRowId via RowId interface dispatch", () => {
        const rid: RowId = new MysqlRowId("interfacedispatch")
        assertEqual(rid.getBytes(), "interfacedispatch")
    })

    // ── MysqlTimestamp tests ───────────────────────────────────

    test("MysqlTimestamp date component getters", () => {
        const ts = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 123456789, 1746362445123)
        assertEqual(ts.getYear(), 2026)
        assertEqual(ts.getMonth(), 5)
        assertEqual(ts.getDay(), 4)
    })

    test("MysqlTimestamp time component getters", () => {
        const ts = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 123456789, 1746362445123)
        assertEqual(ts.getHours(), 12)
        assertEqual(ts.getMinutes(), 30)
        assertEqual(ts.getSeconds(), 45)
        assertEqual(ts.getNanos(), 123456789)
    })

    test("MysqlTimestamp setNanos mutates field", () => {
        const ts = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 0, 0)
        ts.setNanos(987654321)
        assertEqual(ts.getNanos(), 987654321)
    })

    test("MysqlTimestamp getTime returns stored millis", () => {
        const ts = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 0, 1746362445000)
        assertEqual(ts.getTime(), 1746362445000)
    })

    test("MysqlTimestamp setTime mutates millis", () => {
        const ts = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 0, 0)
        ts.setTime(1234567890000)
        assertEqual(ts.getTime(), 1234567890000)
    })

    test("MysqlTimestamp toString full 9-digit nanos", () => {
        const ts = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 123456789, 0)
        assertEqual(ts.toString(), "2026-05-04 12:30:45.123456789")
    })

    test("MysqlTimestamp toString trailing-zero strip", () => {
        const ts = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 123000000, 0)
        assertEqual(ts.toString(), "2026-05-04 12:30:45.123")
    })

    test("MysqlTimestamp toString zero nanos shows '0'", () => {
        const ts = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 0, 0)
        assertEqual(ts.toString(), "2026-05-04 12:30:45.0")
    })

    test("MysqlTimestamp toString single-digit zero pad", () => {
        const ts = new MysqlTimestamp(2026, 1, 5, 9, 8, 7, 0, 0)
        assertEqual(ts.toString(), "2026-01-05 09:08:07.0")
    })

    test("MysqlTimestamp before earlier returns 1", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 0, 1000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 0, 2000)
        assertEqual(t1.before(t2), 1)
        assertEqual(t2.before(t1), 0)
    })

    test("MysqlTimestamp before equal time, lower nanos returns 1", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 100, 1000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 200, 1000)
        assertEqual(t1.before(t2), 1)
    })

    test("MysqlTimestamp after later returns 1", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 0, 2000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 0, 1000)
        assertEqual(t1.after(t2), 1)
        assertEqual(t2.after(t1), 0)
    })

    test("MysqlTimestamp equals same time + same nanos", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 100, 1000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 100, 1000)
        assertEqual(t1.equals(t2), 1)
    })

    test("MysqlTimestamp equals different time returns 0", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 100, 1000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 100, 2000)
        assertEqual(t1.equals(t2), 0)
    })

    test("MysqlTimestamp equals different nanos returns 0", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 100, 1000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 200, 1000)
        assertEqual(t1.equals(t2), 0)
    })

    test("MysqlTimestamp compareTo earlier returns -1", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 0, 1000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 0, 2000)
        assertEqual(t1.compareTo(t2), -1)
    })

    test("MysqlTimestamp compareTo later returns 1", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 0, 2000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 0, 1000)
        assertEqual(t1.compareTo(t2), 1)
    })

    test("MysqlTimestamp compareTo equal returns 0", () => {
        const t1 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 100, 1000)
        const t2 = new MysqlTimestamp(2026, 5, 4, 0, 0, 0, 100, 1000)
        assertEqual(t1.compareTo(t2), 0)
    })

    test("MysqlTimestamp via Timestamp interface dispatch", () => {
        const ts: Timestamp = new MysqlTimestamp(2026, 5, 4, 12, 30, 45, 0, 1746362445000)
        assertEqual(ts.getYear(), 2026)
        assertEqual(ts.getTime(), 1746362445000)
        assertEqual(ts.toString(), "2026-05-04 12:30:45.0")
    })

    // ── MysqlSqlArray tests ────────────────────────────────────

    test("MysqlSqlArray getBaseType returns stored int", () => {
        const arr = new MysqlSqlArray(4, "INTEGER", "[1,2,3]")
        assertEqual(arr.getBaseType(), 4)
    })

    test("MysqlSqlArray getBaseTypeName returns stored name", () => {
        const arr = new MysqlSqlArray(12, "VARCHAR", "[\"a\",\"b\"]")
        assertEqual(arr.getBaseTypeName(), "VARCHAR")
    })

    test("MysqlSqlArray getArray returns serialized payload", () => {
        const arr = new MysqlSqlArray(4, "INTEGER", "[10,20,30]")
        assertEqual(arr.getArray(), "[10,20,30]")
    })

    test("MysqlSqlArray free clears payload", () => {
        const arr = new MysqlSqlArray(4, "INTEGER", "[1,2]")
        arr.free()
        assertEqual(arr.getArray(), "")
    })

    test("MysqlSqlArray via SqlArray interface dispatch", () => {
        const arr: SqlArray = new MysqlSqlArray(4, "INTEGER", "[7,8,9]")
        assertEqual(arr.getBaseType(), 4)
        assertEqual(arr.getBaseTypeName(), "INTEGER")
        assertEqual(arr.getArray(), "[7,8,9]")
    })

    // ── MysqlRef tests ─────────────────────────────────────────

    test("MysqlRef getBaseTypeName returns stored name", () => {
        const ref = new MysqlRef("PERSON_T", "<row-pointer>")
        assertEqual(ref.getBaseTypeName(), "PERSON_T")
    })

    test("MysqlRef getObject returns stored payload", () => {
        const ref = new MysqlRef("PERSON_T", "<row-pointer>")
        assertEqual(ref.getObject(), "<row-pointer>")
    })

    test("MysqlRef setObject mutates payload", () => {
        const ref = new MysqlRef("PERSON_T", "")
        ref.setObject("<new-pointer>")
        assertEqual(ref.getObject(), "<new-pointer>")
    })

    test("MysqlRef via Ref interface dispatch", () => {
        const ref: Ref = new MysqlRef("ORDER_T", "<row-pointer>")
        assertEqual(ref.getBaseTypeName(), "ORDER_T")
        assertEqual(ref.getObject(), "<row-pointer>")
    })

    // ── MysqlAsciiStream tests ─────────────────────────────────

    test("MysqlAsciiStream read sequential bytes then EOF", () => {
        const s = new MysqlAsciiStream("ABC", 0, -1)
        assertEqual(s.read(), 65)
        assertEqual(s.read(), 66)
        assertEqual(s.read(), 67)
        assertEqual(s.read(), -1)
    })

    test("MysqlAsciiStream readN truncates at EOF", () => {
        const s = new MysqlAsciiStream("hello", 0, -1)
        assertEqual(s.readN(3), "hel")
        assertEqual(s.readN(10), "lo")
        assertEqual(s.readN(5), "")
    })

    test("MysqlAsciiStream skip advances pos and available shrinks", () => {
        const s = new MysqlAsciiStream("12345678", 0, -1)
        assertEqual(s.available(), 8)
        assertEqual(s.skip(3), 3)
        assertEqual(s.available(), 5)
    })

    test("MysqlAsciiStream mark + reset rewinds pos", () => {
        const s = new MysqlAsciiStream("ABC", 0, -1)
        s.read()
        s.mark(0)
        s.read()
        s.reset()
        assertEqual(s.read(), 66)
    })

    test("MysqlAsciiStream via InputStream interface dispatch", () => {
        const stream: InputStream = new MysqlAsciiStream("XY", 0, -1)
        assertEqual(stream.read(), 88)
        assertEqual(stream.read(), 89)
        assertEqual(stream.read(), -1)
    })

    // ── MysqlBinaryStream tests ────────────────────────────────

    test("MysqlBinaryStream via InputStream interface dispatch", () => {
        const stream: InputStream = new MysqlBinaryStream("xy", 0, -1)
        assertEqual(stream.read(), 120)
        assertEqual(stream.read(), 121)
        assertEqual(stream.read(), -1)
    })

    test("MysqlBinaryStream markSupported returns 1", () => {
        const s = new MysqlBinaryStream("abc", 0, -1)
        assertEqual(s.markSupported(), 1)
    })

    // ── MysqlCharacterStream tests ─────────────────────────────

    test("MysqlCharacterStream read + ready transitions on EOF", () => {
        const s = new MysqlCharacterStream("Hi", 0, -1)
        assertEqual(s.ready(), 1)
        assertEqual(s.read(), 72)
        assertEqual(s.read(), 105)
        assertEqual(s.ready(), 0)
        assertEqual(s.read(), -1)
    })

    test("MysqlCharacterStream close zeroes payload", () => {
        const s = new MysqlCharacterStream("hello", 0, -1)
        assertEqual(s.readN(2), "he")
        s.close()
        assertEqual(s.read(), -1)
    })

    test("MysqlCharacterStream via Reader interface dispatch", () => {
        const r: Reader = new MysqlCharacterStream("AB", 0, -1)
        assertEqual(r.read(), 65)
        assertEqual(r.read(), 66)
    })

    // ── MysqlNCharacterStream tests ────────────────────────────

    test("MysqlNCharacterStream via Reader interface dispatch", () => {
        const r: Reader = new MysqlNCharacterStream("xy", 0, -1)
        assertEqual(r.read(), 120)
        assertEqual(r.read(), 121)
    })

    test("MysqlNCharacterStream markSupported returns 1", () => {
        const s = new MysqlNCharacterStream("abc", 0, -1)
        assertEqual(s.markSupported(), 1)
    })
}
