// repo_paths.ss — locate repo-relative resources from any cwd.
//
// ss binary needs vendor/mimalloc.o at link time; cwd-relative lookup fails
// when users invoke ss from outside the simple-script repo. /proc/$PPID/exe
// reaches ss binary via popen's sh parent, then dirname twice to repo root.
// (/proc/self/exe would resolve readlink's own binary.)
//
// prelude.ss is no longer reached via this path — embedded into binary via
// prelude_embed.ss — but the same resolver fallback covers cold-start.

let cachedRepoRoot = ""
let cachedRepoRootInit = 0

function stripTrailingNewline(s: string): string {
    let n = s.length()
    while (n > 0) {
        const ch = charCodeAt(s, n - 1)
        if (ch != 10 && ch != 13) { break }
        n = n - 1
    }
    if (n == s.length()) { return s }
    return s.substring(0, n)
}

function findRepoRoot(): string {
    if (cachedRepoRootInit == 1) { return cachedRepoRoot }
    cachedRepoRootInit = 1
    const result = exec("readlink /proc/$PPID/exe")
    if (result.exitCode != 0) { return "" }
    const exePath = stripTrailingNewline(result.stdout)
    if (exePath == "") { return "" }
    const binSlash = lastIndexOf(exePath, "/")
    if (binSlash <= 0) { return "" }
    const binDir = exePath.substring(0, binSlash)
    const rootSlash = lastIndexOf(binDir, "/")
    if (rootSlash <= 0) { return "" }
    cachedRepoRoot = binDir.substring(0, rootSlash)
    return cachedRepoRoot
}

// stdlib root (== repo root). For SS-repo-internal imports this equals the
// project root so existing @/lib/X imports stay equivalent; external projects
// reach the installed stdlib instead of their own non-existent lib/.
function resolveStdlibRoot(fallback: string): string {
    const root = findRepoRoot()
    if (root != "") { return root }
    return fallback
}

function resolveRepoFile(relPath: string): string {
    if (fileExists(relPath) == 1) { return relPath }
    const upPath = `../${relPath}`
    if (fileExists(upPath) == 1) { return upPath }
    const root = findRepoRoot()
    if (root != "") {
        const absPath = `${root}/${relPath}`
        if (fileExists(absPath) == 1) { return absPath }
    }
    return ""
}
