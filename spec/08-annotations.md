# 08 - Annotations (注解)

## 设计理念

> Spring Boot 最好用的注解，直接变成语言内置特性。
> 编译器原生支持，不需要框架，不需要反射。
> Java 需要 Spring + 反射 + 动态代理才能做的事，SimpleScript 编译期全部搞定。
>
> 优势:
> - 零启动延迟（不需要运行时扫描）
> - 零运行时开销（不需要动态代理）
> - 编译期报错（注解写错直接编译失败，不是运行时才发现）

## Builder 注解

```simplescript
// @Builder 自动生成 Builder 模式，编译器代劳
@Builder
class HttpConfig(
    host: string = "0.0.0.0",
    port: int = 8080,
    workers: int = 4,
    ssl: bool = false
)

const config = HttpConfig.builder()
    .host("localhost")
    .port(3000)
    .ssl(true)
    .build()
```

## 序列化注解 (来自 Jackson)

```simplescript
class User(
    @JsonProperty("user_name") name: string,
    @JsonProperty("user_age") age: int,
    email: string,                              // 字段名一致时不需要注解
    @JsonIgnore password: string,                // 序列化时忽略
    @JsonFormat("yyyy-MM-dd") birthday: LocalDate
)

// 反序列化忽略未知字段
@JsonIgnoreUnknown
class ApiResponse(
    code: int,
    message: string
)
```

## Web 框架注解 (来自 Spring Boot)

```simplescript
@RestController
@RequestMapping("/api/users")
class UserController(userService: UserService) {

    @GetMapping("/:id")
    function getUser(@PathVariable id: string): Response {
        const user = userService.findById(id)?
        return Response.ok(user)
    }

    @GetMapping
    function listUsers(@RequestParam page: int = 1,
                       @RequestParam size: int = 20): Response {
        const users = userService.findAll(page, size)
        return Response.ok(users)
    }

    @PostMapping
    function createUser(@RequestBody user: User): Response {
        const saved = userService.save(user)?
        return Response.created(saved)
    }

    @PutMapping("/:id")
    function updateUser(@PathVariable id: string,
                        @RequestBody user: User): Response {
        const updated = userService.update(id, user)?
        return Response.ok(updated)
    }

    @DeleteMapping("/:id")
    function deleteUser(@PathVariable id: string): Response {
        userService.delete(id)?
        return Response.noContent()
    }
}
```

## 依赖注入注解

```simplescript
// @Service — 业务服务层
@Service
class UserService(db: Database, cache: Cache) {

    function findById(id: string): Result<User, Error> {
        const cached = cache.get<User>("user:${id}")
        if (cached != null) return Result.Ok(cached)

        const user = db.query<User>("SELECT * FROM users WHERE id = $1", id)?
        cache.set(`user:${id}`, user)
        return Result.Ok(user)
    }
}

// @Component — 通用组件
@Component
class EmailSender(config: SmtpConfig) {
    function send(to: string, subject: string, body: string) {
        // ...
    }
}

// @Configuration — 配置类，提供 Bean
@Configuration
class AppConfig {
    function dataSource(): Database {
        return Database.connect("postgres://localhost/mydb")
    }

    function cache(): Cache {
        return new RedisCache("localhost:6379")
    }
}

// 依赖自动注入，不需要手动 new
@Service
class OrderService(db: Database, userService: UserService) {
    // userService 自动注入
}

// 应用入口
@Application
class MyApp {
    function main() {
        const app = Application.run<MyApp>()
        app.start(port: 8080)
    }
}
```

## 中间件 / AOP 注解

```simplescript
// 日志
@Slf4j
class OrderService {
    function createOrder(order: Order): Result<Order, Error> {
        log.info(`creating order: ${order.id}`)
        // ...
    }
}

// 事务
class OrderService(db: Database) {
    @Transactional
    function transfer(from: string, to: string, amount: double): Result<void, Error> {
        db.execute("UPDATE accounts SET balance = balance - $1 WHERE id = $2", amount, from)?
        db.execute("UPDATE accounts SET balance = balance + $1 WHERE id = $2", amount, to)?
        return Result.Ok(())
    }
}

// 缓存
class UserService {
    @Cacheable("users")
    function findById(id: string): Result<User, Error> {
        return db.query<User>("SELECT * FROM users WHERE id = $1", id)
    }

    @CacheEvict("users")
    function deleteById(id: string): Result<void, Error> {
        return db.execute("DELETE FROM users WHERE id = $1", id)
    }
}

// 鉴权
class AdminController {
    @RequiresRole("admin")
    function deleteAllUsers(): Response {
        // ...
    }

    @RequiresPermission("user:read")
    function exportUsers(): Response {
        // ...
    }
}
```

## 校验注解

```simplescript
class CreateUserRequest(
    @NotBlank name: string,
    @Email email: string,
    @Min(0) @Max(150) age: int,
    @Size(min: 8, max: 32) password: string
)

@PostMapping("/users")
function createUser(@Valid @RequestBody req: CreateUserRequest): Response {
    // 校验不通过自动返回 400，不需要手动检查
    const user = userService.create(req)?
    return Response.created(user)
}
```

## 定时任务注解

```simplescript
@Component
class ScheduledTasks {
    @Scheduled(cron: "0 0 * * *")          // 每天零点
    function dailyCleanup() {
        log.info("running daily cleanup")
        // ...
    }

    @Scheduled(fixedRate: 60000)            // 每 60 秒
    function healthCheck() {
        // ...
    }
}
```

## 自定义注解

```simplescript
// 声明注解
annotation class RateLimit(maxRequests: int, seconds: int)

// 使用
class ApiController {
    @RateLimit(maxRequests: 100, seconds: 60)
    @GetMapping("/data")
    function getData(): Response {
        // ...
    }
}
```
