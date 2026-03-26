# 21 - Middleware & Interceptor (中间件与拦截器)

## 设计理念

> 请求处理管道化。中间件按顺序执行，横切关注点统一处理。

## 内置中间件

```simplescript
import { HttpServer } from "net/http"
import { cors, rateLimit, compress, requestId, timeout } from "ss/web"

const server = new HttpServer(port: 8080)

// 中间件按顺序执行
server.use(requestId())                              // 自动生成 X-Request-Id
server.use(cors(origins: List.of("*")))              // CORS
server.use(compress())                               // Gzip 压缩
server.use(rateLimit(max: 100, window: 60))          // 限流: 每分钟 100 次
server.use(timeout(Duration.seconds(30)))             // 超时
```

## 自定义中间件

```simplescript
import { Middleware, Request, Response, Next } from "ss/web"

// 实现 Middleware 接口
class AuthMiddleware(authService: AuthService) : Middleware {
    override function handle(req: Request, next: Next): Response {
        const token = req.headers["Authorization"]
        if (token == null) {
            return Response.unauthorized("missing token")
        }

        const user = authService.verify(token)?
        req.set("user", user)           // 传递给后续处理
        return next(req)                 // 继续下一个中间件
    }
}

// 注册
server.use(new AuthMiddleware(authService))

// 或者用 lambda 写简单中间件
server.use((req, next) => {
    const start = now()
    const res = next(req)
    log.info(`${req.method} ${req.path} ${res.status} ${now() - start}ms`)
    return res
})
```

## 路由级中间件

```simplescript
// 只对某些路由生效
server.group("/api/admin", (router) => {
    router.use(new AuthMiddleware(authService))      // 只有 /api/admin/* 需要鉴权
    router.get("/users", adminController.listUsers)
    router.delete("/users/:id", adminController.deleteUser)
})

// 公开路由不需要鉴权
server.get("/health", (req) => Response.ok("ok"))
server.get("/api/public/info", (req) => Response.ok(info))
```

## AOP 拦截器 (注解方式)

```simplescript
import { Before, After, Around } from "ss/aop"

// @Before — 方法执行前
@Before("*Service.*")                  // 匹配所有 Service 的所有方法
function logMethodEntry(method: string, args: List<any>) {
    log.debug(`entering ${method}`)
}

// @After — 方法执行后
@After("*Repository.*")
function logMethodExit(method: string, result: any) {
    log.debug(`exiting ${method}`)
}

// @Around — 完整包装
@Around("*Service.create*")
function measurePerformance(proceed: () => any): any {
    const start = now()
    const result = proceed()
    const elapsed = now() - start
    if (elapsed > Duration.seconds(1)) {
        log.warn(`slow method: ${elapsed}ms`)
    }
    return result
}
```
