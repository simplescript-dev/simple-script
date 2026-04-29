let storedFn: fn = () => {
    println("hello from arrow")
}

function greet(): string {
    return "greet called"
}

let namedFn: fn = greet

function main() {
    storedFn()
    let result = namedFn()
    if (result != "greet called") { exit(1) }
    println("global_fn_var: all passed")
}
