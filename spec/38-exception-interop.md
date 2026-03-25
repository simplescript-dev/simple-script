# 38 - Exception Interop (异常互操作)

## 设计理念

> SimpleScript 没有 try/catch/throw。但调用 C 库或处理系统级错误时，
> 需要一种机制把外部异常转为 Result。

## panic vs Result

```
panic  — 不可恢复，程序 bug（数组越界、断言失败）
Result — 可恢复，业务错误（文件不存在、网络超时、校验失败）

原则：
  能预见的错误 → Result
  不应该发生的 → panic
```

## panic

```simplescript
// 主动 panic
function getItem(list: List<int>, index: int): int {
    if (index < 0 || index >= list.size()) {
        panic(`index out of bounds: ${index}`)
    }
    return list[index]
}

// 断言 (debug 模式生效)
assert(list.size() > 0, "list must not be empty")
assert(user != null, "user should exist at this point")
```

## C 库异常捕获

```simplescript
// C 函数可能导致段错误等系统级异常
// recover 块可以捕获 panic，转为 Result
function safeDivide(a: int, b: int): Result<int, string> {
    return recover {
        return Result.Ok(a / b)
    } catch (e: PanicError) {
        return Result.Err(`panic: ${e.message()}`)
    }
}
```

## 边界处理

```simplescript
// 在系统边界（HTTP handler、main 函数）捕获所有 panic
function main() {
    recover {
        startApp()
    } catch (e: PanicError) {
        println(`fatal error: ${e.message()}`)
        println(e.stackTrace())
        System.exit(1)
    }
}
```
