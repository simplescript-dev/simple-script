# 27 - Pattern Matching (模式匹配)

## 设计理念

> switch 不只是值匹配，是完整的模式匹配引擎。来自 JDK 25 + Rust 的模式匹配。

## 类型匹配

```simplescript
function describe(obj: any): string = switch (obj) {
    case int i -> `integer: ${i}`
    case string s -> `string: ${s}`
    case List<int> list -> `int list of size ${list.size()}`
    default -> "unknown"
}
```

## 解构匹配

```simplescript
class Point(x: double, y: double)

function classify(p: Point): string = switch (p) {
    case Point(0.0, 0.0) -> "origin"
    case Point(x, 0.0) -> `on x-axis at ${x}`
    case Point(0.0, y) -> `on y-axis at ${y}`
    case Point(x, y) -> `at (${x}, ${y})`
}
```

## 条件判断

```simplescript
// switch case 内用 if 处理条件，不需要 guard 语法
function fizzBuzz(n: int): string {
    if (n % 15 == 0) return "FizzBuzz"
    if (n % 3 == 0) return "Fizz"
    if (n % 5 == 0) return "Buzz"
    return n.toString()
}
```

## 嵌套匹配

```simplescript
open class Expr
class Num(value: double) : Expr()
class Add(left: Expr, right: Expr) : Expr()
class Mul(left: Expr, right: Expr) : Expr()

function eval(expr: Expr): double = switch (expr) {
    case Num(v) -> v
    case Add(left, right) -> eval(left) + eval(right)
    case Mul(left, right) -> eval(left) * eval(right)
    default -> 0.0
}

// 优化: 乘以零
function simplify(expr: Expr): Expr = switch (expr) {
    case Mul(_, Num(0.0)) -> new Num(0.0)
    case Mul(Num(0.0), _) -> new Num(0.0)
    case Mul(a, Num(1.0)) -> simplify(a)
    case Add(a, Num(0.0)) -> simplify(a)
    default -> expr
}
```

## Result 匹配

```simplescript
function handle(result: Result<User, AppError>): Response = switch (result) {
    case Result.Ok(user) -> {
        if (user.age >= 18) Response.ok(user)
        else Response.forbidden("underage")
    }
    case Result.Err(AppError.NotFound(id)) -> Response.notFound(`user ${id} not found`)
    case Result.Err(AppError.Unauthorized(u)) -> Response.unauthorized(`${u} not allowed`)
    case Result.Err(e) -> Response.serverError(e.message())
}
```

## 集合匹配

```simplescript
function describe(list: List<int>): string = switch (list.size()) {
    case 0 -> "empty"
    case 1 -> `single: ${list[0]}`
    case 2 -> `pair: ${list[0]}, ${list[1]}`
    default -> `first: ${list[0]}, remaining: ${list.size() - 1}`
}
```

## 变量声明中的匹配

```simplescript
// 解构
const (name, age) = user
const (x, y) = point
const [first, second] = list
const (key, value) = entry

// Result 解包用 switch
const result = findUser(id)
switch (result) {
    case Result.Ok(user) -> println(`found: ${user.name}`)
    case Result.Err(e) -> println(`error: ${e}`)
}

// 循环接收用 for-in
for (msg in channel) {
    process(msg)
}
```
