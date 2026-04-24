// D123 Phase 1 — Spring Boot parity hello app(SS 端最小 app)
//
// 对应 Java oracle:examples/spring-parity/hello/java/src/main/java/hello/HelloApp.java
// Phase 1 scope:@SpringBootApplication 扫描 comptime 打通,HelloApp 下无 @RestController
// 预期 stdout "Started HelloApp\nControllers: 0"。Phase 2 接入 @GetMapping dispatcher
// 后再同并列 Java oracle parity gate(byte-identical HTTP payload)。

import { SpringApplication } from "@/lib/spring/boot/application"

@SpringBootApplication
class HelloApp {}

function main() {
    SpringApplication.run("HelloApp", [])
}
