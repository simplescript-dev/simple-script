# 57 - Middleware Advanced (中间件进阶)

## 请求上下文

```simplescript
import { Request, Response } from "net/http"
import { Context } from "ss/web"

// 中间件可以在 Context 中传递数据
class AuthMiddleware(authService: AuthService) : Middleware {
    override function handle(req: Request, next: Next): Response {
        const token = req.headers["Authorization"]
        if (token == null) return Response.unauthorized("missing token")

        const user = authService.verify(token)?
        Context.set("currentUser", user)     // 存入上下文
        return next(req)
    }
}

// 后续 handler 读取
@RestController
class UserController {
    @GetMapping("/me")
    function me(): Response {
        const user = Context.get<User>("currentUser")!
        return Response.ok(user)
    }
}
```

## 请求/响应拦截

```simplescript
// 记录所有请求的日志中间件
class RequestLogger : Middleware {
    override function handle(req: Request, next: Next): Response {
        const start = Instant.now()

        // 请求前
        log.info(`→ ${req.method} ${req.path}`)

        // 执行后续
        const response = next(req)

        // 响应后
        const elapsed = Duration.between(start, Instant.now())
        log.info(`← ${req.method} ${req.path} ${response.status} ${elapsed.toMillis()}ms`)

        return response
    }
}
```

## 异常兜底

```simplescript
// 全局异常处理中间件
class ErrorHandler : Middleware {
    override function handle(req: Request, next: Next): Response {
        return recover {
            next(req)
        } catch (e: PanicError) {
            log.error(`unhandled error: ${e.message()}`)
            Response.serverError(Map.of(
                ["error", "Internal Server Error"],
                ["message", e.message()]
            ))
        }
    }
}
```

## CORS 详细配置

```simplescript
import { cors, CorsConfig } from "ss/web"

server.use(cors(new CorsConfig(
    origins: List.of("https://example.com", "https://app.example.com"),
    methods: List.of("GET", "POST", "PUT", "DELETE"),
    headers: List.of("Authorization", "Content-Type"),
    maxAge: 86400,
    credentials: true
)))
```

## 请求体大小限制

```simplescript
import { bodyLimit } from "ss/web"

// 全局限制 10MB
server.use(bodyLimit(10 * 1024 * 1024))

// 某个路由单独限制
server.post("/upload", bodyLimit(100 * 1024 * 1024), uploadHandler)
```

## 静态文件服务

```simplescript
import { staticFiles } from "ss/web"

// 服务 public/ 目录下的静态文件
server.use(staticFiles("public", prefix: "/static"))

// 访问: GET /static/css/style.css → public/css/style.css
// 自动设置 Content-Type, Cache-Control
```

## 中间件执行顺序

```
请求进来:
  RequestLogger.before  →  AuthMiddleware  →  ErrorHandler  →  Handler
响应出去:
  RequestLogger.after   ←  AuthMiddleware  ←  ErrorHandler  ←  Handler

注册顺序决定执行顺序:
  server.use(new RequestLogger())     // 1. 最外层
  server.use(new ErrorHandler())      // 2.
  server.use(new AuthMiddleware())    // 3. 最靠近 handler
```
