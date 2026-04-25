// I021-requestbody-nested-deep — N>=3 层 Array<Array<Array<X>>> 反序列化实测覆盖
// (承 nested-array-array commit 5b25573 N=2 双层深化)。
//
// 非显然 RC 不变量:string 元素层(最里 N=1)必 emitRetainForType — jnArrayGetString 返
// jnStr 内部 ptr 未持新 RC,父字段 drop 时双 free。与 a096fd0 单层同模式逐层叠加。

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Cell {
    row: int
    col: int
    value: string
}

class DeepNest {
    name: string
    cube3i: Array<Array<Array<int>>>
    cube3s: Array<Array<Array<string>>>
    cube3c: Array<Array<Array<Cell>>>
    tess4s: Array<Array<Array<Array<string>>>>
    pent5i: Array<Array<Array<Array<Array<int>>>>>
}

@RestController
class DeepCtl {
    @PostMapping(path = "/deep")
    function createDeep(@RequestBody d: DeepNest): string {
        let isum = 0
        let i = 0
        while (i < d.cube3i.length()) {
            let plane = d.cube3i[i]
            let j = 0
            while (j < plane.length()) {
                let row = plane[j]
                let k = 0
                while (k < row.length()) {
                    isum = isum + row[k]
                    k = k + 1
                }
                j = j + 1
            }
            i = i + 1
        }
        let ssum = ""
        let si = 0
        while (si < d.cube3s.length()) {
            let splane = d.cube3s[si]
            let sj = 0
            while (sj < splane.length()) {
                let srow = splane[sj]
                let sk = 0
                while (sk < srow.length()) {
                    ssum = ssum + srow[sk]
                    sk = sk + 1
                }
                sj = sj + 1
            }
            si = si + 1
        }
        let csum = 0
        let ci = 0
        while (ci < d.cube3c.length()) {
            let cplane = d.cube3c[ci]
            let cj = 0
            while (cj < cplane.length()) {
                let crow = cplane[cj]
                let ck = 0
                while (ck < crow.length()) {
                    csum = csum + crow[ck].row + crow[ck].col
                    ck = ck + 1
                }
                cj = cj + 1
            }
            ci = ci + 1
        }
        let tlen = 0
        let ti = 0
        while (ti < d.tess4s.length()) {
            let t3 = d.tess4s[ti]
            let tj = 0
            while (tj < t3.length()) {
                let t2 = t3[tj]
                let tk = 0
                while (tk < t2.length()) {
                    let t1 = t2[tk]
                    let tm = 0
                    while (tm < t1.length()) {
                        tlen = tlen + t1[tm].length()
                        tm = tm + 1
                    }
                    tk = tk + 1
                }
                tj = tj + 1
            }
            ti = ti + 1
        }
        let psum = 0
        let pi = 0
        while (pi < d.pent5i.length()) {
            let p4 = d.pent5i[pi]
            let pj = 0
            while (pj < p4.length()) {
                let p3 = p4[pj]
                let pk = 0
                while (pk < p3.length()) {
                    let p2 = p3[pk]
                    let pl = 0
                    while (pl < p2.length()) {
                        let p1 = p2[pl]
                        let pm = 0
                        while (pm < p1.length()) {
                            psum = psum + p1[pm]
                            pm = pm + 1
                        }
                        pl = pl + 1
                    }
                    pk = pk + 1
                }
                pj = pj + 1
            }
            pi = pi + 1
        }
        return `name=${d.name},isum=${isum},ssum=${ssum},csum=${csum},tlen=${tlen},psum=${psum},lens=${d.cube3i.length()}/${d.cube3s.length()}/${d.cube3c.length()}/${d.tess4s.length()}/${d.pent5i.length()}`
    }
}

function main() {
    test("I021-deep N=3 int cube `[[[1,2],[3]],[[4,5,6]]]` 三层求和=21", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/deep")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"d1\",\"cube3i\":[[[1,2],[3]],[[4,5,6]]],\"cube3s\":[],\"cube3c\":[],\"tess4s\":[],\"pent5i\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=d1,isum=21,ssum=,csum=0,tlen=0,psum=0,lens=2/0/0/0/0")
    })

    test("I021-deep N=3 string cube `[[[\"a\",\"b\"],[\"c\"]],[[\"d\"]]]` 三层拼=abcd", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/deep")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"d2\",\"cube3i\":[],\"cube3s\":[[[\"a\",\"b\"],[\"c\"]],[[\"d\"]]],\"cube3c\":[],\"tess4s\":[],\"pent5i\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=d2,isum=0,ssum=abcd,csum=0,tlen=0,psum=0,lens=0/2/0/0/0")
    })

    test("I021-deep N=3 Cell cube 字段访问 (中层 transfer / 内层 transfer)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/deep")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"d3\",\"cube3i\":[],\"cube3s\":[],\"cube3c\":[[[{\"row\":1,\"col\":2,\"value\":\"x\"}]],[[{\"row\":3,\"col\":4,\"value\":\"y\"},{\"row\":5,\"col\":6,\"value\":\"z\"}]]],\"tess4s\":[],\"pent5i\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=d3,isum=0,ssum=,csum=21,tlen=0,psum=0,lens=0/0/2/0/0")
    })

    test("I021-deep N=4 string tess 四层 length 累加 (中/中/中 tag=5 / 内 tag=5+retain)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/deep")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"d4\",\"cube3i\":[],\"cube3s\":[],\"cube3c\":[],\"tess4s\":[[[[\"hi\"]]],[[[\"abc\",\"de\"]]]],\"pent5i\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=d4,isum=0,ssum=,csum=0,tlen=7,psum=0,lens=0/0/0/2/0")
    })

    test("I021-deep N=5 int pent 极限 `[[[[[1,2,3]]]]]` (lexer >>>>> = USHR+SHR)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/deep")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"d5\",\"cube3i\":[],\"cube3s\":[],\"cube3c\":[],\"tess4s\":[],\"pent5i\":[[[[[1,2,3]]]],[[[[4,5]]]]]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=d5,isum=0,ssum=,csum=0,tlen=0,psum=15,lens=0/0/0/0/2")
    })

    test("I021-deep N=3 边界外/中/内空数组 [[[]],[],[]] — RC 不破裂", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/deep")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"d6\",\"cube3i\":[[[]],[],[]],\"cube3s\":[],\"cube3c\":[],\"tess4s\":[],\"pent5i\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=d6,isum=0,ssum=,csum=0,tlen=0,psum=0,lens=3/0/0/0/0")
    })

    test("I021-deep N=3 全空数组 [] — 顶层容器 free 不触发深层链", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/deep")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"d7\",\"cube3i\":[],\"cube3s\":[],\"cube3c\":[],\"tess4s\":[],\"pent5i\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=d7,isum=0,ssum=,csum=0,tlen=0,psum=0,lens=0/0/0/0/0")
    })

    test("I021-deep 全链路 raw HTTP POST /deep — 5 elemType 同 body 端到端", () => {
        const raw = "POST /deep HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"name\":\"d8\",\"cube3i\":[[[1]]],\"cube3s\":[[[\"a\"]]],\"cube3c\":[[[{\"row\":2,\"col\":3,\"value\":\"v\"}]]],\"tess4s\":[[[[\"hi\"]]]],\"pent5i\":[[[[[10]]]]]}"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=d8,isum=1,ssum=a,csum=5,tlen=2,psum=10,lens=1/1/1/1/1")
    })
}
