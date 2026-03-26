// Statement generation for bootstrap codegen
// ── Statement generation ──────────────────────────────────────

function genStmt(id: int) {
    const kind = nGetKind(id)

    if (kind == "FUNC_DECL") {
        const fname = nGetS1(id)
        // Skip duplicate function declarations (from merged imports)
        if (fname != "main" && funcRetTypes.has(`${fname}_generated`) == 1) { return }
        funcRetTypes.set(`${fname}_generated`, "1")
        genFuncDecl(id)
        return
    }
    if (kind == "VAR_DECL") {
        genVarDecl(id)
        return
    }
    if (kind == "ASSIGN") {
        genAssign(id)
        return
    }
    if (kind == "EXPR_STMT") {
        genExpr(nGetI1(id))
        return
    }
    if (kind == "RETURN") {
        genReturn(id)
        return
    }
    if (kind == "IF") {
        genIf(id)
        return
    }
    if (kind == "FOR") {
        genFor(id)
        return
    }
    if (kind == "FOR_IN") {
        genForIn(id)
        return
    }
    if (kind == "WHILE") {
        genWhile(id)
        return
    }
    if (kind == "BREAK") {
        if (breakLabel != "") {
            emitIR(`  br label %${breakLabel}`)
            terminated = 1
        }
        return
    }
    if (kind == "CONTINUE") {
        if (continueLabel != "") {
            emitIR(`  br label %${continueLabel}`)
            terminated = 1
        }
        return
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") {
        const pRef = varRef(nGetS1(id))
        const r1 = nextReg()
        emitIR(`  ${r1} = load i32, ptr ${pRef}, align 4`)
        const r2 = nextReg()
        if (kind == "POSTFIX_INC") { emitIR(`  ${r2} = add i32 ${r1}, 1`) } else { emitIR(`  ${r2} = sub i32 ${r1}, 1`) }
        emitIR(`  store i32 ${r2}, ptr ${pRef}, align 4`)
        return
    }
    if (kind == "DO_WHILE") {
        genDoWhile(id)
        return
    }
    if (kind == "SWITCH") {
        genSwitch(id)
        return
    }
    if (kind == "INDEX_ASSIGN") {
        // arr[i] = val — nGetS1=arrName, nGetI1=indexExpr, nGetI2=valueExpr
        const arrPtr = nextReg()
        emitIR(`  ${arrPtr} = load ptr, ptr ${varRef(nGetS1(id))}, align 8`)
        const idxVal = genExpr(nGetI1(id))
        const valVal = genExpr(nGetI2(id))
        const vt = inferType(nGetI2(id))
        let v64 = valVal
        if (vt == "int" || vt == "auto" || vt == "") { const s = nextReg(); emitIR(`  ${s} = sext i32 ${valVal} to i64`); v64 = s }
        if (vt == "string" || vt == "ptr") { const c = nextReg(); emitIR(`  ${c} = ptrtoint ptr ${valVal} to i64`); v64 = c }
        emitIR(`  call void @ss_arraySet(ptr ${arrPtr}, i32 ${idxVal}, i64 ${v64})`)
        return
    }
    if (kind == "CLASS_DECL") {
        genClassDecl(id)
        return
    }
    // IMPORT, INTERFACE_DECL, ENUM_DECL — skip
}

function genFuncDecl(id: int) {
    const name = nGetS1(id)
    regCount = 0
    currentFunc = name
    terminated = 0
    varAliases = Map()

    // For 'main', use C main signature
    if (name == "main") {
        emitIR("define i32 @main(i32 %0, ptr %1) {")
        emitIR("entry:")
        emitIR("  call void @ss_initArgs(i32 %0, ptr %1)")
        regCount = 2
    } else {
        // Collect param types (MVP: all int for now)
        const paramList = nGetList(id)
        let paramStr = ""
        if (paramList != "") {
            const parts = paramList.split(",")
            let idx = 0
            for (p in parts) {
                const pId = parseInt(p)
                if (pId > 0) {
                    if (idx > 0) { paramStr = paramStr + ", " }
                    paramStr = `${paramStr}${ssTypeToLLVM(nGetS2(pId))} %${nGetS1(pId)}.arg`
                    idx = idx + 1
                }
            }
        }
        let retType = nGetS2(id)
        if (retType == "") { retType = "void" }
        const llRetType = ssTypeToLLVM(retType)
        emitIR(`define ${llRetType} @${name}(${paramStr}) {`)
        emitIR("entry:")
        // Alloca params and store argument values
        if (paramList != "") {
            const parts = paramList.split(",")
            for (p in parts) {
                const pId = parseInt(p)
                if (pId > 0) {
                    const pName = nGetS1(pId)
                    const pType = nGetS2(pId)
                    const llType = ssTypeToLLVM(pType)
                    const pLLName = allocVarName(pName)
                    emitIR(`  %${pLLName} = alloca ${llType}, align 8`)
                    emitIR(`  store ${llType} %${pName}.arg, ptr %${pLLName}, align 8`)
                    setVarType(pName, pType)
                }
            }
        }
    }

    // Generate body
    const bodyId = nGetI1(id)
    genBlock(bodyId)

    // Default return (only if not already terminated)
    if (terminated == 1) {
        emitIR("}")
        emitIR("")
        return
    }
    if (name == "main") {
        emitIR("  ret i32 0")
    } else {
        const retType = nGetS2(id)
        if (retType == "string") {
            const nullStr = addStringConst("")
            emitIR(`  ret ptr ${nullStr}`)
        } else if (retType == "double") {
            emitIR("  ret double 0.0")
        } else if (retType == "void" || retType == "") {
            emitIR("  ret void")
        } else {
            emitIR("  ret i32 0")
        }
    }
    emitIR("}")
    emitIR("")
}

function genBlock(blockId: int) {
    if (blockId <= 0) { return }
    const stmtList = nGetList(blockId)
    if (stmtList == "") { return }
    const parts = stmtList.split(",")
    for (p in parts) {
        const stmtId = parseInt(p)
        if (stmtId > 0) {
            genStmt(stmtId)
        }
    }
}

function genGlobalVar(id: int) {
    const name = nGetS1(id)
    if (globalAliases.has(name) == 1) { return }
    const initId = nGetI1(id)
    const ik = nGetKind(initId)
    let gType = "ptr"
    if (ik == "INT_LIT") { emitIR(`@${name} = global i32 ${nGetS1(initId)}, align 4`); gType = "int" } else if (ik == "DOUBLE_LIT") { emitIR(`@${name} = global double ${nGetS1(initId)}, align 8`); gType = "double" } else if (ik == "STRING_LIT") { emitIR(`@${name} = global ptr ${addStringConst(nGetS1(initId))}, align 8`); gType = "string" } else if (ik == "TRUE_LIT") { emitIR(`@${name} = global i32 1, align 4`); gType = "int" } else if (ik == "FALSE_LIT") { emitIR(`@${name} = global i32 0, align 4`); gType = "int" } else { emitIR(`@${name} = global ptr null, align 8`) }
    setVarType(name, gType)
    globalAliases.set(name, `@${name}`)
}

function genVarDecl(id: int) {
    const name = nGetS1(id)
    const initId = nGetI1(id)
    const typeAnn = nGetS3(id)

    // Infer type from init expression
    const initType = inferType(initId)
    const llType = ssTypeToLLVM(initType)

    // Skip alloca for globals (already declared) — just store the init value
    if (globalAliases.has(name) == 1) {
        const val = genExpr(initId)
        const gn = globalAliases.getString(name)
        emitIR(`  store ${llType} ${val}, ptr ${gn}, align 8`)
        return
    }
    const llName = allocVarName(name)
    emitIR(`  %${llName} = alloca ${llType}, align 8`)
    setVarType(name, initType)

    // Track object class for method dispatch
    if (nGetKind(initId) == "NEW_EXPR") {
        setObjClass(name, nGetS1(initId))
    }
    if (nGetKind(initId) == "CALL" && nGetS1(initId) == "Map") {
        setObjClass(name, "Map")
    }

    const val = genExpr(initId)
    emitIR(`  store ${llType} ${val}, ptr %${llName}, align 8`)
}

function genAssign(id: int) {
    const name = nGetS1(id)
    const op = nGetS2(id)
    const valId = nGetI1(id)

    const vType = getVarType(name)
    const llType = ssTypeToLLVM(vType)

    if (op == "ASSIGN") {
        const val = genExpr(valId)
        emitIR(`  store ${llType} ${val}, ptr ${varRef(name)}, align 8`)
    } else {
        // Compound: +=, -=, etc.
        const lnRef = varRef(name)
        const r1 = nextReg()
        emitIR(`  ${r1} = load ${llType}, ptr ${lnRef}, align 8`)
        let r2 = genExpr(valId)
        // Trunc i64 to i32 if needed
        const r2Type = inferType(valId)
        if (r2Type == "i64" && vType != "i64") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${r2} to i32`)
            r2 = trR
        }
        const r3 = nextReg()
        if (op == "PLUS_ASSIGN") {
            if (vType == "string") {
                emitIR(`  ${r3} = call ptr @ss_string_concat(ptr ${r1}, ptr ${r2})`)
            } else {
                emitIR(`  ${r3} = add i32 ${r1}, ${r2}`)
            }
        } else if (op == "MINUS_ASSIGN") {
            emitIR(`  ${r3} = sub i32 ${r1}, ${r2}`)
        } else if (op == "STAR_ASSIGN") {
            emitIR(`  ${r3} = mul i32 ${r1}, ${r2}`)
        } else if (op == "SLASH_ASSIGN") {
            emitIR(`  ${r3} = sdiv i32 ${r1}, ${r2}`)
        } else {
            emitIR(`  ${r3} = srem i32 ${r1}, ${r2}`)
        }
        emitIR(`  store ${llType} ${r3}, ptr ${lnRef}, align 8`)
    }
}

function genReturn(id: int) {
    const valId = nGetI1(id)
    if (valId <= 0) {
        if (currentFunc == "main") {
            emitIR("  ret i32 0")
        } else {
            emitIR("  ret void")
        }
    } else {
        const val = genExpr(valId)
        const vType = inferType(valId)
        const retLLType = ssTypeToLLVM(vType)
        // Get declared return type
        let declRet = "i32"
        if (funcRetTypes.has(currentFunc) == 1) {
            declRet = ssTypeToLLVM(funcRetTypes.getString(currentFunc))
        }
        if (currentFunc == "main") { declRet = "i32" }
        // Convert if needed
        if (retLLType == declRet) {
            emitIR(`  ret ${retLLType} ${val}`)
        } else if (retLLType == "i64" && declRet == "i32") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${val} to i32`)
            emitIR(`  ret i32 ${trR}`)
        } else if (retLLType == "double" && declRet == "i32") {
            const fpR = nextReg()
            emitIR(`  ${fpR} = fptosi double ${val} to i32`)
            emitIR(`  ret i32 ${fpR}`)
        } else if (retLLType == "i32" && declRet == "double") {
            const siR = nextReg()
            emitIR(`  ${siR} = sitofp i32 ${val} to double`)
            emitIR(`  ret double ${siR}`)
        } else {
            emitIR(`  ret ${declRet} ${val}`)
        }
    }
    terminated = 1
}

function genIf(id: int) {
    const condId = nGetI1(id)
    const thenId = nGetI2(id)
    const elseId = nGetI3(id)

    const condVal = genExpr(condId)
    const thenLabel = nextLabel("if.then")
    const elseLabel = nextLabel("if.else")
    const mergeLabel = nextLabel("if.merge")

    // Convert condition to i1 if needed
    const r = nextReg()
    emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)

    if (elseId > 0) {
        emitIR(`  br i1 ${r}, label %${thenLabel}, label %${elseLabel}`)
    } else {
        emitIR(`  br i1 ${r}, label %${thenLabel}, label %${mergeLabel}`)
    }

    emitIR(`${thenLabel}:`)
    terminated = 0
    genBlock(thenId)
    if (terminated == 0) {
        emitIR(`  br label %${mergeLabel}`)
    }

    if (elseId > 0) {
        emitIR(`${elseLabel}:`)
        terminated = 0
        genBlock(elseId)
        if (terminated == 0) {
            emitIR(`  br label %${mergeLabel}`)
        }
    }

    terminated = 0
    emitIR(`${mergeLabel}:`)
}

function genFor(id: int) {
    const initId = nGetI1(id)
    const condId = nGetI2(id)
    const updateId = nGetI3(id)
    const bodyId = nGetI4(id)

    const condLabel = nextLabel("for.cond")
    const bodyLabel = nextLabel("for.body")
    const updateLabel = nextLabel("for.update")
    const afterLabel = nextLabel("for.after")

    const savedBreak = breakLabel
    const savedContinue = continueLabel
    breakLabel = afterLabel
    continueLabel = updateLabel

    genStmt(initId)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = nextReg()
    emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    genBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${updateLabel}`) }

    emitIR(`${updateLabel}:`)
    terminated = 0
    genStmt(updateId)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak
    continueLabel = savedContinue
}

function genForIn(id: int) {
    const itemName = nGetS1(id)
    const iterableId = nGetI1(id)
    const bodyId = nGetI2(id)

    const arr = genExpr(iterableId)
    const lenReg = nextReg()
    emitIR(`  ${lenReg} = call i32 @ss_arrayLen(ptr ${arr})`)

    // Index variable
    const idxAlloca = nextReg()
    emitIR(`  ${idxAlloca} = alloca i32, align 4`)
    emitIR(`  store i32 0, ptr ${idxAlloca}, align 4`)

    // Item variable
    const itemLLName = allocVarName(itemName)
    emitIR(`  %${itemLLName} = alloca i64, align 8`)
    setVarType(itemName, "i64")

    const condLabel = nextLabel("forin.cond")
    const bodyLabel = nextLabel("forin.body")
    const afterLabel = nextLabel("forin.after")

    const savedBreak2 = breakLabel
    const savedContinue2 = continueLabel
    const updateLabel2 = nextLabel("forin.update")
    breakLabel = afterLabel
    continueLabel = updateLabel2

    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const curIdx = nextReg()
    emitIR(`  ${curIdx} = load i32, ptr ${idxAlloca}, align 4`)
    const cmp = nextReg()
    emitIR(`  ${cmp} = icmp slt i32 ${curIdx}, ${lenReg}`)
    emitIR(`  br i1 ${cmp}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    const elemVal = nextReg()
    emitIR(`  ${elemVal} = call i64 @ss_arrayGet(ptr ${arr}, i32 ${curIdx})`)
    emitIR(`  store i64 ${elemVal}, ptr %${itemLLName}, align 8`)

    genBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${updateLabel2}`) }

    emitIR(`${updateLabel2}:`)
    terminated = 0
    const nextIdx = nextReg()
    emitIR(`  ${nextIdx} = load i32, ptr ${idxAlloca}, align 4`)
    const incIdx = nextReg()
    emitIR(`  ${incIdx} = add i32 ${nextIdx}, 1`)
    emitIR(`  store i32 ${incIdx}, ptr ${idxAlloca}, align 4`)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak2
    continueLabel = savedContinue2
}

function genWhile(id: int) {
    const condId = nGetI1(id)
    const bodyId = nGetI2(id)

    const condLabel = nextLabel("while.cond")
    const bodyLabel = nextLabel("while.body")
    const afterLabel = nextLabel("while.after")

    const savedBreak3 = breakLabel
    const savedContinue3 = continueLabel
    breakLabel = afterLabel
    continueLabel = condLabel

    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = nextReg()
    emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    genBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${condLabel}`) }

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak3
    continueLabel = savedContinue3
}

function genDoWhile(id: int) {
    const bodyId = nGetI1(id)
    const condId = nGetI2(id)
    const bodyLabel = nextLabel("dowhile.body")
    const condLabel = nextLabel("dowhile.cond")
    const afterLabel = nextLabel("dowhile.after")
    const savedBreak = breakLabel
    const savedContinue = continueLabel
    breakLabel = afterLabel
    continueLabel = condLabel
    emitIR(`  br label %${bodyLabel}`)
    emitIR(`${bodyLabel}:`)
    terminated = 0
    genBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${condLabel}`) }
    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = nextReg()
    emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)
    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak
    continueLabel = savedContinue
}

function genSwitch(id: int) {
    const subjectId = nGetI1(id)
    const defaultId = nGetI2(id)
    const caseList = nGetList(id)
    const subjectVal = genExpr(subjectId)
    const subjectType = inferType(subjectId)
    const afterLabel = nextLabel("switch.end")

    if (caseList != "") {
        const cases = caseList.split(",")
        for (c in cases) {
            const caseId = parseInt(c)
            if (caseId <= 0) { continue }
            const patId = nGetI1(caseId)
            const bodyId = nGetI2(caseId)
            const patType = nGetS1(patId)
            const patVal = nGetS2(patId)
            const thenLabel = nextLabel("switch.case")
            const nextLabel2 = nextLabel("switch.next")
            // Compare subject with pattern
            let cmpResult = ""
            if (patType == "STRING" || subjectType == "string") {
                const patStr = addStringConst(patVal)
                const cmp = nextReg()
                emitIR(`  ${cmp} = call i32 @ss_string_eq(ptr ${subjectVal}, ptr ${patStr})`)
                const br = nextReg()
                emitIR(`  ${br} = icmp ne i32 ${cmp}, 0`)
                cmpResult = br
            } else {
                const cmp = nextReg()
                emitIR(`  ${cmp} = icmp eq i32 ${subjectVal}, ${patVal}`)
                cmpResult = cmp
            }
            emitIR(`  br i1 ${cmpResult}, label %${thenLabel}, label %${nextLabel2}`)
            emitIR(`${thenLabel}:`)
            terminated = 0
            genBlock(bodyId)
            if (terminated == 0) { emitIR(`  br label %${afterLabel}`) }
            emitIR(`${nextLabel2}:`)
        }
    }
    // Default case
    if (defaultId > 0) {
        terminated = 0
        genBlock(defaultId)
    }
    if (terminated == 0) { emitIR(`  br label %${afterLabel}`) }
    emitIR(`${afterLabel}:`)
    terminated = 0
}

