# 09 - Toolchain (工具链)

## 设计理念

> `ym` 一个命令覆盖所有开发环节。不需要额外装 linter、formatter、test runner。
> 来自 Cargo 的一体化 + Go 的工具链内置。

## 完整命令

```bash
# === 项目 ===
ym new my-app                  # 创建项目
ym new my-lib --lib            # 创建库
ym init                        # 在当前目录初始化项目

# === 构建 ===
ym build                       # debug 构建
ym build --release             # release 构建 (优化 + musl 静态链接)
ym run                         # 构建并运行
ym run --release               # release 模式运行
ym run --watch                 # 文件改动自动重新运行

# === 测试 ===
ym test                        # 运行所有测试
ym test user                   # 运行匹配 "user" 的测试
ym test --coverage             # 生成覆盖率报告

# === 代码质量 ===
ym fmt                         # 格式化代码 (内置，无争议风格)
ym lint                        # 静态分析
ym check                       # 类型检查 (不生成二进制)

# === 依赖 ===
ym add net/http                # 添加依赖 (username/package)
ym add zhangsan/sqlite@3.0.0   # 指定版本
ym remove zhangsan/sqlite      # 移除
ym update                      # 更新所有依赖
ym tree                        # 查看依赖树

# === 发布 ===
ym publish                     # 发布包到中央仓库
ym login                       # 登录仓库账号

# === 工具 ===
ym doc                         # 生成文档
ym bench                       # 性能基准测试
ym clean                       # 清理构建产物
```

## 编译流程

```
 .ss 源码
   │
   ├─ 1. 词法分析 (Lexer)
   ├─ 2. 语法分析 (Parser) → AST
   ├─ 3. 类型检查 + 注解处理
   ├─ 4. ARC 插入 (引用计数)
   ├─ 5. 优化 (逃逸分析、内联、死代码消除)
   ├─ 6. 生成 LLVM IR
   ├─ 7. LLVM 优化 (O2/O3)
   ├─ 8. 生成目标平台机器码
   └─ 9. 静态链接 musl libc
         │
         ▼
   单个原生二进制 (无依赖)
```

## ss.json 完整配置

```json
{
  "name": "my-app",
  "version": "0.1.0",
  "target": "bin",
  "main": "src/main.ss",
  "dependencies": {
    "zhangsan/sqlite": "3.0.0"
  },
  "devDependencies": {
    "mock": "1.0.0"
  },
  "scripts": {
    "dev": "ym run --watch",
    "prod": "ym build --release",
    "deploy": "ym build --release && scp target/release/my-app server:/app/"
  },
  "compiler": {
    "target": "linux-x86_64",
    "optimization": "O2"
  }
}
```

## 项目结构约定

```
my-app/
├── ss.json                # 项目配置
├── ss.lock                # 依赖锁文件 (自动生成)
├── src/
│   ├── main.ss            # 入口
│   ├── controller/        # 控制器
│   ├── service/           # 服务层
│   ├── model/             # 数据模型
│   └── util/              # 工具类
├── test/
│   ├── controller/
│   └── service/
├── resources/             # 配置文件、静态资源
│   └── application.yml    # 应用配置
└── target/                # 构建产物 (自动生成)
    ├── debug/
    └── release/
```

## IDE 支持

```
ym lsp                     # 启动 Language Server Protocol 服务

支持:
  ✓ 代码补全
  ✓ 跳转定义
  ✓ 类型提示
  ✓ 错误高亮
  ✓ 重构 (重命名、提取方法)
  ✓ 自动导入

首批支持: VS Code 插件
后续: IntelliJ、Vim/Neovim
```
