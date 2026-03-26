# 48 - Microservice Patterns (微服务模式)

## 设计理念

> 微服务常见模式内置到官方包。不需要自己实现熔断、限流、服务发现。

## 服务注册与发现

```simplescript
import { ServiceRegistry, ServiceDiscovery } from "ss/discovery"

// 注册服务
@Application
class UserServiceApp {
    function main() {
        const app = Application.run<UserServiceApp>()
        app.start(port: 8081)

        ServiceRegistry.register("user-service", "localhost:8081")
    }
}

// 发现服务
@Service
class OrderService(discovery: ServiceDiscovery) {

    function getUser(userId: long): Result<User, Error> {
        const userService = discovery.find("user-service")?
        const client = new HttpClient(baseUrl: userService.url)
        return client.get(`/api/users/${userId}`)?.json<User>()
    }
}
```

## 熔断器

```simplescript
import { CircuitBreaker } from "ss/resilience"

@Service
class PaymentService {

    // 熔断器: 连续 5 次失败后断开，30 秒后半开重试
    @CircuitBreaker(failureThreshold: 5, resetTimeout: 30000)
    function charge(userId: long, amount: double): Result<Receipt, Error> {
        return paymentGateway.charge(userId, amount)
    }
}
```

## 重试

```simplescript
import { Retry } from "ss/resilience"

@Service
class EmailService {

    // 最多重试 3 次，间隔 1 秒
    @Retry(maxAttempts: 3, delay: 1000)
    function send(to: string, subject: string, body: string): Result<void, Error> {
        return smtpClient.send(to, subject, body)
    }
}
```

## 限流

```simplescript
import { RateLimit } from "ss/resilience"

@RestController
class ApiController {

    // 每用户每分钟 100 次
    @RateLimit(max: 100, window: 60, key: "userId")
    @GetMapping("/api/data")
    function getData(): Response {
        // ...
    }
}
```

## 健康检查

```simplescript
import { HealthCheck, Health } from "ss/health"

@Service
class AppHealth : HealthCheck {
    override function check(): Health {
        const dbOk = db.ping()
        const redisOk = redis.ping()

        if (dbOk && redisOk) {
            return Health.up()
        }
        return Health.down("database or redis unreachable")
    }
}

// 自动暴露 GET /health 端点
// { "status": "UP", "components": { "db": "UP", "redis": "UP" } }
```

## 配置中心

```simplescript
import { RemoteConfig } from "ss/config"

// 从远程配置中心拉取配置
@RemoteConfig(source: "consul://localhost:8500/my-app")
class AppConfig(
    @Value("feature.newUI") enableNewUI: bool = false,
    @Value("cache.ttl") cacheTtl: int = 3600
)

// 配置变更自动刷新，无需重启
```

## 链路追踪

```simplescript
import { Traced } from "ss/trace"

@Service
class OrderService(userService: UserService, paymentService: PaymentService) {

    @Traced
    function createOrder(req: CreateOrderRequest): Result<Order, Error> {
        // traceId 自动贯穿整个调用链
        const user = userService.getUser(req.userId)?           // traceId 传递
        const receipt = paymentService.charge(user.id, req.amount)?  // traceId 传递
        return Result.Ok(db.insert(new Order(req)))
    }
}

// 日志自动携带 traceId
// {"traceId":"abc-123","service":"order-service","msg":"creating order"}
// {"traceId":"abc-123","service":"user-service","msg":"fetching user"}
// {"traceId":"abc-123","service":"payment-service","msg":"charging payment"}
```

## 完整微服务示例

```yaml
# application.yml
server:
  port: 8081
  name: user-service

discovery:
  type: consul
  address: localhost:8500

resilience:
  circuitBreaker:
    failureThreshold: 5
    resetTimeout: 30000

tracing:
  enabled: true
  exporter: jaeger
  endpoint: localhost:14268
```
