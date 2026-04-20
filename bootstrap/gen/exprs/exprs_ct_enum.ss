// gen/exprs_ct_enum.ss — Comptime enum helpers:EnumType.names() / values() / valueOf()。

function ctEnumListMethod(eName: string, wantNames: int): int {
    const enumId = parseInt(interpEnumNodes.getString(eName))
    const vl = nGetList(enumId)
    if (vl == "") { return interpNewArray("") }
    const isString = interpEnumTypes.has(eName) == 1
    const arr = interpNewArray("")
    const parts = vl.split(",")
    for (p in parts) {
        const vid = parseInt(p)
        if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
            if (wantNames == 1) {
                interpArrayPush(arr, interpNewString(nGetS1(vid)))
            } else {
                const val = interpEnumValues.getString(`${eName}.${nGetS1(vid)}`)
                if (isString) { interpArrayPush(arr, interpNewString(val)) }
                else { interpArrayPush(arr, interpNewInt(parseInt(val))) }
            }
        }
    }
    return arr
}

function ctEnumValueOfMethod(eName: string, nodeId: int): int {
    const voArgList = nGetList(nodeId)
    if (voArgList != "") {
        const voArgId = parseInt(voArgList.split(",")[0])
        const voVal = genVal(voArgId)
        if (isCt(voVal) == 1) {
            const voName = interpAsStr(payload(voVal))
            const voKey = `${eName}.${voName}`
            if (interpEnumValues.has(voKey) == 1) {
                if (interpEnumTypes.has(eName) == 1) { return interpNewString(interpEnumValues.getString(voKey)) }
                return interpNewInt(parseInt(interpEnumValues.getString(voKey)))
            }
        }
    }
    return interpNewNull()
}
