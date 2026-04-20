// SimpleScript Bootstrap SEMA Interpreter — 运算 / 真值 / 相等
// D092 Phase 2 sub-b(compound op)+ Phase 2 sub-d(标量运算常量折叠路径)。
// 依赖:读 tv*Of / 写 newTv*(interp_value)。纯运算,无 state。

// op 是 parse_stmts.ss 里 ASSIGN/MEMBER_ASSIGN 的 raw token 名
// (PLUS_ASSIGN / MINUS_ASSIGN / STAR_ASSIGN / ...),不是 BINARY 的 Add/Sub
function interpCompoundOp(op: string, lid: int, rid: int): int {
    if (tvKindOf(lid) == "int" && tvKindOf(rid) == "int") {
        const a = tvIntOf(lid)
        const b = tvIntOf(rid)
        if (op == "PLUS_ASSIGN") { return newTvInt(a + b) }
        if (op == "MINUS_ASSIGN") { return newTvInt(a - b) }
        if (op == "STAR_ASSIGN") { return newTvInt(a * b) }
        if (op == "SLASH_ASSIGN") { return newTvInt(a / b) }
        if (op == "PERCENT_ASSIGN") { return newTvInt(a % b) }
    }
    return newTvNull()
}

function interpTruthy(id: int): int {
    const k = tvKindOf(id)
    if (k == "null") { return 0 }
    if (k == "bool") { return tvIntOf(id) }
    if (k == "int") { return tvIntOf(id) != 0 ? 1 : 0 }
    if (k == "string") { return tvStringOf(id) != "" ? 1 : 0 }
    if (k == "array") { return tvI2[id] > 0 ? 1 : 0 }
    if (k == "map") { return tvI3[id] > 0 ? 1 : 0 }
    return 1
}

function interpToStr(id: int): string {
    const k = tvKindOf(id)
    if (k == "int") { return `${tvIntOf(id)}` }
    if (k == "string") { return tvStringOf(id) }
    if (k == "bool") { return tvIntOf(id) == 1 ? "true" : "false" }
    if (k == "null") { return "null" }
    if (k == "double") { return tvD1.getString(id + "") }
    return ""
}

// interpIntOp / interpDoubleOp 接受 raw int/double(不是 tvId),
// 由调用方从 TypedValue 里提取后传入,这是常量折叠路径的专用 API
// —— 区别于 sub-b 的 interpCompoundOp (tvId → tvId)。

// op 名对齐 parse_exprs.ss 的 BINARY nSetS1 约定(Add/Sub/Mul/...),
// 不是 PLUS/MINUS 等 token 名,也不是 Plus/Minus 等随手发明名
function interpIntOp(op: string, a: int, b: int): int {
    if (op == "Add") { return newTvInt(a + b) }
    if (op == "Sub") { return newTvInt(a - b) }
    if (op == "Eq") { return newTvBool(a == b ? 1 : 0) }
    if (op == "Ne") { return newTvBool(a != b ? 1 : 0) }
    if (op == "Lt") { return newTvBool(a < b ? 1 : 0) }
    if (op == "Gt") { return newTvBool(a > b ? 1 : 0) }
    if (op == "Le") { return newTvBool(a <= b ? 1 : 0) }
    if (op == "Ge") { return newTvBool(a >= b ? 1 : 0) }
    if (op == "Mul") { return newTvInt(a * b) }
    if (op == "Div") { return newTvInt(a / b) }
    if (op == "Mod") { return newTvInt(a % b) }
    if (op == "BitAnd") { return newTvInt(a & b) }
    if (op == "BitOr") { return newTvInt(a | b) }
    if (op == "BitXor") { return newTvInt(a ^ b) }
    if (op == "Shl") { return newTvInt(a << b) }
    if (op == "Shr") { return newTvInt(a >> b) }
    // gen_exprs.ss genIntBinary 用 lshr (zero-fill),与 SS 的 >>> 运算符对齐
    if (op == "UShr") { return newTvInt(a >>> b) }
    if (op == "Pow") {
        let pr = 1; let pi = 0
        while (pi < b) { pr = pr * a; pi = pi + 1 }
        return newTvInt(pr)
    }
    return newTvNull()
}

function interpDoubleOp(op: string, a: double, b: double): int {
    if (op == "Add") { return interpNewDouble(a + b) }
    if (op == "Sub") { return interpNewDouble(a - b) }
    if (op == "Mul") { return interpNewDouble(a * b) }
    if (op == "Div") { return interpNewDouble(a / b) }
    if (op == "Eq") { return newTvBool(a == b ? 1 : 0) }
    if (op == "Ne") { return newTvBool(a != b ? 1 : 0) }
    if (op == "Lt") { return newTvBool(a < b ? 1 : 0) }
    if (op == "Gt") { return newTvBool(a > b ? 1 : 0) }
    if (op == "Le") { return newTvBool(a <= b ? 1 : 0) }
    if (op == "Ge") { return newTvBool(a >= b ? 1 : 0) }
    if (op == "Pow") {
        let pr = 1.0; let pi = 0; const pe = parseInt(`${b}`)
        while (pi < pe) { pr = pr * a; pi = pi + 1 }
        return interpNewDouble(pr)
    }
    return newTvNull()
}

function interpValEquals(lid: int, rid: int): int {
    const lk = tvKindOf(lid)
    const rk = tvKindOf(rid)
    if (lk != rk) { return 0 }
    if (lk == "int" || lk == "bool") { return tvIntOf(lid) == tvIntOf(rid) ? 1 : 0 }
    if (lk == "string") { return tvStringOf(lid) == tvStringOf(rid) ? 1 : 0 }
    if (lk == "null") { return 1 }
    if (lk == "double") { return tvD1.getString(lid + "") == tvD1.getString(rid + "") ? 1 : 0 }
    return lid == rid ? 1 : 0
}
