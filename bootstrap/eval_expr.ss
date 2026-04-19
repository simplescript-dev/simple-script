// D099 §步骤 1-4:evalExpr 吸收 BINARY + UNARY + TERNARY + SHORT_CIRCUIT(And/Or)。Phase A mv 编码:
//   mv >= 0   → known,  val = mv        (ctVal tagged int,bit 30 set)
//   mv <= -2  → runtime,regId = -mv - 1  (regTable 1-based)
//   mv == -1  → error 哨兵
// 调派:genValBinary/genValUnary 过滤对应 kind 后转 evalExpr;genVal L135 TERNARY inline 转
// evalExpr。TERNARY / SHORT_CIRCUIT body 落在 evalTernary / evalShortCircuit 独立函数
// (D099 §坑 L:runtime phi AST 密度高 inline 会炸 N3,改删 gen*独立函数 + 新建 eval* 维持 M7b)。

function evalExpr(astId: int): int {
    const k = nGetKind(astId)
    if (k == "UNARY") {
        const uOp = nGetS1(astId)
        if (comptimeDepth > 0) {
            const ctUv = genVal(nGetI1(astId))
            if (isCt(ctUv) == 0) { return ctVal(interpNewNull()) }
            const ctUp = payload(ctUv)
            const ctUt = interpType(ctUp)
            if (uOp == "Neg") {
                if (ctUt == "double") { return ctVal(interpNewDouble(0.0 - parseDouble(interpAsStr(ctUp)))) }
                return ctVal(interpNewInt(0 - interpAsInt(ctUp)))
            }
            if (uOp == "Not") { return ctVal(interpNewBool(interpTruthy(ctUp) == 1 ? 0 : 1)) }
            if (uOp == "BitNot") { return ctVal(interpNewInt(~interpAsInt(ctUp))) }
            return ctVal(interpNewNull())
        }
        const uType = inferType(nGetI1(astId))
        if (uType != "int" && uType != "bool") {
            return 0 - constVal(genUnary(astId)) - 1
        }
        const ov = genVal(nGetI1(astId))
        if (isCt(ov) == 1) {
            const uVal = interpAsInt(payload(ov))
            if (uOp == "Neg") { return ctVal(interpNewInt(0 - uVal)) }
            if (uOp == "Not") { return ctVal(interpNewBool(uVal == 0 ? 1 : 0)) }
            if (uOp == "BitNot") { return ctVal(interpNewInt(~uVal)) }
        }
        const uValStr = reg(ov)
        const uR = nextReg()
        if (uOp == "Neg") {
            emitIR(`  ${uR} = sub i32 0, ${uValStr}`)
            return 0 - constVal(uR) - 1
        }
        if (uOp == "BitNot") {
            emitIR(`  ${uR} = xor i32 ${uValStr}, -1`)
            return 0 - constVal(uR) - 1
        }
        emitIR(`  ${uR} = icmp eq i32 ${uValStr}, 0`)
        const uR2 = nextReg()
        emitIR(`  ${uR2} = zext i1 ${uR} to i32`)
        return 0 - constVal(uR2) - 1
    }
    if (k == "TERNARY") { return evalTernary(astId) }
    if (k == "COMPTIME_EXPR") {
        if (comptimeDepth > 0) { return comptimeError("nested comptime expression", astId) }
        inferType(astId)
        return 0 - constVal(comptimeExprLiteral.getString(`${astId}`)) - 1
    }
    if (k == "INDEX_ACCESS") { return evalIndexAccess(astId) }
    if (k == "TEMPLATE_LIT") { return evalTemplateLit(astId) }
    if (k == "ARRAY_LIT") { return evalArrayLit(astId) }
    if (k == "IDENT") { return evalIdent(astId) }
    const op = nGetS1(astId)
    if (op == "And" || op == "Or") { return evalShortCircuit(op, astId) }
    if (comptimeDepth > 0) {
        if (op == "NullCoalesce") {
            const ctNcL = genVal(nGetI1(astId))
            if (isCt(ctNcL) == 1 && interpType(payload(ctNcL)) != "null") { return ctNcL }
            return genVal(nGetI2(astId))
        }
        if (op == "Instanceof" || op == "As") {
            return comptimeError(`operator '${op}' not supported`, astId)
        }
        const ctBlv = genVal(nGetI1(astId))
        const ctBrv = genVal(nGetI2(astId))
        if (isCt(ctBlv) == 0 || isCt(ctBrv) == 0) {
            return comptimeError(`binary '${op}' operand is not compile-time known`, astId)
        }
        const ctBlp = payload(ctBlv)
        const ctBrp = payload(ctBrv)
        const ctBlt = interpType(ctBlp)
        const ctBrt = interpType(ctBrp)
        if (op == "Add" && (ctBlt == "string" || ctBrt == "string")) {
            return ctVal(interpNewString(`${interpToStr(ctBlp)}${interpToStr(ctBrp)}`))
        }
        if (ctBlt == "string" && ctBrt == "string") { return genValStringCompare(op, astId) }
        if (ctBlt == "double" || ctBrt == "double") {
            const ctLd = ctBlt == "double" ? parseDouble(interpAsStr(ctBlp)) : parseDouble(`${interpAsInt(ctBlp)}`)
            const ctRd = ctBrt == "double" ? parseDouble(interpAsStr(ctBrp)) : parseDouble(`${interpAsInt(ctBrp)}`)
            return ctVal(interpDoubleOp(op, ctLd, ctRd))
        }
        return ctVal(interpIntOp(op, interpAsInt(ctBlp), interpAsInt(ctBrp)))
    }
    if (op == "NullCoalesce" || op == "Instanceof" || op == "As" || op == "Pow") {
        return 0 - constVal(genBinary(astId)) - 1
    }
    const blt = inferType(nGetI1(astId))
    const brt = inferType(nGetI2(astId))
    if (blt == "string" && brt == "string" && (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge")) {
        const sc = genValStringCompare(op, astId)
        if (isCt(sc) == 1) { return sc }
        return 0 - sc - 1
    }
    if ((blt != "int" && blt != "bool") || (brt != "int" && brt != "bool")) {
        return 0 - constVal(genBinary(astId)) - 1
    }
    const lv = genVal(nGetI1(astId))
    const rv = genVal(nGetI2(astId))
    if (isCt(lv) == 1 && isCt(rv) == 1) {
        return ctVal(interpIntOp(op, interpAsInt(payload(lv)), interpAsInt(payload(rv))))
    }
    return 0 - constVal(genIntBinary(op, reg(lv), reg(rv))) - 1
}

function evalTernary(astId: int): int {
    const cv = genVal(nGetI1(astId))
    if (isCt(cv) == 1) {
        const pv = genVal(interpTruthy(payload(cv)) == 1 ? nGetI2(astId) : nGetI3(astId))
        return isCt(pv) == 1 ? pv : 0 - pv - 1
    }
    if (comptimeDepth > 0) { return ctVal(interpNewNull()) }
    const condStr = reg(cv)
    const llType = ssTypeToLLVM(inferType(nGetI2(astId)))
    const alloca = nextReg()
    emitIR(`  ${alloca} = alloca ${llType}, align 8`)
    const cmp = nextReg()
    emitIR(`  ${cmp} = icmp ne i32 ${condStr}, 0`)
    const thenL = nextLabel("tern.then")
    const elseL = nextLabel("tern.else")
    const mergeL = nextLabel("tern.merge")
    emitIR(`  br i1 ${cmp}, label %${thenL}, label %${elseL}`)
    emitIR(`${thenL}:`)
    const thenV = genExpr(nGetI2(astId))
    emitIR(`  store ${llType} ${thenV}, ptr ${alloca}, align 8`)
    emitIR(`  br label %${mergeL}`)
    emitIR(`${elseL}:`)
    const elseV = genExpr(nGetI3(astId))
    emitIR(`  store ${llType} ${elseV}, ptr ${alloca}, align 8`)
    emitIR(`  br label %${mergeL}`)
    emitIR(`${mergeL}:`)
    const r = nextReg()
    emitIR(`  ${r} = load ${llType}, ptr ${alloca}, align 8`)
    return 0 - constVal(r) - 1
}

function evalShortCircuit(op: string, astId: int): int {
    const lv = genVal(nGetI1(astId))
    if (isCt(lv) == 1) {
        const leftTruthy = interpTruthy(payload(lv))
        if (op == "And" && leftTruthy == 0) { return ctVal(interpNewBool(0)) }
        if (op == "Or" && leftTruthy == 1) { return lv }
        const rv = genVal(nGetI2(astId))
        return isCt(rv) == 1 ? rv : 0 - rv - 1
    }
    if (comptimeDepth > 0) { return ctVal(interpNewNull()) }
    const leftStr = reg(lv)
    const scResult = nextReg()
    emitIR(`  ${scResult} = alloca i32, align 4`)
    emitIR(`  store i32 ${leftStr}, ptr ${scResult}, align 4`)
    const scCmp = nextReg()
    emitIR(`  ${scCmp} = icmp ne i32 ${leftStr}, 0`)
    const scRhs = nextLabel("sc.rhs")
    const scEnd = nextLabel("sc.end")
    const brLabels = op == "And" ? `label %${scRhs}, label %${scEnd}` : `label %${scEnd}, label %${scRhs}`
    emitIR(`  br i1 ${scCmp}, ${brLabels}`)
    emitIR(`${scRhs}:`)
    const scRight = genExpr(nGetI2(astId))
    emitIR(`  store i32 ${scRight}, ptr ${scResult}, align 4`)
    emitIR(`  br label %${scEnd}`)
    emitIR(`${scEnd}:`)
    const scRes = nextReg()
    emitIR(`  ${scRes} = load i32, ptr ${scResult}, align 4`)
    return 0 - constVal(scRes) - 1
}

function evalIndexAccess(astId: int): int {
    const obj = genVal(nGetI1(astId))
    const idx = genVal(nGetI2(astId))
    if (isCt(obj) == 1 && isCt(idx) == 1) {
        const objP = payload(obj)
        const ot = interpType(objP)
        if (ot == "array") { return ctVal(interpArrayGet(objP, interpAsInt(payload(idx)))) }
        if (ot == "object" || ot == "map") { return ctVal(interpGetField(objP, interpAsStr(payload(idx)))) }
        if (ot == "string") {
            const s = interpAsStr(objP)
            const i = interpAsInt(payload(idx))
            return ctVal(interpNewString(i >= 0 && i < s.length() ? s.charAt(i) : ""))
        }
    }
    if (comptimeDepth > 0) { return comptimeError("index access requires compile-time known operands", astId) }
    return 0 - constVal(genIndexAccess(astId, reg(obj), reg(idx))) - 1
}

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

function evalArrayLit(astId: int): int {
    const elemList = nGetList(astId)
    if (elemList == "") {
        if (comptimeDepth > 0) { return ctVal(interpNewArray("")) }
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
    if (comptimeDepth > 0) {
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

function evalIdent(astId: int): int {
    const ctIdName = nGetS1(astId)
    if (comptimeDepth > 0 && ctScopeStack.length() > 0) {
        let ctSi = ctScopeStack.length() - 1
        while (ctSi >= 0) {
            const ctScopeKey = `${ctScopeStack[ctSi]}:${ctIdName}`
            if (ctVars.has(ctScopeKey) == 1) {
                return parseInt(ctVars.getString(ctScopeKey))
            }
            ctSi = ctSi - 1
        }
    }
    const ctKey = `${currentFunc}:${ctIdName}`
    if (ctVars.has(ctKey) == 1 && ctInvalidated.has(ctKey) == 0) {
        const ctIdVal = parseInt(ctVars.getString(ctKey))
        if (isCt(ctIdVal) == 1) { return ctIdVal }
    }
    if (comptimeDepth > 0) {
        const ctInterpKey = interpFindScopeKey(ctIdName)
        if (ctInterpKey != "") {
            return ctVal(parseInt(interpVars.getString(ctInterpKey)))
        }
        // class 名 in comptime → TypeValue(已注册的 user/interp class,或 const T = comptime{...} alias)
        if (isKnownClass(ctIdName) == 1) {
            return ctVal(interpNewType(ctIdName))
        }
        // 泛型实参 T 绑定的类名 → TypeValue(monomorphize 时 genericTypeSubs[T]=Foo);
        // 支持 comptime 内 T.name / T.fields / `return T`。
        if (genericTypeSubs.has(ctIdName) == 1) {
            const ctSubName = genericTypeSubs.getString(ctIdName)
            if (isKnownClass(ctSubName) == 1) {
                return ctVal(interpNewType(ctSubName))
            }
        }
        const ctAliased = resolveCtTypeAlias(ctIdName)
        if (ctAliased != ctIdName) {
            return ctVal(interpNewType(ctAliased))
        }
    }
    return 0 - constVal(genIdent(astId)) - 1
}
