# D039 — DateTime Standard Library Module

**Status:** Accepted
**Depends on:** D035 (static method pattern), D037 (Math builtins)

## Decision

Add `lib/datetime.ss` — a pure SS datetime utility module using the static method pattern. Provides Unix timestamp manipulation: component extraction, construction, formatting, parsing, and arithmetic. No compiler changes required.

## Reasoning

- **Practical value**: Timestamp formatting/parsing is a common need. Current builtins (`timeUnix()`, `timeMs()`) only provide raw timestamps with no way to extract year/month/day or format them.
- **Pure SS**: Uses Howard Hinnant's civil_from_days algorithm (C++20 `<chrono>`) for Gregorian calendar math. No libc struct tm / strftime dependency.
- **Static method pattern**: Follows D035 convention — `class DateTime()` + `DateTime_method()` functions, accessed as `DateTime.method()`.

## Rejected Alternatives

1. **libc wrappers (gmtime_r, strftime)**: Would require new runtime functions in gen_rt_system.ss + bootstrap. Violates pure-SS stdlib preference.
2. **Full java.time API (spec/54-date-time.md)**: Requires class instances (Instant, LocalDate, etc.). Too complex for current phase. The static-method module provides the foundation; full API can layer on top later.
3. **Arbitrary format patterns**: `format(ts, "YYYY-MM-DD")` with full pattern parsing is complex. Provide fixed ISO formatters instead; users compose custom formats from component extraction.

## Interfaces

```simplescript
import { DateTime } from "@/lib/datetime"

// Current time
DateTime.now()          // → unix timestamp (seconds)
DateTime.nowMs()        // → millisecond timestamp

// Component extraction (UTC)
DateTime.year(ts)       // → 1970..2038
DateTime.month(ts)      // → 1..12
DateTime.day(ts)        // → 1..31
DateTime.hour(ts)       // → 0..23
DateTime.minute(ts)     // → 0..59
DateTime.second(ts)     // → 0..59
DateTime.dayOfWeek(ts)  // → 0=Sun..6=Sat
DateTime.dayOfYear(ts)  // → 1..366

// Date info
DateTime.isLeapYear(year)          // → 0 or 1
DateTime.daysInMonth(year, month)  // → 28..31

// Construction (UTC)
DateTime.of(year, month, day, hour, minute, second) // → timestamp
DateTime.ofDate(year, month, day)                    // → timestamp

// Arithmetic
DateTime.addSeconds(ts, n) // → timestamp
DateTime.addMinutes(ts, n) // → timestamp
DateTime.addHours(ts, n)   // → timestamp
DateTime.addDays(ts, n)    // → timestamp

// ISO 8601 formatting
DateTime.toISODate(ts) // → "2026-04-01"
DateTime.toISOTime(ts) // → "12:30:45"
DateTime.toISO(ts)     // → "2026-04-01T12:30:45Z"

// ISO 8601 parsing
DateTime.parseISODate(s) // → timestamp ("2026-04-01")
DateTime.parseISO(s)     // → timestamp ("2026-04-01T12:30:45")

// Names
DateTime.dayName(dow)     // → "Sunday".."Saturday"
DateTime.monthName(month) // → "January".."December"
```

## Tensions

- **i32 range**: Unix timestamps in i32 overflow at 2038-01-19. Acceptable for near-term use. Full i64 support deferred to language-level int type evolution.
- **UTC only**: No timezone support. Would require timezone database (IANA tzdata). Noted as known limitation.

## Algorithm

Howard Hinnant's `civil_from_days` (public domain, used in C++20 `<chrono>`):
- Shifts epoch to 0000-03-01 to simplify leap year handling
- Uses era-based decomposition (400-year cycles)
- Pure integer arithmetic, no floating point
