// Reference counting helpers for bootstrap codegen
// ── RC state + scope tracking + cycle detection ──────────────

// ── RC global state ──────────────────────────────────────────
// localPtrVars / blockPtrVarStack schema — "name:type" entries 用 ";" 分隔,
// "|" 分隔 block(type 内 "," 不冲突,Map<K,V> 嵌套泛型安全)。
// D168 §C.11: emitReleaseVarList 经 isRcManaged(读 type 段)判定后对 RC-managed
// 局部发 ss_release_any(magic@-4 运行时分派);Ref/Channel 等第三类对象跳过。

let localPtrVars = ""        // "name1:type1;name2:type2;..."
let localFnVars = ""         // fn-typed locals holding closures (released via ss_release)
let rcBlockDepth = 0
let blockPtrVarStack = ""    // "|"-separated segments of "name:type;..." entries
let loopBlockStackSaved = "" // saved blockPtrVarStack at loop entry (for break/continue)
let lastExprStringOwned = 0
let nonOwningFields = ""     // Map: "ClassName.fieldName" -> "1" (non-owning container fields)
let pushNonOwning = 0        // flag: current push target is non-owning container

function initRcState() {
    localPtrVars = ""
    localFnVars = ""
    rcBlockDepth = 0
    blockPtrVarStack = ""
    loopBlockStackSaved = ""
    lastExprStringOwned = 0
    pushNonOwning = 0
    nonOwningFields = Map()
}

// ── Ptr var entry helpers ("name:type" schema, ";" sep) ──

function rcAppendEntry(list: string, name: string, ssType: string): string {
    const entry = `${name}:${ssType}`
    if (list == "" || list.endsWith("|") == 1) { return `${list}${entry}` }
    return `${list};${entry}`
}

function rcEntryName(entry: string): string {
    const ci = entry.indexOf(":")
    if (ci < 0) { return entry }
    return entry.substring(0, ci)
}

// Extract the type segment of a "name:type" entry (D168 §C.11 isRcManaged 判定)。
function rcEntryType(entry: string): string {
    const ci = entry.indexOf(":")
    if (ci < 0) { return "" }
    return entry.substring(ci + 1, entry.length())
}

// D168 §C.11: 该 SS 类型是否由 OLD(Map/Set)或 NEW(string/Array/class)RC 系统管理
// —— 仅此二类的对象头能被 ss_*_any 的 magic@-4 分派正确识别。Ref/Channel 等 calloc'd
// 第三类对象(无 magic 亦非 ObjHeader)返 0,codegen-local RC 跳过(D082 自管生命周期);
// 类型不精确(""/泛型 T)亦返 0 → 保守跳过(泄漏不崩,优于误 ss_release 致 UAF)。
function isRcManaged(ssType: string): int {
    const t = stripNullableCG(ssType)
    if (t == "string") { return 1 }
    if (isArrayType(t) == 1) { return 1 }
    if (t == "Map" || t.startsWith("Map<") == 1) { return 1 }
    if (t == "Set" || t.startsWith("Set<") == 1) { return 1 }
    if (isUserClass(t) == 1) { return 1 }
    return 0
}

// ── Ptr var tracking ─────────────────────────────────────────

// Track a ptr var for RC release — adds to function-level or block-level list.
// ssType 存入 entry type 段 —— emitReleaseVarList 的 isRcManaged 据此分派(D168 §C.11)。
function trackPtrVar(llName: string, ssType: string) {
    if (rcBlockDepth == 0) {
        // Function-level: track in localPtrVars (released at function exit)
        localPtrVars = rcAppendEntry(localPtrVars, llName, ssType)
    } else {
        // Block-level: track in blockPtrVarStack (released at block exit)
        blockPtrVarStack = rcAppendEntry(blockPtrVarStack, llName, ssType)
    }
}

// Check if a variable is tracked for RC (was retained at declaration)
function isTrackedPtrVar(llName: string): int {
    // Check function-level tracked vars
    if (localPtrVars != "") {
        const parts = localPtrVars.split(";")
        for (p in parts) {
            if (rcEntryName(p) == llName) { return 1 }
        }
    }
    // Check block-level tracked vars
    if (blockPtrVarStack != "") {
        const segments = blockPtrVarStack.split("|")
        for (seg in segments) {
            if (seg == "") { continue }
            const vars = seg.split(";")
            for (v in vars) {
                if (rcEntryName(v) == llName) { return 1 }
            }
        }
    }
    return 0
}

// ── Block scope management ───────────────────────────────────

// Push a new block scope onto blockPtrVarStack
function pushBlockScope() {
    if (blockPtrVarStack != "") {
        blockPtrVarStack = `${blockPtrVarStack}|`
    }
}

// Pop the current block scope from the stack (no emit)
function popBlockScope() {
    if (blockPtrVarStack == "") { return }
    const lastPipe = lastIndexOf(blockPtrVarStack, "|")
    if (lastPipe < 0) {
        blockPtrVarStack = ""
    } else {
        blockPtrVarStack = blockPtrVarStack.substring(0, lastPipe)
    }
}

// ── Release helpers ──────────────────────────────────────────

// Emit release for a ";"-separated entry list ("name:type;name:type;...").
// D168 §C.11: RC-managed 局部(isRcManaged: OLD Map/Set + NEW string/Array/class)
// 经 ss_release_any 按运行时 magic@-4 分派 —— NEW 走 ss_release / OLD 走 ss_rc_release,
// 与 genVarDecl/genAssign/genReturn 的 ss_retain_any 配对侧对称。Ref/Channel 等第三类
// calloc'd 对象(无 OLD magic 亦非 NEW ObjHeader)isRcManaged=0 跳过 —— ss_*_any 会误
// 读其布局致 UAF,其生命周期由 D082 自管;type 不精确亦跳过(保守泄漏不崩)。
function emitReleaseVarList(varList: string) {
    if (varList == "") { return }
    const parts = varList.split(";")
    for (p in parts) {
        if (p == "") { continue }
        const name = rcEntryName(p)
        if (name == "") { continue }
        if (isRcManaged(rcEntryType(p)) == 0) { continue }
        const r = nextReg()
        emitIR(`  ${r} = load ptr, ptr %${name}, align 8`)
        emitIR(`  call void @ss_release_any(ptr ${r})`)
    }
}

// Emit release calls for all tracked local ptr vars
function emitReleaseLocals() {
    emitReleaseVarList(localPtrVars)
}

// Track a fn-typed local for closure release
function trackFnVar(llName: string) {
    localFnVars = listAppendStr(localFnVars, llName)
}

// Emit release for fn-typed locals (closures with tag bit)
function emitReleaseFnLocals() {
    if (localFnVars == "") { return }
    const parts = localFnVars.split(",")
    for (p in parts) {
        if (p == "") { continue }
        const valR = nextReg()
        emitIR(`  ${valR} = load i64, ptr %${p}, align 8`)
        const tagR = nextReg()
        emitIR(`  ${tagR} = and i64 ${valR}, 1`)
        const isClR = nextReg()
        emitIR(`  ${isClR} = icmp eq i64 ${tagR}, 1`)
        const lblRel = nextLabel("fn.release")
        const lblSkip = nextLabel("fn.skip")
        emitIR(`  br i1 ${isClR}, label %${lblRel}, label %${lblSkip}`)
        emitIR(`${lblRel}:`)
        const untagR = nextReg()
        emitIR(`  ${untagR} = and i64 ${valR}, -2`)
        const ptrR = nextReg()
        emitIR(`  ${ptrR} = inttoptr i64 ${untagR} to ptr`)
        emitIR(`  call void @ss_release(ptr ${ptrR})`)
        emitIR(`  br label %${lblSkip}`)
        emitIR(`${lblSkip}:`)
    }
}

// Release vars in the current (top) block scope
function emitReleaseCurrentBlockVars() {
    if (blockPtrVarStack == "") { return }
    const lastPipe = lastIndexOf(blockPtrVarStack, "|")
    let currentSeg = ""
    if (lastPipe < 0) {
        currentSeg = blockPtrVarStack
    } else {
        currentSeg = blockPtrVarStack.substring(lastPipe + 1, blockPtrVarStack.length())
    }
    emitReleaseVarList(currentSeg)
}

// Release all block vars (for return inside nested blocks)
function emitReleaseAllBlockVars() {
    if (blockPtrVarStack == "") { return }
    const segments = blockPtrVarStack.split("|")
    for (seg in segments) {
        emitReleaseVarList(seg)
    }
}

// Release block vars added since savedStack (for break/continue)
function emitReleaseBlockVarsSince(savedStack: string) {
    if (blockPtrVarStack == savedStack) { return }
    let newPart = ""
    if (savedStack == "") {
        newPart = blockPtrVarStack
    } else {
        const start = savedStack.length() + 1
        if (start < blockPtrVarStack.length()) {
            newPart = blockPtrVarStack.substring(start, blockPtrVarStack.length())
        }
    }
    if (newPart == "") { return }
    const segments = newPart.split("|")
    for (seg in segments) {
        emitReleaseVarList(seg)
    }
}

// ── Map value type check ─────────────────────────────────────

function mapValueIsPtr(typeAnn: string): int {
    if (typeAnn == "") { return 0 }
    if (typeAnn.startsWith("Map<") == 0) { return 0 }
    const inner = typeAnn.substring(4, typeAnn.length() - 1)
    const commaIdx = inner.indexOf(",")
    if (commaIdx < 0) { return 0 }
    // Skip ", " after comma
    let valStart = commaIdx + 1
    if (valStart < inner.length()) {
        if (inner.substring(valStart, valStart + 1) == " ") {
            valStart = valStart + 1
        }
    }
    const valType = inner.substring(valStart, inner.length())
    if (valType == "") { return 0 }
    const llType = ssTypeToLLVM(valType)
    return llType == "ptr" ? 1 : 0
}

// ── Cyclic ownership detection ───────────────────────────────
// Detect cyclic ownership through container fields (Array<X>, Map<K,X>).
// Mark container fields on cycle paths as non-owning.

// Find which class in the chain owns a field (for type lookup)
function findFieldOwner(fieldName: string, cls: string): string {
    if (cls == "") { return "" }
    const ownFields = classFields.getString(cls)
    if (ownFields.contains(fieldName) == 1) {
        if (classFieldTypes.has(`${cls}.${fieldName}`) == 1) { return cls }
    }
    const parent = classParents.has(cls) == 1 ? classParents.getString(cls) : ""
    return findFieldOwner(fieldName, parent)
}

function extractContainerElemType(t: string): string {
    if (t.startsWith("Array<") == 1 && t.endsWith(">") == 1) {
        return t.substring(6, t.length() - 7)
    }
    if (t.startsWith("Map<") == 1 && t.endsWith(">") == 1) {
        const inner = t.substring(4, t.length() - 5)
        const ci = inner.indexOf(",")
        if (ci >= 0) {
            return inner.substring(ci + 1, inner.length() - ci - 1)
        }
    }
    return ""
}

function canReachClass(fromClass: string, targetClass: string): int {
    if (fromClass == targetClass) { return 1 }
    if (fromClass == "" || classFields.has(fromClass) == 0) { return 0 }
    // BFS through class field type graph
    let queue = fromClass
    let visited = new Map()
    visited.set(fromClass, "1")
    while (queue != "") {
        let current = queue
        const ci = queue.indexOf(",")
        if (ci >= 0) {
            current = queue.substring(0, ci)
            queue = queue.substring(ci + 1, queue.length() - ci - 1)
        } else {
            queue = ""
        }
        if (current == "" || classFields.has(current) == 0) { continue }
        const fieldStr = classFields.getString(current)
        if (fieldStr == "") { continue }
        const fields = fieldStr.split(",")
        for (f in fields) {
            if (f == "") { continue }
            const owner = findFieldOwner(f, current)
            if (owner == "") { continue }
            const ft = classFieldTypes.getString(`${owner}.${f}`)
            if (ft == "") { continue }
            // Extract referenced class type (from container or direct)
            let refClass = extractContainerElemType(ft)
            if (refClass == "" && classFields.has(ft) == 1) { refClass = ft }
            if (refClass == "") { continue }
            if (refClass == targetClass) { return 1 }
            if (classFields.has(refClass) == 1 && visited.has(refClass) == 0) {
                visited.set(refClass, "1")
                if (queue == "") { queue = refClass }
                else { queue = `${queue},${refClass}` }
            }
        }
    }
    return 0
}

function detectCyclicOwnership() {
    const cList = classFields.keys()
    for (cls in cList) {
        if (cls == "" || cls == "Map" || cls == "Math") { continue }
        const fieldStr = classFields.getString(cls)
        if (fieldStr == "") { continue }
        const fields = fieldStr.split(",")
        for (f in fields) {
            if (f == "") { continue }
            const owner = findFieldOwner(f, cls)
            if (owner == "") { continue }
            const ft = classFieldTypes.getString(`${owner}.${f}`)
            if (ft == "") { continue }
            // Only container fields can create cycles (class fields are immutable)
            const elemType = extractContainerElemType(ft)
            if (elemType == "") { continue }
            if (classFields.has(elemType) == 0) { continue }
            // Check if element type can reach back to this class
            if (canReachClass(elemType, cls) == 1) {
                nonOwningFields.set(`${cls}.${f}`, "1")
            }
        }
    }
}
