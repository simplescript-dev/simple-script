function greet(name: string = "World", greeting: string = "Hello") {
    println(greeting + ", " + name + "!")
}

function repeat(s: string, n: int = 3): string {
    let result = ""
    for (let i = 0; i < n; i++) {
        result += s
    }
    return result
}

function main() {
    greet()                    // Hello, World!
    greet("Alice")             // Hello, Alice!
    greet("Bob", "Hi")         // Hi, Bob!

    println(repeat("ab"))      // ababab (default n=3)
    println(repeat("x", 5))    // xxxxx
}
