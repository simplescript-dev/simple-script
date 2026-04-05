// Test: D067 null safety Phase 3 — operator type propagation
// ?. returns T?, ?? returns T

class Address {
    city: string
    zip: int
}

class User {
    name: string
    age: int
    addr: Address?
}

class Team {
    leader: User?
}

function findUser(id: int): User? {
    if (id <= 0) { return null }
    return new User("Alice", 30, new Address("NYC", 10001))
}

function main() {
    // 1. ?. on field returns T? — assign to T? works
    const u: User? = findUser(1)
    const name: string? = u?.name
    println("test1 passed")

    // 2. ?. result unwrapped by ?? gives T — assign to T works
    const safeName: string = u?.name ?? "default"
    println("test2 passed")

    // 3. ?. on method returns T? — method with return type
    const t = new Team(findUser(1))
    const leaderName: string? = t.leader?.name
    println("test3 passed")

    // 4. ?? unwraps method ?. result
    const safeLeader: string = t.leader?.name ?? "none"
    println("test4 passed")

    // 5. Chained ?? after ?.
    const u2: User? = findUser(-1)
    const fallback: string = u2?.name ?? "anonymous"
    if (fallback == "anonymous") {
        println("test5 passed")
    }

    // 6. ?. on non-null object still returns T? type
    const u3: User? = findUser(1)
    const n3: string? = u3?.name
    const resolved: string = n3 ?? "fallback"
    if (resolved == "Alice") {
        println("test6 passed")
    }

    // 7. Nullable field accessed with ?. — nested nullable
    const u4: User? = findUser(1)
    const city: string? = u4?.addr?.city
    const safeCity: string = city ?? "unknown"
    if (safeCity == "NYC") {
        println("test7 passed")
    }

    println("null_type_propagation: all passed")
}
