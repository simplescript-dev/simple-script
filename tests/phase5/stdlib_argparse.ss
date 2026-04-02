import { ArgParse, ArgParser, ArgResult } from "@/lib/argparse"
import { Assert } from "@/lib/assert"

function main() {
    // Test 1: basic flag and option parsing
    let p1 = ArgParse.create("test", "Test app")
    p1.option("--output", "-o", "Output file", "default.txt")
    p1.flag("--verbose", "-v", "Verbose mode")

    let a1: Array<string> = []
    a1 = a1.push("--output")
    a1 = a1.push("file.txt")
    a1 = a1.push("-v")
    a1 = a1.push("input.txt")
    let r1 = p1.parseArray(a1)

    Assert.equal(r1.getString("output"), "file.txt", "option value")
    Assert.equal(r1.getBool("verbose"), 1, "flag set")
    Assert.equal(r1.has("output"), 1, "has output")
    Assert.equal(r1.has("verbose"), 1, "has verbose")
    Assert.equal(r1.positionalCount(), 1, "positional count")
    let pos1 = r1.positionals()
    Assert.equal(pos1[0], "input.txt", "positional 0")

    // Test 2: default values when no args given
    let p2 = ArgParse.create("test2", "Test 2")
    p2.option("--name", "-n", "Name", "world")
    p2.flag("--debug", "-d", "Debug")

    let a2: Array<string> = []
    let r2 = p2.parseArray(a2)

    Assert.equal(r2.getString("name"), "world", "default name")
    Assert.equal(r2.getBool("debug"), 0, "default debug off")
    Assert.equal(r2.has("name"), 0, "not explicitly set")
    Assert.equal(r2.has("debug"), 0, "not explicitly set")

    // Test 3: --option=value syntax
    let p3 = ArgParse.create("test3", "Test 3")
    p3.option("--config", "-c", "Config file", "")

    let a3: Array<string> = []
    a3 = a3.push("--config=app.json")
    let r3 = p3.parseArray(a3)

    Assert.equal(r3.getString("config"), "app.json", "equals syntax")
    Assert.equal(r3.has("config"), 1, "has config")

    // Test 4: -- stops option parsing
    let p4 = ArgParse.create("test4", "Test 4")
    p4.flag("--verbose", "-v", "Verbose")

    let a4: Array<string> = []
    a4 = a4.push("-v")
    a4 = a4.push("--")
    a4 = a4.push("--not-an-option")
    let r4 = p4.parseArray(a4)

    Assert.equal(r4.getBool("verbose"), 1, "verbose before --")
    Assert.equal(r4.positionalCount(), 1, "positional after --")
    let pos4 = r4.positionals()
    Assert.equal(pos4[0], "--not-an-option", "-- stops parsing")

    // Test 5: help text generation
    let p5 = ArgParse.create("myapp", "My Application")
    p5.version("1.0.0")
    p5.option("--output", "-o", "Output file path", "out.txt")
    p5.flag("--verbose", "", "Enable verbose mode")

    const helpText = p5.help()
    Assert.isTrue(helpText.indexOf("My Application") >= 0, "help has description")
    Assert.isTrue(helpText.indexOf("--output") >= 0, "help has --output")
    Assert.isTrue(helpText.indexOf("-o") >= 0, "help has -o")
    Assert.isTrue(helpText.indexOf("1.0.0") >= 0, "help has version")
    Assert.isTrue(helpText.indexOf("out.txt") >= 0, "help has default")

    // Test 6: getInt
    let p6 = ArgParse.create("test6", "Test 6")
    p6.option("--count", "-n", "Count", "5")

    let a6: Array<string> = []
    a6 = a6.push("--count")
    a6 = a6.push("42")
    let r6 = p6.parseArray(a6)

    Assert.equal(r6.getInt("count"), 42, "getInt explicit")

    // Test 7: default getInt
    let p7 = ArgParse.create("test7", "Test 7")
    p7.option("--port", "-p", "Port", "8080")

    let a7: Array<string> = []
    let r7 = p7.parseArray(a7)

    Assert.equal(r7.getInt("port"), 8080, "getInt default")

    // Test 8: short flags only
    let p8 = ArgParse.create("test8", "Test 8")
    p8.option("--host", "-H", "Host", "localhost")
    p8.option("--port", "-p", "Port", "3000")

    let a8: Array<string> = []
    a8 = a8.push("-H")
    a8 = a8.push("example.com")
    a8 = a8.push("-p")
    a8 = a8.push("9090")
    let r8 = p8.parseArray(a8)

    Assert.equal(r8.getString("host"), "example.com", "short host")
    Assert.equal(r8.getInt("port"), 9090, "short port")

    // Test 9: multiple positionals
    let p9 = ArgParse.create("test9", "Test 9")
    p9.flag("--all", "-a", "All")

    let a9: Array<string> = []
    a9 = a9.push("file1.txt")
    a9 = a9.push("-a")
    a9 = a9.push("file2.txt")
    a9 = a9.push("file3.txt")
    let r9 = p9.parseArray(a9)

    Assert.equal(r9.getBool("all"), 1, "flag among positionals")
    Assert.equal(r9.positionalCount(), 3, "3 positionals")
    let pos9 = r9.positionals()
    Assert.equal(pos9[0], "file1.txt", "pos 0")
    Assert.equal(pos9[1], "file2.txt", "pos 1")
    Assert.equal(pos9[2], "file3.txt", "pos 2")

    // Test 10: no short flag
    let p10 = ArgParse.create("test10", "Test 10")
    p10.option("--timeout", "", "Timeout in seconds", "30")

    let a10: Array<string> = []
    a10 = a10.push("--timeout")
    a10 = a10.push("60")
    let r10 = p10.parseArray(a10)

    Assert.equal(r10.getInt("timeout"), 60, "long-only option")

    println("All argparse tests passed")
}
