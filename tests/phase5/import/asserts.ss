// asserts.ss — 共享测试辅助:phase5 测试通用断言族(assert / assertEq /
// assertInt / assertApprox / assertStr)。
//
// 落点 tests/phase5/import/:目录名以 /import 结尾,collectTestFiles
// (bootstrap/main.ss:410)对 /import 目录只收 main.ss、跳过其余 .ss,故本辅助
// 模块不会被 bin/ss test 误当独立测试编译(它无 main(),被收即编译失败)。
//
// 各断言:条件成立 → 静默;不成立 → println("FAIL: …") + exit(1)。assertEq
// 提供 int / string 双 overload,按实参类型解析。

function assert(cond: int, msg: string) {
    if (cond == 0) {
        println(`FAIL: ${msg}`)
        exit(1)
    }
}

function assertEq(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} - expected ${expected}, got ${actual}`)
        exit(1)
    }
}

function assertEq(actual: string, expected: string, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — expected "${expected}", got "${actual}"`)
        exit(1)
    }
}

function assertInt(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — expected ${expected}, got ${actual}`)
        exit(1)
    }
}

function assertApprox(actual: double, expected: double, msg: string) {
    const diff = Math.abs(actual - expected)
    if (diff > 0.0001) {
        println(`FAIL: ${msg} - expected ${expected}, got ${actual}`)
        exit(1)
    }
}

function assertStr(actual: string, expected: string, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} - expected "${expected}", got "${actual}"`)
        exit(1)
    }
}
