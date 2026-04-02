// SimpleScript DateTime Library — Unix timestamp utilities (UTC)
//
// Usage:
//   import { DateTime } from "@/lib/datetime"
//   const ts = DateTime.now()
//   println(DateTime.toISO(ts))           → "2026-04-01T12:30:45Z"
//   println(DateTime.year(ts))            → 2026
//   const ts2 = DateTime.of(2026, 4, 1, 0, 0, 0)
//   println(DateTime.toISODate(ts2))      → "2026-04-01"
//
// Algorithm: Howard Hinnant's civil_from_days (C++20 <chrono>)
// Limitation: i32 timestamps valid through 2038-01-19. UTC only.

class DateTime {}

// ── helpers (internal) ───────────────────────────────────────

function dtPad2(n: int): string {
    if (n < 10) {
        return `0${n}`
    }
    return `${n}`
}

function dtPad4(n: int): string {
    if (n < 10) {
        return `000${n}`
    }
    if (n < 100) {
        return `00${n}`
    }
    if (n < 1000) {
        return `0${n}`
    }
    return `${n}`
}

// civil_from_days: days since epoch → (year, month, day)
// Returns encoded as year*10000 + month*100 + day for single-value return
function dtCivil(daysSinceEpoch: int): int {
    const z = daysSinceEpoch + 719468
    const era = z / 146097
    const doe = z - era * 146097
    const yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    const y = yoe + era * 400
    const doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    const mp = (5 * doy + 2) / 153
    const d = doy - (153 * mp + 2) / 5 + 1
    let m = mp + 3
    if (mp >= 10) {
        m = mp - 9
    }
    let yr = y
    if (m <= 2) {
        yr = y + 1
    }
    return yr * 10000 + m * 100 + d
}

// days_from_civil: (year, month, day) → days since epoch
function dtDaysFromCivil(year: int, month: int, day: int): int {
    let y = year
    if (month <= 2) {
        y = y - 1
    }
    const era = y / 400
    const yoe = y - era * 400
    let mp = month - 3
    if (month <= 2) {
        mp = month + 9
    }
    const doy = (153 * mp + 2) / 5 + day - 1
    const doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

// ── now ──────────────────────────────────────────────────────

function DateTime_now(): int {
    return timeUnix()
}

function DateTime_nowMs(): int {
    return timeMs()
}

// ── component extraction (UTC) ───────────────────────────────

function DateTime_year(ts: int): int {
    const days = ts / 86400
    const civil = dtCivil(days)
    return civil / 10000
}

function DateTime_month(ts: int): int {
    const days = ts / 86400
    const civil = dtCivil(days)
    return (civil / 100) % 100
}

function DateTime_day(ts: int): int {
    const days = ts / 86400
    const civil = dtCivil(days)
    return civil % 100
}

function DateTime_hour(ts: int): int {
    const rem = ts % 86400
    return rem / 3600
}

function DateTime_minute(ts: int): int {
    const rem = ts % 3600
    return rem / 60
}

function DateTime_second(ts: int): int {
    return ts % 60
}

function DateTime_dayOfWeek(ts: int): int {
    // 1970-01-01 was Thursday (4). Days since epoch mod 7, shifted.
    const days = ts / 86400
    let dow = (days + 4) % 7
    if (dow < 0) {
        dow = dow + 7
    }
    return dow
}

function DateTime_dayOfYear(ts: int): int {
    const days = ts / 86400
    const civil = dtCivil(days)
    const year = civil / 10000
    const jan1 = dtDaysFromCivil(year, 1, 1)
    return days - jan1 + 1
}

// ── date info ────────────────────────────────────────────────

function DateTime_isLeapYear(year: int): int {
    if (year % 4 != 0) { return 0 }
    if (year % 100 != 0) { return 1 }
    if (year % 400 != 0) { return 0 }
    return 1
}

function DateTime_daysInMonth(year: int, month: int): int {
    if (month == 2) {
        if (DateTime_isLeapYear(year) == 1) { return 29 }
        return 28
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
        return 30
    }
    return 31
}

// ── construction (UTC) ───────────────────────────────────────

function DateTime_of(year: int, month: int, day: int, hour: int, minute: int, second: int): int {
    const days = dtDaysFromCivil(year, month, day)
    return days * 86400 + hour * 3600 + minute * 60 + second
}

function DateTime_ofDate(year: int, month: int, day: int): int {
    return dtDaysFromCivil(year, month, day) * 86400
}

// ── arithmetic ───────────────────────────────────────────────

function DateTime_addSeconds(ts: int, n: int): int {
    return ts + n
}

function DateTime_addMinutes(ts: int, n: int): int {
    return ts + n * 60
}

function DateTime_addHours(ts: int, n: int): int {
    return ts + n * 3600
}

function DateTime_addDays(ts: int, n: int): int {
    return ts + n * 86400
}

// ── ISO 8601 formatting ─────────────────────────────────────

function DateTime_toISODate(ts: int): string {
    const days = ts / 86400
    const civil = dtCivil(days)
    const y = civil / 10000
    const m = (civil / 100) % 100
    const d = civil % 100
    return `${dtPad4(y)}-${dtPad2(m)}-${dtPad2(d)}`
}

function DateTime_toISOTime(ts: int): string {
    const rem = ts % 86400
    const h = rem / 3600
    const m = (rem % 3600) / 60
    const s = rem % 60
    return `${dtPad2(h)}:${dtPad2(m)}:${dtPad2(s)}`
}

function DateTime_toISO(ts: int): string {
    return `${DateTime_toISODate(ts)}T${DateTime_toISOTime(ts)}Z`
}

// ── ISO 8601 parsing ─────────────────────────────────────────

function DateTime_parseISODate(s: string): int {
    // "YYYY-MM-DD"
    const year = parseInt(s.substring(0, 4))
    const month = parseInt(s.substring(5, 2))
    const day = parseInt(s.substring(8, 2))
    return dtDaysFromCivil(year, month, day) * 86400
}

function DateTime_parseISO(s: string): int {
    // "YYYY-MM-DDTHH:mm:ss" or "YYYY-MM-DDTHH:mm:ssZ"
    const year = parseInt(s.substring(0, 4))
    const month = parseInt(s.substring(5, 2))
    const day = parseInt(s.substring(8, 2))
    const hour = parseInt(s.substring(11, 2))
    const minute = parseInt(s.substring(14, 2))
    const second = parseInt(s.substring(17, 2))
    const days = dtDaysFromCivil(year, month, day)
    return days * 86400 + hour * 3600 + minute * 60 + second
}

// ── names ────────────────────────────────────────────────────

function DateTime_dayName(dow: int): string {
    if (dow == 0) { return "Sunday" }
    if (dow == 1) { return "Monday" }
    if (dow == 2) { return "Tuesday" }
    if (dow == 3) { return "Wednesday" }
    if (dow == 4) { return "Thursday" }
    if (dow == 5) { return "Friday" }
    return "Saturday"
}

function DateTime_monthName(month: int): string {
    if (month == 1) { return "January" }
    if (month == 2) { return "February" }
    if (month == 3) { return "March" }
    if (month == 4) { return "April" }
    if (month == 5) { return "May" }
    if (month == 6) { return "June" }
    if (month == 7) { return "July" }
    if (month == 8) { return "August" }
    if (month == 9) { return "September" }
    if (month == 10) { return "October" }
    if (month == 11) { return "November" }
    return "December"
}
