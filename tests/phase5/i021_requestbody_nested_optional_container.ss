// I021-requestbody-nested-optional-container(D130 SSoT + D131 谓词层第二次自动 cover) — 容器自身
//   nullable 反序列化
//
// 第二支柱 §247 第九轮:`Array<Tag>?` / `Map<string, Tag>?` 容器自身 nullable user class 集合。
// D130 SSoT(per-class deserializer 单点 nullable case 字段层主路径)+ D131 谓词层
// (stripNullableCG inner 后判 isUserClass / 容器嵌套)联动**自动 cover** — 真零 codegen 场景:
//   `Array<Tag>?` 字段层 stripNullableCG → "Array<Tag>" → nullable case alloca slot +
//   jnIsNullOrMissing → opt_present 委托递归 emitDeserializeForType("Array<Tag>", outer node)
//   → isArrayDeserializable=1(D131 §4.1)→ emitArrayDeserializeInto + inner element
//   @Tag_deserialize transfer。
//
// scope:N=1 单层 outer container nullable,inner element 非 nullable;`Array<int>?` 验证
//   primitive inner 容器自身 nullable;不混 inner element nullable(已落 -inner)/ 不测 N=2
//   双层 nullable(留 -deep-optional 子档)。
//
// D067 narrow 现状:user 层走 `let tags = order.tags` IDENT binding(D067 现状
//   extractNullCheckVar 限 IDENT,member access narrow 留 D067 子档)。

import { test, assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Tag {
    name: string
}

class OrderTagsArrOpt {
    customer: string
    tags: Array<Tag>?
}

class OrderTagsMapOpt {
    customer: string
    items: Map<string, Tag>?
}

class OrderScoresOpt {
    customer: string
    scores: Array<int>?
}

@RestController
class OrderTagsArrOptCtl {
    @PostMapping(path = "/orders/tags-opt")
    function createOrderTagsArrOpt(@RequestBody order: OrderTagsArrOpt): string {
        let tags = order.tags
        if (tags != null) {
            return "customer=" + order.customer + ",tags=" + tags.length()
        }
        return "customer=" + order.customer + ",no-tags"
    }
}

@RestController
class OrderTagsMapOptCtl {
    @PostMapping(path = "/orders/items-opt")
    function createOrderTagsMapOpt(@RequestBody order: OrderTagsMapOpt): string {
        let items = order.items
        if (items != null) {
            return "customer=" + order.customer + ",items=" + items.size()
        }
        return "customer=" + order.customer + ",no-items"
    }
}

@RestController
class OrderScoresOptCtl {
    @PostMapping(path = "/orders/scores-opt")
    function createOrderScoresOpt(@RequestBody order: OrderScoresOpt): string {
        let scores = order.scores
        if (scores != null) {
            let sum = 0
            let i = 0
            while (i < scores.length()) {
                sum = sum + scores[i]
                i = i + 1
            }
            return "customer=" + order.customer + ",sum=" + sum
        }
        return "customer=" + order.customer + ",no-scores"
    }
}

function main() {
    test("I021-optional-container ① Array<Tag>? present — tags=[{...},{...}] tags=2", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/tags-opt")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"alice\",\"tags\":[{\"name\":\"a\"},{\"name\":\"b\"}]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,tags=2")
    })

    test("I021-optional-container ② Array<Tag>? JSON null — opt_null 字段层 store ptr null no-tags", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/tags-opt")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"bob\",\"tags\":null}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,no-tags")
    })

    test("I021-optional-container ③ Array<Tag>? 字段缺失 — jnIsNullOrMissing missing key 走 opt_null no-tags", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/tags-opt")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"carol\"}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=carol,no-tags")
    })

    test("I021-optional-container ④ Map<string, Tag>? present — items={\"k1\":{...}} items=1", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/items-opt")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"dave\",\"items\":{\"k1\":{\"name\":\"x\"}}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=dave,items=1")
    })

    test("I021-optional-container ⑤ Map<string, Tag>? null + 字段缺失双 case — 双路径 no-items", () => {
        let req1: Map<string, string> = new Map()
        req1.set("path", "/orders/items-opt")
        req1.set("method", "POST")
        req1.set("body", "{\"customer\":\"eve\",\"items\":null}")
        assertEqual(dispatchBody(dispatch(req1)), "customer=eve,no-items")

        let req2: Map<string, string> = new Map()
        req2.set("path", "/orders/items-opt")
        req2.set("method", "POST")
        req2.set("body", "{\"customer\":\"frank\"}")
        assertEqual(dispatchBody(dispatch(req2)), "customer=frank,no-items")
    })

    test("I021-optional-container ⑥ Array<int>? null/missing/present — primitive inner 容器自身 nullable", () => {
        let req1: Map<string, string> = new Map()
        req1.set("path", "/orders/scores-opt")
        req1.set("method", "POST")
        req1.set("body", "{\"customer\":\"grace\",\"scores\":[1,2,3]}")
        assertEqual(dispatchBody(dispatch(req1)), "customer=grace,sum=6")

        let req2: Map<string, string> = new Map()
        req2.set("path", "/orders/scores-opt")
        req2.set("method", "POST")
        req2.set("body", "{\"customer\":\"henry\",\"scores\":null}")
        assertEqual(dispatchBody(dispatch(req2)), "customer=henry,no-scores")

        let req3: Map<string, string> = new Map()
        req3.set("path", "/orders/scores-opt")
        req3.set("method", "POST")
        req3.set("body", "{\"customer\":\"isaac\"}")
        assertEqual(dispatchBody(dispatch(req3)), "customer=isaac,no-scores")
    })

    test("I021-optional-container ⑦ 全链路 raw HTTP + RC stress 50 次循环 — 混合 null/非 null 字段 outer drop 不破裂", () => {
        const raw1 = "POST /orders/tags-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"jane\",\"tags\":[{\"name\":\"p\"},{\"name\":\"q\"}]}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw1))), "customer=jane,tags=2")

        const raw2 = "POST /orders/items-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"kate\",\"items\":null}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw2))), "customer=kate,no-items")

        const raw3 = "POST /orders/tags-opt HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"leo\"}"
        assertEqual(dispatchBody(dispatch(parseRequest(raw3))), "customer=leo,no-tags")

        let i = 0
        while (i < 50) {
            let req1: Map<string, string> = new Map()
            req1.set("path", "/orders/tags-opt")
            req1.set("method", "POST")
            req1.set("body", "{\"customer\":\"alice\",\"tags\":[{\"name\":\"a\"},{\"name\":\"b\"}]}")
            assertEqual(dispatchBody(dispatch(req1)), "customer=alice,tags=2")

            let req2: Map<string, string> = new Map()
            req2.set("path", "/orders/items-opt")
            req2.set("method", "POST")
            req2.set("body", "{\"customer\":\"bob\",\"items\":null}")
            assertEqual(dispatchBody(dispatch(req2)), "customer=bob,no-items")

            i = i + 1
        }
    })
}
