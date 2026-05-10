// gen_emit.ss — LLVM IR text buffer + SSA register/label primitives + string constant pool

// ── State ─────────────────────────────────────────────────────

let irBuf = ""
let strConsts = ""
let strCount = 0
let irOutFile = ""
let strOutFile = ""
let regCount = 0
let regTable: Array<string> = []
let labelCount = 0

// SS-LIM-4 entry-alloca hoist (gen_emit.ss owns the buffer + splice).
// All user-code-path alloca calls go through emitEntryAlloca → funcEntryAllocas.
// startFuncEmit/endFuncEmit wrap each function body emit so alloca physical
// position lands right after `entry:` (LLVM dominate-all-uses standard).
//
// Nesting model — stack-based: each startFuncEmit pushes (entryAllocas/Anchor/
// Active + irBuf/irOutFile/strOutFile) onto the 6 stacks then resets to a
// fresh frame; endFuncEmit splices funcEntryAllocas into the freshly emitted
// irBuf, **returns** the spliced funcIR string, then pops saved state. Caller
// routes the returned funcIR to its target (outFile via appendFile, outer
// irBuf, arrowDefs, genericSpecDefs, ...). Supports
// main → genGenericCall → identity_int 三层 + 多 arrow / generic 嵌套.
let funcEntryAllocas = ""
let funcEntryAnchor = -1
let funcEmitActive = 0
let funcEmitAllocasStack: Array<string> = []
let funcEmitAnchorStack: Array<string> = []
let funcEmitActiveStack: Array<string> = []
let funcEmitIrBufStack: Array<string> = []
let funcEmitIrOutStack: Array<string> = []
let funcEmitStrOutStack: Array<string> = []

// ── IR emit / SSA counters ────────────────────────────────────

function emitIR(s: string) {
    if (irOutFile != "") {
        appendFile(irOutFile, `${s}\n`)
    } else {
        irBuf = `${irBuf}${s}\n`
    }
}

// SS-LIM-4 — start a function body emit window. Pushes current 6-state to
// stacks then resets. Caller must pair with endFuncEmit() and route the
// returned funcIR to the appropriate target (outFile / outer irBuf /
// arrowDefs / genericSpecDefs).
function startFuncEmit() {
    funcEmitAllocasStack = funcEmitAllocasStack.push(funcEntryAllocas)
    funcEmitAnchorStack = funcEmitAnchorStack.push(`${funcEntryAnchor}`)
    funcEmitActiveStack = funcEmitActiveStack.push(`${funcEmitActive}`)
    funcEmitIrBufStack = funcEmitIrBufStack.push(irBuf)
    funcEmitIrOutStack = funcEmitIrOutStack.push(irOutFile)
    funcEmitStrOutStack = funcEmitStrOutStack.push(strOutFile)
    if (irOutFile != "") { strOutFile = irOutFile }
    irOutFile = ""
    irBuf = ""
    funcEntryAllocas = ""
    funcEntryAnchor = -1
    funcEmitActive = 1
}

function markEntryAllocaPoint() {
    if (funcEmitActive == 0) { return }
    funcEntryAnchor = irBuf.length()
}

// Emit alloca that should live in entry block (auto-hoist).
// reg: register name like "%foo" or "%42" (with leading %)
// LLVM SSA digit register sequence must be ascending by first-use position;
// hoisting a digit-named alloca (%42) to entry would put high-N before low-N
// and crash the verifier. Detect digit registers and rename to %hoist.N to
// keep them off the SSA digit ladder. Caller MUST use the returned reg name.
function emitEntryAlloca(reg: string, llType: string, align: int): string {
    let regOut = reg
    if (reg.length() >= 2 && reg.charAt(0) == "%") {
        const c1 = charCodeAt(reg, 1)
        if (c1 >= 48 && c1 <= 57) {
            regOut = `%hoist.${reg.substring(1, reg.length() - 1)}`
        }
    }
    if (funcEmitActive == 0 || funcEntryAnchor < 0) {
        emitIR(`  ${regOut} = alloca ${llType}, align ${align}`)
        return regOut
    }
    funcEntryAllocas = `${funcEntryAllocas}  ${regOut} = alloca ${llType}, align ${align}\n`
    return regOut
}

// Splice funcEntryAllocas into irBuf at funcEntryAnchor (immediately after
// `entry:`), capture the spliced function IR string, pop saved 6-state, and
// return the funcIR for caller-controlled routing.
function endFuncEmit(): string {
    if (funcEntryAllocas != "" && funcEntryAnchor >= 0) {
        const before = irBuf.substring(0, funcEntryAnchor)
        const afterLen = irBuf.length() - funcEntryAnchor
        const after = irBuf.substring(funcEntryAnchor, afterLen)
        irBuf = `${before}${funcEntryAllocas}${after}`
    }
    const funcIR = irBuf
    const top = funcEmitAllocasStack.length() - 1
    if (top < 0) {
        funcEntryAllocas = ""
        funcEntryAnchor = -1
        funcEmitActive = 0
        irBuf = ""
        irOutFile = ""
        strOutFile = ""
        return funcIR
    }
    funcEntryAllocas = funcEmitAllocasStack[top]
    funcEntryAnchor = parseInt(funcEmitAnchorStack[top])
    funcEmitActive = parseInt(funcEmitActiveStack[top])
    irBuf = funcEmitIrBufStack[top]
    irOutFile = funcEmitIrOutStack[top]
    strOutFile = funcEmitStrOutStack[top]
    funcEmitAllocasStack = funcEmitAllocasStack.slice(0, top)
    funcEmitAnchorStack = funcEmitAnchorStack.slice(0, top)
    funcEmitActiveStack = funcEmitActiveStack.slice(0, top)
    funcEmitIrBufStack = funcEmitIrBufStack.slice(0, top)
    funcEmitIrOutStack = funcEmitIrOutStack.slice(0, top)
    funcEmitStrOutStack = funcEmitStrOutStack.slice(0, top)
    return funcIR
}

function nextReg(): string {
    regCount = regCount + 1
    return `%${regCount}`
}

function nextLabel(prefix: string): string {
    labelCount = labelCount + 1
    return `${prefix}.${labelCount}`
}

// ── String constant pool ──────────────────────────────────────

function addStringConst(value: string): string {
    const name = `@.str.${strCount}`
    strCount = strCount + 1
    // Escape the string for LLVM IR c"..." format
    let escaped = ""
    let i = 0
    const sLen = value.length()
    while (i < sLen) {
        const ch = value.charAt(i)
        if (ch == "\n") { escaped = escaped + "\\0A"
        } else if (ch == "\r") { escaped = escaped + "\\0D"
        } else if (ch == "\t") { escaped = escaped + "\\09"
        } else if (ch == "\\") { escaped = escaped + "\\5C"
        } else if (ch == "\"") { escaped = escaped + "\\22"
        } else { escaped = escaped + ch }
        i = i + 1
    }
    // D168 §B.2: 字面量 boxed — 双全局常量(@.bytes.N 裸 bytes + @.str.N %String header immortal RC=-1)
    const allocLen = sLen + 1
    const bytesName = `@.bytes.${strCount - 1}`
    const bytesLine = `${bytesName} = constant [${allocLen} x i8] c"${escaped}\\00"\n`
    const headerLine = `${name} = constant %String { i64 -1, ptr @String_type_info, ptr ${bytesName}, i64 ${sLen}, i64 ${allocLen} }\n`
    // strOutFile overrides irOutFile for string constant output (used by arrow functions)
    const strTarget = strOutFile ?? irOutFile
    if (strTarget != "") {
        appendFile(`${strTarget}.str`, bytesLine)
        appendFile(`${strTarget}.str`, headerLine)
    } else {
        strConsts = strConsts + bytesLine
        strConsts = strConsts + headerLine
    }
    return name
}
