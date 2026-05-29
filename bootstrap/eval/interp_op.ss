// SimpleScript Bootstrap SEMA Interpreter — 运算 / 真值 / 相等
// D092 Phase 2 sub-b(compound op)+ Phase 2 sub-d(标量运算常量折叠路径)。
// 依赖:读 tv*Of / 写 newTv*(interp_value)。纯运算,无 state。

// op 是 parse_stmts.ss 里 ASSIGN/MEMBER_ASSIGN 的 raw token 名
// (PLUS_ASSIGN / MINUS_ASSIGN / STAR_ASSIGN / ...),不是 BINARY 的 Add/Sub
function interpCompoundOp(op: string, lid: int, rid: int): int {
    if (tvKindByPool(lid) == "int" && tvKindByPool(rid) == "int") {
        const a = tvIntOf(lid)
        const b = tvIntOf(rid)
        if (op == "PLUS_ASSIGN") { return interpNewInt(a + b) }
        if (op == "MINUS_ASSIGN") { return interpNewInt(a - b) }
        if (op == "STAR_ASSIGN") { return interpNewInt(a * b) }
        if (op == "SLASH_ASSIGN") { return interpNewInt(a / b) }
        if (op == "PERCENT_ASSIGN") { return interpNewInt(a % b) }
    }
    return interpNewNull()
}

function interpTruthy(id: int): int {
    const k = tvKindByPool(id)
    if (k == "null") { return 0 }
    if (k == "bool") { return tvIntOf(id) }
    if (k == "int") { return tvIntOf(id) != 0 ? 1 : 0 }
    if (k == "string") { return tvStringOf(id) != "" ? 1 : 0 }
    if (k == "array") { return tvI2[id] > 0 ? 1 : 0 }
    if (k == "map") { return tvI3[id] > 0 ? 1 : 0 }
    return 1
}

function interpToStr(id: int): string {
    const k = tvKindByPool(id)
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
    if (op == "Add") { return interpNewInt(a + b) }
    if (op == "Sub") { return interpNewInt(a - b) }
    if (op == "Eq") { return interpNewBool(a == b ? 1 : 0) }
    if (op == "Ne") { return interpNewBool(a != b ? 1 : 0) }
    if (op == "Lt") { return interpNewBool(a < b ? 1 : 0) }
    if (op == "Gt") { return interpNewBool(a > b ? 1 : 0) }
    if (op == "Le") { return interpNewBool(a <= b ? 1 : 0) }
    if (op == "Ge") { return interpNewBool(a >= b ? 1 : 0) }
    if (op == "Mul") { return interpNewInt(a * b) }
    if (op == "Div") { return interpNewInt(a / b) }
    if (op == "Mod") { return interpNewInt(a % b) }
    if (op == "BitAnd") { return interpNewInt(a & b) }
    if (op == "BitOr") { return interpNewInt(a | b) }
    if (op == "BitXor") { return interpNewInt(a ^ b) }
    if (op == "Shl") { return interpNewInt(a << b) }
    if (op == "Shr") { return interpNewInt(a >> b) }
    // gen_exprs.ss genIntBinary 用 lshr (zero-fill),与 SS 的 >>> 运算符对齐
    if (op == "UShr") { return interpNewInt(a >>> b) }
    if (op == "Pow") {
        let pr = 1; let pi = 0
        while (pi < b) { pr = pr * a; pi = pi + 1 }
        return interpNewInt(pr)
    }
    return interpNewNull()
}

// D093/D169 1.5d — ct path 通用 binop 数值 fold (int/double dispatch),与 eval_expr.ss BINARY
// 通用 ct path / pow_binary.ss Pow ct path 共享 (1 helper × 2 caller,simplify Finding 1/H2 unify)。
// **double 回读走 tvS1 exact-bits(bitsToDouble)非 tvD1 %g(parseDouble(interpToStr))**(D171 finding C
// 残余 backlog 根因修复):finding C 让 newTvDouble 把 IEEE754 bits 存 tvS1(原恒空),tvD1 仅作 %g human
// 显示(默认 6 位有效数字,丢精)。chained 算术中间值跨操作回读若读 tvD1,`10.0/3.0` 存成 "3.33333" 回读
// ×3.0 = 9.99999;改 bitsToDouble(interpAsStr) 从 exact-bits 重建,与物化路径(materialize/gen_types
// exact-bits)对称闭环 → bit-exact。int 分支仍走 `int → string → parseDouble`(int 值精确无丢精)。
function interpNumericBinop(op: string, lp: int, rp: int, lt: string, rt: string): int {
    if (lt == "double" || rt == "double") {
        const ld = lt == "double" ? bitsToDouble(interpAsStr(lp)) : parseDouble(`${interpAsInt(lp)}`)
        const rd = rt == "double" ? bitsToDouble(interpAsStr(rp)) : parseDouble(`${interpAsInt(rp)}`)
        return interpDoubleOp(op, ld, rd)
    }
    return interpIntOp(op, interpAsInt(lp), interpAsInt(rp))
}

function interpDoubleOp(op: string, a: double, b: double): int {
    if (op == "Add") { return interpNewDouble(a + b) }
    if (op == "Sub") { return interpNewDouble(a - b) }
    if (op == "Mul") { return interpNewDouble(a * b) }
    if (op == "Div") { return interpNewDouble(a / b) }
    if (op == "Eq") { return interpNewBool(a == b ? 1 : 0) }
    if (op == "Ne") { return interpNewBool(a != b ? 1 : 0) }
    if (op == "Lt") { return interpNewBool(a < b ? 1 : 0) }
    if (op == "Gt") { return interpNewBool(a > b ? 1 : 0) }
    if (op == "Le") { return interpNewBool(a <= b ? 1 : 0) }
    if (op == "Ge") { return interpNewBool(a >= b ? 1 : 0) }
    if (op == "Pow") {
        let pr = 1.0; let pi = 0; const pe = parseInt(`${b}`)
        while (pi < pe) { pr = pr * a; pi = pi + 1 }
        return interpNewDouble(pr)
    }
    return interpNewNull()
}

// 9 value kind (int/string/bool/null/type/double/array/map/fn) 全入 InternPool,lid==rid 即 Value.eql O(1)
// D098 §决策 2 §Phase C dedup done (double sibling 58/59 + array/map sibling 60/61);Part B interp* 家族 value 表示迁 = §Phase C step 2 远期可选 trigger unmet
function interpValEquals(lid: int, rid: int): int {
    return lid == rid ? 1 : 0
}
