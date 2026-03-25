function main() {
    // Test stringLength
    const hello = "Hello, World!"
    const len = hello.length()
    println(`"${hello}" has ${len} characters`)

    // Test toInt
    const numStr = "42"
    const num = numStr.toInt()
    println(`"${numStr}".toInt() = ${num}`)
    println(`num * 2 = ${num * 2}`)

    // Test toDouble
    const piStr = "3.14159"
    const pi = piStr.toDouble()
    println(`"${piStr}".toDouble() = ${pi}`)

    // Test print (no newline)
    print("one ")
    print("two ")
    print("three")
    println("")
}
