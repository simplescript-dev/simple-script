// Test: comptime type generation — generate enum and interface definitions at compile time

import { assertEqual } from "@/lib/test"

// Generate an int enum at compile time
comptime {
    @comptimeEmit(`
enum Priority { Low = 1, Medium = 2, High = 3 }
`)
}

// Generate a string enum at compile time
comptime {
    @comptimeEmit(`
enum LogLevel { Debug = "debug", Info = "info", Error = "error" }
`)
}

// Generate an interface at compile time
comptime {
    @comptimeEmit(`
interface Describable {
    function describe(): string
}
`)
}

// Generate a class that implements the comptime-generated interface
comptime {
    @comptimeEmit(`
class Item : Describable {
    name: string
    priority: int

    function describe(): string {
        return this.name + " (priority=" + this.priority + ")"
    }
}
`)
}

// Generate enum from data at compile time (dynamic field generation)
comptime {
    const names = "Red,Green,Blue"
    const parts = names.split(",")
    let body = ""
    let i = 0
    while (i < parts.length()) {
        if (i > 0) { body = body + ", " }
        body = body + parts[i] + " = " + (i + 1)
        i = i + 1
    }
    @comptimeEmit(`enum DynColor { ${body} }`)
}

// Use generated interface for polymorphism
function describeItem(d: Describable): string {
    return d.describe()
}

function main() {
    test("comptime type gen — int enum", () => {
        const p = Priority.Medium
        assertEqual(p, 2)
        assertEqual(Priority.High, 3)
    })
    test("comptime type gen — string enum", () => {
        const lvl = LogLevel.Info
        assertEqual(lvl, "info")
        assertEqual(LogLevel.Error, "error")
    })
    test("comptime type gen — interface + implementing class", () => {
        const item = new Item(name: "Task", priority: 1)
        assertEqual(item.describe(), "Task (priority=1)")
    })
    test("comptime type gen — interface polymorphism", () => {
        const item = new Item(name: "Bug", priority: 3)
        assertEqual(describeItem(item), "Bug (priority=3)")
    })
    test("comptime type gen — dynamically generated enum", () => {
        assertEqual(DynColor.Red, 1)
        assertEqual(DynColor.Green, 2)
        assertEqual(DynColor.Blue, 3)
    })
}
