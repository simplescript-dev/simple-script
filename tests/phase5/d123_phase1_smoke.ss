// D123 Phase 1 smoke test — @SpringBootApplication comptime 入口回归护网。
// 直接验证 SpringApplication.run(骨架)可调 + comptime reflect.classes() 扫
// @RestController CSV 行为。Phase 2+ 扩 dispatcher 时若 lib/spring/boot/application.ss
// 骨架回归,此 test 先于 examples/spring-parity/hello 触发失败,快速定位。

import { assertEqual } from "@/lib/test"
import { SpringApplication } from "@/lib/spring/boot/application"

@SpringBootApplication
class SmokeApp {}

@RestController
class AlphaController {}

@RestController
class BetaController {}

function main() {
    test("D123 Phase 1 — comptime scans @RestController classes in dictionary order", () => {
        const names = comptime {
            let acc = ""
            for (c in reflect.classes()) {
                for (ann in c.annotations) {
                    if (ann.name == "RestController") {
                        if (acc != "") { acc = acc + "," }
                        acc = acc + c.name
                    }
                }
            }
            return acc
        }
        assertEqual(names, "AlphaController,BetaController")
    })

    test("D123 Phase 1 — SpringApplication.run skeleton callable (runtime prints Started)", () => {
        SpringApplication.run("SmokeApp", [])
    })
}
