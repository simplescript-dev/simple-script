// D123 Phase 2 — Spring Boot parity hello app(SS 端 + @RestController + @GetMapping)
//
// 对应 Java oracle:examples/spring-parity/hello/java/src/main/java/hello/HelloApp.java
// 期望 stdout 含 `Controllers: 1 [HelloController]` + `Routes: /hello|HelloController.hello;`
// (Phase 2 中间形态:routes csv 收集到位 + httpServe entrypoint 接入,dispatcher 真兑现待 I014)
//
// 命令:
//   bin/ss build examples/spring-parity/hello/ss/main.ss -o /tmp/hello_ss
//   /tmp/hello_ss              # 仅打印 stdout(routes csv),不 listen
//   /tmp/hello_ss --serve      # 启动 httpServe @ 8080(dispatcher I014 stub 返 503)

import { SpringApplication } from "@/lib/spring/boot/application"
import { HelloController } from "./HelloController"

@SpringBootApplication
class HelloApp {}

function main() {
    let appArgs: Array<string> = []
    let i = 1
    while (i < args()) {
        appArgs = appArgs.push(arg(i))
        i = i + 1
    }
    SpringApplication.run("HelloApp", appArgs)
}
