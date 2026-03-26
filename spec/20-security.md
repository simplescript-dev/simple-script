# 20 - Security (安全)

## 设计理念

> 编译期消除常见安全漏洞。安全不是可选项，是语言默认行为。

## 编译期安全

```
✓ SQL 注入 — 参数化查询是唯一方式，字符串拼接 SQL 编译报错
✓ 空指针 — 类型系统级别空安全 (T / T?)
✓ 缓冲区溢出 — 数组边界检查
✓ 内存安全 — ARC 自动管理，无悬挂指针
✓ 数据竞争 — 可变对象不能跨线程共享
✓ 类型安全 — 强类型，无隐式转换
```

## SQL 注入防护

```simplescript
// 正确: 参数化查询
const users = db.sql<User>("SELECT * FROM users WHERE name = $1", name)

// 编译错误: 检测到字符串拼接 SQL
const users = db.sql<User>("SELECT * FROM users WHERE name = '${name}'")
//                                                              ^^^^^^
// error: SQL injection risk - use parameterized query instead
```

## 鉴权注解

```simplescript
import { RequiresRole, RequiresPermission, Authenticated } from "ss/auth"

@RestController
class AdminController {

    @Authenticated                                  // 需要登录
    @GetMapping("/profile")
    function profile(): Response { }

    @RequiresRole("admin")                          // 需要 admin 角色
    @DeleteMapping("/users/:id")
    function deleteUser(@PathVariable id: long): Response { }

    @RequiresPermission("report:export")            // 需要指定权限
    @GetMapping("/reports/export")
    function exportReport(): Response { }
}
```

## 加密

```simplescript
import { hash, verify } from "crypto/sha"
import { encrypt, decrypt } from "crypto/aes"
import { randomBytes } from "crypto/rand"

// 密码哈希 (bcrypt)
const hashed = hash.bcrypt("mypassword")
const ok = verify.bcrypt("mypassword", hashed)     // true

// AES 加密
const key = randomBytes(32)
const encrypted = encrypt.aes(data, key)
const decrypted = decrypt.aes(encrypted, key)

// SHA 哈希
const digest = hash.sha256("hello")

// JWT
import { Jwt } from "ss/auth"

const token = Jwt.sign(Map.of(["userId", 123]), secret, expiry: Duration.hours(24))
const claims = Jwt.verify(token, secret)?
```

## HTTPS

```simplescript
// 服务器默认支持 TLS
const server = new HttpServer(
    port: 443,
    tls: TlsConfig(
        cert: "cert.pem",
        key: "key.pem"
    )
)
```

## 环境变量敏感信息

```simplescript
import { Secret } from "ss/config"

@Config("database")
class DatabaseConfig(
    driver: string,
    @Secret url: string          // @Secret: 日志中自动脱敏，不会打印明文
)

// log 输出: database.url = ******
```
