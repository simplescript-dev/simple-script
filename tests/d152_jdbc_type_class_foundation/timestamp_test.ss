// D152 Phase 3 — Timestamp / Date / Time interface dispatch test.
//
// Each interface has a stub class implementor; tests verify the
// declarations parse, `class X : Interface` binds, and the JDBC method
// surface dispatches through the interface vtable. Real driver impls
// (MysqlTimestamp / MysqlDate / MysqlTime) land in lib/com/mysql/* in a
// later D152 §Followup and will exercise these interfaces against a
// running MySQL server.
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 3.

import { assertEqual } from "@/lib/test"
import { Timestamp, Date, Time } from "@/lib/java/sql"

// Hardcoded to "2026-05-04 12:30:45.<nanos>"
class StubTimestamp : Timestamp {
    nanos: int

    function getYear(): int { return 2026 }
    function getMonth(): int { return 5 }
    function getDay(): int { return 4 }
    function getHours(): int { return 12 }
    function getMinutes(): int { return 30 }
    function getSeconds(): int { return 45 }
    function getNanos(): int { return this.nanos }
    function setNanos(nanos: int) { this.nanos = nanos }
    function getTime(): int { return 1746362445000 }
    function setTime(time: int) {}
    function before(other: Timestamp): int { return 0 }
    function after(other: Timestamp): int { return 0 }
    function equals(other: Timestamp): int { return 1 }
    function compareTo(other: Timestamp): int { return 0 }
    function toString(): string { return "2026-05-04 12:30:45" }
}

// Hardcoded to 2026-05-04
class StubDate : Date {
    function getYear(): int { return 2026 }
    function getMonth(): int { return 5 }
    function getDay(): int { return 4 }
    function getTime(): int { return 1746316800000 }
    function setTime(time: int) {}
    function before(other: Date): int { return 0 }
    function after(other: Date): int { return 0 }
    function equals(other: Date): int { return 1 }
    function compareTo(other: Date): int { return 0 }
    function toString(): string { return "2026-05-04" }
}

// Hardcoded to 12:30:45
class StubTime : Time {
    function getHours(): int { return 12 }
    function getMinutes(): int { return 30 }
    function getSeconds(): int { return 45 }
    function getTime(): int { return 45045000 }
    function setTime(time: int) {}
    function before(other: Time): int { return 0 }
    function after(other: Time): int { return 0 }
    function equals(other: Time): int { return 1 }
    function compareTo(other: Time): int { return 0 }
    function toString(): string { return "12:30:45" }
}

function main() {
    test("Timestamp accessors (JDBC 1-12 month convention)", () => {
        const ts = new StubTimestamp(789)
        assertEqual(ts.getYear(), 2026)
        assertEqual(ts.getMonth(), 5)
        assertEqual(ts.getDay(), 4)
        assertEqual(ts.getHours(), 12)
        assertEqual(ts.getMinutes(), 30)
        assertEqual(ts.getSeconds(), 45)
        assertEqual(ts.getNanos(), 789)
        assertEqual(ts.toString(), "2026-05-04 12:30:45")
    })

    test("Timestamp setNanos mutates field", () => {
        const ts = new StubTimestamp(0)
        ts.setNanos(123456789)
        assertEqual(ts.getNanos(), 123456789)
    })

    test("Date accessors", () => {
        const d = new StubDate()
        assertEqual(d.getYear(), 2026)
        assertEqual(d.getMonth(), 5)
        assertEqual(d.getDay(), 4)
        assertEqual(d.toString(), "2026-05-04")
    })

    test("Time accessors", () => {
        const t = new StubTime()
        assertEqual(t.getHours(), 12)
        assertEqual(t.getMinutes(), 30)
        assertEqual(t.getSeconds(), 45)
        assertEqual(t.toString(), "12:30:45")
    })
}
