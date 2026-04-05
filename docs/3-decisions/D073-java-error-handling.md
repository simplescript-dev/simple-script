# D073: Java-style Error Handling Enhancement

**Status:** In Progress
**Date:** 2026-04-05

## Decision

模仿 Java 改进 SimpleScript 的错误处理系统，分 4 个阶段实现。

## Current State

- `try { } catch (e) { }` — setjmp/longjmp 实现
- throw 只能抛 string
- catch 变量永远是 string 类型
- 无 finally、无 Error 类、无 typed catch

## Phase 1: finally 块

```simplescript
try {
    const f = openFile("data.txt")
    processFile(f)
} catch (e) {
    println(e)
} finally {
    closeFile(f)  // 不论成功失败都执行
}
```

- AST: TRY 节点 I3 = finally body (0 = 无 finally)
- Codegen: try-success 和 catch-end 两条路径都跳到 finally block
- try { } finally { }（无 catch）也支持

## Phase 2: Error 基类

```simplescript
// prelude.ss 内置
class Error(message: string) {}

// 用户自定义
class IOError extends Error(path: string) {}
class ParseError extends Error(line: int, col: int) {}
```

- Error 定义在 prelude.ss，自动注入
- 用户通过 extends Error 创建自定义错误类型
- 利用现有 class/extends 系统，零新机制

## Phase 3: throw 支持 class 实例

```simplescript
throw new IOError("file not found", "/data.txt")
throw new Error("something went wrong")
throw("backward compatible string")  // 自动包装为 Error
```

- throw(string) → 编译器自动生成 `new Error(string)` 包装
- throw(class_instance) → 直接传递 ptr
- catch 变量类型变为 Error（不再是 string）
- 新增 @ss_exc_is_obj 全局标记，区分旧式 string 和新式 Error 对象

## Phase 4: typed catch (Java 风格)

```simplescript
try {
    readFile("config.json")
} catch (e: IOError) {
    println("IO error: " + e.path)
} catch (e: ParseError) {
    println("Parse error at line " + toString(e.line))
} catch (e: Error) {
    println("Unknown error: " + e.message)
}
```

- Parser: `catch (name: Type)` 多个 catch clause
- AST: TRY.List = CATCH_CLAUSE 节点列表
- CATCH_CLAUSE: S1=变量名, S2=类型, I1=body
- Runtime: 从异常对象的 TypeInfo 提取类名，沿继承链匹配 catch 类型
- 无匹配 → 重新 throw（longjmp 到外层 handler）

## Implementation Order

1. finally — 独立，不依赖其他阶段
2. Error class — prelude.ss 加一行
3. throw objects — 改 genThrow + catch 变量类型
4. typed catch — 改 parser + codegen，最复杂

## Rejected

- Result<T,E> + ? operator — Rust 语法，不符合 TS/Java 原则 (D072)
- checked exceptions (throws 声明) — Java 社区自己也在反思，TypeScript 明确不采用
