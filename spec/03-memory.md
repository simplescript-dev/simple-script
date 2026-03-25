# 03 - Memory Management

## 设计理念

> 自动引用计数 (ARC)。无 GC 停顿，确定性释放，程序员无需手动管理内存。
> 来自 Swift 的 ARC + Rust 的所有权思想，但不暴露生命周期标注。
> 只有 class，没有 struct。编译器自动决定栈/堆分配。

## 基本规则

```simplescript
// 1. 每个对象有一个引用计数器
// 2. 赋值/传参 → 计数 +1
// 3. 离开作用域 → 计数 -1
// 4. 计数归零 → 立即释放

function example() {
    const user = new User("Alice", 30)   // 引用计数 = 1
    const copy = user                     // 引用计数 = 2
    process(copy)                         // 函数内 +1, 返回后 -1
}                                         // copy 和 user 离开作用域, 计数归零, 释放
```

## 统一 class 模型

```simplescript
// 所有自定义类型都是 class，编译器自动优化分配策略
class Point(x: double, y: double)
class Color(r: ubyte, g: ubyte, b: ubyte, a: ubyte = 255)
class Node(value: int, next: Node?)

const a = new Point(1.0, 2.0)
const b = new Point(3.0, 4.0)    // 独立对象

const node1 = new Node(1, null)
const node2 = node1             // 共享引用，计数 +1
```

编译器自动判断:

```
小对象 + 不逃逸 → 栈分配，零 ARC 开销 (等效 struct)
大对象 / 共享引用 → 堆分配 + ARC
程序员不需要关心，性能等效手动区分 struct/class
```

## 循环引用与 weak

```simplescript
// 问题: 两个对象互相引用，计数永远不归零
class Parent {
    let child: Child? = null
}

class Child {
    let parent: Parent? = null     // 循环引用！内存泄漏
}

// 解决: weak 引用，不增加计数
class Child {
    weak let parent: Parent? = null   // 弱引用，不阻止释放
}

// weak 引用在目标释放后自动变为 null
const child = new Child()
child.parent?.doSomething()   // 安全访问，可能为 null
```

## 编译器优化

编译器自动应用以下优化，程序员无需关心:

```
1. 逃逸分析 (Escape Analysis)
   → 对象不逃逸出函数时，栈上分配，跳过 ARC

2. Copy-on-Write (COW)
   → 大集合 (List, Map, string) 共享数据，写入时才拷贝

3. 引用计数省略
   → 编译器证明引用唯一时，省略 +1/-1 操作

4. 移动语义推断
   → 最后一次使用自动变为 move，无额外拷贝
```

## 资源管理 (try-with-resources)

```simplescript
// 需要确定性释放的资源实现 Closeable 接口
interface Closeable {
    function close()
}

class FileHandle(path: string) : Closeable {
    override function close() {
        closeNative(this.fd)
    }
}

// try-with-resources, Java 风格, 离开时自动调用 close()
try (const file = new FileHandle("data.txt")) {
    const content = file.readAll()
    process(content)
}   // 自动调用 file.close()

// 多个资源
try (const db = Database.connect(url),
     const tx = db.beginTransaction()) {
    tx.execute("INSERT INTO ...")
    tx.commit()
}   // tx.close() 先调用，然后 db.close()
```

## 内存安全保证

```
编译期保证:
  ✓ 无悬挂指针 — ARC + weak 自动清理
  ✓ 无二次释放 — 编译器跟踪引用计数
  ✓ 无未初始化访问 — 变量必须初始化
  ✓ 无缓冲区溢出 — 数组边界检查 (release 可关闭)
  ✓ 空安全 — 类型系统级别

运行时保证:
  ✓ 确定性释放 — 计数归零立即回收
  ✓ 无 GC 停顿 — 没有全局垃圾收集器
  ✓ 可预测延迟 — 适合实时场景
```
