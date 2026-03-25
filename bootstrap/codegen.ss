// SimpleScript Bootstrap Code Generator
// Walks the Map-based AST and produces LLVM IR text (.ll format).
// Uses SSA registers (%1, %2, ...) and named allocas for variables.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList } from "./parser"

// ── State ─────────────────────────────────────────────────────

let irBuf = ""
let strConsts = ""
let strCount = 0
let regCount = 0
let labelCount = 0
let varTypes = Map()
let varTypesReady = 0
let currentFunc = ""
let terminated = 0
let varCounter = 0
let varAliases = Map()
let varAliasReady = 0

function initVarAliases() {
    if (varAliasReady == 1) { return }
    varAliases = Map()
    varAliasReady = 1
}

function allocVarName(name: string): string {
    initVarAliases()
    varCounter = varCounter + 1
    const llName = name + "." + varCounter
    varAliases.set(name, llName)
    return llName
}

function llVarName(name: string): string {
    initVarAliases()
    if (varAliases.has(name) == 1) {
        return varAliases.getString(name)
    }
    return name
}
let funcRetTypes = Map()
let funcRetReady = 0
let classFields = Map()     // "ClassName" -> "field1,field2,..."
let classFieldTypes = Map() // "ClassName.field" -> "type"
let classMethods = Map()    // "ClassName" -> "method1,method2,..."
let objClasses = Map()      // "varName" -> "ClassName"
let currentClassName = ""
let breakLabel = ""
let continueLabel = ""

function initFuncRetTypes() {
    if (funcRetReady == 1) { return }
    funcRetTypes = Map()
    classFields = Map()
    classFieldTypes = Map()
    classMethods = Map()
    objClasses = Map()
    funcRetReady = 1
}

function initCodegen() {
    if (varTypesReady == 1) { return }
    varTypes = Map()
    varTypesReady = 1
}

function emitIR(s: string) {

    irBuf = irBuf + s + "\n"
}

function nextReg(): string {
    regCount = regCount + 1
    return "%" + regCount
}

function nextLabel(prefix: string): string {
    labelCount = labelCount + 1
    return prefix + "." + labelCount
}

function addStringConst(value: string): string {
    const name = "@.str." + strCount
    strCount = strCount + 1
    // Escape the string for LLVM IR c"..." format
    let escaped = ""
    let len = 0
    let i = 0
    const sLen = value.length()
    while (i < sLen) {
        const ch = value.charAt(i)
        if (ch == "\n") {
            escaped = escaped + "\\0A"
        } else if (ch == "\t") {
            escaped = escaped + "\\09"
        } else if (ch == "\\") {
            escaped = escaped + "\\5C"
        } else if (ch == "\"") {
            escaped = escaped + "\\22"
        } else {
            escaped = escaped + ch
        }
        len = len + 1
        i = i + 1
    }
    len = len + 1
    strConsts = strConsts + name + " = constant [" + len + " x i8] c\"" + escaped + "\\00\"\n"
    return name
}

// ── Runtime declarations ──────────────────────────────────────

function emitRuntimeDecls() {
    emitIR("; Runtime declarations")
    emitIR("declare void @ym_println(ptr)")
    emitIR("declare void @ym_print(ptr)")
    emitIR("declare ptr @ym_readLine()")
    emitIR("declare ptr @ym_readFile(ptr)")
    emitIR("declare void @ym_writeFile(ptr, ptr)")
    emitIR("declare ptr @ym_string_concat(ptr, ptr)")
    emitIR("declare ptr @ym_int_to_string(i32)")
    emitIR("declare ptr @ym_double_to_string(double)")
    emitIR("declare ptr @ym_i64_to_string(i64)")
    emitIR("declare i32 @ym_string_eq(ptr, ptr)")
    emitIR("declare i32 @ym_string_ne(ptr, ptr)")
    emitIR("declare i32 @ym_parseInt(ptr)")
    emitIR("declare double @ym_parseDouble(ptr)")
    emitIR("declare i32 @ym_stringLength(ptr)")
    emitIR("declare ptr @ym_trim(ptr)")
    emitIR("declare ptr @ym_toUpperCase(ptr)")
    emitIR("declare ptr @ym_toLowerCase(ptr)")
    emitIR("declare i32 @ym_startsWith(ptr, ptr)")
    emitIR("declare i32 @ym_endsWith(ptr, ptr)")
    emitIR("declare i32 @ym_contains(ptr, ptr)")
    emitIR("declare ptr @ym_replace(ptr, ptr, ptr)")
    emitIR("declare ptr @ym_charAt(ptr, i32)")
    emitIR("declare ptr @ym_repeat(ptr, i32)")
    emitIR("declare ptr @ym_substring(ptr, i32, i32)")
    emitIR("declare i32 @ym_indexOf(ptr, ptr)")
    emitIR("declare ptr @ym_padStart(ptr, i32, ptr)")
    emitIR("declare ptr @ym_padEnd(ptr, i32, ptr)")
    emitIR("declare ptr @ym_split(ptr, ptr)")
    emitIR("declare ptr @ym_join(ptr, ptr)")
    emitIR("declare ptr @ym_newArray(i32)")
    emitIR("declare i64 @ym_arrayGet(ptr, i32)")
    emitIR("declare void @ym_arraySet(ptr, i32, i64)")
    emitIR("declare i32 @ym_arrayLen(ptr)")
    emitIR("declare ptr @ym_arrayPush(ptr, i64)")
    emitIR("declare void @ym_arrayReverse(ptr)")
    emitIR("declare void @ym_arraySort(ptr)")
    emitIR("declare i32 @ym_arrayIndexOf(ptr, i64)")
    emitIR("declare ptr @ym_arraySlice(ptr, i32, i32)")
    emitIR("declare ptr @ym_arrayConcat(ptr, ptr)")
    emitIR("declare ptr @ym_arrayToString(ptr)")
    emitIR("declare i64 @ym_arrayFirst(ptr)")
    emitIR("declare i64 @ym_arrayLast(ptr)")
    emitIR("declare void @ym_initArgs(i32, ptr)")
    emitIR("declare i32 @ym_argCount()")
    emitIR("declare ptr @ym_argGet(i32)")
    emitIR("declare i64 @ym_timeMs()")
    emitIR("declare void @ym_exit(i32)")
    emitIR("declare i32 @ym_system(ptr)")
    emitIR("declare double @ym_sqrt(double)")
    emitIR("declare double @ym_abs(double)")
    emitIR("declare double @ym_floor(double)")
    emitIR("declare double @ym_ceil(double)")
    emitIR("declare double @ym_round(double)")
    emitIR("declare double @ym_log(double)")
    emitIR("declare double @ym_sin(double)")
    emitIR("declare double @ym_cos(double)")
    emitIR("declare double @ym_pow(double, double)")
    emitIR("declare double @ym_min(double, double)")
    emitIR("declare double @ym_max(double, double)")
    emitIR("declare double @ym_random()")
    emitIR("declare ptr @ym_mapNew()")
    emitIR("declare void @ym_mapSet(ptr, ptr, i64)")
    emitIR("declare i64 @ym_mapGet(ptr, ptr)")
    emitIR("declare i32 @ym_mapHas(ptr, ptr)")
    emitIR("declare i32 @ym_mapSize(ptr)")
    emitIR("declare ptr @ym_mapKeys(ptr)")
    emitIR("declare void @ym_mapDelete(ptr, ptr)")
    emitIR("declare ptr @malloc(i64)")
    emitIR("")
}

// ── Public API ────────────────────────────────────────────────

function generate(rootId: int): string {
    initCodegen()
    initFuncRetTypes()
    irBuf = ""
    strConsts = ""
    strCount = 0
    regCount = 0
    labelCount = 0

    emitRuntimeDecls()

    // Pass 0: register all user function return types + class info
    const stmtList0 = nGetList(rootId)
    if (stmtList0 != "") {
        const parts0 = stmtList0.split(",")
        for (p0 in parts0) {
            const sid = parseInt(p0)
            if (sid <= 0) { continue }
            const sk = nGetKind(sid)
            if (sk == "FUNC_DECL") {
                const fname = nGetS1(sid)
                let fret = nGetS2(sid)
                if (fret == "") { fret = "void" }
                funcRetTypes.set(fname, fret)
            }
            if (sk == "CLASS_DECL") {
                registerClass(sid)
            }
        }
    }

    // Walk program and generate
    const stmtList = nGetList(rootId)
    if (stmtList != "") {
        const parts = stmtList.split(",")
        for (p in parts) {
            const stmtId = parseInt(p)
            if (stmtId > 0) {
                genStmt(stmtId)
            }
        }
    }

    // Prepend string constants
    const header = "; ModuleID = 'simplescript'\nsource_filename = \"simplescript\"\n\n" + strConsts + "\n"
    return header + irBuf
}

// ── Builtin function name mapping ─────────────────────────────

function runtimeName(callee: string): string {
    if (callee == "println") { return "ym_println" }
    if (callee == "print") { return "ym_print" }
    if (callee == "readLine") { return "ym_readLine" }
    if (callee == "readFile") { return "ym_readFile" }
    if (callee == "writeFile") { return "ym_writeFile" }
    if (callee == "args") { return "ym_argCount" }
    if (callee == "arg") { return "ym_argGet" }
    if (callee == "exit") { return "ym_exit" }
    if (callee == "system") { return "ym_system" }
    if (callee == "parseInt") { return "ym_parseInt" }
    if (callee == "parseDouble") { return "ym_parseDouble" }
    if (callee == "sqrt") { return "ym_sqrt" }
    if (callee == "abs") { return "ym_abs" }
    if (callee == "floor") { return "ym_floor" }
    if (callee == "ceil") { return "ym_ceil" }
    if (callee == "round") { return "ym_round" }
    if (callee == "pow") { return "ym_pow" }
    if (callee == "log") { return "ym_log" }
    if (callee == "sin") { return "ym_sin" }
    if (callee == "cos") { return "ym_cos" }
    if (callee == "random") { return "ym_random" }
    if (callee == "min") { return "ym_min" }
    if (callee == "max") { return "ym_max" }
    if (callee == "Map") { return "ym_mapNew" }
    if (callee == "timeMs") { return "ym_timeMs" }
    return callee
}

// ── Statement generation ──────────────────────────────────────

function genStmt(id: int) {
    const kind = nGetKind(id)

    if (kind == "FUNC_DECL") {
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
            emitIR("  br label %" + breakLabel)
            terminated = 1
        }
        return
    }
    if (kind == "CONTINUE") {
        if (continueLabel != "") {
            emitIR("  br label %" + continueLabel)
            terminated = 1
        }
        return
    }
    if (kind == "POSTFIX_INC") {
        const piName = llVarName(nGetS1(id))
        const r1 = nextReg()
        emitIR("  " + r1 + " = load i32, ptr %" + piName + ", align 4")
        const r2 = nextReg()
        emitIR("  " + r2 + " = add i32 " + r1 + ", 1")
        emitIR("  store i32 " + r2 + ", ptr %" + piName + ", align 4")
        return
    }
    if (kind == "POSTFIX_DEC") {
        const pdName = llVarName(nGetS1(id))
        const r1 = nextReg()
        emitIR("  " + r1 + " = load i32, ptr %" + pdName + ", align 4")
        const r2 = nextReg()
        emitIR("  " + r2 + " = sub i32 " + r1 + ", 1")
        emitIR("  store i32 " + r2 + ", ptr %" + pdName + ", align 4")
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
        emitIR("  call void @ym_initArgs(i32 %0, ptr %1)")
        regCount = 2
    } else {
        // Collect param types (MVP: all int for now)
        const paramList = nGetList(id)
        let paramStr = ""
        let paramNames = ""
        if (paramList != "") {
            const parts = paramList.split(",")
            let idx = 0
            for (p in parts) {
                const pId = parseInt(p)
                if (pId > 0) {
                    const pName = nGetS1(pId)
                    const pType = nGetS2(pId)
                    const llType = ssTypeToLLVM(pType)
                    if (idx > 0) { paramStr = paramStr + ", " }
                    paramStr = paramStr + llType + " %" + pName + ".arg"
                    if (paramNames == "") { paramNames = pId + "" } else { paramNames = paramNames + "," + pId }
                    idx = idx + 1
                }
            }
        }
        let retType = nGetS2(id)
        if (retType == "") { retType = "void" }
        const llRetType = ssTypeToLLVM(retType)
        emitIR("define " + llRetType + " @" + name + "(" + paramStr + ") {")
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
                    emitIR("  %" + pLLName + " = alloca " + llType + ", align 8")
                    emitIR("  store " + llType + " %" + pName + ".arg, ptr %" + pLLName + ", align 8")
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
            emitIR("  ret ptr " + nullStr)
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

function genVarDecl(id: int) {
    const name = nGetS1(id)
    const initId = nGetI1(id)
    const typeAnn = nGetS3(id)

    // Infer type from init expression
    const initType = inferType(initId)
    const llType = ssTypeToLLVM(initType)

    const llName = allocVarName(name)
    emitIR("  %" + llName + " = alloca " + llType + ", align 8")
    setVarType(name, initType)

    // Track object class for method dispatch
    if (nGetKind(initId) == "NEW_EXPR") {
        setObjClass(name, nGetS1(initId))
    }
    if (nGetKind(initId) == "CALL" && nGetS1(initId) == "Map") {
        setObjClass(name, "Map")
    }

    const val = genExpr(initId)
    emitIR("  store " + llType + " " + val + ", ptr %" + llName + ", align 8")
}

function genAssign(id: int) {
    const name = nGetS1(id)
    const op = nGetS2(id)
    const valId = nGetI1(id)

    const vType = getVarType(name)
    const llType = ssTypeToLLVM(vType)

    if (op == "ASSIGN") {
        const val = genExpr(valId)
        emitIR("  store " + llType + " " + val + ", ptr %" + llVarName(name) + ", align 8")
    } else {
        // Compound: +=, -=, etc.
        const ln = llVarName(name)
        const r1 = nextReg()
        emitIR("  " + r1 + " = load " + llType + ", ptr %" + ln + ", align 8")
        const r2 = genExpr(valId)
        const r3 = nextReg()
        if (op == "PLUS_ASSIGN") {
            if (vType == "string") {
                emitIR("  " + r3 + " = call ptr @ym_string_concat(ptr " + r1 + ", ptr " + r2 + ")")
            } else {
                emitIR("  " + r3 + " = add i32 " + r1 + ", " + r2)
            }
        } else if (op == "MINUS_ASSIGN") {
            emitIR("  " + r3 + " = sub i32 " + r1 + ", " + r2)
        } else if (op == "STAR_ASSIGN") {
            emitIR("  " + r3 + " = mul i32 " + r1 + ", " + r2)
        } else if (op == "SLASH_ASSIGN") {
            emitIR("  " + r3 + " = sdiv i32 " + r1 + ", " + r2)
        } else {
            emitIR("  " + r3 + " = srem i32 " + r1 + ", " + r2)
        }
        emitIR("  store " + llType + " " + r3 + ", ptr %" + ln + ", align 8")
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
        emitIR("  ret " + ssTypeToLLVM(vType) + " " + val)
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
    emitIR("  " + r + " = icmp ne i32 " + condVal + ", 0")

    if (elseId > 0) {
        emitIR("  br i1 " + r + ", label %" + thenLabel + ", label %" + elseLabel)
    } else {
        emitIR("  br i1 " + r + ", label %" + thenLabel + ", label %" + mergeLabel)
    }

    emitIR(thenLabel + ":")
    terminated = 0
    genBlock(thenId)
    if (terminated == 0) {
        emitIR("  br label %" + mergeLabel)
    }

    if (elseId > 0) {
        emitIR(elseLabel + ":")
        terminated = 0
        genBlock(elseId)
        if (terminated == 0) {
            emitIR("  br label %" + mergeLabel)
        }
    }

    terminated = 0
    emitIR(mergeLabel + ":")
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
    emitIR("  br label %" + condLabel)

    emitIR(condLabel + ":")
    const condVal = genExpr(condId)
    const r = nextReg()
    emitIR("  " + r + " = icmp ne i32 " + condVal + ", 0")
    emitIR("  br i1 " + r + ", label %" + bodyLabel + ", label %" + afterLabel)

    emitIR(bodyLabel + ":")
    terminated = 0
    genBlock(bodyId)
    if (terminated == 0) { emitIR("  br label %" + updateLabel) }

    emitIR(updateLabel + ":")
    terminated = 0
    genStmt(updateId)
    emitIR("  br label %" + condLabel)

    emitIR(afterLabel + ":")
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
    emitIR("  " + lenReg + " = call i32 @ym_arrayLen(ptr " + arr + ")")

    // Index variable
    const idxAlloca = nextReg()
    emitIR("  " + idxAlloca + " = alloca i32, align 4")
    emitIR("  store i32 0, ptr " + idxAlloca + ", align 4")

    // Item variable
    const itemLLName = allocVarName(itemName)
    emitIR("  %" + itemLLName + " = alloca i64, align 8")
    setVarType(itemName, "i64")

    const condLabel = nextLabel("forin.cond")
    const bodyLabel = nextLabel("forin.body")
    const afterLabel = nextLabel("forin.after")

    const savedBreak2 = breakLabel
    const savedContinue2 = continueLabel
    const updateLabel2 = nextLabel("forin.update")
    breakLabel = afterLabel
    continueLabel = updateLabel2

    emitIR("  br label %" + condLabel)

    emitIR(condLabel + ":")
    const curIdx = nextReg()
    emitIR("  " + curIdx + " = load i32, ptr " + idxAlloca + ", align 4")
    const cmp = nextReg()
    emitIR("  " + cmp + " = icmp slt i32 " + curIdx + ", " + lenReg)
    emitIR("  br i1 " + cmp + ", label %" + bodyLabel + ", label %" + afterLabel)

    emitIR(bodyLabel + ":")
    terminated = 0
    const elemVal = nextReg()
    emitIR("  " + elemVal + " = call i64 @ym_arrayGet(ptr " + arr + ", i32 " + curIdx + ")")
    emitIR("  store i64 " + elemVal + ", ptr %" + itemLLName + ", align 8")

    genBlock(bodyId)
    if (terminated == 0) { emitIR("  br label %" + updateLabel2) }

    emitIR(updateLabel2 + ":")
    terminated = 0
    const nextIdx = nextReg()
    emitIR("  " + nextIdx + " = load i32, ptr " + idxAlloca + ", align 4")
    const incIdx = nextReg()
    emitIR("  " + incIdx + " = add i32 " + nextIdx + ", 1")
    emitIR("  store i32 " + incIdx + ", ptr " + idxAlloca + ", align 4")
    emitIR("  br label %" + condLabel)

    emitIR(afterLabel + ":")
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

    emitIR("  br label %" + condLabel)

    emitIR(condLabel + ":")
    const condVal = genExpr(condId)
    const r = nextReg()
    emitIR("  " + r + " = icmp ne i32 " + condVal + ", 0")
    emitIR("  br i1 " + r + ", label %" + bodyLabel + ", label %" + afterLabel)

    emitIR(bodyLabel + ":")
    terminated = 0
    genBlock(bodyId)
    if (terminated == 0) { emitIR("  br label %" + condLabel) }

    emitIR(afterLabel + ":")
    terminated = 0
    breakLabel = savedBreak3
    continueLabel = savedContinue3
}

// ── Expression generation ─────────────────────────────────────
// Returns the SSA register or constant string holding the result.

function genExpr(id: int): string {
    if (id <= 0) { return "0" }
    const kind = nGetKind(id)

    if (kind == "INT_LIT") {
        return nGetS1(id)
    }
    if (kind == "DOUBLE_LIT") {
        // LLVM requires specific double format
        const val = nGetS1(id)
        return val
    }
    if (kind == "STRING_LIT") {
        const name = addStringConst(nGetS1(id))
        return name
    }
    if (kind == "TRUE_LIT") { return "1" }
    if (kind == "FALSE_LIT") { return "0" }

    if (kind == "IDENT") {
        const name = nGetS1(id)
        const vType = getVarType(name)
        const llType = ssTypeToLLVM(vType)
        const r = nextReg()
        emitIR("  " + r + " = load " + llType + ", ptr %" + llVarName(name) + ", align 8")
        return r
    }

    if (kind == "BINARY") {
        return genBinary(id)
    }

    if (kind == "UNARY") {
        const op = nGetS1(id)
        const val = genExpr(nGetI1(id))
        const r = nextReg()
        if (op == "Neg") {
            const uType = inferType(nGetI1(id))
            if (uType == "double") {
                emitIR("  " + r + " = fsub double 0.0, " + val)
            } else {
                emitIR("  " + r + " = sub i32 0, " + val)
            }
        } else {
            emitIR("  " + r + " = icmp eq i32 " + val + ", 0")
            const r2 = nextReg()
            emitIR("  " + r2 + " = zext i1 " + r + " to i32")
            return r2
        }
        return r
    }

    if (kind == "CALL") {
        return genCall(id)
    }

    if (kind == "METHOD_CALL") {
        return genMethodCall(id)
    }

    if (kind == "MEMBER_ACCESS") {
        return genMemberAccess(id)
    }

    if (kind == "NEW_EXPR") {
        return genNewExpr(id)
    }

    if (kind == "GROUPING") {
        return genExpr(nGetI1(id))
    }

    if (kind == "TERNARY") {
        return genTernary(id)
    }

    if (kind == "TEMPLATE_LIT") {
        return genTemplateLit(id)
    }

    if (kind == "ARRAY_LIT") {
        return genArrayLit(id)
    }

    if (kind == "INDEX_ACCESS") {
        let arrVal = genExpr(nGetI1(id))
        // If array var is i64 (from for-in), inttoptr
        const arrType = inferType(nGetI1(id))
        if (arrType == "i64") {
            const cvtR = nextReg()
            emitIR("  " + cvtR + " = inttoptr i64 " + arrVal + " to ptr")
            arrVal = cvtR
        }
        const idxVal = genExpr(nGetI2(id))
        const r = nextReg()
        emitIR("  " + r + " = call i64 @ym_arrayGet(ptr " + arrVal + ", i32 " + idxVal + ")")
        return r
    }

    if (kind == "POSTFIX_INC") {
        const pieName = llVarName(nGetS1(id))
        const r1 = nextReg()
        emitIR("  " + r1 + " = load i32, ptr %" + pieName + ", align 4")
        const r2 = nextReg()
        emitIR("  " + r2 + " = add i32 " + r1 + ", 1")
        emitIR("  store i32 " + r2 + ", ptr %" + pieName + ", align 4")
        return r1
    }

    return "0"
}

function genBinary(id: int): string {
    const op = nGetS1(id)
    const leftId = nGetI1(id)
    const rightId = nGetI2(id)

    const blt = inferType(leftId)
    const brt = inferType(rightId)

    // String concatenation
    if (op == "Add" && (blt == "string" || brt == "string" || blt == "i64" || brt == "i64")) {
        // Check if at least one side is actually string
        if (blt == "string" || brt == "string") {
            const l = genExprAsString(leftId)
            const rVal = genExprAsString(rightId)
            const r = nextReg()
            emitIR("  " + r + " = call ptr @ym_string_concat(ptr " + l + ", ptr " + rVal + ")")
            return r
        }
    }

    // String equality
    if ((op == "Eq" || op == "Ne") && blt == "string") {
        const l = genExpr(leftId)
        const rVal = genExpr(rightId)
        const r = nextReg()
        if (op == "Eq") {
            emitIR("  " + r + " = call i32 @ym_string_eq(ptr " + l + ", ptr " + rVal + ")")
        } else {
            emitIR("  " + r + " = call i32 @ym_string_ne(ptr " + l + ", ptr " + rVal + ")")
        }
        return r
    }

    let left = genExpr(leftId)
    let right = genExpr(rightId)

    // Normalize i64 operands to i32 for integer arithmetic
    if (blt == "i64" && brt != "i64") {
        const trR = nextReg()
        emitIR("  " + trR + " = trunc i64 " + left + " to i32")
        left = trR
    }
    if (brt == "i64" && blt != "i64") {
        const trR = nextReg()
        emitIR("  " + trR + " = trunc i64 " + right + " to i32")
        right = trR
    }
    if (blt == "i64" && brt == "i64") {
        const trL = nextReg()
        emitIR("  " + trL + " = trunc i64 " + left + " to i32")
        left = trL
        const trR = nextReg()
        emitIR("  " + trR + " = trunc i64 " + right + " to i32")
        right = trR
    }

    if (blt == "double" || brt == "double") {
        // Convert int operand to double if needed
        if (blt != "double") {
            const cvtR = nextReg()
            emitIR("  " + cvtR + " = sitofp i32 " + left + " to double")
            left = cvtR
        }
        if (brt != "double") {
            const cvtR = nextReg()
            emitIR("  " + cvtR + " = sitofp i32 " + right + " to double")
            right = cvtR
        }
        const r = nextReg()
        if (op == "Add") { emitIR("  " + r + " = fadd double " + left + ", " + right); return r }
        if (op == "Sub") { emitIR("  " + r + " = fsub double " + left + ", " + right); return r }
        if (op == "Mul") { emitIR("  " + r + " = fmul double " + left + ", " + right); return r }
        if (op == "Div") { emitIR("  " + r + " = fdiv double " + left + ", " + right); return r }
        if (op == "Mod") { emitIR("  " + r + " = frem double " + left + ", " + right); return r }
        // Float comparison
        let fcmpOp = ""
        if (op == "Eq") { fcmpOp = "oeq" }
        if (op == "Ne") { fcmpOp = "one" }
        if (op == "Lt") { fcmpOp = "olt" }
        if (op == "Gt") { fcmpOp = "ogt" }
        if (op == "Le") { fcmpOp = "ole" }
        if (op == "Ge") { fcmpOp = "oge" }
        if (fcmpOp != "") {
            emitIR("  " + r + " = fcmp " + fcmpOp + " double " + left + ", " + right)
            const r2 = nextReg()
            emitIR("  " + r2 + " = zext i1 " + r + " to i32")
            return r2
        }
    }
    const r = nextReg()
    if (op == "Add") { emitIR("  " + r + " = add i32 " + left + ", " + right); return r }
    if (op == "Sub") { emitIR("  " + r + " = sub i32 " + left + ", " + right); return r }
    if (op == "Mul") { emitIR("  " + r + " = mul i32 " + left + ", " + right); return r }
    if (op == "Div") { emitIR("  " + r + " = sdiv i32 " + left + ", " + right); return r }
    if (op == "Mod") { emitIR("  " + r + " = srem i32 " + left + ", " + right); return r }
    if (op == "And") { emitIR("  " + r + " = and i32 " + left + ", " + right); return r }
    if (op == "Or") { emitIR("  " + r + " = or i32 " + left + ", " + right); return r }
    // Integer comparison
    let cmpOp = ""
    if (op == "Eq") { cmpOp = "eq" }
    if (op == "Ne") { cmpOp = "ne" }
    if (op == "Lt") { cmpOp = "slt" }
    if (op == "Gt") { cmpOp = "sgt" }
    if (op == "Le") { cmpOp = "sle" }
    if (op == "Ge") { cmpOp = "sge" }
    if (cmpOp != "") {
        emitIR("  " + r + " = icmp " + cmpOp + " i32 " + left + ", " + right)
        const r2 = nextReg()
        emitIR("  " + r2 + " = zext i1 " + r + " to i32")
        return r2
    }
    emitIR("  ; unknown binary op: " + op)
    return r
}

function genCall(id: int): string {
    const callee = nGetS1(id)
    const rtName = runtimeName(callee)
    const argList = nGetList(id)

    // Special case: println with auto-conversion
    if (callee == "println" || callee == "print") {
        const fnName = runtimeName(callee)
        if (argList == "") {
            const emptyStr = addStringConst("")
            emitIR("  call void @" + fnName + "(ptr " + emptyStr + ")")
            return "0"
        }
        // Build concatenated string from all args
        let result = ""
        const parts = argList.split(",")
        let first = 1
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                const argStr = genExprAsString(argId)
                if (first == 1) {
                    result = argStr
                    first = 0
                } else {
                    const space = addStringConst(" ")
                    const r1 = nextReg()
                    emitIR("  " + r1 + " = call ptr @ym_string_concat(ptr " + result + ", ptr " + space + ")")
                    const r2 = nextReg()
                    emitIR("  " + r2 + " = call ptr @ym_string_concat(ptr " + r1 + ", ptr " + argStr + ")")
                    result = r2
                }
            }
        }
        emitIR("  call void @" + fnName + "(ptr " + result + ")")
        return "0"
    }

    // General function call
    let args = ""
    if (argList != "") {
        const parts = argList.split(",")
        let first = 1
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                const val = genExpr(argId)
                const vType = inferType(argId)
                const llType = ssTypeToLLVM(vType)
                if (first == 1) { first = 0 } else { args = args + ", " }
                args = args + llType + " " + val
            }
        }
    }

    // Determine return type
    const retType = callReturnType(callee)
    const llRetType = ssTypeToLLVM(retType)

    if (llRetType == "void") {
        emitIR("  call void @" + rtName + "(" + args + ")")
        return "0"
    }
    const r = nextReg()
    emitIR("  " + r + " = call " + llRetType + " @" + rtName + "(" + args + ")")
    return r
}

function genMethodCall(id: int): string {
    const method = nGetS1(id)
    const objId = nGetI1(id)
    const argList = nGetList(id)

    let objVal = genExpr(objId)
    // If object is i64 (e.g., from for-in or Map.get), convert to ptr for string/array methods
    const objType = inferType(objId)
    if (objType == "i64") {
        const castR = nextReg()
        emitIR("  " + castR + " = inttoptr i64 " + objVal + " to ptr")
        objVal = castR
    }

    // String methods
    if (method == "length") {
        const r = nextReg()
        emitIR("  " + r + " = call i32 @ym_stringLength(ptr " + objVal + ")")
        return r
    }
    if (method == "charAt") {
        const argId = parseInt(argList)
        const idx = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_charAt(ptr " + objVal + ", i32 " + idx + ")")
        return r
    }
    if (method == "indexOf") {
        const argId = parseInt(argList)
        const sub = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call i32 @ym_indexOf(ptr " + objVal + ", ptr " + sub + ")")
        return r
    }
    if (method == "substring") {
        const argParts = argList.split(",")
        const startVal = genExpr(parseInt(argParts[0]))
        const lenVal = genExpr(parseInt(argParts[1]))
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_substring(ptr " + objVal + ", i32 " + startVal + ", i32 " + lenVal + ")")
        return r
    }
    if (method == "contains") {
        const argId = parseInt(argList)
        const sub = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call i32 @ym_contains(ptr " + objVal + ", ptr " + sub + ")")
        return r
    }
    if (method == "replace") {
        const argParts = argList.split(",")
        const oldVal = genExpr(parseInt(argParts[0]))
        const newVal = genExpr(parseInt(argParts[1]))
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_replace(ptr " + objVal + ", ptr " + oldVal + ", ptr " + newVal + ")")
        return r
    }
    if (method == "split") {
        const argId = parseInt(argList)
        const delim = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_split(ptr " + objVal + ", ptr " + delim + ")")
        return r
    }
    if (method == "join") {
        const argId = parseInt(argList)
        const delim = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_join(ptr " + objVal + ", ptr " + delim + ")")
        return r
    }
    if (method == "trim") {
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_trim(ptr " + objVal + ")")
        return r
    }
    if (method == "toUpperCase") {
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_toUpperCase(ptr " + objVal + ")")
        return r
    }
    if (method == "toLowerCase") {
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_toLowerCase(ptr " + objVal + ")")
        return r
    }
    // Array methods
    if (method == "push") {
        const argId = parseInt(argList)
        const val = genExpr(argId)
        const pushType = inferType(argId)
        let val64p = val
        if (pushType == "int" || pushType == "auto" || pushType == "") {
            const sR = nextReg()
            emitIR("  " + sR + " = sext i32 " + val + " to i64")
            val64p = sR
        }
        if (pushType == "string" || pushType == "ptr") {
            const cR = nextReg()
            emitIR("  " + cR + " = ptrtoint ptr " + val + " to i64")
            val64p = cR
        }
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_arrayPush(ptr " + objVal + ", i64 " + val64p + ")")
        return r
    }
    // Map methods
    if (method == "set") {
        const argParts = argList.split(",")
        const key = genExpr(parseInt(argParts[0]))
        const val = genExpr(parseInt(argParts[1]))
        const valType = inferType(parseInt(argParts[1]))
        let val64 = val
        if (valType == "int" || valType == "auto" || valType == "") {
            const sextR = nextReg()
            emitIR("  " + sextR + " = sext i32 " + val + " to i64")
            val64 = sextR
        }
        if (valType == "string" || valType == "ptr") {
            const castR = nextReg()
            emitIR("  " + castR + " = ptrtoint ptr " + val + " to i64")
            val64 = castR
        }
        emitIR("  call void @ym_mapSet(ptr " + objVal + ", ptr " + key + ", i64 " + val64 + ")")
        return "0"
    }
    if (method == "get") {
        const argId = parseInt(argList)
        const key = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call i64 @ym_mapGet(ptr " + objVal + ", ptr " + key + ")")
        return r
    }
    if (method == "getString") {
        const argId = parseInt(argList)
        const key = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call i64 @ym_mapGet(ptr " + objVal + ", ptr " + key + ")")
        // Cast i64 to ptr (reinterpret)
        const r2 = nextReg()
        emitIR("  " + r2 + " = inttoptr i64 " + r + " to ptr")
        return r2
    }
    if (method == "has") {
        const argId = parseInt(argList)
        const key = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call i32 @ym_mapHas(ptr " + objVal + ", ptr " + key + ")")
        return r
    }
    if (method == "size") {
        const r = nextReg()
        emitIR("  " + r + " = call i32 @ym_mapSize(ptr " + objVal + ")")
        return r
    }

    // Class method call: obj.method(args) → ClassName_method(obj, args)
    const objId2 = nGetI1(id)
    let className = ""
    if (nGetKind(objId2) == "IDENT") {
        className = getObjClass(nGetS1(objId2))
    }
    if (nGetKind(objId2) == "THIS" && currentClassName != "") {
        className = currentClassName
    }
    if (className != "" && className != "Map") {
        let callArgs = "ptr " + objVal
        if (argList != "") {
            const argParts = argList.split(",")
            for (ap in argParts) {
                const argId = parseInt(ap)
                if (argId > 0) {
                    const aVal = genExpr(argId)
                    const aType = inferType(argId)
                    callArgs = callArgs + ", " + ssTypeToLLVM(aType) + " " + aVal
                }
            }
        }
        let mRetType = "ptr"
        if (funcRetTypes.has(className + "_" + method) == 1) {
            mRetType = ssTypeToLLVM(funcRetTypes.getString(className + "_" + method))
        }
        if (mRetType == "void") {
            emitIR("  call void @" + className + "_" + method + "(" + callArgs + ")")
            return "0"
        }
        const cr = nextReg()
        emitIR("  " + cr + " = call " + mRetType + " @" + className + "_" + method + "(" + callArgs + ")")
        return cr
    }

    emitIR("  ; TODO: method call ." + method)
    return "0"
}

function genTemplateLit(id: int): string {
    const fragList = nGetList(id)
    if (fragList == "") {
        return addStringConst("")
    }
    let result = ""
    const parts = fragList.split(",")
    for (p in parts) {
        const fragId = parseInt(p)
        if (fragId > 0) {
            const fk = nGetKind(fragId)
            let fragStr = ""
            if (fk == "TMPL_FRAG_LIT") {
                fragStr = addStringConst(nGetS1(fragId))
            } else if (fk == "TMPL_FRAG_EXPR") {
                fragStr = genExprAsString(nGetI1(fragId))
            }
            if (result == "") {
                result = fragStr
            } else {
                const r = nextReg()
                emitIR("  " + r + " = call ptr @ym_string_concat(ptr " + result + ", ptr " + fragStr + ")")
                result = r
            }
        }
    }
    return result
}

function genArrayLit(id: int): string {
    const elemList = nGetList(id)
    let count = 0
    if (elemList != "") {
        const parts = elemList.split(",")
        for (p in parts) {
            count = count + 1
        }
    }
    const arrReg = nextReg()
    emitIR("  " + arrReg + " = call ptr @ym_newArray(i32 " + count + ")")

    if (elemList != "") {
        let idx = 0
        const parts = elemList.split(",")
        for (p in parts) {
            const elemId = parseInt(p)
            if (elemId > 0) {
                const val = genExpr(elemId)
                const vType = inferType(elemId)
                if (vType == "string") {
                    const castReg = nextReg()
                    emitIR("  " + castReg + " = ptrtoint ptr " + val + " to i64")
                    emitIR("  call void @ym_arraySet(ptr " + arrReg + ", i32 " + idx + ", i64 " + castReg + ")")
                } else {
                    const extReg = nextReg()
                    emitIR("  " + extReg + " = sext i32 " + val + " to i64")
                    emitIR("  call void @ym_arraySet(ptr " + arrReg + ", i32 " + idx + ", i64 " + extReg + ")")
                }
                idx = idx + 1
            }
        }
    }
    return arrReg
}

function genTernary(id: int): string {
    const condVal = genExpr(nGetI1(id))
    const thenLabel = nextLabel("tern.then")
    const elseLabel = nextLabel("tern.else")
    const mergeLabel = nextLabel("tern.merge")

    const cmp = nextReg()
    emitIR("  " + cmp + " = icmp ne i32 " + condVal + ", 0")
    emitIR("  br i1 " + cmp + ", label %" + thenLabel + ", label %" + elseLabel)

    emitIR(thenLabel + ":")
    const thenVal = genExpr(nGetI2(id))
    emitIR("  br label %" + mergeLabel)

    emitIR(elseLabel + ":")
    const elseVal = genExpr(nGetI3(id))
    emitIR("  br label %" + mergeLabel)

    emitIR(mergeLabel + ":")
    const phi = nextReg()
    const vType = inferType(nGetI2(id))
    const llType = ssTypeToLLVM(vType)
    emitIR("  " + phi + " = phi " + llType + " [" + thenVal + ", %" + thenLabel + "], [" + elseVal + ", %" + elseLabel + "]")
    return phi
}

// Convert any expression to string for println
function genExprAsString(id: int): string {
    const vType = inferType(id)
    if (vType == "string") {
        const sVal = genExpr(id)
        // If the actual LLVM value is i64 (e.g., from array), inttoptr
        const sNodeKind = nGetKind(id)
        if (sNodeKind == "IDENT" && getVarType(nGetS1(id)) == "i64") {
            const castR = nextReg()
            emitIR("  " + castR + " = inttoptr i64 " + sVal + " to ptr")
            return castR
        }
        return sVal
    }
    const val = genExpr(id)
    const r = nextReg()
    if (vType == "double") {
        emitIR("  " + r + " = call ptr @ym_double_to_string(double " + val + ")")
    } else if (vType == "i64") {
        emitIR("  " + r + " = call ptr @ym_i64_to_string(i64 " + val + ")")
    } else if (vType == "ptr") {
        // Object pointer → convert using i64_to_string (heuristic: if > 0x100000, treat as string pointer)
        const castR = nextReg()
        emitIR("  " + castR + " = ptrtoint ptr " + val + " to i64")
        emitIR("  " + r + " = call ptr @ym_i64_to_string(i64 " + castR + ")")
    } else {
        emitIR("  " + r + " = call ptr @ym_int_to_string(i32 " + val + ")")
    }
    return r
}

// ── Type inference (simplified) ───────────────────────────────

function inferType(id: int): string {
    if (id <= 0) { return "int" }
    const kind = nGetKind(id)
    if (kind == "INT_LIT") { return "int" }
    if (kind == "DOUBLE_LIT") { return "double" }
    if (kind == "STRING_LIT") { return "string" }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }
    if (kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "IDENT") {
        const vType = getVarType(nGetS1(id))
        if (vType != "") { return vType }
        return "int"
    }
    if (kind == "BINARY") {
        const op = nGetS1(id)
        if (op == "Add") {
            const blt2 = inferType(nGetI1(id))
            if (blt2 == "string") { return "string" }
            const brt2 = inferType(nGetI2(id))
            if (brt2 == "string") { return "string" }
        }
        if (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge" || op == "And" || op == "Or") {
            return "int"
        }
        // Check both operands for double
        const binLt = inferType(nGetI1(id))
        const binRt = inferType(nGetI2(id))
        if (binLt == "double" || binRt == "double") { return "double" }
        if (binLt == "i64") { return "int" }
        return binLt
    }
    if (kind == "CALL") {
        const callee = nGetS1(id)
        if (callee == "Map") { return "ptr" }
        return callReturnType(callee)
    }
    if (kind == "METHOD_CALL") {
        const method = nGetS1(id)
        if (method == "length" || method == "indexOf" || method == "has" || method == "size") { return "int" }
        if (method == "charAt" || method == "substring" || method == "trim" || method == "toUpperCase" || method == "toLowerCase" || method == "replace" || method == "join") { return "string" }
        if (method == "split" || method == "push") { return "ptr" }
        if (method == "get") { return "i64" }
        if (method == "getString") { return "string" }
        if (method == "contains" || method == "startsWith" || method == "endsWith") { return "int" }
        // Class method — look up return type
        const mObjId = nGetI1(id)
        let mClassName = ""
        if (nGetKind(mObjId) == "IDENT") { mClassName = getObjClass(nGetS1(mObjId)) }
        if (nGetKind(mObjId) == "THIS" && currentClassName != "") { mClassName = currentClassName }
        if (mClassName != "" && funcRetTypes.has(mClassName + "_" + method) == 1) {
            return funcRetTypes.getString(mClassName + "_" + method)
        }
        return "int"
    }
    if (kind == "MEMBER_ACCESS") {
        const mField = nGetS1(id)
        const mObj = nGetI1(id)
        let maClassName = ""
        if (nGetKind(mObj) == "THIS" && currentClassName != "") { maClassName = currentClassName }
        if (nGetKind(mObj) == "IDENT") { maClassName = getObjClass(nGetS1(mObj)) }
        if (maClassName != "" && classFieldTypes.has(maClassName + "." + mField) == 1) {
            return classFieldTypes.getString(maClassName + "." + mField)
        }
        return "int"
    }
    if (kind == "GROUPING") { return inferType(nGetI1(id)) }
    if (kind == "UNARY") { return inferType(nGetI1(id)) }
    if (kind == "TERNARY") { return inferType(nGetI2(id)) }
    if (kind == "ARRAY_LIT") { return "ptr" }
    if (kind == "INDEX_ACCESS") { return "i64" }
    if (kind == "NEW_EXPR") { return "ptr" }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { return "int" }
    return "int"
}

function callReturnType(callee: string): string {
    if (callee == "readLine" || callee == "readFile" || callee == "arg") { return "string" }
    if (callee == "println" || callee == "print" || callee == "writeFile" || callee == "exit") { return "void" }
    if (callee == "parseInt" || callee == "args" || callee == "system") { return "int" }
    if (callee == "parseDouble" || callee == "sqrt" || callee == "abs" || callee == "floor" || callee == "ceil" || callee == "round" || callee == "pow" || callee == "log" || callee == "sin" || callee == "cos" || callee == "random" || callee == "min" || callee == "max") { return "double" }
    if (callee == "Map") { return "ptr" }
    if (callee == "timeMs") { return "i64" }
    // User-defined function
    if (funcRetTypes.has(callee) == 1) {
        return funcRetTypes.getString(callee)
    }
    return "int"
}

// ── Type helpers ──────────────────────────────────────────────

function ssTypeToLLVM(t: string): string {
    if (t == "int" || t == "bool" || t == "auto" || t == "") { return "i32" }
    if (t == "double") { return "double" }
    if (t == "string") { return "ptr" }
    if (t == "void") { return "void" }
    if (t == "ptr") { return "ptr" }
    if (t == "i64") { return "i64" }
    // Class type names → ptr
    if (classFields.has(t) == 1) { return "ptr" }
    return "i32"
}

function setVarType(name: string, varType: string) {
    varTypes.set(name, varType)
}

function getVarType(name: string): string {
    if (varTypes.has(name) == 1) {
        return varTypes.getString(name)
    }
    return ""
}

// ── Class support ─────────────────────────────────────────────

function registerClass(id: int) {
    const name = nGetS1(id)
    const paramList = nGetList(id)
    // Collect field names and types
    let fieldNames = ""
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const fName = nGetS1(pId)
                const fType = nGetS2(pId)
                if (fieldNames == "") { fieldNames = fName } else { fieldNames = fieldNames + "," + fName }
                classFieldTypes.set(name + "." + fName, fType)
            }
        }
    }
    classFields.set(name, fieldNames)
    // Collect method names
    const methodsBlockId = nGetI2(id)
    let methodNames = ""
    if (methodsBlockId > 0) {
        const mList = nGetList(methodsBlockId)
        if (mList != "") {
            const mParts = mList.split(",")
            for (mp in mParts) {
                const mId = parseInt(mp)
                if (mId > 0 && nGetKind(mId) == "FUNC_DECL") {
                    const mName = nGetS1(mId)
                    if (methodNames == "") { methodNames = mName } else { methodNames = methodNames + "," + mName }
                    // Register return type
                    let mRet = nGetS2(mId)
                    if (mRet == "") { mRet = "void" }
                    funcRetTypes.set(name + "_" + mName, mRet)
                }
            }
        }
    }
    classMethods.set(name, methodNames)
}

function genClassDecl(id: int) {
    const name = nGetS1(id)
    const fieldStr = classFields.getString(name)

    // Emit LLVM struct type
    let fieldTypes = ""
    if (fieldStr != "") {
        const parts = fieldStr.split(",")
        let first = 1
        for (p in parts) {
            const ft = classFieldTypes.getString(name + "." + p)
            const llType = ssTypeToLLVM(ft)
            if (first == 1) { first = 0 } else { fieldTypes = fieldTypes + ", " }
            fieldTypes = fieldTypes + llType
        }
    }
    emitIR("%" + name + " = type { " + fieldTypes + " }")
    emitIR("")

    // Emit constructor: @ClassName_new(fields...) -> ptr
    let ctorParams = ""
    let ctorIdx = 0
    if (fieldStr != "") {
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(name + "." + p)
            const llType = ssTypeToLLVM(ft)
            if (ctorIdx > 0) { ctorParams = ctorParams + ", " }
            ctorParams = ctorParams + llType + " %" + p + ".arg"
            ctorIdx = ctorIdx + 1
        }
    }
    regCount = 0
    emitIR("define ptr @" + name + "_new(" + ctorParams + ") {")
    emitIR("entry:")
    // Calculate struct size (simplified: 8 bytes per field)
    const structSize = ctorIdx * 8
    const mallocReg = nextReg()
    emitIR("  " + mallocReg + " = call ptr @malloc(i64 " + structSize + ")")
    // Store fields
    if (fieldStr != "") {
        let idx = 0
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(name + "." + p)
            const llType = ssTypeToLLVM(ft)
            const gepReg = nextReg()
            emitIR("  " + gepReg + " = getelementptr %" + name + ", ptr " + mallocReg + ", i32 0, i32 " + idx)
            emitIR("  store " + llType + " %" + p + ".arg, ptr " + gepReg + ", align 8")
            idx = idx + 1
        }
    }
    emitIR("  ret ptr " + mallocReg)
    emitIR("}")
    emitIR("")

    // Emit methods: @ClassName_methodName(ptr %this, args...) -> retType
    const methodsBlockId = nGetI2(id)
    if (methodsBlockId > 0) {
        const mList = nGetList(methodsBlockId)
        if (mList != "") {
            const mParts = mList.split(",")
            for (mp in mParts) {
                const mId = parseInt(mp)
                if (mId > 0 && nGetKind(mId) == "FUNC_DECL") {
                    genClassMethod(name, mId)
                }
            }
        }
    }
}

function genClassMethod(className: string, id: int) {
    const mName = nGetS1(id)
    let retType = nGetS2(id)
    if (retType == "") { retType = "void" }
    const llRetType = ssTypeToLLVM(retType)

    // Build param list (this + declared params)
    let paramStr = "ptr %this.ptr"
    const paramList = nGetList(id)
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const pName = nGetS1(pId)
                const pType = nGetS2(pId)
                const llType = ssTypeToLLVM(pType)
                paramStr = paramStr + ", " + llType + " %" + pName + ".arg"
            }
        }
    }

    regCount = 0
    terminated = 0
    currentFunc = className + "_" + mName
    currentClassName = className
    varAliases = Map()

    emitIR("define " + llRetType + " @" + className + "_" + mName + "(" + paramStr + ") {")
    emitIR("entry:")

    // Alloca this
    emitIR("  %this = alloca ptr, align 8")
    emitIR("  store ptr %this.ptr, ptr %this, align 8")
    setVarType("this", className)

    // Alloca params
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const pName = nGetS1(pId)
                const pType = nGetS2(pId)
                const llType = ssTypeToLLVM(pType)
                emitIR("  %" + pName + " = alloca " + llType + ", align 8")
                emitIR("  store " + llType + " %" + pName + ".arg, ptr %" + pName + ", align 8")
                setVarType(pName, pType)
                if (classFields.has(pType) == 1) {
                    setObjClass(pName, pType)
                }
            }
        }
    }

    // Generate body
    const bodyId = nGetI1(id)
    genBlock(bodyId)

    // Default return
    if (terminated == 0) {
        if (llRetType == "void") {
            emitIR("  ret void")
        } else if (llRetType == "ptr") {
            const ns = addStringConst("")
            emitIR("  ret ptr " + ns)
        } else {
            emitIR("  ret " + llRetType + " 0")
        }
    }
    emitIR("}")
    emitIR("")
    currentClassName = ""
}

function genNewExpr(id: int): string {
    const className = nGetS1(id)
    const argList = nGetList(id)
    let args = ""
    if (argList != "") {
        const parts = argList.split(",")
        let first = 1
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                const val = genExpr(argId)
                const vType = inferType(argId)
                const llType = ssTypeToLLVM(vType)
                if (first == 1) { first = 0 } else { args = args + ", " }
                args = args + llType + " " + val
            }
        }
    }
    const r = nextReg()
    emitIR("  " + r + " = call ptr @" + className + "_new(" + args + ")")
    return r
}

function genMemberAccess(id: int): string {
    const member = nGetS1(id)
    const objId = nGetI1(id)
    const objKind = nGetKind(objId)

    // this.field
    if (objKind == "THIS") {
        const thisReg = nextReg()
        emitIR("  " + thisReg + " = load ptr, ptr %this, align 8")
        const idx = getFieldIndex(currentClassName, member)
        if (idx >= 0) {
            const fType = classFieldTypes.getString(currentClassName + "." + member)
            const llType = ssTypeToLLVM(fType)
            const gepReg = nextReg()
            emitIR("  " + gepReg + " = getelementptr %" + currentClassName + ", ptr " + thisReg + ", i32 0, i32 " + idx)
            const loadReg = nextReg()
            emitIR("  " + loadReg + " = load " + llType + ", ptr " + gepReg + ", align 8")
            return loadReg
        }
        return thisReg
    }

    // obj.field — need to know object's class
    const objVal = genExpr(objId)
    if (objKind == "IDENT") {
        const varName = nGetS1(objId)
        const className = getObjClass(varName)
        if (className != "") {
            const idx = getFieldIndex(className, member)
            if (idx >= 0) {
                const fType = classFieldTypes.getString(className + "." + member)
                const llType = ssTypeToLLVM(fType)
                const gepReg = nextReg()
                emitIR("  " + gepReg + " = getelementptr %" + className + ", ptr " + objVal + ", i32 0, i32 " + idx)
                const loadReg = nextReg()
                emitIR("  " + loadReg + " = load " + llType + ", ptr " + gepReg + ", align 8")
                return loadReg
            }
        }
    }
    return objVal
}

function setObjClass(varName: string, className: string) {
    objClasses.set(varName, className)
}

function getObjClass(varName: string): string {
    if (objClasses.has(varName) == 1) {
        return objClasses.getString(varName)
    }
    return ""
}

function getFieldIndex(className: string, fieldName: string): int {
    const fieldStr = classFields.getString(className)
    if (fieldStr == "") { return -1 }
    const parts = fieldStr.split(",")
    let idx = 0
    for (p in parts) {
        if (p == fieldName) { return idx }
        idx = idx + 1
    }
    return -1
}
