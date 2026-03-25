function main() {
    const map = Map()

    // Set values (int values)
    map.set("alice", 95)
    map.set("bob", 87)
    map.set("charlie", 92)

    // Get values
    println("alice: " + map.get("alice"))
    println("bob: " + map.get("bob"))
    println("charlie: " + map.get("charlie"))

    // Size
    println("size: " + map.size())

    // Has
    println("has alice: " + map.has("alice"))
    println("has dave: " + map.has("dave"))

    // Overwrite
    map.set("bob", 90)
    println("bob after update: " + map.get("bob"))

    // Default for missing key
    println("missing key: " + map.get("xyz"))

    // Word frequency with manual counting
    println("")
    println("=== Frequency ===")
    const freq = Map()
    count(freq, "hello")
    count(freq, "world")
    count(freq, "hello")
    count(freq, "foo")
    count(freq, "world")
    count(freq, "hello")

    println("hello: " + freq.get("hello"))
    println("world: " + freq.get("world"))
    println("foo: " + freq.get("foo"))
    println("total keys: " + freq.size())
}

function count(freq: string, word: string) {
    if (freq.has(word) == 1) {
        freq.set(word, freq.get(word) + 1)
    } else {
        freq.set(word, 1)
    }
}
