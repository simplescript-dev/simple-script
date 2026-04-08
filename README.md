# SimpleScript

A self-bootstrapping compiled language with Java/TypeScript syntax that produces native static binaries.

**Self-hosted compiler (15,500 LOC SimpleScript). Zero C runtime. Perceus reference counting. 19x faster than Python.**

Website: [simplescript.dev](https://simplescript.dev)

## Quick Start

```bash
ss new myapp && cd myapp
ss run                        # reads ss.json, compiles & runs
ss build --release            # optimized static binary (-O2)
```

## Language

```typescript
// Variables & types
const name = "Alice"
let count = 0
const score: double = 9.5

// Functions with default params & overloading
function greet(name: string = "World") {
    println("Hello, " + name + "!")
}
greet()            // Hello, World!
greet("Alice")     // Hello, Alice!

// Template strings
println(`${name} scored ${score}`)

// Classes with inheritance
class Animal(name: string, sound: string) {
    function speak() { println(`${this.name} says ${this.sound}`) }
}
class Dog extends Animal(breed: string) {
    override function toString(): string {
        return `${this.name} the ${this.breed}`
    }
}
const d = new Dog("Rex", "woof", "Labrador")
println(d)         // Rex the Labrador (auto toString)
d.speak()          // Rex says woof (inherited)

// Abstract classes
abstract class Shape {
    abstract function area(): double
}
class Circle extends Shape(radius: double) {
    override function area(): double { return 3.14159 * this.radius * this.radius }
}

// Access modifiers & static
class Counter(private count: int) {
    static function create(): Counter { return new Counter(0) }
    function increment() { this.count = this.count + 1 }
    function value(): int { return this.count }
}

// Enums with values
enum Color { Red = 1, Green = 2, Blue = 3 }
enum Direction { Up = "up", Down = "down", Left = "left", Right = "right" }
const names = Direction.names()   // ["Up", "Down", "Left", "Right"]

// Generics with constraints
function max<T extends Comparable>(a: T, b: T): T {
    return a > b ? a : b
}
class Stack<T> {
    items: Array<T>
    function push(item: T) { this.items.push(item) }
}

// Null safety
let name: string? = null
if (name != null) {
    println(name.length())     // smart narrowing
}
const fallback = name ?? "default"

// Error handling (try/catch/finally)
class IOError extends Error(path: string) {}
try {
    const data = readFile("config.txt")
} catch (e: IOError) {
    println(`IO error on ${e.path}: ${e.message}`)
} catch (e) {
    println("unexpected: " + e.message)
} finally {
    println("cleanup done")
}

// Type checking & casting
if (animal instanceof Dog) {
    const dog = animal as Dog
    println(dog.breed)
}

// Collections
const nums = [5, 3, 1, 4, 2]
nums.sort()                    // [1, 2, 3, 4, 5]
nums.push(6)

const m = new Map()
m.set("key", "value")

const s = new Set()
s.add("hello")

// Higher-order functions & arrows
const doubled = nums.map((x: int): int => x * 2)
const evens = nums.filter((x: int): int => x % 2 == 0)

// Destructuring
const [first, second] = [10, 20]
const { name, age } = person

// for-in / for-of
for (key in map) { println(key) }
for (item of array) { println(item) }

// Switch
switch (color) {
    case "red": println("stop")
    case "green": println("go")
    default: println("wait")
}

// Bitwise & math
println(2 ** 10)               // 1024
println(0xFF & 0x0F)           // 15
println(sqrt(144))             // 12

// File I/O
writeFile("data.txt", "hello")
const content = readFile("data.txt")

// Imports
import { parse } from "@/lib/json"
import { add } from "./math"
```

## Standard Library

22 modules in `lib/`, importable via `@/lib/<module>`:

| Module | Description |
|--------|-------------|
| json | JSON parse/stringify |
| crypto | SHA256, HMAC-SHA256, Base64 |
| http | HTTP client |
| regex | Regular expressions |
| datetime | Date/time utilities |
| csv | CSV parse/encode |
| url | URL parse/encode |
| argparse | CLI argument parsing |
| template | Template engine |
| color | ANSI terminal colors |
| fs | File system operations |
| path | Path manipulation |
| log | Logging framework |
| math | Extended math functions |
| uuid | UUID generation |
| ini | INI file parsing |
| sort | Sorting algorithms |
| string_utils | String utilities |
| test | Testing framework |
| assert | Assertions |
| base64 | Base64 encode/decode |
| sha256 | SHA256 hashing |

## Testing

```bash
ss test tests/                  # run all 167 tests
ss test tests/phase5/           # run specific phase
```

Built-in testing framework:

```typescript
import { test, assertEqual, assertTrue } from "@/lib/test"

function main() {
    test("addition", () => {
        assertEqual(1 + 1, 2)
    })
    test("string contains", () => {
        assertTrue("hello".contains("ell"))
    })
}
```

## CLI

```
ss new <name>                    Create project (ss.json + src/main.ss)
ss run [--release] [--watch]     Build & run (reads ss.json)
ss build [--release] [-o name]   Compile to static binary
ss check <file>                  Type-check only
ss test [dir]                    Run .ss test files
ss fmt <file>                    Format code
ss repl                          Interactive REPL
ss clean                         Remove build cache
```

## Performance

| Language | fib(35) | vs Python |
|----------|---------|-----------|
| C (gcc -O2) | 13ms | 60x |
| **SimpleScript** | **41ms** | **19x** |
| Python | 785ms | 1x |

Static binary, no runtime dependencies. Starts instantly.

## Architecture

```
.ss source → Lexer → Parser (AST) → Checker → PIR → Codegen (LLVM IR) → llc + musl-gcc → static binary
```

- **Self-bootstrapping**: the compiler compiles itself. 3-stage fixed-point verification produces byte-identical binaries.
- **Self-hosted**: 15,500 lines of SimpleScript across 35 source files in `bootstrap/`.
- **Zero C runtime**: all runtime functions generated as LLVM IR by the compiler itself.
- **Perceus RC**: automatic reference counting for class instances via liveness analysis — no GC, no manual memory management.
- **Static linking**: musl libc + mimalloc allocator, single binary with no shared library dependencies.

## Building from Source

Requires: `llc-18` (LLVM), `musl-gcc` (static linking).

```bash
./build.sh              # build compiler using seed binary
./build.sh bootstrap    # full 3-stage self-bootstrap with fixed-point verification
```

## License

MIT
