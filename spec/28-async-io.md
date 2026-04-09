# 28 - I/O & Networking (I/O 与网络)

## 设计理念

> 所有 I/O 都是同步写法，运行时自动非阻塞。虚拟线程让你不用关心 async。

## 文件 I/O

```simplescript
import { File, readFile, writeFile, appendFile, walkDir } from "io/fs"
import { Path } from "io/path"

// 一次性读写
const content = readFile("data.txt")?
writeFile("output.txt", content)?
appendFile("log.txt", "new line\n")?

// 逐行读取 (大文件友好，不会全部加载到内存)
for (line in File.lines("huge.csv")?) {
    process(line)
}

// 流式写入
try (const writer = File.writer("output.txt")?) {
    writer.writeLine("header")
    for (item in data) {
        writer.writeLine(item.toString())
    }
}

// 目录遍历
for (entry in walkDir("src")?) {
    if (entry.extension() == "ss") {
        println(entry.path)
    }
}

// 路径操作
const p = Path.of("/home", "user", "docs", "file.txt")
println(p.parent())          // /home/user/docs
println(p.fileName())        // file.txt
println(p.extension())       // txt
println(p.exists())          // true/false
```

## TCP

```simplescript
import { TcpServer, TcpClient, TcpConnection } from "net/tcp"

// TCP 服务器
function main() {
    const server = new TcpServer(port: 9000)

    // 每个连接自动在独立虚拟线程中处理
    server.onConnection((conn: TcpConnection) => {
        const msg = conn.readLine()?
        conn.writeLine(`echo: ${msg}`)?
    })

    server.start()
}

// TCP 客户端
function main() {
    const conn = TcpClient.connect("localhost", 9000)?
    conn.writeLine("hello")?
    const response = conn.readLine()?
    println(response)       // "echo: hello"
    conn.close()
}
```

## UDP

```simplescript
import { UdpSocket } from "net/udp"

// 发送
const socket = UdpSocket.bind(0)?                      // 随机端口
socket.sendTo("hello", "localhost", 9000)?

// 接收
const server = UdpSocket.bind(9000)?
const (data, addr) = server.receive()?
println(`from ${addr}: ${data}`)
```

## DNS

```simplescript
import { dns } from "net/dns"

const ips = dns.lookup("example.com")?
const records = dns.resolve("example.com", "MX")?
```

## HTTP 客户端进阶

```simplescript
import { HttpClient, Request } from "net/http"

const client = new HttpClient(
    timeout: Duration.seconds(30),
    maxRetries: 3
)

// GET
const users = client.get("https://api.example.com/users")?
    .json<List<User>>()?

// POST 对象，自动序列化
const created = client.post("https://api.example.com/users", new User("Alice", 30))?
    .json<User>()?

// 自定义请求
const response = client.request(
    Request.builder()
        .url("https://api.example.com/upload")
        .method("PUT")
        .header("Authorization", `Bearer ${token}`)
        .header("Content-Type", "application/octet-stream")
        .body(fileBytes)
        .build()
)?

// 下载文件
client.download("https://example.com/big.zip", "local.zip")?
```

## 进程间通信

```simplescript
import { exec, Command, Pipeline } from "os/exec"

// 简单执行
const output = exec("ls -la")?

// 管道
const result = Pipeline.of("cat data.txt")
    .pipe("grep error")
    .pipe("wc -l")
    .execute()?
println(`error count: ${result.stdout.trim()}`)

// 长运行进程
const process = Command("tail")
    .args("-f", "/var/log/app.log")
    .spawn()?

for (line in process.stdout.lines()) {
    if (line.contains("ERROR")) {
        alert(line)
    }
}
```

## 文件监听 (已实现 — D081)

基于 Linux inotify，零 CPU 开销的文件变更监听。

```simplescript
import { FileWatcher } from "@/lib/watcher"

const watcher = FileWatcher.create()
watcher.watch("src/")       // 递归监听目录树
watcher.watch("data/")      // 可监听多个目录

while (true) {
    const changed = watcher.poll(1000)  // 阻塞最多 1 秒
    if (changed != "") {
        println("Changed: " + changed)
        recompile()
    }
}

watcher.close()
```

- `FileWatcher.create()` — 创建 inotify 实例
- `watch(path)` — 递归添加目录监听（IN_MODIFY | IN_CREATE | IN_DELETE | IN_MOVED_TO）
- `poll(timeoutMs)` — 等待变更事件，返回文件名字符串，无变更返回 `""`
- `close()` — 关闭 inotify fd
