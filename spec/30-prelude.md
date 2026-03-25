# 30 - Prelude (自动导入)

## 设计理念

> 最常用的符号无需 import，编译器自动导入。
> 来自 Rust 的 std::prelude + Java 的 java.lang + Kotlin 的 kotlin.*。
> 原则：出现在 90% 程序中的符号才进 prelude，其他必须显式 import。

## Prelude 清单

```
来自 io/print:
  println(msg: string)
  print(msg: string)
  readLine(): string

来自 util/collections:
  List<T>
  MutableList<T>
  Map<K, V>
  MutableMap<K, V>
  Set<T>
  MutableSet<T>
  Queue<T>
  Deque<T>
  Stack<T>
  Pair<A, B>

来自核心类型 (编译器内置):
  Result<T, E>
  Error (接口)
  Comparable<T>
  Iterable<T>
  Closeable
```

## 效果

```simplescript
// 无需任何 import，直接写
function main() {
    println("hello, world!")

    const list = List.of(1, 2, 3)
    const map = Map.of(["a", 1], ["b", 2])

    const result: Result<int, string> = Result.Ok(42)
    const value = result ?? 0

    println(`value: ${value}`)
}
```

## 非 Prelude 的必须 import

```simplescript
// 文件操作
import { readFile, writeFile } from "io/fs"

// HTTP
import { HttpClient } from "net/http"

// 时间
import { Duration, LocalDate } from "util/time"

// JSON
import { json } from "encoding/json"

// 测试
import { test, expect } from "dev/test"
```

## 编译器实现

```
编译器在解析每个 .ss 文件时，隐式注入：

  use io/print::{println, print, readLine}
  use util/collections::{List, MutableList, Map, MutableMap, Set, MutableSet, Queue, Deque, Stack, Pair}
  use core::{Result, Error, Comparable, Iterable, Closeable}

如果用户显式 import 了 prelude 中的符号，不报错，但也不重复导入。
如果用户定义了同名符号，用户定义的优先（覆盖 prelude）。
```

## 扩展 Prelude？

```
不允许。Prelude 是编译器硬编码的，不能通过配置扩展。
这确保所有 SimpleScript 代码有统一的基础环境，
不会因项目不同而出现"这个符号在你那能用在我这不能用"的问题。
```
