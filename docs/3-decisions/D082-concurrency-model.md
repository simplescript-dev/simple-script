# D082: Concurrency Model (Virtual Threads + Ref)

**Status:** Phase 4+ Done (ref/watch + Thread.start/join + capture analysis + Channel\<T\> + bounded channels)
**Priority:** P1

## Context

SimpleScript 需要并发支持。设计目标：Java 开发者零学习成本，编译器吸收复杂度，RC 保持高性能。

## Decision

三个核心原语，融合 Java 25 虚拟线程 + Vue 3 响应式：

| 原语 | 来源 | 作用 |
|------|------|------|
| `Thread.start(() => {})` | Java 25 Virtual Thread | 启动虚拟线程 |
| `ref(value)` | Vue 3 `ref()` | 线程安全共享状态 |
| `watch(ref, fn)` | Vue 3 `watch()` | 响应式副作用 |

## Syntax

### 虚拟线程

```simplescript
// 启动虚拟线程（M:N 调度，轻量，可创百万级）
const t = Thread.start(() => {
    return fetchUser("123")
})

// 等待结果
const user = t.join()

// fire-and-forget
Thread.start(() => {
    doBackgroundWork()
})
```

对标 Java 25:
```java
Thread.startVirtualThread(() -> { ... });
thread.join();
```

### ref() — 线程安全共享状态

```simplescript
// ref() 是内置函数，返回 Ref<T> 类型
const count = ref(0)            // Ref<int>
const name = ref("alice")       // Ref<string>
const state = ref(new GameState())  // Ref<GameState>

// 通过 .value 读写（自动加锁）
count.value += 1
println(count.value)

// 复杂对象批量修改
state.update((s) => {
    s.score += 10
    s.players.push("alice")
})

// 类型标注
function increment(counter: Ref<int>) {
    counter.value += 1
}
```

### watch() — 响应式

```simplescript
const connections = ref(0)

// 值变了 → 自动触发
watch(connections, (newVal, oldVal) => {
    if (newVal > 1000) {
        alert("连接数过高")
    }
})
```

后端场景：配置热更新、监控告警、状态同步。

### computed()（远期，非核心）

```simplescript
// 自动派生值，依赖变了自动重算
const isOverloaded = computed(() => connections.value > 1000)

// 等价于 watch + ref，语法糖
```

## 线程闭包捕获规则

```simplescript
const count = ref(0)
const config = new Config("localhost")
let age = 25

Thread.start(() => {
    count.value += 1         // OK  Ref<T> → 共享（线程安全）
    println(config.host)     // OK  普通对象 → 自动 clone（线程隔离）
    println(age)             // ERR let 变量不能被线程闭包捕获
})
```

| 捕获的类型 | 行为 | 原因 |
|-----------|------|------|
| 值类型（int/double/bool） | copy | 本身就是值 |
| string | 共享 | 不可变 |
| `Ref<T>` | 共享 | 内部线程安全 |
| 其他对象 | 自动 clone | 保证线程隔离 |
| let 变量 | 编译错误 | 类似 Java effectively final |

## RC 策略

- **普通对象（99%）**：非原子 RC，零额外开销
- **Ref<T> 内部**：原子 RC（仅此类型）
- **自动 clone**：普通对象被线程捕获时 deep clone；PIR 检测 last use 时自动 move（零拷贝）

## ref() 内部实现策略

编译器根据 T 选择最优实现，用户不感知：

| T | 内部实现 | 性能 |
|---|---------|------|
| int / bool | 原子指令（lock-free） | 最快 |
| double | 原子指令（64-bit atomic） | 快 |
| string / 对象 | mutex 保护 | 安全 |

## 运行时架构

M:N 虚拟线程调度器：

- N 个 OS 工作线程（= CPU 核心数）
- M 个虚拟线程映射到 N 个 OS 线程
- 每个虚拟线程独立栈（mmap 分配，初始 ~8KB）
- 阻塞操作（I/O、Channel、锁）自动挂起虚拟线程
- work-stealing 调度，自动负载均衡

### Channel\<T\> — 线程间通信（Phase 4）

```simplescript
// 创建 unbounded channel（无界，默认）
const ch = new Channel<int>()

// 创建 bounded channel（有界，send 满时阻塞）
const bounded = new Channel<int>(10)

// 发送（无界：非阻塞入队；有界：满时阻塞直到有空间。closed 时抛异常）
ch.send(42)

// 接收（阻塞直到有值或 channel closed）
const val = ch.receive()

// 关闭（唤醒所有等待中的 receiver 和 sender）
ch.close()
```

对标 Java BlockingQueue / Go buffered channel。内部实现：

| 组件 | 实现 |
|------|------|
| 队列 | 链表 FIFO（ChanNode: i64 value + ptr next） |
| 同步 | per-channel mutex + cond_recv + cond_send |
| send (unbounded) | lock → enqueue → signal cond_recv → unlock |
| send (bounded) | lock → while count≥cap: wait cond_send → enqueue → signal cond_recv → unlock |
| receive | lock → while empty & !closed: wait cond_recv → dequeue → signal cond_send → unlock |
| close | lock → set flag → broadcast cond_recv + cond_send → unlock |

支持任意类型 T（int/double/string/class 实例），值通过 i64 编码传递。
Bounded channel capacity=0 表示无界（默认），capacity>0 表示有界。

## 不在此决策范围

- `synchronized class`：远期，需要时再设计
- `computed()`：语法糖，可用 watch + ref 替代
- `select` 多路复用：依赖 Channel，远期
- 结构化并发（scope）：远期

## 设计原则

1. **Java 手感**：`Thread.start` / `.join` 对标 Java 25 虚拟线程
2. **Vue 手感**：`ref()` / `.value` / `watch()` 对标 Vue 3 响应式
3. **编译器吸收复杂度**：捕获变量自动 clone/share，用户不需要理解 RC
4. **不加新关键字**：`ref` / `watch` / `computed` 都是内置函数，`Thread` 是内置类
5. **非原子 RC 为主**：只有 `Ref<T>` 内部用原子操作，其余 99% 代码零开销
