function main() {
    const count = args()
    println("arg count: " + count)
    for (let i = 0; i < count; i++) {
        println("  arg[" + i + "] = " + arg(i))
    }
}
