// D099 mv 编码契约(evalExpr / eval/* 通用):
//   mv >= 0   → known,  val = mv        (ctVal tagged int,bit 30 set)
//   mv <= -2  → runtime,regId = -mv - 1  (regTable 1-based)
//   mv == -1  → error 哨兵
// 仅留主 dispatch evalExpr + UNARY/BINARY inline,10 子函数迁 bootstrap/eval/*.ss(eval_expr 子目录拆分)
// 本文件承载 10 条 import(main.ss F1=630 baseline 守门,不+import 行)。

import { evalCall } from "./call"
import { evalTernary } from "./ternary"
import { evalShortCircuit } from "./short_circuit"
import { evalNullCoalesce } from "./null_coalesce"
import { evalInstanceofOrAs } from "./instanceof_as"
import { evalPow } from "./pow_binary"
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
    // D093 §Zig 原理 §1 "唯一求值入口" leaf literal 直返 ctVal — UNARY swap `subMv = evalExpr(childId)`
    // 安全 prereq(否则 leaf literal child fall through 到 BINARY 区域 corrupt)。sibling 对齐
    // gen/exprs/exprs.ss:62-67 + :83 genVal 同 8 case(INT/STRING/TRUE/FALSE/NULL/DOUBLE_LIT
    // + GROUPING + NAMED_ARG;THIS/SUPER/ARROW_FUNC ct-depth 特例留 Phase 4)。GROUPING/NAMED_ARG
    // 委托内层避剥皮丢 location。
    if (k == "INT_LIT") { return ctVal(interpNewInt(parseInt(nGetS1(astId)))) }
    if (k == "STRING_LIT") { return ctVal(interpNewString(nGetS1(astId))) }
    if (k == "TRUE_LIT") { return ctVal(interpNewBool(1)) }
    if (k == "FALSE_LIT") { return ctVal(interpNewBool(0)) }
    if (k == "NULL_LIT") { return ctVal(interpNewNull()) }
    if (k == "DOUBLE_LIT") { return ctVal(interpNewDouble(parseDouble(nGetS1(astId)))) }
    if (k == "GROUPING") { return evalExpr(nGetI1(astId)) }
    if (k == "NAMED_ARG") { return evalExpr(nGetI1(astId)) }
    if (k == "THIS" || k == "SUPER") {
        if (interpThisVal > 0) { return ctVal(interpThisVal) }
        if (comptimeMustBeKnown == 1) { return comptimeError(`'${k}' not bound in comptime context`, astId) }
        return ctVal(interpNewNull())
    }
    if (k == "ARROW_FUNC") { return ctVal(interpNewVal("fn", `${astId}`)) }
    if (k == "UNARY") {
        // D093 §决策 §Zig 原理 §2 / D169 §子拆解 1.5b — UNARY 入口单 dispatch (类 B 入口双轨消除)。
        // 主 case 直接 `evalExpr(childId)` 拿 mv 空间值无 genVal 桥反向编码 — evalExpr 主 dispatch
        // 已返 mv 空间整全(ctVal positive bit-30 + mvRuntime negative),sibling 完全一致对齐
        // BINARY/POW/NULL_COALESCE 主 case 三段式终态。
        // double fold 留 1.5c 前不能挪:`interpAsStr` 跨读 tvS1(string 列)而 double 值在 tvD1
        // (double 列)— 实测 -3.14 global init regression(D169 §POC 失败 N1)。
        const uOp = nGetS1(astId)
        const childId = nGetI1(astId)
        const uType = inferType(childId)
        if (uType != "int" && uType != "bool") {
            if (comptimeMustBeKnown == 1) {
                return comptimeError(`unary '${uOp}' operand not compile-time known`, astId)
            }
            return mvRuntime(constVal(genUnary(astId)))
        }
        const subMv = evalExpr(childId)
        if (mvKnownOf(subMv) == 1) {
            // known int/bool:subMv ∈ positive ctVal 空间(mv >= 0),valOf 取 payload
            const subP = valOf(subMv)
            if (uOp == "Neg") { return ctVal(interpNewInt(0 - interpAsInt(subP))) }
            if (uOp == "Not") { return ctVal(interpNewBool(interpTruthy(subP) == 1 ? 0 : 1)) }
            if (uOp == "BitNot") { return ctVal(interpNewInt(~interpAsInt(subP))) }
            return ctVal(interpNewNull())
        }
        // runtime int/bool:mvKnownOf == 0
        if (comptimeMustBeKnown == 1) {
            return comptimeError(`unary '${uOp}' operand not compile-time known`, astId)
        }
        const uValStr = regTable[mvValOf(subMv) - 1]
        const uR = nextReg()
        if (uOp == "Neg") {
            emitIR(`  ${uR} = sub i32 0, ${uValStr}`)
            return mvRuntime(constVal(uR))
        }
        if (uOp == "BitNot") {
            emitIR(`  ${uR} = xor i32 ${uValStr}, -1`)
            return mvRuntime(constVal(uR))
        }
        emitIR(`  ${uR} = icmp eq i32 ${uValStr}, 0`)
        const uR2 = nextReg()
        emitIR(`  ${uR2} = zext i1 ${uR} to i32`)
        return mvRuntime(constVal(uR2))
    }
    if (k == "TERNARY") { return evalTernary(astId) }
    if (k == "COMPTIME_EXPR") {
        if (comptimeMustBeKnown == 1) { return comptimeError("nested comptime expression", astId) }
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
    // D093 §Phase 4 续 sub-round 第三例 — COMPTIME_EMIT cross-module side-effect 写 comptimeSS
    // (interp_core.ss:79 全局可跨 eval 子模块直读/写,sibling THIS/SUPER 21f8342 interpThisVal cross-module access 模板)。
    // TYPEINFO_EXPR 直构造 ct value(interpBuildTypeInfo 经 interp_obj.ss:215 接受 string 参数,
    // sibling ARROW_FUNC 33c65e2 interpNewVal 单态直构同模板)。
    if (k == "COMPTIME_EMIT") {
        const ctEmitMv = evalExpr(nGetI1(astId))
        if (mvKnownOf(ctEmitMv) == 1) {
            comptimeSS = `${comptimeSS}${interpAsStr(valOf(ctEmitMv))}`
        }
        return ctVal(interpNewNull())
    }
    if (k == "TYPEINFO_EXPR") { return ctVal(interpBuildTypeInfo(nGetS1(astId))) }
    // unsupported 兜底 — BINARY 主 case 之前 kind 白名单守门 prereq(防 fall-through 到 BINARY ct path
    // 致 corrupt;sibling THIS/SUPER 21f8342 comptimeMustBeKnown==1 loud-error path 模板)。
    if (k != "BINARY") {
        if (comptimeMustBeKnown == 1) { return comptimeError(`unsupported expression: ${k}`, astId) }
        return ctVal(interpNewNull())
    }
    const op = nGetS1(astId)
    if (op == "And" || op == "Or") { return evalShortCircuit(op, astId) }
    if (op == "NullCoalesce") { return evalNullCoalesce(astId) }
    if (op == "Instanceof" || op == "As") { return evalInstanceofOrAs(op, astId) }
    if (op == "Pow") { return evalPow(astId) }
    // D093/D169 1.5d 主轮第三子步 — BINARY 主 case 收口为通用 binop only,sibling 完全一致
    // 三段式(ct → 紧 loud → runtime,对齐 `ternary.ss:4-10` / `short_circuit.ss:5-13` /
    // `index_access.ss`)。**eager unify**:lRaw/rRaw 仅 genVal 一次,double-ct fold + 紧 loud +
    // runtime path 共享句柄避 double-eval bug(commit 2af65a7 接口扩 forward reg 已就绪)。
    // **混合 dispatch** `isCt(lRaw) ? valType(lRaw) : inferType(...)` blt/brt — ct path
    // valType 修 §POC N3 17 处 ctVars IDENT fallback "int" 错配(i021/d123/spring);runtime
    // path inferType 等价 OLD 兜底;Air.Inst.Ref 携 type info 终态(全空间 valType 扩展)
    // 依赖 SS 数据流升级跨 phase scope 留 1.5e+。
    const lRaw = genVal(nGetI1(astId))
    const rRaw = genVal(nGetI2(astId))
    // PERMANENT(D093 scope 内不可达 — Air.Inst.Ref 携 type info 终态 + InternPool / Air IR 数据流升级依赖 D093 外 phase / D098 §下一步 无 active §Phase D/§InternPool/§Air IR anchor; D170 §决策 C exit 动作 §2 [permanent] 兜底 + D170 §拒绝准则 #3 SUNSET→PERMANENT 替代 + 记入 D093 §出口清单 sibling 第三十四例):
    const blt = isCt(lRaw) == 1 ? valType(lRaw) : inferType(nGetI1(astId))
    const brt = isCt(rRaw) == 1 ? valType(rRaw) : inferType(nGetI2(astId))
    if (isCt(lRaw) == 1 && isCt(rRaw) == 1) {
        const lp = valOf(lRaw)
        const rp = valOf(rRaw)
        if (op == "Add" && (blt == "string" || brt == "string")) {
            return ctVal(interpNewString(`${interpToStr(lp)}${interpToStr(rp)}`))
        }
        if (blt == "string" && brt == "string") { return genValStringCompare(op, astId, lRaw, rRaw) }
        return ctVal(interpNumericBinop(op, lp, rp, blt, brt))
    }
    if (comptimeMustBeKnown == 1) {
        return comptimeError(`binary '${op}' operand is not compile-time known`, astId)
    }
    if (blt == "string" && brt == "string" && (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge")) {
        const sc = genValStringCompare(op, astId, lRaw, rRaw)
        return isCt(sc) == 1 ? sc : (0 - sc - 1)
    }
    if ((blt != "int" && blt != "bool") || (brt != "int" && brt != "bool")) {
        return mvRuntime(constVal(genBinary(astId, reg(lRaw), reg(rRaw))))
    }
    return mvRuntime(constVal(genIntBinary(op, reg(lRaw), reg(rRaw))))
}
