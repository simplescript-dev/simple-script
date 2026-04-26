// I021-requestbody-nested-optional-inner(D131) — 容器 inner nullable 反序列化
//
// 第二支柱 §247 第八轮:`Array<T?>` / `Map<string, V?>` 容器内 nullable user class 元素。
// D130 SSoT 假设破裂 → D131 谓词层 stripNullableCG inner 升根 — `isArrayDeserializable` /
// `isMapDeserializable` extractContainerElemType 后 strip,emit 路径
// emitDeserializeForType 自身识别 nullable 走 jnIsNullOrMissing → i64 0 分支(commit
// 29c3148 主路径已 cover)。
//
// scope:N=1 单层 inner nullable,user class elem `Tag?`;不混 primitive nullable
// (`Array<int?>` 留 -optional-inner-primitive 子档),不测 N=2 双层
// (`Array<Array<Tag?>>` 留 -deep-optional 子档)。
//
// D067 narrow 现状:user 层 for-in body IDENT 限制 → 用 `let t = arr[i]` binding 走
// IDENT narrow 形态(member access narrow 留 D067 子档)。

import { test, assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Tag {
    name: string
}

class OrderTagsArr {
    customer: string
    tags: Array<Tag?>
}

class OrderTagsMap {
    customer: string
    items: Map<string, Tag?>
}

@RestController
class OrderTagsArrCtl {
    @PostMapping(path = "/orders/tags")
    function createOrderTags(@RequestBody order: OrderTagsArr): string {
        let tagCount = 0
        let nullCount = 0
        let i = 0
        while (i < order.tags.length()) {
            let t = order.tags[i]
            if (t != null) {
                tagCount = tagCount + 1
            } else {
                nullCount = nullCount + 1
            }
            i = i + 1
        }
        return "customer=" + order.customer + ",tags=" + tagCount + ",nulls=" + nullCount
    }
}

@RestController
class OrderTagsMapCtl {
    @PostMapping(path = "/orders/items")
    function createOrderItems(@RequestBody order: OrderTagsMap): string {
        let itemCount = 0
        let nullCount = 0
        const keys = order.items.keys()
        let i = 0
        while (i < keys.length()) {
            let v = order.items.get(keys[i])
            if (v != null) {
                itemCount = itemCount + 1
            } else {
                nullCount = nullCount + 1
            }
            i = i + 1
        }
        return "customer=" + order.customer + ",items=" + itemCount + ",nulls=" + nullCount
    }
}

function main() {
    test("I021-requestbody-nested-optional-inner ① Array<Tag?> [{...},null,{...}] 双路径分流 tags=2 nulls=1", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/tags")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"alice\",\"tags\":[{\"name\":\"a\"},null,{\"name\":\"b\"}]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,tags=2,nulls=1")
    })

    test("I021-requestbody-nested-optional-inner ② Array<Tag?> 全 null — 走 ss_release isnull guard 不 segfault", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/tags")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"bob\",\"tags\":[null,null,null]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,tags=0,nulls=3")
    })

    test("I021-requestbody-nested-optional-inner ③ Array<Tag?> 全非 null", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/tags")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"carol\",\"tags\":[{\"name\":\"x\"},{\"name\":\"y\"}]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=carol,tags=2,nulls=0")
    })

    test("I021-requestbody-nested-optional-inner ④ Map<string, Tag?> value null vs object 双路径分流", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/items")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"dave\",\"items\":{\"a\":{\"name\":\"x\"},\"b\":null,\"c\":{\"name\":\"y\"}}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=dave,items=2,nulls=1")
    })

    test("I021-requestbody-nested-optional-inner ⑤ Map<string, Tag?> 全 null value — 全 ptr null 走 ss_release isnull guard 不 segfault", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/items")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"eve\",\"items\":{\"k1\":null,\"k2\":null,\"k3\":null}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=eve,items=0,nulls=3")
    })

    test("I021-requestbody-nested-optional-inner ⑥ 全链路 raw HTTP — POST /orders/tags + /orders/items 三场景", () => {
        const raw1 = "POST /orders/tags HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"frank\",\"tags\":[{\"name\":\"p\"},null,{\"name\":\"q\"}]}"
        const req1 = parseRequest(raw1)
        assertEqual(dispatchBody(dispatch(req1)), "customer=frank,tags=2,nulls=1")

        const raw2 = "POST /orders/items HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"grace\",\"items\":{\"a\":{\"name\":\"x\"},\"b\":null}}"
        const req2 = parseRequest(raw2)
        assertEqual(dispatchBody(dispatch(req2)), "customer=grace,items=1,nulls=1")

        const raw3 = "POST /orders/tags HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"henry\",\"tags\":[]}"
        const req3 = parseRequest(raw3)
        assertEqual(dispatchBody(dispatch(req3)), "customer=henry,tags=0,nulls=0")
    })

    test("I021-requestbody-nested-optional-inner ⑦ RC stress 50 次混合循环 — Array null/non-null + Map null/non-null 交替不破裂", () => {
        let i = 0
        while (i < 50) {
            let req1: Map<string, string> = new Map()
            req1.set("path", "/orders/tags")
            req1.set("method", "POST")
            req1.set("body", "{\"customer\":\"alice\",\"tags\":[{\"name\":\"a\"},null,{\"name\":\"b\"}]}")
            assertEqual(dispatchBody(dispatch(req1)), "customer=alice,tags=2,nulls=1")

            let req2: Map<string, string> = new Map()
            req2.set("path", "/orders/items")
            req2.set("method", "POST")
            req2.set("body", "{\"customer\":\"bob\",\"items\":{\"k1\":null,\"k2\":{\"name\":\"v\"}}}")
            assertEqual(dispatchBody(dispatch(req2)), "customer=bob,items=1,nulls=1")

            i = i + 1
        }
    })
}
