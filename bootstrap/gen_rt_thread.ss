// gen_rt_thread.ss — Runtime: Thread pool scheduler (D082 Phase 2)
// Generates LLVM IR for Thread.start(), .join(), M:N thread pool.
// N worker pthreads dequeue and execute virtual thread tasks.

function emitRuntimeThread() {
    // ── Struct types ────────────────────────────────────────────
    // VThread: { i32 status, i64 fn, i64 result, ptr mutex, ptr cond }
    emitIR("%__VThread = type { i32, i64, i64, ptr, ptr }")
    // TaskNode: { ptr vthread, ptr next }
    emitIR("%__TaskNode = type { ptr, ptr }")
    emitIR("")

    // ── Globals ─────────────────────────────────────────────────
    // Scheduler queue lock (pthread_mutex_t = 40 bytes on musl x86-64)
    emitIR("@__sched_mutex = global [40 x i8] zeroinitializer")
    // Scheduler "task available" condvar (pthread_cond_t = 48 bytes)
    emitIR("@__sched_cond = global [48 x i8] zeroinitializer")
    // Task queue (singly-linked list)
    emitIR("@__sched_head = global ptr null")
    emitIR("@__sched_tail = global ptr null")
    // Lazy init flag
    emitIR("@__sched_init = global i1 false")
    emitIR("")

    // ── ss_schedInit() ──────────────────────────────────────────
    // Lazily initialize scheduler: create mutex/condvar, spawn worker threads.
    emitIR("define void @ss_schedInit() {")
    emitIR("entry:")
    emitIR("  %flag = load i1, ptr @__sched_init")
    emitIR("  br i1 %flag, label %done, label %init")
    emitIR("init:")
    emitIR("  store i1 true, ptr @__sched_init")
    emitIR("  call i32 @pthread_mutex_init(ptr @__sched_mutex, ptr null)")
    emitIR("  call i32 @pthread_cond_init(ptr @__sched_cond, ptr null)")
    // Get CPU count via sysconf(_SC_NPROCESSORS_ONLN = 84)
    emitIR("  %cpus = call i64 @sysconf(i32 84)")
    emitIR("  %cpus32 = trunc i64 %cpus to i32")
    // Cap: min 2, max 8
    emitIR("  %lt2 = icmp slt i32 %cpus32, 2")
    emitIR("  %capped_low = select i1 %lt2, i32 2, i32 %cpus32")
    emitIR("  %gt8 = icmp sgt i32 %capped_low, 8")
    emitIR("  %nworkers = select i1 %gt8, i32 8, i32 %capped_low")
    // Spawn worker threads
    emitIR("  %tid = alloca ptr, align 8")
    emitIR("  br label %spawn.loop")
    emitIR("spawn.loop:")
    emitIR("  %i = phi i32 [0, %init], [%next, %spawn.body]")
    emitIR("  %cmp = icmp slt i32 %i, %nworkers")
    emitIR("  br i1 %cmp, label %spawn.body, label %done")
    emitIR("spawn.body:")
    emitIR("  call i32 @pthread_create(ptr %tid, ptr null, ptr @ss_workerLoop, ptr null)")
    emitIR("  %tval = load ptr, ptr %tid, align 8")
    emitIR("  call i32 @pthread_detach(ptr %tval)")
    emitIR("  %next = add i32 %i, 1")
    emitIR("  br label %spawn.loop")
    emitIR("done:")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")

    // ── ss_schedEnqueue(ptr vthread) ────────────────────────────
    // Add a VThread to the scheduler queue and signal workers.
    emitIR("define void @ss_schedEnqueue(ptr %vt) {")
    emitIR("  call i32 @pthread_mutex_lock(ptr @__sched_mutex)")
    // Allocate TaskNode
    emitIR("  %node = call ptr @calloc(i64 1, i64 16)")
    emitIR("  %nvt = getelementptr %__TaskNode, ptr %node, i32 0, i32 0")
    emitIR("  store ptr %vt, ptr %nvt, align 8")
    emitIR("  %nnext = getelementptr %__TaskNode, ptr %node, i32 0, i32 1")
    emitIR("  store ptr null, ptr %nnext, align 8")
    // Append to tail
    emitIR("  %tail = load ptr, ptr @__sched_tail")
    emitIR("  %hasTail = icmp ne ptr %tail, null")
    emitIR("  br i1 %hasTail, label %append, label %setHead")
    emitIR("setHead:")
    emitIR("  store ptr %node, ptr @__sched_head")
    emitIR("  store ptr %node, ptr @__sched_tail")
    emitIR("  br label %signal")
    emitIR("append:")
    emitIR("  %tailNext = getelementptr %__TaskNode, ptr %tail, i32 0, i32 1")
    emitIR("  store ptr %node, ptr %tailNext, align 8")
    emitIR("  store ptr %node, ptr @__sched_tail")
    emitIR("  br label %signal")
    emitIR("signal:")
    emitIR("  call i32 @pthread_cond_signal(ptr @__sched_cond)")
    emitIR("  call i32 @pthread_mutex_unlock(ptr @__sched_mutex)")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")

    // ── ss_schedDequeue() → ptr ─────────────────────────────────
    // Remove and return the head VThread (blocks if queue empty).
    emitIR("define ptr @ss_schedDequeue() {")
    emitIR("entry:")
    emitIR("  call i32 @pthread_mutex_lock(ptr @__sched_mutex)")
    emitIR("  br label %wait.check")
    emitIR("wait.check:")
    emitIR("  %head = load ptr, ptr @__sched_head")
    emitIR("  %empty = icmp eq ptr %head, null")
    emitIR("  br i1 %empty, label %wait.sleep, label %dequeue")
    emitIR("wait.sleep:")
    emitIR("  call i32 @pthread_cond_wait(ptr @__sched_cond, ptr @__sched_mutex)")
    emitIR("  br label %wait.check")
    emitIR("dequeue:")
    emitIR("  %h = load ptr, ptr @__sched_head")
    // Get vthread from node
    emitIR("  %hvt = getelementptr %__TaskNode, ptr %h, i32 0, i32 0")
    emitIR("  %vt = load ptr, ptr %hvt, align 8")
    // Advance head
    emitIR("  %hnext = getelementptr %__TaskNode, ptr %h, i32 0, i32 1")
    emitIR("  %nextNode = load ptr, ptr %hnext, align 8")
    emitIR("  store ptr %nextNode, ptr @__sched_head")
    // If head is now null, clear tail too
    emitIR("  %nowEmpty = icmp eq ptr %nextNode, null")
    emitIR("  br i1 %nowEmpty, label %clearTail, label %unlock")
    emitIR("clearTail:")
    emitIR("  store ptr null, ptr @__sched_tail")
    emitIR("  br label %unlock")
    emitIR("unlock:")
    emitIR("  call void @free(ptr %h)")
    emitIR("  call i32 @pthread_mutex_unlock(ptr @__sched_mutex)")
    emitIR("  ret ptr %vt")
    emitIR("}")
    emitIR("")

    // ── ss_workerLoop(ptr arg) → ptr ────────────────────────────
    // Worker thread main: dequeue → execute → store result → signal.
    emitIR("define ptr @ss_workerLoop(ptr %arg) {")
    emitIR("entry:")
    emitIR("  br label %loop")
    emitIR("loop:")
    emitIR("  %vt = call ptr @ss_schedDequeue()")
    // Set status = RUNNING (1)
    emitIR("  %statusP = getelementptr %__VThread, ptr %vt, i32 0, i32 0")
    emitIR("  store i32 1, ptr %statusP, align 4")
    // Load fn (i64, tagged)
    emitIR("  %fnP = getelementptr %__VThread, ptr %vt, i32 0, i32 1")
    emitIR("  %fn = load i64, ptr %fnP, align 8")
    // Tag-bit dispatch: bit 0 = 1 → closure, bit 0 = 0 → direct fn ptr
    emitIR("  %tag = and i64 %fn, 1")
    emitIR("  %isClo = icmp eq i64 %tag, 1")
    emitIR("  br i1 %isClo, label %closure, label %direct")
    // Closure path: untag, load fn_ptr from offset 2, call with self
    emitIR("closure:")
    emitIR("  %untag = and i64 %fn, -2")
    emitIR("  %cloPtr = inttoptr i64 %untag to ptr")
    emitIR("  %fnField = getelementptr ptr, ptr %cloPtr, i32 2")
    emitIR("  %fnPClo = load ptr, ptr %fnField, align 8")
    emitIR("  %resClo = call i64 %fnPClo(ptr %cloPtr)")
    emitIR("  br label %store")
    // Direct function pointer path
    emitIR("direct:")
    emitIR("  %fp = inttoptr i64 %fn to ptr")
    emitIR("  %resDir = call i64 %fp()")
    emitIR("  br label %store")
    // Store result
    emitIR("store:")
    emitIR("  %result = phi i64 [%resClo, %closure], [%resDir, %direct]")
    emitIR("  %resP = getelementptr %__VThread, ptr %vt, i32 0, i32 2")
    emitIR("  store i64 %result, ptr %resP, align 8")
    // Set status = COMPLETED (2)
    emitIR("  store i32 2, ptr %statusP, align 4")
    // Signal completion to joiner
    emitIR("  %mutP = getelementptr %__VThread, ptr %vt, i32 0, i32 3")
    emitIR("  %mut = load ptr, ptr %mutP, align 8")
    emitIR("  call i32 @pthread_mutex_lock(ptr %mut)")
    emitIR("  %condP = getelementptr %__VThread, ptr %vt, i32 0, i32 4")
    emitIR("  %cond = load ptr, ptr %condP, align 8")
    emitIR("  call i32 @pthread_cond_signal(ptr %cond)")
    emitIR("  call i32 @pthread_mutex_unlock(ptr %mut)")
    emitIR("  br label %loop")
    emitIR("}")
    emitIR("")

    // ── ss_threadStart(i64 fn) → ptr ────────────────────────────
    // Create a VThread, initialize per-thread sync, enqueue, return handle.
    emitIR("define ptr @ss_threadStart(i64 %fn) {")
    // Lazy-init scheduler
    emitIR("  call void @ss_schedInit()")
    // Allocate VThread (5 fields: i32 + pad + i64 + i64 + ptr + ptr = 40 bytes)
    emitIR("  %vt = call ptr @calloc(i64 1, i64 40)")
    // Set fn
    emitIR("  %fnP = getelementptr %__VThread, ptr %vt, i32 0, i32 1")
    emitIR("  store i64 %fn, ptr %fnP, align 8")
    // Allocate and init per-thread mutex (40 bytes)
    emitIR("  %mut = call ptr @calloc(i64 1, i64 40)")
    emitIR("  call i32 @pthread_mutex_init(ptr %mut, ptr null)")
    emitIR("  %mutP = getelementptr %__VThread, ptr %vt, i32 0, i32 3")
    emitIR("  store ptr %mut, ptr %mutP, align 8")
    // Allocate and init per-thread condvar (48 bytes)
    emitIR("  %cond = call ptr @calloc(i64 1, i64 48)")
    emitIR("  call i32 @pthread_cond_init(ptr %cond, ptr null)")
    emitIR("  %condP = getelementptr %__VThread, ptr %vt, i32 0, i32 4")
    emitIR("  store ptr %cond, ptr %condP, align 8")
    // Status = READY (0) — already zeroed by calloc
    // Enqueue
    emitIR("  call void @ss_schedEnqueue(ptr %vt)")
    emitIR("  ret ptr %vt")
    emitIR("}")
    emitIR("")

    // ── ss_threadJoin(ptr vt) → i64 ────────────────────────────
    // Wait until VThread completes, return its result.
    emitIR("define i64 @ss_threadJoin(ptr %vt) {")
    emitIR("entry:")
    emitIR("  %mutP = getelementptr %__VThread, ptr %vt, i32 0, i32 3")
    emitIR("  %mut = load ptr, ptr %mutP, align 8")
    emitIR("  %condP = getelementptr %__VThread, ptr %vt, i32 0, i32 4")
    emitIR("  %cond = load ptr, ptr %condP, align 8")
    emitIR("  call i32 @pthread_mutex_lock(ptr %mut)")
    emitIR("  br label %check")
    emitIR("check:")
    emitIR("  %statusP = getelementptr %__VThread, ptr %vt, i32 0, i32 0")
    emitIR("  %status = load i32, ptr %statusP, align 4")
    emitIR("  %done = icmp eq i32 %status, 2")
    emitIR("  br i1 %done, label %complete, label %wait")
    emitIR("wait:")
    emitIR("  call i32 @pthread_cond_wait(ptr %cond, ptr %mut)")
    emitIR("  br label %check")
    emitIR("complete:")
    emitIR("  call i32 @pthread_mutex_unlock(ptr %mut)")
    // Load result
    emitIR("  %resP = getelementptr %__VThread, ptr %vt, i32 0, i32 2")
    emitIR("  %result = load i64, ptr %resP, align 8")
    emitIR("  ret i64 %result")
    emitIR("}")
    emitIR("")
}
