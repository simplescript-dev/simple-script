# 40 - Numeric Types & Conversions (数值类型与转换)

## 设计理念

> 无隐式转换，所有数值转换必须显式。防止精度丢失的 bug。

## 数值类型

```
整数:
  byte     8-bit 有符号    -128 ~ 127
  short    16-bit 有符号   -32768 ~ 32767
  int      32-bit 有符号   -2^31 ~ 2^31-1
  long     64-bit 有符号   -2^63 ~ 2^63-1

无符号整数:
  ubyte    8-bit 无符号    0 ~ 255
  ushort   16-bit 无符号   0 ~ 65535
  uint     32-bit 无符号   0 ~ 2^32-1
  ulong    64-bit 无符号   0 ~ 2^64-1

浮点:
  float    32-bit IEEE 754
  double   64-bit IEEE 754
```

## 字面量

```simplescript
// 整数 (默认 int)
const a = 42                   // int
const b = 42L                  // long
const c = 0xFF                 // int, 十六进制
const d = 0b1010               // int, 二进制
const e = 0o17                 // int, 八进制
const f = 1_000_000            // int, 下划线分隔 (可读性)

// 浮点 (默认 double)
const g = 3.14                 // double
const h = 3.14F                // float
const i = 1.5e10               // double, 科学计数法

// 无符号
const j: ubyte = 255
const k: ulong = 42
```

## 显式转换

```simplescript
const a: int = 42
const b: long = a.toLong()           // int → long (安全，无精度丢失)
const c: double = a.toDouble()       // int → double
const d: byte = a.toByte()           // int → byte (可能截断，编译器警告)
const e: string = a.toString()       // int → string

const f: double = 3.14
const g: int = f.toInt()             // double → int (截断小数部分)
const h: float = f.toFloat()         // double → float (可能丢精度)

const s = "42"
const i: int = s.toInt()?            // string → int (可能失败，返回 Result)
const j: double = s.toDouble()?      // string → double
```

## 运算规则

```simplescript
// 同类型运算
const a: int = 10 + 20              // int

// 不同类型 → 编译错误
const b = 10 + 3.14                 // 编译错误! int + double 不允许

// 必须显式转换
const b = 10.toDouble() + 3.14      // double

// 整数除法
const c = 10 / 3                     // 3 (int / int = int)
const d = 10.toDouble() / 3          // 3.333... (double / int 编译错误)
const d = 10.toDouble() / 3.toDouble()  // 3.333...
```

## 溢出检查

```simplescript
// 默认: debug 模式检查溢出，release 模式不检查 (性能)
const max: int = 2147483647
const overflow = max + 1           // debug: panic! release: 溢出为负数

// 显式溢出处理
const result = max.addExact(1)     // Result<int, OverflowError>
const wrapped = max.addWrapping(1) // 溢出回绕，返回 -2147483648
const clamped = max.addSaturating(1) // 饱和，返回 2147483647
```

## 位运算

```simplescript
const a = 0b1100
const b = 0b1010

a & b        // AND:  0b1000
a | b        // OR:   0b1110
a ^ b        // XOR:  0b0110
~a           // NOT:  按位取反
a << 2       // 左移: 0b110000
a >> 1       // 右移: 0b0110
a >>> 1      // 无符号右移
```
