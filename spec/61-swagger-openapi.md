# 61 - Swagger / OpenAPI (API 文档)

## 设计理念

> 编译器从注解和类型信息自动生成 OpenAPI 文档。不需要手写 YAML/JSON。
> 零额外代码，零维护成本。

## 自动生成

```simplescript
// 编译器读取 @RestController 注解，自动生成 OpenAPI spec
// 不需要任何额外注解

@RestController
@RequestMapping("/api/users")
class UserController(userService: UserService) {

    @GetMapping("/:id")
    function getUser(@PathVariable id: long): Response {
        // 编译器自动推断:
        // - 路径参数: id (long)
        // - 返回类型: User (从 Response.ok(user) 推断)
    }

    @PostMapping
    function createUser(@Valid @RequestBody req: CreateUserRequest): Response {
        // 编译器自动推断:
        // - 请求体: CreateUserRequest 的所有字段
        // - 校验规则: @NotBlank, @Email 等
    }
}
```

## 补充描述 (可选)

```simplescript
import { Api, ApiOperation, ApiParam } from "ss/openapi"

@Api(description: "用户管理接口")
@RestController
@RequestMapping("/api/users")
class UserController(userService: UserService) {

    @ApiOperation(summary: "根据 ID 查询用户", description: "返回用户详情，不存在返回 404")
    @GetMapping("/:id")
    function getUser(
        @ApiParam(description: "用户 ID", example: "1")
        @PathVariable id: long
    ): Response {
        const user = userService.findById(id)
        return switch (user) {
            case User u -> Response.ok(u)
            default -> Response.notFound("not found")
        }
    }
}
```

## 访问文档

```bash
# 启动应用后自动暴露:
# GET /swagger-ui            Swagger UI 界面
# GET /openapi.json          OpenAPI JSON spec
# GET /openapi.yml           OpenAPI YAML spec
```

## 配置

```yaml
# application.yml
openapi:
  enabled: true
  title: "My API"
  version: "1.0.0"
  description: "My awesome API"
  contact:
    name: "API Team"
    email: "api@example.com"
  servers:
    - url: "https://api.example.com"
      description: "Production"
    - url: "http://localhost:8080"
      description: "Development"
```

## 生成的 OpenAPI 示例

```yaml
# 编译器自动生成
openapi: "3.0.0"
info:
  title: "My API"
  version: "1.0.0"
paths:
  /api/users/{id}:
    get:
      summary: "根据 ID 查询用户"
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: integer
            format: int64
      responses:
        200:
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/User"
        404:
          description: "not found"
  /api/users:
    post:
      summary: "创建用户"
      requestBody:
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/CreateUserRequest"
      responses:
        201:
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/User"
        400:
          description: "validation error"
components:
  schemas:
    User:
      type: object
      properties:
        id:
          type: integer
        name:
          type: string
        email:
          type: string
    CreateUserRequest:
      type: object
      required: [name, email, password]
      properties:
        name:
          type: string
          minLength: 2
          maxLength: 50
        email:
          type: string
          format: email
        password:
          type: string
          minLength: 8
```
