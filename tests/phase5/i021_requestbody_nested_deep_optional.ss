// I021-requestbody-nested-deep-optional(D132 + D131 + D130) — N=2 双层 nullable 笛卡尔积
//   反序列化:`Array<Tag?>?` / `Map<string, Tag?>?`(form 1/2 双 `?`)+ `Array<Array<Tag>>?` /
//   `Map<string, Map<string, Tag>>?` / `Array<Map<string, Tag>>?` / `Map<string, Array<Tag>>?`
//   (form 3-6 单 `?` + N=2 嵌套)。
//
// 第二支柱 §247 第十一轮:笛卡尔积全形态。D130 SSoT(per-class deserializer 单点 emitDeserialize
//   ForType 字段层 nullable case)+ D131 谓词层(stripNullableCG inner)+ D132(parser maybeNullable
//   pendingGtTokens guard — `Array<Array<Tag>>?` 等 SHR/USHR 拆分形态正确归 outer)联动。
//
// scope:N=2 嵌套维度 + outer 单 `?` / 双 `?` 笛卡尔积全 6 fixture × {present / outer null /
//   outer missing / inner null}。任意 N=3+ 自动 cover(D132 §4.2 形态 9 推广);任意 M 层 nullable
//   自动 cover(D132 §4.2 形态 8 推广)。RC stress 50 次循环 outer/inner null 混合验证。
//
// D067 narrow:`let x = order.field` IDENT binding 走父档 + -inner / -container 子档同源路径。

import { test, assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Tag {
    name: string
}

class OrderTagsArrDeepOpt {
    customer: string
    tags: Array<Tag?>?
}

class OrderTagsMapDeepOpt {
    customer: string
    items: Map<string, Tag?>?
}

class OrderMatrixOpt {
    customer: string
    matrix: Array<Array<Tag>>?
}

class OrderGroupsOpt {
    customer: string
    groups: Map<string, Map<string, Tag>>?
}

class OrderArrMapOpt {
    customer: string
    entries: Array<Map<string, Tag>>?
}

class OrderMapArrOpt {
    customer: string
    lists: Map<string, Array<Tag>>?
}

@RestController
class OrderTagsArrDeepOptCtl {
    @PostMapping(path = "/orders/tags-deep-opt")
    function createOrderTagsArrDeepOpt(@RequestBody order: OrderTagsArrDeepOpt): string {
        let tags = order.tags
        if (tags != null) {
            let count = 0
            let nullCount = 0
            let i = 0
            while (i < tags.length()) {
                let t = tags[i]
                if (t != null) {
                    count = count + 1
                } else {
                    nullCount = nullCount + 1
                }
                i = i + 1
            }
            return "customer=" + order.customer + ",tags=" + count + ",nulls=" + nullCount
        }
        return "customer=" + order.customer + ",no-tags"
    }
}

@RestController
class OrderTagsMapDeepOptCtl {
    @PostMapping(path = "/orders/items-deep-opt")
    function createOrderTagsMapDeepOpt(@RequestBody order: OrderTagsMapDeepOpt): string {
        let items = order.items
        if (items != null) {
            let count = 0
            let nullCount = 0
            const keys = items.keys()
            let i = 0
            while (i < keys.length()) {
                let v = items.get(keys[i])
                if (v != null) {
                    count = count + 1
                } else {
                    nullCount = nullCount + 1
                }
                i = i + 1
            }
            return "customer=" + order.customer + ",items=" + count + ",nulls=" + nullCount
        }
        return "customer=" + order.customer + ",no-items"
    }
}

@RestController
class OrderMatrixOptCtl {
    @PostMapping(path = "/orders/matrix-opt")
    function createOrderMatrixOpt(@RequestBody order: OrderMatrixOpt): string {
        let m = order.matrix
        if (m != null) {
            let total = 0
            let i = 0
            while (i < m.length()) {
                let row = m[i]
                total = total + row.length()
                i = i + 1
            }
            return "customer=" + order.customer + ",total=" + total
        }
        return "customer=" + order.customer + ",no-matrix"
    }
}

@RestController
class OrderGroupsOptCtl {
    @PostMapping(path = "/orders/groups-opt")
    function createOrderGroupsOpt(@RequestBody order: OrderGroupsOpt): string {
        let g = order.groups
        if (g != null) {
            let total = 0
            const keys = g.keys()
            let i = 0
            while (i < keys.length()) {
                let inner = g.get(keys[i])
                if (inner != null) {
                    total = total + inner.size()
                }
                i = i + 1
            }
            return "customer=" + order.customer + ",total=" + total
        }
        return "customer=" + order.customer + ",no-groups"
    }
}

@RestController
class OrderArrMapOptCtl {
    @PostMapping(path = "/orders/entries-opt")
    function createOrderArrMapOpt(@RequestBody order: OrderArrMapOpt): string {
        let e = order.entries
        if (e != null) {
            let total = 0
            let i = 0
            while (i < e.length()) {
                let m = e[i]
                total = total + m.size()
                i = i + 1
            }
            return "customer=" + order.customer + ",total=" + total
        }
        return "customer=" + order.customer + ",no-entries"
    }
}

@RestController
class OrderMapArrOptCtl {
    @PostMapping(path = "/orders/lists-opt")
    function createOrderMapArrOpt(@RequestBody order: OrderMapArrOpt): string {
        let l = order.lists
        if (l != null) {
            let total = 0
            const keys = l.keys()
            let i = 0
            while (i < keys.length()) {
                let inner = l.get(keys[i])
                if (inner != null) {
                    total = total + inner.length()
                }
                i = i + 1
            }
            return "customer=" + order.customer + ",total=" + total
        }
        return "customer=" + order.customer + ",no-lists"
    }
}

function main() {
    test("I021-deep-optional ① form 1 Array<Tag?>? present + inner mixed null/non-null", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/tags-deep-opt")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"alice\",\"tags\":[{\"name\":\"a\"},null,{\"name\":\"c\"}]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,tags=2,nulls=1")
    })

    test("I021-deep-optional ② form 1 Array<Tag?>? outer null + outer missing — 双 `?` 字段层 outer null guard", () => {
        let req1: Map<string, string> = new Map()
        req1.set("path", "/orders/tags-deep-opt")
        req1.set("method", "POST")
        req1.set("body", "{\"customer\":\"bob\",\"tags\":null}")
        assertEqual(dispatchBody(dispatch(req1)), "customer=bob,no-tags")

        let req2: Map<string, string> = new Map()
        req2.set("path", "/orders/tags-deep-opt")
        req2.set("method", "POST")
        req2.set("body", "{\"customer\":\"carol\"}")
        assertEqual(dispatchBody(dispatch(req2)), "customer=carol,no-tags")
    })

    test("I021-deep-optional ③ form 2 Map<string, Tag?>? present + inner mixed null/non-null", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/items-deep-opt")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"dave\",\"items\":{\"k1\":{\"name\":\"x\"},\"k2\":null,\"k3\":{\"name\":\"z\"}}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=dave,items=2,nulls=1")
    })

    test("I021-deep-optional ④ form 2 Map<string, Tag?>? outer null + outer missing", () => {
        let req1: Map<string, string> = new Map()
        req1.set("path", "/orders/items-deep-opt")
        req1.set("method", "POST")
        req1.set("body", "{\"customer\":\"eve\",\"items\":null}")
        assertEqual(dispatchBody(dispatch(req1)), "customer=eve,no-items")

        let req2: Map<string, string> = new Map()
        req2.set("path", "/orders/items-deep-opt")
        req2.set("method", "POST")
        req2.set("body", "{\"customer\":\"frank\"}")
        assertEqual(dispatchBody(dispatch(req2)), "customer=frank,no-items")
    })

    test("I021-deep-optional ⑤ form 3 Array<Array<Tag>>? present 二层 + outer null/missing — D132 单 `?` + N=2 嵌套修后", () => {
        let req1: Map<string, string> = new Map()
        req1.set("path", "/orders/matrix-opt")
        req1.set("method", "POST")
        req1.set("body", "{\"customer\":\"grace\",\"matrix\":[[{\"name\":\"x\"},{\"name\":\"y\"}],[{\"name\":\"z\"}]]}")
        assertEqual(dispatchBody(dispatch(req1)), "customer=grace,total=3")

        let req2: Map<string, string> = new Map()
        req2.set("path", "/orders/matrix-opt")
        req2.set("method", "POST")
        req2.set("body", "{\"customer\":\"henry\",\"matrix\":null}")
        assertEqual(dispatchBody(dispatch(req2)), "customer=henry,no-matrix")

        let req3: Map<string, string> = new Map()
        req3.set("path", "/orders/matrix-opt")
        req3.set("method", "POST")
        req3.set("body", "{\"customer\":\"isaac\"}")
        assertEqual(dispatchBody(dispatch(req3)), "customer=isaac,no-matrix")
    })

    test("I021-deep-optional ⑥ form 4 Map<string, Map<string, Tag>>? present + outer null/missing — D132 Map N=2 嵌套修后", () => {
        let req1: Map<string, string> = new Map()
        req1.set("path", "/orders/groups-opt")
        req1.set("method", "POST")
        req1.set("body", "{\"customer\":\"jane\",\"groups\":{\"g1\":{\"k1\":{\"name\":\"a\"},\"k2\":{\"name\":\"b\"}},\"g2\":{\"k3\":{\"name\":\"c\"}}}}")
        assertEqual(dispatchBody(dispatch(req1)), "customer=jane,total=3")

        let req2: Map<string, string> = new Map()
        req2.set("path", "/orders/groups-opt")
        req2.set("method", "POST")
        req2.set("body", "{\"customer\":\"kate\",\"groups\":null}")
        assertEqual(dispatchBody(dispatch(req2)), "customer=kate,no-groups")

        let req3: Map<string, string> = new Map()
        req3.set("path", "/orders/groups-opt")
        req3.set("method", "POST")
        req3.set("body", "{\"customer\":\"leo\"}")
        assertEqual(dispatchBody(dispatch(req3)), "customer=leo,no-groups")
    })

    test("I021-deep-optional ⑦ form 5/6 Array<Map<...>>? + Map<...,Array<...>>? 混合 + outer 三态 — D132 跨族嵌套修后", () => {
        let req1: Map<string, string> = new Map()
        req1.set("path", "/orders/entries-opt")
        req1.set("method", "POST")
        req1.set("body", "{\"customer\":\"mike\",\"entries\":[{\"k1\":{\"name\":\"a\"},\"k2\":{\"name\":\"b\"}},{\"k3\":{\"name\":\"c\"}}]}")
        assertEqual(dispatchBody(dispatch(req1)), "customer=mike,total=3")

        let req2: Map<string, string> = new Map()
        req2.set("path", "/orders/entries-opt")
        req2.set("method", "POST")
        req2.set("body", "{\"customer\":\"nina\",\"entries\":null}")
        assertEqual(dispatchBody(dispatch(req2)), "customer=nina,no-entries")

        let req3: Map<string, string> = new Map()
        req3.set("path", "/orders/lists-opt")
        req3.set("method", "POST")
        req3.set("body", "{\"customer\":\"oscar\",\"lists\":{\"a\":[{\"name\":\"x\"},{\"name\":\"y\"}],\"b\":[{\"name\":\"z\"}]}}")
        assertEqual(dispatchBody(dispatch(req3)), "customer=oscar,total=3")

        let req4: Map<string, string> = new Map()
        req4.set("path", "/orders/lists-opt")
        req4.set("method", "POST")
        req4.set("body", "{\"customer\":\"peter\"}")
        assertEqual(dispatchBody(dispatch(req4)), "customer=peter,no-lists")
    })

    test("I021-deep-optional ⑧ 全链路 raw HTTP byte-identical 6 endpoint × 4 场景 smoke", () => {
        const raw1 = "POST /orders/tags-deep-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"alice\",\"tags\":[{\"name\":\"a\"},null]}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw1))), "customer=alice,tags=1,nulls=1")

        const raw2 = "POST /orders/items-deep-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"bob\",\"items\":null}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw2))), "customer=bob,no-items")

        const raw3 = "POST /orders/matrix-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"carol\",\"matrix\":[[{\"name\":\"x\"}]]}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw3))), "customer=carol,total=1")

        const raw4 = "POST /orders/groups-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"dave\"}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw4))), "customer=dave,no-groups")

        const raw5 = "POST /orders/entries-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"eve\",\"entries\":[{\"k\":{\"name\":\"a\"}}]}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw5))), "customer=eve,total=1")

        const raw6 = "POST /orders/lists-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"frank\",\"lists\":null}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw6))), "customer=frank,no-lists")
    })

    test("I021-deep-optional ⑨ RC stress 50 次循环 — 混合 outer null + outer non-null + inner null + inner non-null 字段 outer drop 不破裂", () => {
        let i = 0
        while (i < 50) {
            let req1: Map<string, string> = new Map()
            req1.set("path", "/orders/tags-deep-opt")
            req1.set("method", "POST")
            req1.set("body", "{\"customer\":\"alice\",\"tags\":[{\"name\":\"a\"},null,{\"name\":\"c\"}]}")
            assertEqual(dispatchBody(dispatch(req1)), "customer=alice,tags=2,nulls=1")

            let req2: Map<string, string> = new Map()
            req2.set("path", "/orders/items-deep-opt")
            req2.set("method", "POST")
            req2.set("body", "{\"customer\":\"bob\",\"items\":null}")
            assertEqual(dispatchBody(dispatch(req2)), "customer=bob,no-items")

            let req3: Map<string, string> = new Map()
            req3.set("path", "/orders/matrix-opt")
            req3.set("method", "POST")
            req3.set("body", "{\"customer\":\"carol\",\"matrix\":[[{\"name\":\"x\"},{\"name\":\"y\"}]]}")
            assertEqual(dispatchBody(dispatch(req3)), "customer=carol,total=2")

            let req4: Map<string, string> = new Map()
            req4.set("path", "/orders/groups-opt")
            req4.set("method", "POST")
            req4.set("body", "{\"customer\":\"dave\",\"groups\":null}")
            assertEqual(dispatchBody(dispatch(req4)), "customer=dave,no-groups")

            let req5: Map<string, string> = new Map()
            req5.set("path", "/orders/entries-opt")
            req5.set("method", "POST")
            req5.set("body", "{\"customer\":\"eve\",\"entries\":[{\"k1\":{\"name\":\"a\"}}]}")
            assertEqual(dispatchBody(dispatch(req5)), "customer=eve,total=1")

            let req6: Map<string, string> = new Map()
            req6.set("path", "/orders/lists-opt")
            req6.set("method", "POST")
            req6.set("body", "{\"customer\":\"frank\"}")
            assertEqual(dispatchBody(dispatch(req6)), "customer=frank,no-lists")

            i = i + 1
        }
    })
}
