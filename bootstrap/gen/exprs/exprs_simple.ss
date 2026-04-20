// gen/exprs_simple.ss — 简单表达式:this / ident / unary / index access / postfix。

function genThisExpr(): string {
    const r = nextReg()
    emitIR(`  ${r} = load ptr, ptr %this, align 8`)
    return r
}

function genIdent(id: int): string {
    const name = nGetS1(id)
    const vType = getVarType(name)
    if (vType == "" && funcRetTypes.has(name) == 1) {
        const r = nextReg()
        emitIR(`  ${r} = ptrtoint ptr @${name} to i64`)
        return r
    }
    const r = nextReg(); emitIR(`  ${r} = load ${ssTypeToLLVM(vType)}, ptr ${varRef(name)}, align 8`); return r
}

function genUnary(id: int): string {
    const op = nGetS1(id)
    const val = genExpr(nGetI1(id))
    const r = nextReg()
    if (op == "Neg") {
        const uType = inferType(nGetI1(id))
        if (uType == "double") {
            emitIR(`  ${r} = fsub double 0.0, ${val}`)
        } else {
            emitIR(`  ${r} = sub i32 0, ${val}`)
        }
    } else if (op == "BitNot") {
        emitIR(`  ${r} = xor i32 ${val}, -1`)
    } else {
        emitIR(`  ${r} = icmp eq i32 ${val}, 0`)
        const r2 = nextReg()
        emitIR(`  ${r2} = zext i1 ${r} to i32`)
        return r2
    }
    return r
}

function genIndexAccess(id: int, preObj: string = "", preIdx: string = ""): string {
    const idxId = nGetI2(id)
    if (isCtStringIdx(idxId) == 1) {
        const objClass = resolveObjClass(nGetI1(id))
        if (objClass != "" && classFields.has(objClass) == 1) {
            const fieldName = resolveCtString(idxId)
            const objVal = preObj != "" ? preObj : genExpr(nGetI1(id))
            return emitFieldLoad(objClass, objVal, fieldName)
        }
    }

    let arrVal = preObj != "" ? preObj : genExpr(nGetI1(id))
    const arrType = inferType(nGetI1(id))
    if (arrType == "i64") {
        const cvtR = nextReg()
        emitIR(`  ${cvtR} = inttoptr i64 ${arrVal} to ptr`)
        arrVal = cvtR
    }
    const idxVal = preIdx != "" ? preIdx : genExpr(idxId)
    const rawR = nextReg(); emitIR(`  ${rawR} = call i64 @ss_arrayGet(ptr ${arrVal}, i32 ${idxVal})`)
    let idxElem = inferTupleIndexType(id)
    if (idxElem == "") { idxElem = inferArrayElemType(nGetI1(id)) }
    return emitI64ToValue(rawR, idxElem)
}

function genPostfixExpr(id: int): string {
    const pieRef = varRef(nGetS1(id))
    const r1 = nextReg()
    emitIR(`  ${r1} = load i32, ptr ${pieRef}, align 4`)
    const r2 = nextReg()
    emitIR(`  ${r2} = add i32 ${r1}, 1`)
    emitIR(`  store i32 ${r2}, ptr ${pieRef}, align 4`)
    return r1
}
