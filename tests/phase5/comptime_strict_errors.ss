function check(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — got ${actual}, expected ${expected}`)
        exit(1)
    }
}

function timesTwo(x: int): int {
    return x * 2
}

function main() {
    const fieldOk = comptime {
        class Point { x: int; y: int }
        const p = new Point(10, 20)
        return p.x
    }
    check(fieldOk, 10, "comptime field access on ct object")

    const methodOk = comptime {
        const s = "hello world"
        return s.length()
    }
    check(methodOk, 11, "comptime method call on ct value")

    const indexOk = comptime {
        const arr = [10, 20, 30]
        return arr[1]
    }
    check(indexOk, 20, "comptime index access on ct array")

    const binaryOk = comptime {
        const a = 10
        const b = 3
        return a + b
    }
    check(binaryOk, 13, "comptime binary ops")

    const callOk = comptime {
        return timesTwo(21)
    }
    check(callOk, 42, "comptime function call")

    println("All comptime strict tests passed")
}
