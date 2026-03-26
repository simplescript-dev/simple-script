# 64 - Message Queue (消息队列)

## 设计理念

> 注解声明生产者/消费者。支持主流消息队列，API 统一。

## 发送消息

```simplescript
import { MessageSender, Topic } from "ss/mq"
import { Service } from "ss/di"

@Service
class OrderService(db: Database, mq: MessageSender) {

    function createOrder(req: CreateOrderRequest): Result<Order, Error> {
        const order = db.insert(new Order(req))?

        // 发送消息到队列
        mq.send("order.created", new OrderCreatedMessage(
            orderId: order.id,
            userId: req.userId,
            amount: req.amount
        ))

        return Result.Ok(order)
    }
}
```

## 消费消息

```simplescript
import { MessageListener, Payload } from "ss/mq"
import { Service } from "ss/di"

@Service
class PaymentConsumer {

    @MessageListener(topic: "order.created")
    function handleOrderCreated(msg: OrderCreatedMessage) {
        // 自动反序列化，自动确认
        const result = paymentGateway.charge(msg.userId, msg.amount)
        if (result.isErr()) {
            // 处理失败会自动重试 (根据配置)
            panic(`payment failed: ${result}`)
        }
    }
}

@Service
class NotificationConsumer {

    @MessageListener(topic: "order.created")
    function handleOrderCreated(msg: OrderCreatedMessage) {
        sendEmail(msg.userId, `Order #${msg.orderId} confirmed`)
    }
}
```

## 延迟消息

```simplescript
@Service
class ReminderService(mq: MessageSender) {

    function scheduleReminder(userId: long, message: string) {
        // 30 分钟后投递
        mq.sendDelayed("reminders", new ReminderMessage(userId, message),
            delay: Duration.minutes(30))
    }
}
```

## 配置

```yaml
# application.yml
mq:
  type: redis              # redis | kafka | rabbitmq
  redis:
    host: localhost
    port: 6379
  consumer:
    concurrency: 4         # 消费者并发数
    maxRetries: 3           # 最大重试次数
    retryDelay: 5000        # 重试间隔 (ms)
```

## 死信队列

```simplescript
@Service
class DeadLetterHandler {

    // 重试次数用尽后进入死信队列
    @MessageListener(topic: "order.created.dlq")
    function handleDeadLetter(msg: OrderCreatedMessage) {
        log.error(`dead letter: order ${msg.orderId}`)
        alertOps(`Order ${msg.orderId} failed after max retries`)
    }
}
```
