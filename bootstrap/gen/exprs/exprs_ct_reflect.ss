// gen/exprs_ct_reflect.ss — D120 Execute 1 Phase 1:reflect.classes() comptime API。
// reflect namespace IDENT obj 在 method_call.ss 分派到 ctReflectMethodDispatch,
// genValCtReflectClasses 对 interpClasses + classFields 两注册表 keys 做 union 去重,
// 经 insertion sort 字典序稳定化,每名经 interpBuildTypeInfo 构造 ClassMeta。
// 复用 D117 Meta 工厂 + InternPool CLS| dedup,无新字典 / 无新 registry。

function ctReflectMethodDispatch(astId: int, methodName: string): int {
    if (methodName == "classes") { return genValCtReflectClasses(astId) }
    return comptimeError(`unknown reflect method '${methodName}'`, astId)
}

function genValCtReflectClasses(astId: int): int {
    let seen = new Map()
    let sorted: Array<string> = []
    const icKeys: Array<string> = interpClasses.keys()
    for (k1 in icKeys) {
        if (k1 == "" || seen.has(k1) == 1) { continue }
        seen.set(k1, "1")
        let ns: Array<string> = []
        let ins = 0
        while (ins < sorted.length() && sorted[ins] < k1) { ns = ns.push(sorted[ins]); ins = ins + 1 }
        ns = ns.push(k1)
        while (ins < sorted.length()) { ns = ns.push(sorted[ins]); ins = ins + 1 }
        sorted = ns
    }
    const cfKeys: Array<string> = classFields.keys()
    for (k2 in cfKeys) {
        if (k2 == "" || seen.has(k2) == 1) { continue }
        seen.set(k2, "1")
        let ns: Array<string> = []
        let ins = 0
        while (ins < sorted.length() && sorted[ins] < k2) { ns = ns.push(sorted[ins]); ins = ins + 1 }
        ns = ns.push(k2)
        while (ins < sorted.length()) { ns = ns.push(sorted[ins]); ins = ins + 1 }
        sorted = ns
    }
    const arr = interpNewArray("")
    let k = 0
    while (k < sorted.length()) {
        interpArrayPush(arr, interpBuildTypeInfo(sorted[k]))
        k = k + 1
    }
    return ctVal(arr)
}
