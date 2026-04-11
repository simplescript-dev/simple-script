// Test: basic comptime block execution (D087 Phase 1f)
// comptime blocks run at compile time, produce no runtime code.

comptime {
    let x = 1 + 2
    println(x)
}

comptime {
    const name = "hello"
    const upper = name.toUpperCase()
    println(upper)
}

comptime {
    let sum = 0
    let i = 1
    while (i <= 10) {
        sum = sum + i
        i = i + 1
    }
    println(sum)
}

comptime {
    function factorial(n: int): int {
        if (n <= 1) { return 1 }
        return n * factorial(n - 1)
    }
    println(factorial(6))
}

comptime {
    let arr: Array<string> = []
    arr = arr.push("a")
    arr = arr.push("b")
    arr = arr.push("c")
    println(arr.join("-"))
}

function main() {
    println("runtime ok")
}
