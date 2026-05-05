// D154 Phase 1 spike — MysqlRowId production driver class verification.
//
// Replaces the d152 timestamp_test.ss-style stub-based dispatch pattern
// with a real production driver class. Each test instantiates MysqlRowId
// (lib/com/mysql/driver_types.ss) and verifies the 4 RowId interface
// methods dispatch correctly. Bidirectional闭环 verification: storing
// through MysqlRowId class and reading back through the RowId interface
// type binding (last test case).

import { assertEqual } from "@/lib/test"
import { RowId } from "@/lib/java/sql"
import { MysqlRowId } from "@/lib/com/mysql/driver_types"

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
}
