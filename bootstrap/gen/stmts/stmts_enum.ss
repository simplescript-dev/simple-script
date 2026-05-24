// gen/stmts_enum.ss — Enum 注册(runtime + comptime 共用 registerEnumInto)。

// Populate enum name→value, type marker, and node lookup from an ENUM_DECL AST node.
// Shared by runtime registerEnum and the comptime ENUM_DECL handler — kept in sync by passing
// the target maps explicitly rather than duplicating the ENUM_VARIANT decode.
function registerEnumInto(id: int, valuesMap: Map, typesMap: Map, nodesMap: Map) {
    const eName = nGetS1(id)
    const isStringEnum = nGetI1(id)
    if (isStringEnum == 1) { typesMap.set(eName, "1") }
    nodesMap.set(eName, `${id}`)
    const vl = nGetList(id)
    if (vl == "") { return }
    const parts = vl.split(",")
    for (p in parts) {
        const vid = parseInt(p)
        if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
            const vName = nGetS1(vid)
            if (isStringEnum == 1) {
                valuesMap.set(`${eName}.${vName}`, nGetS2(vid))
            } else {
                valuesMap.set(`${eName}.${vName}`, `${nGetI1(vid)}`)
            }
        }
    }
}

function registerEnum(id: int) {
    if (comptimeMustBeKnown == 1) {
        registerEnumInto(id, interpEnumValues, interpEnumTypes, interpEnumNodes)
        return
    }
    if (enumReady == 0) { enumValues = Map(); enumTypes = Map(); enumDeclNodes = Map(); enumReady = 1 }
    registerEnumInto(id, enumValues, enumTypes, enumDeclNodes)
}
