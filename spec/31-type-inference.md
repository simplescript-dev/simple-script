# 31 - Type Inference (类型推断)

## 设计理念

> 能推断的不写，该写的不省。来自 Kotlin/Swift 的局部类型推断。
> 函数签名必须写类型（接口清晰），函数体内自动推断（代码简洁）。

## 规则

```
必须写类型:
  ✓ 函数参数
  ✓ 函数返回值
  ✓ class 构造参数
  ✓ interface 方法签名

自动推断:
  ✓ 局部变量 (const / let)
  ✓ Lambda 参数（有上下文时）
  ✓ 泛型类型参数（可推断时）
```

## 示例

```simplescript
// 局部变量 — 自动推断
const name = "Alice"               // string
const age = 30                     // int
const pi = 3.14                    // double
const list = List.of(1, 2, 3)     // List<int>
const map = Map.of(["a", 1])      // Map<string, int>
const user = new User("Alice", 30) // User

// 函数签名 — 必须标注
function add(a: int, b: int): int = a + b

// 返回值在单表达式时可推断（可选）
function add(a: int, b: int) = a + b     // 返回值推断为 int

// Lambda — 有上下文时推断参数类型
const numbers = List.of(1, 2, 3)
const doubled = numbers.map((n) => n * 2)        // n 推断为 int
const filtered = numbers.filter((n) => n > 1)    // n 推断为 int

// 泛型 — 从参数推断
const list = List.of(1, 2, 3)         // 推断 List<int>，不用写 List.of<int>(1, 2, 3)
const result = Result.Ok(42)           // 推断 Result<int, ?>，E 在使用处确定

// 无法推断时必须标注
const empty = List.empty<string>()     // 空集合无法推断元素类型
let items: List<User> = List.empty()   // 同上
```

## 显式标注总是可选的

```simplescript
// 以下两种写法等价
const name = "Alice"
const name: string = "Alice"

// 但显式标注可以帮助可读性
const timeout: Duration = Duration.seconds(30)
const config: ServerConfig = loadConfig()?
```
