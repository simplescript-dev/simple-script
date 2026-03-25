# 53 - Environment & Process (环境与进程)

## 环境变量

```simplescript
import { getEnv, setEnv, allEnv } from "os/env"

// 读取
const home = getEnv("HOME") ?? "/root"
const port = getEnv("PORT")?.toInt() ?? 8080
const debug = getEnv("DEBUG") == "true"

// 读取全部
for ((key, value) in allEnv()) {
    println(`${key}=${value}`)
}
```

## 命令行参数

```simplescript
import { args } from "os/env"

function main() {
    const arguments = args()    // List<string>
    // args()[0] 是程序名
    // args()[1], args()[2], ... 是参数

    for (arg in arguments) {
        println(arg)
    }
}
```

## 信号处理

```simplescript
import { onSignal, Signal } from "os/signal"

function main() {
    // 优雅退出
    onSignal(Signal.SIGINT, () => {
        println("shutting down...")
        server.stop()
        db.close()
        System.exit(0)
    })

    onSignal(Signal.SIGTERM, () => {
        println("terminated")
        cleanup()
        System.exit(0)
    })

    server.start()
}
```

## 进程信息

```simplescript
import { System } from "os/env"

println(System.pid())                // 进程 ID
println(System.cpuCount())           // CPU 核心数
println(System.totalMemory())        // 总内存 (bytes)
println(System.freeMemory())         // 可用内存 (bytes)
println(System.osName())             // "linux", "macos", "windows"
println(System.osArch())             // "x86_64", "aarch64"
println(System.version())          // "0.1.0"
```

## 退出

```simplescript
import { System } from "os/env"

System.exit(0)       // 正常退出
System.exit(1)       // 错误退出
```

## 子进程

```simplescript
import { exec, Command } from "os/exec"

// 简单执行
const output = exec("ls -la")?
println(output)

// 完整控制
const result = new Command("git")
    .args("log", "--oneline", "-10")
    .dir("/home/user/project")
    .env("GIT_PAGER", "cat")
    .run()?

println(`exit: ${result.exitCode}`)
println(`stdout: ${result.stdout}`)
println(`stderr: ${result.stderr}`)

// 管道
const count = new Command("cat")
    .args("access.log")
    .pipe(new Command("grep").args("ERROR"))
    .pipe(new Command("wc").args("-l"))
    .run()?

println(`error count: ${count.stdout.trim()}`)

// 后台进程
const process = new Command("tail")
    .args("-f", "/var/log/app.log")
    .spawn()?

for (line in process.stdout.lines()) {
    if (line.contains("FATAL")) {
        sendAlert(line)
    }
}

// 终止子进程
process.kill()
```
