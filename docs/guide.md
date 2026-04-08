# SimpleScript Developer Guide

## 1. Getting Started

### Dependencies

```bash
sudo apt install llvm-18 musl-tools   # Ubuntu/Debian
```

### Create & Run Project

```bash
ss new myapp && cd myapp
ss run                           # compile & run (reads ss.json)
ss build --release -o myapp      # optimized binary (-O2 -s)
```

### CLI

```
ss new <name>                    Create project (ss.json + src/main.ss)
ss run [--release] [--watch]     Build & run
ss build [file] [--release] [-o name] [--emit-ir]
ss check <file>                  Type-check only
ss test [dir]                    Run .ss test files
ss fmt <file>                    Format code
ss repl                          Interactive REPL
ss clean                         Remove build cache
```

### Project Structure

```
myapp/
  ss.json          # project config
  src/
    main.ss        # entry point (must have function main())
```

### Test Files

每个 `.ss` 测试是独立程序，包含 `function main()`。通过条件：编译成功 + exit code 0。

---

## 2. Language Reference

### Types

| Type | Description | LLVM |
|------|-------------|------|
| `int` | 32-bit integer | i32 |
| `double` | 64-bit float | double |
| `bool` | boolean (true/false) | i32 |
| `string` | heap string (RC) | ptr |
| `Array<T>` | dynamic array (RC) | ptr |
| `List<T>` | alias for Array<T> | ptr |
| `Map<K,V>` | hash map (RC) | ptr |
| `Set<T>` | set (Map wrapper) | ptr |
| `T?` | nullable type | ptr |
| `fn` | function pointer | i64 |
| `ClassName` | class instance (RC) | ptr |

### Variables

```typescript
const name = "Alice"              // immutable, type inferred
let count = 0                     // mutable
const x: int = 42                 // explicit type
let s: string? = null             // nullable
```

### Functions

```typescript
function add(a: int, b: int): int {
    return a + b
}

// Default parameters
function greet(name: string = "World") {
    println("Hello, " + name)
}

// Function overloading (name mangling by param types)
function process(x: int): int { return x * 2 }
function process(x: string): string { return x + "!" }
```

### Arrow Functions & Closures

```typescript
const double = (x: int): int => x * 2
const add = (a: int, b: int): int => a + b

// Closures capture outer variables
const threshold = 10
const check = (x: int): int => x > threshold ? 1 : 0

// Multi-line arrow
const compute = (x: int): int => {
    let result = x * 2
    return result + 1
}

// Void arrow (for callbacks)
const log = (msg: string): void => { println(msg) }
```

### Classes

```typescript
// Constructor params become fields
class Player(name: string, health: int) {
    function isAlive(): int { return this.health > 0 ? 1 : 0 }
    function damage(amount: int) { this.health -= amount }
}
const p = new Player("Alice", 100)
println(p.name)

// Field-level const
class Config(const host: string, port: int) {}
// config.host = "x"  // compile error: const field

// Additional fields in body
class Counter(name: string) {
    count: int = 0
    function increment() { this.count += 1 }
}

// Named parameters
const p = new Player(name: "Bob", health: 50)
```

### Inheritance

```typescript
class Animal(name: string) {
    function speak(): string { return this.name }
}

class Dog extends Animal(breed: string) {
    override function speak(): string {
        return `${super.speak()} (${this.breed})`
    }
}

const d = new Dog("Rex", "Lab")
println(d.speak())   // Rex (Lab)
```

### Abstract Classes

```typescript
abstract class Shape {
    abstract function area(): double
}

class Circle extends Shape(radius: double) {
    override function area(): double {
        return 3.14159 * this.radius * this.radius
    }
}
// new Shape() → compile error
```

### Interfaces

```typescript
interface Serializable {
    function toJson(): string
}

class User : Serializable {
    name: string
    function toJson(): string { return `{"name":"${this.name}"}` }
}

// Interface as parameter type (dispatch)
function save(s: Serializable) { writeFile("out.json", s.toJson()) }
```

### Access Modifiers

```typescript
class Account(const name: string, private balance: int) {
    function getBalance(): int { return this.balance }
    private function log(msg: string) { /* internal */ }
}

class Base(protected secret: int) {}
class Child extends Base() {
    function reveal(): int { return this.secret }  // OK
}
```

### Static Methods & Fields

```typescript
class Counter {
    static count: int = 0
    static const MAX: int = 100

    static function create(): Counter { return new Counter() }
    static function getCount(): int { return Counter.count }

    function increment() { Counter.count += 1 }
}

Counter.create()
println(Counter.count)
```

### Generics

```typescript
// Generic function
function identity<T>(x: T): T { return x }
identity(42)
identity("hello")
identity<int>(42)     // explicit type arg

// Generic class
class Box<T>(value: T) {
    function get(): T { return this.value }
}
const b = new Box(42)
const b2 = new Box<string>("hello")

// Constraints
interface Rankable { function rank(): int }
function best<T extends Rankable>(a: T, b: T): T {
    return a.rank() > b.rank() ? a : b
}

// Multiple constraints
function process<T extends Serializable & Rankable>(item: T) { ... }
```

### Enums

```typescript
// Integer enum
enum Color { Red = 0, Green = 1, Blue = 2 }
println(Color.Red)                // 0

// String enum
enum Direction { Up = "up", Down = "down" }
println(Direction.Up)             // "up"

// Iteration
let names = Color.names()         // ["Red", "Green", "Blue"]
let vals = Color.values()         // [0, 1, 2]
let dirs = Direction.values()     // ["up", "down"]
```

### Null Safety

```typescript
let name: string? = null          // nullable
let user: User? = findUser(id)

// Null coalescing
let safe = name ?? "default"

// Optional chaining
let len = name?.length()

// Null check (smart narrowing)
if (user != null) {
    println(user.name)            // user treated as non-null
}

// Nullable return type
function find(id: int): User? {
    if (id <= 0) { return null }
    return new User("Alice")
}
```

### Error Handling

```typescript
// throw string
throw("something went wrong")

// throw Error object
class IOError extends Error(path: string) {}
throw(new IOError("file not found", "/data.txt"))

// try/catch/finally
try {
    const data = readFile("config.txt")
} catch (e: IOError) {
    println("IO error: " + e.message + " path: " + e.path)
} catch (e) {
    println("error: " + e.message)
} finally {
    println("cleanup")
}

// instanceof + as for error handling
try { ... } catch (e) {
    if (e instanceof IOError) {
        const io = e as IOError
        println(io.path)
    }
}
```

### Type Checking & Casting

```typescript
if (animal instanceof Dog) {
    let dog = animal as Dog       // safe downcast
    println(dog.breed)
}

// Failed cast throws exception
try {
    let d = cat as Dog            // throws if not Dog
} catch (e) { ... }
```

### Collections

```typescript
// Array
const nums = [1, 2, 3, 4, 5]
const strs: Array<string> = ["a", "b", "c"]
nums.push(6)
nums.sort()
println(nums.length())

// Map
const m = new Map()
m.set("key", "value")
m.getString("key")                // "value"
m.has("key")                      // 1
for (k in m.keys()) { println(k) }

// Set
const s = new Set()
s.add("hello")
s.has("hello")                    // 1
s.remove("hello")
s.size()
```

### Destructuring

```typescript
// Array destructuring
const [a, b, c] = [10, 20, 30]
const [first, ...rest] = [1, 2, 3, 4]  // rest = [2, 3, 4]

// Object destructuring
const { name, health } = player
const { x: posX, y: posY } = point     // alias
let { name, age } = user               // mutable
```

### Control Flow

```typescript
// if/else
if (x > 0) { println("positive") }
else if (x == 0) { println("zero") }
else { println("negative") }

// Ternary
const label = x > 0 ? "positive" : "negative"

// for loop
for (let i = 0; i < 10; i++) { println(i) }

// for-in (arrays, Map keys)
for (item in array) { println(item) }
for (key in map.keys()) { println(key) }

// for-of
for (const item of array) { println(item) }
for (let x of nums) { x += 1 }

// while / do-while
while (running) { update() }
do { attempt() } while (!done)

// switch/case
switch (cmd) {
    case "add" -> handleAdd()
    case "list" -> handleList()
    default -> showHelp()
}

// break / continue
for (let i = 0; i < 10; i++) {
    if (i == 5) { break }
    if (i % 2 == 0) { continue }
}
```

### Operators

```typescript
// Arithmetic
+ - * / %
**                                // power
++  --                            // increment/decrement

// Comparison
== != < > <= >=

// Logical
&& || !

// Bitwise
& | ^ ~ << >> >>>

// Assignment
= += -= *= /= %= &= |= ^= <<= >>=

// Null
??                                // null coalescing
?.                                // optional chaining

// Type
instanceof                       // runtime type check
as                                // type cast
```

### Template Strings

```typescript
const name = "Alice"
const msg = `Hello, ${name}!`
const calc = `result = ${1 + 2}`
const nested = `outer ${`inner ${x}`}`
```

### Imports

```typescript
// Relative import
import { add, multiply } from "./math"

// Project root import (@/ = project root with ss.json)
import { parse } from "@/lib/json"

// Multi-file project: only main.ss needs function main()
```

### toString Auto-dispatch

```typescript
class Point(x: int, y: int) {
    override function toString(): string {
        return `(${this.x}, ${this.y})`
    }
}
println(new Point(3, 4))          // (3, 4)
```

### Type Conversions

```typescript
"42".toInt()                      // string → int
"3.14".toDouble()                 // string → double
42.toString()                     // int → string
3.14.toString()                   // double → string
parseInt("42")                    // string → int
parseDouble("3.14")               // string → double
```

---

## 3. Built-in API (No Import Needed)

### Global Functions

**I/O**
| Function | Return | Description |
|----------|--------|-------------|
| `println(...)` | void | Print with newline (auto-format multi-args) |
| `print(...)` | void | Print without newline |
| `readLine()` | string | Read line from stdin |
| `readFile(path)` | string | Read file contents |
| `writeFile(path, data)` | void | Write to file |
| `appendFile(path, data)` | void | Append to file |

**Process**
| Function | Return | Description |
|----------|--------|-------------|
| `exit(code)` | void | Exit program |
| `system(cmd)` | int | Execute shell command |
| `args()` | int | Argument count |
| `arg(index)` | string | Get argument at index |
| `getenv(name)` | string | Environment variable |

**Filesystem**
| Function | Return | Description |
|----------|--------|-------------|
| `fileExists(path)` | int | 1 if exists |
| `fileSize(path)` | int | File size in bytes |
| `mkdir(path)` | int | Create directory |
| `mkdirp(path)` | int | Create directory recursively |
| `removeFile(path)` | int | Delete file |
| `renameFile(old, new)` | int | Rename file |
| `listDir(path)` | string | Directory listing (newline-separated) |

**Type Conversion**
| Function | Return | Description |
|----------|--------|-------------|
| `parseInt(s)` | int | Parse string to int |
| `parseDouble(s)` | double | Parse string to double |
| `charCodeAt(s, idx)` | int | Char code at index |
| `fromCharCode(code)` | string | String from char code |

**Math (Global)**
| Function | Return | Description |
|----------|--------|-------------|
| `sqrt(x)` | double | Square root |
| `abs(x)` | int/double | Absolute value |
| `floor(x)` | double | Floor |
| `ceil(x)` | double | Ceiling |
| `round(x)` | double | Round |
| `pow(base, exp)` | double | Power |
| `log(x)` | double | Natural log |
| `sin(x)` / `cos(x)` / `tan(x)` | double | Trig |
| `random()` | double | Random [0, 1) |
| `randomInt(max)` | int | Random [0, max) |

**Time**
| Function | Return | Description |
|----------|--------|-------------|
| `timeMs()` | int | Current time in milliseconds |
| `timeUnix()` | int | Current Unix timestamp |

**Network (TCP)**
| Function | Return | Description |
|----------|--------|-------------|
| `tcpListen(port)` | int | Create listening socket fd |
| `tcpAccept(fd)` | int | Accept connection fd |
| `tcpRead(fd, maxlen)` | string | Read from socket |
| `tcpWrite(fd, data)` | int | Write to socket |
| `tcpClose(fd)` | void | Close socket |

**Testing**
| Function | Return | Description |
|----------|--------|-------------|
| `test(name, fn)` | void | Register and run a test |

### String Methods

| Method | Return | Description |
|--------|--------|-------------|
| `.length()` | int | String length |
| `.charAt(i)` | string | Character at index |
| `.charCodeAt(i)` | int | Char code at index |
| `.indexOf(sub)` | int | First index of substring (-1 if not found) |
| `.contains(sub)` | int | 1 if contains |
| `.startsWith(prefix)` | int | 1 if starts with |
| `.endsWith(suffix)` | int | 1 if ends with |
| `.substring(start, count)` | string | Extract substring |
| `.split(delim)` | Array\<string\> | Split into array |
| `.trim()` | string | Remove whitespace |
| `.replace(old, new)` | string | Replace all occurrences |
| `.toUpperCase()` | string | Uppercase |
| `.toLowerCase()` | string | Lowercase |
| `.repeat(n)` | string | Repeat n times |
| `.padStart(width, pad)` | string | Pad at start |
| `.padEnd(width, pad)` | string | Pad at end |
| `.toInt()` | int | Parse to int |
| `.toDouble()` | double | Parse to double |

### Array Methods

| Method | Return | Description |
|--------|--------|-------------|
| `.length()` | int | Array length |
| `.push(elem)` | Array | Add element |
| `.pop()` | element | Remove & return last |
| `.first()` | element | First element |
| `.last()` | element | Last element |
| `.indexOf(elem)` | int | Index of element (-1 if not found) |
| `.includes(elem)` | int | 1 if contains |
| `.slice(start, end)` | Array | Subarray |
| `.concat(other)` | Array | Concatenate |
| `.reverse()` | Array | Reverse in-place |
| `.sort()` | Array | Sort ascending in-place |
| `.join(delim)` | string | Join with delimiter |
| `.map(fn)` | Array | Transform each element |
| `.filter(fn)` | Array | Filter elements |
| `.reduce(fn, init)` | value | Fold/reduce |
| `.forEach(fn)` | void | Iterate with side effects |
| `.find(fn)` | value | First matching element |
| `.findIndex(fn)` | int | First matching index |
| `.some(fn)` | int | 1 if any matches |
| `.every(fn)` | int | 1 if all match |

### Map Methods

| Method | Return | Description |
|--------|--------|-------------|
| `.set(key, value)` | void | Set key-value |
| `.get(key)` | value | Get value (int) |
| `.getString(key)` | string | Get string value |
| `.has(key)` | int | 1 if key exists |
| `.delete(key)` | void | Remove key |
| `.size()` | int | Number of entries |
| `.keys()` | Array\<string\> | All keys |

### Set Methods

| Method | Return | Description |
|--------|--------|-------------|
| `.add(elem)` | void | Add element |
| `.has(elem)` | int | 1 if contains |
| `.remove(elem)` | void | Remove element |
| `.size()` | int | Number of elements |
| `.values()` | string | All elements |

### Math Static Methods

`Math.sqrt(x)`, `Math.abs(x)`, `Math.floor(x)`, `Math.ceil(x)`, `Math.round(x)`,
`Math.pow(base, exp)`, `Math.log(x)`, `Math.log10(x)`, `Math.log2(x)`,
`Math.sin(x)`, `Math.cos(x)`, `Math.tan(x)`, `Math.asin(x)`, `Math.acos(x)`, `Math.atan(x)`,
`Math.atan2(y, x)`, `Math.exp(x)`, `Math.trunc(x)`, `Math.sign(x)`, `Math.cbrt(x)`,
`Math.hypot(x, y)`, `Math.fmod(x, y)`, `Math.min(a, b)`, `Math.max(a, b)`,
`Math.random()`, `Math.randomInt(max)`

---

## 4. Standard Library

Import via `import { ... } from "@/lib/<module>"`。

### json — JSON Parse/Stringify

```typescript
import { JSON, JsonNode } from "@/lib/json"

const node = JSON.parse('{"name":"Alice","age":30}')
node.getString("name")            // "Alice"
node.getInt("age")                // 30
node.has("name")                  // 1
node.keys()                       // ["name", "age"]
node.type()                       // "object"

// Nested access
const inner = node.get("address")
inner.getString("city")

// Array
const arr = JSON.parse('[1, 2, 3]')
arr.size()                        // 3
arr.get(0).asInt()                // 1

// Build JSON
const obj = JSON.create()
obj.put("name", "Bob")
obj.put("age", 25)
obj.put("score", 9.5)
obj.putBool("active", 1)
obj.putNull("deleted")

const list = JSON.createArray()
list.add("a")
list.add(42)

JSON.stringify(obj)               // {"name":"Bob","age":25,...}
```

**JsonNode Methods:**
- `type(): string` — "object", "array", "string", "number", "bool", "null"
- `getString(key): string`, `getInt(key): int`, `getDouble(key): double`, `getBool(key): int`
- `get(key): JsonNode` (object field), `get(index): JsonNode` (array element)
- `asString(): string`, `asInt(): int`, `asDouble(): double`, `asBool(): int`
- `has(key): int`, `keys(): Array<string>`, `size(): int`
- `put(key, value): JsonNode` (string/int/double), `putBool(key, v): JsonNode`, `putNull(key): JsonNode`
- `add(value): JsonNode` (string/int/double), `addBool(v): JsonNode`, `addNull(): JsonNode`

### argparse — CLI Argument Parsing

```typescript
import { ArgParse } from "@/lib/argparse"

function main() {
    const parser = ArgParse.create("mytool", "A CLI tool")
    parser.option("--output", "-o", "Output file", "out.txt")
    parser.option("--count", "-n", "Number of items", "10")
    parser.flag("--verbose", "-v", "Enable verbose output")
    parser.version("1.0.0")

    const args = parser.parse()
    const output = args.getString("output")   // "out.txt" or user value
    const count = args.getInt("count")         // 10 or user value
    const verbose = args.getBool("verbose")    // 0 or 1

    // Positional arguments
    const files = args.positionals()           // Array<string>
    const fileCount = args.positionalCount()

    // Check if option was provided
    if (args.has("output")) { ... }

    // Auto-generated help
    println(parser.help())
}
```

### fs — File System

```typescript
import { FS } from "@/lib/fs"

FS.readFile("data.txt")
FS.writeFile("out.txt", "content")
FS.appendFile("log.txt", "line\n")
FS.exists("file.txt")             // 1 or 0
FS.fileSize("file.txt")           // bytes
FS.mkdir("dir")
FS.mkdirp("a/b/c")               // recursive
FS.readDir(".")                   // Array<string>
FS.remove("file.txt")
FS.rename("old.txt", "new.txt")
```

### path — Path Manipulation

```typescript
import { Path } from "@/lib/path"

Path.join("a", "b")              // "a/b"
Path.join("a", "b", "c")         // "a/b/c"
Path.basename("/foo/bar.txt")    // "bar.txt"
Path.dirname("/foo/bar.txt")     // "/foo"
Path.extname("file.txt")        // ".txt"
Path.isAbsolute("/foo")          // 1
Path.normalize("a/../b/./c")    // "b/c"
Path.resolve("/base", "./rel")
```

### color — ANSI Terminal Colors

```typescript
import { Color } from "@/lib/color"

println(Color.red("Error!"))
println(Color.green("Success"))
println(Color.bold(Color.yellow("Warning")))
println(Color.dim("debug info"))

// All colors: black, red, green, yellow, blue, magenta, cyan, white
// Bright: gray, brightRed, brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan, brightWhite
// Background: bgBlack, bgRed, bgGreen, bgYellow, bgBlue, bgMagenta, bgCyan, bgWhite
// Modifiers: bold, dim, italic, underline, inverse, strikethrough
// Utility: strip(text), reset()
```

### log — Logging

```typescript
import { Log } from "@/lib/log"

Log.setLevel(1)                   // 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=FATAL, 5=OFF
Log.enableColor(1)

Log.debug("debug message")
Log.info("info message")
Log.warn("warning")
Log.error("error occurred")
Log.fatal("fatal error")
```

### crypto — Cryptography

```typescript
import { Crypto } from "@/lib/crypto"

Crypto.sha256("hello")           // hex string
Crypto.sha1("hello")             // hex string
Crypto.hmacSHA256("key", "msg")  // hex string
Crypto.hmacSHA1("key", "msg")
Crypto.timingSafeEqual(a, b)     // 1 or 0
Crypto.hexToBytes(hex)
Crypto.bytesToHex(data)
```

### datetime — Date/Time

```typescript
import { DateTime } from "@/lib/datetime"

const now = DateTime.now()        // Unix timestamp
DateTime.year(now)
DateTime.month(now)               // 1-12
DateTime.day(now)                 // 1-31
DateTime.hour(now)                // 0-23
DateTime.minute(now)
DateTime.second(now)
DateTime.dayOfWeek(now)           // 0=Sun..6=Sat
DateTime.dayName(0)               // "Sunday"
DateTime.monthName(1)             // "January"
DateTime.isLeapYear(2024)         // 1
DateTime.daysInMonth(2024, 2)     // 29

// Create timestamp
DateTime.of(2024, 1, 15, 10, 30, 0)
DateTime.ofDate(2024, 1, 15)

// Arithmetic
DateTime.addDays(now, 7)
DateTime.addHours(now, 2)

// Formatting
DateTime.toISO(now)               // "2024-01-15T10:30:00Z"
DateTime.toISODate(now)           // "2024-01-15"
DateTime.toISOTime(now)           // "10:30:00"

// Parsing
DateTime.parseISO("2024-01-15T10:30:00Z")
DateTime.parseISODate("2024-01-15")
```

### regex — Regular Expressions

```typescript
import { Regex } from "@/lib/regex"

Regex.test("\\d+", "abc123")     // 1
Regex.match("\\d+", "abc123")    // "123"
Regex.matchAll("\\d+", "a1b2c3") // ["1", "2", "3"]
Regex.matchIndex("\\d+", "abc123") // 3
Regex.replace("\\d", "a1b2", "X") // "aXb2" (first)
Regex.replaceAll("\\d", "a1b2", "X") // "aXbX"
Regex.split(",\\s*", "a, b, c")  // ["a", "b", "c"]
Regex.escape("a.b")              // "a\\.b"

// Supported: . * + ? ^ $ [] [^] \d \w \s \D \W \S () | \\
```

### csv — CSV Parse/Encode

```typescript
import { CSV } from "@/lib/csv"

const table = CSV.parse("name,age\nAlice,30\nBob,25")
table.rowCount()                  // 3 (including header)
table.colCount()                  // 2
table.get(1, 0)                   // "Alice"
table.headers()                   // ["name", "age"]
table.getByName(1, "name")        // "Alice"
table.getRow(1)                   // ["Alice", "30"]

// Build CSV
const t = CSV.create()
t.addRow(["name", "age"])
t.addRow(["Alice", "30"])
CSV.stringify(t)                  // "name,age\nAlice,30\n"

// Custom delimiter
CSV.parseDelimited(data, "\t")
CSV.stringifyDelimited(table, "\t")
```

### url — URL Parse/Encode

```typescript
import { URL } from "@/lib/url"

const parts = URL.parse("https://user:pass@example.com:8080/path?q=1#hash")
parts.protocol()                  // "https"
parts.hostname()                  // "example.com"
parts.port()                      // "8080"
parts.pathname()                  // "/path"
parts.search()                    // "q=1"
parts.hash()                      // "hash"
parts.origin()                    // "https://example.com:8080"
parts.href()                      // full URL

URL.encodeComponent("hello world") // "hello%20world"
URL.decodeComponent("hello%20world")
URL.parseQuery("a=1&b=2")        // Map<string,string>
URL.resolve("http://example.com/a/", "../b") // resolve relative
```

### http — HTTP Server

```typescript
import { httpServe, parseRequest, httpOk, httpJson, httpNotFound } from "@/lib/http"

function handler(req: Map): string {
    const method = req.getString("method")
    const path = req.getString("path")

    if (path == "/api/hello") {
        return httpJson('{"message":"hello"}')
    }
    return httpNotFound("not found")
}

function main() {
    httpServe(8080, handler)
}

// Response helpers: httpOk(body), httpJson(body), httpHtml(body),
//                   httpNotFound(body), httpError(body), httpRedirect(url),
//                   httpResponse(status, contentType, body)
```

### uuid — UUID Generation

```typescript
import { UUID } from "@/lib/uuid"

UUID.v4()                         // "550e8400-e29b-41d4-a716-446655440000"
UUID.isValid(str)                 // 1 or 0
UUID.version(str)                 // 4
UUID.nil()                        // "00000000-0000-0000-0000-000000000000"
```

### ini — INI File Parsing

```typescript
import { Ini } from "@/lib/ini"

const data = Ini.parse("[server]\nhost=localhost\nport=8080")
data.get("server", "host")       // "localhost"
data.getInt("server", "port")    // 8080 (if supported)
data.hasSection("server")        // 1
data.sections()                  // ["server"]
data.keys("server")              // ["host", "port"]

// Build INI
const cfg = Ini.create()
cfg.set("db", "host", "localhost")
cfg.set("db", "port", "5432")
Ini.stringify(cfg)
```

### template — Template Engine

```typescript
import { Template } from "@/lib/template"

const vars = new Map()
vars.set("name", "Alice")
vars.set("show", "1")

Template.render("Hello {{name}}!", vars)              // "Hello Alice!"
Template.render("{{#show}}visible{{/show}}", vars)    // "visible" (section)
Template.render("{{^missing}}default{{/missing}}", vars) // "default" (inverted)
Template.variables("Hello {{name}} {{age}}")          // ["name", "age"]
Template.escape("<b>bold</b>")                        // "&lt;b&gt;bold&lt;/b&gt;"
```

### string_utils — String Utilities

```typescript
import { StringUtil } from "@/lib/string_utils"

StringUtil.capitalize("hello")    // "Hello"
StringUtil.reverse("abc")         // "cba"
StringUtil.isBlank("  ")          // 1
StringUtil.isDigit("123")         // 1
StringUtil.isAlpha("abc")         // 1
StringUtil.trimStart("  hi")      // "hi"
StringUtil.trimEnd("hi  ")        // "hi"
StringUtil.padCenter("hi", 10, "-") // "----hi----"
StringUtil.truncate("hello world", 8, "...") // "hello..."
StringUtil.count("aabaa", "a")    // 4
StringUtil.removePrefix("prefix_name", "prefix_")
StringUtil.removeSuffix("file.txt", ".txt")
StringUtil.equalsIgnoreCase("Hello", "hello") // 1
StringUtil.lines("a\nb\nc")      // ["a", "b", "c"]
StringUtil.words("hello world")  // ["hello", "world"]
```

### sort — Sorting Algorithms

```typescript
import { Sort } from "@/lib/sort"

Sort.quickSort([3, 1, 2])        // [1, 2, 3]
Sort.mergeSort([3, 1, 2])        // [1, 2, 3] (stable)
Sort.insertionSort([3, 1, 2])    // [1, 2, 3]
Sort.descending([1, 2, 3])       // [3, 2, 1]
Sort.isSorted([1, 2, 3])         // 1
Sort.binarySearch([1, 2, 3], 2)  // 1 (index)
Sort.unique([1, 1, 2, 3, 3])     // [1, 2, 3]
Sort.merge([1, 3], [2, 4])       // [1, 2, 3, 4]
Sort.shuffle([1, 2, 3])          // random order
Sort.min([3, 1, 2])              // 1
Sort.max([3, 1, 2])              // 3
```

### math — Extended Math

```typescript
import { MathUtil } from "@/lib/math"

MathUtil.PI()                     // 3.141592653589793
MathUtil.E()                      // 2.718281828459045
MathUtil.clamp(15.0, 0.0, 10.0)  // 10.0
MathUtil.lerp(0.0, 100.0, 0.5)   // 50.0
MathUtil.toDegrees(3.14159)      // ~180.0
MathUtil.toRadians(180.0)        // ~3.14159
MathUtil.gcd(12, 8)              // 4
MathUtil.lcm(4, 6)               // 12
MathUtil.isPowerOfTwo(8)         // 1
MathUtil.isEven(4)               // 1
```

### test — Testing Framework

```typescript
import { assertEqual, assertTrue, assertFalse, assertNull, assertNotNull } from "@/lib/test"

function main() {
    test("math works", (): void => {
        assertEqual(1 + 1, 2)
        assertEqual("hello", "hello")
        assertTrue(5 > 3)
        assertFalse(1 == 2)
    })

    test("nullable", (): void => {
        assertNull(null)
        assertNotNull("value")
    })
}
```

### assert — Assertions (OOP Style)

```typescript
import { Assert } from "@/lib/assert"

Assert.isTrue(x > 0, "must be positive")
Assert.equal("hello", "hello", "strings match")
Assert.equal(42, 42, "ints match")
Assert.notEqual(1, 2, "different")
Assert.greaterThan(10, 5, "10 > 5")
Assert.contains("hello world", "world", "has world")
Assert.startsWith("hello", "hel", "prefix")
Assert.approxEqual(3.14, 3.14159, 0.01, "close enough")
Assert.fail("should not reach here")
```

### base64 — Base64 Encode/Decode

```typescript
import { base64encode, base64decode } from "@/lib/base64"

base64encode("hello")             // "aGVsbG8="
base64decode("aGVsbG8=")          // "hello"
```

### sha256 — SHA256

```typescript
import { sha256pure } from "@/lib/sha256"

sha256pure("hello")               // hex string
```

---

## 5. Patterns for CLI Tools

### Basic CLI Structure

```typescript
import { ArgParse } from "@/lib/argparse"
import { Color } from "@/lib/color"
import { FS } from "@/lib/fs"

function main() {
    const parser = ArgParse.create("mytool", "Description")
    parser.option("--input", "-i", "Input file", "")
    parser.option("--output", "-o", "Output file", "out.txt")
    parser.flag("--verbose", "-v", "Verbose output")

    const args = parser.parse()

    if (args.getString("input") == "") {
        println(Color.red("Error: --input is required"))
        println(parser.help())
        exit(1)
    }

    const input = FS.readFile(args.getString("input"))
    const result = processData(input)
    FS.writeFile(args.getString("output"), result)

    if (args.getBool("verbose")) {
        println(Color.green("Done!"))
    }
}
```

### Subcommand Pattern

```typescript
function main() {
    if (args() < 2) {
        showHelp()
        exit(1)
    }

    const cmd = arg(1)
    switch (cmd) {
        case "init" -> cmdInit()
        case "add" -> cmdAdd()
        case "list" -> cmdList()
        case "help" -> showHelp()
        default -> {
            println("Unknown command: " + cmd)
            exit(1)
        }
    }
}

function cmdInit() {
    if (FS.exists("config.json")) {
        println("Already initialized")
        exit(1)
    }
    const cfg = JSON.create()
    cfg.put("version", "1.0.0")
    FS.writeFile("config.json", JSON.stringify(cfg))
    println("Initialized!")
}
```

### Error Handling Pattern

```typescript
class AppError extends Error {
    code: int
}

function loadConfig(path: string): JsonNode {
    if (!FS.exists(path)) {
        throw(new AppError("Config not found: " + path, 1))
    }
    const raw = FS.readFile(path)
    return JSON.parse(raw)
}

function main() {
    try {
        const config = loadConfig("config.json")
        run(config)
    } catch (e: AppError) {
        println(Color.red(`Error [${e.code}]: ${e.message}`))
        exit(e.code)
    } catch (e) {
        println(Color.red("Unexpected: " + e.message))
        exit(1)
    }
}
```

### Multi-File Project

```
myapp/
  ss.json
  src/
    main.ss              # import { run } from "./commands"
    commands.ss           # import { Config } from "./config"
    config.ss
    utils.ss
```

Only `main.ss` needs `function main()`. Other files export functions/classes via top-level declarations, imported with relative paths.
