// I021-pathvariable — @PathVariable 路径占位符绑参端到端测试
// 验 dispatcher matchPath 路径模式匹配 + 占位符写回 req map __pv_ prefix 独立 namespace,
// invoke sentinel kind == "PathVariable" emit ss_mapGetString(req, "__pv_<name>") + 复用
// RequestParam cast 通道(int/double/ptr 分派);消除 dispatcher 字面相等单形 silent 404。
//
// fix at: lib/spring/boot/application.ss matchPath + dispatcher
//       + bootstrap/eval/method_call.ss:135 §useParamSpecs PathVariable kind 分支
//
// Coverage:
//   ① 单占位 int — /users/{id} → "user=42"(主用例,RED 由 silent 404 → "user=42" 翻 GREEN)
//   ② 多占位 int+int — /u/{uid}/o/{oid} 双占位符独立 __pv_uid / __pv_oid namespace
//   ③ 静态路由 backward compat — /static 无占位段走 matchPath 逐段字面相等等价旧 r.path == path
//   ④ string 占位 — /profile/{name} 验 cast 通道默认 ptr 分派(无 parseInt/parseDouble)
//   ⑤ 404 路径段数不匹配 — /users/42/extra(实际 4 段 vs pattern 3 段)
//   ⑥ 静态 IR 锚 — `grep "ss_mapGetString.*__pv_id" main.ll` ≥ 1 由 shell-level 验
//
// 本文件承载 ①②③④⑤,⑥ 由 shell-level grep 验证(MNK §VCM §2)。

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"

@RestController
class PvCtl {
    @GetMapping(path = "/users/{id}")
    function showUser(@PathVariable(name = "id") id: int): string {
        return "user=" + id
    }

    @GetMapping(path = "/u/{uid}/o/{oid}")
    function showOrder(@PathVariable(name = "uid") uid: int, @PathVariable(name = "oid") oid: int): string {
        return "user=" + uid + ",order=" + oid
    }

    @GetMapping(path = "/static")
    function staticHandler(): string {
        return "static:ok"
    }

    @GetMapping(path = "/profile/{name}")
    function showProfile(@PathVariable(name = "name") name: string): string {
        return "profile:" + name
    }
}

function main() {
    test("I021-pathvariable 单占位 int — /users/{id} → user=42 GREEN", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/users/42")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "user=42")
    })

    test("I021-pathvariable 多占位 int+int — /u/{uid}/o/{oid} 独立 namespace", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/u/7/o/123")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "user=7,order=123")
    })

    test("I021-pathvariable 静态路由 backward compat — /static 无占位等价旧字面相等", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/static")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "static:ok")
    })

    test("I021-pathvariable string 占位 — /profile/{name} cast 默认 ptr 分派", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/profile/alice")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "profile:alice")
    })

    test("I021-pathvariable 404 路径段数不匹配 — /users/42/extra", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/users/42/extra")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "not found")
    })
}

