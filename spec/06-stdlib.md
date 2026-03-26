# 06 - Standard Library

## 设计理念

> 开箱即用，覆盖日常开发 90% 场景。
> 模块命名直觉化，import 即用，不需要翻文档猜包名。

## 标准库模块总览

```
# IO 相关
io/print           println, print, readLine (prelude 自动导入)
io/fs              文件读写、目录操作
io/path            路径操作

# 网络
net/tcp            TCP/UDP Socket
net/http           HTTP 客户端+服务端
net/websocket      WebSocket
net/dns            DNS

# 编码
encoding/json      JSON
encoding/xml       XML
encoding/csv       CSV
encoding/base64    Base64
encoding/toml      TOML

# 加密
crypto/sha         SHA 哈希
crypto/aes         AES 加密
crypto/rsa         RSA
crypto/tls         TLS
crypto/rand        安全随机数

# 压缩
compress/gzip      Gzip
compress/zlib      Zlib

# 系统
os/env             环境变量
os/exec            子进程
os/signal          信号

# 工具
util/time          时间日期
util/math          数学
util/math/rand     随机数
util/strings       字符串工具
util/regex         正则
util/collections   集合 (prelude 自动导入基础类型)
util/concurrent    并发 (Channel, Mutex, Atomic, WaitGroup)

# 开发
dev/test           测试
dev/log            日志
dev/db             数据库接口
```

## Prelude (自动导入)

以下符号无需 import，编译器自动导入：

```
来自 io/print:
  println, print, readLine

来自 util/collections:
  List, MutableList, Map, MutableMap, Set, MutableSet, Queue, Deque, Stack

来自核心类型:
  Result, Error

其他所有模块必须显式 import。
```

## 官方包 (ss/ scope)

```
ss/web          Web 框架 (路由注解、中间件、SSE)
ss/di           依赖注入 (@Service, @Component, @Configuration)
ss/validation   校验 (@Valid, @NotBlank, @Email)
ss/cache        缓存 (@Cacheable, @CacheEvict)
ss/auth         认证鉴权 (@RequiresRole, JWT)
ss/cli          CLI 框架 (@Command, @Arg)
ss/config       配置管理 (@Config, @Value)
ss/schedule     定时任务 (@Scheduled)
ss/trace        链路追踪 (@Traced)
ss/aop          AOP 拦截器
```

## io/print (prelude 自动导入)

```simplescript
// println, print, readLine 无需 import，prelude 自动导入

println("hello")                       // 输出 + 换行
print("name: ")                        // 输出，不换行
const name = readLine()                  // 读取一行输入
println(`hello, ${name}`)
```

## io/fs

```simplescript
import { readFile, writeFile, exists, listDir, mkdir, remove } from "io/fs"

// 读写文件
const content = readFile("data.txt")?
writeFile("output.txt", "hello")?

// 目录操作
if (!exists("logs")) {
    mkdir("logs")?
}

for (file in listDir("src")?) {
    println(file.name)
}

// 追加写入
appendFile("log.txt", `${Time.now()}: event happened\n`)?
```

## net/http

```simplescript
import { HttpClient, HttpServer, Request, Response } from "net/http"

// HTTP 客户端
const client = new HttpClient()
const res = client.get("https://api.example.com/users")?
const users = res.json<List<User>>()?

// POST — 直接传对象，自动序列化为 JSON
const user = new User("Alice", 30)
const res2 = client.post("https://api.example.com/users", user)?

// HTTP 服务器
const server = new HttpServer(port: 8080)

server.get("/hello", (req: Request): Response => {
    return Response.ok("hello world")
})

server.get("/users/:id", (req: Request): Response => {
    const id = req.params["id"]!
    const user = db.findUser(id)?
    return Response.json(user)
})

server.post("/users", (req: Request): Response => {
    const user = req.json<User>()?
    db.saveUser(user)?
    return Response.created(user)
})

server.start()
```

## encoding/json

```simplescript
import { json } from "encoding/json"

// class 自动支持序列化
class User(name: string, age: int)

// 序列化
const user = new User("Alice", 30)
const str = json.encode(user)          // {"name":"Alice","age":30}

// 反序列化
const user2 = json.decode<User>(str)?

// 自定义字段名
class User(
    @Json("user_name") name: string,
    @Json("user_age") age: int
)
```

## util/collections (基础类型 prelude 自动导入)

```simplescript
// List, MutableList, Map, MutableMap, Set, MutableSet 等基础类型无需 import
const names = List.of("Alice", "Bob", "Charlie")     // 不可变
const items = MutableList.of(1, 2, 3)                   // 可变
items.add(4)

// 链式操作
const result = names
    .filter((n) => n.length > 3)
    .map((n) => n.toUpperCase())
    .sorted()

// Map
const scores = Map.of(["Alice", 95], ["Bob", 87])
const aliceScore = scores["Alice"] ?? 0

// Set
const unique = Set.of(1, 2, 3, 2, 1)    // {1, 2, 3}
```

## util/time

```simplescript
import { now, Duration, LocalDate, LocalDateTime, Instant } from "util/time"

const start = now()
doWork()
const elapsed = now() - start
println(`took ${elapsed.millis}ms`)

// 日期
const today = LocalDate.now()
const birthday = LocalDate.of(1995, 3, 15)

// 格式化
println(today.format("yyyy-MM-dd"))

// Duration
const timeout = Duration.seconds(30)
const interval = Duration.minutes(5)
```

## os/exec

```simplescript
import { exec, Command } from "os/exec"

// 简单执行
const output = exec("ls -la")?

// 完整控制
const cmd = new Command("ffmpeg")
    .args("-i", "input.mp4", "-o", "output.mp3")
    .env("PATH", "/usr/local/bin")
    .dir("/tmp")

const result = cmd.run()?
println(`exit code: ${result.code}`)
println(`stdout: ${result.stdout}`)
```

## dev/test

```simplescript
import { test, expect } from "dev/test"

test("addition works", () => {
    expect(1 + 1).toBe(2)
})

test("user creation", () => {
    const user = new User("Alice", 30)
    expect(user.name).toBe("Alice")
    expect(user.age).toBeGreaterThan(0)
})

test("division by zero returns error", () => {
    const result = divide(1.0, 0.0)
    expect(result.isErr()).toBe(true)
})
```

## dev/log

```simplescript
import { log } from "dev/log"

log.debug("detailed info for debugging")
log.info("server started on port 8080")
log.warn("disk usage above 80%")
log.error(`failed to connect: ${err}`)

// 配置
log.setLevel(log.Level.Info)          // 只输出 Info 及以上
log.setFormat("[{time}] {level}: {message}")
```
