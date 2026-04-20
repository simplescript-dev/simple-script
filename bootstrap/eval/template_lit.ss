// D108 §步骤 1: TEMPLATE_LIT 迁出 eval_expr.ss 独立子目录文件
// 对称三段式:全 ct → 拼接 string;有 runtime → tmplPreRegs + genTemplateLit

function evalTemplateLit(astId: int): int {
    const fragList = nGetList(astId)
    if (fragList == "") { return ctVal(interpNewString("")) }
    let allCt = 1
    const tmplParts = fragList.split(",")
    let fragVals = new Map()
    for (tp in tmplParts) {
        const fragId = parseInt(tp)
        if (fragId > 0 && nGetKind(fragId) == "TMPL_FRAG_EXPR") {
            const fv = genVal(nGetI1(fragId))
            fragVals.set(`${fragId}`, `${fv}`)
            if (isCt(fv) != 1) { allCt = 0 }
        }
    }
    if (allCt == 1) {
        let ctResult = ""
        for (tp in tmplParts) {
            const fragId = parseInt(tp)
            if (fragId > 0) {
                const fk = nGetKind(fragId)
                if (fk == "TMPL_FRAG_LIT") {
                    ctResult = `${ctResult}${nGetS1(fragId)}`
                } else if (fk == "TMPL_FRAG_EXPR" && fragVals.has(`${fragId}`) == 1) {
                    const fv = parseInt(fragVals.getString(`${fragId}`))
                    if (isCt(fv) == 1) {
                        ctResult = `${ctResult}${interpToStr(payload(fv))}`
                    }
                }
            }
        }
        return ctVal(interpNewString(ctResult))
    }
    if (comptimeDepth > 0) { return comptimeError("template literal contains runtime expression", astId) }
    tmplPreRegs = new Map()
    for (tp in tmplParts) {
        const fragId = parseInt(tp)
        if (fragId > 0 && nGetKind(fragId) == "TMPL_FRAG_EXPR") {
            const fv = parseInt(fragVals.getString(`${fragId}`))
            tmplPreRegs.set(`${fragId}`, reg(fv))
        }
    }
    return 0 - constVal(genTemplateLit(astId)) - 1
}
