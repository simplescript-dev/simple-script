// D123 Phase 3 Step 1 / I018 §路径 A — Controller 方法接收 req map 并 getString 取值。
// 本测试仅验证 Controller body 语义(走 genMethodCall 常规路径);invoke sentinel 透传的 E2E
// 由 curl `:8080/hello?name=SS == "Hello, SS!"` 补齐(见 I018 §判据)。

import { assertEqual } from "@/lib/test"

class TestBindController {
    function hi(req: Map<string, string>): string {
        return "Hi, " + req.getString("name") + "!"
    }
}

function main() {
    test("Controller req map 参数绑定 — D123 Phase 3 Step 1 / I018 GREEN", () => {
        const ctl = new TestBindController()
        const req: Map<string, string> = new Map()
        req.set("name", "SS")
        assertEqual(ctl.hi(req), "Hi, SS!")
    })
}
