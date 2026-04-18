// gen_exprs.ss — Expression codegen: dispatcher, simple handlers, binary ops, ternary, string conversion
// Function calls in gen_calls.ss, method calls in gen_methods.ss.

import { genCall, genTemplateLit, genArrowFunc, flushArrowDefs, genArrayLit } from "./gen_calls"
import { genMethodCall, genOptionalMethodCall, resolveSuperParent } from "./gen_methods"
import { interpNewInt, interpNewDouble, interpNewString, interpNewBool, interpNewNull, interpNewVal, interpNewArray, interpArrayPush, interpArrayGet, interpNewMap, interpType, interpAsInt, interpAsStr, interpAsBool, interpToStr, interpTruthy, interpGetField, interpSetField, interpFindMethod, interpCollectFields, interpCtFieldsArray, interpCheckLoopExit, interpCompoundOp, interpValEquals, interpMapSet, interpMapGet, interpMapHas, interpMapDelete, interpMapGetKeys, interpMapGetSize } from "./interp"
import { interpBuildTypeInfo } from "./gen_reflect"

// ── Simple expression handlers ──────────────────────────────────

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

// D095: resolve a node to its compile-time string value, honoring:
//   STRING_LIT             → nGetS1
//   IDENT in comptimeConsts → bound value (loop var)
//   IDENT.name where IDENT in comptimeConsts → bound value (FieldMeta.name)
// Returns 1 if resolvable, else 0. Companion resolveCtString returns the string.
function isCtStringIdx(nodeId: int): int {
    const k = nGetKind(nodeId)
    if (k == "STRING_LIT") { return 1 }
    if (k == "IDENT" && comptimeConsts.has(nGetS1(nodeId)) == 1) { return 1 }
    if (k == "MEMBER_ACCESS" && nGetS1(nodeId) == "name") {
        const mObj = nGetI1(nodeId)
        const mk = nGetKind(mObj)
        if (mk == "STRING_LIT") { return 1 }
        if (mk == "IDENT" && comptimeConsts.has(nGetS1(mObj)) == 1) { return 1 }
    }
    return 0
}

function resolveCtString(nodeId: int): string {
    const k = nGetKind(nodeId)
    if (k == "STRING_LIT") { return nGetS1(nodeId) }
    if (k == "IDENT") { return comptimeConsts.getString(nGetS1(nodeId)) }
    if (k == "MEMBER_ACCESS") {
        const mObj = nGetI1(nodeId)
        if (nGetKind(mObj) == "STRING_LIT") { return nGetS1(mObj) }
        return comptimeConsts.getString(nGetS1(mObj))
    }
    return ""
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

function comptimeError(msg: string, nodeId: int): int {
    println(`error: [comptime] ${msg} at line ${nGetLine(nodeId)}:${nGetCol(nodeId)}`)
    exit(1)
    return ctVal(interpNewNull())
}

// ── Expression dispatcher ───────────────────────────────────────

function genVal(id: int): int {
    if (id <= 0) { return constVal("0") }
    const kind = nGetKind(id)
    if (kind == "INT_LIT") { return ctVal(interpNewInt(parseInt(nGetS1(id)))) }
    if (kind == "STRING_LIT") { return ctVal(interpNewString(nGetS1(id))) }
    if (kind == "TRUE_LIT") { return ctVal(interpNewBool(1)) }
    if (kind == "FALSE_LIT") { return ctVal(interpNewBool(0)) }
    if (kind == "NULL_LIT") { return ctVal(interpNewNull()) }
    if (kind == "DOUBLE_LIT") { return ctVal(interpNewDouble(parseDouble(nGetS1(id)))) }
    if (kind == "BINARY") { return genValBinary(id) }
    if (kind == "UNARY") { return genValUnary(id) }
    if (kind == "GROUPING") { return genVal(nGetI1(id)) }
    if (kind == "TERNARY") { return genValTernary(id) }
    if (kind == "IDENT") {
        const ctIdName = nGetS1(id)
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
        return constVal(genIdent(id))
    }
    if (kind == "THIS" || kind == "SUPER") {
        if (comptimeDepth > 0) {
            if (interpThisVal > 0) { return ctVal(interpThisVal) }
            return ctVal(interpNewNull())
        }
        return constVal(genThisExpr())
    }
    if (kind == "POSTFIX_INC") {
        if (comptimeDepth > 0) {
            const piName = nGetS1(id)
            let piKey = ""
            if (ctScopeStack.length() > 0) {
                let piSi = ctScopeStack.length() - 1
                while (piSi >= 0) {
                    const piSk = `${ctScopeStack[piSi]}:${piName}`
                    if (ctVars.has(piSk) == 1) { piKey = piSk; break }
                    piSi = piSi - 1
                }
            }
            if (piKey == "") {
                const piFk = `${currentFunc}:${piName}`
                if (ctVars.has(piFk) == 1) { piKey = piFk }
            }
            if (piKey != "") {
                const piTagged = parseInt(ctVars.getString(piKey))
                if (isCt(piTagged) == 1) {
                    const piOld = payload(piTagged)
                    ctVars.set(piKey, `${ctVal(interpNewInt(interpAsInt(piOld) + 1))}`)
                    return ctVal(piOld)
                }
            }
            return ctVal(interpNewNull())
        }
        return constVal(genPostfixExpr(id))
    }
    if (kind == "COMPTIME_EXPR") {
        if (comptimeDepth > 0) { return comptimeError("nested comptime expression", id) }
        inferType(id)
        return constVal(comptimeExprLiteral.getString(`${id}`))
    }
    if (kind == "CALL") {
        const callName = nGetS1(id)
        const callArgList = nGetList(id)
        if (genericFuncNodes.has(callName) == 1) {
            if (comptimeDepth > 0) {
                if (ctFuncNodes.has(callName) == 0) {
                    ctFuncNodes.set(callName, genericFuncNodes.getString(callName))
                }
            } else {
                return constVal(genGenericCall(id, callName, callArgList))
            }
        }
        const savedCallPreRegs = callPreRegs
        callPreRegs = new Map()
        let callCtArgVals: Array<string> = []
        let callCtNamedArgs = new Map()
        let callCtHasNamed = 0
        if (callArgList != "") {
            const callArgParts = callArgList.split(",")
            for (cap in callArgParts) {
                const callArgId = parseInt(cap)
                if (callArgId > 0) {
                    if (nGetKind(callArgId) == "NAMED_ARG") {
                        callCtHasNamed = 1
                        const nav = genVal(nGetI1(callArgId))
                        if (isCt(nav) == 1) {
                            callCtNamedArgs.set(nGetS1(callArgId), `${payload(nav)}`)
                        } else {
                            callCtNamedArgs.set(nGetS1(callArgId), `${interpNewNull()}`)
                            callPreRegs.set(`${callArgId}`, reg(nav))
                        }
                    } else if (nGetKind(callArgId) == "SPREAD_ELEM") {
                        const srcVal = genVal(nGetI1(callArgId))
                        if (isCt(srcVal) == 1) {
                            const srcPayload = payload(srcVal)
                            if (interpType(srcPayload) != "array") {
                                if (comptimeDepth > 0) {
                                    println(`error: [comptime] cannot spread non-array value at line ${nGetLine(callArgId)}:${nGetCol(callArgId)}`)
                                    exit(1)
                                }
                                callPreRegs.set(`${nGetI1(callArgId)}`, reg(srcVal))
                            } else {
                                const srcLen = interpArrayLen(srcPayload)
                                let srcI = 0
                                while (srcI < srcLen) {
                                    const srcElemId = interpArrayGet(srcPayload, srcI)
                                    if (srcElemId > 0) { callCtArgVals = callCtArgVals.push(`${srcElemId}`) }
                                    srcI = srcI + 1
                                }
                            }
                        } else {
                            if (comptimeDepth > 0) {
                                println(`error: [comptime] cannot spread runtime value at line ${nGetLine(callArgId)}:${nGetCol(callArgId)}`)
                                exit(1)
                            }
                            callPreRegs.set(`${nGetI1(callArgId)}`, reg(srcVal))
                        }
                    } else {
                        const av = genVal(callArgId)
                        if (isCt(av) == 1) {
                            callCtArgVals = callCtArgVals.push(`${payload(av)}`)
                        } else {
                            callCtArgVals = callCtArgVals.push(`${interpNewNull()}`)
                            callPreRegs.set(`${callArgId}`, reg(av))
                        }
                    }
                }
            }
        }
        if (comptimeDepth > 0) {
            callPreRegs = savedCallPreRegs
            return ctCallDispatch(id, callName, callCtArgVals, callCtNamedArgs, callCtHasNamed)
        }
        const callResult = constVal(genCall(id))
        callPreRegs = savedCallPreRegs
        return callResult
    }
    if (kind == "NEW_EXPR") {
        const newClassName = nGetS1(id)
        if (genericClassNodes.has(newClassName) == 1) {
            if (comptimeDepth > 0) {
                if (interpClasses.has(newClassName) == 0) {
                    interpClasses.set(newClassName, genericClassNodes.getString(newClassName))
                }
            } else {
                return constVal(genGenericNewExpr(id, newClassName))
            }
        }
        if (newClassName == "Map" || newClassName == "Set") {
            if (comptimeDepth > 0) { return ctVal(interpNewMap()) }
            return constVal(genNewExpr(id))
        }
        const savedNewPreRegs = callPreRegs
        callPreRegs = new Map()
        let newCtArgVals: Array<string> = []
        let newCtNamedArgs = new Map()
        const newArgList = nGetList(id)
        if (newArgList != "") {
            const newArgParts = newArgList.split(",")
            for (nap in newArgParts) {
                const newArgId = parseInt(nap)
                if (newArgId > 0) {
                    if (nGetKind(newArgId) == "NAMED_ARG") {
                        const nav = genVal(nGetI1(newArgId))
                        if (isCt(nav) == 1) {
                            newCtNamedArgs.set(nGetS1(newArgId), `${payload(nav)}`)
                        } else {
                            newCtNamedArgs.set(nGetS1(newArgId), `${interpNewNull()}`)
                            callPreRegs.set(`${nGetI1(newArgId)}`, reg(nav))
                        }
                    } else {
                        const av = genVal(newArgId)
                        if (isCt(av) == 1) {
                            newCtArgVals = newCtArgVals.push(`${payload(av)}`)
                        } else {
                            newCtArgVals = newCtArgVals.push(`${interpNewNull()}`)
                            callPreRegs.set(`${newArgId}`, reg(av))
                        }
                    }
                }
            }
        }
        if (comptimeDepth > 0) {
            callPreRegs = savedNewPreRegs
            return ctNewExprDispatch(newClassName, newCtArgVals, newCtNamedArgs)
        }
        const newResult = constVal(genNewExpr(id))
        callPreRegs = savedNewPreRegs
        return newResult
    }
    if (kind == "MEMBER_ACCESS") {
        const member = nGetS1(id)
        const objNode = nGetI1(id)
        // D095 FieldMeta: f.name / f.type when f is a for-in-unroll bound comptime const
        if (nGetKind(objNode) == "IDENT" && comptimeConsts.has(nGetS1(objNode)) == 1) {
            const fmName = nGetS1(objNode)
            if (member == "name") {
                const nmStr = comptimeConsts.getString(fmName)
                if (comptimeDepth > 0) { return ctVal(interpNewString(nmStr)) }
                return constVal(addStringConst(nmStr))
            }
            if (member == "type") {
                const fmClsKey = `${fmName}.__class`
                if (comptimeConsts.has(fmClsKey) == 1) {
                    const fmCls = comptimeConsts.getString(fmClsKey)
                    const fmFld = comptimeConsts.getString(fmName)
                    if (classFieldTypes.has(`${fmCls}.${fmFld}`) == 1) {
                        const tStr = classFieldTypes.getString(`${fmCls}.${fmFld}`)
                        if (comptimeDepth > 0) { return ctVal(interpNewString(tStr)) }
                        return constVal(addStringConst(tStr))
                    }
                }
            }
        }
        if (nGetKind(objNode) == "IDENT") {
            const eName = nGetS1(objNode)
            const enumKey = `${eName}.${member}`
            if (interpEnumValues.has(enumKey) == 1) {
                if (interpEnumTypes.has(eName) == 1) {
                    return ctVal(interpNewString(interpEnumValues.getString(enumKey)))
                }
                return ctVal(interpNewInt(parseInt(interpEnumValues.getString(enumKey))))
            }
            if (enumReady == 1 && enumValues.has(enumKey) == 1) {
                if (enumTypes.has(eName) == 1) {
                    return ctVal(interpNewString(enumValues.getString(enumKey)))
                }
                return ctVal(interpNewInt(parseInt(enumValues.getString(enumKey))))
            }
            if (comptimeDepth == 0 && getVarType(eName) == "" && classFields.has(eName) == 1) {
                return constVal(genMemberAccess(id))
            }
        }
        const obj = genVal(objNode)
        if (isCt(obj) == 1) {
            const objPayload = payload(obj)
            if (interpType(objPayload) == "object") {
                return ctVal(interpGetField(objPayload, member))
            }
            if (member == "length" && interpType(objPayload) == "string") {
                return ctVal(interpNewInt(interpAsStr(objPayload).length()))
            }
            if (member == "length" && interpType(objPayload) == "array") {
                const items = interpAsStr(objPayload)
                if (items == "") { return ctVal(interpNewInt(0)) }
                return ctVal(interpNewInt(items.split(",").length()))
            }
            // string / TypeValue 都当作 class 句柄,支持 .name / .fields 属性式访问
            const mpKind = interpType(objPayload)
            if (member == "name" && (mpKind == "string" || mpKind == "type")) {
                if (mpKind == "type") { return ctVal(interpNewString(interpAsStr(objPayload))) }
                return obj
            }
            if (member == "fields" && (mpKind == "string" || mpKind == "type")) {
                const clsName = interpAsStr(objPayload)
                if (isKnownClass(clsName) == 1) {
                    return ctVal(interpCtFieldsArray(clsName))
                }
            }
        }
        if (comptimeDepth > 0) {
            return comptimeError(`cannot access field '${member}' on ${isCt(obj) == 1 ? interpType(payload(obj)) : "runtime"} value`, id)
        }
        if (nGetI3(id) > 0) { return constVal(genOptionalMemberAccess(id, reg(obj))) }
        return constVal(genMemberAccess(id, reg(obj)))
    }
    if (kind == "METHOD_CALL") {
        pendingSuperParent = resolveSuperParent(nGetI1(id), id)
        const mcMethod = nGetS1(id)
        const mcObjNode = nGetI1(id)
        if (nGetKind(mcObjNode) == "IDENT") {
            const mcObjName = nGetS1(mcObjNode)
            if (comptimeDepth > 0 && interpEnumNodes.has(mcObjName) == 1) {
                if (mcMethod == "values") { return ctVal(ctEnumListMethod(mcObjName, 0)) }
                if (mcMethod == "names") { return ctVal(ctEnumListMethod(mcObjName, 1)) }
                if (mcMethod == "valueOf") { return ctVal(ctEnumValueOfMethod(mcObjName, id)) }
            }
            if (comptimeDepth == 0 && enumReady == 1 && enumDeclNodes.has(mcObjName) == 1) {
                if (mcMethod == "values") { return constVal(genEnumValues(mcObjName)) }
                if (mcMethod == "names") { return constVal(genEnumNames(mcObjName)) }
                if (mcMethod == "valueOf") { return constVal(genEnumValueOf(mcObjName, nGetList(id))) }
            }
            if (comptimeDepth == 0) {
                if (mcObjName == "Thread" && mcMethod == "start") { return constVal(genMethodCall(id)) }
                if (getVarType(mcObjName) == "" && classFields.has(mcObjName) == 1) { return constVal(genMethodCall(id)) }
            }
        }
        if (comptimeDepth == 0 && pendingSuperParent != "") { return constVal(genMethodCall(id)) }
        const mcObj = genVal(mcObjNode)
        let mcObjReg = ""
        if (isCt(mcObj) == 0) { mcObjReg = reg(mcObj) }
        const mcArgList = nGetList(id)
        const mcSavedCPR = callPreRegs
        callPreRegs = new Map()
        let mcCtArgs: Array<string> = []
        let mcCtNamed = new Map()
        let mcHasNamed = 0
        if (mcArgList != "") {
            const mcArgParts = mcArgList.split(",")
            for (mcap in mcArgParts) {
                const mcArgId = parseInt(mcap)
                if (mcArgId > 0) {
                    if (nGetKind(mcArgId) == "NAMED_ARG") {
                        mcHasNamed = 1
                        const mcnv = genVal(nGetI1(mcArgId))
                        if (isCt(mcnv) == 1) {
                            mcCtNamed.set(nGetS1(mcArgId), `${payload(mcnv)}`)
                        } else {
                            mcCtNamed.set(nGetS1(mcArgId), `${interpNewNull()}`)
                            callPreRegs.set(`${mcArgId}`, reg(mcnv))
                        }
                    } else {
                        const mcav = genVal(mcArgId)
                        if (isCt(mcav) == 1) {
                            mcCtArgs = mcCtArgs.push(`${payload(mcav)}`)
                        } else {
                            mcCtArgs = mcCtArgs.push(`${interpNewNull()}`)
                            callPreRegs.set(`${mcArgId}`, reg(mcav))
                        }
                    }
                }
            }
        }
        if (comptimeDepth > 0) {
            callPreRegs = mcSavedCPR
            if (isCt(mcObj) == 0) {
                return comptimeError(`cannot call method '${mcMethod}' on runtime value`, id)
            }
            return ctMethodCallDispatch(id, mcMethod, payload(mcObj), mcCtArgs, mcCtNamed, mcHasNamed)
        }
        if (nGetI3(id) > 0) {
            callPreRegs.set(`${mcObjNode}`, mcObjReg)
            const mcOptResult = genOptionalMethodCall(id)
            callPreRegs = mcSavedCPR
            return constVal(mcOptResult)
        }
        const mcResult = genMethodCall(id, mcObjReg)
        callPreRegs = mcSavedCPR
        return constVal(mcResult)
    }
    if (kind == "TEMPLATE_LIT") {
        const fragList = nGetList(id)
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
        if (comptimeDepth > 0) { return comptimeError("template literal contains runtime expression", id) }
        tmplPreRegs = new Map()
        for (tp in tmplParts) {
            const fragId = parseInt(tp)
            if (fragId > 0 && nGetKind(fragId) == "TMPL_FRAG_EXPR") {
                const fv = parseInt(fragVals.getString(`${fragId}`))
                tmplPreRegs.set(`${fragId}`, reg(fv))
            }
        }
        return constVal(genTemplateLit(id))
    }
    if (kind == "ARRAY_LIT") {
        const elemList = nGetList(id)
        if (elemList == "") {
            if (comptimeDepth > 0) { return ctVal(interpNewArray("")) }
            return constVal(genArrayLit(id))
        }
        let allCt = 1
        const arrParts = elemList.split(",")
        let elemVals = new Map()
        for (ap in arrParts) {
            const elemId = parseInt(ap)
            if (elemId > 0) {
                if (nGetKind(elemId) == "SPREAD_ELEM") {
                    const sv = genVal(nGetI1(elemId))
                    elemVals.set(`${elemId}`, `${sv}`)
                    if (isCt(sv) != 1) { allCt = 0 }
                } else {
                    const ev = genVal(elemId)
                    elemVals.set(`${elemId}`, `${ev}`)
                    if (isCt(ev) != 1) { allCt = 0 }
                }
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
        return constVal(genArrayLit(id))
    }
    if (kind == "ARROW_FUNC") {
        if (comptimeDepth > 0) { return ctVal(interpNewVal("fn", `${id}`)) }
        return constVal(genArrowFunc(id))
    }
    if (kind == "INDEX_ACCESS") {
        const obj = genVal(nGetI1(id))
        const idx = genVal(nGetI2(id))
        if (isCt(obj) == 1 && isCt(idx) == 1) {
            const objP = payload(obj)
            const ot = interpType(objP)
            if (ot == "array") {
                const i = interpAsInt(payload(idx))
                return ctVal(interpArrayGet(objP, i))
            }
            if (ot == "object" || ot == "map") {
                const fieldName = interpAsStr(payload(idx))
                return ctVal(interpGetField(objP, fieldName))
            }
            if (ot == "string") {
                const s = interpAsStr(objP)
                const i = interpAsInt(payload(idx))
                if (i >= 0 && i < s.length()) {
                    return ctVal(interpNewString(s.charAt(i)))
                }
                return ctVal(interpNewString(""))
            }
        }
        if (comptimeDepth > 0) { return comptimeError("index access requires compile-time known operands", id) }
        return constVal(genIndexAccess(id, reg(obj), reg(idx)))
    }
    if (kind == "NAMED_ARG") { return genVal(nGetI1(id)) }
    if (comptimeDepth > 0) {
        if (kind == "COMPTIME_EMIT") {
            const ctEmitVal = genVal(nGetI1(id))
            if (isCt(ctEmitVal) == 1) {
                comptimeSS = `${comptimeSS}${interpAsStr(payload(ctEmitVal))}`
            }
            return ctVal(interpNewNull())
        }
        if (kind == "TYPEINFO_EXPR") { return ctVal(interpBuildTypeInfo(nGetS1(id))) }
        return comptimeError(`unsupported expression: ${kind}`, id)
    }
    println(`[genVal] unknown kind: ${kind}`)
    return constVal("0")
}

function genValBinary(id: int): int {
    const op = nGetS1(id)
    if (op == "And" || op == "Or") { return genValShortCircuit(op, id) }
    // Comptime: evaluate operands via genVal (handles ctVars scope chain) and dispatch by actual interp types
    if (comptimeDepth > 0) {
        if (op == "NullCoalesce") {
            const ctNcL = genVal(nGetI1(id))
            if (isCt(ctNcL) == 1 && interpType(payload(ctNcL)) != "null") { return ctNcL }
            return genVal(nGetI2(id))
        }
        if (op == "Instanceof" || op == "As") {
            return comptimeError(`operator '${op}' not supported`, id)
        }
        const ctBlv = genVal(nGetI1(id))
        const ctBrv = genVal(nGetI2(id))
        if (isCt(ctBlv) == 0 || isCt(ctBrv) == 0) {
            return comptimeError(`binary '${op}' operand is not compile-time known`, id)
        }
        const ctBlp = payload(ctBlv)
        const ctBrp = payload(ctBrv)
        const ctBlt = interpType(ctBlp)
        const ctBrt = interpType(ctBrp)
        if (op == "Add" && (ctBlt == "string" || ctBrt == "string")) {
            return ctVal(interpNewString(`${interpToStr(ctBlp)}${interpToStr(ctBrp)}`))
        }
        if (ctBlt == "string" && ctBrt == "string") {
            const cLs = interpAsStr(ctBlp)
            const cRs = interpAsStr(ctBrp)
            if (op == "Eq") { return ctVal(interpNewBool(cLs == cRs ? 1 : 0)) }
            if (op == "Ne") { return ctVal(interpNewBool(cLs != cRs ? 1 : 0)) }
            if (op == "Lt") { return ctVal(interpNewBool(cLs < cRs ? 1 : 0)) }
            if (op == "Gt") { return ctVal(interpNewBool(cLs > cRs ? 1 : 0)) }
            if (op == "Le") { return ctVal(interpNewBool(cLs <= cRs ? 1 : 0)) }
            if (op == "Ge") { return ctVal(interpNewBool(cLs >= cRs ? 1 : 0)) }
        }
        if (ctBlt == "double" || ctBrt == "double") {
            const ctLd = ctBlt == "double" ? parseDouble(interpAsStr(ctBlp)) : parseDouble(`${interpAsInt(ctBlp)}`)
            const ctRd = ctBrt == "double" ? parseDouble(interpAsStr(ctBrp)) : parseDouble(`${interpAsInt(ctBrp)}`)
            return ctVal(interpDoubleOp(op, ctLd, ctRd))
        }
        return ctVal(interpIntOp(op, interpAsInt(ctBlp), interpAsInt(ctBrp)))
    }
    if (op == "NullCoalesce" || op == "Instanceof" || op == "As" || op == "Pow") {
        return constVal(genBinary(id))
    }
    const blt = inferType(nGetI1(id))
    const brt = inferType(nGetI2(id))
    // String comparison: both string operands → comptime fold or inline runtime
    if (blt == "string" && brt == "string" && (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge")) {
        return genValStringCompare(op, id)
    }
    if ((blt != "int" && blt != "bool") || (brt != "int" && brt != "bool")) {
        return constVal(genBinary(id))
    }
    const lv = genVal(nGetI1(id))
    const rv = genVal(nGetI2(id))
    if (isCt(lv) == 1 && isCt(rv) == 1) {
        return ctVal(interpIntOp(op, interpAsInt(payload(lv)), interpAsInt(payload(rv))))
    }
    return constVal(genIntBinary(op, reg(lv), reg(rv)))
}

function genValUnary(id: int): int {
    // Comptime: evaluate via genVal + interp, never fall through to IR emission
    if (comptimeDepth > 0) {
        const ctUv = genVal(nGetI1(id))
        const ctUop = nGetS1(id)
        if (isCt(ctUv) == 0) { return ctVal(interpNewNull()) }
        const ctUp = payload(ctUv)
        const ctUt = interpType(ctUp)
        if (ctUop == "Neg") {
            if (ctUt == "double") { return ctVal(interpNewDouble(0.0 - parseDouble(interpAsStr(ctUp)))) }
            return ctVal(interpNewInt(0 - interpAsInt(ctUp)))
        }
        if (ctUop == "Not") { return ctVal(interpNewBool(interpTruthy(ctUp) == 1 ? 0 : 1)) }
        if (ctUop == "BitNot") { return ctVal(interpNewInt(~interpAsInt(ctUp))) }
        return ctVal(interpNewNull())
    }
    const uType = inferType(nGetI1(id))
    if (uType != "int" && uType != "bool") {
        return constVal(genUnary(id))
    }
    const ov = genVal(nGetI1(id))
    const op = nGetS1(id)
    if (isCt(ov) == 1) {
        const val = interpAsInt(payload(ov))
        if (op == "Neg") { return ctVal(interpNewInt(0 - val)) }
        if (op == "Not") { return ctVal(interpNewBool(val == 0 ? 1 : 0)) }
        if (op == "BitNot") { return ctVal(interpNewInt(~val)) }
    }
    // Runtime — operand already evaluated, emit IR directly
    const valStr = reg(ov)
    const r = nextReg()
    if (op == "Neg") {
        emitIR(`  ${r} = sub i32 0, ${valStr}`)
        return constVal(r)
    }
    if (op == "BitNot") {
        emitIR(`  ${r} = xor i32 ${valStr}, -1`)
        return constVal(r)
    }
    emitIR(`  ${r} = icmp eq i32 ${valStr}, 0`)
    const r2 = nextReg()
    emitIR(`  ${r2} = zext i1 ${r} to i32`)
    return constVal(r2)
}

function genValTernary(id: int): int {
    const cv = genVal(nGetI1(id))
    if (isCt(cv) == 1) {
        if (interpTruthy(payload(cv)) == 1) { return genVal(nGetI2(id)) }
        return genVal(nGetI3(id))
    }
    if (comptimeDepth > 0) { return ctVal(interpNewNull()) }
    // Runtime — condition already evaluated, emit branch directly
    const condStr = reg(cv)
    const vType = inferType(nGetI2(id))
    const llType = ssTypeToLLVM(vType)
    const resultAlloca = nextReg()
    emitIR(`  ${resultAlloca} = alloca ${llType}, align 8`)
    const cmp = nextReg()
    emitIR(`  ${cmp} = icmp ne i32 ${condStr}, 0`)
    const thenLabel = nextLabel("tern.then")
    const elseLabel = nextLabel("tern.else")
    const mergeLabel = nextLabel("tern.merge")
    emitIR(`  br i1 ${cmp}, label %${thenLabel}, label %${elseLabel}`)
    emitIR(`${thenLabel}:`)
    const thenVal = genExpr(nGetI2(id))
    emitIR(`  store ${llType} ${thenVal}, ptr ${resultAlloca}, align 8`)
    emitIR(`  br label %${mergeLabel}`)
    emitIR(`${elseLabel}:`)
    const elseVal = genExpr(nGetI3(id))
    emitIR(`  store ${llType} ${elseVal}, ptr ${resultAlloca}, align 8`)
    emitIR(`  br label %${mergeLabel}`)
    emitIR(`${mergeLabel}:`)
    const result = nextReg()
    emitIR(`  ${result} = load ${llType}, ptr ${resultAlloca}, align 8`)
    return constVal(result)
}

function genValShortCircuit(op: string, id: int): int {
    const lv = genVal(nGetI1(id))
    if (isCt(lv) == 1) {
        const leftTruthy = interpTruthy(payload(lv))
        if (op == "And") {
            if (leftTruthy == 0) { return ctVal(interpNewBool(0)) }
            return genVal(nGetI2(id))
        }
        if (leftTruthy == 1) { return lv }
        return genVal(nGetI2(id))
    }
    if (comptimeDepth > 0) { return ctVal(interpNewNull()) }
    // Runtime left — inline short-circuit IR (left already evaluated)
    const leftStr = reg(lv)
    const scResult = nextReg()
    emitIR(`  ${scResult} = alloca i32, align 4`)
    emitIR(`  store i32 ${leftStr}, ptr ${scResult}, align 4`)
    const scCmp = nextReg()
    emitIR(`  ${scCmp} = icmp ne i32 ${leftStr}, 0`)
    const scRhs = nextLabel("sc.rhs")
    const scEnd = nextLabel("sc.end")
    if (op == "And") {
        emitIR(`  br i1 ${scCmp}, label %${scRhs}, label %${scEnd}`)
    } else {
        emitIR(`  br i1 ${scCmp}, label %${scEnd}, label %${scRhs}`)
    }
    emitIR(`${scRhs}:`)
    const scRight = genExpr(nGetI2(id))
    emitIR(`  store i32 ${scRight}, ptr ${scResult}, align 4`)
    emitIR(`  br label %${scEnd}`)
    emitIR(`${scEnd}:`)
    const scRes = nextReg()
    emitIR(`  ${scRes} = load i32, ptr ${scResult}, align 4`)
    return constVal(scRes)
}

function genValStringCompare(op: string, id: int): int {
    const lv = genVal(nGetI1(id))
    const rv = genVal(nGetI2(id))
    if (isCt(lv) == 1 && isCt(rv) == 1) {
        const ls = interpAsStr(payload(lv))
        const rs = interpAsStr(payload(rv))
        if (op == "Eq") { return ctVal(interpNewBool(ls == rs ? 1 : 0)) }
        if (op == "Ne") { return ctVal(interpNewBool(ls != rs ? 1 : 0)) }
        if (op == "Lt") { return ctVal(interpNewBool(ls < rs ? 1 : 0)) }
        if (op == "Gt") { return ctVal(interpNewBool(ls > rs ? 1 : 0)) }
        if (op == "Le") { return ctVal(interpNewBool(ls <= rs ? 1 : 0)) }
        return ctVal(interpNewBool(ls >= rs ? 1 : 0))
    }
    // Runtime — operands already evaluated, inline string compare IR
    const lStr = reg(lv)
    const rStr = reg(rv)
    if (op == "Eq") {
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_string_eq(ptr ${lStr}, ptr ${rStr})`)
        return constVal(r)
    }
    if (op == "Ne") {
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_string_ne(ptr ${lStr}, ptr ${rStr})`)
        return constVal(r)
    }
    // Lt/Gt/Le/Ge: strcmp + icmp
    const cmpR = nextReg()
    emitIR(`  ${cmpR} = call i32 @ss_strcmp(ptr ${lStr}, ptr ${rStr})`)
    let cmpOp = "slt"
    if (op == "Gt") { cmpOp = "sgt" }
    if (op == "Le") { cmpOp = "sle" }
    if (op == "Ge") { cmpOp = "sge" }
    const cmpBool = nextReg()
    emitIR(`  ${cmpBool} = icmp ${cmpOp} i32 ${cmpR}, 0`)
    const r = nextReg()
    emitIR(`  ${r} = zext i1 ${cmpBool} to i32`)
    return constVal(r)
}

// ── Comptime expression helpers ─────────────────────────────────

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
            const soTmp = "/tmp/ss_comptime_exec.tmp"
            system(`${soCmd} > ${soTmp} 2>/dev/null`)
            return ctVal(interpNewString(readFile(soTmp)))
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

    // ── User-defined function call ──
    if (ctFuncNodes.has(name) == 1) {
        const ctFuncId = parseInt(ctFuncNodes.getString(name))
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

    println(`[comptime] unknown function: ${name}`)
    return ctVal(interpNewNull())
}

function ctNewExprDispatch(className: string, ctArgVals: Array<string>, ctNamedArgs: Map): int {
    const realName = resolveCtTypeAlias(className)
    if (interpClasses.has(realName) != 1) {
        println(`[comptime] unknown class: ${realName}`)
        return ctVal(interpNewNull())
    }
    const objId = interpNewVal("object", realName)
    const allFields = interpCollectFields(realName)
    let ctFieldNames: Array<string> = []
    if (allFields != "") {
        const fieldParts = allFields.split(",")
        let fi = 0
        while (fi < fieldParts.length()) {
            const fId = parseInt(fieldParts[fi])
            const fName = nGetS1(fId)
            ctFieldNames = ctFieldNames.push(fName)
            const defaultId = nGetI1(fId)
            if (defaultId > 0) {
                const dv = genVal(defaultId)
                interpSetField(objId, fName, isCt(dv) == 1 ? payload(dv) : interpNewNull())
            } else {
                interpSetField(objId, fName, interpNewNull())
            }
            fi = fi + 1
        }
    }
    let posIdx = 0
    while (posIdx < ctArgVals.length()) {
        if (posIdx < ctFieldNames.length()) {
            interpSetField(objId, ctFieldNames[posIdx], parseInt(ctArgVals[posIdx]))
        }
        posIdx = posIdx + 1
    }
    const namedKeys = ctNamedArgs.keys()
    for (nk in namedKeys) {
        if (nk != "") {
            interpSetField(objId, nk, parseInt(ctNamedArgs.getString(nk)))
        }
    }
    return ctVal(objId)
}

function ctMethodCallDispatch(id: int, methodName: string, objPayload: int, ctArgVals: Array<string>, ctNamedArgs: Map, ctHasNamed: int): int {
    const objType = interpType(objPayload)
    if (objType == "string" || objType == "array" || objType == "map") {
        return ctVal(ctBuiltinMethod(objPayload, methodName, ctArgVals))
    }
    // TypeValue: T.fields()/T.name — read off the underlying class name
    if (objType == "type") {
        const typeName = interpAsStr(objPayload)
        if (methodName == "fields") { return ctVal(interpCtFieldsArray(typeName)) }
        if (methodName == "name") { return ctVal(interpNewString(typeName)) }
        return comptimeError(`method '${methodName}' not supported on type value`, id)
    }
    if (objType != "object") {
        println(`[comptime] cannot call method '${methodName}' on ${objType}`)
        return ctVal(interpNewNull())
    }
    const className = interpAsStr(objPayload)
    if (methodName == "fields") {
        return ctVal(interpCtFieldsArray(className))
    }
    let lookupStart = className
    if (pendingSuperParent != "") {
        lookupStart = pendingSuperParent
    }
    const methodNode = interpFindMethod(lookupStart, methodName)
    if (methodNode == 0) {
        return comptimeError(`no method '${methodName}' on class ${lookupStart}`, id)
    }
    const ownerClass = interpLastFoundMethodClass
    const savedThis = interpThisVal
    const savedFunc = currentFunc
    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    const savedTerm = terminated
    const savedMethodClass = interpCurrentMethodClass
    interpBreakFlag = 0
    interpContinueFlag = 0
    terminated = 0
    interpThisVal = objPayload
    interpCurrentMethodClass = ownerClass
    ctCallCounter = ctCallCounter + 1
    currentFunc = `__ct_${ownerClass}_${methodName}_${ctCallCounter}`
    ctScopeStack = ctScopeStack.push(currentFunc)
    const mParamList = nGetList(methodNode)
    if (mParamList != "") {
        const mParams = mParamList.split(",")
        let mPosIdx = 0
        let mPi = 0
        while (mPi < mParams.length()) {
            const mPid = parseInt(mParams[mPi])
            const mPname = nGetS1(mPid)
            if (ctHasNamed == 1 && ctNamedArgs.has(mPname) == 1) {
                ctVars.set(`${currentFunc}:${mPname}`, `${ctVal(parseInt(ctNamedArgs.getString(mPname)))}`)
            } else if (mPosIdx < ctArgVals.length()) {
                ctVars.set(`${currentFunc}:${mPname}`, `${ctVal(parseInt(ctArgVals[mPosIdx]))}`)
                mPosIdx = mPosIdx + 1
            } else {
                const mDefId = nGetI1(mPid)
                if (mDefId > 0) {
                    const mDefVal = genVal(mDefId)
                    ctVars.set(`${currentFunc}:${mPname}`, `${isCt(mDefVal) == 1 ? mDefVal : ctVal(interpNewNull())}`)
                } else {
                    ctVars.set(`${currentFunc}:${mPname}`, `${ctVal(interpNewNull())}`)
                }
            }
            mPi = mPi + 1
        }
    }
    const mBodyId = nGetI1(methodNode)
    if (mBodyId > 0) { genBlock(mBodyId) }
    let mResult = interpNewNull()
    if (interpReturnFlag == 1) {
        mResult = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }
    ctPopScope()
    currentFunc = savedFunc
    interpThisVal = savedThis
    interpCurrentMethodClass = savedMethodClass
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue
    terminated = savedTerm
    return ctVal(mResult)
}

// Comptime enum helpers
function ctEnumListMethod(eName: string, wantNames: int): int {
    const enumId = parseInt(interpEnumNodes.getString(eName))
    const vl = nGetList(enumId)
    if (vl == "") { return interpNewArray("") }
    const isString = interpEnumTypes.has(eName) == 1
    const arr = interpNewArray("")
    const parts = vl.split(",")
    for (p in parts) {
        const vid = parseInt(p)
        if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
            if (wantNames == 1) {
                interpArrayPush(arr, interpNewString(nGetS1(vid)))
            } else {
                const val = interpEnumValues.getString(`${eName}.${nGetS1(vid)}`)
                if (isString) { interpArrayPush(arr, interpNewString(val)) }
                else { interpArrayPush(arr, interpNewInt(parseInt(val))) }
            }
        }
    }
    return arr
}

function ctEnumValueOfMethod(eName: string, nodeId: int): int {
    const voArgList = nGetList(nodeId)
    if (voArgList != "") {
        const voArgId = parseInt(voArgList.split(",")[0])
        const voVal = genVal(voArgId)
        if (isCt(voVal) == 1) {
            const voName = interpAsStr(payload(voVal))
            const voKey = `${eName}.${voName}`
            if (interpEnumValues.has(voKey) == 1) {
                if (interpEnumTypes.has(eName) == 1) { return interpNewString(interpEnumValues.getString(voKey)) }
                return interpNewInt(parseInt(interpEnumValues.getString(voKey)))
            }
        }
    }
    return interpNewNull()
}

// ── Comptime built-in method dispatch ───────────────────────────

function ctCallValue(fnValId: int, argVals: Array<string>): int {
    if (interpType(fnValId) != "fn") {
        println("[comptime] ctCallValue: not a function")
        return interpNewNull()
    }
    const funcNodeId = parseInt(interpAsStr(fnValId))
    const paramList = nGetList(funcNodeId)
    const bodyId = nGetI1(funcNodeId)

    const savedFunc = currentFunc
    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    const savedTerm = terminated
    interpBreakFlag = 0
    interpContinueFlag = 0
    terminated = 0

    ctCallCounter = ctCallCounter + 1
    currentFunc = `__ct_lambda_${ctCallCounter}`
    ctScopeStack = ctScopeStack.push(currentFunc)

    let paramNames: Array<string> = []
    if (paramList != "") {
        const params = paramList.split(",")
        let pi = 0
        while (pi < params.length() && pi < argVals.length()) {
            const pname = nGetS1(parseInt(params[pi]))
            ctVars.set(`${currentFunc}:${pname}`, `${ctVal(parseInt(argVals[pi]))}`)
            paramNames = paramNames.push(pname)
            pi = pi + 1
        }
    }

    if (bodyId > 0) { genBlock(bodyId) }

    let result = interpNewNull()
    if (interpReturnFlag == 1) {
        result = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }

    let di = 0
    while (di < paramNames.length()) {
        ctVars.delete(`${currentFunc}:${paramNames[di]}`)
        di = di + 1
    }
    ctPopScope()
    currentFunc = savedFunc
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue
    terminated = savedTerm
    return result
}

function ctStringMethod(objVal: int, method: string, argVals: Array<string>): int {
    const s = interpAsStr(objVal)
    if (method == "length") { return interpNewInt(s.length()) }
    if (method == "trim") { return interpNewString(s.trim()) }
    if (method == "toUpperCase") { return interpNewString(s.toUpperCase()) }
    if (method == "toLowerCase") { return interpNewString(s.toLowerCase()) }
    if (method == "split") {
        const sep = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        const parts = s.split(sep)
        const arr = interpNewArray("")
        let i = 0
        while (i < parts.length()) {
            interpArrayPush(arr, interpNewString(parts[i]))
            i = i + 1
        }
        return arr
    }
    if (method == "indexOf") {
        const sub = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        return interpNewInt(s.indexOf(sub))
    }
    if (method == "substring") {
        const start = argVals.length() > 0 ? interpAsInt(parseInt(argVals[0])) : 0
        const len = argVals.length() > 1 ? interpAsInt(parseInt(argVals[1])) : s.length()
        return interpNewString(s.substring(start, len))
    }
    if (method == "replace") {
        const old = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        const rep = argVals.length() > 1 ? interpAsStr(parseInt(argVals[1])) : ""
        return interpNewString(s.replace(old, rep))
    }
    if (method == "startsWith") {
        const prefix = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        return interpNewInt(s.startsWith(prefix))
    }
    if (method == "endsWith") {
        const suffix = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        return interpNewInt(s.endsWith(suffix))
    }
    if (method == "charAt") {
        const idx = argVals.length() > 0 ? interpAsInt(parseInt(argVals[0])) : 0
        return interpNewString(s.charAt(idx))
    }
    if (method == "includes") {
        const sub = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        return interpNewInt(s.indexOf(sub) >= 0 ? 1 : 0)
    }
    if (method == "repeat") {
        const n = argVals.length() > 0 ? interpAsInt(parseInt(argVals[0])) : 0
        let result = ""
        let i = 0
        while (i < n) {
            result = `${result}${s}`
            i = i + 1
        }
        return interpNewString(result)
    }
    println(`[comptime] unsupported string method: ${method}`)
    return interpNewNull()
}

function ctArrayMethod(objVal: int, method: string, argVals: Array<string>): int {
    if (method == "push") { return interpArrayPush(objVal, parseInt(argVals[0])) }
    const len = interpArrayLen(objVal)
    if (method == "length") { return interpNewInt(len) }
    if (method == "join") {
        const sep = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ","
        let result = ""
        let i = 0
        while (i < len) {
            if (i > 0) { result = `${result}${sep}` }
            result = `${result}${interpToStr(interpArrayGet(objVal, i))}`
            i = i + 1
        }
        return interpNewString(result)
    }
    if (method == "indexOf") {
        const target = parseInt(argVals[0])
        let i = 0
        while (i < len) {
            if (interpValEquals(interpArrayGet(objVal, i), target) == 1) {
                return interpNewInt(i)
            }
            i = i + 1
        }
        return interpNewInt(-1)
    }
    if (method == "slice") {
        let start = argVals.length() > 0 ? interpAsInt(parseInt(argVals[0])) : 0
        let end = argVals.length() > 1 ? interpAsInt(parseInt(argVals[1])) : len
        if (start < 0) { start = len + start }
        if (end < 0) { end = len + end }
        if (start < 0) { start = 0 }
        if (end > len) { end = len }
        const newArr = interpNewArray("")
        let i = start
        while (i < end) {
            interpArrayPush(newArr, interpArrayGet(objVal, i))
            i = i + 1
        }
        return newArr
    }
    if (method == "map") {
        const fnVal = parseInt(argVals[0])
        const newArr = interpNewArray("")
        let i = 0
        while (i < len) {
            let callArgs: Array<string> = []
            callArgs = callArgs.push(`${interpArrayGet(objVal, i)}`)
            interpArrayPush(newArr, ctCallValue(fnVal, callArgs))
            i = i + 1
        }
        return newArr
    }
    if (method == "filter") {
        const fnVal = parseInt(argVals[0])
        const newArr = interpNewArray("")
        let i = 0
        while (i < len) {
            const elemId = interpArrayGet(objVal, i)
            let callArgs: Array<string> = []
            callArgs = callArgs.push(`${elemId}`)
            if (interpTruthy(ctCallValue(fnVal, callArgs)) == 1) {
                interpArrayPush(newArr, elemId)
            }
            i = i + 1
        }
        return newArr
    }
    if (method == "forEach") {
        const fnVal = parseInt(argVals[0])
        let i = 0
        while (i < len) {
            let callArgs: Array<string> = []
            callArgs = callArgs.push(`${interpArrayGet(objVal, i)}`)
            ctCallValue(fnVal, callArgs)
            i = i + 1
        }
        return interpNewNull()
    }
    if (method == "reduce") {
        const fnVal = parseInt(argVals[0])
        let acc = argVals.length() > 1 ? parseInt(argVals[1]) : interpNewNull()
        let i = 0
        while (i < len) {
            let callArgs: Array<string> = []
            callArgs = callArgs.push(`${acc}`)
            callArgs = callArgs.push(`${interpArrayGet(objVal, i)}`)
            acc = ctCallValue(fnVal, callArgs)
            i = i + 1
        }
        return acc
    }
    println(`[comptime] unsupported array method: ${method}`)
    return interpNewNull()
}

function ctMapMethod(objVal: int, method: string, argVals: Array<string>): int {
    if (method == "set") {
        const key = interpAsStr(parseInt(argVals[0]))
        interpMapSet(objVal, key, parseInt(argVals[1]))
        return interpNewNull()
    }
    if (method == "get" || method == "getString") {
        const key = interpAsStr(parseInt(argVals[0]))
        return interpMapGet(objVal, key)
    }
    if (method == "has") {
        const key = interpAsStr(parseInt(argVals[0]))
        return interpNewInt(interpMapHas(objVal, key))
    }
    if (method == "delete") {
        const key = interpAsStr(parseInt(argVals[0]))
        interpMapDelete(objVal, key)
        return interpNewNull()
    }
    if (method == "keys") { return interpMapGetKeys(objVal) }
    if (method == "size") { return interpNewInt(interpMapGetSize(objVal)) }
    println(`[comptime] unsupported map method: ${method}`)
    return interpNewNull()
}

function ctBuiltinMethod(objPayload: int, methodName: string, argVals: Array<string>): int {
    const objType = interpType(objPayload)
    if (objType == "string") { return ctStringMethod(objPayload, methodName, argVals) }
    if (objType == "array") { return ctArrayMethod(objPayload, methodName, argVals) }
    if (objType == "map") { return ctMapMethod(objPayload, methodName, argVals) }
    println(`[comptime] no built-in method '${methodName}' on ${objType}`)
    return interpNewNull()
}

function genExpr(id: int): string {
    const cpKey = `${id}`
    if (callPreRegs.has(cpKey) == 1) {
        const pre = callPreRegs.getString(cpKey)
        callPreRegs.delete(cpKey)
        return pre
    }
    return reg(genVal(id))
}

// ── Binary operation helpers ────────────────────────────────────

function genStringConcat(leftId: int, rightId: int): string {
    const l = genExprAsString(leftId)
    const lOwned = lastExprStringOwned
    const rVal = genExprAsString(rightId)
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

function genNullCoalesce(leftId: int, rightId: int): string {
    const ncResult = nextReg()
    emitIR(`  ${ncResult} = alloca ptr, align 8`)
    const ncLeft = genExpr(leftId)
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
    const ncRight = genExpr(rightId)
    emitIR(`  store ptr ${ncRight}, ptr ${ncResult}, align 8`)
    emitIR(`  br label %${ncEnd}`)
    emitIR(`${ncEnd}:`)
    const ncFinal = nextReg()
    emitIR(`  ${ncFinal} = load ptr, ptr ${ncResult}, align 8`)
    return ncFinal
}

function genShortCircuit(op: string, leftId: int, rightId: int): string {
    const scResult = nextReg()
    emitIR(`  ${scResult} = alloca i32, align 4`)
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

function genBinary(id: int): string {
    const op = nGetS1(id)
    const leftId = nGetI1(id)
    const rightId = nGetI2(id)
    const blt = inferType(leftId)
    const brt = inferType(rightId)

    // String concatenation
    if (op == "Add" && (blt == "string" || brt == "string" || blt == "i64" || brt == "i64")) {
        if (blt == "string" || brt == "string") {
            return genStringConcat(leftId, rightId)
        }
    }
    // String equality/comparison
    if ((op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge") && (blt == "string" || brt == "string")) {
        return genStringCompare(op, leftId, rightId, blt, brt)
    }
    if (op == "NullCoalesce") { return genNullCoalesce(leftId, rightId) }
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

    // Numeric: evaluate operands
    let left = genExpr(leftId)
    let right = genExpr(rightId)
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

// ── Expression to string conversion ─────────────────────────────

// Convert any expression to string for println
// Sets lastExprStringOwned: 1 if result is newly allocated (conversion), 0 if borrowed
function genExprAsString(id: int, preReg: string = ""): string {
    const vType = inferType(id)
    const llType = ssTypeToLLVM(vType)
    if (vType == "string" || (llType == "ptr" && vType != "ptr" && vType.contains("<") == 0)) {
        const sVal = preReg != "" ? preReg : genExpr(id)
        const sNodeKind = nGetKind(id)
        if (sNodeKind == "IDENT" && getVarType(nGetS1(id)) == "i64") {
            const castR = nextReg()
            emitIR(`  ${castR} = inttoptr i64 ${sVal} to ptr`)
            lastExprStringOwned = 0
            return castR
        }
        lastExprStringOwned = 0
        return sVal
    }
    const val = preReg != "" ? preReg : genExpr(id)
    if (vType == "double") {
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_double_to_string(double ${val})`)
        lastExprStringOwned = 1
        return r
    }
    if (vType == "i64") {
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_i64_to_string(i64 ${val})`)
        lastExprStringOwned = 1
        return r
    }
    if (vType == "ptr" || vType.contains("<") == 1) {
        const castR = nextReg()
        emitIR(`  ${castR} = ptrtoint ptr ${val} to i64`)
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_i64_to_string(i64 ${castR})`)
        lastExprStringOwned = 1
        return r
    }
    const r = nextReg(); emitIR(`  ${r} = call ptr @ss_int_to_string(i32 ${val})`)
    lastExprStringOwned = 1
    return r
}
