// I021-requestbody — per-class @ClassName_deserialize codegen 拆出独立 file
// (从 gen_type_ops.ss 拆出,F1 ≤ 600 物理拆 — 嵌套 closure 工作 + 嵌套字段 case 后
//  gen_type_ops.ss > 600,按 feedback_600_split_not_inline 物理拆,按 feedback_structure_not_linecount
//  拆判据为「deserialize 单一职能」与 drop/clone/ctor 自然解耦)。
//
// 模块职能:**仅 @RequestBody 引用 class 的 per-class deserializer 编译期自动生成**
// — 与 ss_drop_X / ss_deep_clone_X / ss_shallow_clone_X 全 class 自动生成对称形态分流;
// 嵌套 user class 字段递归调 + transitive closure 扩展 deserializerTargets;
// 字段缺失 fallback 默认值(int=0/string=""/bool=0/double=0.0,严格 4xx 留 I021-requestbody-validation)。

// invoke sentinel kind == "RequestBody" 分支注册 deserializerTargets(eval/method_call.ss),
// codegen module 末尾(codegen.ss emitGlobalsAndCode 收尾)调 emitPendingDeserializers
// 仅对实际需要的 class emit,避免 jnGet* 调用污染未 import lib/json.ss 的程序。
let deserializerTargets: Map<string, int> = new Map()

// I021-requestbody-nested-array(-primitive)(-array) — Array<UserClass | int | string | double | bool>
// 单层 + Array<Array<X>> 双层(及任意层 N>1 — 递归终止条件:内层 X ∈ {int/string/double/bool/UserClass})。
// UserClass elemType 走 <Elem>_deserialize 递归路径(c3361c9 落地),primitive elemType 走
// jnArrayGetInt/String/Double/Bool raw helper(a096fd0 落地);Array<X> elemType 走第 6 路递归
// emitArrayDeserializeInto 自身(本子档落地);Map<> 留 -map 子档返 0 fallback。
function isArrayDeserializable(ft: string): int {
    if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const et = extractContainerElemType(ft)
    if (isUserClass(et) == 1) { return 1 }
    if (et == "int" || et == "string" || et == "double" || et == "bool") { return 1 }
    if (isArrayDeserializable(et) == 1) { return 1 }
    return 0
}

// I021-requestbody-nested — 嵌套 user class 字段递归调 <NestedClass>_deserialize,
// 嵌套 class 通过 outer class 字段间接引用,单遍 BFS 出队即 emit + 字段扫描入队;
// `deserializerTargets.has` 入队 guard 同时充当 visited(set 后即拒绝再入队),
// Map.keys() 初始 snapshot 也是 unique,故初始 workList 与扩展项均不重复。
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
            } else if (isArrayDeserializable(ft) == 1) {
                // I021-requestbody-nested-array(-primitive)(-array) — Array<UserClass> 单层
                // (b79aa97 升维 cover collection)+ Array<Array<UserClass>> 嵌套(本子档双层
                // 任意层 unwrap)。外层 elemType 仍是 Array<X> 时递归剥皮直到拿 base elem,
                // base 是 UserClass 才入队;primitive elem 不入队(走 lib/json raw helper)。
                let inner = extractContainerElemType(ft)
                while (inner.startsWith("Array<") == 1) {
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

// I021-requestbody-nested-array(-primitive)(-array) — Array<X> 字段反序列化 inline emit body。
// 接受已有的 array 子 nodeId reg 名(由调用方从 jnGetField 或 jnArrayGet 拿到),返回
// final array ptr reg 名;helper 自身不 store 任何 dst(由调用方在外层用 finalArrR store
// 字段槽 / 内层 push i64 转换源)。**第 6 路递归 emitArrayDeserializeInto 自身** —
// elemType startsWith "Array<" 时 inner array node = jnArrayGet(outer, idx),递归取 inner ptr
// + ptrtoint i64 + ss_arrayPush 外层(D013 list-append 单签 i64);递归终止条件:elemType
// ∈ {int/string/double/bool/UserClass}。RC 契约:外层 push 内层 ptr 不 retain(transfer);
// 内层 push string elem 必 emitRetainForType(jnArrayGetString 返 jnStr 内部 ptr 未持新 RC)。
function emitArrayDeserializeInto(arrNodeR: string, arrFieldType: string): string {
    const elemType = extractContainerElemType(arrFieldType)
    const elemIsPtr = (elemType == "string" || isUserClass(elemType) == 1 || elemType.startsWith("Array<") == 1) ? 1 : 0
    const newArrFn = elemIsPtr == 1 ? "ss_newArrayPtr" : "ss_newArray"
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
    let elemI64R = ""
    if (isUserClass(elemType) == 1) {
        const elemNodeR = nextReg()
        emitIR(`  ${elemNodeR} = call i32 @jnArrayGet(i32 ${arrNodeR}, i32 ${idxR})`)
        const elemPtrR = nextReg()
        emitIR(`  ${elemPtrR} = call ptr @${elemType}_deserialize(i32 ${elemNodeR})`)
        elemI64R = nextReg()
        emitIR(`  ${elemI64R} = ptrtoint ptr ${elemPtrR} to i64`)
    } else if (elemType == "int") {
        const valR = nextReg()
        emitIR(`  ${valR} = call i32 @jnArrayGetInt(i32 ${arrNodeR}, i32 ${idxR})`)
        elemI64R = nextReg()
        emitIR(`  ${elemI64R} = sext i32 ${valR} to i64`)
    } else if (elemType == "double") {
        const valR = nextReg()
        emitIR(`  ${valR} = call double @jnArrayGetDouble(i32 ${arrNodeR}, i32 ${idxR})`)
        elemI64R = nextReg()
        emitIR(`  ${elemI64R} = bitcast double ${valR} to i64`)
    } else if (elemType == "string") {
        const valR = nextReg()
        emitIR(`  ${valR} = call ptr @jnArrayGetString(i32 ${arrNodeR}, i32 ${idxR})`)
        emitRetainForType(valR, elemType)
        elemI64R = nextReg()
        emitIR(`  ${elemI64R} = ptrtoint ptr ${valR} to i64`)
    } else if (elemType == "bool") {
        const valR = nextReg()
        emitIR(`  ${valR} = call i32 @jnArrayGetBool(i32 ${arrNodeR}, i32 ${idxR})`)
        elemI64R = nextReg()
        emitIR(`  ${elemI64R} = zext i32 ${valR} to i64`)
    } else if (elemType.startsWith("Array<") == 1) {
        const innerArrNodeR = nextReg()
        emitIR(`  ${innerArrNodeR} = call i32 @jnArrayGet(i32 ${arrNodeR}, i32 ${idxR})`)
        const innerPtrR = emitArrayDeserializeInto(innerArrNodeR, elemType)
        elemI64R = nextReg()
        emitIR(`  ${elemI64R} = ptrtoint ptr ${innerPtrR} to i64`)
    }
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

// I021-requestbody — per-class @ClassName_deserialize(i32 nodeId): ClassName 编译期自动生成
// (mirror ss_drop / ss_deep_clone / ss_shallow_clone 模式 — D018 ObjectLayout TypeInfo +
//  D022 clone 语义 第四步 deserializer)。nodeId = JsonNode 实例 nodeId 字段 raw int
// (避免 JsonNode wrapper alloc 开销);字段递归:primitive(int/double/string/bool)调
// jnGet*(lib/json.ss),嵌套 user class 调 jnGetField + <NestedClass>_deserialize 递归,
// Array<Class> / Map<K,Class> 留 I021-requestbody-nested-array / -map 子档。
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
            const ft = classFieldTypes.has(`${className}.${p}`) == 1 ? classFieldTypes.getString(`${className}.${p}`) : "int"
            const keyConst = addStringConst(p)
            const dstR = nextReg()
            emitIR(`  ${dstR} = getelementptr %${className}, ptr %new, i32 0, i32 ${idx}`)
            if (ft == "int") {
                const valR = nextReg()
                emitIR(`  ${valR} = call i32 @jnGetInt(i32 %nodeId.arg, ptr ${keyConst})`)
                emitIR(`  store i32 ${valR}, ptr ${dstR}, align 8`)
            } else if (ft == "double") {
                const valR = nextReg()
                emitIR(`  ${valR} = call double @jnGetDouble(i32 %nodeId.arg, ptr ${keyConst})`)
                emitIR(`  store double ${valR}, ptr ${dstR}, align 8`)
            } else if (ft == "string") {
                const valR = nextReg()
                emitIR(`  ${valR} = call ptr @jnGetString(i32 %nodeId.arg, ptr ${keyConst})`)
                // string 字段必须 retain:jnGetString 返 jnStr 内部 ptr 未持新 RC,Outer drop
                // 时 emitFieldReleaseLoop ss_rc_release 字段 → free jnStr 仍持有的 string → 下一个
                // POST use-after-free。对照 emitClassDeepCloneFn / emitClassCtorBody ptr 字段 store
                // 前 emitRetainForType 模式(D018 + D022 contract)。
                emitRetainForType(valR, ft)
                emitIR(`  store ptr ${valR}, ptr ${dstR}, align 8`)
            } else if (ft == "bool") {
                const valR = nextReg()
                emitIR(`  ${valR} = call i32 @jnGetBool(i32 %nodeId.arg, ptr ${keyConst})`)
                emitIR(`  store i32 ${valR}, ptr ${dstR}, align 8`)
            } else if (isUserClass(ft) == 1) {
                // I021-requestbody-nested — 嵌套 user class 字段:jnGetField 拿子 nodeId(int)
                // + 递归调 <ft>_deserialize(返新 ptr rc=1,emitPendingDeserializers transitive
                // closure 保证 ft 也在 deserializerTargets 已 emit)+ 直接 store(无 retain;
                // 子 deserialize 已 transfer ownership,父 ss_drop_<Outer> 链 emit ss_release
                // 自动级联触发子 drop)。字段缺失 jnGetField 返 0 → 子 deserialize 内部 jnGet*
                // primitive 走默认值 fallback,生成全默认值嵌套对象 ptr(对齐 primitive 缺失 fallback)。
                const childIdR = nextReg()
                emitIR(`  ${childIdR} = call i32 @jnGetField(i32 %nodeId.arg, ptr ${keyConst})`)
                const childPtrR = nextReg()
                emitIR(`  ${childPtrR} = call ptr @${ft}_deserialize(i32 ${childIdR})`)
                emitIR(`  store ptr ${childPtrR}, ptr ${dstR}, align 8`)
            } else if (isArrayDeserializable(ft) == 1) {
                // I021-requestbody-nested-array(-primitive)(-array) — Array<UserClass | int |
                // string | double | bool | Array<X>> 单层 / N=2 双层 / 递归任意层。jnGetField
                // 拿 array 子 nodeId 后委托 emitArrayDeserializeInto inline emit ss_newArray(tag=1)
                // 或 ss_newArrayPtr(tag=5)+ jnArrayLen 循环 + 6 路 elemType 分派(原 5 路 + 内层
                // Array<X> 第 6 路递归 emitArrayDeserializeInto 自身),返 final array ptr。store
                // 直接 transfer ownership(内层 Array 是新分配 mimalloc ptr 持新 RC=1,无 retain)。
                // RC 双层契约:外层 push 内层 ptr 不 retain;内层 push string elem 必 retain
                // (jnStr 内部 ptr 未持新 RC,与 a096fd0 单层 string elem 同模式)。父
                // ss_drop_<Outer> 链由 emitFieldReleaseLoop 走 Array<X> 字段路径(gen_type_ops.ss
                // :172),tag=5 逐元素 ss_release_arr → 内层 tag={1|5} elem release 链。
                const arrNodeR = nextReg()
                emitIR(`  ${arrNodeR} = call i32 @jnGetField(i32 %nodeId.arg, ptr ${keyConst})`)
                const finalArrR = emitArrayDeserializeInto(arrNodeR, ft)
                emitIR(`  store ptr ${finalArrR}, ptr ${dstR}, align 8`)
            } else {
                // v0 不支持的字段类型(Map<K,Class>) — emit 默认值 fallback,留 -map 子档完善;
                // **未被 @RequestBody 引用的 class**(bootstrap 反射 Meta:FieldMeta 等)
                // 此 deserializer 永不被调用,fallback 仅是"per-class 函数自动生成对称形态"。
                const llType = ssTypeToLLVM(ft)
                if (llType == "i32") {
                    emitIR(`  store i32 0, ptr ${dstR}, align 8`)
                } else if (llType == "double") {
                    emitIR(`  store double 0.0, ptr ${dstR}, align 8`)
                } else {
                    emitIR(`  store ptr null, ptr ${dstR}, align 8`)
                }
            }
            idx = idx + 1
        }
    }
    emitIR("  ret ptr %new")
    emitIR("}")
    emitIR("")
}
