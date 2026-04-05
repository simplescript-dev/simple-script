// Test: D067 null safety — Phase 1 checker-level null awareness

class User {
    name: string
    age: int
}

// Function returning nullable type
function findUser(id: int): User? {
    if (id <= 0) { return null }
    return new User("Alice", 30)
}

// Function returning non-nullable type
function createUser(name: string): User {
    return new User(name, 25)
}

function main() {
    // 1. Nullable variable can hold null
    let u1: User? = null
    let u2: User? = new User("Bob", 20)

    // 2. Non-nullable variable holds a value
    let u3: User = new User("Charlie", 35)

    // 3. T is assignable to T?
    let u4: User? = createUser("Dave")

    // 4. Function returning T? works
    let found: User? = findUser(1)
    let notFound: User? = findUser(-1)

    // 5. ?? (null coalescing) unwraps nullable
    let safe: User = findUser(1) ?? new User("default", 0)

    // 6. Nullable string type
    let s1: string? = null
    let s2: string? = "hello"
    let s3: string = s2 ?? "default"

    // 7. Optional chaining on nullable
    const cfg: User? = findUser(1)
    const name = cfg?.name

    // 8. Null comparison is valid (== and != with null)
    if (found != null) {
        println("found user")
    }
    if (notFound == null) {
        println("not found")
    }

    println("null_safety: all passed")
}
