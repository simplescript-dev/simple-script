// I021-requestbody-nested-array-primitive — 嵌套 Array<int|string|double|bool> 反序列化
// 验 emitClassDeserializeFn isArrayDeserializable 谓词扩 + Array 分支 elemType 4+1 路分派
//   + lib/json.ss 4 raw helper(jnArrayGetInt/String/Double/Bool 委托 jnArrayGet + parseXxx)
//   + ss_newArray(tag=1, int/double/bool)vs ss_newArrayPtr(tag=5, string)二族 tag 选择
//   + Array<string> elem retain 契约(emitRetainForType,push 后 jnStr ptr 持新 RC)
//   + 父 ss_drop_<Outer> 链 tag=1 仅 free 容器 / tag=5 逐元素 ss_release_str 自动
//
// fix at: bootstrap/gen/gen_deserialize.ss:isArrayDeserializable + emitClassDeserializeFn
//       + lib/json.ss:jnArrayGetInt / jnArrayGetString / jnArrayGetDouble / jnArrayGetBool
//
// Coverage:
//   ① Array<string> length=3 — tags 元素相加 abc(string elem retain + tag=5 free 链)
//   ② Array<int> length=3 — scores 求和 60(int sext + tag=1)
//   ③ Array<double> length=2 — prices 求和 4.0(double bitcast + tag=1)
//   ④ Array<bool> length=2 — flags 逻辑 1/0(bool zext + tag=1)
//   ⑤ Array<int> 空数组 — length=0 RC 不破裂(ss_newArray tag=1 容器 free)
//   ⑥ Array<string> 空数组 — length=0 RC 不破裂(ss_newArrayPtr tag=5 elem 0 iter)
//   ⑦ 全链路 raw HTTP POST /orders-prim parseRequest → dispatchBody

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class OrderPrim {
    customer: string
    tags: Array<string>
    scores: Array<int>
    prices: Array<double>
    flags: Array<bool>
}

@RestController
class OrderPrimCtl {
    @PostMapping(path = "/orders-prim")
    function createOrderPrim(@RequestBody order: OrderPrim): string {
        let tagSum = ""
        let i = 0
        while (i < order.tags.length()) {
            tagSum = tagSum + order.tags[i]
            i = i + 1
        }
        let scoreSum = 0
        let j = 0
        while (j < order.scores.length()) {
            scoreSum = scoreSum + order.scores[j]
            j = j + 1
        }
        let priceSum = 0.0
        let k = 0
        while (k < order.prices.length()) {
            priceSum = priceSum + order.prices[k]
            k = k + 1
        }
        let flagsLen = order.flags.length()
        let flag0 = 0
        let flag1 = 0
        if (flagsLen > 0) { flag0 = order.flags[0] }
        if (flagsLen > 1) { flag1 = order.flags[1] }
        return `customer=${order.customer},tags=${tagSum},scores=${scoreSum},prices=${priceSum},flags=${flag0}/${flag1},lens=${order.tags.length()}/${order.scores.length()}/${order.prices.length()}/${flagsLen}`
    }
}

function main() {
    test("I021-array-primitive Array<string> length=3 — tags abc + retain 契约", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-prim")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"alice\",\"tags\":[\"a\",\"b\",\"c\"],\"scores\":[],\"prices\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,tags=abc,scores=0,prices=0,flags=0/0,lens=3/0/0/0")
    })

    test("I021-array-primitive Array<int> length=3 — scores 求和 60(sext + tag=1)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-prim")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"bob\",\"tags\":[],\"scores\":[10,20,30],\"prices\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,tags=,scores=60,prices=0,flags=0/0,lens=0/3/0/0")
    })

    test("I021-array-primitive Array<double> length=2 — prices 求和(bitcast + tag=1)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-prim")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"carol\",\"tags\":[],\"scores\":[],\"prices\":[1.5,2.5],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=carol,tags=,scores=0,prices=4,flags=0/0,lens=0/0/2/0")
    })

    test("I021-array-primitive Array<bool> length=2 — flags 1/0(zext + tag=1)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-prim")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"dave\",\"tags\":[],\"scores\":[],\"prices\":[],\"flags\":[true,false]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=dave,tags=,scores=0,prices=0,flags=1/0,lens=0/0/0/2")
    })

    test("I021-array-primitive Array<int> 空数组 — length=0 RC 不破裂(tag=1 容器 free)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-prim")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"eve\",\"tags\":[],\"scores\":[],\"prices\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=eve,tags=,scores=0,prices=0,flags=0/0,lens=0/0/0/0")
    })

    test("I021-array-primitive Array<string> 空数组 — tag=5 elem 0 iter 不触发 release", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders-prim")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"frank\",\"tags\":[],\"scores\":[1],\"prices\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=frank,tags=,scores=1,prices=0,flags=0/0,lens=0/1/0/0")
    })

    test("I021-array-primitive 全链路 raw HTTP POST /orders-prim — 4 elemType 同 body", () => {
        const raw = "POST /orders-prim HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"grace\",\"tags\":[\"x\",\"y\"],\"scores\":[7,13],\"prices\":[0.5,1.5],\"flags\":[true,true]}"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=grace,tags=xy,scores=20,prices=2,flags=1/1,lens=2/2/2/2")
    })
}
