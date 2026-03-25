# 35 - Chaining & Fluent API (链式调用与流式 API)

## 设计理念

> SimpleScript 不引入 Kotlin 风格的作用域函数 (let/apply/also/run/takeIf/takeUnless)。
> 这些场景用标准的局部变量、if 判断和方法调用即可，更清晰、更易读。

## 替代方案

### let → 局部变量

```simplescript
// Kotlin 风格 (不采用):
// const length = "hello".let((s) => s.length)

// SimpleScript 方式: 直接用局部变量
const s = "hello"
const length = s.length
```

### apply → 直接调方法 / Builder 模式

```simplescript
// Kotlin 风格 (不采用):
// const server = new HttpServer().apply((s) => { s.port = 8080 })

// SimpleScript 方式: 直接设置属性
const server = new HttpServer()
server.port = 8080
server.maxConnections = 100
server.timeout = Duration.seconds(30)

// 或者用 @Builder 注解
@Builder
class HttpServerConfig(
    port: int = 8080,
    maxConnections: int = 100,
    timeout: int = 30000
)

const config = HttpServerConfig.builder()
    .port(8080)
    .maxConnections(100)
    .build()
```

### also → 直接写代码

```simplescript
// Kotlin 风格 (不采用):
// const user = createUser("Alice").also((u) => audit.log(u.id))

// SimpleScript 方式: 分开写，逻辑清晰
const user = createUser("Alice")
audit.log("user_created", user.id)
```

### takeIf → if 判断

```simplescript
// Kotlin 风格 (不采用):
// const validAge = age.takeIf((a) => a >= 0 && a <= 150)

// SimpleScript 方式: 用 if 表达式
const validAge = if (age >= 0 && age <= 150) age else null
```

## 链式调用

SimpleScript 支持标准的链式方法调用，类似 Java Stream 和 TypeScript Array：

```simplescript
// 集合链式操作
const result = users
    .filter((u) => u.age >= 18)
    .map((u) => u.name.toUpperCase())
    .sorted()
    .joinToString(", ")

// 惰性序列链式
const top5 = data.asSequence()
    .filter((x) => x.isValid())
    .map((x) => x.transform())
    .take(5)
    .toList()

// StringBuilder 链式
const sb = new StringBuilder()
sb.append("hello")
sb.append(" ")
sb.append("world")
const text = sb.toString()
```

## 流式 API 设计

自定义类支持链式调用，只需要方法返回 `this`：

```simplescript
class QueryBuilder {
    let table: string = ""
    let conditions: List<string> = []
    let limit: int = 100

    function from(table: string): QueryBuilder {
        this.table = table
        return this
    }

    function where(condition: string): QueryBuilder {
        conditions = conditions + condition
        return this
    }

    function limit(n: int): QueryBuilder {
        this.limit = n
        return this
    }

    function build(): string {
        const where = if (conditions.isEmpty()) "" else " WHERE " + conditions.joinToString(" AND ")
        return `SELECT * FROM ${table}${where} LIMIT ${limit}`
    }
}

const sql = new QueryBuilder()
    .from("users")
    .where("age > 18")
    .where("active = true")
    .limit(10)
    .build()
```
