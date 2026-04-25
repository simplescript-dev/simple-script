// I021-requestbody-nested-map(D130) — 嵌套 Map<string, UserClass> 反序列化 RC 递归契约实测
// 验 emitDeserializeForType SSoT 单点解码 + isMapDeserializable + emitMapDeserializeInto
//   + emitPendingDeserializers BFS Map<string, UserClass> value 类型递归入队
//   + ss_mapSet(transfer ownership 不 retain)+ ss_drop_<Outer> 链 Map 字段 release
//   → ss_rc_destroy_map 逐 entry value tag-based dispatcher → ss_drop_<vClass>
//   + lib/json.ss jnObjectKeys + jnAs* by-nodeId raw helper(SSoT)
//
// fix at: bootstrap/gen/gen_deserialize.ss:emitDeserializeForType + emitMapDeserializeInto
//       + bootstrap/gen/gen_deserialize.ss:emitArrayDeserializeInto 委托重构
//       + bootstrap/gen/gen_deserialize.ss:emitClassDeserializeFn 字段循环委托重构
//       + bootstrap/gen/gen_deserialize.ss:emitPendingDeserializers BFS Map<K,Class> value
//       + lib/json.ss:jnObjectKeys + jnAsInt/Double/String/Bool raw int 接口
//
// Coverage:
//   ① 单层 Map<string, Tag> 1 entry — OrderMeta { metadata: Map<string, Tag> } value 字段访问
//   ② 空 Map {} size=0 — RC 契约不破裂(ss_mapNew + val_type=1 + 无 entry + ss_drop_OrderMeta free)
//   ③ Map<string, Tag> 5 entries — element-wise deserialize + 累加 priority + size=5
//   ④ 全链路 raw HTTP POST /orders/meta 整链路对齐
//   ⑤ 静态 IR 锚 — shell-level `grep "@Tag_deserialize\|jnObjectKeys" /tmp/t_i021_map.ll` ≥ 2 由 VCM §2 行为验

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Tag {
    color: string
    priority: int
}

class OrderMeta {
    customer: string
    metadata: Map<string, Tag>
}

@RestController
class OrderMetaCtl {
    @PostMapping(path = "/orders/meta")
    function createOrderMeta(@RequestBody order: OrderMeta): string {
        let totalPriority = 0
        const keys = order.metadata.keys()
        let i = 0
        while (i < keys.length()) {
            const t = order.metadata.get(keys[i])
            if (t != null) {
                totalPriority = totalPriority + t.priority
            }
            i = i + 1
        }
        const urgent = order.metadata.get("urgent")
        if (urgent != null) {
            return "customer=" + order.customer + ",urgent.color=" + urgent.color + ",size=" + order.metadata.size() + ",total=" + totalPriority
        }
        return "customer=" + order.customer + ",size=" + order.metadata.size() + ",total=" + totalPriority
    }
}

function main() {
    test("I021-requestbody-nested-map size=1 — Map<string, Tag> entry value scalar 字段 + .get GREEN", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/meta")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"alice\",\"metadata\":{\"urgent\":{\"color\":\"red\",\"priority\":1}}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=alice,urgent.color=red,size=1,total=1")
    })

    test("I021-requestbody-nested-map 空 Map size=0 — RC 契约不破裂", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/meta")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"bob\",\"metadata\":{}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,size=0,total=0")
    })

    test("I021-requestbody-nested-map size=5 多 entry — element-wise + 累加 + size 大 map RC 链不爆栈", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/meta")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"carol\",\"metadata\":{\"a\":{\"color\":\"red\",\"priority\":1},\"b\":{\"color\":\"green\",\"priority\":2},\"c\":{\"color\":\"blue\",\"priority\":3},\"d\":{\"color\":\"yellow\",\"priority\":4},\"e\":{\"color\":\"purple\",\"priority\":5}}}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=carol,size=5,total=15")
    })

    test("I021-requestbody-nested-map 全链路 raw HTTP — parseRequest POST /orders/meta 整链路对齐", () => {
        const raw = "POST /orders/meta HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"david\",\"metadata\":{\"urgent\":{\"color\":\"crimson\",\"priority\":7},\"low\":{\"color\":\"gray\",\"priority\":1}}}"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=david,urgent.color=crimson,size=2,total=8")
    })
}
