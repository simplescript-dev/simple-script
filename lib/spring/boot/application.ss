// D123 Phase 2 — @SpringBootApplication entrypoint + @RestController/@GetMapping 路由分派
// I014 §路径 A:dispatch(req) 用 ct-array<RouteMeta> for-in unroll + `r.invoke()` sentinel
// 触发 method_call.ss 识别 className+methodName 字段对组合,emit `call ptr @<cn>_<mn>()`
// 静态 IR;禁 runtime 反射 / @comptimeEmit / @derive(D088 §反模式 L377-386)。

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

        const routes = comptime {
            let arr: Array<RouteMeta> = []
            for (c in reflect.classes()) {
                for (cAnn in c.annotations) {
                    if (cAnn.name == "RestController") {
                        for (m in c.methods) {
                            for (mAnn in m.annotations) {
                                if (mAnn.name == "GetMapping") {
                                    arr = arr.push(new RouteMeta(
                                        path: mAnn.args.getString("path"),
                                        className: c.name,
                                        methodName: m.name
                                    ))
                                }
                            }
                        }
                    }
                }
            }
            return arr
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

        let routesCsv = ""
        for (r in routes) {
            routesCsv = routesCsv + r.path + "|" + r.className + "." + r.methodName + ";"
        }
        println("Routes: " + routesCsv)

        // --serve 才启动 httpServe(阻塞 listen);默认入口仅打印 routes csv 退出。
        let wantsServe = 0
        for (a in args) {
            if (a == "--serve") { wantsServe = 1 }
        }
        if (wantsServe == 1) {
            httpServe(8080, dispatch)
        }
    }
}

function dispatch(req: Map<string, string>): string {
    const routes = comptime {
        let arr: Array<RouteMeta> = []
        for (c in reflect.classes()) {
            for (cAnn in c.annotations) {
                if (cAnn.name == "RestController") {
                    for (m in c.methods) {
                        for (mAnn in m.annotations) {
                            if (mAnn.name == "GetMapping") {
                                arr = arr.push(new RouteMeta(
                                    path: mAnn.args.getString("path"),
                                    className: c.name,
                                    methodName: m.name
                                ))
                            }
                        }
                    }
                }
            }
        }
        return arr
    }
    const path = req.get("path")
    for (r in routes) {
        if (r.path == path) {
            return httpResponse(200, "text/plain", r.invoke())
        }
    }
    return httpResponse(404, "text/plain", "not found")
}
