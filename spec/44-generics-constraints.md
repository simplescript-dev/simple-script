# 44 - Generic Constraints (泛型约束)

## 设计理念

> 泛型约束用接口表达。编译器在编译期检查，运行时零开销（单态化）。

## 单约束

```simplescript
function <T : Comparable<T>> max(a: T, b: T): T {
    return if (a > b) a else b
}

// 使用
max(1, 2)          // T = int, int 实现了 Comparable<int>
max("a", "b")      // T = string
// max(user1, user2) // 编译错误! User 没实现 Comparable
```

## 多约束

```simplescript
function <T> process(item: T): string
    where T : Serializable, T : Printable
{
    return item.toJson()
}
```

## 常用约束接口

```simplescript
// 标准库提供的约束接口
interface Comparable<T> {
    function compareTo(other: T): int
}

interface Equatable<T> {
    function equals(other: T): bool
}

interface Serializable {
    function toJson(): string
}

interface Cloneable<T> {
    function clone(): T
}

interface Iterable<T> {
    function iterator(): Iterator<T>
}
```

## 泛型类约束

```simplescript
// 排序集合要求元素可比较
class SortedList<T : Comparable<T>> {
    let items: MutableList<T> = MutableList.of()

    function add(item: T) {
        items.add(item)
        items.sort()
    }

    function first(): T? = if (items.isEmpty()) null else items[0]
}

const numbers = new SortedList<int>()
numbers.add(3)
numbers.add(1)
numbers.add(2)
println(numbers.first())   // 1
```

## 泛型接口

```simplescript
interface Repository<T, ID> {
    function findById(id: ID): T?
    function findAll(): List<T>
    function save(entity: T): T
    function deleteById(id: ID)
}

// 实现时指定具体类型
class UserRepository : Repository<User, long> {
    override function findById(id: long): User? { ... }
    override function findAll(): List<User> { ... }
    override function save(entity: User): User { ... }
    override function deleteById(id: long) { ... }
}
```

## 类型擦除？不

```simplescript
// Java 泛型在运行时擦除类型信息：
//   List<String> 和 List<Integer> 运行时是同一个类型
//   不能写 if (x instanceof List<String>)

// SimpleScript 泛型通过单态化，编译器为每个具体类型生成独立代码
// 类型信息完整保留

function <T> checkType(value: T): string {
    return typeof(T)    // 编译期确定，不是运行时反射
}

checkType(42)           // "int" — 编译器生成 checkType_int
checkType("hello")      // "string" — 编译器生成 checkType_string
```
