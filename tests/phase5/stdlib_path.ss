import { Path } from "@/lib/path"

import { assert, assertEq } from "./import/asserts"

function main() {
    // join — 2 args
    assertEq(Path.join("/usr", "local"), "/usr/local", "join basic")
    assertEq(Path.join("/usr/", "local"), "/usr/local", "join trailing slash")
    assertEq(Path.join("/usr", "/local"), "/usr/local", "join leading slash")
    assertEq(Path.join("/usr/", "/local"), "/usr/local", "join both slashes")
    assertEq(Path.join("", "local"), "local", "join empty a")
    assertEq(Path.join("/usr", ""), "/usr", "join empty b")

    // join — 3 args
    assertEq(Path.join("/usr", "local", "bin"), "/usr/local/bin", "join 3 args")

    // join — 4 args
    assertEq(Path.join("a", "b", "c", "d"), "a/b/c/d", "join 4 args")

    // basename
    assertEq(Path.basename("/usr/local/bin"), "bin", "basename basic")
    assertEq(Path.basename("/usr/local/bin/"), "bin", "basename trailing slash")
    assertEq(Path.basename("file.txt"), "file.txt", "basename no dir")
    assertEq(Path.basename("/"), "", "basename root")
    assertEq(Path.basename(""), "", "basename empty")

    // dirname
    assertEq(Path.dirname("/usr/local/bin"), "/usr/local", "dirname basic")
    assertEq(Path.dirname("/usr/local/bin/"), "/usr/local", "dirname trailing slash")
    assertEq(Path.dirname("file.txt"), ".", "dirname no dir")
    assertEq(Path.dirname("/file.txt"), "/", "dirname root file")
    assertEq(Path.dirname(""), ".", "dirname empty")

    // extname
    assertEq(Path.extname("file.txt"), ".txt", "extname basic")
    assertEq(Path.extname("file.tar.gz"), ".gz", "extname double ext")
    assertEq(Path.extname("file"), "", "extname no ext")
    assertEq(Path.extname(".gitignore"), "", "extname dotfile")
    assertEq(Path.extname("/path/to/file.ss"), ".ss", "extname with path")

    // isAbsolute
    assert(Path.isAbsolute("/usr") == 1, "isAbsolute /usr")
    assert(Path.isAbsolute("usr") == 0, "isAbsolute usr")
    assert(Path.isAbsolute("") == 0, "isAbsolute empty")

    // normalize
    assertEq(Path.normalize("/usr/./local/../bin"), "/usr/bin", "normalize mixed")
    assertEq(Path.normalize("/usr/local/./bin"), "/usr/local/bin", "normalize dot")
    assertEq(Path.normalize("a/b/../c"), "a/c", "normalize relative dotdot")
    assertEq(Path.normalize("a/b/../../c"), "c", "normalize double dotdot")
    assertEq(Path.normalize("../a/b"), "../a/b", "normalize leading dotdot")
    assertEq(Path.normalize(""), ".", "normalize empty")
    assertEq(Path.normalize("/"), "/", "normalize root")

    // resolve
    assertEq(Path.resolve("/usr", "local/bin"), "/usr/local/bin", "resolve relative")
    assertEq(Path.resolve("/usr", "/etc/config"), "/etc/config", "resolve absolute")

    println("all path tests passed")
}
