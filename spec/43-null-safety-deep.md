# 43 - Null Safety Deep Dive (空安全详解)

## 设计理念

> 编译期消除 NullPointerException。来自 TypeScript 的 strict null checks。
> null 是类型系统的一部分，不是所有类型的子类型。

## 非空 vs 可空

```simplescript
// 非空类型 — 永远不会是 null
const name: string = "Alice"
// name = null              // 编译错误!

// 可空类型 — 可能是 null
let nickname: string? = "Bob"
nickname = null              // OK
```

## 安全访问 ?.

```simplescript
const user: User? = findUser(id)

// 安全访问链
const city = user?.address?.city       // string?

// 等价于
const city = if (user != null && user.address != null) user.address.city else null
```

## 默认值 ??

```simplescript
const name = user?.name ?? "anonymous"
const port = config?.port ?? 8080
const list = data?.items ?? List.empty<Item>()
```

## 强制解包 !

```simplescript
// 你确定不是 null 时使用，null 则 panic
const name = user!.name

// 慎用! 尽量用 ?. 或 ?? 替代
```

## 智能类型收窄

```simplescript
const user: User? = findUser(id)

// if 检查后自动收窄为非空
if (user != null) {
    println(user.name)     // 这里 user 是 User，不是 User?
    println(user.age)      // 无需 ?. 或 !
}

// switch 中也能收窄
switch (user) {
    case User u -> println(u.name)     // u 是 User (非空)
    case null -> println("not found")
}

// is 检查
if (user is User) {
    println(user.name)     // 自动收窄
}
```

## 函数返回可空

```simplescript
function findUser(id: long): User? {
    const result = db.query("SELECT * FROM users WHERE id = $1", id)
    if (result.isEmpty()) return null
    return result.first()
}

// 调用者必须处理 null
const user = findUser(123)
// user.name             // 编译错误! user 是 User?
user?.name               // OK, 返回 string?
user?.name ?? "unknown"  // OK, 返回 string
```

## 集合中的 null

```simplescript
// List<string>  — 元素不能是 null
// List<string?> — 元素可以是 null
// List<string>? — 整个 List 可以是 null

const names: List<string> = List.of("Alice", "Bob")
// names.add(null)       // 编译错误!

const names: List<string?> = List.of("Alice", null, "Bob")
for (name in names) {
    println(name ?? "unknown")    // 需要处理 null
}
```

## 平台互操作

```simplescript
// C 函数返回的指针可能是 null
// 编译器自动标记为可空类型
import "sqlite3.h" as sqlite

// sqlite3_errmsg 返回 char*，自动映射为 string?
const msg: string? = sqlite.sqlite3_errmsg(db)
println(msg ?? "no error")
```
