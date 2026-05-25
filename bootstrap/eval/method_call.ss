// METHOD_CALL 子目录文件(原 eval_expr.ss 迁出)
// 对称三段式:ctEnumNodes/runtime enum + Thread/super 短路 + args(NAMED_ARG/普通)+ comptime/runtime 分派

function evalMethodCall(astId: int): int {
    pendingSuperParent = resolveSuperParent(nGetI1(astId), astId)
    const mcMethod = nGetS1(astId)
    const mcObjNode = nGetI1(astId)
    if (nGetKind(mcObjNode) == "IDENT") {
        const mcObjName = nGetS1(mcObjNode)
        if (comptimeMustBeKnown == 1 && interpEnumNodes.has(mcObjName) == 1) {
            if (mcMethod == "values") { return ctVal(ctEnumListMethod(mcObjName, 0)) }
            if (mcMethod == "names") { return ctVal(ctEnumListMethod(mcObjName, 1)) }
            if (mcMethod == "valueOf") { return ctVal(ctEnumValueOfMethod(mcObjName, astId)) }
        }
        if (comptimeMustBeKnown == 1 && mcObjName == "reflect") {
            return ctReflectMethodDispatch(astId, mcMethod)
        }
        if (comptimeMustBeKnown == 0 && enumReady == 1 && enumDeclNodes.has(mcObjName) == 1) {
            if (mcMethod == "values") { return 0 - constVal(genEnumValues(mcObjName)) - 1 }
            if (mcMethod == "names") { return 0 - constVal(genEnumNames(mcObjName)) - 1 }
            if (mcMethod == "valueOf") { return 0 - constVal(genEnumValueOf(mcObjName, nGetList(astId))) - 1 }
        }
        if (comptimeMustBeKnown == 0) {
            if (mcObjName == "Thread" && mcMethod == "start") { return 0 - constVal(genMethodCall(astId)) - 1 }
            if (getVarType(mcObjName) == "" && classFields.has(mcObjName) == 1) { return 0 - constVal(genMethodCall(astId)) - 1 }
        }
    }
    if (comptimeMustBeKnown == 0 && pendingSuperParent != "") { return 0 - constVal(genMethodCall(astId)) - 1 }
    const mcObj = genVal(mcObjNode)
    let mcObjReg = ""
    if (isCt(mcObj) == 0) { mcObjReg = reg(mcObj) }
    const mcArgList = nGetList(astId)
    // D148 Phase 5: outer pre-eval 4 helper 反推循环全删(含 mangled name resolution) — checker 已写
    // nSetS2(check_exprs.ss:155 METHOD_CALL arg 反推 ★ + check_types.ss:42 checkerInferType 4 case),
    // codegen 阶段 H6 short-circuit 已 noop;eval pre-eval 时序前移亦无价值。
    const mcSavedCPR = callPreRegs
    callPreRegs = new Map()
    let mcCtArgs: Array<string> = []
    let mcCtNamed = new Map()
    let mcHasNamed = 0
    if (mcArgList != "") {
        const mcArgParts = mcArgList.split(",")
        for (mcap in mcArgParts) {
            const mcArgId = parseInt(mcap)
            if (mcArgId > 0) {
                if (nGetKind(mcArgId) == "NAMED_ARG") {
                    mcHasNamed = 1
                    const mcnv = genVal(nGetI1(mcArgId))
                    if (isCt(mcnv) == 1) {
                        mcCtNamed.set(nGetS1(mcArgId), `${payload(mcnv)}`)
                    } else {
                        mcCtNamed.set(nGetS1(mcArgId), `${interpNewNull()}`)
                        callPreRegs.set(`${mcArgId}`, reg(mcnv))
                    }
                } else {
                    const mcav = genVal(mcArgId)
                    if (isCt(mcav) == 1) {
                        mcCtArgs = mcCtArgs.push(`${payload(mcav)}`)
                    } else {
                        mcCtArgs = mcCtArgs.push(`${interpNewNull()}`)
                        callPreRegs.set(`${mcArgId}`, reg(mcav))
                    }
                }
            }
        }
    }
    if (comptimeMustBeKnown == 1) {
        callPreRegs = mcSavedCPR
        if (isCt(mcObj) == 0) {
            return comptimeError(`cannot call method '${mcMethod}' on runtime value`, astId)
        }
        return ctMethodCallDispatch(astId, mcMethod, payload(mcObj), mcCtArgs, mcCtNamed, mcHasNamed)
    }
    // ctVal array/map 接收者无法 materialize 成寄存器(interp_value.ss:41 返 "0"),
    // 必须走 ctMethodCallDispatch 否则运行时 genMethodCall 发 `ss_mapKeysArray(ptr 0)`。
    // @methodOf handler 体常触发(comptimeMustBeKnown == 0 + for-in 绑 ctVal)。
    if (isCt(mcObj) == 1) {
        const mcObjKind = interpType(payload(mcObj))
        if (mcObjKind == "array" || mcObjKind == "map") {
            callPreRegs = mcSavedCPR
            return ctMethodCallDispatch(astId, mcMethod, payload(mcObj), mcCtArgs, mcCtNamed, mcHasNamed)
        }
        // I014 §路径 A + I018 §路径 A — ctVar class instance w/ (className, methodName) 字
        // 段对 + invoke sentinel → emit `call @<cn>_<mn>(ptr null[, ptr <arg>...])` 静态
        // IR,消除 comptime (path, cn, mn) 与 runtime method call 的 symbolic gap(D088
        // §反模式 禁 @comptimeEmit/runtime 反射)。I018 runtime arg 通道:funcParamCount
        // (gen_registry.ss pre-register)拿 callee arity,callPreRegs[mcArgId] 取 runtime
        // reg,按形参数追加;0 形参保持单 this 不回归(I014 Phase 2 契约)。
        if (mcObjKind == "object" && mcMethod == "invoke") {
            const ctObjId = payload(mcObj)
            const cnTv = interpGetField(ctObjId, "className")
            const mnTv = interpGetField(ctObjId, "methodName")
            if (interpType(cnTv) == "string" && interpType(mnTv) == "string") {
                const cnStr = interpAsStr(cnTv)
                const mnStr = interpAsStr(mnTv)
                if (cnStr != "" && mnStr != "") {
                    const mangled = `${cnStr}_${mnStr}`
                    // I018 §路径 A — 按 callee 形参数追加 runtime args(callPreRegs reset 之前)
                    // I021bc — 按 funcParamTypes[mangled:idx] 分派 cast emit:V=int → ss_parseInt
                    // + i32 / V=double → ss_parseDouble + double / V=string/默认 → ptr 透传。
                    // 信息源 = gen_registry.ss registerClassMethodRetType 注册端;消费端按目标
                    // LLVM 类型 emit cast,消除 dispatcher ptr 实参 vs callee i32/double 形参 LLVM
                    // type mismatch silent miscompile。
                    let invokeExtraArgs = ""
                    // I021-multi-param — 数据驱动模式:ctObj 含 paramSpecs ct array 字段时,
                    // sentinel 自驱按 N 个 spec emit ss_mapGetString + cast,生成单次多参 call;
                    // dispatch 单调用 `r.invoke(req)`,sentinel 内部展开 multi-spec 实参表,消除
                    // dispatch ct unroll spec loop 各发独立 invoke 的 silent miscompile 双轨。
                    const psSv = interpGetField(ctObjId, "paramSpecs")
                    let useParamSpecs = 0
                    let psArrIdSv = 0
                    let psLenSv = 0
                    if (interpType(psSv) == "array") {
                        psArrIdSv = payload(psSv)
                        psLenSv = interpArrayLen(psArrIdSv)
                        if (psLenSv > 0) { useParamSpecs = 1 }
                    }
                    if (useParamSpecs == 1 && mcArgList != "") {
                        // dispatch 写 r.invoke(req) — mcArgList 第一个 mcArgId 对应 req map LLVM reg
                        const mcArgPartsPS = mcArgList.split(",")
                        let reqRegPS = ""
                        for (mcapPS in mcArgPartsPS) {
                            if (reqRegPS == "") {
                                const mcArgIdPS = parseInt(mcapPS)
                                if (mcArgIdPS > 0 && callPreRegs.has(`${mcArgIdPS}`) == 1) {
                                    reqRegPS = callPreRegs.getString(`${mcArgIdPS}`)
                                }
                            }
                        }
                        if (reqRegPS != "") {
                            let psIdx = 0
                            while (psIdx < psLenSv) {
                                const specVal = interpArrayGet(psArrIdSv, psIdx)
                                if (interpType(specVal) == "object") {
                                    const specObjId = payload(specVal)
                                    const kindTv = interpGetField(specObjId, "kind")
                                    const kindStr = interpType(kindTv) == "string" ? interpAsStr(kindTv) : ""
                                    if (kindStr == "RequestParam" || kindStr == "PathVariable" || kindStr == "RequestHeader") {
                                        const nameTv = interpGetField(specObjId, "name")
                                        const typeTv = interpGetField(specObjId, "type")
                                        const nameStr = interpType(nameTv) == "string" ? interpAsStr(nameTv) : ""
                                        const typeStr = interpType(typeTv) == "string" ? interpAsStr(typeTv) : ""
                                        // I021-pathvariable — kind == "PathVariable" 走 __pv_ prefix 隔离 namespace,
                                        // dispatch matchPath 在 runtime 写 req.set("__pv_<name>", value),sentinel 这里
                                        // emit ss_mapGetString(req, "__pv_<name>") 取值,与 RequestParam query namespace 分离。
                                        // I021-requestheader — kind == "RequestHeader" 走 __hdr_ prefix 隔离 namespace,
                                        // lib/http.ss:78 parseRequest 写 req.set("__hdr_<lower-name>", value),sentinel 这里
                                        // emit ss_mapGetString(req, "__hdr_<lower-name>") 取值,与 RequestParam query / __pv_
                                        // path variable namespace 三方严格分离;name 在 comptime push 时已 lowercase normalize
                                        // (lib/spring/boot/application.ss RequestHeader 分支),sentinel emit 不重复 toLowerCase。
                                        // cast 通道(int/double/ptr 分派)RequestParam / PathVariable / RequestHeader 三 kind 完全复用,不三轨。
                                        let lookupKey = nameStr
                                        if (kindStr == "PathVariable") { lookupKey = "__pv_" + nameStr }
                                        else if (kindStr == "RequestHeader") { lookupKey = "__hdr_" + nameStr }
                                        const nameStrConst = addStringConst(lookupKey)
                                        const valReg = nextReg()
                                        emitIR(`  ${valReg} = call ptr @ss_mapGetString(ptr ${reqRegPS}, ptr ${nameStrConst})`)
                                        if (typeStr == "int") {
                                            const intReg = nextReg()
                                            emitIR(`  ${intReg} = call i32 @ss_parseInt(ptr ${valReg})`)
                                            invokeExtraArgs = `${invokeExtraArgs}, i32 ${intReg}`
                                        } else if (typeStr == "double") {
                                            const dblReg = nextReg()
                                            emitIR(`  ${dblReg} = call double @ss_parseDouble(ptr ${valReg})`)
                                            invokeExtraArgs = `${invokeExtraArgs}, double ${dblReg}`
                                        } else {
                                            invokeExtraArgs = `${invokeExtraArgs}, ptr ${valReg}`
                                        }
                                    } else if (kindStr == "RequestBody") {
                                        // I021-requestbody — kindStr == "RequestBody" 分支:POST/PUT/PATCH
                                        // JSON body → class 反序列化:emit ss_mapGetString(req, "body") + JSON_parse + JsonNode.nodeId 取
                                        // 字段 + per-class @<ClassName>_deserialize(i32 nodeId) 自动生成
                                        // (gen_type_ops.ss:emitClassDeserializeFn 模式 mirror ss_drop_X)。
                                        // ParamSpec.type 存 SS class 名(D123 §253 alignment — 重用 type slot,
                                        // 不扩 ParamSpec 字段)。body key 直接用 "body"(对齐 lib/http.ss:83
                                        // I014 split body 入此 key,无 namespace 撞名风险)。
                                        const typeTv = interpGetField(specObjId, "type")
                                        const typeStr = interpType(typeTv) == "string" ? interpAsStr(typeTv) : ""
                                        // 注册 deserializer emit target — codegen.ss emitGlobalsAndCode 末尾
                                        // emitPendingDeserializers 选择性 emit,避免 jnGet* 污染所有程序。
                                        deserializerTargets.set(typeStr, 1)
                                        const bodyKeyConst = addStringConst("body")
                                        const bodyReg = nextReg()
                                        emitIR(`  ${bodyReg} = call ptr @ss_mapGetString(ptr ${reqRegPS}, ptr ${bodyKeyConst})`)
                                        const nodeJnReg = nextReg()
                                        emitIR(`  ${nodeJnReg} = call ptr @JSON_parse(ptr ${bodyReg})`)
                                        // jnRoot 走 SS 函数 ABI 取 JsonNode.nodeId,不直接 GEP %JsonNode
                                        // struct slot — 避免 lib/json 内部布局 leak 到 bootstrap 编译器
                                        const nodeIdReg = nextReg()
                                        emitIR(`  ${nodeIdReg} = call i32 @jnRoot(ptr ${nodeJnReg})`)
                                        const instReg = nextReg()
                                        emitIR(`  ${instReg} = call ptr @${typeStr}_deserialize(i32 ${nodeIdReg})`)
                                        invokeExtraArgs = `${invokeExtraArgs}, ptr ${instReg}`
                                    } else if (kindStr == "RequestMap") {
                                        invokeExtraArgs = `${invokeExtraArgs}, ptr ${reqRegPS}`
                                    }
                                }
                                psIdx = psIdx + 1
                            }
                        }
                    }
                    if (useParamSpecs == 0 && funcParamCount.has(mangled) == 1 && mcArgList != "") {
                        const expectedPC = parseInt(funcParamCount.getString(mangled))
                        if (expectedPC > 0) {
                            const mcArgParts2 = mcArgList.split(",")
                            let consumed = 0
                            for (mcap2 in mcArgParts2) {
                                const mcArgId2 = parseInt(mcap2)
                                if (mcArgId2 > 0 && consumed < expectedPC) {
                                    if (callPreRegs.has(`${mcArgId2}`) == 1) {
                                        const aReg = callPreRegs.getString(`${mcArgId2}`)
                                        const ptKey = `${mangled}:${consumed}`
                                        const ssType = funcParamTypes.has(ptKey) == 1 ? funcParamTypes.getString(ptKey) : ""
                                        if (ssType == "int") {
                                            const intReg = nextReg()
                                            emitIR(`  ${intReg} = call i32 @ss_parseInt(ptr ${aReg})`)
                                            invokeExtraArgs = `${invokeExtraArgs}, i32 ${intReg}`
                                        } else if (ssType == "double") {
                                            const dblReg = nextReg()
                                            emitIR(`  ${dblReg} = call double @ss_parseDouble(ptr ${aReg})`)
                                            invokeExtraArgs = `${invokeExtraArgs}, double ${dblReg}`
                                        } else {
                                            invokeExtraArgs = `${invokeExtraArgs}, ptr ${aReg}`
                                        }
                                    } else {
                                        invokeExtraArgs = `${invokeExtraArgs}, ptr null`
                                    }
                                    consumed = consumed + 1
                                }
                            }
                        }
                    }
                    callPreRegs = mcSavedCPR
                    const retTy = funcRetTypes.has(mangled) == 1 ? funcRetTypes.getString(mangled) : "string"
                    const llRet = retTy == "void" ? "void" : (retTy == "int" ? "i32" : "ptr")
                    if (llRet == "void") {
                        emitIR(`  call void @${mangled}(ptr null${invokeExtraArgs})`)
                        return 0 - constVal("null") - 1
                    }
                    const resReg = nextReg()
                    emitIR(`  ${resReg} = call ${llRet} @${mangled}(ptr null${invokeExtraArgs})`)
                    return 0 - constVal(resReg) - 1
                }
            }
            return comptimeError(`static dispatch 'invoke' requires className+methodName fields on ctVar class instance`, astId)
        }
    }
    if (nGetI3(astId) > 0) {
        callPreRegs.set(`${mcObjNode}`, mcObjReg)
        const mcOptResult = genOptionalMethodCall(astId)
        callPreRegs = mcSavedCPR
        return 0 - constVal(mcOptResult) - 1
    }
    const mcResult = genMethodCall(astId, mcObjReg)
    callPreRegs = mcSavedCPR
    return 0 - constVal(mcResult) - 1
}
