// source_probe.ss — 共享测试辅助:按函数名从 SimpleScript 源码文本提取函数体。
//
// 服务"源码核对型"回归测试(I029 / I031 等):这类回归若行为驱动,会在
// bin/ss test 内嵌套 bin/ss test、与外层并行 runner race(I028 §isolate),
// 故改为静态核对编译器源码 —— 提取目标函数体文本、断言其含/不含特定字面值。
//
// 落点 tests/phase5/import/:目录名以 /import 结尾,collectTestFiles
// (bootstrap/main.ss)对 /import 目录只收 main.ss、跳过其余 .ss,故本辅助
// 模块不会被 bin/ss test 误当独立测试编译(它无 main(),被收即编译失败)。
//
// functionBody(src, fnName):返回从 `function fnName(` 起、到紧随其后下一个
// 顶层 function 声明之前的源码文本(目标为文件末函数则到 EOF);未找到返回 ""。
// 依赖 bootstrap/*.ss 顶层函数无前导缩进这一不变量。

function functionBody(src: string, fnName: string): string {
    const marker = "function " + fnName + "("
    const startIdx = src.indexOf(marker)
    if (startIdx < 0) { return "" }
    const rest = src.substring(startIdx, src.length() - startIdx)
    const nextFn = rest.indexOf("\nfunction ")
    if (nextFn < 0) { return rest }
    return rest.substring(0, nextFn)
}
