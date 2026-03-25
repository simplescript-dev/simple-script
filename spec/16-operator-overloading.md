# 16 - Operator Overloading (运算符重载)

## 设计理念

> 通过实现标准接口来重载运算符。来自 Kotlin 的 operator 约定，直觉自然。

## 运算符 → 接口映射

| 运算符 | 接口 | 方法 |
|--------|------|------|
| `a + b` | `Addable<T>` | `plus(other: T): T` |
| `a - b` | `Subtractable<T>` | `minus(other: T): T` |
| `a * b` | `Multipliable<T>` | `times(other: T): T` |
| `a / b` | `Dividable<T>` | `div(other: T): T` |
| `a % b` | `Modable<T>` | `mod(other: T): T` |
| `a == b` | `Equatable<T>` | `equals(other: T): bool` |
| `a > b` | `Comparable<T>` | `compareTo(other: T): int` |
| `a[i]` | `Indexable<K, V>` | `get(key: K): V` |
| `a[i] = v` | `MutableIndexable<K, V>` | `set(key: K, value: V)` |
| `for (x in a)` | `Iterable<T>` | `iterator(): Iterator<T>` |
| `a.toString()` | 所有 class 自带 | `toString(): string` |

## 示例

```simplescript
class Vec2(x: double, y: double) : Addable<Vec2>, Subtractable<Vec2>, Comparable<Vec2> {

    override function plus(other: Vec2): Vec2 {
        return new Vec2(x + other.x, y + other.y)
    }

    override function minus(other: Vec2): Vec2 {
        return new Vec2(x - other.x, y - other.y)
    }

    override function compareTo(other: Vec2): int {
        return length().compareTo(other.length())
    }

    function length(): double = Math.sqrt(x * x + y * y)
}

// 使用
const a = new Vec2(1.0, 2.0)
const b = new Vec2(3.0, 4.0)
const c = a + b                    // Vec2(4.0, 6.0)
const d = b - a                    // Vec2(2.0, 2.0)
println(a > b)                     // false
```

## 自定义集合

```simplescript
class Matrix(rows: int, cols: int) : Indexable<Pair<int, int>, double>,
                                                   MutableIndexable<Pair<int, int>, double> {
    let data = new Array<double>(rows * cols)

    override function get(key: Pair<int, int>): double {
        return data[key.first * cols + key.second]
    }

    override function set(key: Pair<int, int>, value: double) {
        data[key.first * cols + key.second] = value
    }
}

const m = new Matrix(3, 3)
m[[0, 1]] = 3.14                    // set
const v = m[[0, 1]]                // get → 3.14
```
