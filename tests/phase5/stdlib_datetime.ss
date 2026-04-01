// Test: DateTime standard library module (D039)

import { DateTime } from "@/lib/datetime"

function assert(cond: int, msg: string) {
    if (cond == 0) {
        println(`FAIL: ${msg}`)
        exit(1)
    }
}

function assertEq(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} - expected ${expected}, got ${actual}`)
        exit(1)
    }
}

function assertStr(actual: string, expected: string, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} - expected "${expected}", got "${actual}"`)
        exit(1)
    }
}

function main() {
    // ── epoch (1970-01-01 00:00:00 UTC) ─────────────────────
    assertEq(DateTime.year(0), 1970, "epoch year")
    assertEq(DateTime.month(0), 1, "epoch month")
    assertEq(DateTime.day(0), 1, "epoch day")
    assertEq(DateTime.hour(0), 0, "epoch hour")
    assertEq(DateTime.minute(0), 0, "epoch minute")
    assertEq(DateTime.second(0), 0, "epoch second")
    assertEq(DateTime.dayOfWeek(0), 4, "epoch is Thursday")
    assertEq(DateTime.dayOfYear(0), 1, "epoch dayOfYear")

    // ── known date: 2000-01-01 00:00:00 = 946684800 ─────────
    const y2k = 946684800
    assertEq(DateTime.year(y2k), 2000, "y2k year")
    assertEq(DateTime.month(y2k), 1, "y2k month")
    assertEq(DateTime.day(y2k), 1, "y2k day")
    assertEq(DateTime.hour(y2k), 0, "y2k hour")
    assertEq(DateTime.dayOfWeek(y2k), 6, "y2k is Saturday")
    assertEq(DateTime.dayOfYear(y2k), 1, "y2k dayOfYear")

    // ── known date with time: 2024-07-15 14:30:59 ───────────
    const ts1 = DateTime.of(2024, 7, 15, 14, 30, 59)
    assertEq(DateTime.year(ts1), 2024, "ts1 year")
    assertEq(DateTime.month(ts1), 7, "ts1 month")
    assertEq(DateTime.day(ts1), 15, "ts1 day")
    assertEq(DateTime.hour(ts1), 14, "ts1 hour")
    assertEq(DateTime.minute(ts1), 30, "ts1 minute")
    assertEq(DateTime.second(ts1), 59, "ts1 second")

    // ── leap year ───────────────────────────────────────────
    assertEq(DateTime.isLeapYear(2000), 1, "2000 leap")
    assertEq(DateTime.isLeapYear(2024), 1, "2024 leap")
    assertEq(DateTime.isLeapYear(1900), 0, "1900 not leap")
    assertEq(DateTime.isLeapYear(2023), 0, "2023 not leap")
    assertEq(DateTime.isLeapYear(2100), 0, "2100 not leap")

    // ── daysInMonth ─────────────────────────────────────────
    assertEq(DateTime.daysInMonth(2024, 2), 29, "feb leap")
    assertEq(DateTime.daysInMonth(2023, 2), 28, "feb normal")
    assertEq(DateTime.daysInMonth(2024, 1), 31, "jan")
    assertEq(DateTime.daysInMonth(2024, 4), 30, "apr")
    assertEq(DateTime.daysInMonth(2024, 12), 31, "dec")

    // ── of / ofDate construction ────────────────────────────
    assertEq(DateTime.of(1970, 1, 1, 0, 0, 0), 0, "of epoch")
    assertEq(DateTime.ofDate(1970, 1, 1), 0, "ofDate epoch")
    assertEq(DateTime.ofDate(2000, 1, 1), y2k, "ofDate y2k")

    // round-trip: of → extract
    const ts2 = DateTime.of(2026, 4, 1, 12, 30, 45)
    assertEq(DateTime.year(ts2), 2026, "rt year")
    assertEq(DateTime.month(ts2), 4, "rt month")
    assertEq(DateTime.day(ts2), 1, "rt day")
    assertEq(DateTime.hour(ts2), 12, "rt hour")
    assertEq(DateTime.minute(ts2), 30, "rt minute")
    assertEq(DateTime.second(ts2), 45, "rt second")

    // ── leap day round-trip ─────────────────────────────────
    const leap = DateTime.ofDate(2024, 2, 29)
    assertEq(DateTime.year(leap), 2024, "leap year")
    assertEq(DateTime.month(leap), 2, "leap month")
    assertEq(DateTime.day(leap), 29, "leap day")

    // ── dayOfWeek ───────────────────────────────────────────
    // 2026-04-01 is Wednesday
    const wed = DateTime.ofDate(2026, 4, 1)
    assertEq(DateTime.dayOfWeek(wed), 3, "2026-04-01 is Wed")

    // ── dayOfYear ───────────────────────────────────────────
    const jan31 = DateTime.ofDate(2024, 1, 31)
    assertEq(DateTime.dayOfYear(jan31), 31, "jan31 doy")
    const mar1 = DateTime.ofDate(2024, 3, 1)
    assertEq(DateTime.dayOfYear(mar1), 61, "mar1 leap doy")
    const dec31 = DateTime.ofDate(2024, 12, 31)
    assertEq(DateTime.dayOfYear(dec31), 366, "dec31 leap doy")

    // ── arithmetic ──────────────────────────────────────────
    const base = DateTime.of(2026, 4, 1, 10, 0, 0)
    assertEq(DateTime.second(DateTime.addSeconds(base, 30)), 30, "addSeconds")
    assertEq(DateTime.minute(DateTime.addMinutes(base, 15)), 15, "addMinutes")
    assertEq(DateTime.hour(DateTime.addHours(base, 3)), 13, "addHours")
    assertEq(DateTime.day(DateTime.addDays(base, 5)), 6, "addDays")

    // ── ISO formatting ──────────────────────────────────────
    assertStr(DateTime.toISODate(ts2), "2026-04-01", "toISODate")
    assertStr(DateTime.toISOTime(ts2), "12:30:45", "toISOTime")
    assertStr(DateTime.toISO(ts2), "2026-04-01T12:30:45Z", "toISO")

    // epoch formatting
    assertStr(DateTime.toISODate(0), "1970-01-01", "toISODate epoch")
    assertStr(DateTime.toISOTime(0), "00:00:00", "toISOTime epoch")

    // y2k formatting
    assertStr(DateTime.toISODate(y2k), "2000-01-01", "toISODate y2k")

    // ── ISO parsing ─────────────────────────────────────────
    const p1 = DateTime.parseISODate("2026-04-01")
    assertEq(DateTime.year(p1), 2026, "parseISODate year")
    assertEq(DateTime.month(p1), 4, "parseISODate month")
    assertEq(DateTime.day(p1), 1, "parseISODate day")

    const p2 = DateTime.parseISO("2024-07-15T14:30:59")
    assertEq(DateTime.year(p2), 2024, "parseISO year")
    assertEq(DateTime.month(p2), 7, "parseISO month")
    assertEq(DateTime.day(p2), 15, "parseISO day")
    assertEq(DateTime.hour(p2), 14, "parseISO hour")
    assertEq(DateTime.minute(p2), 30, "parseISO minute")
    assertEq(DateTime.second(p2), 59, "parseISO second")

    // round-trip: format → parse
    const rt = DateTime.parseISO(DateTime.toISO(ts2))
    assertEq(rt, ts2, "format-parse round-trip")

    // ── names ───────────────────────────────────────────────
    assertStr(DateTime.dayName(0), "Sunday", "dayName Sun")
    assertStr(DateTime.dayName(3), "Wednesday", "dayName Wed")
    assertStr(DateTime.dayName(6), "Saturday", "dayName Sat")
    assertStr(DateTime.monthName(1), "January", "monthName Jan")
    assertStr(DateTime.monthName(7), "July", "monthName Jul")
    assertStr(DateTime.monthName(12), "December", "monthName Dec")

    println("all datetime tests passed")
}
