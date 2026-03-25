# 54 - Date & Time (日期与时间)

## 设计理念

> 来自 Java 的 java.time (JSR-310)，公认最好的日期时间 API。
> 不可变对象，线程安全，时区明确。

## 基本类型

```simplescript
import { Instant, LocalDate, LocalTime, LocalDateTime,
         ZonedDateTime, Duration, Period } from "util/time"

// Instant — 时间戳 (UTC)
const now = Instant.now()                         // 2026-03-22T10:30:00Z
const epoch = now.toEpochMilli()                  // 毫秒时间戳

// LocalDate — 日期 (无时间，无时区)
const today = LocalDate.now()                     // 2026-03-22
const birthday = LocalDate.of(1995, 3, 15)

// LocalTime — 时间 (无日期，无时区)
const time = LocalTime.now()                      // 10:30:45
const noon = LocalTime.of(12, 0, 0)

// LocalDateTime — 日期+时间 (无时区)
const dt = LocalDateTime.now()                    // 2026-03-22T10:30:45
const specific = LocalDateTime.of(2026, 3, 22, 10, 30, 0)

// ZonedDateTime — 带时区的日期时间
const beijing = ZonedDateTime.now("Asia/Shanghai")
const tokyo = ZonedDateTime.now("Asia/Tokyo")
const utc = ZonedDateTime.now("UTC")
```

## 日期操作

```simplescript
const today = LocalDate.now()

// 加减
const tomorrow = today.plusDays(1)
const nextWeek = today.plusWeeks(1)
const nextMonth = today.plusMonths(1)
const lastYear = today.minusYears(1)

// 获取信息
today.year()         // 2026
today.month()        // 3
today.dayOfMonth()   // 22
today.dayOfWeek()    // "SATURDAY"
today.dayOfYear()    // 81

// 比较
today.isAfter(birthday)       // true
today.isBefore(tomorrow)      // true
today.isEqual(LocalDate.of(2026, 3, 22))  // true
```

## Duration 与 Period

```simplescript
// Duration — 精确时间量 (纳秒精度)
const d1 = Duration.seconds(30)
const d2 = Duration.minutes(5)
const d3 = Duration.hours(2)
const d4 = Duration.millis(500)

// 计时
const start = Instant.now()
doWork()
const elapsed = Duration.between(start, Instant.now())
println(`took ${elapsed.toMillis()}ms`)

// Period — 日历时间量 (年月日)
const p1 = Period.days(30)
const p2 = Period.months(3)
const p3 = Period.years(1)

// 两个日期之间
const age = Period.between(birthday, today)
println(`${age.years()} years old`)
```

## 格式化与解析

```simplescript
const dt = LocalDateTime.now()

// 格式化
dt.format("yyyy-MM-dd")                 // "2026-03-22"
dt.format("yyyy-MM-dd HH:mm:ss")        // "2026-03-22 10:30:45"
dt.format("yyyy年MM月dd日")              // "2026年03月22日"
dt.format("HH:mm")                      // "10:30"

// 解析
const date = LocalDate.parse("2026-03-22")
const dateTime = LocalDateTime.parse("2026-03-22T10:30:00")
const custom = LocalDate.parse("22/03/2026", "dd/MM/yyyy")
```

## 时区转换

```simplescript
const beijing = ZonedDateTime.now("Asia/Shanghai")
const newYork = beijing.withZone("America/New_York")
const london = beijing.withZone("Europe/London")

println(`Beijing:  ${beijing.format("HH:mm")}`)    // 18:30
println(`New York: ${newYork.format("HH:mm")}`)     // 05:30
println(`London:   ${london.format("HH:mm")}`)      // 10:30
```

## 实际场景

```simplescript
// 数据库中存储 UTC
const createdAt = Instant.now()

// 显示时转为用户时区
function formatForUser(instant: Instant, timezone: string): string {
    return instant.atZone(timezone).format("yyyy-MM-dd HH:mm:ss")
}

// Token 过期检查
function isExpired(expiry: Instant): bool {
    return Instant.now().isAfter(expiry)
}

// 生成 cron 下次执行时间
function nextMidnight(): Instant {
    return LocalDate.now()
        .plusDays(1)
        .atStartOfDay()
        .atZone("UTC")
        .toInstant()
}
```
