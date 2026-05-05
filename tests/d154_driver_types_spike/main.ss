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
import { Timestamp, RowId } from "@/lib/java/sql"
import { MysqlRowId, MysqlTimestamp } from "@/lib/com/mysql/driver_types"

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
}
