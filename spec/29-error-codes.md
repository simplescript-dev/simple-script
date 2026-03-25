# 29 - Compiler Error Messages (编译器错误信息)

## 设计理念

> 错误信息是给人看的，不是给机器看的。来自 Rust/Elm 的友好错误信息。

## 错误格式

```
error[E001]: type mismatch
  → src/main.ss:12:5
   |
12 |     const name: int = "hello"
   |                       ^^^^^^^
   |                       expected `int`, found `string`
   |
help: change the type to `string`
   |
12 |     const name: string = "hello"
   |                ~~~~~~
```

## 常见错误示例

### 空安全

```
error[E010]: value might be null
  → src/service.ss:8:5
   |
 8 |     const name = user.name
   |                  ^^^^
   |                  `user` is `User?` (nullable)
   |
help: use safe access `?.` or assert non-null `!`
   |
 8 |     const name = user?.name       // returns string?
   |                      ^
 8 |     const name = user!.name       // panics if null
   |                      ^
```

### 未处理的 Result

```
error[E020]: Result not handled
  → src/main.ss:5:5
   |
 5 |     readFile("data.txt")
   |     ^^^^^^^^^^^^^^^^^^^^
   |     this returns `Result<string, IOError>` which must be handled
   |
help: propagate with `?` or handle with `switch`
   |
 5 |     const content = readFile("data.txt")?
   |                                         ^
```

### 线程安全

```
error[E030]: mutable object shared across threads
  → src/main.ss:10:5
   |
 8 |     const list = MutableList.of(1, 2, 3)
   |     --- `list` is mutable
   |
10 |     spawn { list.add(4) }
   |             ^^^^^^^^^^^^
   |             cannot access mutable `list` from another thread
   |
help: use a Channel to communicate, or wrap with Mutex
   |
   |     const ch = new Channel<int>()
   |     spawn { ch.send(4) }
```

### switch 不完整

```
error[E040]: switch is not exhaustive
  → src/main.ss:15:5
   |
15 |     switch (shape) {
16 |         case Shape.Circle c -> ...
17 |     }
   |     ^
   |     missing case: `Shape.Rect`
   |
help: add the missing case or add a `default` branch
   |
17 |         case Shape.Rect r -> ...
```

### SQL 注入检测

```
error[E050]: potential SQL injection
  → src/repo.ss:8:5
   |
 8 |     db.sql<User>("SELECT * FROM users WHERE name = '${name}'")
   |                                                     ^^^^^^^^
   |     string interpolation in SQL query is unsafe
   |
help: use parameterized query
   |
 8 |     db.sql<User>("SELECT * FROM users WHERE name = $1", name)
   |                                                    ^^   ^^^^
```

## 警告

```
warning[W001]: unused variable
  → src/main.ss:3:5
   |
 3 |     const result = compute()
   |           ^^^^^^ `result` is never used
   |
help: prefix with `_` to suppress this warning
   |
 3 |     const _result = compute()

warning[W002]: deprecated API
  → src/service.ss:10:5
   |
10 |     user.getUser(id)
   |          ^^^^^^^
   |          `getUser` is deprecated: use `findById` instead
```

## 编译器 LSP 集成

```
编译器错误直接在 IDE 中显示:
  - 红色波浪线 + 错误描述
  - 鼠标悬停显示完整错误 + help
  - 一键 Quick Fix 应用 help 建议
  - 实时检查，保存即反馈
```
