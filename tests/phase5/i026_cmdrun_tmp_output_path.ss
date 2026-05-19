// Regression I026: bin/ss run 必须为每次调用用进程唯一编译输出路径,
// 不得硬编码共享 /tmp/ss_run_output —— 否则并发 bin/ss run 在该路径上 race。
//
// bug: cmdRun(bootstrap/main.ss) const outBin = "/tmp/ss_run_output" 固定常量,
//      两个并发 bin/ss run 在 /tmp/ss_run_output{,.ll,.ll.str,.o} 上竞争
//      (musl-gcc 并发写、一方 rm 另一方在读、exec 半截二进制)→ 非确定编译失败 / flaky。
// fix: cmdRun outBin = shell("mktemp /tmp/ss_run_output.XXXXXX").trim() —— 每进程唯一。
// 见 i026_cmdrun_tmp_output_path.options.md
//    / tools/bugfix_reports/2026-05-19-i026-cmdrun-tmp-output-path.bugfix
// 父约束:docs/4-issues/I026-cmdrun-tmp-output-path-not-concurrency-safe.md
//
// 检测法(确定性,无 race):bin/ss run 编译时 println("compiled: <outBin>");
// 连跑两次解析该路径 —— 修复前两次恒为 "/tmp/ss_run_output"(等于旧硬编码),
// 修复后为各异的 /tmp/ss_run_output.XXXXXX。两次必各异即坐实「每次调用路径进程唯一」。
//
// 失败退出码:1=bin/ss run 输出无 compiled 行   2=两次输出路径相同(非进程唯一)
//            3=路径仍为旧硬编码 /tmp/ss_run_output   4=被运行程序输出缺失

function compiledPath(runOut: string): string {
    const prefix = "compiled: "
    const lines = runOut.split("\n")
    for (line in lines) {
        if (line.startsWith(prefix) == 1) {
            return line.substring(prefix.length(), line.length()).trim()
        }
    }
    return ""
}

function main() {
    const fixture = "/tmp/ss_i026_fixture.ss"
    writeFile(fixture, "function main() {\n    println(\"I026_FIXTURE_OK\")\n}\n")

    // 第 1 次 bin/ss run:解析编译输出路径
    const out1 = shell(`bin/ss run ${fixture} 2>/dev/null`)
    const p1 = compiledPath(out1)
    if (p1 == "") { exit(1) }
    if (out1.contains("I026_FIXTURE_OK") == 0) { exit(4) }
    if (p1 == "/tmp/ss_run_output") { exit(3) }

    // 第 2 次 bin/ss run
    const out2 = shell(`bin/ss run ${fixture} 2>/dev/null`)
    const p2 = compiledPath(out2)
    if (p2 == "") { exit(1) }
    if (out2.contains("I026_FIXTURE_OK") == 0) { exit(4) }
    if (p2 == "/tmp/ss_run_output") { exit(3) }

    // 核心不变量:每次调用编译输出路径进程唯一 → 连跑两次必各异
    if (p1 == p2) { exit(2) }

    println(`i026_cmdrun_tmp_output_path: bin/ss run uses per-invocation unique output path`)
    println(`  run1 -> ${p1}`)
    println(`  run2 -> ${p2}`)
}
