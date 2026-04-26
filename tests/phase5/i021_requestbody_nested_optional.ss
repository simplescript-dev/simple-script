// I021-requestbody-nested-optional — 嵌套 nullable user class 字段反序列化
//
// D067 narrow 现状:check_narrow.ss:12-26 extractNullCheckVar 只 cover IDENT 形态,
//   `order.addr != null` member access narrow 不生效 → 用户层 `let a = order.addr`
//   binding 走 IDENT narrow(D067 现状合法形态);member access narrow 留 D067 子档。

import { test, assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Address {
    city: string
    zip: string
}

class OrderOpt {
    customer: string
    addr: Address?
}

@RestController
class OrderOptCtl {
    @PostMapping(path = "/orders/optional")
    function createOrderOpt(@RequestBody order: OrderOpt): string {
        let a = order.addr
        if (a != null) {
            return "customer=" + order.customer + ",city=" + a.city
        }
        return "customer=" + order.customer + ",no-addr"
    }
}

function main() {
    test("I021-requestbody-nested-optional ① addr 存在 — narrow let a 走 if 分支 city=NYC", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/optional")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"alice\",\"addr\":{\"city\":\"NYC\",\"zip\":\"10001\"}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,city=NYC")
    })

    test("I021-requestbody-nested-optional ② addr JSON null literal — narrow let a 走 else 分支 no-addr", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/optional")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"bob\",\"addr\":null}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,no-addr")
    })

    test("I021-requestbody-nested-optional ③ addr 字段缺失 — narrow let a 走 else 分支 no-addr", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/optional")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"carol\"}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=carol,no-addr")
    })

    test("I021-requestbody-nested-optional ④ 全链路 raw HTTP — parseRequest POST /orders/optional 三场景", () => {
        const raw1 = "POST /orders/optional HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"dave\",\"addr\":{\"city\":\"LA\",\"zip\":\"90001\"}}"
        const req1 = parseRequest(raw1)
        assertEqual(dispatchBody(dispatch(req1)), "customer=dave,city=LA")

        const raw2 = "POST /orders/optional HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"eve\",\"addr\":null}"
        const req2 = parseRequest(raw2)
        assertEqual(dispatchBody(dispatch(req2)), "customer=eve,no-addr")

        const raw3 = "POST /orders/optional HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"frank\"}"
        const req3 = parseRequest(raw3)
        assertEqual(dispatchBody(dispatch(req3)), "customer=frank,no-addr")
    })

    test("I021-requestbody-nested-optional ⑤ RC 契约严审 — case 1 重复 dispatchBody 50 次不破裂", () => {
        let i = 0
        while (i < 50) {
            let req: Map<string, string> = new Map()
            req.set("path", "/orders/optional")
            req.set("method", "POST")
            req.set("body", "{\"customer\":\"alice\",\"addr\":{\"city\":\"NYC\",\"zip\":\"10001\"}}")
            const body = dispatchBody(dispatch(req))
            assertEqual(body, "customer=alice,city=NYC")
            i = i + 1
        }
    })
}
