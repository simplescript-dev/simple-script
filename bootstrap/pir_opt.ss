// Perceus IR — optimization passes (D019)
// Pass 1: Liveness Analysis — last-use → RC_DEC insertion
// Pass 2: Move Analysis — RC_INC+RC_DEC pair elimination
//
// Scans PIR instruction list in reverse, finds last-use point for each
// class-typed variable, and builds an emission schedule that maps AST
// statement IDs to RC_DEC operations.

// ── Pass 1: Liveness Analysis ────────────────────────────────────

function pirLivenessPass(pirBuf: string, funcName: string) {
    if (pirBuf == "") { return }

    // Step 1: Collect all class variables and their defining AST statements
    let classVars = Map()    // varName → "1"
    let defStmt = Map()      // varName → AST stmt node ID (defining statement)
    let escapedVars = Map()  // varName → "1" (returned/moved out of scope)

    const instrIds = pirBuf.split(",")
    for (iStr in instrIds) {
        const i = parseInt(iStr)
        if (i < 0) { continue }
        const kind = pirGetKind(i)
        if (kind == "ALLOC") {
            const vn = pirGetS1(i)
            classVars.set(vn, "1")
            defStmt.set(vn, `${pirGetI1(i)}`)
        }
        if (kind == "RC_INC" && pirGetS2(i) != "") {
            const vn = pirGetS2(i)
            classVars.set(vn, "1")
            defStmt.set(vn, `${pirGetI1(i)}`)
        }
        if (kind == "CALL" && pirGetS2(i) != "") {
            const vn = pirGetS2(i)
            classVars.set(vn, "1")
            defStmt.set(vn, `${pirGetI1(i)}`)
        }
        if (kind == "MOVE" && pirGetS2(i) == "__return__") {
            escapedVars.set(pirGetS1(i), "1")
        }
    }

    // Step 2: Reverse scan — find last use of each variable
    // "Use" = any instruction that reads the variable (USE, FIELD_SET, FIELD_GET,
    // RC_INC where var is source, RC_DEC)
    let lastUseStmt = Map()  // varName → AST stmt ID
    let seen = Map()         // varName → "1"

    // Build indexed array for reverse iteration (SS has no reverse for-in)
    let posMap = Map()
    let total = 0
    for (iStr in instrIds) {
        posMap.set(total + "", iStr)
        total = total + 1
    }

    let ri = total - 1
    while (ri >= 0) {
        const iStr = posMap.getString(ri + "")
        const i = parseInt(iStr)
        ri = ri - 1
        if (i < 0) { continue }

        const kind = pirGetKind(i)
        const astId = pirGetI1(i)

        // Determine which variable this instruction references
        // RC_DEC from reassignment also counts as a use of the variable
        let usedVar = ""
        if (kind == "USE" || kind == "FIELD_SET" || kind == "FIELD_GET" || kind == "RC_INC" || kind == "RC_DEC") {
            usedVar = pirGetS1(i)
        }

        if (usedVar == "") { continue }
        if (classVars.has(usedVar) == 0) { continue }
        if (seen.has(usedVar) == 1) { continue }

        seen.set(usedVar, "1")
        if (escapedVars.has(usedVar) == 0) {
            lastUseStmt.set(usedVar, `${astId}`)
        }
    }

    // Step 3: Variables with no post-definition uses → RC_DEC at defining stmt
    const allVarKeys = classVars.keys()
    if (allVarKeys == "") { return }
    const varList = allVarKeys.split("\n")
    for (vn in varList) {
        if (vn == "") { continue }
        if (escapedVars.has(vn) == 1) { continue }
        if (lastUseStmt.has(vn) == 1) { continue }
        // No use found — release at definition statement
        if (defStmt.has(vn) == 1) {
            lastUseStmt.set(vn, defStmt.getString(vn))
        }
    }

    // Step 4: Build emission schedule
    // pirSchedule[astStmtId] = "var1:type1|var2:type2"
    for (vn in varList) {
        if (vn == "") { continue }
        if (escapedVars.has(vn) == 1) { continue }
        if (lastUseStmt.has(vn) == 0) { continue }

        const astId = parseInt(lastUseStmt.getString(vn))
        const ssType = pirGetType(vn)
        if (ssType == "" || pirIsClass(ssType) == 0) { continue }

        const entry = `${vn}:${ssType}`
        if (pirSchedule.has(astId + "") == 1) {
            const existing = pirSchedule.getString(astId + "")
            pirSchedule.set(astId + "", `${existing}|${entry}`)
        } else {
            pirSchedule.set(astId + "", entry)
        }
        pirManagedLLVars.set(`__pir_${vn}`, "1")
    }
}

// ── Pass 2: Move Analysis ─────────────────────────────────────
// Eliminates redundant RC_INC+RC_DEC pairs. Pattern:
//   RC_INC src=A dst=B (at AST stmt S)  +  RC_DEC A scheduled at S
// → A's last use IS the RC_INC, so retain+release cancel out.
//   Remove A's RC_DEC from schedule, mark S as a move assignment
//   (genVarDecl skips ss_retain).

function pirMoveAnalysis(pirBuf: string) {
    if (pirBuf == "") { return }

    const instrIds = pirBuf.split(",")
    for (iStr in instrIds) {
        const i = parseInt(iStr)
        if (i < 0) { continue }
        const kind = pirGetKind(i)
        if (kind != "RC_INC") { continue }

        const src = pirGetS1(i)
        const astId = pirGetI1(i)
        if (src == "" || astId <= 0) { continue }

        // Check: is src's RC_DEC scheduled at this same AST statement?
        const key = astId + ""
        if (pirSchedule.has(key) == 0) { continue }
        const schedule = pirSchedule.getString(key)
        if (schedule == "") { continue }

        // Find src entry in schedule (format: "var1:type1|var2:type2")
        const ssType = pirGetType(src)
        if (ssType == "" || pirIsClass(ssType) == 0) { continue }
        const target = `${src}:${ssType}`

        if (schedule.contains(target) == 0) { continue }

        // Match! Remove src's RC_DEC from schedule
        const parts = schedule.split("|")
        let remaining = ""
        for (p in parts) {
            if (p == target) { continue }
            if (p == "") { continue }
            if (remaining == "") { remaining = p }
            else { remaining = `${remaining}|${p}` }
        }
        pirSchedule.set(key, remaining)

        // Mark src as released — ownership transferred to dst
        pirReleasedVars.set(src, "1")

        // Mark this AST stmt as a move assignment (skip retain in genVarDecl)
        pirMoveStmts.set(key, "1")
    }
}

// ── Pass 3: Uniqueness Analysis ───────────────────────────────
// Statically prove rc==1 at release → direct drop (skip ss_release overhead).
// A variable is provably unique at release if:
//   1. Created by ALLOC (rc starts at 1)
//   2. Never used as RC_INC source (no shared references)
//   3. Never reassigned (no RC_DEC from pirLowerAssign)
//   4. Not already released by Move Analysis
//   5. Not passed as constructor arg (constructor retains ref-type params)

function pirUniquenessPass(pirBuf: string) {
    if (pirBuf == "") { return }

    let allocVars = Map()
    let nonUniqueVars = Map()
    let allocStmts = Map()

    const instrIds = pirBuf.split(",")
    for (iStr in instrIds) {
        const i = parseInt(iStr)
        if (i < 0) { continue }
        const kind = pirGetKind(i)

        if (kind == "ALLOC") {
            allocVars.set(pirGetS1(i), "1")
            allocStmts.set(pirGetI1(i) + "", pirGetS1(i))
        }
        if (kind == "RC_INC") {
            nonUniqueVars.set(pirGetS1(i), "1")
        }
        if (kind == "RC_DEC") {
            nonUniqueVars.set(pirGetS1(i), "1")
        }
        // Constructor arg check: USE at same stmt as ALLOC of different var
        // (ALLOC emitted before USE in PIR, so allocStmts is populated)
        if (kind == "USE") {
            const usedVar = pirGetS1(i)
            const astId = pirGetI1(i) + ""
            if (allocStmts.has(astId) == 1 && allocStmts.getString(astId) != usedVar) {
                nonUniqueVars.set(usedVar, "1")
            }
        }
    }

    const allKeys = allocVars.keys()
    if (allKeys == "") { return }
    const varList = allKeys.split("\n")
    for (vn in varList) {
        if (vn == "") { continue }
        if (nonUniqueVars.has(vn) == 1) { continue }
        if (pirReleasedVars.has(vn) == 1) { continue }
        pirUniqueAtRelease.set(vn, "1")
    }
}

// ── Pass 5: Reuse Analysis ──────────────────────────────────────
// Detect drop+alloc patterns: when a unique variable is dropped and the
// immediately following statement allocates a new object of the SAME type,
// we can reuse the memory (skip mi_free + mi_calloc).
// Pattern: pirSchedule[prevStmt] has "dropVar:Type" (unique), next stmt has ALLOC of same Type.

function pirReusePass(pirBuf: string) {
    if (pirBuf == "") { return }

    let prevStmtId = 0
    let usedDrops = Map()

    const instrIds = pirBuf.split(",")
    for (iStr in instrIds) {
        const i = parseInt(iStr)
        if (i < 0) { continue }
        const kind = pirGetKind(i)
        const curStmtId = pirGetI1(i)

        if (kind == "ALLOC") {
            const allocVar = pirGetS1(i)
            const allocClass = pirGetS2(i)

            // Check previous statement's schedule for a matching unique drop
            if (prevStmtId > 0 && prevStmtId != curStmtId && pirSchedule.has(prevStmtId + "") == 1) {
                const schedule = pirSchedule.getString(prevStmtId + "")
                if (schedule != "") {
                    const sParts = schedule.split("|")
                    for (sp in sParts) {
                        if (sp == "") { continue }
                        const dropVar = pirParseEntryVar(sp)
                        const dropType = pirParseEntryType(sp)
                        if (dropVar == "" || dropType == "") { continue }
                        // Match: same type + unique + not already used for another reuse
                        if (dropType == allocClass && pirUniqueAtRelease.has(dropVar) == 1 && usedDrops.has(dropVar) == 0) {
                            pirReuseAllocs.set(allocVar, `${dropVar}:${allocClass}`)
                            pirReuseDrops.set(dropVar, allocVar)
                            usedDrops.set(dropVar, "1")
                        }
                    }
                }
            }
        }

        // Track statement boundaries
        if (curStmtId > 0 && curStmtId != prevStmtId) {
            prevStmtId = curStmtId
        }
    }
}
