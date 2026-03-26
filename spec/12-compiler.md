# 12 - Compiler Implementation Plan (编译器实现计划)

## 编译器自身用什么语言写

| 阶段 | 语言 | 理由 |
|------|------|------|
| Stage 0 (引导) | Rust | 性能好、LLVM 绑定成熟 (inkwell/llvm-sys) |
| Stage 1 (自举) | SimpleScript | 用 SimpleScript 写 SimpleScript 编译器，吃自己的狗粮 |

## 实现路线

### Phase 1 — 最小可用编译器

```
目标: Hello World 能跑

实现:
  ✓ 词法分析 (Lexer)
  ✓ 语法分析 (Parser) → AST
  ✓ 基本类型: int, string, bool
  ✓ 变量: const, let
  ✓ 函数: function
  ✓ 控制流: if, for, while
  ✓ println
  ✓ LLVM IR 生成
  ✓ musl 静态链接
  ✓ ss build / ss run
```

```simplescript
// Phase 1 能编译这个
function main() {
    const name = "SimpleScript"
    println(`hello, ${name}!`)
}
```

### Phase 2 — 类型系统

```
目标: OOP 能用

实现:
  ✓ class (构造函数、方法、属性)
  ✓ interface
  ✓ 继承、实现
  ✓ 泛型 (单态化)
  ✓ 空安全 (T / T?)
  ✓ 枚举 + 模式匹配
  ✓ switch 表达式
  ✓ 类型推断
```

### Phase 3 — 内存管理

```
目标: ARC 自动内存管理

实现:
  ✓ 引用计数插入
  ✓ weak 引用
  ✓ 逃逸分析 (栈/堆自动分配)
  ✓ Copy-on-Write
  ✓ 移动语义推断
  ✓ Closeable + try-with-resources
```

### Phase 4 — 错误处理 + 标准库

```
目标: 能写实际程序

实现:
  ✓ Result<T, E>
  ✓ ? / ?? / ! 操作符
  ✓ 标准库: io/print, io/fs, util/collections, util/strings, util/math, util/time
  ✓ 箭头函数
  ✓ 扩展函数
  ✓ 解构
  ✓ import / export 模块系统
```

### Phase 5 — 并发

```
目标: 虚拟线程能用

实现:
  ✓ M:N 调度器运行时
  ✓ spawn
  ✓ Channel / select
  ✓ 结构化并发 (scope, timeout)
  ✓ Mutex / Atomic
  ✓ 编译器线程安全检查
```

### Phase 6 — Web + 注解

```
目标: 能写 Web 服务

实现:
  ✓ net/http (客户端) + ss/web (服务器、路由、中间件)
  ✓ 注解系统 (@RestController, @GetMapping, ...)
  ✓ 依赖注入 (@Service, @Component, @Configuration)
  ✓ JSON 序列化 (@JsonProperty, ...)
  ✓ 数据库 / ORM (@Table, @Id, ...)
  ✓ 校验 (@Valid, @NotBlank, ...)
```

### Phase 7 — 生态

```
目标: 能用于生产

实现:
  ✓ 包管理器 (ss add/publish, ss.json)
  ✓ 中央仓库
  ✓ C Interop (import .h)
  ✓ 交叉编译
  ✓ LSP (IDE 支持)
  ✓ ss fmt / ss lint / ss test
  ✓ ss doc (文档生成)
```

### Phase 8 — 自举

```
目标: SimpleScript 编译器用 SimpleScript 自己写

实现:
  ✓ 用 SimpleScript 重写 Lexer / Parser
  ✓ 用 SimpleScript 重写类型检查器
  ✓ 用 SimpleScript 重写 LLVM IR 生成器
  ✓ 通过自举测试: 新编译器能编译自己
```

## 技术选型

| 组件 | 选型 | 理由 |
|------|------|------|
| Lexer | 手写 | 性能最好，错误信息可控 |
| Parser | 递归下降 | 简单、可读、错误恢复好 |
| 类型检查 | 双向类型推断 | 兼顾推断能力和可预测性 |
| IR | LLVM IR | 成熟优化、多平台支持 |
| 链接 | musl-gcc 静态链接 | 零依赖二进制 |
| ARC | 编译期插入 retain/release | 确定性、零 GC |
| 调度器 | 自研 M:N runtime | 虚拟线程核心 |

## 里程碑

| 里程碑 | 内容 | 标志 |
|--------|------|------|
| v0.1 | Phase 1-2 | Hello World + class 能跑 |
| v0.2 | Phase 3-4 | 能写 CLI 工具 |
| v0.3 | Phase 5 | 并发程序能跑 |
| v0.4 | Phase 6 | 能写 Web 服务 |
| v0.5 | Phase 7 | 生态工具链齐全 |
| v1.0 | Phase 8 | 自举完成，可用于生产 |
