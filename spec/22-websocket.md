# 22 - WebSocket & Realtime (实时通信)

## 设计理念

> WebSocket 是一等公民。注解声明端点，配合虚拟线程，天然适合长连接。

## 服务端

```simplescript
import { WebSocket, OnOpen, OnMessage, OnClose, OnError } from "net/websocket"

@WebSocket("/ws/chat")
class ChatEndpoint {
    let sessions = MutableList.of<Session>()

    @OnOpen
    function onOpen(session: Session) {
        sessions.add(session)
        log.info(`user connected: ${session.id}`)
    }

    @OnMessage
    function onMessage(session: Session, message: string) {
        // 广播给所有人
        for (s in sessions) {
            s.send(`${session.id}: ${message}`)
        }
    }

    @OnClose
    function onClose(session: Session) {
        sessions.remove(session)
        log.info(`user disconnected: ${session.id}`)
    }

    @OnError
    function onError(session: Session, err: Error) {
        log.error(`websocket error: ${err.message()}`)
    }
}
```

## 客户端

```simplescript
import { WebSocketClient } from "net/websocket"

function main() {
    const ws = WebSocketClient.connect("ws://localhost:8080/ws/chat")?

    // 接收消息 (在虚拟线程中自动处理)
    spawn {
        for (msg in ws.messages()) {
            println(`received: ${msg}`)
        }
    }

    // 发送消息
    ws.send("hello everyone")

    // 关闭
    ws.close()
}
```

## SSE (Server-Sent Events)

```simplescript
import { SSE, SseEmitter } from "ss/web"

@RestController
class NotificationController {

    @GetMapping("/events")
    @SSE
    function events(): SseEmitter {
        const emitter = new SseEmitter()

        spawn {
            while (!emitter.isClosed()) {
                const event = waitForEvent()
                emitter.send(event)
            }
        }

        return emitter
    }
}
```
