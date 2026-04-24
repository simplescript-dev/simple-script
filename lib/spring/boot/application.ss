// D123 Phase 2 — @SpringBootApplication entrypoint + @RestController/@GetMapping 路由分派
// I014 §路径 A:dispatch(req) 用 ct-array<RouteMeta> for-in unroll + `r.invoke(req)` sentinel
// 触发 method_call.ss 识别 className+methodName 字段对组合,emit `call ptr @<cn>_<mn>(ptr null, ptr %req)`
// 静态 IR;禁 runtime 反射 / @comptimeEmit / @derive(D088 §反模式 L377-386)。
// I018 §路径 A:r.invoke(req) 透传 runtime req map 指针,Controller 方法按形参签名接收
// (funcParamCount 在 gen/class/class_method.ss 注册,invoke sentinel 按 arity 追加 ptr)。
//
// I015 §路径 A:routes comptime block 抽顶级 const,SpringApplication.run + dispatch 共享
// 单一 ctVars binding(D128 §A.1/A.2 顶级 ctArray 全局 scope `:_ssRoutes`),消除跨函数 copy-paste。
// controllerNames 由 _ssRoutes 派生(去重 className),避免双 comptime block。

import { httpServe, httpResponse } from "@/lib/http"

class RouteMeta {
    path: string
    className: string
    methodName: string
}

const _ssRoutes: Array<RouteMeta> = comptime {
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

class SpringApplication {
    static function run(appName: string, args: Array<string>) {
        let controllerNames = ""
        // seenClassNames value=1 表已见(SS 无 Set 类型,Map<string,int> 当 set 用)
        let seenClassNames: Map<string, int> = new Map()
        for (r in _ssRoutes) {
            if (seenClassNames.has(r.className) == 0) {
                seenClassNames.set(r.className, 1)
                if (controllerNames != "") { controllerNames = controllerNames + "," }
                controllerNames = controllerNames + r.className
            }
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
        for (r in _ssRoutes) {
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
    const path = req.get("path")
    for (r in _ssRoutes) {
        if (r.path == path) {
            return httpResponse(200, "text/plain", r.invoke(req))
        }
    }
    return httpResponse(404, "text/plain", "not found")
}
