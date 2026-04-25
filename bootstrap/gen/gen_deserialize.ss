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

// I021-requestbody-nested-array — Array<UserClass> 字段谓词;
// Array<int> / Array<string> primitive 元素返 0,留 -array-primitive 子档处理。
function isArrayClass(ft: string): int {
    if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
    return isUserClass(extractContainerElemType(ft))
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
            } else if (isArrayClass(ft) == 1) {
                // I021-requestbody-nested-array — Array<UserClass> 字段元素类型递归入队
                // (b79aa97 单遍 BFS 升维 cover collection 维度;原仅 cover scalar 字段
                // user class,现 cover array elem class 同一封闭性)。
                const et = extractContainerElemType(ft)
                if (deserializerTargets.has(et) == 0) {
                    deserializerTargets.set(et, 1)
                    workList = workList.push(et)
                }
            }
        }
    }
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
            } else if (isArrayClass(ft) == 1) {
                // I021-requestbody-nested-array — Array<UserClass> 字段:jnGetField 拿 array
                // 子 nodeId + jnArrayLen 拿 length + ss_newArrayPtr(0) 初始空 ptr-array
                // (D013 list-append 标准 ss_arrayPush 唯一入口,tag=5 ptr 元素 array);
                // 循环 jnArrayGet(arrNode, idx) 拿元素 nodeId → <ElemClass>_deserialize 拿子 ptr
                // → ptrtoint i64 → ss_arrayPush(arr, val);**无 retain**(子 deserialize 已 transfer
                // ownership,push 仅存指针不增 RC,对称 nested v0 字段 store transfer)。
                // 父 ss_drop_<Outer> 链由 emitFieldReleaseLoop 走 Array<X> 字段 release 路径
                // (gen_type_ops.ss:172,与 lib/spring/boot/application.ss Array<RouteMeta>
                // 实战路径同),逐元素自动级联 ss_drop_<Item> + free 容器。
                const elemType = extractContainerElemType(ft)
                const arrNodeR = nextReg()
                emitIR(`  ${arrNodeR} = call i32 @jnGetField(i32 %nodeId.arg, ptr ${keyConst})`)
                const arrLenR = nextReg()
                emitIR(`  ${arrLenR} = call i32 @jnArrayLen(i32 ${arrNodeR})`)
                const initArrR = nextReg()
                emitIR(`  ${initArrR} = call ptr @ss_newArrayPtr(i32 0)`)
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
                const elemPtrR = nextReg()
                emitIR(`  ${elemPtrR} = call ptr @${elemType}_deserialize(i32 ${elemNodeR})`)
                const elemI64R = nextReg()
                emitIR(`  ${elemI64R} = ptrtoint ptr ${elemPtrR} to i64`)
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
