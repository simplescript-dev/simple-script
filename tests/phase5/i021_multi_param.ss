// I021-multi-param — @RequestParam 多参绑参端到端测试
// 验 invoke sentinel 数据驱动展开:dispatch 单调用 r.invoke(req),sentinel 按
// r.paramSpecs N 个 spec 自驱 emit 多参实参表(每个 RequestParam emit ss_mapGetString +
// typed cast,RequestMap 透传 reqReg),消除 dispatch spec loop 各发独立 invoke 的
// silent miscompile 双轨。
//
// fix at: bootstrap/eval/method_call.ss:86-160 §useParamSpecs 分支
//       + lib/spring/boot/application.ss:122-141 dispatch 单调用形态
//
// Coverage:
//   ① 双参 int+int — sum=x+y(主用例,RED 由 sum=0 → sum=30 翻 GREEN)
//   ② 三参混合 string+int+double — 验 sentinel 数据驱动按 spec.type 分派 cast 全 type
//   ③ I021 / I021bc 单参 backward compat regression(hello/age/calc 仍 work via dispatch)
//   ④ I018 RequestMap backward compat — 整 req map 透传形态仍 work
//   ⑤ 静态 IR 锚 — `grep "call ptr @MultiCtl_add(ptr null, i32 %.*, i32 %.*)" main.ll` ≥ 1
//
// 本文件承载 ①②③④,⑤ 由 shell-level grep 验证(MNK §VCM §2)。
// 注:同 codepath 边际效益评估 — 双 int 仅留主用例 ①,不另设"边界值"重复 case。

import { assertEqual } from "@/lib/test"
import { dispatch } from "@/lib/spring/boot/application"

@RestController
class MultiCtl {
    @GetMapping(path = "/add")
    function add(@RequestParam(name = "x") x: int, @RequestParam(name = "y") y: int): string {
        return "sum=" + (x + y)
    }

    @GetMapping(path = "/mix")
    function mix(@RequestParam(name = "s") s: string, @RequestParam(name = "n") n: int, @RequestParam(name = "d") d: double): string {
        return "s=" + s + " n=" + n + " d=" + d
    }

    @GetMapping(path = "/single")
    function single(@RequestParam(name = "name") name: string): string {
        return "single:" + name
    }
}

@RestController
class MapCtl {
    @GetMapping(path = "/echo")
    function echo(req: Map<string, string>): string {
        return "echo:" + req.get("msg")
    }
}

function main() {
    test("I021-multi-param 双参 int+int — dispatch 单调用 sentinel 多参展开 GREEN", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/add")
        req.set("x", "10")
        req.set("y", "20")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "sum=30")
    })

    test("I021-multi-param 三参混合 string+int+double — 全 spec.type 分派 cast", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/mix")
        req.set("s", "hello")
        req.set("n", "42")
        req.set("d", "3.14")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "s=hello n=42 d=3.14")
    })

    test("I021 单参 backward compat regression — hello via dispatch 仍 work", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/single")
        req.set("name", "SS")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "single:SS")
    })

    test("I018 RequestMap backward compat — 整 req map 透传 fallback 仍 work", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/echo")
        req.set("msg", "ok")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "echo:ok")
    })
}

// dispatch 返完整 HTTP response(headers + body),测试只取 body 比对
function dispatchBody(resp: string): string {
    const sep = "\r\n\r\n"
    const idx = resp.indexOf(sep)
    if (idx < 0) { return resp }
    return resp.substring(idx + 4, resp.length())
}
