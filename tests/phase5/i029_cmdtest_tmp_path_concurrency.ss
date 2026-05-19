// Regression I029: bin/ss test 的 cmdTest 必须为每次调用用进程唯一临时目录承载
// 测试构建产物,不得用固定共享 /tmp 路径 —— 否则并发 bin/ss test 在
// /tmp/ss_test_<idx> / /tmp/ss_res_<idx> / /tmp/ss_test_par.sh 上 race。
//
// bug: cmdTest(bootstrap/main.ss)三类固定共享路径,${idx} 每次调用从 0 重数,
//      两个并发 bin/ss test 在这些路径竞争(build 覆写、cleanup 跨进程销毁、
//      exec 撕裂半截二进制)→ 段错误 / 非确定 FAIL / flaky。
// fix: cmdTest 起手 testRunDir = shell("mktemp -d /tmp/ss_test_run.XXXXXX").trim()
//      —— 每进程唯一目录承载全部产物;cleanup rm -rf 自有目录。
// 见 i029_cmdtest_tmp_path_concurrency.options.md
//    / tools/bugfix_reports/2026-05-19-i029-cmdtest-tmp-path-concurrency.bugfix
// 父约束:docs/4-issues/I029-cmdtest-tmp-path-not-concurrency-safe.md
//
// 检测法(确定性、无 race):cmdTest 的行为驱动测试会在 bin/ss test 内嵌套
// bin/ss test、与外层并行 runner race(I028 §isolate 同款约束),故核对编译器
// 源码 —— 提取 bootstrap/main.ss 的 cmdTest 函数体,断言其不含固定共享路径字面值
// /tmp/ss_test_$ /tmp/ss_res_$ /tmp/ss_test_par、且含进程唯一目录原语 mktemp -d。
//
// 失败退出码:1=无法读 main.ss / 定位 cmdTest   2=cmdTest 仍含 /tmp/ss_test_$(固定二进制路径)
//            3=cmdTest 仍含 /tmp/ss_res_$(固定结果路径)   4=cmdTest 仍含 /tmp/ss_test_par(固定脚本路径)
//            5=cmdTest 未用 mktemp -d 进程唯一目录

function cmdTestBody(src: string): string {
    const marker = "function cmdTest()"
    const startIdx = src.indexOf(marker)
    if (startIdx < 0) { return "" }
    const rest = src.substring(startIdx, src.length())
    const nextFn = rest.indexOf("\nfunction ")
    if (nextFn < 0) { return rest }
    return rest.substring(0, nextFn)
}

function main() {
    const src = readFile("bootstrap/main.ss")
    if (src == "") { exit(1) }
    const body = cmdTestBody(src)
    if (body == "") { exit(1) }

    // 核心不变量:cmdTest 不得含固定共享 /tmp 路径
    if (body.contains("/tmp/ss_test_$") == 1) { exit(2) }
    if (body.contains("/tmp/ss_res_$") == 1) { exit(3) }
    if (body.contains("/tmp/ss_test_par") == 1) { exit(4) }
    // 修复标记:用 mktemp -d 进程唯一目录
    if (body.contains("mktemp -d") == 0) { exit(5) }

    println("i029_cmdtest_tmp_path_concurrency: cmdTest uses per-invocation unique temp dir (mktemp -d)")
    println("  no fixed shared /tmp/ss_test_* /tmp/ss_res_* /tmp/ss_test_par paths in cmdTest")
}
