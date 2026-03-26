# 47 - Event System (事件系统)

## 设计理念

> 解耦组件通信。来自 Spring 的 ApplicationEvent + Node.js 的 EventEmitter。

## 定义事件

```simplescript
import { Event } from "ss/event"

// 事件就是普通 class
class UserCreatedEvent(userId: long, name: string, email: string) : Event
class OrderPaidEvent(orderId: long, amount: double) : Event
class UserDeletedEvent(userId: long) : Event
```

## 发布事件

```simplescript
import { EventBus } from "ss/event"
import { Service } from "ss/di"

@Service
class UserService(db: Database, eventBus: EventBus) {

    function createUser(name: string, email: string): User {
        const user = db.insert(new User(name: name, email: email))

        // 发布事件
        eventBus.publish(new UserCreatedEvent(user.id, name, email))

        return user
    }
}
```

## 监听事件

```simplescript
import { EventListener } from "ss/event"
import { Service } from "ss/di"

@Service
class NotificationService {

    @EventListener
    function onUserCreated(event: UserCreatedEvent) {
        sendWelcomeEmail(event.email, event.name)
    }

    @EventListener
    function onOrderPaid(event: OrderPaidEvent) {
        sendReceipt(event.orderId)
    }
}

@Service
class AuditService {

    // 多个 listener 可以监听同一个事件
    @EventListener
    function onUserCreated(event: UserCreatedEvent) {
        auditLog("user_created", event.userId)
    }

    @EventListener
    function onUserDeleted(event: UserDeletedEvent) {
        auditLog("user_deleted", event.userId)
    }
}
```

## 异步事件

```simplescript
import { AsyncEventListener } from "ss/event"

@Service
class AnalyticsService {

    // 异步处理，不阻塞发布者
    @AsyncEventListener
    function onUserCreated(event: UserCreatedEvent) {
        // 在独立虚拟线程中执行
        trackEvent("signup", event.userId)
        syncToExternalCRM(event)
    }
}
```

## 事件顺序

```simplescript
@Service
class OrderProcessor {

    // 指定优先级，数字越小越先执行
    @EventListener(order: 1)
    function validateOrder(event: OrderCreatedEvent) {
        // 先校验
    }

    @EventListener(order: 2)
    function processPayment(event: OrderCreatedEvent) {
        // 再处理支付
    }

    @EventListener(order: 3)
    function sendNotification(event: OrderCreatedEvent) {
        // 最后通知
    }
}
```
