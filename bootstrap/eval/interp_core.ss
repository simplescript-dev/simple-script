// SimpleScript Bootstrap SEMA Interpreter — 运行期核心状态 + 模块 barrel
// 单一职责:SEMA 解释器的"上下文"层(何时停、类在哪、comptime 缓冲哪里、scope 里有啥)。
//
// SEMA 模块物理切分(eval/,import 链从本文件 barrel 拉入):
//   interp_value.ss — Value 构造 / TypedValue 容器 (ctVal/isCt/payload + newTv* + interpNew* + interpType/AsInt/AsStr)
//   interp_op.ss    — 运算 / 真值 / 相等 (interpIntOp/DoubleOp/CompoundOp/Truthy/ToStr/ValEquals)
//   interp_obj.ss   — 对象 / 容器 / 类反射 (interpGetField/SetField/Array*/Map*/NewVal/FindMethod/CollectFields/CtFieldsArray/BuildTypeInfo/isKnownClass)
//   interp_core.ss  — 本文件:控制流 flag + class/enum registry + comptime buffer + scope
//
// 消费方 import 从 "./eval/interp_core" 统一走 barrel 路径,不感知内部细分
// (SS resolveImports advisory,但需真实 import 链触达才会被 inline,故本文件显式 re-chain)。

import { ctVal, isCt, payload, constVal, reg, materialize, initTypedValue, allocTv, newTvInt, newTvString, newTvType, newTvBool, newTvNull, newTvArray, tvKindOf, tvIntOf, tvStringOf, interpType, interpAsInt, interpAsStr, interpNewInt, interpNewString, interpNewBool, interpNewNull, interpNewType, interpNewArray, interpNewDouble } from "./interp_value"
import { interpCompoundOp, interpTruthy, interpToStr, interpIntOp, interpDoubleOp, interpValEquals } from "./interp_op"
import { interpGetField, interpSetField, interpArrayPush, interpArraySet, interpArrayLen, interpArrayGet, interpNewMap, interpMapSet, interpMapGet, interpMapHas, interpMapDelete, interpMapGetKeys, interpMapGetSize, interpNewVal, interpBuildTypeInfo, isKnownClass, interpFindMethod } from "./interp_obj"

// ── 控制流 flag (D092 Phase 2 sub-c) ─────────────────────────
// tvI3[id] 锁定为 object/map 的 field/entry 个数(Phase 0 第二次锁定)。

let interpReturnFlag = 0
let interpReturnVal = 0
let interpBreakFlag = 0
let interpContinueFlag = 0
let interpCurrentMethodClass = ""

// ── Class / Enum registry ───────────────────────────────────

let interpClasses = new Map()
let interpClassParents = new Map()
let interpEnumValues = new Map()
let interpEnumTypes = new Map()
let interpEnumNodes = new Map()

// enum 双 map 查找 (I010 — D127 §A.1 衍生):interpEnumValues/Types = comptime
// 注册,enumValues/Types = runtime 注册(codegen.ss,受 enumReady gate)。
// lookupEnumBackingValue typed hit 返 backing value("" = miss/untyped);
// lookupEnumOrdinal untyped hit 返 ordinal(-1 = miss/typed)。两者互斥,
// 调用点(member_access / interp_obj.evalAnnotationArg / exprs_ct_enum.ctEnumValueOfMethod)
// 按各自 untyped 语义组装 tv。
function lookupEnumBackingValue(eName: string, eKey: string): string {
    if (interpEnumValues.has(eKey) == 1 && interpEnumTypes.has(eName) == 1) {
        return interpEnumValues.getString(eKey)
    }
    if (enumReady == 1 && enumValues.has(eKey) == 1 && enumTypes.has(eName) == 1) {
        return enumValues.getString(eKey)
    }
    return ""
}

function lookupEnumOrdinal(eName: string, eKey: string): int {
    if (interpEnumValues.has(eKey) == 1 && interpEnumTypes.has(eName) == 0) {
        return parseInt(interpEnumValues.getString(eKey))
    }
    if (enumReady == 1 && enumValues.has(eKey) == 1 && enumTypes.has(eName) == 0) {
        return parseInt(enumValues.getString(eKey))
    }
    return -1
}

function interpShouldStop(): int {
    if (interpReturnFlag == 1) { return 1 }
    if (interpBreakFlag == 1) { return 1 }
    if (interpContinueFlag == 1) { return 1 }
    return 0
}

// continue 由循环体自行消费,不向循环外层冒泡,因此不计入 exit 判据
function interpCheckLoopExit(): int {
    if (interpReturnFlag == 1) { return 1 }
    if (interpBreakFlag == 1) { return 1 }
    return 0
}

// ── Comptime buffer (D092 Phase 2 sub-d) ────────────────────
// gen_exprs.ss 在 comptimeMustBeKnown == 1 时往 comptimeIR/SS 积累代码,
// @comptime 块结束由 interpGet*Comptime* 读出后清空。

let comptimeIR = ""
let comptimeSS = ""

function interpGetComptimeIR(): string {
    return comptimeIR
}

function interpGetComptimeSS(): string {
    return comptimeSS
}

function interpClearComptimeIR() {
    comptimeIR = ""
}

function interpClearComptimeSS() {
    comptimeSS = ""
}

// Phase 3 建立 scope stack 根帧;sub-d 阶段 interpVars 作为 flat scope 够用
function interpEnsureComptimeRoot() {
}

// ── scope (comptime 变量 flat store) ────────────────────────
// interpVars 是 comptime 变量的全局 scope store;scope stack 留给 Phase 3

let interpVars = new Map()
let interpThisVal = 0
let interpLastFoundMethodClass = ""
let comptimeReleaseMode = 0

function interpFindScopeKey(name: string): string {
    if (interpVars.has(name) == 1) { return name }
    return ""
}
