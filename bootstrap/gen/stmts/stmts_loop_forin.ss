// gen/stmts_loop_forin.ss — for-in / for-of 循环。
// genForIn 不拆分:comptime/反射分支一拆即碎,genForInUnrolled 紧耦合同文件。

import { genBlock, genNestedBlock } from "./stmts_core"

// Compile-time for-in unroll. itemCsv is a comma-separated list of the values
// the loop variable takes on each iteration — from classFields when iterating
// obj.fields(), or from stringLitArrayCsv when iterating a string-literal array.
function genForInUnrolled(id: int, itemCsv: string, classContext: string = "") {
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

    // D095 FieldMeta: when looping over cls.fields, bind class context so
    // f.name / f.type can resolve per iteration.
    if (classContext != "") { comptimeConsts.set(`${itemName}.__class`, classContext) }

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
    if (classContext != "") { comptimeConsts.delete(`${itemName}.__class`) }

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

    // D089 Phase 4: comptime for-in over array
    if (comptimeDepth > 0) {
        const ctIterVal = genVal(iterableId)
        if (isCt(ctIterVal) == 1 && interpType(payload(ctIterVal)) == "array") {
            // D095 FieldMeta: detect `cls.fields` so nested FUNC_DECL cloning
            // can resolve f.name / f.type against the class in comptimeConsts.
            let ctFieldsClass = ""
            if (nGetKind(iterableId) == "MEMBER_ACCESS" && nGetS1(iterableId) == "fields") {
                const ctFObjVal = genVal(nGetI1(iterableId))
                if (isCt(ctFObjVal) == 1) {
                    const ctFObjStr = interpAsStr(payload(ctFObjVal))
                    if (isKnownClass(ctFObjStr) == 1) { ctFieldsClass = ctFObjStr }
                }
            }
            if (ctFieldsClass != "") {
                comptimeConsts.set(`${itemName}.__class`, ctFieldsClass)
            }
            const ctArrId = payload(ctIterVal)
            const ctArrLen = interpArrayLen(ctArrId)
            let ctFi = 0
            while (ctFi < ctArrLen) {
                const ctCurRaw = interpArrayGet(ctArrId, ctFi)
                // D117 Execute 3/4 边界: cls.fields 现返回 FieldMeta 对象数组。
                // foldComptimeIdentsInTree 只能 fold scalar tvKind,所以在 field-loop
                // 场景 unwrap 成 string tv(f.name),让 FUNC_DECL clone 路径里的
                // `get_${f.name}` 模板 fold → resolveComptimeString 仍然走 STRING_LIT。
                // sidecar comptimeConsts[f]/[f.__class] 承接 f.type/f.annotations 求值(D095 path)。
                const ctCurVal = (ctFieldsClass != "" && interpType(ctCurRaw) == "object") ? interpNewString(interpAsStr(interpGetField(ctCurRaw, "name"))) : ctCurRaw
                ctVars.set(`${currentFunc}:${itemName}`, `${ctVal(ctCurVal)}`)
                if (ctFieldsClass != "") { comptimeConsts.set(itemName, interpAsStr(ctCurVal)) }
                genBlock(bodyId)
                if (interpCheckLoopExit() == 1) { break }
                ctFi = ctFi + 1
            }
            if (ctFieldsClass != "") {
                comptimeConsts.delete(`${itemName}.__class`)
                comptimeConsts.delete(itemName)
            }
        }
        return
    }

    // D088: detect obj.fields() → compile-time unroll
    if (getMethodName(iterableId) == "fields") {
        const fieldsObjId = nGetI1(iterableId)
        const fieldsClass = resolveObjClass(fieldsObjId)
        if (fieldsClass != "" && classFields.has(fieldsClass) == 1) {
            const fsStr = classFields.getString(fieldsClass)
            genForInUnrolled(id, fsStr, fieldsClass)
            return
        }
    }

    // D095: detect "ClassName".fields (STRING_LIT.fields) → compile-time unroll.
    // Fires inside @methodOf body where cls IDENT was folded to string literal.
    if (nGetKind(iterableId) == "MEMBER_ACCESS" && nGetS1(iterableId) == "fields") {
        const mfObj = nGetI1(iterableId)
        if (nGetKind(mfObj) == "STRING_LIT") {
            const mfCls = nGetS1(mfObj)
            if (classFields.has(mfCls) == 1) {
                genForInUnrolled(id, classFields.getString(mfCls), mfCls)
                return
            }
        }
    }
    // L2ι: cls.methods unroll. No classContext passed — __class sidecar is
    // owned by L2ζ field-level .annotations; reusing it here would misroute.
    // L2κ: __methodCls sidecar binds method's owning class for inner m.annotations.
    if (nGetKind(iterableId) == "MEMBER_ACCESS" && nGetS1(iterableId) == "methods") {
        const mmObj = nGetI1(iterableId)
        if (nGetKind(mmObj) == "STRING_LIT") {
            const mmCls = nGetS1(mmObj)
            if (classMethods.has(mmCls) == 1) {
                const mmItemName = nGetS1(id)
                comptimeConsts.set(`${mmItemName}.__methodCls`, mmCls)
                genForInUnrolled(id, classMethods.getString(mmCls))
                comptimeConsts.delete(`${mmItemName}.__methodCls`)
                return
            }
        }
    }
    // D095 Stage C: f.annotations unroll — mirrors the .fields path but keyed on
    // comptimeConsts-bound field IDENT (set by the enclosing cls.fields loop's
    // genForInUnrolled). Item binding is plain string, no class context needed.
    if (nGetKind(iterableId) == "MEMBER_ACCESS" && nGetS1(iterableId) == "annotations") {
        const annObj = nGetI1(iterableId)
        if (nGetKind(annObj) == "IDENT" && comptimeConsts.has(nGetS1(annObj)) == 1) {
            const annFieldIdent = nGetS1(annObj)
            // L2κ: m.annotations when m is bound inside cls.methods unroll.
            // __methodCls sidecar (set by .methods branch) signals method-level lookup.
            const mAnnSidecarKey = `${annFieldIdent}.__methodCls`
            if (comptimeConsts.has(mAnnSidecarKey) == 1) {
                const mAnnCls = comptimeConsts.getString(mAnnSidecarKey)
                const mAnnName = comptimeConsts.getString(annFieldIdent)
                let mAnnCsv = ""
                const mAnnKey = `${mAnnCls}.${mAnnName}`
                if (classMethodAnnotations.has(mAnnKey) == 1) {
                    mAnnCsv = classMethodAnnotations.getString(mAnnKey)
                }
                // Only a.annotations is resolved here; a.args for method-level
                // annotations needs additional sidecar wiring not yet in place.
                genForInUnrolled(id, mAnnCsv)
                return
            }
            const annClsKey = `${annFieldIdent}.__class`
            if (comptimeConsts.has(annClsKey) == 1) {
                const annCls = comptimeConsts.getString(annClsKey)
                const annFld = comptimeConsts.getString(annFieldIdent)
                let annCsv = ""
                const annKey = `${annCls}.${annFld}`
                if (classFieldAnnotations.has(annKey) == 1) {
                    annCsv = classFieldAnnotations.getString(annKey)
                }
                // L2η sidecar: bind ${a}.__annCls / ${a}.__annFld so inner a.args
                // unroll can resolve classFieldAnnotationArgs keys.
                const annItemName = nGetS1(id)
                comptimeConsts.set(`${annItemName}.__annCls`, annCls)
                comptimeConsts.set(`${annItemName}.__annFld`, annFld)
                genForInUnrolled(id, annCsv)
                comptimeConsts.delete(`${annItemName}.__annCls`)
                comptimeConsts.delete(`${annItemName}.__annFld`)
                return
            }
        }
    }
    // L2η: a.args unroll (field-level). a = annotation name (per-iteration),
    // __annCls/__annFld sidecars identify the class+field owning the annotation.
    if (nGetKind(iterableId) == "MEMBER_ACCESS" && nGetS1(iterableId) == "args") {
        const argObj = nGetI1(iterableId)
        if (nGetKind(argObj) == "IDENT" && comptimeConsts.has(nGetS1(argObj)) == 1) {
            const argAnnIdent = nGetS1(argObj)
            const argClsKey = `${argAnnIdent}.__annCls`
            const argFldKey = `${argAnnIdent}.__annFld`
            if (comptimeConsts.has(argClsKey) == 1 && comptimeConsts.has(argFldKey) == 1) {
                const argAnnName = comptimeConsts.getString(argAnnIdent)
                const argCls = comptimeConsts.getString(argClsKey)
                const argFld = comptimeConsts.getString(argFldKey)
                let argCsv = ""
                const argKey = `${argCls}.${argFld}.${argAnnName}`
                if (classFieldAnnotationArgs.has(argKey) == 1) {
                    argCsv = classFieldAnnotationArgs.getString(argKey)
                }
                genForInUnrolled(id, argCsv)
                return
            }
        }
    }

    if (nGetKind(iterableId) == "ARRAY_LIT") {
        const litCsv = stringLitArrayCsv(iterableId)
        if (litCsv != "") {
            genForInUnrolled(id, litCsv)
            return
        }
    }

    const arr = genExpr(iterableId)
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
