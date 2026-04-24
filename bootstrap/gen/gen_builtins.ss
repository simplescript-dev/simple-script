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
    if (method == "join") {
        const delim = genExpr(parseInt(argList))
        const fn = preludeName("ss_join")
        const r = nextReg(); emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal}, ptr ${delim})`); return r
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
            if (pushNonOwning == 0) {
                emitIR(`  call void @ss_rc_retain(ptr ${val})`)
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
        const slEnd = genExpr(parseInt(slArgs[1]))
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
        const val = genExpr(parseInt(argParts[1]))
        const valType = inferType(parseInt(argParts[1]))
        let val64 = val
        const llValType = ssTypeToLLVM(valType)
        if (llValType == "ptr") {
            emitIR(`  call void @ss_rc_retain(ptr ${val})`)
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
        const r = nextReg()
        if (method == "has") {
            emitIR(`  ${r} = call i32 @ss_mapHas(ptr ${objVal}, ptr ${mkey})`)
        } else if (method == "getString") {
            emitIR(`  ${r} = call ptr @ss_mapGetString(ptr ${objVal}, ptr ${mkey})`)
        } else if (objType.startsWith("Map<") == 1 && extractMapValueType(objType) == "string") {
            // I019 — typed Map<K,string>.get → ss_mapGetString (ptr + @.rt.str.empty on miss).
            emitIR(`  ${r} = call ptr @ss_mapGetString(ptr ${objVal}, ptr ${mkey})`)
        } else {
            emitIR(`  ${r} = call i64 @ss_mapGet(ptr ${objVal}, ptr ${mkey})`)
        }
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
