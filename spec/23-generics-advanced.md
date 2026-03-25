# 23 - Advanced Generics (泛型进阶)

## 设计理念

> 泛型通过单态化实现，零运行时开销。约束清晰，编译期报错明确。

## 基本约束

```simplescript
// 单约束
function <T : Comparable<T>> max(a: T, b: T): T {
    return if (a > b) a else b
}

// 多约束
function <T> serialize(item: T): string where T : Serializable, T : Printable {
    return item.toJson()
}
```

## 接口泛型

```simplescript
interface Repository<T, ID> {
    function findById(id: ID): T?
    function findAll(): List<T>
    function save(entity: T): T
    function deleteById(id: ID)
}

@Service
class UserRepository(db: Database) : Repository<User, long> {
    override function findById(id: long): User? = db.find<User>(id)
    override function findAll(): List<User> = db.findAll<User>()
    override function save(entity: User): User = db.insert(entity)
    override function deleteById(id: long) = db.delete<User>(id)
}
```

## 协变与逆变

```simplescript
// out = 协变 (只读, 可以用子类代替父类)
interface Producer<out T> {
    function produce(): T
}

// in = 逆变 (只写, 可以用父类代替子类)
interface Consumer<in T> {
    function consume(item: T)
}

// 示例
class AnimalProducer : Producer<Animal> {
    override function produce(): Animal = new Dog()
}

const producer: Producer<Animal> = new AnimalProducer()
// Producer<Dog> 可以赋值给 Producer<Animal> (因为 out)
```

## 类型擦除? 不，单态化

```simplescript
// SimpleScript 泛型通过单态化实现
// 编译器为每个具体类型生成独立代码

function <T> identity(value: T): T = value

// 调用
identity(42)        // 编译器生成: identity_int(value: int): int
identity("hello")   // 编译器生成: identity_string(value: string): string

// 好处:
// ✓ 零运行时开销
// ✓ 可以对泛型类型做 switch
// ✓ 类型信息完整保留
```

## 泛型扩展函数

```simplescript
// 对任意 List<T> 添加方法
function <T> List<T>.secondOrNull(): T? {
    return if (this.size() >= 2) this[1] else null
}

// 带约束的扩展
function <T : Comparable<T>> List<T>.isSorted(): bool {
    for (let i = 1; i < this.size(); i++) {
        if (this[i] < this[i - 1]) return false
    }
    return true
}

const list = List.of(1, 2, 3)
println(list.isSorted())        // true
println(list.secondOrNull())    // 2
```
