// ss_shell(cmd) — popen + dynamic-grow fread buffer + pclose,返回 stdout 作 RC string。
// 语义上与 ss_popen_read 分化:不写全局 @ss_last_exit_code。stdout-only 场景用这个。

function emitRuntimeShell() {
    emitIR("define ptr @ss_shell(ptr %cmd) {")
    irLabel("entry")
    // D168 §B.7: %cmd 是 SS String header,GEP buffer
    emitIR("  %cmd_buf_ptr = getelementptr %String, ptr %cmd, i32 0, i32 2")
    emitIR("  %cmd_buf = load ptr, ptr %cmd_buf_ptr, align 8")
    irCall("fp", "ptr", "popen", "ptr %cmd_buf, ptr @.rt.str.r")
    irICmp("isnull", "eq", "ptr", "%fp", "null")
    irBrCond("isnull", "fail", "init")

    irLabel("init")
    irCall("buf", "ptr", "malloc", "i64 4096")
    irStore("i8", "0", "%buf")
    emitIR("  br label %read")

    irLabel("read")
    // read-block phi: buf/off/cap 的三来源 — init 首次 / grow 扩容回 / append 写入回读下一块
    emitIR("  %pbuf = phi ptr [ %buf, %init ], [ %rbuf, %grow ], [ %pbuf2, %append ]")
    emitIR("  %poff = phi i64 [ 0, %init ], [ %goff, %grow ], [ %newoff, %append ]")
    emitIR("  %pcap = phi i64 [ 4096, %init ], [ %newcap, %grow ], [ %pcap2, %append ]")
    irSub("rem0", "i64", "%pcap", "%poff")
    irSub("rem", "i64", "%rem0", "1")
    irGEP("dst", "i8", "%pbuf", "%poff")
    irCall("n", "i64", "fread", "ptr %dst, i64 1, i64 %rem, ptr %fp")
    irICmp("eof", "eq", "i64", "%n", "0")
    irBrCond("eof", "done", "append")

    irLabel("append")
    emitIR("  %pbuf2 = phi ptr [ %pbuf, %read ]")
    emitIR("  %pcap2 = phi i64 [ %pcap, %read ]")
    irAdd("newoff", "i64", "%poff", "%n")
    irGEP("term", "i8", "%pbuf2", "%newoff")
    irStore("i8", "0", "%term")
    irICmp("full", "eq", "i64", "%n", "%rem")
    irBrCond("full", "grow", "read")

    irLabel("grow")
    emitIR("  %goff = phi i64 [ %newoff, %append ]")
    emitIR("  %gbuf = phi ptr [ %pbuf2, %append ]")
    emitIR("  %gcap = phi i64 [ %pcap2, %append ]")
    irMul("newcap", "i64", "%gcap", "2")
    irCall("rbuf", "ptr", "realloc", "ptr %gbuf, i64 %newcap")
    emitIR("  br label %read")

    irLabel("done")
    irCall("_1", "i32", "pclose", "ptr %fp")
    // D168 §B.7: 返回模式 B,包装 byte buf → SS String header,释放原 byte buf
    irCall("result", "ptr", "ss_string_from_cstr", "ptr %pbuf")
    irCallVoid("free", "ptr %pbuf")
    irRet("ptr", "%result")

    irLabel("fail")
    irCall("empty", "ptr", "ss_string_from_cstr", "ptr @.rt.str.empty")
    irRet("ptr", "%empty")
    emitIR("}")
    emitIR("")
}
