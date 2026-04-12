// Test: type-level comptime — comptime blocks inside class body generate methods

import { assertEqual } from "@/lib/test"

class Point {
    x: int
    y: int

    comptime {
        const info = getTypeInfo("Point")
        let body = "    return \""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { body = body + ", " }
            body = body + f.name + "=\" + this." + f.name + " + \""
            i = i + 1
        }
        body = body + "\""
        @comptimeEmit(`
function describe(): string {
${body}
}
`)
    }
}

class Config {
    host: string
    port: int
    debug: int

    comptime {
        // Generate a field-count method
        const info = getTypeInfo("Config")
        const count = info.fields.length()
        @comptimeEmit(`
function fieldCount(): int {
    return ${count}
}
`)
    }

    comptime {
        // Generate a fieldNames method using reflection
        const info = getTypeInfo("Config")
        let names = ""
        let i = 0
        while (i < info.fields.length()) {
            if (i > 0) { names = names + "," }
            names = names + info.fields[i].name
            i = i + 1
        }
        @comptimeEmit(`
function fieldNames(): string {
    return "${names}"
}
`)
    }
}

function main() {
    test("class comptime describe method", () => {
        const p = new Point(x: 10, y: 20)
        assertEqual(p.describe(), "x=10, y=20")
    })
    test("class comptime fieldCount", () => {
        const c = new Config(host: "localhost", port: 8080, debug: 1)
        assertEqual(c.fieldCount(), 3)
    })
    test("class comptime fieldNames", () => {
        const c = new Config(host: "localhost", port: 8080, debug: 1)
        assertEqual(c.fieldNames(), "host,port,debug")
    })
}
