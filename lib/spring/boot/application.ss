// D123 Phase 1+2 — @SpringBootApplication entrypoint + @RestController/@GetMapping 路由 csv
// 真 dispatch 待 I014(comptime ctMethodMeta → static method call IR emit);
// 禁 runtime 反射 / @comptimeEmit / @derive(D088 §反模式 L377-386)。

import { httpServe, httpResponse } from "@/lib/http"

class RouteMeta {
    path: string
    className: string
    methodName: string
}

class SpringApplication {
    static function run(appName: string, args: Array<string>) {
        const controllerNames = comptime {
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

        const routesCsv = comptime {
            let acc = ""
            for (c in reflect.classes()) {
                for (cAnn in c.annotations) {
                    if (cAnn.name == "RestController") {
                        for (m in c.methods) {
                            for (mAnn in m.annotations) {
                                if (mAnn.name == "GetMapping") {
                                    acc = acc + mAnn.args.getString("path") + "|" + c.name + "." + m.name + ";"
                                }
                            }
                        }
                    }
                }
            }
            return acc
        }

        println("Started " + appName)
        let count = 0
        if (controllerNames != "") {
            count = controllerNames.split(",").length()
        }
        if (count == 0) {
            println("Controllers: 0")
        } else {
            println("Controllers: " + count + " [" + controllerNames + "]")
        }
        println("Routes: " + routesCsv)

        // --serve 才启动 httpServe(阻塞 listen);默认入口仅打印 routes csv 退出。
        let wantsServe = 0
        for (a in args) {
            if (a == "--serve") { wantsServe = 1 }
        }
        if (wantsServe == 1) {
            httpServe(8080, dispatchPending)
        }
    }
}

function dispatchPending(req: Map<string, string>): string {
    return httpResponse(503, "text/plain", "dispatcher pending I014 — see docs/4-issues/I014-spring-dispatch-impl.md")
}
