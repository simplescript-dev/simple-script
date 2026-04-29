// SimpleScript web demo — Spring Boot 注解风格
//
// 编译 + 运行:
//   bin/ss build examples/web_demo.ss -o /tmp/web_demo
//   /tmp/web_demo                       # 默认 listen 8080
//
// 另开终端:
//   curl http://localhost:8080/
//   curl http://localhost:8080/ping
//   curl http://localhost:8080/hello?name=Alice

import { SpringApplication } from "@/lib/spring/boot/application"

@RestController
class HelloController {
    @GetMapping(path = "/")
    function index(): string {
        return "Hello from SimpleScript!"
    }

    @GetMapping(path = "/ping")
    function ping(): string {
        return "pong"
    }

    @GetMapping(path = "/hello")
    function hello(@RequestParam(name = "name") name: string): string {
        return "Hello, " + name + "!"
    }
}

@SpringBootApplication
class WebDemoApp {}

function main() {
    let appArgs: Array<string> = ["--serve"]   // demo 默认 listen
    let i = 1
    while (i < args()) {
        appArgs = appArgs.push(arg(i))
        i = i + 1
    }
    SpringApplication.run("WebDemoApp", appArgs)
}
