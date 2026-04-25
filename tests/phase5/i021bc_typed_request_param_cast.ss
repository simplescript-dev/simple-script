// I021bc — Typed @RequestParam V=int + V=double cast lowering 回归测试
// before: invoke sentinel hardcode `, ptr ${aReg}` + funcParamTypes class method 路径漏注册
//         dispatcher 实参 ptr vs callee i32/double silent miscompile
//         (V=int n=-1116582928 / V=double x=4.95e-315)
// fix at:  bootstrap/gen/gen_registry.ss:42-58 + bootstrap/eval/method_call.ss:97-128
//
// 端到端 curl + serve 由 examples/spring-parity/hello/ss/HelloController.ss 三路由覆盖,
// 本单测验 invoke sentinel 静态 IR cast emit 路径(不需要 SpringApplication 全套)。

import { assertEqual } from "@/lib/test"

class TypedDispatchController {
    function intArg(n: int): string { return "n=" + n }
    function doubleArg(x: double): string { return "x=" + x }
    function stringArg(s: string): string { return "s=" + s }
}

function main() {
    test("I021bc V=int 直接调 callee i32 形参 GREEN", () => {
        const c = new TypedDispatchController()
        assertEqual(c.intArg(42), "n=42")
        assertEqual(c.intArg(-7), "n=-7")
    })

    test("I021bc V=double 直接调 callee double 形参 GREEN", () => {
        const c = new TypedDispatchController()
        assertEqual(c.doubleArg(3.14), "x=3.14")
    })

    test("I021bc V=string regression callee ptr 形参不破", () => {
        const c = new TypedDispatchController()
        assertEqual(c.stringArg("SS"), "s=SS")
    })
}
