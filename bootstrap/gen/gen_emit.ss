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

// ── IR emit / SSA counters ────────────────────────────────────

function emitIR(s: string) {
    if (irOutFile != "") {
        appendFile(irOutFile, `${s}\n`)
    } else {
        irBuf = `${irBuf}${s}\n`
    }
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
    const line = `${name} = constant [${sLen + 1} x i8] c"${escaped}\\00"\n`
    // strOutFile overrides irOutFile for string constant output (used by arrow functions)
    const strTarget = strOutFile ?? irOutFile
    if (strTarget != "") {
        appendFile(`${strTarget}.str`, line)
    } else {
        strConsts = strConsts + line
    }
    return name
}
