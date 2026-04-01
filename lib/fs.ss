// SimpleScript File System Library — High-level wrapper over runtime functions
//
// Usage:
//   import { FS } from "@/lib/fs"
//   const content = FS.readFile("data.txt")
//   FS.writeFile("output.txt", content)
//   if (FS.exists("config.json")) { ... }
//   const entries = FS.readDir("/tmp")

class FS()

// ── Read/Write ───────────────────────────────────────────────

function FS_readFile(path: string): string {
    return readFile(path)
}

function FS_writeFile(path: string, content: string) {
    writeFile(path, content)
}

function FS_appendFile(path: string, content: string) {
    appendFile(path, content)
}

// ── Existence & Info ─────────────────────────────────────────

function FS_exists(path: string): int {
    return fileExists(path)
}

function FS_fileSize(path: string): int {
    return fileSize(path)
}

// ── Directory ────────────────────────────────────────────────

function FS_mkdir(path: string): int {
    return mkdir(path)
}

function FS_mkdirp(path: string): int {
    return mkdirp(path)
}

function FS_readDir(path: string): Array<string> {
    const raw = listDir(path)
    if (raw == "") { return [] }
    return raw.split("\n")
}

// ── Modify ───────────────────────────────────────────────────

function FS_remove(path: string): int {
    return removeFile(path)
}

function FS_rename(oldPath: string, newPath: string): int {
    return renameFile(oldPath, newPath)
}
