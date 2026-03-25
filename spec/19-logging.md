# 19 - Logging & Observability (日志与可观测性)

## 设计理念

> @Slf4j 一个注解搞定日志。结构化日志 + 链路追踪，生产级开箱即用。

## 基本用法

```simplescript
import { Slf4j } from "dev/log"

@Slf4j
class UserService {
    function createUser(name: string) {
        log.info(`creating user: ${name}`)
        // ...
        log.debug(`user created, id: ${id}`)
    }
}
```

## 日志级别

```simplescript
log.trace("very detailed")
log.debug("debugging info")
log.info("normal operation")
log.warn("something might be wrong")
log.error(`failed: ${err}`)
```

## 结构化日志

```simplescript
// 输出 JSON 格式，方便 ELK/Grafana 采集
log.info("order created", Map.of(
    ["orderId", order.id],
    ["userId", user.id],
    ["amount", order.amount]
))

// 输出:
// {"time":"2026-03-22T10:00:00Z","level":"INFO","msg":"order created","orderId":123,"userId":456,"amount":99.9}
```

## 配置

```yaml
# application.yml
logging:
  level: info                    # 全局级别
  levels:
    service: debug               # 某个包的级别
    db: warn
  format: json                   # json | text
  output: stdout                 # stdout | file
  file:
    path: logs/app.log
    maxSize: 100MB
    maxFiles: 10
```

## 链路追踪

```simplescript
import { Traced } from "yummy/trace"

@Slf4j
@RestController
class OrderController(orderService: OrderService) {

    @Traced                       // 自动生成 traceId，贯穿整个调用链
    @PostMapping("/orders")
    function create(@RequestBody order: Order): Response {
        log.info("received order")           // 自动带 traceId
        const result = orderService.create(order)?
        return Response.created(result)
    }
}

// 日志输出自动带 traceId:
// {"time":"...","level":"INFO","msg":"received order","traceId":"abc-123"}
// {"time":"...","level":"INFO","msg":"saving to db","traceId":"abc-123"}
// {"time":"...","level":"INFO","msg":"order created","traceId":"abc-123"}
```
