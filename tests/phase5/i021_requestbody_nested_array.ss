// I021-requestbody-nested-array — 嵌套 Array<UserClass> 反序列化 RC 递归契约实测
// 验 emitClassDeserializeFn isArrayClass 字段 case + lib/json.ss jnArrayLen / jnArrayGet
//   + emitPendingDeserializers BFS Array<UserClass> 元素类型递归入队
//   + ss_arrayPush(transfer ownership 不 retain)+ ss_drop_<Outer> 链 Array 字段 release
//
// fix at: bootstrap/gen/gen_deserialize.ss:isArrayClass + emitClassDeserializeFn 分支
//       + bootstrap/gen/gen_deserialize.ss:emitPendingDeserializers BFS 扩 array elem
//       + lib/json.ss:jnArrayLen / jnArrayGet raw int 接口
//
// Coverage:
//   ① 单层 Array<Item> length=2 — OrderList { items: Array<Item> } 元素字段 + sum 值访问
//   ② 空数组 [] length=0 — RC 契约不破裂(ss_newArrayPtr(0) + ss_drop_OrderList free 容器)
//   ③ length=10 大数组 — element-wise deserialize + 循环 RC 链不爆栈
//   ④ 全链路 raw HTTP — parseRequest POST /orders-list raw → dispatchBody
//   ⑤ 静态 IR 锚 — shell-level `grep "@Item_deserialize\|jnArrayLen\|jnArrayGet" /tmp/t_i021_array.ll` ≥ 3 由 VCM §2 行为验

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Item {
    name: string
    price: int
}

class OrderList {
    customer: string
    items: Array<Item>
}

@RestController
class OrderListCtl {
    @PostMapping(path = "/orders-list")
    function createOrderList(@RequestBody order: OrderList): string {
        let total = 0
        let i = 0
        while (i < order.items.length()) {
            total = total + order.items[i].price
            i = i + 1
        }
        return "customer=" + order.customer + ",total=" + total + ",len=" + order.items.length()
    }
}

function main() {
    test("I021-requestbody-nested-array length=2 — Array<Item> 元素 scalar 字段 + sum 访问 GREEN", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-list")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"alice\",\"items\":[{\"name\":\"a\",\"price\":10},{\"name\":\"b\",\"price\":20}]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,total=30,len=2")
    })

    test("I021-requestbody-nested-array 空数组 length=0 — RC 契约不破裂", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-list")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"bob\",\"items\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,total=0,len=0")
    })

    test("I021-requestbody-nested-array length=10 大数组 — element-wise + RC 链不爆栈", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-list")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"carol\",\"items\":[{\"name\":\"i0\",\"price\":1},{\"name\":\"i1\",\"price\":2},{\"name\":\"i2\",\"price\":3},{\"name\":\"i3\",\"price\":4},{\"name\":\"i4\",\"price\":5},{\"name\":\"i5\",\"price\":6},{\"name\":\"i6\",\"price\":7},{\"name\":\"i7\",\"price\":8},{\"name\":\"i8\",\"price\":9},{\"name\":\"i9\",\"price\":10}]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=carol,total=55,len=10")
    })

    test("I021-requestbody-nested-array 全链路 raw HTTP — parseRequest POST /orders-list 整链路对齐", () => {
        const raw = "POST /orders-list HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"david\",\"items\":[{\"name\":\"x\",\"price\":7},{\"name\":\"y\",\"price\":13}]}"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=david,total=20,len=2")
    })
}
