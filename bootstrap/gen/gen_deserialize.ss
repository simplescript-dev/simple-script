// per-class @ClassName_deserialize codegen — 仅 @RequestBody 引用的 class 编译期自动生成。
// 字段缺失 fallback 默认值(int=0/string=""/bool=0/double=0.0,严格 4xx 留 I021-requestbody-validation)。
// SSoT 单点解码入口 emitDeserializeForType(ssType, jsonNodeR) -> i64 reg 详见 docs/3-decisions/D130-deserializer-ssot-converge.md。

// invoke sentinel kind == "RequestBody" 分支注册 deserializerTargets(eval/method_call.ss),
// codegen module 末尾(codegen.ss emitGlobalsAndCode 收尾)调 emitPendingDeserializers
// 仅对实际需要的 class emit,避免 jnGet* 调用污染未 import lib/json.ss 的程序。
let deserializerTargets: Map<string, int> = new Map()

// I021-requestbody-nested-array(-primitive)(-array) — Array<X> 字段判断;X ∈ {UserClass /
// int / string / double / bool / Array<Y> 任意层},递归终止 X ∈ {scalar / UserClass}。
function isArrayDeserializable(ft: string): int {
    if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const et = extractContainerElemType(ft)
    if (isUserClass(et) == 1) { return 1 }
    if (et == "int" || et == "string" || et == "double" || et == "bool") { return 1 }
    if (isArrayDeserializable(et) == 1) { return 1 }
    if (isMapDeserializable(et) == 1) { return 1 }
    return 0
}

// I021-requestbody-nested-map(D130) — Map<string, V> 字段判断;V ∈ {scalar / UserClass /
// Array<Y> / Map<string, Z>}。key 限 string(JSON object key 标准形态),非 string key 留
// I021-requestbody-nested-map-typed-key 子档;extractContainerElemType 已支持 Map<K,V> 返 V
// (gen_rc.ss:220-232)。
function isMapDeserializable(ft: string): int {
    if (ft.startsWith("Map<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const vt = extractContainerElemType(ft)
    if (isUserClass(vt) == 1) { return 1 }
    if (vt == "int" || vt == "string" || vt == "double" || vt == "bool") { return 1 }
    if (isArrayDeserializable(vt) == 1) { return 1 }
    if (isMapDeserializable(vt) == 1) { return 1 }
    return 0
}

// I021-requestbody-nested — 嵌套 user class 字段递归调 <NestedClass>_deserialize,
// 嵌套 class 通过 outer class 字段间接引用,单遍 BFS 出队即 emit + 字段扫描入队;
// `deserializerTargets.has` 入队 guard 同时充当 visited(set 后即拒绝再入队)。
// **D130 BFS 扩 Array<UserClass> + Map<string, UserClass> value class** 入队 transitive
// closure(同一字段类型路径递归剥皮直到拿 base elem)。
function emitPendingDeserializers() {
    let workList: Array<string> = deserializerTargets.keys()
    let i = 0
    while (i < workList.length()) {
        const cn = workList[i]
        i = i + 1
        if (cn == "") { continue }
        if (classFields.has(cn) == 0) { continue }
        const fieldStr = classFields.getString(cn)
        const hasVtable = classVtableSlots.has(cn) == 1 ? 1 : 0
        emitClassDeserializeFn(cn, fieldStr, hasVtable)
        if (fieldStr == "") { continue }
        const parts = fieldStr.split(",")
        for (p in parts) {
            if (classFieldTypes.has(`${cn}.${p}`) == 0) { continue }
            const ft = classFieldTypes.getString(`${cn}.${p}`)
            if (isUserClass(ft) == 1 && deserializerTargets.has(ft) == 0) {
                deserializerTargets.set(ft, 1)
                workList = workList.push(ft)
            } else if (isArrayDeserializable(ft) == 1 || isMapDeserializable(ft) == 1) {
                // Array<X> / Map<string, X> 递归剥皮直到拿 base elem,base 是 UserClass 才入队
                let inner = extractContainerElemType(ft)
                while (inner.startsWith("Array<") == 1 || inner.startsWith("Map<") == 1) {
                    inner = extractContainerElemType(inner)
                }
                if (isUserClass(inner) == 1 && deserializerTargets.has(inner) == 0) {
                    deserializerTargets.set(inner, 1)
                    workList = workList.push(inner)
                }
            }
        }
    }
}

// I021-D130 — emitDeserializeForType:从 JSON nodeId 反序列化为 SS 类型 T,返回 i64 reg
// 名(持反序列化结果)。**SSoT 单点解码入口** — 所有"from nodeId emit i64 of type T"职能
// 收敛此处,调用方按 T 类型语义解 i64 → 写入字段槽 / push 数组元素 / set Map entry。
//
// RC 契约:
//   - primitive scalar(int/double/bool):无 ptr 不 retain
//   - string:emitRetainForType(jnAsString 返 jnStr 内部 ptr 未持新 RC)
//   - UserClass:子 @<C>_deserialize 返新分配 ptr rc=1,transfer ownership 不 retain
//   - Array<X> / Map<string, X>:容器内层值由递归 emitDeserializeForType 自身负责 RC
//
// 调用方 store 语义:
//   - i32 字段(int/bool):trunc i64 to i32 + store i32
//   - double 字段:bitcast i64 to double + store double
//   - ptr 字段(string/UserClass/容器):inttoptr i64 to ptr + store ptr
//   (emitFieldStoreI64 / 容器循环 push/set 自动正确转换)
function emitDeserializeForType(ssType: string, jsonNodeR: string): string {
    // D067 + I021-requestbody-nested-optional — nullable T?:missing OR JSON null → i64 0;
    //   stripped 是 Array/Map 时 inner emit 含 head/body/end label,phi predecessor 跟踪
    //   不安全 → 用 alloca slot 跨 block load。
    const stripped = stripNullableCG(ssType)
    if (stripped != ssType) {
        const slotR = nextReg()
        emitIR(`  ${slotR} = alloca i64, align 8`)
        emitIR(`  store i64 0, ptr ${slotR}, align 8`)
        const isNullR = nextReg()
        emitIR(`  ${isNullR} = call i32 @jnIsNullOrMissing(i32 ${jsonNodeR})`)
        const condR = nextReg()
        emitIR(`  ${condR} = icmp eq i32 ${isNullR}, 0`)
        const presentLabel = nextLabel("opt_present")
        const doneLabel = nextLabel("opt_done")
        emitIR(`  br i1 ${condR}, label %${presentLabel}, label %${doneLabel}`)
        emitIR(`${presentLabel}:`)
        const innerI64R = emitDeserializeForType(stripped, jsonNodeR)
        emitIR(`  store i64 ${innerI64R}, ptr ${slotR}, align 8`)
        emitIR(`  br label %${doneLabel}`)
        emitIR(`${doneLabel}:`)
        const finalR = nextReg()
        emitIR(`  ${finalR} = load i64, ptr ${slotR}, align 8`)
        return finalR
    }
    if (ssType == "int") {
        const valR = nextReg()
        emitIR(`  ${valR} = call i32 @jnAsInt(i32 ${jsonNodeR})`)
        const i64R = nextReg()
        emitIR(`  ${i64R} = sext i32 ${valR} to i64`)
        return i64R
    }
    if (ssType == "double") {
        const valR = nextReg()
        emitIR(`  ${valR} = call double @jnAsDouble(i32 ${jsonNodeR})`)
        const i64R = nextReg()
        emitIR(`  ${i64R} = bitcast double ${valR} to i64`)
        return i64R
    }
    if (ssType == "string") {
        const valR = nextReg()
        emitIR(`  ${valR} = call ptr @jnAsString(i32 ${jsonNodeR})`)
        emitRetainForType(valR, ssType)
        const i64R = nextReg()
        emitIR(`  ${i64R} = ptrtoint ptr ${valR} to i64`)
        return i64R
    }
    if (ssType == "bool") {
        const valR = nextReg()
        emitIR(`  ${valR} = call i32 @jnAsBool(i32 ${jsonNodeR})`)
        const i64R = nextReg()
        emitIR(`  ${i64R} = zext i32 ${valR} to i64`)
        return i64R
    }
    if (isUserClass(ssType) == 1) {
        const ptrR = nextReg()
        emitIR(`  ${ptrR} = call ptr @${ssType}_deserialize(i32 ${jsonNodeR})`)
        const i64R = nextReg()
        emitIR(`  ${i64R} = ptrtoint ptr ${ptrR} to i64`)
        return i64R
    }
    if (isArrayDeserializable(ssType) == 1) {
        const arrPtrR = emitArrayDeserializeInto(jsonNodeR, ssType)
        const i64R = nextReg()
        emitIR(`  ${i64R} = ptrtoint ptr ${arrPtrR} to i64`)
        return i64R
    }
    if (isMapDeserializable(ssType) == 1) {
        const mapPtrR = emitMapDeserializeInto(jsonNodeR, ssType)
        const i64R = nextReg()
        emitIR(`  ${i64R} = ptrtoint ptr ${mapPtrR} to i64`)
        return i64R
    }
    // fallback i64 0(未支持类型,RC 安全占位 — emit add i64 0, 0 拿 reg 持 0 值)
    const zR = nextReg()
    emitIR(`  ${zR} = add i64 0, 0`)
    return zR
}

// I021-D130 — Array<X> 字段反序列化 inline emit framework。接受 array 子 nodeId reg 名
// (调用方从 jnGetField 或上层 jnArrayGet 拿到),返回 final array ptr reg。**inner elem
// dispatch 全部委托 emitDeserializeForType**(SSoT 收敛 — 7 路 case 单点解码,Array<X> /
// Map<string, X> 嵌套递归自动 cover)。
function emitArrayDeserializeInto(arrNodeR: string, arrFieldType: string): string {
    const elemType = extractContainerElemType(arrFieldType)
    const newArrFn = ssTypeToLLVM(elemType) == "ptr" ? "ss_newArrayPtr" : "ss_newArray"
    const arrLenR = nextReg()
    emitIR(`  ${arrLenR} = call i32 @jnArrayLen(i32 ${arrNodeR})`)
    const initArrR = nextReg()
    emitIR(`  ${initArrR} = call ptr @${newArrFn}(i32 0)`)
    const arrSlotR = nextReg()
    emitIR(`  ${arrSlotR} = alloca ptr, align 8`)
    emitIR(`  store ptr ${initArrR}, ptr ${arrSlotR}, align 8`)
    const idxSlotR = nextReg()
    emitIR(`  ${idxSlotR} = alloca i32, align 4`)
    emitIR(`  store i32 0, ptr ${idxSlotR}, align 4`)
    const headLabel = nextLabel("arr_loop.head")
    const bodyLabel = nextLabel("arr_loop.body")
    const endLabel = nextLabel("arr_loop.end")
    emitIR(`  br label %${headLabel}`)
    emitIR(`${headLabel}:`)
    const idxR = nextReg()
    emitIR(`  ${idxR} = load i32, ptr ${idxSlotR}, align 4`)
    const condR = nextReg()
    emitIR(`  ${condR} = icmp slt i32 ${idxR}, ${arrLenR}`)
    emitIR(`  br i1 ${condR}, label %${bodyLabel}, label %${endLabel}`)
    emitIR(`${bodyLabel}:`)
    const elemNodeR = nextReg()
    emitIR(`  ${elemNodeR} = call i32 @jnArrayGet(i32 ${arrNodeR}, i32 ${idxR})`)
    const elemI64R = emitDeserializeForType(elemType, elemNodeR)
    const curArrR = nextReg()
    emitIR(`  ${curArrR} = load ptr, ptr ${arrSlotR}, align 8`)
    const newArrR = nextReg()
    emitIR(`  ${newArrR} = call ptr @ss_arrayPush(ptr ${curArrR}, i64 ${elemI64R})`)
    emitIR(`  store ptr ${newArrR}, ptr ${arrSlotR}, align 8`)
    const idxNextR = nextReg()
    emitIR(`  ${idxNextR} = add i32 ${idxR}, 1`)
    emitIR(`  store i32 ${idxNextR}, ptr ${idxSlotR}, align 4`)
    emitIR(`  br label %${headLabel}`)
    emitIR(`${endLabel}:`)
    const finalArrR = nextReg()
    emitIR(`  ${finalArrR} = load ptr, ptr ${arrSlotR}, align 8`)
    return finalArrR
}

// I021-D130 — Map<string, X> 字段反序列化 inline emit framework。接受 object 子 nodeId
// reg 名,返回 final map ptr reg。**inner value dispatch 全部委托 emitDeserializeForType**
// (SSoT 收敛 — 与 emitArrayDeserializeInto 对称形态)。**val_type=1 写 offset 516** 标记 ptr
// value(对齐 gen_decls.ss:653-664 用户层 `let m: Map<...> = new Map()` val_type 协议) —
// Map drop 时 ss_rc_destroy_map 自动级联触发 value drop;keys array 临时变量 emit 末尾
// ss_rc_release 走 ss_rc_destroy_array_ptrs 自动逐元素释放(jnObjectKeys 内 string 副本)。
function emitMapDeserializeInto(mapNodeR: string, mapFieldType: string): string {
    const vType = extractContainerElemType(mapFieldType)
    const initMapR = nextReg()
    emitIR(`  ${initMapR} = call ptr @ss_mapNew()`)
    if (ssTypeToLLVM(vType) == "ptr") {
        const vtpGepR = nextReg()
        emitIR(`  ${vtpGepR} = getelementptr i8, ptr ${initMapR}, i64 516`)
        emitIR(`  store i32 1, ptr ${vtpGepR}, align 4`)
    }
    const keysArrR = nextReg()
    emitIR(`  ${keysArrR} = call ptr @jnObjectKeys(i32 ${mapNodeR})`)
    const keysLenR = nextReg()
    emitIR(`  ${keysLenR} = call i32 @ss_arrayLen(ptr ${keysArrR})`)
    const idxSlotR = nextReg()
    emitIR(`  ${idxSlotR} = alloca i32, align 4`)
    emitIR(`  store i32 0, ptr ${idxSlotR}, align 4`)
    const headLabel = nextLabel("map_loop.head")
    const bodyLabel = nextLabel("map_loop.body")
    const endLabel = nextLabel("map_loop.end")
    emitIR(`  br label %${headLabel}`)
    emitIR(`${headLabel}:`)
    const idxR = nextReg()
    emitIR(`  ${idxR} = load i32, ptr ${idxSlotR}, align 4`)
    const condR = nextReg()
    emitIR(`  ${condR} = icmp slt i32 ${idxR}, ${keysLenR}`)
    emitIR(`  br i1 ${condR}, label %${bodyLabel}, label %${endLabel}`)
    emitIR(`${bodyLabel}:`)
    const keyI64R = nextReg()
    emitIR(`  ${keyI64R} = call i64 @ss_arrayGet(ptr ${keysArrR}, i32 ${idxR})`)
    const keyPtrR = nextReg()
    emitIR(`  ${keyPtrR} = inttoptr i64 ${keyI64R} to ptr`)
    const valNodeR = nextReg()
    emitIR(`  ${valNodeR} = call i32 @jnGetField(i32 ${mapNodeR}, ptr ${keyPtrR})`)
    const valI64R = emitDeserializeForType(vType, valNodeR)
    emitIR(`  call void @ss_mapSet(ptr ${initMapR}, ptr ${keyPtrR}, i64 ${valI64R})`)
    const idxNextR = nextReg()
    emitIR(`  ${idxNextR} = add i32 ${idxR}, 1`)
    emitIR(`  store i32 ${idxNextR}, ptr ${idxSlotR}, align 4`)
    emitIR(`  br label %${headLabel}`)
    emitIR(`${endLabel}:`)
    emitIR(`  call void @ss_rc_release(ptr ${keysArrR})`)
    return initMapR
}

// I021-D130 — emitFieldStoreI64:把 emitDeserializeForType 返回的 i64 reg 按 SS 字段类型
// 语义写入字段槽。3 种存储宽度:i32(int/bool)/double(double bitcast)/ptr(string/UserClass/容器);
// SSoT 收敛 type-aware store(否则每字段 case 重复 trunc/bitcast/inttoptr 模式)。
function emitFieldStoreI64(dstR: string, ft: string, valI64R: string) {
    const llType = ssTypeToLLVM(ft)
    if (llType == "i32") {
        const i32R = nextReg()
        emitIR(`  ${i32R} = trunc i64 ${valI64R} to i32`)
        emitIR(`  store i32 ${i32R}, ptr ${dstR}, align 8`)
    } else if (llType == "double") {
        const dR = nextReg()
        emitIR(`  ${dR} = bitcast i64 ${valI64R} to double`)
        emitIR(`  store double ${dR}, ptr ${dstR}, align 8`)
    } else {
        const pR = nextReg()
        emitIR(`  ${pR} = inttoptr i64 ${valI64R} to ptr`)
        emitIR(`  store ptr ${pR}, ptr ${dstR}, align 8`)
    }
}

// per-class @ClassName_deserialize(i32 nodeId): ClassName 编译期自动生成(mirror ss_drop /
// ss_deep_clone / ss_shallow_clone 模式 — D018 ObjectLayout TypeInfo + D022 clone 语义)。
// nodeId = JsonNode 实例 raw int(避免 wrapper alloc 开销);字段循环委托 emitDeserializeForType
// 单点解码 + emitFieldStoreI64 type-aware store(D130)。
function emitClassDeserializeFn(className: string, fieldStr: string, hasVtable: int) {
    regCount = 0
    regTable = []
    emitIR(`define ptr @${className}_deserialize(i32 %nodeId.arg) {`)
    emitIR("entry:")
    emitIR(`  %size = ptrtoint ptr getelementptr (%${className}, ptr null, i32 1) to i64`)
    emitIR("  %new = call ptr @mi_calloc(i64 1, i64 %size)")
    emitIR("  store i32 1, ptr %new, align 4")
    emitIR(`  %ti_ptr = getelementptr %${className}, ptr %new, i32 0, i32 1`)
    emitIR(`  store ptr @${className}_type_info, ptr %ti_ptr, align 8`)
    if (hasVtable == 1) {
        emitIR(`  %vt_dst = getelementptr %${className}, ptr %new, i32 0, i32 2`)
        emitIR(`  store ptr @${className}_vtable, ptr %vt_dst, align 8`)
    }
    if (fieldStr != "") {
        let idx = fieldStartIdx(hasVtable)
        const parts = fieldStr.split(",")
        for (p in parts) {
            let ft = classFieldTypes.has(`${className}.${p}`) == 1 ? classFieldTypes.getString(`${className}.${p}`) : "int"
            // I021-requestbody-nested-optional + D067 — 恢复字段 nullable 标记给
            //   emitDeserializeForType(D067 codegen invariant 让 classFieldTypes 存 stripped,
            //   反序列化路径需 nullable 元数据决定 missing/null → store ptr null vs 调子
            //   <C>_deserialize)。classFieldNullable Map 在 class_register.ss 字段注册时
            //   set。同源 emitFieldStoreI64 用 stripped ft(ssTypeToLLVM 自然 handle ptr 类型)。
            if (classFieldNullable.has(`${className}.${p}`) == 1) { ft = ft + "?" }
            const keyConst = addStringConst(p)
            const dstR = nextReg()
            emitIR(`  ${dstR} = getelementptr %${className}, ptr %new, i32 0, i32 ${idx}`)
            const childNodeR = nextReg()
            emitIR(`  ${childNodeR} = call i32 @jnGetField(i32 %nodeId.arg, ptr ${keyConst})`)
            const valI64R = emitDeserializeForType(ft, childNodeR)
            emitFieldStoreI64(dstR, ft, valI64R)
            idx = idx + 1
        }
    }
    emitIR("  ret ptr %new")
    emitIR("}")
    emitIR("")
}
