# 02 - Error Handling

## 设计理念

> 无异常。错误是值，必须显式处理。来自 Rust 的 Result + Go 的显式错误 + Swift 的简洁语法。

SimpleScript 没有传统的 try/catch/throw 异常机制。错误通过类型系统强制处理，编译器确保不会遗漏。

注意区分三种语法：
- `Result<T, E>` + `?` — 业务错误处理（本文档）
- `try (resource) { }` — 资源管理，自动调用 close()（见 03-memory.md）
- `recover { } catch` — panic 捕获，仅用于系统边界（见 38-exception-interop.md）

这三者不是传统异常，不存在异常传播链。

## Result 类型

```simplescript
// 标准库内置
enum Result<T, E> {
    Ok(T value),
    Err(E error)
}
```

## 基本用法

```simplescript
function divide(a: double, b: double): Result<double, string> {
    if (b == 0.0) {
        return Result.Err("division by zero")
    }
    return Result.Ok(a / b)
}

// 显式处理
const result = divide(10.0, 3.0)
switch (result) {
    case Result.Ok ok -> println(`result: ${ok.value}`)
    case Result.Err e -> println(`error: ${e.error}`)
}
```

## `?` 操作符 (错误传播)

```simplescript
// ? 自动传播错误，来自 Rust
// 如果是 Err，立即 return Err；如果是 Ok，解包值
function readConfig(path: string): Result<Config, IOError> {
    const content = readFile(path)?          // IOError 自动传播
    const parsed = parseJson(content)?       // 解析失败也传播
    return Result.Ok(Config.from(parsed))
}

// 等价于手写:
function readConfig(path: string): Result<Config, IOError> {
    const contentResult = readFile(path)
    switch (contentResult) {
        case Result.Err e -> return Result.Err(e)
        case Result.Ok ok -> {}
    }
    const content = contentResult.value
    // ...
}
```

## Error 接口

```simplescript
// 标准错误接口
interface Error {
    function message(): string
    function cause(): Error? = null
}

// 自定义错误
class HttpError(code: int, msg: string) : Error {
    override function message(): string = `HTTP ${code}: ${msg}`
}

class ValidationError(field: string, reason: string) : Error {
    override function message(): string = `${field}: ${reason}`
}
```

## 错误类型联合

```simplescript
// 用 class 继承定义一组相关错误
open class AppError : Error {
    override function message(): string = "unknown error"
}
class NotFoundError(id: string) : AppError() {
    override function message(): string = `not found: ${id}`
}
class UnauthorizedError(user: string) : AppError() {
    override function message(): string = `unauthorized: ${user}`
}
class InternalError(cause: Error) : AppError() {
    override function message(): string = `internal: ${cause.message()}`
}

// switch 匹配错误类型
function handleError(e: AppError) {
    switch (e) {
        case NotFoundError nf -> respond(404, nf.message())
        case UnauthorizedError ua -> respond(401, ua.message())
        case InternalError ie -> respond(500, ie.message())
        default -> respond(500, e.message())
    }
}
```

## 解包

```simplescript
const result: Result<int, string> = Result.Ok(42)

// switch 解包 (推荐，最显式)
switch (result) {
    case Result.Ok ok -> println(`got: ${ok.value}`)
    case Result.Err e -> println(`error: ${e.error}`)
}

// ?? 解包带默认值 (和空安全一致)
const value = result ?? 0          // Err 时返回默认值

// ! 强制解包 (Err 时 panic，谨慎使用)
const value2 = result!
```

## panic (不可恢复错误)

```simplescript
// 用于程序 bug，不应该被捕获
function getItem(index: int): Item {
    if (index < 0) {
        panic(`invalid index: ${index}`)
    }
    return items[index]
}

// 断言 (debug 构建生效，release 可选移除)
assert(list.size() > 0, "list must not be empty")
```

## 与空安全的配合

```simplescript
// Result 和可空类型用同一套操作符，语义一致
//   ?   → 传播 (Result 传播 Err, 可空传播 null)
//   ??  → 默认值
//   !   → 强制解包

const user: User? = db.findUser("123")
const name = user?.name ?? "anonymous"

const config = readConfig("app.yml")? // Result 传播
const port = config.port ?? 8080
```
