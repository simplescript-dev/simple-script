# 66 - Error Handling in Web (Web 错误处理)

## 设计理念

> 统一的错误响应格式。全局异常处理器 + 自定义错误页面。

## 统一错误格式

```json
// 所有错误响应遵循统一格式
{
  "status": 404,
  "error": "Not Found",
  "message": "user 123 not found",
  "path": "/api/users/123",
  "timestamp": "2026-03-22T10:30:00Z",
  "traceId": "abc-123"
}
```

## 全局异常处理器

```simplescript
import { ExceptionHandler, ErrorResponse } from "ss/web"

@ExceptionHandler
class GlobalErrorHandler {

    function handleNotFound(path: string): ErrorResponse {
        return new ErrorResponse(404, "Not Found", `${path} not found`)
    }

    function handleValidation(errors: List<ValidationError>): ErrorResponse {
        return new ErrorResponse(400, "Validation Error",
            errors.map((e) => `${e.field}: ${e.message}`).joinToString(", "))
    }

    function handleUnauthorized(): ErrorResponse {
        return new ErrorResponse(401, "Unauthorized", "please login first")
    }

    function handleInternalError(err: Error): ErrorResponse {
        log.error(`internal error: ${err.message()}`)
        // 生产环境不暴露错误详情
        return new ErrorResponse(500, "Internal Server Error", "something went wrong")
    }
}
```

## Controller 中的错误处理

```simplescript
@RestController
@RequestMapping("/api/users")
class UserController(userService: UserService) {

    @GetMapping("/:id")
    function getUser(@PathVariable id: long): Response {
        const user = userService.findById(id)
        if (user == null) {
            return Response.notFound(`user ${id} not found`)
        }
        return Response.ok(user)
    }

    @PostMapping
    function createUser(@Valid @RequestBody req: CreateUserRequest): Response {
        const result = userService.create(req)
        return switch (result) {
            case Result.Ok ok -> Response.created(ok.value)
            case Result.Err e -> switch (e) {
                case AppError.Duplicate d -> Response.conflict(d.message())
                case AppError.Validation v -> Response.badRequest(v.message())
                default -> Response.serverError(e.message())
            }
        }
    }
}
```

## Response 快捷方法

```simplescript
// 成功
Response.ok(body)                    // 200
Response.created(body)               // 201
Response.noContent()                 // 204

// 重定向
Response.redirect("/new-path")       // 302
Response.permanentRedirect("/new")   // 301

// 客户端错误
Response.badRequest("message")       // 400
Response.unauthorized("message")     // 401
Response.forbidden("message")        // 403
Response.notFound("message")         // 404
Response.conflict("message")         // 409
Response.tooManyRequests("message")  // 429

// 服务端错误
Response.serverError("message")      // 500
Response.serviceUnavailable("msg")   // 503
```

## 自定义 HTML 错误页

```html
<!-- resources/error/404.html -->
<!DOCTYPE html>
<html>
<body>
    <h1>404 - Page Not Found</h1>
    <p>${message}</p>
    <a href="/">Go Home</a>
</body>
</html>
```

```yaml
# application.yml
error:
  pages:
    enabled: true
    path: resources/error    # 404.html, 500.html 等
```
