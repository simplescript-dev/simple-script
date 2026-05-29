// gen_builtins.ss — Built-in method handlers: string, higher-order, array, map, set
// Used by gen_methods.ss via textual import. No own imports needed.

// ── String methods ──────────────────────────────────────────────

function genStringMethod(method: string, objVal: string, argList: string): string {
    if (method == "charAt" || method == "charCodeAt" || method == "repeat") {
        const av = genExpr(parseInt(argList))
        let retT = "ptr"
        if (method == "charCodeAt") { retT = "i32" }
        const fn = preludeName(`ss_${method}`)
        const r = nextReg(); emitIR(`  ${r} = call ${retT} @${fn}(ptr ${objVal}, i32 ${av})`); return r
    }
    if (method == "substring") {
        const argParts = argList.split(",")
        const startVal = genExpr(parseInt(argParts[0]))
        const lenVal = genExpr(parseInt(argParts[1]))
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_substring(ptr ${objVal}, i32 ${startVal}, i32 ${lenVal})`); return r
    }
    if (method == "contains") {
        const sub = genExpr(parseInt(argList))
        const idxR = nextReg()
        emitIR(`  ${idxR} = call i32 @ss_indexOf(ptr ${objVal}, ptr ${sub})`)
        const cmpR = nextReg()
        emitIR(`  ${cmpR} = icmp sge i32 ${idxR}, 0`)
        const r = nextReg()
        emitIR(`  ${r} = zext i1 ${cmpR} to i32`)
        return r
    }
    if (method == "startsWith") {
        const sub = genExpr(parseInt(argList))
        const pLen = nextReg()
        emitIR(`  ${pLen} = call i32 @ss_stringLength(ptr ${sub})`)
        const subStr = nextReg()
        emitIR(`  ${subStr} = call ptr @ss_substring(ptr ${objVal}, i32 0, i32 ${pLen})`)
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_string_eq(ptr ${subStr}, ptr ${sub})`)
        return r
    }
    if (method == "endsWith") {
        const sub = genExpr(parseInt(argList))
        const sLen = nextReg()
        emitIR(`  ${sLen} = call i32 @ss_stringLength(ptr ${objVal})`)
        const sufLen = nextReg()
        emitIR(`  ${sufLen} = call i32 @ss_stringLength(ptr ${sub})`)
        const start = nextReg()
        emitIR(`  ${start} = sub i32 ${sLen}, ${sufLen}`)
        const subStr = nextReg()
        emitIR(`  ${subStr} = call ptr @ss_substring(ptr ${objVal}, i32 ${start}, i32 ${sufLen})`)
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_string_eq(ptr ${subStr}, ptr ${sub})`)
        return r
    }
    if (method == "replace") {
        const argParts = argList.split(",")
        const oldVal = genExpr(parseInt(argParts[0]))
        const newVal = genExpr(parseInt(argParts[1]))
        const fn = preludeName("ss_replace")
        const r = nextReg(); emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal}, ptr ${oldVal}, ptr ${newVal})`); return r
    }
    if (method == "split") {
        const delim = genExpr(parseInt(argList))
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_split(ptr ${objVal}, ptr ${delim})`); return r
    }
    if (method == "trim" || method == "toUpperCase" || method == "toLowerCase") {
        const fn = preludeName(`ss_${method}`)
        const r = nextReg(); emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal})`); return r
    }
    if (method == "padStart" || method == "padEnd") {
        const ap = argList.split(",")
        const w = genExpr(parseInt(ap[0]))
        const p = genExpr(parseInt(ap[1]))
        const fn = preludeName(`ss_${method}`)
        const r = nextReg(); emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal}, i32 ${w}, ptr ${p})`); return r
    }
    return ""
}

// ── Higher-order methods ────────────────────────────────────────

function genHigherOrderMethod(method: string, objVal: string, argList: string): string {
    if (method == "map" || method == "filter" || method == "forEach") {
        const cbVal = genExpr(parseInt(argList))
        const fn = preludeName(`ss_${method}`)
        const r = nextReg()
        emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal}, i64 ${cbVal})`)
        return r
    }
    if (method == "findIndex" || method == "some" || method == "every") {
        const cbVal = genExpr(parseInt(argList))
        const fn = preludeName(`ss_${method}`)
        const r = nextReg()
        emitIR(`  ${r} = call i32 @${fn}(ptr ${objVal}, i64 ${cbVal})`)
        return r
    }
    if (method == "find") {
        const cbVal = genExpr(parseInt(argList))
        const fn = preludeName("ss_find")
        const r64 = nextReg()
        emitIR(`  ${r64} = call i64 @${fn}(ptr ${objVal}, i64 ${cbVal})`)
        const r = nextReg()
        emitIR(`  ${r} = trunc i64 ${r64} to i32`)
        return r
    }
    if (method == "reduce") {
        const rArgs = argList.split(",")
        const cbVal = genExpr(parseInt(rArgs[0]))
        const initVal = genExpr(parseInt(rArgs[1]))
        let initI64 = initVal
        if (inferType(parseInt(rArgs[1])) == "int") {
            const sR = nextReg()
            emitIR(`  ${sR} = sext i32 ${initVal} to i64`)
            initI64 = sR
        }
        const fn = preludeName("ss_reduce")
        const r64 = nextReg()
        emitIR(`  ${r64} = call i64 @${fn}(ptr ${objVal}, i64 ${cbVal}, i64 ${initI64})`)
        const r = nextReg()
        emitIR(`  ${r} = trunc i64 ${r64} to i32`)
        return r
    }
    return ""
}

// ── Array methods ───────────────────────────────────────────────

function genArrayMethod(method: string, objVal: string, objType: string, argList: string): string {
    if (method == "push") {
        const argId = parseInt(argList)
        const val = genExpr(argId)
        const pushType = inferType(argId)
        let val64p = val
        const llPushType = ssTypeToLLVM(pushType)
        if (llPushType == "ptr") {
            if (pushNonOwning == 0 && isOwnedExpr(argId) == 0) {
                // D168 §C.9 / P2.3a: ref Array push borrowed 元素 retain — array 持有
                // elem 一份引用,dispatch via emitRetainForType(string/class/Array<T> 走
                // ss_retain,Map 走 ss_rc_retain)。owned 元素(new / 字面量 / 返回 owned
                // 的调用)自带 +1 转移给 array,不再 retain — 与 genVarDecl:653 同走 isOwnedExpr。
                emitRetainForType(val, pushType)
            }
            const cR = nextReg()
            emitIR(`  ${cR} = ptrtoint ptr ${val} to i64`)
            val64p = cR
        } else if (pushType == "double") {
            const dR = nextReg()
            emitIR(`  ${dR} = bitcast double ${val} to i64`)
            val64p = dR
        } else if (llPushType == "i64" || pushType == "i64") {
            val64p = val
        } else {
            const sR = nextReg()
            emitIR(`  ${sR} = sext i32 ${val} to i64`)
            val64p = sR
        }
        pushNonOwning = 0
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_arrayPush(ptr ${objVal}, i64 ${val64p})`); return r
    }
    if (method == "reverse") { emitIR(`  call void @ss_arrayReverse(ptr ${objVal})`); return objVal }
    if (method == "sort") { emitIR(`  call void @ss_arraySort(ptr ${objVal})`); return objVal }
    if (method == "slice") {
        const slArgs = argList.split(",")
        const slStart = genExpr(parseInt(slArgs[0]))
        // 单参 slice(start):end 缺省传 sentinel 2147483647,ss_arraySlice clamp 到 len
        // (复用解构 rest gen_decls.ss:399 既有 sentinel,对齐 comptime end 缺省 = len)
        let slEnd = "2147483647"
        if (slArgs.length() > 1) { slEnd = genExpr(parseInt(slArgs[1])) }
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_arraySlice(ptr ${objVal}, i32 ${slStart}, i32 ${slEnd})`); return r
    }
    if (method == "concat") {
        const otherArr = genExpr(parseInt(argList))
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_arrayConcat(ptr ${objVal}, ptr ${otherArr})`); return r
    }
    if (method == "includes") {
        const argId = parseInt(argList)
        const argType = inferType(argId)
        const sub = genExpr(argId)
        // string.includes(sub) → substring search via strstr (same as contains)
        if (objType == "string") {
            const idxR = nextReg()
            emitIR(`  ${idxR} = call i32 @ss_indexOf(ptr ${objVal}, ptr ${sub})`)
            const cmpR = nextReg()
            emitIR(`  ${cmpR} = icmp sge i32 ${idxR}, 0`)
            const r = nextReg()
            emitIR(`  ${r} = zext i1 ${cmpR} to i32`)
            return r
        }
        // Array.includes(elem): dispatch by argType (objType is "ptr" or "Array<T>")
        if (argType == "int" || argType == "i64" || argType == "double") {
            let val64 = sub
            if (argType == "int") {
                const sR = nextReg()
                emitIR(`  ${sR} = sext i32 ${sub} to i64`)
                val64 = sR
            }
            const idxR = nextReg()
            emitIR(`  ${idxR} = call i32 @ss_arrayIndexOf(ptr ${objVal}, i64 ${val64})`)
            const cmpR = nextReg()
            emitIR(`  ${cmpR} = icmp sge i32 ${idxR}, 0`)
            const r = nextReg()
            emitIR(`  ${r} = zext i1 ${cmpR} to i32`)
            return r
        }
        // string element: strcmp-based search
        const idxR = nextReg()
        emitIR(`  ${idxR} = call i32 @ss_arrayIndexOfStr(ptr ${objVal}, ptr ${sub})`)
        const cmpR = nextReg()
        emitIR(`  ${cmpR} = icmp sge i32 ${idxR}, 0`)
        const r = nextReg()
        emitIR(`  ${r} = zext i1 ${cmpR} to i32`)
        return r
    }
    return ""
}

// ── Map methods ─────────────────────────────────────────────────

function genMapMethod(method: string, objVal: string, objType: string, argList: string): string {
    if (method == "set") {
        const argParts = argList.split(",")
        let key = genExpr(parseInt(argParts[0]))
        const keyType = inferType(parseInt(argParts[0]))
        if (keyType == "i64") {
            const kR = nextReg()
            emitIR(`  ${kR} = inttoptr i64 ${key} to ptr`)
            key = kR
        }
        const valArgId = parseInt(argParts[1])
        const val = genExpr(valArgId)
        const valType = inferType(valArgId)
        let val64 = val
        const llValType = ssTypeToLLVM(valType)
        if (llValType == "ptr") {
            // D168 Phase 3 §C.10-map: ptr value retain — Map 持有 value 一份引用。
            // 走 ss_retain_any(magic@-4 分派 OLD/NEW),与 ss_mapSet/Delete/destroy_map
            // 的 ss_release_any 释放对称 —— retain/release 同按运行时 magic 分派,不依赖
            // 编译期类型名精度(emitRetainForType 对泛型/nullable/推断缺口的 NEW value
            // 误落 ss_rc_retain,与 ss_release_any 失配 → 半边 no-op → over-release UAF)。
            // owned 元素(new/字面量/返回 owned 的调用)自带 +1 转移,不再 retain —
            // 与 array push gen_builtins.ss:140 同走 isOwnedExpr。
            if (pushNonOwning == 0 && isOwnedExpr(valArgId) == 0) {
                emitIR(`  call void @ss_retain_any(ptr ${val})`)
            }
            pushNonOwning = 0
            // val_type flag @offset 516 = 1 标记 ptr value(typed + 无注解 Map() 统一覆盖);
            // ss_mapSet update / ss_mapDelete / ss_rc_destroy_map 据此走 ss_release_any。
            const vtGep = nextReg()
            emitIR(`  ${vtGep} = getelementptr i8, ptr ${objVal}, i64 516`)
            emitIR(`  store i32 1, ptr ${vtGep}, align 4`)
            const castR = nextReg()
            emitIR(`  ${castR} = ptrtoint ptr ${val} to i64`)
            val64 = castR
        } else if (valType == "double") {
            const dR = nextReg()
            emitIR(`  ${dR} = bitcast double ${val} to i64`)
            val64 = dR
        } else if (llValType == "i64" || valType == "i64") {
            val64 = val
        } else {
            const sextR = nextReg()
            emitIR(`  ${sextR} = sext i32 ${val} to i64`)
            val64 = sextR
        }
        emitIR(`  call void @ss_mapSet(ptr ${objVal}, ptr ${key}, i64 ${val64})`)
        return "0"
    }
    if (method == "get" || method == "getString" || method == "has") {
        let mkey = genExpr(parseInt(argList))
        const mkeyType = inferType(parseInt(argList))
        if (mkeyType == "i64") {
            const cvR = nextReg()
            emitIR(`  ${cvR} = inttoptr i64 ${mkey} to ptr`)
            mkey = cvR
        }
        if (method == "has") {
            const r = nextReg()
            emitIR(`  ${r} = call i32 @ss_mapHas(ptr ${objVal}, ptr ${mkey})`)
            return r
        }
        if (method == "getString") {
            const r = nextReg()
            emitIR(`  ${r} = call ptr @ss_mapGetString(ptr ${objVal}, ptr ${mkey})`)
            return r
        }
        const mapV = extractMapValueType(objType)
        if (mapV == "string") {
            // I019 — V=string routes ss_mapGetString.
            const r = nextReg()
            emitIR(`  ${r} = call ptr @ss_mapGetString(ptr ${objVal}, ptr ${mkey})`)
            return r
        }
        if (mapV == "int" || mapV == "bool") {
            // I020a — V=int: ss_mapGet i64 + trunc i32(r64 def must precede r32, LLVM SSA #-order).
            // I021-cartesian — V=bool 同形(SS bool 编码为 i32,与 int trunc 同模式).
            const r64 = nextReg()
            emitIR(`  ${r64} = call i64 @ss_mapGet(ptr ${objVal}, ptr ${mkey})`)
            const r32 = nextReg()
            emitIR(`  ${r32} = trunc i64 ${r64} to i32`)
            return r32
        }
        if (mapV == "double") {
            // I020b — V=double: ss_mapGet i64 + bitcast to double (mapSet bitcast double→i64 对称).
            const r64 = nextReg()
            emitIR(`  ${r64} = call i64 @ss_mapGet(ptr ${objVal}, ptr ${mkey})`)
            const rd = nextReg()
            emitIR(`  ${rd} = bitcast i64 ${r64} to double`)
            return rd
        }
        if (mapV.startsWith("Array<") == 1 || mapV.startsWith("Map<") == 1) {
            // I021-cartesian — V=Array<X> / V=Map<K2,V2>:ss_mapGet i64 + inttoptr ptr +
            // emitRetainForType (旧 RC 容器,emitRetainForType 自动分派 ss_rc_retain;
            // ss_rc_retain 自带 isnull guard,miss 返 ptr null 时 retain no-op).
            const r64 = nextReg()
            emitIR(`  ${r64} = call i64 @ss_mapGet(ptr ${objVal}, ptr ${mkey})`)
            const rp = nextReg()
            emitIR(`  ${rp} = inttoptr i64 ${r64} to ptr`)
            emitRetainForType(rp, mapV)
            return rp
        }
        // I021-requestbody-nested-optional-inner(D131) — V=Tag? strip 后参与 V=class 分派,
        // ss_retain 自带 isnull guard 同覆盖 nullable null value 路径(JSON null → ss_mapGet
        // i64 0 → inttoptr ptr null → retain no-op,if (v != null) narrow 解包,与 V=Tag
        // miss/null 同形)。
        const mapVStripped = stripNullableCG(mapV)
        if (mapVStripped != "" && classFields.has(mapVStripped) == 1) {
            // I020c — V=class: ss_mapGet i64 + inttoptr to ptr + emitRetainForType (双 RC 统一分派,
            // V=class 自动选 ss_retain;ss_retain 自带 isnull guard,miss 返 ptr null 时 retain no-op).
            const r64 = nextReg()
            emitIR(`  ${r64} = call i64 @ss_mapGet(ptr ${objVal}, ptr ${mkey})`)
            const rp = nextReg()
            emitIR(`  ${rp} = inttoptr i64 ${r64} to ptr`)
            emitRetainForType(rp, mapVStripped)
            return rp
        }
        const r = nextReg()
        emitIR(`  ${r} = call i64 @ss_mapGet(ptr ${objVal}, ptr ${mkey})`)
        return r
    }
    if (method == "size") { const r = nextReg(); emitIR(`  ${r} = call i32 @ss_mapSize(ptr ${objVal})`); return r }
    if (method == "keys") { const r = nextReg(); emitIR(`  ${r} = call ptr @ss_mapKeysArray(ptr ${objVal})`); return r }
    if (method == "delete") { const dk = genExpr(parseInt(argList)); emitIR(`  call void @ss_mapDelete(ptr ${objVal}, ptr ${dk})`); return "0" }
    return ""
}

// ── Set methods ─────────────────────────────────────────────────

// Set<T> methods — backed by Map (values stored as keys, value=1)
function genSetMethod(method: string, objVal: string, argList: string): string {
    if (method == "add" || method == "has") {
        const argId = parseInt(argList)
        let key = genExpr(argId)
        if (inferType(argId) == "i64") {
            const kR = nextReg()
            emitIR(`  ${kR} = inttoptr i64 ${key} to ptr`)
            key = kR
        }
        if (method == "add") {
            emitIR(`  call void @ss_mapSet(ptr ${objVal}, ptr ${key}, i64 1)`)
            return "0"
        }
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_mapHas(ptr ${objVal}, ptr ${key})`)
        return r
    }
    if (method == "remove") {
        const dk = genExpr(parseInt(argList))
        emitIR(`  call void @ss_mapDelete(ptr ${objVal}, ptr ${dk})`)
        return "0"
    }
    if (method == "size") { const r = nextReg(); emitIR(`  ${r} = call i32 @ss_mapSize(ptr ${objVal})`); return r }
    if (method == "values") { const r = nextReg(); emitIR(`  ${r} = call ptr @ss_mapKeys(ptr ${objVal})`); return r }
    return ""
}
