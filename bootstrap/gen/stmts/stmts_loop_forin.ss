// gen/stmts_loop_forin.ss — for-in / for-of 循环。
// 路径:ct-array unroll(comptime iterable 数组)、obj.fields() runtime unroll
// (METHOD_CALL 绑 string 供 obj[name] bracket)、ARRAY_LIT unroll、runtime
// for-in。cls.fields MEMBER_ACCESS 走 ct-probe 绑 Meta object ctVars,经
// evalMemberAccess interpGetField 统一 Meta object read。

import { genBlock, genNestedBlock } from "./stmts_core"

// Compile-time for-in unroll. itemCsv is a comma-separated list of the values
// the loop variable takes on each iteration — from classFields when iterating
// obj.fields(), or from stringLitArrayCsv when iterating a string-literal array.
function genForInUnrolled(id: int, itemCsv: string) {
    const itemName = nGetS1(id)
    const bodyId = nGetI2(id)

    const itemLLName = allocVarName(itemName)
    emitIR(`  %${itemLLName} = alloca ptr, align 8`)
    setVarType(itemName, "string")

    if (itemCsv == "") { return }

    const items = itemCsv.split(",")
    const fieldCount = items.length()
    const afterLabel = nextLabel("forin.unroll.after")

    // Save/set break/continue
    const savedBreak = breakLabel
    const savedContinue = continueLabel
    const savedLoopStack = loopBlockStackSaved
    breakLabel = afterLabel
    loopBlockStackSaved = blockPtrVarStack

    let i = 0
    for (itemVal in items) {
        comptimeConsts.set(itemName, itemVal)

        const strConst = addStringConst(itemVal)
        emitIR(`  store ptr ${strConst}, ptr %${itemLLName}, align 8`)

        let nextIterLabel = afterLabel
        if (i < fieldCount - 1) {
            nextIterLabel = nextLabel("forin.unroll.next")
        }
        continueLabel = nextIterLabel

        genNestedBlock(bodyId)

        if (terminated == 0) {
            emitIR(`  br label %${nextIterLabel}`)
        }
        if (i < fieldCount - 1) {
            emitIR(`${nextIterLabel}:`)
        }
        terminated = 0

        i = i + 1
    }

    comptimeConsts.delete(itemName)

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak
    continueLabel = savedContinue
    loopBlockStackSaved = savedLoopStack
}

function genForIn(id: int) {
    const itemName = nGetS1(id)
    const iterableId = nGetI1(id)
    const bodyId = nGetI2(id)

    // D089 Phase 4 / D117 Execute 4 / D120 §A.4 #3 — 通用 ct-array unroll:
    // ctProbe 不依赖 kind 白名单,改按 "genVal 返回 ctVal array" 决定;
    // 字面量短路(INT/STRING/DOUBLE/BOOL/NULL/ARRAY_LIT 由其他入口处理);
    // 非字面量 kind 尝试 genVal,cache 供 runtime path 复用 reg,避免双重 IR。
    let ctProbe = comptimeDepth > 0 ? 1 : 0
    let ctIterVal = 0
    let ctIterReady = 0
    if (ctProbe == 0) {
        const iterKind = nGetKind(iterableId)
        if (iterKind != "INT_LIT" && iterKind != "STRING_LIT" && iterKind != "DOUBLE_LIT" && iterKind != "TRUE_LIT" && iterKind != "FALSE_LIT" && iterKind != "NULL_LIT" && iterKind != "ARRAY_LIT") {
            ctIterVal = genVal(iterableId)
            ctIterReady = 1
            if (isCt(ctIterVal) == 1) {
                const probeType = interpType(payload(ctIterVal))
                if (probeType == "array" || probeType == "map") { ctProbe = 1 }
            }
        }
    }
    if (ctProbe == 1) {
        if (ctIterReady == 0) { ctIterVal = genVal(iterableId); ctIterReady = 1 }
        if (isCt(ctIterVal) == 1 && interpType(payload(ctIterVal)) == "array") {
            const ctArrId = payload(ctIterVal)
            const ctArrLen = interpArrayLen(ctArrId)
            if (ctArrLen > 0 && interpType(interpArrayGet(ctArrId, 0)) == "string") { setVarType(itemName, "string") }
            let ctFi = 0
            while (ctFi < ctArrLen) {
                ctVars.set(`${currentFunc}:${itemName}`, `${ctVal(interpArrayGet(ctArrId, ctFi))}`)
                genBlock(bodyId)
                if (interpCheckLoopExit() == 1) { break }
                ctFi = ctFi + 1
            }
            return
        }
        if (isCt(ctIterVal) == 1 && interpType(payload(ctIterVal)) == "map") {
            const ctMapId = payload(ctIterVal)
            const keysArr = interpMapGetKeys(ctMapId)
            const mapLen = interpArrayLen(keysArr)
            if (mapLen > 0 && interpType(interpGetField(ctMapId, interpAsStr(interpArrayGet(keysArr, 0)))) == "string") { setVarType(itemName, "string") }
            let ctMi = 0
            while (ctMi < mapLen) {
                ctVars.set(`${currentFunc}:${itemName}`, `${ctVal(interpGetField(ctMapId, interpAsStr(interpArrayGet(keysArr, ctMi))))}`)
                genBlock(bodyId)
                if (interpCheckLoopExit() == 1) { break }
                ctMi = ctMi + 1
            }
            return
        }
        if (comptimeDepth > 0) { return }
    }

    // D088: detect obj.fields() → compile-time unroll(runtime obj,Execute 5 迁)
    if (getMethodName(iterableId) == "fields") {
        const fieldsObjId = nGetI1(iterableId)
        const fieldsClass = resolveObjClass(fieldsObjId)
        if (fieldsClass != "" && classFields.has(fieldsClass) == 1) {
            const fsStr = classFields.getString(fieldsClass)
            genForInUnrolled(id, fsStr)
            return
        }
    }

    if (nGetKind(iterableId) == "ARRAY_LIT") {
        const litCsv = stringLitArrayCsv(iterableId)
        if (litCsv != "") {
            genForInUnrolled(id, litCsv)
            return
        }
    }

    const arr = ctIterReady == 1 ? reg(ctIterVal) : genExpr(iterableId)
    const lenReg = nextReg(); emitIR(`  ${lenReg} = call i32 @ss_arrayLen(ptr ${arr})`)

    // Index variable
    const idxAlloca = nextReg(); emitIR(`  ${idxAlloca} = alloca i32, align 4`)
    emitIR(`  store i32 0, ptr ${idxAlloca}, align 4`)

    let itemType = inferArrayElemType(iterableId)
    if (itemType == "") { itemType = "i64" }
    const itemLLName = allocVarName(itemName)
    const itemLLType = ssTypeToLLVM(itemType)
    emitIR(`  %${itemLLName} = alloca ${itemLLType}, align 8`)
    setVarType(itemName, itemType)

    const condLabel = nextLabel("forin.cond")
    const bodyLabel = nextLabel("forin.body")
    const afterLabel = nextLabel("forin.after")

    const savedBreak2 = breakLabel
    const savedContinue2 = continueLabel
    const savedLoopStack2 = loopBlockStackSaved
    const updateLabel2 = nextLabel("forin.update")
    breakLabel = afterLabel
    continueLabel = updateLabel2
    loopBlockStackSaved = blockPtrVarStack

    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const curIdx = nextReg(); emitIR(`  ${curIdx} = load i32, ptr ${idxAlloca}, align 4`)
    const cmp = nextReg(); emitIR(`  ${cmp} = icmp slt i32 ${curIdx}, ${lenReg}`)
    emitIR(`  br i1 ${cmp}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    const elemVal = nextReg(); emitIR(`  ${elemVal} = call i64 @ss_arrayGet(ptr ${arr}, i32 ${curIdx})`)
    // Convert i64 element to item type
    if (itemType == "" || itemType == "auto" || itemType == "i64") {
        emitIR(`  store i64 ${elemVal}, ptr %${itemLLName}, align 8`)
    } else {
        const converted = emitI64ToValue(elemVal, itemType)
        emitIR(`  store ${itemLLType} ${converted}, ptr %${itemLLName}, align 8`)
    }

    genNestedBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${updateLabel2}`) }

    emitIR(`${updateLabel2}:`)
    terminated = 0
    const nextIdx = nextReg(); emitIR(`  ${nextIdx} = load i32, ptr ${idxAlloca}, align 4`)
    const incIdx = nextReg(); emitIR(`  ${incIdx} = add i32 ${nextIdx}, 1`)
    emitIR(`  store i32 ${incIdx}, ptr ${idxAlloca}, align 4`)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak2
    continueLabel = savedContinue2
    loopBlockStackSaved = savedLoopStack2
}
