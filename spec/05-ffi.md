# 05 - C Interop (调用 C 库)

## 设计理念

> 直接 import C 头文件，编译器自动生成绑定。程序员不写任何胶水代码。
> 来自 Zig 的 @cImport 思路：编译器内置 C 头文件解析器。

## 用法

```simplescript
// 导入 C 库，就像导入 SimpleScript 包一样
import "sqlite3.h" as sqlite
import "openssl/ssl.h" as ssl
import "curl/curl.h" as curl

// 直接调用，编译器自动处理类型转换
function main() {
    const db = sqlite.sqlite3_open("app.db")
    sqlite.sqlite3_exec(db, "CREATE TABLE users (id INT, name TEXT)")
    sqlite.sqlite3_close(db)
}
```

就这么多。编译器做所有脏活：
- 解析 `.h` 文件，自动生成函数签名
- `string` ↔ `char*` 自动转换
- 链接对应的 `.a` / `.so` 库

## 导出给其他语言

```simplescript
// 加 @Export，其他语言就能像调 C 函数一样调它
@Export
function add(a: int, b: int): int = a + b
```
