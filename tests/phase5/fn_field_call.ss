// Test: calling fn-typed class fields (function pointer stored in field)
class Plugin {
    name: string
    run: fn
}

function doWork(): int { return 42 }

class Callback {
    label: string
    action: fn
    count: int
}

function greet(): string { return "hello" }

function main() {
    const p = new Plugin("test", doWork)
    const result = p.run()
    if (result != 42) { exit(1) }

    const cb = new Callback("cb1", greet, 0)
    const msg = cb.action()
    if (msg != "hello") { exit(1) }

    println("fn_field_call: all passed")
}
