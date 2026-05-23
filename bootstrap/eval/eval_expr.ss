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
    if (k == "UNARY") {
        // D093 §决策 §Zig 原理 §2 / D169 §子拆解 1.5b — UNARY 入口单 dispatch
        // (类 B 入口双轨消除)。callsite 走 D098 §决策 1 §Phase A mv 编码协议:
        //   genVal(child) → positive 空间 → 转 mv 空间 → mvKnownOf 判定
        //   fold (int/bool: interpNewInt/Bool + ctVal) / runtime emit IR + mvRuntime / error
        // genVal 已对 evalExpr 复杂 kind 返值解码(`mv >= 0 ? mv : 0 - mv - 1`,见
        // gen/exprs/exprs.ss:68);本 case 再以 `isCt(v) == 1 ? v : 0 - v - 1` 反向
        // 编码回 mv 空间,让 callsite 走 mvKnownOf/mvValOf 协议(D169 §POC 失败实证
        // 锁的"mv 空间 vs positive 空间隔离"边界,Phase 1.5d genVal 桥消除后此反向
        // 转可去除直接 `subMv = evalExpr(child)`)。
        // comptimeMustBeKnown read callsite 首接入(D169 §B 立法 → read 协议物理推进)。
        // 1.5c 前不能挪 double fold:`interpAsStr` 跨读 tvS1(string 列)而 double 值在
        // tvD1(double 列)— 实测 -3.14 global init regression(D169 §POC 失败 N1)。
        const uOp = nGetS1(astId)
        const childId = nGetI1(astId)
        const uType = inferType(childId)
        if (uType != "int" && uType != "bool") {
            if (comptimeMustBeKnown == 1) {
                return comptimeError(`unary '${uOp}' operand not compile-time known`, astId)
            }
            return mvRuntime(constVal(genUnary(astId)))
        }
        const subRaw = genVal(childId)
        const subMv = isCt(subRaw) == 1 ? subRaw : (0 - subRaw - 1)
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
    if (op == "NullCoalesce") { return evalNullCoalesce(astId) }
    if (op == "Instanceof" || op == "As") { return evalInstanceofOrAs(op, astId) }
    if (op == "Pow") { return evalPow(astId) }
    // D093/D169 — BINARY 入口双轨消除 (4 op 拆独立 sibling 子文件 dispatch 上移)。
    // **comptime 路径按 valType(genVal 后真实值类型)dispatch,禁 inferType** —
    // comptime `let acc = ""` 注册 ctVars 而非 varTypes,inferType IDENT fallback 返
    // "int"(`gen/gen_types.ss:331-336`),致 `acc != ""` 走 int interpAsInt → 0 → Ne
    // 恒 false(D169 §POC N3 实证 17 处 i021/d123/spring regression 复发预防)。
    if (comptimeMustBeKnown == 1) {
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
        if (ctBlt == "string" && ctBrt == "string") { return genValStringCompare(op, astId, ctBlv, ctBrv) }
        if (ctBlt == "double" || ctBrt == "double") {
            const ctLd = ctBlt == "double" ? parseDouble(interpAsStr(ctBlp)) : parseDouble(`${interpAsInt(ctBlp)}`)
            const ctRd = ctBrt == "double" ? parseDouble(interpAsStr(ctBrp)) : parseDouble(`${interpAsInt(ctBrp)}`)
            return ctVal(interpDoubleOp(op, ctLd, ctRd))
        }
        return ctVal(interpIntOp(op, interpAsInt(ctBlp), interpAsInt(ctBrp)))
    }
    // D169 §1.5d 真单 dispatch 主轮第一子步 — eager genVal + 混合 dispatch + 142/146 forward。
    // **不变量**:caller forward `lRaw/rRaw`(positive 空间 = ctVal tagged | regId,reg() /
    // isCt() / valType() 合法输入);mv 空间值禁传 delegate — reg(negative_mv) 走 isCt
    // bit 30 误判 → IR `ptr 0` 崩 + valType(negative_mv) bit-mask 后 InternPool miss → ""。
    // **类型 dispatch**:`isCt(lRaw) ? valType(lRaw) : inferType(...)` — ct path valType
    // 修 §POC N3 17 处 ctVars IDENT fallback "int" 错配(i021/d123/spring),runtime path
    // inferType 等价 OLD 兜底。候选 C(regToType 全空间 valType 扩展)依赖 SS 数据流
    // Air.Inst.Ref 等价物升级,跨 phase scope 留 1.5e+。142/146 callsite forward 消除
    // delegate 内重 genVal → `f()+g()` 副作用 emit 两次的 double-eval bug。
    const lRaw = genVal(nGetI1(astId))
    const rRaw = genVal(nGetI2(astId))
    const lMv = isCt(lRaw) == 1 ? lRaw : (0 - lRaw - 1)
    const rMv = isCt(rRaw) == 1 ? rRaw : (0 - rRaw - 1)
    const blt = isCt(lRaw) == 1 ? valType(lRaw) : inferType(nGetI1(astId))
    const brt = isCt(rRaw) == 1 ? valType(rRaw) : inferType(nGetI2(astId))
    if (blt == "string" && brt == "string" && (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge")) {
        const sc = genValStringCompare(op, astId, lRaw, rRaw)
        return isCt(sc) == 1 ? sc : (0 - sc - 1)
    }
    if ((blt != "int" && blt != "bool") || (brt != "int" && brt != "bool")) {
        return mvRuntime(constVal(genBinary(astId, reg(lRaw), reg(rRaw))))
    }
    // int/bool runtime — eager mv 协议(已 line 上移 eager,本块仅 mvKnownOf/IR emit)
    if (mvKnownOf(lMv) == 1 && mvKnownOf(rMv) == 1) {
        return ctVal(interpIntOp(op, interpAsInt(valOf(lMv)), interpAsInt(valOf(rMv))))
    }
    return mvRuntime(constVal(genIntBinary(op, reg(lRaw), reg(rRaw))))
}
