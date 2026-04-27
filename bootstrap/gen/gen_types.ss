// Type inference, type helpers, and method overloading for bootstrap codegen
// Extracted from gen_exprs.ss — pure query functions (no IR emission)

function getMethodName(exprId: int): string {
    if (nGetKind(exprId) != "METHOD_CALL") { return "" }
    return nGetS1(exprId)
}

// ── Tuple type helpers ────────────────────────────────────────

function isTupleType(t: string): int {
    if (t.startsWith("Tuple<") == 1) { return 1 }
    return 0
}

// Extract the element type at a given index from a tuple type string
// e.g. tupleElemTypeAtIndex("Tuple<int,string>", 1) → "string"
function tupleElemTypeAtIndex(tupleType: string, idx: int): string {
    const inner = tupleType.substring(6, tupleType.length() - 7)
    let depth = 0
    let start = 0
    let pos = 0
    let i = 0
    while (i < inner.length()) {
        const ch = inner.substring(i, 1)
        if (ch == "<") { depth = depth + 1 }
        if (ch == ">") { depth = depth - 1 }
        if (ch == "," && depth == 0) {
            if (pos == idx) { return inner.substring(start, i - start) }
            pos = pos + 1
            start = i + 1
        }
        i = i + 1
    }
    if (pos == idx) { return inner.substring(start, inner.length() - start) }
    return ""
}

function inferTupleIndexType(indexAccessId: int): string {
    if (nGetKind(nGetI1(indexAccessId)) != "IDENT") { return "" }
    const varType = getVarType(nGetS1(nGetI1(indexAccessId)))
    if (isTupleType(varType) != 1) { return "" }
    if (nGetKind(nGetI2(indexAccessId)) != "INT_LIT") { return "" }
    return tupleElemTypeAtIndex(varType, parseInt(nGetS1(nGetI2(indexAccessId))))
}

// ── Ref type helper (D082) ────────────────────────────────────

// Extract element type from "Ref<int>" → "int", "Ref<string>" → "string"
function refElemType(refType: string): string {
    if (refType.startsWith("Ref<") == 1 && refType.length() > 5) {
        return refType.substring(4, refType.length() - 5)
    }
    return "int"
}

// ── Thread type helper (D082 Phase 2) ────────────────────────

// Extract element type from "Thread<int>" → "int", "Thread<string>" → "string"
function threadElemType(threadType: string): string {
    if (threadType.startsWith("Thread<") == 1 && threadType.length() > 8) {
        return threadType.substring(7, threadType.length() - 8)
    }
    return "int"
}

// ── Channel type helper (D082 Phase 4) ────────────────────────

// Extract element type from "Channel<int>" → "int", "Channel<string>" → "string"
function channelElemType(chanType: string): string {
    if (chanType.startsWith("Channel<") == 1 && chanType.length() > 9) {
        return chanType.substring(8, chanType.length() - 9)
    }
    return "int"
}

// ── Map value type helper (I019) ─────────────────────────────
// "Map<K,V>" / "Map<K, V>" → V;v0 naive first-comma split(嵌套 generic K 不在 scope,
// typical Spring 用例 Map<string,*> / Map<int,*> 足够)。
function extractMapValueType(mapType: string): string {
    if (mapType.startsWith("Map<") == 0) { return "" }
    const emCI = mapType.indexOf(",")
    if (emCI < 0) { return "" }
    const emEnd = mapType.length() - 1
    let emS = emCI + 1
    while (emS < emEnd && mapType.charAt(emS) == " ") { emS = emS + 1 }
    return mapType.substring(emS, emEnd - emS)
}

// Walk a BLOCK body for the first RETURN, returning inferType on its expression
// (or "" if body missing / bare return / no RETURN found). Shared by arrow and
// comptime-class-method retType inference; callers pick their own fallback.
function firstReturnInferredType(bodyId: int): string {
    if (bodyId <= 0 || nGetKind(bodyId) != "BLOCK") { return "" }
    const bodyList = nGetList(bodyId)
    if (bodyList == "") { return "" }
    const parts = bodyList.split(",")
    for (p in parts) {
        const stmtId = parseInt(p)
        if (stmtId > 0 && nGetKind(stmtId) == "RETURN") {
            const retVal = nGetI1(stmtId)
            if (retVal > 0) { return inferType(retVal) }
            return ""
        }
    }
    return ""
}

// Infer the return type of an arrow function node
function inferArrowRetType(arrowId: int): string {
    if (arrowId <= 0) { return "int" }
    const annot = nGetS2(arrowId)
    if (annot != "") { return annot }
    const bodyId = nGetI1(arrowId)
    if (bodyId <= 0) { return "int" }
    // Single-expression body: infer directly (no BLOCK to walk).
    if (nGetKind(bodyId) != "BLOCK") { return inferType(bodyId) }
    const t = firstReturnInferredType(bodyId)
    if (t == "") { return "void" }
    return t
}

// ── Type inference ────────────────────────────────────────────

// Infer element type of an array expression (returns element type string, or "" if unknown)
function inferArrayElemType(arrId: int): string {
    if (arrId <= 0) { return "" }
    const aeKind = nGetKind(arrId)
    if (aeKind == "IDENT") {
        const aeType = getVarType(nGetS1(arrId))
        const ltIdx = aeType.indexOf("<")
        if (ltIdx >= 0 && aeType.length() > ltIdx + 2) {
            return aeType.substring(ltIdx + 1, aeType.length() - ltIdx - 2)
        }
    }
    if (aeKind == "METHOD_CALL") {
        const aeMethod = nGetS1(arrId)
        if (aeMethod == "split") { return "string" }
        if (aeMethod == "filter" || aeMethod == "slice" || aeMethod == "reverse" || aeMethod == "sort") {
            return inferArrayElemType(nGetI1(arrId))
        }
    }
    // I021-requestbody-nested-array — MEMBER_ACCESS Array<T>.field elem type;缺此 → `arr[i].field` ss_arrayGet i64 不 cast 至 ptr,user class elem 字段访问失败
    if (aeKind == "MEMBER_ACCESS") {
        const moc = resolveObjClass(nGetI1(arrId))
        if (moc == "") { return "" }
        const fKey = `${moc}.${nGetS1(arrId)}`
        if (classFieldTypes.has(fKey) == 1) { return extractContainerElemType(classFieldTypes.getString(fKey)) }
    }
    return ""
}

// Resolve the CLASS name of an expression (returns class name or "")
function resolveObjClass(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    // Variable → check varType for class name
    if (kind == "IDENT") {
        const vt = getVarType(nGetS1(nodeId))
        // D082: Ref<T> type
        if (vt.startsWith("Ref<") == 1) { return "Ref" }
        // D082 Phase 2: Thread<T> type
        if (vt.startsWith("Thread<") == 1) { return "Thread" }
        // D082 Phase 4: Channel<T> type
        if (vt.startsWith("Channel<") == 1) { return "Channel" }
        if (vt != "" && classFields.has(vt) == 1) { return vt }
        if (vt != "" && ifaceMethodsCG.has(vt) == 1) { return vt }
        const oc = getObjClass(nGetS1(nodeId))
        if (oc != "") { return oc }
        // Class name used as static method target (e.g., JSON.create())
        if (classFields.has(nGetS1(nodeId)) == 1) { return nGetS1(nodeId) }
        return ""
    }
    // this → current class
    if (kind == "THIS" && currentClassName != "") { return currentClassName }
    // super → parent class
    if (kind == "SUPER" && currentClassName != "" && classParents.has(currentClassName) == 1) {
        return classParents.getString(currentClassName)
    }
    // new ClassName() → class name directly (mangled for generic classes)
    if (kind == "NEW_EXPR") {
        const neCn = resolveCtTypeAlias(nGetS1(nodeId))
        if (genericClassNodes.has(neCn) == 1) { return inferGenericClassName(neCn, nGetList(nodeId), nGetS2(nodeId)) }
        return neCn
    }
    // Function call → check return type
    if (kind == "CALL") {
        const callee = nGetS1(nodeId)
        if (callee == "ref") { return "Ref" }
        if (funcRetTypes.has(callee) == 1) {
            const rt = funcRetTypes.getString(callee)
            if (classFields.has(rt) == 1) { return rt }
            if (ifaceMethodsCG.has(rt) == 1) { return rt }
        }
        return ""
    }
    // Method call → recursively resolve object, then look up method return type
    if (kind == "METHOD_CALL") {
        const rt = inferType(nodeId)
        if (classFields.has(rt) == 1) { return rt }
        if (ifaceMethodsCG.has(rt) == 1) { return rt }
        return ""
    }
    // as cast → target class
    if (kind == "BINARY" && nGetS1(nodeId) == "As") {
        return nGetS1(nGetI2(nodeId))
    }
    // Index access → resolve array element type as class
    if (kind == "INDEX_ACCESS") {
        const iaElem = inferArrayElemType(nGetI1(nodeId))
        if (iaElem != "" && classFields.has(iaElem) == 1) { return iaElem }
        if (iaElem != "" && ifaceMethodsCG.has(iaElem) == 1) { return iaElem }
        return ""
    }
    // Member access → resolve object class, look up field type
    if (kind == "MEMBER_ACCESS") {
        // D078: Static field → resolve type as class name
        if (nGetKind(nGetI1(nodeId)) == "IDENT") {
            const sfKey = `${nGetS1(nGetI1(nodeId))}.${nGetS1(nodeId)}`
            if (staticFieldTypes.has(sfKey) == 1) {
                const sfType = staticFieldTypes.getString(sfKey)
                if (classFields.has(sfType) == 1) { return sfType }
                return ""
            }
        }
        const objClass = resolveObjClass(nGetI1(nodeId))
        if (objClass != "") {
            const iacKey = `${objClass}.${nGetS1(nodeId)}`
            if (classAccessorGetters.has(iacKey) == 1) {
                const iacRet = getAccessorRetType(objClass, nGetS1(nodeId))
                if (iacRet != "" && classFields.has(iacRet) == 1) { return iacRet }
                return ""
            }
            const fType = classFieldTypes.getString(`${objClass}.${nGetS1(nodeId)}`)
            if (fType != "" && classFields.has(fType) == 1) { return fType }
        }
        return ""
    }
    return ""
}

function inferType(id: int): string {
    if (id <= 0) { return "int" }
    const kind = nGetKind(id)
    if (kind == "INT_LIT") { return "int" }
    if (kind == "DOUBLE_LIT") { return "double" }
    if (kind == "STRING_LIT") { return "string" }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }
    if (kind == "NULL_LIT") { return "ptr" }
    if (kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "THIS") {
        if (currentClassName != "") { return currentClassName }
        return "ptr"
    }
    if (kind == "SUPER") {
        if (currentClassName != "" && classParents.has(currentClassName) == 1) {
            return classParents.getString(currentClassName)
        }
        return "ptr"
    }
    // COMPTIME_EXPR: evaluate once, cache type+literal for genExpr.
    // Side effects (flushComptimeSS/IR) are intentional — inferType is the earliest
    // point where the type is needed, and cache prevents double execution.
    if (kind == "COMPTIME_EXPR") {
        const ceKey = `${id}`
        if (comptimeExprType.has(ceKey) == 1) { return comptimeExprType.getString(ceKey) }
        const ceRetVal = runComptimeBlockBody(nGetI1(id))
        flushComptimeSS()
        flushComptimeIR()
        if (ceRetVal > 0) {
            const ceType = interpType(ceRetVal)
            if (ceType == "int") {
                comptimeExprType.set(ceKey, "int")
                comptimeExprLiteral.set(ceKey, `${interpAsInt(ceRetVal)}`)
                return "int"
            }
            if (ceType == "double") {
                comptimeExprType.set(ceKey, "double")
                comptimeExprLiteral.set(ceKey, interpAsStr(ceRetVal))
                return "double"
            }
            if (ceType == "string") {
                const ceStr = interpAsStr(ceRetVal)
                const ceConst = addStringConst(ceStr)
                comptimeExprType.set(ceKey, "string")
                comptimeExprLiteral.set(ceKey, ceConst)
                return "string"
            }
            // SS bool is i32 at IR level
            if (ceType == "bool") {
                comptimeExprType.set(ceKey, "int")
                comptimeExprLiteral.set(ceKey, `${tvIntOf(ceRetVal)}`)
                return "int"
            }
            // D112: TypeValue literal 存 class 名,外层 VAR_DECL 走 ctVars(消除独立通道)
            if (ceType == "type") {
                const ceClass = tvStringOf(ceRetVal)
                comptimeExprType.set(ceKey, "type")
                comptimeExprLiteral.set(ceKey, ceClass)
                return "type"
            }
            // I014 §路径 A — COMPTIME_EXPR 返 array/object/map 时 literal 存 tvId 字符串,
            // eval_expr.ss 消费侧按 array/object/map type 解回 ctVal(tvId)。gen_decls.ss 对 CONST
            // 绑定走 ctVars,跳过 runtime alloca。route 收集 `const routes = comptime{...return arr}`
            // 与 D120 §A.4 #3 ct-array unroll 入口形成闭环(iter → unroll → body invoke → static call)。
            if (ceType == "array" || ceType == "object" || ceType == "map") {
                comptimeExprType.set(ceKey, ceType)
                comptimeExprLiteral.set(ceKey, `${ceRetVal}`)
                return ceType
            }
        }
        comptimeExprType.set(ceKey, "int")
        comptimeExprLiteral.set(ceKey, "0")
        return "int"
    }
    if (kind == "IDENT") {
        const vType = getVarType(nGetS1(id))
        if (vType != "") { return vType }
        if (funcRetTypes.has(nGetS1(id)) == 1) { return "fn" }
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
        if (op == "As") {
            return nGetS1(nGetI2(id))
        }
        if (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge" || op == "And" || op == "Or" || op == "Instanceof") {
            return "int"
        }
        const binLt = inferType(nGetI1(id))
        const binRt = inferType(nGetI2(id))
        if (binLt == "double" || binRt == "double") { return "double" }
        if (binLt == "i64") { return "int" }
        return binLt
    }
    if (kind == "CALL") {
        const callee = nGetS1(id)
        if (callee == "Map") { return "Map" }
        // D082: ref(val) → Ref<T> where T is inferred from argument
        if (callee == "ref") {
            const refArgList = nGetList(id)
            if (refArgList != "") {
                const refArgType = inferType(parseInt(refArgList.split(",")[0]))
                return `Ref<${refArgType}>`
            }
            return "Ref<int>"
        }
        if (isFnType(getVarType(callee)) == 1 || getVarType(callee) == "i64") {
            // D141 Phase 3 — fn(T):R 结构化时返真实 retType;非结构化退 i64(老兼容)
            const callFnVT = getVarType(callee)
            if (callFnVT.startsWith("fn(") == 1) {
                const callFnRet = extractFnRetType(callFnVT)
                if (callFnRet != "") { return callFnRet }
            }
            return "i64"
        }
        // Generic function: infer return type from arguments
        if (genericFuncNodes.has(callee) == 1) {
            const grt = inferGenericRetType(callee, nGetList(id), nGetS2(id))
            if (grt != "") { return grt }
        }
        // Use funcRetTypes directly — preserves class names
        if (funcRetTypes.has(callee) == 1) {
            return funcRetTypes.getString(callee)
        }
        return callReturnType(callee)
    }
    if (kind == "NEW_EXPR") {
        const newCn = resolveCtTypeAlias(nGetS1(id))
        // D082 Phase 4: new Channel<T>() → Channel<T>
        if (newCn == "Channel") {
            const chanTypeArg = nGetS2(id)
            if (chanTypeArg != "") { return `Channel<${chanTypeArg}>` }
            return "Channel<int>"
        }
        if (genericClassNodes.has(newCn) == 1) { return inferGenericClassName(newCn, nGetList(id), nGetS2(id)) }
        return newCn
    }
    if (kind == "METHOD_CALL") {
        const method = nGetS1(id)
        const mcObj = nGetI1(id)
        // D082 Phase 2: Thread.start(fn) → Thread<T>
        if (method == "start" && nGetKind(mcObj) == "IDENT" && nGetS1(mcObj) == "Thread") {
            const tsArgList = nGetList(id)
            if (tsArgList != "") {
                const tsArgId = parseInt(tsArgList.split(",")[0])
                if (tsArgId > 0 && nGetKind(tsArgId) == "ARROW_FUNC") {
                    return `Thread<${inferArrowRetType(tsArgId)}>`
                }
                // Named function reference
                if (tsArgId > 0 && nGetKind(tsArgId) == "IDENT") {
                    const fnName = nGetS1(tsArgId)
                    if (funcRetTypes.has(fnName) == 1) {
                        return `Thread<${funcRetTypes.getString(fnName)}>`
                    }
                }
            }
            return "Thread<int>"
        }
        // D082 Phase 2: thread.join() → T from Thread<T>
        if (method == "join") {
            const jtType = inferType(mcObj)
            if (jtType.startsWith("Thread<") == 1) {
                return threadElemType(jtType)
            }
        }
        // D082 Phase 4: ch.receive() → T from Channel<T>
        if (method == "receive") {
            const chType = inferType(mcObj)
            if (chType.startsWith("Channel<") == 1) {
                return channelElemType(chType)
            }
        }
        // I019/I020a/I020b/I020c/I021-cartesian — Map<K,V>.get dispatch by V
        // (extractMapValueType returns "" for non-Map). I021-cartesian 扩 bool / Array<X> /
        // Map<K2,V2> 三路:V=非 scalar 容器或 bool 时返 raw V 类型(D130 SSoT 已用 ptrtoint
        // 保证 i64 编码统一,调用方按 V 容器类型走 inttoptr to ptr + 后续容器 method)。
        if (method == "get") {
            // D131 — V=T? strip 后参与下游 scalar / class / 容器分派,miss/null 同 i64 0 → ptr null。
            const mgV = stripNullableCG(extractMapValueType(inferType(mcObj)))
            if (mgV == "string") { return "string" }
            if (mgV == "int") { return "int" }
            if (mgV == "double") { return "double" }
            if (mgV == "bool") { return "bool" }
            if (mgV.startsWith("Array<") == 1 || mgV.startsWith("Map<") == 1) { return mgV }
            // I020c — V=class: return "ClassName?" (D067 Kotlin/Dart T? = TS strict V|undefined,
            // miss 路径 ss_mapGet 返 i64 0 → inttoptr 得 ptr null,用户必须 if (u != null) narrow).
            if (mgV != "" && classFields.has(mgV) == 1) { return mgV + "?" }
        }
        if (enumReady == 1 && nGetKind(mcObj) == "IDENT" && enumDeclNodes.has(nGetS1(mcObj)) == 1) {
            if (method == "values" || method == "names") { return "ptr" }
            if (method == "valueOf") {
                if (enumTypes.has(nGetS1(mcObj)) == 1) { return "string" }
                return "int"
            }
        }
        // D088: obj.fields() returns Array<string>
        if (method == "fields") {
            const fObjClass = resolveObjClass(mcObj)
            if (fObjClass != "" && classFields.has(fObjClass) == 1) {
                return "Array<string>"
            }
        }
        // I014 §路径 A — invoke sentinel:obj class 含 (className, methodName) 字段对组合时,
        // method_call.ss emit `call ptr @<cn>_<mn>(ptr null)` 返 string body(Spring Boot
        // @GetMapping handler 惯例)。inferType 返 "string" 让 gen_calls.ss ssTypeToLLVM
        // 选 ptr,避免 httpResponse(i32 %7) 类型撞错。
        if (method == "invoke") {
            const invokeObjType = resolveObjClass(mcObj)
            if (invokeObjType != "" && classFieldTypes.getString(`${invokeObjType}.className`) == "string" && classFieldTypes.getString(`${invokeObjType}.methodName`) == "string") {
                return "string"
            }
        }
        // Resolve object type FIRST via unified inferType (recursive)
        const objType = resolveObjClass(mcObj)
        // If object is a known class, look up method return type in class chain
        if (objType != "" && objType != "string" && objType != "int" && objType != "double") {
            let lookupClass = objType
            while (lookupClass != "") {
                if (funcRetTypes.has(`${lookupClass}_${method}`) == 1) {
                    return funcRetTypes.getString(`${lookupClass}_${method}`)
                }
                if (classParents.has(lookupClass) == 1) {
                    lookupClass = classParents.getString(lookupClass)
                } else {
                    lookupClass = ""
                }
            }
        }
        // fn field call: obj.field() where field is fn type → returns i64
        if (objType != "" && isFnType(classFieldTypes.getString(`${objType}.${method}`)) == 1) {
            return "i64"
        }
        // Interface method return type lookup
        if (ifaceMethodsCG.has(objType) == 1 && ifaceMethodRets.has(`${objType}.${method}`) == 1) {
            return ifaceMethodRets.getString(`${objType}.${method}`)
        }
        // find() returns the array element type
        if (method == "find") {
            const elemType = inferArrayElemType(nGetI1(id))
            if (elemType != "") { return elemType }
        }
        // Built-in method return types (fallback for string/array/map methods)
        if (methodRetTypes.has(method) == 1) {
            return methodRetTypes.getString(method)
        }
        return "int"
    }
    if (kind == "MEMBER_ACCESS") {
        const mObj = nGetI1(id)
        // D095: STRING_LIT.name → string (cls.name after fold)
        if (nGetKind(mObj) == "STRING_LIT" && nGetS1(id) == "name") { return "string" }
        // D095 / D117 Execute 4 — IDENT 绑定 comptime-loop-string / ctVars-Meta-object 时 Meta .name/.type/.returnType → "string"
        if (nGetKind(mObj) == "IDENT") {
            const mctfk = `${currentFunc}:${nGetS1(mObj)}`
            if ((comptimeConsts.has(nGetS1(mObj)) == 1 || (ctVars.has(mctfk) == 1 && ctInvalidated.has(mctfk) == 0 && interpType(payload(parseInt(ctVars.getString(mctfk)))) == "object")) && (nGetS1(id) == "name" || nGetS1(id) == "type" || nGetS1(id) == "returnType")) { return "string" }
        }
        // D082: Ref<T>.value → element type T
        if (nGetS1(id) == "value" && nGetKind(mObj) == "IDENT") {
            const rvt = getVarType(nGetS1(mObj))
            if (rvt.startsWith("Ref<") == 1) {
                return refElemType(rvt)
            }
        }
        if (nGetKind(mObj) == "IDENT" && enumReady == 1) {
            const eName = nGetS1(mObj)
            const eKey = `${eName}.${nGetS1(id)}`
            if (enumValues.has(eKey) == 1) {
                if (enumTypes.has(eName) == 1) { return "string" }
                return "int"
            }
        }
        // D078: Static field type inference
        if (nGetKind(mObj) == "IDENT") {
            const sfKey = `${nGetS1(mObj)}.${nGetS1(id)}`
            if (staticFieldTypes.has(sfKey) == 1) {
                return staticFieldTypes.getString(sfKey)
            }
        }
        const mField = nGetS1(id)
        let maClassName = resolveObjClass(mObj)
        // D096: accessor getter retType wins over field type (TS/JS semantics
        // forbid same-name coexistence).
        if (maClassName != "") {
            const maAccRet = getAccessorRetType(maClassName, mField)
            if (maAccRet != "") { return maAccRet }
        }
        if (maClassName != "" && classFieldTypes.has(`${maClassName}.${mField}`) == 1) {
            return classFieldTypes.getString(`${maClassName}.${mField}`)
        }
        return "int"
    }
    if (kind == "GROUPING") { return inferType(nGetI1(id)) }
    if (kind == "UNARY") { return inferType(nGetI1(id)) }
    if (kind == "TERNARY") { return inferType(nGetI2(id)) }
    if (kind == "ARRAY_LIT") { return "ptr" }
    if (kind == "ARROW_FUNC") { return "fn" }
    if (kind == "INDEX_ACCESS") {
        // D088: obj[name] bracket notation on class instance
        // D095: idx can also be f.name where f is comptimeConsts-bound
        const iaIdxNode = nGetI2(id)
        if (isCtStringIdx(iaIdxNode) == 1) {
            const iaObjClass = resolveObjClass(nGetI1(id))
            if (iaObjClass != "" && classFields.has(iaObjClass) == 1) {
                const iaFieldName = resolveCtString(iaIdxNode)
                if (classFieldTypes.has(`${iaObjClass}.${iaFieldName}`) == 1) {
                    return classFieldTypes.getString(`${iaObjClass}.${iaFieldName}`)
                }
            }
        }
        const tElem = inferTupleIndexType(id)
        if (tElem != "") { return tElem }
        const iaElem = inferArrayElemType(nGetI1(id))
        if (iaElem != "") { return iaElem }
        return "i64"
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { return "int" }
    if (kind == "SPREAD_ELEM") { return inferType(nGetI1(id)) }
    if (kind == "NAMED_ARG") { return inferType(nGetI1(id)) }
    return "int"
}

function preludeName(cName: string): string {
    const pName = `_${cName}`
    if (funcRetTypes.has(pName) == 1) { return pName }
    return cName
}

function callReturnType(callee: string): string {
    if (funcRetTypes.has(callee) == 1) {
        return funcRetTypes.getString(callee)
    }
    return "int"
}

// Infer concrete return type for a generic function call
function inferGenericRetType(callee: string, argList: string, explicitTypes: string): string {
    if (genericFuncNodes.has(callee) == 0) { return "" }
    const funcNodeId = parseInt(genericFuncNodes.getString(callee))
    const declRet = nGetS2(funcNodeId)
    if (declRet == "") { return "void" }
    const typeParams = nGetS3(funcNodeId)
    // If return type is not a type param, return it directly
    let isRetTP = 0
    const tpParts = typeParams.split(",")
    for (tpp in tpParts) {
        if (tpp == declRet) { isRetTP = 1 }
    }
    if (isRetTP == 0) { return declRet }
    // Explicit type args: resolve directly
    if (explicitTypes != "") {
        let tpIdx = 0
        for (tpp in tpParts) {
            if (tpp == declRet) { return listGet(explicitTypes, tpIdx) }
            tpIdx = tpIdx + 1
        }
        return "int"
    }
    // Match declared params to actual args to resolve type params
    const declParams = nGetList(funcNodeId)
    if (declParams == "" || argList == "") { return "int" }
    const dParts = declParams.split(",")
    const aParts = argList.split(",")
    let argIdx = 0
    for (dp in dParts) {
        const pId = parseInt(dp)
        if (pId <= 0 || nGetKind(pId) != "PARAM") { continue }
        const pType = nGetS2(pId)
        if (pType == declRet) {
            let ai = 0
            for (ap in aParts) {
                if (ai == argIdx) { return inferType(parseInt(ap)) }
                ai = ai + 1
            }
        }
        argIdx = argIdx + 1
    }
    return "int"
}

// Infer mangled class name for a generic class instantiation (e.g., "Box" + [42] → "Box_i")
function inferGenericClassName(className: string, argList: string, explicitTypes: string): string {
    if (genericClassNodes.has(className) == 0) { return className }
    const classNodeId = parseInt(genericClassNodes.getString(className))
    const typeParamStr = classTypeParams(classNodeId)
    const typeParamList = typeParamStr.split(",")
    const declFields = classFieldList(classNodeId)
    const subs = Map()
    if (explicitTypes != "") {
        let tpIdx = 0
        for (tp in typeParamList) {
            subs.set(tp, listGet(explicitTypes, tpIdx))
            tpIdx = tpIdx + 1
        }
    } else if (declFields != "" && argList != "") {
        const fParts = declFields.split(",")
        const aParts = argList.split(",")
        let argIdx = 0
        for (fp in fParts) {
            const pId = parseInt(fp)
            if (pId <= 0 || nGetKind(pId) != "PARAM") { continue }
            const pType = nGetS2(pId)
            let isTP = 0
            for (tp in typeParamList) { if (tp == pType) { isTP = 1 } }
            if (isTP == 1 && subs.has(pType) == 0) {
                let ai = 0
                for (ap in aParts) {
                    if (ai == argIdx) { subs.set(pType, inferType(parseInt(ap))) }
                    ai = ai + 1
                }
            }
            argIdx = argIdx + 1
        }
    }
    let mangledSig = ""
    for (tp in typeParamList) {
        if (subs.has(tp) == 1) {
            if (mangledSig != "") { mangledSig = `${mangledSig}_` }
            mangledSig = `${mangledSig}${typeSig(subs.getString(tp))}`
        }
    }
    const mangledName = mangledSig != "" ? `${className}_${mangledSig}` : className
    // Ensure Maps are pre-registered so ssTypeToLLVM etc. recognize the mangled name
    if (classFields.has(mangledName) == 0) {
        preRegisterSpecializedClass(classNodeId, mangledName, subs)
    }
    return mangledName
}

// ── Type helpers ──────────────────────────────────────────────

// Resolve generic type param via active substitution map (e.g., "T" → "int")
function resolveTypeParam(t: string): string {
    if (genericTypeSubs.has(t) == 1) { return genericTypeSubs.getString(t) }
    return t
}

function ssTypeToLLVM(t: string): string {
    // Generic type param substitution (active during specialization)
    if (genericTypeSubs.has(t) == 1) { return ssTypeToLLVM(genericTypeSubs.getString(t)) }
    // Nullable types (T?) → always ptr (D067)
    if (t.length() > 1 && t.charAt(t.length() - 1) == "?") { return "ptr" }
    if (t == "int" || t == "bool" || t == "auto" || t == "") { return "i32" }
    if (t == "double") { return "double" }
    if (t == "string") { return "ptr" }
    if (t == "void") { return "void" }
    if (t == "ptr") { return "ptr" }
    if (isFnType(t) == 1) { return "i64" }
    if (t == "i64") { return "i64" }
    // Generic types (Array<string>, Map<string,int>, etc.) → ptr
    if (t.contains("<") == 1) { return "ptr" }
    // Interface type names → ptr
    if (ifaceMethodsCG.has(t) == 1) { return "ptr" }
    // Class type names → ptr (includes Map, registered as built-in class)
    if (classFields.has(t) == 1) { return "ptr" }
    // Generic type params (single uppercase letter like T, U, V) → ptr (erased)
    if (t.length() == 1 && charCodeAt(t, 0) >= 65 && charCodeAt(t, 0) <= 90) { return "ptr" }
    return "i32"
}

// Strip nullable suffix — codegen treats T? same as T (D067: nullability is checker-only)
function stripNullableCG(t: string): string {
    if (t.length() > 1 && t.charAt(t.length() - 1) == "?") {
        return t.substring(0, t.length() - 1)
    }
    return t
}

function setVarType(name: string, varType: string) {
    varTypes.set(`${currentFunc}:${name}`, stripNullableCG(varType))
}

function getVarType(name: string): string {
    const scopedKey = `${currentFunc}:${name}`
    if (varTypes.has(scopedKey) == 1) {
        return varTypes.getString(scopedKey)
    }
    const globalKey = `:${name}`
    if (varTypes.has(globalKey) == 1) {
        return varTypes.getString(globalKey)
    }
    return ""
}

// ── D141 Phase 2.2: fn 类型判断 helper ─────────────────────────
// "fn" 单字符串 / "fn(T1,T2):R" 结构化签名 — 统一判定接口
// (lib/spring fn-typed PARAM / fn-typed local var / fn-typed class field 等检查全部走此 helper)
function isFnType(t: string): int {
    if (t == "fn") { return 1 }
    if (t.startsWith("fn(") == 1) { return 1 }
    return 0
}

// ── D141 Phase 2.2: lambda 反推 helper ─────────────────────────
// 从 fn(T1,T2,...):R 结构化签名提取第 idx 个形参类型;非结构化 / 索引越界返 ""。
// 简化版:不支持嵌套 fn(fn(T):R):R(D141 主线场景 setter: fn(PreparedStatement):void 不嵌套)。
function extractFnParamType(fnSig: string, idx: int): string {
    if (fnSig.startsWith("fn(") == 0) { return "" }
    const rparenIdx = fnSig.indexOf(")")
    if (rparenIdx < 0) { return "" }
    const paramStr = fnSig.substring(3, rparenIdx - 3)
    if (paramStr == "") { return "" }
    const types = paramStr.split(",")
    let i = 0
    for (t in types) {
        if (i == idx) { return t }
        i = i + 1
    }
    return ""
}

// D141 Phase 3 — 提取 fn(T1,T2):R 中的 R(retType);非结构化 / 缺 ":R" 返 ""。
function extractFnRetType(fnSig: string): string {
    if (fnSig.startsWith("fn(") == 0) { return "" }
    const rparenIdx = fnSig.indexOf(")")
    if (rparenIdx < 0) { return "" }
    if (fnSig.length() < rparenIdx + 3) { return "" }
    return fnSig.substring(rparenIdx + 2, fnSig.length() - rparenIdx - 2)
}

// 反推回填 ARROW_FUNC PARAM s2:查 funcParamTypes[`${typeCallee}:${argIdx}`] 拿到 callee
// PARAM 类型,若结构化签名(fn(...))则 extractFnParamType 提取 Pi 反填 ARROW_FUNC PARAM
// s2;H6 显式优先(已有 s2 不覆盖);H13 非结构化 callee skip(不破现有 setter: fn 路径)。
// D141 Phase 3 — 同步反推 ARROW_FUNC retT(slot s2 of arrow node)从 callee `fn(...):R`
// 提取 R 回填,gen_arrows.ss:109 默认 "int" 破裂修正。
function inferArrowFuncParams(argId: int, typeCallee: string, argIdx: int) {
    if (nGetKind(argId) != "ARROW_FUNC") { return }
    const ptKey = `${typeCallee}:${argIdx}`
    if (funcParamTypes.has(ptKey) == 0) { return }
    const calleeParamType = funcParamTypes.getString(ptKey)
    if (calleeParamType.startsWith("fn(") == 0) { return }  // H13: 非结构化 skip
    const arrowParamList = nGetList(argId)
    if (arrowParamList != "") {
        const arrParts = arrowParamList.split(",")
        let pi = 0
        for (apId in arrParts) {
            const aPid = parseInt(apId)
            if (aPid > 0 && nGetKind(aPid) == "PARAM") {
                if (nGetS2(aPid) == "") {  // H6 显式优先
                    const inferredType = extractFnParamType(calleeParamType, pi)
                    if (inferredType != "") {
                        nSetS2(aPid, inferredType)
                    }
                }
                pi = pi + 1
            }
        }
    }
    if (nGetS2(argId) == "") {  // H6 显式优先 — ARROW_FUNC retT 反推
        const inferredRet = extractFnRetType(calleeParamType)
        if (inferredRet != "") {
            nSetS2(argId, inferredRet)
        }
    }
}

// ── D142 Phase 2: array literal contextual typing helper ──────
// 从 "Array<T>" / "List<T>" / "Tuple<T>" 提取 T;非 array 容器(Map<K,V> / fn(...) / 类名等)返 ""。
// Array/List/Tuple 白名单是 H13 失败硬错粒度的关键 — 不能与 checker/check_types.ss extractElemType
// 合并(后者无白名单,会误从 Map<int> 提 int / 从 fn(int):int 提 int):int 等语义错配)。
function extractArrayElemType(arrType: string): string {
    if (arrType == "") { return "" }
    const ltIdx = arrType.indexOf("<")
    if (ltIdx <= 0) { return "" }
    if (arrType.length() < ltIdx + 3) { return "" }
    const aBase = arrType.substring(0, ltIdx)
    if (aBase != "Array" && aBase != "List" && aBase != "Tuple") { return "" }
    return arrType.substring(ltIdx + 1, arrType.length() - ltIdx - 2)
}

// D142 Phase 2: ARRAY_LIT 反推回填 nSetS2 — 查 funcParamTypes[typeCallee:argIdx] 拿
// callee PARAM 结构化签名 Array<T>,extractArrayElemType 提取 T 反填 ARRAY_LIT 节点
// nSetS2(参 D141 inferArrowFuncParams 同模式;H6 显式优先 — 已有 nSetS2 不覆盖;
// H13 非结构化 callee skip 不破现有 "Array" 单一字符串调用方)。
function inferArrayLitElems(argId: int, typeCallee: string, argIdx: int) {
    if (argId <= 0) { return }
    if (nGetKind(argId) != "ARRAY_LIT") { return }
    if (nGetS2(argId) != "") { return }
    const ptKey = `${typeCallee}:${argIdx}`
    if (funcParamTypes.has(ptKey) == 0) { return }
    const calleeParamType = funcParamTypes.getString(ptKey)
    const elemType = extractArrayElemType(calleeParamType)
    if (elemType == "") { return }
    nSetS2(argId, elemType)
}

// ── Method overloading: type signature ───────────────────────

function typeSig(ssType: string): string {
    const st = stripNullableCG(ssType)
    if (genericTypeSubs.has(st) == 1) { return typeSig(genericTypeSubs.getString(st)) }
    if (st == "int" || st == "bool" || st == "auto" || st == "") { return "i" }
    if (st == "double") { return "d" }
    if (st == "string") { return "s" }
    // D141 Phase 2.1: fn 结构化签名 fn(T1,T2):R 压缩为 "f"(与 fn 单字符串同 mangled,
    // 避免 mangled name 含特殊字符破 LLVM IR 命名;后续如需 fn(T) vs fn(string) 区分重载再细化)
    if (st == "fn" || st.startsWith("fn(") == 1) { return "f" }
    if (st == "void") { return "v" }
    if (st.contains("<") == 1) { return "p" }
    // Class name → use full name
    return st
}

function paramSig(paramList: string): string {
    if (paramList == "") { return "" }
    let sig = ""
    const parts = paramList.split(",")
    for (p in parts) {
        const pId = parseInt(p)
        if (pId > 0 && nGetKind(pId) == "PARAM") {
            if (sig != "") { sig = `${sig}_` }
            sig = `${sig}${typeSig(nGetS2(pId))}`
        }
    }
    return sig
}

function argsSig(argList: string): string {
    if (argList == "") { return "" }
    let sig = ""
    const parts = argList.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) {
            const aType = inferType(argId)
            if (sig != "") { sig = `${sig}_` }
            // For IDENT with class type, use class name
            if (nGetKind(argId) == "IDENT") {
                const objClass = getObjClass(nGetS1(argId))
                if (objClass != "") {
                    sig = `${sig}${objClass}`
                    continue
                }
            }
            if (nGetKind(argId) == "NEW_EXPR") {
                sig = `${sig}${nGetS1(argId)}`
                continue
            }
            sig = `${sig}${typeSig(aType)}`
        }
    }
    return sig
}

function resolveOverload(baseName: string, argList: string): string {
    // Only resolve overloads for functions with multiple signatures
    if (overloadReady == 0) { return baseName }
    if (overloadCount.has(baseName) == 0) { return baseName }
    if (parseInt(overloadCount.getString(baseName)) <= 1) { return baseName }
    // This function IS overloaded — find the right signature
    const sig = argsSig(argList)
    if (sig != "") {
        const mangled = `${baseName}_${sig}`
        if (funcRetTypes.has(mangled) == 1) { return mangled }
    }
    return baseName
}
