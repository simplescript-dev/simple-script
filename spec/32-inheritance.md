# 32 - Inheritance & Composition (继承与组合)

## 设计理念

> 单继承 + 多接口实现。来自 Java 的继承模型，但鼓励组合优于继承。
> 默认不可继承，显式标记 `open` 才能被继承（来自 Kotlin）。

## 单继承

```simplescript
// 默认 class 不能被继承
class User(name: string, age: int)

// class Dog : User {}  // 编译错误! User 不是 open 的

// open 标记允许继承
open class Animal(name: string) {
    open function speak(): string = "..."
}

class Dog(name: string, breed: string) : Animal(name) {
    override function speak(): string = "woof!"
}

class Cat(name: string) : Animal(name) {
    override function speak(): string = "meow!"
}
```

## 多接口实现

```simplescript
interface Flyable {
    function fly()
}

interface Swimmable {
    function swim()
}

// 一个 class 可以实现多个 interface
class Duck(name: string) : Animal(name), Flyable, Swimmable {
    override function speak(): string = "quack!"
    override function fly() { println(`${name} is flying`) }
    override function swim() { println(`${name} is swimming`) }
}
```

## 接口默认实现

```simplescript
interface Logger {
    function log(msg: string)

    // 默认实现
    function info(msg: string) {
        log("[INFO] ${msg}")
    }

    function error(msg: string) {
        log("[ERROR] ${msg}")
    }
}

// 只需要实现核心方法
class ConsoleLogger : Logger {
    override function log(msg: string) {
        println(msg)
    }
    // info() 和 error() 自动继承默认实现
}
```

## abstract class

```simplescript
// 抽象类不能直接实例化
abstract class Shape {
    abstract function area(): double
    abstract function perimeter(): double

    // 非抽象方法可以有实现
    function describe(): string = `area=${area()}, perimeter=${perimeter()}`
}

class Circle(radius: double) : Shape() {
    override function area(): double = Math.PI * radius * radius
    override function perimeter(): double = 2 * Math.PI * radius
}

class Rect(width: double, height: double) : Shape() {
    override function area(): double = width * height
    override function perimeter(): double = 2 * (width + height)
}
```

## 组合优于继承

```simplescript
// 不推荐: 深层继承
open class Vehicle { }
open class Car : Vehicle() { }
open class ElectricCar : Car() { }
open class TeslaModelS : ElectricCar() { }   // 继承链太深

// 推荐: 接口 + 组合
interface Drivable {
    function drive()
}

interface Electric {
    function charge()
}

interface Autopilot {
    function selfDrive()
}

class TeslaModelS(
    engine: ElectricEngine,
    pilot: AutopilotSystem
) : Drivable, Electric, Autopilot {
    override function drive() { engine.start() }
    override function charge() { engine.charge() }
    override function selfDrive() { pilot.engage() }
}
```

## 访问修饰符

```simplescript
open class Base {
    export function publicMethod() { }           // 任何人可访问
    internal function internalMethod() { }       // 同包可访问
    protected function protectedMethod() { }     // 子类可访问
    function privateMethod() { }                 // 仅本类 (默认)
}
```

| 修饰符 | 本类 | 子类 | 同包 | 外部 |
|--------|------|------|------|------|
| (默认) | ✓ | ✗ | ✗ | ✗ |
| `protected` | ✓ | ✓ | ✗ | ✗ |
| `internal` | ✓ | ✓ | ✓ | ✗ |
| `export` | ✓ | ✓ | ✓ | ✓ |
