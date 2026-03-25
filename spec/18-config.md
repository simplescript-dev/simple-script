# 18 - Configuration (配置管理)

## 设计理念

> 一套配置方案：YAML 配置文件 + 环境变量覆盖 + 类型安全注入。

## application.yml

```yaml
server:
  port: 8080
  host: "0.0.0.0"

database:
  driver: postgres
  url: "postgres://localhost/mydb"
  pool:
    min: 5
    max: 20

cache:
  ttl: 3600

app:
  name: my-service
  debug: false
```

## 类型安全配置类

```simplescript
import { Config, Value } from "yummy/config"

@Config("server")
class ServerConfig(
    port: int = 8080,
    host: string = "0.0.0.0"
)

@Config("database")
class DatabaseConfig(
    driver: string,
    url: string,
    pool: PoolConfig = new PoolConfig()
)

class PoolConfig(
    min: int = 5,
    max: int = 20
)

// 注入使用
@Service
class AppService(serverConfig: ServerConfig, dbConfig: DatabaseConfig) {
    function start() {
        println(`starting on ${serverConfig.host}:${serverConfig.port}`)
        println(`database: ${dbConfig.driver}`)
    }
}

// 单个值注入
@Service
class SimpleService(
    @Value("app.name") appName: string,
    @Value("app.debug") debug: bool
) {
    // ...
}
```

## 环境变量覆盖

```bash
# 环境变量自动覆盖配置文件，规则:
# server.port → SERVER_PORT
# database.url → DATABASE_URL

SERVER_PORT=3000 DATABASE_URL=postgres://prod/mydb ./my-app
```

## 多环境

```
resources/
├── application.yml           # 默认配置
├── application.dev.yml       # 开发环境 (覆盖默认)
├── application.prod.yml      # 生产环境
└── application.test.yml      # 测试环境
```

```bash
# 通过环境变量指定
YM_ENV=prod ./my-app

# 或者命令行参数
./my-app --env prod
```

优先级: **环境变量 > 环境配置文件 > 默认配置文件**
