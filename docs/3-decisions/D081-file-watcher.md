# D081: File Watcher (inotify)

**Status:** Done
**Depends on:** D080 (exec — 验证 runtime 函数 + prelude class 模式)
**Priority:** P1

## Context

van-cli 的 `van dev` 开发服务器需要监听文件变化实现热重载。需要监听 `.van` 模板文件和数据文件的变更，触发重新编译。

## Decision

基于 Linux inotify 实现文件监听。Runtime 层提供三个系统调用包装，Stdlib 层提供 FileWatcher class。

## Syntax

```simplescript
import { FileWatcher } from "@/lib/watcher"

const watcher = FileWatcher.create()
watcher.watch("src/")
watcher.watch("data/")

while (true) {
    const changed = watcher.poll(1000)  // 阻塞最多 1 秒
    if (changed != "") {
        println("Changed: " + changed)
        recompile()
    }
}

watcher.close()
```

## Implementation

### 1. Runtime functions (gen_rt_system.ss)

- `ss_inotify_init() → i32`：
  - 调用 `inotify_init()` 返回 fd

- `ss_inotify_add_watch(fd: i32, path: ptr, recursive: i32) → i32`：
  - 调用 `inotify_add_watch(fd, path, IN_MODIFY | IN_CREATE | IN_DELETE | IN_MOVED_TO)`
  - 如果 recursive=1，遍历子目录递归 add_watch
  - 返回 watch descriptor

- `ss_inotify_poll(fd: i32, timeout_ms: i32) → ptr`：
  - 用 `poll()` 做超时等待（避免无限阻塞）
  - 读取 `inotify_event`，提取文件名
  - 如果 `IN_CREATE` 且是目录，自动 add_watch（递归监听）
  - 返回变更文件路径字符串，无变更返回 ""

- `ss_inotify_close(fd: i32) → void`：
  - 调用 `close(fd)`

### 2. Stdlib class (lib/watcher.ss)

```simplescript
class FileWatcher {
    private fd: int

    static function create(): FileWatcher {
        const fd = _ss_inotify_init()
        return new FileWatcher(fd)
    }

    function watch(path: string) {
        _ss_inotify_add_watch(this.fd, path, 1)  // recursive=1
    }

    function poll(timeoutMs: int): string {
        return _ss_inotify_poll(this.fd, timeoutMs)
    }

    function close() {
        _ss_inotify_close(this.fd)
    }
}
```

### 3. Registry (gen_registry.ss)

- 注册 `_ss_inotify_init` 返回类型 `int`
- 注册 `_ss_inotify_add_watch` 返回类型 `int`
- 注册 `_ss_inotify_poll` 返回类型 `string`

## Design Notes

- **为什么选 inotify 不选 stat 轮询**：inotify 即时通知、零 CPU 开销。stat 轮询在文件多时 CPU 高、有秒级延迟。SimpleScript 目标平台是 Linux，inotify 是原生方案。
- **递归监听**：inotify 本身不递归。`add_watch` 时遍历子目录；`IN_CREATE` 目录事件时自动添加新 watch。
- **poll 超时**：用 `poll()` 系统调用做超时等待，避免 busy-wait 或无限阻塞。
- **返回值设计**：poll 返回单个文件路径字符串。如果同时有多个文件变更，只返回第一个（dev server 场景足够——任何变更都触发全量重编译）。

## Test Plan

```simplescript
// tests/phase5/watcher_basic.ss
function main() {
    const watcher = FileWatcher.create()

    // 创建临时目录和文件
    mkdir("/tmp/ss_watch_test")
    writeFile("/tmp/ss_watch_test/a.txt", "hello")

    watcher.watch("/tmp/ss_watch_test/")

    // 修改文件
    writeFile("/tmp/ss_watch_test/a.txt", "world")

    // poll 应该能检测到变更
    const changed = watcher.poll(500)
    if (changed == "") { exit(1) }

    watcher.close()
    removeFile("/tmp/ss_watch_test/a.txt")
}
```
