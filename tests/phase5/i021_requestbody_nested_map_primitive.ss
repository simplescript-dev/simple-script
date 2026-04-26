// I021-requestbody-nested-map-primitive(D130)— 嵌套 Map<string, int|string|double|bool>
// primitive value 反序列化 + RC + val_type 二分契约实测
//
// 验 emitDeserializeForType SSoT primitive 4 路 (gen_deserialize.ss:91-119)
//   + emitMapDeserializeInto inner value dispatch 委托 (line 230)
//   + ss_mapSet i64 直存 (sext int / bitcast double / zext bool / ptrtoint string)
//   + emitMapDeserializeInto val_type=1 写 offset 516 仅 ssTypeToLLVM(vType)=="ptr" (line 201-205)
//   → ss_rc_destroy_map val_type 字段判定:val_type=0 仅 free 容器 / val_type=1 逐 entry release
//   + 父 ss_drop_OrderConfig 链 4 vType Map 字段全 release 不破裂
//
// 自动覆盖路径 (零 codegen 改动):D130 SSoT 收敛 c52e9b5 已设计承载,本子档纯 RED 锁定
//
// Coverage:
//   ① Map<string, string> size=2 — env=prod / region=us(val_type=1, ptr)
//   ② Map<string, int>    size=2 — qty=100 / limit=500(sext + val_type=0)
//   ③ Map<string, double> size=1 — unit=1.5(bitcast + val_type=0;1.5 IEEE-754 精确)
//   ④ Map<string, bool>   size=1 — active=true(zext + val_type=0;SS bool=i32 1)
//   ⑤ 全空 Map {} 4 vType — size=0 4 字段父 OrderConfig drop 链不破裂
//   ⑥ 全链路 raw HTTP POST /orders/config — 4 vType 同 body 端到端

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class OrderConfig {
    customer: string
    tags: Map<string, string>
    scores: Map<string, int>
    prices: Map<string, double>
    flags: Map<string, bool>
}

@RestController
class OrderConfigCtl {
    @PostMapping(path = "/orders/config")
    function createOrderConfig(@RequestBody order: OrderConfig): string {
        const envS = order.tags.get("env")
        const regionS = order.tags.get("region")
        const qty = order.scores.get("qty")
        const limit = order.scores.get("limit")
        const unit = order.prices.get("unit")
        const active = order.flags.get("active")
        let activeI = 0
        if (active) { activeI = 1 }
        return `customer=${order.customer},sizes=${order.tags.size()}/${order.scores.size()}/${order.prices.size()}/${order.flags.size()},tags=${envS}/${regionS},scores=${qty}/${limit},unit=${unit},active=${activeI}`
    }
}

function main() {
    test("I021-map-primitive Map<string, string> size=2 — val_type=1 + ptrtoint contract", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/config")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"alice\",\"tags\":{\"env\":\"prod\",\"region\":\"us\"},\"scores\":{},\"prices\":{},\"flags\":{}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,sizes=2/0/0/0,tags=prod/us,scores=0/0,unit=0,active=0")
    })

    test("I021-map-primitive Map<string, int> size=2 — sext + val_type=0 contract", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/config")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"bob\",\"tags\":{},\"scores\":{\"qty\":100,\"limit\":500},\"prices\":{},\"flags\":{}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,sizes=0/2/0/0,tags=/,scores=100/500,unit=0,active=0")
    })

    test("I021-map-primitive Map<string, double> size=1 — bitcast + val_type=0(1.5 IEEE-754 精确)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/config")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"carol\",\"tags\":{},\"scores\":{},\"prices\":{\"unit\":1.5},\"flags\":{}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=carol,sizes=0/0/1/0,tags=/,scores=0/0,unit=1.5,active=0")
    })

    test("I021-map-primitive Map<string, bool> size=1 — zext + val_type=0(SS bool=i32 1)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/config")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"dave\",\"tags\":{},\"scores\":{},\"prices\":{},\"flags\":{\"active\":true}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=dave,sizes=0/0/0/1,tags=/,scores=0/0,unit=0,active=1")
    })

    test("I021-map-primitive 全空 Map {} 4 vType — size=0 父 OrderConfig drop 链不破裂", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/config")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"eve\",\"tags\":{},\"scores\":{},\"prices\":{},\"flags\":{}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=eve,sizes=0/0/0/0,tags=/,scores=0/0,unit=0,active=0")
    })

    test("I021-map-primitive 全链路 raw HTTP POST /orders/config — 4 vType 同 body 端到端", () => {
        const raw = "POST /orders/config HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"frank\",\"tags\":{\"env\":\"prod\",\"region\":\"us\"},\"scores\":{\"qty\":100,\"limit\":500},\"prices\":{\"unit\":1.5},\"flags\":{\"active\":true}}"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=frank,sizes=2/2/1/1,tags=prod/us,scores=100/500,unit=1.5,active=1")
    })
}
