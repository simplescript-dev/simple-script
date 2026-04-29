class Handler {
    name: string
    callback: fn
}

function doWork(): string {
    return "done"
}

function add(a: int, b: int): int {
    return a + b
}

function main() {
    let h = new Handler("test", doWork)
    let result = h.callback()
    if (result != "done") { exit(1) }

    h.callback = add
    let sum = h.callback(3, 4)
    if (sum != 7) { exit(1) }

    h.callback = () => {
        return 42
    }
    let r3 = h.callback()
    if (r3 != 42) { exit(1) }

    println("class_fn_field: all passed")
}
