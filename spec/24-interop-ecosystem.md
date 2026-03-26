# 24 - Ecosystem & Interop (生态与互操作)

## 设计理念

> 不重复造轮子。能调 C 库就直接调，能复用就复用。

## 标准库模块

```
# IO 相关
io/print           println, print, readLine (prelude 自动导入)
io/fs              文件读写、目录操作
io/path            路径操作

# 网络
net/tcp            TCP/UDP Socket
net/http           HTTP 客户端+服务端 (HttpClient, HttpServer, Request, Response)
net/websocket      WebSocket 通信 (WebSocket, WebSocketClient)
net/dns            DNS

# 编码
encoding/json      JSON (@JsonProperty)
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
dev/log            结构化日志 (@Slf4j)
dev/db             数据库通用接口、ORM (@Table, @Id, 查询构建器)
```

## 官方包 (ss/ scope)

```
ss/web          Web 框架 (路由注解、中间件、SSE)，依赖 net/http
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

## C 库生态直接可用

```simplescript
// 直接 import C 头文件，编译器自动绑定
import "sqlite3.h" as sqlite
import "openssl/ssl.h" as ssl
import "curl/curl.h" as curl
import "zlib.h" as zlib
import "pcre2.h" as pcre
import "leveldb/c.h" as leveldb
```

## 数据库驱动

```
db-postgres    PostgreSQL (libpq)
db-mysql       MySQL (libmysqlclient)
db-sqlite      SQLite (libsqlite3)
db-redis       Redis (hiredis)
```

## 包仓库

```
中央仓库: https://pkg.simplescript.dev

命名: username/package
示例:
  web                官方包
  zhangsan/grpc      社区包
  lisi/msgpack       社区包
```

## 发布包

```bash
# 登录
ss login

# 发布
ss publish

# 包的 ss.json
{
  "name": "zhangsan/awesome-lib",
  "version": "1.0.0",
  "target": "lib",
  "license": "MIT",
  "repository": "https://github.com/zhangsan/awesome-lib",
  "keywords": ["util", "string"]
}
```

## 构建为共享库

```bash
# 编译为 .so / .a，给其他语言调用
ss build --target lib-shared        # libmylib.so
ss build --target lib-static        # libmylib.a
```

```simplescript
// 导出函数
@Export
function processData(input: string): string {
    // ...
}

// Python 调用:
// import ctypes
// lib = ctypes.CDLL('./libmylib.so')
// lib.processData(b"hello")
```

## Docker 部署

```dockerfile
# 多阶段构建
FROM simplescript:latest AS builder
WORKDIR /app
COPY . .
RUN ss build --release

# 最终镜像: 只需要二进制，不需要运行时
FROM scratch
COPY --from=builder /app/target/release/my-app /my-app
ENTRYPOINT ["/my-app"]

# 镜像大小 ≈ 二进制大小 ≈ 几 MB
```
