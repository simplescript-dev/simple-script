# 14 - CLI Framework (命令行框架)

## 设计理念

> Phase 1 目标是 CLI 工具。标准库内置 CLI 框架，注解声明命令，零模板代码。

## 基本用法

```simplescript
import { Command, Arg, Option } from "yummy/cli"

@Command(name: "greet", description: "Say hello")
class GreetCommand(
    @Arg(description: "Name to greet")
    name: string,

    @Option(short: "c", description: "Number of times")
    count: int = 1
) {
    function run() {
        for (let i = 0; i < count; i++) {
            println(`hello, ${name}!`)
        }
    }
}

function main() {
    GreetCommand.execute()
}
```

```bash
$ ym run -- Alice
hello, Alice!

$ ym run -- Alice -c 3
hello, Alice!
hello, Alice!
hello, Alice!

$ ym run -- --help
Usage: greet [OPTIONS] <name>

Say hello

Arguments:
  <name>  Name to greet

Options:
  -c, --count <int>  Number of times [default: 1]
  -h, --help         Show help
  -v, --version      Show version
```

## 子命令

```simplescript
import { Command, SubCommand, Arg, Option } from "yummy/cli"

@Command(name: "ym", description: "SimpleScript package manager")
class YmCli {

    @SubCommand(name: "new", description: "Create a new project")
    class NewCommand(
        @Arg(description: "Project name")
        name: string,

        @Option(long: "lib", description: "Create library project")
        lib: bool = false
    ) {
        function run() {
            if (lib) {
                createLibProject(name)
            } else {
                createBinProject(name)
            }
            println(`created project: ${name}`)
        }
    }

    @SubCommand(name: "build", description: "Build the project")
    class BuildCommand(
        @Option(long: "release", description: "Release mode")
        release: bool = false
    ) {
        function run() {
            const mode = if (release) "release" else "debug"
            println(`building in ${mode} mode...`)
        }
    }
}

function main() {
    YmCli.execute()
}
```

```bash
$ myapp new hello-world
created project: hello-world

$ myapp build --release
building in release mode...

$ myapp --help
Usage: ym <COMMAND>

Commands:
  new    Create a new project
  build  Build the project

Options:
  -h, --help     Show help
  -v, --version  Show version
```

## 交互式输入

```simplescript
import { prompt, confirm, select } from "yummy/cli"

function main() {
    const name = prompt("Project name:")?
    const lang = select("Language:", List.of("SimpleScript", "Rust", "Go"))?
    const ok = confirm("Create project?")?

    if (ok) {
        println(`creating ${lang} project: ${name}`)
    }
}
```

## 进度条 / 颜色输出

```simplescript
import { style, ProgressBar } from "yummy/cli"

// 颜色输出
println(style.green("✓ success"))
println(style.red("✗ error"))
println(style.yellow("⚠ warning"))
println(style.bold("important"))

// 进度条
const bar = new ProgressBar(total: 100)
for (let i = 0; i <= 100; i++) {
    doWork()
    bar.advance(1)
}
bar.finish("done!")
```

## 完整示例: 文件搜索工具

```simplescript
import { Command, Arg, Option } from "yummy/cli"
import { walkDir } from "io/fs"
import { Regex } from "util/regex"
import { style } from "yummy/cli"

@Command(name: "ygrep", description: "Search files for a pattern")
class YGrep(
    @Arg(description: "Search pattern")
    pattern: string,

    @Arg(description: "Search path")
    path: string = ".",

    @Option(short: "i", description: "Case insensitive")
    ignoreCase: bool = false,

    @Option(short: "n", description: "Show line numbers")
    lineNumbers: bool = true
) {
    function run() {
        const flags = if (ignoreCase) "i" else ""
        const regex = new Regex(pattern, flags)
        let matchCount = 0

        for (file in walkDir(path)) {
            if (!file.isFile()) continue
            const lines = file.readLines()

            for (let i = 0; i < lines.size(); i++) {
                const line = lines[i]
                if (regex.matches(line)) {
                    const prefix = if (lineNumbers) `${i + 1}:` else ""
                    println(`${style.green(file.path)}:${prefix}${line}`)
                    matchCount += 1
                }
            }
        }

        println(`\n${matchCount} matches found`)
    }
}

function main() {
    YGrep.execute()
}
```

```bash
$ ym build --release
$ ./ygrep "function main" src/
src/main.ss:15:function main() {
src/cli.ss:8:function main() {

2 matches found
```
