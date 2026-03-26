# 07 - Package Manager (ss)

## 设计理念

> 一个命令搞定一切。来自 Cargo 的一体化体验 + npm 的简单直觉。
> 项目管理、依赖、构建、测试、发布，全部集成在 `ss` 命令里。

## 项目结构

```
my-app/
├── ss.json              # 项目配置 (唯一配置文件)
├── src/
│   └── main.ss          # 入口文件
├── test/
│   └── main.test.ss     # 测试文件
└── lib/                  # 库代码 (可选)
```

## ss.json

```json
{
  "name": "my-app",
  "version": "0.1.0",
  "target": "bin",
  "dependencies": {
    "zhangsan/sqlite": "3.0.0",
    "lisi/redis": "git:https://github.com/lisi/ss-redis#1.0.0"
  },
  "scripts": {
    "dev": "ss run --watch",
    "prod": "ss build --release"
  }
}
```

## 命令

```bash
# 创建项目
ss new my-app              # 创建可执行项目
ss new my-lib --lib        # 创建库项目

# 依赖管理
ss add net/http            # 添加依赖 (username/package 格式)
ss add zhangsan/sqlite@3.0.0   # 指定版本
ss remove zhangsan/sqlite  # 移除依赖
ss update                  # 更新所有依赖

# 构建
ss build                   # debug 构建
ss build --release         # release 构建 (优化 + 体积压缩)

# 运行
ss run                     # 构建并运行
ss run --release           # release 模式运行

# 测试
ss test                    # 运行所有测试
ss test user               # 运行匹配 "user" 的测试

# 发布
ss publish                 # 发布到中央仓库
```

## 构建产物

```bash
ss build --release

# 输出:
# target/release/my-app        ← 单个静态二进制，musl 链接
# 大小: ~80KB (hello world)
# 依赖: 无，任何 Linux 直接运行
```

## 交叉编译

```bash
# 一行命令，交叉编译到其他平台
ss build --target linux-x86_64
ss build --target linux-aarch64
ss build --target macos-x86_64
ss build --target macos-aarch64
ss build --target windows-x86_64
```
