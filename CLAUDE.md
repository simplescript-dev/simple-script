# SimpleScript

SimpleScript 是一门面向现代软件开发的编译型语言。语法以 Java/TypeScript 为基础，编译到 LLVM IR 并静态链接 musl libc，产出高性能、小体积的原生二进制。

## 项目结构

```
crates/
  ym-lexer/      词法分析
  ym-parser/     语法分析 (递归下降)
  ym-checker/    类型检查
  ym-codegen/    LLVM IR 生成 (inkwell)
  ym-cli/        CLI 入口 (ss build / ss run)
runtime/
  runtime.c      C 运行时 (字符串、I/O、数组)
spec/            语言规范 (70 个文件)
tests/           测试用例
examples/        示例程序
```

## 构建与测试

```bash
cargo build -p ym-cli              # 编译
cargo run -p ym-cli --bin ss -- build file.ss -o output  # 编译 .ss 文件
cargo run -p ym-cli --bin ss -- run file.ss              # 编译并运行
cargo run -p ym-cli --bin ss -- build --release file.ss  # 优化构建
```

## 语法设计原则

- 语法只参考 Java 和 TypeScript，不引入 Go/Rust/Kotlin 的奇怪语法
- const/let (TypeScript 风格)，类型后置 (name: Type)
- 顶层 const 编译为 LLVM 全局变量（不是 hack 到 main 里）
- function 关键字，class/new/this/extends
- 模板字符串 `${}`，JDK 25 风格 switch

## 开发原则

### 问题解决

- **Root Cause 优先**：永远从根源修复问题（修改工具/框架代码），不逐个修补项目文件。不用临时方案绕过问题，不要表层最快方案假装解决
- **三思而后行**：方案选择时要搜索、对比，选择最优最佳实践，不要第一个能跑的方案就用
- **技术结论必须验证**：说"X 方案有 Y 缺点"之前，先确认 Y 是否真实存在。不确定就说不确定，不要编一个听起来合理的理由。用模糊的"复杂度"当借口回避工作 = 偷懒
- **用 log 调试难题**：遇到难以定位的问题，添加调试日志输出定位根因，不要靠猜测反复尝试
- **逐步确认不想当然**：每一步修复后都要验证结果，不要假设已经修好就继续下一步

### 代码质量

- **单文件不要过大**：单个源文件超过 500 行时应考虑拆分。过大的文件难以理解、难以 review、增量编译效率低
- **最小改动**：只做直接请求的改动，不加无关的重构、注释、docstring
- **不过度工程**：不加 feature flag、不设计假想需求、不为一次性操作创建抽象
- **降低心智负担**：API/配置/命令设计要让用户零思考即可使用，合理默认值、自动推断、约定大于配置
- **删除即删除**：废弃代码直接删掉，不留 `// removed` 注释或 `_unused` 变量
- **先读后改**：修改代码前必须先读懂现有代码，不凭印象写代码
- **全面深度阅读**：读文档/代码时要完整深入，不要只看开头几行就下结论，避免遗漏关键细节
- **融入项目风格**：成熟项目中做迭代时，先观察项目现有的代码风格、命名惯例、架构模式，保持一致

### 安全与规范

- **不引入安全漏洞**：注意命令注入、XSS、SQL 注入等 OWASP Top 10
- **不跳过检查**：不用 `--no-verify`、`--force` 等跳过安全检查的参数
- **只验证边界**：只在系统边界（用户输入、外部 API）做验证，内部代码信任框架保证

### 工作方式

- **先搜索最佳实践**：动手前先搜索业界最佳实践和成熟方案，不闭门造车
- **方案对比决策**：有多个方案时，列表对比各方案优缺点，选出最佳方案再动手
- **先搜索再造轮子**：GitHub、npm/PyPI/crates.io 搜索现有实现，优先采用成熟方案
- **Spec 先行**：新功能必须先写 spec，讨论充分后再实现
- **逐条实现**：对照 spec 实现时，列出 checklist 逐条完成，不凭印象跳步
- **问题分类逐个击破**：处理多个问题时，先将问题归类列表，然后逐个解决并确认，不混在一起处理
- **优先使用项目 skill**：操作其他项目时，先检查该项目下是否有可用的 slash command / skill，优先使用而非手动操作
- **主动发现反模式并提案新原则**：发现自己或代码中违反应成为原则的模式时，主动指出问题、提炼为一句原则、提醒用户确认后加入 init-principle 持久化
- **memory 写入时询问持久化**：写入 memory 时，如果内容有普适价值，询问用户是否同时写入 init-principle。memory 会丢，principle 存 GitHub 永不丢
