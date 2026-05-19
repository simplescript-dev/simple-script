// Regression: build.sh 三阶段固定点校验不得依赖 xxd(缺失环境假阳性)
//
// bug: build.sh:27 `diff <(xxd a) <(xxd b)` —— xxd 缺失时 bash process
//      substitution 退化为空流,diff 比较两空流恒返 0 → "Fixed point
//      verified!" 假阳性,stage2 != stage3 非确定 miscompilation 漏检。
// fix: `cmp -s /tmp/ss_stage2 /tmp/ss_stage3` —— POSIX 直接字节比较,无 xxd 依赖。
// 见 build_xxd_fixed_point.options.md
//    / tools/bugfix_reports/2026-05-19-build-xxd-fixed-point.bugfix
// 父约束:docs/1-axioms.md §C1(stage2 == stage3 byte-identical)
//
// 失败退出码:1=build.sh 仍含 xxd  2=未改用 cmp -s  3=cmp 漏判不同文件  4=cmp 漏判相同文件

function main() {
    // 工件层:build.sh 固定点校验必须用 cmp,不得依赖 xxd
    const buildSh = readFile("build.sh")
    if (buildSh.indexOf("xxd") >= 0) { exit(1) }
    if (buildSh.indexOf("cmp -s") < 0) { exit(2) }

    // 行为层:cmp -s 须能区分不同文件、识别两个内容相同的独立文件
    const sameBytes = "fixed-point-identical"
    writeFile("/tmp/ss_fp_rt_a", sameBytes)
    writeFile("/tmp/ss_fp_rt_b", "fixed-point-different")
    writeFile("/tmp/ss_fp_rt_c", sameBytes)
    if (system("cmp -s /tmp/ss_fp_rt_a /tmp/ss_fp_rt_b") == 0) { exit(3) }
    if (system("cmp -s /tmp/ss_fp_rt_a /tmp/ss_fp_rt_c") != 0) { exit(4) }

    println("build_xxd_fixed_point: fixed-point verification is byte-real")
}
