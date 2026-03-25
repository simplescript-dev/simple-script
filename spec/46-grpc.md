# 46 - gRPC & Protocol Buffers

## 设计理念

> gRPC 是微服务通信标准。SimpleScript 原生支持 protobuf，注解声明服务。
> 不需要 .proto 文件和代码生成步骤 — 直接用 SimpleScript class 定义消息。

## 定义服务

```simplescript
import { GrpcService, GrpcMethod, GrpcStream } from "yummy/grpc"

// 消息用普通 class 定义，编译器自动生成 protobuf 序列化
class HelloRequest(name: string)
class HelloReply(message: string)

class User(id: long, name: string, email: string)
class UserListReply(users: List<User>)
class UserRequest(id: long)

// 服务定义
@GrpcService("greeter.GreeterService")
class GreeterService {

    @GrpcMethod
    function sayHello(req: HelloRequest): HelloReply {
        return new HelloReply(`hello, ${req.name}`)
    }

    @GrpcMethod
    function getUser(req: UserRequest): Result<User, Error> {
        const user = db.find<User>(req.id)
        if (user == null) return Result.Err(new Error("not found"))
        return Result.Ok(user)
    }

    @GrpcMethod
    function listUsers(req: EmptyRequest): UserListReply {
        return new UserListReply(db.findAll<User>())
    }
}
```

## 流式 RPC

```simplescript
@GrpcService("chat.ChatService")
class ChatService {

    // 服务端流
    @GrpcStream(type: "server")
    function subscribe(req: SubscribeRequest, stream: ServerStream<Event>) {
        while (!stream.isClosed()) {
            const event = waitForEvent(req.topic)
            stream.send(event)
        }
    }

    // 客户端流
    @GrpcStream(type: "client")
    function upload(stream: ClientStream<Chunk>): UploadResult {
        let totalSize = 0
        for (chunk in stream) {
            totalSize += chunk.data.length
            saveChunk(chunk)
        }
        return new UploadResult(totalSize)
    }

    // 双向流
    @GrpcStream(type: "bidirectional")
    function chat(stream: BidiStream<ChatMessage, ChatMessage>) {
        for (msg in stream.incoming()) {
            const reply = processMessage(msg)
            stream.send(reply)
        }
    }
}
```

## 客户端

```simplescript
import { GrpcClient } from "yummy/grpc"

function main() {
    const client = GrpcClient.connect<GreeterService>("localhost:50051")

    const reply = client.sayHello(new HelloRequest("Alice"))?
    println(reply.message)    // "hello, Alice"

    const user = client.getUser(new UserRequest(1))?
    println(user.name)
}
```

## 启动服务

```simplescript
import { GrpcServer } from "yummy/grpc"

function main() {
    const server = new GrpcServer(port: 50051)
    server.register(new GreeterService())
    server.register(new ChatService())
    server.start()
    println("gRPC server listening on :50051")
}
```
