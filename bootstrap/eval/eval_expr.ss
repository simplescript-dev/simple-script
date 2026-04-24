// D099 mv 编码契约(evalExpr / eval/* 通用):
//   mv >= 0   → known,  val = mv        (ctVal tagged int,bit 30 set)
//   mv <= -2  → runtime,regId = -mv - 1  (regTable 1-based)
//   mv == -1  → error 哨兵
// 仅留主 dispatch evalExpr + UNARY/BINARY inline,10 子函数迁 bootstrap/eval/*.ss(eval_expr 子目录拆分)
// 本文件承载 10 条 import(main.ss F1=630 baseline 守门,不+import 行)。

import { evalCall } from "./call"
import { evalTernary } from "./ternary"
import { evalShortCircuit } from "./short_circuit"
import { evalIndexAccess } from "./index_access"
import { evalTemplateLit } from "./template_lit"
import { evalArrayLit } from "./array_lit"
import { evalIdent } from "./ident"
import { evalMemberAccess } from "./member_access"
import { evalPostfixInc } from "./postfix_inc"
import { evalMethodCall } from "./method_call"
import { evalNewExpr } from "./new_expr"
import { valOf, valType } from "../gen/gen_maybeval"

function evalExpr(astId: int): int {
    const k = nGetKind(astId)
    if (k == "UNARY") {
        const uOp = nGetS1(astId)
        if (comptimeDepth > 0) {
            const ctUv = genVal(nGetI1(astId))
            if (isCt(ctUv) == 0) { return ctVal(interpNewNull()) }
            const ctUp = valOf(ctUv)
            const ctUt = valType(ctUv)
            if (uOp == "Neg") {
                if (ctUt == "double") { return ctVal(interpNewDouble(0.0 - parseDouble(interpAsStr(ctUp)))) }
                return ctVal(interpNewInt(0 - interpAsInt(ctUp)))
            }
            if (uOp == "Not") { return ctVal(interpNewBool(interpTruthy(ctUp) == 1 ? 0 : 1)) }
            if (uOp == "BitNot") { return ctVal(interpNewInt(~interpAsInt(ctUp))) }
            return ctVal(interpNewNull())
        }
        const uType = inferType(nGetI1(astId))
        if (uType != "int" && uType != "bool") {
            return 0 - constVal(genUnary(astId)) - 1
        }
        const ov = genVal(nGetI1(astId))
        if (isCt(ov) == 1) {
            const uVal = interpAsInt(payload(ov))
            if (uOp == "Neg") { return ctVal(interpNewInt(0 - uVal)) }
            if (uOp == "Not") { return ctVal(interpNewBool(uVal == 0 ? 1 : 0)) }
            if (uOp == "BitNot") { return ctVal(interpNewInt(~uVal)) }
        }
        const uValStr = reg(ov)
        const uR = nextReg()
        if (uOp == "Neg") {
            emitIR(`  ${uR} = sub i32 0, ${uValStr}`)
            return 0 - constVal(uR) - 1
        }
        if (uOp == "BitNot") {
            emitIR(`  ${uR} = xor i32 ${uValStr}, -1`)
            return 0 - constVal(uR) - 1
        }
        emitIR(`  ${uR} = icmp eq i32 ${uValStr}, 0`)
        const uR2 = nextReg()
        emitIR(`  ${uR2} = zext i1 ${uR} to i32`)
        return 0 - constVal(uR2) - 1
    }
    if (k == "TERNARY") { return evalTernary(astId) }
    if (k == "COMPTIME_EXPR") {
        if (comptimeDepth > 0) { return comptimeError("nested comptime expression", astId) }
        const ceK = `${astId}`
        const ceTy = inferType(astId)
        // I014 §路径 A — array/object/map 返回不 materialize 成 runtime literal(无法压 i32),
        // 改返 ctVal(tvId) 让外层 VAR_DECL CONST 绑定 ctVars,消费侧走 ct 路径(for-in unroll /
        // member access)。gen_types.ss inferType 把 tvId 以字符串形式缓存到 comptimeExprLiteral。
        if (ceTy == "array" || ceTy == "object" || ceTy == "map") {
            return ctVal(parseInt(comptimeExprLiteral.getString(ceK)))
        }
        return 0 - constVal(comptimeExprLiteral.getString(ceK)) - 1
    }
    if (k == "INDEX_ACCESS") { return evalIndexAccess(astId) }
    if (k == "TEMPLATE_LIT") { return evalTemplateLit(astId) }
    if (k == "ARRAY_LIT") { return evalArrayLit(astId) }
    if (k == "IDENT") { return evalIdent(astId) }
    if (k == "MEMBER_ACCESS") { return evalMemberAccess(astId) }
    if (k == "POSTFIX_INC") { return evalPostfixInc(astId) }
    if (k == "METHOD_CALL") { return evalMethodCall(astId) }
    if (k == "CALL") { return evalCall(astId) }
    if (k == "NEW_EXPR") { return evalNewExpr(astId) }
    const op = nGetS1(astId)
    if (op == "And" || op == "Or") { return evalShortCircuit(op, astId) }
    if (comptimeDepth > 0) {
        if (op == "NullCoalesce") {
            const ctNcL = genVal(nGetI1(astId))
            if (isCt(ctNcL) == 1 && valType(ctNcL) != "null") { return ctNcL }
            return genVal(nGetI2(astId))
        }
        if (op == "Instanceof" || op == "As") {
            return comptimeError(`operator '${op}' not supported`, astId)
        }
        const ctBlv = genVal(nGetI1(astId))
        const ctBrv = genVal(nGetI2(astId))
        if (isCt(ctBlv) == 0 || isCt(ctBrv) == 0) {
            return comptimeError(`binary '${op}' operand is not compile-time known`, astId)
        }
        const ctBlp = valOf(ctBlv)
        const ctBrp = valOf(ctBrv)
        const ctBlt = valType(ctBlv)
        const ctBrt = valType(ctBrv)
        if (op == "Add" && (ctBlt == "string" || ctBrt == "string")) {
            return ctVal(interpNewString(`${interpToStr(ctBlp)}${interpToStr(ctBrp)}`))
        }
        if (ctBlt == "string" && ctBrt == "string") { return genValStringCompare(op, astId) }
        if (ctBlt == "double" || ctBrt == "double") {
            const ctLd = ctBlt == "double" ? parseDouble(interpAsStr(ctBlp)) : parseDouble(`${interpAsInt(ctBlp)}`)
            const ctRd = ctBrt == "double" ? parseDouble(interpAsStr(ctBrp)) : parseDouble(`${interpAsInt(ctBrp)}`)
            return ctVal(interpDoubleOp(op, ctLd, ctRd))
        }
        return ctVal(interpIntOp(op, interpAsInt(ctBlp), interpAsInt(ctBrp)))
    }
    if (op == "NullCoalesce" || op == "Instanceof" || op == "As" || op == "Pow") {
        return 0 - constVal(genBinary(astId)) - 1
    }
    const blt = inferType(nGetI1(astId))
    const brt = inferType(nGetI2(astId))
    if (blt == "string" && brt == "string" && (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge")) {
        const sc = genValStringCompare(op, astId)
        if (isCt(sc) == 1) { return sc }
        return 0 - sc - 1
    }
    if ((blt != "int" && blt != "bool") || (brt != "int" && brt != "bool")) {
        return 0 - constVal(genBinary(astId)) - 1
    }
    const lv = genVal(nGetI1(astId))
    const rv = genVal(nGetI2(astId))
    if (isCt(lv) == 1 && isCt(rv) == 1) {
        return ctVal(interpIntOp(op, interpAsInt(payload(lv)), interpAsInt(payload(rv))))
    }
    return 0 - constVal(genIntBinary(op, reg(lv), reg(rv))) - 1
}
