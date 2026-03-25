# 37 - Range & Tuple (范围与元组)

## Range (范围)

```simplescript
// for 循环 — Java 风格
for (let i = 0; i < 10; i++) { }           // 0 到 9
for (let i = 0; i <= 10; i++) { }          // 0 到 10
for (let i = 10; i >= 0; i--) { }          // 10 到 0
for (let i = 0; i < 100; i += 2) { }       // 0, 2, 4, ..., 98

// for-in 遍历集合
for (item in list) { }
for ((k, v) in map) { }

// 范围检查
if (age >= 18 && age <= 65) { }
```

## Tuple (元组)

```simplescript
// 数组风格元组 — TypeScript 风格
const pair: [string, int] = ["Alice", 30]
const triple: [string, int, string] = ["Alice", 30, "Beijing"]

// 解构
const [name, age] = pair
const [name, age, city] = triple

// 函数返回多个值
function divide(a: int, b: int): [int, int] {
    return [a / b, a % b]
}
const [quotient, remainder] = divide(10, 3)   // 3, 1

// Map 初始化
const map = new Map<string, int>([
    ["Alice", 95],
    ["Bob", 87],
    ["Charlie", 92]
])
```
