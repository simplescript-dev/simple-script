// Test: RC destructors for Map and Array<ptr>
// Verifies no crash when containers with owned children are freed

function testMapDestruct() {
    // Create map, add entries, let it go out of scope
    let m = new Map()
    m.set("key1", "value1")
    m.set("key2", "value2")
    m.set("key3", "value3")
    // Delete an entry (should release key + value)
    m.delete("key2")
    println("map ok")
    // m goes out of scope — destructor releases remaining keys + frees entries
}

function testMapPtrValue() {
    // Map with ptr values — destructor should release values too
    let m: Map<string, string> = new Map()
    m.set("a", "alpha")
    m.set("b", "beta")
    m.set("c", "gamma")
    // Overwrite: old value should be released
    m.set("b", "bravo")
    // Delete: value should be released
    m.delete("c")
    println(m.getString("a"))
    println(m.getString("b"))
    println(m.size())
    // m goes out of scope — destructor releases keys AND values
}

function testArraySplit() {
    // split() creates Array<string> with tag=5
    const parts = "hello,world,foo,bar".split(",")
    println(parts[0])
    println(parts[1])
    println(parts.length())
    // parts goes out of scope — destructor releases string elements
}

function testArraySlice() {
    const parts = "a,b,c,d,e".split(",")
    const sub = parts.slice(1, 4)
    println(sub[0])
    println(sub[1])
    println(sub[2])
    println(sub.length())
    // Both parts and sub freed — slice retains elements, no double-free
}

function main() {
    testMapDestruct()
    testMapPtrValue()
    testArraySplit()
    testArraySlice()
    println("all done")
}
