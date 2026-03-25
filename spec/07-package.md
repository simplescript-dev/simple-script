# 07 - Package Manager (ym)

## 设计理念

> 一个命令搞定一切。来自 Cargo 的一体化体验 + npm 的简单直觉。
> 项目管理、依赖、构建、测试、发布，全部集成在 `ym` 命令里。

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
    "lisi/redis": "git:https://github.com/lisi/ym-redis#1.0.0"
  },
  "scripts": {
    "dev": "ym run --watch",
    "prod": "ym build --release"
  }
}
```

## 命令

```bash
# 创建项目
ym new my-app              # 创建可执行项目
ym new my-lib --lib        # 创建库项目

# 依赖管理
ym add net/http            # 添加依赖 (username/package 格式)
ym add zhangsan/sqlite@3.0.0   # 指定版本
ym remove zhangsan/sqlite  # 移除依赖
ym update                  # 更新所有依赖

# 构建
ym build                   # debug 构建
ym build --release         # release 构建 (优化 + 体积压缩)

# 运行
ym run                     # 构建并运行
ym run --release           # release 模式运行

# 测试
ym test                    # 运行所有测试
ym test user               # 运行匹配 "user" 的测试

# 发布
ym publish                 # 发布到中央仓库
```

## 构建产物

```bash
ym build --release

# 输出:
# target/release/my-app        ← 单个静态二进制，musl 链接
# 大小: ~80KB (hello world)
# 依赖: 无，任何 Linux 直接运行
```

## 交叉编译

```bash
# 一行命令，交叉编译到其他平台
ym build --target linux-x86_64
ym build --target linux-aarch64
ym build --target macos-x86_64
ym build --target macos-aarch64
ym build --target windows-x86_64
```
