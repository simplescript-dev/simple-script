// Regression I027: comptime intrinsic shellOutput 必须不经任何 /tmp 中转文件捕获
// 命令 stdout —— 否则并发编译进程在该固定路径上 race(撕裂内容 / 读到他命令 stdout)。
//
// bug: ctCallDispatch(bootstrap/gen/exprs/exprs_ct_call.ss)shellOutput 分支
//      const soTmp = "/tmp/ss_comptime_exec.tmp" 硬编码跨进程固定常量,
//      system(cmd > soTmp) 落盘后 readFile(soTmp) 读回 —— 两个并发编译进程
//      各自 comptime 调 shellOutput 时在 /tmp/ss_comptime_exec.tmp 上竞争。
// fix: shellOutput 分支 delegate 到 shell builtin(popen 直捕 stdout,零中转文件)——
//      return ctVal(interpNewString(shell(`${soCmd} 2>/dev/null`)))。无路径即无 race。
// 见 i027_shelloutput_comptime_tmp_path.options.md
//    / tools/bugfix_reports/2026-05-19-i027-shelloutput-comptime-tmp-path.bugfix
// 父约束:docs/4-issues/I027-shelloutput-comptime-tmp-path-not-concurrency-safe.md
//
// 检测法(确定性,无 race):清掉旧的固定中转路径 → 编译一个含
// comptime { shellOutput(...) } 块的 fixture → 断言固定路径 /tmp/ss_comptime_exec.tmp
// 未被创建。修复前 buggy 编译器 system(cmd > 该路径)创建并遗留它;修复后
// shell() popen 直捕、零中转文件,该路径永不出现。
//
// 失败退出码:2=固定中转路径 /tmp/ss_comptime_exec.tmp 被使用(并发不安全)
//            3=fixture 编译失败   4=comptime shellOutput 未捕获命令 stdout

function main() {
    const sharedTmp = "/tmp/ss_comptime_exec.tmp"
    const fixture = "/tmp/ss_i027_fixture.ss"
    const fixtureBin = "/tmp/ss_i027_fixture_bin"

    // 清掉上一次运行 / 他进程遗留的固定中转路径与旧产物,保证检测起点干净。
    system(`rm -f ${sharedTmp} ${fixtureBin}`)

    // fixture:comptime 块调 shellOutput —— 编译它即在编译期触发 comptime stdout 捕获路径。
    writeFile(fixture, "const CT = comptime {\n    return shellOutput(\"echo I027_CT_OK\")\n}\nfunction main() {\n    println(CT)\n}\n")

    // 用当前 bin/ss 编译 fixture(comptime shellOutput 在编译期求值)。
    shell(`bin/ss build ${fixture} -o ${fixtureBin} 2>/dev/null`)
    if (fileExists(fixtureBin) != 1) { exit(3) }

    // 证明 comptime shellOutput 确实执行并捕获了 echo 的 stdout(防平凡通过)。
    const runOut = shell(fixtureBin)
    if (runOut.contains("I027_CT_OK") == 0) { exit(4) }

    // 核心不变量:comptime shellOutput 不得经固定共享中转文件 ——
    // buggy 编译器 system(cmd > /tmp/ss_comptime_exec.tmp) 创建并遗留该路径;
    // 修复后 shell() popen 直捕、零中转文件 → 该固定路径永不出现。
    if (fileExists(sharedTmp) == 1) { exit(2) }

    println("i027_shelloutput_comptime_tmp_path: comptime shellOutput captures stdout with zero /tmp staging file")
}
