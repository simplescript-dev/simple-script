// Regression I028: 运行时 IR 缓存子系统是死代码 —— 必须整体删除,不得复现。
//
// bug: gen_rt_cache.ss 的运行时 IR 缓存构建器每次 bin/ss test 起手构建一份
//      (a) 确定性 llc 失败的(喂 llc 的 IR 缺 %String/%Array/%Map typedecl →
//      "base element of getelementptr must be sized")、(b) 从未被读的(编译子进程
//      该缓存开关恒 0)运行时 IR 缓存 —— 整子系统 broken + dead。
// fix: 删整个 dead 缓存子系统(gen_rt_cache.ss 文件 + codegen.ss / main.ss 调用点)。
// 见 I028.options.md
//    / tools/bugfix_reports/2026-05-19-i028-runtime-cache-dead-subsystem.bugfix
// 父约束:docs/4-issues/I028-runtime-cache-dead-subsystem.md
//
// 检测法(确定性,无 race,零嵌套 bin/ss test):死缓存子系统由编译器源码本身坐实,
//   直接核对 bootstrap/ 源码 —— (a) gen_rt_cache.ss 文件不存在;(b) 该子系统的
//   缓存符号在 bootstrap/ 全删干净。修复前 buggy 源码:文件在 → 失败;修复后
//   整体删除 → exit 0。
//   为何不行为驱动:bug 由 cmdTest 触发,嵌套 bin/ss test 会与外层 tests/ 并行
//   runner 在固定路径 /tmp/ss_test_par.sh /tmp/ss_test_<idx> 上 race(I028
//   §关联观察 明列的独立 bug)—— 死代码已删 即 llc 噪音已除,源码核对是该死
//   子系统不复现的精确、无 race 守卫;行为层 RED→GREEN 由 .bugfix 证据单进程实测。
//
// 失败退出码:2=gen_rt_cache.ss 文件仍在(死缓存子系统未删)
//            3=缓存子系统符号仍残留于 bootstrap/(未删干净)
//            4=核对探针自身失效(读不到 bootstrap/ — 防平凡通过)

function main() {
    // 防平凡通过:确认探针在仓库根、能读到 bootstrap/ 源码树。
    if (fileExists("bootstrap/gen/codegen.ss") != 1) { exit(4) }

    // 不变量 (a):死缓存子系统的文件载体已删除。
    if (fileExists("bootstrap/gen/rt/gen_rt_cache.ss") == 1) { exit(2) }

    // 不变量 (b):缓存子系统四个符号在 bootstrap/ 全删干净(grep 命中即残留)。
    const sym = "buildRuntimeCache|useRuntimeCache|runtimeCacheObj|runtimeCacheDecls"
    const hits = shell(`grep -rlE '${sym}' bootstrap/ 2>/dev/null`).trim()
    if (hits != "") { exit(3) }

    println("i028_runtime_cache_dead_subsystem: dead runtime IR cache subsystem fully removed")
}
