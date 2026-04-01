// Test: Map.keys() on a Map passed as function parameter

function printKeys(m: Map<string, string>) {
    const k = m.keys()
    const n = k.length()
    println("keys count: " + n)
    for (let i = 0; i < n; i++) {
        println("key: " + k[i])
    }
}

function main() {
    let m = new Map()
    m.set("a", "1")
    m.set("b", "2")
    m.set("c", "3")

    // Direct call — should work
    const k1 = m.keys()
    println("direct count: " + k1.length())

    // Via function parameter — reported as unreliable
    printKeys(m)
}
