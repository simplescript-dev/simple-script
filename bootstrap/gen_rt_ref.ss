// gen_rt_ref.ss — Runtime: Ref<T> reactive reference (D082)
// Generates LLVM IR for ref(), watch(), .value read/write, watcher notification.

function emitRuntimeRef() {
    // ── Ref struct type ──────────────────────────────────────────
    // %__Ref = { i32 rc, i32 flags, i64 value, ptr watchers }
    emitIR("%__Ref = type { i32, i32, i64, ptr }")
    emitIR("")

    // ── ss_refNew(i64 value) → ptr ──────────────────────────────
    emitIR("define ptr @ss_refNew(i64 %value) {")
    emitIR("  %ref = call ptr @calloc(i64 1, i64 32)")
    // rc = 1
    emitIR("  store i32 1, ptr %ref, align 4")
    // value
    emitIR("  %vp = getelementptr %__Ref, ptr %ref, i32 0, i32 2")
    emitIR("  store i64 %value, ptr %vp, align 8")
    // watchers = empty array
    emitIR("  %wa = call ptr @ss_newArray(i32 0)")
    emitIR("  %wp = getelementptr %__Ref, ptr %ref, i32 0, i32 3")
    emitIR("  store ptr %wa, ptr %wp, align 8")
    emitIR("  ret ptr %ref")
    emitIR("}")
    emitIR("")

    // ── ss_refGet(ptr ref) → i64 ────────────────────────────────
    emitIR("define i64 @ss_refGet(ptr %ref) {")
    emitIR("  %vp = getelementptr %__Ref, ptr %ref, i32 0, i32 2")
    emitIR("  %val = load i64, ptr %vp, align 8")
    emitIR("  ret i64 %val")
    emitIR("}")
    emitIR("")

    // ── ss_refSet(ptr ref, i64 newValue) → void ─────────────────
    // Stores new value, then notifies all watchers with (newVal, oldVal).
    emitIR("define void @ss_refSet(ptr %ref, i64 %newValue) {")
    emitIR("  %vp = getelementptr %__Ref, ptr %ref, i32 0, i32 2")
    emitIR("  %oldValue = load i64, ptr %vp, align 8")
    emitIR("  store i64 %newValue, ptr %vp, align 8")
    emitIR("  call void @ss_refNotify(ptr %ref, i64 %newValue, i64 %oldValue)")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")

    // ── ss_refWatch(ptr ref, i64 callback) → void ───────────────
    emitIR("define void @ss_refWatch(ptr %ref, i64 %callback) {")
    emitIR("  %wp = getelementptr %__Ref, ptr %ref, i32 0, i32 3")
    emitIR("  %wa = load ptr, ptr %wp, align 8")
    emitIR("  %na = call ptr @ss_arrayPush(ptr %wa, i64 %callback)")
    emitIR("  store ptr %na, ptr %wp, align 8")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")

    // ── ss_refNotify(ptr ref, i64 newVal, i64 oldVal) → void ────
    // Loops through watcher array, calls each (supports closures via tag bit).
    emitIR("define void @ss_refNotify(ptr %ref, i64 %newVal, i64 %oldVal) {")
    emitIR("entry:")
    emitIR("  %wp = getelementptr %__Ref, ptr %ref, i32 0, i32 3")
    emitIR("  %wa = load ptr, ptr %wp, align 8")
    emitIR("  %len = call i32 @ss_arrayLen(ptr %wa)")
    emitIR("  %hasW = icmp sgt i32 %len, 0")
    emitIR("  br i1 %hasW, label %loop, label %done")
    emitIR("loop:")
    emitIR("  %i = phi i32 [0, %entry], [%next, %call.done]")
    emitIR("  %elem = call i64 @ss_arrayGet(ptr %wa, i32 %i)")
    // Check closure tag bit
    emitIR("  %tag = and i64 %elem, 1")
    emitIR("  %isClo = icmp eq i64 %tag, 1")
    emitIR("  br i1 %isClo, label %closure, label %direct")
    // Closure path: untag, get fn_ptr from offset 2, call with self
    emitIR("closure:")
    emitIR("  %untag = and i64 %elem, -2")
    emitIR("  %cloPtr = inttoptr i64 %untag to ptr")
    emitIR("  %fnF = getelementptr ptr, ptr %cloPtr, i32 2")
    emitIR("  %fnP = load ptr, ptr %fnF, align 8")
    emitIR("  call void %fnP(ptr %cloPtr, i64 %newVal, i64 %oldVal)")
    emitIR("  br label %call.done")
    // Direct function pointer path
    emitIR("direct:")
    emitIR("  %fp = inttoptr i64 %elem to ptr")
    emitIR("  call void %fp(i64 %newVal, i64 %oldVal)")
    emitIR("  br label %call.done")
    // Next iteration
    emitIR("call.done:")
    emitIR("  %next = add i32 %i, 1")
    emitIR("  %cmp = icmp slt i32 %next, %len")
    emitIR("  br i1 %cmp, label %loop, label %done")
    emitIR("done:")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")
}
