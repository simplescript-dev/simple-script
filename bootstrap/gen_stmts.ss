// Statement generation for bootstrap codegen
// ── Statement generation ──────────────────────────────────────

function genDestructureArray(id: int) {
    const names = nGetS1(id)
    const initId = nGetI1(id)
    const arrVal = genExpr(initId)
    const parts = names.split(",")
    let idx = 0
    for (n in parts) {
        const llName = allocVarName(n)
        emitIR(`  %${llName} = alloca i64, align 8`)
        const elemR = nextReg()
        emitIR(`  ${elemR} = call i64 @ss_arrayGet(ptr ${arrVal}, i32 ${idx})`)
        emitIR(`  store i64 ${elemR}, ptr %${llName}, align 8`)
        setVarType(n, "i64")
        idx = idx + 1
    }
}

function genTryCatch(id: int) {
    const tryBody = nGetI1(id)
    const catchBody = nGetI2(id)
    const errName = nGetS1(id)

    const tryLabel = nextLabel("try")
    const catchLabel = nextLabel("catch")
    const endLabel = nextLabel("try.end")

    // Push exception handler: increment depth, get jmpbuf slot
    const depthR = nextReg()
    emitIR(`  ${depthR} = load i32, ptr @ss_exc_depth`)
    const newDepth = nextReg()
    emitIR(`  ${newDepth} = add i32 ${depthR}, 1`)
    emitIR(`  store i32 ${newDepth}, ptr @ss_exc_depth`)
    const offset = nextReg()
    emitIR(`  ${offset} = mul i32 ${depthR}, 200`)
    const off64 = nextReg()
    emitIR(`  ${off64} = sext i32 ${offset} to i64`)
    const bufPtr = nextReg()
    emitIR(`  ${bufPtr} = getelementptr i8, ptr @ss_jmpbuf, i64 ${off64}`)

    // setjmp returns 0 normally, non-zero when longjmp is called
    const sjRet = nextReg()
    emitIR(`  ${sjRet} = call i32 @setjmp(ptr ${bufPtr})`)
    const isExc = nextReg()
    emitIR(`  ${isExc} = icmp ne i32 ${sjRet}, 0`)
    emitIR(`  br i1 ${isExc}, label %${catchLabel}, label %${tryLabel}`)

    // Try block
    emitIR(`${tryLabel}:`)
    const savedTerm = terminated
    terminated = 0
    genBlock(tryBody)
    if (terminated == 0) {
        // Pop handler and skip catch
        const d2 = nextReg()
        emitIR(`  ${d2} = load i32, ptr @ss_exc_depth`)
        const d3 = nextReg()
        emitIR(`  ${d3} = sub i32 ${d2}, 1`)
        emitIR(`  store i32 ${d3}, ptr @ss_exc_depth`)
        emitIR(`  br label %${endLabel}`)
    }

    // Catch block
    emitIR(`${catchLabel}:`)
    terminated = 0
    // Pop handler
    const d4 = nextReg()
    emitIR(`  ${d4} = load i32, ptr @ss_exc_depth`)
    const d5 = nextReg()
    emitIR(`  ${d5} = sub i32 ${d4}, 1`)
    emitIR(`  store i32 ${d5}, ptr @ss_exc_depth`)
    // Bind error variable
    const errLLName = allocVarName(errName)
    emitIR(`  %${errLLName} = alloca ptr, align 8`)
    const excMsg = nextReg()
    emitIR(`  ${excMsg} = load ptr, ptr @ss_exc_msg`)
    emitIR(`  store ptr ${excMsg}, ptr %${errLLName}, align 8`)
    setVarType(errName, "string")
    genBlock(catchBody)
    if (terminated == 0) {
        emitIR(`  br label %${endLabel}`)
    }

    emitIR(`${endLabel}:`)
    terminated = savedTerm
}

function registerEnum(id: int) {
    if (enumReady == 0) { enumValues = Map(); enumReady = 1 }
    const eName = nGetS1(id)
    const vl = nGetList(id)
    if (vl == "") { return }
    const parts = vl.split(",")
    for (p in parts) {
        const vid = parseInt(p)
        if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
            const vName = nGetS1(vid)
            const vVal = nGetI1(vid)
            enumValues.set(`${eName}.${vName}`, `${vVal}`)
        }
    }
}

function genStmt(id: int) {
    const kind = nGetKind(id)

    if (kind == "FUNC_DECL") {
        const fname = nGetS1(id)
        const fSig = paramSig(nGetList(id))
        // Use mangled key for duplicate detection (supports overloading)
        const genKey = fSig != "" ? `${fname}_${fSig}_generated` : `${fname}_generated`
        if (fname != "main" && funcRetTypes.has(genKey) == 1) { return }
        funcRetTypes.set(genKey, "1")
        genFuncDecl(id)
        return
    }
    if (kind == "VAR_DECL") {
        genVarDecl(id)
        return
    }
    if (kind == "DESTRUCTURE_ARRAY") {
        genDestructureArray(id)
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
        const r1 = nextReg(); emitIR(`  ${r1} = load i32, ptr ${pRef}, align 4`)
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
        const arrPtr = nextReg(); emitIR(`  ${arrPtr} = load ptr, ptr ${varRef(nGetS1(id))}, align 8`)
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
    if (kind == "ENUM_DECL") {
        registerEnum(id)
        return
    }
    if (kind == "TRY") {
        genTryCatch(id)
        return
    }
    if (kind == "THROW") {
        const msgVal = genExpr(nGetI1(id))
        emitIR(`  call void @ss_throw(ptr ${msgVal})`)
        emitIR("  unreachable")
        terminated = 1
        return
    }
    // IMPORT, INTERFACE_DECL — skip
}

function isOverloaded(fname: string): int {
    if (overloadReady == 0) { return 0 }
    if (overloadCount.has(fname) == 0) { return 0 }
    return parseInt(overloadCount.getString(fname)) > 1 ? 1 : 0
}

function genFuncDecl(id: int) {
    const name = nGetS1(id)
    // Use mangled name if function is overloaded
    let llName = name
    if (isOverloaded(name) == 1) {
        const fSig = paramSig(nGetList(id))
        if (fSig != "") { llName = `${name}_${fSig}` }
    }
    regCount = 0
    currentFunc = llName
    terminated = 0
    varAliases = Map()

    // For 'main', use C main signature
    if (name == "main") {
        emitIR("define i32 @main(i32 %0, ptr %1) {")
        emitIR("entry:")
        emitIR("  call void @ss_initArgs(i32 %0, ptr %1)")
        regCount = 2
        emitGlobalInits()
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
        emitIR(`define ${llRetType} @${llName}(${paramStr}) {`)
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
                    // Register class type for method dispatch
                    if (classFields.has(pType) == 1) {
                        setObjClass(pName, pType)
                    }
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
        } else if (ssTypeToLLVM(retType) == "ptr") {
            emitIR("  ret ptr null")
        } else {
            emitIR("  ret i32 0")
        }
    }
    emitIR("}")
    emitIR("")
    flushArrowDefs()
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

// Track global vars needing runtime init (new Map(), function calls, etc.)
let globalInitIds = ""

function genGlobalVar(id: int) {
    const name = nGetS1(id)
    if (globalAliases.has(name) == 1) { return }
    const initId = nGetI1(id)
    const ik = nGetKind(initId)
    let gType = "ptr"
    if (ik == "INT_LIT") {
        emitIR(`@${name} = global i32 ${nGetS1(initId)}, align 4`)
        gType = "int"
    } else if (ik == "DOUBLE_LIT") {
        emitIR(`@${name} = global double ${nGetS1(initId)}, align 8`)
        gType = "double"
    } else if (ik == "STRING_LIT") {
        emitIR(`@${name} = global ptr ${addStringConst(nGetS1(initId))}, align 8`)
        gType = "string"
    } else if (ik == "TRUE_LIT") {
        emitIR(`@${name} = global i32 1, align 4`)
        gType = "int"
    } else if (ik == "FALSE_LIT") {
        emitIR(`@${name} = global i32 0, align 4`)
        gType = "int"
    } else {
        // Non-literal init: declare null, queue runtime init
        emitIR(`@${name} = global ptr null, align 8`)
        if (globalInitIds == "") { globalInitIds = `${id}` }
        else { globalInitIds = `${globalInitIds},${id}` }
    }
    setVarType(name, gType)
    globalAliases.set(name, `@${name}`)
}

// Called at the start of main() to init global vars with runtime expressions
function emitGlobalInits() {
    if (globalInitIds != "") {
        const parts = globalInitIds.split(",")
        for (p in parts) {
            const gid = parseInt(p)
            if (gid > 0) {
                const gname = nGetS1(gid)
                const initId = nGetI1(gid)
                const val = genExpr(initId)
                emitIR(`  store ptr ${val}, ptr @${gname}, align 8`)
            }
        }
    }
    // Auto-register annotated routes (@GetMapping etc.)
    if (annotatedRoutes != "") {
        emitAnnotatedRoutes()
    }
}

function emitAnnotatedRoutes() {
    // For each @RestController class, create a singleton wrapper function per route
    // that passes null as this (controller methods shouldn't use this for state)
    let remaining = annotatedRoutes
    let wrapperIdx = 0
    while (remaining != "") {
        let entry = remaining
        const nlIdx = remaining.indexOf("\n")
        if (nlIdx >= 0) {
            entry = remaining.substring(0, nlIdx)
            remaining = remaining.substring(nlIdx + 1, remaining.length() - nlIdx - 1)
        } else {
            remaining = ""
        }
        const p1 = entry.indexOf(":")
        if (p1 < 0) { continue }
        const httpMethod = entry.substring(0, p1)
        const rest1 = entry.substring(p1 + 1, entry.length() - p1 - 1)
        const p2 = rest1.indexOf(":")
        const path = rest1.substring(0, p2)
        const rest2 = rest1.substring(p2 + 1, rest1.length() - p2 - 1)
        const p3 = rest2.indexOf(":")
        const className = rest2.substring(0, p3)
        const methodName = rest2.substring(p3 + 1, rest2.length() - p3 - 1)
        // Generate registerRoute call with function pointer
        const pathStr = addStringConst(path)
        const methodStr = addStringConst(httpMethod)
        // Create singleton instance stored in global
        const globalName = `@__ctrl_${className}`
        // Emit global declaration (only once per class)
        if (funcRetTypes.has(`__ctrl_${className}_init`) == 0) {
            funcRetTypes.set(`__ctrl_${className}_init`, "1")
            emitIR(`  ; init controller ${className}`)
        }
        const instR = nextReg()
        emitIR(`  ${instR} = call ptr @${className}_new()`)
        // Create wrapper function that loads instance from register
        // Use a global to pass the instance
        const wrapName = `__route_${wrapperIdx}`
        wrapperIdx = wrapperIdx + 1
        // Store instance in a global variable
        const gName = `__ctrl_inst_${wrapperIdx}`
        arrowDefs = `${arrowDefs}@${gName} = internal global ptr null\n`
        emitIR(`  store ptr ${instR}, ptr @${gName}`)
        arrowDefs = `${arrowDefs}define ptr @${wrapName}(ptr %req, ptr %resp) {\nentry:\n  %inst = load ptr, ptr @${gName}\n  %r = call ptr @${className}_${methodName}(ptr %inst, ptr %req, ptr %resp)\n  ret ptr %r\n}\n\n`
        const fnPtr = nextReg()
        emitIR(`  ${fnPtr} = ptrtoint ptr @${wrapName} to i64`)
        emitIR(`  call void @registerRoute(ptr ${methodStr}, ptr ${pathStr}, i64 ${fnPtr})`)
    }
}

function genVarDecl(id: int) {
    const name = nGetS1(id)
    const initId = nGetI1(id)
    const typeAnn = nGetS3(id)

    // Infer type from init expression
    const initType = inferType(initId)
    const llType = ssTypeToLLVM(initType)

    // Global vars: just store (alloca already done by genGlobalVar)
    if (currentFunc == "" && globalAliases.has(name) == 1) {
        const val = genExpr(initId)
        const gn = globalAliases.getString(name)
        emitIR(`  store ${llType} ${val}, ptr ${gn}, align 8`)
        return
    }
    const llName = allocVarName(name)
    emitIR(`  %${llName} = alloca ${llType}, align 8`)
    setVarType(name, initType)

    // Track generic type annotation (e.g., Array<string>)
    if (typeAnn.contains("<") == 1) {
        setVarType(name, typeAnn)
    }

    // Track object class for method dispatch
    if (nGetKind(initId) == "NEW_EXPR") {
        setObjClass(name, nGetS1(initId))
    }
    if (nGetKind(initId) == "CALL") {
        if (nGetS1(initId) == "Map") {
            setObjClass(name, "Map")
        } else {
            const callRet = funcRetTypes.getString(nGetS1(initId)) ?? ""
            if (callRet != "" && classFields.has(callRet) == 1) {
                setObjClass(name, callRet)
            }
        }
    }
    // Infer class from method call chain (e.g., createFoo().setBar())
    if (nGetKind(initId) == "METHOD_CALL") {
        const mRetType = inferType(initId)
        if (mRetType != "" && classFields.has(mRetType) == 1) {
            setObjClass(name, mRetType)
        }
    }

    let val = genExpr(initId)
    const valLLType = ssTypeToLLVM(inferType(initId))
    if (valLLType == "i64" && llType == "i32") {
        const trR = nextReg()
        emitIR(`  ${trR} = trunc i64 ${val} to i32`)
        val = trR
    }
    if (valLLType == "i64" && llType == "ptr") {
        const cvR = nextReg()
        emitIR(`  ${cvR} = inttoptr i64 ${val} to ptr`)
        val = cvR
    }
    emitIR(`  store ${llType} ${val}, ptr %${llName}, align 8`)
}

function genAssign(id: int) {
    const name = nGetS1(id)
    const op = nGetS2(id)
    const valId = nGetI1(id)

    const vType = getVarType(name)
    const llType = ssTypeToLLVM(vType)

    if (op == "ASSIGN") {
        let val = genExpr(valId)
        const valType = inferType(valId)
        const valLL = ssTypeToLLVM(valType)
        if (valLL == "i64" && llType == "i32") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${val} to i32`)
            val = trR
        }
        if (valLL == "i64" && llType == "ptr") {
            const cvR = nextReg()
            emitIR(`  ${cvR} = inttoptr i64 ${val} to ptr`)
            val = cvR
        }
        emitIR(`  store ${llType} ${val}, ptr ${varRef(name)}, align 8`)
    } else {
        // Compound: +=, -=, etc.
        const lnRef = varRef(name)
        const r1 = nextReg(); emitIR(`  ${r1} = load ${llType}, ptr ${lnRef}, align 8`)
        let r2 = genExpr(valId)
        // Trunc i64 to i32 if needed
        const r2Type = inferType(valId)
        if (r2Type == "i64" && vType != "i64") {
            const trR = nextReg(); emitIR(`  ${trR} = trunc i64 ${r2} to i32`)
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
            const trR = nextReg(); emitIR(`  ${trR} = trunc i64 ${val} to i32`)
            emitIR(`  ret i32 ${trR}`)
        } else if (retLLType == "i64" && declRet == "ptr") {
            const cvR = nextReg(); emitIR(`  ${cvR} = inttoptr i64 ${val} to ptr`)
            emitIR(`  ret ptr ${cvR}`)
        } else if (retLLType == "double" && declRet == "i32") {
            const fpR = nextReg(); emitIR(`  ${fpR} = fptosi double ${val} to i32`)
            emitIR(`  ret i32 ${fpR}`)
        } else if (retLLType == "i32" && declRet == "double") {
            const siR = nextReg(); emitIR(`  ${siR} = sitofp i32 ${val} to double`)
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
    const r = nextReg(); emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)

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
    const r = nextReg(); emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)
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
    const lenReg = nextReg(); emitIR(`  ${lenReg} = call i32 @ss_arrayLen(ptr ${arr})`)

    // Index variable
    const idxAlloca = nextReg(); emitIR(`  ${idxAlloca} = alloca i32, align 4`)
    emitIR(`  store i32 0, ptr ${idxAlloca}, align 4`)

    // Item variable — infer element type from iterable's type annotation
    let itemType = "i64"
    if (nGetKind(iterableId) == "IDENT") {
        const arrType = getVarType(nGetS1(iterableId))
        if (arrType.contains("<string>") == 1) { itemType = "string" }
        if (arrType.contains("<int>") == 1) { itemType = "int" }
        if (arrType.contains("<double>") == 1) { itemType = "double" }
    }
    const itemLLName = allocVarName(itemName)
    const itemLLType = ssTypeToLLVM(itemType)
    emitIR(`  %${itemLLName} = alloca ${itemLLType}, align 8`)
    setVarType(itemName, itemType)

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
    const curIdx = nextReg(); emitIR(`  ${curIdx} = load i32, ptr ${idxAlloca}, align 4`)
    const cmp = nextReg(); emitIR(`  ${cmp} = icmp slt i32 ${curIdx}, ${lenReg}`)
    emitIR(`  br i1 ${cmp}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    const elemVal = nextReg(); emitIR(`  ${elemVal} = call i64 @ss_arrayGet(ptr ${arr}, i32 ${curIdx})`)
    // Convert i64 element to item type
    if (itemType == "string") {
        const elemPtr = nextReg(); emitIR(`  ${elemPtr} = inttoptr i64 ${elemVal} to ptr`)
        emitIR(`  store ptr ${elemPtr}, ptr %${itemLLName}, align 8`)
    } else if (itemType == "int") {
        const elemI32 = nextReg(); emitIR(`  ${elemI32} = trunc i64 ${elemVal} to i32`)
        emitIR(`  store i32 ${elemI32}, ptr %${itemLLName}, align 8`)
    } else {
        emitIR(`  store i64 ${elemVal}, ptr %${itemLLName}, align 8`)
    }

    genBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${updateLabel2}`) }

    emitIR(`${updateLabel2}:`)
    terminated = 0
    const nextIdx = nextReg(); emitIR(`  ${nextIdx} = load i32, ptr ${idxAlloca}, align 4`)
    const incIdx = nextReg(); emitIR(`  ${incIdx} = add i32 ${nextIdx}, 1`)
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
    const r = nextReg(); emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)
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
    const r = nextReg(); emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)
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
                const cmp = nextReg(); emitIR(`  ${cmp} = call i32 @ss_string_eq(ptr ${subjectVal}, ptr ${patStr})`)
                const br = nextReg(); emitIR(`  ${br} = icmp ne i32 ${cmp}, 0`)
                cmpResult = br
            } else {
                const cmp = nextReg(); emitIR(`  ${cmp} = icmp eq i32 ${subjectVal}, ${patVal}`)
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

