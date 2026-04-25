// I021-requestbody-nested-array-array — N=2 双层 Array<Array<X>> 嵌套反序列化
// 验 lexer/parser SHR 拆 + isArrayDeserializable 谓词第三层递归 + emitArrayDeserializeInto
// helper 第 6 路 elemType 递归 emit + per-class deserializer BFS 内层 UserClass unwrap +
// RC 双层契约(外层 transfer / 内层 string retain / 内层 UserClass transfer)+ tag 选择
// 对齐(外层 tag=5 内层是 ptr / 内层 tag={1|5} 按内 X primitive vs ptr-bearing)。
//
// fix at:
//   bootstrap/parse/parser.ss expectGtTypeCtx — 类型上下文 SHR/USHR 虚拟拆分为 GT 序列
//   bootstrap/gen/gen_deserialize.ss isArrayDeserializable — 谓词第三层递归
//   bootstrap/gen/gen_deserialize.ss emitArrayDeserializeInto — Array 字段 inline emit helper
//   bootstrap/gen/gen_deserialize.ss emitPendingDeserializers — BFS 内层 UserClass unwrap
//
// Coverage:
//   ① Array<Array<int>> 2×3 grid `[[1,2,3],[4,5,6]]` 双层 length + 元素求和 = 21
//   ② Array<Array<string>> 2×2 labels `[["a","b"],["c","d"]]` 双层 length + 元素拼 = "abcd"
//   ③ Array<Array<Cell>> 2×2 cells `[[{r:0,c:0,v:"x"}]...]` 双层 length + 元素 scalar 字段
//   ④ 外非空内空 `[[],[]]` length=2 但每内层 length=0 RC 契约不破裂
//   ⑤ 外空数组 `[]` length=0 RC 契约不破裂(外容器 free 不触发内层链)
//   ⑥ Array<Array<double>> 2×2 元素求和精度对齐(bitcast 内层 + tag=1 内 / tag=5 外)
//   ⑦ Array<Array<bool>> 2×2 元素逻辑 `flags[0][0] && !flags[1][1]`(zext + tag=1 内)
//   ⑧ 全链路 raw HTTP POST /matrix(parseRequest → dispatchBody)— 5 路同 body

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

class Cell {
    row: int
    col: int
    value: string
}

class Matrix {
    name: string
    grid: Array<Array<int>>
    cells: Array<Array<Cell>>
    labels: Array<Array<string>>
    nums: Array<Array<double>>
    flags: Array<Array<bool>>
}

@RestController
class MatrixCtl {
    @PostMapping(path = "/matrix")
    function createMatrix(@RequestBody m: Matrix): string {
        let total = 0
        let i = 0
        while (i < m.grid.length()) {
            let row = m.grid[i]
            let j = 0
            while (j < row.length()) {
                total = total + row[j]
                j = j + 1
            }
            i = i + 1
        }
        let labelSum = ""
        let li = 0
        while (li < m.labels.length()) {
            let lrow = m.labels[li]
            let lj = 0
            while (lj < lrow.length()) {
                labelSum = labelSum + lrow[lj]
                lj = lj + 1
            }
            li = li + 1
        }
        let cellTotal = 0
        let ci = 0
        while (ci < m.cells.length()) {
            let crow = m.cells[ci]
            let cj = 0
            while (cj < crow.length()) {
                cellTotal = cellTotal + crow[cj].row + crow[cj].col
                cj = cj + 1
            }
            ci = ci + 1
        }
        let nsum = 0.0
        let ni = 0
        while (ni < m.nums.length()) {
            let nrow = m.nums[ni]
            let nj = 0
            while (nj < nrow.length()) {
                nsum = nsum + nrow[nj]
                nj = nj + 1
            }
            ni = ni + 1
        }
        let fsum = 0
        let fi = 0
        while (fi < m.flags.length()) {
            let frow = m.flags[fi]
            let fj = 0
            while (fj < frow.length()) {
                if (frow[fj] == 1) { fsum = fsum + 1 }
                fj = fj + 1
            }
            fi = fi + 1
        }
        return `name=${m.name},total=${total},labels=${labelSum},cellTotal=${cellTotal},nsum=${nsum},fsum=${fsum},lens=${m.grid.length()}/${m.labels.length()}/${m.cells.length()}/${m.nums.length()}/${m.flags.length()}`
    }
}

function main() {
    test("I021-array-array Array<Array<int>> 2x3 grid 求和=21(外 tag=5 / 内 tag=1)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/matrix")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"m1\",\"grid\":[[1,2,3],[4,5,6]],\"cells\":[],\"labels\":[],\"nums\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=m1,total=21,labels=,cellTotal=0,nsum=0,fsum=0,lens=2/0/0/0/0")
    })

    test("I021-array-array Array<Array<string>> 2x2 labels=abcd(外 tag=5 / 内 tag=5 + retain)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/matrix")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"m2\",\"grid\":[],\"cells\":[],\"labels\":[[\"a\",\"b\"],[\"c\",\"d\"]],\"nums\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=m2,total=0,labels=abcd,cellTotal=0,nsum=0,fsum=0,lens=0/2/0/0/0")
    })

    test("I021-array-array Array<Array<Cell>> 2x2 cells 字段访问(外 tag=5 / 内 tag=5 + transfer)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/matrix")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"m3\",\"grid\":[],\"cells\":[[{\"row\":0,\"col\":0,\"value\":\"x\"},{\"row\":1,\"col\":2,\"value\":\"y\"}],[{\"row\":3,\"col\":4,\"value\":\"z\"}]],\"labels\":[],\"nums\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        // cellTotal = (0+0) + (1+2) + (3+4) = 10
        assertEqual(body, "name=m3,total=0,labels=,cellTotal=10,nsum=0,fsum=0,lens=0/0/2/0/0")
    })

    test("I021-array-array 外非空内空 [[],[]] — RC 契约不破裂(双层容器 free)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/matrix")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"m4\",\"grid\":[[],[]],\"cells\":[],\"labels\":[],\"nums\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=m4,total=0,labels=,cellTotal=0,nsum=0,fsum=0,lens=2/0/0/0/0")
    })

    test("I021-array-array 外空数组 [] — RC 契约不破裂(外容器 free 不触发内层链)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/matrix")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"m5\",\"grid\":[],\"cells\":[],\"labels\":[],\"nums\":[],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "name=m5,total=0,labels=,cellTotal=0,nsum=0,fsum=0,lens=0/0/0/0/0")
    })

    test("I021-array-array Array<Array<double>> 2x2 nsum 精度(bitcast 内 + tag=1 内)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/matrix")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"m6\",\"grid\":[],\"cells\":[],\"labels\":[],\"nums\":[[0.5,1.5],[2.0,1.0]],\"flags\":[]}")
        const body = dispatchBody(dispatch(req))
        // nsum = 0.5+1.5+2.0+1.0 = 5.0(println 默认整数化保留)
        assertEqual(body, "name=m6,total=0,labels=,cellTotal=0,nsum=5,fsum=0,lens=0/0/0/2/0")
    })

    test("I021-array-array Array<Array<bool>> 2x2 fsum 逻辑(zext + tag=1 内)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/matrix")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"m7\",\"grid\":[],\"cells\":[],\"labels\":[],\"nums\":[],\"flags\":[[true,false],[true,true]]}")
        const body = dispatchBody(dispatch(req))
        // fsum = 1+0+1+1 = 3
        assertEqual(body, "name=m7,total=0,labels=,cellTotal=0,nsum=0,fsum=3,lens=0/0/0/0/2")
    })

    test("I021-array-array 全链路 raw HTTP POST /matrix — 5 路 elemType 同 body", () => {
        const raw = "POST /matrix HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"name\":\"m8\",\"grid\":[[1,2],[3,4]],\"cells\":[[{\"row\":0,\"col\":1,\"value\":\"a\"}]],\"labels\":[[\"x\",\"y\"]],\"nums\":[[2.5]],\"flags\":[[true]]}"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        // total=10, labels=xy, cellTotal=0+1=1, nsum=2.5, fsum=1
        assertEqual(body, "name=m8,total=10,labels=xy,cellTotal=1,nsum=2.5,fsum=1,lens=2/1/1/1/1")
    })
}
