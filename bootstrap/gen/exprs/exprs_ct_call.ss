// gen/exprs_ct_call.ss — Comptime 函数调用分发:intrinsics (println/emit/getTypeInfo/...)
// + user-defined comptime 函数调用(参数绑定 + scope 切换 + body 执行 + return 捕获)。

// D171 Phase 1:把 callee 名解析到绑定的 fn-kind ctVar 值所指向的 ARROW_FUNC astId
// (闭包/arrow 在 comptime 可调用)。只读现有 ctVars / fn-value(D093 §差距 #3 `fn|${id}` 入
// InternPool),不新开 ct* 注册表(D171 §拒绝准则)。作用域解析镜像 evalIdent(eval/ident.ss):
// scope 链(由内向外)→ currentFunc → 全局 `:name`,与 arrow 绑定点 gen_decls.ss:530 同 key 协议
// (外层变量捕获沿同一链解析)。返 -1 = 该名未绑定 fn-kind value。
function ctResolveFnNodeId(name: string): int {
    let ctFnRaw = -1
    if (ctScopeStack.length() > 0) {
        let csi = ctScopeStack.length() - 1
        while (csi >= 0 && ctFnRaw == -1) {
            const csk = `${ctScopeStack[csi]}:${name}`
            if (ctVars.has(csk) == 1) { ctFnRaw = parseInt(ctVars.getString(csk)) }
            csi = csi - 1
        }
    }
    if (ctFnRaw == -1) {
        const cck = `${currentFunc}:${name}`
        if (ctVars.has(cck) == 1 && ctInvalidated.has(cck) == 0) { ctFnRaw = parseInt(ctVars.getString(cck)) }
    }
    if (ctFnRaw == -1) {
        const cgk = `:${name}`
        if (ctVars.has(cgk) == 1) { ctFnRaw = parseInt(ctVars.getString(cgk)) }
    }
    if (ctFnRaw == -1 || isCt(ctFnRaw) == 0) { return -1 }
    const ctFnTv = payload(ctFnRaw)
    if (interpType(ctFnTv) != "fn") { return -1 }
    return interpAsInt(ctFnTv)  // fn-value 的 tvI1 = ARROW_FUNC astId(interp_obj.ss:106)
}

function ctCallDispatch(id: int, name: string, ctArgVals: Array<string>, ctNamedArgs: Map, ctHasNamed: int): int {
    // ── Intrinsics ──
    if (name == "println") {
        if (ctArgVals.length() > 0) { println(interpToStr(parseInt(ctArgVals[0]))) }
        else { println("") }
        return ctVal(interpNewNull())
    }
    if (name == "print") {
        if (ctArgVals.length() > 0) { print(interpToStr(parseInt(ctArgVals[0]))) }
        return ctVal(interpNewNull())
    }
    if (name == "parseInt") {
        if (ctArgVals.length() > 0) { return ctVal(interpNewInt(parseInt(interpAsStr(parseInt(ctArgVals[0]))))) }
        return ctVal(interpNewInt(0))
    }
    if (name == "parseDouble") {
        if (ctArgVals.length() > 0) { return ctVal(interpNewDouble(parseDouble(interpAsStr(parseInt(ctArgVals[0]))))) }
        return ctVal(interpNewDouble(0.0))
    }
    if (name == "toString") {
        if (ctArgVals.length() > 0) { return ctVal(interpNewString(interpToStr(parseInt(ctArgVals[0])))) }
        return ctVal(interpNewString(""))
    }
    if (name == "emit") {
        if (ctArgVals.length() > 0) { comptimeIR = `${comptimeIR}${interpAsStr(parseInt(ctArgVals[0]))}` }
        return ctVal(interpNewNull())
    }
    if (name == "registerFunction") {
        if (ctArgVals.length() >= 1) {
            const rfName = interpAsStr(parseInt(ctArgVals[0]))
            const rfRet = ctArgVals.length() > 1 ? interpAsStr(parseInt(ctArgVals[1])) : "void"
            const rfPc = ctArgVals.length() > 2 ? interpAsInt(parseInt(ctArgVals[2])) : 0
            funcRetTypes.set(rfName, rfRet)
            funcParamCount.set(rfName, `${rfPc}`)
        }
        return ctVal(interpNewNull())
    }
    if (name == "getAnnotatedClasses") {
        if (ctArgVals.length() >= 1) {
            const gacName = interpAsStr(parseInt(ctArgVals[0]))
            const gacResult = interpNewArray("")
            let gacSeen = new Map()
            let gacI = 0
            while (gacI < annClassAnnNames.length()) {
                if (annClassAnnNames[gacI] == gacName) {
                    const gacClassId = parseInt(annClassNodeIds[gacI])
                    const gacCn = nGetS1(gacClassId)
                    if (gacSeen.has(gacCn) == 0) {
                        interpArrayPush(gacResult, interpNewString(gacCn))
                        gacSeen.set(gacCn, "1")
                    }
                }
                gacI = gacI + 1
            }
            return ctVal(gacResult)
        }
        return ctVal(interpNewArray(""))
    }
    if (name == "addStringConst") {
        if (ctArgVals.length() >= 1) {
            return ctVal(interpNewString(addStringConst(interpAsStr(parseInt(ctArgVals[0])))))
        }
        return ctVal(interpNewString(""))
    }
    if (name == "getTypeInfo") {
        if (ctArgVals.length() >= 1) {
            return ctVal(interpBuildTypeInfo(interpAsStr(parseInt(ctArgVals[0]))))
        }
        return ctVal(interpNewNull())
    }
    if (name == "compileError") {
        const ceMsg = ctArgVals.length() > 0 ? interpAsStr(parseInt(ctArgVals[0])) : "compile error"
        println(`error: ${ceMsg}`)
        println("  --> comptime block")
        exit(1)
        return ctVal(interpNewNull())
    }
    if (name == "comptimeAssert") {
        if (ctArgVals.length() >= 1) {
            if (interpTruthy(parseInt(ctArgVals[0])) == 0) {
                const caMsg = ctArgVals.length() > 1 ? interpAsStr(parseInt(ctArgVals[1])) : "comptime assertion failed"
                println(`error: ${caMsg}`)
                println("  --> comptime block")
                exit(1)
            }
        }
        return ctVal(interpNewNull())
    }
    if (name == "getenv") {
        if (ctArgVals.length() >= 1) { return ctVal(interpNewString(getenv(interpAsStr(parseInt(ctArgVals[0]))))) }
        return ctVal(interpNewString(""))
    }
    if (name == "readFile") {
        if (ctArgVals.length() >= 1) { return ctVal(interpNewString(readFile(interpAsStr(parseInt(ctArgVals[0]))))) }
        return ctVal(interpNewString(""))
    }
    if (name == "writeFile") {
        if (ctArgVals.length() >= 2) {
            writeFile(interpAsStr(parseInt(ctArgVals[0])), interpAsStr(parseInt(ctArgVals[1])))
        }
        return ctVal(interpNewNull())
    }
    if (name == "fileExists") {
        if (ctArgVals.length() >= 1) { return ctVal(interpNewInt(fileExists(interpAsStr(parseInt(ctArgVals[0]))))) }
        return ctVal(interpNewInt(0))
    }
    if (name == "system") {
        if (ctArgVals.length() >= 1) { return ctVal(interpNewInt(system(interpAsStr(parseInt(ctArgVals[0]))))) }
        return ctVal(interpNewInt(-1))
    }
    if (name == "shellOutput") {
        if (ctArgVals.length() >= 1) {
            const soCmd = interpAsStr(parseInt(ctArgVals[0]))
            // I027: 经 shell()(popen 直捕子进程 stdout)取命令输出,不落任何 /tmp 中转文件 ——
            // 无中转路径即无并发编译进程的 race。2>/dev/null 保留原 shellOutput 丢弃 stderr 的语义。
            return ctVal(interpNewString(shell(`${soCmd} 2>/dev/null`)))
        }
        return ctVal(interpNewString(""))
    }
    if (name == "classNames") {
        const cnList = classFields.keys()
        const cnResult = interpNewArray("")
        for (cn in cnList) {
            if (cn == "" || cn == "Map") { continue }
            interpArrayPush(cnResult, interpNewString(cn))
        }
        return ctVal(cnResult)
    }
    if (name == "enumNames") {
        const enResult = interpNewArray("")
        if (enumReady == 1) {
            const enList = enumDeclNodes.keys()
            for (en in enList) {
                if (en == "") { continue }
                interpArrayPush(enResult, interpNewString(en))
            }
        }
        return ctVal(enResult)
    }
    if (name == "hasField") {
        if (ctArgVals.length() >= 2) {
            const hfCls = interpAsStr(parseInt(ctArgVals[0]))
            const hfFld = interpAsStr(parseInt(ctArgVals[1]))
            return ctVal(interpNewInt(classFieldTypes.has(`${hfCls}.${hfFld}`) == 1 ? 1 : 0))
        }
        return ctVal(interpNewInt(0))
    }
    if (name == "hasMethod") {
        if (ctArgVals.length() >= 2) {
            const hmCls = interpAsStr(parseInt(ctArgVals[0]))
            const hmMth = interpAsStr(parseInt(ctArgVals[1]))
            const hmMethods = classMethods.has(hmCls) == 1 ? classMethods.getString(hmCls) : ""
            return ctVal(interpNewInt(`,${hmMethods},`.indexOf(`,${hmMth},`) >= 0 ? 1 : 0))
        }
        return ctVal(interpNewInt(0))
    }
    if (name == "fieldCount") {
        if (ctArgVals.length() >= 1) {
            const fcCls = interpAsStr(parseInt(ctArgVals[0]))
            if (classFields.has(fcCls) == 0) { return ctVal(interpNewInt(0)) }
            const fcStr = classFields.getString(fcCls)
            if (fcStr == "") { return ctVal(interpNewInt(0)) }
            return ctVal(interpNewInt(fcStr.split(",").length()))
        }
        return ctVal(interpNewInt(0))
    }
    if (name == "fieldNames") {
        if (ctArgVals.length() >= 1) {
            const fnCls = interpAsStr(parseInt(ctArgVals[0]))
            if (classFields.has(fnCls) == 0) { return ctVal(interpNewString("")) }
            return ctVal(interpNewString(classFields.getString(fnCls)))
        }
        return ctVal(interpNewString(""))
    }
    if (name == "hasInterface") {
        if (ctArgVals.length() >= 2) {
            const imCls = interpAsStr(parseInt(ctArgVals[0]))
            const imIface = interpAsStr(parseInt(ctArgVals[1]))
            if (ifaceImplementors.has(imIface) == 0) { return ctVal(interpNewInt(0)) }
            return ctVal(interpNewInt(`,${ifaceImplementors.getString(imIface)},`.indexOf(`,${imCls},`) >= 0 ? 1 : 0))
        }
        return ctVal(interpNewInt(0))
    }
    if (name == "isSubclassOf") {
        if (ctArgVals.length() >= 2) {
            const scChild = interpAsStr(parseInt(ctArgVals[0]))
            const scParent = interpAsStr(parseInt(ctArgVals[1]))
            let scCls = scChild
            while (classParents.has(scCls) == 1) {
                scCls = classParents.getString(scCls)
                if (scCls == scParent) { return ctVal(interpNewInt(1)) }
            }
        }
        return ctVal(interpNewInt(0))
    }

    // ── User-defined function call OR comptime closure/arrow value (D171 Phase 1) ──
    // callee 解析到一个 func-node astId(布局 nGetList=params / nGetI1=body,FUNC_DECL 与
    // ARROW_FUNC 同布局):(a) 顶层注册函数 ctFuncNodes;(b) ctVars 作用域链绑定的 fn-kind value
    // (arrow/闭包,走 D093 统一 evalExpr 产出的 fn-value,只消费不另立 ct* 注册表 — D171 §拒绝准则)。
    let ctFuncId = -1
    if (ctFuncNodes.has(name) == 1) {
        ctFuncId = parseInt(ctFuncNodes.getString(name))
    } else {
        ctFuncId = ctResolveFnNodeId(name)
    }
    if (ctFuncId > 0) {
        const ctParamList = nGetList(ctFuncId)
        const ctBodyId = nGetI1(ctFuncId)

        // Save state
        const savedFunc = currentFunc
        const savedBreak = interpBreakFlag
        const savedContinue = interpContinueFlag
        const savedTerm = terminated
        interpBreakFlag = 0
        interpContinueFlag = 0
        terminated = 0

        // Push new scope
        ctCallCounter = ctCallCounter + 1
        currentFunc = `__ct_${name}_${ctCallCounter}`
        ctScopeStack = ctScopeStack.push(currentFunc)

        // Bind parameters (store tagged ct values in ctVars for consistency with VAR_DECL)
        if (ctParamList != "") {
            const ctParams = ctParamList.split(",")
            let ctPosIdx = 0
            let ctPi = 0
            while (ctPi < ctParams.length()) {
                const ctPid = parseInt(ctParams[ctPi])
                const ctPname = nGetS1(ctPid)
                if (ctHasNamed == 1 && ctNamedArgs.has(ctPname) == 1) {
                    ctVars.set(`${currentFunc}:${ctPname}`, `${ctVal(parseInt(ctNamedArgs.getString(ctPname)))}`)
                } else if (ctPosIdx < ctArgVals.length()) {
                    ctVars.set(`${currentFunc}:${ctPname}`, `${ctVal(parseInt(ctArgVals[ctPosIdx]))}`)
                    ctPosIdx = ctPosIdx + 1
                } else {
                    const ctDefId = nGetI1(ctPid)
                    if (ctDefId > 0) {
                        const ctDefVal = genVal(ctDefId)
                        ctVars.set(`${currentFunc}:${ctPname}`, `${isCt(ctDefVal) == 1 ? ctDefVal : ctVal(interpNewNull())}`)
                    } else {
                        ctVars.set(`${currentFunc}:${ctPname}`, `${ctVal(interpNewNull())}`)
                    }
                }
                ctPi = ctPi + 1
            }
        }

        // Execute body
        if (ctBodyId > 0) { genBlock(ctBodyId) }

        // Capture return value
        let ctResult = interpNewNull()
        if (interpReturnFlag == 1) {
            ctResult = interpReturnVal
            interpReturnFlag = 0
            interpReturnVal = 0
        }

        ctPopScope()
        currentFunc = savedFunc
        interpBreakFlag = savedBreak
        interpContinueFlag = savedContinue
        terminated = savedTerm

        return ctVal(ctResult)
    }

    // 真未命中(非 intrinsic / 顶层函数 / 绑定 fn-value)— D088 §Phase 8 不变量 + D171 Phase 1:
    // 静默返 null(解码为 0)是误编译,升 loud comptimeError 不再 swallow。
    return comptimeError(`unknown function: ${name}`, id)
}
