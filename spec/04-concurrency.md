# 04 - Concurrency

## 设计理念

> 虚拟线程 + Channel。同步写法，自动并发，无 async 传染性。
> 来自 JDK 25 的虚拟线程 + Go 的 goroutine/channel + Kotlin 的结构化并发。
> 运行时内置 M:N 调度器，阻塞操作自动挂起虚拟线程。

## 核心原则

```
1. 没有 async/await — 所有函数都是普通函数
2. 阻塞即挂起 — 运行时自动处理，程序员不感知
3. spawn 创建虚拟线程 — 轻量，可创建百万级
4. channel 通信 — 协程间不共享内存，通过消息传递
```

## 基本用法

```simplescript
// 所有代码都是同步写法，没有 async/await
function fetchUser(id: string): Result<User, HttpError> {
    const response = http.get(`https://api.example.com/users/${id}`)
    const body = response.body()      // 阻塞时自动挂起虚拟线程
    return parseUser(body)
}

function main() {
    const user = fetchUser("123")?
    println(`hello, ${user.name}`)
}
```

## spawn (创建虚拟线程)

```simplescript
// spawn 启动一个虚拟线程，返回 Thread<T>
function main() {
    const t1 = spawn fetchUser("123")
    const t2 = spawn fetchOrders("123")
    const t3 = spawn fetchNotifications("123")

    // join 等待结果
    const user = t1.join()?
    const orders = t2.join()?
    const notifications = t3.join()?

    println(`${user.name} has ${orders.size()} orders`)
}

// spawn 块
spawn {
    const data = loadData()
    process(data)
}
```

## parallel (并行快捷语法)

```simplescript
// 多个任务并行执行，全部完成后返回
const (user, orders, notifications) = parallel {
    fetchUser(userId),
    fetchOrders(userId),
    fetchNotifications(userId)
}

// 对集合并行处理
const users = ids.parallelMap((id) => fetchUser(id))
```

## Channel (通道)

```simplescript
// 来自 Go: 虚拟线程间通过 channel 通信

const ch = new Channel<int>()          // 无缓冲
const ch = new Channel<int>(100)       // 缓冲 100

// 生产者 / 消费者
function producer(ch: Channel<int>) {
    for (let i = 0; i < 100; i++) {
        ch.send(i)             // 缓冲满时自动挂起
    }
    ch.close()
}

function consumer(ch: Channel<int>) {
    for (value in ch) {        // 迭代直到 channel 关闭
        println(`received: ${value}`)
    }
}

function main() {
    const ch = new Channel<int>(10)
    spawn producer(ch)
    spawn consumer(ch)
}
```

## select (多路复用)

```simplescript
// 来自 Go: 同时等待多个 channel
function multiplexer(ch1: Channel<string>, ch2: Channel<string>, quit: Channel<void>) {
    while (true) {
        select {
            case msg1 from ch1 -> println(`ch1: ${msg1}`)
            case msg2 from ch2 -> println(`ch2: ${msg2}`)
            case from quit -> {
                println("shutting down")
                return
            }
        }
    }
}
```

## 结构化并发

```simplescript
// 来自 Kotlin: 虚拟线程有作用域，父线程取消时子线程自动取消
function processData(): Result<Report, Error> {
    const results = scope {
        const a = spawn fetchPartA()
        const b = spawn fetchPartB()
        const c = spawn fetchPartC()

        // 任何一个失败，其余自动取消
        new Results(a.join(), b.join(), c.join())
    }
    return generateReport(results)
}

// 超时控制
function fetchWithTimeout(): Result<Data, Error> {
    return timeout(5000) {       // 5 秒超时，超时自动取消
        fetchData()
    }
}
```

## 线程安全

```simplescript
// 编译器强制线程安全，防止数据竞争

// Mutex — 互斥锁
class Counter {
    private const mutex = new Mutex()
    private let count = 0

    function increment() {
        mutex.lock {              // 块结束自动释放
            count += 1
        }
    }

    function getCount(): int = count
}

// Atomic — 原子操作，无锁
class AtomicCounter {
    private const count = new Atomic<int>(0)

    function increment() {
        count.add(1)
    }

    function getCount(): int = count.load()
}

// 编译器检查: 可变对象不能跨虚拟线程共享
const shared = new ArrayList<int>()
spawn {
    shared.add(1)     // 编译错误! 可变对象不能跨线程直接访问
}

// 正确做法: channel 通信 或 Mutex/Atomic
const ch2 = new Channel<int>()
spawn {
    ch2.send(1)        // 通过 channel 安全传递
}
```

## 运行时调度器

```
M:N 调度模型:
  M 个虚拟线程 映射到 N 个 OS 线程 (N = CPU 核心数)

特性:
  ✓ 虚拟线程栈初始 ~4KB，按需增长
  ✓ 可创建百万级虚拟线程
  ✓ 阻塞 I/O 自动挂起，不占 OS 线程
  ✓ work-stealing 调度，自动负载均衡
  ✓ 抢占式调度，防止单个线程饿死其他线程
```

## 实际示例: HTTP 服务器

```simplescript
import { HttpServer } from "net/http"
import { Request, Response } from "net/http"
import { Database } from "dev/db"

function main() {
    const db = Database.connect("postgres://localhost/mydb")
    const server = new HttpServer(port: 8080)

    // 每个请求自动在独立虚拟线程中处理
    server.get("/users/:id", (req: Request): Response => {
        const id = req.params["id"]!
        const user = db.query("SELECT * FROM users WHERE id = $1", id)?

        switch (user) {
            case User u -> Response.json(u)
            default -> Response.notFound(`user ${id} not found`)
        }
    })

    println("listening on :8080")
    server.start()    // 没有 await，同步写法
}
```
