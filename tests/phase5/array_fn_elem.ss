function twice(x: int): int { return x * 2 }
function thrice(x: int): int { return x * 3 }

function apply(f: fn, val: int): int {
    return f(val)
}

function main() {
    let fns: Array<fn> = [twice, thrice]

    // for-in with Array<fn>
    let sum = 0
    for (f in fns) {
        sum = sum + apply(f, 10)
    }
    if (sum != 50) { exit(1) }

    // index access with Array<fn>
    let r = apply(fns[0], 5)
    if (r != 10) { exit(1) }
    r = apply(fns[1], 5)
    if (r != 15) { exit(1) }
}
