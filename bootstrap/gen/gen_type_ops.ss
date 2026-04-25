// TypeInfo, drop, clone, vtable, and dtor generation for classes

// ── Class dtor tags ──────────────────────────────────────────
// Assign unique tags (>= 10) to classes with ptr fields for destructor dispatch.
// Called after resolveInheritance() so inherited fields are known.

// Per-class dtor tag assignment for comptime-generated classes.
function assignDtorTagForClass(className: string) {
    if (classDtorTags.has(className) == 1) { return }
    const fieldStr = classFields.getString(className)
    if (fieldStr == "") { return }
    let hasPtrField = 0
    const dtFields = fieldStr.split(",")
    for (dtf in dtFields) {
        if (dtf == "") { continue }
        const dtOwner = findFieldOwner(dtf, className)
        if (dtOwner == "") { continue }
        const dtType = classFieldTypes.getString(`${dtOwner}.${dtf}`)
        if (dtType == "" ) { continue }
        if (ssTypeToLLVM(dtType) == "ptr") { hasPtrField = 1 }
    }
    if (hasPtrField == 1) {
        classDtorTags.set(className, `${dtorNextTag}`)
        dtorNextTag = dtorNextTag + 1
    }
}

function assignClassDtorTags() {
    const cList = classFields.keys()
    for (c in cList) {
        if (c == "" || c == "Map") { continue }
        assignDtorTagForClass(c)
    }
}

// ── Vtable ────────────────────────────────────────────────────
// Build vtable metadata for classes in inheritance hierarchies.
// Called after resolveInheritance() so parent chains are complete.

function buildClassVtables() {
    const classList = classFields.keys()
    // Mark all classes that are part of an inheritance hierarchy
    for (cls in classList) {
        if (cls == "") { continue }
        if (classParents.has(cls) == 1) {
            classNeedsVtable.set(cls, "1")
            classNeedsVtable.set(classParents.getString(cls), "1")
        }
    }
    // Build vtable for each marked class (recursion ensures parents built first)
    for (cls in classList) {
        if (cls == "") { continue }
        if (classNeedsVtable.has(cls) == 0) { continue }
        buildVtableForClass(cls)
    }
}

function buildVtableForClass(cls: string) {
    // Already built?
    if (classVtableSlots.has(cls) == 1) { return }
    const parent = classParents.has(cls) == 1 ? classParents.getString(cls) : ""
    // Build parent first (recursion)
    if (parent != "" && classNeedsVtable.has(parent) == 1) {
        buildVtableForClass(parent)
    }
    let slots = ""
    // Inherit parent slot ordering + implementations
    if (parent != "" && classVtableSlots.has(parent) == 1) {
        slots = classVtableSlots.getString(parent)
        const parentSlots = slots.split(",")
        for (ps in parentSlots) {
            if (ps == "") { continue }
            const parentImpl = classVtableImpl.getString(`${parent}.${ps}`)
            classVtableImpl.set(`${cls}.${ps}`, parentImpl)
        }
    }
    // Collect own methods + toJson
    let allMethods = classMethods.getString(cls)
    const fieldStr = classFields.getString(cls)
    if (fieldStr != "") {
        if (allMethods == "") { allMethods = "toJson" }
        else if (allMethods.contains("toJson") == 0) { allMethods = `${allMethods},toJson` }
    }
    if (allMethods != "") {
        const methods = allMethods.split(",")
        for (m in methods) {
            if (m == "") { continue }
            // Check if already in slots
            let found = 0
            if (slots != "") {
                const existing = slots.split(",")
                for (es in existing) {
                    if (es == m) { found = 1 }
                }
            }
            if (found == 0) {
                slots = listAppendStr(slots, m)
            }
            // Set implementation for this class (null for abstract methods D071)
            if (abstractMethodsCG.has(`${cls}.${m}`) == 1) {
                classVtableImpl.set(`${cls}.${m}`, "null")
            } else {
                classVtableImpl.set(`${cls}.${m}`, `${cls}_${m}`)
            }
        }
    }
    classVtableSlots.set(cls, slots)
}

// ── Vtable codegen ───────────────────────────────────────────

function emitClassVtableConst(name: string, hasVtable: int) {
    if (hasVtable == 0 || classVtableSlots.has(name) == 0) { return }
    const vtSlots = classVtableSlots.getString(name)
    if (vtSlots == "") { return }
    const slotParts = vtSlots.split(",")
    let vtEntries = ""
    let vtCount = 0
    for (sp in slotParts) {
        if (sp == "") { continue }
        const impl = classVtableImpl.getString(`${name}.${sp}`)
        if (vtCount > 0) { vtEntries = vtEntries + ", " }
        if (impl == "null") {
            vtEntries = `${vtEntries}ptr null`
        } else {
            vtEntries = `${vtEntries}ptr @${impl}`
        }
        vtCount = vtCount + 1
    }
    emitIR(`@${name}_vtable = constant [${vtCount} x ptr] [${vtEntries}]`)
    emitIR("")
}

// ── Dtor registration ────────────────────────────────────────

function emitClassDtorRegister(name: string, fieldStr: string, hasVtable: int) {
    if (classDtorTags.has(name) == 0) { return }
    const dtorTag = parseInt(classDtorTags.getString(name))
    emitClassDestroy(name, fieldStr, hasVtable)
    const dtorIdx = dtorTag - 10
    emitIR(`@${name}_dtor_init = internal global i1 false`)
    emitIR(`define internal void @${name}_dtor_register() {`)
    emitIR("entry:")
    emitIR(`  %done = load i1, ptr @${name}_dtor_init`)
    emitIR(`  br i1 %done, label %ret, label %init`)
    emitIR("init:")
    emitIR(`  store i1 true, ptr @${name}_dtor_init`)
    emitIR(`  %gep = getelementptr [100 x ptr], ptr @ss_class_dtor, i64 0, i64 ${dtorIdx}`)
    emitIR(`  store ptr @${name}_destroy, ptr %gep`)
    emitIR("  br label %ret")
    emitIR("ret:")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")
}

// Emit @ClassName_destroy(ptr %self) — release all ptr-type fields (old dtor system)
function emitClassDestroy(className: string, fieldStr: string, hasVtable: int) {
    regCount = 0
    regTable = []
    emitIR(`define void @${className}_destroy(ptr %self) {`)
    emitIR("entry:")
    emitFieldReleaseLoop(className, fieldStr, hasVtable)
    emitIR("  ret void")
    emitIR("}")
    emitIR("")
}

// ── Field release loop ───────────────────────────────────────
// Shared by emitClassDestroy and emitClassDropFn

function emitFieldReleaseLoop(className: string, fieldStr: string, hasVtable: int) {
    if (fieldStr == "") { return }
    let idx = fieldStartIdx(hasVtable)
    const parts = fieldStr.split(",")
    for (p in parts) {
        const owner = findFieldOwner(p, className)
        let ft = ""
        if (owner != "") { ft = classFieldTypes.getString(`${owner}.${p}`) }
        if (ft == "") { ft = classFieldTypes.getString(`${className}.${p}`) }
        const llType = ssTypeToLLVM(ft)
        if (llType == "ptr") {
            const gepR = nextReg()
            emitIR(`  ${gepR} = getelementptr %${className}, ptr %self, i32 0, i32 ${idx}`)
            const loadR = nextReg()
            emitIR(`  ${loadR} = load ptr, ptr ${gepR}, align 8`)
            if (nonOwningFields.has(`${className}.${p}`) == 1) {
                emitIR(`  call void @ss_rc_release_no_children(ptr ${loadR})`)
            } else {
                emitReleaseForType(loadR, ft)
            }
        }
        idx = idx + 1
    }
}

// ── TypeInfo + drop + clone ──────────────────────────────────

// Emit drop/clone functions and TypeInfo constant per class
// (per-class deserializer 拆到 gen_deserialize.ss — F1 ≤ 600 物理拆 + deserialize 单一职能)。
function emitClassTypeInfo(name: string, fieldStr: string, hasVtable: int) {
    emitClassDropFn(name, fieldStr, hasVtable)
    emitClassDeepCloneFn(name, fieldStr, hasVtable)
    emitClassShallowCloneFn(name, fieldStr, hasVtable)
    // Emit type name string constant
    const nameLen = name.length() + 1
    emitIR(`@.rt.str.${name} = private constant [${nameLen} x i8] c"${name}\\00"`)
    const cid = classIds.has(name) == 1 ? classIds.getString(name) : "0"
    const parentName = classParents.has(name) == 1 ? classParents.getString(name) : ""
    let parentTIRef = "null"
    if (parentName != "") {
        parentTIRef = `@${parentName}_type_info`
    }
    emitIR(`@${name}_type_info = constant %TypeInfo {`)
    emitIR(`  ptr @ss_drop_${name},`)
    emitIR(`  ptr @ss_deep_clone_${name},`)
    emitIR(`  ptr @ss_shallow_clone_${name},`)
    emitIR(`  i64 ptrtoint (ptr getelementptr (%${name}, ptr null, i32 1) to i64),`)
    emitIR(`  ptr @.rt.str.${name},`)
    emitIR(`  i32 ${cid},`)
    emitIR(`  ptr ${parentTIRef}`)
    emitIR("}")
    emitIR("")
}

// ss_drop_ClassName — release all ref-typed fields, then dealloc
function emitClassDropFn(className: string, fieldStr: string, hasVtable: int) {
    emitIR(`define void @ss_drop_${className}(ptr %self) {`)
    emitIR("entry:")
    emitIR(`  call void @ss_drop_fields_${className}(ptr %self)`)
    emitIR(`  call void @ss_dealloc(ptr %self)`)
    emitIR("  ret void")
    emitIR("}")
    emitIR("")
}

// ss_drop_fields_ClassName — release ref-typed fields only (NO dealloc)
// Used by REUSE: keep memory, just release old field references
function emitClassDropFieldsFn(className: string, fieldStr: string, hasVtable: int) {
    regCount = 0
    regTable = []
    emitIR(`define void @ss_drop_fields_${className}(ptr %self) {`)
    emitIR("entry:")
    emitFieldReleaseLoop(className, fieldStr, hasVtable)
    emitIR("  ret void")
    emitIR("}")
    emitIR("")
}

// Shared constructor body: write rc, TypeInfo, vtable, fields into objReg
function emitClassCtorBody(name: string, fieldStr: string, hasVtable: int, objReg: string) {
    const rcGep = nextReg()
    emitIR(`  ${rcGep} = getelementptr %${name}, ptr ${objReg}, i32 0, i32 0`)
    emitIR(`  store i32 1, ptr ${rcGep}, align 4`)
    const tiGep = nextReg()
    emitIR(`  ${tiGep} = getelementptr %${name}, ptr ${objReg}, i32 0, i32 1`)
    emitIR(`  store ptr @${name}_type_info, ptr ${tiGep}, align 8`)
    if (hasVtable == 1) {
        const vtGep = nextReg()
        emitIR(`  ${vtGep} = getelementptr %${name}, ptr ${objReg}, i32 0, i32 2`)
        emitIR(`  store ptr @${name}_vtable, ptr ${vtGep}, align 8`)
    }
    if (fieldStr != "") {
        let idx = fieldStartIdx(hasVtable)
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(`${name}.${p}`)
            const llType = ssTypeToLLVM(ft)
            const gepReg = nextReg()
            emitIR(`  ${gepReg} = getelementptr %${name}, ptr ${objReg}, i32 0, i32 ${idx}`)
            if (llType == "ptr") {
                emitRetainForType(`%${p}.arg`, ft)
            }
            emitIR(`  store ${llType} %${p}.arg, ptr ${gepReg}, align 8`)
            idx = idx + 1
        }
    }
}

// ClassName_new_reuse(ptr, args) — constructor variant that reuses existing memory
function emitClassConstructorReuse(name: string, fieldStr: string, hasVtable: int) {
    let ctorParams = "ptr %__reuse"
    if (fieldStr != "") {
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(`${name}.${p}`)
            const llType = ssTypeToLLVM(ft)
            ctorParams = `${ctorParams}, ${llType} %${p}.arg`
        }
    }
    regCount = 0
    regTable = []
    emitIR(`define ptr @${name}_new_reuse(${ctorParams}) {`)
    emitIR("entry:")
    emitClassCtorBody(name, fieldStr, hasVtable, "%__reuse")
    emitIR("  ret ptr %__reuse")
    emitIR("}")
    emitIR("")
}

// ss_deep_clone_ClassName — allocate new object, deep-copy fields
function emitClassDeepCloneFn(className: string, fieldStr: string, hasVtable: int) {
    regCount = 0
    regTable = []
    emitIR(`define ptr @ss_deep_clone_${className}(ptr %self) {`)
    emitIR("entry:")
    // Allocate new object via mimalloc
    emitIR(`  %size = ptrtoint ptr getelementptr (%${className}, ptr null, i32 1) to i64`)
    emitIR("  %new = call ptr @mi_calloc(i64 1, i64 %size)")
    // Set rc = 1
    emitIR("  store i32 1, ptr %new, align 4")
    // Set TypeInfo pointer
    emitIR(`  %ti_ptr = getelementptr %${className}, ptr %new, i32 0, i32 1`)
    emitIR(`  store ptr @${className}_type_info, ptr %ti_ptr, align 8`)
    // Copy vtable pointer if needed
    if (hasVtable == 1) {
        emitIR(`  %vt_src = getelementptr %${className}, ptr %self, i32 0, i32 2`)
        emitIR("  %vt_val = load ptr, ptr %vt_src, align 8")
        emitIR(`  %vt_dst = getelementptr %${className}, ptr %new, i32 0, i32 2`)
        emitIR("  store ptr %vt_val, ptr %vt_dst, align 8")
    }
    // Copy each field
    if (fieldStr != "") {
        let idx = fieldStartIdx(hasVtable)
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.has(`${className}.${p}`) == 1 ? classFieldTypes.getString(`${className}.${p}`) : "int"
            const llType = ssTypeToLLVM(ft)
            const isConst = classConstFields.has(`${className}.${p}`) == 1 ? 1 : 0
            const srcR = nextReg()
            emitIR(`  ${srcR} = getelementptr %${className}, ptr %self, i32 0, i32 ${idx}`)
            const valR = nextReg()
            emitIR(`  ${valR} = load ${llType}, ptr ${srcR}, align 8`)
            const dstR = nextReg()
            emitIR(`  ${dstR} = getelementptr %${className}, ptr %new, i32 0, i32 ${idx}`)
            if (llType == "ptr") {
                if (isUserClass(ft) == 1 && isConst == 0) {
                    // Mutable class-type field: recursive deep clone (with null guard)
                    const nullR = nextReg()
                    emitIR(`  ${nullR} = icmp eq ptr ${valR}, null`)
                    const cloneL = `dc.clone.${idx}`
                    const doneL = `dc.done.${idx}`
                    emitIR(`  br i1 ${nullR}, label %${doneL}, label %${cloneL}`)
                    emitIR(`${cloneL}:`)
                    const clonedR = nextReg()
                    emitIR(`  ${clonedR} = call ptr @ss_deep_clone_${ft}(ptr ${valR})`)
                    emitIR(`  store ptr ${clonedR}, ptr ${dstR}, align 8`)
                    emitIR(`  br label %${doneL}`)
                    emitIR(`${doneL}:`)
                } else {
                    // String, const class field, Map, List: share (retain)
                    emitRetainForType(valR, ft)
                    emitIR(`  store ptr ${valR}, ptr ${dstR}, align 8`)
                }
            } else {
                // Value types (int, double, bool): direct copy
                emitIR(`  store ${llType} ${valR}, ptr ${dstR}, align 8`)
            }
            idx = idx + 1
        }
    }
    emitIR("  ret ptr %new")
    emitIR("}")
    emitIR("")
}

// ss_shallow_clone_ClassName — memcpy + retain all ref-type fields
function emitClassShallowCloneFn(className: string, fieldStr: string, hasVtable: int) {
    regCount = 0
    regTable = []
    emitIR(`define ptr @ss_shallow_clone_${className}(ptr %self) {`)
    emitIR("entry:")
    // Allocate and memcpy
    emitIR(`  %size = ptrtoint ptr getelementptr (%${className}, ptr null, i32 1) to i64`)
    emitIR("  %new = call ptr @mi_calloc(i64 1, i64 %size)")
    emitIR("  %_mc = call ptr @memcpy(ptr %new, ptr %self, i64 %size)")
    // Reset rc = 1 (overwrite the copied rc)
    emitIR("  store i32 1, ptr %new, align 4")
    // Retain all ref-type fields (now shared between old and new)
    if (fieldStr != "") {
        let idx = fieldStartIdx(hasVtable)
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.has(`${className}.${p}`) == 1 ? classFieldTypes.getString(`${className}.${p}`) : "int"
            if (ssTypeToLLVM(ft) == "ptr") {
                const fR = nextReg()
                emitIR(`  ${fR} = getelementptr %${className}, ptr %new, i32 0, i32 ${idx}`)
                const vR = nextReg()
                emitIR(`  ${vR} = load ptr, ptr ${fR}, align 8`)
                emitRetainForType(vR, ft)
            }
            idx = idx + 1
        }
    }
    emitIR("  ret ptr %new")
    emitIR("}")
    emitIR("")
}

// ── Auto toJson ──────────────────────────────────────────────

function genAutoToJson(className: string, fieldStr: string) {
    // Skip if comptime/@derive already generated a toJson method
    const existingMethods = classMethods.has(className) == 1 ? classMethods.getString(className) : ""
    if (`,${existingMethods},`.indexOf(",toJson,") >= 0) { return }
    funcRetTypes.set(`${className}_toJson`, "string")

    regCount = 0
    regTable = []
    emitIR(`define ptr @${className}_toJson(ptr %this.ptr) {`)
    emitIR("entry:")
    emitIR("  %this = alloca ptr, align 8")
    emitIR("  store ptr %this.ptr, ptr %this, align 8")

    // Fieldless class: return "{}"
    if (fieldStr == "") {
        const emptyObj = addStringConst("{}")
        emitIR(`  ret ptr ${emptyObj}`)
        emitIR("}")
        emitIR("")
        return
    }

    // Build JSON string: {"field1":value1,"field2":value2}
    let resultReg = addStringConst("{")
    const fields = fieldStr.split(",")
    // New layout: rc at 0, TypeInfo at 1, optional vtable at 2, fields at 2 or 3
    let fieldIdx = classNeedsVtable.has(className) == 1 ? 3 : 2
    let fieldOrd = 0
    for (f in fields) {
        const fType = classFieldTypes.getString(`${className}.${f}`)
        const llFType = ssTypeToLLVM(fType)

        // Add comma separator
        if (fieldOrd > 0) {
            const commaStr = addStringConst(",")
            const cR = nextReg()
            emitIR(`  ${cR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${commaStr})`)
            resultReg = cR
        }

        // Add "fieldName":
        const keyStr = addStringConst(`"${f}":`)
        const kR = nextReg()
        emitIR(`  ${kR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${keyStr})`)
        resultReg = kR

        // Load field value
        const thisR = nextReg()
        emitIR(`  ${thisR} = load ptr, ptr %this, align 8`)
        const gepR = nextReg()
        emitIR(`  ${gepR} = getelementptr %${className}, ptr ${thisR}, i32 0, i32 ${fieldIdx}`)
        const valR = nextReg()
        emitIR(`  ${valR} = load ${llFType}, ptr ${gepR}, align 8`)

        // Convert to string and add
        if (fType == "string") {
            // Wrap in quotes: "value"
            const quoteStr = addStringConst("\"")
            const q1 = nextReg()
            emitIR(`  ${q1} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${quoteStr})`)
            const q2 = nextReg()
            emitIR(`  ${q2} = call ptr @ss_string_concat(ptr ${q1}, ptr ${valR})`)
            const q3 = nextReg()
            emitIR(`  ${q3} = call ptr @ss_string_concat(ptr ${q2}, ptr ${quoteStr})`)
            resultReg = q3
        } else if (fType == "int") {
            const numStr = nextReg()
            emitIR(`  ${numStr} = call ptr @ss_int_to_string(i32 ${valR})`)
            const nR = nextReg()
            emitIR(`  ${nR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${numStr})`)
            resultReg = nR
        } else if (fType == "double") {
            const dblStr = nextReg()
            emitIR(`  ${dblStr} = call ptr @ss_double_to_string(double ${valR})`)
            const dR = nextReg()
            emitIR(`  ${dR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${dblStr})`)
            resultReg = dR
        } else if (classFields.has(fType) == 1 && fType.contains("<") == 0) {
            // Nested POJO — call its toJson
            const nestedJson = nextReg()
            emitIR(`  ${nestedJson} = call ptr @${fType}_toJson(ptr ${valR})`)
            const njR = nextReg()
            emitIR(`  ${njR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${nestedJson})`)
            resultReg = njR
        } else {
            // Unknown type (Map, generic, etc.) — output as string representation
            const objStr = addStringConst("\"[object]\"")
            const oR = nextReg()
            emitIR(`  ${oR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${objStr})`)
            resultReg = oR
        }
        fieldIdx = fieldIdx + 1
        fieldOrd = fieldOrd + 1
    }

    // Close with }
    const closeStr = addStringConst("}")
    const finalR = nextReg()
    emitIR(`  ${finalR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${closeStr})`)
    emitIR(`  ret ptr ${finalR}`)
    emitIR("}")
    emitIR("")
}
