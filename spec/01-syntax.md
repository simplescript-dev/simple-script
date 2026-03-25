# 01 - Syntax & Type System

## 基本类型

```simplescript
// 整数
byte                     // 8-bit 有符号
short                    // 16-bit 有符号
int                      // 32-bit 有符号
long                     // 64-bit 有符号

// 无符号整数
ubyte                    // 8-bit 无符号
ushort                   // 16-bit 无符号
uint                     // 32-bit 无符号
ulong                    // 64-bit 无符号

// 浮点
float                    // 32-bit
double                   // 64-bit

// 其他
bool                     // true / false
char                     // Unicode scalar value (4 bytes)
string                   // UTF-8, 引用计数, 不可变
void                     // 无返回值
any                      // 任意类型, 绕过类型检查 (慎用, 仅 FFI 场景)
```

## 变量声明

```simplescript
const name = "SimpleScript"              // 类型推断
let count = 0                        // 类型推断, 可变
const pi: double = 3.14159           // 显式类型标注
const items: List<string> = []       // 显式类型
```

> 编译器自动推断类型。`const` 用于不可变绑定，`let` 用于可变绑定，`const` 也用于顶层常量。

```simplescript
// 顶层常量
const VERSION: string = "1.0.0"
const MAX_RETRY: int = 3
```

**构造参数规则**: class 构造参数默认可变，无需写前缀。`weak` 修饰符保留。

```simplescript
class User(name: string, age: int)
class Node(value: int, weak parent: Node?)
```

## 空安全

```simplescript
const name: string = "hello"         // 非空，永远不会是 null
let nickname: string? = null         // 可空类型

// 安全访问
const len = nickname?.length           // int?
const len2 = nickname?.length ?? 0     // int, 带默认值

// 断言非空 (失败则 panic)
const len3 = nickname!.length
```

## 函数

```simplescript
// 基本函数
function add(a: int, b: int): int {
    return a + b
}

// 表达式函数 (单表达式可省略大括号)
function add(a: int, b: int): int = a + b

// 默认参数 + 命名参数
function greet(name: string, greeting: string = "Hello"): string {
    return `${greeting}, ${name}!`
}
greet("World")                       // "Hello, World!"
greet("World", greeting: "Hi")      // "Hi, World!"

// 无返回值
function log(msg: string) {
    println(msg)
}
```

## 字符串

```simplescript
const name = "world"

// 普通字符串 (无插值)
const plain = "hello, world"

// 模板字符串 (反引号, 支持插值, 来自 TypeScript)
const greeting = `hello, ${name}`
const expr = `1 + 1 = ${1 + 1}`

// 多行模板字符串
const query = `
    SELECT *
    FROM users
    WHERE name = '${name}'
`                                                 // 自动 trim indent
```

## 控制流

```simplescript
// if 是表达式
const max = if (a > b) a else b

// switch 表达式 (JDK 25 风格，箭头 + 模式匹配)
const result = switch (x) {
    case 1 -> "one"
    case 2, 3 -> "few"
    case string s -> `it's a string: ${s}`
    default -> "other"
}

// 模式匹配 + 条件判断
const msg = switch (shape) {
    case Circle c -> {
        if (c.radius > 10) "big circle"
        else `circle r=${c.radius}`
    }
    case Rect r -> `rect ${r.w}x${r.h}`
}

// switch 语句 (多行 case)
switch (code) {
    case 200 -> println("ok")
    case 404 -> {
        log("not found")
        retry()
    }
    default -> panic(`unknown: ${code}`)
}

// for 循环
for (let i = 0; i <= 10; i++) { }   // 0 到 10 (含)
for (let i = 0; i < 10; i++) { }    // 0 到 9
for (item in list) { }              // 迭代器
for ((k, v) in map) { }            // 解构

// while
while (condition) { }
do { } while (condition)
```

## 类与接口

```simplescript
// 类
// new 关键字创建实例
// const p = new Point(1.0, 2.0)
class Point(x: double, y: double) {
    function distanceTo(other: Point): double {
        const dx = this.x - other.x
        const dy = this.y - other.y
        return Math.sqrt(dx * dx + dy * dy)
    }
}

// 所有 class 自动生成 equals, hashCode, toString
class User(name: string, age: int)

const user = new User("Alice", 30)
const older = new User("Alice", 31)

// 接口
interface Drawable {
    function draw()
    function opacity(): double = 1.0    // 默认实现
}

// 实现接口
class Circle(radius: double) : Drawable {
    override function draw() {
        // ...
    }
}

// 继承体系
open class Shape
class Circle(radius: double) : Shape()
class Rect(w: double, h: double) : Shape()

// 配合 switch 进行模式匹配
function area(s: Shape): double = switch (s) {
    case Circle c -> Math.PI * c.radius * c.radius
    case Rect r -> r.w * r.h
    default -> 0.0
}
```

## 枚举

```simplescript
// 简单枚举
enum Color { Red, Green, Blue }

// 关联值枚举
enum Result<T, E> {
    Ok(value: T),
    Err(error: E)
}

// enum 变体直接构造，不需要 new
const success = Result.Ok(42)              // 不是 new Result.Ok(42)
const failure = Result.Err("not found")

// 模式匹配
function handle(r: Result<int, string>) {
    switch (r) {
        case Result.Ok ok -> println(`got ${ok.value}`)
        case Result.Err e -> println(`error: ${e.error}`)
    }
}
```

## 泛型

```simplescript
// 泛型函数
function <T> identity(value: T): T = value

// 泛型类
class Stack<T> {
    let items: List<T> = []

    function push(item: T) { items = items + item }
    function pop(): T? = items.lastOrNull()
}

// 约束
function <T : Comparable<T>> max(a: T, b: T): T {
    return if (a > b) a else b
}

// 多约束
function <T> process(item: T) where T : Serializable, T : Printable {
    // ...
}
```

> 泛型通过单态化 (monomorphization) 实现，零运行时开销。

## 扩展函数

```simplescript
// 不修改原类，扩展方法
function string.reversed(): string {
    // ...
}

const r = "hello".reversed()   // "olleh"

// 扩展属性
const string.lastChar: char
    get() = this[this.length - 1]
```

## 属性 (Properties)

```simplescript
class Temperature {
    let celsius: double = 0.0

    // 计算属性
    const fahrenheit: double
        get() = celsius * 9.0 / 5.0 + 32.0

    // 带 setter
    let kelvin: double
        get() = celsius + 273.15
        set(value) { celsius = value - 273.15 }
}
```

## Builder 模式

```simplescript
// @Builder 注解自动生成 Builder 类，编译器代劳
@Builder
class HttpConfig(
    host: string,
    port: int = 8080,
    maxConnections: int = 100,
    timeout: int = 30000,
    ssl: bool = false
)

// 使用 Builder
const config = HttpConfig.builder()
    .host("localhost")
    .port(3000)
    .ssl(true)
    .build()

// 也可以直接 new（参数少的时候）
const config = new HttpConfig("localhost", port: 3000, ssl: true)

// @Builder 用在任意 class 上
@Builder
class User(
    name: string,
    email: string,
    age: int = 0,
    role: string = "user"
)

const user = User.builder()
    .name("Alice")
    .email("alice@example.com")
    .role("admin")
    .build()
```

## 属性引用

```simplescript
// :: 获取类的属性描述符 (编译期, 用于类型安全的查询、排序等)
class User(name: string, age: int)

// User::name 的类型是 Property<User, string>
// User::age  的类型是 Property<User, int>

// 用于 ORM 查询
const adults = db.query<User>()
    .where(User::age.gte(18))
    .orderBy(User::name.asc())
    .list()

// 用于排序
users.sortBy(User::age)
```

## 类型别名

```simplescript
type UserId = ulong
type Handler = (Request) => Response
type StringMap<V> = Map<string, V>
```

## 箭头函数与高阶函数

```simplescript
// 箭头函数 (来自 TypeScript)
const square = (x: int): int => x * x
const add = (a: int, b: int): int => a + b
const greet = (name: string): string => `hello, ${name}`

// 多行箭头函数
const process = (data: List<int>): int => {
    const filtered = data.filter((x) => x > 0)
    return filtered.sum()
}

// 高阶函数
function map<T, R>(list: List<T>, transform: (T) => R): List<R> {
    // ...
}

// 尾随 Lambda
const numbers = listOf(1, 2, 3)
const doubled = numbers.map((it) => it * 2)
const pairs = numbers.map((n) => [n, n * n])
```

## 模块与导出

```simplescript
// 导出函数 (来自 TypeScript)
export function handleRequest(req: Request): Response {
    // ...
}

// 导出类
export class HttpClient {
    // ...
}

// 导出接口
export interface Logger {
    function log(msg: string)
}

// 导出箭头函数
export const parseJson = (raw: string): Map<string, any> => {
    // ...
}

// 导出常量
export const string VERSION = "1.0.0"

// 导入
import { HttpClient } from "net/http"
import { Logger } from "dev/log"
import { readFile, writeFile } from "io/fs"
import * as json from "encoding/json"          // 命名空间导入
```

## 解构

```simplescript
const (name, age) = user                  // 类解构
const [first, second] = list              // 列表前两个
const (key, value) = entry                // 键值对解构

// 在 for 循环中
for (let i = 0; i < list.size(); i++) {
    const item = list[i]
    println(`${i}: ${item}`)
}
```
