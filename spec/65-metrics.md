# 65 - Metrics & Monitoring (指标与监控)

## 设计理念

> 应用指标内置采集，Prometheus 格式导出。来自 Spring Actuator + Micrometer。

## 自动指标

```simplescript
// @RestController 自动采集:
//   http_requests_total{method, path, status}
//   http_request_duration_seconds{method, path}
//
// Database 自动采集:
//   db_query_total{operation}
//   db_query_duration_seconds{operation}
//   db_pool_active_connections
//   db_pool_idle_connections
//
// JVM/Runtime 自动采集:
//   process_cpu_usage
//   process_memory_bytes
//   process_threads_count
//   process_uptime_seconds
```

## 访问指标

```bash
# 自动暴露 Prometheus 格式
GET /metrics

# 输出:
# http_requests_total{method="GET",path="/api/users",status="200"} 1523
# http_request_duration_seconds{method="GET",path="/api/users"} 0.012
# db_pool_active_connections 5
# process_memory_bytes 52428800
```

## 自定义指标

```simplescript
import { Counter, Gauge, Histogram, Timer } from "yummy/metrics"
import { Service } from "yummy/di"

@Service
class OrderService(db: Database) {

    // 计数器
    const orderCounter = Counter.create("orders_total", "Total orders created")

    // 仪表盘 (可增可减)
    const activeOrders = Gauge.create("orders_active", "Active orders count")

    // 直方图 (分布)
    const orderAmount = Histogram.create("order_amount", "Order amounts",
        buckets: List.of(10.0, 50.0, 100.0, 500.0, 1000.0))

    function createOrder(req: CreateOrderRequest): Result<Order, Error> {
        const order = db.insert(new Order(req))?

        orderCounter.increment()
        activeOrders.increment()
        orderAmount.observe(order.amount)

        return Result.Ok(order)
    }

    function completeOrder(id: long): Result<void, Error> {
        db.execute("UPDATE orders SET status = 'done' WHERE id = $1", id)?
        activeOrders.decrement()
        return Result.Ok(())
    }
}
```

## 计时

```simplescript
import { Timer } from "yummy/metrics"

@Service
class ExternalApiClient {

    const apiTimer = Timer.create("external_api_duration", "External API call duration")

    function callExternalApi(url: string): Result<string, Error> {
        return apiTimer.record(() => {
            const response = httpClient.get(url)?
            return Result.Ok(response.body())
        })
    }
}
```

## 健康检查端点

```bash
# 自动暴露
GET /health

# 输出:
# {
#   "status": "UP",
#   "components": {
#     "database": { "status": "UP", "details": { "pool": "5/20" } },
#     "redis": { "status": "UP" },
#     "diskSpace": { "status": "UP", "details": { "free": "50GB" } }
#   }
# }
```

## 配置

```yaml
# application.yml
metrics:
  enabled: true
  endpoint: /metrics
  tags:
    app: my-service
    env: production

health:
  enabled: true
  endpoint: /health
  showDetails: true
```

## Grafana Dashboard

```
内置 Grafana Dashboard JSON:
  ym metrics dashboard > grafana.json

包含面板:
  - HTTP 请求率与延迟
  - 错误率
  - 数据库连接池状态
  - 内存与 CPU 使用率
  - 自定义业务指标
```
