import { FS } from "@/lib/fs"

function assert(cond: int, msg: string) {
    if (cond == 0) {
        println(`FAIL: ${msg}`)
        exit(1)
    }
}

function assertEq(actual: string, expected: string, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — expected "${expected}", got "${actual}"`)
        exit(1)
    }
}

function main() {
    const testDir = "/tmp/ss_fs_test"
    const testFile = "/tmp/ss_fs_test/hello.txt"

    // mkdirp
    FS.mkdirp(testDir)
    assert(FS.exists(testDir) == 1, "mkdirp creates dir")

    // writeFile + readFile
    FS.writeFile(testFile, "hello world")
    assert(FS.exists(testFile) == 1, "writeFile creates file")
    assertEq(FS.readFile(testFile), "hello world", "readFile content")

    // appendFile
    FS.appendFile(testFile, "!")
    assertEq(FS.readFile(testFile), "hello world!", "appendFile")

    // fileSize
    assert(FS.fileSize(testFile) == 12, "fileSize")

    // readDir
    FS.writeFile("/tmp/ss_fs_test/a.txt", "a")
    FS.writeFile("/tmp/ss_fs_test/b.txt", "b")
    const entries = FS.readDir(testDir)
    assert(entries.length() >= 3, "readDir has entries")

    // rename
    FS.rename("/tmp/ss_fs_test/b.txt", "/tmp/ss_fs_test/c.txt")
    assert(FS.exists("/tmp/ss_fs_test/c.txt") == 1, "rename target exists")
    assert(FS.exists("/tmp/ss_fs_test/b.txt") == 0, "rename source gone")

    // remove
    FS.remove("/tmp/ss_fs_test/c.txt")
    assert(FS.exists("/tmp/ss_fs_test/c.txt") == 0, "remove deletes file")

    // cleanup
    FS.remove("/tmp/ss_fs_test/a.txt")
    FS.remove(testFile)
    FS.remove(testDir)

    println("all fs tests passed")
}
