# 45 - Coding Conventions (编码规范)

## 设计理念

> 唯一风格，无争议。`ym fmt` 自动格式化，不需要讨论代码风格。

## 命名规范

```
类型名:       PascalCase     class UserService, interface Drawable, enum Color
函数名:       camelCase      function getUserById(), function isValid()
变量名:       camelCase      const userName, let itemCount
常量:         UPPER_SNAKE    const MAX_RETRY = 3, const API_URL = "..."
文件名:       snake_case     user_service.ss, http_client.ss
包名:         snake_case     net/http, encoding/json
泛型参数:     单大写字母      T, K, V, E
```

## 缩进与格式

```
缩进:         4 空格 (不用 tab)
行宽:         120 字符
大括号:       同行 (Java 风格)
分号:         不需要
尾逗号:       允许
```

```simplescript
// 正确
class User(name: string, age: int) {
    function greet(): string {
        return `hello, ${name}`
    }
}

// 错误 — 大括号换行
class User(name: string, age: int)
{
    // ...
}
```

## import 顺序

```simplescript
// 1. 标准库
import { HttpServer, Request, Response } from "net/http"
import { readFile } from "io/fs"

// 2. 官方包
import { RestController, GetMapping } from "yummy/web"
import { Service } from "yummy/di"

// 3. 第三方包
import { Redis } from "zhangsan/redis"

// 4. 本项目
import { UserService } from "./service/user_service"
import { User } from "./model/user"
```

## 函数风格

```simplescript
// 短函数用表达式
function isAdult(age: int): bool = age >= 18
function greet(name: string): string = `hello, ${name}`

// 长函数用代码块
function processOrder(order: Order): Result<Receipt, Error> {
    const user = findUser(order.userId)?
    const payment = chargePayment(user, order.amount)?
    const receipt = generateReceipt(order, payment)
    return Result.Ok(receipt)
}
```

## class 风格

```simplescript
// 短 class 一行
class Point(x: double, y: double)
class Color(r: ubyte, g: ubyte, b: ubyte)

// 参数多时换行
class HttpConfig(
    host: string = "0.0.0.0",
    port: int = 8080,
    maxConnections: int = 100,
    timeout: int = 30000
)

// 成员顺序: 常量 → 变量 → 构造相关 → 公开方法 → 内部方法
export class UserService(db: Database) {
    const MAX_PAGE_SIZE = 100

    let cache: Map<long, User> = Map.of()

    export function findById(id: long): User? {
        return cache[id] ?? db.find<User>(id)
    }

    export function findAll(page: int, size: int): List<User> {
        const safeSize = if (size > MAX_PAGE_SIZE) MAX_PAGE_SIZE else size
        return db.query<User>().page(page, safeSize)
    }

    function refreshCache() {
        // internal implementation
    }
}
```

## 注释风格

```simplescript
// 单行注释

/*
 * 多行注释
 */

/// 文档注释 — 用于生成 API 文档
/// @param name 用户名
/// @return 问候语
function greet(name: string): string {
    return `hello, ${name}`
}
```

## ym fmt

```bash
# 格式化单个文件
ym fmt src/main.ss

# 格式化整个项目
ym fmt

# 检查但不修改 (CI 用)
ym fmt --check
```

`ym fmt` 的风格不可配置。一个项目、一种风格、零争议。
