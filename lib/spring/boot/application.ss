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
//
// I021-pathvariable:@PathVariable 路径占位符绑参 — comptime 加 "PathVariable" kind + matchPath
// runtime helper 路径模式匹配(`{name}` 段 buffered commit,防失败早期 set 污染);invoke sentinel
// 加 kind == "PathVariable" 分支 emit ss_mapGetString(req, "__pv_<name>") 复用 RequestParam
// cast 通道(int/double/ptr),`__pv_` 独立 namespace 与 query 严格分离。
//
// I021-requestbody:@RequestBody POST/PUT/PATCH JSON body → class 反序列化 — comptime 加
// "RequestBody" kind + RouteMeta 扩 httpMethod slot(GET/POST/PUT/DELETE/PATCH dispatch 区分);
// dispatcher matchPath 同 path 不同 method 各 route;invoke sentinel kind == "RequestBody" 分支
// emit ss_mapGetString(req, "body") + JSON_parse + @ClassName_deserialize per-class codegen
// 自动生成(mirror ss_drop_X / ss_deep_clone_X 模式 — D018 + D022 第四步 deserializer)。
// body key 直接用 "body"(对齐 lib/http.ss:83 split body 入此 key,无 namespace 撞名风险 —
// __pv_ 是 path variable name 可能撞 query key 才需 prefix,body 是单值)。
// RouteMeta.httpMethod 是项目内部 routing 数据扩字段(与 ParamMeta/MethodMeta 反射 Meta 不同),
// D123 §253 alignment 限定反射 Meta 不扩,RouteMeta 扩 httpMethod 是 routing dispatch 必需。

import { httpServe, httpResponse } from "@/lib/http"
// I021-requestbody — import lib/json 让 JsonNode struct + JSON_parse + jnGet* 进编译单元;
// invoke sentinel kind == "RequestBody" emit IR 直接引用 %JsonNode struct + @JSON_parse
// + @jnGet* per-class deserializer 字段提取 — bootstrap/eval/method_call.ss:159 §RequestBody 分支。
import { JSON_parse } from "@/lib/json"

class RouteMeta {
    path: string
    httpMethod: string
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
// **bootstrap 编译器侧** sentinel 同名字面量(`bootstrap/eval/method_call.ss:135, 154, 178`)
// 因跨域无 ct const 共享通道走硬编;改名时两端必须同步。
const PARAM_KIND_REQUEST_PARAM = "RequestParam"
const PARAM_KIND_REQUEST_MAP = "RequestMap"
const PARAM_KIND_PATH_VARIABLE = "PathVariable"
const PARAM_KIND_REQUEST_BODY = "RequestBody"

const _ssRoutes: Array<RouteMeta> = comptime {
    let arr: Array<RouteMeta> = []
    for (c in reflect.classes()) {
        for (cAnn in c.annotations) {
            if (cAnn.name == "RestController") {
                for (m in c.methods) {
                    for (mAnn in m.annotations) {
                        let httpMethod = ""
                        if (mAnn.name == "GetMapping") { httpMethod = "GET" }
                        else if (mAnn.name == "PostMapping") { httpMethod = "POST" }
                        else if (mAnn.name == "PutMapping") { httpMethod = "PUT" }
                        else if (mAnn.name == "DeleteMapping") { httpMethod = "DELETE" }
                        else if (mAnn.name == "PatchMapping") { httpMethod = "PATCH" }
                        if (httpMethod != "") {
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
                                    if (pAnn.name == "PathVariable") {
                                        specs = specs.push(new ParamSpec(
                                            kind: PARAM_KIND_PATH_VARIABLE,
                                            name: pAnn.args.getString("name"),
                                            type: p.type
                                        ))
                                        matched = 1
                                    }
                                    if (pAnn.name == "RequestBody") {
                                        specs = specs.push(new ParamSpec(
                                            kind: PARAM_KIND_REQUEST_BODY,
                                            name: p.name,
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
                                httpMethod: httpMethod,
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

// matchPath:路径模式匹配 + 占位符 buffered commit。占位符段 `{name}` 先缓冲到本地
// pvNames/pvValues 数组,**全段成功匹配**后才一次性 `req.set("__pv_<name>", value)` 提交 —
// 防失败早期 set 污染 req 让后续路由 fallback 看到脏 __pv_<name>。`__pv_` 独立 namespace 与
// RequestParam query 严格分离。invoke sentinel 端取值见 `bootstrap/eval/method_call.ss:135 §useParamSpecs`。
function matchPath(pattern: string, pathSegs: Array<string>, req: Map<string, string>): int {
    const patSegs = pattern.split("/")
    if (patSegs.length() != pathSegs.length()) { return 0 }
    let pvNames: Array<string> = []
    let pvValues: Array<string> = []
    let i = 0
    while (i < patSegs.length()) {
        const patSeg = patSegs[i]
        const pathSeg = pathSegs[i]
        const patLen = patSeg.length()
        if (patLen >= 2 && patSeg.charAt(0) == "{" && patSeg.charAt(patLen - 1) == "}") {
            pvNames = pvNames.push(patSeg.substring(1, patLen - 2))
            pvValues = pvValues.push(pathSeg)
        } else if (patSeg != pathSeg) {
            return 0
        }
        i = i + 1
    }
    let j = 0
    while (j < pvNames.length()) {
        req.set("__pv_" + pvNames[j], pvValues[j])
        j = j + 1
    }
    return 1
}

function dispatch(req: Map<string, string>): string {
    const path = req.get("path")
    const httpMethod = req.get("method")
    const pathSegs = path.split("/")
    for (r in _ssRoutes) {
        if (r.httpMethod == httpMethod && matchPath(r.path, pathSegs, req) == 1) {
            // r.invoke(req) — invoke sentinel 自驱展开多 spec(method_call.ss:86-160 §useParamSpecs)
            return httpResponse(200, "text/plain", r.invoke(req))
        }
    }
    return httpResponse(404, "text/plain", "not found")
}

// dispatch 返完整 HTTP response(headers + body),日志/测试场景剥头取 body。
function dispatchBody(resp: string): string {
    const sep = "\r\n\r\n"
    const idx = resp.indexOf(sep)
    if (idx < 0) { return resp }
    return resp.substring(idx + 4, resp.length())
}
