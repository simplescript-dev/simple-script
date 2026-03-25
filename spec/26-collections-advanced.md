# 26 - Collections Advanced (集合进阶)

## 设计理念

> 不可变优先，可变按需。链式操作惰性求值，大数据集不会炸内存。

## 集合类型

| 类型 | 不可变 | 可变 |
|------|--------|------|
| 列表 | `List<T>` | `MutableList<T>` |
| 映射 | `Map<K, V>` | `MutableMap<K, V>` |
| 集合 | `Set<T>` | `MutableSet<T>` |
| 队列 | `Queue<T>` | `MutableQueue<T>` |
| 双端队列 | `Deque<T>` | `MutableDeque<T>` |
| 栈 | `Stack<T>` | — |

## 创建

```simplescript
// 不可变
const list = List.of(1, 2, 3)
const map = Map.of(["a", 1], ["b", 2])
const set = Set.of(1, 2, 3)

// 可变
const list = MutableList.of(1, 2, 3)
const map = MutableMap.of(["a", 1])
const set = MutableSet.of<int>()

// 空集合
const empty = List.empty<int>()

// 从范围创建
const range = List.range(1, 100)

// 生成器
const squares = List.generate(10, (i) => i * i)    // [0, 1, 4, 9, 16, ...]
```

## 链式操作

```simplescript
const users = List.of(
    new User("Alice", 30),
    new User("Bob", 17),
    new User("Charlie", 25),
    new User("Diana", 15)
)

// 过滤 + 转换 + 排序
const result = users
    .filter((u) => u.age >= 18)
    .map((u) => u.name.toUpperCase())
    .sorted()
// ["ALICE", "CHARLIE"]

// 分组
const byAge = users.groupBy((u) => if (u.age >= 18) "adult" else "minor")
// {"adult": [Alice, Charlie], "minor": [Bob, Diana]}

// 聚合
const totalAge = users.sumOf((u) => u.age)          // 87
const oldest = users.maxBy((u) => u.age)             // Alice
const names = users.joinToString(", ", (u) => u.name) // "Alice, Bob, Charlie, Diana"

// 查找
const first = users.first((u) => u.age > 20)        // Alice
const any = users.any((u) => u.age < 18)             // true
const all = users.all((u) => u.age > 0)              // true
```

## 惰性序列 (Sequence)

```simplescript
// 大数据集用 Sequence，惰性求值，不创建中间集合
const result = users.asSequence()
    .filter((u) => u.age >= 18)        // 不执行
    .map((u) => u.name)                // 不执行
    .take(10)                           // 不执行
    .toList()                           // 这里才一次性执行

// 无限序列
const fibs = Sequence.generate([0, 1], (prev) => {
    const [a, b] = prev
    return [b, a + b]
}).map((pair) => pair.first)

const first10 = fibs.take(10).toList()  // [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
```

## Map 操作

```simplescript
const scores = Map.of(["Alice", 95], ["Bob", 87], ["Charlie", 92])

// 访问
const alice = scores["Alice"] ?? 0
const has = scores.containsKey("Alice")       // true

// 转换
const passed = scores
    .filter((k, v) => v >= 90)
    .mapValues((k, v) => if (v >= 95) "A+" else "A")
// {"Alice": "A+", "Charlie": "A"}

// 合并
const more = Map.of(["Diana", 88])
const all = scores.merge(more)

// 解构遍历
for ((name, score) in scores) {
    println(`${name}: ${score}`)
}
```

## 不可变 → 可变转换

```simplescript
const list = List.of(1, 2, 3)
const mutable = list.toMutable()          // 拷贝为可变
mutable.add(4)

const frozen = mutable.toList()          // 冻结为不可变
```
