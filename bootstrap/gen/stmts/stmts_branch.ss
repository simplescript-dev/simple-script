// gen/stmts_branch.ss — 分支:if / switch。

import { emitCondToI1, genBlock, genNestedBlock } from "./stmts_core"

function genIf(id: int) {
    const condId = nGetI1(id)
    const thenId = nGetI2(id)
    const elseId = nGetI3(id)

    // D089 Phase 3: comptime condition in comptime block → only codegen hit branch
    if (comptimeMustBeKnown == 1) {
        const condTagged = genVal(condId)
        if (isCt(condTagged) == 1) {
            if (interpTruthy(payload(condTagged)) == 1) {
                genBlock(thenId)
            } else if (elseId > 0) {
                genBlock(elseId)
            }
        }
        return
    }

    const condVal = genExpr(condId)
    const thenLabel = nextLabel("if.then")
    const elseLabel = nextLabel("if.else")
    const mergeLabel = nextLabel("if.merge")

    const r = emitCondToI1(condId, condVal)

    if (elseId > 0) {
        emitIR(`  br i1 ${r}, label %${thenLabel}, label %${elseLabel}`)
    } else {
        emitIR(`  br i1 ${r}, label %${thenLabel}, label %${mergeLabel}`)
    }

    emitIR(`${thenLabel}:`)
    terminated = 0
    genNestedBlock(thenId)
    if (terminated == 0) {
        emitIR(`  br label %${mergeLabel}`)
    }

    if (elseId > 0) {
        emitIR(`${elseLabel}:`)
        terminated = 0
        genNestedBlock(elseId)
        if (terminated == 0) {
            emitIR(`  br label %${mergeLabel}`)
        }
    }

    terminated = 0
    emitIR(`${mergeLabel}:`)
}

function genSwitch(id: int) {
    const subjectId = nGetI1(id)
    const defaultId = nGetI2(id)
    const caseList = nGetList(id)

    if (comptimeMustBeKnown == 1) {
        const subjTagged = genVal(subjectId)
        if (isCt(subjTagged) == 1) {
            const subjPayload = payload(subjTagged)
            const subjKind = interpType(subjPayload)
            const subjStr = interpAsStr(subjPayload)
            const subjInt = subjKind == "int" ? interpAsInt(subjPayload) : 0
            let matched = 0
            if (caseList != "") {
                const ctCases = caseList.split(",")
                for (cc in ctCases) {
                    const ctCaseId = parseInt(cc)
                    if (ctCaseId <= 0) { continue }
                    const ctPatList = nGetList(ctCaseId)
                    const ctBodyId = nGetI2(ctCaseId)
                    let hit = 0
                    if (ctPatList != "") {
                        const ctPats = ctPatList.split(",")
                        let cpi = 0
                        while (cpi < ctPats.length()) {
                            const ctPatId = parseInt(ctPats[cpi].trim())
                            cpi = cpi + 1
                            if (ctPatId <= 0) { continue }
                            const ctPatType = nGetS1(ctPatId)
                            const ctPatVal = nGetS2(ctPatId)
                            if (ctPatType == "STRING") {
                                if (subjStr == ctPatVal) { hit = 1 }
                            } else if (ctPatType == "INT") {
                                if (subjInt == parseInt(ctPatVal)) { hit = 1 }
                            } else if (ctPatType == "BOOL") {
                                if (interpTruthy(subjPayload) == parseInt(ctPatVal)) { hit = 1 }
                            } else if (ctPatType == "ENUM") {
                                if (interpEnumValues.has(ctPatVal) == 1) {
                                    const ctResolved = interpEnumValues.getString(ctPatVal)
                                    if (subjKind == "string") {
                                        if (subjStr == ctResolved) { hit = 1 }
                                    } else {
                                        if (subjInt == parseInt(ctResolved)) { hit = 1 }
                                    }
                                }
                            }
                            if (hit == 1) { break }
                        }
                    }
                    if (hit == 1) {
                        genBlock(ctBodyId)
                        matched = 1
                        break
                    }
                }
            }
            if (matched == 0 && defaultId > 0) { genBlock(defaultId) }
            if (interpBreakFlag == 1) { interpBreakFlag = 0 }
        }
        return
    }

    const subjectVal = genExpr(subjectId)
    const subjectType = inferType(subjectId)
    const afterLabel = nextLabel("switch.end")

    if (caseList != "") {
        const cases = caseList.split(",")
        for (c in cases) {
            const caseId = parseInt(c)
            if (caseId <= 0) { continue }
            const patList = nGetList(caseId)
            const bodyId = nGetI2(caseId)
            const thenLabel = nextLabel("switch.case")
            const nextCaseLabel = nextLabel("switch.next")

            if (patList != "") {
                const pats = patList.split(",")
                let pi = 0
                while (pi < pats.length()) {
                    const patId = parseInt(pats[pi].trim())
                    pi = pi + 1
                    if (patId <= 0) { continue }
                    const patType = nGetS1(patId)
                    const patVal = nGetS2(patId)
                    let cmpResult = ""
                    let resolvedVal = patVal
                    let useStringCmp = 0
                    if (patType == "STRING" || subjectType == "string") { useStringCmp = 1 }
                    if (patType == "ENUM") {
                        if (enumValues.has(patVal) == 0) {
                            println(`error: unknown enum value '${patVal}' in switch case`)
                            exit(1)
                        }
                        resolvedVal = enumValues.getString(patVal)
                        const dotIdx = patVal.indexOf(".")
                        if (dotIdx > 0 && enumTypes.has(patVal.substring(0, dotIdx)) == 1) { useStringCmp = 1 }
                    }
                    if (useStringCmp == 1) {
                        const patStr = addStringConst(resolvedVal)
                        const cmp = nextReg(); emitIR(`  ${cmp} = call i32 @ss_string_eq(ptr ${subjectVal}, ptr ${patStr})`)
                        const br = nextReg(); emitIR(`  ${br} = icmp ne i32 ${cmp}, 0`)
                        cmpResult = br
                    } else {
                        const cmp = nextReg(); emitIR(`  ${cmp} = icmp eq i32 ${subjectVal}, ${resolvedVal}`)
                        cmpResult = cmp
                    }
                    if (pi < pats.length()) {
                        const nextPatLabel = nextLabel("switch.pat")
                        emitIR(`  br i1 ${cmpResult}, label %${thenLabel}, label %${nextPatLabel}`)
                        emitIR(`${nextPatLabel}:`)
                    } else {
                        emitIR(`  br i1 ${cmpResult}, label %${thenLabel}, label %${nextCaseLabel}`)
                    }
                }
            }

            emitIR(`${thenLabel}:`)
            terminated = 0
            genNestedBlock(bodyId)
            if (terminated == 0) { emitIR(`  br label %${afterLabel}`) }
            emitIR(`${nextCaseLabel}:`)
        }
    }
    // Last switch.next block is the no-match fallthrough — needs a terminator
    terminated = 0
    // Default case
    if (defaultId > 0) {
        genNestedBlock(defaultId)
    }
    if (terminated == 0) { emitIR(`  br label %${afterLabel}`) }
    emitIR(`${afterLabel}:`)
    terminated = 0
}
