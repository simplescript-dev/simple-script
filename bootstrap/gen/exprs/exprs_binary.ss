// gen/exprs_binary.ss — 二元运算 codegen:string concat / string cmp / null coalesce /
// short circuit / int / double / Instanceof / As / Pow / fn 比较。genBinary 为本族分发入口。

// D169 §1.5d prereq:lPreReg/rPreReg 可选预求值 reg(默认 "")透传 genExprAsString
// preReg 协议(exprs_str_conv.ss:4 先例)— caller 已 eager 时 forward 避双 eval。
function genStringConcat(leftId: int, rightId: int, lPreReg: string = "", rPreReg: string = ""): string {
    const l = genExprAsString(leftId, lPreReg)
    const lOwned = lastExprStringOwned
    const rVal = genExprAsString(rightId, rPreReg)
    const rOwned = lastExprStringOwned
    const r = nextReg(); emitIR(`  ${r} = call ptr @ss_string_concat(ptr ${l}, ptr ${rVal})`)
    // RC: release left operand (concat chain intermediate or conversion temp)
    if (lOwned == 1 || (nGetKind(leftId) == "BINARY" && inferType(nGetI1(leftId)) == "string")) {
        emitIR(`  call void @ss_rc_release(ptr ${l})`)
    }
    // RC Phase 5: release right conversion temp
    if (rOwned == 1) {
        emitIR(`  call void @ss_rc_release(ptr ${rVal})`)
    }
    return r
}

function genStringCompare(op: string, leftId: int, rightId: int, blt: string, brt: string): string {
    // String equality (Eq/Ne)
    if (op == "Eq" || op == "Ne") {
        let l = genExpr(leftId)
        let rVal = genExpr(rightId)
        if (blt == "i64") {
            const cvR = nextReg()
            emitIR(`  ${cvR} = inttoptr i64 ${l} to ptr`)
            l = cvR
        }
        if (brt == "i64") {
            const cvR = nextReg()
            emitIR(`  ${cvR} = inttoptr i64 ${rVal} to ptr`)
            rVal = cvR
        }
        const r = nextReg()
        if (op == "Eq") {
            emitIR(`  ${r} = call i32 @ss_string_eq(ptr ${l}, ptr ${rVal})`)
        } else {
            emitIR(`  ${r} = call i32 @ss_string_ne(ptr ${l}, ptr ${rVal})`)
        }
        return r
    }
    // String ordering (Lt/Gt/Le/Ge) using strcmp
    const sl = genExpr(leftId)
    const sr = genExpr(rightId)
    const cmpR = nextReg()
    emitIR(`  ${cmpR} = call i32 @ss_strcmp(ptr ${sl}, ptr ${sr})`)
    let cmpOp = "slt"
    if (op == "Gt") { cmpOp = "sgt" }
    if (op == "Le") { cmpOp = "sle" }
    if (op == "Ge") { cmpOp = "sge" }
    const cmpBool = nextReg()
    emitIR(`  ${cmpBool} = icmp ${cmpOp} i32 ${cmpR}, 0`)
    const r = nextReg(); emitIR(`  ${r} = zext i1 ${cmpBool} to i32`); return r
}

// D093 §Phase 1.5e+ ext:lPreReg/rPreReg 哨兵 forward — caller eager `genVal(nGetI1)`
// 后 reg(lRaw) 传入,本函数避 genExpr(leftId) 再 eval(双 eval bug 桥消除);rPreReg 同形
// 但 NullCoalesce 短路语义保留 — rhs 只在 lhs null 时 lazy eval,本函数 ncRight 由
// rPreReg(若 forward)或 genExpr(rightId) 在 lhs-null br then 块内 eval(D093 §1.5d
// 主轮第三子步 sibling 完全一致接口扩,对齐 genStringConcat/genBinary 范式)
function genNullCoalesce(leftId: int, rightId: int, lPreReg: string = "", rPreReg: string = ""): string {
    const ncResult = emitEntryAlloca(nextReg(), "ptr", 8)
    const ncLeft = lPreReg != "" ? lPreReg : genExpr(leftId)
    emitIR(`  store ptr ${ncLeft}, ptr ${ncResult}, align 8`)
    // String: check length == 0; class/other ptr: check == null (D067)
    const ncLType = inferType(leftId)
    let ncCmp = ""
    if (ncLType == "string") {
        const ncLen = nextReg()
        emitIR(`  ${ncLen} = call i32 @ss_stringLength(ptr ${ncLeft})`)
        ncCmp = nextReg()
        emitIR(`  ${ncCmp} = icmp eq i32 ${ncLen}, 0`)
    } else {
        ncCmp = nextReg()
        emitIR(`  ${ncCmp} = icmp eq ptr ${ncLeft}, null`)
    }
    const ncThen = nextLabel("nc.then")
    const ncEnd = nextLabel("nc.end")
    emitIR(`  br i1 ${ncCmp}, label %${ncThen}, label %${ncEnd}`)
    emitIR(`${ncThen}:`)
    const ncRight = rPreReg != "" ? rPreReg : genExpr(rightId)
    emitIR(`  store ptr ${ncRight}, ptr ${ncResult}, align 8`)
    emitIR(`  br label %${ncEnd}`)
    emitIR(`${ncEnd}:`)
    const ncFinal = nextReg()
    emitIR(`  ${ncFinal} = load ptr, ptr ${ncResult}, align 8`)
    return ncFinal
}

function genShortCircuit(op: string, leftId: int, rightId: int): string {
    const scResult = emitEntryAlloca(nextReg(), "i32", 4)
    const scLeft = genExpr(leftId)
    emitIR(`  store i32 ${scLeft}, ptr ${scResult}, align 4`)
    const scCmp = nextReg()
    emitIR(`  ${scCmp} = icmp ne i32 ${scLeft}, 0`)
    const scRhs = nextLabel("sc.rhs")
    const scEnd = nextLabel("sc.end")
    if (op == "And") { emitIR(`  br i1 ${scCmp}, label %${scRhs}, label %${scEnd}`) } else { emitIR(`  br i1 ${scCmp}, label %${scEnd}, label %${scRhs}`) }
    emitIR(`${scRhs}:`)
    const scRight = genExpr(rightId)
    emitIR(`  store i32 ${scRight}, ptr ${scResult}, align 4`)
    emitIR(`  br label %${scEnd}`)
    emitIR(`${scEnd}:`)
    const scRes = nextReg()
    emitIR(`  ${scRes} = load i32, ptr ${scResult}, align 4`)
    return scRes
}

function genDoubleBinary(op: string, left: string, right: string, blt: string, brt: string): string {
    let dl = left
    let dr = right
    if (blt != "double") {
        const cvtR = nextReg()
        emitIR(`  ${cvtR} = sitofp i32 ${dl} to double`)
        dl = cvtR
    }
    if (brt != "double") {
        const cvtR = nextReg()
        emitIR(`  ${cvtR} = sitofp i32 ${dr} to double`)
        dr = cvtR
    }
    const r = nextReg()
    if (op == "Add") { emitIR(`  ${r} = fadd double ${dl}, ${dr}`); return r }
    if (op == "Sub") { emitIR(`  ${r} = fsub double ${dl}, ${dr}`); return r }
    if (op == "Mul") { emitIR(`  ${r} = fmul double ${dl}, ${dr}`); return r }
    if (op == "Div") { emitIR(`  ${r} = fdiv double ${dl}, ${dr}`); return r }
    if (op == "Mod") { emitIR(`  ${r} = frem double ${dl}, ${dr}`); return r }
    let fcmpOp = ""
    if (op == "Eq") { fcmpOp = "oeq" }
    if (op == "Ne") { fcmpOp = "one" }
    if (op == "Lt") { fcmpOp = "olt" }
    if (op == "Gt") { fcmpOp = "ogt" }
    if (op == "Le") { fcmpOp = "ole" }
    if (op == "Ge") { fcmpOp = "oge" }
    if (fcmpOp != "") {
        emitIR(`  ${r} = fcmp ${fcmpOp} double ${dl}, ${dr}`)
        const r2 = nextReg()
        emitIR(`  ${r2} = zext i1 ${r} to i32`)
        return r2
    }
    return r
}

function genIntBinary(op: string, left: string, right: string): string {
    const r = nextReg()
    if (op == "Add") { emitIR(`  ${r} = add i32 ${left}, ${right}`); return r }
    if (op == "Sub") { emitIR(`  ${r} = sub i32 ${left}, ${right}`); return r }
    if (op == "Mul") { emitIR(`  ${r} = mul i32 ${left}, ${right}`); return r }
    if (op == "Div") { emitIR(`  ${r} = sdiv i32 ${left}, ${right}`); return r }
    if (op == "Mod") { emitIR(`  ${r} = srem i32 ${left}, ${right}`); return r }
    if (op == "BitAnd") { emitIR(`  ${r} = and i32 ${left}, ${right}`); return r }
    if (op == "BitOr") { emitIR(`  ${r} = or i32 ${left}, ${right}`); return r }
    if (op == "BitXor") { emitIR(`  ${r} = xor i32 ${left}, ${right}`); return r }
    if (op == "Shl") { emitIR(`  ${r} = shl i32 ${left}, ${right}`); return r }
    if (op == "Shr") { emitIR(`  ${r} = ashr i32 ${left}, ${right}`); return r }
    if (op == "UShr") { emitIR(`  ${r} = lshr i32 ${left}, ${right}`); return r }
    let cmpOp = ""
    if (op == "Eq") { cmpOp = "eq" }
    if (op == "Ne") { cmpOp = "ne" }
    if (op == "Lt") { cmpOp = "slt" }
    if (op == "Gt") { cmpOp = "sgt" }
    if (op == "Le") { cmpOp = "sle" }
    if (op == "Ge") { cmpOp = "sge" }
    if (cmpOp != "") {
        emitIR(`  ${r} = icmp ${cmpOp} i32 ${left}, ${right}`)
        const r2 = nextReg()
        emitIR(`  ${r2} = zext i1 ${r} to i32`)
        return r2
    }
    emitIR(`  ; unknown binary op: ${op}`)
    return r
}

// D169 §1.5d prereq + D093 §1.5e+ ext:lPreReg/rPreReg 可选预求值 reg(默认 "")
// 透传 genStringConcat + 数值 op eager + NullCoalesce(rhs 在 ncThen br 块内 lazy
// genExpr 保短路语义,见 genNullCoalesce sig 注)。**不 forward** 给 ShortCircuit/
// Instanceof/As(短路/单边控制流语义不可 eager);genStringCompare 本轮不在 scope。
function genBinary(id: int, lPreReg: string = "", rPreReg: string = ""): string {
    const op = nGetS1(id)
    const leftId = nGetI1(id)
    const rightId = nGetI2(id)
    const blt = inferType(leftId)
    const brt = inferType(rightId)

    // String concatenation
    if (op == "Add" && (blt == "string" || brt == "string" || blt == "i64" || brt == "i64")) {
        if (blt == "string" || brt == "string") {
            return genStringConcat(leftId, rightId, lPreReg, rPreReg)
        }
    }
    // String equality/comparison
    if ((op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge") && (blt == "string" || brt == "string")) {
        return genStringCompare(op, leftId, rightId, blt, brt)
    }
    if (op == "NullCoalesce") { return genNullCoalesce(leftId, rightId, lPreReg, rPreReg) }
    if (op == "And" || op == "Or") { return genShortCircuit(op, leftId, rightId) }
    if (op == "Instanceof") {
        const objReg = genExpr(leftId)
        const className = nGetS1(rightId)
        const nameStr = addStringConst(className)
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_isinstance(ptr ${objReg}, ptr ${nameStr})`)
        return r
    }
    if (op == "As") {
        const objReg = genExpr(leftId)
        const className = nGetS1(rightId)
        const nameStr = addStringConst(className)
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_isinstance(ptr ${objReg}, ptr ${nameStr})`)
        const ok = nextReg()
        emitIR(`  ${ok} = icmp eq i32 ${r}, 1`)
        const okL = nextLabel("cast.ok")
        const failL = nextLabel("cast.fail")
        emitIR(`  br i1 ${ok}, label %${okL}, label %${failL}`)
        emitIR(`${failL}:`)
        const errMsg = addStringConst(`type cast failed: expected ${className}`)
        emitIR(`  call void @ss_throw(ptr ${errMsg})`)
        emitIR("  unreachable")
        emitIR(`${okL}:`)
        return objReg
    }

    // Numeric: evaluate operands (lPreReg/rPreReg forward if caller eager)
    let left = lPreReg != "" ? lPreReg : genExpr(leftId)
    let right = rPreReg != "" ? rPreReg : genExpr(rightId)
    if (blt == "i64") { const tr = nextReg(); emitIR(`  ${tr} = trunc i64 ${left} to i32`); left = tr }
    if (brt == "i64") { const tr = nextReg(); emitIR(`  ${tr} = trunc i64 ${right} to i32`); right = tr }

    // Pow: always use double math via ss_pow, convert back if both operands are int
    if (op == "Pow") {
        let dl = left
        let dr = right
        if (blt != "double") {
            const cv = nextReg()
            emitIR(`  ${cv} = sitofp i32 ${dl} to double`)
            dl = cv
        }
        if (brt != "double") {
            const cv = nextReg()
            emitIR(`  ${cv} = sitofp i32 ${dr} to double`)
            dr = cv
        }
        const powR = nextReg()
        emitIR(`  ${powR} = call double @ss_pow(double ${dl}, double ${dr})`)
        if (blt != "double" && brt != "double") {
            const intR = nextReg()
            emitIR(`  ${intR} = fptosi double ${powR} to i32`)
            return intR
        }
        return powR
    }

    if (blt == "double" || brt == "double") {
        return genDoubleBinary(op, left, right, blt, brt)
    }
    // Pointer comparison: class/null Eq/Ne — both sides must be ptr (D067)
    if ((op == "Eq" || op == "Ne") && ssTypeToLLVM(blt) == "ptr" && ssTypeToLLVM(brt) == "ptr") {
        const pcOp = op == "Eq" ? "eq" : "ne"
        const pcR = nextReg()
        emitIR(`  ${pcR} = icmp ${pcOp} ptr ${left}, ${right}`)
        const pcR2 = nextReg()
        emitIR(`  ${pcR2} = zext i1 ${pcR} to i32`)
        return pcR2
    }
    // fn comparison: compare as i64
    if ((op == "Eq" || op == "Ne") && (blt == "fn" || brt == "fn")) {
        let fnL = left
        let fnR = right
        if (blt != "fn" && blt != "i64") {
            const ext = nextReg()
            emitIR(`  ${ext} = sext i32 ${fnL} to i64`)
            fnL = ext
        }
        if (brt != "fn" && brt != "i64") {
            const ext = nextReg()
            emitIR(`  ${ext} = sext i32 ${fnR} to i64`)
            fnR = ext
        }
        const fnCmpOp = op == "Eq" ? "eq" : "ne"
        const fnCmpR = nextReg()
        emitIR(`  ${fnCmpR} = icmp ${fnCmpOp} i64 ${fnL}, ${fnR}`)
        const fnCmpR2 = nextReg()
        emitIR(`  ${fnCmpR2} = zext i1 ${fnCmpR} to i32`)
        return fnCmpR2
    }
    return genIntBinary(op, left, right)
}
