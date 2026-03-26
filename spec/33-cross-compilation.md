# 33 - Cross Compilation & Deployment (交叉编译与部署)

## 设计理念

> 一次编写，编译到任何平台。来自 Go 的交叉编译体验。

## 支持的目标平台

```
linux/x86_64       (首要目标)
linux/aarch64      (ARM 服务器、树莓派)
macos/x86_64
macos/aarch64      (Apple Silicon)
windows/x86_64
```

## 交叉编译

```bash
# 当前平台编译
ss build --release

# 指定目标平台
ss build --release --target linux/x86_64
ss build --release --target linux/aarch64
ss build --release --target macos/aarch64
ss build --release --target windows/x86_64

# 一次编译所有平台
ss build --release --target all
```

## 产物

```bash
$ ss build --release
$ ls -lh target/release/

my-app           1.2 MB    # 单文件静态二进制
                            # 无依赖，复制到任何同架构 Linux 直接运行
```

## Docker 部署

```dockerfile
# 多阶段构建
FROM simplescript:latest AS builder
WORKDIR /app
COPY . .
RUN ss build --release

# 最终镜像: FROM scratch，零依赖
FROM scratch
COPY --from=builder /app/target/release/my-app /my-app
EXPOSE 8080
ENTRYPOINT ["/my-app"]
```

```bash
$ docker build -t my-app .
$ docker images my-app
REPOSITORY   TAG     SIZE
my-app       latest  1.5 MB    # 镜像 ≈ 二进制大小
```

## systemd 部署

```ini
# /etc/systemd/system/my-app.service
[Unit]
Description=My SimpleScript App
After=network.target

[Service]
Type=simple
ExecStart=/opt/my-app/my-app
Restart=always
Environment=YM_ENV=prod

[Install]
WantedBy=multi-user.target
```

```bash
scp target/release/my-app server:/opt/my-app/
ssh server "systemctl enable --now my-app"
```

## CI/CD

```yaml
# GitHub Actions
name: Build & Deploy
on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: simplescript/setup-ss@v1

      - run: ss test
      - run: ss build --release

      - uses: actions/upload-artifact@v4
        with:
          name: my-app
          path: target/release/my-app
```

## 体积优化

```bash
# 默认 release 已开启:
# - LTO (Link Time Optimization)
# - 死代码消除
# - musl 静态链接
# - strip 符号表

# 额外优化
ss build --release --size         # 优化体积 (Os)
ss build --release --speed        # 优化速度 (O3)
```

| 项目类型 | 预期体积 |
|---------|---------|
| Hello World | < 100 KB |
| CLI 工具 | 200 KB ~ 1 MB |
| Web API 服务 | 1 MB ~ 5 MB |
| 带数据库的完整应用 | 3 MB ~ 10 MB |
