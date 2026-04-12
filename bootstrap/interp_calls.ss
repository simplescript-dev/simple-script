// interp_calls.ss — Function/method call handling for the AST interpreter
//
// Handles interpCall (user + builtin functions), interpNewExpr (class instantiation),
// interpMemberAccess, interpMethodCall, interpCallValue (higher-order).
// Forward-references interpEval from interp_eval.ss, interpExec from interp_exec.ss,
// interpBuildTypeInfo from interp_reflect.ss, and value/scope helpers from interp.ss.

// ── Helpers ───────────────────────────────────────────────────

function interpComptimeAbort(msg: string) {
    println(`error: ${msg}`)
    println("  --> comptime block")
    exit(1)
}

// ── Function Calls ────────────────────────────────────────────

function interpCall(nodeId: int): int {
    const name = nGetS1(nodeId)
    const argList = nGetList(nodeId)

    // Built-in: println (allowed for comptime debugging)
    if (name == "println") {
        if (argList != "") {
            const argIds = argList.split(",")
            println(interpToStr(interpEval(parseInt(argIds[0]))))
        } else {
            println("")
        }
        return interpNewNull()
    }
    // Built-in: parseInt, parseDouble, toString
    if (name == "parseInt") {
        if (argList != "") {
            const val = interpEval(parseInt(argList.split(",")[0]))
            return interpNewInt(parseInt(interpAsStr(val)))
        }
        return interpNewInt(0)
    }
    if (name == "parseDouble") {
        if (argList != "") {
            const val = interpEval(parseInt(argList.split(",")[0]))
            return interpNewDouble(parseDouble(interpAsStr(val)))
        }
        return interpNewDouble(0.0)
    }
    if (name == "toString") {
        if (argList != "") {
            const val = interpEval(parseInt(argList.split(",")[0]))
            return interpNewString(interpToStr(val))
        }
        return interpNewString("")
    }
    // Built-in: emit(irString) — append LLVM IR to comptime output (D087 Phase 3b)
    if (name == "emit") {
        if (argList != "") {
            const val = interpEval(parseInt(argList.split(",")[0]))
            comptimeIR = `${comptimeIR}${interpAsStr(val)}`
        }
        return interpNewNull()
    }
    // Built-in: registerFunction(name, retType, paramCount) — register in compiler tables (D087 Phase 3b)
    if (name == "registerFunction") {
        if (argList == "") {
            println("[comptime] registerFunction requires at least 1 argument: name")
            return interpNewNull()
        }
        const rfArgs = argList.split(",")
        const rfName = interpAsStr(interpEval(parseInt(rfArgs[0])))
        const rfRetType = rfArgs.length() > 1 ? interpAsStr(interpEval(parseInt(rfArgs[1]))) : "void"
        const rfParamCount = rfArgs.length() > 2 ? interpAsInt(interpEval(parseInt(rfArgs[2]))) : 0
        funcRetTypes.set(rfName, rfRetType)
        funcParamCount.set(rfName, `${rfParamCount}`)
        return interpNewNull()
    }
    // Built-in: getAnnotatedClasses(annName) — return array of class names with annotation (D087 Phase 4a)
    if (name == "getAnnotatedClasses") {
        if (argList == "") {
            println("[comptime] getAnnotatedClasses requires 1 argument: annName")
            return interpNewArray("")
        }
        const gacName = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        const gacResult = interpNewArray("")
        let gacSeen = new Map()
        let gacI = 0
        while (gacI < annClassAnnNames.length()) {
            if (annClassAnnNames[gacI] == gacName) {
                const gacClassId = parseInt(annClassNodeIds[gacI])
                const gacClassName = nGetS1(gacClassId)
                if (gacSeen.has(gacClassName) == 0) {
                    interpArrayPush(gacResult, interpNewString(gacClassName))
                    gacSeen.set(gacClassName, "1")
                }
            }
            gacI = gacI + 1
        }
        return gacResult
    }
    // Built-in: addStringConst(str) — calls compiler's addStringConst, returns IR ref (D087 Phase 4b)
    if (name == "addStringConst") {
        if (argList == "") {
            println("[comptime] addStringConst requires 1 argument: str")
            return interpNewString("")
        }
        const ascVal = interpEval(parseInt(argList.split(",")[0]))
        const ascRef = addStringConst(interpAsStr(ascVal))
        return interpNewString(ascRef)
    }
    // Built-in: getTypeInfo(className) — like @typeInfo but takes a string arg (D087 Phase 4a)
    if (name == "getTypeInfo") {
        if (argList == "") {
            println("[comptime] getTypeInfo requires 1 argument: className")
            return interpNewNull()
        }
        const gtiName = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        return interpBuildTypeInfo(gtiName)
    }
    // Built-in: compileError(msg) — abort compilation with error message
    if (name == "compileError") {
        const ceMsg = argList != "" ? interpAsStr(interpEval(parseInt(argList.split(",")[0]))) : "compile error"
        interpComptimeAbort(ceMsg)
        return interpNewNull()
    }
    // Built-in: comptimeAssert(cond, msg) — abort compilation if condition is false
    if (name == "comptimeAssert") {
        if (argList == "") { interpComptimeAbort("comptimeAssert requires at least 1 argument") }
        const caArgs = argList.split(",")
        const caCond = interpEval(parseInt(caArgs[0]))
        if (interpTruthy(caCond) == 0) {
            const caMsg = caArgs.length() > 1 ? interpAsStr(interpEval(parseInt(caArgs[1]))) : "comptime assertion failed"
            interpComptimeAbort(caMsg)
        }
        return interpNewNull()
    }
    // Built-in: getenv(name) — read environment variable at compile time
    if (name == "getenv") {
        if (argList == "") { return interpNewString("") }
        const geName = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        return interpNewString(getenv(geName))
    }
    // Built-in: readFile(path) — read file contents at compile time
    if (name == "readFile") {
        if (argList == "") { return interpNewString("") }
        const rfPath = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        return interpNewString(readFile(rfPath))
    }
    // Built-in: writeFile(path, content) — write file at compile time
    if (name == "writeFile") {
        if (argList == "") { return interpNewNull() }
        const wfArgs = argList.split(",")
        if (wfArgs.length() < 2) { return interpNewNull() }
        const wfPath = interpAsStr(interpEval(parseInt(wfArgs[0])))
        const wfContent = interpAsStr(interpEval(parseInt(wfArgs[1])))
        writeFile(wfPath, wfContent)
        return interpNewNull()
    }
    // Built-in: fileExists(path) — check file existence at compile time
    if (name == "fileExists") {
        if (argList == "") { return interpNewInt(0) }
        const fePath = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        return interpNewInt(fileExists(fePath))
    }
    // Built-in: system(cmd) — execute shell command at compile time, return exit code
    if (name == "system") {
        if (argList == "") { return interpNewInt(-1) }
        const sysCmd = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        return interpNewInt(system(sysCmd))
    }
    // Built-in: shellOutput(cmd) — execute shell command, return stdout as string
    if (name == "shellOutput") {
        if (argList == "") { return interpNewString("") }
        const soCmd = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        const soTmp = "/tmp/ss_comptime_exec.tmp"
        system(`${soCmd} > ${soTmp} 2>/dev/null`)
        const soOut = readFile(soTmp)
        return interpNewString(soOut)
    }
    // Built-in: classNames() — return array of all registered class names
    if (name == "classNames") {
        const cnList = classFields.keys()
        const cnResult = interpNewArray("")
        for (cn in cnList) {
            if (cn == "" || cn == "Map") { continue }
            interpArrayPush(cnResult, interpNewString(cn))
        }
        return cnResult
    }
    // Built-in: enumNames() — return array of all registered enum names
    if (name == "enumNames") {
        const enList = enumDeclNodes.keys()
        const enResult = interpNewArray("")
        for (en in enList) {
            if (en == "") { continue }
            interpArrayPush(enResult, interpNewString(en))
        }
        return enResult
    }
    // Built-in: hasField(className, fieldName) — check if class has field, returns 0/1
    if (name == "hasField") {
        if (argList == "") { return interpNewInt(0) }
        const hfArgs = argList.split(",")
        if (hfArgs.length() < 2) { return interpNewInt(0) }
        const hfClass = interpAsStr(interpEval(parseInt(hfArgs[0])))
        const hfField = interpAsStr(interpEval(parseInt(hfArgs[1])))
        return interpNewInt(classFieldTypes.has(`${hfClass}.${hfField}`) == 1 ? 1 : 0)
    }
    // Built-in: hasMethod(className, methodName) — check if class has method, returns 0/1
    if (name == "hasMethod") {
        if (argList == "") { return interpNewInt(0) }
        const hmArgs = argList.split(",")
        if (hmArgs.length() < 2) { return interpNewInt(0) }
        const hmClass = interpAsStr(interpEval(parseInt(hmArgs[0])))
        const hmMethod = interpAsStr(interpEval(parseInt(hmArgs[1])))
        const hmMethods = classMethods.has(hmClass) == 1 ? classMethods.getString(hmClass) : ""
        const hmSearch = `,${hmMethods},`
        return interpNewInt(hmSearch.indexOf(`,${hmMethod},`) >= 0 ? 1 : 0)
    }
    // Built-in: fieldCount(className) — return number of fields in a class
    if (name == "fieldCount") {
        if (argList == "") { return interpNewInt(0) }
        const fcClass = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        if (classFields.has(fcClass) == 0) { return interpNewInt(0) }
        const fcStr = classFields.getString(fcClass)
        if (fcStr == "") { return interpNewInt(0) }
        return interpNewInt(fcStr.split(",").length())
    }
    // Built-in: fieldNames(className) — return comma-separated field names string
    if (name == "fieldNames") {
        if (argList == "") { return interpNewString("") }
        const fnClass = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        if (classFields.has(fnClass) == 0) { return interpNewString("") }
        return interpNewString(classFields.getString(fnClass))
    }
    // Built-in: hasInterface(className, ifaceName) — check if class implements interface, returns 0/1
    if (name == "hasInterface") {
        if (argList == "") { return interpNewInt(0) }
        const imArgs = argList.split(",")
        if (imArgs.length() < 2) { return interpNewInt(0) }
        const imClass = interpAsStr(interpEval(parseInt(imArgs[0])))
        const imIface = interpAsStr(interpEval(parseInt(imArgs[1])))
        if (ifaceImplementors.has(imIface) == 0) { return interpNewInt(0) }
        const imImpls = `,${ifaceImplementors.getString(imIface)},`
        return interpNewInt(imImpls.indexOf(`,${imClass},`) >= 0 ? 1 : 0)
    }
    // Built-in: isSubclassOf(child, parent) — check inheritance chain, returns 0/1
    if (name == "isSubclassOf") {
        if (argList == "") { return interpNewInt(0) }
        const scArgs = argList.split(",")
        if (scArgs.length() < 2) { return interpNewInt(0) }
        const scChild = interpAsStr(interpEval(parseInt(scArgs[0])))
        const scParent = interpAsStr(interpEval(parseInt(scArgs[1])))
        if (scChild == "" || scParent == "") { return interpNewInt(0) }
        let scCls = scChild
        while (classParents.has(scCls) == 1) {
            scCls = classParents.getString(scCls)
            if (scCls == scParent) { return interpNewInt(1) }
        }
        return interpNewInt(0)
    }

    // Look up function value
    const fnVal = interpGetVar(name)
    if (interpType(fnVal) != "fn") {
        println(`[interp] not a function: ${name}`)
        return interpNewNull()
    }

    const funcNodeId = parseInt(interpAsStr(fnVal))
    const paramList = nGetList(funcNodeId)
    const bodyId = nGetI1(funcNodeId)

    // Evaluate all arguments before pushing scope
    let argVals: Array<string> = []
    let namedArgs = new Map()
    let hasNamed = 0
    if (argList != "") {
        const argIds = argList.split(",")
        let i = 0
        while (i < argIds.length()) {
            const argNodeId = parseInt(argIds[i])
            if (nGetKind(argNodeId) == "NAMED_ARG") {
                hasNamed = 1
                const argVal = interpEval(nGetI1(argNodeId))
                namedArgs.set(nGetS1(argNodeId), `${argVal}`)
            } else {
                const argVal = interpEval(argNodeId)
                argVals = argVals.push(`${argVal}`)
            }
            i = i + 1
        }
    }

    // Save and reset control flow flags (isolate function body)
    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    interpBreakFlag = 0
    interpContinueFlag = 0

    // Push scope and bind parameters
    interpPushScope()
    if (paramList != "") {
        const params = paramList.split(",")
        let posIdx = 0
        let pi = 0
        while (pi < params.length()) {
            const paramId = parseInt(params[pi])
            const pName = nGetS1(paramId)
            if (hasNamed == 1 && namedArgs.has(pName) == 1) {
                interpSetVar(pName, parseInt(namedArgs.getString(pName)))
            } else if (posIdx < argVals.length()) {
                interpSetVar(pName, parseInt(argVals[posIdx]))
                posIdx = posIdx + 1
            } else {
                // Default parameter value
                const defaultId = nGetI1(paramId)
                if (defaultId > 0) {
                    interpSetVar(pName, interpEval(defaultId))
                } else {
                    interpSetVar(pName, interpNewNull())
                }
            }
            pi = pi + 1
        }
    }

    // Execute function body
    if (bodyId > 0) { interpExec(bodyId) }

    // Capture return value and reset return flag
    let result = interpNewNull()
    if (interpReturnFlag == 1) {
        result = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }

    interpPopScope()

    // Restore caller's control flow flags
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue

    return result
}

// ── New Expression ────────────────────────────────────────────

function interpNewExpr(nodeId: int): int {
    const className = nGetS1(nodeId)
    if (className == "Map") { return interpNewMap() }
    if (interpClasses.has(className) != 1) {
        println(`[interp] unknown class: ${className}`)
        return interpNewNull()
    }
    const objId = interpNewVal("object", className)
    const allFields = interpCollectFields(className)
    let fieldNames: Array<string> = []
    if (allFields != "") {
        const fieldParts = allFields.split(",")
        let fi = 0
        while (fi < fieldParts.length()) {
            const fId = parseInt(fieldParts[fi])
            const fName = nGetS1(fId)
            fieldNames = fieldNames.push(fName)
            const defaultId = nGetI1(fId)
            if (defaultId > 0) {
                interpSetField(objId, fName, interpEval(defaultId))
            } else {
                interpSetField(objId, fName, interpNewNull())
            }
            fi = fi + 1
        }
    }
    const argList = nGetList(nodeId)
    if (argList != "") {
        const argIds = argList.split(",")
        let posIdx = 0
        let i = 0
        while (i < argIds.length()) {
            const argNodeId = parseInt(argIds[i])
            if (nGetKind(argNodeId) == "NAMED_ARG") {
                interpSetField(objId, nGetS1(argNodeId), interpEval(nGetI1(argNodeId)))
            } else {
                const argVal = interpEval(argNodeId)
                if (posIdx < fieldNames.length()) {
                    interpSetField(objId, fieldNames[posIdx], argVal)
                }
                posIdx = posIdx + 1
            }
            i = i + 1
        }
    }
    return objId
}

// ── Member Access ─────────────────────────────────────────────

function interpMemberAccess(nodeId: int): int {
    const objVal = interpEval(nGetI1(nodeId))
    const fieldName = nGetS1(nodeId)
    if (interpType(objVal) == "object") {
        return interpGetField(objVal, fieldName)
    }
    println(`[interp] no field '${fieldName}' on ${interpType(objVal)}`)
    return interpNewNull()
}

// ── Method Call ───────────────────────────────────────────────

function interpMethodCall(nodeId: int): int {
    const methodName = nGetS1(nodeId)
    const objVal = interpEval(nGetI1(nodeId))
    const objType = interpType(objVal)

    // Built-in type methods (string, array, map)
    if (objType == "string" || objType == "array" || objType == "map") {
        const bArgList = nGetList(nodeId)
        let bArgs: Array<string> = []
        if (bArgList != "") {
            const bArgIds = bArgList.split(",")
            let bi = 0
            while (bi < bArgIds.length()) {
                bArgs = bArgs.push(`${interpEval(parseInt(bArgIds[bi]))}`)
                bi = bi + 1
            }
        }
        return interpBuiltinMethod(objType, objVal, methodName, bArgs)
    }

    if (objType != "object") {
        println(`[interp] cannot call method '${methodName}' on ${objType}`)
        return interpNewNull()
    }
    const className = interpAsStr(objVal)
    const methodNode = interpFindMethod(className, methodName)
    if (methodNode == 0) {
        println(`[interp] no method '${methodName}' on class ${className}`)
        return interpNewNull()
    }
    const argList = nGetList(nodeId)
    let argVals: Array<string> = []
    let namedArgs = new Map()
    let hasNamed = 0
    if (argList != "") {
        const argIds = argList.split(",")
        let i = 0
        while (i < argIds.length()) {
            const argNodeId = parseInt(argIds[i])
            if (nGetKind(argNodeId) == "NAMED_ARG") {
                hasNamed = 1
                namedArgs.set(nGetS1(argNodeId), `${interpEval(nGetI1(argNodeId))}`)
            } else {
                argVals = argVals.push(`${interpEval(argNodeId)}`)
            }
            i = i + 1
        }
    }
    const savedThis = interpThisVal
    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    interpBreakFlag = 0
    interpContinueFlag = 0
    interpThisVal = objVal
    interpPushScope()
    const paramList = nGetList(methodNode)
    if (paramList != "") {
        const params = paramList.split(",")
        let posIdx = 0
        let pi = 0
        while (pi < params.length()) {
            const paramId = parseInt(params[pi])
            const pName = nGetS1(paramId)
            if (hasNamed == 1 && namedArgs.has(pName) == 1) {
                interpSetVar(pName, parseInt(namedArgs.getString(pName)))
            } else if (posIdx < argVals.length()) {
                interpSetVar(pName, parseInt(argVals[posIdx]))
                posIdx = posIdx + 1
            } else {
                const defaultId = nGetI1(paramId)
                if (defaultId > 0) {
                    interpSetVar(pName, interpEval(defaultId))
                } else {
                    interpSetVar(pName, interpNewNull())
                }
            }
            pi = pi + 1
        }
    }
    const bodyId = nGetI1(methodNode)
    if (bodyId > 0) { interpExec(bodyId) }
    let result = interpNewNull()
    if (interpReturnFlag == 1) {
        result = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }
    interpPopScope()
    interpThisVal = savedThis
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue
    return result
}

// ── Call Function Value (for higher-order methods) ────────────

function interpCallValue(fnValId: int, args: Array<string>): int {
    if (interpType(fnValId) != "fn") {
        println("[interp] interpCallValue: not a function")
        return interpNewNull()
    }
    const funcNodeId = parseInt(interpAsStr(fnValId))
    const paramList = nGetList(funcNodeId)
    const bodyId = nGetI1(funcNodeId)

    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    interpBreakFlag = 0
    interpContinueFlag = 0

    interpPushScope()
    if (paramList != "") {
        const params = paramList.split(",")
        let pi = 0
        while (pi < params.length() && pi < args.length()) {
            interpSetVar(nGetS1(parseInt(params[pi])), parseInt(args[pi]))
            pi = pi + 1
        }
    }

    if (bodyId > 0) { interpExec(bodyId) }

    let result = interpNewNull()
    if (interpReturnFlag == 1) {
        result = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }

    interpPopScope()
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue
    return result
}
