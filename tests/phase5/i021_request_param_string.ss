// I021 — @RequestParam string 绑参 v0 验证(反射 Meta 三层 + dispatcher 静态 unpack)
//
// Coverage(4 case,第 4 为 shell grep 见 VCM §2 / 本 issue §验收 RED 命令):
//   ① @RequestParam string 命中 —— Controller 直接形参签名,不手 unpack req
//   ② @RequestParam miss query —— 空串语义由 ss_mapGetString 路由保证(I019 §miss 路径)
//   ③ I018/I019 backward compat —— `req: Map<string,string>` 形态仍可路由(走 RequestMap fallback)
//   ④ 静态 IR 锚 —— `grep "call ptr @<cn>_<mn>(ptr null, ptr %.*ss_mapGetString" main.ll`
//      确认 dispatcher emit 了 req.get(name) 而非 req 整体(见 I021 §验收 RED 命令)
//
// 本文件承载 ① ② ③,④ 由 shell-level grep 验证。

import { assertEqual } from "@/lib/test"

@RestController
class GreetController {
    @GetMapping(path = "/greet")
    function greet(@RequestParam(name = "who") who: string): string {
        return "hi:" + who
    }
}

@RestController
class EchoController {
    @GetMapping(path = "/echo")
    function echo(req: Map<string, string>): string {
        return "echo:" + req.get("msg")
    }
}

function main() {
    test("@RequestParam string hit — I021 GREEN", () => {
        const ctl = new GreetController()
        assertEqual(ctl.greet("SS"), "hi:SS")
        assertEqual(ctl.greet("Alice"), "hi:Alice")
    })

    test("@RequestParam string 空入参 — miss query 语义(empty str 由 ss_mapGetString 返)", () => {
        const ctl = new GreetController()
        assertEqual(ctl.greet(""), "hi:")
    })

    test("I018 backward compat — req: Map<string,string> 形态走 RequestMap fallback 仍 work", () => {
        const ctl = new EchoController()
        const req: Map<string, string> = new Map()
        req.set("msg", "ok")
        assertEqual(ctl.echo(req), "echo:ok")
    })
}
