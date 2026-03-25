# 36 - Destructuring (解构)

## 设计理念

> 从复合数据中提取字段，减少临时变量。来自 JS/Kotlin/Rust 的解构语法。

## 类解构

```simplescript
class User(name: string, age: int, email: string)

const user = new User("Alice", 30, "alice@example.com")

// 解构所有字段
const (name, age, email) = user

// 只解构需要的，用 _ 跳过
const (name, _, email) = user

// 在 for 循环中
const users = List.of(
    new User("Alice", 30, "a@mail.com"),
    new User("Bob", 25, "b@mail.com")
)
for ((name, age, _) in users) {
    println(`${name} is ${age}`)
}
```

## List 解构

```simplescript
const list = List.of(1, 2, 3, 4, 5)

// 取前几个
const first = list[0]
const second = list[1]

// 取子列表
const tail = list.subList(1, list.size())     // [2,3,4,5]
const middle = list.subList(1, list.size() - 1) // [2,3,4]
```

## Map 解构

```simplescript
const scores = Map.of(["math", 95], ["english", 87])

for ((subject, score) in scores) {
    println(`${subject}: ${score}`)
}
```

## Pair / Triple 解构

```simplescript
const pair: [string, int] = ["Alice", 30]
const [name, age] = pair

function minMax(list: List<int>): [int, int] {
    return [list.min()!, list.max()!]
}

const (min, max) = minMax(List.of(3, 1, 4, 1, 5))
println(`min=${min}, max=${max}`)      // min=1, max=5
```

## 函数参数解构

```simplescript
// 直接在参数中解构
function greet((name, age): User) {
    println(`hello ${name}, you are ${age}`)
}

// Lambda 参数解构
users.forEach(((name, age, _)) => {
    println(`${name}: ${age}`)
})
```

## 嵌套解构

```simplescript
class Address(city: string, zip: string)
class Person(name: string, address: Address)

const person = new Person("Alice", new Address("Beijing", "100000"))

// 嵌套解构
const (name, (city, zip)) = person
println(`${name} lives in ${city}`)    // Alice lives in Beijing
```

## switch 中的解构

```simplescript
function describe(point: Pair<int, int>): string = switch (point) {
    case (0, 0) -> "origin"
    case (x, 0) -> `on x-axis at ${x}`
    case (0, y) -> `on y-axis at ${y}`
    case (x, y) -> `at (${x}, ${y})`
}
```

## 变量交换

```simplescript
let a = 1
let b = 2
(a, b) = (b, a)       // a=2, b=1
```
