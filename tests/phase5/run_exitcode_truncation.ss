// Regression: bin/ss run 必须透传被运行程序的真实退出码,不得 mod-256 截断
//
// bug: cmdRun(bootstrap/main.ss) 把 system() 返回的 C raw wait-status
//      (正常退出 = 退出码 << 8)直接交给 exit();exit() 进程退出码 = 参数 & 0xFF,
//      使被运行程序退出码 1-255 经 bin/ss run 后 $? 全归 0。
// fix: cmdRun 解码 wait-status —— 正常退出 exit(rc / 256),信号终止 exit(128 + sig)。
// 见 run_exitcode_truncation.options.md
//    / tools/bugfix_reports/2026-05-19-run-exitcode-truncation.bugfix
// 父约束:docs/1-axioms.md §V3(对标 go run / cargo run / zig run 透传退出码)
//
// 失败退出码:1=exit(7) 截断   2=exit(255) 截断   3=exit(0) 误判
//            4=exit(1) 截断   5=信号终止(SIGFPE)未透传为 128+signal

function ssRunExitCode(body: string): int {
    // ws 是 shell 的 wait-status,bin/ss run 透传出的退出码在高 8 位 → / 256 还原
    writeFile("/tmp/ss_run_ec_fixture.ss", "function main() {\n" + body + "\n}\n")
    const ws = system("bin/ss run /tmp/ss_run_ec_fixture.ss >/dev/null 2>&1")
    return ws / 256
}

function main() {
    // 正常退出:bin/ss run 须把 0-255 全量透传,不得 mod-256 截断
    if (ssRunExitCode("    exit(7)") != 7) { exit(1) }
    if (ssRunExitCode("    exit(255)") != 255) { exit(2) }
    if (ssRunExitCode("    exit(0)") != 0) { exit(3) }
    if (ssRunExitCode("    exit(1)") != 1) { exit(4) }

    // 信号终止:子程序整数除零 → SIGFPE → bin/ss run 须透传为 exit(128 + 8)
    const sigCode = ssRunExitCode("    let d = args() - args()\n    println(1 / d)")
    if (sigCode != 136) { exit(5) }

    println("run_exitcode_truncation: bin/ss run propagates real exit code (exit 0-255 + signal)")
}
