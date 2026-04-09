import { FileWatcher } from "@/lib/watcher"

function main() {
    // Setup: create temp dir and file
    mkdir("/tmp/ss_watch_test")
    writeFile("/tmp/ss_watch_test/a.txt", "hello")

    // Start watching
    const watcher = FileWatcher.create()
    watcher.watch("/tmp/ss_watch_test/")

    // Trigger a file change
    writeFile("/tmp/ss_watch_test/a.txt", "world")

    // Poll should detect the change
    const changed = watcher.poll(500)
    if (changed == "") {
        println("ERROR: no file change detected")
        exit(1)
    }

    // Cleanup
    watcher.close()
    removeFile("/tmp/ss_watch_test/a.txt")
}
