// gen/exprs.ss — 表达式 codegen 分发器 + CT 字符串 idx 辅助 + 共享错误处理。
// 分发器仅分发,细项实现在 exprs_simple/binary/str_conv/ct_call/ct_obj/ct_enum/ct_builtin。

import { genCall, genTemplateLit, genArrowFunc, flushArrowDefs, genArrayLit } from "../gen_calls"
import { genMethodCall, genOptionalMethodCall, resolveSuperParent } from "../gen_methods"
import { interpNewInt, interpNewDouble, interpNewString, interpNewBool, interpNewNull, interpNewVal, interpNewArray, interpArrayPush, interpArrayGet, interpNewMap, interpType, interpAsInt, interpAsStr, interpToStr, interpTruthy, interpGetField, interpSetField, interpFindMethod, interpCollectFields, interpCtFieldsArray, interpCheckLoopExit, interpCompoundOp, interpValEquals, interpMapSet, interpMapGet, interpMapHas, interpMapDelete, interpMapGetKeys, interpMapGetSize } from "../eval/interp_core"
import { interpBuildTypeInfo } from "../gen_reflect"
import { genThisExpr, genIdent, genUnary, genIndexAccess, genPostfixExpr } from "./exprs_simple"
import { genBinary, genStringConcat, genStringCompare, genNullCoalesce, genShortCircuit, genDoubleBinary, genIntBinary } from "./exprs_binary"
import { genExprAsString } from "./exprs_str_conv"
import { ctCallDispatch } from "./exprs_ct_call"
import { ctNewExprDispatch, ctMethodCallDispatch } from "./exprs_ct_obj"
import { ctEnumListMethod, ctEnumValueOfMethod } from "./exprs_ct_enum"
import { ctCallValue, ctStringMethod, ctArrayMethod, ctMapMethod, ctBuiltinMethod } from "./exprs_ct_builtin"

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
    if (kind == "BINARY" || kind == "UNARY" || kind == "TERNARY" || kind == "COMPTIME_EXPR" || kind == "INDEX_ACCESS" || kind == "TEMPLATE_LIT" || kind == "ARRAY_LIT" || kind == "IDENT" || kind == "MEMBER_ACCESS" || kind == "POSTFIX_INC" || kind == "METHOD_CALL" || kind == "CALL" || kind == "NEW_EXPR") { const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1 }
    if (kind == "GROUPING") { return genVal(nGetI1(id)) }
    if (kind == "THIS" || kind == "SUPER") {
        if (comptimeDepth > 0) {
            if (interpThisVal > 0) { return ctVal(interpThisVal) }
            return ctVal(interpNewNull())
        }
        return constVal(genThisExpr())
    }
    if (kind == "ARROW_FUNC") {
        if (comptimeDepth > 0) { return ctVal(interpNewVal("fn", `${id}`)) }
        return constVal(genArrowFunc(id))
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

function genExpr(id: int): string {
    const cpKey = `${id}`
    if (callPreRegs.has(cpKey) == 1) {
        const pre = callPreRegs.getString(cpKey)
        callPreRegs.delete(cpKey)
        return pre
    }
    return reg(genVal(id))
}
