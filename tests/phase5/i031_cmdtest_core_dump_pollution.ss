// Regression I031: bin/ss test 的 cmdTest 生成并行测试脚本必须含 ulimit -c 0,
// 收束整棵测试子进程树的 RLIMIT_CORE —— 否则崩溃测试(或其嵌套 bin/ss run 派生的
// ss_run_output.* 孙进程)的 ≈1GB core 转储会落到 repo 根(继承自 bin/ss test 的 CWD)。
//
// bug: cmdTest(bootstrap/main.ss)拼 par.sh 脚本字符串只设 MAX_JOBS 并发度,
//      不设资源限界;RLIMIT_CORE 默认 unlimited 被子进程树继承 → 崩溃写 core.<PID>
//      到 repo 根 → 污染 git status / 磁盘累积(core 不在 .gitignore)。
// fix: cmdTest 拼脚本时 #!/bin/bash 之后加一行 ulimit -c 0 —— bash 内建映射
//      setrlimit(RLIMIT_CORE,0),跨 fork+exec 继承,崩溃时内核零 core 写盘。
// 见 i031_cmdtest_core_dump_pollution.options.md
//    / tools/bugfix_reports/2026-05-19-i031-cmdtest-core-dump-pollution.bugfix
// 父约束:docs/4-issues/I031-cmdtest-core-dump-repo-root-pollution.md
//
// 检测法(确定性、无 race):cmdTest 的行为驱动测试会在 bin/ss test 内嵌套
// bin/ss test、与外层并行 runner race(I028/I029 §isolate 同款约束),故核对编译器
// 源码 —— 提取 bootstrap/main.ss 的 cmdTest 函数体,断言其含 ulimit -c 0。
//
// 失败退出码:1=无法读 main.ss / 定位 cmdTest   2=cmdTest 未含 ulimit -c 0

import { functionBody } from "./import/source_probe"

function main() {
    const src = readFile("bootstrap/main.ss")
    if (src == "") { exit(1) }
    const body = functionBody(src, "cmdTest")
    if (body == "") { exit(1) }

    // 核心不变量:cmdTest 生成的并行脚本必含 ulimit -c 0(收束子进程树 RLIMIT_CORE)
    if (body.contains("ulimit -c 0") == 0) { exit(2) }

    println("i031_cmdtest_core_dump_pollution: cmdTest emits 'ulimit -c 0' in parallel test script")
    println("  test subprocess tree RLIMIT_CORE=0 -> crash writes no core into repo root")
}
