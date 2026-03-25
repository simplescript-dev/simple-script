# 39 - Compile-Time Metaprogramming (编译期元编程)

## 设计理念

> 没有运行时反射。需要"反射"的场景全部在编译期解决。
> 注解 + 编译器代码生成 = 零运行时开销的元编程。

## 注解处理器

```simplescript
// 自定义注解
annotation class Serializable

// 编译器看到 @Serializable 后，自动生成 toJson() 和 fromJson()
@Serializable
class User(name: string, age: int)

// 编译后等价于:
class User(name: string, age: int) {
    function toJson(): string { ... }           // 编译器自动生成
    static function fromJson(s: string): User { ... }  // 编译器自动生成
}
```

## 编译期类型信息

```simplescript
// typeof 操作符 — 编译期确定类型名称
function logType<T>(value: T) {
    println(`type: ${typeof(T)}, value: ${value}`)
}

logType(42)         // "type: int, value: 42"
logType("hello")    // "type: string, value: hello"
```

## 编译期条件

```simplescript
// comptime if — 编译期分支，不满足的分支不生成代码
function serialize<T>(value: T): string {
    comptime if (T implements Serializable) {
        return value.toJson()
    } else {
        return value.toString()
    }
}
```

## 为什么不要反射

```
反射的问题:
  ✗ 运行时开销 — 类型查找、方法调用都有额外成本
  ✗ 二进制膨胀 — 必须保留所有类型元数据
  ✗ 无法优化 — 编译器不知道运行时会调什么方法
  ✗ 类型不安全 — 绕过编译器检查，运行时才发现错误
  ✗ 安全风险 — 可以访问 private 成员

SimpleScript 的替代:
  ✓ 注解 + 编译器代码生成 — 零运行时开销
  ✓ 泛型单态化 — 编译期生成具体类型代码
  ✓ comptime if — 编译期条件分支
  ✓ typeof — 编译期类型信息
```
