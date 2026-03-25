# SimpleScript

A compiled language with Java/TypeScript syntax that produces tiny, fast native binaries.

**82KB static binary. 30ms fib(35). 29x faster than Python.**

Website: [simplescript.dev](https://simplescript.dev)

## Quick Start

```bash
ss new myapp && cd myapp
ss run                        # reads ss.json, compiles & runs
ss build --release            # 82KB static binary
```

## Language

```javascript
// Variables
const name = "Alice"
let count = 0

// Functions with default params
function greet(name: string = "World") {
    println("Hello,", name + "!")
}
greet()            // Hello, World!
greet("Alice")     // Hello, Alice!

// Classes with inheritance
class Animal(name: string, sound: string) {
    function toString(): string { return this.name }
    function speak() { println(this.name, "says", this.sound) }
}
class Dog extends Animal(breed: string) {
    override function toString(): string { return this.name + " the " + this.breed }
}
const d = new Dog("Rex", "woof", "Labrador")
println(d)         // Rex the Labrador (auto toString)
d.speak()          // Rex says woof (inherited)

// Arrays
const nums = [5, 3, 1, 4, 2]
nums.sort()
println(nums)      // [1, 2, 3, 4, 5]
nums.push(6)
nums.reverse()
println(nums.slice(0, 3))  // [6, 5, 4]

// String arrays
const parts = "a,b,c".split(",")
println(parts)     // ["a", "b", "c"]
for (p in parts) { print(p + " ") }
println(parts.join(" | "))  // a | b | c

// Map
const m = Map()
m.set("key", "value")
println(m.getString("key"))  // value

// String methods (19 total)
"  hello  ".trim().toUpperCase()           // "HELLO"
"hello".replace("l", "L")                  // "heLLo"
"42".padStart(6, "0")                      // "000042"
"ha".repeat(3)                             // "hahaha"
"hello".contains("ell")                    // 1

// Math
println(sqrt(144))          // 12
println(2 ** 10)            // 1024
println(abs(-42))           // 42

// Ternary
const grade = score >= 90 ? "A" : score >= 80 ? "B" : "C"

// Multi-file imports
import { add } from "./math"

// File I/O
writeFile("data.txt", "hello")
const content = readFile("data.txt")

// Multi-arg println with auto-format
println("x =", 10, "arr =", [1, 2, 3])
// x = 10 arr = [1, 2, 3]
```

## CLI

```bash
ss new <name>                    # Create project (ss.json + src/main.ss)
ss run [--release] [--watch]     # Build & run (reads ss.json)
ss build [--release] [-o name]   # Compile to static binary
ss check <file>                  # Type-check only (~0ms)
ss test [dir]                    # Run all .ss test files
ss fmt <file>                    # Format code
ss repl                          # Interactive REPL (multi-line)
ss clean                         # Remove cached build files
```

## Performance

| Language | fib(35) | Binary |
|----------|---------|--------|
| C (gcc -O2) | 19ms | — |
| **SimpleScript** | **30ms** | **82KB** |
| Python | 873ms | — |

## Architecture

```
.ss → Lexer → Parser → Checker → LLVM IR → musl link → static binary
```

Rust compiler (5300 lines) + C runtime (560 lines) + LLVM 18.

## License

MIT
