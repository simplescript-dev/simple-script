// SimpleScript Bootstrap Comptime Driver
// SEMA ↔ IR 桥接:comptime 块的 SS/IR buffer flush、CLASS_DECL 预扫描 + 延迟发射。
// 依赖 codegen.ss 暴露的 registerClass/genStmt 等 codegen 钩子,以及 interp_core.ss
// 的 ctVars/interp* 状态通道。

// comptime 块里声明的 CLASS_DECL AST id。flushPendingCtClasses() 消费后清空。
// 延迟到主 codegen pass 外发射,避免在其他函数体 IR 输出中途插入 class IR。
let pendingCtClassIds: Array<string> = []

// Flush @comptimeEmit SS source: tokenize → parse → multi-pass codegen.
// Shared by COMPTIME_BLOCK (gen_stmts) and COMPTIME_EXPR (gen_types).
function flushComptimeSS() {
    const fss = interpGetComptimeSS()
    if (fss == "") { return }
    const fssTokens = tokenize(fss)
    const fssRoot = parse(fssTokens)
    const fssList = nGetList(fssRoot)
    if (fssList != "") {
        const fssParts = fssList.split(",")
        // Pass 0: VAR_DECL → global vars
        const fssSavedFunc = currentFunc
        currentFunc = ""
        emitGlobalVars(fssList)
        currentFunc = fssSavedFunc
        // Pass 1: CLASS_DECL/ENUM_DECL/INTERFACE_DECL → register before codegen
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid <= 0) { continue }
            const fsKind = nGetKind(fsSid)
            if (fsKind == "CLASS_DECL") {
                registerClass(fsSid)
                collectClassAnnotations(fsSid)
                resolveInheritanceForClass(nGetS1(fsSid))
                assignDtorTagForClass(nGetS1(fsSid))
            }
            if (fsKind == "ENUM_DECL") { registerEnum(fsSid) }
            if (fsKind == "INTERFACE_DECL") { registerInterface(fsSid) }
        }
        // Pass 2: FUNC_DECL → register
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid > 0 && nGetKind(fsSid) == "FUNC_DECL") { registerFuncDeclNode(fsSid) }
        }
        // Pass 3: codegen (skip VAR_DECL, already emitted)
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid > 0 && nGetKind(fsSid) != "VAR_DECL") { genStmt(fsSid) }
        }
        // Pass 4: generate interface dispatchers (idempotent — skips already emitted)
        generateInterfaceDispatchers()
    }
    interpClearComptimeSS()
}

// Flush comptime IR buffer emitted by emit() calls.
function flushComptimeIR() {
    const fir = interpGetComptimeIR()
    if (fir != "") { emitIR(fir); interpClearComptimeIR() }
}

// 幂等注册一条 class 的完整元数据(由 flush 与预扫描共享;顺序同原 flush)。
function fullyRegisterCtClass(id: int) {
    registerClass(id)
    collectClassAnnotations(id)
    resolveInheritanceForClass(nGetS1(id))
    assignDtorTagForClass(nGetS1(id))
}

// 预扫描 `const X = comptime { class Y ...; return Y }` 模式(含递归函数体),把 CLASS_DECL
// 元数据注册 + push 提前到模块 codegen 开头,让 struct/ctor IR 必先于任何函数体发射。
// 不执行 comptime 块(依 AST 静态结构),避免 reactive<T> 这类需 T 绑定的场景过早跑崩。
// inheritance resolution 与 dtor tag 延后到 flush:预扫时父类可能还未入表,提前 resolve
// 会把 resolvedInheritance memo 写成 no-op,后面真正的父类到位也不会再 resolve。
function preScanCodegenCtClassesInStmts(stmtList: string) {
    if (stmtList == "") { return }
    const parts = stmtList.split(",")
    for (p in parts) {
        const s = parseInt(p)
        if (s <= 0) { continue }
        const sk = nGetKind(s)
        if (sk == "FUNC_DECL") {
            const fbId = nGetI1(s)
            if (fbId > 0) { preScanCodegenCtClassesInStmts(nGetList(fbId)) }
            continue
        }
        if (sk != "VAR_DECL") { continue }
        const initId = nGetI1(s)
        if (initId <= 0 || nGetKind(initId) != "COMPTIME_EXPR") { continue }
        const bodyId = nGetI1(initId)
        if (bodyId <= 0) { continue }
        const bList = nGetList(bodyId)
        if (bList == "") { continue }
        const bParts = bList.split(",")
        let returnName = ""
        for (bp in bParts) {
            const bs = parseInt(bp)
            if (bs <= 0) { continue }
            if (nGetKind(bs) == "CLASS_DECL") {
                // 带类型参数的 comptime class 延迟到实参绑定时再走 specialization 路径
                if (classTypeParams(bs) != "") { continue }
                const csName = nGetS1(bs)
                if (classFields.has(csName) == 0) {
                    registerClass(bs)
                    collectClassAnnotations(bs)
                    pendingCtClassIds = pendingCtClassIds.push(`${bs}`)
                }
                interpClasses.set(csName, `${bs}`)
                const csParent = nGetS2(bs)
                if (csParent != "") { interpClassParents.set(csName, csParent) }
            }
            if (nGetKind(bs) == "RETURN") {
                const retExpr = nGetI1(bs)
                if (retExpr > 0 && nGetKind(retExpr) == "IDENT") {
                    returnName = nGetS1(retExpr)
                }
            }
        }
        if (returnName != "" && isKnownClass(returnName) == 1) {
            ctVars.set(`:${nGetS1(s)}`, `${ctVal(interpNewType(returnName))}`)
        }
    }
}

// 消费 comptime 块里声明的 class:registration + IR emit 在 comptimeDepth=0 下跑,
// genClassDecl 走 runtime 分支。genStmt 若产生新 pending(嵌套 comptime class),继续 drain。
function flushPendingCtClasses() {
    while (pendingCtClassIds.length() > 0) {
        const snapshot = pendingCtClassIds
        pendingCtClassIds = []
        for (idStr in snapshot) {
            const sid = parseInt(idStr)
            if (sid > 0 && nGetKind(sid) == "CLASS_DECL") { fullyRegisterCtClass(sid) }
        }
        for (idStr in snapshot) {
            const sid = parseInt(idStr)
            if (sid > 0 && nGetKind(sid) == "CLASS_DECL") { genStmt(sid) }
        }
    }
}
