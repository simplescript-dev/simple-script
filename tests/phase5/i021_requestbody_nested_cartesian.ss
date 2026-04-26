// I021-requestbody-nested-cartesian(D130)— 嵌套 collection 笛卡尔积 SSoT 端到端锁定
//
// 验 D130 SSoT 收敛(c52e9b5)笛卡尔积自动覆盖 — emitDeserializeForType 7 路单点解码
//   + emitArrayDeserializeInto / emitMapDeserializeInto inner dispatch 自递归委托
//   + isArrayDeserializable / isMapDeserializable 谓词第三层递归
//   + emitPendingDeserializers BFS 任意嵌套层数剥皮 base UserClass 入队
//   + ss_mapNew val_type=1(ptr)/0(primitive)二分 + ss_newArray tag=1/5 二分自动正确
//
// 综合 ~ 15 cell:
//   5 cell  Map<string, Array<X>>     X ∈ {int / string / double / bool / Class}
//   5 cell  Map<string, Map<string,Y>> Y ∈ {int / string / double / bool / Class}
//   3 cell  Array<Map<string, X>>     X ∈ {int / string / Class}
//   1 cell  Map<string, Map<string, Array<int>>>      N=3 混合(Map → Map → Array)
//   1 cell  Array<Array<Map<string, int>>>            N=3 反向混合(Array → Array → Map)
//
// 零 codegen 改动 — D130 SSoT 设计意图首次端到端实证轮(对照 Jackson 编译期对偶)
//
// fix at: tests + spring-parity DTO 加 BigOrder + endpoint;无 codegen / lib/json 改动

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Tag {
    color: string
    priority: int
}

// BigOrder 字段命名 schema(陌生人秒懂表):
//   <vTypePair><containerSuffix> — 前缀编码 vType, 后缀编码外层容器形态
//   ia/sa/da/ba/ca = Map<string, Array<{int|string|double|bool|Class}>>      "Groups"
//   ii/ss/dd/bb/cc = Map<string, Map<string, {int|string|double|bool|Class}>> "Maps"
//   i/s/c          = Array<Map<string, {int|string|Class}>>                   "MapList"
//   deepMix        = Map<string, Map<string, Array<int>>>                     N=3 混合(Map→Map→Array)
//   deepMixR       = Array<Array<Map<string, int>>>                           N=3 反向(Array→Array→Map)
class BigOrder {
    customer: string
    iaGroups: Map<string, Array<int>>
    saGroups: Map<string, Array<string>>
    daGroups: Map<string, Array<double>>
    baGroups: Map<string, Array<bool>>
    caGroups: Map<string, Array<Tag>>
    iiMaps: Map<string, Map<string, int>>
    ssMaps: Map<string, Map<string, string>>
    ddMaps: Map<string, Map<string, double>>
    bbMaps: Map<string, Map<string, bool>>
    ccMaps: Map<string, Map<string, Tag>>
    iMapList: Array<Map<string, int>>
    sMapList: Array<Map<string, string>>
    cMapList: Array<Map<string, Tag>>
    deepMix: Map<string, Map<string, Array<int>>>
    deepMixR: Array<Array<Map<string, int>>>
}

@RestController
class BigOrderCtl {
    @PostMapping(path = "/orders/cartesian")
    function createBigOrder(@RequestBody order: BigOrder): string {
        let iaSum = 0
        const iaKeys = order.iaGroups.keys()
        let iaI = 0
        while (iaI < iaKeys.length()) {
            const arr = order.iaGroups.get(iaKeys[iaI])
            let j = 0
            while (j < arr.length()) {
                iaSum = iaSum + arr[j]
                j = j + 1
            }
            iaI = iaI + 1
        }

        let saSum = ""
        const saKeys = order.saGroups.keys()
        let saI = 0
        while (saI < saKeys.length()) {
            const arr = order.saGroups.get(saKeys[saI])
            let j = 0
            while (j < arr.length()) {
                saSum = saSum + arr[j]
                j = j + 1
            }
            saI = saI + 1
        }

        let daSum = 0.0
        const daKeys = order.daGroups.keys()
        let daI = 0
        while (daI < daKeys.length()) {
            const arr = order.daGroups.get(daKeys[daI])
            let j = 0
            while (j < arr.length()) {
                daSum = daSum + arr[j]
                j = j + 1
            }
            daI = daI + 1
        }

        let baSum = 0
        const baKeys = order.baGroups.keys()
        let baI = 0
        while (baI < baKeys.length()) {
            const arr = order.baGroups.get(baKeys[baI])
            let j = 0
            while (j < arr.length()) {
                if (arr[j] == 1) { baSum = baSum + 1 }
                j = j + 1
            }
            baI = baI + 1
        }

        let caSum = 0
        const caKeys = order.caGroups.keys()
        let caI = 0
        while (caI < caKeys.length()) {
            const arr = order.caGroups.get(caKeys[caI])
            let j = 0
            while (j < arr.length()) {
                caSum = caSum + arr[j].priority
                j = j + 1
            }
            caI = caI + 1
        }

        let iiSum = 0
        const iiKeys = order.iiMaps.keys()
        let iiI = 0
        while (iiI < iiKeys.length()) {
            const inner = order.iiMaps.get(iiKeys[iiI])
            const innerKeys = inner.keys()
            let j = 0
            while (j < innerKeys.length()) {
                iiSum = iiSum + inner.get(innerKeys[j])
                j = j + 1
            }
            iiI = iiI + 1
        }

        let ssSum = ""
        const ssKeys = order.ssMaps.keys()
        let ssI = 0
        while (ssI < ssKeys.length()) {
            const inner = order.ssMaps.get(ssKeys[ssI])
            const innerKeys = inner.keys()
            let j = 0
            while (j < innerKeys.length()) {
                ssSum = ssSum + inner.get(innerKeys[j])
                j = j + 1
            }
            ssI = ssI + 1
        }

        let ddSum = 0.0
        const ddKeys = order.ddMaps.keys()
        let ddI = 0
        while (ddI < ddKeys.length()) {
            const inner = order.ddMaps.get(ddKeys[ddI])
            const innerKeys = inner.keys()
            let j = 0
            while (j < innerKeys.length()) {
                ddSum = ddSum + inner.get(innerKeys[j])
                j = j + 1
            }
            ddI = ddI + 1
        }

        let bbSum = 0
        const bbKeys = order.bbMaps.keys()
        let bbI = 0
        while (bbI < bbKeys.length()) {
            const inner = order.bbMaps.get(bbKeys[bbI])
            const innerKeys = inner.keys()
            let j = 0
            while (j < innerKeys.length()) {
                if (inner.get(innerKeys[j])) { bbSum = bbSum + 1 }
                j = j + 1
            }
            bbI = bbI + 1
        }

        let ccSum = 0
        const ccKeys = order.ccMaps.keys()
        let ccI = 0
        while (ccI < ccKeys.length()) {
            const inner = order.ccMaps.get(ccKeys[ccI])
            const innerKeys = inner.keys()
            let j = 0
            while (j < innerKeys.length()) {
                const t = inner.get(innerKeys[j])
                if (t != null) { ccSum = ccSum + t.priority }
                j = j + 1
            }
            ccI = ccI + 1
        }

        let imlSum = 0
        let imlI = 0
        while (imlI < order.iMapList.length()) {
            const m = order.iMapList[imlI]
            const mKeys = m.keys()
            let j = 0
            while (j < mKeys.length()) {
                imlSum = imlSum + m.get(mKeys[j])
                j = j + 1
            }
            imlI = imlI + 1
        }

        let smlSum = ""
        let smlI = 0
        while (smlI < order.sMapList.length()) {
            const m = order.sMapList[smlI]
            const mKeys = m.keys()
            let j = 0
            while (j < mKeys.length()) {
                smlSum = smlSum + m.get(mKeys[j])
                j = j + 1
            }
            smlI = smlI + 1
        }

        let cmlSum = 0
        let cmlI = 0
        while (cmlI < order.cMapList.length()) {
            const m = order.cMapList[cmlI]
            const mKeys = m.keys()
            let j = 0
            while (j < mKeys.length()) {
                const t = m.get(mKeys[j])
                if (t != null) { cmlSum = cmlSum + t.priority }
                j = j + 1
            }
            cmlI = cmlI + 1
        }

        let dmSum = 0
        const dmKeys = order.deepMix.keys()
        let dmI = 0
        while (dmI < dmKeys.length()) {
            const inner = order.deepMix.get(dmKeys[dmI])
            const innerKeys = inner.keys()
            let j = 0
            while (j < innerKeys.length()) {
                const arr = inner.get(innerKeys[j])
                let k = 0
                while (k < arr.length()) {
                    dmSum = dmSum + arr[k]
                    k = k + 1
                }
                j = j + 1
            }
            dmI = dmI + 1
        }

        let dmrSum = 0
        let dmrI = 0
        while (dmrI < order.deepMixR.length()) {
            const inner = order.deepMixR[dmrI]
            let j = 0
            while (j < inner.length()) {
                const m = inner[j]
                const mKeys = m.keys()
                let k = 0
                while (k < mKeys.length()) {
                    dmrSum = dmrSum + m.get(mKeys[k])
                    k = k + 1
                }
                j = j + 1
            }
            dmrI = dmrI + 1
        }

        return `customer=${order.customer},sums=${iaSum}/${saSum}/${daSum}/${baSum}/${caSum}/${iiSum}/${ssSum}/${ddSum}/${bbSum}/${ccSum}/${imlSum}/${smlSum}/${cmlSum}/${dmSum}/${dmrSum},sizes=${order.iaGroups.size()}/${order.saGroups.size()}/${order.daGroups.size()}/${order.baGroups.size()}/${order.caGroups.size()}/${order.iiMaps.size()}/${order.ssMaps.size()}/${order.ddMaps.size()}/${order.bbMaps.size()}/${order.ccMaps.size()}/${order.iMapList.length()}/${order.sMapList.length()}/${order.cMapList.length()}/${order.deepMix.size()}/${order.deepMixR.length()}`
    }
}

// ─ sums signature 15 slot 顺序(对应 createBigOrder return)─
//   slot  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
//   field ia sa da ba ca ii ss dd bb cc iml sml cml dm dmr
//   类型  i  s  d  i  i  i  s  d  i  i   i   s   i  i   i   (s=string concat / d=double sum / i=int sum)
//   双 // = 空 string concat(slot 2 saSum / 7 ssSum / 12 smlSum)
const ZERO_SUMS = "0//0/0/0/0//0/0/0/0//0/0/0"
// sizes signature 15 slot 顺序同 sums(.size() / .length() — 容器实际元素数)
const ZERO_SIZES = "0/0/0/0/0/0/0/0/0/0/0/0/0/0/0"
const EMPTY_BODY_FIELDS = "\"iaGroups\":{},\"saGroups\":{},\"daGroups\":{},\"baGroups\":{},\"caGroups\":{},\"iiMaps\":{},\"ssMaps\":{},\"ddMaps\":{},\"bbMaps\":{},\"ccMaps\":{},\"iMapList\":[],\"sMapList\":[],\"cMapList\":[],\"deepMix\":{},\"deepMixR\":[]"

function main() {
    test("I021-cartesian case 1: 全空 16 字段 size=0 — 15 cell drop 链多层契约不破裂", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/cartesian")
        req.set("method", "POST")
        req.set("body", `{"customer":"alice",${EMPTY_BODY_FIELDS}}`)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, `customer=alice,sums=${ZERO_SUMS},sizes=${ZERO_SIZES}`)
    })

    test("I021-cartesian case 2: 5 cell Map<string, Array<X>> 5 vType — emitMapDeserializeInto vType=Array 自递归", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/cartesian")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"bob\",\"iaGroups\":{\"a\":[1,2,3]},\"saGroups\":{\"a\":[\"x\",\"y\"]},\"daGroups\":{\"a\":[1.5,2.5]},\"baGroups\":{\"a\":[true,false,true]},\"caGroups\":{\"a\":[{\"color\":\"red\",\"priority\":7}]},\"iiMaps\":{},\"ssMaps\":{},\"ddMaps\":{},\"bbMaps\":{},\"ccMaps\":{},\"iMapList\":[],\"sMapList\":[],\"cMapList\":[],\"deepMix\":{},\"deepMixR\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=bob,sums=6/xy/4/2/7/0//0/0/0/0//0/0/0,sizes=1/1/1/1/1/0/0/0/0/0/0/0/0/0/0")
    })

    test("I021-cartesian case 3: 5 cell Map<string, Map<string, Y>> 5 vType — emitMapDeserializeInto vType=Map 嵌套自递归", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/cartesian")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"carol\",\"iaGroups\":{},\"saGroups\":{},\"daGroups\":{},\"baGroups\":{},\"caGroups\":{},\"iiMaps\":{\"g\":{\"a\":1,\"b\":2}},\"ssMaps\":{\"g\":{\"a\":\"x\",\"b\":\"y\"}},\"ddMaps\":{\"g\":{\"a\":0.5,\"b\":1.5}},\"bbMaps\":{\"g\":{\"a\":true,\"b\":true,\"c\":false}},\"ccMaps\":{\"g\":{\"a\":{\"color\":\"red\",\"priority\":3},\"b\":{\"color\":\"blue\",\"priority\":4}}},\"iMapList\":[],\"sMapList\":[],\"cMapList\":[],\"deepMix\":{},\"deepMixR\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=carol,sums=0//0/0/0/3/xy/2/2/7/0//0/0/0,sizes=0/0/0/0/0/1/1/1/1/1/0/0/0/0/0")
    })

    test("I021-cartesian case 4: 3 cell Array<Map<string, X>> 3 vType — emitArrayDeserializeInto elemType=Map 委托", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/cartesian")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"dave\",\"iaGroups\":{},\"saGroups\":{},\"daGroups\":{},\"baGroups\":{},\"caGroups\":{},\"iiMaps\":{},\"ssMaps\":{},\"ddMaps\":{},\"bbMaps\":{},\"ccMaps\":{},\"iMapList\":[{\"a\":10,\"b\":20}],\"sMapList\":[{\"a\":\"x\",\"b\":\"y\"}],\"cMapList\":[{\"a\":{\"color\":\"red\",\"priority\":5}}],\"deepMix\":{},\"deepMixR\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=dave,sums=0//0/0/0/0//0/0/0/30/xy/5/0/0,sizes=0/0/0/0/0/0/0/0/0/0/1/1/1/0/0")
    })

    test("I021-cartesian case 5: N=3 混合 Map<string, Map<string, Array<int>>> — Map → Map → Array 三层自递归", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/cartesian")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"eve\",\"iaGroups\":{},\"saGroups\":{},\"daGroups\":{},\"baGroups\":{},\"caGroups\":{},\"iiMaps\":{},\"ssMaps\":{},\"ddMaps\":{},\"bbMaps\":{},\"ccMaps\":{},\"iMapList\":[],\"sMapList\":[],\"cMapList\":[],\"deepMix\":{\"region\":{\"slot1\":[1,2,3],\"slot2\":[4,5]}},\"deepMixR\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=eve,sums=0//0/0/0/0//0/0/0/0//0/15/0,sizes=0/0/0/0/0/0/0/0/0/0/0/0/0/1/0")
    })

    test("I021-cartesian case 6: N=3 反向 Array<Array<Map<string, int>>> — Array → Array → Map 三层自递归", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/cartesian")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"frank\",\"iaGroups\":{},\"saGroups\":{},\"daGroups\":{},\"baGroups\":{},\"caGroups\":{},\"iiMaps\":{},\"ssMaps\":{},\"ddMaps\":{},\"bbMaps\":{},\"ccMaps\":{},\"iMapList\":[],\"sMapList\":[],\"cMapList\":[],\"deepMix\":{},\"deepMixR\":[[{\"a\":1,\"b\":2}],[{\"a\":3},{\"b\":4}]]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=frank,sums=0//0/0/0/0//0/0/0/0//0/0/10,sizes=0/0/0/0/0/0/0/0/0/0/0/0/0/0/2")
    })

    test("I021-cartesian case 7: 全 16 字段联合压测 — 15 cell 笛卡尔积同 body 端到端", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/orders/cartesian")
        req.set("method", "POST")
        req.set("body", "{\"customer\":\"grace\",\"iaGroups\":{\"g\":[1,2]},\"saGroups\":{\"g\":[\"a\"]},\"daGroups\":{\"g\":[1.0]},\"baGroups\":{\"g\":[true]},\"caGroups\":{\"g\":[{\"color\":\"red\",\"priority\":2}]},\"iiMaps\":{\"g\":{\"x\":3}},\"ssMaps\":{\"g\":{\"x\":\"b\"}},\"ddMaps\":{\"g\":{\"x\":2.5}},\"bbMaps\":{\"g\":{\"x\":true}},\"ccMaps\":{\"g\":{\"x\":{\"color\":\"blue\",\"priority\":4}}},\"iMapList\":[{\"x\":5}],\"sMapList\":[{\"x\":\"c\"}],\"cMapList\":[{\"x\":{\"color\":\"green\",\"priority\":6}}],\"deepMix\":{\"g\":{\"x\":[7,8]}},\"deepMixR\":[[{\"x\":9}]]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=grace,sums=3/a/1/1/2/3/b/2.5/1/4/5/c/6/15/9,sizes=1/1/1/1/1/1/1/1/1/1/1/1/1/1/1")
    })

    test("I021-cartesian case 8: 全链路 raw HTTP POST /orders/cartesian — parity smoke 仅 customer + sizes", () => {
        const raw = "POST /orders/cartesian HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"customer\":\"helen\",\"iaGroups\":{\"g\":[1]},\"saGroups\":{},\"daGroups\":{},\"baGroups\":{},\"caGroups\":{},\"iiMaps\":{\"g\":{\"x\":2}},\"ssMaps\":{},\"ddMaps\":{},\"bbMaps\":{},\"ccMaps\":{},\"iMapList\":[{\"x\":3}],\"sMapList\":[],\"cMapList\":[],\"deepMix\":{},\"deepMixR\":[]}"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "customer=helen,sums=1//0/0/0/2//0/0/0/3//0/0/0,sizes=1/0/0/0/0/1/0/0/0/0/1/0/0/0/0")
    })
}
