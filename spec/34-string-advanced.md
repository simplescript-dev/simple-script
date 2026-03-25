# 34 - String Advanced (字符串进阶)

## 设计理念

> UTF-8 内部编码，不可变，引用计数共享。
> 来自 Rust 的 UTF-8 正确性 + Kotlin 的扩展方法 + JS 的模板字符串。

## 基本特性

```simplescript
// 字符串是不可变的，UTF-8 编码
const s = "hello"
// s[0] = 'H'  // 编译错误! 不可变

// 普通字符串
const plain = "hello, world"

// 模板字符串 (反引号)
const name = "Alice"
const greeting = `hello, ${name}`
const expr = `1 + 1 = ${1 + 1}`

// 多行模板字符串
const sql = `
    SELECT *
    FROM users
    WHERE age > ${minAge}
`

// 原始字符串 (不转义)
const path = r"C:\Users\Alice\Documents"
const regex = r"\d{3}-\d{4}"
```

## 常用方法

```simplescript
const s = "Hello, World!"

// 查询
s.length                    // 13
s.isEmpty()                 // false
s.contains("World")         // true
s.startsWith("Hello")       // true
s.endsWith("!")             // true
s.indexOf("World")          // 7

// 转换
s.toUpperCase()             // "HELLO, WORLD!"
s.toLowerCase()             // "hello, world!"
s.trim()                    // 去首尾空格
s.trimStart()               // 去首部空格
s.trimEnd()                 // 去尾部空格
s.replace("World", "YM")   // "Hello, YM!"
s.repeat(3)                 // "Hello, World!Hello, World!Hello, World!"
s.reversed()                // "!dlroW ,olleH"

// 分割与拼接
"a,b,c".split(",")                    // ["a", "b", "c"]
List.of("a", "b", "c").joinToString(",")  // "a,b,c"
"  hello  world  ".split(" ")          // ["hello", "world"] (自动去空)

// 截取
s.substring(0, 5)           // "Hello"
s.take(5)                   // "Hello"
s.drop(7)                   // "World!"

// 填充
"42".padStart(5, '0')       // "00042"
"hi".padEnd(10, '.')        // "hi........"
```

## 字符操作

```simplescript
const s = "hello"

// 遍历字符
for (ch in s) {
    println(ch)        // h, e, l, l, o
}

// 带索引遍历
for (let i = 0; i < s.length(); i++) {
    println(`${i}: ${s[i]}`)
}

// 字符检查
'A'.isUpperCase()      // true
'3'.isDigit()          // true
' '.isWhitespace()     // true
'中'.isLetter()        // true (Unicode)
```

## 字符串构建器

```simplescript
// 大量拼接用 StringBuilder，避免反复创建新字符串
import { StringBuilder } from "util/strings"

const sb = new StringBuilder()
for (let i = 0; i < 1000; i++) {
    sb.append(`line ${i}\n`)
}
const result = sb.toString()

// 或者用链式写法
const result = new StringBuilder()
    .append("header\n")
    .append(items.map((item) => `- ${item}\n`).joinToString(""))
    .append("footer")
    .toString()
```

## 正则表达式

```simplescript
import { Regex } from "util/regex"

const pattern = new Regex(r"\d{3}-\d{4}")

// 匹配
pattern.matches("123-4567")               // true
pattern.find("call 123-4567 now")          // Match(value: "123-4567", range: [5, 13])
pattern.findAll("123-4567 and 890-1234")   // [Match(...), Match(...)]

// 替换
pattern.replace("call 123-4567", "***")    // "call ***"

// 分组
const datePattern = new Regex(r"(\d{4})-(\d{2})-(\d{2})")
const match = datePattern.find("date: 2026-03-22")?
println(match.group(1))    // "2026"
println(match.group(2))    // "03"
println(match.group(3))    // "22"
```

## 编码转换

```simplescript
const s = "hello"

// 字符串 ↔ 字节
const bytes = s.toBytes()              // List<ubyte>, UTF-8
const back = string.fromBytes(bytes)   // "hello"

// 编码检查
const valid = string.isValidUtf8(bytes)   // true
```
