// I021-requestbody-nested — 嵌套 class 深度反序列化 RC 递归契约实测覆盖
// 验 emitClassDeserializeFn 嵌套 user class 字段递归 jnGetField + <NestedClass>_deserialize
//   + emitPendingDeserializers transitive closure(Outer 注册 → 嵌套 Customer/Address 自动加入 targets)
//
// fix at: bootstrap/gen/gen_type_ops.ss:emitClassDeserializeFn 嵌套 user class 字段 case
//       + bootstrap/gen/gen_type_ops.ss:emitPendingDeserializers transitive closure work-list
//
// Coverage:
//   ① 单层嵌套 — Order { customer: Customer, addr: Address } 双字段访问 → "customer=alice,city=sh"(主用例)
//   ② JSON 内层字段顺序乱 — {"customer":{"age":30,"name":"alice"},...} age 先 name 后 — 验内层字段顺序无关
//   ③ 嵌套 primitive int + string 混合 — /orders-detail 端点访问 customer.age int + customer.name string 双 primitive
//   ④ 全链路 raw HTTP — parseRequest POST /orders raw → dispatchBody(承接 I021-requestheader case 6 raw HTTP \r\n 协议)
//   ⑤ 静态 IR 锚 — shell-level `grep "@Customer_deserialize\|@Address_deserialize" /tmp/t_i021_nested.ll` ≥ 2 由 VCM §2 行为验
//
// 本文件承载 ①②③④,⑤ 由 shell-level grep 验证(MNK §VCM §2)。

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Address {
    city: string
    zip: string
}

class Customer {
    name: string
    age: int
}

class Order {
    customer: Customer
    addr: Address
}

@RestController
class OrderCtl {
    @PostMapping(path = "/orders")
    function createOrder(@RequestBody order: Order): string {
        return "customer=" + order.customer.name + ",city=" + order.addr.city
    }

    @PostMapping(path = "/orders-detail")
    function createOrderDetail(@RequestBody order: Order): string {
        return "name=" + order.customer.name + ",age=" + order.customer.age + ",city=" + order.addr.city
    }
}

function main() {
    test("I021-requestbody-nested 单层嵌套 — Order { customer, addr } 双字段访问 GREEN", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders")
        req.set("method", "POST")
        req.set("body", "{\"customer\":{\"name\":\"alice\",\"age\":30},\"addr\":{\"city\":\"sh\",\"zip\":\"200000\"}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,city=sh")
    })

    test("I021-requestbody-nested JSON 内层字段顺序乱 — age 先 name 后 vs class 声明顺序无关", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders")
        req.set("method", "POST")
        req.set("body", "{\"addr\":{\"zip\":\"100000\",\"city\":\"bj\"},\"customer\":{\"age\":42,\"name\":\"bob\"}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,city=bj")
    })

    test("I021-requestbody-nested 嵌套 primitive int + string — Customer.age int + Customer.name string 双 primitive", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-detail")
        req.set("method", "POST")
        req.set("body", "{\"customer\":{\"name\":\"charlie\",\"age\":25},\"addr\":{\"city\":\"gz\",\"zip\":\"510000\"}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=charlie,age=25,city=gz")
    })

    test("I021-requestbody-nested 全链路 raw HTTP — parseRequest POST /orders 整链路对齐", () => {
        const raw = "POST /orders HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":{\"name\":\"david\",\"age\":18},\"addr\":{\"city\":\"sz\",\"zip\":\"518000\"}}"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=david,city=sz")
    })
}
