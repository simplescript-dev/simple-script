// gen_rt_channel.ss — Runtime: Channel<T> blocking queue (D082 Phase 4)
// Generates LLVM IR for Channel.send(), .receive(), .close().
// Unbounded FIFO queue with mutex + condvar for blocking receive.

function emitRuntimeChannel() {
    // ── Struct types ────────────────────────────────────────────
    // Channel: { i32 closed, i32 count, ptr head, ptr tail, [40 x i8] mutex, [48 x i8] cond }
    // Offsets: closed=0, count=4, head=8, tail=16, mutex=24, cond=64
    // Total = 112 bytes
    emitIR("%__Channel = type { i32, i32, ptr, ptr, [40 x i8], [48 x i8] }")
    // ChanNode: { i64 value, ptr next }
    emitIR("%__ChanNode = type { i64, ptr }")
    emitIR("")

    // ── ss_channelNew() → ptr ──────────────────────────────────
    emitIR("define ptr @ss_channelNew() {")
    emitIR("  %ch = call ptr @calloc(i64 1, i64 112)")
    // closed = 0, count = 0, head = null, tail = null — zeroed by calloc
    // Init mutex at offset 4 (field index 4)
    emitIR("  %mutP = getelementptr %__Channel, ptr %ch, i32 0, i32 4")
    emitIR("  call i32 @pthread_mutex_init(ptr %mutP, ptr null)")
    // Init condvar at offset 5 (field index 5)
    emitIR("  %condP = getelementptr %__Channel, ptr %ch, i32 0, i32 5")
    emitIR("  call i32 @pthread_cond_init(ptr %condP, ptr null)")
    emitIR("  ret ptr %ch")
    emitIR("}")
    emitIR("")

    // ── ss_channelSend(ptr ch, i64 val) → void ─────────────────
    // Enqueue value, signal waiting receivers.
    emitIR("define void @ss_channelSend(ptr %ch, i64 %val) {")
    emitIR("entry:")
    // Check closed
    emitIR("  %closedP = getelementptr %__Channel, ptr %ch, i32 0, i32 0")
    emitIR("  %mutP = getelementptr %__Channel, ptr %ch, i32 0, i32 4")
    emitIR("  call i32 @pthread_mutex_lock(ptr %mutP)")
    emitIR("  %closed = load i32, ptr %closedP, align 4")
    emitIR("  %isClosed = icmp ne i32 %closed, 0")
    emitIR("  br i1 %isClosed, label %err, label %enqueue")
    // Error: send on closed channel
    emitIR("err:")
    emitIR("  call i32 @pthread_mutex_unlock(ptr %mutP)")
    emitIR("  call void @ss_throw(ptr @.rt.str.chan_send_closed)")
    emitIR("  unreachable")
    // Enqueue
    emitIR("enqueue:")
    // Allocate ChanNode (16 bytes)
    emitIR("  %node = call ptr @calloc(i64 1, i64 16)")
    emitIR("  %nvP = getelementptr %__ChanNode, ptr %node, i32 0, i32 0")
    emitIR("  store i64 %val, ptr %nvP, align 8")
    emitIR("  %nnP = getelementptr %__ChanNode, ptr %node, i32 0, i32 1")
    emitIR("  store ptr null, ptr %nnP, align 8")
    // Append to tail
    emitIR("  %tailP = getelementptr %__Channel, ptr %ch, i32 0, i32 3")
    emitIR("  %tail = load ptr, ptr %tailP, align 8")
    emitIR("  %hasTail = icmp ne ptr %tail, null")
    emitIR("  br i1 %hasTail, label %append, label %setHead")
    emitIR("setHead:")
    emitIR("  %headP0 = getelementptr %__Channel, ptr %ch, i32 0, i32 2")
    emitIR("  store ptr %node, ptr %headP0, align 8")
    emitIR("  store ptr %node, ptr %tailP, align 8")
    emitIR("  br label %signal")
    emitIR("append:")
    emitIR("  %tailNext = getelementptr %__ChanNode, ptr %tail, i32 0, i32 1")
    emitIR("  store ptr %node, ptr %tailNext, align 8")
    emitIR("  store ptr %node, ptr %tailP, align 8")
    emitIR("  br label %signal")
    emitIR("signal:")
    // Increment count
    emitIR("  %countP = getelementptr %__Channel, ptr %ch, i32 0, i32 1")
    emitIR("  %cnt = load i32, ptr %countP, align 4")
    emitIR("  %cnt1 = add i32 %cnt, 1")
    emitIR("  store i32 %cnt1, ptr %countP, align 4")
    // Signal one waiting receiver
    emitIR("  %condP = getelementptr %__Channel, ptr %ch, i32 0, i32 5")
    emitIR("  call i32 @pthread_cond_signal(ptr %condP)")
    emitIR("  call i32 @pthread_mutex_unlock(ptr %mutP)")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")

    // ── ss_channelReceive(ptr ch) → i64 ────────────────────────
    // Block until value available or channel closed.
    emitIR("define i64 @ss_channelReceive(ptr %ch) {")
    emitIR("entry:")
    emitIR("  %mutP = getelementptr %__Channel, ptr %ch, i32 0, i32 4")
    emitIR("  %condP = getelementptr %__Channel, ptr %ch, i32 0, i32 5")
    emitIR("  call i32 @pthread_mutex_lock(ptr %mutP)")
    emitIR("  br label %check")
    emitIR("check:")
    emitIR("  %countP = getelementptr %__Channel, ptr %ch, i32 0, i32 1")
    emitIR("  %cnt = load i32, ptr %countP, align 4")
    emitIR("  %hasData = icmp sgt i32 %cnt, 0")
    emitIR("  br i1 %hasData, label %dequeue, label %checkClosed")
    emitIR("checkClosed:")
    emitIR("  %closedP = getelementptr %__Channel, ptr %ch, i32 0, i32 0")
    emitIR("  %closed = load i32, ptr %closedP, align 4")
    emitIR("  %isClosed = icmp ne i32 %closed, 0")
    emitIR("  br i1 %isClosed, label %empty, label %wait")
    emitIR("wait:")
    emitIR("  call i32 @pthread_cond_wait(ptr %condP, ptr %mutP)")
    emitIR("  br label %check")
    // Channel closed and empty → return 0
    emitIR("empty:")
    emitIR("  call i32 @pthread_mutex_unlock(ptr %mutP)")
    emitIR("  ret i64 0")
    // Dequeue head node
    emitIR("dequeue:")
    emitIR("  %headP = getelementptr %__Channel, ptr %ch, i32 0, i32 2")
    emitIR("  %head = load ptr, ptr %headP, align 8")
    // Load value from node
    emitIR("  %valP = getelementptr %__ChanNode, ptr %head, i32 0, i32 0")
    emitIR("  %val = load i64, ptr %valP, align 8")
    // Advance head
    emitIR("  %nextP = getelementptr %__ChanNode, ptr %head, i32 0, i32 1")
    emitIR("  %next = load ptr, ptr %nextP, align 8")
    emitIR("  store ptr %next, ptr %headP, align 8")
    // If head is now null, clear tail
    emitIR("  %nowEmpty = icmp eq ptr %next, null")
    emitIR("  br i1 %nowEmpty, label %clearTail, label %decCount")
    emitIR("clearTail:")
    emitIR("  %tailP = getelementptr %__Channel, ptr %ch, i32 0, i32 3")
    emitIR("  store ptr null, ptr %tailP, align 8")
    emitIR("  br label %decCount")
    emitIR("decCount:")
    // Decrement count
    emitIR("  %cnt2 = load i32, ptr %countP, align 4")
    emitIR("  %cnt3 = sub i32 %cnt2, 1")
    emitIR("  store i32 %cnt3, ptr %countP, align 4")
    // Free node
    emitIR("  call void @free(ptr %head)")
    emitIR("  call i32 @pthread_mutex_unlock(ptr %mutP)")
    emitIR("  ret i64 %val")
    emitIR("}")
    emitIR("")

    // ── ss_channelClose(ptr ch) → void ─────────────────────────
    // Set closed flag, wake all waiting receivers.
    emitIR("define void @ss_channelClose(ptr %ch) {")
    emitIR("  %mutP = getelementptr %__Channel, ptr %ch, i32 0, i32 4")
    emitIR("  call i32 @pthread_mutex_lock(ptr %mutP)")
    emitIR("  %closedP = getelementptr %__Channel, ptr %ch, i32 0, i32 0")
    emitIR("  store i32 1, ptr %closedP, align 4")
    // Broadcast to wake all waiting receivers
    emitIR("  %condP = getelementptr %__Channel, ptr %ch, i32 0, i32 5")
    emitIR("  call i32 @pthread_cond_broadcast(ptr %condP)")
    emitIR("  call i32 @pthread_mutex_unlock(ptr %mutP)")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")

    // ── Runtime string constants ────────────────────────────────
    emitIR(`@.rt.str.chan_send_closed = private constant [30 x i8] c"send on closed Channel failed\\00"`)
    emitIR("")
}
