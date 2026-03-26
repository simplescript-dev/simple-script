# SimpleScript Language Specification — Index

## 语言核心

| # | 文件 | 主题 |
|---|------|------|
| 00 | overview.md | 总览、设计理念、六边形战士对比 |
| 01 | syntax.md | 语法、类型系统、类与接口、泛型 |
| 02 | error-handling.md | Result、`?` `??` `!` 操作符、panic |
| 03 | memory.md | ARC 自动引用计数、统一 class 模型 |
| 04 | concurrency.md | 虚拟线程、spawn、Channel、select |
| 11 | modules.md | import/export、文件即模块、Prelude |
| 16 | operator-overloading.md | 运算符重载、标准接口 |
| 23 | generics-advanced.md | 协变逆变、单态化、泛型扩展 |
| 27 | pattern-matching.md | switch 模式匹配、解构、guard |
| 30 | prelude.md | 自动导入清单、编译器 Prelude |
| 31 | type-inference.md | 类型推断规则 |
| 32 | inheritance.md | 单继承、多接口、open/abstract |
| 34 | string-advanced.md | 字符串、模板、正则、编码 |
| 36 | destructuring.md | 解构赋值、List/Map/嵌套 |
| 37 | range-tuple.md | Java 风格 for 循环、元组 |
| 38 | exception-interop.md | panic/recover、C 异常互操作 |
| 39 | reflection-alternative.md | 编译期元编程替代反射 |
| 40 | numeric-types.md | 数值类型、显式转换、溢出 |
| 41 | grammar-summary.md | 语法速查表、关键字、操作符 |
| 42 | access-modifiers.md | 四级访问控制 |
| 43 | null-safety-deep.md | 空安全详解、智能收窄 |
| 44 | generics-constraints.md | 泛型约束详解 |
| 45 | coding-conventions.md | 编码规范、ss fmt |

## 标准库

| # | 文件 | 主题 |
|---|------|------|
| 06 | stdlib.md | 标准库模块总览 |
| 26 | collections-advanced.md | 集合进阶、惰性序列 |
| 35 | scope-functions.md | 链式调用与流式 API |
| 28 | async-io.md | I/O 与网络 (文件、TCP、UDP、HTTP) |
| 29 | error-codes.md | 编译器错误信息 (友好提示、Quick Fix) |
| 53 | environment.md | 环境变量、信号、子进程 |
| 54 | date-time.md | 日期时间 API (java.time 风格) |

## Web 开发

| # | 文件 | 主题 |
|---|------|------|
| 08 | annotations.md | 注解系统 (Jackson + Spring Boot) |
| 21 | middleware.md | 中间件基础 |
| 22 | websocket.md | WebSocket 与 SSE |
| 51 | template-engine.md | HTML 模板引擎 |
| 52 | file-upload.md | 文件上传下载 |
| 57 | middleware-advanced.md | 中间件进阶 |
| 59 | session-cookie.md | Session 与 Cookie |
| 61 | swagger-openapi.md | 自动生成 OpenAPI 文档 |
| 66 | error-page.md | Web 错误处理 |
| 67 | pagination.md | 分页与排序 |

## 数据层

| # | 文件 | 主题 |
|---|------|------|
| 10 | orm.md | ORM 注解、查询构建器 |
| 55 | database-migration.md | 数据库迁移 |
| 56 | connection-pool.md | 连接池与多数据源 |
| 63 | cache-advanced.md | 缓存进阶 |

## 微服务

| # | 文件 | 主题 |
|---|------|------|
| 46 | grpc.md | gRPC 与 Protocol Buffers |
| 47 | event-system.md | 事件发布/订阅 |
| 48 | microservice.md | 熔断、重试、限流、服务发现 |
| 64 | message-queue.md | 消息队列 |
| 65 | metrics.md | 指标监控、Prometheus |

## 工程化

| # | 文件 | 主题 |
|---|------|------|
| 05 | ffi.md | C 互操作 |
| 07 | package.md | 包管理器 (ss) |
| 09 | toolchain.md | 工具链 |
| 12 | compiler.md | 编译器实现计划 |
| 14 | cli-framework.md | CLI 框架 |
| 17 | testing.md | 测试框架 |
| 18 | config.md | 配置管理 |
| 19 | logging.md | 日志与可观测性 |
| 20 | security.md | 安全 |
| 33 | cross-compilation.md | 交叉编译与部署 |
| 49 | task-scheduling.md | 定时任务 |
| 50 | file-extension.md | 文件约定 |
| 58 | i18n.md | 国际化 |
| 62 | wasm.md | WebAssembly |
| 68 | async-task.md | 异步任务与后台作业 |
| 69 | email.md | 邮件发送 |

## 架构与参考

| # | 文件 | 主题 |
|---|------|------|
| 13 | annotation-layers.md | 注解分层架构 |
| 15 | example-project.md | 完整示例项目 (Todo API) |
| 24 | interop-ecosystem.md | 生态与互操作 |
| 25 | comparison.md | 语言对比 |
| 60 | validation-advanced.md | 校验进阶 |
