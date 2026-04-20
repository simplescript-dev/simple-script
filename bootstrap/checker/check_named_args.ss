// check_named_args.ss — D084 named constructor args validation.
// Parent field walk + duplicate detection + per-field type check.
// State read via global scope: checkerDeferredAliases / checkerClassFields /
// checkerClassParents / checkerFieldTypes / checkerGenericClasses.

// Validate named constructor arguments: all names must be valid fields, no duplicates
function checkNamedConstructorArgs(className: string, argList: string, line: int, col: int) {
    if (argList == "") { return }
    // type-param-dependent alias(L2δ):具体 class 由 specialization 时决定,字段校验下放 codegen
    if (checkerDeferredAliases.has(className) == 1) { return }
    // Resolve full field list including parent fields
    let fullFields = ""
    let cls = className
    while (cls != "") {
        if (checkerClassFields.has(cls) == 1) {
            const ownFields = checkerClassFields.getString(cls)
            if (ownFields != "") {
                if (fullFields == "") { fullFields = ownFields }
                else { fullFields = `${ownFields},${fullFields}` }
            }
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    let seen = Map()
    let namedCount = 0
    const fieldsSplit = fullFields != "" ? fullFields.split(",") : "".split(",")
    const parts = argList.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId <= 0) { continue }
        if (nGetKind(argId) != "NAMED_ARG") {
            checkerError("cannot mix positional and named arguments in constructor", line, col)
            return
        }
        const argName = nGetS1(argId)
        namedCount = namedCount + 1
        // Check duplicate
        if (seen.has(argName) == 1) {
            checkerError(`duplicate named argument '${argName}' in constructor '${className}'`, nGetLine(argId), nGetCol(argId))
            continue
        }
        seen.set(argName, "1")
        // Check field exists
        let found = 0
        for (f in fieldsSplit) {
            if (f == argName) { found = 1 }
        }
        if (found == 0) {
            checkerError(`'${argName}' is not a field of class '${className}'`, nGetLine(argId), nGetCol(argId))
        } else {
            // Check named arg type against field type
            let fieldOwner = ""
            let fcls = className
            while (fcls != "") {
                if (checkerFieldTypes.has(`${fcls}.${argName}`) == 1) {
                    fieldOwner = fcls
                    fcls = ""
                } else if (checkerClassParents.has(fcls) == 1) {
                    fcls = checkerClassParents.getString(fcls)
                } else {
                    fcls = ""
                }
            }
            if (fieldOwner != "" && checkerGenericClasses.has(fieldOwner) == 0) {
                const naExpType = checkerFieldTypes.getString(`${fieldOwner}.${argName}`)
                const naActType = checkerInferType(nGetI1(argId))
                if (naActType != "" && naExpType != "" && isTypeCompatible(naExpType, naActType) == 0) {
                    checkerError(`field '${argName}' of constructor '${className}': expected '${naExpType}', got '${naActType}'`, nGetLine(argId), nGetCol(argId))
                }
            }
        }
    }
    // Check all required fields are provided
    for (f in fieldsSplit) {
        if (f == "" ) { continue }
        if (seen.has(f) == 0) {
            checkerError(`missing field '${f}' in named constructor for '${className}'`, line, col)
        }
    }
}
