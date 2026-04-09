// SimpleScript File Watcher — inotify-based file change monitoring (D081)
//
// Usage:
//   import { FileWatcher } from "@/lib/watcher"
//   const watcher = FileWatcher.create()
//   watcher.watch("src/")
//   const changed = watcher.poll(1000)
//   watcher.close()

class FileWatcher {
    private fd: int

    static function create(): FileWatcher {
        const fd = _ss_inotify_init()
        return new FileWatcher(fd)
    }

    function watch(path: string) {
        _ss_inotify_add_watch(this.fd, path, 1)
    }

    function poll(timeoutMs: int): string {
        return _ss_inotify_poll(this.fd, timeoutMs)
    }

    function close() {
        _ss_inotify_close(this.fd)
    }
}
