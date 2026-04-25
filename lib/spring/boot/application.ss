// D123 Phase 2 — @SpringBootApplication entrypoint + @RestController/@GetMapping 路由分派
// I014 §路径 A:dispatch(req) 用 ct-array<RouteMeta> for-in unroll + `r.invoke(...)` sentinel
// 触发 method_call.ss 识别 className+methodName 字段对组合,emit `call ptr @<cn>_<mn>(ptr null, ...)`
// 静态 IR;禁 runtime 反射 / @comptimeEmit / @derive(D088 §反模式 L377-386)。
// I018 §路径 A:r.invoke(...) 透传 runtime ptr,Controller 方法按形参签名接收
// (funcParamCount 在 gen/class/class_method.ss 注册,invoke sentinel 按 arity 追加 ptr)。
//
// I015 §路径 A:routes comptime block 抽顶级 const,SpringApplication.run + dispatch 共享
// 单一 ctVars binding(D128 §A.1/A.2 顶级 ctArray 全局 scope `:_ssRoutes`),消除跨函数 copy-paste。
// controllerNames 由 _ssRoutes 派生(去重 className),避免双 comptime block。
//
// I021 §路径 A:RouteMeta 扩 paramSpecs: Array<ParamSpec>,comptime 遍历 m.params +
// p.annotations 提取 (kind, name, type)。ParamSpec 是应用层 spec 容器(非反射 Meta),
// 不影响 D123 §253 "不新建 Meta" 合规面。
//
// I021-multi-param:dispatcher 单次 `r.invoke(req)` 调用,invoke sentinel 按 r.paramSpecs
// ct 元数据自驱展开多 spec 实参表(每个 RequestParam emit ss_mapGetString + typed cast 按
// spec.type 分派 i32/double/ptr;RequestMap 透传 reqReg),消除多 spec 各发独立 invoke 的
// silent miscompile。具体在 bootstrap/eval/method_call.ss:86-160 §useParamSpecs 分支。

import { httpServe, httpResponse } from "@/lib/http"

class RouteMeta {
    path: string
    className: string
    methodName: string
    paramSpecs: Array<ParamSpec>
}

class ParamSpec {
    kind: string
    name: string
    type: string
}

// ParamSpec.kind 标记,只在本文件 _ssRoutes comptime push 端用(抽常量防拼写错)。
// **bootstrap 编译器侧** sentinel 同名字面量(`bootstrap/eval/method_call.ss:135, 154`)
// 因跨域无 ct const 共享通道走硬编;改名时两端必须同步。
const PARAM_KIND_REQUEST_PARAM = "RequestParam"
const PARAM_KIND_REQUEST_MAP = "RequestMap"

const _ssRoutes: Array<RouteMeta> = comptime {
    let arr: Array<RouteMeta> = []
    for (c in reflect.classes()) {
        for (cAnn in c.annotations) {
            if (cAnn.name == "RestController") {
                for (m in c.methods) {
                    for (mAnn in m.annotations) {
                        if (mAnn.name == "GetMapping") {
                            let specs: Array<ParamSpec> = []
                            for (p in m.params) {
                                let matched = 0
                                for (pAnn in p.annotations) {
                                    if (pAnn.name == "RequestParam") {
                                        specs = specs.push(new ParamSpec(
                                            kind: PARAM_KIND_REQUEST_PARAM,
                                            name: pAnn.args.getString("name"),
                                            type: p.type
                                        ))
                                        matched = 1
                                    }
                                }
                                if (matched == 0 && p.type == "Map<string, string>") {
                                    specs = specs.push(new ParamSpec(
                                        kind: PARAM_KIND_REQUEST_MAP,
                                        name: p.name,
                                        type: p.type
                                    ))
                                }
                            }
                            arr = arr.push(new RouteMeta(
                                path: mAnn.args.getString("path"),
                                className: c.name,
                                methodName: m.name,
                                paramSpecs: specs
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
            // I021-multi-param — invoke sentinel 数据驱动模式:sentinel 按 r.paramSpecs ct
            // 元数据自驱展开多 spec 实参表(每个 RequestParam emit ss_mapGetString + typed cast,
            // RequestMap 透传 reqReg),消除 dispatch 内 spec loop 各发独立 invoke 的多参 silent
            // miscompile。dispatch 这里单次 r.invoke(req) 调用,具体实参展开见
            // bootstrap/eval/method_call.ss:86-160 invoke sentinel §useParamSpecs 分支。
            return httpResponse(200, "text/plain", r.invoke(req))
        }
    }
    return httpResponse(404, "text/plain", "not found")
}
