# D080: Process Output Capture (exec)

**Status:** Done
**Depends on:** None
**Priority:** P0

## Context

当前 `system(cmd)` 只返回 exit code，无法获取 stdout。van-cli 需要调用 GraalVM 编译的 van-core 原生二进制并捕获输出。

原始需求考虑过 FFI（直接调用 libvan.so），但因 SimpleScript 静态链接（musl-gcc -static）与共享库动态链接的架构冲突，决定采用子进程方案：van-core 编译为独立 native 可执行文件，SimpleScript 通过 exec() 捕获输出。代价是 ~10ms/次进程启动开销，对模板编译场景完全可接受。

## Decision

新增 `exec(cmd): ExecResult` 内置函数，基于 popen 实现，一次调用返回 stdout 和 exitCode。

## Syntax

```simplescript
const result = exec("van-core compile pages/index.van /src '{\"title\":\"Hello\"}'")
println(result.stdout)      // 编译结果 HTML
println(result.exitCode)    // 0

// 简单用法 — 只需 stdout
const output = exec("ls -la").stdout

// 错误处理
const r = exec("van-core compile bad.van")
if (r.exitCode != 0) {
    println("Error: " + r.stdout)
    exit(1)
}
```

## Implementation

### 1. Prelude class (prelude.ss)

```simplescript
class ExecResult {
    stdout: string
    exitCode: int
}
```

### 2. Runtime function (gen_rt_io.ss)

- `ss_popen_read(cmd: ptr) → ptr`：
  - `popen(cmd, "r")` 打开管道
  - 动态缓冲区 + `fread()` 循环读取全部 stdout
  - `pclose()` 获取 exit status，`(status >> 8) & 0xFF` 提取 exit code
  - exit code 存入全局变量 `@ss_last_exit_code`
  - `ss_rc_strdup` 复制到 RC 管理的字符串，`free` 原始缓冲区
  - 返回 RC 字符串

### 3. Codegen handler (gen_calls.ss)

`exec()` 在 genCall() 中作为特殊 case 处理（同 `test()`/`println()` 模式），避免 prelude 调用 seed 未知的 builtin 导致 bootstrap 鸡生蛋问题：

```
genExecCall(argList):
  1. genExpr(cmdId) → %cmd
  2. call ptr @ss_popen_read(ptr %cmd) → %stdout
  3. load i32 @ss_last_exit_code → %code
  4. call ptr @ExecResult_new(ptr %stdout, i32 %code) → %result
```

### 4. Registry

- gen_registry.ss: `funcRetTypes.set("exec", "ExecResult")`
- checker.ss: `funcNames.set("exec", "ExecResult")` + param count 1

## Rejected Alternatives

| 方案 | 原因 |
|------|------|
| FFI 调用 libvan.so | musl 静态链接不支持 dlopen；引入动态链接破坏静态二进制公理；实现复杂度高 |
| 两个独立函数 execOutput() + system() | 命令执行两次，不可接受 |
| 全局暂存无 class 包装 | 不优雅，API 不直观 |
| fork/exec + pipe | 比 popen 复杂，当前场景 popen 足够 |

## Test Plan

```simplescript
// tests/phase5/exec_basic.ss
function main() {
    // Test 1: capture stdout
    const r1 = exec("echo hello")
    if (r1.stdout != "hello\n") { exit(1) }
    if (r1.exitCode != 0) { exit(1) }

    // Test 2: exit code
    const r2 = exec("false")
    if (r2.exitCode == 0) { exit(1) }

    // Test 3: multi-line output
    const r3 = exec("printf 'a\nb\nc'")
    if (r3.stdout != "a\nb\nc") { exit(1) }
}
```
