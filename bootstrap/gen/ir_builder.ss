// SimpleScript Bootstrap IR Builder Primitives
// LLVM IR 文本构造原语 — 纯 emitIR 包装,零状态耦合。

function irLabel(name: string) {
    emitIR(`${name}:`)
}

function irAlloca(dst: string, ty: string, align: int) {
    emitIR(`  %${dst} = alloca ${ty}, align ${align}`)
}

function irLoad(dst: string, ty: string, ptr: string) {
    emitIR(`  %${dst} = load ${ty}, ptr ${ptr}`)
}

function irStore(ty: string, val: string, ptr: string) {
    emitIR(`  store ${ty} ${val}, ptr ${ptr}`)
}

function irGEP(dst: string, baseTy: string, base: string, idx: string) {
    emitIR(`  %${dst} = getelementptr ${baseTy}, ptr ${base}, i64 ${idx}`)
}

function irICmp(dst: string, op: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = icmp ${op} ${ty} ${a}, ${b}`)
}

function irBr(label: string) {
    emitIR(`  br label %${label}`)
}

function irBrCond(cond: string, thenL: string, elseL: string) {
    emitIR(`  br i1 %${cond}, label %${thenL}, label %${elseL}`)
}

function irRet(ty: string, val: string) {
    emitIR(`  ret ${ty} ${val}`)
}

function irRetVoid() {
    emitIR("  ret void")
}

function irAdd(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = add ${ty} ${a}, ${b}`)
}

function irSub(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = sub ${ty} ${a}, ${b}`)
}

function irMul(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = mul ${ty} ${a}, ${b}`)
}

function irCall(dst: string, retTy: string, func: string, args: string) {
    emitIR(`  %${dst} = call ${retTy} @${func}(${args})`)
}

function irCallVoid(func: string, args: string) {
    emitIR(`  call void @${func}(${args})`)
}

function irSext(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = sext ${fromTy} ${val} to ${toTy}`)
}

function irZext(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = zext ${fromTy} ${val} to ${toTy}`)
}

function irSelect(dst: string, cond: string, ty: string, thenVal: string, elseVal: string) {
    emitIR(`  %${dst} = select i1 %${cond}, ${ty} ${thenVal}, ${ty} ${elseVal}`)
}

function irSDiv(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = sdiv ${ty} ${a}, ${b}`)
}

function irOr(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = or ${ty} ${a}, ${b}`)
}

function irTrunc(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = trunc ${fromTy} ${val} to ${toTy}`)
}

function irPtrToInt(dst: string, val: string, toTy: string) {
    emitIR(`  %${dst} = ptrtoint ptr ${val} to ${toTy}`)
}

function irIntToPtr(dst: string, fromTy: string, val: string) {
    emitIR(`  %${dst} = inttoptr ${fromTy} ${val} to ptr`)
}

// Load array data buffer pointer from header slot 2
function irLoadArrayData(dst: string, arr: string) {
    irGEP(`${dst}p`, "i64", arr, "2")
    irLoad(`${dst}_i`, "i64", `%${dst}p`)
    irIntToPtr(dst, "i64", `%${dst}_i`)
}
