# 17 - Testing (测试)

## 设计理念

> 内置测试框架，不需要第三方库。来自 Jest 的简洁 API + Go 的内置测试。

## 基本测试

```simplescript
import { test, expect } from "dev/test"

test("1 + 1 = 2", () => {
    expect(1 + 1).toBe(2)
})

test("string contains", () => {
    const greeting = "hello world"
    expect(greeting).toContain("world")
})

test("list operations", () => {
    const list = List.of(1, 2, 3)
    expect(list.size()).toBe(3)
    expect(list).toContain(2)
})
```

## 断言 API

```simplescript
expect(value).toBe(expected)              // == 比较
expect(value).toEqual(expected)            // 深度比较
expect(value).toBeNull()
expect(value).toBeNotNull()
expect(value).toBeTrue()
expect(value).toBeFalse()
expect(value).toBeGreaterThan(n)
expect(value).toBeLessThan(n)
expect(value).toContain(item)
expect(value).toMatch(regex)
expect(value).toThrow()                   // panic
expect(value).toBeInstanceOf<Type>()
```

## 生命周期

```simplescript
import { test, expect, beforeAll, afterAll, beforeEach, afterEach } from "dev/test"

let db: Database

beforeAll(() => {
    db = Database.connect("file::memory:")
    db.autoMigrate()
})

afterAll(() => {
    db.close()
})

beforeEach(() => {
    db.execute("DELETE FROM users")
})

test("insert user", () => {
    db.insert(new User(name: "Alice", age: 30))
    const count = db.query<User>().count()
    expect(count).toBe(1)
})
```

## 分组

```simplescript
import { describe, test, expect } from "dev/test"

describe("UserService", () => {

    describe("findById", () => {
        test("returns user when exists", () => {
            // ...
        })

        test("returns null when not found", () => {
            // ...
        })
    })

    describe("create", () => {
        test("saves user to database", () => {
            // ...
        })

        test("validates name is not blank", () => {
            // ...
        })
    })
})
```

## Mock

```simplescript
import { test, expect, mock } from "dev/test"

test("send welcome email on registration", () => {
    const emailSender = mock<EmailSender>()
    const service = new UserService(db, emailSender)

    service.register("Alice", "alice@example.com")

    expect(emailSender.send).toHaveBeenCalledWith(
        "alice@example.com",
        "Welcome",
        "Hello Alice!"
    )
})

test("mock return value", () => {
    const cache = mock<Cache>()
    cache.get.returns("cached value")

    const result = cache.get("key")
    expect(result).toBe("cached value")
})
```

## 基准测试

```simplescript
import { bench } from "dev/test"

bench("list sort 10000 items", () => {
    const list = MutableList.of<int>()
    for (let i = 0; i < 10000; i++) {
        list.add((Math.random() * 10000).toInt())
    }
    list.sort()
})

bench("map lookup", () => {
    const map = Map.of(["key", "value"])
    for (let i = 0; i < 100000; i++) {
        map["key"]
    }
})
```

```bash
$ ym bench
list sort 10000 items ... 2.34 ms/iter (±0.12)
map lookup            ... 0.85 ns/iter (±0.03)
```

## 运行

```bash
ym test                        # 全部
ym test user                   # 匹配 "user"
ym test --coverage             # 覆盖率
ym test --watch                # 文件改动自动重跑
ym bench                       # 基准测试
```
