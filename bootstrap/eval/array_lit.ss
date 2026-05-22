// ARRAY_LIT 子目录文件(原 eval_expr.ss 迁出)
// 对称三段式:空数组 / comptime 全 ct(含 SPREAD_ELEM 展平)/ runtime arrPreRegs

function evalArrayLit(astId: int): int {
    const elemList = nGetList(astId)
    if (elemList == "") {
        if (comptimeMustBeKnown == 1) { return ctVal(interpNewArray("")) }
        return 0 - constVal(genArrayLit(astId)) - 1
    }
    let allCt = 1
    const arrParts = elemList.split(",")
    let elemVals = new Map()
    for (ap in arrParts) {
        const elemId = parseInt(ap)
        if (elemId > 0) {
            const ev = nGetKind(elemId) == "SPREAD_ELEM" ? genVal(nGetI1(elemId)) : genVal(elemId)
            elemVals.set(`${elemId}`, `${ev}`)
            if (isCt(ev) != 1) { allCt = 0 }
        }
    }
    if (comptimeMustBeKnown == 1) {
        const arr = interpNewArray("")
        for (ap in arrParts) {
            const elemId = parseInt(ap)
            if (elemId > 0) {
                const ev = parseInt(elemVals.getString(`${elemId}`))
                if (nGetKind(elemId) == "SPREAD_ELEM") {
                    if (isCt(ev) == 1 && interpType(payload(ev)) == "array") {
                        const srcArrId = payload(ev)
                        const srcLen = interpArrayLen(srcArrId)
                        let srcI = 0
                        while (srcI < srcLen) {
                            const srcElemId = interpArrayGet(srcArrId, srcI)
                            if (srcElemId > 0) { interpArrayPush(arr, srcElemId) }
                            srcI = srcI + 1
                        }
                    } else {
                        println(`error: [comptime] cannot spread non-array value at line ${nGetLine(elemId)}:${nGetCol(elemId)}`)
                        exit(1)
                    }
                } else {
                    interpArrayPush(arr, isCt(ev) == 1 ? payload(ev) : interpNewNull())
                }
            }
        }
        return ctVal(arr)
    }
    arrPreRegs = new Map()
    for (ap in arrParts) {
        const elemId = parseInt(ap)
        if (elemId > 0) {
            const ev = parseInt(elemVals.getString(`${elemId}`))
            if (nGetKind(elemId) == "SPREAD_ELEM") {
                arrPreRegs.set(`${nGetI1(elemId)}`, reg(ev))
            } else {
                arrPreRegs.set(`${elemId}`, reg(ev))
            }
        }
    }
    return 0 - constVal(genArrayLit(astId)) - 1
}
